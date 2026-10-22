/**
* @author Saurabh Rawat
* @dateModified 2024-04-25
* @description Test class for UpdateExpiredContractBatch
*/
@isTest
public class UpdateExpiredContractBatchTest {

    @isTest
    public static void Method1() {

        List<InsurancePolicy> contractsList =
            new List<InsurancePolicy>();

        // =====================================================
        // ACCOUNT
        // =====================================================
        Account accRec =
            TestDataFactory.createAccount(false);

        accRec.AccountNumber = 'WUS';
        accRec.FirstName = 'Test';
        accRec.LastName = 'Customer';
        accRec.BillingStreet = '123 Test Street';
        accRec.BillingCity = 'Columbus';
        accRec.BillingState = 'OH';
        accRec.BillingPostalCode = '43004';
        accRec.Phone = '6145551234';

        insert accRec;


        // =====================================================
        // INSURANCE POLICY
        // =====================================================
        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                accRec.Id
            );

        // Relationships
        policyRec.Client__c = accRec.Id;
        policyRec.NameInsuredId = accRec.Id;

        // Status
        policyRec.Status = 'Active';

        // Dates
        policyRec.OriginalEffectiveDate =
            Date.newInstance(
                2019,
                10,
                21
            );

        policyRec.SaleDate =
            Date.today().addDays(-60);

        policyRec.Sale_Date__c =
            Date.today().addDays(-60);

        // Contract Term
        policyRec.Contract_Term_Months__c = 1;

        // Required Contract fields
        policyRec.Dec_Code__c = 'TEST';

        policyRec.Roadside_Number__c = 'TEST';

        policyRec.T_and_C_Code__c = 'TEST';

        // Vehicle
        policyRec.VIN__c =
            'TestVin1A34123456';

        policyRec.Vehicle_Mileage_at_Contract_Inception__c =
            100000;

        policyRec.Contract_Term_Mileage__c =
            12000;

        policyRec.Vehicle_Make__c =
            'ACUR';

        policyRec.Vehicle_Model__c =
            'TEST';

        policyRec.Vehicle_Year__c =
            '2023';

        policyRec.Vehicle_New_or_Used__c =
            'U';

        policyRec.Class__c =
            'SUV';

        // Product / Coverage
        policyRec.Product__c =
            'SecureOne';

        policyRec.Coverage_Name__c =
            'PowerTrain';

        /*
         * ContractTriggerHandler has a Test.isRunningTest()
         * PowerTrain validation path using:
         *
         * Validation Days  = 14
         * Validation Miles = 1000
         */
        policyRec.Validation_Days__c =
            14;

        policyRec.Validation_Miles__c =
            1000;

        // Financial / contract values
        policyRec.Net_Dealer_Cost__c =
            700;

        policyRec.PremiumAmount =
            690;

        policyRec.Down_Payment_Amount__c =
            90;

        policyRec.Deductible__c =
            89;

        // Insurance
        policyRec.Ins_Carrier__c =
            'Technology Insurance Company';

        policyRec.Insurance_Code__c =
            'KNB';

        policyRec.Rate_Code__c =
            '1';

        policyRec.Dealer_Program_Id__c =
            '1';

        policyRec.Option_1__c =
            'Salvaged';

        policyRec.Is_Commercial__c =
            true;

        policyRec.Up_To_or_Add__c =
            'UpTo';

        policyRec.Fulfillment_Date__c =
            Date.today();


        contractsList.add(policyRec);

        insert contractsList;


        // =====================================================
        // SET CREATED DATE
        // =====================================================
        Test.setCreatedDate(
            policyRec.Id,
            Date.today().addDays(-2)
        );


        // =====================================================
        // REQUERY
        // =====================================================
        contractsList = [
            SELECT
                Id,
                Status,
                OriginalEffectiveDate,
                Contract_Term_Months__c
            FROM InsurancePolicy
            WHERE Id = :policyRec.Id
        ];


        // =====================================================
        // TEST
        // =====================================================
        Test.startTest();

        UpdateExpiredContractBatch tsc =
            new UpdateExpiredContractBatch();

        // Batch execute
        tsc.execute(
            null,
            contractsList
        );

        // Schedulable execute
        SchedulableContext sc = null;

        tsc.execute(sc);

        Test.stopTest();


        // =====================================================
        // ASSERT
        // =====================================================
        InsurancePolicy fetchedPolicy = [
            SELECT
                Id,
                Status
            FROM InsurancePolicy
            WHERE Id = :policyRec.Id
            LIMIT 1
        ];

        Assert.AreEqual(
            'Expired',
            fetchedPolicy.Status,
            'Not equal'
        );
    }
}