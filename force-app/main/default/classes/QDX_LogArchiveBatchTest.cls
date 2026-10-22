@isTest
public with sharing class QDX_LogArchiveBatchTest {
    @TestSetup
    static void makeData(){
        QDX_LogSetting__c settings = new QDX_LogSetting__c();
        settings.Name = 'TestSettings';
        settings.Logging_Level__c = 'FINE';
        settings.Days_To_Expire__c = -5;
        insert settings;
        
        QDX_Log__c log = new QDX_Log__c();
        log.QDX_Message__c ='Index out of bound expection';
        insert log;   
    }
   
    @isTest
    static void logBatchError() 
	{
        QDX_LogSetting__c logsettings = [
            SELECT id,
                   Name 
            FROM QDX_LogSetting__c 
            WHERE Name =: 'TestSettings'
            ];
        Test.startTest();
        QDX_LogArchiveScheduler logarchive = new QDX_LogArchiveScheduler();
        String sch = '0 0 23 * * ?';
		system.schedule('Test status Check', sch, logarchive );
		Test.stopTest();
        System.assertEquals('TestSettings', logsettings.Name, 'Failed to process stackTrace');
    }

}