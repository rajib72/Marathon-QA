@IsTest
private class VendorPricingAuthenticationServiceTest {
    private static final Id VENDOR_ID = 'm00000000000601';
    private static final Id QUOTE_ID = 'm00000000000602';
    private static final Id LOGIN_ID = 'm00000000000603';
    private static final Id REFRESH_ID = 'm00000000000604';
    private static final String CREDENTIAL = 'Fixture_Pricing';
    private static final String LOGIN_USER = '{!$Credential.Fixture_Ext.LoginUser}';
    private static final String LOGIN_SECRET = '{!$Credential.Fixture_Ext.LoginSecret}';
    private static final Long TEST_NOW = 1800000000000L;

    private class ExpectedRequest {
        public String path;
        public String bearer;
        public Map<String, Object> body;
        public Integer statusCode;
        public String responseBody;

        public ExpectedRequest(
            String path, String bearer, Map<String, Object> body, Integer statusCode, String responseBody
        ) {
            this.path = path;
            this.bearer = bearer;
            this.body = body;
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
    }

    private class RequestSequence implements HttpCalloutMock {
        public List<ExpectedRequest> requests;
        public Integer seen = 0;

        public RequestSequence(List<ExpectedRequest> requests) {
            this.requests = requests;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assert(seen < requests.size(), 'Unexpected extra HTTP request.');
            ExpectedRequest expected = requests[seen];
            seen++;
            System.assertEquals('callout:' + CREDENTIAL + expected.path, request.getEndpoint());
            System.assertEquals('POST', request.getMethod());
            System.assertEquals('application/json', request.getHeader('Content-Type'));
            System.assertEquals(expected.bearer == null ? null : 'Bearer ' + expected.bearer,
                request.getHeader('Authorization'));
            System.assertEquals(expected.body, JSON.deserializeUntyped(request.getBody()));
            if (expected.path == '/quotes' || expected.path == '/renew') {
                System.assert(!request.getBody().contains('{!'), 'Keep formulas from input values literal.');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(expected.statusCode);
            response.setBody(expected.responseBody);
            return response;
        }
    }

    private static RequestSequence mock(List<ExpectedRequest> requests) {
        RequestSequence sequence = new RequestSequence(requests);
        Test.setMock(HttpCalloutMock.class, sequence);
        return sequence;
    }

    private static VendorPricingMetadataRepository.CalloutConfiguration fixture(Boolean withRefresh) {
        VendorPricingMetadataRepository.CalloutConfiguration result =
            new VendorPricingMetadataRepository.CalloutConfiguration();
        result.vendor = (Vendor_Integration__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => VENDOR_ID,
            'DeveloperName' => 'FIXTURE_VENDOR',
            'Active__c' => true,
            'Include_in_All_Vendor_Search__c' => true,
            'Named_Credential_API_Name__c' => CREDENTIAL,
            'Authentication_Strategy__c' => withRefresh ? 'TOKEN_WITH_REFRESH' : 'TOKEN',
            'Token_Expiry_Buffer_Seconds__c' => 3
        }), Vendor_Integration__mdt.class);
        result.endpoint = endpoint(QUOTE_ID, 'FIXTURE_QUOTE', 'QUOTE_CREATE', 'INITIAL_PRICING', '/quotes', true);

        VendorPricingMetadataRepository.AuthenticationConfiguration auth =
            new VendorPricingMetadataRepository.AuthenticationConfiguration();
        auth.endpoints.add(endpoint(LOGIN_ID, 'FIXTURE_LOGIN', 'TOKEN', 'PREREQUISITE', '/login', false));
        auth.fields.add(field(LOGIN_ID, 'OUTBOUND', 'AUTH_CREDENTIAL', 'identity', LOGIN_USER));
        auth.fields.add(field(LOGIN_ID, 'OUTBOUND', 'AUTH_CREDENTIAL', 'secret', LOGIN_SECRET));
        auth.fields.add(field(LOGIN_ID, 'OUTBOUND', 'AUTH_CONSTANT', 'grant_type', 'password'));
        if (withRefresh) {
            auth.endpoints.add(endpoint(REFRESH_ID, 'FIXTURE_REFRESH', 'TOKEN_REFRESH', 'PREREQUISITE', '/renew', false));
            auth.fields.add(field(REFRESH_ID, 'OUTBOUND', 'AUTH_REFRESH_TOKEN', 'renewal', null));
            for (Id endpointId : new List<Id>{LOGIN_ID, REFRESH_ID}) {
                auth.fields.add(field(endpointId, 'INBOUND', 'AUTH_ACCESS_TOKEN', 'envelope.access', null));
                auth.fields.add(field(endpointId, 'INBOUND', 'AUTH_REFRESH_TOKEN', 'envelope.renewal', null));
                auth.fields.add(field(endpointId, 'INBOUND', 'AUTH_EXPIRES_IN_SECONDS', 'envelope.ttl', null));
            }
        } else {
            auth.fields.add(field(LOGIN_ID, 'INBOUND', 'AUTH_ACCESS_TOKEN', 'access_Token', null));
            auth.fields.add(field(LOGIN_ID, 'INBOUND', 'AUTH_EXPIRES_IN_SECONDS', 'expires_in', null));
        }
        VendorPricingAuthenticationService.testConfiguration = auth;
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW;
        return result;
    }

    private static Vendor_Endpoint__mdt endpoint(
        Id endpointId, String developerName, String operation, String policy, String path, Boolean requiresToken
    ) {
        return (Vendor_Endpoint__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => endpointId,
            'DeveloperName' => developerName,
            'Vendor__c' => VENDOR_ID,
            'Active__c' => true,
            'Operation__c' => operation,
            'Invocation_Policy__c' => policy,
            'Execution_Mode__c' => 'DIRECT',
            'HTTP_Method__c' => 'POST',
            'Relative_Path__c' => path,
            'Requires_Authentication__c' => requiresToken
        }), Vendor_Endpoint__mdt.class);
    }

    private static Vendor_Field_Mapping__mdt field(
        Id endpointId, String direction, String code, String path, String reference
    ) {
        return new Vendor_Field_Mapping__mdt(
            Vendor_Endpoint__c = endpointId,
            Direction__c = direction,
            Internal_Field_Code__c = code,
            Vendor_Field_Path__c = path,
            Source_Reference__c = reference
        );
    }

    private static ExpectedRequest login(Integer statusCode, String body) {
        return new ExpectedRequest('/login', null, new Map<String, Object>{
            'identity' => LOGIN_USER, 'secret' => LOGIN_SECRET, 'grant_type' => 'password'
        }, statusCode, body);
    }

    private static ExpectedRequest refresh(String previousToken, Integer statusCode, String body) {
        return new ExpectedRequest('/renew', null, new Map<String, Object>{'renewal' => previousToken}, statusCode, body);
    }

    private static ExpectedRequest quote(String rowKey, String bearer, Integer statusCode) {
        return new ExpectedRequest('/quotes', bearer, new Map<String, Object>{'item' => rowKey}, statusCode, '{"offers":[]}');
    }

    private static String quoteBody(String rowKey) {
        return JSON.serialize(new Map<String, Object>{'item' => rowKey});
    }

    private static String envelope(String accessToken, String refreshToken) {
        Map<String, Object> payload = new Map<String, Object>{'access' => accessToken, 'ttl' => 20};
        if (refreshToken != null) {
            payload.put('renewal', refreshToken);
        }
        return JSON.serialize(new Map<String, Object>{'envelope' => payload});
    }

    private static VendorPricingRequestBuilder.PreparedRequest batch(String rowKey) {
        VendorPricingRequestBuilder.PreparedRequest result = new VendorPricingRequestBuilder.PreparedRequest();
        result.jsonBody = quoteBody(rowKey);
        result.rowKeys.add(rowKey);
        result.rowKeyByRequestKey.put('request-' + rowKey, rowKey);
        return result;
    }

    @IsTest
    static void logsInOnceAndSendsBothPreparedBatches() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(false);
        configuration.endpoint.Prerequisite_Endpoint_Code__c = 'FIXTURE_LOGIN';
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(201, '{"access_Token":"fixture-access","expires_in":600}'),
            quote('row-1', 'fixture-access', 200), quote('row-2', 'fixture-access', 201)
        });
        VendorPricingRequestBuilder.Result prepared = new VendorPricingRequestBuilder.Result();
        prepared.endpointDeveloperName = configuration.endpoint.DeveloperName;
        prepared.requests.add(batch('row-1'));
        prepared.requests.add(batch('row-2'));

        VendorPricingCalloutService.Result result = VendorPricingCalloutService.executePrepared(
            new VendorEndpointResolver.Route(configuration.vendor.DeveloperName, configuration.endpoint),
            prepared, configuration, null
        );

        System.assertEquals(0, result.preparationIssues.size());
        System.assertEquals(2, result.batches.size());
        System.assertEquals(true, result.batches[0].response.success);
        System.assertEquals(201, result.batches[1].response.statusCode);
        System.assertEquals('row-2', result.batches[1].rowKeyByRequestKey.get('request-row-2'));
        System.assertEquals('{"offers":[]}', result.batches[1].response.body);
        System.assertEquals(3, sequence.seen);
    }

    @IsTest
    static void refreshesAheadOfExpiryAndKeepsTheLatestRefreshToken() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(true);
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(200, envelope('access-one', 'refresh-one')), quote('row-1', 'access-one', 200),
            refresh('refresh-one', 200, envelope('access-two', 'refresh-two')), quote('row-2', 'access-two', 200),
            refresh('refresh-two', 200, envelope('access-three', null)), quote('row-3', 'access-three', 200),
            refresh('refresh-two', 200, envelope('access-four', 'refresh-four')), quote('row-4', 'access-four', 200)
        });

        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).success);
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW + 17000L;
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-2')).success);
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW + 34000L;
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-3')).success);
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW + 51000L;
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-4')).success);
        System.assertEquals(8, sequence.seen);
    }

    @IsTest
    static void aRejectedRefreshReacquiresForTheNextBatchWithoutReplayingThePreviousBatch() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(true);
        VendorPricingAuthenticationService.testConfiguration.fields.add(
            field(REFRESH_ID, 'OUTBOUND', 'AUTH_ACCESS_TOKEN', 'presentedAccess', null)
        );
        ExpectedRequest rejectedRefresh = refresh('refresh-one', 400, '{"private":"fixture-detail"}');
        rejectedRefresh.body.put('presentedAccess', 'access-one');
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(200, envelope('access-one', 'refresh-one')), quote('row-1', 'access-one', 401),
            rejectedRefresh,
            login(200, envelope('access-two', 'refresh-two')), quote('row-2', 'access-two', 401)
        });

        System.assertEquals(401, VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).statusCode);
        System.assertEquals(401, VendorPricingAuthenticationService.send(configuration, quoteBody('row-2')).statusCode);
        VendorPricingHttpTransport.Response result = VendorPricingAuthenticationService.send(configuration, quoteBody('row-3'));
        System.assertEquals('AUTH_BEARER_REJECTED', result.code);
        System.assertEquals(null, result.body);
        System.assertEquals(5, sequence.seen);
    }

    @IsTest
    static void refreshRateLimitStopsFurtherAuthenticationInTheTransaction() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(true);
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(200, envelope('access-one', 'refresh-one')), quote('row-1', 'access-one', 200),
            refresh('refresh-one', 429, '{"private":"fixture-detail"}')
        });
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).success);
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW + 20000L;

        VendorPricingHttpTransport.Response result = VendorPricingAuthenticationService.send(configuration, quoteBody('row-2'));
        System.assertEquals('AUTH_REFRESH_HTTP_RATE_LIMITED', result.code);
        System.assertEquals(429, result.statusCode);
        System.assertEquals(null, result.body);
        System.assertEquals(result.code, VendorPricingAuthenticationService.send(configuration, quoteBody('row-3')).code);
        System.assertEquals(3, sequence.seen);
    }

    @IsTest
    static void preservesFormulaLikeRuntimeValuesAsJsonLiterals() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(true);
        String formulaLikeValue = '{!$Credential.Fixture_Ext.LoginSecret}';
        VendorPricingAuthenticationService.testConfiguration.fields.add(
            field(REFRESH_ID, 'OUTBOUND', 'AUTH_CONSTANT', 'mode', 'refresh')
        );
        ExpectedRequest refreshRequest = refresh('opaque-' + formulaLikeValue, 200, envelope('access-two', 'refresh-two'));
        refreshRequest.body.put('mode', 'refresh');
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(200, envelope('access-one', 'opaque-' + formulaLikeValue)),
            quote(formulaLikeValue, 'access-one', 200),
            refreshRequest,
            quote('row-2', 'access-two', 200)
        });
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody(formulaLikeValue)).success);
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW + 17000L;
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-2')).success);
        System.assertEquals(4, sequence.seen);
    }

    @IsTest
    static void verifiesSandboxCredentialsAndRefreshWithoutSendingAPricingRequest() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(true);
        configuration.endpoint.Active__c = false;
        VendorPricingMetadataRepository.AuthenticationConfiguration auth = VendorPricingAuthenticationService.testConfiguration;
        for (Integer index = auth.fields.size() - 1; index >= 0; index--) {
            Vendor_Field_Mapping__mdt mapping = auth.fields[index];
            if (mapping.Direction__c == 'INBOUND' && mapping.Internal_Field_Code__c == 'AUTH_EXPIRES_IN_SECONDS') {
                auth.fields.remove(index);
            } else if (mapping.Direction__c == 'INBOUND') {
                mapping.Vendor_Field_Path__c = mapping.Internal_Field_Code__c == 'AUTH_ACCESS_TOKEN'
                    ? 'data.token' : 'data.refreshToken';
            } else if (mapping.Vendor_Endpoint__c == REFRESH_ID) {
                mapping.Vendor_Field_Path__c = 'refreshToken';
            }
        }
        auth.fields.add(field(REFRESH_ID, 'OUTBOUND', 'AUTH_ACCESS_TOKEN', 'token', null));
        String loginBody = '{"succeeded":true,"data":{"token":"fixture-access","refreshToken":"fixture-refresh",' +
            '"refreshTokenExpiryTime":"2030-01-01T12:00:00.1234567-08:00"}}';
        String refreshBody = '{"succeeded":true,"data":{"token":"renewed-access","refreshToken":"renewed-refresh",' +
            '"refreshTokenExpiryTime":"2030-01-01T12:00:00.1234567"}}';
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(200, loginBody),
            new ExpectedRequest('/renew', null, new Map<String, Object>{
                'token' => 'fixture-access', 'refreshToken' => 'fixture-refresh'
            }, 200, refreshBody)
        });

        List<VendorPricingHttpTransport.Response> steps = VendorPricingAuthenticationService.verify(configuration, true);

        System.assertEquals(2, steps.size());
        System.assertEquals('AUTH_LOGIN_SUCCESS', steps[0].code);
        System.assertEquals(200, steps[0].statusCode);
        System.assertEquals('AUTH_REFRESH_SUCCESS', steps[1].code);
        System.assertEquals(null, steps[0].body);
        System.assertEquals(null, steps[1].body);
        System.assertEquals(2, sequence.seen);
    }

    @IsTest
    static void requiresExactResponseKeyAndWithholdsTheResponseBody() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(false);
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(201, '{"access_token":"different-key","expires_in":600}')
        });

        VendorPricingHttpTransport.Response result = VendorPricingAuthenticationService.send(configuration, quoteBody('row-1'));
        System.assertEquals('AUTH_RESPONSE_INVALID', result.code);
        System.assertEquals(201, result.statusCode);
        System.assertEquals(null, result.body);
        System.assertEquals(result.code, VendorPricingAuthenticationService.send(configuration, quoteBody('row-2')).code);
        System.assertEquals(1, sequence.seen);
    }

    @IsTest
    static void reportsMissingLoginAndRejectsCredentialLiterals() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(false);
        RequestSequence sequence = mock(new List<ExpectedRequest>());
        configuration.endpoint.Prerequisite_Endpoint_Code__c = 'MISSING_ENDPOINT';
        System.assertEquals('AUTH_LOGIN_UNAVAILABLE',
            VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).code);

        configuration.endpoint.Prerequisite_Endpoint_Code__c = 'FIXTURE_LOGIN';
        VendorPricingAuthenticationService.testConfiguration.fields[0].Source_Reference__c = 'fixture-literal';
        System.assertEquals('AUTH_MAPPING_INVALID',
            VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).code);
        System.assertEquals(0, sequence.seen);
    }

    @IsTest
    static void validatesAnAbsoluteExpiryAndReacquiresForTokenOnlyVendors() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(false);
        Vendor_Field_Mapping__mdt expiry = VendorPricingAuthenticationService.testConfiguration.fields[4];
        expiry.Internal_Field_Code__c = 'AUTH_EXPIRES_AT';
        expiry.Vendor_Field_Path__c = 'expires';
        String firstExpiry = Datetime.newInstance(TEST_NOW + 10000L).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String nextExpiry = Datetime.newInstance(TEST_NOW + 30000L).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(201, '{"access_Token":"absolute-one","expires":"' + firstExpiry + '"}'),
            quote('row-1', 'absolute-one', 201),
            login(201, '{"access_Token":"absolute-two","expires":"' + nextExpiry + '"}'),
            quote('row-2', 'absolute-two', 201)
        });
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).success);
        VendorPricingAuthenticationService.testTimeMilliseconds = TEST_NOW + 7000L;
        System.assertEquals(true, VendorPricingAuthenticationService.send(configuration, quoteBody('row-2')).success);
        System.assertEquals(4, sequence.seen);
    }

    @IsTest
    static void returnsOnlyAStatusForHttpAuthenticationFailures() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(false);
        RequestSequence sequence = mock(new List<ExpectedRequest>{
            login(400, '{"access_Token":"unused-fixture","errorMessage":"fixture-detail"}')
        });
        VendorPricingHttpTransport.Response result = VendorPricingAuthenticationService.send(configuration, quoteBody('row-1'));
        System.assertEquals(false, result.success);
        System.assertEquals(400, result.statusCode);
        System.assertEquals('AUTH_LOGIN_HTTP_REQUEST_REJECTED', result.code);
        System.assertEquals(null, result.body);
        System.assertEquals(1, sequence.seen);
    }

    @IsTest
    static void detectsUnlinkedAndInactiveConfigurationBeforeSendingRequests() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture(false);
        RequestSequence sequence = mock(new List<ExpectedRequest>());
        configuration.vendor.Named_Credential_API_Name__c = null;
        System.assertEquals('NAMED_CREDENTIAL_INVALID',
            VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).code);
        configuration.vendor.Active__c = false;
        System.assertEquals('AUTH_CONFIGURATION_REQUIRED',
            VendorPricingAuthenticationService.send(configuration, quoteBody('row-1')).code);
        System.assertEquals('AUTH_CONFIGURATION_REQUIRED',
            VendorPricingAuthenticationService.verifyAuthentication(null, false)[0].code);
        System.assertEquals(0, sequence.seen);
    }
}