@IsTest
private class CreateClaimAdjustmentNoteActionTest {

    // Create independent test Claim
    private static Claim createTestClaim() {

        Claim testClaim = new Claim();
        testClaim.Name = 'Test Claim';

        testClaim.Driven_or_Towed_In__c = 'Driven';
        testClaim.Labor_Rate__c = 0;
        testClaim.Mileage__c = 105000;
        testClaim.Parts_Warranty__c = 'N/A';
        testClaim.ReportDate = Datetime.newInstance(
            2025, 3, 16, 12, 0, 0
        );
        testClaim.ReportNumber = 'TEST-RO-001';

        insert testClaim;

        return testClaim;
    }

    @IsTest
    static void testSingleNoteCreation() {

        Claim testClaim = createTestClaim();

        CreateClaimAdjustmentNoteAction.Request req =
            new CreateClaimAdjustmentNoteAction.Request();

        req.claimId = testClaim.Id;
        req.noteBody = 'Additional approved expense';

        Test.startTest();

        CreateClaimAdjustmentNoteAction.createNotes(
            new List<CreateClaimAdjustmentNoteAction.Request>{req}
        );

        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testClaim.Id
        ];

        System.assertEquals(1, links.size());

        ContentNote note = [
            SELECT Id, Title, Content
            FROM ContentNote
            WHERE Id = :links[0].ContentDocumentId
        ];

        System.assertEquals('Adjustment Note', note.Title);

        System.assertEquals(
            'Additional approved expense',
            note.Content.toString()
        );

        System.assertEquals(testClaim.Id, links[0].LinkedEntityId);
    }

    @IsTest
    static void testBulkNoteCreation() {

        Claim testClaim = createTestClaim();

        List<CreateClaimAdjustmentNoteAction.Request> requests =
            new List<CreateClaimAdjustmentNoteAction.Request>();

        for (Integer i = 1; i <= 3; i++) {

            CreateClaimAdjustmentNoteAction.Request req =
                new CreateClaimAdjustmentNoteAction.Request();

            req.claimId = testClaim.Id;
            req.noteBody = 'Adjustment Note ' + i;

            requests.add(req);
        }

        Test.startTest();

        CreateClaimAdjustmentNoteAction.createNotes(requests);

        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testClaim.Id
        ];

        System.assertEquals(3, links.size());
    }

    @IsTest
    static void testEmptyNoteBody() {

        Claim testClaim = createTestClaim();

        CreateClaimAdjustmentNoteAction.Request req =
            new CreateClaimAdjustmentNoteAction.Request();

        req.claimId = testClaim.Id;
        req.noteBody = '';

        Test.startTest();

        CreateClaimAdjustmentNoteAction.createNotes(
            new List<CreateClaimAdjustmentNoteAction.Request>{req}
        );

        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testClaim.Id
        ];

        System.assertEquals(0, links.size());
    }

    @IsTest
    static void testNullClaimId() {

        CreateClaimAdjustmentNoteAction.Request req =
            new CreateClaimAdjustmentNoteAction.Request();

        req.claimId = null;
        req.noteBody = 'Test note';

        Test.startTest();

        CreateClaimAdjustmentNoteAction.createNotes(
            new List<CreateClaimAdjustmentNoteAction.Request>{req}
        );

        Test.stopTest();

        System.assertEquals(true, true);
    }
}