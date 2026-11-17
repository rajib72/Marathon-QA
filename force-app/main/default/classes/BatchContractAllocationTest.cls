/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-22-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest(SeeAllData=false)
public class BatchContractAllocationTest {

    /* =========================================================
       CONTRACT FIXTURE: populate everything before INSERT.
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
        // Client.AccountNumber is set to WUS by the calling test.
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

        // BatchContractAllocation is testing Funding/Allocation behavior,
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

    /* =========================================================
       ADDITIONAL DETERMINISTIC BATCH CONTROL FLOW TESTS.
       ========================================================= */

    @IsTest
    static void testConstructorsAndTargetIdValidation() {
        Id policyId = (Id)(
            InsurancePolicy.SObjectType.getDescribe().getKeyPrefix()
            + '000000000001'
        );

        BatchContractAllocation singleBatch =
            new BatchContractAllocation(
                BatchContractAllocation.SINGLE_MODE, policyId, 4, 3);
        System.assertEquals(true, singleBatch.isSingleMode);
        System.assertEquals(policyId, singleBatch.targetContract);
        System.assertEquals(4, singleBatch.previousRemainingCount);
        System.assertEquals(3, singleBatch.iterationCount);

        BatchContractAllocation eligibleBatch =
            new BatchContractAllocation(
                BatchContractAllocation.ELIGIBLE_MODE, null);
        System.assertEquals(false, eligibleBatch.isSingleMode);
        System.assertEquals(-1, eligibleBatch.previousRemainingCount);
        System.assertEquals(0, eligibleBatch.iterationCount);

        Boolean rejected = false;
        try {
            new BatchContractAllocation(
                BatchContractAllocation.SINGLE_MODE,
                UserInfo.getUserId());
        } catch (BatchContractAllocation.OtherException ex) {
            rejected = true;
            System.assert(ex.getMessage().contains('InsurancePolicy'));
        }
        System.assertEquals(true, rejected,
            'Single mode must reject a non-InsurancePolicy Id.');
    }

    @IsTest
    static void testEmptyScopeDoesNotCountAsProcessed() {
        BatchContractAllocation batch =
            new BatchContractAllocation(
                BatchContractAllocation.ELIGIBLE_MODE, null);
        Test.startTest();
        batch.execute(null, new List<InsurancePolicy>());
        Test.stopTest();
        System.assertEquals(0, batch.processedContractsCount);
    }

    @IsTest
    static void testExecuteSkipsContractWithNoPendingFunding() {
        // The current batch uses a stale-query guard: when another job has
        // already processed all Funding, a second job must do no allocation.
        Account client = TestDataFactory.createAccount(true);
        client.AccountNumber = 'WUS';
        update client;
        Account dealer = TestDataFactory.createDealerAccount(true);
        InsurancePolicy policy = createValidInsurancePolicy(client.Id, dealer.Id);

        System.assertEquals(0, [
            SELECT COUNT() FROM Funding__c
            WHERE Contract__c = :policy.Id AND Time_Processed__c = null
        ]);

        Integer allocationCountBefore = [
            SELECT COUNT() FROM Allocation__c WHERE Contract__c = :policy.Id
        ];
        BatchContractAllocation batch = new BatchContractAllocation(
            BatchContractAllocation.ELIGIBLE_MODE, null
        );
        Test.startTest();
        batch.execute(null, new List<InsurancePolicy>{ policy });
        Test.stopTest();

        System.assertEquals(0, batch.processedContractsCount,
            'An already-completed Contract must never count as newly processed.');
        System.assertEquals(allocationCountBefore, [
            SELECT COUNT() FROM Allocation__c WHERE Contract__c = :policy.Id
        ], 'A replay with no pending Funding must not create additional allocations.');
    }

    @IsTest
    static void testFinishDoesNotChainWithNoPendingFunding() {
        BatchContractAllocation batch =
            new BatchContractAllocation(
                BatchContractAllocation.ELIGIBLE_MODE, null);
        batch.processedContractsCount = 1;
        System.assertEquals(0,
            [SELECT COUNT() FROM Funding__c WHERE Time_Processed__c = null]);

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM AsyncApexJob
             WHERE ApexClass.Name = 'BatchContractAllocation']);
    }

    // One pending funding record is enough to drive finish() control paths.
    private static void createOnePendingFunding() {
        Account client = TestDataFactory.createAccount(true);
        client.AccountNumber = 'WUS';
        update client;

        Account dealer = TestDataFactory.createDealerAccount(true);
        InsurancePolicy contract = createValidInsurancePolicy(
            client.Id, dealer.Id);

        FundingAllocationOrchestrator.disableBatchExecution = true;
        Funding__c funding =
            TestDataFactory.createFunding(false, contract.Id);
        funding.Funded_Amount__c = 100;
        funding.Time_Processed__c = null;
        insert funding;

        System.assert(
            [SELECT COUNT() FROM Funding__c
             WHERE Time_Processed__c = null] > 0,
            'Test requires pending Funding.');
    }

    @IsTest
    static void testFinishDoesNotChainInSingleMode() {
        createOnePendingFunding();
        Id policyId = [SELECT Contract__c
                       FROM Funding__c LIMIT 1].Contract__c;
        BatchContractAllocation batch =
            new BatchContractAllocation(
                BatchContractAllocation.SINGLE_MODE, policyId);
        batch.processedContractsCount = 1;

        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM AsyncApexJob
             WHERE ApexClass.Name = 'BatchContractAllocation']);
    }

    @IsTest
    static void testFinishDoesNotChainWithoutProcessedContracts() {
        createOnePendingFunding();
        BatchContractAllocation batch =
            new BatchContractAllocation(
                BatchContractAllocation.ELIGIBLE_MODE, null);
        batch.processedContractsCount = 0;

        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM AsyncApexJob
             WHERE ApexClass.Name = 'BatchContractAllocation']);
    }

    @IsTest
    static void testFinishStopsWhenNoProgress() {
        createOnePendingFunding();
        Integer pending =
            [SELECT COUNT() FROM Funding__c
             WHERE Time_Processed__c = null];
        BatchContractAllocation batch =
            new BatchContractAllocation(
                BatchContractAllocation.ELIGIBLE_MODE,
                null, pending, 1);
        batch.processedContractsCount = 1;

        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM AsyncApexJob
             WHERE ApexClass.Name = 'BatchContractAllocation']);
    }

    @IsTest
    static void testFinishStopsAtMaxIterations() {
        createOnePendingFunding();
        BatchContractAllocation batch =
            new BatchContractAllocation(
                BatchContractAllocation.ELIGIBLE_MODE,
                null, -1,
                BatchContractAllocation.MAX_ITERATIONS);
        batch.processedContractsCount = 1;

        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM AsyncApexJob
             WHERE ApexClass.Name = 'BatchContractAllocation']);
    }

    @isTest
    public static void TestCase1_SINGLE_HaveExistingPriorityAllocation() {
        List<InsurancePolicy> policiesList = new List<InsurancePolicy>();
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS'; // Allowed client code under Sold_Contract_Validation.
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;    
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.DLRS_Total_Unprocessed_Funding__c = 10;
        policyRec1.SaleDate = System.Today();
        policyRec1.Vehicle_Mileage_at_Contract_Inception__c  = 1000;
        policyRec1.Vehicle_Year__c = '2023';
        policyRec1.Contract_Term_Months__c = 12;
        policyRec1.Legacy_Source__c = 'DSI';
        update policyRec1;
        
        Funding__c funding = TestDataFactory.createFunding(true,policyRec1.Id);
        funding.Funded_Amount__c = 1000;
        update funding;
        
        Test.startTest();
        BatchContractAllocation batch = new BatchContractAllocation(BatchContractAllocation.SINGLE_MODE, policyRec1.Id);
        Database.executeBatch(batch);
        Test.stopTest();
    }
    
    @isTest
    public static void TestCase1_SINGLE_HaveNoExistingPriorityAllocation() {
        List<InsurancePolicy> policiesList = new List<InsurancePolicy>();
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS'; // Allowed client code under Sold_Contract_Validation.
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;    
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.SaleDate = System.Today();
        policyRec1.Vehicle_Mileage_at_Contract_Inception__c  = 1000;
        policyRec1.Vehicle_Year__c = '2023';
        policyRec1.Legacy_Source__c = 'DSI';
        update policyRec1;
         
        List<Dealer_Cost_Allocation__c> allocations = new List<Dealer_Cost_Allocation__c>();
        
        Dealer_Cost_Allocation__c DCA1 = TestDataFactory.createDealerCostAllocation(false);
        DCA1.RatingRecordID__c = 'AAR230289';
        DCA1.AllocationCode__c = '1017';
        DCA1.Allocation_Amount__c = 10;
        allocations.add(DCA1);
        Dealer_Cost_Allocation__c DCA2 = TestDataFactory.createDealerCostAllocation(false);
        DCA2.RatingRecordID__c = 'AAR230289';
        DCA2.AllocationCode__c = '8001';
        DCA2.Allocation_Amount__c = 243.5;
        allocations.add(DCA2);
        
        insert allocations;
        List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        Allocation_Code__c all8001Code = TestDataFactory.createAllocationCode(false);
        all8001Code.Payee_Type__c = 'Company';
        Allocation_Code__c all1017Code = TestDataFactory.createAllocationCode(false);
        all1017Code.name = '1017';
        all1017Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8001Code);
        allocationCodes.add(all1017Code);
        Allocation_Code__c all8004Code = TestDataFactory.createAllocationCode(false);
        all8004Code.name = '8004';
        all8004Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8004Code);
        insert allocationCodes;
                
        Funding__c funding = TestDataFactory.createFunding(true,policyRec1.Id);
        funding.Funded_Amount__c = 1000;
        update funding;
        
        Test.startTest();
        BatchContractAllocation batch = new BatchContractAllocation(BatchContractAllocation.SINGLE_MODE, policyRec1.Id);
        Database.executeBatch(batch);
        Test.stopTest();
    }
    @isTest
    public static void TestCase1_SINGLE_HaveExistingNonPriorityAllocation() {
        List<InsurancePolicy> policiesList = new List<InsurancePolicy>();
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS'; // Allowed client code under Sold_Contract_Validation.
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;  
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.SaleDate = System.Today();
        policyRec1.Vehicle_Mileage_at_Contract_Inception__c  = 1000;
        policyRec1.Vehicle_Year__c = '2023';
        policyRec1.Legacy_Source__c = 'DSI';
        update policyRec1; 
        
        List<Dealer_Cost_Allocation__c> allocations = new List<Dealer_Cost_Allocation__c>();
        
        Dealer_Cost_Allocation__c DCA1 = TestDataFactory.createDealerCostAllocation(false);
        DCA1.RatingRecordID__c = 'AAR230289';
        DCA1.AllocationCode__c = '1017';
        DCA1.Allocation_Amount__c = 10;
        allocations.add(DCA1);
        Dealer_Cost_Allocation__c DCA2 = TestDataFactory.createDealerCostAllocation(false);
        DCA2.RatingRecordID__c = 'AAR230289';
        DCA2.AllocationCode__c = '8001';
        DCA2.Allocation_Amount__c = 243.5;
        allocations.add(DCA2);
        
        insert allocations;
        List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        Allocation_Code__c all8001Code = TestDataFactory.createAllocationCode(false);
        all8001Code.Payee_Type__c = 'Company';
        Allocation_Code__c all1017Code = TestDataFactory.createAllocationCode(false);
        all1017Code.name = '1017';
        all1017Code.Payee_Type__c = 'Company';
        Allocation_Code__c all8004Code = TestDataFactory.createAllocationCode(false);
        all8004Code.name = '8004';
        all8004Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8004Code);
        allocationCodes.add(all8001Code);
        allocationCodes.add(all1017Code);
        
        insert allocationCodes;
        
        Allocation__c all1017 = TestDataFactory.createAllocation(false, policyRec1.Id, all1017Code.Id);
        all1017.Allocation_Amount__c = 3;
        insert all1017;  
        
        Funding__c funding = TestDataFactory.createFunding(true,policyRec1.Id);
        funding.Funded_Amount__c = 1000;
        update funding;
        
        Test.startTest();
        BatchContractAllocation batch = new BatchContractAllocation(BatchContractAllocation.SINGLE_MODE, policyRec1.Id);
        Database.executeBatch(batch);
        Test.stopTest();
    }
    @isTest
    public static void TestCase1_SINGLE_HaveExistingNonPriorityUnderFundedAllocation() {
        List<InsurancePolicy> policiesList = new List<InsurancePolicy>();
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS'; // Allowed client code under Sold_Contract_Validation.
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;    
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.SaleDate = System.Today();
        policyRec1.Vehicle_Mileage_at_Contract_Inception__c  = 1000;
        policyRec1.Vehicle_Year__c = '2023';
        policyRec1.Product__c = 'NonSecure';
        update policyRec1;
        
        List<Dealer_Cost_Allocation__c> allocations = new List<Dealer_Cost_Allocation__c>();
        
        Dealer_Cost_Allocation__c DCA1 = TestDataFactory.createDealerCostAllocation(false);
        DCA1.RatingRecordID__c = 'AAR230289';
        DCA1.AllocationCode__c = '1017';
        DCA1.Allocation_Amount__c = 790;
        allocations.add(DCA1);
        Dealer_Cost_Allocation__c DCA2 = TestDataFactory.createDealerCostAllocation(false);
        DCA2.RatingRecordID__c = 'AAR230289';
        DCA2.AllocationCode__c = '8001';
        DCA2.Allocation_Amount__c = 243.5;
        allocations.add(DCA2);
        
        insert allocations;
        List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        Allocation_Code__c all8001Code = TestDataFactory.createAllocationCode(false);
        all8001Code.Payee_Type__c = 'Company';
        Allocation_Code__c all1017Code = TestDataFactory.createAllocationCode(false);
        all1017Code.name = '1017';
        all1017Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8001Code);
        allocationCodes.add(all1017Code);
        Allocation_Code__c all8004Code = TestDataFactory.createAllocationCode(false);
        all8004Code.name = '8004';
        all8004Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8004Code);
        insert allocationCodes;
        
        Allocation__c all1017 = TestDataFactory.createAllocation(false, policyRec1.Id, all1017Code.Id);
        all1017.Allocation_Amount__c = 3;
        insert all1017;
        
        Allocation__c all8004 = TestDataFactory.createAllocation(false, policyRec1.Id, all8004Code.Id);
        all8004.Contract__c = policyRec1.Id;
        all8004.Allocation_Amount__c = 100;
        all8004.Payment_Return__c = 'P';
        all8004.Allocation_Code__c = all8004Code.Id;
        insert all8004;
         
        Funding__c funding = TestDataFactory.createFunding(true,policyRec1.Id);
        funding.Funded_Amount__c = 246.5;
        update funding;
        
        Test.startTest();
       
        BatchContractAllocation batch = new BatchContractAllocation(BatchContractAllocation.SINGLE_MODE, policyRec1.Id);
        Database.executeBatch(batch);
        Test.stopTest();
    }
    @isTest
    public static void TestCase1_Eligible_HaveExistingNonPriorityUnderFundedAllocation() {
        List<InsurancePolicy> policiesList = new List<InsurancePolicy>();
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS'; // Allowed client code under Sold_Contract_Validation.
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        Id recordTypeId = Schema.SObjectType.InsurancePolicy.getRecordTypeInfosByDeveloperName().get('Auto_Warranty').getRecordTypeId();
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;    
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.SaleDate = System.Today();
        policyRec1.Vehicle_Mileage_at_Contract_Inception__c  = 1000;
        policyRec1.Vehicle_Year__c = '2023';
        policyRec1.RecordTypeId = recordTypeId;
        policyRec1.Legacy_Source__c = 'DSI';
        update policyRec1;  
        
        List<Dealer_Cost_Allocation__c> allocations = new List<Dealer_Cost_Allocation__c>();
        
        Dealer_Cost_Allocation__c DCA1 = TestDataFactory.createDealerCostAllocation(false);
        DCA1.RatingRecordID__c = 'AAR230289';
        DCA1.AllocationCode__c = '1017';
        DCA1.Allocation_Amount__c = 790;
        allocations.add(DCA1);
        Dealer_Cost_Allocation__c DCA2 = TestDataFactory.createDealerCostAllocation(false);
        DCA2.RatingRecordID__c = 'AAR230289';
        DCA2.AllocationCode__c = '8001';
        DCA2.Allocation_Amount__c = 243.5;
        allocations.add(DCA2);
        
        insert allocations;
        List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        Allocation_Code__c all8001Code = TestDataFactory.createAllocationCode(false);
        all8001Code.Payee_Type__c = 'Company';
        Allocation_Code__c all1017Code = TestDataFactory.createAllocationCode(false);
        all1017Code.name = '1017';
        //all1017Code.Payee_Type__c = '02 - INSPECTION';
        all1017Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8001Code);
        allocationCodes.add(all1017Code);
        Allocation_Code__c all8004Code = TestDataFactory.createAllocationCode(false);
        all8004Code.name = '8004';
        //all8004Code.Payee_Type__c = '02 - INSPECTION';
        all8004Code.Payee_Type__c = 'Company';
        allocationCodes.add(all8004Code);
        insert allocationCodes;
        
        Allocation__c all1017 = TestDataFactory.createAllocation(false, policyRec1.Id, all1017Code.Id);
        all1017.Allocation_Amount__c = 3;
        insert all1017;
            
        Funding__c funding = TestDataFactory.createFunding(true,policyRec1.Id);
        funding.Funded_Amount__c = 246.5;
        update funding;
        
        Test.startTest();
        BatchContractAllocation batch = new BatchContractAllocation(
            BatchContractAllocation.ELIGIBLE_MODE,
            null,
            -1,
            BatchContractAllocation.MAX_ITERATIONS
        ); // No self-chaining at Test.stopTest().
        Database.executeBatch(batch);
        Test.stopTest();
        
    }

    // //
    
    @IsTest
    public static void testCalculateMaxAllocation() {
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS';
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        InsurancePolicy policyRec1 = createValidInsurancePolicy(
            clientAccount.Id, programcodeAccount.Id
        );
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.Reserve__c = 1000;
        policyRec1.SaleDate = System.today();
        policyRec1.Legacy_Source__c = 'DSI';
        update policyRec1;

        List<Allocation_Code__c> allocationCodes = new List<Allocation_Code__c>();
        Allocation_Code__c numericCode = new Allocation_Code__c(
            Name = '1017', Allocation_Amount__c = '200.50', Payee_Type__c = 'Company'
        );
        Allocation_Code__c reserveByDescriptorCode = new Allocation_Code__c(
            Name = '8001', Allocation_Amount__c = 'Premium Tax',
            Descriptor__c = 'Premium Tax', Payee_Type__c = 'Company'
        );
        Allocation_Code__c supplementalCode = new Allocation_Code__c(
            Name = '8004', Allocation_Amount__c = 'S12', Payee_Type__c = 'Company'
        );
        Allocation_Code__c formulaCode = new Allocation_Code__c(
            Name = '8005', Allocation_Amount__c = '{!Reserve__c} + 100',
            Payee_Type__c = 'Company'
        );
        allocationCodes.add(numericCode);
        allocationCodes.add(reserveByDescriptorCode);
        allocationCodes.add(supplementalCode);
        allocationCodes.add(formulaCode);
        insert allocationCodes;

        // These two records are only supplied to the public method; no DML needed.
        Allocation_Code__c malformedCode = new Allocation_Code__c(
            Name = 'AAA1', Allocation_Amount__c = 'Invalid Formula',
            Payee_Type__c = 'Company'
        );
        Allocation_Code__c nullAmountCode = new Allocation_Code__c(Name = 'Null');

        Test.startTest();
        Decimal numericResult = ContractAllocationUtilityCtrl.calculateMaxAllocation(
            policyRec1, numericCode
        );
        Decimal descriptorResult = ContractAllocationUtilityCtrl.calculateMaxAllocation(
            policyRec1, reserveByDescriptorCode
        );
        Decimal supplementalResult = ContractAllocationUtilityCtrl.calculateMaxAllocation(
            policyRec1, supplementalCode
        );
        Decimal formulaResult = ContractAllocationUtilityCtrl.calculateMaxAllocation(
            policyRec1, formulaCode
        );

        // With the new financial error propagation, malformed formulas MUST throw.
        // Previously this test expected the method to quietly return zero.
        Boolean malformedFormulaRejected = false;
        try {
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policyRec1, malformedCode
            );
        } catch (Exception ex) {
            malformedFormulaRejected = true;
            System.assert(
                String.isNotBlank(ex.getMessage()),
                'A malformed allocation formula must expose a diagnostic exception.'
            );
        }
        Decimal nullResult = ContractAllocationUtilityCtrl.calculateMaxAllocation(
            policyRec1, nullAmountCode
        );
        Test.stopTest();

        System.assertEquals(Decimal.valueOf('200.50'), numericResult);
        System.assertEquals(Decimal.valueOf('1000'), descriptorResult);
        System.assertEquals(Decimal.valueOf('0'), supplementalResult);
        System.assertEquals(Decimal.valueOf('1100'), formulaResult);
        System.assert(malformedFormulaRejected,
            'Malformed formulas must be rejected, not treated as a zero allocation.');
        System.assertEquals(Decimal.valueOf('0'), nullResult);
    }

    @IsTest
    public static void testCatchBlock() {
        Test.startTest();
        // Null collections are a programmer error. The current utility correctly
        // propagates a NullPointerException to its transaction-level caller.
        Boolean nullInputRejected = false;
        try {
            ContractAllocationUtilityCtrl.assignAllocationtoContract(null);
        } catch (System.NullPointerException ex) {
            nullInputRejected = true;
        }
        System.assert(nullInputRejected,
            'assignAllocationtoContract(null) must not silently succeed.');

        // Empty collections are the supported no-work input to these entry points.
        // The tests below must finish without errors or creating allocations.
        ContractAllocationUtilityCtrl.splitContractsByClient(
            new List<InsurancePolicy>()
        );
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>()
        );
        Test.stopTest();
    }

    @isTest
    public static void testGetSupplementalValue() {
        List<InsurancePolicy> policiesList = new List<InsurancePolicy>();
        Account clientAccount = TestDataFactory.createAccount(true);
        clientAccount.AccountNumber = 'WUS'; // Allowed client code under Sold_Contract_Validation.
        update clientAccount;
        Account programcodeAccount = TestDataFactory.createDealerAccount(true);
        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';
        update programcodeAccount;
        InsurancePolicy policyRec1 = createValidInsurancePolicy(clientAccount.Id, programcodeAccount.Id);
        policyRec1.Client__c = clientAccount.Id;
        policyRec1.Lien_Holder__c = programcodeAccount.Id;    
        policyRec1.Program_Code__c = 'MDMD';
        policyRec1.DLRS_Total_Unprocessed_Funding__c = 10;
        policyRec1.SaleDate = System.Today();
        policyRec1.Premium_Tax_Old__c = 100.00; 
        policyRec1.MBI_Seller_Commission__c = 500.75;
        update policyRec1;
        
        List<String> descriptors = new List<String>{'Premium Tax', 'Seller Commission'};
            for (String descriptor : descriptors) {
             Decimal result = ContractAllocationUtilityCtrl.getSupplementalValue(policyRec1, null, descriptor);
             
             if (descriptor == 'Premium Tax') {
                System.assertEquals(100.00, result, 'Expected value for Premium Tax');
            } else if (descriptor == 'Seller Commission') {
                System.assertEquals(500.75, result, 'Expected value for Seller Commission');   
            }
         }
        try {
            Test.startTest(); 
            InsurancePolicy policy = null;
            String resultName = 'SomeResult';
            String descriptor = 'Premium Tax';
            Decimal result = ContractAllocationUtilityCtrl.getSupplementalValue(policy, resultName, descriptor);
            Test.stopTest(); 
            
        } catch (Exception e) {
            System.assert(!String.isBlank(e.getMessage()), 'If null input is rejected, the error must be descriptive.'); 
        }
   }   
}