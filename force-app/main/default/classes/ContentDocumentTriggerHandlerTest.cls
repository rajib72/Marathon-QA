@isTest
private class ContentDocumentTriggerHandlerTest {
    
    @isTest static void testContentDocumentTrigger() {
        
        User nonAdminUser = TestDataFactory.createStandardUser(true);

        System.runAs(nonAdminUser) {
            ContentVersion testContentVersion = new ContentVersion(
                Title = 'Test Note',
                PathOnClient = 'TestPath.SNOTE',
                VersionData = Blob.valueOf('Test Content')
            );
            insert testContentVersion;
            ContentVersion notes = [Select Id, ContentDocumentId from ContentVersion WHERE Id = :testContentVersion.Id];
            ContentDocument noteDocument = [Select Id from ContentDocument Where Id = :notes.ContentDocumentId LIMIT 1];	
            Test.setCreatedDate(noteDocument.Id,Date.today().addDays(-2));
            Test.startTest(); 
            try{
            	update noteDocument;
                Assert.fail('Expected error');
            }catch(Exception ex){
                Assert.isNotNull(ex.getMessage(), 'Not expected thrown error.');
            }
            Test.stopTest();
        }
    }
    @isTest static void testContentDocumentBeforeDeleteTrigger() {
       
        User nonAdminUser = TestDataFactory.createStandardUser(true);

        System.runAs(nonAdminUser) {
            ContentVersion testContentVersion = new ContentVersion(
                Title = 'Test Note',
                PathOnClient = 'TestPath.SNOTE',
                VersionData = Blob.valueOf('Test Content')
            );
            insert testContentVersion;
            ContentVersion notes = [Select Id, ContentDocumentId from ContentVersion WHERE Id = :testContentVersion.Id];
            ContentDocument noteDocument = [Select Id from ContentDocument Where Id = :notes.ContentDocumentId LIMIT 1];  
            Test.setCreatedDate(noteDocument.Id, Date.today().addDays(-2));
            Test.startTest(); 
            try {
                delete noteDocument;
                Assert.fail('Expected error');
            } catch(Exception ex) {
                Assert.isNotNull(ex.getMessage(), 'Not expected thrown error.');
            }
            Test.stopTest();
        }
    }
}