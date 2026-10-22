/**
* @author Sujit Dengale
* @dateModified 23-04-2024
* @description Create clone report request of completed records
*/

public class CloneRequestReport {
    @invocableMethod(Label='CreateClone')
    public static void createClone(List<RecordWrapper> recordIdList){
        List<String> recordIdListApex = recordIdList[0].recordIdListApex;
        String recordId = recordIdListApex[0];
        Date retunedStartDate;
        SObject clonedRecord;
        List<String> recurranceVariable = new List<String> ();
        
        try{
            if(recordId != NULL){   
                Map<String, Schema.SObjectField> fieldsMap = Schema.getGlobalDescribe().get('Report_Request__c').getDescribe().fields.getMap();
                List<String> fieldNames = new List<String>();
                
                
                for (String fieldName : fieldsMap.keySet()) {
                    Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
                    if (!fieldDescribe.isCalculated() && !fieldDescribe.isAutoNumber() && fieldDescribe.isCreateable()) {
                        fieldNames.add(fieldName);
                    }
                }
                String soql = 'SELECT ' + String.join(fieldNames, ',') + ' FROM Report_Request__c WHERE Id = :recordId';
                SObject record = Database.query(soql);
                if(record != NULL){
                    clonedRecord = record.clone(false, true, false, false);
                }
            }
            
            String recordFrequency = (String) clonedRecord.get('Frequency__c');
            if(recordFrequency != NULL){
                Object StartDateObj = (Object) clonedRecord.get('Start_Date__c');
                Date StartDateVar = (Date) StartDateObj;
                if(recordFrequency == 'Weekly'){
                    Object weekList = clonedRecord.get('Weekly_Recurrence__c');
                    String weeks = (String )weekList;
                    recurranceVariable = weeks.Split(';');
                    retunedStartDate = UtilityClass.getNextFollowupDate(StartDateVar,recordFrequency,recurranceVariable,false);
                }  
                if(recordFrequency == 'Monthly'){
                    Object dayOfMonth = clonedRecord.get('Monthly_Recurrence__c');
                    String days = (String )dayOfMonth;
                    recurranceVariable.add(days);
                    if(days != 'Last'){
                        retunedStartDate = UtilityClass.getNextFollowupDate(StartDateVar,recordFrequency,recurranceVariable,false);
                    }
                    else{
                        retunedStartDate = UtilityClass.getNextFollowupDate(StartDateVar,recordFrequency,recurranceVariable,true);
                    }
                } 
            }
            
            clonedRecord.put('Start_Date__c',retunedStartDate);
            clonedRecord.put('Status__c','Requested');
            Database.insert(clonedRecord, false);
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
        }  
    }
    
    public class RecordWrapper{
        @InvocableVariable(required=true)
        public List<String> recordIdListApex;
        
    }
    
    
    
}