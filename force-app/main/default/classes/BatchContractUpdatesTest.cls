@isTest
public class BatchContractUpdatesTest {

    @isTest
    public static void testBatch() {

        // =====================================================
        // CLIENT / NAME INSURED
        // =====================================================
        Account clientAccount =
            TestDataFactory.createAccount(false);

        clientAccount.AccountNumber = 'AAR';
        clientAccount.FirstName = 'Test';
        clientAccount.LastName = 'Customer';
        clientAccount.BillingStreet = '123 Test Street';
        clientAccount.BillingCity = 'Columbus';
        clientAccount.BillingState = 'OH';
        clientAccount.BillingPostalCode = '43004';
        clientAccount.Phone = '6145551234';

        insert clientAccount;


        // =====================================================
        // DEALER / LIEN HOLDER
        // =====================================================
        Account programcodeAccount =
            TestDataFactory.createDealerAccount(true);

        programcodeAccount.Name = 'CCV';
        programcodeAccount.AccountNumber = 'CCV';

        update programcodeAccount;


        // =====================================================
        // AUTO WARRANTY RECORD TYPE
        // =====================================================
        Id autoWarrantyRecordTypeId =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty')
                .getRecordTypeId();


        // =====================================================
        // POLICY
        // false = do NOT insert from factory
        // =====================================================
        InsurancePolicy policyRec1 =
            TestDataFactory.createInsurancePolicy(
                false,
                clientAccount.Id
            );


        // =====================================================
        // RELATIONSHIPS
        // =====================================================
        policyRec1.Client__c =
            clientAccount.Id;

        policyRec1.NameInsuredId =
            clientAccount.Id;

        policyRec1.Lien_Holder__c =
            programcodeAccount.Id;

        policyRec1.Dealer__c =
            programcodeAccount.Id;

        policyRec1.RecordTypeId =
            autoWarrantyRecordTypeId;


        // =====================================================
        // CONTRACT INFORMATION
        // =====================================================
        policyRec1.Program_Code__c =
            'MDMD';

        policyRec1.Dealer_Program_Id__c =
            '1';

        policyRec1.SaleDate =
            System.now();

        policyRec1.Sale_Date__c =
            Date.today();

        policyRec1.Fulfillment_Date__c =
            Date.today();


        // =====================================================
        // FINANCIAL / RATE COST
        //
        // IMPORTANT:
        // For NonSecureOne:
        //
        // Net Dealer Cost must equal:
        // Reserve
        // + Options Cost
        // + Surcharge Cost
        // + Projected Allocation Cost
        //
        // Keep this simple:
        // Reserve = 1000
        // everything else = 0
        // Net Dealer Cost = 1000
        // =====================================================
        policyRec1.Reserve__c =
            1000;

        policyRec1.Options_Cost__c =
            0;

        policyRec1.Surcharge_Cost__c =
            0;

        policyRec1.Projected_Allocation_Cost__c =
            0;

        policyRec1.Net_Dealer_Cost__c =
            1000;

        policyRec1.PremiumAmount =
            690;

        policyRec1.Deductible__c =
            89;

        policyRec1.Down_Payment_Amount__c =
            90;

        policyRec1.DLRS_Total_Unprocessed_Funding__c =
            10;


        // =====================================================
        // AUTO WARRANTY FIELDS
        // =====================================================
        policyRec1.VIN__c =
            'TestVin1A34123456';

        policyRec1.Vehicle_Mileage_at_Contract_Inception__c =
            10000;

        policyRec1.Contract_Term_Mileage__c =
            12000;

        policyRec1.Contract_Term_Months__c =
            12;

        policyRec1.Vehicle_Make__c =
            'ACUR';

        policyRec1.Vehicle_Model__c =
            'TEST';

        policyRec1.Vehicle_Year__c =
            '2010';

        policyRec1.Vehicle_New_or_Used__c =
            'U';

        policyRec1.Class__c =
            'SUV';


        // =====================================================
        // PRODUCT / COVERAGE
        // =====================================================
        policyRec1.Product__c =
            'NonSecureOne';

        policyRec1.Coverage_Name__c =
            'PowerTrain';


        // ContractTriggerHandler test-specific values
        policyRec1.Validation_Days__c =
            14;

        policyRec1.Validation_Miles__c =
            1000;


        // =====================================================
        // OTHER RATE VALUES
        // =====================================================
        policyRec1.Insurance_Code__c =
            'KNB';

        policyRec1.Rate_Code__c =
            '1';

        policyRec1.Option_1__c =
            'Salvaged';

        policyRec1.Is_Commercial__c =
            true;

        policyRec1.Up_To_or_Add__c =
            'UpTo';


        // =====================================================
        // INSERT POLICY
        // =====================================================
        insert policyRec1;


        // =====================================================
        // FUNDING
        // =====================================================
        Funding__c funding =
            TestDataFactory.createFunding(
                false,
                policyRec1.Id
            );

        funding.Contract__c =
            policyRec1.Id;

        funding.Funded_Amount__c =
            1000;

        insert funding;


        // =====================================================
        // EXECUTE BATCH
        // =====================================================
        Test.startTest();

        BatchContractUpdates batch =
            new BatchContractUpdates();

        Database.executeBatch(
            batch
        );

        Test.stopTest();
    }
}