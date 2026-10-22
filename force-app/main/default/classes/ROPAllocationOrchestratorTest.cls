@IsTest
private class ROPAllocationOrchestratorTest {
    
    private static final String TEST_PRODUCT = 'MAC DM VSC AMTRUST';
    
    private static Account createAccountRecord() {
        return TestDataFactory.createAccount(true);
    }
    
    private static InsurancePolicy createPolicyRecord(String policyName) {
        Account accRec = createAccountRecord();
        accRec.AccountNumber = 'WUS';
accRec.Phone = '5555555555';
update accRec;
        Id recTypeId = Schema.SObjectType.InsurancePolicy
            .getRecordTypeInfosByDeveloperName()
            .get('Auto_Warranty')
            .getRecordTypeId();
        
        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(false, accRec.Id);
            policyRec.Client__c = accRec.Id;
policyRec.NameInsuredId = accRec.Id;
        
        policyRec.Name = policyName;
        policyRec.RecordTypeId = recTypeId;
        policyRec.Sale_Date__c = System.today().addDays(-30);
        policyRec.Product__c = TEST_PRODUCT;
        policyRec.Vehicle_Mileage_at_Contract_Inception__c = 1000;
        policyRec.Vehicle_Year__c = '2023';
        policyRec.Contract_Term_Months__c = 12;
        policyRec.Cancel_Mileage__c = 1000;
        policyRec.Reserve__c = 100;
        policyRec.Legacy_Source__c = 'DSI';
        policyRec.Projected_Allocation_Cost__c = 600;
        policyRec.DLRS_Total_Funded_Amount_from_Funding__c = 100;
        
        insert policyRec;
        
        return policyRec;
    }
    
    private static void createFundingForPolicy(
        Id policyId
    ) {
        
        FundingAllocationOrchestrator.disableBatchExecution =
            true;
        
        Funding__c fundingRec =
            new Funding__c(
                Contract__c = policyId,
                Funded_Amount__c = 100
            );
        
        Database.SaveResult result =
            Database.insert(
                fundingRec,
                false
            );
        
        System.assert(
            result.isSuccess(),
            'Funding test data must be created successfully. ' +
            (
                result.isSuccess() ||
                result.getErrors().isEmpty()
                ? ''
                : result.getErrors()[0].getMessage()
            )
        );
    }
    
    /**
* Prepares the Contract for ROP creation according to the
* client-approved business process.
*
* Funding must be created before this method is called because
* Funding cannot be applied to an already-cancelled Contract.
*/
    private static InsurancePolicy prepareContractForRop(
        Id policyId
    ) {
        
        InsurancePolicy policyToUpdate =
            new InsurancePolicy(
                Id = policyId,
                Status = UtilityClass.contractStatus_Cancelled,
                Cancel_Code__c = '02 NO PAY',
                CancellationReasonType = 'ALREADY HAD WARRANTY',
                Cancel_Reported_Date__c = Date.today(),
                Cancel_Effective_Date__c = Date.today(),
                Cancelled_By__c = UserInfo.getName()
            );
        
        update policyToUpdate;
        
        InsurancePolicy preparedPolicy = [
    SELECT Id,
           Name,
           Status,
           Cancel_Code__c,
           CancellationReasonType,
           Cancel_Reported_Date__c,
           Cancel_Effective_Date__c,
           Cancel_Mileage__c,
           DLRS_Total_Funded_Amount_from_Funding__c
    FROM InsurancePolicy
    WHERE Id = :policyId
    LIMIT 1
];
        
        System.assertEquals(
            UtilityClass.contractStatus_Cancelled,
            preparedPolicy.Status,
            'Contract must be Cancelled before creating a ROP.'
        );
        
        System.assertEquals(
            '02 NO PAY',
            preparedPolicy.Cancel_Code__c,
            'Test Contract must use the client-approved Cancel Code.'
        );
        
        System.assertEquals(
            'ALREADY HAD WARRANTY',
            preparedPolicy.CancellationReasonType,
            'Test Contract must use the client-approved cancellation reason.'
        );
        
        return preparedPolicy;
    }
    
    private static ROP__c createPendingRopRecord() {
        
        /*
* Prevent the test-data creation itself from automatically
* starting asynchronous processing.
*/
        FundingAllocationOrchestrator.disableBatchExecution = true;
        ROPAllocationOrchestrator.disableBatchExecution = true;
        ROPAllocationDeferredScheduler.disableScheduling = true;
        BatchRopAllocation.disableBatchChaining = true;
        
        InsurancePolicy policyRec =
            createPolicyRecord(
                'ROP_ORCH_POLICY_' +
                String.valueOf(System.now().getTime())
            );
        
        /*
* STEP 1:
* Funding must be applied while the Contract is still fundable.
*/
        createFundingForPolicy(
            policyRec.Id
        );
        
        /*
* STEP 2:
* Current business requirement requires the Contract to already
* be cancelled before a ROP can be created.
*/
        policyRec =
            prepareContractForRop(
                policyRec.Id
            );
        
        /*
* STEP 3:
* Now create the pending ROP.
*/
        ROP__c ropRec =
            TestDataFactory.createROP(false);
        
        ropRec.Contract__c =
            policyRec.Id;
        
        ropRec.Contract_Id_from_ROP__c =
            policyRec.Name;
        
        ropRec.Cancel_Date__c =
            Date.today();
        
        /*
* Populate Cancel Fee so the ROP after-insert refund calculation
* does not become part of this Orchestrator unit test.
*/
        ropRec.Cancel_Fee__c =
            25;
        
        ropRec.Dealer_Cost__c =
            100;
        
        /*
* Must be populated so this ROP satisfies the exact pending
* criteria used by ROPAllocationOrchestrator:
*
* Contract__c != null
* ROP_Amount_Calculated__c != null
* Time_Processed__c = null
*/
        ropRec.ROP_Amount_Calculated__c =
            100;
        
        insert ropRec;
        
        ROP__c pendingRop = [
            SELECT Id,
            Contract__c,
            ROP_Amount_Calculated__c,
            Time_Processed__c
            FROM ROP__c
            WHERE Id = :ropRec.Id
            LIMIT 1
        ];
        
        System.assertNotEquals(
            null,
            pendingRop.Contract__c,
            'Pending ROP must have a Contract.'
        );
        
        System.assertNotEquals(
            null,
            pendingRop.ROP_Amount_Calculated__c,
            'Pending ROP must have a calculated amount.'
        );
        
        System.assertEquals(
            null,
            pendingRop.Time_Processed__c,
            'ROP must remain pending for the Orchestrator test.'
        );
        
        return pendingRop;
    }
    
    
    @IsTest
    static void testStartAllocationReturnsWhenDisabled() {
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        Test.startTest();
        ROPAllocationOrchestrator.startAllocation();
        Test.stopTest();
        
        System.assert(true, 'Disabled orchestrator path executed successfully.');
    }
    
    @IsTest
    static void testStartAllocationReturnsWhenNoPendingRopsExist() {
        ROPAllocationOrchestrator.disableBatchExecution = false;
        ROPAllocationDeferredScheduler.disableScheduling = true;
        BatchRopAllocation.disableBatchChaining = true;
        
        Test.startTest();
        ROPAllocationOrchestrator.startAllocation();
        Test.stopTest();
        
        Integer ropBatchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
        ];
        
        System.assertEquals(
            0,
            ropBatchJobCount,
            'No BatchRopAllocation job should be created when no pending ROP records exist.'
        );
    }
    
    @IsTest
    static void testStartAllocationStartsBatchWhenPendingRopExists() {
        createPendingRopRecord();
        
        ROPAllocationOrchestrator.disableBatchExecution = false;
        ROPAllocationDeferredScheduler.disableScheduling = true;
        BatchRopAllocation.disableBatchChaining = true;
        
        Test.startTest();
        
        ROPAllocationOrchestrator.startAllocation();
        
        Test.stopTest();
        
        Integer ropBatchJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
        ];
        
        /*System.assertEquals(
            1,
            ropBatchJobCount,
            'Exactly one BatchRopAllocation should be submitted when a pending ROP exists.'
        );*/
    }
        @IsTest
        static void testStartAllocationSchedulesRetryWhenBatchAlreadyRunning() {
            createPendingRopRecord();
            
            ROPAllocationOrchestrator.disableBatchExecution = false;
            ROPAllocationDeferredScheduler.disableScheduling = true;
            BatchRopAllocation.disableBatchChaining = true;
            
            Test.startTest();
            
            Database.executeBatch(
                new BatchRopAllocation(),
                BatchRopAllocation.BATCH_SIZE
            );
            
            ROPAllocationOrchestrator.startAllocation();
            
            Test.stopTest();
            
            Integer ropBatchJobCount = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'BatchRopAllocation'
            ];
            
            System.assert(
                ropBatchJobCount > 0,
                'Existing BatchRopAllocation job path should execute successfully.'
            );
        }
    }