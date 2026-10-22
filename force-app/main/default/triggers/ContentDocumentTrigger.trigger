/**
* @author Saurabh Rawat
* @dateModified 2024-04-05
* @description Trigger on Content Document
*/
trigger ContentDocumentTrigger on ContentDocument (before update, before delete){

    if(UtilityClass.triggerActiveCheck('ContentDocument')) {
        if (Trigger.isBefore && Trigger.isUpdate){
            ContentDocumentTriggerHandler.handleBeforeUpdate(Trigger.new);
        }
        if (Trigger.isBefore && Trigger.isDelete){
            ContentDocumentTriggerHandler.handleBeforeDelete(Trigger.old);
        }
    }
}