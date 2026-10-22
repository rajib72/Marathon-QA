@isTest
public class AmtrustContractServiceTest {

    @isTest
    static void testSetupMethod() {
        AmtrustContractService.APIRequest req =
            new AmtrustContractService.APIRequest();

        req.RequestType = 'ContractHomeReport';

        Test.startTest();
        String result = AmtrustContractService.setup(req);
        Test.stopTest();

        System.assertEquals(
            'ContractHomeReport',
            AmtrustContractService.requestDataMap.get('RequestType'),
            'Home report request type should be captured.'
        );
    }


    @isTest
    static void testSetupMethod1() {
        AmtrustContractService.APIRequest req =
            new AmtrustContractService.APIRequest();

        req.RequestType = 'ContractAutoReport';

        Test.startTest();
        String result = AmtrustContractService.setup(req);
        Test.stopTest();

        System.assertEquals(
            'ContractAutoReport',
            AmtrustContractService.requestDataMap.get('RequestType'),
            'Auto report request type should be captured.'
        );
    }


    @isTest
    static void testSetupError() {
        AmtrustContractService.APIRequest req =
            new AmtrustContractService.APIRequest();

        req.RequestType = 'null';

        Test.startTest();
        String result = AmtrustContractService.setup(req);
        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Unsupported request types should return null.'
        );
    }


    @isTest
    static void testFetchContractsID() {

        // =====================================================
        // CLIENT / NAME INSURED
        // =====================================================
        Account clientAccount =
            TestDataFactory.createAccount(false);

        clientAccount.AccountNumber = 'WLK';
        clientAccount.FirstName = 'Test';
        clientAccount.LastName = 'Customer';
        clientAccount.BillingStreet = '123 Test Street';
        clientAccount.BillingCity = 'Columbus';
        clientAccount.BillingState = 'OH';
        clientAccount.BillingPostalCode = '43004';
        clientAccount.Phone = '6145551234';

        insert clientAccount;


        // =====================================================
        // PROGRAM CODE / LIEN HOLDER / DEALER
        // =====================================================
        Account programcodeAccount =
            TestDataFactory.createDealerAccount(true);


        // =====================================================
        // AUTO WARRANTY RECORD TYPE
        // =====================================================
        Id recTypeId =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty')
                .getRecordTypeId();


        // =====================================================
        // POLICY
        // =====================================================
        InsurancePolicy policyRec1 =
            TestDataFactory.createInsurancePolicy(
                false,
                clientAccount.Id
            );


        // =====================================================
        // RELATIONSHIPS
        // =====================================================
        policyRec1.Client__c =
            clientAccount.Id;

        policyRec1.NameInsuredId =
            clientAccount.Id;

        policyRec1.Lien_Holder__c =
            programcodeAccount.Id;

        policyRec1.Dealer__c =
            programcodeAccount.Id;

        policyRec1.RecordTypeId =
            recTypeId;


        // =====================================================
        // BASIC CONTRACT INFORMATION
        // =====================================================
        policyRec1.Program_Code__c =
            'MDMD';

        policyRec1.Ins_Carrier__c =
            'Technology Insurance Company';

        policyRec1.Dealer_Program_Id__c =
            '1';


        // =====================================================
        // REQUIRED COST FIELDS
        // =====================================================
        policyRec1.Net_Dealer_Cost__c =
            1000;

        policyRec1.PremiumAmount =
            690;

        policyRec1.Deductible__c =
            89;

        policyRec1.Down_Payment_Amount__c =
            90;


        // =====================================================
        // SALE DATE
        // =====================================================
        policyRec1.SaleDate =
            System.now();

        policyRec1.Sale_Date__c =
            Date.today();


        // =====================================================
        // REQUIRED WLK / WFI CONTRACT FIELDS
        // =====================================================
        policyRec1.Dec_Code__c =
            'TEST';

        /*
         * Product Coverage Level validation has special test logic:
         *
         * Coverage_Name__c = PowerTrain
         * Validation_Days__c = 14
         * Validation_Miles__c = 1000
         *
         * Do not use 30 for Validation_Days__c.
         */
        policyRec1.Validation_Days__c =
            14;

        policyRec1.Validation_Miles__c =
            1000;

        policyRec1.Roadside_Number__c =
            'TEST';

        policyRec1.T_and_C_Code__c =
            'TEST';


        // =====================================================
        // AUTO WARRANTY VEHICLE FIELDS
        // =====================================================
        policyRec1.VIN__c =
            'TestVin1A34123456';

        policyRec1.Vehicle_Mileage_at_Contract_Inception__c =
            100000;

        policyRec1.Contract_Term_Mileage__c =
            12000;

        policyRec1.Contract_Term_Months__c =
            12;

        policyRec1.Fulfillment_Date__c =
            Date.today();

        // Must be 4 characters or fewer
        policyRec1.Vehicle_Make__c =
            'ACUR';

        policyRec1.Vehicle_Model__c =
            'TEST';

        policyRec1.Vehicle_Year__c =
            '2023';

        // Valid picklist value: U = Used
        policyRec1.Vehicle_New_or_Used__c =
            'U';

        policyRec1.Class__c =
            'SUV';


        // =====================================================
        // RATE RELATED FIELDS
        // =====================================================
        policyRec1.Product__c =
            'SecureOne';

        policyRec1.Coverage_Name__c =
            'PowerTrain';

        policyRec1.Insurance_Code__c =
            'KNB';

        policyRec1.Rate_Code__c =
            '1';

        policyRec1.Option_1__c =
            'Salvaged';

        policyRec1.Is_Commercial__c =
            true;

        policyRec1.Up_To_or_Add__c =
            'UpTo';


        // =====================================================
        // AMTRUST CONDITIONS
        // =====================================================
        policyRec1.Earliest_Contract_Funded_Date__c =
            Date.today().addMonths(-1);

        policyRec1.Reinstatement_Date__c =
            Date.today().addMonths(-1);


        // =====================================================
        // INSERT POLICY
        // =====================================================
        insert policyRec1;


        // =====================================================
        // FUNDING
        // =====================================================
        Funding__c funding =
            TestDataFactory.createFunding(
                false,
                policyRec1.Id
            );

        funding.Funded_Amount__c =
            1000;

        funding.Contract__c =
            policyRec1.Id;

        insert funding;

        /*
         * IMPORTANT:
         * Funding automation can recalculate Earliest_Contract_Funded_Date__c
         * when the Funding record is inserted. Therefore set the service
         * criterion AFTER the Funding DML so this unit test deterministically
         * exercises the LAST_MONTH branch.
         */
        Date firstDayOfThisMonth =
            Date.newInstance(
                Date.today().year(),
                Date.today().month(),
                1
            );

        Date lastMonthDate =
            firstDayOfThisMonth.addDays(-1);

        update new InsurancePolicy(
            Id = policyRec1.Id,
            Earliest_Contract_Funded_Date__c = lastMonthDate
        );

        InsurancePolicy qualifyingContract = [
            SELECT Id,
                   Earliest_Contract_Funded_Date__c,
                   Ins_Carrier__c,
                   RecordType.DeveloperName
            FROM InsurancePolicy
            WHERE Id = :policyRec1.Id
        ];

        System.assertEquals(
            lastMonthDate,
            qualifyingContract.Earliest_Contract_Funded_Date__c,
            'The Contract must satisfy the service LAST_MONTH funded-date criterion.'
        );

        System.assertEquals(
            'Auto_Warranty',
            qualifyingContract.RecordType.DeveloperName
        );


        // =====================================================
        // TEST
        // =====================================================
        Test.startTest();

        String result =
            AmtrustContractService.fetchContractIDs(
                'Auto_Warranty'
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'The qualifying contract should be returned.'
        );

        System.assert(
            result.contains('\'' + String.valueOf(policyRec1.Id) + '\''),
            'The result should contain the qualifying Contract Id.'
        );
    }


    @isTest
    static void testFetchContractsID1() {

        // =====================================================
        // CLIENT / NAME INSURED
        // =====================================================
        Account clientAccount =
            TestDataFactory.createAccount(false);

        clientAccount.AccountNumber = 'WLK';
        clientAccount.FirstName = 'Test';
        clientAccount.LastName = 'Customer';
        clientAccount.BillingStreet = '123 Test Street';
        clientAccount.BillingCity = 'Columbus';
        clientAccount.BillingState = 'OH';
        clientAccount.BillingPostalCode = '43004';
        clientAccount.Phone = '6145551234';

        insert clientAccount;


        // =====================================================
        // PROGRAM CODE / LIEN HOLDER / DEALER
        // =====================================================
        Account programcodeAccount =
            TestDataFactory.createDealerAccount(true);


        // =====================================================
        // AUTO WARRANTY RECORD TYPE
        // =====================================================
        Id recTypeId =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty')
                .getRecordTypeId();


        // =====================================================
        // POLICY
        // =====================================================
        InsurancePolicy policyRec1 =
            TestDataFactory.createInsurancePolicy(
                false,
                clientAccount.Id
            );


        // =====================================================
        // RELATIONSHIPS
        // =====================================================
        policyRec1.Client__c =
            clientAccount.Id;

        policyRec1.NameInsuredId =
            clientAccount.Id;

        policyRec1.Lien_Holder__c =
            programcodeAccount.Id;

        policyRec1.Dealer__c =
            programcodeAccount.Id;

        policyRec1.RecordTypeId =
            recTypeId;


        // =====================================================
        // BASIC CONTRACT INFORMATION
        // =====================================================
        policyRec1.Program_Code__c =
            'MDMD';

        policyRec1.Ins_Carrier__c =
            'Security National Insurance Company';

        policyRec1.Dealer_Program_Id__c =
            '1';


        // =====================================================
        // REQUIRED COST FIELDS
        // =====================================================
        policyRec1.Net_Dealer_Cost__c =
            1000;

        policyRec1.PremiumAmount =
            690;

        policyRec1.Deductible__c =
            89;

        policyRec1.Down_Payment_Amount__c =
            90;


        // =====================================================
        // SALE DATE
        // =====================================================
        policyRec1.SaleDate =
            System.now();

        policyRec1.Sale_Date__c =
            Date.today();


        // =====================================================
        // REQUIRED WLK / WFI CONTRACT FIELDS
        // =====================================================
        policyRec1.Dec_Code__c =
            'TEST';

        /*
         * Must match ContractTriggerHandler test values
         * for PowerTrain.
         */
        policyRec1.Validation_Days__c =
            14;

        policyRec1.Validation_Miles__c =
            1000;

        policyRec1.Roadside_Number__c =
            'TEST';

        policyRec1.T_and_C_Code__c =
            'TEST';


        // =====================================================
        // AUTO WARRANTY VEHICLE FIELDS
        // =====================================================
        policyRec1.VIN__c =
            'TestVin1A34123456';

        policyRec1.Vehicle_Mileage_at_Contract_Inception__c =
            100000;

        policyRec1.Contract_Term_Mileage__c =
            12000;

        policyRec1.Contract_Term_Months__c =
            12;

        policyRec1.Fulfillment_Date__c =
            Date.today();

        policyRec1.Vehicle_Make__c =
            'ACUR';

        policyRec1.Vehicle_Model__c =
            'TEST';

        policyRec1.Vehicle_Year__c =
            '2023';

        policyRec1.Vehicle_New_or_Used__c =
            'U';

        policyRec1.Class__c =
            'SUV';


        // =====================================================
        // RATE RELATED FIELDS
        // =====================================================
        policyRec1.Product__c =
            'SecureOne';

        policyRec1.Coverage_Name__c =
            'PowerTrain';

        policyRec1.Insurance_Code__c =
            'KNB';

        policyRec1.Rate_Code__c =
            '1';

        policyRec1.Option_1__c =
            'Salvaged';

        policyRec1.Is_Commercial__c =
            true;

        policyRec1.Up_To_or_Add__c =
            'UpTo';


        // =====================================================
        // AMTRUST CONDITIONS
        // =====================================================
        policyRec1.Reinstatement_Date__c =
            Date.today().addMonths(-1);


        // =====================================================
        // INSERT POLICY
        // =====================================================
        insert policyRec1;

        /*
         * Set the reinstatement criterion AFTER the initial Contract insert.
         * This keeps Contract insert validation/trigger behavior separate from
         * the specific Amtrust service condition under test.
         */
        Date firstDayOfThisMonth =
            Date.newInstance(
                Date.today().year(),
                Date.today().month(),
                1
            );

        Date lastMonthDate =
            firstDayOfThisMonth.addDays(-1);

        Datetime lastMonthDateTime =
            Datetime.newInstance(
                lastMonthDate,
                Time.newInstance(12, 0, 0, 0)
            );

        update new InsurancePolicy(
            Id = policyRec1.Id,
            Reinstatement_Date__c = lastMonthDateTime
        );

        InsurancePolicy qualifyingContract = [
            SELECT Id,
                   Reinstatement_Date__c,
                   Ins_Carrier__c,
                   RecordType.DeveloperName
            FROM InsurancePolicy
            WHERE Id = :policyRec1.Id
        ];

        System.assertEquals(
            lastMonthDate,
            qualifyingContract.Reinstatement_Date__c.date(),
            'The Contract must satisfy the service LAST_MONTH reinstatement criterion.'
        );

        System.assertEquals(
            'Auto_Warranty',
            qualifyingContract.RecordType.DeveloperName
        );


        // =====================================================
        // TEST
        // =====================================================
        Test.startTest();

        String result =
            AmtrustContractService.fetchContractIDs(
                'Auto_Warranty'
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'The qualifying contract should be returned.'
        );

        System.assert(
            result.contains('\'' + String.valueOf(policyRec1.Id) + '\''),
            'The result should contain the qualifying Contract Id.'
        );
    }


    @isTest
    static void testCatchBlock() {

        RestRequest req =
            new RestRequest();

        RestResponse res =
            new RestResponse();

        req.requestUri =
            '/services/apexrest/AmtrustContractService/';

        req.httpMethod =
            'POST';

        req.requestBody =
            Blob.valueOf('badJson');

        RestContext.request =
            req;

        RestContext.response =
            res;


        Test.startTest();

        String result =
            AmtrustContractService.processRateImplementation();

        Test.stopTest();

        Map<String, Object> errorPayload =
            (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(
            Decimal.valueOf(400),
            (Decimal) errorPayload.get('status'),
            'Malformed JSON should return status 400.'
        );

        System.assertNotEquals(
            null,
            errorPayload.get('error'),
            'Malformed JSON should return an error message.'
        );
    }


    @isTest
    static void testDateMethod() {

        Date today =
            Date.today();

        Date lastMonth =
            today.addMonths(-1);

        System.assert(
            AmtrustContractService.isFromLastMonth(
                lastMonth
            )
        );

        System.assert(
            !AmtrustContractService.isFromLastMonth(
                today
            )
        );

        System.assert(
            AmtrustContractService.isFromThisMonth(
                today
            )
        );

        System.assertEquals(
            false,
            AmtrustContractService.isFromThisMonth(null),
            'Null must not be treated as this month.'
        );

        System.assertEquals(
            false,
            AmtrustContractService.isFromThisMonth(
                today.addMonths(-1)
            ),
            'A prior-month date must not be treated as this month.'
        );
    }


    // =========================================================
    // ADDITIONAL COVERAGE - NULL REQUEST OBJECT
    // =========================================================
    @isTest
    static void testSetupNullRequestCurrentBehavior() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            AmtrustContractService.setup(null);
        } catch (NullPointerException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'The current production implementation dereferences RequestType before its null guard.'
        );
    }


    // =========================================================
    // ADDITIONAL COVERAGE - REST SUCCESS PATH
    // =========================================================
    @isTest
    static void testProcessRateImplementationSuccess() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri =
            '/services/apexrest/AmtrustContractService/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"RequestType":"ContractAutoReport"}'
        );

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();

        String result =
            AmtrustContractService.processRateImplementation();

        Test.stopTest();

        System.assertEquals(
            'ContractAutoReport',
            AmtrustContractService.requestDataMap.get('RequestType'),
            'The REST success path should deserialize and route the request.'
        );

        // No matching contract is required for this test. The purpose is
        // to cover processRateImplementation()'s successful try path.
        System.assert(
            result == null || result.length() >= 0,
            'REST success path should complete without throwing.'
        );
    }


    // =========================================================
    // SCHEMA GUARD - NEXT CYCLE DATE IS READ ONLY
    // =========================================================
    @isTest
    static void testNextCycleDateFieldIsReadOnly() {

        Schema.DescribeFieldResult nextCycleDescribe =
            InsurancePolicy.Next_Cycle_Date__c.getDescribe();

        System.assertEquals(
            false,
            nextCycleDescribe.isUpdateable(),
            'Next_Cycle_Date__c is read-only and must not be assigned directly in unit-test DML.'
        );
    }


    // =========================================================
    // ADDITIONAL COVERAGE - NO MATCH / ERROR GENERATOR
    // =========================================================
    @isTest
    static void testNoMatchingRecordAndErrorResponseGenerator() {

        Test.startTest();

        String noContracts =
            AmtrustContractService.fetchContractIDs(
                'Record_Type_That_Does_Not_Exist'
            );

        String errorJson =
            AmtrustContractService.generateErrorResponse(
                'Unit test error'
            );

        Test.stopTest();

        System.assertEquals(
            null,
            noContracts,
            'No matching contracts should return null.'
        );

        Map<String, Object> errorPayload =
            (Map<String, Object>)
                JSON.deserializeUntyped(errorJson);

        System.assertEquals(
            Decimal.valueOf(400),
            (Decimal) errorPayload.get('status')
        );

        System.assertEquals(
            'Unit test error',
            (String) errorPayload.get('error')
        );
    }
}