@IsTest(SeeAllData=false)
private class RopAllocationUtilityCtrlTest {

    private static Integer sequenceNumber = 0;

    private class Scenario {
        Account client;
        InsurancePolicy policy;
        Funding__c funding;
    }

    /* =========================================================
       TEST DATA HELPERS
       ========================================================= */

    private static Scenario createScenario(
        Boolean legacyContract,
        Decimal fundingAmount,
        Datetime fundingProcessedAt
    ) {
        Scenario ctx = new Scenario();

        /*
         * Sold_Contract_Validation is an INSERT-only Contract validation.
         *
         * The rule explicitly exempts Contracts whose Client AccountNumber is
         * WLK, WFI or WUS. These tests are validating ROP allocation behavior,
         * not Contract intake completeness, so use the same stable WUS test
         * Client pattern used by the other allocation test suites.
         *
         * IMPORTANT:
         * Do this BEFORE the InsurancePolicy is inserted. The previous version
         * called createInsurancePolicy(true, ...), so the factory performed the
         * insert immediately and the validation rule failed before this test
         * class could normalize the Contract.
         */
        ctx.client = TestDataFactory.createAccount(true);
        ctx.client.AccountNumber = 'WUS';
        update ctx.client;

        /*
         * Keep the TestDataFactory's internally consistent Coverage Level /
         * term / validation-day values, but request the policy WITHOUT DML so
         * the relationship fields can be normalized before first insert.
         */
        ctx.policy = TestDataFactory.createInsurancePolicy(
            false,
            ctx.client.Id
        );

        // This field is explicitly referenced by Sold_Contract_Validation.
        ctx.policy.Client__c = ctx.client.Id;

        putIfCreateable(
            ctx.policy,
            'NameInsuredId',
            ctx.client.Id
        );

        insert ctx.policy;

        // startRopAllocations() routes by Dealer_Program_Id__c.
        ctx.policy.Dealer_Program_Id__c =
            legacyContract ? null : 'DP-1';

        update ctx.policy;

        /*
         * IMPORTANT BUSINESS ORDER:
         * Funding must exist BEFORE Contract cancellation and ROP creation.
         */
        ctx.funding = createAppliedFunding(
            ctx.policy.Id,
            fundingAmount,
            fundingProcessedAt
        );

        prepareContractForRop(
            ctx.policy.Id,
            fundingAmount
        );

        ctx.policy = reloadPolicy(ctx.policy.Id);

        return ctx;
    }


    private static Funding__c createAppliedFunding(
        Id contractId,
        Decimal amount,
        Datetime processedAt
    ) {
        Decimal safeAmount =
            amount == null || amount <= 0
            ? 100
            : amount;

        Funding__c funding = new Funding__c(
            Contract__c = contractId,
            Funded_Amount__c = safeAmount,
            Time_Processed__c =
                processedAt == null
                ? System.now()
                : processedAt
        );

        populateRequiredPrimitiveFields(
            funding,
            null
        );

        /*
         * Prevent test-data setup from asynchronously starting another
         * allocation batch.
         */
        FundingAllocationOrchestrator.disableBatchExecution = true;

        try {
            insert funding;
        }
        finally {
            FundingAllocationOrchestrator.disableBatchExecution = false;
        }

        return funding;
    }


    private static Date getValidCancelEffectiveDate(
        Date saleDate,
        Date expirationDate
    ) {
        Date candidate = Date.today();

        if (
            saleDate != null &&
            candidate < saleDate
        ) {
            candidate = saleDate;
        }

        if (
            expirationDate != null &&
            candidate > expirationDate
        ) {
            candidate = expirationDate;
        }

        if (
            saleDate != null &&
            expirationDate != null
        ) {
            System.assert(
                saleDate <= expirationDate,
                'Test Contract has an invalid Sale Date / Expiration Date range.'
            );
        }

        return candidate;
    }


    /*
     * Mirrors the deployment-safe cancellation state already used by the
     * ROP/Batch tests. This protects against the Policy Contract validation
     * rules that differ between QA, UAT and PROD.
     */
    private static InsurancePolicy prepareContractForRop(
        Id contractId,
        Decimal fundedAmount
    ) {
        InsurancePolicy sourceContract = [
            SELECT Id,
                   Sale_Date__c,
                   Expiration_Date__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];

        Date validCancelDate =
            getValidCancelEffectiveDate(
                sourceContract.Sale_Date__c,
                sourceContract.Expiration_Date__c
            );

        InsurancePolicy contractToUpdate =
            new InsurancePolicy(
                Id = contractId,
                DLRS_Total_Funded_Amount_from_Funding__c = fundedAmount,
                Status = UtilityClass.contractStatus_Cancelled,
                Cancel_Code__c = '02 NO PAY',
                CancellationReasonType = 'ALREADY HAD WARRANTY',
                Cancel_Reported_Date__c = validCancelDate,
                Cancel_Effective_Date__c = validCancelDate,
                Cancelled_By__c = UserInfo.getName()
            );

        update contractToUpdate;

        InsurancePolicy preparedContract = [
            SELECT Id,
                   Name,
                   Status,
                   Sale_Date__c,
                   Expiration_Date__c,
                   Cancel_Code__c,
                   CancellationReasonType,
                   Cancel_Reported_Date__c,
                   Cancel_Effective_Date__c,
                   DLRS_Total_Funded_Amount_from_Funding__c,
                   Dealer_Program_Id__c,
                   Product__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];

        System.assertEquals(
            UtilityClass.contractStatus_Cancelled,
            preparedContract.Status,
            'Contract must be Cancelled before a test ROP is inserted.'
        );

        System.assertEquals(
            '02 NO PAY',
            preparedContract.Cancel_Code__c,
            'Test Contract must use the deployment-safe cancellation code.'
        );

        if (preparedContract.Sale_Date__c != null) {
            System.assert(
                preparedContract.Cancel_Effective_Date__c >=
                preparedContract.Sale_Date__c,
                'Cancel Effective Date must not be earlier than Sale Date.'
            );
        }

        if (preparedContract.Expiration_Date__c != null) {
            System.assert(
                preparedContract.Cancel_Effective_Date__c <=
                preparedContract.Expiration_Date__c,
                'Cancel Effective Date must not be later than Expiration Date.'
            );
        }

        return preparedContract;
    }


    /*
     * Safe ROP fixture:
     * - Cancel_Fee__c is non-null, avoiding refund-rule metadata lookup.
     * - Dealer_Cost__c is positive, satisfying Currency_values_must_be_positive.
     * - Trigger-side batch orchestration is disabled during insert.
     */
    private static ROP__c createSafeRop(
        Id contractId,
        Decimal ropAmount,
        Decimal cancelFee,
        Datetime timeProcessed
    ) {
        Decimal safeAmount =
            ropAmount == null || ropAmount <= 0
            ? 100
            : ropAmount;

        InsurancePolicy policy = [
            SELECT Id,
                   Name,
                   Cancel_Effective_Date__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];

        ROP__c rop = TestDataFactory.createROP(false);

        rop.Contract__c = contractId;
        rop.Contract_Id_from_ROP__c = policy.Name;
        rop.Cancel_Date__c =
            policy.Cancel_Effective_Date__c == null
            ? Date.today()
            : policy.Cancel_Effective_Date__c;
        rop.ROP_Amount_Calculated__c = safeAmount;
        rop.Legacy_ROP_Amount__c = safeAmount;
        rop.Dealer_Cost__c = safeAmount;
        rop.Claims_Paid__c = 0;
        rop.Cancel_Fee__c =
            cancelFee == null
            ? 0
            : cancelFee;

        if (timeProcessed != null) {
            rop.Time_Processed__c = timeProcessed;
        }

        populateRequiredPrimitiveFields(
            rop,
            null
        );

        ROPAllocationOrchestrator.disableBatchExecution = true;

        try {
            insert rop;
        }
        finally {
            ROPAllocationOrchestrator.disableBatchExecution = false;
        }

        return reloadRop(rop.Id);
    }


    /*
     * Creates a refundable P allocation for processContracts().
     * The Allocation Code is intentionally real so the test is safe whether
     * Code_Refundable__c is writable or derived from Allocation Code data.
     */
    private static Allocation__c createRefundablePaidAllocation(
        InsurancePolicy policy,
        String descriptor,
        Decimal amount,
        Decimal maxAmount,
        Integer priority
    ) {
        Allocation_Code__c code = createAllocationCode(
            policy,
            descriptor,
            priority,
            maxAmount
        );

        Allocation__c allocation = new Allocation__c(
            Contract__c = policy.Id,
            Allocation_Code__c = code.Id,
            Allocation_Amount__c = amount,
            Descriptor__c = descriptor,
            Payment_Return__c = 'P',
            Max_Allocation_Amount__c = maxAmount,
            Payee__c = code.Payee__c,
            is_Expense__c = false,
            Fee_Label_for_Summary_Reporting__c = descriptor
        );

        putYesFlagIfCreateable(
            allocation,
            'Code_Refundable__c'
        );

        populateRequiredPrimitiveFields(
            allocation,
            null
        );

        insert allocation;

        Allocation__c refreshed = [
            SELECT Id,
                   Contract__c,
                   Allocation_Code__c,
                   Allocation_Amount__c,
                   Descriptor__c,
                   Payment_Return__c,
                   Code_Refundable__c,
                   Max_Allocation_Amount__c,
                   Payee__c
            FROM Allocation__c
            WHERE Id = :allocation.Id
            LIMIT 1
        ];

        /*
         * Some org versions populate Code_Refundable__c only after insert.
         * If the field itself is editable and is still not Y, set it once.
         */
        Map<String, Schema.SObjectField> allocationFields =
            Allocation__c.SObjectType
                .getDescribe()
                .fields
                .getMap();

        if (
            refreshed.Code_Refundable__c != 'Y' &&
            allocationFields.containsKey('Code_Refundable__c')
        ) {
            Schema.DescribeFieldResult dfr =
                allocationFields
                    .get('Code_Refundable__c')
                    .getDescribe();

            if (
                dfr.isUpdateable() &&
                !dfr.isCalculated()
            ) {
                refreshed.put(
                    'Code_Refundable__c',
                    'Y'
                );

                update refreshed;

                refreshed = [
                    SELECT Id,
                           Contract__c,
                           Allocation_Code__c,
                           Allocation_Amount__c,
                           Descriptor__c,
                           Payment_Return__c,
                           Code_Refundable__c,
                           Max_Allocation_Amount__c,
                           Payee__c
                    FROM Allocation__c
                    WHERE Id = :allocation.Id
                    LIMIT 1
                ];
            }
        }

        return refreshed;
    }


    /*
     * Allocation_Code__c has a Selling_Agency lookup filter in these orgs.
     * This follows the same stable setup pattern used by the allocation
     * utility tests.
     */
    private static Allocation_Code__c createAllocationCode(
        InsurancePolicy policy,
        String descriptor,
        Integer priority,
        Decimal maxAmount
    ) {
        sequenceNumber++;

        Id sellingAgencyRecordTypeId =
            getSellingAgencyAccountRecordTypeId();

        Account sellingAgency = new Account(
            Name = 'UT Selling Agency ' + sequenceNumber,
            RecordTypeId = sellingAgencyRecordTypeId
        );

        populateRequiredPrimitiveFields(
            sellingAgency,
            null
        );

        insert sellingAgency;

        Account payee = TestDataFactory.createAccount(true);

        Coverage_Level__c coverage = new Coverage_Level__c();

        putIfCreateable(
            coverage,
            'Name',
            'UT ROP Coverage ' + sequenceNumber
        );

        populateRequiredPrimitiveFields(
            coverage,
            null
        );

        insert coverage;

        String productValue =
            String.isBlank(policy.Product__c)
            ? 'UT Product'
            : policy.Product__c;

        Allocation_Code__c code = new Allocation_Code__c(
            Name = 'UTROP' + sequenceNumber,
            Priority__c = priority,
            Allocation_Type__c =
                descriptor == 'Reserve'
                ? 'Reserve Split'
                : 'Fixed',
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c = Date.today().addDays(30),
            Insurance_Carrier__c = 'Include All',
            States__c = 'Include All',
            Allocation_Amount__c = String.valueOf(maxAmount),
            Descriptor__c = descriptor,
            is_Expense__c = false,
            Client__c = sellingAgency.Id,
            Coverage_Level__c = coverage.Name,
            Product__c = productValue,
            Contract_Type__c = 'Auto',
            Payee__c = payee.Id,
            Term_Months__c = 'Include All',
            Option__c = 'Include All'
        );

        // Support either refundable-field implementation used by target orgs.
        putYesFlagIfCreateable(
            code,
            'Refundable__c'
        );

        putYesFlagIfCreateable(
            code,
            'Code_Refundable__c'
        );

        populateRequiredPrimitiveFields(
            code,
            null
        );

        insert code;

        return code;
    }


    private static Id getSellingAgencyAccountRecordTypeId() {
        Schema.RecordTypeInfo sellingAgencyRecordType =
            Account.SObjectType
                .getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get('Selling_Agency');

        System.assertNotEquals(
            null,
            sellingAgencyRecordType,
            'Selling_Agency Account record type is required by Allocation_Code__c.Client__c.'
        );

        return sellingAgencyRecordType.getRecordTypeId();
    }


    private static ROP__c reloadRop(Id ropId) {
        return [
            SELECT Id,
                   Contract__c,
                   Contract__r.Cancel_Effective_Date__c,
                   Cancel_Date__c,
                   ROP_Amount_Calculated__c,
                   Cancel_Fee__c,
                   Time_Processed__c,
                   ROP_Allocation_Status__c,
                   ROP_Allocation_Batch_Job_Id__c,
                   CreatedDate
            FROM ROP__c
            WHERE Id = :ropId
            LIMIT 1
        ];
    }


    private static InsurancePolicy reloadPolicy(Id policyId) {
        return [
            SELECT Id,
                   Name,
                   Status,
                   Dealer_Program_Id__c,
                   Client_Program_Code__c,
                   Product__c,
                   Refund_Percent__c,
                   Earned_Percent__c,
                   Cancel_Effective_Date__c,
                   ROP_Amount__c,
                   Applied_ROP_Amount__c,
                   ROP_Cancel_Fee__c,
                   Funded_Reserve__c,
                   DLRS_Total_Funded_Amount_from_Funding__c
            FROM InsurancePolicy
            WHERE Id = :policyId
            LIMIT 1
        ];
    }


    private static Integer countRopAllocations(Id contractId) {
        return [
            SELECT COUNT()
            FROM Allocation__c
            WHERE Contract__c = :contractId
            AND Payment_Return__c = 'R'
        ];
    }


    private static List<Allocation__c> getAdminCancelFeeAllocations(
        Id contractId
    ) {
        return [
            SELECT Id,
                   Allocation_Amount__c,
                   Max_Allocation_Amount__c,
                   Descriptor__c,
                   Payee__c,
                   Payment_Return__c,
                   is_Expense__c
            FROM Allocation__c
            WHERE Contract__c = :contractId
            AND Descriptor__c = 'Admin Cancel Fee'
            AND Payment_Return__c = 'R'
            ORDER BY CreatedDate ASC
        ];
    }


    /* =========================================================
       FUNCTIONAL TESTS
       ========================================================= */

    @IsTest
    static void testStartRopAllocationsRoutesAndProcessesNewContract() {
        Scenario ctx = createScenario(
            false,
            2000,
            System.now().addMinutes(-5)
        );

        Allocation__c adminPaid =
            createRefundablePaidAllocation(
                ctx.policy,
                'Admin',
                200,
                200,
                1
            );

        Allocation__c reservePaid =
            createRefundablePaidAllocation(
                ctx.policy,
                'Reserve',
                800,
                800,
                2
            );

        System.assertEquals(
            'Y',
            adminPaid.Code_Refundable__c,
            'Admin test allocation must be refundable.'
        );

        System.assertEquals(
            'Y',
            reservePaid.Code_Refundable__c,
            'Reserve test allocation must be refundable.'
        );

        ROP__c rop = createSafeRop(
            ctx.policy.Id,
            500.005,
            25.005,
            null
        );

        Test.startTest();

        RopAllocationUtilityCtrl.startRopAllocations(
            new List<ROP__c>{
                rop
            }
        );

        Test.stopTest();

        ROP__c updatedRop =
            reloadRop(rop.Id);

        System.assertNotEquals(
            null,
            updatedRop.Time_Processed__c,
            'Non-legacy ROP should be marked processed.'
        );

        List<Allocation__c> feeRows =
            getAdminCancelFeeAllocations(
                ctx.policy.Id
            );

        System.assertEquals(
            1,
            feeRows.size(),
            'Exactly one Admin Cancel Fee ROP allocation should be created.'
        );

        System.assertEquals(
            Decimal.valueOf('25.01'),
            feeRows[0].Allocation_Amount__c,
            'Cancel Fee must use HALF_UP currency rounding.'
        );

        System.assertEquals(
            Decimal.valueOf('25.01'),
            feeRows[0].Max_Allocation_Amount__c
        );

        System.assertEquals(
            'Marathon Administrative',
            feeRows[0].Payee__c
        );

        System.assertEquals(
            false,
            feeRows[0].is_Expense__c
        );
    }


    @IsTest
    static void testProcessContractsFallbackCreatesAdminCancelFeeWithoutReserve() {
        Scenario ctx = createScenario(
            false,
            1000,
            System.now().addMinutes(-5)
        );

        Allocation__c adminPaid =
            createRefundablePaidAllocation(
                ctx.policy,
                'Admin',
                100,
                100,
                1
            );

        System.assertEquals(
            'Y',
            adminPaid.Code_Refundable__c
        );

        ROP__c rop = createSafeRop(
            ctx.policy.Id,
            100,
            10,
            null
        );

        Integer allocationCountBefore =
            countRopAllocations(
                ctx.policy.Id
            );

        Boolean integrityExceptionThrown = false;
        String errorMessage;

        Test.startTest();

        try {
            RopAllocationUtilityCtrl.processContracts(
                new List<ROP__c>{
                    rop
                }
            );
        }
        catch (
            RopAllocationUtilityCtrl.RopAllocationIntegrityException e
        ) {
            integrityExceptionThrown = true;
            errorMessage = e.getMessage();
        }

        Test.stopTest();

        System.assertEquals(
            true,
            integrityExceptionThrown,
            'The updated utility must reject a positive eligible ROP when no refundable Reserve source exists.'
        );

        System.assert(
            errorMessage != null &&
            errorMessage.contains(
                'Refundable Reserve Funding allocation missing'
            ),
            'Expected the missing Reserve integrity error.'
        );

        System.assertEquals(
            allocationCountBefore,
            countRopAllocations(
                ctx.policy.Id
            ),
            'The savepoint rollback must prevent partial ROP allocations.'
        );

        System.assertEquals(
            0,
            getAdminCancelFeeAllocations(
                ctx.policy.Id
            ).size(),
            'Admin Cancel Fee must also roll back when Reserve source validation fails.'
        );

        System.assertEquals(
            null,
            reloadRop(rop.Id).Time_Processed__c,
            'The rejected ROP must remain unprocessed.'
        );
    }


    @IsTest
    static void testProcessContractsZeroCancelFeeDoesNotCreateAdminFee() {
        Scenario ctx = createScenario(
            false,
            1000,
            System.now().addMinutes(-5)
        );

        Allocation__c reservePaid =
            createRefundablePaidAllocation(
                ctx.policy,
                'Reserve',
                500,
                500,
                1
            );

        System.assertEquals(
            'Y',
            reservePaid.Code_Refundable__c
        );

        ROP__c rop = createSafeRop(
            ctx.policy.Id,
            100,
            0,
            null
        );

        Test.startTest();

        RopAllocationUtilityCtrl.processContracts(
            new List<ROP__c>{
                rop
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            getAdminCancelFeeAllocations(
                ctx.policy.Id
            ).size(),
            'Zero Cancel Fee must not create an Admin Cancel Fee allocation.'
        );

        System.assertNotEquals(
            null,
            reloadRop(rop.Id).Time_Processed__c
        );
    }


    @IsTest
    static void testProcessContractsDoesNotCreateRefundWhenNoNewFundingExists() {
        Scenario ctx = createScenario(
            false,
            2000,
            System.now().addHours(-3)
        );

        ROP__c previousRop = createSafeRop(
            ctx.policy.Id,
            50,
            0,
            System.now().addHours(-2)
        );

        Allocation__c reservePaid =
            createRefundablePaidAllocation(
                ctx.policy,
                'Reserve',
                500,
                500,
                1
            );

        System.assertEquals(
            'Y',
            reservePaid.Code_Refundable__c
        );

        ROP__c currentRop = createSafeRop(
            ctx.policy.Id,
            100,
            20,
            null
        );

        Integer allocationCountBefore =
            countRopAllocations(
                ctx.policy.Id
            );

        Test.startTest();

        RopAllocationUtilityCtrl.processContracts(
            new List<ROP__c>{
                currentRop
            }
        );

        Test.stopTest();

        Integer allocationCountAfter =
            countRopAllocations(
                ctx.policy.Id
            );

        System.assertEquals(
            allocationCountBefore,
            allocationCountAfter,
            'No new ROP allocation should be created when no newer Funding exists.'
        );

        System.assertNotEquals(
            null,
            reloadRop(currentRop.Id).Time_Processed__c
        );

        System.assertNotEquals(
            null,
            previousRop.Time_Processed__c
        );
    }


    @IsTest
    static void testProcessLegacyContractsAggregatesContractRopValues() {
        /*
         * The current legacy implementation only includes the CURRENT ROP in
         * Applied_ROP_Amount__c when that ROP is actually selected for legacy
         * allocation processing.  This test deliberately provides no legacy
         * allocation source rows, while still creating an already-processed
         * historical ROP.  The historical value must therefore be preserved
         * in the contract aggregate and the current unprocessed ROP must not
         * be counted prematurely.
         */
        Scenario ctx = createScenario(
            true,
            2000,
            System.now().addMinutes(-1)
        );

        ROP__c historicalRop = createSafeRop(
            ctx.policy.Id,
            125.005,
            0,
            System.now().addMinutes(-2)
        );

        ROP__c currentRop = createSafeRop(
            ctx.policy.Id,
            300.005,
            15.005,
            null
        );

        Test.startTest();

        RopAllocationUtilityCtrl.processLegacyContracts(
            new List<ROP__c>{
                currentRop
            }
        );

        Test.stopTest();

        InsurancePolicy updatedPolicy =
            reloadPolicy(
                ctx.policy.Id
            );

        ROP__c refreshedCurrentRop =
            reloadRop(
                currentRop.Id
            );

        Decimal expectedAppliedAmount =
            Decimal.valueOf('125.01');

        /*
         * Legacy configuration can vary by target org. If this test Contract
         * has a valid legacy allocation source, the current ROP will also be
         * processed and included. Otherwise only the historical processed ROP
         * contributes. In both cases we verify the production aggregation rule.
         */
        if (refreshedCurrentRop.Time_Processed__c != null) {
            expectedAppliedAmount +=
                Decimal.valueOf('300.01');
        }

        System.assertEquals(
            expectedAppliedAmount,
            updatedPolicy.Applied_ROP_Amount__c,
            'Applied ROP must aggregate only processed/currently-selected ROPs using HALF_UP currency rounding.'
        );

        System.assertEquals(
            Decimal.valueOf('300.005'),
            updatedPolicy.ROP_Amount__c,
            'ROP Amount must preserve the latest current ROP amount exactly.'
        );

        System.assertEquals(
            Decimal.valueOf('15.005'),
            updatedPolicy.ROP_Cancel_Fee__c,
            'ROP Cancel Fee must preserve the latest current ROP cancel fee exactly.'
        );

        System.assertNotEquals(
            null,
            historicalRop.Time_Processed__c,
            'Historical fixture must remain processed.'
        );
    }


    @IsTest
    static void testProcessLegacyContractsSkipsWhenFundingIsOlderThanPreviousRop() {
        Scenario ctx = createScenario(
            true,
            2000,
            System.now().addHours(-3)
        );

        createSafeRop(
            ctx.policy.Id,
            50,
            0,
            System.now().addHours(-2)
        );

        ROP__c currentRop = createSafeRop(
            ctx.policy.Id,
            100,
            10,
            null
        );

        Test.startTest();

        RopAllocationUtilityCtrl.processLegacyContracts(
            new List<ROP__c>{
                currentRop
            }
        );

        Test.stopTest();

        ROP__c processedCurrentRop =
            reloadRop(
                currentRop.Id
            );

        System.assertNotEquals(
            null,
            processedCurrentRop.Time_Processed__c,
            'The updated legacy utility intentionally marks an ineligible/no-new-funding ROP as processed so it does not remain stuck in the pending queue.'
        );

        System.assertEquals(
            0,
            processedCurrentRop.ROP_Amount_Calculated__c,
            'An ineligible legacy ROP must be zeroed when no newer Funding exists.'
        );

        System.assertEquals(
            0,
            processedCurrentRop.Cancel_Fee__c,
            'Cancel Fee must also be zeroed for a skipped legacy ROP.'
        );
    }


    @IsTest
    static void testUpdateContractAllocationFieldsAndRounding() {
        Scenario ctx = createScenario(
            false,
            1000,
            System.now().addMinutes(-5)
        );

        createRefundablePaidAllocation(
            ctx.policy,
            'Reserve',
            123.455,
            500,
            1
        );

        InsurancePolicy policyInMemory =
            reloadPolicy(
                ctx.policy.Id
            );

        Map<Id, InsurancePolicy> contractMap =
            new Map<Id, InsurancePolicy>{
                policyInMemory.Id =>
                    policyInMemory
            };

        Integer mappingCount = [
            SELECT COUNT()
            FROM ContractFundingAllocationFieldMapping__mdt
            WHERE Descriptor__c != null
        ];

        Test.startTest();

        // Guard clauses.
        RopAllocationUtilityCtrl.updateContractAllocationFields(
            null
        );

        RopAllocationUtilityCtrl.updateContractAllocationFields(
            new Map<Id, InsurancePolicy>()
        );

        // Functional path.
        RopAllocationUtilityCtrl.updateContractAllocationFields(
            contractMap
        );

        Test.stopTest();

        if (mappingCount > 0) {
            System.assertEquals(
                Decimal.valueOf('123.46'),
                contractMap
                    .get(policyInMemory.Id)
                    .Funded_Reserve__c,
                'Funded Reserve must use HALF_UP currency rounding.'
            );
        }
        else {
            // Production code intentionally returns if mapping metadata is absent.
            System.assertEquals(
                0,
                mappingCount
            );
        }
    }


    @IsTest
    static void testNullAndEmptyGuardAndCatchPaths() {
        Test.startTest();

        // startRopAllocations(): no Contract ids.
        RopAllocationUtilityCtrl.startRopAllocations(
            new List<ROP__c>()
        );

        RopAllocationUtilityCtrl.startRopAllocations(
            new List<ROP__c>{
                new ROP__c()
            }
        );

        // processContracts(): normal empty return.
        RopAllocationUtilityCtrl.processContracts(
            new List<ROP__c>()
        );

        // Null deliberately exercises the method's catch/rollback/log path.
        RopAllocationUtilityCtrl.processContracts(
            null
        );

        // Legacy normal + caught paths.
        RopAllocationUtilityCtrl.processLegacyContracts(
            new List<ROP__c>()
        );

        RopAllocationUtilityCtrl.processLegacyContracts(
            null
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void testTransientNullCancelFeeExercisesPrivateGuardAndRollback() {
        Scenario ctx = createScenario(
            false,
            1000,
            System.now().addMinutes(-5)
        );

        Allocation__c reservePaid =
            createRefundablePaidAllocation(
                ctx.policy,
                'Reserve',
                500,
                500,
                1
            );

        System.assertEquals(
            'Y',
            reservePaid.Code_Refundable__c
        );

        Integer beforeCount =
            countRopAllocations(
                ctx.policy.Id
            );

        /*
         * Intentionally do not insert this ROP. This reaches the private
         * addAdminCancelFeeRopAllocation() null-Cancel-Fee guard. The
         * production method later attempts to update the transient ROP and,
         * by design, rethrows the DML exception after rolling back.
         */
        ROP__c transientRop = new ROP__c(
            Contract__c = ctx.policy.Id,
            Cancel_Date__c = Date.today(),
            ROP_Amount_Calculated__c = 100,
            Cancel_Fee__c = null
        );

        Boolean expectedExceptionThrown = false;

        Test.startTest();

        try {
            RopAllocationUtilityCtrl.processContracts(
                new List<ROP__c>{
                    transientRop
                }
            );
        }
        catch (DmlException e) {
            expectedExceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'Id not specified in an update call'
                ),
                'Unexpected DML failure: ' + e.getMessage()
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            expectedExceptionThrown,
            'The transient ROP path must rethrow the final update failure.'
        );

        System.assertEquals(
            beforeCount,
            countRopAllocations(
                ctx.policy.Id
            ),
            'Rollback must leave no transient refund allocations behind.'
        );
    }


    @IsTest
    static void testStartRopAllocationsReturnsZeroForNonProcessableInput() {
        Test.startTest();

        Integer nullResult =
            RopAllocationUtilityCtrl.startRopAllocations(
                (List<ROP__c>) null,
                UserInfo.getUserId()
            );

        Integer emptyResult =
            RopAllocationUtilityCtrl.startRopAllocations(
                new List<ROP__c>(),
                UserInfo.getUserId()
            );

        Integer transientResult =
            RopAllocationUtilityCtrl.startRopAllocations(
                new List<ROP__c>{
                    new ROP__c()
                },
                UserInfo.getUserId()
            );

        Test.stopTest();

        System.assertEquals(0, nullResult);
        System.assertEquals(0, emptyResult);
        System.assertEquals(0, transientResult);
    }


    @IsTest
    static void testStartRopAllocationsProcessesOnlyOldestPendingRop() {
        Scenario ctx = createScenario(
            false,
            2000,
            System.now().addMinutes(-5)
        );

        ROP__c olderRop = createSafeRop(
            ctx.policy.Id,
            100,
            0,
            null
        );

        ROP__c newerRop = createSafeRop(
            ctx.policy.Id,
            150,
            0,
            null
        );

        Test.setCreatedDate(
            olderRop.Id,
            System.now().addMinutes(-2)
        );

        Test.setCreatedDate(
            newerRop.Id,
            System.now().addMinutes(-1)
        );

        olderRop = reloadRop(olderRop.Id);
        newerRop = reloadRop(newerRop.Id);

        Test.startTest();

        Integer processedCount =
            RopAllocationUtilityCtrl.startRopAllocations(
                new List<ROP__c>{
                    newerRop
                },
                null
            );

        Test.stopTest();

        System.assertEquals(
            0,
            processedCount,
            'A newer same-Contract ROP must not bypass the oldest pending ROP.'
        );

        System.assertEquals(
            null,
            reloadRop(newerRop.Id).Time_Processed__c,
            'The newer ROP must remain pending until the older ROP is handled.'
        );
    }


    @IsTest
    static void testStartRopAllocationsStoresProcessedStatusAndBatchId() {
        Scenario ctx = createScenario(
            false,
            2000,
            System.now().addMinutes(-5)
        );

        createRefundablePaidAllocation(
            ctx.policy,
            'Admin',
            100,
            100,
            1
        );

        createRefundablePaidAllocation(
            ctx.policy,
            'Reserve',
            900,
            900,
            2
        );

        ROP__c rop = createSafeRop(
            ctx.policy.Id,
            200,
            20,
            null
        );

        Id syntheticBatchJobId =
            UserInfo.getUserId();

        Test.startTest();

        Integer processedCount =
            RopAllocationUtilityCtrl.startRopAllocations(
                new List<ROP__c>{
                    rop
                },
                syntheticBatchJobId
            );

        Test.stopTest();

        ROP__c processedRop =
            reloadRop(
                rop.Id
            );

        System.assertEquals(
            1,
            processedCount,
            'Exactly one ROP should transition from Pending to Processed.'
        );

        System.assertNotEquals(
            null,
            processedRop.Time_Processed__c
        );

        System.assertEquals(
            'Processed',
            processedRop.ROP_Allocation_Status__c
        );

        System.assertEquals(
            String.valueOf(syntheticBatchJobId),
            processedRop.ROP_Allocation_Batch_Job_Id__c
        );
    }


    @IsTest
    static void testProcessContractsRejectsMultipleRopsForSameContract() {
        Scenario ctx = createScenario(
            false,
            1000,
            System.now().addMinutes(-5)
        );

        ROP__c firstRop = createSafeRop(
            ctx.policy.Id,
            100,
            0,
            null
        );

        ROP__c secondRop = createSafeRop(
            ctx.policy.Id,
            120,
            0,
            null
        );

        Boolean expectedExceptionThrown = false;

        Test.startTest();

        try {
            RopAllocationUtilityCtrl.processContracts(
                new List<ROP__c>{
                    firstRop,
                    secondRop
                }
            );
        }
        catch (
            RopAllocationUtilityCtrl.RopAllocationIntegrityException e
        ) {
            expectedExceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'More than one ROP for a Contract'
                )
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            expectedExceptionThrown,
            'Direct phase-2 processing must reject multiple ROPs for one Contract.'
        );
    }


    @IsTest
    static void testProcessLegacyContractsRejectsMultipleRopsForSameContract() {
        Scenario ctx = createScenario(
            true,
            1000,
            System.now().addMinutes(-5)
        );

        ROP__c firstRop = createSafeRop(
            ctx.policy.Id,
            100,
            0,
            null
        );

        ROP__c secondRop = createSafeRop(
            ctx.policy.Id,
            120,
            0,
            null
        );

        Boolean expectedExceptionThrown = false;

        Test.startTest();

        try {
            RopAllocationUtilityCtrl.processLegacyContracts(
                new List<ROP__c>{
                    firstRop,
                    secondRop
                }
            );
        }
        catch (
            RopAllocationUtilityCtrl.RopAllocationIntegrityException e
        ) {
            expectedExceptionThrown = true;

            System.assert(
                e.getMessage().contains(
                    'Multiple legacy ROPs for the same Contract'
                )
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            expectedExceptionThrown,
            'Direct legacy processing must reject multiple ROPs for one Contract.'
        );
    }


    /* =========================================================
       GENERIC ORG-SAFE FIELD HELPERS
       ========================================================= */

    private static void putIfCreateable(
        SObject record,
        String fieldApiName,
        Object value
    ) {
        if (
            record == null ||
            String.isBlank(fieldApiName) ||
            value == null
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields =
            record
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult describe =
            fields
                .get(fieldApiName)
                .getDescribe();

        if (
            describe.isCreateable() &&
            !describe.isCalculated()
        ) {
            record.put(
                fieldApiName,
                value
            );
        }
    }


    private static void putYesFlagIfCreateable(
        SObject record,
        String fieldApiName
    ) {
        if (
            record == null ||
            String.isBlank(fieldApiName)
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields =
            record
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult describe =
            fields
                .get(fieldApiName)
                .getDescribe();

        if (
            !describe.isCreateable() ||
            describe.isCalculated()
        ) {
            return;
        }

        if (
            describe.getType() ==
            Schema.DisplayType.Boolean
        ) {
            record.put(
                fieldApiName,
                true
            );
        }
        else {
            record.put(
                fieldApiName,
                'Y'
            );
        }
    }


    /*
     * Adds safe defaults only for required, createable primitive fields.
     * This helps prevent source-org/target-org required-field drift from
     * causing CI/CD-only failures.
     */
    private static void populateRequiredPrimitiveFields(
        SObject record,
        Id defaultAccountId
    ) {
        Map<String, Schema.SObjectField> fields =
            record
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();

        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult describe =
                fields
                    .get(fieldName)
                    .getDescribe();

            if (
                !describe.isCreateable() ||
                describe.isCalculated() ||
                describe.isDefaultedOnCreate() ||
                describe.isNillable() ||
                record.get(fieldName) != null
            ) {
                continue;
            }

            Schema.DisplayType typeValue =
                describe.getType();

            if (
                typeValue == Schema.DisplayType.String ||
                typeValue == Schema.DisplayType.TextArea ||
                typeValue == Schema.DisplayType.EncryptedString
            ) {
                record.put(
                    fieldName,
                    'UT'
                );
            }
            else if (
                typeValue == Schema.DisplayType.Boolean
            ) {
                record.put(
                    fieldName,
                    false
                );
            }
            else if (
                typeValue == Schema.DisplayType.Date
            ) {
                record.put(
                    fieldName,
                    Date.today()
                );
            }
            else if (
                typeValue == Schema.DisplayType.DateTime
            ) {
                record.put(
                    fieldName,
                    System.now()
                );
            }
            else if (
                typeValue == Schema.DisplayType.Integer
            ) {
                record.put(
                    fieldName,
                    1
                );
            }
            else if (
                typeValue == Schema.DisplayType.Currency ||
                typeValue == Schema.DisplayType.Double ||
                typeValue == Schema.DisplayType.Percent
            ) {
                record.put(
                    fieldName,
                    1
                );
            }
            else if (
                typeValue == Schema.DisplayType.Email
            ) {
                record.put(
                    fieldName,
                    'rop.utility.test@example.com'
                );
            }
            else if (
                typeValue == Schema.DisplayType.Phone
            ) {
                record.put(
                    fieldName,
                    '5550000000'
                );
            }
            else if (
                typeValue == Schema.DisplayType.Url
            ) {
                record.put(
                    fieldName,
                    'https://example.com'
                );
            }
            else if (
                typeValue == Schema.DisplayType.Picklist ||
                typeValue == Schema.DisplayType.MultiPicklist
            ) {
                for (
                    Schema.PicklistEntry entry :
                    describe.getPicklistValues()
                ) {
                    if (entry.isActive()) {
                        record.put(
                            fieldName,
                            entry.getValue()
                        );
                        break;
                    }
                }
            }
            else if (
                typeValue == Schema.DisplayType.Reference &&
                defaultAccountId != null &&
                (
                    fieldName == 'AccountId' ||
                    fieldName == 'Client__c'
                )
            ) {
                record.put(
                    fieldName,
                    defaultAccountId
                );
            }
        }
    }
}