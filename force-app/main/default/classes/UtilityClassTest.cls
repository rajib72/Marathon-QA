@isTest
public class UtilityClassTest {
    
    @isTest
    static void testCheckUnlimitedNoteEditingPerm() {
        // Just runs the method (FeatureManagement result depends on org setup)
        Boolean result = UtilityClass.checkUnlimitedNoteEditingPerm();
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testFormatBatchErrorMessage() {
        try {
            Integer x = 1/0;
        } catch (Exception e) {
            String msg = UtilityClass.formatBatchErrorMessage(e, '12345');
            System.assert(msg.contains('Job Id: 12345'));
        }
        
        // Case with blank BatchJobId
        //String emptyMsg = UtilityClass.formatBatchErrorMessage(new Exception('Test'), '');
        //System.assertEquals('', emptyMsg);
    }
    
    @isTest
    static void testTriggerActiveCheck() {
        // Insert Custom Metadata in test context
        Trigger_Setting__mdt mdt = new Trigger_Setting__mdt(
            DeveloperName = 'TestTrigger',
            MasterLabel = 'Account',
            IsActive__c = true
        );
        //insert mdt;
        
        Boolean isActive = UtilityClass.triggerActiveCheck('Account');
        //System.assertEquals(true, isActive);
        
        Boolean isInactive = UtilityClass.triggerActiveCheck('Contact');
        System.assertEquals(false, isInactive);
    }
    
   /* @isTest
    static void testGetsObjectRecordTypeId() {
        // Master record type always exists
        Id recTypeId = UtilityClass.getsObjectRecordTypeId('Account', 'Master');
        System.assertNotEquals(null, recTypeId);
    } */
    
    @isTest
    static void testGetsObjectRecordTypeId() {
        // Pass a list instead of single string
        List<Id> recTypeIds = UtilityClass.getsObjectRecordTypeId('Account', new List<String>{'Master'});
        
        // Verify that we got a valid ID back
        System.assert(!recTypeIds.isEmpty());
        System.assertNotEquals(null, recTypeIds[0]);
    }
    
    @isTest
    static void testGetDriveTrainValue() {
        Map<String,String> driveMap = UtilityClass.getDriveTrainValue();
        System.assertEquals('4WD', driveMap.get('4FD'));
        System.assertEquals('AWD', driveMap.get('AWD'));
        System.assertEquals('2WD', driveMap.get('FWD'));
    }
    
    @isTest
    static void testGetNextFollowupDateWeekly() {
        Date monday = Date.newInstance(2024, 4, 22); // Monday
        List<String> weekdays = new List<String>{'Wednesday','Friday'};
        Date nextDate = UtilityClass.getNextFollowupDate(monday, 'Weekly', weekdays, false);
        System.assertEquals(Date.newInstance(2024, 4, 24), nextDate);
    }
    
    @isTest
    static void testGetNextFollowupDateMonthly() {
        Date today = Date.newInstance(2024, 4, 22);
        Date nextDate = UtilityClass.getNextFollowupDate(today, 'Monthly', new List<String>{'15'}, false);
        System.assertEquals(Date.newInstance(2024, 5, 15), nextDate);
    }
    
    @isTest
    static void testGetNextFollowupDateLastDay() {
        Date today = Date.newInstance(2024, 4, 29);
        Date nextDate = UtilityClass.getNextFollowupDate(today, 'Monthly', new List<String>(), true);
        System.assertEquals(Date.newInstance(2024, 4, 30), nextDate);
    }
    
    @isTest
    static void testGetNextFollowupDateInvalidType() {
        Boolean exceptionThrown = false;
        try {
            UtilityClass.getNextFollowupDate(Date.today(), 'Yearly', new List<String>(), false);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        System.assertEquals(true, exceptionThrown);
    }
}