/**
* @author Waidehee Kuradkar
* @dateModified 2025-05-19
* @description Trigger Handler on Vin Detail object
*/
public class VINDetailTriggerHandler {
    public static void handleAfterInsert(List<VIN_Detail__c> newVinDetailRecords,  Map<Id,VIN_Detail__c> oldVinDetailMap, Boolean isUpdate){ 
        createVinClasses(newVinDetailRecords, isUpdate);
    }
    
    public static void handleAfterUpdate(List<VIN_Detail__c> newVinDetailRecords,  Map<Id,VIN_Detail__c> oldVinDetailMap, Boolean isUpdate){ 
        createVinClasses(newVinDetailRecords, isUpdate);
    }
    
    // Creates new VinClass Records for  the new Vin Detail records. Finds best possible match for the new Vin Detail records.
    // Once match is found, fetches associated Vin Class Record and clone them to create unique Vin Class records for new vin detail record.
    public static void createVinClasses(List<VIN_Detail__c> newVinDetailRecords, Boolean isUpdate){
        try{
            Set<String> allEthnicity = new Set<String> ();
            Set<String> allModels = new Set<String> ();
            Set<String> allMakes = new Set<String> ();
            List<Id> vinDetailIds = new List<id> ();
            Map< Id, Id> squishVinToNewRecordMap = new Map< Id, Id>();
            Map< Id, List<VIN_Class__c>> squishVinToVinClassMap = new Map< Id, List<VIN_Class__c>>();
            List<VIN_Detail__c> filteredData = new List<VIN_Detail__c>();
            List<VIN_Detail__c> vinDetailstoProcess = new List<VIN_Detail__c>();
            List<VIN_Class__c> vinClassToInsert = new List<VIN_Class__c>();
            List<String> fieldAPINames = new List<String> {'Ethnicity__c', 'MAK_NM__c', 'MDL_DESC__c', 'TRIM_DESC__c', 'ENG_MDL_DESC__c', 'ENG_ASP_SUP_CHGR_CD__c', 'ENG_ASP_TRBL_CHGR_CD__c', 'ENG_CLNDR_RTR_CNT__c', 'ENG_FUEL_DESC__c', 'DRV_TYP_CD__c', 'TRK_TNG_RAT_CD__c'};
            if(isUpdate) {
                vinDetailstoProcess = [SELECT Id, Ethnicity__c, MAK_NM__c, MDL_DESC__c, TRIM_DESC__c, ENG_MDL_DESC__c, ENG_ASP_SUP_CHGR_CD__c,
                    ENG_ASP_TRBL_CHGR_CD__c, ENG_CLNDR_RTR_CNT__c, ENG_FUEL_DESC__c, DRV_TYP_CD__c, TRK_TNG_RAT_CD__c FROM Vin_Detail__c
                    WHERE Id NOT IN (Select Squish_VIN__c from VIN_Class__c) AND Id IN : newVinDetailRecords];
            } else {
                vinDetailstoProcess = newVinDetailRecords;
            }
            if(vinDetailstoProcess.size() > 0) {
                for ( VIN_Detail__c vinDetailRec : vinDetailstoProcess){
                    if(vinDetailRec.Ethnicity__c != NULL || vinDetailRec.Ethnicity__c != ''){
                        allEthnicity.add(vinDetailRec.Ethnicity__c);
                    }
                    if(vinDetailRec.MDL_DESC__c != NULL && vinDetailRec.MDL_DESC__c != ''){
                        allModels.add(vinDetailRec.MDL_DESC__c);
                    }
                    if(vinDetailRec.MAK_NM__c != NULL && vinDetailRec.MAK_NM__c != ''){
                        allMakes.add(vinDetailRec.MAK_NM__c);
                    }                
                }
                
                List<VIN_Detail__c> tempData = new List<VIN_Detail__c> ();
                List<VIN_Detail__c> allMatchingVinDetails = new List<VIN_Detail__c> ();
                
                if( allEthnicity != NULL &&  allModels != NULL && allMakes != NULL && allEthnicity.size()>0 && allMakes.size()>0 && allModels.size()>0){
                    allMatchingVinDetails  = [SELECT Id, Ethnicity__c, MAK_NM__c, MDL_DESC__c, TRIM_DESC__c, ENG_MDL_DESC__c, ENG_ASP_SUP_CHGR_CD__c, ENG_ASP_TRBL_CHGR_CD__c, ENG_CLNDR_RTR_CNT__c, ENG_FUEL_DESC__c, DRV_TYP_CD__c, TRK_TNG_RAT_CD__c FROM VIN_Detail__c WHERE Ethnicity__c IN :allEthnicity AND MAK_NM__c IN :allMakes AND ID IN(Select Squish_VIN__c from VIN_Class__c) ORDER BY MDL_YR__c DESC LIMIT 50000];
                }
                if(allMatchingVinDetails.size()>0){
                    for(VIN_Detail__c newVinDetailRec : vinDetailstoProcess){
                        tempData = new List<VIN_Detail__c>();
                        filteredData = new List<VIN_Detail__c> (allMatchingVinDetails);
                        for( Integer i = 0; i < fieldAPINames.size() ; i++){  
                            tempData.clear();                      
                            
                            for( VIN_Detail__c oldVinDetailRec : filteredData){
                                if(newVinDetailRec.Ethnicity__c == oldVinDetailRec.Ethnicity__c && newVinDetailRec.MAK_NM__c == oldVinDetailRec.MAK_NM__c){
                                    // If field API is ENG_ASP_SUP_CHGR_CD__c, the code takes into consideration ENG_ASP_SUP_CHGR_CD__c and ENG_ASP_TRBL_CHGR_CD__c values together.
                                    if( fieldAPINames[i] == 'ENG_ASP_SUP_CHGR_CD__c' && newVinDetailRec.Id != oldVinDetailRec.get('Id') && ( newVinDetailRec.get(fieldAPINames[i]) == oldVinDetailRec.get(fieldAPINames[i])  && newVinDetailRec.get(fieldAPINames[i+1]) == oldVinDetailRec.get(fieldAPINames[i+1]))){
                                        tempData.add(oldVinDetailRec);
                                    } 
                                    else if( (fieldAPINames[i] != 'ENG_ASP_SUP_CHGR_CD__c' || fieldAPINames[i] != 'ENG_ASP_TRBL_CHGR_CD__c') && newVinDetailRec.Id != oldVinDetailRec.get('Id') && (newVinDetailRec.get(fieldAPINames[i]) == oldVinDetailRec.get(fieldAPINames[i]))){
                                        tempData.add(oldVinDetailRec);
                                    } 
                                }
                                
                            }
    
                            if(tempData.size() > 1 ){
                                filteredData = new List<VIN_Detail__c>(tempData);                   
                            }
                            else if(tempData.size() == 1){
                                squishVinToNewRecordMap.put(tempData[0].Id, newVinDetailRec.Id);
                                vinDetailIds.add(tempData[0].Id);
                                filteredData = new List<VIN_Detail__c>();
                                break;
                            }
                            else {
                                squishVinToNewRecordMap.put(filteredData[filteredData.size() - 1].Id, newVinDetailRec.Id);
                                vinDetailIds.add(filteredData[filteredData.size() - 1].Id);   
                                filteredData = new List<VIN_Detail__c>();
                                break;
                            }
                        }
                        if(filteredData.size() > 0){           
                            squishVinToNewRecordMap.put(filteredData[filteredData.size() - 1].Id, newVinDetailRec.Id);
                            vinDetailIds.add(filteredData[filteredData.size() - 1].Id);
                        }
                    }
                    List<VIN_Class__c> vinClassList =  new List<VIN_Class__c>();
                    if( vinDetailIds != NULL && vinDetailIds.size()>0){
                        vinClassList = [Select Id, Squish_VIN__c, Partner__c, Class_Guide_Name__c, Class__c, Rule__c, Purchase_Type__c from VIN_Class__c where  Squish_VIN__c IN :vinDetailIds AND Class__c != NULL ORDER BY Squish_VIN__c];  
                    }
                    if(vinClassList.size() > 0){
                        for( VIN_Class__c vinClassRec : vinClassList){
                            if(squishVinToVinClassMap.containsKey(vinClassRec.Squish_VIN__c)){
                                squishVinToVinClassMap.get(vinClassRec.Squish_VIN__c).add(vinClassRec);
                            }
                            else{
                                squishVinToVinClassMap.put(vinClassRec.Squish_VIN__c, new List<VIN_Class__c> {vinClassRec});
                            }
                        }
                        
                        
                        for ( Id vinDetailId : squishVinToNewRecordMap.keySet()){
                            if(squishVinToVinClassMap.containsKey(vinDetailId)){
                                for( VIN_Class__c oldVinClassRec : squishVinToVinClassMap.get(vinDetailId)){
                                    VIN_Class__c vinClassRec = oldVinClassRec.clone(false, false, false, false);
                                    vinClassRec.Id = NULL;
                                    vinClassRec.Squish_VIN__c = squishVinToNewRecordMap.get(vinDetailId);
                                    vinClassToInsert.add(vinClassRec);
                                    
                                }
                            }                       
                            
                        } 
                        Database.SaveResult[] srList = Database.insert(vinClassToInsert, False);           
                        for (Database.SaveResult sr : srList) {                
                            if (!sr.isSuccess()){
                                QDX_Log.error('Exception Occurred: ' +sr.getErrors()[0].getMessage());
                                QDX_Log.publish();                    
                            }
                        }  
                    }
                    
                }
            }            
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage());
            QDX_Log.publish();            
        }
    }    
}