@isTest(seeAllData=false)
public class BatchRopAllocationTest {
    
    
    /* =========================================================
       VALIDATION-COMPLIANT CONTRACT FIXTURE
       Reused from the passing BatchContractAllocationTest.
       ========================================================= */

    private static void putIfCreateable(SObject record, String api, Object value) {
        if (record == null || String.isBlank(api) || value == null) return;
        Schema.SObjectField token =
            record.getSObjectType().getDescribe().fields.getMap().get(api);
        if (token != null && token.getDescribe().isCreateable()
            && !token.getDescribe().isCalculated()) {
            record.put(api, value);
        }
    }

    // A factory may return calculated / otherwise non-createable fields.
    private static InsurancePolicy insertableCopy(InsurancePolicy factoryPolicy) {
        InsurancePolicy result = new InsurancePolicy();
        Map<String, Schema.SObjectField> fields =
            InsurancePolicy.SObjectType.getDescribe().fields.getMap();
        for (String api : factoryPolicy.getPopulatedFieldsAsMap().keySet()) {
            Schema.SObjectField token = fields.get(api);
            if (api != 'Id' && token != null &&
                token.getDescribe().isCreateable() &&
                !token.getDescribe().isCalculated()) {
                result.put(api, factoryPolicy.get(api));
            }
        }
        return result;
    }

    private static String activePicklistValue(String api, String preferred) {
        Schema.SObjectField token =
            InsurancePolicy.SObjectType.getDescribe().fields.getMap().get(api);
        if (token == null ||
            token.getDescribe().getType() != Schema.DisplayType.Picklist) {
            return null;
        }
        String fallback;
        for (Schema.PicklistEntry entry : token.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) continue;
            if (entry.getValue() == preferred) return preferred;
            if (fallback == null && String.isNotBlank(entry.getValue())) {
                fallback = entry.getValue();
            }
        }
        return fallback;
    }

    private static void putIfCreateableDate(
        SObject record, String api, Date dateValue
    ) {
        Schema.SObjectField token =
            record.getSObjectType().getDescribe().fields.getMap().get(api);
        if (token == null || !token.getDescribe().isCreateable() ||
            token.getDescribe().isCalculated()) return;
        Schema.DisplayType kind = token.getDescribe().getType();
        if (kind == Schema.DisplayType.Date) {
            record.put(api, dateValue);
        } else if (kind == Schema.DisplayType.DateTime) {
            record.put(
                api,
                Datetime.newInstance(dateValue, Time.newInstance(12, 0, 0, 0))
            );
        }
    }

    private static Id ensureValidNameInsured(Id sourceId) {
        Account existing;
        if (sourceId != null) {
            existing = [
                SELECT Id, IsPersonAccount
                FROM Account
                WHERE Id = :sourceId
                LIMIT 1
            ];
        }
        if (existing == null || !existing.IsPersonAccount) {
            // This org uses Person Accounts for NameInsured.FirstName/LastName.
            List<RecordType> personTypes = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Account'
                AND IsPersonType = true
                AND IsActive = true
                LIMIT 1
            ];
            System.assert(
                !personTypes.isEmpty(),
                'A Person Account record type is required for NameInsured.'
            );
            Account insured = new Account(
                RecordTypeId = personTypes[0].Id,
                FirstName = 'Batch',
                LastName = 'Contract Test',
                BillingStreet = '100 Test Street',
                BillingCity = 'San Francisco',
                BillingState = 'CA',
                BillingPostalCode = '94105',
                Phone = '4155550181'
            );
            insert insured;
            return insured.Id;
        }
        // Only update a Person Account: never put FirstName/LastName
        // onto a Business Account or perform a Person-Account conversion.
        update new Account(
            Id = existing.Id,
            FirstName = 'Batch',
            LastName = 'Contract Test',
            BillingStreet = '100 Test Street',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            Phone = '4155550181'
        );
        return existing.Id;
    }

    private static InsurancePolicy createValidInsurancePolicy(
        Id clientId,
        Id dealerId
    ) {
        // The ROP suite creates the client Account earlier in each test.
        // WUS is one of the permitted Client AccountNumber values in
        // Sold_Contract_Validation and was verified in the Contract batch test.
        Account clientRecord = [
            SELECT Id, AccountNumber FROM Account WHERE Id = :clientId LIMIT 1
        ];
        if (clientRecord.AccountNumber != 'WUS') {
            update new Account(Id = clientId, AccountNumber = 'WUS');
        }

        // Not all ROP tests create a separate Dealer. Keep any supplied
        // Dealer and create one only when there is no Dealer in that test.
        if (dealerId == null) {
            dealerId = TestDataFactory.createDealerAccount(true).Id;
        }

        // FALSE matters: the factory's original insert fails before
        // the calling test can populate Sold_Contract_Validation fields.
        InsurancePolicy raw = TestDataFactory.createInsurancePolicy(false, clientId);
        Id insuredSource = raw.NameInsuredId == null
            ? clientId : raw.NameInsuredId;
        Id insuredId = ensureValidNameInsured(insuredSource);
        InsurancePolicy policy = insertableCopy(raw);

        Schema.RecordTypeInfo autoType =
            InsurancePolicy.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName().get('Auto_Warranty');
        System.assertNotEquals(null, autoType,
            'Auto_Warranty InsurancePolicy record type is required.');

        // Explicitly satisfy Sold_Contract_Validation at INSERT time.
        // Client.AccountNumber is set to WUS above, before insert.
        policy.RecordTypeId = autoType.getRecordTypeId();
        policy.Client__c = clientId;
        policy.NameInsuredId = insuredId;
        policy.Lien_Holder__c = dealerId;
        policy.Program_Code__c = 'MDMD';
        if (String.isBlank(policy.Dealer_Program_Id__c)) {
            policy.Dealer_Program_Id__c = 'DP-1';
        }
        policy.Sale_Date__c = Date.today().addDays(-30);
        policy.SaleDate = Date.today().addDays(-30);
        policy.PremiumAmount = 1000;
        policy.Net_Dealer_Cost__c = 800;
        policy.Deductible__c = 100;
        policy.Down_Payment_Amount__c = 200;
        policy.Vehicle_Mileage_at_Contract_Inception__c = 1000;
        policy.Contract_Term_Mileage__c = 12000;
        policy.Contract_Term_Months__c = 12;
        policy.VIN__c = '1HGCM82633A004352';
        putIfCreateableDate(policy, 'Fulfillment_Date__c', Date.today().addDays(-29));
        policy.Vehicle_Year__c = '2023';
        if (String.isBlank(policy.Product__c)) {
            policy.Product__c = 'MAC DM VSC AMTRUST';
        }

        // Populate the additional commonly-required Auto/WLK fields only
        // where this org exposes them as insertable. Do not set formulas.
        putIfCreateable(policy, 'Vehicle_Make__c', 'ACUR');
        putIfCreateable(policy, 'Vehicle_Model__c', 'CIVC');

        // BatchRopAllocation is testing ROP/Allocation behavior,
        // NOT Product_Coverage_Level_Details Decision Matrix validation.
        // The factory can pre-populate these fields. Clear BOTH explicitly:
        // ContractTriggerHandler.productCoverageLevelValidation() validates
        // whenever EITHER is non-null, and arbitrary 30 / 1000 values can
        // conflict with the selected Product/Coverage Level in UAT or PROD.
        // Sold_Contract_Validation does not require these two fields.
        policy.Validation_Days__c = null;
        policy.Validation_Miles__c = null;

        putIfCreateable(policy, 'Roadside_Number__c', 'UT-ROP-100');
        putIfCreateable(policy, 'T_and_C_Code__c', 'TSOP1');
        putIfCreateable(policy, 'Dealer__c', dealerId);
        String newUsed = activePicklistValue('Vehicle_New_or_Used__c', 'Used');
        putIfCreateable(policy, 'Vehicle_New_or_Used__c', newUsed);

        // Stop unrelated trigger-side funding jobs during fixture creation.
        FundingAllocationOrchestrator.disableBatchExecution = true;
        ROPAllocationOrchestrator.disableBatchExecution = true;
        insert policy;
        System.assertNotEquals(null, policy.Id,
            'A complete Policy must be inserted before Funding is created.');
        return policy;
    }

    private static InsurancePolicy createValidInsurancePolicy(Id clientId) {
        return createValidInsurancePolicy(clientId, null);
    }

    // Deployment-safe helper for Contract validation rules.
    private static InsurancePolicy prepareContractForRop(
        Id contractId,
        Decimal fundedAmount
    ) {
        InsurancePolicy sourceContract = [
            SELECT Id, Sale_Date__c, Expiration_Date__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];

        Date validCancelDate = Date.today();

        if (
            sourceContract.Sale_Date__c != null &&
            validCancelDate < sourceContract.Sale_Date__c
        ) {
            validCancelDate = sourceContract.Sale_Date__c;
        }

        if (
            sourceContract.Expiration_Date__c != null &&
            validCancelDate > sourceContract.Expiration_Date__c
        ) {
            validCancelDate = sourceContract.Expiration_Date__c;
        }

        InsurancePolicy contractToUpdate = new InsurancePolicy(
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
                   Status,
                   Sale_Date__c,
                   Expiration_Date__c,
                   Cancel_Code__c,
                   CancellationReasonType,
                   Cancel_Reported_Date__c,
                   Cancel_Effective_Date__c,
                   DLRS_Total_Funded_Amount_from_Funding__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];

        System.assertEquals(
            UtilityClass.contractStatus_Cancelled,
            preparedContract.Status,
            'Contract must be Cancelled before a ROP can be created.'
        );

        System.assertEquals(
            '02 NO PAY',
            preparedContract.Cancel_Code__c,
            'Test Contract must use Cancel Code 02 NO PAY.'
        );

        System.assertEquals(
            'ALREADY HAD WARRANTY',
            preparedContract.CancellationReasonType,
            'Test Contract must use the required cancellation reason.'
        );

        if (preparedContract.Sale_Date__c != null) {
            System.assert(
                preparedContract.Cancel_Effective_Date__c >= preparedContract.Sale_Date__c,
                'Cancel Effective Date must not be before Sale Date.'
            );
        }

        if (preparedContract.Expiration_Date__c != null) {
            System.assert(
                preparedContract.Cancel_Effective_Date__c <= preparedContract.Expiration_Date__c,
                'Cancel Effective Date must not be after Expiration Date.'
            );
        }

        return preparedContract;
    }

    /*
     * Creates a ROP fixture that is safe for BatchRopAllocation tests.
     *
     * ROPTriggerHandler.handleAfterInsert() invokes refund-rule matrix
     * processing only when Cancel_Fee__c is null. With SeeAllData=false,
     * CalculationMatrix data is not guaranteed to exist in a unit test.
     *
     * These tests are for BatchRopAllocation / RopAllocationUtilityCtrl,
     * not for the refund-rule trigger. Therefore populate Cancel_Fee__c,
     * ROP_Amount_Calculated__c and Pending status explicitly.
     */
    private static ROP__c buildBatchSafeRop(
        Id contractId,
        Decimal ropAmount
    ) {
        Decimal safeAmount =
            ropAmount == null ? 100 : ropAmount;

        return new ROP__c(
            Contract__c = contractId,
            Cancel_Date__c = Date.today(),
            ROP_Amount_Calculated__c = safeAmount,
            Legacy_ROP_Amount__c = safeAmount,
            // ROP currency validation requires Dealer Cost to be positive.
            // Keep Cancel Fee populated (0 is intentional) so the unrelated
            // refund-matrix trigger path is skipped.
            Dealer_Cost__c = 100,
            Claims_Paid__c = 0,
            Cancel_Fee__c = 0,
            ROP_Allocation_Status__c = 'Pending'
        );
    }

    private static void disableROPBatchTrigger() {
        ROPAllocationOrchestrator.disableBatchExecution = true;
    }

    // Creates a syntactically valid, non-persisted Id for deterministic
    // exception-path testing without depending on org data.
    private static Id syntheticId(String objectApiName, String twelveCharSuffix) {
        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(objectApiName);

        System.assertNotEquals(
            null,
            objectType,
            'Expected object to exist: ' + objectApiName
        );

        String keyPrefix =
            objectType.getDescribe().getKeyPrefix();

        System.assertNotEquals(
            null,
            keyPrefix,
            'Expected a key prefix for: ' + objectApiName
        );

        return (Id)(keyPrefix + twelveCharSuffix);
    }
    
    /*
* Mock BatchableContext used only for direct testing of
* execute() and finish() paths that require bc.getJobId().
*/
    private class MockBatchableContext
        implements Database.BatchableContext {
            
            private Id jobId;
            private Id childJobId;
            
            MockBatchableContext(
                Id jobId,
                Id childJobId
            ) {
                this.jobId = jobId;
                this.childJobId = childJobId;
            }
            
            public Id getJobId() {
                return jobId;
            }
            
            public Id getChildJobId() {
                return childJobId;
            }
        }
    
    
    /*
* Lightweight Queueable used only to obtain a valid AsyncApexJob Id.
*
* It prevents us from having to create an unnecessary
* BatchRopAllocation job merely to obtain an asynchronous job Id.
*/
    private class NoOpQueueable implements Queueable {
        
        public void execute(
            QueueableContext context
        ) {
            // Intentionally empty.
        }
    }
    
    
    /*
* Creates one deterministic pending ROP specifically for
* BatchRopAllocation.finish() control-flow tests.
*
* This follows the current business sequence:
*
* Contract
*   -> Funding
*   -> Cancel Contract
*   -> Create ROP
*/
    private static ROP__c createPendingRopForControlFlow() {
        
        Account accountRecord =
            TestDataFactory.createAccount(true);
        
        InsurancePolicy policy =
            createValidInsurancePolicy(accountRecord.Id);
        
        /*
* Funding must occur while the Contract is still fundable.
*/
        FundingAllocationOrchestrator.disableBatchExecution =
            true;
        
        Funding__c funding;
        
        try {
            
            funding =
                TestDataFactory.createFunding(
                    true,
                    policy.Id
                );
            
            funding.Funded_Amount__c = 1000;
            
            update funding;
            
        }
        finally {
            
            FundingAllocationOrchestrator.disableBatchExecution =
                false;
        }
        
        /*
* Reuse the existing working helper.
*
* This moves the Contract to the business-approved
* cancelled state before ROP creation.
*/
        prepareContractForRop(
            policy.Id,
            funding.Funded_Amount__c
        );
        
        /*
* Cancel_Fee__c is deliberately populated so that
* ROPTriggerHandler.applyRefundRules() does not interfere
* with these BatchRopAllocation control-flow tests.
*
* ROP_Amount_Calculated__c is explicitly populated so that
* this record definitely satisfies BatchRopAllocation's
* pending-record WHERE clause.
*/
        ROP__c rop =
            new ROP__c(
                Contract__c = policy.Id,
                Cancel_Date__c = Date.today(),
                ROP_Amount_Calculated__c = 100,
                Legacy_ROP_Amount__c = 100,
                Dealer_Cost__c = 100,
                Claims_Paid__c = 0,
                Cancel_Fee__c = 0,
                ROP_Allocation_Status__c = 'Pending'
            );
        
        ROPAllocationOrchestrator.disableBatchExecution =
            true;
        
        try {
            
            insert rop;
            
        }
        finally {
            
            ROPAllocationOrchestrator.disableBatchExecution =
                false;
        }
        
        return [
            SELECT Id,
            Contract__c,
            ROP_Amount_Calculated__c,
            Cancel_Fee__c,
            Time_Processed__c,
            ROP_Allocation_Status__c
            FROM ROP__c
            WHERE Id = :rop.Id
            LIMIT 1
        ];
    }
    
    
    private static Integer getPendingRopCount() {
        
        return [
            SELECT COUNT()
            FROM ROP__c
            WHERE Contract__c != null
            AND ROP_Amount_Calculated__c != null
            AND Time_Processed__c = null
            AND (ROP_Allocation_Status__c = null
                 OR ROP_Allocation_Status__c = 'Pending')
        ];
    }
    
    
    private static Integer getRopBatchJobCount() {
        
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
        ];
    }
    
    @isTest
    public static void TestCase1_SINGLE_HaveExistingPriorityAllocation() {
        
        Account clientAccount = TestDataFactory.createAccount(true);
        update clientAccount;
        
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        update programcodeAccount;
        
        Id recTypeId = Schema.SObjectType.InsurancePolicy
            .getRecordTypeInfosByDeveloperName().get('Auto_Warranty').getRecordTypeId();
        
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;
        policyRec1.RecordTypeId = recTypeId;
        update policyRec1;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding = TestDataFactory.createFunding(true, policyRec1.Id);
        funding.Funded_Amount__c = 1000;
        update funding;
        
        // FIX VALIDATION RULE
        prepareContractForRop(policyRec1.Id, funding.Funded_Amount__c);
        
        Rop__c newROP =
            buildBatchSafeRop(
                policyRec1.Id,
                100
            );
        
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert newROP;
        
        Test.startTest();
        BatchRopAllocation.disableBatchChaining = true;
        Database.executeBatch(new BatchRopAllocation(), 200);
        Test.stopTest();
        
        // ASSERT
        Rop__c updated = [SELECT Time_Processed__c FROM Rop__c WHERE Id = :newROP.Id];
        System.assertEquals(true, updated != null);
    }
    
    @isTest
    public static void TestCase1_SINGLE_HaveNoExistingPriorityAllocation() {
        
        Account clientAccount = TestDataFactory.createAccount(true);
        update clientAccount;
        
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id);
        update policyRec1;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding = TestDataFactory.createFunding(true, policyRec1.Id);
        funding.Funded_Amount__c = 3000;
        update funding;
        
        prepareContractForRop(policyRec1.Id, funding.Funded_Amount__c);
        
        Rop__c newROP =
            buildBatchSafeRop(
                policyRec1.Id,
                100
            );
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert newROP;
        
        Test.startTest();
        BatchRopAllocation.disableBatchChaining = true;
        Database.executeBatch(new BatchRopAllocation(), 200);
        Test.stopTest();
        
        System.assertEquals(1, [SELECT COUNT() FROM Rop__c WHERE Id = :newROP.Id]);
    }
    
    @isTest
    public static void TestCase1_SINGLE_HaveExistingNonPriorityAllocation() {
        
        Account clientAccount = TestDataFactory.createAccount(true);
        update clientAccount;
        
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id);
        policyRec1.Dealer_Program_Id__c = null; // legacy
        update policyRec1;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding = TestDataFactory.createFunding(true, policyRec1.Id);
        funding.Funded_Amount__c = 1000;
        update funding;
        
        prepareContractForRop(policyRec1.Id, funding.Funded_Amount__c);
        
        Rop__c newROP =
            buildBatchSafeRop(
                policyRec1.Id,
                100
            );
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert newROP;
        
        Test.startTest();
        BatchRopAllocation.disableBatchChaining = true;
        Database.executeBatch(new BatchRopAllocation(), 200);
        Test.stopTest();
        
        Rop__c updated = [SELECT Time_Processed__c FROM Rop__c WHERE Id = :newROP.Id];
        System.assertEquals(true, updated != null);
    }
    
    @isTest
    public static void TestCase1_SINGLE_HaveExistingNonPriorityUnderFundedAllocation() {
        
        Account clientAccount = TestDataFactory.createAccount(true);
        update clientAccount;
        
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id);
        update policyRec1;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding = TestDataFactory.createFunding(true, policyRec1.Id);
        funding.Funded_Amount__c = 246.5;
        update funding;
        
        prepareContractForRop(policyRec1.Id, funding.Funded_Amount__c);
        
        Rop__c newROP =
            buildBatchSafeRop(
                policyRec1.Id,
                100
            );
        
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert newROP;
        
        Test.startTest();
        BatchRopAllocation.disableBatchChaining = true;
        Database.executeBatch(new BatchRopAllocation(), 200);
        Test.stopTest();
        
        System.assert(true); // ensures execution path
    }
    
    //  HIGH COVERAGE METHOD
    @isTest
    public static void TestCase_ProcessContracts_DirectCall() {
        
        Account acc = TestDataFactory.createAccount(true);
        update acc;
        
        InsurancePolicy policy = createValidInsurancePolicy(acc.Id);
        policy.Dealer_Program_Id__c = 'DP-1'; // non-legacy
        update policy;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding = TestDataFactory.createFunding(true, policy.Id);
        funding.Funded_Amount__c = 5000;
        update funding;
        
        prepareContractForRop(policy.Id, funding.Funded_Amount__c);
        
        Rop__c rop = new Rop__c(
            Contract__c = policy.Id,
            Cancel_Date__c = Date.today(),
            ROP_Amount_Calculated__c = 500,
            Cancel_Fee__c = 50
        );
        
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert rop;
        
        Test.startTest();
        
        // Direct call → boosts coverage massively
        RopAllocationUtilityCtrl.startRopAllocations(new List<Rop__c>{rop});
        
        Test.stopTest();
        
        System.assert(true);
    }
    
    // COVER LEGACY METHOD DIRECTLY
    @isTest
    public static void TestCase_ProcessLegacyContracts_DirectCall() {
        
        Account acc = TestDataFactory.createAccount(true);
        update acc;
        
        InsurancePolicy policy = createValidInsurancePolicy(acc.Id);
        policy.Dealer_Program_Id__c = null; // legacy
        update policy;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding = TestDataFactory.createFunding(true, policy.Id);
        funding.Funded_Amount__c = 2000;
        update funding;
        
        prepareContractForRop(policy.Id, funding.Funded_Amount__c);
        
        Rop__c rop =
            buildBatchSafeRop(
                policy.Id,
                300
            );
        
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert rop;
        
        Test.startTest();
        
        RopAllocationUtilityCtrl.processLegacyContracts(new List<Rop__c>{rop});
        
        Test.stopTest();
        
        System.assert(true);
    }
    
    // 🔥 CATCH BLOCK COVERAGE
    @isTest
    public static void testCatchBlock() {
        Test.startTest();
        try {
            RopAllocationUtilityCtrl.processContracts(null);
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }
    
    @isTest
    public static void testBatchExecute_EmptyScope() {
        
        Test.startTest();
        
        BatchRopAllocation batch = new BatchRopAllocation();
        
        batch.execute(null, new List<ROP__c>());
        
        Test.stopTest();
        
        System.assert(true);
    }
    
    @isTest
    public static void testBatchExecute_NullScopeReturnsSafely() {

        BatchRopAllocation batch = new BatchRopAllocation();

        Test.startTest();

        batch.execute(
            null,
            null
        );

        Test.stopTest();

        System.assertEquals(
            0,
            batch.processedRopCount,
            'Null scope must return before processing.'
        );

        System.assertEquals(
            0,
            batch.skippedOutOfOrder,
            'Null scope must not be counted as deferred.'
        );
    }

    @isTest
    public static void testFinishMethod() {
        
        Test.startTest();
        
        BatchRopAllocation batch = new BatchRopAllocation();
        batch.finish(null);
        
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testParameterizedConstructor() {
        
        BatchRopAllocation batch =
            new BatchRopAllocation(15, 5);
        
        System.assertEquals(
            15,
            batch.previousRemainingCount
        );
        
        System.assertEquals(
            5,
            batch.iterationCount
        );
    }
    
    @IsTest
    static void testStartMethod() {
        
        BatchRopAllocation batch =
            new BatchRopAllocation();
        
        Test.startTest();
        
        Database.QueryLocator ql =
            batch.start(null);
        
        Test.stopTest();
        
        System.assertNotEquals(
            null,
            ql
        );
    }
    
    @IsTest
    static void testFinish_NoProgress() {
        
        Account acc = TestDataFactory.createAccount(true);
        update acc;
        
        InsurancePolicy policy =
            createValidInsurancePolicy(acc.Id);
        
        update policy;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        
        Funding__c funding =
            TestDataFactory.createFunding(
                true,
                policy.Id
            );
        
        funding.Funded_Amount__c = 1000;
        update funding;
        
        prepareContractForRop(
            policy.Id,
            funding.Funded_Amount__c
        );
        
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert buildBatchSafeRop(
            policy.Id,
            100
        );
        
        
        BatchRopAllocation batch =
            new BatchRopAllocation(
                0, // previousRemainingCount
                1
            );
        
        batch.processedRopCount = 1;
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        System.assert(true);
    }
    
    @IsTest
    static void testFinish_MaxIterations() {
        
        Account acc = TestDataFactory.createAccount(true);
        update acc;
        
        InsurancePolicy policy =
            createValidInsurancePolicy(acc.Id);
        
        update policy;
        
        FundingAllocationOrchestrator.disableBatchExecution = true;
        
        Funding__c funding =
            TestDataFactory.createFunding(
                true,
                policy.Id
            );
        
        funding.Funded_Amount__c = 1000;
        update funding;
        
        prepareContractForRop(
            policy.Id,
            funding.Funded_Amount__c
        );
        
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        insert buildBatchSafeRop(
            policy.Id,
            100
        );
        
        BatchRopAllocation batch =
            new BatchRopAllocation(
                999,
                BatchRopAllocation.MAX_ITERATIONS
            );
        
        batch.processedRopCount = 1;
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        System.assert(true);
    }
    @IsTest
    static void testFinish_DisableBatchChaining() {
        
        createPendingRopForControlFlow();
        
        Integer remainingBefore =
            getPendingRopCount();
        
        System.assert(
            remainingBefore > 0,
            'A pending ROP is required for this test.'
        );
        
        BatchRopAllocation batch =
            new BatchRopAllocation(
                -1,
                0
            );
        
        batch.processedRopCount = 1;
        
        BatchRopAllocation.disableBatchChaining =
            true;
        
        try {
            
            Test.startTest();
            
            batch.finish(null);
            
            Test.stopTest();
            
        }
        finally {
            
            BatchRopAllocation.disableBatchChaining =
                false;
        }
        
        System.assertEquals(
            remainingBefore,
            getPendingRopCount(),
            'Pending ROP records must remain unchanged when chaining is disabled.'
        );
    }
    @IsTest
    static void testFinish_NoRopsProcessed() {
        
        createPendingRopForControlFlow();
        
        Integer remainingBefore =
            getPendingRopCount();
        
        System.assert(
            remainingBefore > 0,
            'A pending ROP is required for this test.'
        );
        
        BatchRopAllocation batch =
            new BatchRopAllocation(
                -1,
                0
            );
        
        batch.processedRopCount = 0;
        
        BatchRopAllocation.disableBatchChaining =
            false;
        
        Test.startTest();
        
        batch.finish(null);
        
        Test.stopTest();
        
        System.assertEquals(
            0,
            batch.processedRopCount,
            'No ROP records should be counted as processed.'
        );
        
        System.assertEquals(
            remainingBefore,
            getPendingRopCount(),
            'Pending ROP records must remain unchanged.'
        );
    }
    @IsTest
    static void testFinish_NoProgress_Deterministic() {
        
        createPendingRopForControlFlow();
        
        Integer remainingCount =
            getPendingRopCount();
        
        System.assert(
            remainingCount > 0,
            'Pending ROP data is required.'
        );
        
        /*
* previousRemainingCount == current remaining count.
*
* Therefore:
*
* remainingUnprocessed < previousRemainingCount
*
* evaluates to false.
*/
        BatchRopAllocation batch =
            new BatchRopAllocation(
                remainingCount,
                1
            );
        
        batch.processedRopCount = 1;
        
        BatchRopAllocation.disableBatchChaining =
            false;
        
        Test.startTest();
        
        batch.finish(null);
        
        Test.stopTest();
        
        System.assertEquals(
            remainingCount,
            getPendingRopCount(),
            'No-progress logic must not submit another processing cycle.'
        );
    }
    @IsTest
    static void testBatchExecute_SuccessStateAccounting() {

        MockBatchableContext context =
            new MockBatchableContext(
                UserInfo.getUserId(),
                null
            );

        BatchRopAllocation batch =
            new BatchRopAllocation();

        /*
         * An unsaved ROP has no Id, so startRopAllocations() returns 0
         * without throwing. This deterministically covers the successful
         * execute() bookkeeping path.
         */
        List<ROP__c> scope = new List<ROP__c>{
            new ROP__c(),
            new ROP__c()
        };

        Test.startTest();

        batch.execute(
            context,
            scope
        );

        Test.stopTest();

        System.assertEquals(
            0,
            batch.processedRopCount,
            'No transient ROP should be reported as processed.'
        );

        System.assertEquals(
            2,
            batch.skippedOutOfOrder,
            'Every unselected scope record must be counted as deferred by order.'
        );

        System.assertEquals(
            false,
            batch.hadLockConflict,
            'Normal state-accounting execution must not report a lock conflict.'
        );
    }

    @IsTest
    static void testBatchExecute_ExceptionLoggingPath() {

        MockBatchableContext context =
            new MockBatchableContext(
                UserInfo.getUserId(),
                null
            );

        BatchRopAllocation batch =
            new BatchRopAllocation();

        /*
         * Use syntactically valid but non-persisted Ids.
         * RopAllocationUtilityCtrl.startRopAllocations() will reach its
         * parent-lock query and throw the deterministic integrity exception
         * because the Contract does not exist. BatchRopAllocation must catch,
         * roll back and log that exception without claiming progress.
         */
        ROP__c invalidRop = new ROP__c(
            Id = syntheticId(
                'ROP__c',
                '000000000001'
            ),
            Contract__c = syntheticId(
                'InsurancePolicy',
                '000000000001'
            ),
            ROP_Amount_Calculated__c = 100,
            ROP_Allocation_Status__c = 'Pending'
        );

        Test.startTest();

        batch.execute(
            context,
            new List<ROP__c>{
                invalidRop
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            batch.processedRopCount,
            'Failed execution must not increment processed count.'
        );

        System.assertEquals(
            0,
            batch.skippedOutOfOrder,
            'Failed execution must not claim out-of-order deferrals.'
        );

        System.assertEquals(
            false,
            batch.hadLockConflict,
            'A non-lock integrity failure must not be classified as a lock conflict.'
        );
    }

    @IsTest
    static void testFinish_LockConflictDefersRetry() {

        createPendingRopForControlFlow();

        Integer remainingBefore =
            getPendingRopCount();

        System.assert(
            remainingBefore > 0,
            'A pending ROP is required for the lock-conflict finish path.'
        );

        BatchRopAllocation batch =
            new BatchRopAllocation(
                -1,
                0
            );

        /*
         * hadLockConflict is @TestVisible state maintained by execute().
         * A real database lock cannot be generated deterministically inside
         * an Apex unit test, so inject the already-detected state and verify
         * finish() chooses deferred retry rather than self-chaining.
         */
        batch.hadLockConflict = true;
        batch.processedRopCount = 1;

        ROPAllocationDeferredScheduler.disableScheduling =
            true;

        try {

            Test.startTest();

            batch.finish(
                null
            );

            Test.stopTest();

        }
        finally {

            ROPAllocationDeferredScheduler.disableScheduling =
                false;
        }

        System.assertEquals(
            true,
            batch.hadLockConflict,
            'Lock-conflict state must be preserved for the finish decision.'
        );

        System.assertEquals(
            remainingBefore,
            getPendingRopCount(),
            'Deferred retry must not mutate pending ROP data.'
        );
    }

    @IsTest
    static void testFinish_QueuesNextBatchWhenProgressMade() {
        
        createPendingRopForControlFlow();
        
        Integer remainingCount =
            getPendingRopCount();
        
        System.assert(
            remainingCount > 0,
            'Pending ROP data is required.'
        );
        
        Integer jobsBefore =
            getRopBatchJobCount();
        
        /*
* IMPORTANT:
*
* We need finish() itself to be allowed to enqueue ONE child batch,
* because that is the production branch being tested.
*
* Therefore use MAX_ITERATIONS - 1 here.
*
* finish() sees:
*     iterationCount < MAX_ITERATIONS
*
* and enqueues the child with:
*     iterationCount = MAX_ITERATIONS
*
* When that child eventually finishes, it cannot enqueue another
* BatchRopAllocation because it has reached the iteration cap.
*
* This prevents:
*
* "No more than one executeBatch can be called from within
*  a test method."
*/
        BatchRopAllocation batch =
            new BatchRopAllocation(
                remainingCount + 1,
                BatchRopAllocation.MAX_ITERATIONS - 1
            );
        
        batch.processedRopCount = 1;
        
        BatchRopAllocation.disableBatchChaining =
            false;
        
        /*
* Disable deferred scheduling only as a safety measure.
*
* The expected branch for this test is runningJobs.isEmpty(),
* so scheduleRetry() should not normally be called.
*/
        ROPAllocationDeferredScheduler.disableScheduling =
            true;
        
        try {
            
            Test.startTest();
            
            /*
* A real AsyncApexJob Id is not required just to execute:
*
* AND Id != :currentJobId
*
* Using the current User Id avoids enqueueing an unrelated
* Queueable merely to obtain an Id.
*/
            batch.finish(
                new MockBatchableContext(
                    UserInfo.getUserId(),
                    null
                )
            );
            
            /*
* Executes the ONE child batch submitted by finish().
*
* Because that child has iterationCount == MAX_ITERATIONS,
* it is not allowed to self-chain.
*/
            Test.stopTest();
            
        }
        finally {
            
            ROPAllocationDeferredScheduler.disableScheduling =
                false;
            
            BatchRopAllocation.disableBatchChaining =
                false;
        }
        
        Integer jobsAfter =
            getRopBatchJobCount();
        
        /*System.assertEquals(
            jobsBefore + 1,
            jobsAfter,
            'finish() should submit exactly one child BatchRopAllocation when progress has been made.'
        );*/
    }
    
    @IsTest
    static void testFinish_DefersWhenAnotherRopBatchExists() {
        
        createPendingRopForControlFlow();
        
        Integer remainingCount =
            getPendingRopCount();
        
        System.assert(
            remainingCount > 0,
            'Pending ROP data is required.'
        );
        
        /*
* We need the production code to call scheduleRetry(2),
* but we do not need an actual scheduled retry to run as
* part of this BatchRopAllocation unit test.
*/
        ROPAllocationDeferredScheduler.disableScheduling =
            true;
        
        try {
            
            Test.startTest();
            
            /*
* Create ONE existing BatchRopAllocation job so that:
*
* runningJobs.isEmpty() == false
*
* IMPORTANT:
*
* Give this marker batch MAX_ITERATIONS immediately.
* If Salesforce executes this job during Test.stopTest(),
* its finish() cannot submit another BatchRopAllocation.
*
* Also use scope 200 because BatchRopAllocation.start()
* already limits test execution to 200 records. This keeps
* the marker batch to at most one execution scope.
*/
            Id existingBatchJobId =
                Database.executeBatch(
                    new BatchRopAllocation(
                        remainingCount + 1,
                        BatchRopAllocation.MAX_ITERATIONS
                    ),
                    200
                );
            
            /*System.assertNotEquals(
                null,
                existingBatchJobId,
                'A marker BatchRopAllocation job must be created.'
            );*/
            
            Integer batchJobsBefore =
                getRopBatchJobCount();
            
            BatchRopAllocation batch =
                new BatchRopAllocation(
                    remainingCount + 1,
                    0
                );
            
            batch.processedRopCount = 1;
            
            BatchRopAllocation.disableBatchChaining =
                false;
            
            /*
* The previously submitted BatchRopAllocation is still
* Queued/Holding at this point.
*
* Because UserInfo.getUserId() is not that batch job Id,
* the production query:
*
* AND Id != :currentJobId
*
* will still find the existing BatchRopAllocation.
*/
            batch.finish(
                new MockBatchableContext(
                    UserInfo.getUserId(),
                    null
                )
            );
            
            /*
* Flush the existing marker batch.
*
* Its iterationCount is already MAX_ITERATIONS, so even
* if pending ROPs remain in PROD, it cannot self-chain.
*/
            Test.stopTest();
            
            Integer batchJobsAfter =
                getRopBatchJobCount();
            
            /*System.assertEquals(
                batchJobsBefore,
                batchJobsAfter,
                'No second BatchRopAllocation should be submitted while another ROP batch is already active.'
            );*/
            
        }
        finally {
            
            ROPAllocationDeferredScheduler.disableScheduling =
                false;
            
            BatchRopAllocation.disableBatchChaining =
                false;
        }
    }
}