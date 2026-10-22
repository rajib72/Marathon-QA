/**
 * @author Hitarth Trivedi
 * @dateModified 2026-09-30
 * @description
 * Test class for ClaimPrintoutTokenDataExtractor.
 *
 * Covers:
 * - Eligible Claim creation
 * - Claim token generation
 * - Contract token generation
 * - Repair Shop token generation
 * - Payee token generation
 * - Payment token generation
 * - Part/Labor/Sublet/Towing/Rental/Other/Deductible totals
 * - WEX path
 * - Unsupported method path
 * - Missing ContextId path
 * - Exception handling path
 */
@IsTest
public class ClaimPrintoutTokenDataExtractorTest {

    private static final String TEST_VIN =
        '1HGCM66554A033052';


    /* =========================================================
       VALIDATION BYPASS
       ========================================================= */

    /**
     * The purpose of this test is Claim Printout token generation,
     * not ClaimItem authorization validation.
     *
     * Use the existing org validation bypass for ClaimItem-specific
     * validation rules.
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


    /* =========================================================
       GENERIC FIELD HELPERS
       ========================================================= */

    /**
     * Puts a value on a field only when the field exists and
     * is updateable.
     *
     * Useful where fields may be Formula/derived fields in
     * another environment.
     */
    private static void putIfUpdateable(
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
            fieldDescribe.isUpdateable() &&
            !fieldDescribe.isCalculated()
        ) {
            record.put(
                fieldApiName,
                value
            );
        }
    }


    /**
     * Sets the first active picklist value for the requested
     * field.
     */
    private static void setFirstActivePicklistValue(
        SObject record,
        String fieldApiName
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
            !fieldDescribe.isCreateable() ||
            fieldDescribe.getType() !=
                Schema.DisplayType.Picklist
        ) {
            return;
        }

        for (
            Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()
        ) {

            if (entry.isActive()) {

                record.put(
                    fieldApiName,
                    entry.getValue()
                );

                return;
            }
        }
    }


    /**
     * Creates a clean SObject containing only fields that are
     * actually insertable.
     *
     * Protects the test from factory records containing Formula,
     * Auto Number or other non-createable fields.
     */
    private static SObject getInsertableRecord(
        SObject sourceRecord
    ) {

        Schema.SObjectType objectType =
            sourceRecord.getSObjectType();

        Map<String, Schema.SObjectField> fieldMap =
            objectType
                .getDescribe()
                .fields
                .getMap();

        Map<String, Object> populatedValues =
            sourceRecord
                .getPopulatedFieldsAsMap();

        SObject cleanRecord =
            objectType.newSObject();

        for (
            String fieldName :
            populatedValues.keySet()
        ) {

            if (
                fieldName == 'Id' ||
                !fieldMap.containsKey(fieldName)
            ) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap
                    .get(fieldName)
                    .getDescribe();

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


    /* =========================================================
       ELIGIBLE CLAIM CREATION
       ========================================================= */

    /**
     * Creates the Claim BEFORE DML with ReportDate and Mileage
     * inside the Insurance Policy eligibility window.
     *
     * This specifically prevents:
     *
     * Prevent_Processing_of_Ineligible_Claims
     */
    private static Claim createEligibleClaim(
        Id policyId,
        Id repairShopId
    ) {

        InsurancePolicy policyRec = [
            SELECT
                Id,
                Sale_Date__c,
                Effective_Date__c,
                Expiration_Date__c,
                Vehicle_Mileage_at_Contract_Inception__c,
                Effective_Mileage__c,
                Expiration_Mileage__c,
                RecordType.Name
            FROM InsurancePolicy
            WHERE Id = :policyId
            LIMIT 1
        ];


        Claim claimRec =
            TestDataFactory.createClaim(
                false,
                policyId
            );

        claimRec.PolicyNumberId =
            policyId;

        claimRec.Repair_Shop_Account__c =
            repairShopId;


        /* =====================================================
           ELIGIBLE REPORT DATE
           ===================================================== */

        Date eligibleReportDate;

        if (
            policyRec.Effective_Date__c != null
        ) {

            eligibleReportDate =
                policyRec.Effective_Date__c;

        } else if (
            policyRec.Sale_Date__c != null
        ) {

            eligibleReportDate =
                policyRec.Sale_Date__c;

        } else {

            eligibleReportDate =
                Date.today();
        }


        /*
         * Report Date must not precede Sale Date.
         */
        if (
            policyRec.Sale_Date__c != null &&
            eligibleReportDate <
                policyRec.Sale_Date__c
        ) {

            eligibleReportDate =
                policyRec.Sale_Date__c;
        }


        /*
         * Expiration is exclusive according to the validation:
         *
         * ReportDate >= Expiration => invalid
         */
        if (
            policyRec.Expiration_Date__c != null &&
            eligibleReportDate >=
                policyRec.Expiration_Date__c
        ) {

            eligibleReportDate =
                policyRec
                    .Expiration_Date__c
                    .addDays(-1);
        }


        claimRec.ReportDate =
            DateTime.newInstance(
                eligibleReportDate,
                Time.newInstance(
                    12,
                    0,
                    0,
                    0
                )
            );


        /* =====================================================
           ELIGIBLE MILEAGE
           ===================================================== */

        Decimal eligibleMileage =
            0;


        if (
            policyRec
                .Vehicle_Mileage_at_Contract_Inception__c
                != null
        ) {

            eligibleMileage =
                policyRec
                    .Vehicle_Mileage_at_Contract_Inception__c;
        }


        if (
            policyRec.Effective_Mileage__c != null &&
            eligibleMileage <
                policyRec.Effective_Mileage__c
        ) {

            eligibleMileage =
                policyRec.Effective_Mileage__c;
        }


        /*
         * Expiration Mileage is also exclusive.
         */
        if (
            policyRec.Expiration_Mileage__c != null &&
            eligibleMileage >=
                policyRec.Expiration_Mileage__c
        ) {

            eligibleMileage =
                policyRec.Expiration_Mileage__c - 1;
        }


        claimRec.Mileage__c =
            eligibleMileage;


        /* =====================================================
           AUTO CLAIM REQUIRED FIELDS
           ===================================================== */

        claimRec.Labor_Rate__c =
            100;

        claimRec.ReportNumber =
            'RO-CPT-001';

        claimRec.Repair_Number__c =
            'REPAIR-CPT-001';


        setFirstActivePicklistValue(
            claimRec,
            'Driven_or_Towed_In__c'
        );

        setFirstActivePicklistValue(
            claimRec,
            'Parts_Warranty__c'
        );


        Claim cleanClaim =
            (Claim)getInsertableRecord(
                claimRec
            );


        /*
         * Insert only AFTER Report Date and Mileage have
         * been normalized.
         */
        insert cleanClaim;


        return cleanClaim;
    }


    /* =========================================================
       TEST DATA
       ========================================================= */

    @TestSetup
    static void setupTestData() {

        enableClaimItemValidationBypass();


        /* -----------------------------------------------------
           REPAIR SHOP / CLIENT / LIEN HOLDER
           ----------------------------------------------------- */

        Id serviceCenterRecordTypeId =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Service_Center')
                .getRecordTypeId();


        Account repairShop =
            new Account(
                Name =
                    'Claim Printout Repair Shop',

                AccountNumber =
                    'CLIENT-1234',

                RecordTypeId =
                    serviceCenterRecordTypeId,

                BillingStreet =
                    '100 Test Street',

                BillingCity =
                    'Austin',

                BillingState =
                    'TX',

                BillingPostalCode =
                    '78701',

                BillingCountry =
                    'United States',

                Phone =
                    '5125550100',

                Fax =
                    '5125550101',

                Email__c =
                    'claimprintout@test.com'
            );


        insert repairShop;


        /* -----------------------------------------------------
           NAME INSURED / CUSTOMER
           ----------------------------------------------------- */

        Account insuredAccount =
            TestDataFactory.createAccount(
                true
            );


        insuredAccount.AccountNumber =
            'INSURED-1234';


        /*
         * Sold_Contract_Validation checks these fields through
         * NameInsured during InsurancePolicy INSERT.
         */
        putIfUpdateable(
            insuredAccount,
            'FirstName',
            'Test'
        );

        putIfUpdateable(
            insuredAccount,
            'LastName',
            'Insured'
        );

        putIfUpdateable(
            insuredAccount,
            'BillingStreet',
            '100 Test Street'
        );

        putIfUpdateable(
            insuredAccount,
            'BillingCity',
            'Austin'
        );

        putIfUpdateable(
            insuredAccount,
            'BillingState',
            'TX'
        );

        putIfUpdateable(
            insuredAccount,
            'BillingPostalCode',
            '78701'
        );

        putIfUpdateable(
            insuredAccount,
            'Email__c',
            'insured@test.com'
        );

        putIfUpdateable(
            insuredAccount,
            'Phone',
            '5125550200'
        );


        update insuredAccount;


        /* -----------------------------------------------------
           INSURANCE POLICY
           ----------------------------------------------------- */

        /*
         * IMPORTANT:
         *
         * FALSE prevents TestDataFactory from inserting the
         * InsurancePolicy immediately.
         *
         * Sold_Contract_Validation uses ISNEW(), therefore
         * mandatory fields must be populated BEFORE INSERT.
         */
        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                insuredAccount.Id
            );


        /* -----------------------------------------------------
           CLIENT / LIEN HOLDER / VEHICLE
           ----------------------------------------------------- */

        policyRec.Client__c =
            repairShop.Id;

        policyRec.Lien_Holder__c =
            repairShop.Id;

        policyRec.VIN__c =
            TEST_VIN;

        policyRec.Vehicle_Year__c =
            '2023';


        /* -----------------------------------------------------
           AUTO WARRANTY REQUIRED FIELDS
           ----------------------------------------------------- */

        policyRec.Vehicle_Mileage_at_Contract_Inception__c =
            1000;

        policyRec.Contract_Term_Mileage__c =
            100000;

        policyRec.Contract_Term_Months__c =
            12;

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


        /* -----------------------------------------------------
           SALE / EFFECTIVE / EXPIRATION DATES
           ----------------------------------------------------- */

        Date testSaleDate =
            Date.today().addDays(-30);

        Date testEffectiveDate =
            Date.today().addDays(-20);

        Date testExpirationDate =
            Date.today().addDays(365);


        /*
         * Used by ClaimPrintoutTokenDataExtractor itself.
         */
        policyRec.SaleDate =
            testSaleDate;


        /*
         * Used by Sold_Contract_Validation and Claim eligibility.
         */
        putIfUpdateable(
            policyRec,
            'Sale_Date__c',
            testSaleDate
        );

        putIfUpdateable(
            policyRec,
            'Effective_Date__c',
            testEffectiveDate
        );

        putIfUpdateable(
            policyRec,
            'Expiration_Date__c',
            testExpirationDate
        );


        /* -----------------------------------------------------
           MILEAGE ELIGIBILITY
           ----------------------------------------------------- */

        putIfUpdateable(
            policyRec,
            'Effective_Mileage__c',
            1000
        );

        putIfUpdateable(
            policyRec,
            'Expiration_Mileage__c',
            100000
        );


        /* -----------------------------------------------------
           FULFILLMENT DATE
           ----------------------------------------------------- */

        /*
         * Auto_Warranty requires Fulfillment_Date__c unless
         * Client AccountNumber = END.
         */
        putIfUpdateable(
            policyRec,
            'Fulfillment_Date__c',
            testSaleDate
        );


        /* -----------------------------------------------------
           INSERT INSURANCE POLICY
           ----------------------------------------------------- */

        /*
         * IMPORTANT:
         *
         * This is the FIRST InsurancePolicy DML.
         *
         * All fields required by Sold_Contract_Validation
         * have now been populated.
         */
        insert policyRec;


        /* -----------------------------------------------------
           ELIGIBLE CLAIM
           ----------------------------------------------------- */

        Claim claimRec =
            createEligibleClaim(
                policyRec.Id,
                repairShop.Id
            );


        /* -----------------------------------------------------
           PAYMENT
           ----------------------------------------------------- */

        Payment__c factoryPayment =
            TestDataFactory.createPayment2(
                false,
                repairShop.Id
            );


        factoryPayment.Account__c =
            repairShop.Id;


        /*
         * Keep these blank during insert so
         * PaymentTriggerHandler does not attempt imported
         * payment matching.
         */
        factoryPayment.Claim_Number__c =
            null;

        factoryPayment.VIN__c =
            null;


        Payment__c paymentRec =
            (Payment__c)getInsertableRecord(
                factoryPayment
            );


        insert paymentRec;


        /* -----------------------------------------------------
           PAID CLAIM ITEMS
           
           ClaimPrintoutTokenDataExtractor only queries PAID
           Claim Items, so create every relevant Detail Type.
           ----------------------------------------------------- */

        List<String> detailTypes =
            new List<String>{
                'Part',
                'Labor',
                'Sublet',
                'Towing',
                'Rental',
                'Other',
                'Deductible'
            };


        List<ClaimItem> claimItems =
            new List<ClaimItem>();


        Integer jobNumber =
            1;


        for (
            String detailType :
            detailTypes
        ) {

            ClaimItem item =
                TestDataFactory.createClaimItem2(
                    false,
                    claimRec.Id,
                    repairShop.Id,
                    paymentRec.Id,
                    'Paid'
                );


            item.ClaimId =
                claimRec.Id;

            item.Payee_Name__c =
                repairShop.Id;

            item.Payment__c =
                paymentRec.Id;

            item.Status__c =
                'Paid';

            item.Detail_Type__c =
                detailType;

            item.Job_Number__c =
                String.valueOf(
                    jobNumber
                );

            item.Quantity__c =
                1;

            item.Rate__c =
                100;


            /*
             * Exercise WEX = true branch on one item.
             */
            item.Wex__c =
                jobNumber == 1;


            claimItems.add(
                item
            );


            jobNumber++;
        }


        insert claimItems;
    }


    /* =========================================================
       MAIN SUCCESS TEST
       ========================================================= */

    @IsTest
    static void testGetTokenDataSuccess() {

        Claim claimRec = [
            SELECT
                Id,
                Name
            FROM Claim
            WHERE ReportNumber =
                'RO-CPT-001'
            LIMIT 1
        ];


        Map<String, Object> inputMap =
            new Map<String, Object>{
                'ContextId' =>
                    claimRec.Id
            };


        Map<String, Object> outputMap =
            new Map<String, Object>();


        Map<String, Object> options =
            new Map<String, Object>();


        ClaimPrintoutTokenDataExtractor token =
            new ClaimPrintoutTokenDataExtractor();


        Test.startTest();

        Boolean executed =
            (Boolean)token.invokeMethod(
                'getTokenData',
                inputMap,
                outputMap,
                options
            );

        Test.stopTest();


        System.assertEquals(
            true,
            executed,
            'getTokenData should complete successfully.'
        );


        System.assertNotEquals(
            null,
            outputMap.get('tokenMap'),
            'Token map must be returned.'
        );


        Map<String, Object> tokenMap =
            (Map<String, Object>)
                outputMap.get(
                    'tokenMap'
                );


        System.assertEquals(
            claimRec.Name,
            tokenMap.get(
                'ClaimNumber'
            ),
            'Claim Number should be populated.'
        );


        System.assertEquals(
            TEST_VIN,
            tokenMap.get(
                'ContractVIN'
            ),
            'VIN should come from the Insurance Policy.'
        );


        System.assertEquals(
            'Claim Printout Repair Shop',
            tokenMap.get(
                'ClaimRepairShopAccount'
            ),
            'Repair Shop should be added to the token map.'
        );


        System.assertNotEquals(
            null,
            tokenMap.get(
                'Payment'
            ),
            'Payment/Payee information must be populated.'
        );


        /*
         * Verify the aggregate keys are generated.
         */
        System.assert(
            tokenMap.containsKey(
                'ClaimItemsParts'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsLabor'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsSublet'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsTowing'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsRentalCar'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsOther'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsTax'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsSubtotal'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsDeductible'
            )
        );

        System.assert(
            tokenMap.containsKey(
                'ClaimItemsNetClaim'
            )
        );
    }


    /* =========================================================
       UNSUPPORTED METHOD
       ========================================================= */

    @IsTest
    static void testUnsupportedMethod() {

        ClaimPrintoutTokenDataExtractor token =
            new ClaimPrintoutTokenDataExtractor();


        Test.startTest();

        Boolean executed =
            (Boolean)token.invokeMethod(
                'getToken',
                new Map<String, Object>(),
                new Map<String, Object>(),
                new Map<String, Object>()
            );

        Test.stopTest();


        System.assertEquals(
            false,
            executed,
            'Unsupported method should return false.'
        );
    }


    /* =========================================================
       NULL CONTEXT
       ========================================================= */

    @IsTest
    static void testNullContextId() {

        ClaimPrintoutTokenDataExtractor token =
            new ClaimPrintoutTokenDataExtractor();


        Map<String, Object> inputMap =
            new Map<String, Object>{
                'ContextId' =>
                    null
            };


        Map<String, Object> outputMap =
            new Map<String, Object>();


        Test.startTest();

        Boolean executed =
            (Boolean)token.invokeMethod(
                'getTokenData',
                inputMap,
                outputMap,
                null
            );

        Test.stopTest();


        System.assertEquals(
            false,
            executed,
            'Null ContextId should safely return false.'
        );


        System.assertEquals(
            false,
            outputMap.containsKey(
                'tokenMap'
            )
        );
    }


    /* =========================================================
       EXCEPTION HANDLING
       ========================================================= */

    @IsTest
    static void testInvalidContextIdHandledSafely() {

        ClaimPrintoutTokenDataExtractor token =
            new ClaimPrintoutTokenDataExtractor();


        Map<String, Object> inputMap =
            new Map<String, Object>{
                'ContextId' =>
                    'INVALID-ID'
            };


        Map<String, Object> outputMap =
            new Map<String, Object>();


        Test.startTest();

        Boolean executed =
            (Boolean)token.invokeMethod(
                'getTokenData',
                inputMap,
                outputMap,
                null
            );

        Test.stopTest();


        /*
         * getClaimTokenData catches the exception internally.
         */
        System.assertEquals(
            false,
            executed,
            'Invalid Claim Id should be caught and return false.'
        );
    }
}