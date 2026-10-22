@isTest(seealldata = true)
public class TabularReportQueryServiceTest {
    
    @isTest
    static void testReportRequest() {
        Report_request__c reportRequest = TestDataFactory.createReportRequest(false);
        reportRequest.Fields__c = 'Id';
        reportRequest.Object__c= 'Report_request__c';
        reportRequest.Filters__c= 'Product__c != null';
        reportRequest.Group_By__c= 'Id';
        reportRequest.Order_By__c= 'Id';
        insert reportRequest;
        
        String mockResponse = '{ "rows": [ ' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "DealerProgramId": "123", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "State": "CA", "Carrier": "MockCarrier", "Admin": "MockAdmin", "Obligor": "MockObligor", "InsuranceType": "MockType" } }' +
    ' ] }';
        Test.setMock(HttpCalloutMock.class, new TabularReportQueryServiceTest.TabularReportQueryServiceMock(mockResponse));
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        TabularReportQueryService.RateRequest mockRequest= new TabularReportQueryService.RateRequest();
        mockRequest.reportRequestId= reportRequest.Id;
        
        req.requestURI = '/services/apexrest/TabularReportQuery/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(mockRequest));
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = TabularReportQueryService.executeReportQuery();
        result = TabularReportQueryService.getFieldLabel('InsurancePolicy', 'Id');
        Test.stopTest();
    }
    
    @isTest
    static void testException() {
        Report_request__c reportRequest = TestDataFactory.createReportRequest(false);
        reportRequest.Fields__c = 'Id';
        reportRequest.Object__c= 'Report_request';
        reportRequest.Filters__c= 'Id != null';
        reportRequest.Group_By__c= 'Id';
        reportRequest.Order_By__c= 'Id';
        insert reportRequest;
        
        String mockResponse = '{ "rows": [ ' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "CoverageLevel": "Standard Used", "DealerProgramId": "123", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "Client": "Endurance", "Product": "Marathon MBI", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "State": "CA", "Carrier": "MockCarrier", "Admin": "MockAdmin", "Obligor": "MockObligor", "InsuranceType": "MockType" } }' +
    ' ] }';
        Test.setMock(HttpCalloutMock.class, new TabularReportQueryServiceTest.TabularReportQueryServiceMock(mockResponse));
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        TabularReportQueryService.RateRequest mockRequest= new TabularReportQueryService.RateRequest();
        mockRequest.reportRequestId= reportRequest.Id;
        
        req.requestURI = '/services/apexrest/TabularReportQuery/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(mockRequest));
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = TabularReportQueryService.executeReportQuery();
        result = TabularReportQueryService.getFieldLabel('InsurancePolicy', 'Id');
        Test.stopTest();
    }
       
    @isTest
    static void testErrorResponse() {
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/TabularReportQuery/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{}');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        String result = TabularReportQueryService.executeReportQuery();
        Test.stopTest();
    }
    @isTest
    static void testErrorResponse1() {
        Test.startTest();
        String errorMessage = 'Test error occurred';
        String response = TabularReportQueryService.generateErrorResponse(errorMessage);
        Test.stopTest();
    }
    
    
    public class TabularReportQueryServiceMock implements HttpCalloutMock {
        public String body;
        
        public TabularReportQueryServiceMock(String body) {
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