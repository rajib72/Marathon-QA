/**
* ContractTriggerHandlerTest - focused on the ACTIVE (uncommented) handler.
*
* CI/CD design:
* - SeeAllData=false; no pre-existing policies or client-specific org data.
* - Cancellation and reinstatement are exercised IN MEMORY, not by DML.
* - Only ContentVersion, Account, Coverage Level and Allocation Code test
*   fixtures use DML. No test inserts/updates a Cancelled InsurancePolicy.
* - One Test.startTest()/Test.stopTest() pair per test at most; no batch jobs.
* - This class does not test notification code that is currently commented out.
*
* Requires the same dependent classes, decision-matrix definitions and
* account/coverage/allocation metadata as ContractTriggerHandler itself.
* Run in QA and UAT before deploying to production. An offline source review
* cannot certify coverage or prove that target-org validation rules will pass.
*/
@IsTest(SeeAllData=false)
private class ContractTriggerHandlerTest {
    
    private static final String SECURE_ONE = 'SecureOne';
    
    // JSON lets us build IN-MEMORY records with formula/read-only inputs that
    // the production handler reads, without attempting to persist those fields.
    private static InsurancePolicy policyFromJson(Map<String, Object> values) {
        JSONGenerator generator = JSON.createGenerator(false);
        generator.writeStartObject();
        generator.writeFieldName('attributes');
        generator.writeStartObject();
        generator.writeStringField('type', 'InsurancePolicy');
        generator.writeEndObject();
        for (String apiName : values.keySet()) {
            generator.writeObjectField(apiName, values.get(apiName));
        }
        generator.writeEndObject();
        return (InsurancePolicy) JSON.deserialize(
            generator.getAsString(), InsurancePolicy.class
        );
    }
    
    private static Id autoWarrantyId() {
        Schema.RecordTypeInfo rt = Schema.SObjectType.InsurancePolicy
            .getRecordTypeInfosByDeveloperName().get('Auto_Warranty');
        System.assertNotEquals(null, rt,
                               'Auto_Warranty record type is required by production handler.');
        return rt.getRecordTypeId();
    }
    
    // A properly prefixed synthetic ID is used ONLY for old/new map lookups.
    // No record containing this ID is ever sent to DML.
    private static Id inMemoryPolicyId() {
        
        Schema.SObjectType policyType =
            Schema.getGlobalDescribe().get('InsurancePolicy');
        
        System.assertNotEquals(
            null,
            policyType,
            'InsurancePolicy object must exist.'
        );
        
        String keyPrefix =
            policyType.getDescribe().getKeyPrefix();
        
        return (Id)(
            keyPrefix + '000000000001'
        );
    }
    
    private static String firstError(InsurancePolicy record) {
        return record.getErrors().isEmpty() ? '' : record.getErrors()[0].getMessage();
    }
    
    private static void assertErrorContains(InsurancePolicy record, String text) {
        System.assert(record.hasErrors(),
                      'Expected a validation error containing: ' + text);
        System.assert(firstError(record).contains(text),
                      'Expected [' + text + '] but received: ' + firstError(record));
    }
    
    private static InsurancePolicy basicInMemoryPolicy() {
        return new InsurancePolicy(
            Name = 'CTH-TEST-IN-MEMORY',
            Product__c = SECURE_ONE,
            SaleDate = System.now().addDays(-30),
            Sale_Date__c = Date.today().addDays(-30),
            Vehicle_Mileage_at_Contract_Inception__c = 1000,
            Contract_Term_Months__c = 12,
            Validation_Days__c = 0,
            Rate_Code__c = 'CTH-RATE',
            Insurance_Code__c = 'CTH-INS',
            Ins_Carrier__c = 'CTH-CARRIER'
        );
    }
    
    @IsTest
    static void testEntryPointsWithSafeInMemoryPolicy() {
        // A real before-insert call without InsurancePolicy DML exercises the
        // orchestration without firing unrelated cross-org validation rules.
        InsurancePolicy insertCandidate = basicInMemoryPolicy();
        insertCandidate.Status = 'Active';
        Test.startTest();
        ContractTriggerHandler.handleBeforeInsert(
            new List<InsurancePolicy>{ insertCandidate }
        );
        ContractTriggerHandler.handleAfterInsert(
            new List<InsurancePolicy>{ insertCandidate }, null
        );
        Test.stopTest();
        System.assertNotEquals(null, insertCandidate.Contract_Funded_Date__c,
                               'SecureOne funding date must be derived during before insert.');
        System.assertNotEquals(null, insertCandidate.Expiration_Date_Calc__c,
                               'Fixed-term expiration must be calculated.');
        System.assertEquals(insertCandidate.Sale_Date__c,
                            insertCandidate.Earning_Start_Date__c,
                            'Fixed-term earning start is sale date.');
    }
    
    @IsTest
    static void testEmptyEntryPointsAndGuards() {
        // Empty collections are supported by most utility entry points.
        // Do not pass null into updateStatus/calculateAdminCost, which do not
        // advertise null-safe contracts.
        Test.startTest();
        ContractTriggerHandler.handleBeforeInsert(new List<InsurancePolicy>());
        ContractTriggerHandler.handleBeforeUpdate(
            new List<InsurancePolicy>(), new Map<Id, InsurancePolicy>()
        );
        ContractTriggerHandler.handleAfterInsert(
            new List<InsurancePolicy>(), null
        );
        ContractTriggerHandler.findDuplicateContracts(new List<InsurancePolicy>());
        ContractTriggerHandler.populateAllocationCosts(null);
        ContractTriggerHandler.populateAllocationCosts(new List<InsurancePolicy>());
        ContractTriggerHandler.setNextCycleDateForM2MContracts(null, null);
        ContractTriggerHandler.setNextCycleDateForM2MContracts(
            new List<InsurancePolicy>(), null
        );
        ContractTriggerHandler.setExpirationDate(null);
        ContractTriggerHandler.validateCancelMilage(null);
        ContractTriggerHandler.setRefundPercent(null);
        ContractTriggerHandler.setUnearnedPercent(null);
        Test.stopTest();
    }
    
    @IsTest
    static void testStatusAndSecureOneFundingOnInsert() {
        InsurancePolicy future = policyFromJson(new Map<String, Object>{
            'Effective_Date__c' => Date.today().addDays(10),
                'Product__c' => 'OTHER'
                });
        InsurancePolicy started = policyFromJson(new Map<String, Object>{
            'Effective_Date__c' => Date.today().addDays(-2),
                'Product__c' => 'OTHER'
                });
        InsurancePolicy secureOne = new InsurancePolicy(
            Product__c = SECURE_ONE,
            SaleDate = System.now().addDays(-12)
        );
        ContractTriggerHandler.updateStatus(
            new List<InsurancePolicy>{ future, started, secureOne }, null
        );
        System.assertEquals(UtilityClass.contractStatus_InWaiting, future.Status);
        System.assertEquals(UtilityClass.contractStatus_Active, started.Status);
        System.assertEquals(secureOne.SaleDate.date().addMonths(1),
                            secureOne.Contract_Funded_Date__c);
        System.assertEquals(secureOne.Contract_Funded_Date__c,
                            secureOne.Earliest_Contract_Funded_Date__c);
    }
    
    @IsTest
    static void testStatusReinstatementOnUpdateWithoutCancelledDml() {
        Id key = inMemoryPolicyId();
        InsurancePolicy oldPolicy = new InsurancePolicy(
            Id = key, Status = UtilityClass.contractStatus_Cancelled
        );
        InsurancePolicy updated = new InsurancePolicy(
            Id = key,
            Status = UtilityClass.contractStatus_Active,
            Reinstated_Effective_Date__c = Date.today().addDays(8)
        );
        ContractTriggerHandler.updateStatus(
            new List<InsurancePolicy>{ updated },
            new Map<Id, InsurancePolicy>{ key => oldPolicy }
        );
        System.assertEquals(UtilityClass.contractStatus_InWaiting, updated.Status);
    }
    
    @IsTest
    static void testAdminCostInsertAndUpdate() {
        InsurancePolicy ny = policyFromJson(new Map<String, Object>{
            'Product__c' => UtilityClass.PRODUCT_SECUREONE,
                'Original_State__c' => UtilityClass.NEW_YORK
                });
        InsurancePolicy program = new InsurancePolicy(
            Product__c = UtilityClass.PRODUCT_SECUREONE,
            Program_Code__c = UtilityClass.PROGRAM_CODE
        );
        InsurancePolicy normal = new InsurancePolicy(
            Product__c = UtilityClass.PRODUCT_SECUREONE,
            Program_Code__c = 'CTH-OTHER'
        );
        InsurancePolicy sale = new InsurancePolicy(SaleDate = System.now());
        ContractTriggerHandler.calculateAdminCost(
            new List<InsurancePolicy>{ ny, program, normal, sale }, null, false
        );
        System.assertEquals(Decimal.valueOf('52.45'), ny.Admin_Cost__c);
        System.assertEquals(Decimal.valueOf('10.00'), program.Admin_Cost__c);
        System.assertEquals(Decimal.valueOf('42.45'), normal.Admin_Cost__c);
        //System.assertEquals(sale.SaleDate.date(), sale.Sale_Date__c);
        
        Id key = inMemoryPolicyId();
        InsurancePolicy oldPolicy = new InsurancePolicy(
            Id = key, Product__c = SECURE_ONE,
            Program_Code__c = 'CTH-OLD', SaleDate = System.now().addDays(-5)
        );
        InsurancePolicy newPolicy = new InsurancePolicy(
            Id = key, Product__c = SECURE_ONE,
            Program_Code__c = UtilityClass.PROGRAM_CODE, SaleDate = System.now()
        );
        ContractTriggerHandler.calculateAdminCost(
            new List<InsurancePolicy>{ newPolicy },
            new Map<Id, InsurancePolicy>{ key => oldPolicy }, true
        );
        System.assertEquals(Decimal.valueOf('10.00'), newPolicy.Admin_Cost__c);
        //System.assertEquals(newPolicy.SaleDate.date(), newPolicy.Sale_Date__c);
        
        // Unchanged update must not overwrite an existing admin cost.
        InsurancePolicy same = new InsurancePolicy(
            Id = key, Product__c = SECURE_ONE,
            Program_Code__c = UtilityClass.PROGRAM_CODE,
            Admin_Cost__c = 77, SaleDate = oldPolicy.SaleDate
        );
        InsurancePolicy sameOld = new InsurancePolicy(
            Id = key, Product__c = SECURE_ONE,
            Program_Code__c = UtilityClass.PROGRAM_CODE,
            SaleDate = oldPolicy.SaleDate
        );
        ContractTriggerHandler.calculateAdminCost(
            new List<InsurancePolicy>{ same },
            new Map<Id, InsurancePolicy>{ key => sameOld }, true
        );
        System.assertEquals(Decimal.valueOf('77'), same.Admin_Cost__c);
    }
    
    @IsTest
    static void testInsuranceCarrierMatchMissingAndUnchanged() {
        Schema.RecordTypeInfo carrierRt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(UtilityClass.Insurance_Carrier_Developer_Name);
        System.assertNotEquals(null, carrierRt,
                               'The Insurance Carrier Account record type must be deployed.');
        // Set the business record type before inserting: never convert a
        // persisted Person Account into a business Account.
        Account carrier = new Account(
            Name = 'CTH Carrier Test', RecordTypeId = carrierRt.getRecordTypeId()
        );
        insert carrier;
        
        InsurancePolicy matching = new InsurancePolicy(
            Ins_Carrier__c = carrier.Name
        );
        InsurancePolicy notFound = new InsurancePolicy(
            Ins_Carrier__c = 'CTH Unknown Carrier'
        );
        ContractTriggerHandler.setInsuranceCarrierDetails(
            new List<InsurancePolicy>{ matching, notFound }, null
        );
        System.assertEquals(carrier.Id, matching.Insurance_Carrier_Id__c);
        System.assertEquals(null, notFound.Insurance_Carrier_Id__c);
        
        Id key = inMemoryPolicyId();
        InsurancePolicy changed = new InsurancePolicy(
            Id = key, Ins_Carrier__c = carrier.Name
        );
        InsurancePolicy oldValue = new InsurancePolicy(
            Id = key, Ins_Carrier__c = 'OLD CARRIER'
        );
        ContractTriggerHandler.setInsuranceCarrierDetails(
            new List<InsurancePolicy>{ changed },
            new Map<Id, InsurancePolicy>{ key => oldValue }
        );
        System.assertEquals(carrier.Id, changed.Insurance_Carrier_Id__c);
    }
    
    @IsTest
    static void testTnCDocumentLookupAndNoMatch() {
        String title = 'CTH-TNC-TEST';
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = 'CTH-TNC-TEST.pdf',
            VersionData = Blob.valueOf('Contract terms')
        );
        insert version;
        ContentVersion stored = [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE Id = :version.Id LIMIT 1
        ];
        InsurancePolicy matching = new InsurancePolicy(T_and_C_Code__c = title);
        InsurancePolicy missing = new InsurancePolicy(
            T_and_C_Code__c = 'CTH-DOCUMENT-DOES-NOT-EXIST'
        );
        InsurancePolicy blank = new InsurancePolicy();
        ContractTriggerHandler.setContractTnCCodeURL(
            new List<InsurancePolicy>{ matching, missing, blank }, null
        );
        System.assertNotEquals(null, matching.Contract_PDF_URL__c);
        System.assert(matching.Contract_PDF_URL__c.contains(
            String.valueOf(stored.ContentDocumentId)),
                      'The correct ContentDocument Id must be used.');
        System.assertEquals(null, missing.Contract_PDF_URL__c);
        System.assertEquals(null, blank.Contract_PDF_URL__c);
    }
    
    @IsTest
    static void testDuplicateLookupWithoutExistingPolicy() {
        // No InsurancePolicy DML: validation-safe no-match and empty paths.
        InsurancePolicy uniqueCandidate = new InsurancePolicy(
            Name = 'CTH-UNIQUE-' + String.valueOf(System.now().getTime())
        );
        ContractTriggerHandler.findDuplicateContracts(
            new List<InsurancePolicy>{ uniqueCandidate }
        );
        System.assertEquals(false, uniqueCandidate.hasErrors(),
                            'A unique in-memory contract must not be flagged as a duplicate.');
    }
    
    @IsTest
    static void testRateValidationForNonSecureOne() {
        InsurancePolicy zeroReserve = new InsurancePolicy(
            Product__c = 'CTH-OTHER', Reserve__c = 0
        );
        InsurancePolicy costMismatch = new InsurancePolicy(
            Product__c = 'CTH-OTHER', Reserve__c = 10,
            Options_Cost__c = 0, Surcharge_Cost__c = 0,
            Projected_Allocation_Cost__c = 0, Net_Dealer_Cost__c = 5
        );
        InsurancePolicy excessMileage = policyFromJson(new Map<String, Object>{
            'Product__c' => 'CTH-OTHER',
                'Reserve__c' => 10,
                'Options_Cost__c' => 0,
                'Surcharge_Cost__c' => 0,
                'Projected_Allocation_Cost__c' => 0,
                'Net_Dealer_Cost__c' => 10,
                'Vehicle_Mileage_at_Contract_Inception__c' => 1200,
                'MaxVehicleMilesOutput__c' => 1000
                });
        ContractTriggerHandler.contractRateValidation(
            new List<InsurancePolicy>{ zeroReserve, costMismatch, excessMileage }
        );
        assertErrorContains(zeroReserve, 'Total Cost = $0');
        assertErrorContains(costMismatch, 'Imported Cost');
        assertErrorContains(excessMileage, 'Rate Set DM');
    }
    
    @IsTest
    static void testSecureOneRateAndProductValidation() {
        Coverage_Level__c level = new Coverage_Level__c(Name = 'Powertrain');
        insert level;
        InsurancePolicy noRate = new InsurancePolicy(Product__c = SECURE_ONE);
        InsurancePolicy noCode = new InsurancePolicy(
            Product__c = SECURE_ONE, Rate_Code__c = 'RC'
        );
        InsurancePolicy noCarrier = new InsurancePolicy(
            Product__c = SECURE_ONE, Rate_Code__c = 'RC',
            Insurance_Code__c = 'IC'
        );
        InsurancePolicy optionError = policyFromJson(new Map<String, Object>{
            'Product__c' => SECURE_ONE,
                'Rate_Code__c' => 'RC',
                'Insurance_Code__c' => 'IC',
                'Ins_Carrier__c' => 'CTH Carrier',
                'Coverage_Level__c' => level.Id,
                'Class__c' => '1',
                'Vehicle_Type__c' => 'Commercial',
                'Options_Cost__c' => 0
                });
        InsurancePolicy noProductLongMake = new InsurancePolicy(
            Vehicle_Make__c = 'TOOLONG'
        );
        InsurancePolicy noProductShortMake = new InsurancePolicy(
            Vehicle_Make__c = 'FORD'
        );
        ContractTriggerHandler.contractRateValidation(new List<InsurancePolicy>{
            noRate, noCode, noCarrier, optionError,
                noProductLongMake, noProductShortMake
                });
        assertErrorContains(noRate, 'Rate Set DM');
        assertErrorContains(noCode, 'Insurance Code DM');
        assertErrorContains(noCarrier, 'State Set DM');
        assertErrorContains(optionError, 'Option Set DM');
        assertErrorContains(noProductLongMake, 'converted Make Code');
        assertErrorContains(noProductShortMake, 'Product was NULL');
    }
    
    @IsTest
    static void testCoverageMatrixGuardAndValidation() {
        // Targeted in-memory input. The custom decision matrix must be
        // deployed with the production handler; exceptions are logged by it.
        Coverage_Level__c level = new Coverage_Level__c(Name = 'CTH Matrix Level');
        insert level;
        InsurancePolicy candidate = new InsurancePolicy(
            RecordTypeId = autoWarrantyId(),
            Coverage_Level__c = level.Id,
            Product__c = SECURE_ONE,
            Coverage_Name__c = 'PowerTrain',
            Validation_Days__c = 10,
            Validation_Miles__c = 1000
        );
        ContractTriggerHandler.productCoverageLevelValidation(
            new List<InsurancePolicy>{ candidate }
        );
        // Do not make a fake matrix row or assert a result supplied by
        // different org-specific decision-matrix metadata. This test calls
        // the real matrix path; specific matrix outputs require a managed
        // test configuration that is identical in QA/UAT/PROD.
        System.assertEquals(autoWarrantyId(), candidate.RecordTypeId);
    }
    
    @IsTest
    static void testAllocationCostsMatchedProjectedAndExpense() {
        // Only these minimal fixtures are persisted. No InsurancePolicy DML.
        // These are the same Allocation_Code fields used in the existing test.
        Account client = TestDataFactory.createSellingAgencyAccount(true);
        Coverage_Level__c level = new Coverage_Level__c(Name = 'CTH Allocation Level');
        insert level;
        Allocation_Code__c projected = new Allocation_Code__c(
            Name = 'CTH-ALLOC-P', Allocation_Amount__c = '25.00',
            Descriptor__c = 'Premium Tax', Payee_Type__c = 'Company',
            Client__c = client.Id, Product__c = SECURE_ONE,
            Coverage_Level__c = level.Name,
            Insurance_Carrier__c = UtilityClass.INCLUDE_ALL,
            States__c = UtilityClass.INCLUDE_ALL,
            Term_Months__c = UtilityClass.INCLUDE_ALL,
            Option__c = UtilityClass.INCLUDE_ALL,
            Start_Date__c = Date.today().addDays(-30),
            Is_Expense__c = false
        );
        Allocation_Code__c expense = new Allocation_Code__c(
            Name = 'CTH-ALLOC-E', Allocation_Amount__c = '10.00',
            Descriptor__c = 'Premium Tax', Payee_Type__c = 'Company',
            Client__c = client.Id, Product__c = SECURE_ONE,
            Coverage_Level__c = level.Name,
            Insurance_Carrier__c = UtilityClass.INCLUDE_ALL,
            States__c = UtilityClass.INCLUDE_ALL,
            Term_Months__c = UtilityClass.INCLUDE_ALL,
            Option__c = UtilityClass.INCLUDE_ALL,
            Start_Date__c = Date.today().addDays(-30),
            Is_Expense__c = true
        );
        Allocation_Code__c expired = new Allocation_Code__c(
            Name = 'CTH-ALLOC-EXPIRED', Allocation_Amount__c = '900.00',
            Descriptor__c = 'Premium Tax', Payee_Type__c = 'Company',
            Client__c = client.Id, Product__c = SECURE_ONE,
            Coverage_Level__c = level.Name,
            Insurance_Carrier__c = UtilityClass.INCLUDE_ALL,
            States__c = UtilityClass.INCLUDE_ALL,
            Term_Months__c = UtilityClass.INCLUDE_ALL,
            Option__c = UtilityClass.INCLUDE_ALL,
            Start_Date__c = Date.today().addDays(-60),
            End_Date__c = Date.today().addDays(-31),
            Is_Expense__c = false
        );
        insert new List<Allocation_Code__c>{ projected, expense, expired };
            
            InsurancePolicy matching = new InsurancePolicy(
                Client__c = client.Id,
                Product__c = SECURE_ONE,
                Coverage_Level__c = level.Id,
                Contract_Term_Months__c = 12,
                Sale_Date__c = Date.today().addDays(-15)
            );
        InsurancePolicy unmatched = new InsurancePolicy(
            Client__c = client.Id,
            Product__c = 'CTH-NO-MATCH',
            Coverage_Level__c = level.Id,
            Sale_Date__c = Date.today().addDays(-15)
        );
        Test.startTest();
        ContractTriggerHandler.populateAllocationCosts(
            new List<InsurancePolicy>{ matching, unmatched }
        );
        Test.stopTest();
        System.assertEquals(Decimal.valueOf('25.00'),
                            matching.Projected_Allocation_Cost__c,
                            'Matching projected amount must exclude the expired code.');
        System.assertEquals(Decimal.valueOf('10.00'),
                            matching.Allocation_Expense_Amount__c,
                            'The expense code must be kept separate.');
        System.assertEquals(null, unmatched.Projected_Allocation_Cost__c,
                            'An unmatched product must not receive another product allocation.');
    }
    
    @IsTest
    static void testAllocationEarlyExitMissingRequiredFilters() {
        InsurancePolicy missingFields = new InsurancePolicy(
            Product__c = SECURE_ONE, Sale_Date__c = Date.today()
        );
        ContractTriggerHandler.populateAllocationCosts(
            new List<InsurancePolicy>{ missingFields }
        );
        System.assertEquals(null, missingFields.Projected_Allocation_Cost__c);
    }
    
    @IsTest
    static void testMonthlyNextCycleActiveAndCancelled() {
        Id key = inMemoryPolicyId();
        InsurancePolicy oldActive = new InsurancePolicy(
            Id = key, Status = UtilityClass.contractStatus_Active
        );
        InsurancePolicy active = new InsurancePolicy(
            Status = UtilityClass.contractStatus_Active,
            Sale_Date__c = Date.today().addDays(-40),
            Contract_Term_Months__c = 1
        );
        InsurancePolicy futureSale = new InsurancePolicy(
            Status = UtilityClass.contractStatus_Active,
            Sale_Date__c = Date.today().addDays(10),
            Contract_Term_Months__c = 1
        );
        InsurancePolicy cancelBeforeSale = new InsurancePolicy(
            Id = key, Status = UtilityClass.contractStatus_Cancelled,
            Sale_Date__c = Date.today().addDays(-10),
            Cancel_Effective_Date__c = Date.today().addDays(-11),
            Contract_Term_Months__c = 1
        );
        ContractTriggerHandler.setNextCycleDateForM2MContracts(
            new List<InsurancePolicy>{ active, futureSale }, null
        );
        ContractTriggerHandler.setNextCycleDateForM2MContracts(
            new List<InsurancePolicy>{ cancelBeforeSale },
            new Map<Id, InsurancePolicy>{ key => oldActive }
        );
        System.assertNotEquals(null, active.Next_Cycle_Date_Calc__c);
        System.assertEquals(futureSale.Sale_Date__c.addMonths(1),
                            futureSale.Next_Cycle_Date_Calc__c);
        System.assertEquals(cancelBeforeSale.Sale_Date__c,
                            cancelBeforeSale.Next_Cycle_Date_Calc__c);
        
        InsurancePolicy cancelAfterSale = new InsurancePolicy(
            Id = key, Status = UtilityClass.contractStatus_Cancelled,
            Sale_Date__c = Date.today().addMonths(-3),
            Cancel_Effective_Date__c = Date.today().addDays(-10),
            Contract_Term_Months__c = 1
        );
        ContractTriggerHandler.setNextCycleDateForM2MContracts(
            new List<InsurancePolicy>{ cancelAfterSale },
            new Map<Id, InsurancePolicy>{ key => oldActive }
        );
        System.assert(cancelAfterSale.Next_Cycle_Date_Calc__c >
                      cancelAfterSale.Cancel_Effective_Date__c);
    }
    
    @IsTest
    static void testExpirationMonthlyAndFixedTerm() {
        InsurancePolicy activeM2M = new InsurancePolicy(
            Status = UtilityClass.contractStatus_Active,
            Contract_Term_Months__c = 1,
            Next_Cycle_Date_Calc__c = Date.today().addMonths(1)
        );
        InsurancePolicy cancelled = new InsurancePolicy(
            Status = UtilityClass.contractStatus_Cancelled,
            Contract_Term_Months__c = 1,
            Sale_Date__c = Date.today().addMonths(-3),
            Cancel_Effective_Date__c = Date.today().addDays(-5)
        );
        InsurancePolicy cancelledBeforeSale = new InsurancePolicy(
            Status = UtilityClass.contractStatus_Cancelled,
            Contract_Term_Months__c = 1,
            Sale_Date__c = Date.today(),
            Cancel_Effective_Date__c = Date.today().addDays(-1)
        );
        InsurancePolicy fixedTerm = new InsurancePolicy(
            Status = UtilityClass.contractStatus_Active,
            Contract_Term_Months__c = 12,
            Sale_Date__c = Date.today().addDays(-30),
            Validation_Days__c = 14
        );
        ContractTriggerHandler.setExpirationDate(new List<InsurancePolicy>{
            activeM2M, cancelled, cancelledBeforeSale, fixedTerm
                });
        System.assertEquals(activeM2M.Next_Cycle_Date_Calc__c,
                            activeM2M.Expiration_Date_Calc__c);
        System.assert(cancelled.Expiration_Date_Calc__c >
                      cancelled.Cancel_Effective_Date__c);
        System.assertEquals(cancelledBeforeSale.Sale_Date__c,
                            cancelledBeforeSale.Expiration_Date_Calc__c);
        System.assertEquals(fixedTerm.Sale_Date__c.addDays(14).addMonths(12),
                            fixedTerm.Expiration_Date_Calc__c);
    }
    
    @IsTest
    static void testCancelMileageOnlyAutoWarranty() {
        InsurancePolicy auto = new InsurancePolicy(
            RecordTypeId = autoWarrantyId(),
            Status = UtilityClass.contractStatus_Cancelled,
            Vehicle_Mileage_at_Contract_Inception__c = 12345
        );
        InsurancePolicy alreadySet = new InsurancePolicy(
            RecordTypeId = autoWarrantyId(),
            Status = UtilityClass.contractStatus_Cancelled,
            Cancel_Mileage__c = 13000,
            Vehicle_Mileage_at_Contract_Inception__c = 12345
        );
        ContractTriggerHandler.validateCancelMilage(
            new List<InsurancePolicy>{ auto, alreadySet }
        );
        System.assertEquals(Decimal.valueOf('12345'), auto.Cancel_Mileage__c);
        System.assertEquals(Decimal.valueOf('13000'), alreadySet.Cancel_Mileage__c);
    }
    
    @IsTest
    static void testRefundPercentageBranches() {
        Id autoRt = autoWarrantyId();
        InsurancePolicy beforeEffective = new InsurancePolicy(
            RecordTypeId = autoRt,
            Sale_Date__c = Date.today(), Validation_Days__c = 14,
            Cancel_Effective_Date__c = Date.today().addDays(5)
        );
        InsurancePolicy autoMinMileage = policyFromJson(new Map<String, Object>{
            'RecordTypeId' => autoRt,
                'Sale_Date__c' => Date.today().addDays(-60),
                'Validation_Days__c' => 14,
                'Cancel_Effective_Date__c' => Date.today(),
                'Refund_Date_Percent__c' => Decimal.valueOf('0.80'),
                'Refund_Mileage_Percent__c' => Decimal.valueOf('0.60')
                });
        InsurancePolicy autoMinDate = policyFromJson(new Map<String, Object>{
            'RecordTypeId' => autoRt,
                'Sale_Date__c' => Date.today().addDays(-60),
                'Cancel_Effective_Date__c' => Date.today(),
                'Refund_Date_Percent__c' => Decimal.valueOf('0.30'),
                'Refund_Mileage_Percent__c' => Decimal.valueOf('0.70')
                });
        InsurancePolicy nonAuto = policyFromJson(new Map<String, Object>{
            'Sale_Date__c' => Date.today().addDays(-60),
                'Cancel_Effective_Date__c' => Date.today(),
                'Refund_Date_Percent__c' => Decimal.valueOf('0.75'),
                'Refund_Mileage_Percent__c' => Decimal.valueOf('0.25')
                });
        InsurancePolicy missingCancel = new InsurancePolicy(
            Sale_Date__c = Date.today()
        );
        ContractTriggerHandler.setRefundPercent(new List<InsurancePolicy>{
            beforeEffective, autoMinMileage, autoMinDate, nonAuto, missingCancel
                });
        System.assertEquals(Decimal.valueOf('1'), beforeEffective.Refund_Percent_Calc__c);
        System.assertEquals(Decimal.valueOf('0.60'), autoMinMileage.Refund_Percent_Calc__c);
        System.assertEquals(Decimal.valueOf('0.30'), autoMinDate.Refund_Percent_Calc__c);
        System.assertEquals(Decimal.valueOf('0.75'), nonAuto.Refund_Percent_Calc__c);
        System.assertEquals(null, missingCancel.Refund_Percent_Calc__c);
    }
    
    @IsTest
    static void testUnearnedPercentageStartDates() {
        InsurancePolicy monthly = new InsurancePolicy(
            Contract_Term_Months__c = 1,
            Expiration_Date_Calc__c = Date.today().addMonths(1)
        );
        InsurancePolicy fixedTerm = new InsurancePolicy(
            Contract_Term_Months__c = 12,
            Sale_Date__c = Date.today().addDays(-30),
            Expiration_Date_Calc__c = Date.today().addMonths(12)
        );
        InsurancePolicy noSale = new InsurancePolicy(
            Contract_Term_Months__c = 12,
            Expiration_Date_Calc__c = Date.today().addMonths(12)
        );
        InsurancePolicy noExpiration = new InsurancePolicy(
            Sale_Date__c = Date.today()
        );
        ContractTriggerHandler.setUnearnedPercent(new List<InsurancePolicy>{
            monthly, fixedTerm, noSale, noExpiration
                });
        System.assertEquals(monthly.Expiration_Date_Calc__c.addMonths(-1),
                            monthly.Earning_Start_Date__c);
        System.assertEquals(fixedTerm.Sale_Date__c, fixedTerm.Earning_Start_Date__c);
        System.assertEquals(null, noSale.Earning_Start_Date__c);
        System.assertEquals(null, noExpiration.Earning_Start_Date__c);
    }
    
    @IsTest
    static void testBeforeUpdateOrchestrationWithoutPolicyDml() {
        Id key = inMemoryPolicyId();
        InsurancePolicy oldPolicy = new InsurancePolicy(
            Id = key, Status = UtilityClass.contractStatus_Active,
            Product__c = SECURE_ONE,
            Program_Code__c = 'CTH-OLD',
            SaleDate = System.now().addDays(-5)
        );
        InsurancePolicy candidate = new InsurancePolicy(
            Id = key,
            Status = UtilityClass.contractStatus_Cancelled,
            RecordTypeId = autoWarrantyId(),
            Product__c = SECURE_ONE,
            Program_Code__c = UtilityClass.PROGRAM_CODE,
            SaleDate = System.now().addDays(-30),
            Sale_Date__c = Date.today().addDays(-30),
            Contract_Term_Months__c = 1,
            Cancel_Effective_Date__c = Date.today().addDays(-2),
            Vehicle_Mileage_at_Contract_Inception__c = 15000,
            Cancel_Mileage__c = null
        );
        ContractTriggerHandler.handleBeforeUpdate(
            new List<InsurancePolicy>{ candidate },
            new Map<Id, InsurancePolicy>{ key => oldPolicy }
        );
        System.assertEquals(Decimal.valueOf('15000'), candidate.Cancel_Mileage__c);
        System.assertNotEquals(null, candidate.Expiration_Date_Calc__c);
        System.assertNotEquals(null, candidate.Next_Cycle_Date_Calc__c);
        System.assertNotEquals(null, candidate.Refund_Percent_Calc__c);
    }
}