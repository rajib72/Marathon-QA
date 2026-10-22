@IsTest
public class ContractUtilityTest {

    // ============================================================
    // MOCK FOR fetchLookupTableRows()
    // ============================================================

    private class DecisionMatrixMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest request) {

            HttpResponse response = new HttpResponse();

            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');

            response.setBody(
                '{"success":true,"rows":[{"id":"TEST_ROW"}]}'
            );

            return response;
        }
    }


    // ============================================================
    // TEST calculateRefundAmount()
    // ============================================================

    @IsTest
    static void testCalculateRefundAmount() {

        List<ContractUtility.RefundRequest> requests =
            new List<ContractUtility.RefundRequest>{
                new ContractUtility.RefundRequest(),
                new ContractUtility.RefundRequest(),
                new ContractUtility.RefundRequest()
            };

        requests[0].TotalPremiumAmount = null;
        requests[1].TotalPremiumAmount = 0.0;
        requests[2].TotalPremiumAmount = 100.0;

        Test.startTest();

        List<ContractUtility.RefundRequest> results =
            ContractUtility.calculateRefundAmount(requests);

        Test.stopTest();

        System.assertEquals(
            0.0,
            results[0].RefundAmount,
            'Refund should be 0.0 when premium is null'
        );

        System.assertEquals(
            0.0,
            results[1].RefundAmount,
            'Refund should be 0.0 when premium is 0.0'
        );

        System.assertEquals(
            50.0,
            results[2].RefundAmount,
            'Refund should be 50.0 when premium is 100.0'
        );
    }


    // ============================================================
    // TEST findContractsfromNumber()
    // SUCCESSFUL SEARCH
    // ============================================================

    @IsTest
    static void testFindContractsfromNumber() {

        Set<String> policyNumbers =
            new Set<String>{ 'Policy001' };

        // --------------------------------------------------------
        // CREATE ACCOUNT
        // WUS avoids SecureOne-specific validation.
        // --------------------------------------------------------

        Account accRec =
            TestDataFactory.createAccount(false);

        accRec.AccountNumber = 'WUS';
        accRec.FirstName = 'Test';
        accRec.LastName = 'Insured';

        accRec.BillingStreet = '100 Test Street';
        accRec.BillingCity = 'Kolkata';
        accRec.BillingState = 'West Bengal';
        accRec.BillingPostalCode = '700001';
        accRec.Phone = '9876543210';

        insert accRec;


        // --------------------------------------------------------
        // CREATE INSURANCE POLICY
        // --------------------------------------------------------

        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                accRec.Id
            );

        policyRec.Name = 'Policy001';
        policyRec.Client__c = accRec.Id;

        // Required by Sold_Contract_Validation
        policyRec.Dealer_Program_Id__c = 'TEST';
        policyRec.Net_Dealer_Cost__c = 1000;
        policyRec.PremiumAmount = 1500;
        policyRec.Deductible__c = 100;
        policyRec.Down_Payment_Amount__c = 500;
        policyRec.Sale_Date__c = Date.today().addDays(-30);

        // Auto Warranty fields
        policyRec.Vehicle_Mileage_at_Contract_Inception__c = 1000;
        policyRec.Contract_Term_Mileage__c = 100000;
        policyRec.Contract_Term_Months__c = 12;
        policyRec.VIN__c = 'TESTVIN123';
        policyRec.Fulfillment_Date__c = Date.today();

        insert policyRec;


        // --------------------------------------------------------
        // EXECUTE
        // --------------------------------------------------------

        Test.startTest();

        Map<String, InsurancePolicy> result =
            ContractUtility.findContractsfromNumber(
                policyNumbers
            );

        Test.stopTest();


        // --------------------------------------------------------
        // VERIFY
        // --------------------------------------------------------

        System.assertEquals(
            1,
            result.size(),
            'One contract should be returned.'
        );

        System.assert(
            result.containsKey('Policy001'),
            'The result should contain Policy001.'
        );

        System.assertEquals(
            policyRec.Id,
            result.get('Policy001').Id,
            'The returned policy should be Policy001.'
        );
    }


    // ============================================================
    // TEST findContractsfromNumber()
    // NO MATCHING CONTRACT
    // ============================================================

    @IsTest
    static void testFindContractsfromNumberNoMatch() {

        Set<String> policyNumbers =
            new Set<String>{ 'PolicyDoesNotExist' };

        Test.startTest();

        Map<String, InsurancePolicy> result =
            ContractUtility.findContractsfromNumber(
                policyNumbers
            );

        Test.stopTest();

        System.assertEquals(
            0,
            result.size(),
            'No contracts should be returned when no policy matches.'
        );
    }


    // ============================================================
    // TEST findContractsfromNumber()
    // NULL INPUT
    // ============================================================

    @IsTest
    static void testFindContractsfromNumberNullInput() {

        Test.startTest();

        Map<String, InsurancePolicy> result =
            ContractUtility.findContractsfromNumber(null);

        Test.stopTest();

        System.assertEquals(
            0,
            result.size(),
            'Null policy numbers should return an empty map.'
        );
    }


    // ============================================================
    // TEST findContractsfromNumber()
    // EMPTY INPUT
    // ============================================================

    @IsTest
    static void testFindContractsfromNumberEmptyInput() {

        Set<String> policyNumbers =
            new Set<String>();

        Test.startTest();

        Map<String, InsurancePolicy> result =
            ContractUtility.findContractsfromNumber(
                policyNumbers
            );

        Test.stopTest();

        System.assertEquals(
            0,
            result.size(),
            'Empty policy numbers should return an empty map.'
        );
    }


    // ============================================================
    // TEST fetchLookupTableRows()
    // HTTP CALLOUT
    // ============================================================

    @IsTest
    static void testFetchLookupTableRows() {

        Test.setMock(
            HttpCalloutMock.class,
            new DecisionMatrixMock()
        );

        Test.startTest();

        String response =
            ContractUtility.fetchLookupTableRows(
                'TEST_LOOKUP_TABLE_ID',
                'TEST_VERSION_ID'
            );

        Test.stopTest();


        // --------------------------------------------------------
        // VERIFY RESPONSE
        // --------------------------------------------------------

        System.assertNotEquals(
            null,
            response,
            'Response should not be null.'
        );

        System.assert(
            response.contains('"success":true'),
            'Response should contain the success value.'
        );

        System.assert(
            response.contains('TEST_ROW'),
            'Response should contain the mock row.'
        );
    }
}