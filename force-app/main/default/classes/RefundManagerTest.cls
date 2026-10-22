/**
* @author: Waidehee Kuradkar
* @description:
* Test class for RefundManager.
*
* UAT contains active InsurancePolicy cancellation validation rules which
* fire when Status = 'Cancelled'. RefundManager.calculateCancelFee() does
* not require the InsurancePolicy record itself to be in Cancelled status;
* it only reads the cancellation reason / formula fields.
*
* These tests therefore create a valid NON-CANCELLED policy so they test
* RefundManager itself without being blocked by unrelated Policy Contract
* cancellation validations.
*/
@IsTest
public class RefundManagerTest {

    private static InsurancePolicy createRefundTestPolicy(
        String cancellationReason
    ) {
        Account accRec = TestDataFactory.createAccount(true);

accRec.AccountNumber = 'WUS';
accRec.Phone = '5555555555';
update accRec;

InsurancePolicy policyRec =
    TestDataFactory.createInsurancePolicy(
        false,
        accRec.Id
    );

policyRec.Client__c = accRec.Id;

        // Critical for UAT:
        // do NOT insert the policy as Cancelled.
        policyRec.Status = 'Active';

        // Keep the same T&C pattern used by the original tests.
        policyRec.T_and_C_Code__c = 'TSOP1';

        if (String.isNotBlank(cancellationReason)) {
            policyRec.CancellationReasonType =
                cancellationReason;
        }
        policyRec.Vehicle_New_or_Used__c = 'U';

        policyRec.Lien_Holder__c = accRec.Id;

        insert policyRec;

        return [
            SELECT
                Id,
                Status,
                CancellationReasonType,
                PremiumAmount,
                RecordType.Name,
                Refund_Percent__c,
                Cancel_Effective_Date__c,
                Effective_Date__c,
                Sale_Date__c,
                Validation_Days__c,
                Refund_Date_Percent__c,
                Refund_Mileage_Percent__c,
                Expiration_Date__c,
                Contract_Term_Months__c,
                Vehicle_Mileage_at_Contract_Inception__c,
                Contract_Term_Mileage__c,
                Validation_Miles__c,
                Product__c
            FROM InsurancePolicy
            WHERE Id = :policyRec.Id
            LIMIT 1
        ];
    }

    @IsTest
    static void calculateCancelFeeTestNumericFee() {

        // Numeric fees return immediately, before any policy query.
        List<String> inputs =
            new List<String>{
                '35',
                ''
            };

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(
                new List<List<String>>{
                    inputs
                }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.size(),
            'One result should be returned.'
        );

        System.assertEquals(
            Decimal.valueOf('35'),
            result[0],
            'Numeric cancellation fee should be returned unchanged.'
        );
    }

    @IsTest
    static void calculateCancelFeeCancellationType() {

        /*
         * The RefundManager branch only checks CancellationReasonType.
         * Status does not need to be Cancelled.
         */
        InsurancePolicy policyRec =
            createRefundTestPolicy(
                UtilityClass.CANCELLED_BY_ADMINISTRATOR
            );

        List<String> inputs =
            new List<String>{
                'MIN(50, PremiumAmount * 0.10)',
                String.valueOf(policyRec.Id)
            };

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(
                new List<List<String>>{
                    inputs
                }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.size(),
            'One result should be returned.'
        );

        System.assertEquals(
            Decimal.valueOf('0.0'),
            result[0],
            'Administrator cancellation should return zero.'
        );
    }

    @IsTest
    static void calculateFormulaFee() {

        InsurancePolicy policyRec =
            createRefundTestPolicy(null);

        /*
         * Non-numeric formula forces RefundManager into FormulaEval.
         * This formula is deterministic and does not depend on org data.
         */
        List<String> inputs =
            new List<String>{
                '25 + 25',
                String.valueOf(policyRec.Id)
            };

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(
                new List<List<String>>{
                    inputs
                }
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.size(),
            'One result should be returned.'
        );

        System.assertEquals(
            Decimal.valueOf('50'),
            result[0],
            'Formula fee should evaluate to 50.'
        );
    }

    @IsTest
    static void calculateBlankFormulaReturnsZero() {

        List<String> inputs =
            new List<String>{
                '',
                ''
            };

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(
                new List<List<String>>{
                    inputs
                }
            );

        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('0.0'),
            result[0],
            'Blank formula should return zero.'
        );
    }

    @IsTest
    static void calculateFormulaFeeError() {

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(null);

        Test.stopTest();

        System.assertEquals(
            1,
            result.size(),
            'Exception path should return one value.'
        );

        System.assertEquals(
            Decimal.valueOf('0.0'),
            result[0],
            'Exception path should return zero.'
        );
    }

    @IsTest
    static void calculateCancelFeeFlatCancelForTMU() {

        InsurancePolicy policyRec =
            createRefundTestPolicy(
                UtilityClass.FLAT_CANCEL_FOR_TMU
            );

        List<String> inputs =
            new List<String>{
                '10 + 5',
                String.valueOf(policyRec.Id)
            };

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(
                new List<List<String>>{
                    inputs
                }
            );

        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('0.0'),
            result[0],
            'Flat Cancel for TMU should return zero.'
        );
    }

    @IsTest
    static void calculateFormulaWithBlankPolicyIdReturnsZero() {

        List<String> inputs =
            new List<String>{
                '25 + 25',
                ''
            };

        Test.startTest();

        List<Decimal> result =
            RefundManager.calculateCancelFee(
                new List<List<String>>{
                    inputs
                }
            );

        Test.stopTest();

        System.assertEquals(
            Decimal.valueOf('0.0'),
            result[0],
            'Formula with blank policy Id should return zero.'
        );
    }
}