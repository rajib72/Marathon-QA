/** Sends an internal vendor request using the configured Salesforce Named Credential. */
public with sharing class VendorPricingHttpTransport {
    private static final Pattern CREDENTIAL_NAME = Pattern.compile('[A-Za-z][A-Za-z0-9_]*');
    private static final Pattern UNSAFE_PATH = Pattern.compile('[\\s#\\\\]');
    private static final Pattern HEADER_LINE_BREAK = Pattern.compile('[\\r\\n]');
    private static final Pattern TOKEN_WHITESPACE = Pattern.compile('\\s');
    private static final Set<String> METHODS = new Set<String>{'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'};
    private static final String JSON_CONTENT_TYPE = 'application/json';
    private static final Integer MAX_TIMEOUT_MILLISECONDS = 120000;

    public class Response {
        public Boolean success = false;
        public String code;
        public String message;
        public Integer statusCode;
        // The response body is for internal parsing. Keep it out of debug or UI responses.
        public String body;
    }

    private class TransportException extends Exception {
        public String code;
    }

    public static Response send(
        VendorPricingMetadataRepository.CalloutConfiguration configuration,
        String requestBody,
        String accessToken
    ) {
        HttpRequest request;
        try {
            request = createRequest(configuration, requestBody, accessToken);
        } catch (TransportException error) {
            return outcome(error.code, error.getMessage());
        }
        if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
            return outcome('CALLOUT_LIMIT_REACHED', 'The transaction reached its HTTP callout limit.');
        }

        try {
            HttpResponse externalResponse = new Http().send(request);
            Response result = classify(externalResponse.getStatusCode());
            result.statusCode = externalResponse.getStatusCode();
            result.body = externalResponse.getBody();
            return result;
        } catch (CalloutException error) {
            return outcome('CALLOUT_FAILED', 'Salesforce could not complete the vendor HTTP request.');
        }
    }

    private static HttpRequest createRequest(
        VendorPricingMetadataRepository.CalloutConfiguration configuration,
        String requestBody,
        String accessToken
    ) {
        if (configuration == null || configuration.endpoint == null || configuration.vendor == null) {
            throw problem('CALLOUT_CONFIGURATION_REQUIRED', 'Provide a configured endpoint and its vendor.');
        }
        Vendor_Endpoint__mdt endpoint = configuration.endpoint;
        Vendor_Integration__mdt vendor = configuration.vendor;
        if (endpoint.Vendor__c == null || endpoint.Vendor__c != vendor.Id) {
            throw problem('CALLOUT_CONFIGURATION_REQUIRED', 'The endpoint must belong to the configured vendor.');
        }
        if (endpoint.Active__c != true || vendor.Active__c != true) {
            throw problem('CALLOUT_ENDPOINT_INACTIVE', 'The vendor and endpoint must be active for HTTP execution.');
        }
        if (String.isNotBlank(endpoint.Execution_Mode__c) && endpoint.Execution_Mode__c != 'DIRECT') {
            throw problem('CALLOUT_EXECUTION_MODE_UNSUPPORTED', 'This transport supports direct HTTP execution.');
        }

        String credentialName = vendor.Named_Credential_API_Name__c;
        if (String.isBlank(credentialName) || !CREDENTIAL_NAME.matcher(credentialName).matches()) {
            throw problem('NAMED_CREDENTIAL_INVALID', 'Configure a Named Credential API Name for this vendor.');
        }
        String path = endpoint.Relative_Path__c;
        if (String.isBlank(path) || !path.startsWith('/') || path.startsWith('//') || path.contains('://') ||
            UNSAFE_PATH.matcher(path).find()) {
            throw problem('CALLOUT_PATH_INVALID', 'Configure a valid relative path for this endpoint.');
        }
        String method = String.isBlank(endpoint.HTTP_Method__c) ? null : endpoint.HTTP_Method__c.trim().toUpperCase();
        if (!METHODS.contains(method)) {
            throw problem('CALLOUT_METHOD_UNSUPPORTED', 'Configure a supported HTTP method.');
        }
        if (String.isNotBlank(requestBody) && (method == 'GET' || method == 'HEAD')) {
            throw problem('CALLOUT_BODY_UNSUPPORTED', 'Use a body-capable HTTP method for this prepared request.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + credentialName + path);
        request.setMethod(method);
        Integer timeoutMilliseconds = resolveTimeout(endpoint, vendor);
        if (timeoutMilliseconds != null) {
            request.setTimeout(timeoutMilliseconds);
        }
        request.setHeader('Accept', headerValue(endpoint.Accept_Header__c, 'Accept'));
        if (String.isNotBlank(requestBody)) {
            String contentType = headerValue(endpoint.Request_Content_Type__c, 'Content-Type');
            Boolean credentialExchange = endpoint.Invocation_Policy__c == 'PREREQUISITE' &&
                (endpoint.Operation__c == 'TOKEN' || endpoint.Operation__c == 'TOKEN_REFRESH') &&
                endpoint.Requires_Authentication__c != true;
            if (requestBody.contains('{!') && (String.isNotBlank(accessToken) ||
                (usesTokenStrategy(vendor) && !credentialExchange))) {
                String mediaType = contentType.substringBefore(';').trim().toLowerCase();
                if (mediaType != JSON_CONTENT_TYPE && !mediaType.endsWith('+json')) {
                    throw problem('CALLOUT_BODY_INVALID', 'The bearer-authenticated request contains unescaped formula syntax.');
                }
                requestBody = escapeCredentialExpressions(requestBody);
            }
            request.setHeader('Content-Type', contentType);
            request.setBody(requestBody);
        }
        applyAuthentication(request, endpoint, vendor, accessToken);
        return request;
    }

    @TestVisible
    private static Integer resolveTimeout(Vendor_Endpoint__mdt endpoint, Vendor_Integration__mdt vendor) {
        Decimal configured = endpoint.Timeout_Milliseconds__c == null
            ? vendor.Default_Timeout_Milliseconds__c : endpoint.Timeout_Milliseconds__c;
        if (configured == null) {
            return null;
        }
        if (configured < 1 || configured > MAX_TIMEOUT_MILLISECONDS ||
            configured != configured.setScale(0, System.RoundingMode.DOWN)) {
            throw problem('CALLOUT_TIMEOUT_INVALID', 'Configure a whole-number timeout from 1 to 120000 milliseconds.');
        }
        return configured.intValue();
    }

    private static String headerValue(String configured, String headerName) {
        if (String.isBlank(configured)) {
            return JSON_CONTENT_TYPE;
        }
        if (HEADER_LINE_BREAK.matcher(configured).find()) {
            throw problem('CALLOUT_HEADER_INVALID', 'Review the configured ' + headerName + ' header.');
        }
        return configured.trim();
    }

    private static void applyAuthentication(
        HttpRequest request, Vendor_Endpoint__mdt endpoint, Vendor_Integration__mdt vendor, String accessToken
    ) {
        Boolean hasPrerequisite = String.isNotBlank(endpoint.Prerequisite_Endpoint_Code__c);
        if (hasPrerequisite && endpoint.Requires_Authentication__c != true) {
            throw problem('CALLOUT_PREREQUISITE_UNSUPPORTED', 'This prerequisite requires an execution handler.');
        }
        Boolean needsToken = endpoint.Requires_Authentication__c == true &&
            (usesTokenStrategy(vendor) || hasPrerequisite);
        if (needsToken) {
            if (String.isBlank(accessToken)) {
                throw problem('AUTH_TOKEN_REQUIRED', 'Provide the runtime bearer token for this endpoint.');
            }
            if (TOKEN_WHITESPACE.matcher(accessToken).find() || accessToken.contains('{!')) {
                throw problem('AUTH_TOKEN_INVALID', 'The runtime bearer token has an invalid format.');
            }
            request.setHeader('Authorization', 'Bearer ' + accessToken);
        } else if (String.isNotBlank(accessToken)) {
            throw problem('AUTH_TOKEN_UNEXPECTED', 'This endpoint uses its Named Credential for authentication.');
        }
    }

    public static Boolean usesTokenStrategy(Vendor_Integration__mdt vendor) {
        String strategy = vendor.Authentication_Strategy__c;
        return String.isNotBlank(strategy) && strategy.toUpperCase().startsWith('TOKEN');
    }

    // Keeps formula syntax literal in a JSON value while preserving the decoded value.
    public static String escapeCredentialExpressions(String jsonText) {
        return jsonText.replace('{!', '\\u007B!');
    }

    private static Response classify(Integer statusCode) {
        if (statusCode >= 200 && statusCode < 300) {
            Response result = outcome('HTTP_SUCCESS', 'The vendor returned a successful HTTP status.');
            result.success = true;
            return result;
        }
        if (statusCode == 401 || statusCode == 403) {
            return outcome('HTTP_AUTHORIZATION_FAILED', 'The vendor rejected the request credentials or access.');
        }
        if (statusCode == 429) {
            return outcome('HTTP_RATE_LIMITED', 'The vendor applied a request rate limit.');
        }
        if (statusCode >= 500) {
            return outcome('HTTP_VENDOR_ERROR', 'The vendor returned a server error.');
        }
        if (statusCode >= 400) {
            return outcome('HTTP_REQUEST_REJECTED', 'The vendor rejected the HTTP request.');
        }
        return outcome('HTTP_UNEXPECTED_STATUS', 'The vendor returned an unexpected HTTP status.');
    }

    private static Response outcome(String code, String message) {
        Response result = new Response();
        result.code = code;
        result.message = message;
        return result;
    }

    private static TransportException problem(String code, String message) {
        TransportException error = new TransportException(message);
        error.code = code;
        return error;
    }
}