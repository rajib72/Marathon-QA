public with sharing class OAuthRequestGenerator {
    
    // Consumer Key provided by the vendor
    private static QDX_Property propConsumerKey = QDX_Property.forLabel('MC Consumer Key');
    private static final String CONSUMER_KEY = propConsumerKey.textValue;
    
    // Private Key extracted from the PEM file
    private static QDX_Property propPrivateKey = QDX_Property.forLabel('MC Private Key');
    private static final String PRIVATE_KEY = propPrivateKey.textValue;
    
    //Setting Endpoint URL
    private static QDX_Property prop = QDX_Property.forLabel('MC URL');
    private static final String endpointURL = prop.textValue;
    
    // Mastercard Reporting Endpoint
    private static QDX_Property propReporting =
        QDX_Property.forLabel('MC Reporting URL');
    
    private static final String reportingEndpointURL =
        propReporting.textValue;
    
    /**
* Sends an authenticated POST request to the given URL with the XML payload.
* @param xmlPayload The XML payload to send.
* @return The response from the API.
*/
    public static HttpResponse sendRequest(String xmlPayload) {
        String oauthNonce = generateNonce();
        String oauthTimestamp = String.valueOf(DateTime.now().getTime() / 1000);
        
        // Compute the body hash
        String bodyHash = calculateBodyHash(xmlPayload);
        
        // Generate the OAuth signature base string
        String signatureBaseString = generateSignatureBaseString(endpointURL, oauthNonce, oauthTimestamp, bodyHash);
        
        // Generate the signature using RSA-SHA256
        String oauthSignature = generateSignature(signatureBaseString);
        
        // Prepare the Authorization header
        String authorizationHeader = buildAuthorizationHeader(oauthNonce, oauthTimestamp, oauthSignature, bodyHash);
        // Set up the HTTP request
        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint(endpointUrl);
        request.setHeader('Authorization', authorizationHeader);
        request.setHeader('Content-Type', 'text/xml');
        request.setBody(xmlPayload);
        
        // Send the request
        Http http = new Http();
        return http.send(request);
    }
    
    //added by Swastika on 28th Sept
/**
 * Sends an authenticated POST request to the Mastercard
 * Reporting endpoint.
 *
 * Used specifically for ICCP reporting APIs.
 *
 * @param xmlPayload The XML payload to send.
 * @return The response from the Mastercard Reporting API.
 */
public static HttpResponse sendReportingRequest(String xmlPayload) {

    String oauthNonce = generateNonce();

    String oauthTimestamp =
        String.valueOf(DateTime.now().getTime() / 1000);

    // Compute the body hash
    String bodyHash =
        calculateBodyHash(xmlPayload);

    // IMPORTANT:
    // Generate the OAuth signature using the
    // Reporting endpoint, not the Financial endpoint.
    String signatureBaseString =
        generateSignatureBaseString(
            reportingEndpointURL,
            oauthNonce,
            oauthTimestamp,
            bodyHash
        );

    // Generate RSA-SHA256 signature
    String oauthSignature =
        generateSignature(signatureBaseString);

    // Prepare Authorization header
    String authorizationHeader =
        buildAuthorizationHeader(
            oauthNonce,
            oauthTimestamp,
            oauthSignature,
            bodyHash
        );

    HttpRequest request =
        new HttpRequest();

    request.setMethod('POST');

    // IMPORTANT:
    // Reporting API must use /iccp/reporting
    request.setEndpoint(
        reportingEndpointURL
    );

    request.setHeader(
        'Authorization',
        authorizationHeader
    );

    request.setHeader(
        'Content-Type',
        'text/xml'
    );

    request.setBody(xmlPayload);

    System.debug(
        LoggingLevel.INFO,
        'MRT3-38 Reporting Endpoint: ' +
        reportingEndpointURL
    );

    System.debug(
        LoggingLevel.INFO,
        'MRT3-38 Reporting Request: ' +
        xmlPayload
    );

    Http http =
        new Http();

    return http.send(request);
}
    
    /**
* Generates the OAuth signature base string.
*/
    private static String generateSignatureBaseString(String endpointUrl, String oauthNonce, String oauthTimestamp, String bodyHash) {
        Map<String, String> params = new Map<String, String>{
            'oauth_consumer_key' => CONSUMER_KEY,
                'oauth_nonce' => oauthNonce,
                'oauth_signature_method' => 'RSA-SHA256',
                'oauth_timestamp' => oauthTimestamp,
                'oauth_version' => '1.0',
                'oauth_body_hash' => bodyHash
                };
                    
                    // Build the parameter string
                    List<String> sortedKeys = new List<String>(params.keySet());
        sortedKeys.sort();
        List<String> encodedParams = new List<String>();
        for (String key : sortedKeys) {
            encodedParams.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(params.get(key), 'UTF-8'));
        }
        String parameterString = String.join(encodedParams, '&');
        
        // Build the signature base string
        String baseString = 'POST&' + EncodingUtil.urlEncode(endpointUrl, 'UTF-8') + '&' + EncodingUtil.urlEncode(parameterString, 'UTF-8');
        return baseString;
    }
    
    /**
* Calculates the SHA-256 body hash and encodes it in Base64.
*/
    private static String calculateBodyHash(String body) {
        Blob bodyBlob = Blob.valueOf(body);
        Blob hashBlob = Crypto.generateDigest('SHA-256', bodyBlob);
        return EncodingUtil.base64Encode(hashBlob);
    }
    
    /**
* Generates the RSA-SHA256 signature.
*/
    private static String generateSignature(String signatureBaseString) {
        Blob privateKeyBlob = EncodingUtil.base64Decode(PRIVATE_KEY.replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace('\n', ''));
        //Crypto.signAlgorithm String algorithm = Crypto.SignatureAlgorithm.RSASHA256;
        Blob signature = Crypto.sign('RSA-SHA256', Blob.valueOf(signatureBaseString), privateKeyBlob);
        return EncodingUtil.base64Encode(signature);
    }
    
    /**
* Builds the Authorization header for OAuth.
*/
    private static String buildAuthorizationHeader(String oauthNonce, String oauthTimestamp, String oauthSignature, String bodyHash) {
        return 'OAuth ' +
            'oauth_consumer_key="' + CONSUMER_KEY + '", ' +
            'oauth_nonce="' + oauthNonce + '", ' +
            'oauth_signature="' + EncodingUtil.urlEncode(oauthSignature, 'UTF-8') + '", ' +
            'oauth_signature_method="RSA-SHA256", ' +
            'oauth_timestamp="' + oauthTimestamp + '", ' +
            'oauth_body_hash="' + EncodingUtil.urlEncode(bodyHash, 'UTF-8') + '", ' +
            'oauth_version="1.0"';
    }
    
    /**
* Generates a unique nonce for each request.
*/
    private static String generateNonce() {
        Integer currentSecond = DateTime.now().second();
        Integer initialSecond = DateTime.newInstanceGMT(1970, 01, 01, 0, 0, 0).second();
        return String.valueOf(currentSecond - initialSecond);
    }
}