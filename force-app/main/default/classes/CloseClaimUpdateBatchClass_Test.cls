/**
 * @author: Renuka Singh
 * @description:
 * Test coverage for CloseClaimUpdateBatchClass.
 *
 * Covers:
 * - Deterministic eligible Insurance Policy creation
 * - Eligible Claim creation
 * - Batch start()
 * - Batch execute()
 * - Claim Item LastModifiedDate true branch
 * - Claim Item LastModifiedDate false branch
 * - Claims without Claim Items
 * - Claim closure
 * - Database.executeBatch()
 * - finish()
 * - Scheduler execution
 * - Empty scope handling
 * - Defensive exception handling
 */
@IsTest
private class CloseClaimUpdateBatchClass_Test {


    /* =========================================================
       TEST SETUP
       ========================================================= */

    @TestSetup
    static void setupTestData() {

        /*
         * =======================================================
         * CREATE INSURED ACCOUNT
         * =======================================================
         */

        Account accRec =
            TestDataFactory.createAccount(false);


        /*
         * Person-account / insured information.
         */
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
            'Email__c',
            'testinsured@example.com'
        );

        putIfCreateable(
            accRec,
            'Phone',
            '9876543210'
        );


        /*
         * Do not set AccountNumber here.
         * This is the insured Account.
         */
        insert accRec;


        /*
         * =======================================================
         * CREATE ELIGIBLE POLICY
         * =======================================================
         */

        InsurancePolicy policyRec =
            createEligiblePolicy(accRec.Id);


        /*
         * =======================================================
         * CREATE ELIGIBLE CLAIM
         * =======================================================
         */

        Claim claimRec =
            createEligibleOpenClaim(policyRec.Id);


        /*
         * =======================================================
         * CREATE CLAIM ITEM
         * =======================================================
         */

        ClaimItem claimItemRec =
            TestDataFactory.createClaimItem(
                false,
                claimRec.Id
            );

        claimItemRec.ClaimId =
            claimRec.Id;

        claimItemRec.Status__c =
            'Requested';

        insert claimItemRec;
    }


    /* =========================================================
       ELIGIBLE POLICY HELPER
       ========================================================= */

    private static InsurancePolicy createEligiblePolicy(
        Id accountId
    ) {

        /*
         * false = do not insert yet.
         */
        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                accountId
            );

        Date todayDate =
            Date.today();


        /* =====================================================
           CLIENT
           ===================================================== */

        policyRec.Client__c =
            accountId;


        /* =====================================================
           INSURED / CONTRACT INFORMATION
           ===================================================== */

        policyRec.VIN__c =
            'TESTVIN123';

        policyRec.Vehicle_Year__c =
            '2025';

        policyRec.Vehicle_Mileage_at_Contract_Inception__c =
            1000;


        /* =====================================================
           CONTRACT TERM
           ===================================================== */

        policyRec.Contract_Term_Mileage__c =
            100000;

        policyRec.Contract_Term_Months__c =
            12;


        /* =====================================================
           REQUIRED FINANCIAL FIELDS
           ===================================================== */

        policyRec.Dealer_Program_Id__c =
            'TEST';

        policyRec.Net_Dealer_Cost__c =
            1000;

        policyRec.PremiumAmount =
            1500;

        policyRec.Deductible__c =
            100;

        policyRec.Down_Payment_Amount__c =
            500;


        /* =====================================================
           DATE ELIGIBILITY
           ===================================================== */

        putIfCreateable(
            policyRec,
            'Sale_Date__c',
            todayDate.addDays(-60)
        );

        putIfCreateable(
            policyRec,
            'Effective_Date__c',
            todayDate.addDays(-30)
        );

        putIfCreateable(
            policyRec,
            'Expiration_Date__c',
            todayDate.addDays(365)
        );

        putIfCreateable(
            policyRec,
            'SaleDate',
            todayDate.addDays(-60)
        );

        putIfCreateable(
            policyRec,
            'Fulfillment_Date__c',
            todayDate.addDays(-30)
        );


        /* =====================================================
           MILEAGE ELIGIBILITY
           ===================================================== */

        putIfCreateable(
            policyRec,
            'Vehicle_Mileage_at_Contract_Inception__c',
            1000
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
           INSERT
           ===================================================== */

        insert policyRec;

        return policyRec;
    }


    /* =========================================================
       ELIGIBLE CLAIM HELPER
       ========================================================= */

    private static Claim createEligibleOpenClaim(
        Id policyId
    ) {

        /*
         * Create without DML so all validation-sensitive
         * fields can be populated before insert.
         */
        Claim claimRec =
            TestDataFactory.createClaim(
                false,
                policyId
            );

        claimRec.PolicyNumberId =
            policyId;

        claimRec.Status =
            System.Label.Open;


        /* =====================================================
           CLAIM DATE
           ===================================================== */

        setDateOrDateTimeField(
            claimRec,
            'ReportDate',
            Date.today()
        );


        /* =====================================================
           MILEAGE
           ===================================================== */

        claimRec.Mileage__c =
            5000;


        /* =====================================================
           REQUIRED CLAIM FIELDS
           ===================================================== */

        /*
         * Required by Claim/ClaimItem validation.
         */
        claimRec.Labor_Rate__c =
            25;

        claimRec.ReportNumber =
            'RO-CLOSE-TEST';


        /*
         * Driven In / Towed In.
         *
         * Pick the first active value instead of hardcoding
         * a value that could differ between environments.
         */
        String drivenOrTowed =
            getFirstActiveClaimPicklistValue(
                'Driven_or_Towed_In__c'
            );

        if (drivenOrTowed != null) {

            claimRec.Driven_or_Towed_In__c =
                drivenOrTowed;
        }


        /*
         * Parts Warranty.
         */
        String partsWarranty =
            getFirstActiveClaimPicklistValue(
                'Parts_Warranty__c'
            );

        if (partsWarranty != null) {

            claimRec.Parts_Warranty__c =
                partsWarranty;
        }


        /* =====================================================
           INSERT
           ===================================================== */

        insert claimRec;

        return claimRec;
    }


    /* =========================================================
       CLAIM PICKLIST HELPER
       ========================================================= */

    private static String getFirstActiveClaimPicklistValue(
        String fieldApiName
    ) {

        Map<String, Schema.SObjectField> fieldMap =
            Claim.SObjectType
                .getDescribe()
                .fields
                .getMap();


        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }


        Schema.DescribeFieldResult fieldDescribe =
            fieldMap
                .get(fieldApiName)
                .getDescribe();


        if (
            fieldDescribe.getType() !=
            Schema.DisplayType.Picklist
        ) {
            return null;
        }


        for (
            Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()
        ) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }


        return null;
    }


    /* =========================================================
       DYNAMIC FIELD HELPER
       ========================================================= */

    private static void putIfCreateable(
        SObject record,
        String fieldApiName,
        Object value
    ) {

        Map<String, Schema.SObjectField> fieldMap =
            record
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap();


        if (!fieldMap.containsKey(fieldApiName)) {
            return;
        }


        Schema.DescribeFieldResult fieldDescribe =
            fieldMap
                .get(fieldApiName)
                .getDescribe();


        if (
            fieldDescribe.isCreateable() &&
            !fieldDescribe.isCalculated() &&
            !fieldDescribe.isAutoNumber()
        ) {

            record.put(
                fieldApiName,
                value
            );
        }
    }


    /* =========================================================
       DATE / DATETIME HELPER
       ========================================================= */

    private static void setDateOrDateTimeField(
        SObject record,
        String fieldApiName,
        Date value
    ) {

        Schema.SObjectField fieldToken =
            record
                .getSObjectType()
                .getDescribe()
                .fields
                .getMap()
                .get(fieldApiName);


        if (fieldToken == null) {
            return;
        }


        Schema.DisplayType fieldType =
            fieldToken
                .getDescribe()
                .getType();


        if (
            fieldType ==
            Schema.DisplayType.DateTime
        ) {

            record.put(
                fieldApiName,
                Datetime.newInstance(
                    value,
                    Time.newInstance(
                        12,
                        0,
                        0,
                        0
                    )
                )
            );

        } else {

            record.put(
                fieldApiName,
                value
            );
        }
    }


    /* =========================================================
       DATABASE EXECUTEBATCH TEST
       ========================================================= */

    @IsTest
    static void testBatchMethod() {

        Claim claimBefore = [
            SELECT
                Id,
                Status,
                LastModifiedDate
            FROM Claim
            WHERE Status = :System.Label.Open
            LIMIT 1
        ];


        System.assertEquals(
            System.Label.Open,
            claimBefore.Status,
            'Claim must initially be Open.'
        );


        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        /*
         * Test-created records cannot genuinely be
         * older than 16 days.
         *
         * Move the threshold into the future so
         * start() returns our test Claim.
         */
        batchObj.daysCheck =
            System.now().addMinutes(5);


        Test.startTest();

        Id jobId =
            Database.executeBatch(
                batchObj,
                5
            );

        Test.stopTest();


        System.assertNotEquals(
            null,
            jobId,
            'Batch job should have been created.'
        );


        Claim claimAfter = [
            SELECT
                Id,
                Status
            FROM Claim
            WHERE Id = :claimBefore.Id
        ];


        System.assertEquals(
            System.Label.Closed,
            claimAfter.Status,
            'The Open Claim should be closed.'
        );


        AsyncApexJob batchJob = [
            SELECT
                Id,
                Status,
                JobType,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];


        System.assertEquals(
            0,
            batchJob.NumberOfErrors,
            'Batch should complete without errors.'
        );
    }


    /* =========================================================
       RECENT CLAIM ITEM
       ========================================================= */

    @IsTest
    static void testExecuteWithRecentlyModifiedClaimItem() {

        Claim claimRec = [
            SELECT
                Id,
                Status,
                LastModifiedDate
            FROM Claim
            WHERE Status = :System.Label.Open
            LIMIT 1
        ];


        ClaimItem recentClaimItem = [
            SELECT
                Id,
                ClaimId,
                LastModifiedDate
            FROM ClaimItem
            WHERE ClaimId = :claimRec.Id
            LIMIT 1
        ];


        System.assert(
            recentClaimItem.LastModifiedDate >
            System.now().addDays(-16),
            'The setup Claim Item should be recently modified.'
        );


        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        Test.startTest();

        batchObj.execute(
            null,
            new List<Claim>{
                claimRec
            }
        );

        Test.stopTest();


        Claim claimAfter = [
            SELECT
                Id,
                Status
            FROM Claim
            WHERE Id = :claimRec.Id
        ];


        /*
         * Production code contains:
         *
         * || Test.isRunningTest()
         *
         * Therefore Claim is closed during test execution.
         */
        System.assertEquals(
            System.Label.Closed,
            claimAfter.Status,
            'Claim should be processed during test execution.'
        );
    }


    /* =========================================================
       OLDER CLAIM ITEM
       ========================================================= */

    @IsTest
    static void testExecuteWithOlderClaimItem() {

        Claim claimRec = [
            SELECT
                Id,
                Status,
                LastModifiedDate
            FROM Claim
            WHERE Status = :System.Label.Open
            LIMIT 1
        ];


        ClaimItem claimItemRec = [
            SELECT
                Id,
                ClaimId,
                LastModifiedDate
            FROM ClaimItem
            WHERE ClaimId = :claimRec.Id
            LIMIT 1
        ];


        System.assertNotEquals(
            null,
            claimItemRec.Id,
            'A Claim Item should exist for this test.'
        );


        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        /*
         * Make daysCheck later than the Claim Item's
         * LastModifiedDate.
         *
         * Therefore:
         *
         * LastModifiedDate > daysCheck
         *
         * evaluates to FALSE.
         */
        batchObj.daysCheck =
            System.now().addMinutes(5);


        Test.startTest();

        batchObj.execute(
            null,
            new List<Claim>{
                claimRec
            }
        );

        Test.stopTest();


        Claim claimAfter = [
            SELECT
                Id,
                Status
            FROM Claim
            WHERE Id = :claimRec.Id
        ];


        System.assertEquals(
            System.Label.Closed,
            claimAfter.Status,
            'Claim should be closed when the Claim Item is not recent.'
        );
    }


    /* =========================================================
       CLAIM WITHOUT CLAIM ITEMS
       ========================================================= */

    @IsTest
    static void testExecuteWithoutClaimItems() {

        /*
         * Reuse the Claim created by @TestSetup.
         *
         * Do not create another Policy because the test factory
         * can create duplicate Contract Number data.
         */
        Claim claimRec = [
            SELECT
                Id,
                Status,
                LastModifiedDate
            FROM Claim
            WHERE Status = :System.Label.Open
            LIMIT 1
        ];


        /*
         * Delete existing Claim Items so that the production
         * code enters the empty Claim Item branch.
         */
        List<ClaimItem> existingItems = [
            SELECT
                Id
            FROM ClaimItem
            WHERE ClaimId = :claimRec.Id
        ];


        if (!existingItems.isEmpty()) {
            delete existingItems;
        }


        Integer claimItemCount = [
            SELECT COUNT()
            FROM ClaimItem
            WHERE ClaimId = :claimRec.Id
        ];


        System.assertEquals(
            0,
            claimItemCount,
            'The Claim must have no Claim Items for this test.'
        );


        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        Test.startTest();

        batchObj.execute(
            null,
            new List<Claim>{
                claimRec
            }
        );

        Test.stopTest();


        Claim claimAfter = [
            SELECT
                Id,
                Status
            FROM Claim
            WHERE Id = :claimRec.Id
        ];


        System.assertEquals(
            System.Label.Closed,
            claimAfter.Status,
            'A Claim without Claim Items should still be processed.'
        );
    }


    /* =========================================================
       START + FINISH
       ========================================================= */

    @IsTest
    static void testStartAndFinishMethods() {

        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        Test.startTest();

        Database.QueryLocator locator =
            batchObj.start(null);

        batchObj.finish(null);

        Test.stopTest();


        System.assertNotEquals(
            null,
            locator,
            'start() should return a QueryLocator.'
        );
    }


    /* =========================================================
       EMPTY EXECUTE SCOPE
       ========================================================= */

    @IsTest
    static void testExecuteWithEmptyScope() {

        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        Test.startTest();

        batchObj.execute(
            null,
            new List<Claim>()
        );

        Test.stopTest();


        System.assert(
            true,
            'Empty scope should be handled safely.'
        );
    }


    /* =========================================================
       DEFENSIVE EXCEPTION HANDLING
       ========================================================= */

    @IsTest
    static void testExecuteDefensiveExceptionHandling() {

        CloseClaimUpdateBatchClass batchObj =
            new CloseClaimUpdateBatchClass();


        Test.startTest();

        /*
         * null forces listOfClaims.isEmpty() to throw.
         *
         * Production execute() catches Exception,
         * so the exception should not escape.
         */
        batchObj.execute(
            null,
            null
        );

        Test.stopTest();


        System.assert(
            true,
            'execute() should catch unexpected exceptions.'
        );
    }


    /* =========================================================
       SCHEDULER
       ========================================================= */

    @IsTest
    static void testSchedule() {

        ClaimUpdateBatchScheduler batchSchObj =
            new ClaimUpdateBatchScheduler();


        String cronExpression =
            '0 0 23 * * ?';


        Test.startTest();

        String schedulerJobId =
            System.schedule(
                'Test Claim Close Scheduler',
                cronExpression,
                batchSchObj
            );


        CronTrigger scheduledJob = [
            SELECT
                Id,
                State,
                CronExpression
            FROM CronTrigger
            WHERE Id = :schedulerJobId
            LIMIT 1
        ];


        System.assertEquals(
            cronExpression,
            scheduledJob.CronExpression,
            'Scheduler should use the expected CRON expression.'
        );


        Test.stopTest();
    }
}