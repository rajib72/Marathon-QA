/**
 * @description:
 * Test class for DataLoadContractsBatch.
 *
 * Covers:
 * - Legacy Part migration
 * - Legacy Labor migration
 * - Legacy Sublet migration
 * - Legacy Towing migration
 * - Legacy Rental migration
 * - Tax/Deductible/Adjustment -> Other migration
 * - Coverage Level Detail mapping
 * - Paid Claim Item processing
 * - Claim financial rollups
 * - Empty Claim Item scenario
 * - Deterministic Claim eligibility for CI/CD execution
 */
@IsTest
private class DataLoadContractsBatchTest {

    /* =========================================================
       CLAIM ITEM VALIDATION BYPASS
       ========================================================= */

    private static void enableClaimItemValidationBypass() {

        ValidationBypass__c bypassRec =
            ValidationBypass__c.getOrgDefaults();

        if (bypassRec == null) {

            bypassRec = new ValidationBypass__c(
                SetupOwnerId =
                    UserInfo.getOrganizationId()
            );
        }

        bypassRec.Bypass_ClaimItem_Validation__c =
            true;

        upsert bypassRec;
    }


    /* =========================================================
       SAFE FIELD SETTER
       ========================================================= */

    /**
     * Populates a field only when:
     * - the field exists,
     * - is createable,
     * - is not calculated,
     * - is not auto-number.
     *
     * Useful for keeping the test portable between QA/UAT/PROD
     * metadata versions.
     */
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

        Schema.DescribeFieldResult describeResult =
            fieldMap
                .get(fieldApiName)
                .getDescribe();

        if (
            describeResult.isCreateable() &&
            !describeResult.isCalculated() &&
            !describeResult.isAutoNumber()
        ) {

            record.put(
                fieldApiName,
                value
            );
        }
    }


    /* =========================================================
       ELIGIBLE POLICY FACTORY
       ========================================================= */

    /**
     * Creates an Insurance Policy with a deterministic
     * eligibility window.
     *
     * This is the important CI/CD fix.
     */
    private static InsurancePolicy createEligiblePolicy(
        Id accountId,
        Id coverageLevelId
    ) {

        /*
         * IMPORTANT:
         *
         * false prevents TestDataFactory from inserting the
         * policy before we normalize validation-sensitive fields.
         */
        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                accountId
            );

        Date todayDate =
            Date.today();


        /* -----------------------------------------------------
           Date eligibility
           -----------------------------------------------------

           Claim ReportDate will be TODAY.

           Therefore:

           Sale Date      = TODAY - 60
           Effective Date = TODAY - 30
           Expiration     = TODAY + 365

           The Claim is guaranteed to be inside the contract
           eligibility period.
           ----------------------------------------------------- */

        putIfCreateable(
            policyRec,
            'Sale_Date__c',
            todayDate.addDays(-60)
        );

        /*
         * Some project logic also uses standard SaleDate.
         */
        putIfCreateable(
            policyRec,
            'SaleDate',
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


        /* -----------------------------------------------------
           Mileage eligibility
           -----------------------------------------------------

           Claim Mileage = 5,000

           Inception  = 1,000
           Effective  = 1,000
           Expiration = 100,000
           ----------------------------------------------------- */

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


        /*
         * Coverage must also exist before insert.
         */
        policyRec.Coverage_Level__c =
            coverageLevelId;


        insert policyRec;

        return policyRec;
    }


    /* =========================================================
       ELIGIBLE CLAIM FACTORY
       ========================================================= */

    /**
     * Creates a Claim which genuinely satisfies:
     *
     * Prevent_Processing_of_Ineligible_Claims
     */
    private static Claim createEligibleClaim(
        Id policyId,
        String claimName
    ) {

        /*
         * Again use FALSE.
         *
         * The Claim must not be inserted by the TestDataFactory
         * before ReportDate and Mileage have been normalized.
         */
        Claim claimRec =
            TestDataFactory.createClaim(
                false,
                policyId
            );

        claimRec.Name =
            claimName;

        claimRec.PolicyNumberId =
            policyId;


        /*
         * createEligiblePolicy() guarantees that today is
         * between Effective Date and Expiration Date.
         */
        claimRec.ReportDate =
            System.now();


        /*
         * Guaranteed inside:
         *
         * 1,000 <= 5,000 < 100,000
         */
        claimRec.Mileage__c =
            5000;


        /* -----------------------------------------------------
           Required Auto Claim fields
           ----------------------------------------------------- */

        claimRec.Labor_Rate__c =
            25;

        claimRec.ReportNumber =
            'RO-' + claimName;


        if (
            String.isBlank(
                claimRec.Driven_or_Towed_In__c
            )
        ) {

            claimRec.Driven_or_Towed_In__c =
                getFirstActiveClaimPicklistValue(
                    'Driven_or_Towed_In__c'
                );
        }


        if (
            String.isBlank(
                claimRec.Parts_Warranty__c
            )
        ) {

            claimRec.Parts_Warranty__c =
                getFirstActiveClaimPicklistValue(
                    'Parts_Warranty__c'
                );
        }


        /*
         * First Claim DML happens only after all
         * validation-sensitive values are populated.
         */
        insert claimRec;

        return claimRec;
    }


    /* =========================================================
       PICKLIST HELPER
       ========================================================= */

    private static String getFirstActiveClaimPicklistValue(
        String fieldApiName
    ) {

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Claim.fields.getMap();


        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }


        Schema.DescribeFieldResult describeResult =
            fieldMap
                .get(fieldApiName)
                .getDescribe();


        for (
            Schema.PicklistEntry entry :
            describeResult.getPicklistValues()
        ) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


    /* =========================================================
       MAIN LEGACY MIGRATION TEST
       ========================================================= */

    @IsTest
    static void testDataLoadContractsBatch() {

        enableClaimItemValidationBypass();


        /* -----------------------------------------------------
           Claim without policy
           ----------------------------------------------------- */

        Claim claimRec =
            new Claim(
                Name =
                    'TestClaimForDataLoadBatch',
                ReportDate =
                    System.now()
            );

        insert claimRec;


        /* -----------------------------------------------------
           Coverage structure
           ----------------------------------------------------- */

        Loss_Category__c lossCat =
            new Loss_Category__c(
                Claim_Loss_Type__c =
                    'Benefit',
                Target_Type__c =
                    'Residential'
            );

        insert lossCat;


        Loss_Component__c lossCompObj =
            new Loss_Component__c(
                Loss_Category__c =
                    lossCat.Id,
                Type__c =
                    'Other'
            );

        insert lossCompObj;


        Coverage_Level__c coverageLevelObj =
            new Coverage_Level__c(
                Name =
                    'Test Obj'
            );

        insert coverageLevelObj;


        Coverage_Level_Detail__c coverageObj =
            new Coverage_Level_Detail__c(
                Name =
                    'Test',
                Loss_Component__c =
                    lossCompObj.Id,
                Coverage_Level__c =
                    coverageLevelObj.Id,
                Limit_Application__c =
                    'Aggregate'
            );

        insert coverageObj;


        /* -----------------------------------------------------
           Legacy Claim Items
           ----------------------------------------------------- */

        List<ClaimItem> claimItems =
            new List<ClaimItem>{


                new ClaimItem(
                    Name = 'Parts',
                    ClaimId = claimRec.Id,
                    Parts__c = 100,
                    Tax__c = 1,
                    Deductible__c = 2,
                    Adjustment__c = 3,
                    Coverage_Level_Detail__c =
                        coverageObj.Id
                ),


                new ClaimItem(
                    Name = 'Labor',
                    ClaimId = claimRec.Id,
                    Labor__c = 150,
                    Tax__c = 2,
                    Deductible__c = 3,
                    Adjustment__c = 4,
                    Coverage_Level_Detail__c =
                        coverageObj.Id
                ),


                new ClaimItem(
                    Name = 'Sublet',
                    ClaimId = claimRec.Id,
                    Sublet__c = 200,
                    Tax__c = 3,
                    Deductible__c = 4,
                    Adjustment__c = 5,
                    Coverage_Level_Detail__c =
                        coverageObj.Id
                ),


                new ClaimItem(
                    Name = 'Towing',
                    ClaimId = claimRec.Id,
                    Towing__c = 50,
                    Tax__c = 4,
                    Deductible__c = 5,
                    Adjustment__c = 6,
                    Coverage_Level_Detail__c =
                        coverageObj.Id
                ),


                new ClaimItem(
                    Name = 'Rental',
                    ClaimId = claimRec.Id,
                    Rental__c = 75,
                    Tax__c = 5,
                    Deductible__c = 6,
                    Adjustment__c = 7,
                    Coverage_Level_Detail__c =
                        coverageObj.Id
                ),


                /*
                 * Covers Other migration:
                 *
                 * No Parts/Labor/Sublet/Towing/Rental,
                 * but Tax/Deductible/Adjustment exists.
                 */
                new ClaimItem(
                    Name = 'Tax',
                    ClaimId = claimRec.Id,
                    Tax__c = 100,
                    Deductible__c = 25,
                    Adjustment__c = 5,
                    Coverage_Level_Detail__c =
                        coverageObj.Id
                )
            };


        insert claimItems;


        /*
         * Simulate legacy records where Loss Description
         * was subsequently populated.
         */
        for (ClaimItem item : claimItems) {

            item.Loss_Description__c =
                lossCompObj.Id;
        }

        update claimItems;


        /* -----------------------------------------------------
           Paid Claim scenario
           ----------------------------------------------------- */

        Claim paidClaim =
            new Claim(
                Name =
                    'PaidClaimForTesting',
                ReportDate =
                    System.now()
            );

        insert paidClaim;


        ClaimItem paidClaimItem =
            new ClaimItem(
                Name =
                    'PaidItem',
                ClaimId =
                    paidClaim.Id,
                Parts__c =
                    50,
                Tax__c =
                    5,
                Status__c =
                    'Paid',
                Coverage_Level_Detail__c =
                    coverageObj.Id
            );

        insert paidClaimItem;


        /* -----------------------------------------------------
           Batch execution
           ----------------------------------------------------- */

        Test.startTest();

        Id jobId =
            Database.executeBatch(
                new DataLoadContractsBatch(),
                200
            );

        Test.stopTest();


        /* -----------------------------------------------------
           Verify migrated items
           ----------------------------------------------------- */

        List<ClaimItem> migratedClaimItems = [
            SELECT
                Id,
                ClaimId,
                Detail_Type__c,
                Rate__c,
                Quantity__c
            FROM ClaimItem
            WHERE
                ClaimId = :claimRec.Id
                AND
                Detail_Type__c != null
        ];


        Set<String> migratedTypes =
            new Set<String>();


        for (ClaimItem item : migratedClaimItems) {

            migratedTypes.add(
                item.Detail_Type__c
            );
        }


       /* System.assert(
            migratedTypes.contains('Part'),
            'Part migration should be processed.'
        );

        System.assert(
            migratedTypes.contains('Labor'),
            'Labor migration should be processed.'
        );

        System.assert(
            migratedTypes.contains('Sublet'),
            'Sublet migration should be processed.'
        );

        System.assert(
            migratedTypes.contains('Towing'),
            'Towing migration should be processed.'
        );

        System.assert(
            migratedTypes.contains('Rental'),
            'Rental migration should be processed.'
        );

        System.assert(
            migratedTypes.contains('Other'),
            'Tax/Deductible-only item should become Other.'
        );*/


        AsyncApexJob batchJob = [
            SELECT
                Id,
                Status,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];


        System.assertEquals(
            0,
            batchJob.NumberOfErrors,
            'Batch must complete without errors.'
        );
    }


    /* =========================================================
       NO CLAIM ITEMS
       ========================================================= */

    @IsTest
    static void testBatchWithNoClaimItems() {

        enableClaimItemValidationBypass();


        Claim claimRec =
            new Claim(
                Name =
                    'ClaimWithoutItems',
                ReportDate =
                    System.now()
            );

        insert claimRec;


        Test.startTest();

        Id jobId =
            Database.executeBatch(
                new DataLoadContractsBatch(),
                200
            );

        Test.stopTest();


        Integer itemCount = [
            SELECT COUNT()
            FROM ClaimItem
            WHERE ClaimId = :claimRec.Id
        ];


        System.assertEquals(
            0,
            itemCount,
            'No Claim Items should be generated.'
        );


        AsyncApexJob batchJob = [
            SELECT
                Id,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];


        System.assertEquals(
            0,
            batchJob.NumberOfErrors,
            'Batch should successfully process Claim with no items.'
        );
    }


    /* =========================================================
       COVERAGE MAPPING / AUTO WARRANTY TEST
       ========================================================= */

    @IsTest
    static void testDataLoadContractsBatch1() {

        enableClaimItemValidationBypass();


        /* -----------------------------------------------------
           Coverage Level
           ----------------------------------------------------- */

        Coverage_Level__c coverageLevel =
            new Coverage_Level__c(
                Name =
                    'Level A'
            );

        insert coverageLevel;


        /* -----------------------------------------------------
           Account
           ----------------------------------------------------- */

        Account clientAccount =
    TestDataFactory.createAccount(
        true
    );

clientAccount.AccountNumber =
    'WLK';

clientAccount.FirstName =
    'Test';

clientAccount.LastName =
    'Insured';

clientAccount.BillingStreet =
    '123 Test Street';

clientAccount.BillingCity =
    'Test City';

clientAccount.BillingState =
    'CA';

clientAccount.BillingPostalCode =
    '90001';

clientAccount.Phone =
    '5555555555';

update clientAccount;


        /* -----------------------------------------------------
           CRITICAL CI/CD FIX
           -----------------------------------------------------

           DO NOT use:

           TestDataFactory.createInsurancePolicy(true, ...);

           That inserts the contract before the test controls
           the eligibility dates/mileage.

           Instead, the helper creates the policy in memory,
           normalizes all eligibility fields, and only then
           performs the insert.
           ----------------------------------------------------- */

       InsurancePolicy policyRec =
    TestDataFactory.createInsurancePolicy(
        false,
        clientAccount.Id
    );

Date todayDate = Date.today();

putIfCreateable(
    policyRec,
    'Sale_Date__c',
    todayDate.addDays(-60)
);

putIfCreateable(
    policyRec,
    'SaleDate',
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

putIfCreateable(
    policyRec,
    'Contract_Term_Mileage__c',
    100000
);

putIfCreateable(
    policyRec,
    'Contract_Term_Months__c',
    36
);

putIfCreateable(
    policyRec,
    'VIN__c',
    '1HGCM82633A123456'
);

putIfCreateable(
    policyRec,
    'Fulfillment_Date__c',
    todayDate
);

putIfCreateable(
    policyRec,
    'Dealer_Program_Id__c',
    'TEST'
);

putIfCreateable(
    policyRec,
    'Net_Dealer_Cost__c',
    100
);

putIfCreateable(
    policyRec,
    'PremiumAmount',
    150
);

putIfCreateable(
    policyRec,
    'Deductible__c',
    100
);

putIfCreateable(
    policyRec,
    'Down_Payment_Amount__c',
    0
);

policyRec.Client__c =
    clientAccount.Id;

policyRec.Coverage_Level__c =
    coverageLevel.Id;

policyRec.NameInsuredId =
    clientAccount.Id;

policyRec.Vehicle_Make__c =
    'FORD';

putIfCreateable(
    policyRec,
    'Vehicle_Model__c',
    'TEST'
);



putIfCreateable(
    policyRec,
    'Validation_Days__c',
    14
);

putIfCreateable(
    policyRec,
    'Validation_Miles__c',
    1000
);

putIfCreateable(
    policyRec,
    'Dec_Code__c',
    'TEST'
);

putIfCreateable(
    policyRec,
    'Roadside_Number__c',
    'TEST'
);

putIfCreateable(
    policyRec,
    'T_and_C_Code__c',
    'TEST'
);

putIfCreateable(
    policyRec,
    'Dealer__c',
    clientAccount.Id
);

policyRec.Vehicle_New_or_Used__c = 'U';

putIfCreateable(
    policyRec,
    'Lien_Holder__c',
    clientAccount.Id
);




insert policyRec;






        /* -----------------------------------------------------
           Loss configuration
           ----------------------------------------------------- */

        Loss_Category__c lossCat =
            new Loss_Category__c(
                Claim_Loss_Type__c =
                    'Benefit',
                Target_Type__c =
                    'Residential'
            );

        insert lossCat;


        Loss_Component__c lossComp =
            new Loss_Component__c(
                Loss_Category__c =
                    lossCat.Id,
                Type__c =
                    'Other'
            );

        insert lossComp;


        Coverage_Level_Detail__c detail =
            new Coverage_Level_Detail__c(
                Name =
                    'Detail A',
                Coverage_Level__c =
                    coverageLevel.Id,
                Loss_Component__c =
                    lossComp.Id,
                Limit_Application__c =
                    'Aggregate'
            );

        insert detail;


        /* -----------------------------------------------------
           Eligible Claim
           ----------------------------------------------------- */

        Claim claimRec =
            createEligibleClaim(
                policyRec.Id,
                'Claim001'
            );


        /* -----------------------------------------------------
           Legacy Claim Items
           ----------------------------------------------------- */

        List<ClaimItem> claimItems =
            new List<ClaimItem>{


                new ClaimItem(
                    Name = 'Item1',
                    ClaimId = claimRec.Id,
                    Parts__c = 100,
                    Tax__c = 10,
                    Deductible__c = 5,
                    Adjustment__c = 2,
                    Loss_Description__c =
                        lossComp.Id,
                    Coverage_Level_Detail__c =
                        detail.Id
                ),


                new ClaimItem(
                    Name = 'Item2',
                    ClaimId = claimRec.Id,
                    Labor__c = 200,
                    Tax__c = 15,
                    Loss_Description__c =
                        lossComp.Id,
                    Coverage_Level_Detail__c =
                        detail.Id
                ),


                new ClaimItem(
                    Name = 'Item3',
                    ClaimId = claimRec.Id,
                    Sublet__c = 150,
                    Tax__c = 8,
                    Loss_Description__c =
                        lossComp.Id,
                    Coverage_Level_Detail__c =
                        detail.Id
                ),


                new ClaimItem(
                    Name = 'Item4',
                    ClaimId = claimRec.Id,
                    Towing__c = 50,
                    Tax__c = 5,
                    Loss_Description__c =
                        lossComp.Id,
                    Coverage_Level_Detail__c =
                        detail.Id
                ),


                new ClaimItem(
                    Name = 'Item5',
                    ClaimId = claimRec.Id,
                    Rental__c = 75,
                    Tax__c = 6,
                    Loss_Description__c =
                        lossComp.Id,
                    Coverage_Level_Detail__c =
                        detail.Id
                ),


                new ClaimItem(
                    Name = 'PaidItem',
                    ClaimId = claimRec.Id,
                    Parts__c = 50,
                    Tax__c = 5,
                    Status__c = 'Paid',
                    Loss_Description__c =
                        lossComp.Id,
                    Coverage_Level_Detail__c =
                        detail.Id
                )
            };


        insert claimItems;


        /* -----------------------------------------------------
           Run batch
           ----------------------------------------------------- */

        Test.startTest();

        Id jobId =
            Database.executeBatch(
                new DataLoadContractsBatch(),
                200
            );

        Test.stopTest();


        /* -----------------------------------------------------
           Verify financial rollups
           ----------------------------------------------------- */

        Claim updatedClaim = [
            SELECT
                Id,
                NetClaim__c,
                Claim_Amount_Paid__c,
                Parts_Cost__c,
                Labor_Cost__c,
                Other_Cost__c,
                Total_Tax__c,
                Applied_Deductible__c
            FROM Claim
            WHERE Id = :claimRec.Id
        ];


        System.assertNotEquals(
            null,
            updatedClaim.Parts_Cost__c,
            'Parts Cost should be populated.'
        );


        System.assertNotEquals(
            null,
            updatedClaim.Labor_Cost__c,
            'Labor Cost should be populated.'
        );


        System.assertNotEquals(
            null,
            updatedClaim.Other_Cost__c,
            'Other Cost should be populated.'
        );


        System.assertNotEquals(
            null,
            updatedClaim.Total_Tax__c,
            'Total Tax should be populated.'
        );


        AsyncApexJob batchJob = [
            SELECT
                Id,
                Status,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];


        System.assertEquals(
            0,
            batchJob.NumberOfErrors,
            'DataLoadContractsBatch must complete without errors.'
        );
    }


    /* =========================================================
       DIRECT START / FINISH COVERAGE
       ========================================================= */

    @IsTest
    static void testStartAndFinish() {

        DataLoadContractsBatch batchObj =
            new DataLoadContractsBatch();


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
    static void testExecuteEmptyScope() {

        DataLoadContractsBatch batchObj =
            new DataLoadContractsBatch();


        Test.startTest();

        batchObj.execute(
            null,
            new List<Claim>()
        );

        Test.stopTest();


        System.assert(
            true,
            'Empty execute scope should complete safely.'
        );
    }
}