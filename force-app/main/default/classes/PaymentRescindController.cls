/**
 * @description
 * Controller for the Rescind Payment Quick Action.
 *
 * Responsibilities:
 * - Validate the Salesforce Payment record
 * - Prevent invalid/duplicate rescind attempts
 * - Call BOKPaymentCancellationService
 * - Update Payment only after Mastercard confirms cancellation
 *
 * Mastercard SOAP/callout logic must remain inside
 * BOKPaymentCancellationService.
 */
public with sharing class PaymentRescindController {

    private static final String ERROR_MESSAGE =
        'Cancellation request was unable to be processed';

    private static final String SUCCESS_MESSAGE =
        'Payment cancelled successfully.';

    private static final String STATUS_PENDING =
        'Pending';

    private static final String STATUS_PROCESSED =
        'Processed';

    private static final String STATUS_CANCELLED =
        'Cancelled';

    private static final String STATUS_VOIDED =
        'Voided';

    private static final String STATUS_FAILED =
        'Failed';

    private static final Set<String> NON_RESCINDABLE_STATUSES =
        new Set<String>{
            STATUS_PROCESSED,
            STATUS_CANCELLED,
            STATUS_VOIDED
        };


    /**
     * Called by paymentRescindAction LWC.
     */
    @AuraEnabled
    public static RescindResponse rescindPayment(
        Id paymentId
    ) {

        if (paymentId == null) {
            throwCancellationError();
        }

        Payment__c payment;

        /*
         * Query in user mode because this method is directly
         * invoked from the user-facing Quick Action.
         */
        try {

            payment = [
                SELECT
                    Id,
                    BOK_Purchase_Request_Id__c,
                    Credit_Card_Confirmation_Number__c,
                    Credit_Card_Cancel_Date__c,
                    Credit_Card_Cancel_User__c,
                    Status__c
                FROM Payment__c
                WHERE Id = :paymentId
                WITH USER_MODE
                LIMIT 1
            ];

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.ERROR,
                'Unable to load Payment for rescind. ' +
                ex.getMessage()
            );

            throwCancellationError();

            return null;
        }


        /*
         * -----------------------------------------
         * Salesforce-side business validations
         * -----------------------------------------
         */


        /*
         * Mastercard cannot cancel a Payment without
         * the corresponding Purchase Request Id.
         */
        if (
            String.isBlank(
                payment.BOK_Purchase_Request_Id__c
            )
        ) {
            throwCancellationError();
        }


        /*
         * Requirement:
         * Card must not already have been
         * processed/authorized.
         */
        if (
            String.isNotBlank(
                payment.Credit_Card_Confirmation_Number__c
            )
        ) {
            throwCancellationError();
        }


        /*
         * Do not allow rescind when the Payment has already
         * been processed, cancelled, or voided.
         *
         * Pending Payments remain eligible for rescind.
         */
        if (
            String.isNotBlank(
                payment.Status__c
            ) &&
            NON_RESCINDABLE_STATUSES.contains(
                payment.Status__c
            )
        ) {
            throwCancellationError();
        }


        /*
         * Additional duplicate rescind protection.
         */
        if (
            payment.Credit_Card_Cancel_Date__c != null
        ) {
            throwCancellationError();
        }


        /*
         * -----------------------------------------
         * Mastercard cancellation
         * -----------------------------------------
         *
         * No Salesforce DML has occurred before
         * this external callout.
         */

        BOKPaymentCancellationService.CancellationResult
            cancellationResult =
                BOKPaymentCancellationService.cancelPurchaseRequest(
                        payment.BOK_Purchase_Request_Id__c
                    );


        /*
         * Mastercard must explicitly approve
         * the cancellation.
         */
        if (
            cancellationResult == null ||
            cancellationResult.success != true
        ) {

            System.debug(
                LoggingLevel.ERROR,
                'Mastercard cancellation failed. ' +
                (
                    cancellationResult != null
                    ? cancellationResult.errorMessage
                    : 'No response returned from cancellation service.'
                )
            );

            throwCancellationError();
        }


        /*
         * Verify that Mastercard cancelled the same
         * Purchase Request that Salesforce requested.
         */
        if (
            String.isBlank(
                cancellationResult.purchaseRequestId
            ) ||
            cancellationResult.purchaseRequestId !=
                payment.BOK_Purchase_Request_Id__c
        ) {

            System.debug(
                LoggingLevel.ERROR,
                'Mastercard cancellation Purchase Request Id mismatch.'
            );

            throwCancellationError();
        }


        /*
         * -----------------------------------------
         * Mastercard confirmed cancellation.
         *
         * ONLY NOW update Salesforce.
         * -----------------------------------------
         */

        Payment__c paymentToUpdate =
            new Payment__c(
                Id = payment.Id,

                Credit_Card_Cancel_Date__c =
                    System.now(),

                Credit_Card_Cancel_User__c =
                    UserInfo.getUserId(),

                Status__c =
                    STATUS_CANCELLED
            );


        try {

            /*
             * Explicit CRUD/FLS protection.
             */
            if (
                !Schema.sObjectType.Payment__c.isUpdateable() ||

                !Schema.sObjectType.Payment__c.fields.Credit_Card_Cancel_Date__c.isUpdateable() ||

                !Schema.sObjectType.Payment__c.fields.Credit_Card_Cancel_User__c.isUpdateable() ||

                !Schema.sObjectType.Payment__c.fields.Status__c.isUpdateable()
            ) {

                throwCancellationError();
            }

            update paymentToUpdate;

        } catch (AuraHandledException ex) {

            throw ex;

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.ERROR,
                'Payment was cancelled by Mastercard, ' +
                'but Salesforce Payment update failed. ' +
                ex.getMessage()
            );

            /*
             * Mastercard may already have cancelled the VCN.
             * This condition must be captured in integration
             * logging/reconciliation.
             */
            throwCancellationError();
        }


        RescindResponse response =
            new RescindResponse();

        response.success =
            true;

        response.message =
            SUCCESS_MESSAGE;

        response.paymentId =
            payment.Id;

        response.purchaseRequestId =
            cancellationResult.purchaseRequestId;

        return response;
    }


    /**
     * Keeps the required client-facing error
     * message consistent.
     */
    private static void throwCancellationError() {

        throw new AuraHandledException(
            ERROR_MESSAGE
        );
    }


    /**
     * Response returned to the LWC.
     */
    public class RescindResponse {

        @AuraEnabled
        public Boolean success {
            get;
            set;
        }

        @AuraEnabled
        public String message {
            get;
            set;
        }

        @AuraEnabled
        public Id paymentId {
            get;
            set;
        }

        @AuraEnabled
        public String purchaseRequestId {
            get;
            set;
        }
    }
}