/**
* @author Saurabh Rawat
* @dateModified 2024-04-17
* @description Trigger Handler on Content Document Link
*/
public class ContentDocumentLinkTriggerHandler {    
    /**
* @param : oldContentDocumentLinks: ContentDocumentLink:List
* @description: Handler method : execution : before delete
* */
    public static void handleBeforeDelete(List<ContentDocumentLink> oldContentDocumentLinks) {
        restrictNonAdminNotesEditAccess(oldContentDocumentLinks);
    }
    
    /**
* @param : oldContentDocumentLinks, contentDocumentMap : ContentDocumentLink:List
* @description: Ticket : MRT-28, filtering ContentNote and restricting access to non admin users/without Unlimited_Notes_Editing PM to not remove the records
* */
    public static void restrictNonAdminNotesEditAccess(List<ContentDocumentLink> oldContentDocumentLinks) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink cdl : oldContentDocumentLinks) {
            if(String.isNotBlank(cdl.ContentDocumentId)){
             	documentIds.add(cdl.ContentDocumentId);   
            }
        }        
        Map<Id, ContentDocument> contentDocumentMap = new Map<Id,ContentDocument>();
        if(documentIds.size() > 0){
        	contentDocumentMap = new Map<Id, ContentDocument>([SELECT Id, FileType, CreatedDate FROM ContentDocument WHERE Id IN :documentIds]);    
        }
        

        for (ContentDocumentLink cdl : oldContentDocumentLinks) {
            ContentDocument relatedDocument = contentDocumentMap.containsKey(cdl.ContentDocumentId)?contentDocumentMap.get(cdl.ContentDocumentId):null;
            if (relatedDocument != null && relatedDocument.FileType == UtilityClass.CONTENT_DOCUMENT_NOTES && !UtilityClass.checkUnlimitedNoteEditingPerm()) {
                if (DateTime.now().addHours(-24) > relatedDocument.CreatedDate) {
                    cdl.addError(UtilityClass.NOTES_NOT_DELETABLE_ERR_MSG);
                }
            }
        }
    }
}