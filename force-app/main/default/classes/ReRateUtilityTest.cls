/**
 * ReRateUtilityTest Class
 * This class handles the test coverage for ReRateUtility class
 * and creates mock HTTP POST requests and response.
 */
@isTest
public class ReRateUtilityTest {
    //Method covers reRateContract method.
	@isTest
    public static void calculateRateDetails() {
		// Begin test context
        // Set up DML options to allow duplicate rules for test data insertion
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        
        Account clientAccount = TestDataFactory.createSellingAgencyAccount(true);
        clientAccount.Name = 'Endurance';
        // Validation-safe client for Sold_Contract_Validation.
        // WUS bypasses the non-SecureOne blanket validation and does not
        // activate the WLK/WFI SecureOne-specific validation.
        clientAccount.AccountNumber = 'WUS';
        update clientAccount;
        
        // Create and insert a test Account
        Account testAccount = TestDataFactory.createAccount(false);
        testAccount.FirstName = 'Spanish';
        testAccount.LastName = 'Service Center';
        testAccount.BillingState = 'FL';
        Database.insert(testAccount, dmlOptions);

        // Create and insert a test Coverage Level
        Coverage_Level__c coverageLevel = new Coverage_Level__c();
        coverageLevel.Name = 'EZ Elite - FL';
        insert coverageLevel;
        
        //Create contract record
        InsurancePolicy policyRec = TestDataFactory.createInsurancePolicy(false, testAccount.Id);
        policyRec.Dealer_Program_Id__c = '259';
        policyRec.Client__c= clientAccount.Id;
        policyRec.Sale_Date__c=System.now().Date();
        policyRec.Vehicle_Make__c='ACUR';
        policyRec.Contract_Term_Mileage__c=24000;
        policyRec.Contract_Term_Months__c=24;
        policyRec.Vehicle_Mileage_at_Contract_Inception__c=50002;
        policyRec.Option_1__c='Salvaged';
        policyRec.Is_Commercial__c=true;
        policyRec.NameInsuredId=testAccount.Id;
        policyRec.Coverage_Level__c=coverageLevel.Id;
        policyRec.Rate_Set__c = 'EZ FL M2M DM VSC AMT';
        policyRec.Ins_Carrier__c = 'AmericanResourceInsuranceCompany';
        policyRec.Product__c = 'SecureOne';
        
        List<InsurancePolicy> insList = new List<InsurancePolicy> ();
        insList.add(policyRec);
        insert insList;
        
        //Create Vin detail Record
        VIN_Detail__c detail = new VIN_Detail__c();
        detail.Name = '137FA553*6E******';
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
        detail.VIN_SIGNI_PATTRN_MASK__c = '137FA553*6E******';
        detail.TRIM_DESC__c = 'KSC2';
        detail.SEGMENTATION_DESC__c = 'Full Size Luxury Utility';
        insert detail;
        
        //Create VinClass to be associated with VinDetail record
        VIN_Class__C classObj = new VIN_Class__c();
        classObj.Class__c = 'test';
        classObj.Class_Guide_Name__c = 'test';
        classObj.Partner__c = 'Amtrust';
        classObj.Purchase_Type__c = 'New';
        classObj.Squish_VIN__c = detail.Id;
        insert classObj;
        
         List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        //Allocation Amount is numeric
        Allocation_Code__c all1017Code = new Allocation_Code__c();
        all1017Code.Name = '1017';
        all1017Code.Allocation_Amount__c = '200.50';
        all1017Code.Payee_Type__c = 'Company';
        all1017Code.Client__c = clientAccount.Id;
        all1017Code.Product__c =  'SecureOne';
        all1017Code.Coverage_Level__c = 'EZ Elite - FL';
        all1017Code.Insurance_Carrier__c = 'Include All';
        all1017Code.States__c = 'Include All';
        all1017Code.Start_Date__c = System.now().Date() - 1;
        allocationCodes.add(all1017Code);

        //Allocation Amount matches Descriptor
        Allocation_Code__c all8001Code = new Allocation_Code__c();
        all8001Code.Name = '8001';
        all8001Code.Allocation_Amount__c = 'Premium Tax';
        all8001Code.Descriptor__c = 'Premium Tax';
        all8001Code.Payee_Type__c = 'Company';
        all8001Code.Client__c = clientAccount.Id;
        all8001Code.Product__c =  'SecureOne';
        all8001Code.Coverage_Level__c = 'EZ Elite - FL';
        all8001Code.Insurance_Carrier__c = 'Include All';
        all8001Code.States__c = 'Include All';
        all8001Code.Start_Date__c = System.now().Date() - 1;
        allocationCodes.add(all8001Code);

        //Allocation Amount starts with 'S' and length < 5
        Allocation_Code__c all8004Code = new Allocation_Code__c();
        all8004Code.Name = '8004';
        all8004Code.Allocation_Amount__c = 'S12';
        all8004Code.Payee_Type__c = 'Company';
        all8004Code.Client__c = clientAccount.Id;
        all8004Code.Product__c =  'SecureOne';
        all8004Code.Coverage_Level__c = 'EZ Elite - FL';
        all8004Code.Insurance_Carrier__c = 'Include All';
        all8004Code.States__c = 'Include All';
        all8004Code.Start_Date__c = System.now().Date() - 1;
        allocationCodes.add(all8004Code);
        
        //Allocation Amount starts with 'S' and length < 5
        Allocation_Code__c all8002Code = new Allocation_Code__c();
        all8002Code.Name = '8002';
        all8002Code.Allocation_Amount__c = 'S12';
        all8002Code.Descriptor__c = 'Premium Tax';
        all8002Code.Payee_Type__c = 'Company';
        all8002Code.Client__c = clientAccount.Id;
        all8002Code.Product__c =  'SecureOne';
        all8002Code.Coverage_Level__c = 'EZ Elite - FL';
        all8002Code.Insurance_Carrier__c = 'Include All';
        all8002Code.States__c = 'Include All';
        all8002Code.Start_Date__c = System.now().Date() - 1;
        allocationCodes.add(all8002Code);
        
        //Allocation Amount starts with 'S' and length < 5
        Allocation_Code__c all8000Code = new Allocation_Code__c();
        all8000Code.Name = '8002';
        all8000Code.Allocation_Amount__c = 'S12';
        all8000Code.Descriptor__c = 'Seller Commission';
        all8000Code.Payee_Type__c = 'Company';
        all8000Code.Client__c = clientAccount.Id;
        all8000Code.Product__c =  'SecureOne';
        all8000Code.Coverage_Level__c = 'EZ Elite - FL';
        all8000Code.Insurance_Carrier__c = 'Include All';
        all8000Code.States__c = 'Include All';
        all8000Code.Start_Date__c = System.now().Date() - 1;
        allocationCodes.add(all8000Code);
        
        //Formula allocation amount
        Allocation_Code__c all8005Code = new Allocation_Code__c();
        all8005Code.Name = '8005';
        all8005Code.Allocation_Amount__c = '{!Reserve__c} + 100';
        all8005Code.Payee_Type__c = 'Company';
        all8005Code.Client__c = clientAccount.Id;
        all8005Code.Product__c =  'SecureOne';
        all8005Code.Coverage_Level__c = 'EZ Elite - FL';
        all8005Code.Insurance_Carrier__c = 'Include All';
        all8005Code.States__c = 'Include All';
        all8005Code.Start_Date__c = System.now().Date() - 1;
        allocationCodes.add(all8005Code);
        //insert allocationCodes;
        
        //invalid Formula and null
        Allocation_Code__c invalidFormulaCode = new Allocation_Code__c();
        invalidFormulaCode.Name = 'AAA1';
        invalidFormulaCode.Allocation_Amount__c = 'Invalid Formula';
        invalidFormulaCode.Payee_Type__c = 'Company';
        allocationCodes.add(invalidFormulaCode);
        Allocation_Code__c nullAllocCode = new Allocation_Code__c();
        nullAllocCode.Name = 'Null';
        nullAllocCode.Start_Date__c = System.now().Date() - 1;
        insert allocationCodes;
        
        
        
        //Create JSON input map which would be used to populate request body containing Contract data.
        Map<String, Object> Contract = new Map<String, Object>();
        Contract.put('Dealer_Program_Id__c', '100');
        Contract.put('Client__c', clientAccount.Id);
        Contract.put('Original_State__c', 'TX');
        Contract.put('Up_To_or_Add__c', 'AddOn');
        Contract.put('Vehicle_Year__c', 3);
        Contract.put('Vehicle_Make__c', 'ACUR');
        Contract.put('Term_Months', 24000);
        Contract.put('Term_Miles', 24);
        Contract.put('Sale_Mileage', 50002);
        Contract.put('Option_1', 'Salvaged');
        Contract.put('Is_Commercial__c', true);
        Contract.put('NameInsuredId', clientAccount.Id);
        Contract.put('Coverage_Level__Id', coverageLevel.Id);
        Contract.put('Coverage_Name', 'EZ Elite - FL');
        Contract.put('Class__c', 7);
        Contract.put('Deductible__c', 100);
        Contract.put('Options_Sets__c', 'EZ Elite - FL Option Set');
        Contract.put('VIN__c', '137FA55326E214697');
        Contract.put('Ins_Carrier__c', 'AmericanResourceInsuranceCompany');
        Contract.put('Product__c', 'SecureOne');
        

        Map<String, Object> options = new Map<String, Object>();
        options.put('Sale_Date', System.now().Date());
        options.put('Rate_Set', 'FL DM VSC AmTrust');
        options.put('contract', Contract);      
        
        Test.startTest();
        // Validate the response
        Test.setMock(HttpCalloutMock.class, new RateDetailsMock());
        ReRateUtility.reRateContract(new Map<String, Object>(), new Map<String, Object>(), options);        
        Test.stopTest();
      }
    
    public class RateDetailsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":[{}]},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{"Rate_Set":"Test","Product":"Test","Rate_Code":"Test","Class_Guide":"Test","Rate_Class":"Test","Expire_Type":"Test","CLIPFeeAmTrustOutput":2.8,"CommissionOutput":2.8,"MaxMilesOutput":150000.0,"MaxAgeOutput":20.0,"BaseReserveOutput":69.0,"Option_Cost":2.8,"PremiumTaxOutput":1.0,"InsuranceCarrier":"AmericanResourceInsuranceCompany","Obligor":"TestObligor","AdminCompany":"TestAdminCompany","TypeOfInsurance":"TestTypeOfInsurance", "Premium_Tax_Old__c":100,"MaxSquareFootOutput":20, "MaxUnitOutput":30,"MaxTermMonthsOutput":12, "MaxTermMilesOutput":2000, "MaxVehicleMilesOutput":35000, "MaxVehicleAgeOutput":20, "OptionCostOutput":200, "SurchargeCostOutput":300 }}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            return res;
        }
    }
    
    @isTest
    public static void callObjectMethod() {
		// Begin test context
        // Set up DML options to allow duplicate rules for test data insertion
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        
        // Create and insert a test Account
        Account testAccount = TestDataFactory.createAccount(false);
        testAccount.FirstName = 'Spanish';
        testAccount.LastName = 'Service Center';
        testAccount.BillingState = 'FL';
        // This Account is used as Client__c in this test, so make it
        // validation-safe before the InsurancePolicy is inserted.
        testAccount.AccountNumber = 'WUS';
        Database.insert(testAccount, dmlOptions);

        // Create and insert a test Coverage Level
        Coverage_Level__c coverageLevel = new Coverage_Level__c();
        coverageLevel.Name = 'EZ Elite - FL';
        insert coverageLevel;
        
        //Create contract record
        InsurancePolicy policyRec = TestDataFactory.createInsurancePolicy(false, testAccount.Id);
        policyRec.Dealer_Program_Id__c = '259';
        policyRec.Client__c= testAccount.Id;
        policyRec.Sale_Date__c=System.now().Date();
        policyRec.Vehicle_Make__c='ACUR';
        policyRec.Contract_Term_Mileage__c=24000;
        policyRec.Contract_Term_Months__c=24;
        policyRec.Vehicle_Mileage_at_Contract_Inception__c=50002;
        policyRec.Option_1__c='Salvaged';
        policyRec.Is_Commercial__c=true;
        policyRec.NameInsuredId=testAccount.Id;
        policyRec.Coverage_Level__c=coverageLevel.Id;
        policyRec.Rate_Set__c = 'EZ FL M2M DM VSC AMT';
        policyRec.Ins_Carrier__c = 'AmericanResourceInsuranceCompany';
        policyRec.Product__c = 'SecureOne';
        
        List<InsurancePolicy> insList = new List<InsurancePolicy> ();
        insList.add(policyRec);
        insert insList;
        
        //Create Vin detail Record
        VIN_Detail__c detail = new VIN_Detail__c();
        detail.Name = '137FA553*6E******';
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
        detail.VIN_SIGNI_PATTRN_MASK__c = '137FA553*6E******';
        detail.TRIM_DESC__c = 'KSC2';
        detail.SEGMENTATION_DESC__c = 'Full Size Luxury Utility';
        insert detail;
        
        //Create VinClass to be associated with VinDetail record
        VIN_Class__C classObj = new VIN_Class__c();
        classObj.Class__c = 'test';
        classObj.Class_Guide_Name__c = 'test';
        classObj.Partner__c = 'Amtrust';
        classObj.Purchase_Type__c = 'New';
        classObj.Squish_VIN__c = detail.Id;
        insert classObj;
        
        //Create JSON input map which would be used to populate request body containing Contract data.
        Map<String, Object> Contract = new Map<String, Object>();
        Contract.put('Dealer_Program_Id__c', '100');
        Contract.put('Client__c', testAccount.Id);
        Contract.put('Original_State__c', 'TX');
        Contract.put('Up_To_or_Add__c', 'AddOn');
        Contract.put('Vehicle_Year__c', 3);
        Contract.put('Vehicle_Make__c', 'ACUR');
        Contract.put('Term_Months', 24000);
        Contract.put('Term_Miles', 24);
        Contract.put('Sale_Mileage', 50002);
        Contract.put('Option_1', 'Salvaged');
        Contract.put('Is_Commercial__c', true);
        Contract.put('NameInsuredId', testAccount.Id);
        Contract.put('Coverage_Level__Id', coverageLevel.Id);
        Contract.put('Coverage_Name', 'EZ Elite - FL');
        Contract.put('Class__c', 7);
        Contract.put('Deductible__c', 100);
        Contract.put('Options_Sets__c', 'EZ Elite - FL Option Set');
        Contract.put('VIN__c', '137FA55326E214697');

        Map<String, Object> options = new Map<String, Object>();
        options.put('Sale_Date', '2024-11-30');
        options.put('Rate_Set', 'FL DM VSC AmTrust');
        options.put('contract', Contract);
        
         Map<String, Object> args = new Map<String, Object>();
        args.put('input', new Map<String, Object>());
        args.put('output', new Map<String, Object>());
        args.put('options', options);
        
		Test.startTest();
        // Validate the response
        Test.setMock(HttpCalloutMock.class, new RateDetailsMock());
        ReRateUtility.call('createSquishVIN', args);
        ReRateUtility.call('rateSetContract', args);
        ReRateUtility.call('coverageLevelOptions', args);        
        Test.stopTest();
      }
    
    @isTest
    public static void calculateRateDetailsForNULLResult() {
		// Begin test context
        // Set up DML options to allow duplicate rules for test data insertion
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        
        Account clientAccount = TestDataFactory.createSellingAgencyAccount(true);
        clientAccount.Name = 'Endurance';
        // Validation-safe client for Sold_Contract_Validation.
        clientAccount.AccountNumber = 'WUS';
        update clientAccount;
        
        // Create and insert a test Account
        Account testAccount = TestDataFactory.createAccount(false);
        testAccount.FirstName = 'Spanish';
        testAccount.LastName = 'Service Center';
        testAccount.BillingState = 'FL';
        Database.insert(testAccount, dmlOptions);

        // Create and insert a test Coverage Level
        Coverage_Level__c coverageLevel = new Coverage_Level__c();
        coverageLevel.Name = 'EZ Elite - FL';
        insert coverageLevel;
        
        //Create contract record
        InsurancePolicy policyRec = TestDataFactory.createInsurancePolicy(false, testAccount.Id);
        policyRec.Dealer_Program_Id__c = '259';
        policyRec.Client__c= clientAccount.Id;
        policyRec.Sale_Date__c=System.now().Date();
        policyRec.Vehicle_Make__c='ACUR';
        policyRec.Contract_Term_Mileage__c=24000;
        policyRec.Contract_Term_Months__c=24;
        policyRec.Vehicle_Mileage_at_Contract_Inception__c=50002;
        policyRec.Option_1__c='Salvaged';
        policyRec.Is_Commercial__c=true;
        policyRec.NameInsuredId=testAccount.Id;
        policyRec.Coverage_Level__c=coverageLevel.Id;
        policyRec.Rate_Set__c = 'EZ FL M2M DM VSC AMT';
        policyRec.Ins_Carrier__c = 'AmericanResourceInsuranceCompany';
        policyRec.Product__c = 'SecureOne';
        
        List<InsurancePolicy> insList = new List<InsurancePolicy> ();
        insList.add(policyRec);
        insert insList;
        
        //Create Vin detail Record
        VIN_Detail__c detail = new VIN_Detail__c();
        detail.Name = '137FA553*6E******';
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
        detail.VIN_SIGNI_PATTRN_MASK__c = '137FA553*6E******';
        detail.TRIM_DESC__c = 'KSC2';
        detail.SEGMENTATION_DESC__c = 'Full Size Luxury Utility';
        insert detail;
        
        //Create VinClass to be associated with VinDetail record
        VIN_Class__C classObj = new VIN_Class__c();
        classObj.Class__c = 'test';
        classObj.Class_Guide_Name__c = 'test';
        classObj.Partner__c = 'Amtrust';
        classObj.Purchase_Type__c = 'New';
        classObj.Squish_VIN__c = detail.Id;
        insert classObj;
        
         List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        //Allocation Amount is numeric
        Allocation_Code__c all1017Code = new Allocation_Code__c();
        all1017Code.Name = '1017';
        all1017Code.Allocation_Amount__c = '200.50';
        all1017Code.Payee_Type__c = 'Company';
        all1017Code.Client__c = clientAccount.Id;
        all1017Code.Product__c =  'SecureOne';
        all1017Code.Coverage_Level__c = 'EZ Elite - FL';
        all1017Code.Insurance_Carrier__c = 'Include All';
        all1017Code.States__c = 'Include All';
        allocationCodes.add(all1017Code);

        //Allocation Amount matches Descriptor
        Allocation_Code__c all8001Code = new Allocation_Code__c();
        all8001Code.Name = '8001';
        all8001Code.Allocation_Amount__c = 'Premium Tax';
        all8001Code.Descriptor__c = 'Premium Tax';
        all8001Code.Payee_Type__c = 'Company';
        all8001Code.Client__c = clientAccount.Id;
        all8001Code.Product__c =  'SecureOne';
        all8001Code.Coverage_Level__c = 'EZ Elite - FL';
        all8001Code.Insurance_Carrier__c = 'Include All';
        all8001Code.States__c = 'Include All';
        allocationCodes.add(all8001Code);

        //Allocation Amount starts with 'S' and length < 5
        Allocation_Code__c all8004Code = new Allocation_Code__c();
        all8004Code.Name = '8004';
        all8004Code.Allocation_Amount__c = 'S12';
        all8004Code.Payee_Type__c = 'Company';
        all8004Code.Client__c = clientAccount.Id;
        all8004Code.Product__c =  'SecureOne';
        all8004Code.Coverage_Level__c = 'EZ Elite - FL';
        all8004Code.Insurance_Carrier__c = 'Include All';
        all8004Code.States__c = 'Include All';
        allocationCodes.add(all8004Code);
        
        //Allocation Amount starts with 'S' and length < 5
        Allocation_Code__c all8002Code = new Allocation_Code__c();
        all8002Code.Name = '8002';
        all8002Code.Allocation_Amount__c = 'S12';
        all8002Code.Descriptor__c = 'Premium Tax';
        all8002Code.Payee_Type__c = 'Company';
        all8002Code.Client__c = clientAccount.Id;
        all8002Code.Product__c =  'SecureOne';
        all8002Code.Coverage_Level__c = 'EZ Elite - FL';
        all8002Code.Insurance_Carrier__c = 'Include All';
        all8002Code.States__c = 'Include All';
        allocationCodes.add(all8002Code);
        
        //Allocation Amount starts with 'S' and length < 5
        Allocation_Code__c all8000Code = new Allocation_Code__c();
        all8000Code.Name = '8002';
        all8000Code.Allocation_Amount__c = 'S12';
        all8000Code.Descriptor__c = 'Seller Commission';
        all8000Code.Payee_Type__c = 'Company';
        all8000Code.Client__c = clientAccount.Id;
        all8000Code.Product__c =  'SecureOne';
        all8000Code.Coverage_Level__c = 'EZ Elite - FL';
        all8000Code.Insurance_Carrier__c = 'Include All';
        all8000Code.States__c = 'Include All';
        allocationCodes.add(all8000Code);
        
        //Formula allocation amount
        Allocation_Code__c all8005Code = new Allocation_Code__c();
        all8005Code.Name = '8005';
        all8005Code.Allocation_Amount__c = '{!Reserve__c} + 100';
        all8005Code.Payee_Type__c = 'Company';
        all8005Code.Client__c = clientAccount.Id;
        all8005Code.Product__c =  'SecureOne';
        all8005Code.Coverage_Level__c = 'EZ Elite - FL';
        all8005Code.Insurance_Carrier__c = 'Include All';
        all8005Code.States__c = 'Include All';
        allocationCodes.add(all8005Code);
        //insert allocationCodes;
        
        //invalid Formula and null
        Allocation_Code__c invalidFormulaCode = new Allocation_Code__c();
        invalidFormulaCode.Name = 'AAA1';
        invalidFormulaCode.Allocation_Amount__c = 'Invalid Formula';
        invalidFormulaCode.Payee_Type__c = 'Company';
        allocationCodes.add(invalidFormulaCode);
        Allocation_Code__c nullAllocCode = new Allocation_Code__c();
        nullAllocCode.Name = 'Null';
        insert allocationCodes;
        
        
        
        //Create JSON input map which would be used to populate request body containing Contract data.
        Map<String, Object> Contract = new Map<String, Object>();
        Contract.put('Dealer_Program_Id__c', '100');
        Contract.put('Client__c', clientAccount.Id);
        Contract.put('Original_State__c', 'TX');
        Contract.put('Up_To_or_Add__c', 'AddOn');
        Contract.put('Vehicle_Year__c', 3);
        Contract.put('Vehicle_Make__c', 'ACUR');
        Contract.put('Term_Months', 24000);
        Contract.put('Term_Miles', 24);
        Contract.put('Sale_Mileage', 50002);
        Contract.put('Option_1', 'Salvaged');
        Contract.put('Is_Commercial__c', true);
        Contract.put('NameInsuredId', clientAccount.Id);
        Contract.put('Coverage_Level__Id', coverageLevel.Id);
        Contract.put('Coverage_Name', 'EZ Elite - FL');
        Contract.put('Class__c', 7);
        Contract.put('Deductible__c', 100);
        Contract.put('Options_Sets__c', 'EZ Elite - FL Option Set');
        Contract.put('VIN__c', '137FA55326E214697');
        Contract.put('Ins_Carrier__c', 'AmericanResourceInsuranceCompany');
        Contract.put('Product__c', 'SecureOne');
        

        Map<String, Object> options = new Map<String, Object>();
        options.put('Sale_Date', '2024-11-30');
        options.put('Rate_Set', 'FL DM VSC AmTrust');
        options.put('contract', Contract);      
        
        Test.startTest();
        // Validate the response
        Test.setMock(HttpCalloutMock.class, new RateNULLDetailsMock());
        ReRateUtility.reRateContract(new Map<String, Object>(), new Map<String, Object>(), options);       
        Test.stopTest();
      }
    
    public class RateNULLDetailsMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fullJson = '{"aggregationResults":{"results":[{}]},"executionId":"d121f912-302a-483d-a0b8-4fd3110e1a18","outputs":[{"results":{}}]}';
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/json');
            res.setBody(fullJson);
            res.setStatusCode(200);
            return res;
        }
    }
}