/**
* @author Saurabh Rawat
* @dateModified 2024-04-17
* @description Trigger Handler on Content Document Link
*/
trigger ContentDocumentLinkTrigger on ContentDocumentLink (before delete) {

    if(UtilityClass.triggerActiveCheck('ContentDocumentLink')) {
        if (Trigger.isBefore && Trigger.isDelete) {
            ContentDocumentLinkTriggerHandler.handleBeforeDelete(Trigger.old);
        }
    }
}