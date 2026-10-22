/**
 * @author Sujit Dengale
 * @dateModified 30-07-2026
 * @Modified By : Raj Sekhar Mukherjee
 * @description Trigger on Contract-InsurancePolicy
 */
trigger ContractTrigger on InsurancePolicy (
    before insert,
    before update,
    after insert,
    after update
) {
    if (UtilityClass.triggerActiveCheck('InsurancePolicy')) {

        if (Trigger.isBefore && Trigger.isInsert) {
            ContractTriggerHandler.handleBeforeInsert(
                Trigger.new
            );
        }

        if (Trigger.isBefore && Trigger.isUpdate) {
            ContractTriggerHandler.handleBeforeUpdate(
                Trigger.new,
                Trigger.oldMap
            );
        }

        if (Trigger.isAfter && Trigger.isInsert) {
            ContractTriggerHandler.handleAfterInsert(
                Trigger.new,
                Trigger.oldMap
            );
        }

        /*if (Trigger.isAfter && Trigger.isUpdate) {
            ContractTriggerHandler.handleAfterUpdate(
                Trigger.new,
                Trigger.oldMap
            );
        }*/
    }
}