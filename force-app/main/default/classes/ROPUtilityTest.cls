/**
* @author      Raj Sekhar Mukherjee
* @description Production-ready tests for ROPUtility.
*
* Covered outcomes:
* - No pending ROP records.
* - Successful BatchRopAllocation submission.
* - Duplicate/running batch protection.
* - Exception handling when batch submission is not permitted.
*/
@IsTest(SeeAllData=false)
private class ROPUtilityTest {
    
    private static final String NO_PENDING_MESSAGE =
        'No pending ROP records found for allocation.';
    
    private static final String RUNNING_JOB_MESSAGE =
        'Another ROP allocation job is already running. Please try again later.';
    
    private static final String INTERNAL_ERROR_MESSAGE =
        'An internal error occurred while starting the ROP allocation job. ' +
        'Please contact your administrator.';
    
   
        
        /*
* Reuse the org's established test-data factory.
*
* InsurancePolicy has substantial trigger/validation dependencies,
* therefore using TestDataFactory keeps this unit test independent
* from unrelated Contract setup requirements.
*/
        @TestSetup
static void setupData() {

    Account client = TestDataFactory.createAccount(true);

    client.AccountNumber = 'WUS';
    client.Phone = '5555555555';
    update client;

    InsurancePolicy policy =
        TestDataFactory.createInsurancePolicy(
            false,
            client.Id
        );

    policy.Client__c = client.Id;
    policy.NameInsuredId = client.Id;

    insert policy;

    System.assertNotEquals(
        null,
        policy.Id,
        'TestDataFactory must create a persisted InsurancePolicy.'
    );
}
    
    
    /* =========================================================
NO PENDING ROP
========================================================= */
    
    @IsTest
    static void returnsNoPendingMessageWhenNoEligibleRopsExist() {
        
        Test.startTest();
        
        List<ROPUtility.FlowResponse> responses =
            ROPUtility.startRopAllocation(null);
        
        Test.stopTest();
        
        assertResponse(
            responses,
            false,
            NO_PENDING_MESSAGE
        );
        
        System.assertEquals(
            0,
            countRopBatchJobs(),
            'No batch should be submitted when no eligible ROP exists.'
        );
    }
    
    
    /* =========================================================
SUCCESSFUL BATCH SUBMISSION
========================================================= */
    
    @IsTest
    static void submitsBatchWhenPendingRopsExist() {
        
        Id contractId = getPolicyId();
        
        /*
* IMPORTANT:
*
* Funding must be created BEFORE the first ROP.
*
* ROPTriggerHandler changes the Contract status to Cancelled
* when the first ROP is inserted. A Funding record cannot then
* be created against that cancelled Contract unless the Contract
* has been reinstated.
*
* The purpose of this test is ROPUtility batch submission, not
* Contract reinstatement. Therefore create enough applied Funding
* for both pending ROP records before creating either ROP.
*
* 125.50 + 74.50 = 200.00
*/
        createAppliedFunding(
            contractId,
            200.00
        );
        
        /*
* Contract must be cancelled only after Funding has been applied
* and before any ROP is created.
*/
        prepareContractForRop(
            contractId
        );
        
        createPendingRop(
            contractId,
            125.50
        );
        
        createPendingRop(
            contractId,
            74.50
        );
        
        System.assertEquals(
            2,
            countPendingRops(),
            'The test must arrange exactly two pending ROP records.'
        );
        
        /*
* Do not call Test.stopTest() here.
*
* This test verifies only that ROPUtility submits the
* BatchRopAllocation job. Actual execution of that batch belongs
* in BatchRopAllocationTest.
*/
        List<ROPUtility.FlowResponse> responses =
            ROPUtility.startRopAllocation(
                new List<String>{
                    String.valueOf(contractId)
                        }
            );
        
        assertResponse(
            responses,
            true,
            'ROP allocation job has been started successfully for 2 pending ROP record(s).'
        );
        
        List<AsyncApexJob> jobs =
            getRopBatchJobs();
        
        System.assertEquals(
            1,
            jobs.size(),
            'Exactly one BatchRopAllocation job must be submitted.'
        );
        
        System.assertEquals(
            'BatchApex',
            jobs[0].JobType
        );
        
        System.assert(
            new Set<String>{
                'Holding',
                    'Preparing',
                    'Processing',
                    'Queued'
                    }.contains(jobs[0].Status),
            'The submitted job must be active or queued.'
        );
    }
    
    
    /* =========================================================
DUPLICATE BATCH PROTECTION
========================================================= */
    
    @IsTest
    static void blocksDuplicateSubmissionWhenRopBatchIsAlreadyRunning() {
        
        Id contractId = getPolicyId();
        
        /*
* Arrange valid Funding before creating the ROP because the
* ROP insert will cancel the related Contract.
*/
        createAppliedFunding(
            contractId,
            125.50
        );
        
        prepareContractForRop(
            contractId
        );
        
        createPendingRop(
            contractId,
            125.50
        );
        
        Id existingJobId =
            Database.executeBatch(
                new BatchRopAllocation(),
                BatchRopAllocation.BATCH_SIZE
            );
        
        List<ROPUtility.FlowResponse> responses =
            ROPUtility.startRopAllocation(
                new List<String>{
                    String.valueOf(contractId)
                        }
            );
        
        assertResponse(
            responses,
            false,
            RUNNING_JOB_MESSAGE
        );
        
        List<AsyncApexJob> jobs =
            getRopBatchJobs();
        
        System.assertEquals(
            1,
            jobs.size(),
            'ROPUtility must not submit a duplicate ROP batch.'
        );
        
        System.assertEquals(
            existingJobId,
            jobs[0].Id,
            'The original queued job must remain the only ROP batch.'
        );
    }
    
    
    /* =========================================================
EXCEPTION HANDLING
========================================================= */
    
    @IsTest
    static void returnsInternalErrorWhenBatchSubmissionFails() {
        
        Id contractId = getPolicyId();
        
        /*
* Arrange valid Funding before the ROP insert.
*/
        createAppliedFunding(
            contractId,
            125.50
        );
        
        /*
* The Contract must already be cancelled before ROP creation,
* in accordance with the current business rule.
*/
        prepareContractForRop(
            contractId
        );
        
        createPendingRop(
            contractId,
            125.50
        );
        
        List<ROPUtility.FlowResponse> responses;
        
        /*
* Use the deterministic @TestVisible seam exposed by
* ROPUtility rather than relying on asynchronous failure timing.
*/
        ROPUtility.forceBatchSubmissionFailure = true;
        
        try {
            
            Test.startTest();
            
            responses =
                ROPUtility.startRopAllocation(
                    new List<String>{
                        String.valueOf(contractId)
                            }
                );
            
            Test.stopTest();
            
        }
        finally {
            
            /*
* Always reset static test state so this test cannot influence
* anything that executes later in the same transaction.
*/
            ROPUtility.forceBatchSubmissionFailure = false;
        }
        
        assertResponse(
            responses,
            false,
            INTERNAL_ERROR_MESSAGE
        );
        
        System.assertEquals(
            1,
            countPendingRops(),
            'The ROP must remain pending when batch submission fails.'
        );
        
        System.assertEquals(
            0,
            countRopBatchJobs(),
            'No BatchRopAllocation job should be created when submission fails.'
        );
    }
    
    
    /* =========================================================
RESPONSE ASSERTION
========================================================= */
    
    private static void assertResponse(
        List<ROPUtility.FlowResponse> responses,
        Boolean expectedSuccess,
        String expectedMessage
    ) {
        
        System.assertNotEquals(
            null,
            responses,
            'ROPUtility must return a response collection.'
        );
        
        System.assertEquals(
            1,
            responses.size(),
            'ROPUtility must return exactly one FlowResponse.'
        );
        
        System.assertNotEquals(
            null,
            responses[0],
            'The FlowResponse must not be null.'
        );
        
        System.assertEquals(
            expectedSuccess,
            responses[0].isSuccess,
            'Unexpected ROPUtility success result.'
        );
        
        System.assertEquals(
            expectedMessage,
            responses[0].message,
            'Unexpected ROPUtility response message.'
        );
    }
    
    
    /* =========================================================
CONTRACT TEST DATA
========================================================= */
    
    private static Id getPolicyId() {
        
        return [
            SELECT Id
            FROM InsurancePolicy
            LIMIT 1
        ].Id;
    }
    
    /**
* Prepares the related Contract for ROP creation according to the
* current business rule:
*
* - Funding must already have been applied.
* - The Contract must already be Cancelled.
* - Cancel Code must not be "04 ROP REQUEST".
*
* This intentionally mirrors the valid Contract state established
* by the client-approved Cancel Contract process.
*/
    private static InsurancePolicy prepareContractForRop(
        Id contractId
    ) {
        InsurancePolicy contractToUpdate =
            new InsurancePolicy(
                Id = contractId,
                Status = UtilityClass.contractStatus_Cancelled,
                Cancel_Code__c = '02 NO PAY',
                CancellationReasonType = 'ALREADY HAD WARRANTY',
                Cancel_Reported_Date__c = Date.today(),
                Cancel_Effective_Date__c = Date.today(),
                Cancelled_By__c = UserInfo.getName()
            );
        
        update contractToUpdate;
        
        InsurancePolicy preparedContract = [
            SELECT Id,
            Status,
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
            'ROP test Contract must use the approved cancellation code.'
        );
        
        System.assertEquals(
            'ALREADY HAD WARRANTY',
            preparedContract.CancellationReasonType,
            'ROP test Contract must use the approved cancellation reason.'
        );
        
        return preparedContract;
    }
    
    /* =========================================================
ROP TEST DATA
========================================================= */
    
    private static ROP__c createPendingRop(
        Id contractId,
        Decimal calculatedAmount
    ) {
        
        /*
* Prevent trigger-side asynchronous orchestration while arranging
* the unit-test data.
*
* ROPUtility must be the only component responsible for submitting
* BatchRopAllocation in this test class.
*/
        ROPAllocationOrchestrator.disableBatchExecution = true;
        
        try {
            
            InsurancePolicy policy = [
                SELECT Id,
                Name
                FROM InsurancePolicy
                WHERE Id = :contractId
                LIMIT 1
            ];
            
            /*
* Funding and Contract cancellation are deliberately NOT performed
* inside this helper.
*
* Current business sequence:
*
* 1. Funding must be applied while the Contract is still fundable.
* 2. The Contract must then be cancelled through the valid
*    cancellation state.
* 3. Only after that may the ROP be created.
*
* Keeping those prerequisites outside this helper makes each test
* explicitly arrange the business state it requires and prevents this
* helper from hiding Contract lifecycle transitions.
*/
            ROP__c rop =
                TestDataFactory.createROP(false);
            
            rop.Contract__c =
                contractId;
            
            rop.Contract_Id_from_ROP__c =
                policy.Name;
            
            rop.ROP_Amount_Calculated__c =
                calculatedAmount;
            
            rop.Cancel_Fee__c =
                0;
            
            rop.Cancel_Date__c =
                Date.today();
            
            rop.Claims_Paid__c =
                0;
            
            rop.Legacy_ROP_Amount__c =
                calculatedAmount;
            
            rop.Dealer_Cost__c =
                calculatedAmount;
            
            insert rop;
            
            return [
                SELECT Id,
                Contract__c,
                ROP_Amount_Calculated__c,
                Time_Processed__c
                FROM ROP__c
                WHERE Id = :rop.Id
                LIMIT 1
            ];
            
        }
        finally {
            
            ROPAllocationOrchestrator.disableBatchExecution = false;
        }
    }
    
    
    /* =========================================================
FUNDING TEST DATA
========================================================= */
    
    /**
* Creates an already-processed Funding record before ROP creation.
*
* Time_Processed__c is intentionally populated because:
*
* 1. The Funding record represents Funding already applied to
*    the Contract.
*
* 2. It prevents BatchContractAllocation from treating this
*    Funding record as pending work during ROPUtility tests.
*/
    private static Funding__c createAppliedFunding(
        Id contractId,
        Decimal amount
    ) {
        
        Decimal fundingAmount =
            amount == null || amount <= 0
            ? 100
            : amount;
        
        Funding__c funding =
            new Funding__c(
                Contract__c = contractId,
                Funded_Amount__c = fundingAmount,
                Time_Processed__c = System.now()
            );
        
        populateRequiredPrimitiveFields(
            funding,
            null
        );
        
        insert funding;
        
        /*
* Keep the Contract's funded-total value synchronized.
*
* ROP validations/calculations can reference the Contract-level
* rollup before asynchronous or DLRS processing has completed
* during an Apex test.
*/
        InsurancePolicy policy = [
            SELECT Id,
            DLRS_Total_Funded_Amount_from_Funding__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];
        
        Decimal currentFundedTotal =
            policy.DLRS_Total_Funded_Amount_from_Funding__c == null
            ? 0
            : policy.DLRS_Total_Funded_Amount_from_Funding__c;
        
        policy.DLRS_Total_Funded_Amount_from_Funding__c =
            currentFundedTotal +
            fundingAmount;
        
        update policy;
        
        return funding;
    }
    
    
    /* =========================================================
QUERY HELPERS
========================================================= */
    
    private static Integer countPendingRops() {
        
        return [
            SELECT COUNT()
            FROM ROP__c
            WHERE Contract__c != null
            AND ROP_Amount_Calculated__c != null
            AND Time_Processed__c = null
        ];
    }
    
    
    private static List<AsyncApexJob> getRopBatchJobs() {
        
        return [
            SELECT Id,
            Status,
            JobType,
            ApexClass.Name
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
            ORDER BY CreatedDate ASC
        ];
    }
    
    
    private static Integer countRopBatchJobs() {
        
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
        ];
    }
    
    
    /* =========================================================
GENERIC REQUIRED FIELD SUPPORT
========================================================= */
    
    /**
* Adds safe defaults for required, createable primitive fields whose
* exact requirements can differ between Salesforce Industries orgs.
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