/**
* @author Saurabh Rawat
* @dateModified 2024-04-17
* @description Trigger Handler on Content Document
*/
public class ContentDocumentTriggerHandler {    
    /**
     * @param : newContentDocuments: ContentDocument:List
     * @description: Handler method : execution : before Update
     * */
    public static void handleBeforeUpdate(List<ContentDocument> newContentDocuments){
        restrictNonAdminNotesEditAccess(newContentDocuments);
    }
    
    /**
     * @param : newContentDocuments: ContentDocument:List
     * @description: Handler method : execution : before delete
     * */
    public static void handleBeforeDelete(List<ContentDocument> newContentDocuments){
        restrictNonAdminNotesEditAccess(newContentDocuments);
    }
    /**
     * @param : newContentDocuments: ContentDocument:List
     * @description: Ticket : MRT-28, filtering ContentNote and restricting access to non admin users/without Unlimited_Notes_Editing PM to lock records
     * */
    public static void restrictNonAdminNotesEditAccess(List<ContentDocument> newContentDocuments){
        for (ContentDocument contentDocument : newContentDocuments){
            if (contentDocument.FileType == UtilityClass.CONTENT_DOCUMENT_NOTES && !UtilityClass.checkUnlimitedNoteEditingPerm()){
                if (DateTime.now().addHours(-24) > contentDocument.CreatedDate){
                    contentDocument.addError(UtilityClass.NOTES_NOT_EDITABLE_ERR_MSG);
                }	
            }
        }
    }
}