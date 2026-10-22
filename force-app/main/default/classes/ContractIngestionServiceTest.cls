@isTest
Public class ContractIngestionServiceTest{

    @isTest
    static void testDoPost() {
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/ContractIngestionService/';  
        req.httpMethod = 'POST';
        req.requestBody = blob.valueOf('{ "DealerProgramId" : "129", "ContractNumber" : "asdf123", "FirstName" : "asdf", "LastName" : "asdf", "AddressLine1" : "123asdf", "City" : "asdf", "StateProvAbbrev" : "as", "PostalCode" : "asdf123", "VIN" : "asdf123", "Make" : "asdf123", "Model" : "asdf123", "Trim" : "asdf123", "Option1" : "asdf123", "Option2" : "asdf123", "Option3" : "asdf123", "Option4" : "asdf123", "CurrentOdometer" : "123", "UpToorAddOn" : "asdf", "TermMonths" : "123", "TermMiles" : "123", "RateClass" : "asdf123", "RetailCost" : "123", "NetAdminCost" : "123", "Deductible" : "123", "DownPaymentAmount" : "123", "ContractSaleDate" : "03-22-2025", "FulfillmentDate" : "11-22-2024", "VehiclePurchaseDate": "10-20-2023", "VehicleLastServiceDate": "10-22-2023","FinanceFirstPmtDate": "12-01-2023" }');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        ContractIngestionService.receiveContractRequest();
        Test.stopTest();
        
    }
    
    @isTest
    static void testInvalidateRequestBody() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/ContractIngestionService/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ "DealerProgramId" : "129", "ContractNumber" : "asdf123", "FirstName" : "asdf", "LastName" : "asdf", "AddressLine1" : "123asdf", "City" : "asdf", "StateProvAbbrev" : "as", "PostalCode" : "asdf123", "VIN" : "asdf123", "Make" : "asdf123", "Model" : "asdf123", "Trim" : "asdf123", "Option1" : "asdf123", "Option2" : "asdf123", "Option3" : "asdf123", "Option4" : "asdf123", "CurrentOdometer" : "invalid", "UpToorAddOn" : "asdf", "TermMonths" : "123", "TermMiles" : "123", "RateClass" : "asdf123", "RetailCost" : "123", "NetAdminCost" : "123", "Deductible" : "123", "DownPaymentAmount" : "123", "ContractSaleDate" : "03-22-2025", "FulfillmentDate" : "11-22-2024" }');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        ContractIngestionService.receiveContractRequest();
        Test.stopTest();
    }

    
    @isTest
    static void testDealerCode() {
        //List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>([SELECT Id FROM CalculationMatrix WHERE UniqueName = 'Dealer_Code_Lookup']);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BREServiceTest.DealerCodeMock());
        String response = ContractIngestionService.determineClientName('129', DateTime.now());
        String requestBody = '{ "DealerProgramId": "129", "SubDealerId": "asdf123", "ContractNumber": "asdf123", "FirstName": "asdf", "LastName": "asdf", "MiddleName": "asdf", "Prefix": "asdf", "Suffix": "asdf", "Phone1": "asdf", "Phone2": "asdf", "Email": "asdf", "Language": "asdf", "AddressLine1": "asdf123", "AddressLine2": "asdf123", "City": "asdf", "StateProvAbbrev": "as", "PostalCode": "asdf123", "VIN": "asdf123", "CurrentOdometer": "1234", "VehiclePurchasePrice": "1235", "VehiclePurchaseDate": "11-22-2024", "VehicleLastServiceDate": "11-22-2024", "UpToorAddOn": "asdf", "TermMonths": "123", "TermMiles": "123", "RateClass": "asdf123", "WaitingPeriodDays": "123", "WaitingPeriodMiles": "123", "TaxAmount": "123", "RetailCost": "123", "NetAdminCost": "123", "Deductible": "123", "DownPaymentAmount": "123", "LienHolderId": "asdf123", "FinancedTerm": "123", "FinanceFirstPmtDate": "11-22-2024", "FinanceLedgerBalance": "123", "ContractSaleDate": "04-14-2025", "FulfillmentDate": "11-22-2024", "Option1": "asdf123", "Option2": "asdf123", "Option3": "asdf123", "Option4": "asdf123", "Option5": "asdf123" }';
        ContractIngestionService.EnduranceRequest requestBodyObj = (ContractIngestionService.EnduranceRequest) JSON.deserialize(
                requestBody, ContractIngestionService.EnduranceRequest.class
            );        
        List<Pentaho_Contract_Ingestion_Setting__mdt> pentahoMeta = new List<Pentaho_Contract_Ingestion_Setting__mdt>([SELECT FTP_File_Path_Sandbox__c, FTP_Host__c, FTP_Port__c, Pentaho_Callout_Password__c, Pentaho_Callout_Username__c, Pentaho_Endpoint__c FROM Pentaho_Contract_Ingestion_Setting__mdt WHERE DeveloperName = 'Endurance' LIMIT 1]);
        ContractIngestionService.ingestionSetting = pentahoMeta[0];
        ContractIngestionService.ingestEnduranceContract(requestBodyObj);
        ContractIngestionService.triggerPentahoJob();
        Boolean result = ContractIngestionService.isDecimal('not-a-number');
        System.assertEquals(false, result);
        Test.stopTest();
    
    }
        
    public class ContractIngestionServiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":[{}]},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"Rate_Set":"Test","Product":"Test","Rate_Code":"Test","Class_Guide":"Test","Rate_Class":"Test","Expire_Type":"Test","CLIPFeeAmTrustOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"Option_Cost":2.8,"PremiumTaxOutput":1.0,"InsuranceCarrier":"AmericanResourceInsuranceCompany","Obligor":"TestObligor","AdminCompany":"TestAdminCompany","TypeOfInsurance":"TestTypeOfInsurance"}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            return res;
        }
    }
  }