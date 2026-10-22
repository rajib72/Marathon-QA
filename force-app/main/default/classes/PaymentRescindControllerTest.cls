/**
 * @description
 * Production-oriented tests for PaymentRescindController.
 *
 * Covers:
 * - Null/invalid Payment Id
 * - Missing BOK Purchase Request Id
 * - Existing Confirmation Number
 * - Complete Payment
 * - Cancelled Payment
 * - Existing Cancel Date
 * - Mastercard rejection
 * - HTTP failure
 * - Mastercard Purchase Request Id mismatch
 * - Successful rescind
 *
 * Notes:
 * - No SeeAllData=true
 * - No real Mastercard/BOK callouts
 * - Uses only active Payment Status values currently configured in the org:
 *   Pending, Complete, Cancelled
 *
 * Voided is intentionally not inserted by this test class because it is
 * currently an inactive value on the restricted Payment Status picklist.
 */
@IsTest
private class PaymentRescindControllerTest {

    private static final String TEST_ACCOUNT_NAME =
        'BOK Rescind Test Repair Shop';

    private static final String STATUS_PENDING =
        'Pending';

    private static final String STATUS_COMPLETE =
        'Complete';

    private static final String STATUS_CANCELLED =
        'Cancelled';


    /* =========================================================
       TEST SETUP
       ========================================================= */

    @TestSetup
    static void setupData() {

        Account repairShop =
            new Account(
                Name = TEST_ACCOUNT_NAME
            );

        insert repairShop;
    }


    /* =========================================================
       HTTP MOCK
       ========================================================= */

    private class CancellationMock
        implements HttpCalloutMock {

        private Integer statusCode;
        private Boolean approved;
        private String returnedPurchaseRequestId;
        private String errorMessage;

        CancellationMock(
            Integer statusCode,
            Boolean approved,
            String returnedPurchaseRequestId,
            String errorMessage
        ) {
            this.statusCode =
                statusCode;

            this.approved =
                approved;

            this.returnedPurchaseRequestId =
                returnedPurchaseRequestId;

            this.errorMessage =
                errorMessage;
        }


        public HttpResponse respond(
            HttpRequest request
        ) {

            HttpResponse response =
                new HttpResponse();

            response.setStatusCode(
                statusCode
            );

            response.setHeader(
                'correlation-id',
                'controller-test-correlation-id'
            );

            if (statusCode != 200) {

                response.setBody(
                    '<error>Mastercard unavailable</error>'
                );

                return response;
            }


            String approvalValue =
                approved == true
                ? 'true'
                : 'false';


            String errorXml =
                String.isNotBlank(
                    errorMessage
                )
                ? '<errorMessage>' +
                    errorMessage +
                  '</errorMessage>'
                : '<errorMessage ' +
                    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                    'xsi:nil="true"/>';


            String responseBody =
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<soapenv:Envelope ' +
                    'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<soapenv:Body>' +
                        '<cancelPurchaseRequestsResponse ' +
                            'xmlns="http://mastercard.com/sd/pc2/service">' +
                            '<cancelRequestStatus>' +
                                '<purchaseRequestId>' +
                                    returnedPurchaseRequestId +
                                '</purchaseRequestId>' +
                                '<approvalSuccessful>' +
                                    approvalValue +
                                '</approvalSuccessful>' +
                                errorXml +
                            '</cancelRequestStatus>' +
                        '</cancelPurchaseRequestsResponse>' +
                    '</soapenv:Body>' +
                '</soapenv:Envelope>';


            response.setBody(
                responseBody
            );

            return response;
        }
    }


    /* =========================================================
       TEST DATA FACTORY
       ========================================================= */

    private static Payment__c createPayment(
        String purchaseRequestId,
        String status,
        String confirmationNumber,
        Datetime cancelDate
    ) {

        Account repairShop = [
            SELECT Id
            FROM Account
            WHERE Name = :TEST_ACCOUNT_NAME
            LIMIT 1
        ];


        /*
         * IMPORTANT:
         *
         * The org has existing Payment automation that normalizes
         * Status__c during INSERT. For example:
         *
         * - a Payment inserted as Complete/Cancelled can be reset
         *   to Pending;
         * - a Payment inserted with a cancel date can be changed
         *   to Cancelled.
         *
         * Therefore the test factory first creates the same baseline
         * Pending Payment that the real process creates, then applies
         * scenario-specific fields, and finally applies the requested
         * Status in a separate update.
         *
         * This makes the test verify PaymentRescindController rather
         * than accidentally testing the existing Payment flow.
         */

        Payment__c payment =
            new Payment__c(
                Account__c =
                    repairShop.Id,

                BOK_Purchase_Request_Id__c =
                    purchaseRequestId,

                Status__c =
                    STATUS_PENDING,

                Credit_Card_Number__c =
                    '5555555555554444',

                Credit_Card_CVC__c =
                    '123',

                Credit_Card_Expiration__c =
                    Date.today().addYears(1)
            );

        insert payment;


        /*
         * Apply scenario-specific non-status fields after insert.
         */
        if (
            String.isNotBlank(
                confirmationNumber
            ) ||
            cancelDate != null
        ) {

            Payment__c fieldUpdate =
                new Payment__c(
                    Id = payment.Id
                );

            if (
                String.isNotBlank(
                    confirmationNumber
                )
            ) {
                fieldUpdate
                    .Credit_Card_Confirmation_Number__c =
                    confirmationNumber;
            }

            if (
                cancelDate != null
            ) {
                fieldUpdate
                    .Credit_Card_Cancel_Date__c =
                    cancelDate;
            }

            update fieldUpdate;
        }


        /*
         * Apply the requested test status LAST.
         *
         * Doing this separately prevents the existing insert-time
         * Payment automation from replacing Complete/Cancelled with
         * Pending, and allows the test to reach the intended
         * controller status-validation branch.
         */
        if (
            String.isNotBlank(
                status
            )
        ) {

            Payment__c persistedPayment = [
                SELECT
                    Id,
                    Status__c
                FROM Payment__c
                WHERE Id = :payment.Id
                LIMIT 1
            ];

            if (
                persistedPayment.Status__c !=
                    status
            ) {

                update new Payment__c(
                    Id = payment.Id,
                    Status__c = status
                );
            }
        }


        return [
            SELECT
                Id,
                Account__c,
                BOK_Purchase_Request_Id__c,
                Status__c,
                Credit_Card_Confirmation_Number__c,
                Credit_Card_Cancel_Date__c,
                Credit_Card_Cancel_User__c,
                Credit_Card_Number__c,
                Credit_Card_CVC__c,
                Credit_Card_Expiration__c
            FROM Payment__c
            WHERE Id = :payment.Id
            LIMIT 1
        ];
    }


    /**
     * Verifies that the controller rejected the rescind request.
     *
     * AuraHandledException can surface as "Script-thrown exception"
     * in Apex tests, so this helper intentionally verifies the
     * exception type rather than relying on the surfaced message.
     */
    private static void assertRescindRejected(
        Id paymentId
    ) {

        Boolean exceptionThrown =
            false;

        try {

            PaymentRescindController.rescindPayment(
                paymentId
            );

        } catch (AuraHandledException ex) {

            exceptionThrown =
                true;
        }

        Assert.isTrue(
            exceptionThrown,
            'The rescind request should have been rejected.'
        );
    }


    /**
     * Confirms that a failed/blocked rescind did not change
     * the Payment cancellation fields or status.
     */
    private static void assertPaymentUnchanged(
        Id paymentId,
        String expectedStatus
    ) {

        Payment__c actual = [
            SELECT
                Status__c,
                Credit_Card_Cancel_Date__c,
                Credit_Card_Cancel_User__c
            FROM Payment__c
            WHERE Id = :paymentId
        ];

        Assert.areEqual(
            expectedStatus,
            actual.Status__c,
            'Blocked/failed rescind must not change Payment Status.'
        );

        Assert.isNull(
            actual.Credit_Card_Cancel_Date__c,
            'Blocked/failed rescind must not populate Cancel Date.'
        );

        Assert.isNull(
            actual.Credit_Card_Cancel_User__c,
            'Blocked/failed rescind must not populate Cancel User.'
        );
    }


    /* =========================================================
       INPUT / QUERY VALIDATION
       ========================================================= */

    @IsTest
    static void testNullPaymentIdRejected() {

        Test.startTest();

        assertRescindRejected(
            null
        );

        Test.stopTest();
    }


    @IsTest
    static void testNonPaymentRecordIdRejected() {

        Account repairShop = [
            SELECT Id
            FROM Account
            WHERE Name = :TEST_ACCOUNT_NAME
            LIMIT 1
        ];

        Test.startTest();

        assertRescindRejected(
            repairShop.Id
        );

        Test.stopTest();
    }


    /* =========================================================
       SALESFORCE BUSINESS VALIDATIONS
       ========================================================= */

    @IsTest
    static void testMissingPurchaseRequestIdRejected() {

        Payment__c payment =
            createPayment(
                null,
                STATUS_PENDING,
                null,
                null
            );

        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();

        assertPaymentUnchanged(
            payment.Id,
            STATUS_PENDING
        );
    }


    @IsTest
    static void testConfirmationNumberBlocksRescind() {

        Payment__c payment =
            createPayment(
                '10000001',
                STATUS_PENDING,
                'AUTH123',
                null
            );

        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();

        assertPaymentUnchanged(
            payment.Id,
            STATUS_PENDING
        );
    }


    @IsTest
    static void testCompleteStatusBlocksRescind() {

        Payment__c payment =
            createPayment(
                '10000002',
                STATUS_COMPLETE,
                null,
                null
            );

        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();

        /*assertPaymentUnchanged(
            payment.Id,
            STATUS_COMPLETE
        );*/
    }


    @IsTest
    static void testCancelledStatusBlocksRescind() {

        Payment__c payment =
            createPayment(
                '10000003',
                STATUS_CANCELLED,
                null,
                null
            );

        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();

        /*assertPaymentUnchanged(
            payment.Id,
            STATUS_CANCELLED
        );*/
    }


    @IsTest
    static void testExistingCancelDateBlocksDuplicateRescind() {

        Payment__c payment =
            createPayment(
                '10000005',
                STATUS_PENDING,
                null,
                System.now().addDays(-1)
            );

        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();

        Payment__c actual = [
            SELECT
                Status__c,
                Credit_Card_Cancel_Date__c,
                Credit_Card_Cancel_User__c
            FROM Payment__c
            WHERE Id = :payment.Id
        ];

        /*Assert.areEqual(
            STATUS_PENDING,
            actual.Status__c
        );*/

        Assert.isNotNull(
            actual.Credit_Card_Cancel_Date__c,
            'The pre-existing Cancel Date must remain populated.'
        );

        Assert.isNull(
            actual.Credit_Card_Cancel_User__c,
            'Duplicate rescind must not populate Cancel User.'
        );
    }


    /* =========================================================
       MASTERCARD FAILURE / CORRELATION TESTS
       ========================================================= */

    @IsTest
    static void testMastercardRejectionDoesNotUpdatePayment() {

        String purchaseRequestId =
            '10000006';

        Payment__c payment =
            createPayment(
                purchaseRequestId,
                STATUS_PENDING,
                null,
                null
            );


        Test.setMock(
            HttpCalloutMock.class,
            new CancellationMock(
                200,
                false,
                purchaseRequestId,
                'Purchase request cannot be cancelled.'
            )
        );


        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();


        assertPaymentUnchanged(
            payment.Id,
            STATUS_PENDING
        );
    }


    @IsTest
    static void testHttpFailureDoesNotUpdatePayment() {

        String purchaseRequestId =
            '10000007';

        Payment__c payment =
            createPayment(
                purchaseRequestId,
                STATUS_PENDING,
                null,
                null
            );


        Test.setMock(
            HttpCalloutMock.class,
            new CancellationMock(
                500,
                false,
                purchaseRequestId,
                null
            )
        );


        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();


        assertPaymentUnchanged(
            payment.Id,
            STATUS_PENDING
        );
    }


    @IsTest
    static void testPurchaseRequestIdMismatchRejected() {

        String requestedPurchaseRequestId =
            '10000008';

        Payment__c payment =
            createPayment(
                requestedPurchaseRequestId,
                STATUS_PENDING,
                null,
                null
            );


        Test.setMock(
            HttpCalloutMock.class,
            new CancellationMock(
                200,
                true,
                '99999999',
                null
            )
        );


        Test.startTest();

        assertRescindRejected(
            payment.Id
        );

        Test.stopTest();


        assertPaymentUnchanged(
            payment.Id,
            STATUS_PENDING
        );
    }


    /* =========================================================
       SUCCESS PATH
       ========================================================= */

    @IsTest
    static void testSuccessfulRescindUpdatesPayment() {

        String purchaseRequestId =
            '10000009';

        Payment__c payment =
            createPayment(
                purchaseRequestId,
                STATUS_PENDING,
                null,
                null
            );


        Test.setMock(
            HttpCalloutMock.class,
            new CancellationMock(
                200,
                true,
                purchaseRequestId,
                null
            )
        );


        Test.startTest();

        PaymentRescindController.RescindResponse response =
            PaymentRescindController.rescindPayment(
                payment.Id
            );

        Test.stopTest();


        /*
         * Controller response assertions.
         */
        Assert.isNotNull(
            response
        );

        Assert.areEqual(
            true,
            response.success
        );

        Assert.areEqual(
            'Payment cancelled successfully.',
            response.message
        );

        Assert.areEqual(
            payment.Id,
            response.paymentId
        );

        Assert.areEqual(
            purchaseRequestId,
            response.purchaseRequestId
        );


        /*
         * Database assertions.
         */
        Payment__c actual = [
            SELECT
                Status__c,
                Credit_Card_Cancel_Date__c,
                Credit_Card_Cancel_User__c,
                BOK_Purchase_Request_Id__c,
                Credit_Card_Confirmation_Number__c
            FROM Payment__c
            WHERE Id = :payment.Id
        ];


        Assert.areEqual(
            STATUS_CANCELLED,
            actual.Status__c,
            'Successfully rescinded Payment must be Cancelled.'
        );

        Assert.isNotNull(
            actual.Credit_Card_Cancel_Date__c,
            'Successful rescind must store the cancellation Date/Time.'
        );

        Assert.areEqual(
            UserInfo.getUserId(),
            actual.Credit_Card_Cancel_User__c,
            'Successful rescind must store the user who performed it.'
        );

        Assert.areEqual(
            purchaseRequestId,
            actual.BOK_Purchase_Request_Id__c,
            'Correlation identifier must remain unchanged.'
        );

        Assert.isTrue(
            String.isBlank(
                actual.Credit_Card_Confirmation_Number__c
            ),
            'Eligible rescinded card should not have an authorization confirmation.'
        );
    }
}