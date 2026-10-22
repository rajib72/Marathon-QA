/**
* @author Saurabh Rawat
* @dateModified 2026-07-16
* @ModifiedBy Raj Sekhar Mukherjee
* @description Trigger on ROP__c
*/

trigger ROPTrigger on ROP__c (
    before insert,
    after insert,
    after update
) {
    
    if(UtilityClass.triggerActiveCheck('ROP__c')) {
        
        if(Trigger.isBefore && Trigger.isInsert){
            ROPTriggerHandler.handleBeforeInsert(
                Trigger.new
            );
        }
        
        if(Trigger.isAfter && Trigger.isInsert){
            
            ROPTriggerHandler.handleAfterInsert(
                Trigger.new
            );
            
            ROPTriggerHandler.startAllocationProcess(
                Trigger.new,
                null
            );
        }
        
        if(Trigger.isAfter && Trigger.isUpdate){
            
            ROPTriggerHandler.startAllocationProcess(
                Trigger.new,
                Trigger.oldMap
            );
        }
    }
}