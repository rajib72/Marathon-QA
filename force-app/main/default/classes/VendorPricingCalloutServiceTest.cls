@IsTest
private class VendorPricingCalloutServiceTest {
    private static final Id VENDOR_ID = 'm00000000000021';
    private static final Id ENDPOINT_ID = 'm00000000000022';
    private static final String ENDPOINT_NAME = 'FIXTURE_QUOTE';
    private static final String FIXTURE_URL = 'callout:Fixture_Pricing/api/quotes';

    public class ExpectedCallouts implements HttpCalloutMock {
        public String expectedEndpoint = FIXTURE_URL;
        public String expectedMethod = 'POST';
        public String expectedAccept = 'application/json';
        public String expectedContentType = 'application/json';
        public String expectedAuthorization;
        private List<String> expectedBodies;
        private List<Integer> statuses;
        private Integer requestsSeen = 0;

        public ExpectedCallouts(List<String> expectedBodies, List<Integer> statuses) {
            this.expectedBodies = expectedBodies;
            this.statuses = statuses;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assert(requestsSeen < statuses.size(), 'An extra HTTP request was attempted.');
            System.assertEquals(expectedEndpoint, request.getEndpoint());
            System.assertEquals(expectedMethod, request.getMethod());
            System.assertEquals(expectedAccept, request.getHeader('Accept'));
            System.assertEquals(expectedContentType, request.getHeader('Content-Type'));
            System.assertEquals(expectedAuthorization, request.getHeader('Authorization'));
            String expectedBody = expectedBodies[requestsSeen];
            if (expectedBody == null) {
                System.assert(String.isBlank(request.getBody()), 'Expected an empty request body.');
            } else {
                System.assertEquals(JSON.deserializeUntyped(expectedBody), JSON.deserializeUntyped(request.getBody()));
            }
            Integer statusCode = statuses[requestsSeen];
            requestsSeen++;
            if (statusCode == null) {
                throw new CalloutException('Mock diagnostic with fixture-private-detail');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody('{"fixture":"response"}');
            return response;
        }
    }

    private static VendorPricingMetadataRepository.CalloutConfiguration fixture() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration =
            new VendorPricingMetadataRepository.CalloutConfiguration();
        configuration.vendor = (Vendor_Integration__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => VENDOR_ID,
            'DeveloperName' => 'FIXTURE_VENDOR',
            'Active__c' => true,
            'Include_in_All_Vendor_Search__c' => true,
            'Named_Credential_API_Name__c' => 'Fixture_Pricing',
            'Default_Timeout_Milliseconds__c' => 5000,
            'Default_Request_Builder__c' => 'FLAT_JSON'
        }), Vendor_Integration__mdt.class);
        configuration.endpoint = (Vendor_Endpoint__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => ENDPOINT_ID,
            'DeveloperName' => ENDPOINT_NAME,
            'Vendor__c' => VENDOR_ID,
            'Active__c' => true,
            'Operation__c' => 'QUOTE_CREATE',
            'Invocation_Policy__c' => 'INITIAL_PRICING',
            'Execution_Mode__c' => 'DIRECT',
            'HTTP_Method__c' => 'POST',
            'Relative_Path__c' => '/api/quotes',
            'Supported_Search_Modes__c' => 'PART_NUMBER'
        }), Vendor_Endpoint__mdt.class);
        return configuration;
    }

    private static VendorEndpointResolver.Route route(VendorPricingMetadataRepository.CalloutConfiguration configuration) {
        return new VendorEndpointResolver.Route(configuration.vendor.DeveloperName, configuration.endpoint);
    }

    private static VendorPricingRequestBuilder.PreparedRequest preparedBatch(String rowKey, String requestKey) {
        VendorPricingRequestBuilder.PreparedRequest request = new VendorPricingRequestBuilder.PreparedRequest();
        request.rowKeys.add(rowKey);
        request.rowKeyByRequestKey.put(requestKey, rowKey);
        request.jsonBody = '{"partRef":"' + rowKey + '"}';
        return request;
    }

    private static VendorPricingRequestBuilder.Result twoPreparedBatches() {
        VendorPricingRequestBuilder.Result result = new VendorPricingRequestBuilder.Result();
        result.endpointDeveloperName = ENDPOINT_NAME;
        result.validation = new VendorPricingValidationService.Result();
        result.validation.validRowKeys.addAll(new List<String>{'row-1', 'row-2'});
        result.requests.add(preparedBatch('row-1', '1'));
        result.requests.add(preparedBatch('row-2', '2'));
        return result;
    }

    private static void allowNoHttpRequests() {
        Test.setMock(HttpCalloutMock.class, new ExpectedCallouts(new List<String>(), new List<Integer>()));
    }

    @IsTest
    static void sendsBothPreparedBatchesAndPreservesTheirRowCorrelation() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        VendorPricingRequestBuilder.Result prepared = twoPreparedBatches();
        Test.setMock(HttpCalloutMock.class, new ExpectedCallouts(
            new List<String>{prepared.requests[0].jsonBody, prepared.requests[1].jsonBody},
            new List<Integer>{201, 429}
        ));

        VendorPricingCalloutService.Result result = VendorPricingCalloutService.executePrepared(
            route(configuration), prepared, configuration, null
        );

        System.assertEquals(0, result.preparationIssues.size());
        System.assertEquals(2, result.batches.size());
        System.assertEquals(new List<String>{'row-1', 'row-2'}, result.validation.validRowKeys);
        System.assertEquals(new List<String>{'row-1'}, result.batches[0].rowKeys);
        System.assertEquals('row-1', result.batches[0].rowKeyByRequestKey.get('1'));
        System.assertEquals('row-2', result.batches[1].rowKeyByRequestKey.get('2'));
        System.assertEquals(true, result.batches[0].response.success);
        System.assertEquals(201, result.batches[0].response.statusCode);
        System.assertEquals('{"fixture":"response"}', result.batches[0].response.body);
        System.assertEquals(false, result.batches[1].response.success);
        System.assertEquals(429, result.batches[1].response.statusCode);
        System.assertEquals('HTTP_RATE_LIMITED', result.batches[1].response.code);
        prepared.requests[0].rowKeys.clear();
        System.assertEquals(1, result.batches[0].rowKeys.size());
    }

    @IsTest
    static void sendsARequestBuiltWithExistingPricingPreparationLogic() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        VendorPricingMetadataRepository.RequestConfiguration builderConfig =
            new VendorPricingMetadataRepository.RequestConfiguration();
        builderConfig.vendor = configuration.vendor;
        builderConfig.endpoint = configuration.endpoint;
        builderConfig.fields.add(new Vendor_Field_Mapping__mdt(
            Active__c = true, Internal_Field_Code__c = 'PART_NUMBER',
            Vendor_Field_Path__c = 'lookup', Record_Scope__c = 'PART_ITEM',
            Transport_Location__c = 'BODY', Source_Type__c = 'REQUEST_CONTEXT',
            Data_Type__c = 'STRING', Requirement_Mode__c = 'REQUIRED'
        ));

        VendorPricingRequestContext context = new VendorPricingRequestContext();
        context.claimId = (Id)(Claim.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        context.vin = '1HGCM82633A004352';
        context.repairShopAccountId = '001000000000001';
        context.repairShopStreet = '100 Main St';
        context.repairShopCity = 'Los Angeles';
        context.repairShopState = 'CA';
        context.repairShopPostalCode = '90001';
        VendorPricingLineContext line = new VendorPricingLineContext();
        line.rowKey = 'test-part';
        line.detailType = 'Part';
        line.searchMode = 'PART_NUMBER';
        line.partNumber = 'FIXTURE-123';
        line.adjustedQuantity = 1;
        context.lines.add(line);
        VendorPricingRequestBuilder.Result prepared = VendorPricingRequestBuilder.prepare(
            context, ENDPOINT_NAME, new Set<String>{'test-part'}, null, false, builderConfig
        );
        ExpectedCallouts mock = new ExpectedCallouts(
            new List<String>{'{"lookup":"FIXTURE-123"}'}, new List<Integer>{200}
        );
        Test.setMock(HttpCalloutMock.class, mock);

        VendorPricingCalloutService.Result result = VendorPricingCalloutService.executePrepared(
            route(configuration), prepared, configuration, null
        );
        System.assertEquals(0, result.preparationIssues.size(), JSON.serialize(result.preparationIssues));
        System.assertEquals(1, result.batches.size());
        System.assertEquals('test-part', result.batches[0].rowKeyByRequestKey.get('1'));
        System.assertEquals('HTTP_SUCCESS', result.batches[0].response.code);
    }

    @IsTest
    static void usesTheConfiguredCredentialPathAndMediaHeaders() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        configuration.vendor.Named_Credential_API_Name__c = 'Other_Pricing';
        configuration.endpoint.Relative_Path__c = '/v2/lookup';
        configuration.endpoint.HTTP_Method__c = 'PUT';
        configuration.endpoint.Accept_Header__c = 'application/vnd.fixture+json';
        configuration.endpoint.Request_Content_Type__c = 'application/json; charset=utf-8';
        ExpectedCallouts mock = new ExpectedCallouts(new List<String>{'{}'}, new List<Integer>{202});
        mock.expectedEndpoint = 'callout:Other_Pricing/v2/lookup';
        mock.expectedMethod = 'PUT';
        mock.expectedAccept = 'application/vnd.fixture+json';
        mock.expectedContentType = 'application/json; charset=utf-8';
        Test.setMock(HttpCalloutMock.class, mock);

        VendorPricingHttpTransport.Response result = VendorPricingHttpTransport.send(configuration, '{}', null);
        System.assertEquals(true, result.success);
        System.assertEquals(202, result.statusCode);
    }

    @IsTest
    static void handsOffBearerAuthenticationAndRejectsMissingOrMalformedTokens() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        configuration.vendor.Authentication_Strategy__c = 'TOKEN_WITH_REFRESH';
        configuration.endpoint.Requires_Authentication__c = true;
        configuration.endpoint.Prerequisite_Endpoint_Code__c = 'FIXTURE_TOKEN';
        allowNoHttpRequests();

        System.assertEquals('AUTH_TOKEN_REQUIRED', VendorPricingHttpTransport.send(configuration, '{}', null).code);
        System.assertEquals('AUTH_TOKEN_INVALID', VendorPricingHttpTransport.send(configuration, '{}', 'bad token').code);
        configuration.endpoint.Requires_Authentication__c = false;
        System.assertEquals(
            'CALLOUT_PREREQUISITE_UNSUPPORTED', VendorPricingHttpTransport.send(configuration, '{}', null).code
        );
        configuration.endpoint.Requires_Authentication__c = true;

        ExpectedCallouts mock = new ExpectedCallouts(new List<String>{'{}'}, new List<Integer>{200});
        mock.expectedAuthorization = 'Bearer fixture-token';
        Test.setMock(HttpCalloutMock.class, mock);
        System.assertEquals(
            'HTTP_SUCCESS', VendorPricingHttpTransport.send(configuration, '{}', 'fixture-token').code
        );
    }

    @IsTest
    static void checksMetadataOwnershipActivationPolicyAndOperation() {
        allowNoHttpRequests();
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        VendorEndpointResolver.Route chosenRoute = route(configuration);
        VendorPricingRequestBuilder.Result prepared = twoPreparedBatches();
        VendorPricingCalloutService.Result result = VendorPricingCalloutService.executePrepared(
            chosenRoute, prepared, null, null
        );
        System.assertEquals('CALLOUT_ROUTE_UNAVAILABLE', result.preparationIssues[0].code);

        configuration.vendor.Include_in_All_Vendor_Search__c = false;
        result = VendorPricingCalloutService.executePrepared(chosenRoute, prepared, configuration, null);
        System.assertEquals('CALLOUT_ROUTE_UNAVAILABLE', result.preparationIssues[0].code);

        configuration.vendor.Include_in_All_Vendor_Search__c = true;
        configuration.endpoint.Invocation_Policy__c = 'ON_DEMAND';
        result = VendorPricingCalloutService.executePrepared(chosenRoute, prepared, configuration, null);
        System.assertEquals('CALLOUT_ROUTE_UNAVAILABLE', result.preparationIssues[0].code);

        configuration.endpoint.Invocation_Policy__c = 'INITIAL_PRICING';
        prepared.endpointDeveloperName = 'WRONG_ENDPOINT';
        result = VendorPricingCalloutService.executePrepared(chosenRoute, prepared, configuration, null);
        System.assertEquals('CALLOUT_ROUTE_UNAVAILABLE', result.preparationIssues[0].code);
        System.assertEquals(0, result.batches.size());
    }

    @IsTest
    static void rejectsInactiveEndpointsAndUnreadyConfiguration() {
        allowNoHttpRequests();
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        System.assertEquals('CALLOUT_CONFIGURATION_REQUIRED', VendorPricingHttpTransport.send(null, '{}', null).code);
        configuration.endpoint.Vendor__c = null;
        System.assertEquals('CALLOUT_CONFIGURATION_REQUIRED', VendorPricingHttpTransport.send(configuration, '{}', null).code);

        configuration = fixture();
        configuration.endpoint.Active__c = false;
        System.assertEquals('CALLOUT_ENDPOINT_INACTIVE', VendorPricingHttpTransport.send(configuration, '{}', null).code);

        configuration.endpoint.Active__c = true;
        configuration.endpoint.Execution_Mode__c = 'UNSUPPORTED';
        System.assertEquals(
            'CALLOUT_EXECUTION_MODE_UNSUPPORTED', VendorPricingHttpTransport.send(configuration, '{}', null).code
        );
    }

    @IsTest
    static void requiresAValidNamedCredentialNameAndRelativePath() {
        allowNoHttpRequests();
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        configuration.vendor.Named_Credential_API_Name__c = 'http://invalid.example';
        System.assertEquals('NAMED_CREDENTIAL_INVALID', VendorPricingHttpTransport.send(configuration, '{}', null).code);
        configuration.vendor.Named_Credential_API_Name__c = 'Fixture_Pricing';
        for (String invalidPath : new List<String>{null, 'https://invalid.example', '//invalid.example', '/has space', '/a#b'}) {
            configuration.endpoint.Relative_Path__c = invalidPath;
            System.assertEquals('CALLOUT_PATH_INVALID', VendorPricingHttpTransport.send(configuration, '{}', null).code);
        }
    }

    @IsTest
    static void honorsTimeoutPrecedenceAndRejectsInvalidTransportSettings() {
        allowNoHttpRequests();
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        System.assertEquals(5000, VendorPricingHttpTransport.resolveTimeout(configuration.endpoint, configuration.vendor));
        configuration.endpoint.Timeout_Milliseconds__c = 15000;
        System.assertEquals(15000, VendorPricingHttpTransport.resolveTimeout(configuration.endpoint, configuration.vendor));

        configuration.endpoint.Timeout_Milliseconds__c = 120001;
        System.assertEquals('CALLOUT_TIMEOUT_INVALID', VendorPricingHttpTransport.send(configuration, '{}', null).code);
        configuration.endpoint.Timeout_Milliseconds__c = null;
        configuration.vendor.Default_Timeout_Milliseconds__c = null;
        System.assertEquals(null, VendorPricingHttpTransport.resolveTimeout(configuration.endpoint, configuration.vendor));

        configuration.endpoint.Accept_Header__c = 'application/json\nX-Fake-Header: value';
        System.assertEquals('CALLOUT_HEADER_INVALID', VendorPricingHttpTransport.send(configuration, '{}', null).code);
        configuration.endpoint.Accept_Header__c = null;
        System.assertEquals('AUTH_TOKEN_UNEXPECTED', VendorPricingHttpTransport.send(configuration, '{}', 'fixture-token').code);

        configuration.endpoint.HTTP_Method__c = 'GET';
        System.assertEquals('CALLOUT_BODY_UNSUPPORTED', VendorPricingHttpTransport.send(configuration, '{}', null).code);
        configuration.endpoint.HTTP_Method__c = 'TRACE';
        System.assertEquals('CALLOUT_METHOD_UNSUPPORTED', VendorPricingHttpTransport.send(configuration, '{}', null).code);
    }

    @IsTest
    static void supportsAConfiguredBodylessGet() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        configuration.endpoint.HTTP_Method__c = 'GET';
        ExpectedCallouts mock = new ExpectedCallouts(new List<String>{null}, new List<Integer>{204});
        mock.expectedMethod = 'GET';
        mock.expectedContentType = null;
        Test.setMock(HttpCalloutMock.class, mock);
        VendorPricingHttpTransport.Response result = VendorPricingHttpTransport.send(configuration, null, null);
        System.assertEquals(true, result.success);
        System.assertEquals(204, result.statusCode);
    }

    @IsTest
    static void classifiesHttpFailuresAndSanitizesCalloutExceptions() {
        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        Map<Integer, String> expectedCodes = new Map<Integer, String>{
            302 => 'HTTP_UNEXPECTED_STATUS', 400 => 'HTTP_REQUEST_REJECTED',
            401 => 'HTTP_AUTHORIZATION_FAILED', 403 => 'HTTP_AUTHORIZATION_FAILED',
            503 => 'HTTP_VENDOR_ERROR'
        };
        for (Integer statusCode : expectedCodes.keySet()) {
            Test.setMock(HttpCalloutMock.class, new ExpectedCallouts(new List<String>{'{}'}, new List<Integer>{statusCode}));
            VendorPricingHttpTransport.Response result = VendorPricingHttpTransport.send(configuration, '{}', null);
            System.assertEquals(false, result.success);
            System.assertEquals(statusCode, result.statusCode);
            System.assertEquals(expectedCodes.get(statusCode), result.code);
        }
        Test.setMock(HttpCalloutMock.class, new ExpectedCallouts(new List<String>{'{}'}, new List<Integer>{null}));
        VendorPricingHttpTransport.Response failure = VendorPricingHttpTransport.send(configuration, '{}', null);
        System.assertEquals('CALLOUT_FAILED', failure.code);
        System.assertEquals(null, failure.statusCode);
        System.assertEquals(false, failure.message.contains('fixture-private-detail'));
    }

    @IsTest
    static void preservesPreparationIssuesAndHandlesAnEmptyRoute() {
        allowNoHttpRequests();
        VendorPricingCalloutService.Result result = VendorPricingCalloutService.execute(null, null, null, null);
        System.assertEquals('CALLOUT_ROUTE_REQUIRED', result.preparationIssues[0].code);
        System.assertEquals(0, result.batches.size());

        VendorPricingMetadataRepository.CalloutConfiguration configuration = fixture();
        result = VendorPricingCalloutService.execute(null, route(configuration), new Set<String>{'row-1'}, null, null);
        System.assertEquals('CONTEXT_REQUIRED', result.validation.requestIssues[0].code);
        System.assertEquals(0, result.batches.size());

        VendorPricingRequestBuilder.Result prepared = new VendorPricingRequestBuilder.Result();
        prepared.issues.add(new VendorPricingRequestBuilder.Issue('FIXTURE_ISSUE', 'row-1', 'Fixture issue.'));
        result = VendorPricingCalloutService.executePrepared(route(configuration), prepared, null, null);
        System.assertEquals('FIXTURE_ISSUE', result.preparationIssues[0].code);
        System.assertEquals(0, result.batches.size());
    }

    @IsTest
    static void verifiesTheLiveRepositoryProjectionWithoutMakingARequest() {
        System.assertEquals(null, VendorPricingMetadataRepository.loadForCallout(null).endpoint);
        List<Vendor_Endpoint__mdt> configuredEndpoints = [SELECT Id, DeveloperName FROM Vendor_Endpoint__mdt LIMIT 1];
        if (!configuredEndpoints.isEmpty()) {
            VendorPricingMetadataRepository.CalloutConfiguration loaded =
                VendorPricingMetadataRepository.loadForCallout(configuredEndpoints[0].Id);
            System.assertEquals(configuredEndpoints[0].DeveloperName, loaded.endpoint.DeveloperName);
        }
        System.assertEquals(0, Limits.getDmlStatements());
        System.assertEquals(0, Limits.getCallouts());
    }
}