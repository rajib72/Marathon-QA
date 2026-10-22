/**
* @author Sujit Dengale
* @dateModified 19-06-2026
* @ModifiedBy Raj Sekhar Mukherjee
* @description Trigger on Funding Object
*/
trigger FundingTrigger on Funding__c (before insert, after insert, after update) {

    if(UtilityClass.triggerActiveCheck('Funding__c')) {

        if (Trigger.isBefore && Trigger.isInsert){

            FundingTriggerHandler.handleBeforeInsert(Trigger.new);
        }

        if (Trigger.isAfter && Trigger.isInsert){

            FundingTriggerHandler.handleAfterInsert(Trigger.new, Trigger.oldMap);

            FundingTriggerHandler.startAllocationProcess(Trigger.new, Trigger.oldMap);
        }

        if (Trigger.isAfter && Trigger.isUpdate) {

            FundingDSIContractTriggerHandler.updateContractFundedAmount(Trigger.new,Trigger.old);

            FundingTriggerHandler.startAllocationProcess(Trigger.new, Trigger.oldMap);
        }
    }
}