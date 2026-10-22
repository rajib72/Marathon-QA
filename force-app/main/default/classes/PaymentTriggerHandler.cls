/**
* @author: Hitarth Trivedi
* @dateModified: 09-09-2024
* @description:
* Handles Payment__c trigger processing.
*
* Responsibilities:
* 1. Set Payment Status based on Credit Card dates.
* 2. Link newly inserted Payments to Claim Items.
* 3. Process Claim Items when a Payment becomes Cancelled.
*/
public class PaymentTriggerHandler {


    /**
     * ---------------------------------------------------------
     * Set Payment Status
     * ---------------------------------------------------------
     *
     * Business Rules:
     *
     * 1. Cancelled
     *    Credit_Card_Cancel_Date__c is populated.
     *
     * 2. Complete
     *    Credit_Card_Date_Ran__c is populated and
     *    Credit_Card_Cancel_Date__c is not populated.
     *
     * 3. Pending
     *    Both Credit_Card_Cancel_Date__c and
     *    Credit_Card_Date_Ran__c are blank.
     *
     * Cancelled takes priority if both dates are populated.
     */
    public static void setPaymentStatus(
        List<Payment__c> payments
    ) {

        if (
            payments == null ||
            payments.isEmpty()
        ) {
            return;
        }


        for (Payment__c payment : payments) {

            /*
             * -------------------------------------------------
             * CANCELLED
             * -------------------------------------------------
             */
            if (
                payment.Credit_Card_Cancel_Date__c != null
            ) {

                payment.Status__c = 'Cancelled';
            }


            /*
             * -------------------------------------------------
             * COMPLETE
             * -------------------------------------------------
             */
           else if (
    payment.Credit_Card_Date_Ran__c != null ||
    payment.CheckDate__c != null
) {

    payment.Status__c = 'Complete';
}


            /*
             * -------------------------------------------------
             * PENDING
             * -------------------------------------------------
             */
            else {

                payment.Status__c = 'Pending';
            }
        }
    }


    /**
     * ---------------------------------------------------------
     * AFTER INSERT
     * ---------------------------------------------------------
     *
     * Links newly inserted Payments to their related Claim Items.
     */
    public static void handleAfterInsert(
        List<Payment__c> newPayments,
        Map<Id, Payment__c> oldPaymentsMap
    ) {

        linkPaymentsToClaim(newPayments);
    }


    /**
     * ---------------------------------------------------------
     * AFTER UPDATE
     * ---------------------------------------------------------
     *
     * Detects Payments whose status changed to Cancelled.
     *
     * For those Payments:
     *
     * 1. Related Claim Items are changed to Cancelled.
     * 2. Original Claim Items are cloned.
     * 3. Cloned Claim Items are set to Requested.
     */
    public static void handleAfterUpdate(
        Map<Id, Payment__c> oldPaymentsMap,
        List<Payment__c> newPayments
    ) {

        Set<Id> cancelledPaymentIds =
            new Set<Id>();


        if (
            oldPaymentsMap == null ||
            newPayments == null ||
            newPayments.isEmpty()
        ) {
            return;
        }


        for (Payment__c payment : newPayments) {

            Payment__c oldPayment =
                oldPaymentsMap.get(payment.Id);


            /*
             * -------------------------------------------------
             * Detect transition to Cancelled.
             * -------------------------------------------------
             */
            if (
                oldPayment != null &&
                oldPayment.Status__c != 'Cancelled' &&
                payment.Status__c == 'Cancelled'
            ) {

                cancelledPaymentIds.add(
                    payment.Id
                );


                System.debug(
                    LoggingLevel.INFO,
                    'Payment became Cancelled: ' +
                    payment.Id
                );
            }
        }


        /*
         * -------------------------------------------------
         * Process related Claim Items.
         * -------------------------------------------------
         */
        if (
            !cancelledPaymentIds.isEmpty()
        ) {

            PaymentClaimItemUtility.handleCancelledPayments(
                cancelledPaymentIds
            );
        }
    }


    /**
     * ---------------------------------------------------------
     * Link Payments to Claim Items
     * ---------------------------------------------------------
     *
     * Links Payments to Claim Items by matching:
     *
     * - Claim Number
     * - VIN
     * - Payee Name / Account
     *
     * Existing implementation retained.
     */
    public static void linkPaymentsToClaim(
        List<Payment__c> newPayments
    ) {

        /*
         * Map Payment Id -> Claim Items
         */
        Map<Id, List<ClaimItem>> paymentClaimItemMap =
            new Map<Id, List<ClaimItem>>();


        /*
         * Unique Claim Numbers.
         */
        Set<String> claimNames =
            new Set<String>();


        /*
         * Payments that contain the required
         * matching information.
         */
        List<Payment__c> importedPayments =
            new List<Payment__c>();


        /*
         * -------------------------------------------------
         * Collect Claim Numbers from Payments.
         * -------------------------------------------------
         */
        for (
            Payment__c payment :
            newPayments
        ) {

            if (
                payment.Claim_Number__c != null &&
                payment.VIN__c != null &&
                payment.Account__c != null
            ) {

                claimNames.add(
                    payment.Claim_Number__c
                );

                importedPayments.add(
                    payment
                );
            }
        }


        /*
         * -------------------------------------------------
         * Query Claim Items.
         * -------------------------------------------------
         */
        List<ClaimItem> claimItems =
            new List<ClaimItem>();


        if (
            !claimNames.isEmpty()
        ) {

            claimItems = [
                SELECT
                    Id,
                    Name,
                    Claim.Name,
                    Claim.PolicyNumber.VIN__c,
                    Payee_Name__c
                FROM ClaimItem
                WHERE Claim.Name IN :claimNames
            ];
        }


        /*
         * -------------------------------------------------
         * Match Payments to Claim Items.
         * -------------------------------------------------
         */
        for (
            Payment__c payment :
            importedPayments
        ) {

            List<ClaimItem> paymentClaimItems =
                new List<ClaimItem>();


            for (
                ClaimItem claimItem :
                claimItems
            ) {

                if (
                    claimItem.Claim != null &&
                    claimItem.Claim.Name != null &&
                    payment.Claim_Number__c != null &&
                    claimItem.Claim.PolicyNumber != null &&
                    claimItem.Claim.PolicyNumber.VIN__c != null &&
                    payment.VIN__c != null &&
                    claimItem.Payee_Name__c != null &&
                    payment.Account__c != null &&
                    claimItem.Claim.Name ==
                        payment.Claim_Number__c &&
                    claimItem.Claim.PolicyNumber.VIN__c ==
                        payment.VIN__c &&
                    claimItem.Payee_Name__c ==
                        payment.Account__c
                ) {

                    paymentClaimItems.add(
                        claimItem
                    );
                }
            }


            /*
             * -------------------------------------------------
             * Matching Claim Items found.
             * -------------------------------------------------
             */
            if (
                !paymentClaimItems.isEmpty()
            ) {

                paymentClaimItemMap.put(
                    payment.Id,
                    paymentClaimItems
                );
            }


            /*
             * -------------------------------------------------
             * No Claim Items found.
             * -------------------------------------------------
             */
            else {

                QDX_Log.error(
                    'No ClaimItem found related to Payment Number: ' +
                    payment.Name
                );

                QDX_Log.publish();


                payment.addError(
                    'No ClaimItem found related to Payment Number: ' +
                    payment.Name
                );
            }
        }


        /*
         * -------------------------------------------------
         * Link Payments to Claim Items.
         * -------------------------------------------------
         */
        PaymentUtility.linkPaymentsToClaimItems(
            paymentClaimItemMap
        );
    }
}