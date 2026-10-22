/**
 * @description
 * Production-oriented test coverage for
 * BOKPaymentCancellationService.
 *
 * Covers:
 * - Cancel request XML generation
 * - Purchase Request Id validation
 * - Successful Mastercard response parsing
 * - Mastercard business rejection
 * - Missing/empty/malformed responses
 * - HTTP failures
 * - Correlation Id propagation
 * - End-to-end service callout using HttpCalloutMock
 *
 * No production data is accessed.
 */
@IsTest
private class BOKPaymentCancellationServiceTest {

    private static final String PURCHASE_REQUEST_ID =
        '29237047';

    private static final String CORRELATION_ID =
        'test-correlation-id-001';


    /* =========================================================
       HTTP MOCK
       ========================================================= */

    private class MastercardCancellationMock
        implements HttpCalloutMock {

        private Integer statusCode;
        private String responseBody;
        private String correlationId;
        private String expectedPurchaseRequestId;
        private Boolean validateRequest;

        MastercardCancellationMock(
            Integer statusCode,
            String responseBody,
            String correlationId,
            String expectedPurchaseRequestId,
            Boolean validateRequest
        ) {
            this.statusCode =
                statusCode;

            this.responseBody =
                responseBody;

            this.correlationId =
                correlationId;

            this.expectedPurchaseRequestId =
                expectedPurchaseRequestId;

            this.validateRequest =
                validateRequest;
        }

        public HttpResponse respond(
            HttpRequest request
        ) {

            if (validateRequest == true) {

                Assert.areEqual(
                    'POST',
                    request.getMethod(),
                    'Mastercard cancellation must use POST.'
                );

                Assert.isNotNull(
                    request.getBody(),
                    'Cancellation request body must be populated.'
                );

                Assert.isTrue(
                    request.getBody().contains(
                        'cancelPurchaseRequestsRequest'
                    ),
                    'Request must contain cancelPurchaseRequestsRequest.'
                );

                Assert.isTrue(
                    request.getBody().contains(
                        '<ser:purchaseRequestId>' +
                        expectedPurchaseRequestId +
                        '</ser:purchaseRequestId>'
                    ),
                    'Request must contain the correct Purchase Request Id.'
                );

                Assert.isFalse(
                    request.getBody().contains(
                        'blockPurchaseRequest'
                    ),
                    'Rescind must cancel the Purchase Request, not block it.'
                );
            }

            HttpResponse response =
                new HttpResponse();

            response.setStatusCode(
                statusCode
            );

            if (responseBody != null) {
                response.setBody(
                    responseBody
                );
            }

            if (
                String.isNotBlank(
                    correlationId
                )
            ) {
                response.setHeader(
                    'correlation-id',
                    correlationId
                );
            }

            return response;
        }
    }


    /* =========================================================
       RESPONSE BUILDERS
       ========================================================= */

    private static String buildSuccessResponse(
        String purchaseRequestId
    ) {

        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope ' +
                'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<soapenv:Body>' +
                    '<cancelPurchaseRequestsResponse ' +
                        'xmlns="http://mastercard.com/sd/pc2/service">' +
                        '<cancelRequestStatus>' +
                            '<purchaseRequestId>' +
                                purchaseRequestId +
                            '</purchaseRequestId>' +
                            '<approvalSuccessful>' +
                                'true' +
                            '</approvalSuccessful>' +
                            '<errorMessage ' +
                                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                                'xsi:nil="true"/>' +
                        '</cancelRequestStatus>' +
                        '<errorMessage ' +
                            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                            'xsi:nil="true"/>' +
                    '</cancelPurchaseRequestsResponse>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }


    private static String buildFailureResponse(
        String purchaseRequestId,
        String errorMessage
    ) {

        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope ' +
                'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<soapenv:Body>' +
                    '<cancelPurchaseRequestsResponse ' +
                        'xmlns="http://mastercard.com/sd/pc2/service">' +
                        '<cancelRequestStatus>' +
                            '<purchaseRequestId>' +
                                purchaseRequestId +
                            '</purchaseRequestId>' +
                            '<approvalSuccessful>' +
                                'false' +
                            '</approvalSuccessful>' +
                            '<errorMessage>' +
                                errorMessage +
                            '</errorMessage>' +
                        '</cancelRequestStatus>' +
                    '</cancelPurchaseRequestsResponse>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }


    /* =========================================================
       REQUEST BUILDER TESTS
       ========================================================= */

    @IsTest
    static void testBuildCancelRequestSuccess() {

        Test.startTest();

        String requestBody =
            BOKPaymentCancellationService.buildCancelRequest(
                    PURCHASE_REQUEST_ID
                );

        Test.stopTest();

        Assert.isNotNull(
            requestBody,
            'SOAP request must be returned.'
        );

        Assert.isTrue(
            requestBody.contains(
                'cancelPurchaseRequestsRequest'
            ),
            'SOAP request must contain cancellation operation.'
        );

        Assert.isTrue(
            requestBody.contains(
                '<ser:purchaseRequestId>' +
                PURCHASE_REQUEST_ID +
                '</ser:purchaseRequestId>'
            ),
            'SOAP request must contain the Purchase Request Id.'
        );

        Assert.isTrue(
            requestBody.contains(
                'http://mastercard.com/sd/pc2/service'
            ),
            'Mastercard service namespace must be present.'
        );

        Assert.isTrue(
            requestBody.contains(
                'http://schemas.xmlsoap.org/soap/envelope/'
            ),
            'SOAP envelope namespace must be present.'
        );

        Assert.isFalse(
            requestBody.contains(
                'blockPurchaseRequest'
            ),
            'Rescind request must not temporarily block the card.'
        );
    }


    @IsTest
    static void testBuildCancelRequestTrimsId() {

        String requestBody =
            BOKPaymentCancellationService.buildCancelRequest(
                    '   ' +
                    PURCHASE_REQUEST_ID +
                    '   '
                );

        Assert.isTrue(
            requestBody.contains(
                '<ser:purchaseRequestId>' +
                PURCHASE_REQUEST_ID +
                '</ser:purchaseRequestId>'
            ),
            'Whitespace must not be sent to Mastercard.'
        );
    }


    @IsTest
    static void testBuildCancelRequestAllows22Digits() {

        String maxLengthId =
            '1234567890123456789012';

        String requestBody =
            BOKPaymentCancellationService.buildCancelRequest(
                    maxLengthId
                );

        Assert.isTrue(
            requestBody.contains(
                maxLengthId
            ),
            'A valid 22 digit Purchase Request Id must be accepted.'
        );
    }


    @IsTest
    static void testBuildCancelRequestRejectsBlankId() {

        Boolean exceptionThrown =
            false;

        try {

            BOKPaymentCancellationService.buildCancelRequest(
                    null
                );

        } catch (
            BOKPaymentCancellationService.BOKCancellationException ex
        ) {

            exceptionThrown =
                true;

            Assert.areEqual(
                'BOK Purchase Request Id is required.',
                ex.getMessage()
            );
        }

        Assert.isTrue(
            exceptionThrown,
            'Blank Purchase Request Id must be rejected.'
        );
    }


    @IsTest
    static void testBuildCancelRequestRejectsNonNumericId() {

        Boolean exceptionThrown =
            false;

        try {

            BOKPaymentCancellationService.buildCancelRequest(
                    'ABC123'
                );

        } catch (
            BOKPaymentCancellationService.BOKCancellationException ex
        ) {

            exceptionThrown =
                true;

            Assert.areEqual(
                'BOK Purchase Request Id must contain digits only.',
                ex.getMessage()
            );
        }

        Assert.isTrue(
            exceptionThrown,
            'Non-numeric Purchase Request Id must be rejected.'
        );
    }


    @IsTest
    static void testBuildCancelRequestRejectsMoreThan22Digits() {

        Boolean exceptionThrown =
            false;

        try {

            BOKPaymentCancellationService.buildCancelRequest(
                    '12345678901234567890123'
                );

        } catch (
            BOKPaymentCancellationService.BOKCancellationException ex
        ) {

            exceptionThrown =
                true;

            Assert.areEqual(
                'BOK Purchase Request Id cannot exceed 22 digits.',
                ex.getMessage()
            );
        }

        Assert.isTrue(
            exceptionThrown,
            'Purchase Request Id longer than 22 digits must be rejected.'
        );
    }


    /* =========================================================
       RESPONSE PARSER TESTS
       ========================================================= */

    @IsTest
    static void testParseSuccessfulResponse() {

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                        buildSuccessResponse(
                            PURCHASE_REQUEST_ID
                        )
                    );

        Assert.areEqual(
            true,
            result.success,
            'Approved Mastercard cancellation must return success.'
        );

        Assert.areEqual(
            PURCHASE_REQUEST_ID,
            result.purchaseRequestId,
            'Returned Purchase Request Id must be parsed.'
        );

        Assert.isTrue(
            String.isBlank(
                result.errorMessage
            ),
            'Successful response should not contain an error.'
        );
    }


    @IsTest
    static void testParseRejectedResponseWithError() {

        String mastercardError =
            'Purchase request cannot be cancelled.';

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                        buildFailureResponse(
                            PURCHASE_REQUEST_ID,
                            mastercardError
                        )
                    );

        Assert.areEqual(
            false,
            result.success,
            'Rejected Mastercard cancellation must fail.'
        );

        Assert.areEqual(
            PURCHASE_REQUEST_ID,
            result.purchaseRequestId
        );

        Assert.areEqual(
            mastercardError,
            result.errorMessage,
            'Mastercard business error must be preserved.'
        );
    }


    @IsTest
    static void testParseRejectedResponseWithoutError() {

        String responseBody =
            '<cancelRequestStatus>' +
                '<purchaseRequestId>' +
                    PURCHASE_REQUEST_ID +
                '</purchaseRequestId>' +
                '<approvalSuccessful>false</approvalSuccessful>' +
            '</cancelRequestStatus>';

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                        responseBody
                    );

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            'Mastercard did not approve the cancellation request.',
            result.errorMessage,
            'A meaningful fallback error should be returned.'
        );
    }


    @IsTest
    static void testParseEmptyResponse() {

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                        null
                    );

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            'Empty Mastercard cancellation response.',
            result.errorMessage
        );
    }


    @IsTest
    static void testParseMalformedResponse() {

        /*
         * Do not use a fragment such as '<InvalidXml' here.
         *
         * In some Salesforce runtimes that specific incomplete
         * token can cause an internal DOM parser
         * System.UnexpectedException before Apex can handle the
         * parsing exception normally.
         *
         * This XML is still intentionally malformed, but it
         * produces the normal catchable XML parsing exception
         * that parseCancelResponse() is designed to handle.
         */
        String malformedXml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<root>' +
                '<child>' +
            '</root>';

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                    malformedXml
                );

        Assert.areEqual(
            false,
            result.success,
            'Malformed XML must not be treated as a successful cancellation.'
        );

        Assert.isNotNull(
            result.errorMessage,
            'Malformed XML must return a controlled parser error.'
        );

        Assert.isTrue(
            result.errorMessage.startsWith(
                'Unable to parse Mastercard cancellation response:'
            ),
            'Malformed XML must be handled safely.'
        );
    }


    @IsTest
    static void testParseResponseLevelError() {

        String responseBody =
            '<?xml version="1.0"?>' +
            '<soapenv:Envelope ' +
                'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<soapenv:Body>' +
                    '<cancelPurchaseRequestsResponse>' +
                        '<errorMessage>' +
                            'Invalid purchase request.' +
                        '</errorMessage>' +
                    '</cancelPurchaseRequestsResponse>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                        responseBody
                    );

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            'Invalid purchase request.',
            result.errorMessage
        );
    }


    @IsTest
    static void testParseMissingCancelRequestStatusAndError() {

        String responseBody =
            '<?xml version="1.0"?>' +
            '<soapenv:Envelope ' +
                'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<soapenv:Body>' +
                    '<cancelPurchaseRequestsResponse/>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.parseCancelResponse(
                        responseBody
                    );

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            'Mastercard cancellation response did not contain cancelRequestStatus.',
            result.errorMessage
        );
    }


    /* =========================================================
       END-TO-END SERVICE TESTS WITH MOCK CALLOUT
       ========================================================= */

    @IsTest
    static void testCancelPurchaseRequestSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new MastercardCancellationMock(
                200,
                buildSuccessResponse(
                    PURCHASE_REQUEST_ID
                ),
                CORRELATION_ID,
                PURCHASE_REQUEST_ID,
                true
            )
        );

        Test.startTest();

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.cancelPurchaseRequest(
                        PURCHASE_REQUEST_ID
                    );

        Test.stopTest();

        Assert.areEqual(
            true,
            result.success
        );

        Assert.areEqual(
            PURCHASE_REQUEST_ID,
            result.purchaseRequestId
        );

        Assert.areEqual(
            200,
            result.httpStatusCode
        );

        Assert.areEqual(
            CORRELATION_ID,
            result.correlationId
        );
    }


    @IsTest
    static void testCancelPurchaseRequestBusinessFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new MastercardCancellationMock(
                200,
                buildFailureResponse(
                    PURCHASE_REQUEST_ID,
                    'Cancellation not permitted.'
                ),
                CORRELATION_ID,
                PURCHASE_REQUEST_ID,
                true
            )
        );

        Test.startTest();

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.cancelPurchaseRequest(
                        PURCHASE_REQUEST_ID
                    );

        Test.stopTest();

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            'Cancellation not permitted.',
            result.errorMessage
        );

        Assert.areEqual(
            200,
            result.httpStatusCode
        );
    }


    @IsTest
    static void testCancelPurchaseRequestHttpFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new MastercardCancellationMock(
                500,
                '<error>Internal Server Error</error>',
                CORRELATION_ID,
                PURCHASE_REQUEST_ID,
                true
            )
        );

        Test.startTest();

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.cancelPurchaseRequest(
                        PURCHASE_REQUEST_ID
                    );

        Test.stopTest();

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            500,
            result.httpStatusCode
        );

        Assert.areEqual(
            'Mastercard cancellation request failed. HTTP Status: 500',
            result.errorMessage
        );
    }


    @IsTest
    static void testCancelPurchaseRequestEmpty200Response() {

        Test.setMock(
            HttpCalloutMock.class,
            new MastercardCancellationMock(
                200,
                '',
                CORRELATION_ID,
                PURCHASE_REQUEST_ID,
                true
            )
        );

        Test.startTest();

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.cancelPurchaseRequest(
                        PURCHASE_REQUEST_ID
                    );

        Test.stopTest();

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            200,
            result.httpStatusCode
        );

        Assert.areEqual(
            'Mastercard cancellation request failed. HTTP Status: 200',
            result.errorMessage
        );
    }


    @IsTest
    static void testCancelPurchaseRequestInvalidIdHandledSafely() {

        Test.startTest();

        BOKPaymentCancellationService.CancellationResult
            result =
                BOKPaymentCancellationService.cancelPurchaseRequest(
                        'ABC'
                    );

        Test.stopTest();

        Assert.areEqual(
            false,
            result.success
        );

        Assert.areEqual(
            'BOK Purchase Request Id must contain digits only.',
            result.errorMessage
        );
    }
}