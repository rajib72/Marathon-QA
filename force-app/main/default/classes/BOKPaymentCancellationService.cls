/**
 * @description
 * Dedicated service for cancelling/rescinding BOK/Mastercard
 * virtual card purchase requests.
 *
 * Responsibilities:
 * - Validate Purchase Request Id
 * - Build Mastercard CancelPurchaseRequests SOAP request
 * - Execute the existing Mastercard authenticated callout
 * - Parse the Mastercard cancellation response
 *
 * This class does NOT update Payment__c.
 */
public with sharing class BOKPaymentCancellationService {

    private static final String SOAP_NAMESPACE =
        'http://schemas.xmlsoap.org/soap/envelope/';

    private static final String SERVICE_NAMESPACE =
        'http://mastercard.com/sd/pc2/service';

    private static final Integer MAX_PURCHASE_REQUEST_ID_LENGTH = 22;

    /**
     * Result returned to the calling layer.
     */
    public class CancellationResult {

        public Boolean success;
        public String purchaseRequestId;
        public String errorMessage;

        public Integer httpStatusCode;
        public String correlationId;

        public CancellationResult() {
            success = false;
        }
    }

    /**
     * Cancels one Mastercard purchase request.
     *
     * @param purchaseRequestId
     *        BOK/Mastercard Purchase Request Id stored on Payment__c.
     *
     * @return CancellationResult
     */
    public static CancellationResult cancelPurchaseRequest(
        String purchaseRequestId
    ) {

        CancellationResult result =
            new CancellationResult();

        try {

            /*
             * Validate before making an external callout.
             */
            validatePurchaseRequestId(
                purchaseRequestId
            );

            String requestBody =
                buildCancelRequest(
                    purchaseRequestId
                );

            /*
             * Reuse existing Mastercard OAuth/callout infrastructure.
             * Do NOT duplicate OAuth/signature logic here.
             */
            HttpResponse response =
                OAuthRequestGenerator.sendRequest(
                    requestBody
                );

            result.httpStatusCode =
                response.getStatusCode();

            result.correlationId =
                response.getHeader(
                    'correlation-id'
                );

            /*
             * Transport-level validation.
             */
            if (
                response.getStatusCode() != 200 ||
                String.isBlank(response.getBody())
            ) {

                result.success = false;

                result.errorMessage =
                    'Mastercard cancellation request failed. ' +
                    'HTTP Status: ' +
                    response.getStatusCode();

                logError(
                    result.errorMessage
                );

                return result;
            }

            /*
             * Parse Mastercard business response.
             */
            CancellationResult parsedResult =
                parseCancelResponse(
                    response.getBody()
                );

            /*
             * Preserve HTTP metadata.
             */
            parsedResult.httpStatusCode =
                response.getStatusCode();

            parsedResult.correlationId =
                response.getHeader(
                    'correlation-id'
                );

            return parsedResult;

        } catch (Exception ex) {

            result.success = false;

            result.errorMessage =
                ex.getMessage();

            logError(
                'BOK Payment cancellation failed: ' +
                ex.getMessage() +
                ' Line: ' +
                ex.getLineNumber()
            );

            return result;
        }
    }

    /**
     * Generates Mastercard CancelPurchaseRequests SOAP XML.
     *
     * BlockPurchaseRequest is intentionally NOT supplied because
     * this ticket requires permanent cancellation/rescind,
     * not temporary blocking.
     */
    public static String buildCancelRequest(
        String purchaseRequestId
    ) {

        validatePurchaseRequestId(
            purchaseRequestId
        );

        Dom.Document document =
            new Dom.Document();

        Dom.XmlNode envelope =
            document.createRootElement(
                'Envelope',
                SOAP_NAMESPACE,
                'soapenv'
            );

        envelope.addChildElement(
            'Header',
            SOAP_NAMESPACE,
            'soapenv'
        );

        Dom.XmlNode body =
            envelope.addChildElement(
                'Body',
                SOAP_NAMESPACE,
                'soapenv'
            );

        Dom.XmlNode cancelRequest =
            body.addChildElement(
                'cancelPurchaseRequestsRequest',
                SERVICE_NAMESPACE,
                'ser'
            );

        Dom.XmlNode purchaseRequestNode =
            cancelRequest.addChildElement(
                'purchaseRequestId',
                SERVICE_NAMESPACE,
                'ser'
            );

        purchaseRequestNode.addTextNode(
            purchaseRequestId.trim()
        );

        return document.toXmlString();
    }

    /**
     * Parses Mastercard CancelPurchaseRequests response.
     *
     * Expected structure:
     *
     * cancelPurchaseRequestsResponse
     *      cancelRequestStatus
     *          purchaseRequestId
     *          approvalSuccessful
     *          errorMessage
     */
    public static CancellationResult parseCancelResponse(
        String responseBody
    ) {

        CancellationResult result =
            new CancellationResult();

        if (String.isBlank(responseBody)) {

            result.errorMessage =
                'Empty Mastercard cancellation response.';

            return result;
        }

        try {

            Dom.Document document =
                new Dom.Document();

            document.load(
                responseBody
            );

            Dom.XmlNode root =
                document.getRootElement();

            Dom.XmlNode cancelRequestStatus =
                findFirstNode(
                    root,
                    'cancelRequestStatus'
                );

            if (cancelRequestStatus == null) {

                result.errorMessage =
                    getResponseLevelError(root);

                if (
                    String.isBlank(
                        result.errorMessage
                    )
                ) {
                    result.errorMessage =
                        'Mastercard cancellation response did not contain cancelRequestStatus.';
                }

                return result;
            }

            Dom.XmlNode purchaseRequestNode =
                findDirectChild(
                    cancelRequestStatus,
                    'purchaseRequestId'
                );

            Dom.XmlNode approvalNode =
                findDirectChild(
                    cancelRequestStatus,
                    'approvalSuccessful'
                );

            Dom.XmlNode errorNode =
                findDirectChild(
                    cancelRequestStatus,
                    'errorMessage'
                );

            if (purchaseRequestNode != null) {

                result.purchaseRequestId =
                    purchaseRequestNode.getText();
            }

            String approvalValue =
                approvalNode != null
                ? approvalNode.getText()
                : null;

            result.success =
                String.isNotBlank(approvalValue) &&
                approvalValue.trim().toLowerCase()
                    == 'true';

            if (errorNode != null) {

                String errorText =
                    errorNode.getText();

                if (
                    String.isNotBlank(
                        errorText
                    )
                ) {
                    result.errorMessage =
                        errorText.trim();
                }
            }

            /*
             * If Mastercard returned false without an explicit
             * error message, retain an internal meaningful message.
             */
            if (
                result.success != true &&
                String.isBlank(
                    result.errorMessage
                )
            ) {

                result.errorMessage =
                    'Mastercard did not approve the cancellation request.';
            }

            return result;

        } catch (Exception ex) {

            result.success = false;

            result.errorMessage =
                'Unable to parse Mastercard cancellation response: ' +
                ex.getMessage();

            return result;
        }
    }

    /**
     * Validates Mastercard purchaseRequestId.
     *
     * Mastercard documentation:
     * - Numeric identifier
     * - Maximum 22 digits
     */
    private static void validatePurchaseRequestId(
        String purchaseRequestId
    ) {

        if (
            String.isBlank(
                purchaseRequestId
            )
        ) {

            throw new BOKCancellationException(
                'BOK Purchase Request Id is required.'
            );
        }

        String normalizedId =
            purchaseRequestId.trim();

        if (
            normalizedId.length() >
            MAX_PURCHASE_REQUEST_ID_LENGTH
        ) {

            throw new BOKCancellationException(
                'BOK Purchase Request Id cannot exceed 22 digits.'
            );
        }

        if (
            !Pattern.matches(
                '^[0-9]+$',
                normalizedId
            )
        ) {

            throw new BOKCancellationException(
                'BOK Purchase Request Id must contain digits only.'
            );
        }
    }

    /**
     * Finds the first matching node anywhere below the supplied node.
     * Namespace prefixes are intentionally ignored because Mastercard
     * samples use different SOAP/service prefixes.
     */
    private static Dom.XmlNode findFirstNode(
        Dom.XmlNode parentNode,
        String targetName
    ) {

        if (parentNode == null) {
            return null;
        }

        if (
            parentNode.getName() ==
            targetName
        ) {
            return parentNode;
        }

        for (
            Dom.XmlNode child :
            parentNode.getChildElements()
        ) {

            Dom.XmlNode match =
                findFirstNode(
                    child,
                    targetName
                );

            if (match != null) {
                return match;
            }
        }

        return null;
    }

    /**
     * Finds a direct child by local element name.
     */
    private static Dom.XmlNode findDirectChild(
        Dom.XmlNode parentNode,
        String childName
    ) {

        if (parentNode == null) {
            return null;
        }

        for (
            Dom.XmlNode child :
            parentNode.getChildElements()
        ) {

            if (
                child.getName() ==
                childName
            ) {
                return child;
            }
        }

        return null;
    }

    /**
     * Attempts to retrieve a response-level Mastercard error.
     */
    private static String getResponseLevelError(
        Dom.XmlNode root
    ) {

        Dom.XmlNode errorNode =
            findFirstNode(
                root,
                'errorMessage'
            );

        if (errorNode == null) {
            return null;
        }

        String errorText =
            errorNode.getText();

        return String.isNotBlank(errorText)
            ? errorText.trim()
            : null;
    }

    /**
     * Uses the project's existing logging framework.
     */
    private static void logError(
        String message
    ) {

        try {

            QDX_LOG.error(
                message
            );

            QDX_Log.Requests errorRequest =
                new QDX_Log.Requests();

            errorRequest.errorMessage =
                message;

            errorRequest.flowName =
                'BOKPaymentCancellationService.cls';

            QDX_Log.publishError(
                new List<QDX_Log.Requests>{
                    errorRequest
                }
            );

        } catch (Exception loggingException) {

            /*
             * Logging must never replace the original integration
             * error with another exception.
             */
            System.debug(
                LoggingLevel.ERROR,
                'Unable to publish BOK cancellation log: ' +
                loggingException.getMessage()
            );
        }
    }

    /**
     * Service-specific exception.
     */
    public class BOKCancellationException
        extends Exception {
    }
}