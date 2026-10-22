/**
 * @author: Jigar Trivedi
 * @description:
 * Validation-safe test class for CARFAXIntegration.
 */
@IsTest
private class CARFAXIntegrationTest {

    private static final String TEST_VIN =
        '1HGCM66554A033052';


    /* =========================================================
       HTTP MOCKS
       ========================================================= */

    private class CarfaxSuccessMock
        implements HttpCalloutMock {

        public HTTPResponse respond(
            HTTPRequest request
        ) {

            System.assertEquals(
                'GET',
                request.getMethod()
            );

            System.assert(
                request.getEndpoint().contains(
                    'vin=' + TEST_VIN
                )
            );

            HTTPResponse response =
                new HTTPResponse();

            response.setStatusCode(200);

            response.setHeader(
                'Content-Type',
                'application/pdf'
            );

            response.setBody(
                '%PDF-1.4 Test CARFAX PDF'
            );

            return response;
        }
    }


    private class CarfaxFailureMock
        implements HttpCalloutMock {

        public HTTPResponse respond(
            HTTPRequest request
        ) {

            HTTPResponse response =
                new HTTPResponse();

            response.setStatusCode(500);

            response.setStatus(
                'Internal Server Error'
            );

            response.setBody(
                'CARFAX service unavailable'
            );

            return response;
        }
    }


    private class CarfaxExceptionMock
        implements HttpCalloutMock {

        public HTTPResponse respond(
            HTTPRequest request
        ) {

            throw new CalloutException(
                'Simulated CARFAX callout exception'
            );
        }
    }


    /* =========================================================
       GENERIC FIELD HELPERS
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

        Schema.DescribeFieldResult describe =
            fieldMap
                .get(fieldApiName)
                .getDescribe();

        if (
            describe.isCreateable() &&
            !describe.isCalculated() &&
            !describe.isAutoNumber()
        ) {

            record.put(
                fieldApiName,
                value
            );
        }
    }


    private static String getFirstActiveClaimPicklistValue(
        String fieldApiName
    ) {

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Claim
                .fields
                .getMap();

        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }

        for (
            Schema.PicklistEntry entry :
            fieldMap
                .get(fieldApiName)
                .getDescribe()
                .getPicklistValues()
        ) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


    /* =========================================================
       TEST DATA HELPERS
       ========================================================= */

    /**
     * Creates the Client / Name Insured Account.
     *
     * IMPORTANT:
     * WUS is intentionally used.
     *
     * It bypasses the general Sold Contract required-fields
     * validation while also avoiding the separate stricter
     * WLK/WFI validation path.
     */
    private static Account createCustomerAccount() {

        Account accountRec =
            TestDataFactory.createAccount(false);

        accountRec.AccountNumber =
            'WUS';

        // NameInsured fields
        accountRec.FirstName =
            'CARFAX';

        accountRec.LastName =
            'Customer';

        accountRec.BillingStreet =
            '100 Test Street';

        accountRec.BillingCity =
            'Chicago';

        accountRec.BillingState =
            'IL';

        accountRec.BillingPostalCode =
            '60601';

        accountRec.Phone =
            '3125550100';

        insert accountRec;

        return accountRec;
    }


    /**
     * Creates a Service Center Account.
     */
    private static Account createRepairShopAccount() {

        Account repairShop =
            new Account();

        Map<String, Schema.RecordTypeInfo> recordTypes =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName();

        if (
            recordTypes.containsKey(
                'Service_Center'
            )
        ) {

            repairShop.RecordTypeId =
                recordTypes
                    .get('Service_Center')
                    .getRecordTypeId();
        }

        repairShop.Name =
            'CARFAX Test Repair Shop';

        repairShop.AccountNumber =
            'CFXR001';

        repairShop.BillingStreet =
            '100 Test Street';

        repairShop.BillingCity =
            'Chicago';

        repairShop.BillingState =
            'IL';

        repairShop.BillingPostalCode =
            '60601';

        repairShop.BillingCountry =
            'USA';

        repairShop.Phone =
            '3125550100';

        repairShop.Website =
            'https://example.com';

        putIfCreateable(
            repairShop,
            'Email__c',
            'carfaxrepair@test.com'
        );

        insert repairShop;

        return repairShop;
    }


    /**
     * Creates an eligible InsurancePolicy.
     *
     * IMPORTANT:
     * TestDataFactory creates Coverage_Level__c together with
     * the contract values associated with that Coverage Level.
     *
     * Do NOT independently overwrite:
     *
     * Validation_Days__c
     * Validation_Miles__c
     * Contract_Term_Months__c
     * Contract_Term_Mileage__c
     */
    private static InsurancePolicy createEligiblePolicy(
        Id accountId
    ) {

        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                accountId
            );

        Date todayDate =
            Date.today();


        // =====================================================
        // RELATIONSHIPS
        // =====================================================

        putIfCreateable(
            policyRec,
            'Client__c',
            accountId
        );

        putIfCreateable(
            policyRec,
            'NameInsuredId',
            accountId
        );


        // =====================================================
        // SALE / ELIGIBILITY DATE
        // =====================================================

        putIfCreateable(
            policyRec,
            'SaleDate',
            todayDate.addDays(-60)
        );

        putIfCreateable(
            policyRec,
            'Sale_Date__c',
            todayDate.addDays(-60)
        );

        /*
         * These may be calculated/read-only.
         * putIfCreateable() safely ignores them when they
         * cannot be assigned.
         */
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


        // =====================================================
        // CLAIM ELIGIBILITY MILEAGE
        // =====================================================

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
            101000
        );


        // =====================================================
        // CARFAX VIN
        // =====================================================

        putIfCreateable(
            policyRec,
            'VIN__c',
            TEST_VIN
        );


        // =====================================================
        // INSERT POLICY
        // =====================================================

        insert policyRec;

        return policyRec;
    }


    /**
     * Creates a Claim inside the Policy eligibility window.
     */
    private static Claim createEligibleClaim(
        Id policyId,
        Id repairShopAccountId,
        Decimal usageCount,
        String claimSuffix
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


        putIfCreateable(
            claimRec,
            'Name',
            'CARFAX-TEST-' + claimSuffix
        );


        // =====================================================
        // REPORT DATE
        // =====================================================

        Date eligibleReportDate =
            Date.today();

        Date lowerDateBoundary =
            null;


        if (
            policyRec.Sale_Date__c != null
        ) {

            lowerDateBoundary =
                policyRec.Sale_Date__c;
        }


        if (
            policyRec.Effective_Date__c != null &&
            (
                lowerDateBoundary == null ||
                policyRec.Effective_Date__c >
                    lowerDateBoundary
            )
        ) {

            lowerDateBoundary =
                policyRec.Effective_Date__c;
        }


        if (
            lowerDateBoundary != null &&
            eligibleReportDate <
                lowerDateBoundary
        ) {

            eligibleReportDate =
                lowerDateBoundary;
        }


        if (
            policyRec.Expiration_Date__c != null &&
            eligibleReportDate >=
                policyRec.Expiration_Date__c
        ) {

            eligibleReportDate =
                policyRec.Expiration_Date__c
                    .addDays(-1);
        }


        claimRec.ReportDate =
            Datetime.newInstance(
                eligibleReportDate,
                Time.newInstance(
                    12,
                    0,
                    0,
                    0
                )
            );


        // =====================================================
        // MILEAGE
        // =====================================================

        Decimal eligibleMileage =
            0;

        Decimal lowerMileageBoundary =
            0;


        if (
            policyRec
                .Vehicle_Mileage_at_Contract_Inception__c
                != null
        ) {

            lowerMileageBoundary =
                policyRec
                    .Vehicle_Mileage_at_Contract_Inception__c;
        }


        if (
            policyRec.Effective_Mileage__c != null &&
            policyRec.Effective_Mileage__c >
                lowerMileageBoundary
        ) {

            lowerMileageBoundary =
                policyRec.Effective_Mileage__c;
        }


        eligibleMileage =
            lowerMileageBoundary;


        if (
            policyRec.Expiration_Mileage__c != null &&
            eligibleMileage >=
                policyRec.Expiration_Mileage__c
        ) {

            eligibleMileage =
                policyRec.Expiration_Mileage__c
                    - 1;
        }


        claimRec.Mileage__c =
            eligibleMileage;


        // =====================================================
        // REQUIRED CLAIM FIELDS
        // =====================================================

        claimRec.Labor_Rate__c =
            25;

        claimRec.ReportNumber =
            'RO-CARFAX-' + claimSuffix;

        claimRec.Repair_Shop_Account__c =
            repairShopAccountId;


        String drivenOrTowed =
            getFirstActiveClaimPicklistValue(
                'Driven_or_Towed_In__c'
            );

        if (drivenOrTowed != null) {

            claimRec.Driven_or_Towed_In__c =
                drivenOrTowed;
        }


        String partsWarranty =
            getFirstActiveClaimPicklistValue(
                'Parts_Warranty__c'
            );

        if (partsWarranty != null) {

            claimRec.Parts_Warranty__c =
                partsWarranty;
        }


        putIfCreateable(
            claimRec,
            'Repair_Email__c',
            'carfaxrepair@test.com'
        );

        putIfCreateable(
            claimRec,
            'Service_Phone_Number__c',
            '3125550100'
        );


        claimRec.Usage_Count__c =
            usageCount;


        insert claimRec;

        return claimRec;
    }


    /* =========================================================
       TEST SETUP
       ========================================================= */

    @TestSetup
    static void setupTestData() {

        Account customerAccount =
            createCustomerAccount();

        Account repairShop =
            createRepairShopAccount();

        InsurancePolicy policyRec =
            createEligiblePolicy(
                customerAccount.Id
            );


        // Usage Count = NULL
        createEligibleClaim(
            policyRec.Id,
            repairShop.Id,
            null,
            'NULL'
        );


        // Existing Usage Count
        createEligibleClaim(
            policyRec.Id,
            repairShop.Id,
            5,
            'EXIST'
        );
    }


    /* =========================================================
       CALLABLE ARGUMENT BUILDER
       ========================================================= */

    private static Map<String, Object> buildArgs(
        Id claimId
    ) {

        Map<String, Object> input =
            new Map<String, Object>{
                'ClaimId' => claimId,
                'VIN'     => TEST_VIN
            };

        Map<String, Object> output =
            new Map<String, Object>();

        Map<String, Object> options =
            new Map<String, Object>();


        return new Map<String, Object>{
            'input'   => input,
            'output'  => output,
            'options' => options
        };
    }


    /* =========================================================
       SUCCESS - USAGE COUNT NULL
       ========================================================= */

    @IsTest
    static void testCallSuccessUsageCountNull() {

        Claim clm = [
            SELECT
                Id,
                Usage_Count__c,
                Date_Processed__c
            FROM Claim
            WHERE Usage_Count__c = null
            LIMIT 1
        ];


        Test.setMock(
            HttpCalloutMock.class,
            new CarfaxSuccessMock()
        );


        Test.startTest();

        Map<String, Object> result =
            (Map<String, Object>)
            new CARFAXIntegration().call(
                'getCarFaxFile',
                buildArgs(clm.Id)
            );

        Test.stopTest();


        System.assertEquals(
            true,
            result.get('isSuccess')
        );

        System.assertNotEquals(
            null,
            result.get('contentDocumentId')
        );

        System.assertNotEquals(
            null,
            result.get('contentDocumentURL')
        );


        List<ContentDocumentLink> links = [
            SELECT
                Id,
                ContentDocumentId,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :clm.Id
        ];

        System.assertEquals(
            1,
            links.size()
        );


        Claim updatedClaim = [
            SELECT
                Usage_Count__c,
                Date_Processed__c
            FROM Claim
            WHERE Id = :clm.Id
        ];

        System.assertEquals(
            1,
            updatedClaim.Usage_Count__c
        );

        System.assertNotEquals(
            null,
            updatedClaim.Date_Processed__c
        );
    }


    /* =========================================================
       SUCCESS - EXISTING USAGE COUNT
       ========================================================= */

    @IsTest
    static void testCallSuccessExistingUsageCount() {

        Claim clm = [
            SELECT
                Id,
                Usage_Count__c
            FROM Claim
            WHERE Usage_Count__c = 5
            LIMIT 1
        ];


        Test.setMock(
            HttpCalloutMock.class,
            new CarfaxSuccessMock()
        );


        Test.startTest();

        Map<String, Object> result =
            (Map<String, Object>)
            new CARFAXIntegration().call(
                'getCarFaxFile',
                buildArgs(clm.Id)
            );

        Test.stopTest();


        System.assertEquals(
            true,
            result.get('isSuccess')
        );


        Claim updatedClaim = [
            SELECT
                Usage_Count__c,
                Date_Processed__c
            FROM Claim
            WHERE Id = :clm.Id
        ];

        System.assertEquals(
            6,
            updatedClaim.Usage_Count__c
        );

        System.assertNotEquals(
            null,
            updatedClaim.Date_Processed__c
        );
    }


    /* =========================================================
       NON-200 RESPONSE
       ========================================================= */

    @IsTest
    static void testCarfaxFailureResponse() {

        Claim clm = [
            SELECT Id
            FROM Claim
            LIMIT 1
        ];


        Test.setMock(
            HttpCalloutMock.class,
            new CarfaxFailureMock()
        );


        Test.startTest();

        Map<String, Object> result =
            (Map<String, Object>)
            CARFAXIntegration.getCarFaxFile(
                new Map<String, Object>(),
                String.valueOf(clm.Id),
                TEST_VIN
            );

        Test.stopTest();


        System.assertEquals(
            false,
            result.get('isSuccess')
        );

        System.assertEquals(
            false,
            result.containsKey(
                'contentDocumentId'
            )
        );
    }


    /* =========================================================
       EXCEPTION / CATCH PATH
       ========================================================= */

    @IsTest
    static void testCarfaxExceptionPath() {

        Test.setMock(
            HttpCalloutMock.class,
            new CarfaxExceptionMock()
        );


        Test.startTest();

        Map<String, Object> result =
            (Map<String, Object>)
            CARFAXIntegration.getCarFaxFile(
                new Map<String, Object>(),
                null,
                TEST_VIN
            );

        Test.stopTest();


        System.assertNotEquals(
            null,
            result
        );

        System.assertEquals(
            false,
            result.containsKey(
                'contentDocumentId'
            )
        );
    }


    /* =========================================================
       UNKNOWN CALLABLE ACTION
       ========================================================= */

    @IsTest
    static void testUnsupportedCallableAction() {

        Claim clm = [
            SELECT Id
            FROM Claim
            LIMIT 1
        ];


        Boolean exceptionThrown =
            false;


        Test.startTest();

        try {

            new CARFAXIntegration().call(
                'unsupportedAction',
                buildArgs(clm.Id)
            );

        } catch (Exception ex) {

            exceptionThrown =
                true;
        }

        Test.stopTest();


        System.assertEquals(
            true,
            exceptionThrown
        );
    }
}