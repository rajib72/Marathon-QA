@isTest
public class CloneRequestReportTest {
    static User testUser;

    @testSetup
    static void setupTestData() {
        // Create a user with a required profile
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'pentaho@example.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
        
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'System_Administrator_Only'];
        
        // Create a PermissionSetAssignment
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = ps.Id
        );
        
        // Insert the PermissionSetAssignment
        insert psa;
}
    @isTest
    static void WeeklyTestMethod(){
        User userRetrived = [SELECT Id FROM User WHERE Username = 'pentaho@example.com' LIMIT 1];
        System.runAs(userRetrived) {
            List<String> recordIdList = new List<String> ();
            List<CloneRequestReport.RecordWrapper> recordWrapperList = new List<CloneRequestReport.RecordWrapper> ();
            CloneRequestReport.RecordWrapper recordWrapperObj = new CloneRequestReport.RecordWrapper();
            
            Report_Request__c report = TestDataFactory.createReportRequest(true);
            report.Status__c ='Completed';
            report.Frequency__c ='Weekly';
            report.Weekly_Recurrence__c = 'Monday';
            recordIdList.add(report.Id);
            recordWrapperObj.recordIdListApex = recordIdList;
            recordWrapperList.add(recordWrapperObj);
            Test.startTest();
            update report;
            CloneRequestReport.createClone(recordWrapperList);
            Test.stopTest();
        }
    }
    @isTest
    static void MonthlyTestMethod(){
        User userRetrived = [SELECT Id FROM User WHERE Username = 'pentaho@example.com' LIMIT 1];
        System.runAs(userRetrived) {
            List<String> recordIdList = new List<String> ();
            List<CloneRequestReport.RecordWrapper> recordWrapperList = new List<CloneRequestReport.RecordWrapper> ();
            CloneRequestReport.RecordWrapper recordWrapperObj = new CloneRequestReport.RecordWrapper();
            
            Report_Request__c report = TestDataFactory.createReportRequest(true);
            report.Status__c ='Completed';
            report.Frequency__c ='Monthly';
            report.Monthly_Recurrence__c = '1';
            recordIdList.add(report.Id);
            recordWrapperObj.recordIdListApex = recordIdList;
            recordWrapperList.add(recordWrapperObj);
            Test.startTest();
            update report;
            CloneRequestReport.createClone(recordWrapperList);
            Test.stopTest();
        }
    }
    @isTest
    static void MonthlyTestMethod1(){
        User userRetrived = [SELECT Id FROM User WHERE Username = 'pentaho@example.com' LIMIT 1];
        System.runAs(userRetrived) {
            List<String> recordIdList = new List<String> ();
            List<CloneRequestReport.RecordWrapper> recordWrapperList = new List<CloneRequestReport.RecordWrapper> ();
            CloneRequestReport.RecordWrapper recordWrapperObj = new CloneRequestReport.RecordWrapper();
            
            Report_Request__c report = TestDataFactory.createReportRequest(true);
            report.Status__c ='Completed';
            report.Frequency__c ='Monthly';
            report.Monthly_Recurrence__c = 'Last';
            recordIdList.add(report.Id);
            recordWrapperObj.recordIdListApex = recordIdList;
            recordWrapperList.add(recordWrapperObj);
            Test.startTest();
            update report;
            CloneRequestReport.createClone(recordWrapperList);
            Test.stopTest();
        }
    }
    
}