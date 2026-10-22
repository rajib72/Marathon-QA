/**
* @author Hitarth Trivedi
* @dateModified 09-09-2024
* @description Trigger on Payment__c
*/
trigger PaymentTrigger on Payment__c (
    before insert,
    before update,
    after insert,
    after update
) {

    if (UtilityClass.triggerActiveCheck('Payment__c')) {

        /*
         * -------------------------------------------------
         * BEFORE INSERT / UPDATE
         * Set Payment Status based on card dates
         * -------------------------------------------------
         */
        if (Trigger.isBefore) {

            PaymentTriggerHandler.setPaymentStatus(
                Trigger.new
            );
        }


        /*
         * -------------------------------------------------
         * AFTER INSERT
         * Link Payment to Claim Items
         * -------------------------------------------------
         */
        if (
            Trigger.isAfter &&
            Trigger.isInsert
        ) {

            PaymentTriggerHandler.handleAfterInsert(
                Trigger.new,
                Trigger.oldMap
            );
        }


        /*
         * -------------------------------------------------
         * AFTER UPDATE
         * Handle cancelled Payments
         * -------------------------------------------------
         */
        if (
            Trigger.isAfter &&
            Trigger.isUpdate
        ) {

            PaymentTriggerHandler.handleAfterUpdate(
                Trigger.oldMap,
                Trigger.new
            );
        }
    }
}