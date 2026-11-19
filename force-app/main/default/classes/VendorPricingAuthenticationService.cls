/** Runs the configured token exchange and keeps bearer tokens inside the Apex transaction. */
public with sharing class VendorPricingAuthenticationService {
    private static final String TOKEN_OPERATION = 'TOKEN';
    private static final String REFRESH_OPERATION = 'TOKEN_REFRESH';
    private static final String REFRESH_STRATEGY = 'TOKEN_WITH_REFRESH';
    private static final String ACCESS_CODE = 'AUTH_ACCESS_TOKEN';
    private static final String REFRESH_CODE = 'AUTH_REFRESH_TOKEN';
    private static final String EXPIRY_SECONDS = 'AUTH_EXPIRES_IN_SECONDS';
    private static final String EXPIRY_MILLISECONDS = 'AUTH_EXPIRES_IN_MILLISECONDS';
    private static final String EXPIRY_DATE = 'AUTH_EXPIRES_AT';
    private static final Set<String> EXPIRY_CODES = new Set<String>{EXPIRY_SECONDS, EXPIRY_MILLISECONDS, EXPIRY_DATE};
    private static final Pattern JSON_PATH = Pattern.compile('[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*');
    private static final Pattern CREDENTIAL_FORMULA =
        Pattern.compile('\\{!\\$Credential\\.[A-Za-z][A-Za-z0-9_]*\\.[A-Za-z][A-Za-z0-9_]*\\}');
    private static final Pattern TOKEN_CONTROL_CHARACTER = Pattern.compile('[\\s\\x00-\\x1F\\x7F]');
    private static final Map<String, Session> sessions = new Map<String, Session>();

    @TestVisible
    private static VendorPricingMetadataRepository.AuthenticationConfiguration testConfiguration;
    @TestVisible
    private static Long testTimeMilliseconds;

    private class AuthFailureException extends Exception {
        public String code;
        public Integer statusCode;
    }

    private class EndpointDefinition {
        public Vendor_Endpoint__mdt endpoint;
        public Map<String, Object> requestFields = new Map<String, Object>();
        public Map<String, String> requestTokenPaths = new Map<String, String>();
        public Map<String, String> responsePaths = new Map<String, String>();
        public String expiryCode;
    }

    private class TokenState {
        public String accessToken;
        public String refreshToken;
        public Long renewAtMilliseconds;
        public Integer statusCode;
        public Boolean accessTokenRejected = false;
    }

    private class Session {
        public Vendor_Integration__mdt vendor;
        public EndpointDefinition login;
        public EndpointDefinition refresh;
        public Long expiryBufferMilliseconds;
        public TokenState token;
        public AuthFailureException failure;
        public Boolean authorizationRecoveryUsed = false;
    }

    public static Boolean appliesTo(VendorPricingMetadataRepository.CalloutConfiguration configuration) {
        return configuration != null && configuration.endpoint != null && configuration.vendor != null &&
            configuration.endpoint.Requires_Authentication__c == true &&
            VendorPricingHttpTransport.usesTokenStrategy(configuration.vendor);
    }

    public static VendorPricingHttpTransport.Response send(
        VendorPricingMetadataRepository.CalloutConfiguration configuration, String requestBody
    ) {
        try {
            Session session = openSession(configuration);
            if (session.token == null || session.token.accessTokenRejected ||
                (session.token.renewAtMilliseconds != null && nowMilliseconds() >= session.token.renewAtMilliseconds)) {
                try {
                    session.token = renew(session);
                } catch (AuthFailureException error) {
                    session.failure = error;
                    throw error;
                }
            }

            VendorPricingHttpTransport.Response result =
                VendorPricingHttpTransport.send(configuration, requestBody, session.token.accessToken);
            if (result.statusCode == 401) {
                session.token.accessTokenRejected = true;
                if (session.authorizationRecoveryUsed) {
                    session.failure = problem('AUTH_BEARER_REJECTED', 'The vendor rejected the renewed bearer token.', 401);
                }
                session.authorizationRecoveryUsed = true;
            }
            return result;
        } catch (AuthFailureException error) {
            return failureResponse(error);
        }
    }

    /** Probes login and optionally refresh. The results contain status information only. */
    public static List<VendorPricingHttpTransport.Response> verifyAuthentication(Id pricingEndpointId, Boolean probeRefresh) {
        return verify(VendorPricingMetadataRepository.loadForCallout(pricingEndpointId), probeRefresh);
    }

    @TestVisible
    private static List<VendorPricingHttpTransport.Response> verify(
        VendorPricingMetadataRepository.CalloutConfiguration configuration, Boolean probeRefresh
    ) {
        List<VendorPricingHttpTransport.Response> results = new List<VendorPricingHttpTransport.Response>();
        try {
            Session session = openSession(configuration);
            if (probeRefresh == true && session.refresh == null) {
                throw problem('AUTH_REFRESH_UNAVAILABLE', 'This vendor uses token acquisition without refresh.', null);
            }
            session.token = null;
            session.token = exchange(session, session.login, null);
            results.add(probeSuccess('AUTH_LOGIN_SUCCESS', session.token.statusCode));
            if (probeRefresh == true) {
                session.token = exchange(session, session.refresh, session.token);
                results.add(probeSuccess('AUTH_REFRESH_SUCCESS', session.token.statusCode));
            }
        } catch (AuthFailureException error) {
            results.add(failureResponse(error));
        }
        return results;
    }

    private static Session openSession(VendorPricingMetadataRepository.CalloutConfiguration configuration) {
        if (!appliesTo(configuration) || configuration.vendor.Active__c != true ||
            configuration.vendor.Id == null || configuration.endpoint.Vendor__c != configuration.vendor.Id) {
            throw problem('AUTH_CONFIGURATION_REQUIRED', 'Select a token-authenticated endpoint for an active vendor.', null);
        }
        Vendor_Integration__mdt vendor = configuration.vendor;
        String prerequisite = configuration.endpoint.Prerequisite_Endpoint_Code__c;
        prerequisite = String.isBlank(prerequisite) ? '' : prerequisite.trim();
        String sessionKey = String.valueOf(vendor.Id) + '|' + vendor.Named_Credential_API_Name__c +
            '|' + UserInfo.getUserId() + '|' + prerequisite;
        if (!sessions.containsKey(sessionKey)) {
            Session session = new Session();
            session.vendor = vendor;
            try {
                configure(session, prerequisite);
            } catch (AuthFailureException error) {
                session.failure = error;
            }
            sessions.put(sessionKey, session);
        }
        Session session = sessions.get(sessionKey);
        if (session.failure != null) {
            throw session.failure;
        }
        return session;
    }

    private static void configure(Session session, String prerequisite) {
        if (String.isBlank(session.vendor.Named_Credential_API_Name__c)) {
            throw problem('NAMED_CREDENTIAL_INVALID', 'Configure a Named Credential API Name for this vendor.', null);
        }
        VendorPricingMetadataRepository.AuthenticationConfiguration configuration = testConfiguration == null
            ? VendorPricingMetadataRepository.loadForAuthentication(session.vendor.Id) : testConfiguration;
        Vendor_Endpoint__mdt loginEndpoint;
        Vendor_Endpoint__mdt refreshEndpoint;
        Boolean configureRefresh = session.vendor.Authentication_Strategy__c == REFRESH_STRATEGY;
        for (Vendor_Endpoint__mdt endpoint : configuration.endpoints) {
            if (endpoint.Vendor__c != session.vendor.Id || endpoint.Active__c != true ||
                endpoint.Invocation_Policy__c != 'PREREQUISITE') {
                continue;
            }
            if (endpoint.Operation__c == TOKEN_OPERATION &&
                (String.isBlank(prerequisite) || endpoint.DeveloperName == prerequisite)) {
                if (loginEndpoint != null) {
                    throw problem('AUTH_LOGIN_AMBIGUOUS', 'Select one active token acquisition endpoint for the vendor.', null);
                }
                loginEndpoint = endpoint;
            }
            if (configureRefresh && endpoint.Operation__c == REFRESH_OPERATION) {
                if (refreshEndpoint != null) {
                    throw problem('AUTH_REFRESH_AMBIGUOUS', 'Configure one active refresh endpoint for the vendor.', null);
                }
                refreshEndpoint = endpoint;
            }
        }
        if (loginEndpoint == null) {
            throw problem('AUTH_LOGIN_UNAVAILABLE', 'Configure the active token acquisition endpoint for this route.', null);
        }
        session.login = definition(loginEndpoint, configuration.fields);
        if (configureRefresh) {
            if (refreshEndpoint == null || !session.login.responsePaths.containsKey(REFRESH_CODE)) {
                throw problem('AUTH_REFRESH_UNAVAILABLE', 'Configure the active refresh endpoint and login refresh-token mapping.', null);
            }
            session.refresh = definition(refreshEndpoint, configuration.fields);
        }

        Decimal configuredBuffer = session.vendor.Token_Expiry_Buffer_Seconds__c;
        if (configuredBuffer != null && (configuredBuffer < 0 || configuredBuffer > 99999 ||
            configuredBuffer != configuredBuffer.setScale(0, System.RoundingMode.DOWN))) {
            throw problem('AUTH_EXPIRY_BUFFER_INVALID', 'Set the token expiry buffer to whole seconds from 0 to 99999.', null);
        }
        session.expiryBufferMilliseconds = configuredBuffer == null ? 30000L : configuredBuffer.longValue() * 1000L;
    }

    private static EndpointDefinition definition(Vendor_Endpoint__mdt endpoint, List<Vendor_Field_Mapping__mdt> fields) {
        String contentType = endpoint.Request_Content_Type__c;
        if (endpoint.HTTP_Method__c != 'POST' || endpoint.Requires_Authentication__c == true ||
            String.isNotBlank(endpoint.Prerequisite_Endpoint_Code__c) ||
            (String.isNotBlank(endpoint.Execution_Mode__c) && endpoint.Execution_Mode__c != 'DIRECT') ||
            (String.isNotBlank(contentType) && contentType.substringBefore(';').trim() != 'application/json')) {
            throw problem('AUTH_ENDPOINT_INVALID', 'Use a direct JSON POST for the token endpoint without bearer authentication.', null);
        }
        EndpointDefinition result = new EndpointDefinition();
        result.endpoint = endpoint;
        Set<String> requestKeys = new Set<String>();
        Boolean hasCredential = false;
        for (Vendor_Field_Mapping__mdt field : fields) {
            if (field.Vendor_Endpoint__c != endpoint.Id) {
                continue;
            }
            String fieldCode = field.Internal_Field_Code__c;
            String path = field.Vendor_Field_Path__c;
            if (String.isBlank(path) || !JSON_PATH.matcher(path).matches()) {
                throw problem('AUTH_MAPPING_INVALID', 'Configure a valid JSON path for each token mapping.', null);
            }
            if (field.Direction__c == 'OUTBOUND') {
                if (path.contains('.') || requestKeys.contains(path)) {
                    throw problem('AUTH_MAPPING_INVALID', 'Configure distinct root JSON fields for the token request.', null);
                }
                requestKeys.add(path);
                String reference = field.Source_Reference__c;
                if (fieldCode == 'AUTH_CREDENTIAL' && String.isNotBlank(reference) &&
                    CREDENTIAL_FORMULA.matcher(reference).matches()) {
                    result.requestFields.put(path, reference);
                    hasCredential = true;
                } else if (fieldCode == 'AUTH_CONSTANT' && String.isNotBlank(reference) && !reference.contains('{!')) {
                    result.requestFields.put(path, reference);
                } else if (endpoint.Operation__c == REFRESH_OPERATION && String.isBlank(reference) &&
                    (fieldCode == ACCESS_CODE || fieldCode == REFRESH_CODE) &&
                    !result.requestTokenPaths.containsKey(fieldCode)) {
                    result.requestTokenPaths.put(fieldCode, path);
                } else {
                    throw problem('AUTH_MAPPING_INVALID', 'Review the outbound token mapping code and source reference.', null);
                }
            } else if (field.Direction__c == 'INBOUND') {
                if (result.responsePaths.containsKey(fieldCode) ||
                    (fieldCode != ACCESS_CODE && fieldCode != REFRESH_CODE && !EXPIRY_CODES.contains(fieldCode)) ||
                    (EXPIRY_CODES.contains(fieldCode) && result.expiryCode != null)) {
                    throw problem('AUTH_MAPPING_INVALID', 'Configure each token response role once with at most one expiry mapping.', null);
                }
                result.responsePaths.put(fieldCode, path);
                if (EXPIRY_CODES.contains(fieldCode)) {
                    result.expiryCode = fieldCode;
                }
            }
        }
        if (!result.responsePaths.containsKey(ACCESS_CODE) ||
            (endpoint.Operation__c == TOKEN_OPERATION && !hasCredential) ||
            (endpoint.Operation__c == REFRESH_OPERATION && !result.requestTokenPaths.containsKey(REFRESH_CODE))) {
            throw problem('AUTH_MAPPING_REQUIRED', 'Configure the token request fields and the access-token response path.', null);
        }
        return result;
    }

    private static TokenState renew(Session session) {
        if (session.refresh != null && session.token != null && session.token.refreshToken != null) {
            try {
                return exchange(session, session.refresh, session.token);
            } catch (AuthFailureException error) {
                if (error.statusCode != 400 && error.statusCode != 401) {
                    throw error;
                }
            }
        }
        return exchange(session, session.login, null);
    }

    private static TokenState exchange(Session session, EndpointDefinition definition, TokenState previousToken) {
        Boolean isRefresh = definition.endpoint.Operation__c == REFRESH_OPERATION;
        String requestBody = tokenRequestBody(definition, previousToken);
        VendorPricingMetadataRepository.CalloutConfiguration transportConfig =
            new VendorPricingMetadataRepository.CalloutConfiguration();
        transportConfig.endpoint = definition.endpoint;
        transportConfig.vendor = session.vendor;

        Long requestStartedAt = nowMilliseconds();
        VendorPricingHttpTransport.Response response =
            VendorPricingHttpTransport.send(transportConfig, requestBody, null);
        if (!response.success) {
            String action = isRefresh ? 'AUTH_REFRESH_' : 'AUTH_LOGIN_';
            throw problem(action + response.code, response.message, response.statusCode);
        }

        TokenState state = new TokenState();
        state.statusCode = response.statusCode;
        if (String.isBlank(response.body)) {
            throw problem('AUTH_RESPONSE_INVALID', 'The token endpoint returned an empty response.', response.statusCode);
        }
        try {
            Object payload = JSON.deserializeUntyped(response.body);
            if (!(payload instanceof Map<String, Object>)) {
                throw problem('AUTH_RESPONSE_INVALID', 'The token endpoint must return a JSON object.', response.statusCode);
            }
            state.accessToken = readToken(valueAtPath(payload, definition.responsePaths.get(ACCESS_CODE)), response.statusCode);
            Object refreshValue = valueAtPath(payload, definition.responsePaths.get(REFRESH_CODE));
            if (refreshValue != null && !(refreshValue instanceof String && String.isBlank((String) refreshValue))) {
                state.refreshToken = readToken(refreshValue, response.statusCode);
            } else if (isRefresh) {
                state.refreshToken = previousToken.refreshToken;
            } else if (session.refresh != null) {
                throw problem('AUTH_RESPONSE_INVALID', 'The login response is missing the configured refresh token.', response.statusCode);
            }
            if (definition.expiryCode != null) {
                Object expiryValue = valueAtPath(payload, definition.responsePaths.get(definition.expiryCode));
                Long expiryAt = expiryMilliseconds(expiryValue, definition.expiryCode, requestStartedAt);
                Long remaining = expiryAt - nowMilliseconds();
                if (remaining <= 0) {
                    throw problem('AUTH_EXPIRY_INVALID', 'The token response reported an expired bearer token.', response.statusCode);
                }
                Long halfLife = remaining / 2;
                Long buffer = session.expiryBufferMilliseconds < halfLife ? session.expiryBufferMilliseconds : halfLife;
                state.renewAtMilliseconds = expiryAt - buffer;
            }
        } catch (System.JSONException error) {
            throw problem('AUTH_RESPONSE_INVALID', 'The token response did not match the configured JSON contract.', response.statusCode);
        } catch (System.TypeException error) {
            throw problem('AUTH_EXPIRY_INVALID', 'The token response did not match the configured expiry format.', response.statusCode);
        }
        return state;
    }

    private static String tokenRequestBody(EndpointDefinition definition, TokenState previousToken) {
        String configuredFields = JSON.serialize(definition.requestFields);
        if (definition.requestTokenPaths.isEmpty()) {
            return configuredFields;
        }
        Map<String, Object> runtimeFields = new Map<String, Object>{
            definition.requestTokenPaths.get(REFRESH_CODE) => previousToken.refreshToken
        };
        String accessTokenPath = definition.requestTokenPaths.get(ACCESS_CODE);
        if (accessTokenPath != null) {
            runtimeFields.put(accessTokenPath, previousToken.accessToken);
        }
        String runtimeBody = VendorPricingHttpTransport.escapeCredentialExpressions(JSON.serialize(runtimeFields));
        if (definition.requestFields.isEmpty()) {
            return runtimeBody;
        }
        // Escape formula-like text in returned tokens before combining them with configured credential expressions.
        return configuredFields.substring(0, configuredFields.length() - 1) + ',' + runtimeBody.substring(1);
    }

    private static Object valueAtPath(Object node, String path) {
        if (path == null) {
            return null;
        }
        for (String segment : path.split('\\.')) {
            if (!(node instanceof Map<String, Object>)) {
                return null;
            }
            node = ((Map<String, Object>) node).get(segment);
        }
        return node;
    }

    private static String readToken(Object value, Integer statusCode) {
        if (!(value instanceof String) || String.isBlank((String) value) ||
            TOKEN_CONTROL_CHARACTER.matcher((String) value).find()) {
            throw problem('AUTH_RESPONSE_INVALID', 'The configured token response field is missing or invalid.', statusCode);
        }
        return (String) value;
    }

    private static Long expiryMilliseconds(Object value, String fieldCode, Long startedAt) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            throw new TypeException('The expiry value is missing.');
        }
        if (fieldCode == EXPIRY_DATE) {
            if (!(value instanceof String)) {
                throw new TypeException('Use an ISO date-time string for absolute expiry.');
            }
            return ((Datetime) JSON.deserialize(JSON.serialize(value), Datetime.class)).getTime();
        }
        Decimal lifetime = Decimal.valueOf(String.valueOf(value));
        if (lifetime < 1 || lifetime > 2147483647 ||
            lifetime != lifetime.setScale(0, System.RoundingMode.DOWN)) {
            throw new TypeException('Use a positive whole number for relative expiry.');
        }
        return startedAt + lifetime.longValue() * (fieldCode == EXPIRY_SECONDS ? 1000L : 1L);
    }

    private static Long nowMilliseconds() {
        return testTimeMilliseconds == null ? Datetime.now().getTime() : testTimeMilliseconds;
    }

    private static VendorPricingHttpTransport.Response probeSuccess(String code, Integer statusCode) {
        VendorPricingHttpTransport.Response result = new VendorPricingHttpTransport.Response();
        result.success = true;
        result.code = code;
        result.statusCode = statusCode;
        return result;
    }

    private static VendorPricingHttpTransport.Response failureResponse(AuthFailureException error) {
        VendorPricingHttpTransport.Response result = new VendorPricingHttpTransport.Response();
        result.code = error.code;
        result.message = error.getMessage();
        result.statusCode = error.statusCode;
        return result;
    }

    private static AuthFailureException problem(String code, String message, Integer statusCode) {
        AuthFailureException error = new AuthFailureException(message);
        error.code = code;
        error.statusCode = statusCode;
        return error;
    }
}