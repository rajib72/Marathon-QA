public with sharing class CreateClaimAdjustmentNoteAction {

    public class Request {
        @InvocableVariable(required=true)
        public Id claimId;

        @InvocableVariable
        public String noteBody;
    }

    @InvocableMethod(label='Create Claim Adjustment Note')
    public static void createNotes(List<Request> requests) {

        List<ContentNote> notes = new List<ContentNote>();
        List<Id> claimIds = new List<Id>();

        for (Request req : requests) {
            if (req.claimId != null && !String.isBlank(req.noteBody)) {

                notes.add(new ContentNote(
                    Title = 'Adjustment Note',
                    Content = Blob.valueOf(req.noteBody)
                ));

                claimIds.add(req.claimId);
            }
        }

        if (notes.isEmpty()) {
            return;
        }

        insert notes;

        List<ContentDocumentLink> links =
            new List<ContentDocumentLink>();

        for (Integer i = 0; i < notes.size(); i++) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = notes[i].Id,
                LinkedEntityId = claimIds[i],
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        insert links;
    }
}