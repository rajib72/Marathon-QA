@isTest
public class UpdatePolicyContractMonthsBatchTest {

    @isTest
    static void Policytestcover() {

        // =====================================================
        // CUSTOMER ACCOUNT
        // =====================================================
        Account acc =
            TestDataFactory.createAccount(false);

        acc.AccountNumber = 'WUS';
        acc.FirstName = 'Test';
        acc.LastName = 'Customer';
        acc.BillingStreet = '123 Test Street';
        acc.BillingCity = 'Columbus';
        acc.BillingState = 'OH';
        acc.BillingPostalCode = '43004';
        acc.Phone = '6145551234';

        insert acc;


        // =====================================================
        // DEALER / LIEN HOLDER
        // =====================================================
        Account dealer =
            TestDataFactory.createDealerAccount(true);


        // =====================================================
        // AUTO WARRANTY RECORD TYPE
        // =====================================================
        Id autoWarrantyRecordTypeId =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty')
                .getRecordTypeId();


        // =====================================================
        // CREATE VALID INSURANCE POLICY
        // =====================================================
        InsurancePolicy ip =
            TestDataFactory.createInsurancePolicy(
                false,
                acc.Id
            );


        // Relationships
        ip.RecordTypeId =
            autoWarrantyRecordTypeId;

        ip.Client__c =
            acc.Id;

        ip.NameInsuredId =
            acc.Id;

        ip.Dealer__c =
            dealer.Id;

        ip.Lien_Holder__c =
            dealer.Id;


        // =====================================================
        // BATCH-RELATED DATA
        // =====================================================
        ip.Status =
            'Active';

        ip.Sale_Date__c =
            Date.today().addMonths(-2);

        ip.SaleDate =
            Datetime.newInstance(
                Date.today().addMonths(-2),
                Time.newInstance(
                    12,
                    0,
                    0,
                    0
                )
            );


        /*
         * This combination is explicitly allowed by
         * UpdatePolicyContractMonthsBatch.wouldFailValidationRule().
         */
        ip.Cancel_Code__c =
            '04 ROP Request';

        ip.CancellationReasonType =
            'NON PAYMENT';

        ip.Cancel_Mileage__c =
            50;

        ip.Cancel_Effective_Date__c =
            null;


        // =====================================================
        // REQUIRED CONTRACT DATA
        // =====================================================
        ip.Program_Code__c =
            'MDMD';

        ip.Dealer_Program_Id__c =
            '1';

        ip.Dec_Code__c =
            'TEST';

        ip.Roadside_Number__c =
            'TEST';

        ip.T_and_C_Code__c =
            'TEST';


        // =====================================================
        // VEHICLE
        // =====================================================
        ip.VIN__c =
            'TestVin1A34123456';

        ip.Vehicle_Mileage_at_Contract_Inception__c =
            40;

        ip.Vehicle_Make__c =
            'ACUR';

        ip.Vehicle_Model__c =
            'TEST';

        ip.Vehicle_Year__c =
            '2023';

        ip.Vehicle_New_or_Used__c =
            'U';

        ip.Class__c =
            'SUV';


        // =====================================================
        // PRODUCT / COVERAGE
        // =====================================================
        ip.Product__c =
            'SecureOne';

        ip.Coverage_Name__c =
            'PowerTrain';

        ip.Validation_Days__c =
            14;

        ip.Validation_Miles__c =
            1000;


        // =====================================================
        // FINANCIAL
        // =====================================================
        ip.Net_Dealer_Cost__c =
            700;

        ip.PremiumAmount =
            690;

        ip.Down_Payment_Amount__c =
            90;

        ip.Deductible__c =
            89;


        // =====================================================
        // INSURANCE
        // =====================================================
        ip.Ins_Carrier__c =
            'Technology Insurance Company';

        ip.Insurance_Code__c =
            'KNB';

        ip.Rate_Code__c =
            '1';

        ip.Option_1__c =
            'Salvaged';

        ip.Is_Commercial__c =
            true;

        ip.Up_To_or_Add__c =
            'UpTo';

        ip.Fulfillment_Date__c =
            Date.today();


        // =====================================================
        // IMPORTANT:
        // DO NOT SET Contract_Term_Months__c = 1 YET.
        //
        // First insert using the factory-compatible term.
        // =====================================================
        insert ip;


        // =====================================================
        // NOW MAKE RECORD ELIGIBLE FOR THE BATCH
        // =====================================================
        ip.Contract_Term_Months__c = 1;

        update ip;


        // =====================================================
        // CONFIRM TEST DATA MATCHES BATCH START QUERY
        // =====================================================
        InsurancePolicy beforeBatch = [
            SELECT
                Id,
                Sale_Date__c,
                Contract_Term_Months__c,
                Status,
                Number_of_Funding_Months__c
            FROM InsurancePolicy
            WHERE Id = :ip.Id
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            beforeBatch.Sale_Date__c,
            'Sale Date must be populated for batch selection.'
        );

        System.assertEquals(
            1,
            beforeBatch.Contract_Term_Months__c,
            'Contract Term Months must be 1 for batch selection.'
        );

        System.assertNotEquals(
            'Cancelled',
            beforeBatch.Status,
            'Policy must not be Cancelled.'
        );


        // =====================================================
        // EXPECTED MONTHS
        // Same calculation as production class.
        // =====================================================
        Date today =
            Date.today();

        Date saleDate =
            beforeBatch.Sale_Date__c;

        Integer expectedMonths =
            (
                today.year() -
                saleDate.year()
            ) * 12
            +
            (
                today.month() -
                saleDate.month()
            );

        if (
            today.day() >=
            saleDate.day()
        ) {
            expectedMonths++;
        }


        // =====================================================
        // RUN BATCH
        // =====================================================
        Test.startTest();

        UpdatePolicyContractMonthsBatch batchObj =
            new UpdatePolicyContractMonthsBatch();

        Database.executeBatch(
            batchObj,
            1
        );

        Test.stopTest();


        // =====================================================
        // VERIFY BATCH RESULT
        // =====================================================
        InsurancePolicy updatedIP = [
            SELECT
                Id,
                Sale_Date__c,
                Contract_Term_Months__c,
                Number_of_Funding_Months__c
            FROM InsurancePolicy
            WHERE Id = :ip.Id
            LIMIT 1
        ];


        System.assertEquals(
            expectedMonths,
            updatedIP.Number_of_Funding_Months__c,
            'Number of Funding Months was not calculated correctly.'
        );
    }


    // =========================================================
    // SCHEDULER TEST
    // Keep scheduler coverage separate from batch calculation.
    // =========================================================
    @isTest
    static void testScheduler() {

        Test.startTest();

        String CRON =
            '0 0 0 1 1 ? 2099';

        String jobId =
            System.schedule(
                'PolicySchedulerTest',
                CRON,
                new PolicyContractMonthsScheduler()
            );

        Test.stopTest();


        System.assertNotEquals(
            null,
            jobId,
            'Scheduler job should be created.'
        );
    }
}