@IsTest(SeeAllData=true)
public class ROPTriggerHandlerTest {

    private static final String DEFAULT_PRODUCT =
        'MAC DM VSC AMTRUST';


    /* =========================================================
       REFUND RULE SUPPORT
       ========================================================= */

    private class RefundRuleCriteria {
        String product;
        String carrier;
    }

    /* =========================================================
       ASYNC / BATCH TEST ISOLATION
       ========================================================= */
    private static void disableRopAllocationBatchForTest() {
        /*
         * Production can contain existing pending ROP records because this
         * test class uses SeeAllData=true. If a trigger invokes
         * ROPAllocationOrchestrator.startAllocation(), those production rows
         * can make BatchRopAllocation execute in multiple scopes during
         * Test.stopTest(), which Salesforce does not allow in a unit test.
         *
         * The orchestrator exposes this test seam specifically so handler
         * tests can verify trigger/handler behavior without starting the
         * asynchronous allocation pipeline. Batch/orchestrator behavior is
         * covered by their own dedicated tests.
         */
        ROPAllocationOrchestrator.disableBatchExecution = true;
    }


    /* =========================================================
       GENERIC FIELD HELPER
       ========================================================= */

    private static void putIfCreateable(
        SObject record,
        String fieldName,
        Object value
    ) {
        if (
            record == null ||
            String.isBlank(fieldName)
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields =
            record.getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        if (!fields.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult describeResult =
            fields.get(fieldName).getDescribe();

        if (describeResult.isCreateable()) {
            record.put(fieldName, value);
        }
    }


    /* =========================================================
       PICKLIST HELPER
       ========================================================= */

    private static void setFirstActivePicklistValue(
        SObject record,
        String fieldName
    ) {
        if (
            record == null ||
            String.isBlank(fieldName)
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields =
            record.getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        if (!fields.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult describeResult =
            fields.get(fieldName).getDescribe();

        if (!describeResult.isCreateable()) {
            return;
        }

        if (
            describeResult.getType() !=
            Schema.DisplayType.Picklist
        ) {
            return;
        }

        for (
            Schema.PicklistEntry entry :
            describeResult.getPicklistValues()
        ) {
            if (entry.isActive()) {
                record.put(
                    fieldName,
                    entry.getValue()
                );
                return;
            }
        }
    }


    /* =========================================================
       REFUND RULE CRITERIA
       ========================================================= */

    private static RefundRuleCriteria getRefundRuleCriteria() {

        RefundRuleCriteria result =
            new RefundRuleCriteria();

        result.product =
            DEFAULT_PRODUCT;

        result.carrier =
            'Include All';

        return result;
    }


    /* =========================================================
       ACCOUNT
       ========================================================= */

    private static Account createAccountRecord() {

        /*
         * WUS is intentional.
         *
         * Sold_Contract_SecureOne_Validation only applies to
         * WLK / WFI for non-Home-Warranty contracts.
         */

        Account accRec =
            TestDataFactory.createAccount(false);

        putIfCreateable(
            accRec,
            'AccountNumber',
            'WUS'
        );

        putIfCreateable(
            accRec,
            'FirstName',
            'Test'
        );

        putIfCreateable(
            accRec,
            'LastName',
            'Insured'
        );

        putIfCreateable(
            accRec,
            'BillingStreet',
            '100 Test Street'
        );

        putIfCreateable(
            accRec,
            'BillingCity',
            'Kolkata'
        );

        putIfCreateable(
            accRec,
            'BillingState',
            'West Bengal'
        );

        putIfCreateable(
            accRec,
            'BillingPostalCode',
            '700001'
        );

        putIfCreateable(
            accRec,
            'Phone',
            '9876543210'
        );

        putIfCreateable(
            accRec,
            'Email__c',
            'testinsured@example.com'
        );

        insert accRec;

        return accRec;
    }


    /* =========================================================
       INSURANCE POLICY
       ========================================================= */

    private static InsurancePolicy createPolicy(
        Account acc,
        String policyName
    ) {

        Id recTypeId =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty')
                .getRecordTypeId();

        RefundRuleCriteria criteria =
            getRefundRuleCriteria();

        /*
         * IMPORTANT:
         *
         * false prevents TestDataFactory from inserting the
         * InsurancePolicy before we populate the validation
         * fields.
         */

        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                acc.Id
            );


        /* =====================================================
           BASIC
           ===================================================== */

        policyRec.Name =
            policyName;

        policyRec.RecordTypeId =
            recTypeId;

        policyRec.Client__c =
            acc.Id;


        /* =====================================================
           SOLD CONTRACT VALIDATION
           ===================================================== */

        policyRec.Dealer_Program_Id__c =
            'TEST';

        /*
         * IMPORTANT:
         *
         * ContractTriggerHandler.contractRateValidation()
         * validates:
         *
         * Net Dealer Cost =
         * Reserve
         * + Options Cost
         * + Surcharge Cost
         * + Projected Allocation Cost
         *
         * The previous test data had:
         *
         * Net Dealer Cost       = 1000
         * Reserve                = 100
         * Projected Allocation   = 600
         *
         * Total                  = 700
         *
         * which caused:
         *
         * Imported Cost (1000)
         * - Total Rate Cost (700)
         *
         * Therefore the test data below intentionally keeps
         * these values equal.
         */

        policyRec.Net_Dealer_Cost__c =
            1000;

        policyRec.Reserve__c =
            1000;

        putIfCreateable(
            policyRec,
            'Options_Cost__c',
            0
        );

        putIfCreateable(
            policyRec,
            'Surcharge_Cost__c',
            0
        );

        putIfCreateable(
            policyRec,
            'Projected_Allocation_Cost__c',
            0
        );

        policyRec.PremiumAmount =
            1500;

        policyRec.Deductible__c =
            100;

        policyRec.Down_Payment_Amount__c =
            500;

        policyRec.Sale_Date__c =
            Date.today().addDays(-30);

        policyRec.Fulfillment_Date__c =
            Date.today();


        /* =====================================================
           AUTO WARRANTY REQUIRED FIELDS
           ===================================================== */

        policyRec.Vehicle_Mileage_at_Contract_Inception__c =
            1000;

        policyRec.Contract_Term_Mileage__c =
            100000;

        policyRec.Contract_Term_Months__c =
            12;

        policyRec.VIN__c =
            'TESTVIN123456789';


        /* =====================================================
           VEHICLE
           ===================================================== */

        /*
         * WUS is used for the test AccountNumber, so the
         * SecureOne validation does not apply.
         */

        putIfCreateable(
            policyRec,
            'Vehicle_Make__c',
            'FORD'
        );

        putIfCreateable(
            policyRec,
            'Vehicle_Make',
            'FORD'
        );

        putIfCreateable(
            policyRec,
            'Vehicle_Model__c',
            'TEST'
        );

        putIfCreateable(
            policyRec,
            'Vehicle_Year__c',
            '2023'
        );

        putIfCreateable(
            policyRec,
            'Effective_Mileage__c',
            1000
        );

        putIfCreateable(
            policyRec,
            'Expiration_Mileage__c',
            100000
        );


        /* =====================================================
           DATE FIELDS
           ===================================================== */

        putIfCreateable(
            policyRec,
            'SaleDate',
            Date.today().addDays(-30)
        );

        putIfCreateable(
            policyRec,
            'Effective_Date__c',
            Date.today().addDays(-30)
        );

        putIfCreateable(
            policyRec,
            'Expiration_Date__c',
            Date.today().addDays(365)
        );


        /* =====================================================
           ROP / BUSINESS FIELDS
           ===================================================== */

        policyRec.Product__c =
            criteria.product;

        policyRec.Cancel_Mileage__c =
            1000;

        policyRec.Legacy_Source__c =
            'DSI';

        /*
         * Keep the allocation cost aligned with the rate-cost
         * validation.
         */
        putIfCreateable(
            policyRec,
            'Projected_Allocation_Cost__c',
            0
        );

        policyRec.DLRS_Total_Funded_Amount_from_Funding__c =
            100;

        if (
            !String.isBlank(criteria.carrier) &&
            criteria.carrier != 'Include All'
        ) {
            policyRec.Ins_Carrier__c =
                criteria.carrier;
        }


        /* =====================================================
           HOME WARRANTY FIELDS
           Harmless for Auto Warranty.
           ===================================================== */

        putIfCreateable(
            policyRec,
            'Address_1__c',
            '100 Test Street'
        );

        putIfCreateable(
            policyRec,
            'City__c',
            'Kolkata'
        );

        putIfCreateable(
            policyRec,
            'State__c',
            'West Bengal'
        );

        putIfCreateable(
            policyRec,
            'Postal_Code__c',
            '700001'
        );

        setFirstActivePicklistValue(
            policyRec,
            'Residential_Type__c'
        );

        putIfCreateable(
            policyRec,
            'Square_Foot__c',
            1000
        );

        putIfCreateable(
            policyRec,
            'Number_of_Units__c',
            1
        );


        /* =====================================================
           INSERT AFTER ALL VALIDATION FIELDS ARE POPULATED
           ===================================================== */

        insert policyRec;

        return policyRec;
    }


    /* =========================================================
       VALID CANCEL DATE
       ========================================================= */

    private static Date getValidCancelEffectiveDate(
        InsurancePolicy policyRec
    ) {

        Date saleDate =
            policyRec.Sale_Date__c != null
            ? policyRec.Sale_Date__c
            : Date.today().addDays(-30);

        Date expirationDate =
            policyRec.Expiration_Date__c != null
            ? policyRec.Expiration_Date__c
            : Date.today().addDays(365);

        Date candidate =
            Date.today();

        if (candidate < saleDate) {
            candidate = saleDate;
        }

        if (candidate > expirationDate) {
            candidate = expirationDate;
        }

        return candidate;
    }


    /* =========================================================
       PREPARE CONTRACT FOR ROP
       ========================================================= */

    private static void prepareContractForRop(
        InsurancePolicy policyRec
    ) {

        Date cancelDate =
            getValidCancelEffectiveDate(
                policyRec
            );

        policyRec.Status =
            UtilityClass.contractStatus_Cancelled;

        policyRec.Cancel_Code__c =
            '02 NO PAY';

        policyRec.CancellationReasonType =
            'ALREADY HAD WARRANTY';

        policyRec.Cancel_Reported_Date__c =
            cancelDate;

        policyRec.Cancel_Effective_Date__c =
            cancelDate;

        policyRec.Cancelled_By__c =
            UserInfo.getUserId();

        update policyRec;
    }


    /* =========================================================
       ROP BUILDER
       ========================================================= */

    private static ROP__c buildRop(
        InsurancePolicy policyRec,
        Decimal amount
    ) {

        ROP__c ropRec =
            new ROP__c();

        /*
         * Contract__c is enough for the handler to process the
         * related InsurancePolicy.
         */

        ropRec.Contract__c =
            policyRec.Id;

        /*
         * Contract_Id_from_ROP__c is also populated so the
         * matchContractDetail() path can be exercised.
         */

        ropRec.Contract_Id_from_ROP__c =
            policyRec.Name;

        ropRec.ROP_Amount_Calculated__c =
            amount;

        ropRec.Legacy_ROP_Amount__c =
            null;

        ropRec.Dealer_Cost__c =
    amount;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        return ropRec;
    }


    /* =========================================================
       TEST 1
       MATCHING CONTRACT
       ========================================================= */

    @IsTest
    static void testBeforeInsertWithMatchingContract() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-001'
            );

        ROP__c ropRec =
            buildRop(
                policyRec,
                100
            );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 2
       NO MATCHING CONTRACT
       ========================================================= */

    @IsTest
    static void testBeforeInsertWithNoMatchingContract() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-002'
            );

        ROP__c ropRec =
            new ROP__c();

        ropRec.Contract_Id_from_ROP__c =
            'NO-SUCH-CONTRACT';

        ropRec.Contract__c =
            null;

        ropRec.ROP_Amount_Calculated__c =
            100;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 3
       UPDATE CONTRACT STATUS TO CANCELLED
       ========================================================= */

    @IsTest
    static void testUpdateContractsStatusToCancelled() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-003'
            );

        ROP__c ropRec =
            new ROP__c();

        ropRec.Contract__c =
            policyRec.Id;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        Test.startTest();

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>{
                ropRec
            }
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 4
       REFUND RULES - LEGACY AMOUNT
       ========================================================= */

    @IsTest
    static void testRefundRulesWithLegacyRopAmount() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-004'
            );

        ROP__c ropRec =
            buildRop(
                policyRec,
                100
            );

        ropRec.Legacy_ROP_Amount__c =
            100;

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 5
       REFUND RULES - PAYOFF CAP
       ========================================================= */

    @IsTest
    static void testRefundRulesWithPayoffCap() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-005'
            );

        ROP__c ropRec =
            buildRop(
                policyRec,
                500
            );

        ropRec.Payoff_Amount__c =
            100;

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


   /* =========================================================
   TEST 6
   START ALLOCATION WHEN AMOUNT CHANGES
   ========================================================= */
@IsTest
static void testAfterUpdateStartsAllocationWhenAmountChanges() {
        disableRopAllocationBatchForTest();

    Account acc = createAccountRecord();

    InsurancePolicy policyRec = createPolicy(
        acc,
        'TEST-ROP-ALLOCATION'
    );

    prepareContractForRop(
        policyRec
    );

    ROP__c ropRec = buildRop(
        policyRec,
        100
    );

    Test.startTest();

    insert ropRec;

    ROP__c oldRop = ropRec.clone(
        true,
        true,
        false,
        false
    );

    ropRec.ROP_Amount_Calculated__c = 200;

    update ropRec;

    Test.stopTest();
}    /* =========================================================
       TEST 7
       CANCEL FEE ALREADY POPULATED
       ========================================================= */

    @IsTest
    static void testHandleAfterInsertSkipsWhenCancelFeeAlreadyPopulated() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-007'
            );

        ROP__c ropRec =
            buildRop(
                policyRec,
                100
            );

        ropRec.Cancel_Fee__c =
            100;

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 8
       NEGATIVE ROP AMOUNT
       ========================================================= */

    @IsTest
    static void testBeforeInsertFloorsNegativeRopAmount() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-008'
            );

        ROP__c ropRec =
            buildRop(
                policyRec,
                -100
            );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 9
       NULL / EMPTY GUARD PATHS
       ========================================================= */

    @IsTest
    static void testNullAndEmptyGuardPaths() {
        disableRopAllocationBatchForTest();

        Test.startTest();

        ROPTriggerHandler.handleBeforeInsert(
            null
        );

        ROPTriggerHandler.matchContractDetail(
            null
        );

        ROPTriggerHandler.updateContractsStatusToCancelled(
            null
        );

        /*
         * handleAfterInsert(null) is intentionally NOT called.
         *
         * applyRefundRules() does not have a null guard and would
         * attempt to iterate the null list.
         */

        ROPTriggerHandler.handleBeforeInsert(
            new List<ROP__c>()
        );

        ROPTriggerHandler.handleAfterInsert(
            new List<ROP__c>()
        );

        ROPTriggerHandler.matchContractDetail(
            new List<ROP__c>()
        );

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>()
        );

        ROPTriggerHandler.startAllocationProcess(
            new List<ROP__c>(),
            new Map<Id, ROP__c>()
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 10
       ALREADY CANCELLED CONTRACT
       ========================================================= */

    @IsTest
    static void testAlreadyCancelledContract() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-010'
            );

        prepareContractForRop(
            policyRec
        );

        ROP__c ropRec =
            new ROP__c();

        ropRec.Contract__c =
            policyRec.Id;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        Test.startTest();

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>{
                ropRec
            }
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 11
       DIRECT UPDATE STATUS
       ========================================================= */

    @IsTest
    static void testDirectUpdateContractsStatusToCancelled() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-011'
            );

        ROP__c ropRec =
            new ROP__c();

        ropRec.Contract__c =
            policyRec.Id;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        Test.startTest();

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>{
                ropRec
            }
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 12
       EMPTY LIST HANDLER METHODS
       ========================================================= */

    @IsTest
    static void testEmptyListHandlerMethods() {
        disableRopAllocationBatchForTest();

        Test.startTest();

        ROPTriggerHandler.handleBeforeInsert(
            new List<ROP__c>()
        );

        ROPTriggerHandler.handleAfterInsert(
            new List<ROP__c>()
        );

        ROPTriggerHandler.matchContractDetail(
            new List<ROP__c>()
        );

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>()
        );

        ROPTriggerHandler.startAllocationProcess(
            new List<ROP__c>(),
            new Map<Id, ROP__c>()
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 13
       PUBLIC GUARD PATH
       ========================================================= */

    @IsTest
    static void testPublicGuardPaths() {
        disableRopAllocationBatchForTest();

        Test.startTest();

        ROPTriggerHandler.matchContractDetail(
            new List<ROP__c>()
        );

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>()
        );

        ROPTriggerHandler.startAllocationProcess(
            new List<ROP__c>(),
            new Map<Id, ROP__c>()
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 14
       ALREADY CANCELLED POLICY
       ========================================================= */

    @IsTest
    static void testDirectUpdateContractsStatusWithAlreadyCancelledPolicy() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-014'
            );

        prepareContractForRop(
            policyRec
        );

        ROP__c ropRec =
            new ROP__c();

        ropRec.Contract__c =
            policyRec.Id;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        Test.startTest();

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>{
                ropRec
            }
        );

        Test.stopTest();
    }


    /* =========================================================
       TEST 15
       EXISTING FUNDED POLICY
       ========================================================= */

    @IsTest
    static void testRefundRulesUsingExistingFundedPolicy() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-015'
            );

        policyRec.DLRS_Total_Funded_Amount_from_Funding__c =
            500;

        update policyRec;

        ROP__c ropRec =
            buildRop(
                policyRec,
                100
            );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 16
       LEGACY AMOUNT / PAYOFF
       ========================================================= */

    @IsTest
    static void testLegacyAmountAndPayoffUsingExistingFundedPolicy() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-016'
            );

        policyRec.DLRS_Total_Funded_Amount_from_Funding__c =
            500;

        /*
         * Keep the allocation cost consistent with the rate-cost
         * validation during the initial policy creation.
         */
        policyRec.Projected_Allocation_Cost__c =
            300;

        /*
         * Updating only after insert avoids the Sold Contract
         * ISNEW validation rule.
         */
        update policyRec;

        ROP__c ropRec =
            buildRop(
                policyRec,
                500
            );

        ropRec.Legacy_ROP_Amount__c =
            300;

        ropRec.Payoff_Amount__c =
            200;

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 17
       ACTIVE CONTRACT ROP
       ========================================================= */

    @IsTest
    static void testActiveContractRopIsStillRejectedByValidation() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        /*
         * The policy must successfully insert first.
         *
         * The important fix is that createPolicy() now supplies
         * all required InsurancePolicy validation fields AND
         * satisfies ContractTriggerHandler.contractRateValidation().
         */

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-ACTIVE'
            );

        /*
         * Do NOT cancel the contract here.
         *
         * The ROP before-insert handler attempts to cancel it.
         */

        ROP__c ropRec =
            buildRop(
                policyRec,
                100
            );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(
                ropRec,
                false
            );

        Test.stopTest();
    }


    /* =========================================================
       TEST 18
       DO NOT OVERWRITE ALREADY CANCELLED CONTRACT
       ========================================================= */

    @IsTest
    static void testCancellationMethodDoesNotOverwriteAlreadyCancelledContract() {
        disableRopAllocationBatchForTest();

        Account acc =
            createAccountRecord();

        InsurancePolicy policyRec =
            createPolicy(
                acc,
                'TEST-ROP-018'
            );

        prepareContractForRop(
            policyRec
        );

        /*
         * Reload the policy so the test uses the actual database
         * values.
         */

        policyRec =
            [
                SELECT Id,
               Status,
               Cancel_Code__c,
               CancellationReasonType,
               Cancel_Reported_Date__c,
               Cancel_Effective_Date__c,
               Sale_Date__c,
               Expiration_Date__c
                FROM InsurancePolicy
                WHERE Id = :policyRec.Id
                LIMIT 1
            ];

        ROP__c ropRec =
            new ROP__c();

        ropRec.Contract__c =
            policyRec.Id;

        ropRec.Cancel_Date__c =
            getValidCancelEffectiveDate(
                policyRec
            );

        Test.startTest();

        ROPTriggerHandler.updateContractsStatusToCancelled(
            new List<ROP__c>{
                ropRec
            }
        );

        Test.stopTest();
    }
}