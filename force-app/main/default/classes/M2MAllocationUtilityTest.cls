@isTest
public class M2MAllocationUtilityTest {

    @TestSetup
    public static void CreateTestData() {

        FundingAllocationOrchestrator.disableBatchExecution = true;

        String sellingRT = Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Selling Agency')
            .getRecordTypeId();


        // =========================================================
        // NAME INSURED / DEALER ACCOUNT
        // =========================================================
        Account clientAccount =
            TestDataFactory.createAccount(false);

        clientAccount.AccountNumber = 'AAR';

        // Required because this Account is used as NameInsured
        clientAccount.FirstName = 'Test';
        clientAccount.LastName = 'Customer';
        clientAccount.BillingStreet = '123 Test Street';
        clientAccount.BillingCity = 'Columbus';
        clientAccount.BillingState = 'OH';
        clientAccount.BillingPostalCode = '43004';

        // Validation requires Email__c OR Phone
        clientAccount.Phone = '6145551234';

        insert clientAccount;


        // =========================================================
        // PROGRAM CODE / LIEN HOLDER ACCOUNT
        // =========================================================
        Account programcodeAccount =
            TestDataFactory.createDealerAccount(true);

        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';

        update programcodeAccount;


        // =========================================================
        // SELLING AGENCY / CLIENT
        // =========================================================
        Account clientAccount1 =
            TestDataFactory.createDealerAccount(false);

        clientAccount1.Name = 'CCV';
        clientAccount1.AccountNumber = 'CCV';
        clientAccount1.RecordTypeId = sellingRT;

        insert clientAccount1;


        // =========================================================
        // INSURANCE POLICY / CONTRACT
        // =========================================================
        InsurancePolicy policyRec1 =
            TestDataFactory.createInsurancePolicy(
                false,
                clientAccount.Id
            );


        // =========================================================
        // M2M ALLOCATION FIELDS
        // =========================================================
        policyRec1.Client__c =
            clientAccount1.Id;

        policyRec1.Dealer__c =
            clientAccount.Id;

        policyRec1.NameInsuredId =
            clientAccount.Id;

        policyRec1.Lien_Holder__c =
            programcodeAccount.Id;

        policyRec1.Program_Code__c =
            'MDMD';

        policyRec1.DLRS_Total_Unprocessed_Funding__c =
            1000;

        policyRec1.State__c =
            'OH';

        policyRec1.Net_Dealer_Cost__c =
            1000;


        // =========================================================
        // EXPLICITLY SATISFY COMMON REQUIRED CONTRACT FIELDS
        // =========================================================

        // Required by validation
        policyRec1.Dealer_Program_Id__c =
            '1';

        policyRec1.Net_Dealer_Cost__c =
            1000;

        policyRec1.PremiumAmount =
            690;

        policyRec1.Deductible__c =
            89;

        policyRec1.Down_Payment_Amount__c =
            90;

        policyRec1.SaleDate =
            Date.today();

        policyRec1.Fulfillment_Date__c =
            Date.today();


        // =========================================================
        // AUTO WARRANTY REQUIRED FIELDS
        //
        // These values already come from TestDataFactory,
        // but keeping them explicit makes the test safe against
        // the required-fields validation.
        // =========================================================
        policyRec1.Vehicle_Mileage_at_Contract_Inception__c =
            100000;

        policyRec1.Contract_Term_Mileage__c =
            12000;

        policyRec1.Contract_Term_Months__c =
            12;

        policyRec1.VIN__c =
            'TestVin1A34123456';


        // =========================================================
        // KEEP RATE-RELATED FACTORY VALUES
        // =========================================================
        // Product__c = SecureOne
        // Coverage_Name__c = PowerTrain
        // Coverage_Level__c = factory Coverage Level
        // Insurance_Code__c = KNB
        // Ins_Carrier__c = Technology Insurance Company
        // Rate_Code__c = 1
        // Vehicle_Year__c = 2023
        // Option_1__c = Salvaged
        //
        // Do not change these back to Fortegra / MAC DM VSC
        // until we know the Rate configuration.


        insert policyRec1;


        // =========================================================
        // FUNDING
        // =========================================================
        Funding__c funding =
            TestDataFactory.createFunding(
                false,
                policyRec1.Id
            );

        funding.Funded_Amount__c =
            1000;

        insert funding;


        // =========================================================
        // GET ACTUAL COVERAGE LEVEL
        // =========================================================
        Coverage_Level__c coverageLevel = [
            SELECT
                Id,
                Name
            FROM Coverage_Level__c
            WHERE Id = :policyRec1.Coverage_Level__c
            LIMIT 1
        ];


        // =========================================================
        // ALLOCATION CODE
        // =========================================================
        Allocation_Code__c all8001Code =
            TestDataFactory.createAllocationCode(false);

        all8001Code.Payee_Type__c =
            'Company';

        all8001Code.Insurance_Carrier__c =
            'Include All';

        all8001Code.Term_Months__c =
            'Include All';

        all8001Code.States__c =
            'Include All';

        all8001Code.Option__c =
            'Include All';

        all8001Code.Start_Date__c =
            Date.today().addDays(-1);

        all8001Code.Client__c =
            clientAccount1.Id;

        all8001Code.Coverage_Level__c =
            coverageLevel.Name;

        all8001Code.Product__c =
            policyRec1.Product__c;

        insert all8001Code;
    }


    @isTest
    public static void testM2MAllocationUtility() {

        // =========================================================
        // GET TEST POLICY
        // =========================================================
        List<InsurancePolicy> policyList = [
            SELECT
                Id,
                Name,
                Program_Code__c,
                Client__c,
                Client_Program_Code__c,
                Lien_Holder__c,
                Lien_Holder__r.AccountNumber,
                Coverage_Level__c,
                Coverage_Level__r.Name,
                Product__c,
                Ins_Carrier__c,
                Original_State__c,
                Contract_Term_Months__c,
                Premium_Tax_Old__c,
                MBI_Seller_Commission__c,
                Reserve__c,
                Written_Reserve__c,
                Reinstatement_Date__c,
                Options_Cost__c,
                Surcharge_Cost__c,
                Allocation_Expense_Amount__c,
                Sale_Date__c,
                Option_1__c
            FROM InsurancePolicy
            WHERE
                DLRS_Total_Unprocessed_Funding__c > 0
                AND Client__c != null
        ];


        System.assert(
            !policyList.isEmpty(),
            'Expected an Insurance Policy for M2M allocation testing.'
        );


        // =========================================================
        // EXECUTE
        // =========================================================
        Test.startTest();

        M2MAllocationUtility.distributeFundingToContracts(
            policyList
        );

        Test.stopTest();


        // =========================================================
        // VERIFY
        // =========================================================
        List<Allocation__c> allocList = [
            SELECT
                Id,
                Contract__c
            FROM Allocation__c
            WHERE Contract__c = :policyList[0].Id
        ];


        System.assert(
            !allocList.isEmpty(),
            'At least one Allocation should have been created.'
        );
    }
}