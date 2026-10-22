/**
* @author: Saurabh Rawat
* @dateModified: 2024-07-16
* @description: This Trigger manages the after actions on Claim Items
*/
trigger ClaimItemTrigger on ClaimItem (
    before update,
    after update,
    before insert,
    after insert
) {
    if(UtilityClass.triggerActiveCheck('ClaimItem')) {
        
        if(Trigger.isBefore && Trigger.isInsert){
            ClaimItemTriggerHandler.handleBeforeInsert(
                Trigger.new
            );
        }
        
        if(Trigger.isBefore && Trigger.isUpdate){
            ClaimItemTriggerHandler.handleBeforeUpdate(
                Trigger.oldMap,
                Trigger.new
            );
        }
        
        if(Trigger.isAfter && Trigger.isUpdate){
            
            /*
* Existing Claim Item business logic.
*/
            ClaimItemTriggerHandler.handleAfterUpdate(
                Trigger.oldMap,
                Trigger.new
            );
            
            /*
* Marathon Connect notification logic.
*
* Kept separate so notification functionality does
* not become coupled with the existing business handler.
*/
            ClaimItemNotificationHandler.handleAfterUpdate(
                Trigger.oldMap,
                Trigger.new
            );
        }
        
        if(Trigger.isAfter && Trigger.isInsert){
            ClaimItemTriggerHandler.handleAfterInsert(
                Trigger.new
            );
        }
    }
}