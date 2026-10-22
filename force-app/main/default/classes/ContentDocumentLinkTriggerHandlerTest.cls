@IsTest
private class ContentDocumentLinkTriggerHandlerTest {
    
    @isTest 
    private static void testContentDocumentBeforeDeleteTrigger() {
        
        User nonAdminUser = TestDataFactory.createStandardUser(false);
        insert nonAdminUser;
        System.runAs(nonAdminUser) {
            ContentVersion testContentVersion = new ContentVersion(
                Title = 'Test Note',
                PathOnClient = 'TestPath.SNOTE',
                VersionData = Blob.valueOf('Test Content')
            );
            insert testContentVersion;
            
            ContentVersion notes = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id];
            ContentDocument notesDocument = [SELECT Id, CreatedDate FROM ContentDocument WHERE Id = :notes.ContentDocumentId];
			ContentDocumentLink cdl = [Select Id from ContentDocumentLink Where ContentDocumentId = :notes.ContentDocumentId];
            Test.setCreatedDate(notesDocument.Id, DateTime.now().addDays(-2));
            Test.startTest(); 
            try {
                delete cdl;
                Assert.fail('Expected error');
            } catch(Exception ex) {
                Assert.isNotNull(ex.getMessage(), 'Not expected thrown error.');
            }
            Test.stopTest();
        }
    }
}