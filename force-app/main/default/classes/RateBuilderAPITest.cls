@isTest(seealldata = true)
public class RateBuilderAPITest {
    @isTest
    static void testDealerCostRate() {
        String mockJson = '{ "rows": [ { "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "RateSet": "MBI_RateSet_CA", "DealerProgramId": "123","OptionSet": "MBI Options - AmTrust (CA)" } } ] }';
        Test.setMock(HttpCalloutMock.class, new RateBuilderAPITest.RateBuilderAPIMock(mockJson));
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/RateImplementationBuilder/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{'Client' => 'Endurance', 'Product' => 'Marathon MBI', 'CoverageLevel' => 'Standard Used', 'RequestType' => 'Dealer Cost Rates'}));
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = RateBuilderAPI.processRateImplementation();
        //RateBuilderAPI.rateSetsDMCall();
        //RateBuilderAPI.fetchMetadatabyTableName('MBI_RateSet_CA', 'Standard Used');
        Test.stopTest();
    } 
    
   @isTest
    static void testBreakoutRateSetsDMCall() {
        String mockJson = '{ "rows": [ ' +
            '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "DealerProgramId": "123", "RateSet": "Superior RSC", "OptionSet": "MBI Options - AmTrust (CA)", "StateSet": "MBI AmTrust States" } },' +
            '{ "rowData": { "CoverageName": "Standard Used", "ExpireType": "Term", "MinTermMonths": "12", "MaxTermMonths": "60", "MinTermMiles": "12000", "MaxTermMiles": "100000", "RateClass": "Class1" } }' +']}';
        Test.setMock(HttpCalloutMock.class, new RateBuilderAPITest.RateBuilderAPIMock(mockJson));
        
        Account clientAccount = TestDataFactory.createSellingAgencyAccount(true);
        clientAccount.Name = 'Endurance';
        update clientAccount;
        Allocation_Code__c all8001Code = new Allocation_Code__c(Name = '8001', Client__c = clientAccount.Id, Product__c = 'Marathon MBI', Coverage_Level__c = 'Standard Used', Descriptor__c = 'Admin Fee', Allocation_Amount__c = '100.0');
        insert all8001Code;
         
        RateBuilderAPI.RateRequest req = new RateBuilderAPI.RateRequest();
        req.Client = 'Endurance';
        req.Product = 'Marathon MBI';
        req.CoverageLevel = 'Premium New';
        req.RequestType = 'Dealer Cost Breakout';
        Test.startTest();
        String result = RateBuilderAPI.setup(req);
        RateBuilderAPI.dealerCostBreakoutRateSetsDMCall();
        Test.stopTest();
    }

    
    @isTest
    static void testDealerCodeOptions() {
        String mockOptionSetResponse = '{ "rows": [' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "DealerProgramId": "123", "OptionSets": "MBI_Option_Set" } },' +
        '{ "rowData": { ' +
            '"CoverageName": "Standard Used", "ExpireType": "Term", "MinTermMonths": "12", "MaxTermMonths": "60", ' +
            '"MinTermMiles": "12000", "MaxTermMiles": "100000", "MinVehicleMiles": " 10000", "MaxVehicleMiles": "60000", ' +
            '"MinVehicleAge": "0", "MaxVehicleAge": "5", "RateClass": "Class1", "OptionCost": "250.00", "AutoApply": "true" ' +
        '} }' +']}';
        Test.setMock(HttpCalloutMock.class, new RateBuilderAPITest.RateBuilderAPIMock(mockOptionSetResponse));
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/RateImplementationBuilder/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{'Client' => 'Endurance', 'Product' => 'Marathon MBI', 'CoverageLevel' => 'Standard Used', 'RequestType' => 'Rate Options'}));
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = RateBuilderAPI.processRateImplementation();
        RateBuilderAPI.optionSetsDMCall();
        Test.stopTest();
    }
    
    @isTest
    static void testDealerCodeSurcharge() {
        String mockResponse = '{ "rows": [ ' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "DealerProgramId": "123", "SurchargeSets": "MBI_Surcharge_Set" } },' +
        '{ "rowData": { "SurchargeName": "AWD", "CoverageName": "Standard Used", "SurchargeCost": "150", "UpToAddOn": "Yes", ' +
        '"MinTermMonths": "12", "MaxTermMonths": "48", "MinTermMiles": "12000", "MaxTermMiles": "48000", ' +
        '"MinVehicleMiles": "0", "MaxVehicleMiles": "100000", "MinVehicleAge": "0", "MaxVehicleAge": "10", ' +
        '"RateClassList": "Class1" } }' + 
    ' ] }';
        Test.setMock(HttpCalloutMock.class, new RateBuilderAPITest.RateBuilderAPIMock(mockResponse));
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/RateImplementationBuilder/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{'Client' => 'Endurance', 'Product' => 'Marathon MBI', 'CoverageLevel' => 'Standard Used', 'RequestType' => 'Rate Surcharges'}));
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = RateBuilderAPI.processRateImplementation();
        RateBuilderAPI.surchargeSetsDMCall();
        Test.stopTest();
    }
    
    @isTest
    static void testDealerCodeState() {
        String mockResponse = '{ "rows": [ ' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "DealerProgramId": "123", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "State": "CA", "Carrier": "MockCarrier", "Admin": "MockAdmin", "Obligor": "MockObligor", "InsuranceType": "MockType" } }' +
    ' ] }';
        Test.setMock(HttpCalloutMock.class, new RateBuilderAPITest.RateBuilderAPIMock(mockResponse));
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/RateImplementationBuilder/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{'Client' => 'Endurance', 'Product' => 'Marathon MBI', 'CoverageLevel' => 'Standard Used', 'RequestType' => 'State Eligibility'}));
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = RateBuilderAPI.processRateImplementation();
        RateBuilderAPI.stateSetsDMCall();
        RateBuilderAPI.fetchMetadatabyTableName('MBI AmTrust States', 'Standard Used');
        Test.stopTest();
    }
       
    @isTest
    static void testErrorResponse() {
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/RateImplementationBuilder/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{}');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = RateBuilderAPI.processRateImplementation();
        Test.stopTest();
    }
    @isTest
    static void testErrorResponse1() {
        Test.startTest();
        String errorMessage = 'Test error occurred';
        String response = RateBuilderAPI.generateErrorResponse(errorMessage);
        Test.stopTest();
    }
    
    @isTest
    static void test_getStateFullName() {
        //valid state
        String stateFullName = RateBuilderAPI.getStateFullName('AL');
        stateFullName = RateBuilderAPI.getStateFullName('CA');
        stateFullName = RateBuilderAPI.getStateFullName('TX');
        //invalid state
        stateFullName = RateBuilderAPI.getStateFullName('XX');
        //empty state
        stateFullName = RateBuilderAPI.getStateFullName('');
    }
    
    public class RateBuilderAPIMock implements HttpCalloutMock {
        public String body;
        
        public RateBuilderAPIMock(String body) {
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/json');
            res.setBody(body);
            res.setStatusCode(200);
            return res;
        }
    }
}