/**
* @description		 : Test File For BREService Bulkified class
* @author            : Sohel Azmi
* @group             :
* @last modified on  : 06-12-2026
* @last modified by  : Sohel Azmi
**/
@isTest
public class BREServiceTest {

    @testSetup
    static void setupData() {
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;

        /*
         * Validation-safe BRE client.
         *
         * Sold_Contract_Validation is bypassed when Client__c is populated
         * and the client AccountNumber is WLK, WFI, or WUS. WUS is used here
         * because it avoids coupling this test to WLK/WFI SecureOne-specific
         * validation rules.
         */
        Account testAccount = TestDataFactory.createAccount(false);
        testAccount.AccountNumber = 'WUS';
        Database.insert(testAccount, dmlOptions);

        List<InsurancePolicy> policies = new List<InsurancePolicy>();

        for (Integer i = 0; i < 5; i++) {
            InsurancePolicy policyRec =
                TestDataFactory.createInsurancePolicy(false, testAccount.Id);

            policyRec.Client__c = testAccount.Id;

            // Keeps Full_Pay_Validation out of this BRE-focused unit test.
            policyRec.Legacy_Source__c = 'DSI';

            // Preserve the original BRE fixture values.
            policyRec.Name = 'Test Policy ' + i;
            policyRec.VIN__c = 'TestVin1A3412345' + i;
            policyRec.Option_1__c = 'Salvaged;Rideshare';
            policyRec.Surcharge_Set__c = 'MAC DM VSC AmTrust Surcharges';
            policyRec.Premium_Tax_Old__c = 1.0;
            policyRec.OT_Allocation__c = 1.0;

            policies.add(policyRec);
        }

        Database.insert(policies, dmlOptions);
    }

    private static List<InsurancePolicy> loadPolicies(Integer rowLimit) {
        return [
            SELECT Id,
                   Name,
                   Dealer_Program_Id__c,
                   Client__c,
                   Dealer__c,
                   NameInsuredId,
                   SaleDate,
                   Vehicle_Make__c,
                   Contract_Term_Mileage__c,
                   Contract_Term_Months__c,
                   Vehicle_Mileage_at_Contract_Inception__c,
                   Option_1__c,
                   Is_Commercial__c,
                   Coverage_Level__c,
                   Rate_Set__c,
                   Product__c,
                   Surcharge_Set__c,
                   Class__c,
                   Deductible__c,
                   VIN__c,
                   Up_To_or_Add__c,
                   RecordTypeId,
                   Premium_Tax_Old__c,
                   OT_Allocation__c,
                   Options_Cost__c,
                   Surcharge_Cost__c,
                   Net_Dealer_Cost__c,
                   Vehicle_Year__c,
                   State__c,
                   Vehicle_Type__c,
                   Options_Sets__c,
                   Residential_Type__c,
                   Square_Foot__c,
                   Number_of_Units__c,
                   Year_Built__c,
                   Ins_Carrier__c,
                   Drivetrain__c
            FROM InsurancePolicy
            ORDER BY Name
            LIMIT :rowLimit
        ];
    }

    @isTest
    static void testBulkifiedPipeline() {
        List<InsurancePolicy> policies = loadPolicies(5);
        
        // Inject static test dependencies to bypass OmniStudio version queries
        injectStaticCaches();

        Test.startTest();
        // Use the smart mock that adapts to batch sizes
        Test.setMock(HttpCalloutMock.class, new SmartBREMock());
        List<InsurancePolicy> processed = BREServiceHandlerBulkified.executeBusinessRule(policies);
        Test.stopTest();

        // Validate outcomes from pipeline calculations
        System.assertEquals(
            policies.size(),
            processed.size(),
            'Every input policy should be returned by the bulkified BRE pipeline.'
        );
        System.assert(
            String.isNotBlank(processed[0].Ins_Carrier__c),
            'Insurance Carrier should be populated by the BRE pipeline.'
        );
        System.assert(
            processed[0].Options_Cost__c != null &&
            processed[0].Options_Cost__c > 0,
            'Option cost should be populated by the BRE expression-set pipeline.'
        );
        // System.assertEquals('4WD', processed[0].Drivetrain__c, 'Surcharge logic should have mapped drivetrain accurately based on global drive train mapper.');
    }

    @isTest
    static void testRESTServiceEndpoint() {
        List<InsurancePolicy> policies = loadPolicies(2);
        String requestBodyJson = JSON.serialize(policies);

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/BusinessRuleService/executeBusinessRules';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBodyJson);
        
        RestResponse response = new RestResponse();
        
        RestContext.request = request;
        RestContext.response = response;

        // Inject static test dependencies
        injectStaticCaches();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SmartBREMock());
        BREService.executeBusinessRules();
        Test.stopTest();

        System.assertEquals(200, response.statusCode, 'Service should return a 200 OK status code.');
        System.assert(response.responseBody.toString().contains('AmericanResourceInsuranceCompany'), 'Payload should include the enriched JSON data.');
    }

    @isTest
    static void testRESTServiceEmptyPayload() {
        RestRequest request = new RestRequest();
        request.requestURI =
            '/services/apexrest/BusinessRuleService/executeBusinessRules';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('[]');

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        injectStaticCaches();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SmartBREMock());
        BREService.executeBusinessRules();
        Test.stopTest();

        System.assertEquals(
            200,
            response.statusCode,
            'An empty contract list is still a valid request.'
        );
        System.assertEquals(
            '[]',
            response.responseBody.toString(),
            'No processed contracts should return an empty JSON array.'
        );
    }

    @isTest
    static void testExceptionBlocks() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/BusinessRuleService/';
        request.httpMethod = 'POST';
        request.requestBody =
            Blob.valueOf('THIS_IS_INVALID_JSON_TO_TRIGGER_CATCH_BLOCK');

        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        BREService.executeBusinessRules();
        Test.stopTest();

        System.assertEquals(
            500,
            response.statusCode,
            'Invalid JSON should result in a 500 error code from the catch block.'
        );

        List<Object> errorPayload =
            (List<Object>) JSON.deserializeUntyped(
                response.responseBody.toString()
            );

        System.assertEquals(
            1,
            errorPayload.size(),
            'The REST error response should contain one error item.'
        );

        Map<String, Object> errorItem =
            (Map<String, Object>) errorPayload[0];

        System.assertEquals(
            'error',
            (String) errorItem.get('status'),
            'The catch path should return status=error.'
        );

        System.assert(
            ((String) errorItem.get('message')).contains(
                'An error occurred while processing the request'
            ),
            'The catch path should return the controlled BRE error message.'
        );
    }

    // ==========================================
    // HELPER METHODS
    // ==========================================
    
    public static void injectStaticCaches() {
        // The squish pattern created by TestDataFactory.createVinDetail
        String dummySquish = 'TestVin1*34******';
        
        // Link the specific VINs created in setup to the squish pattern
        for(Integer i = 0; i < 5; i++) {
            BREServiceHandlerBulkified.squishVinCache.put('TestVin1A3412345' + i, dummySquish);
        }
        
        // Map the properties of the vehicle based on the TestDataFactory inputs
        Map<String, Object> details = new Map<String, Object>{
            'mdl_yr__c' => 2008,
            'mak_nm__c' => 'CHEVROLET',
            'mdl_desc__c' => 'EXPRESS G1500',
            'trk_tng_rat_cd__c' => 'D',
            'eng_fuel_desc__c' => 'Gas',
            'eng_asp_trbl_chgr_cd__c' => true,
            'eng_asp_sup_chgr_cd__c' => true,
            'drv_typ_cd__c' => '4WD',
            'trim_desc__c' => 'Coupe',
            'body_style_desc__c' => 'VAN PASSENGER'
        };
        BREServiceHandlerBulkified.globalVinDetails.put(dummySquish, details);
        BREServiceHandlerBulkified.globalDriveTrainMapper = new Map<String, String>{'4WD' => '4WD', 'AWD' => 'AWD', 'RWD' => 'RWD'};

        // Inject Cache for BRE Versions to bypass OmniStudio SOQL rules
        BREServiceHandlerBulkified.brVersionCache.put('Insurance_Codes', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('Reinsurance_Company', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('Dealer_Code_Lookup', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('SecureOne_State_Matrix', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('WLK_Rate', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('State_Insurance_Guide', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('Rate_Sets', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('Options_Sets', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
        BREServiceHandlerBulkified.brVersionCache.put('Surcharge_Sets', new List<BREServiceHandlerBulkified.VersionCache>{ new BREServiceHandlerBulkified.VersionCache(Datetime.now().addDays(-1), Datetime.now().addDays(1)) });
    }

    /**
     * An intelligent mock that reads the incoming request, counts the batch size, 
     * and returns the exact number of responses formatted properly based on 
     * whether the endpoint is hitting a Decision Matrix (DM) or Expression Set (EX).
     */
    public class SmartBREMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            
            // 1. Determine payload batch size dynamically
            Map<String, Object> reqBody = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            List<Object> inputs = (List<Object>) reqBody.get('inputs');
            Integer batchSize = (inputs != null) ? inputs.size() : 1;

            // 2. Identify Endpoint Type
            String endpoint = req.getEndpoint();
            Boolean isDM = endpoint.contains('Insurance_Codes') || 
                           endpoint.contains('Reinsurance_Company') || 
                           endpoint.contains('Dealer_Code_Lookup') || 
                           endpoint.contains('SecureOne_State_Matrix');

            // 3. Build Dynamic Response Structure
            List<Object> outputs = new List<Object>();
            for(Integer i = 0; i < batchSize; i++) {
                Map<String, Object> outputItem = new Map<String, Object>();
                
                if (isDM) {
                    // Decision Matrices return arrays of name/value pairs inside 'results'
                    List<Map<String, Object>> dmResults = new List<Map<String, Object>>{
                        new Map<String, Object>{'name' => 'InsuranceCode', 'value' => 'KNB'},
                        new Map<String, Object>{'name' => 'ReinsuranceCompany', 'value' => 'TestReinsurance'},
                        new Map<String, Object>{'name' => 'CoverageLevel', 'value' => 'Coverage Level Name Test Data'}, // Align with TestDataFactory
                        new Map<String, Object>{'name' => 'Product', 'value' => 'SecureOne'},
                        new Map<String, Object>{'name' => 'Client', 'value' => 'Marathon'},
                        new Map<String, Object>{'name' => 'RateSet', 'value' => 'EZ FL M2M DM VSC AMT'},
                        new Map<String, Object>{'name' => 'InsuranceCarrier', 'value' => 'AmericanResourceInsuranceCompany'},
                        new Map<String, Object>{'name' => 'Obligor', 'value' => 'TestObligor'},
                        new Map<String, Object>{'name' => 'AdminCompany', 'value' => 'TestAdmin'}
                    };
                    outputItem.put('results', dmResults);
                } else {
                    // Expression Sets return direct mappings inside 'results'
                    Map<String, Object> exResults = new Map<String, Object>{
                        'Option_Cost' => 10.5,
                        'Rate_Set' => 'EZ FL M2M DM VSC AMT',
                        'Product' => 'SecureOne',
                        'Rate_Code' => 'RC-EX',
                        'Class_Guide' => 'MAC DM VSC 8 CLASS AMTRUST',
                        'Rate_Class' => '8',
                        'Rate_Cost' => 100.0,
                        'Expire_Type' => 'UpTo',
                        'Final_Total_Rate' => 250.0,
                        'CarrierOutput' => 'AmericanResourceInsuranceCompany',
                        'ObligorOutput' => 'Obligor',
                        'AdminOutput' => 'Admin',
                        'InsuranceTypeOutput' => 'Type',
                        'BaseReserveOutput' => 69.0,
                        'PremiumTaxOutput' => 1.0,
                        'ObligorTaxOutput' => 1.0,
                        'CommissionOutput' => 2.8,
                        'MaxMilesOutput' => 150000.0,
                        'MaxSquareFootOutput' => 5000.0,
                        'MaxUnitOutput' => 2.0,
                        'MaxAgeOutput' => 20.0,
                        'MaxTermMonthsOutput' => 72.0,
                        'MaxTermMilesOutput' => 100000.0,
                        'OptionCostOutput' => 10.5,
                        'SurchargeCostOutput' => 50.0
                    };
                    outputItem.put('results', exResults);
                }
                outputs.add(outputItem);
            }

            // 4. Construct Final JSON
            Map<String, Object> finalJson = new Map<String, Object>{
                'outputs' => outputs
            };

            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(finalJson));
            res.setStatusCode(200);
            res.setStatus('OK');
            
            return res;
        }
    }
    
    public class DealerCodeMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"outputs":[{"results":[{"name":"ClientAllocationTables","value":"Consumers Choice Auto - EZ FL M2M DM VSC AMT"},{"name":"RateSet","value":"EZ FL M2M DM VSC AMT"},{"name":"CoverageLevel","value":"EZ Elite - FL"},{"name":"ClassGuide","value":"MAC DM VSC 8 CLASS AMTRUST"},{"name":"OptionSets","value":"EZ FL M2M DM VSC AMT Options"},{"name":"Product","value":"EZ FL M2M DM VSC AMT"},{"name":"Client","value":"Consumers Choice"},{"name":"SurchargeSets","value":"N/A"},{"name":"StateSet","value":"MAC DM VSC AmTrust"},{"name":"dealerProgramId","value":"259"}]}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class RateDetailsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":[{}]},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":[{"Rate_Set":"Test","Product":"Test","Rate_Code":"Test","Class_Guide":"Test","Rate_Class":"Test","Expire_Type":"Test","CLIPFeeAmTrustOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"Option_Cost":2.8,"PremiumTaxOutput":1.0,"InsuranceCarrier":"AmericanResourceInsuranceCompany","Obligor":"TestObligor","AdminCompany":"TestAdminCompany","TypeOfInsurance":"TestTypeOfInsurance"}]}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class StateInsuranceGuideMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"outputs":[{"results":{"CarrierOutput":"AmericanResourceInsuranceCompany","ObligorOutput":"TestObligor","AdminOutput":"TestAdmin","InsuranceTypeOutput":"TestInsuranceType","InsuranceCode":"ABC","MaxMilesOutput": 999999.0,"MaxSquareFootOutput":2.8,"MaxUnitOutput":2.8,"MaxAgeOutput": 999.0,"CommissionOutput":1.0}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class ExpressionSetMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":{}},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"AdminFeeNMOutput":2.8,"MaxSquareFootOutput":2.8,"MaxUnitOutput":2.8,"AdminFeeARICOutput":2.8,"CLIPFeeARICOutput":2.8,"AdminFeeAmTrustOutput":2.8,"CLIPFeeAmTrustOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"RateCodeOutput":"MTMFLEZELT8","PremiumTaxOutput":1.0,"CommissionOutput":2.8,"MinAgeInput":50002}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class OptionsSetMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":{}},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"MaxTermMonthsOutput":2.8,"MaxTermMilesOutput":2.8,"MaxVehicleMilesOutput":100000,"MaxVehicleAgeOutput":2.8,"MaxResidenceSqFtOutput":2.8,"MaxResidenceAgeOutput":2.8,"OptionCostOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"RateCodeOutput":"MTMFLEZELT8","PremiumTaxOutput":1.0}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class SurchargeDetailsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"outputs":[{"results":{"mdl_yr__c":"100.0","mak_nm__c":"ACUR","mdl_desc__c":"4WD","trk_tng_rat_cd__c":"true","eng_fuel_desc__c":"Diesel","eng_asp_trbl_chgr_cd__c":"true","drv_typ_cd__c":"4WD","TRIM_DESC__c":"10","eng_asp_sup_chgr_cd__c":"true","BODY_STYLE_DESC__c":"SUV","SurchargeCostOutput":2.8,"MaxTermMonthsOutput":2.8,"MaxTermMilesOutput":2.8,"MaxVehicleMilesOutput":100000,"MaxVehicleAgeOutput":2.8,"PremiumTaxOutput":2.8}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class StateInsuranceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":{}},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"MaxTermMonthsOutput":2.8,"MaxTermMilesOutput":2.8,"MaxVehicleMilesOutput":100000,"MaxVehicleAgeOutput":2.8,"MaxResidenceSqFtOutput":2.8,"MaxResidenceAgeOutput":2.8,"OptionCostOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"RateCodeOutput":"MTMFLEZELT8","PremiumTaxOutput":1.0,"CarrierOutput":"AmericanResourceInsuranceCompany","ObligorOutput":"TestObligor","AdminOutput":"TestAdmin","InsuranceTypeOutput":"TestInsuranceType"}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class OriginalStateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"outputs":[{"results":{"dealerSet": "Dealer123" ,"namedInsuredSet":"NameInsuredId","accRecs": {"Dealer123": "FL",  "NameInsuredId": "testAccount.Id"}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }

    public class BREResponseMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":{}},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"MaxTermMonthsOutput":2.8,"MaxTermMilesOutput":2.8,"MaxVehicleMilesOutput":2.8,"MaxVehicleAgeOutput":2.8,"MaxResidenceSqFtOutput":2.8,"MaxResidenceAgeOutput":2.8,"OptionCostOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"RateCodeOutput":"MTMFLEZELT8","PremiumTaxOutput":1.0}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            res.setStatus('Created');
            return res;
        }
    }
}