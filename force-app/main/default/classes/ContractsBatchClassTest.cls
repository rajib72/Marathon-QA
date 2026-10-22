/**
* @author: Sujit Dengale
* @dateModified: 19-04-2028
* @description: Test class for code coverage of Batch class ContractsBatchClass.
*/
@IsTest
public class ContractsBatchClassTest {

    /* =========================================================
       COMMON ACCOUNT CREATION
       ========================================================= */

    private static Account createTestAccount() {

        Account accRec =
            TestDataFactory.createAccount(false);

        /*
         * IMPORTANT:
         * WUS is allowed by Sold_Contract_Validation,
         * but does NOT trigger Sold_Contract_SecureOne_Validation.
         */
        putIfCreateable(
            accRec,
            'AccountNumber',
            'WUS'
        );

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

        insert accRec;

        return accRec;
    }


    /* =========================================================
       COMMON POLICY CREATION
       ========================================================= */

    private static InsurancePolicy createTestPolicy(
        Id accountId
    ) {

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
           VEHICLE INFORMATION
           ===================================================== */

        /*
         * Vehicle_Make__c is not required for the general
         * WUS validation, but keep it populated because the
         * batch may use this information.
         */
        putIfCreateable(
            policyRec,
            'Vehicle_Make__c',
            'FORD'
        );

        putIfCreateable(
            policyRec,
            'Vehicle_Make',
            'FORD'
        );

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
           REQUIRED FINANCIAL INFORMATION
           ===================================================== */

        /*
         * Dealer_Program_Id__c has a maximum length of 4
         * characters in this org.
         */
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
           DATE INFORMATION
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

        /*
         * Required by Sold_Contract_Validation for Auto Warranty
         * unless Client AccountNumber = END.
         */
        putIfCreateable(
            policyRec,
            'Fulfillment_Date__c',
            todayDate.addDays(-30)
        );


        /* =====================================================
           MILEAGE
           ===================================================== */

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
           HOME WARRANTY FIELDS
           ===================================================== */

        /*
         * These are harmless for an Auto Warranty and protect
         * the test if the factory record type/configuration
         * changes.
         */

        putIfCreateable(
            policyRec,
            'Address_1__c',
            '100 Test Street'
        );

        putIfCreateable(
            policyRec,
            'City__c',
            'Kolkata'
        );

        putIfCreateable(
            policyRec,
            'State__c',
            'West Bengal'
        );

        putIfCreateable(
            policyRec,
            'Postal_Code__c',
            '700001'
        );

        setFirstActivePicklistValue(
            policyRec,
            'Residential_Type__c'
        );

        putIfCreateable(
            policyRec,
            'Square_Foot__c',
            1000
        );

        putIfCreateable(
            policyRec,
            'Number_of_Units__c',
            1
        );


        /* =====================================================
           INSERT POLICY
           ===================================================== */

        insert policyRec;

        return policyRec;
    }


    /* =========================================================
       DYNAMIC CREATEABLE FIELD HELPER
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
       PICKLIST HELPER
       ========================================================= */

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
            fieldDescribe.getType() != Schema.DisplayType.Picklist
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


    /* =========================================================
       METHOD 1
       ========================================================= */

    @IsTest
    public static void Method1() {

        Account accRec =
            createTestAccount();

        InsurancePolicy policyRec =
            createTestPolicy(
                accRec.Id
            );

        policyRec.Reinstated_Effective_Date__c =
            System.Today().addDays(-2);

        policyRec.Status =
            'In Waiting';

        update policyRec;

        Test.setCreatedDate(
            policyRec.Id,
            Date.today().addDays(-2)
        );

        Test.startTest();

        ContractsBatchClass batchObj =
            new ContractsBatchClass();

        Database.executeBatch(
            batchObj,
            5
        );

        Test.stopTest();


        InsurancePolicy policyAfter =
            [
                SELECT
                    Id,
                    Status
                FROM InsurancePolicy
                WHERE Id = :policyRec.Id
            ];

       
    }


    /* =========================================================
       METHOD 2
       ========================================================= */

    @IsTest
    public static void Method2() {

        Account accRec =
            createTestAccount();

        InsurancePolicy policyRec1 =
            createTestPolicy(
                accRec.Id
            );

        policyRec1.Reinstated_Effective_Date__c =
            System.Today().addDays(4);

        policyRec1.SaleDate =
            Date.Today().addDays(-1);

        policyRec1.Validation_Days__c =
            14;

        policyRec1.Status =
            'In Waiting';

        update policyRec1;

        Test.setCreatedDate(
            policyRec1.Id,
            Date.today().addDays(-2)
        );

        Test.startTest();

        ContractsBatchClass batchObj =
            new ContractsBatchClass();

        Database.executeBatch(
            batchObj,
            5
        );

        Test.stopTest();


        InsurancePolicy policyAfter =
            [
                SELECT
                    Id,
                    Status
                FROM InsurancePolicy
                WHERE Id = :policyRec1.Id
            ];

        System.assertEquals(
            UtilityClass.contractStatus_InWaiting,
            policyAfter.Status,
            'The Status field of policyRec1 should be "In Waiting" after executing the batch job.'
        );
    }


    /* =========================================================
       SCHEDULER
       ========================================================= */

    @IsTest
    static void myTestMethod() {

        Test.startTest();

        ContractsBatchClass myClass =
            new ContractsBatchClass();

        String chron =
            '0 0 23 * * ?';

        String jobId =
            System.schedule(
                'Test Sched',
                chron,
                myClass
            );

        System.assertNotEquals(
            null,
            jobId,
            'Scheduler job should be created.'
        );

        Test.stopTest();
    }
}