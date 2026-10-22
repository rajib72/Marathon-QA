@isTest
public class ClassGuideBuilderControllerTest {    
    @isTest
    public static void testGetMakes(){
        List<Ethnicity_Lookup__mdt> makesList = [Select Label from Ethnicity_Lookup__mdt where Ethnicity__c = 'American'];
        Test.startTest();
        List<sObject> data = ClassGuideBuilderController.getMakes('American');
        Test.stopTest();
        System.assertEquals(data.size(), makesList.size() , 'Makes returned successfully');
    }
    
    @isTest
    public static void testQueryReturn(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        Test.startTest();
        List<sObject> data = ClassGuideBuilderController.getRecords('American', 'CHEVROLET');
        Test.stopTest();
        System.assertEquals(data.size(), 1 , 'Vin details returned');
    }
    
    @isTest
    public static void testVinClassUpdateMethod(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        Test.startTest();
        VIN_Detail__c vinDetailRec1 = TestDataFactory.createVinDetail(false);
        vinDetailRec1.VIN_SIGNI_PATTRN_MASK__c = '***********';
        insert vinDetailRec1;
        delete [SELECT Id from VIN_Class__c where Squish_VIN__c = :vinDetailRec1.Id];
        String result = ClassGuideBuilderController.updateVinClassRecords('ABC', new List<VIN_Detail__c>{vinDetailRec}, 'American','', '' ,'RR', '', '', '', '', '', '', '', '', '','','');
        String resultNoRecToUpdate = ClassGuideBuilderController.updateVinClassRecords('ABC', new List<VIN_Detail__c>{vinDetailRec1}, 'Asian','', '' ,'RR', 'Trims', '', '', '', '', '', '', '', '','','');
        
        Test.stopTest();
        System.assertEquals(result, System.Label.Class_Guide_Builder_Success_Message , 'Vin Class updated');
        System.assertEquals(resultNoRecToUpdate, System.Label.Class_Guide_Builder_Success_Message , 'No records to update');
        
    }
    
    @isTest
    public static void testVinClassUpsertErrorMethod(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        Test.startTest();
        VIN_Detail__c vinDetailRec1 = TestDataFactory.createVinDetail(false);
        vinDetailRec1.VIN_SIGNI_PATTRN_MASK__c = '***********';
        insert vinDetailRec1;
        delete [SELECT Id from VIN_Class__c where Squish_VIN__c = :vinDetailRec1.Id];
        String result = ClassGuideBuilderController.updateVinClassRecords('ABC', new List<VIN_Detail__c>{vinDetailRec}, 'American','', '' ,'RR', '', '', '', '', '', '', '', '', '','','');
        
        try{
            String resultNoRecToUpdate = ClassGuideBuilderController.updateVinClassRecords('ABC', new List<VIN_Detail__c>{vinDetailRec1}, 'Asian','', '' ,'RRRRRRR', 'Trims', '', '', '', '', '', '', '', '','','');
        }
        catch(Exception e){
        	System.assert(e.getMessage().contains('Script-thrown exception'));   
        }
        Test.stopTest();
        
    }
    
    @isTest
    public static void testVinClassInsertMethod(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        Test.startTest();
        String result = ClassGuideBuilderController.updateVinClassRecords(UtilityClass.NEW_CLASS_GUIDE, new List<VIN_Detail__c>{vinDetailRec}, 'American','All models', 'All makes' ,'RR', 'Trims', '', '', '', '', '', '', '', '','Partner Test','Class Guide Name test');
        
        Test.stopTest();
        System.assertEquals(result, System.Label.Class_Guide_Builder_Success_Message_Insert , 'Vin Class Inserted');
    }
    
    @isTest
    public static void testVinClassInsertMethodError(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        String result;
        Test.startTest();
        try{
        result = ClassGuideBuilderController.updateVinClassRecords(UtilityClass.NEW_CLASS_GUIDE, new List<VIN_Detail__c>{vinDetailRec}, 'American','All models', 'All makes' ,'RRRRRRR', 'Trims', '', '', '', '', '', '', '', '','Partner Test','Class Guide Name Test');        
        }
        catch(Exception e){
        System.assert(e.getMessage().contains('Script-thrown exception'));   
        }
        Test.stopTest();        
    }
    
    @isTest
    public static void testVinClassInsertMethodErrorNoRateClass(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        String result;
        Test.startTest();
        try{
        result = ClassGuideBuilderController.updateVinClassRecords(UtilityClass.NEW_CLASS_GUIDE, new List<VIN_Detail__c>{vinDetailRec}, 'American','All models', 'All makes' ,'', 'Trims', '', '', '', '', '', '', '', '','Partner Test','Class Guide Name Test');        
        }
        catch(Exception e){
        System.assert(e.getMessage().contains('Script-thrown exception'));   
        }
        Test.stopTest();        
    }
    
    @isTest
    public static void testVinClassNoRecordsToInsert(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        Test.startTest();
        String result = ClassGuideBuilderController.updateVinClassRecords(UtilityClass.NEW_CLASS_GUIDE, new List<VIN_Detail__c>(), 'American','All models', 'All makes' ,'RR', 'Trims', '', '', '', '', '', '', '', '','','');
        Test.stopTest();
        System.assertEquals(result, System.Label.No_records_to_update_error_message , 'No Vin Class to insert');
        
    }
    
    @isTest
    public static void testGetClassGuideName(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        Test.startTest();
        List<String> classGuideNames = ClassGuideBuilderController.getClassBuilderNames();
        Test.stopTest();
        System.assertEquals(classGuideNames.contains(vinClassRec.Class_Guide_Name__c), TRUE , 'Class Guide Names returned successfully');
    }
    
    @isTest
    public static void testVinClassUpdateMethodError(){
        VIN_Detail__c vinDetailRec = TestDataFactory.createVinDetail(true);
        VIN_Class__c vinClassRec = TestDataFactory.createVinClass(true, vinDetailRec.Id);
        Test.startTest();
        try{
            ClassGuideBuilderController.updateVinClassRecords('ABC', new List<VIN_Detail__c>{vinDetailRec}, 'American','All models', 'All makes', 'RRRRRR', 'Trims', '', '', '', '', '', '', '', '','','');
        }
        catch(Exception e){
            System.assert(e.getMessage().contains('Script-thrown exception'));
        }
        Test.stopTest();
    }
    

}