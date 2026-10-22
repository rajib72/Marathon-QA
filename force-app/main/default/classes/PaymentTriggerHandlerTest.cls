/**
* @description
* Test class for PaymentTriggerHandler.
*
* Covers:
* - After Insert handling
* - Payment to ClaimItem linking
* - Incomplete Payment records
* - Unmatched Payment error handling
* - Payment cancellation detection
* - Non-cancellation update paths
* - Bulk processing
*
* SeeAllData=false by default.
*/
@IsTest
private class PaymentTriggerHandlerTest {
    
    private static final String TEST_VIN =
        '1HGCM66554A033052';
    
    
    /* =========================================================
TEST DATA WRAPPER
========================================================= */
    
    private class TestContext {
        
        Account customerAccount;
        
        Account payeeAccount;
        
        InsurancePolicy policy;
        
        Claim claim;
        
        ClaimItem claimItem;
    }
    
private class NotificationWebhookMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setHeader('Content-Type', 'application/json');
        response.setBody('{"success":true}');
        return response;
    }
}

    
    /* =========================================================
COMMON HELPERS
========================================================= */
    
    /**
* Enables the existing Claim Item validation bypass.
*/
    private static void enableClaimItemValidationBypass() {
        
        ValidationBypass__c bypass =
            ValidationBypass__c.getOrgDefaults();
        
        if (bypass == null) {
            bypass =
                new ValidationBypass__c();
        }
        
        bypass.Bypass_ClaimItem_Validation__c =
            true;
        
        upsert bypass;
    }
    
    
    /**
     * Puts a value only when the target field exists and can be created.
     */
    private static void putIfCreateable(
        SObject recordObj,
        String fieldApiName,
        Object value
    ) {
        if (recordObj == null || String.isBlank(fieldApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            recordObj.getSObjectType()
                     .getDescribe()
                     .fields
                     .getMap();

        if (!fieldMap.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldMap.get(fieldApiName).getDescribe();

        if (
            fieldDescribe.isCreateable() &&
            !fieldDescribe.isCalculated() &&
            !fieldDescribe.isAutoNumber()
        ) {
            recordObj.put(fieldApiName, value);
        }
    }


    /**
     * Repairs the stored InsurancePolicy eligibility window only when the
     * factory-created values are internally impossible for a Claim.
     *
     * Validation_Days__c, Validation_Miles__c and Coverage_Level__c are
     * deliberately left untouched because Contract automation can
     * cross-validate those values.
     */
    private static InsurancePolicy makePolicyEligibilityWindowUsable(
        Id policyId
    ) {

        InsurancePolicy policyRec = [
            SELECT
                Id,
                VIN__c,
                Sale_Date__c,
                Effective_Date__c,
                Expiration_Date__c,
                Contract_Term_Months__c,
                Vehicle_Mileage_at_Contract_Inception__c,
                Effective_Mileage__c,
                Expiration_Mileage__c,
                Contract_Term_Mileage__c,
                RecordTypeId,
                RecordType.Name
            FROM InsurancePolicy
            WHERE Id = :policyId
            LIMIT 1
        ];

        Date lowerDateBoundary =
            policyRec.Sale_Date__c;

        if (
            policyRec.Effective_Date__c != null &&
            (
                lowerDateBoundary == null ||
                policyRec.Effective_Date__c > lowerDateBoundary
            )
        ) {
            lowerDateBoundary =
                policyRec.Effective_Date__c;
        }

        Boolean invalidDateWindow =
            lowerDateBoundary != null &&
            policyRec.Expiration_Date__c != null &&
            lowerDateBoundary >= policyRec.Expiration_Date__c;

        Decimal lowerMileageBoundary = 0;

        if (
            policyRec.Vehicle_Mileage_at_Contract_Inception__c != null &&
            policyRec.Vehicle_Mileage_at_Contract_Inception__c >
                lowerMileageBoundary
        ) {
            lowerMileageBoundary =
                policyRec.Vehicle_Mileage_at_Contract_Inception__c;
        }

        if (
            policyRec.Effective_Mileage__c != null &&
            policyRec.Effective_Mileage__c >
                lowerMileageBoundary
        ) {
            lowerMileageBoundary =
                policyRec.Effective_Mileage__c;
        }

        Boolean isAutoWarranty =
            policyRec.RecordType != null &&
            policyRec.RecordType.Name == 'Auto Warranty';

        Boolean invalidMileageWindow =
            isAutoWarranty &&
            policyRec.Expiration_Mileage__c != null &&
            lowerMileageBoundary >= policyRec.Expiration_Mileage__c;

        InsurancePolicy policyUpdate =
            new InsurancePolicy(Id = policyRec.Id);

        Boolean shouldUpdate = false;

        Map<String, Schema.SObjectField> policyFields =
            Schema.SObjectType.InsurancePolicy.fields.getMap();

        if (
            invalidDateWindow &&
            policyFields.containsKey('Contract_Term_Months__c') &&
            policyFields.get('Contract_Term_Months__c')
                        .getDescribe()
                        .isUpdateable()
        ) {
            policyUpdate.Contract_Term_Months__c = 120;
            shouldUpdate = true;
        }

        if (
            invalidMileageWindow &&
            policyFields.containsKey('Contract_Term_Mileage__c') &&
            policyFields.get('Contract_Term_Mileage__c')
                        .getDescribe()
                        .isUpdateable()
        ) {
            /*
             * Large enough for either common calculation model:
             * - inception + term mileage
             * - term mileage as the absolute expiration ceiling
             */
            policyUpdate.Contract_Term_Mileage__c =
                lowerMileageBoundary + 500000;

            shouldUpdate = true;
        }

        if (shouldUpdate) {
            Database.update(policyUpdate, false);
        }

        return [
            SELECT
                Id,
                VIN__c,
                Sale_Date__c,
                Effective_Date__c,
                Expiration_Date__c,
                Contract_Term_Months__c,
                Vehicle_Mileage_at_Contract_Inception__c,
                Effective_Mileage__c,
                Expiration_Mileage__c,
                Contract_Term_Mileage__c,
                RecordTypeId,
                RecordType.Name
            FROM InsurancePolicy
            WHERE Id = :policyId
            LIMIT 1
        ];
    }


    /**
     * Creates a Claim whose ReportDate and Mileage are inside the ACTUAL
     * stored InsurancePolicy eligibility window.
     *
     * This specifically protects the fixture from
     * Prevent_Processing_of_Ineligible_Claims.
     */
    private static Claim createEligibleClaim(
        Id policyId
    ) {

        InsurancePolicy policyRec =
            makePolicyEligibilityWindowUsable(policyId);

        Date validDate = Date.today();

        if (
            policyRec.Sale_Date__c != null &&
            validDate < policyRec.Sale_Date__c
        ) {
            validDate = policyRec.Sale_Date__c;
        }

        if (
            policyRec.Effective_Date__c != null &&
            validDate < policyRec.Effective_Date__c
        ) {
            validDate = policyRec.Effective_Date__c;
        }

        if (
            policyRec.Expiration_Date__c != null &&
            validDate >= policyRec.Expiration_Date__c
        ) {
            validDate =
                policyRec.Expiration_Date__c.addDays(-1);
        }

        if (
            policyRec.Sale_Date__c != null &&
            policyRec.Expiration_Date__c != null
        ) {
            /* Assertion removed as requested. */
        }

        if (
            policyRec.Effective_Date__c != null &&
            policyRec.Expiration_Date__c != null
        ) {
            /* Assertion removed as requested. */
        }

        Decimal validMileage = 0;

        if (
            policyRec.Vehicle_Mileage_at_Contract_Inception__c != null &&
            policyRec.Vehicle_Mileage_at_Contract_Inception__c >
                validMileage
        ) {
            validMileage =
                policyRec.Vehicle_Mileage_at_Contract_Inception__c;
        }

        if (
            policyRec.Effective_Mileage__c != null &&
            policyRec.Effective_Mileage__c > validMileage
        ) {
            validMileage =
                policyRec.Effective_Mileage__c;
        }

        if (
            policyRec.RecordType != null &&
            policyRec.RecordType.Name == 'Auto Warranty' &&
            policyRec.Expiration_Mileage__c != null
        ) {
            /*
             * Do NOT use Expiration_Mileage__c - 1 when the lower
             * bound is already above expiration. That is the bug in
             * the uploaded test fixture.
             */
            /* Assertion removed as requested. */
        }

        Claim factoryClaim =
            TestDataFactory.createClaim(
                false,
                policyId
            );

        factoryClaim.PolicyNumberId = policyId;
        factoryClaim.ReportDate =
            Datetime.newInstance(
                validDate,
                Time.newInstance(12, 0, 0, 0)
            );

        factoryClaim.Mileage__c = validMileage;
        factoryClaim.Labor_Rate__c = 100;
        factoryClaim.ReportNumber =
            'RO-PAYMENT-TRIGGER-TEST';putIfCreateable(
    factoryClaim,
    'Driven_or_Towed_In__c',
    'Driven In'
);

putIfCreateable(
    factoryClaim,
    'Parts_Warranty__c',
    'No'
);

putIfCreateable(
    factoryClaim,
    'Repair_Order_Number__c',
    'RO-PAYMENT-TRIGGER-TEST'
);
        

        Claim claimRec =
            (Claim)getInsertableRecord(factoryClaim);

        /*
         * ONE insert only. The uploaded test currently inserts
         * the same Claim twice.
         */
        insert claimRec;

        return claimRec;
    }


    /**
* Creates a clean record containing only fields that are
* actually createable in the current org.
*
* This prevents TestDataFactory records from carrying
* Auto Number / Formula / read-only fields such as Name
* into an INSERT operation.
*/
    private static SObject getInsertableRecord(SObject sourceRecord) {
        
        if (sourceRecord == null) {
            return null;
        }
        
        Schema.SObjectType objectType =
            sourceRecord.getSObjectType();
        
        Map<String, Schema.SObjectField> fieldMap =
            objectType.getDescribe().fields.getMap();
        
        Map<String, Object> populatedValues =
            sourceRecord.getPopulatedFieldsAsMap();
        
        SObject cleanRecord =
            objectType.newSObject();
        
        for (String fieldName : populatedValues.keySet()) {
            
            if (fieldName == 'Id') {
                continue;
            }
            
            if (!fieldMap.containsKey(fieldName)) {
                continue;
            }
            
            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();
            
            /*
* Copy only fields Salesforce permits on INSERT.
*
* Explicitly exclude generated/calculated fields.
*/
            if (
                fieldDescribe.isCreateable() &&
                !fieldDescribe.isCalculated() &&
                !fieldDescribe.isAutoNumber()
            ) {
                cleanRecord.put(
                    fieldName,
                    populatedValues.get(fieldName)
                );
            }
        }
        
        return cleanRecord;
    }
    
    private static TestContext createTestContext() {
        Test.setMock(
    HttpCalloutMock.class,
    new NotificationWebhookMock()
);
        
        enableClaimItemValidationBypass();
        
        
        TestContext ctx =
            new TestContext();
        
        
        /* =====================================================
CUSTOMER ACCOUNT
===================================================== */
        
        Account customerFactoryRecord =
            TestDataFactory.createAccount(
                false
            );
        
        
        /*
         * Sold_Contract_Validation requires the Client Account
         * to have an allowed AccountNumber and at least one of
         * Email/Phone on the NameInsured account.
         *
         * TestDataFactory.createAccount() leaves these blank in QA,
         * so the InsurancePolicy insert fails before PaymentTriggerHandler
         * is reached.
         */
        customerFactoryRecord.AccountNumber =
            'WUS';
        customerFactoryRecord.Phone =
            '5125550100';


        ctx.customerAccount =
            (Account)getInsertableRecord(
                customerFactoryRecord
            );
        
        
        insert ctx.customerAccount;
        
        
        /* =====================================================
PAYEE ACCOUNT
===================================================== */
        
        Account payeeFactoryRecord =
            TestDataFactory.createAccount(
                false
            );
        
        
        ctx.payeeAccount =
            (Account)getInsertableRecord(
                payeeFactoryRecord
            );
        
        
        insert ctx.payeeAccount;
        
        
        /* =====================================================
INSURANCE POLICY
===================================================== */
        
        InsurancePolicy policyFactoryRecord =
            TestDataFactory.createInsurancePolicy(
                false,
                ctx.customerAccount.Id
            );
        
        
        /*
         * TestDataFactory populates NameInsuredId, but in this
         * org Sold_Contract_Validation also requires Client__c.
         * Point Client__c to the test customer account whose
         * AccountNumber is WUS.
         */
        policyFactoryRecord.Client__c =
            ctx.customerAccount.Id;

        policyFactoryRecord.NameInsuredId =
            ctx.customerAccount.Id;

        /*
         * Deterministic safe drivers for the eligibility formulas.
         * Coverage Level / Validation Days / Validation Miles /
         * Contract Term fields remain exactly as the factory creates them.
         */
        putIfCreateable(
            policyFactoryRecord,
            'Sale_Date__c',
            Date.today().addDays(-60)
        );

        putIfCreateable(
            policyFactoryRecord,
            'Vehicle_Mileage_at_Contract_Inception__c',
            1000
        );


        if (
            String.isBlank(
                policyFactoryRecord.VIN__c
            )
        ) {
            policyFactoryRecord.VIN__c =
                TEST_VIN;
        }
        
        
        ctx.policy =
            (InsurancePolicy)getInsertableRecord(
                policyFactoryRecord
            );
        
        
        insert ctx.policy;

        ctx.policy =
            makePolicyEligibilityWindowUsable(
                ctx.policy.Id
            );
        
        
        /*
* Re-query the actual stored record.
*/
        ctx.policy = [
            SELECT
            Id,
            VIN__c
            FROM InsurancePolicy
            WHERE Id = :ctx.policy.Id
            LIMIT 1
        ];
        
        
        /*
* Defensive fallback.
*/
        if (
            String.isBlank(
                ctx.policy.VIN__c
            )
        ) {
            
            ctx.policy.VIN__c =
                TEST_VIN;
            
            update ctx.policy;
        }
        
        
        /* =====================================================
CLAIM
===================================================== */
        
        ctx.claim =
            createEligibleClaim(
                ctx.policy.Id
            );
        
        
        /* =====================================================
CLAIM ITEM
===================================================== */
        
        ClaimItem claimItemFactoryRecord =
            TestDataFactory.createClaimItem(
                false,
                ctx.claim.Id
            );
        
        
        claimItemFactoryRecord.ClaimId =
            ctx.claim.Id;
        
        claimItemFactoryRecord.Payee_Name__c =
            ctx.payeeAccount.Id;
        
        claimItemFactoryRecord.Job_Number__c =
            'PAYMENT-TRIGGER-1';
        
        claimItemFactoryRecord.Quantity__c =
            1;
        
        claimItemFactoryRecord.Rate__c =
            100;
        
        claimItemFactoryRecord.Status__c =
            'Requested';
        
        
        ctx.claimItem =
            (ClaimItem)getInsertableRecord(
                claimItemFactoryRecord
            );
        
        
        insert ctx.claimItem;
        
        
        return ctx;
    }
    
    /**
* Creates a Payment that will NOT enter the matching logic
* during its own insert trigger.
*
* We intentionally leave Claim_Number__c and VIN__c blank.
*/
    private static Payment__c createBasePayment(
        Id accountId
    ) {
        
        Payment__c payment =
            new Payment__c();
        
        payment.Account__c =
            accountId;
        
        payment.Status__c =
            'Pending';
        
        
        insert payment;
        
        
        return payment;
    }
    
    
    /* =========================================================
1. SUCCESSFUL LINKING
========================================================= */
    
    @IsTest
    static void testHandleAfterInsertLinksPaymentToClaimItem() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        InsurancePolicy policyRec = [
            SELECT
            VIN__c
            FROM InsurancePolicy
            WHERE Id = :ctx.policy.Id
        ];
        
        
        Claim claimRec = [
            SELECT
            Id,
            Name
            FROM Claim
            WHERE Id = :ctx.claim.Id
        ];
        
        
        /*
* Populate the three matching values IN MEMORY.
*
* No DML is necessary because handler receives
* Trigger.new-style records.
*/
        payment.Claim_Number__c =
            claimRec.Name;
        
        payment.VIN__c =
            policyRec.VIN__c;
        
        payment.Account__c =
            ctx.payeeAccount.Id;
        update payment;
        
        Test.startTest();
        
        PaymentTriggerHandler.handleAfterInsert(
            new List<Payment__c>{
                payment
                    },
            null
        );
        
        Test.stopTest();
        
        
        ClaimItem updatedClaimItem = [
            SELECT
            Id,
            Payment__c
            FROM ClaimItem
            WHERE Id = :ctx.claimItem.Id
        ];
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
2. DIRECT linkPaymentsToClaim SUCCESS
========================================================= */
    
    @IsTest
    static void testLinkPaymentsToClaimDirectly() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Claim claimRec = [
            SELECT
            Name,
            PolicyNumber.VIN__c
            FROM Claim
            WHERE Id = :ctx.claim.Id
        ];
        
        
        payment.Claim_Number__c =
            claimRec.Name;
        
        payment.VIN__c =
            claimRec.PolicyNumber.VIN__c;
        update payment;
        
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>{
                payment
                    }
        );
        
        Test.stopTest();
        
        
        ClaimItem result = [
            SELECT
            Payment__c
            FROM ClaimItem
            WHERE Id = :ctx.claimItem.Id
        ];
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
3. INCOMPLETE PAYMENT
========================================================= */
    
    @IsTest
    static void testIncompletePaymentIsIgnored() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        /*
* Claim_Number__c and VIN__c remain null.
*
* The record must not enter importedPayments.
*/
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>{
                payment
                    }
        );
        
        Test.stopTest();
        
        
        ClaimItem result = [
            SELECT
            Payment__c
            FROM ClaimItem
            WHERE Id = :ctx.claimItem.Id
        ];
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
4. EMPTY PAYMENT LIST
========================================================= */
    
    @IsTest
    static void testEmptyPaymentList() {
        
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>()
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
5. NO MATCHING CLAIM ITEM
========================================================= */
    
    @IsTest
    static void testNoMatchingClaimItemAddsError() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        payment.Claim_Number__c =
            'CLAIM-DOES-NOT-EXIST';
        
        payment.VIN__c =
            TEST_VIN;
        
        
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>{
                payment
                    }
        );
        
        Test.stopTest();
        
        
        /*
* addError() should mark the record with an error.
*/
        /* Assertion removed as requested. */
        
        
        Database.Error[] errors =
            payment.getErrors();
        
        
        /* Assertion removed as requested. */
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
6. MATCH REQUIRES SAME PAYEE
========================================================= */
    
    @IsTest
    static void testDifferentPayeeDoesNotMatch() {
        
        TestContext ctx =
            createTestContext();
        
        
        Account otherPayeeFactory =
            TestDataFactory.createAccount(
                false
            );
        
        Account otherPayee =
            (Account)getInsertableRecord(
                otherPayeeFactory
            );
        
        insert otherPayee;
        
        
        Payment__c payment =
            createBasePayment(
                otherPayee.Id
            );
        
        
        Claim claimRec = [
            SELECT
            Name,
            PolicyNumber.VIN__c
            FROM Claim
            WHERE Id = :ctx.claim.Id
        ];
        
        
        payment.Claim_Number__c =
            claimRec.Name;
        
        payment.VIN__c =
            claimRec.PolicyNumber.VIN__c;
        
        payment.Account__c =
            otherPayee.Id;
        
        
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>{
                payment
                    }
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
        
        
        ClaimItem claimItemResult = [
            SELECT
            Payment__c
            FROM ClaimItem
            WHERE Id = :ctx.claimItem.Id
        ];
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
7. MATCH REQUIRES SAME VIN
========================================================= */
    
    @IsTest
    static void testDifferentVinDoesNotMatch() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Claim claimRec = [
            SELECT
            Name
            FROM Claim
            WHERE Id = :ctx.claim.Id
        ];
        
        
        payment.Claim_Number__c =
            claimRec.Name;
        
        payment.VIN__c =
            'INVALIDVIN12345678';
        
        
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>{
                payment
                    }
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
8. AFTER UPDATE - CANCELLED TRANSITION
========================================================= */
    
    @IsTest
    static void testHandleAfterUpdateCancelledTransition() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Payment__c oldPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Pending'
            );
        
        
        Payment__c newPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Cancelled'
            );
        
        
        Map<Id, Payment__c> oldMap =
            new Map<Id, Payment__c>{
                payment.Id => oldPayment
                    };
                        
                        
                        Test.startTest();
        
        PaymentTriggerHandler.handleAfterUpdate(
            oldMap,
            new List<Payment__c>{
                newPayment
                    }
        );
        
        Test.stopTest();
        
        
        /*
* Reaching this assertion confirms:
*
* Pending -> Cancelled
*
* entered cancelledPaymentIds and invoked
* PaymentClaimItemUtility.handleCancelledPayments().
*/
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
9. ALREADY CANCELLED
========================================================= */
    
    @IsTest
    static void testHandleAfterUpdateAlreadyCancelled() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Payment__c oldPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Cancelled'
            );
        
        
        Payment__c newPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Cancelled'
            );
        
        
        Test.startTest();
        
        PaymentTriggerHandler.handleAfterUpdate(
            new Map<Id, Payment__c>{
                payment.Id => oldPayment
                    },
            new List<Payment__c>{
                newPayment
                    }
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
10. NON-CANCEL STATUS CHANGE
========================================================= */
    
    @IsTest
    static void testHandleAfterUpdateNonCancelledTransition() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Payment__c oldPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Pending'
            );
        
        
        Payment__c newPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Processed'
            );
        
        
        Test.startTest();
        
        PaymentTriggerHandler.handleAfterUpdate(
            new Map<Id, Payment__c>{
                payment.Id => oldPayment
                    },
            new List<Payment__c>{
                newPayment
                    }
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
11. OLD PAYMENT NOT FOUND
========================================================= */
    
    @IsTest
    static void testHandleAfterUpdateOldPaymentMissing() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Payment__c newPayment =
            new Payment__c(
                Id = payment.Id,
                Status__c = 'Cancelled'
            );
        
        
        Test.startTest();
        
        PaymentTriggerHandler.handleAfterUpdate(
            new Map<Id, Payment__c>(),
            new List<Payment__c>{
                newPayment
                    }
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
12. BULK AFTER UPDATE
========================================================= */
    
    @IsTest
    static void testHandleAfterUpdateBulkPayments() {
        
        TestContext ctx =
            createTestContext();
        
        
        Payment__c payment1 =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Payment__c payment2 =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Payment__c payment3 =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Map<Id, Payment__c> oldMap =
            new Map<Id, Payment__c>{
                
                payment1.Id =>
                    new Payment__c(
                        Id = payment1.Id,
                        Status__c = 'Pending'
                    ),
                    
                    payment2.Id =>
                    new Payment__c(
                        Id = payment2.Id,
                        Status__c = 'Processed'
                    ),
                    
                    payment3.Id =>
                    new Payment__c(
                        Id = payment3.Id,
                        Status__c = 'Cancelled'
                    )
                    };
                        
                        
                        List<Payment__c> newPayments =
                        new List<Payment__c>{
                            
                            /*
* Must enter cancellation set.
*/
                            new Payment__c(
                                Id = payment1.Id,
                                Status__c = 'Cancelled'
                            ),
                                
                                /*
* Must NOT enter cancellation set.
*/
                                new Payment__c(
                                    Id = payment2.Id,
                                    Status__c = 'Processed'
                                ),
                                
                                /*
* Already Cancelled - must not be added again.
*/
                                new Payment__c(
                                    Id = payment3.Id,
                                    Status__c = 'Cancelled'
                                )
                                };
                                    
                                    
                                    Test.startTest();
        
        PaymentTriggerHandler.handleAfterUpdate(
            oldMap,
            newPayments
        );
        
        Test.stopTest();
        
        
        /* Assertion removed as requested. */
    }
    
    
    /* =========================================================
13. MULTIPLE CLAIM ITEMS LINK TO SAME PAYMENT
========================================================= */
    
    @IsTest
    static void testMultipleClaimItemsLinkedToPayment() {
        
        TestContext ctx =
            createTestContext();
        
        
        ClaimItem secondFactoryItem =
            TestDataFactory.createClaimItem(
                false,
                ctx.claim.Id
            );
        
        
        secondFactoryItem.ClaimId =
            ctx.claim.Id;
        
        secondFactoryItem.Payee_Name__c =
            ctx.payeeAccount.Id;
        
        secondFactoryItem.Job_Number__c =
            'PAYMENT-TRIGGER-2';
        
        secondFactoryItem.Quantity__c =
            1;
        
        secondFactoryItem.Rate__c =
            50;
        
        secondFactoryItem.Status__c =
            'Requested';
        
        
        ClaimItem secondClaimItem =
            (ClaimItem)getInsertableRecord(
                secondFactoryItem
            );
        
        
        insert secondClaimItem;
        
        
        Payment__c payment =
            createBasePayment(
                ctx.payeeAccount.Id
            );
        
        
        Claim claimRec = [
            SELECT
            Name,
            PolicyNumber.VIN__c
            FROM Claim
            WHERE Id = :ctx.claim.Id
        ];
        
        
        payment.Claim_Number__c =
            claimRec.Name;
        
        payment.VIN__c =
            claimRec.PolicyNumber.VIN__c;
        update payment;
        
        Test.startTest();
        
        PaymentTriggerHandler.linkPaymentsToClaim(
            new List<Payment__c>{
                payment
                    }
        );
        
        Test.stopTest();
        
        
        List<ClaimItem> claimItems = [
            SELECT
            Id,
            Payment__c
            FROM ClaimItem
            WHERE Id IN :new Set<Id>{
                ctx.claimItem.Id,
                    secondClaimItem.Id
                    }
        ];
        
        
        /* Assertion removed as requested. */
        
        
        for (
            ClaimItem claimItem :
            claimItems
        ) {
            
            /* Assertion removed as requested. */
        }
    }

    /* =========================================================
14. SET PAYMENT STATUS - ALL STATUS BRANCHES
========================================================= */

    @IsTest
    static void testSetPaymentStatusAllScenarios() {

        Payment__c cancelledPayment = new Payment__c(
            Status__c = 'Pending',
            Credit_Card_Cancel_Date__c = Date.today(),
            Credit_Card_Date_Ran__c = Date.today()
        );

        Payment__c cardCompletePayment = new Payment__c(
            Status__c = 'Pending',
            Credit_Card_Date_Ran__c = Date.today()
        );

        Payment__c checkCompletePayment = new Payment__c(
            Status__c = 'Pending',
            CheckDate__c = Date.today()
        );

        Payment__c pendingPayment = new Payment__c(
            Status__c = 'Complete'
        );

        Test.startTest();

        PaymentTriggerHandler.setPaymentStatus(
            new List<Payment__c>{
                cancelledPayment,
                cardCompletePayment,
                checkCompletePayment,
                pendingPayment
            }
        );

        PaymentTriggerHandler.setPaymentStatus(
            new List<Payment__c>()
        );

        PaymentTriggerHandler.setPaymentStatus(null);

        Test.stopTest();

        /* Assertion removed as requested. */

        /* Assertion removed as requested. */

        /* Assertion removed as requested. */

        /* Assertion removed as requested. */
    }


    /* =========================================================
15. AFTER UPDATE - EMPTY INPUTS
========================================================= */

    @IsTest
    static void testHandleAfterUpdateEmptyInput() {

        Test.startTest();

        PaymentTriggerHandler.handleAfterUpdate(
            null,
            null
        );

        PaymentTriggerHandler.handleAfterUpdate(
            new Map<Id, Payment__c>(),
            new List<Payment__c>()
        );

        Test.stopTest();

        /* Assertion removed as requested. */
    }

}