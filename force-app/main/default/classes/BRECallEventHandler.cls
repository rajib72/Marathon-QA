public with sharing class BRECallEventHandler {
    
    // 🔒 Safety constants (can later move to Custom Metadata)
    private static final Integer MAX_RECORDS = 200;
    private static final Integer MIN_EXECUTION_TIME_MS = 20;
    private static final Integer MIN_CALLOUT_THRESHOLD = 5;
    private static Boolean isRunning = false;
    
    public static void handleAfterInsert(List<BRE_Call_Event__e> events) {
        
        // Master logging switch
        BRE_Logging_Config__mdt config = BRE_Logging_Config__mdt.getInstance('Default');
        
        if(config == null || !config.Enable_Logging__c){
            return;
        }
        
        if(isRunning){
            return;
        }
        
        isRunning = true;
        
        try{
            if (events == null || events.isEmpty()) {
                return;
            }
            
            List<BRE_Call_Audit__c> recordsToInsert = new List<BRE_Call_Audit__c>();
            
            for (BRE_Call_Event__e evt : events) {
                
                if (!shouldLog(evt)) {
                    continue;
                }
                
                recordsToInsert.add(buildAuditRecord(evt));
                
                // 🔒 Hard cap protection
                if (recordsToInsert.size() >= MAX_RECORDS) {
                    break;
                }
            }
            
            insertRecords(recordsToInsert);
        }finally{
            isRunning = false;
        }
    }
    
    /**
* 🔍 Determines whether the event should be logged
*/
    private static Boolean shouldLog(BRE_Call_Event__e evt) {
        
        if (evt == null) {
            return false;
        }
        
        // Ignore missing rule name
        if (String.isBlank(evt.Rule_Name__c)) {
            return false;
        }
        
        // Ignore very fast calls (low value)
        if (evt.Execution_Time__c != null &&
            evt.Execution_Time__c < MIN_EXECUTION_TIME_MS) {
                return false;
            }
        
        // Ignore low-volume transactions
        if (evt.Callout_Count__c != null &&
            evt.Callout_Count__c < MIN_CALLOUT_THRESHOLD) {
                return false;
            }
        
        return true;
    }
    
    /**
* 🏗️ Builds audit record from event
*/
    private static BRE_Call_Audit__c buildAuditRecord(BRE_Call_Event__e evt) {
        
        return new BRE_Call_Audit__c(
            Rule_Name__c        = evt.Rule_Name__c,
            Rule_Type__c        = evt.Rule_Type__c,
            Call_Type__c        = evt.Call_Type__c,
            Source__c           = evt.Source__c,
            Caller_Class__c     = evt.Caller_Class__c,
            Caller_Method__c    = evt.Caller_Method__c,
            Method_Call_Count__c = evt.Method_Call_Count__c,
            Execution_Time__c   = evt.Execution_Time__c,
            Response_Status__c  = evt.Response_Status__c,
            Transaction_Id__c   = evt.Transaction_Id__c,
            Callout_Count__c    = evt.Callout_Count__c,
            Cache_Hit__c        = evt.Cache_Hit__c,
            Input_Size__c       = evt.Input_Size__c,
            Input_Hash__c       = evt.Input_Hash__c,
            Contract_Number__c = evt.Contract_Number__c,
            User__c             = evt.User_Id__c
        );
    }
    
    /**
      *  Safe insert with error handling
     */
    private static void insertRecords(List<BRE_Call_Audit__c> records) {
        
        if (records == null || records.isEmpty()) {
            return;
        }
        
        try {
            Database.insert(records, false);
        } catch (DmlException e) {
            System.debug('BRE Audit Insert Failed: ' + e.getMessage());
        }
    }
}