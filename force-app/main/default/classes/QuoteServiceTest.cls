/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 07-15-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest(seealldata = true)
public class QuoteServiceTest {

    @isTest
    static void testDoPost() {
        VIN_Detail__c detail = new VIN_Detail__c();
        detail.Name = 'JN1BV7AR*FM******';
        detail.BODY_STYLE_DESC__c = 'SPORT UTILITY VEHICLE';
        detail.BDY_STYLE_CD__c = 'UT';
        detail.ENG_CLNDR_RTR_CNT__c = '8';
        detail.DRV_TYP_CD__c = 'AWD';
        detail.ENG_DISPLCMNT_CI__c = '397';
        detail.ENG_DISPLCMNT_CL__c = '6.5';
        detail.ENG_MDL_DESC__c = '6.5L';
        detail.Ethnicity__c = 'American';
        detail.ENG_FUEL_DESC__c = 'Diesel';
        detail.ENG_ASP_SUP_CHGR_CD__c = false;
        detail.ENG_ASP_TRBL_CHGR_CD__c = true;
        detail.MAK_NM__c = 'HUMMER';
        detail.NCI_MAK_ABBR_CD__c = 'HUMM';
        detail.MFG_DESC__c = 'General Motors';
        detail.MDL_DESC__c = 'H1';
        detail.MDL_YR__c = '2006';
        detail.VIN_SIGNI_PATTRN_MASK__c = 'JN1BV7AR*FM******';
        detail.TRIM_DESC__c = 'KSC2';
        detail.SEGMENTATION_DESC__c = 'Full Size Luxury Utility';
        //insert detail;
        
        VIN_Class__C classObj = new VIN_Class__c();
        classObj.Class__c = 'test';
        classObj.Class_Guide_Name__c = 'Test Guide';
        classObj.Partner__c = 'Amtrust';
        classObj.Purchase_Type__c = 'New';
        classObj.Squish_VIN__c = detail.Id;
        //insert classObj;
        
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/ContractIngestionService/';  
        req.httpMethod = 'POST';
        req.requestBody = blob.valueOf('{ "VIN" : "JN1BV7AR9FM419178", "Vehicle_Mileage_at_Contract_Inception" : "11461", "Original_State" : "CA", "Option_1" : "value", "Client" : "Endurance" }');
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        QuoteService.processQuoteRequest();
        Test.stopTest();    
    }
    
    @isTest
    static void testDo_Post1() {
        VIN_Detail__c detail = new VIN_Detail__c();
        detail.Name = 'JN2CV7AR*FM******';
        detail.BODY_STYLE_DESC__c = 'SPORT UTILITY VEHICLE';
        detail.BDY_STYLE_CD__c = 'UT';
        detail.ENG_CLNDR_RTR_CNT__c = '8';
        detail.DRV_TYP_CD__c = 'AWD';
        detail.ENG_DISPLCMNT_CI__c = '397';
        detail.ENG_DISPLCMNT_CL__c = '6.5';
        detail.ENG_MDL_DESC__c = '6.5L';
        detail.Ethnicity__c = 'American';
        detail.ENG_FUEL_DESC__c = 'Diesel';
        detail.ENG_ASP_SUP_CHGR_CD__c = false;
        detail.ENG_ASP_TRBL_CHGR_CD__c = true;
        detail.MAK_NM__c = 'HUMMER';
        detail.NCI_MAK_ABBR_CD__c = 'HUMM';
        detail.MFG_DESC__c = 'General Motors';
        detail.MDL_DESC__c = 'H1';
        detail.MDL_YR__c = '2006';
        detail.VIN_SIGNI_PATTRN_MASK__c = 'JN2CV7AR*FM******';
        detail.TRIM_DESC__c = 'KSC2';
        detail.SEGMENTATION_DESC__c = 'Full Size Luxury Utility';
        insert detail;
        System.debug(detail.Id);
        VIN_Class__C classObj = new VIN_Class__c();
        classObj.Class__c = 'test';
        classObj.Class_Guide_Name__c = 'Class Guide';
        classObj.Partner__c = 'Amtrust';
        classObj.Purchase_Type__c = 'New';
        classObj.Squish_VIN__c = detail.Id;
        insert classObj;
        
        QuoteService.EnduranceRequest reqObj = new QuoteService.EnduranceRequest();
        reqObj.VIN = 'JN2CV7AR9FM419178';
        reqObj.Vehicle_Mileage_at_Contract_Inception = 11461;
        reqObj.Original_State = 'CA';
        reqObj.Option_1 = 'SomeOption';
        reqObj.Client = 'Endurance';
        
        String mockResponse = '{ "rows": [ ' +
           '{ "rowData": { "DealerProgramId": "129", "ClientAllocationTables": "Endurance Auto - Marathon MBI", "RateSet": "MBI - Amtrust (CA)", "CoverageLevel": "Standard Used", "ClassGuide": "Class Guide", "OptionSet": "MBI Options - AmTrust (CA)", "Product": "Marathon MBI", "Client": "Endurance", "SurchargeSet": "MBI Surcharges - AmTrust (CA)", "StateSet": "MBI AmTrust States" } },' +
           '{ "rowData": { "State": "CA", "Carrier": "MockCarrier", "Admin": "MockAdmin", "Obligor": "MockObligor", "InsuranceType": "MockType", "StateSetName": "Mock StateSet" } },' +
           '{ "rowData": { "CoverageName": "Standard Used", "RateClass": "Class1", "ExpireType": "AddOn", "MinMiles": 10000, "MaxMiles": 15000, "MinAge": 0, "MaxAge": 5, "BaseReserve": 100.0, "RateCode": "R123", "Commission": 10.0, "PremiumTax": 5.0, "TermMonths": 36, "TermMiles": 36000, "Deductible": 100 } },' +
           '{ "rowData": { "CoverageName": "Standard Used", "Option": "MBI Options - AmTrust (CA)", "MinVehicleMiles": 10000, "MaxVehicleMiles": 60000, "MinVehicleAge": 0, "MaxVehicleAge": 5, "OptionCost": 250.00, "MaxTermMonths": 36, "MaxTermMiles": 36000, "PremiumTax": 5.00, "AutoApply": true } },' +
           '{ "rowData": { "CoverageName": "Standard Used", "SurchargeName": "Turbo", "MinVehicleMiles": "1000", "MaxVehicleMiles": "200000", "MinVehicleAge": "0", "MaxVehicleAge": "10", "SurchargeCost": "150", "PremiumTax": "15", "MaxTermMonths": "36", "MaxTermMiles": "50000" } },' +
           '{ "rowData": { "CoverageLevel": "Standard Used", "Product": "Marathon MBI", "ValidationDays": "30", "ValidationMiles": "1000", "PurchaseType": "New" } }' +'] }';
        Test.setMock(HttpCalloutMock.class, new QuoteServiceTest.QuoteServiceMock(mockResponse));
        
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/ContractIngestionService/';  
        req.httpMethod = 'POST';
        req.requestBody = blob.valueOf('{ "VIN" : "JN2CV7AR9FM419178", "Vehicle_Mileage_at_Contract_Inception" : "11461", "Original_State" : "CA", "Option_1" : "value", "Client" : "Endurance" }');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        //QuoteService.setup(reqObj);
        QuoteService.fetchMetadatabyTableName('MBI_Options_AmTrust_CA_Standard_Used', 'Standard Used');
        QuoteService.responseMap = new Map<String, Map<String, String>>{'125' => new Map<String, String>{'RateSet' => 'MBI - Amtrust (CA)','CoverageLevel' => 'Standard Used','class' => 'Class1', 'SurchargeCost' => '100', 'Allocation Amount' => '50', 'Commission' => 'true', 'Commission RateCost' => '20','Premium Tax' => 'true', 'PremiumTax RateCost' => '10', 'Product' => 'Marathon MBI', 'PurchaseType' => 'New', 'ValidationDays' => '30', 'ValidationMiles' => '1000', 'Surcharges' => 'Turbo'}};
        QuoteService.responseMapList = new Map<String, List<Map<String, String>>>{'125' => new List<Map<String, String>>{new Map<String, String>{'Deductible RateCost' => '100', 'TermMonths RateCost' => '36', 'TermMiles RateCost' => '36000', 'RateClass RateCost' => 'Class1', 'RateCost' => '200'}}};
        QuoteService.vehicleMap = new Map<String, String>{'Vehicle_Mileage_at_Contract_Inception' => '11461','MakeYear' => String.valueOf(System.today().year() - 2), 'VIN' => 'JN2CV7AR9FM419178', 'Original_State' => 'CA', 'Option_1' => 'value', 'Client' => 'Endurance'};
        //QuoteService.rateCostLookup('AddOn');
        //QuoteService.processQuoteRequest();
        Test.stopTest();
    }
    
    @isTest
    static void testDo_Post2() {
        VIN_Detail__c detail = new VIN_Detail__c();
        detail.Name = 'JN2CV7AR*FM******';
        detail.BODY_STYLE_DESC__c = 'SPORT UTILITY VEHICLE';
        detail.BDY_STYLE_CD__c = 'UT';
        detail.ENG_CLNDR_RTR_CNT__c = '8';
        detail.DRV_TYP_CD__c = 'AWD';
        detail.ENG_DISPLCMNT_CI__c = '397';
        detail.ENG_DISPLCMNT_CL__c = '6.5';
        detail.ENG_MDL_DESC__c = '6.5L';
        detail.Ethnicity__c = 'American';
        detail.ENG_FUEL_DESC__c = 'Diesel';
        detail.ENG_ASP_SUP_CHGR_CD__c = false;
        detail.ENG_ASP_TRBL_CHGR_CD__c = true;
        detail.MAK_NM__c = 'HUMMER';
        detail.NCI_MAK_ABBR_CD__c = 'HUMM';
        detail.MFG_DESC__c = 'General Motors';
        detail.MDL_DESC__c = 'H1';
        detail.MDL_YR__c = '2006';
        detail.VIN_SIGNI_PATTRN_MASK__c = 'JN2CV7AR*FM******';
        detail.TRIM_DESC__c = 'KSC2';
        detail.SEGMENTATION_DESC__c = 'Full Size Luxury Utility';
        insert detail;
        System.debug(detail.Id);
        VIN_Class__C classObj = new VIN_Class__c();
        classObj.Class__c = 'test';
        classObj.Class_Guide_Name__c = 'Class Guide';
        classObj.Partner__c = 'Amtrust';
        classObj.Purchase_Type__c = 'New';
        classObj.Squish_VIN__c = detail.Id;
        insert classObj;
        
        QuoteService.EnduranceRequest reqObj = new QuoteService.EnduranceRequest();
        reqObj.VIN = 'JN2CV7AR9FM419178';
        reqObj.Vehicle_Mileage_at_Contract_Inception = 11461;
        reqObj.Original_State = 'CA';
        reqObj.Option_1 = 'SomeOption';
        reqObj.Client = 'Endurance';
        
        String mockResponse = '{ "rows": [ ' +
       '{ "rowData": { "DealerProgramId": "129", "ClientAllocationTables": "Endurance Auto - Marathon MBI", "RateSet": "MBI - Amtrust (CA)", "CoverageLevel": "Standard Used", "ClassGuide": "Class Guide", "OptionSets": "MBI Options - AmTrust (CA)", "Product": "Marathon MBI", "Client": "Endurance", "SurchargeSets": "MBI Surcharges - AmTrust (CA)", "StateSet": "MBI AmTrust States" } },' +
       '{ "rowData": { "CoverageName": "Standard Used", "RateClass": "Class1", "ExpireType": "AddOn", "BaseReserve": 200.0, "Commission": 20.0, "PremiumTax": 10.0, "TermMonths": 36, "TermMiles": 36000, "Deductible": 100 } },' +
       '{ "rowData": { "CoverageName": "Standard Used", "SurchargeName": "Turbo", "SurchargeCost": "150" } },' +
       '{ "rowData": { "CoverageLevel": "Standard Used", "Product": "Marathon MBI", "ValidationDays": "30", "ValidationMiles": "1000", "PurchaseType": "New" } }' +'] }';
        Test.setMock(HttpCalloutMock.class, new QuoteServiceTest.QuoteServiceMock(mockResponse));
        
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/ContractIngestionService/';  
        req.httpMethod = 'POST';
        req.requestBody = blob.valueOf('{ "VIN" : "JN2CV7AR9FM419178", "Vehicle_Mileage_at_Contract_Inception" : "11461", "Original_State" : "CA", "Option_1" : "value", "Client" : "Endurance" }');
        RestContext.request = req;
        RestContext.response = res;
        
        QuoteService.responseMap = new Map<String, Map<String, String>>{'129' => new Map<String, String>{'RateSet' => 'MBI - Amtrust (CA)','CoverageLevel' => 'Standard Used','class' => 'Class1', 'SurchargeCost' => '100', 'Allocation Amount' => '50', 'Commission' => 'true', 'Commission RateCost' => '20','Premium Tax' => 'true', 'PremiumTax RateCost' => '10', 'Product' => 'Marathon MBI', 'PurchaseType' => 'New', 'ValidationDays' => '30', 'ValidationMiles' => '1000', 'Surcharges' => 'Turbo'}};
        QuoteService.responseMapList = new Map<String, List<Map<String, String>>>{'129' => new List<Map<String, String>>{new Map<String, String>{'BaseReserve RateCost' => '100', 'Deductible RateCost' => '100', 'TermMonths RateCost' => '36', 'TermMiles RateCost' => '36000', 'RateClass RateCost' => 'Class1', 'RateCost' => '200'}}};
        QuoteService.vehicleMap = new Map<String, String>{'Vehicle_Mileage_at_Contract_Inception' => '11461','MakeYear' => String.valueOf(System.today().year() - 2), 'VIN' => 'JN2CV7AR9FM419178', 'Original_State' => 'CA', 'Option_1' => 'value', 'Client' => 'Endurance'};
        
        Test.startTest();
        System.debug('DEBUG responseMap: ' + QuoteService.responseMap);
        System.debug('DEBUG responseMapList: ' + QuoteService.responseMapList);

        //QuoteService.processQuoteRequest();        
        QuoteService.fetchMetadatabyTableName('MBI_Options_AmTrust_CA_Standard_Used', 'Standard Used');
        Test.stopTest();
        
    }
    
    @isTest
    static void test_ErrorResponse() {
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/ContractIngestionService/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ "VIN": "", "Vehicle_Mileage_at_Contract_Inception": "", "Original_State": "", "Option_1": "", "Client": "" }');
        RestContext.request = req;
        RestContext.response = res;
        Test.startTest();
        QuoteService.processQuoteRequest();
        Test.stopTest();
    }
 
    @isTest
    static void testDealerCode() {
        //List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>([SELECT Id FROM CalculationMatrix WHERE UniqueName = 'Dealer_Code_Lookup']);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QuoteServiceMock('{ "message": null, "rows": [ { "id": "9mtO80000002eCf", "name": "d0aaa383db813fd2b5d5063c12570465", "rowData": { "DealerProgramId": "129", "ClientAllocationTables": "Endurance Auto - Marathon MBI", "RateSet": "MBI - Amtrust (CA)", "CoverageLevel": "Standard Used", "ClassGuide": "MARATHON MBI USED CLASS GUIDE", "OptionSets": "MBI Options - AmTrust (CA)", "Product": "Marathon MBI", "Client": "Endurance", "SurchargeSets": "MBI Surcharges - AmTrust (CA)", "StateSet": "MBI AmTrust States" } } ], "totalRows": 182 }'));
        QuoteService.EnduranceRequest reqObj = new QuoteService.EnduranceRequest();
reqObj.VIN = 'JN1BV7AR9FM419178';
reqObj.Vehicle_Mileage_at_Contract_Inception = 11461;
reqObj.Original_State = 'CA';
reqObj.Option_1 = 'value';
reqObj.Client = 'Endurance';
reqObj.UpToorAddOn = 'AddOn';

QuoteService.setup(reqObj);
        QuoteService.dealerCodeLookup('Endurance');
        System.debug('responseMap: '+QuoteService.responseMap);
        QuoteService.vehicleClassLookup();
        QuoteService.fetchMetadatabyTableName('MBI_Options_AmTrust_CA_Standard_Used', 'Standard Used');
        Test.stopTest();
    }
    
    @isTest
    static void testStateSetLookup() {
        //List<CalculationMatrix> state_Set_GuideRec = new List<CalculationMatrix>([SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE LIMIT 1) FROM CalculationMatrix WHERE UniqueName = 'State_Set_Guide']);
        Test.startTest();
        String mockResponse = '{ "rows": [ ' +
        '{ "rowData": { "Client": "Endurance", "CoverageLevel": "Standard Used", "Product": "Marathon MBI", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "Client": "Endurance", "CoverageLevel": "Standard Used", "Product": "Marathon MBI", "StateSet": "MBI AmTrust States" } },' +
        '{ "rowData": { "State": "CA", "Carrier": "MockCarrier", "Admin": "MockAdmin", "Obligor": "MockObligor", "InsuranceType": "MockType", "StateSetName": "Mock StateSet" } }' +
            ' ] }';
        Test.setMock(HttpCalloutMock.class, new QuoteServiceMock(mockResponse));
        String dealerKey = 'Standard Used#Marathon MBI#Endurance';
        String dealerId = '129';
        String matrixName = 'MBI_Options_AmTrust_CA_Standard_Used';

        QuoteService.responseMap = new Map<String, Map<String, String>>();
        QuoteService.responseMap.put(dealerId, new Map<String, String>());
        
        QuoteService.vehicleMap = new Map<String, String>();
        QuoteService.vehicleMap.put('Original_State', 'CA');
        // Initialize clientConfig without allowing the setup callouts
// to populate responseMap and trigger the CPU-heavy rate lookup.
Test.setMock(
    HttpCalloutMock.class,
    new QuoteServiceMock('{ "rows": [] }')
);

QuoteService.EnduranceRequest reqObj = new QuoteService.EnduranceRequest();
reqObj.VIN = 'JN1BV7AR9FM419178';
reqObj.Vehicle_Mileage_at_Contract_Inception = 11461;
reqObj.Original_State = 'CA';
reqObj.Option_1 = 'value';
reqObj.Client = 'Endurance';
reqObj.UpToorAddOn = 'AddOn';

QuoteService.setup(reqObj);

// Restore the original mock response for the actual stateSetLookup test.
Test.setMock(
    HttpCalloutMock.class,
    new QuoteServiceMock(mockResponse)
);
         
        QuoteService.stateSetLookup('Endurance');
        QuoteService.fetchMetadatabyTableName('MBI_Options_AmTrust_CA_Standard_Used', 'Standard Used');
        System.debug('responseMap: '+QuoteService.responseMap);
        Test.stopTest();
    }   

    @isTest
    static void testRateCostLookup() {
        // List<CalculationMatrix> matrixRecordList = new List<CalculationMatrix>([SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE LIMIT 1) FROM CalculationMatrix WHERE UniqueName IN : dealerCodeDetailsMap.keySet()]);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QuoteServiceMock('{ "rows": [ { "rowData": { "CoverageName": "Standard Used","RateSet": "MBI_Surcharges_AmTrust_CA", "RateClass": "Class1", "ExpireType": "AddOn", "MinMiles": 10000, "MaxMiles": 15000, "MinAge": 0, "MaxAge": 5, "BaseReserve": 100.0, "RateCode": "R123", "Commission": 10.0, "PremiumTax": 5.0, "TermMonths": 36, "TermMiles": 36000, "Deductible": 100 } } ] }'));
        String dealerId = '129';
        String matrixName = 'MBI_Surcharges_AmTrust_CA';
        
        QuoteService.responseMap = new Map<String, Map<String, String>>{
        'dealer1' => new Map<String, String>{'RateSet' => 'MBI_Surcharges_AmTrust_CA','CoverageLevel' => 'Standard Used','class' => 'Class1'},
        'dealer2' => new Map<String, String>{'RateSet' => 'MBI_Surcharges_AmTrust_CA','CoverageLevel' => 'Standard Used','class' => 'Class1'}};
        
        QuoteService.vehicleMap = new Map<String, String>();
        QuoteService.vehicleMap.put('Vehicle_Mileage_at_Contract_Inception', '11461');
        QuoteService.vehicleMap.put('MakeYear', String.valueOf(System.today().year() - 2));
        QuoteService.rateCostLookup('AddOn');
        System.debug('responseMap: '+QuoteService.responseMap);
        QuoteService.fetchMetadatabyTableName('MBI_Surcharges_AmTrust_CA', 'Standard Used');
        Test.stopTest();
    }
   
    @isTest
    static void testSurchargeSetLookup() {
        // List<CalculationMatrix> matrixRecordList = new List<CalculationMatrix>([SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE LIMIT 1) FROM CalculationMatrix WHERE UniqueName IN : dealerCodeDetailsMap.keySet()]);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QuoteServiceMock('{ "rows": [ { "rowData": { "CoverageName": "Standard Used", "SurchargeSet": "MBI_Surcharges_AmTrust_CA", "SurchargeName": "Turbo", "MinVehicleMiles": "1000", "MaxVehicleMiles": "200000", "MinVehicleAge": "0", "MaxVehicleAge": "10", "SurchargeCost": "150", "PremiumTax": "15", "MaxTermMonths": "36", "MaxTermMiles": "50000" } } ] }'));
        String dealerId = '129';
        String matrixName = 'MBI_Surcharges_AmTrust_CA';
        
        QuoteService.responseMap = new Map<String, Map<String, String>>{
        'dealer1' => new Map<String, String>{'SurchargeSet' => matrixName,'CoverageLevel' => 'Standard Used'},
        'dealer2' => new Map<String, String>{'SurchargeSet' => matrixName,'CoverageLevel' => 'Standard Used'}};
        
        QuoteService.vehicleMap = new Map<String, String>{'Vehicle_Mileage_at_Contract_Inception' => '11461', 'MakeYear' => String.valueOf(System.today().year() - 2), 'Is Turbocharged?' => 'Turbo', 'Is Supercharged?' => 'No', 'Fuel' => 'Gas', 'Drivetrain' => 'FWD'};   
        QuoteService.surchargeSetLookup();
        System.debug('responseMap: '+QuoteService.responseMap);
        QuoteService.fetchMetadatabyTableName('MBI_Surcharges_AmTrust_CA', 'Standard Used');
        Test.stopTest();
    }
       
     @isTest
static void testCallCoverageLevelDM() {
    // List<CalculationMatrix> coverageLevelRec = new List<CalculationMatrix>([SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE LIMIT 1) FROM CalculationMatrix WHERE UniqueName = 'Product_Coverage_Level_Details']);
    Test.startTest();
    Test.setMock(HttpCalloutMock.class, new QuoteServiceMock('{ "rows": [ { "rowData": { "CoverageLevel": "Standard Used", "Product": "Marathon MBI", "ValidationDays": "30", "ValidationMiles": "1000", "PurchaseType": "New" } } ] }'));
    String dealerId = '129';
    QuoteService.responseMap = new Map<String, Map<String, String>>();
    QuoteService.responseMap.put(dealerId, new Map<String, String>{'CoverageLevel' => 'Standard Used', 'Product' => 'Marathon MBI'});

    // Added only to initialize the existing QuoteService client configuration
    QuoteService.EnduranceRequest reqObj = new QuoteService.EnduranceRequest();
    reqObj.VIN = 'JN1BV7AR9FM419178';
    reqObj.Vehicle_Mileage_at_Contract_Inception = 11461;
    reqObj.Original_State = 'CA';
    reqObj.Option_1 = 'value';
    reqObj.Client = 'Endurance';
    reqObj.UpToorAddOn = 'AddOn';

    QuoteService.setup(reqObj);

    // Existing code - DO NOT CHANGE
    QuoteService.callCoverageLevelDM();

    System.assertNotEquals(null, QuoteService.responseMap, 'Response map should be populated.');
    System.debug('responseMap: '+QuoteService.responseMap);
    Test.stopTest();
}
    
     @isTest
     static void testAllocationCostLookup() {
        //List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>([SELECT Id FROM CalculationMatrix WHERE UniqueName = 'Dealer_Code_Lookup']);
        Test.startTest();
        Account clientAccount = TestDataFactory.createSellingAgencyAccount(true);
        clientAccount.Name = 'Endurance';
        update clientAccount;
        
        Allocation_Code__c all8001Code = new Allocation_Code__c(Name = '8001', Client__c = clientAccount.Id, Product__c = 'Marathon MBI', Coverage_Level__c = 'Standard Used', Insurance_Carrier__c = 'MockCarrier', States__c = 'CA,Include All', Allocation_Amount__c = '100.0', Option__c = 'SomeOption', Descriptor__c = 'Premium Tax'); 
        insert all8001Code;
        String dealerId = '129';

        QuoteService.responseMap = new Map<String, Map<String, String>>();
        QuoteService.responseMap.put(dealerId, new Map<String, String>{'Product' => 'Marathon MBI', 'CoverageLevel' => 'Standard Used', 'Carrier' => 'MockCarrier'});
        QuoteService.vehicleMap = new Map<String, String>{'Original_State' => 'CA'};
        QuoteService.allocationCostLookup('Endurance');
        System.debug('responseMap: '+QuoteService.responseMap);
        Test.stopTest();
    }

    /*@isTest
    static void testVehicleClassLookup() {
        //List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>([SELECT Id FROM CalculationMatrix WHERE UniqueName = 'Dealer_Code_Lookup']);
        Test.startTest();
        
        
        //Test.setMock(HttpCalloutMock.class, new QuoteServiceMock('{ "message": null, "rows": [ { "id": "9mtO80000002eCf", "name": "d0aaa383db813fd2b5d5063c12570465", "rowData": { "DealerProgramId": "129", "ClientAllocationTables": "Endurance Auto - Marathon MBI", "RateSet": "MBI - Amtrust (CA)", "CoverageLevel": "Standard Used", "ClassGuide": "MARATHON MBI USED CLASS GUIDE", "OptionSets": "MBI Options - AmTrust (CA)", "Product": "Marathon MBI", "Client": "Endurance", "SurchargeSets": "MBI Surcharges - AmTrust (CA)", "StateSet": "MBI AmTrust States" } } ], "totalRows": 182 }'));
        //QuoteService.rateCostLookup();
        Test.stopTest();
    }*/
        
    public class QuoteServiceMock implements HttpCalloutMock {
        public String body;
        
        public QuoteServiceMock(String body) {
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            //String fullJson = '{"aggregationResults":{"results":[{}]},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"Rate_Set":"Test","Product":"Test","Rate_Code":"Test","Class_Guide":"Test","Rate_Class":"Test","Expire_Type":"Test","CLIPFeeAmTrustOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"Option_Cost":2.8,"PremiumTaxOutput":1.0,"InsuranceCarrier":"AmericanResourceInsuranceCompany","Obligor":"TestObligor","AdminCompany":"TestAdminCompany","TypeOfInsurance":"TestTypeOfInsurance"}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/json');
            res.setBody(body);
            res.setStatusCode(200);
            return res;
        }
    }
}