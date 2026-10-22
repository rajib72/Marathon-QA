/**
* @author Waidehee Kuradkar
* @dateModified 2025-05-19
* @description Test Class for VINDetailTriggerHandler
*/
@isTest
public class VINDetailTriggerHandlerTest {
    // Create new Vindetail records and checks whether correct number of vinClass records are automatically created.
    @isTest
    public static void createVinClassesTest(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        VIN_Detail__c vinDetailRecToInsert = TestDataFactory.createVinDetail(false);
        Test.startTest();
        vinDetailRecToInsert.VIN_SIGNI_PATTRN_MASK__c = 'AAAAAAAAAA**';
        insert vinDetailRecToInsert;   
        
        List<VIN_Class__c> vinClassRecCreated = [SELECT Id from VIN_Class__c where Squish_VIN__c = :vinDetailRecToInsert.Id];
        System.assertEquals(vinClassRecCreated.size(), 1 , 'Successfully created VinClass records');
 
        update vinDetailRecToInsert;     
        Test.stopTest();
    }
    
    

}