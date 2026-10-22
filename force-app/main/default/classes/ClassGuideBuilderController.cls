public with sharing class ClassGuideBuilderController {
    
    /*** This method is called from ClassGuideBuilder lwc component.
    @param String ethnicity, String of all selected ethnicity on UI
    @param String minYear, Selected Min Year
    @param String maxYear, Selected Max Year
    @param String makes, String of all selected makes on UI
    @param String bodyStyle, String of all selected bodyStyle on UI
    @param String models, String of all models makes on UI
    @param String trims, String of all selected trims on UI
    @param String engines, String of all selected engines on UI
    This method creates a dynamic query to find all Vin Detail records for the given inputs.
    If the returned rows are more than 50000, then Error is returned to lwc. **/
    @AuraEnabled(cacheable=true)
    public static List<sObject> getRecords(String ethnicity, String makes)
    {
        try{
            List<String> ethnicityList = ethnicity != null && ethnicity != '' ? ethnicity.split(', '): NULL;
            List<String> makesList = makes != null && makes != '' ? makes.split(', '): NULL;
            Integer countOfRecords;
            String filterQuery = '';
            String countQuery = 'SELECT count() from VIN_Detail__c where';
            String query = 'SELECT Id, MAK_NM__c, BODY_STYLE_DESC__c, MDL_DESC__c, TRIM_DESC__c, ENG_MDL_DESC__c, ENG_CLNDR_RTR_CNT__c, ENG_FUEL_DESC__c, DRV_TYP_CD__c, TRK_TNG_RAT_CD__c, VIN_SIGNI_PATTRN_MASK__c, ENG_ASP_SUP_CHGR_CD__c, ENG_ASP_TRBL_CHGR_CD__c  from VIN_Detail__c where';
            filterQuery = ethnicity != null && ethnicity != '' ? filterQuery + ' Ethnicity__c IN :ethnicityList AND' : filterQuery;
            filterQuery = makes != null && makes != '' ? filterQuery + ' MAK_NM__c IN :makesList' : filterQuery;
            query = filterQuery!= null && filterQuery !='' ? query + filterQuery : query;
            countQuery = filterQuery!= null && filterQuery !='' ? countQuery + filterQuery : countQuery;
            countOfRecords = Database.countQuery(countQuery);
            if(countOfRecords > 50000){ 
                //This will set the message on error and will be handled in catch to send the correct exception to lwc.
                AuraHandledException error = new AuraHandledException('Too many query rows: 50001');
                error.setMessage('Too many query rows: 50001');        
                throw error;
            }
            return DataBase.query(query);            
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
            if( e.getMessage() == 'Too many query rows: 50001') {
                throw new AuraHandledException('Too many query rows: 50001');
            }
            else{
                throw new AuraHandledException(System.Label.Error_Message);
            }            
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<sObject> getMakes(String ethnicity)
    {
        try{            
            String query = 'Select Label from Ethnicity_Lookup__mdt where Ethnicity__c = :ethnicity ';
            return DataBase.query(query);            
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
            if( e.getMessage() == 'Too many query rows: 50001') {
                throw new AuraHandledException('Too many query rows: 50001');
            }
            else{
                throw new AuraHandledException(System.Label.Error_Message);
            }            
        }
    }
    
    /*** This method is called from ClassGuideBuilder lwc component.
    @param String classGuideName , String of Class Guide Name on UI
    @param List<sObject> vinDetailIdString , filtered list of Vin Detail records based on user selection
    @param String rateClass, String of rate class on UI
    @param String vinPrefix, String of selected Vin Prefix on UI
    @param String valueTrims, String of selected trims on UI
    @param String valueEngines, String of selected engines on UI
    @param String valueCylinders, String of selected cylinders on UI
    @param String valueAspiration, String of selected Aspiration on UI
    @param String valueFuel, String of selected fuel on UI
    @param String valueDrive, String of selected drive on UI
    @param String valueBodyStyle, String of selected body style on UI
    @param String valueTonnage, String of selected Tonnage on UI
    This method creates a dynamic query to find all Vin Class records for the given inputs and updates Rule and Rate Class fields on Vin Class Record
    ***/
    @AuraEnabled
    public static String updateVinClassRecords(String classGuideName, List<sObject> vinDetailIdString, String ethnicity, String makes, String models, String rateClass, String vinPrefix, String valueTrims, String valueEngines, String valueCylinders, String valueAspiration, String valueFuel, String valueDrive, String valueTonnage, String valueBodyStyle, String valuePartner, String valueNewClassGuide){
        try{
            String vinDetailFieldValues = '';
            //Checks if user has selected to create New Class Guide. If yes, then creates new Class Guide record for selected VinDetail records.
            if( classGuideName == UtilityClass.NEW_CLASS_GUIDE){
                if(rateClass != null && rateClass !=''){
                    vinDetailFieldValues = createRuleFieldData(ethnicity, makes, models, valueTrims, valueEngines, valueCylinders, valueAspiration, valueFuel, valueDrive, valueTonnage, valueBodyStyle, vinPrefix);
                    return insertVinClassRecords(valueNewClassGuide, rateClass, vinDetailIdString, vinDetailFieldValues, valuePartner);
                }
                else{
                    AuraHandledException error = new AuraHandledException('No Rate Class Defined');
                    error.setMessage('No Rate Class Defined');        
                    throw error;                    
                }
            }
            else{
                vinDetailFieldValues = createRuleFieldData(ethnicity, makes, models, valueTrims, valueEngines, valueCylinders, valueAspiration, valueFuel, valueDrive, valueTonnage, valueBodyStyle, vinPrefix);
                return upsertVinClassRecords(classGuideName, rateClass, vinDetailIdString, vinDetailFieldValues);                    
            }            
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
            if( e.getMessage() == 'No Rate Class Defined'){
                throw new AuraHandledException('No Rate Class Defined');
            }
            else if( e.getMessage() == 'Too many query rows: 50001'){
                throw new AuraHandledException('Too many query rows: 50001');                             
            }
            else{
                throw new AuraHandledException(System.Label.Error_Message);   
            }
        }
        
    }
    
    /*** This method is called from updateVinClassRecords method.
    @param String classGuideName , String of Class Guide Name on UI
    @param List<sObject> vinDetailIdString , filtered list of Vin Detail records based on user selection
    @param String rateClass, String of rate class on UI
    This method creates a dynamic query to find all Vin Class records for the given inputs and updates Rule and Rate Class fields on Vin Class Record
    When user selects to update the VinClass records and associated Vin Detail records doesn't have any VinClass record for the given Vin Detail records.
    In this case, creates a new Vin Class record for the given Vin Detail records. Partner field remains same for all VinClass for a particular Class Guide Name
    ***/
    public static String upsertVinClassRecords(String classGuideName, String rateClass, List<sObject> vinDetailIdString, String vinDetailFieldValues){
        String partnerName ='';
        List<VIN_Class__c> vinClassToUpdate = new List<VIN_Class__c>();
        List<VIN_Class__c> vinClassToInsert = new List<VIN_Class__c>();
        Set<Id> vinDetailId =  new Set<Id>();
        List<sObject> vinClassRecords = new List<sObject>();                
        Map<Id, VIN_Detail__c> vinDetailMap = new Map<Id, VIN_Detail__c>();
        Map<Id, VIN_Class__c> vinClassMap = new Map<Id, VIN_Class__c>();
        
        //Retrieves all Vin Detail records from filtered data.
        for(sObject vinDetail : vinDetailIdString){
            VIN_Detail__c  vinDetailRec = (VIN_Detail__c ) vinDetail;
            vinDetailMap.put(vinDetailRec.Id, vinDetailRec);
        }
        
        
        if(!vinDetailMap.isEmpty()){  
            vinDetailId = vinDetailMap.keySet();                    
            String vinClassQuery = 'SELECT Id, Class__c, Rule__c, Squish_VIN__c, Partner__c from VIN_Class__c where Squish_VIN__c IN :vinDetailId AND Class_Guide_Name__c = :classGuideName';
            String countQuery = 'SELECT Count() from VIN_Class__c where Squish_VIN__c IN :vinDetailId AND Class_Guide_Name__c = :classGuideName';     
            if(Database.countQuery(countQuery) > 50000){
                AuraHandledException error = new AuraHandledException('Too many query rows: 50001');
                error.setMessage('Too many query rows: 50001');        
                throw error;
            }
            
            vinClassRecords = DataBase.query(vinClassQuery);                    
            if(vinClassRecords.size()>0){  
                partnerName = (String) vinClassRecords[0].get('Partner__c');
                for ( sObject vinClass : vinClassRecords){
                    if(!vinClassMap.containsKey((Id)vinClass.get('Squish_VIN__c'))){
                        vinClassMap.put((Id)vinClass.get('Squish_VIN__c'), (VIN_Class__c)vinClass);
                    }
                }
            }
            else{
                partnerName = [SELECT Partner__c from VIN_Class__c where Class_Guide_Name__c = :classGuideName LIMIT 1].Partner__c;
            }
            
            for(Id vinDetailRecId : vinDetailMap.keySet()){
                if(vinClassMap.containsKey(vinDetailRecId)){
                    VIN_Class__c vinClass = vinClassMap.get(vinDetailRecId);
                    vinClass.Class__c = rateClass;
                    vinClass.Rule__c = vinDetailFieldValues;
                    vinClassToUpdate.add(vinClass);
                }
                else{
                    VIN_Class__c vinClass = new VIN_Class__c();
                    vinClass.Class_Guide_Name__c = classGuideName;
                    vinClass.Squish_VIN__c = vinDetailRecId;
                    vinClass.Class__c = rateClass;
                    vinClass.Partner__c = partnerName;
                    vinClass.Rule__c = vinDetailFieldValues;
                    vinClassToInsert.add(vinClass);
                }
            }
        }
        
        if(vinClassToUpdate != NULL && !vinClassToUpdate.isEmpty()){
            Database.SaveResult[] srList = Database.update(vinClassToUpdate, False);
            for (Database.SaveResult sr : srList) {                
                if (!sr.isSuccess()){
                    QDX_Log.error('Exception Occurred: ' +sr.getErrors()[0].getMessage());
                    QDX_Log.publish();
                    AuraHandledException error = new AuraHandledException(sr.getErrors()[0].getMessage());
                    error.setMessage(sr.getErrors()[0].getMessage());        
                    throw error;                    
                }
            } 
        }
        if( vinClassToInsert != NULL && !vinClassToInsert.isEmpty()){
            Database.SaveResult[] srList = Database.insert(vinClassToInsert, False);           
            for (Database.SaveResult sr : srList) {                
                if (!sr.isSuccess()){
                    QDX_Log.error('Exception Occurred: ' +sr.getErrors()[0].getMessage());
                    QDX_Log.publish();
                    AuraHandledException error = new AuraHandledException(sr.getErrors()[0].getMessage());
                    error.setMessage(sr.getErrors()[0].getMessage());        
                    throw error; 
                }
            }  
        }           
        
        //Update VinClass records with updated Rule and Rate Class fields.
        // Resetting the variables to prevent hitting heap limits.
        vinClassToUpdate = new List<VIN_Class__c>();
        vinClassToInsert = new List<VIN_Class__c>();
        vinDetailId =  new Set<Id>();
        vinClassRecords = new List<sObject>();
        vinDetailMap = new Map<Id, VIN_Detail__c>();
        vinClassMap = new Map<Id, VIN_Class__c>();
        return System.Label.Class_Guide_Builder_Success_Message;
    }
    
    /*** This method is called from updateVinClassRecords from same class.
    @param String valueNewClassGuide , String of New Class Guide Name on UI
    @param String rateClass , String of rate class on UI
    @param List<sObject> vinDetailIdString , filtered list of Vin Detail records based on user selection
    @param String vinDetailFieldValues , String of concatenated field values of selected Vin Detail records for Rule field update
    @param String valuePartner , String of selected Partner on UI        
    This method creates a new VinClass Records and insert the records.
    ***/
    public static String insertVinClassRecords(String valueNewClassGuide, String rateClass, List<sObject> vinDetailIdString, String vinDetailFieldValues, String valuePartner){
        List<VIN_Class__c> vinClassToInsert = new List<VIN_Class__c>();    
        for(sObject vinDetail : vinDetailIdString){
            VIN_Class__c vinClass = new VIN_Class__c();
            vinClass.Class_Guide_Name__c = valueNewClassGuide;
            vinClass.Squish_VIN__c = (Id) vinDetail.get('Id');
            vinClass.Class__c = rateClass;
            vinClass.Partner__c = valuePartner;
            vinClass.Rule__c = vinDetailFieldValues;
            vinClassToInsert.add(vinClass);
        }
        if(vinClassToInsert != NULL && !vinClassToInsert.isEmpty()){
            Boolean anyRecordFailedToInsert = false;
            Database.SaveResult[] srList = Database.insert(vinClassToInsert, False);           
            for (Database.SaveResult sr : srList) {                
                if (!sr.isSuccess()){
                    anyRecordFailedToInsert = true;
                    QDX_Log.error('Exception Occurred: ' +sr.getErrors()[0].getMessage());
                    QDX_Log.publish();
                    throw new AuraHandledException(System.Label.Error_Message);
                }
            }            
            if(!anyRecordFailedToInsert){
                return System.Label.Class_Guide_Builder_Success_Message_Insert;
            }
        }            
        
        return System.Label.No_records_to_update_error_message;
    }
    
    // This method creates a concatenated string that will be used to update value of Rule field on Vin Class record.
    public static String createRuleFieldData(String ethnicity, String makes, String models, String valueTrims, String valueEngines, String valueCylinders, String valueAspiration, String valueFuel, String valueDrive, String valueTonnage, String valueBodyStyle, String vinPrefix){
        String vinDetailFieldValues = '';
        vinDetailFieldValues = ethnicity != null && ethnicity != '' ? vinDetailFieldValues + '[Ethnicity] = '+ethnicity+'\n' : vinDetailFieldValues;
        vinDetailFieldValues = makes != null && makes != '' ? vinDetailFieldValues + '[Makes] = '+makes+'\n' : vinDetailFieldValues;
        vinDetailFieldValues = models != null && models != '' ? vinDetailFieldValues + '[Models] = '+models+' \n' : vinDetailFieldValues;
        vinDetailFieldValues = valueTrims != null && valueTrims != '' ? vinDetailFieldValues + '[Trims] = '+ valueTrims +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueEngines != null && valueEngines != '' ? vinDetailFieldValues + '[Engines] = '+ valueEngines +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueCylinders != null && valueCylinders !='' ? vinDetailFieldValues + '[Cylinders] = '+ valueCylinders +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueAspiration != null && valueAspiration !='' ? vinDetailFieldValues + '[Cylinders] = '+ valueAspiration +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueFuel != null && valueFuel !='' ? vinDetailFieldValues + '[Fuel] = '+ valueFuel +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueDrive != null && valueDrive != '' ? vinDetailFieldValues + '[Drivetrain] = '+ valueDrive +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueTonnage != null && valueTonnage != '' ? vinDetailFieldValues + '[Tonnage] = '+ valueTonnage +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = valueBodyStyle != null && valueBodyStyle !='' ? vinDetailFieldValues + '[Body Style] = '+ valueBodyStyle +'\n' : vinDetailFieldValues;
        vinDetailFieldValues = vinPrefix != null && vinPrefix!= '' ? vinDetailFieldValues + '[VIN Prefix] = '+ vinPrefix +'\n' : vinDetailFieldValues;
        if(vinDetailFieldValues.endsWith('\n')){
            vinDetailFieldValues = vinDetailFieldValues.substring(0, vinDetailFieldValues.length() - 1);
        }
        return vinDetailFieldValues;
    }
    
    /*** This method is called from ClassGuideBuilder lwc component.
    This method returns all unique class guide names.
    ***/
    @AuraEnabled
    public static List<String> getClassBuilderNames(){
        try{
            List<String> classGuideNameList = new List<String>();
            for(sObject vinClassRecSObj : [SELECT Class_Guide_Name__c from VIN_Class__c group by Class_Guide_Name__c]){   
                AggregateResult vinClassRec = (AggregateResult) vinClassRecSObj;
                classGuideNameList.add((String) vinClassRec.get('Class_Guide_Name__c'));
            }
            return classGuideNameList;
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
            throw new AuraHandledException(System.Label.Error_Message);
        }
    }
}