global class ContractsBatchClass implements Database.Batchable<sObject>,Schedulable
{
    global Database.QueryLocator start(Database.BatchableContext BC)
    {
        string statusValue = UtilityClass.contractStatus_InWaiting;
        Date todayDate = System.Today(); 
        String query = 'SELECT Id,Name,Status,CreatedDate,Reinstated_Effective_Date__c,Effective_Date__c FROM InsurancePolicy WHERE Status = :statusValue AND CreatedDate <:todayDate ' ;
        return Database.getQueryLocator(query);
    }
    global void execute(Database.BatchableContext BC, List<InsurancePolicy> ContractsList)
    {
        
        //Execute method of Batch class for updating the Status
        try{
            for(InsurancePolicy contractObj : ContractsList)
            {
                if((contractObj.Reinstated_Effective_Date__c != NULL &&
                    contractObj.Reinstated_Effective_Date__c <= System.Today()) || 
                   (contractObj.Effective_Date__c != NULL &&
                    contractObj.Effective_Date__c <= System.Today())){
                        contractObj.Status = UtilityClass.contractStatus_Active;
                    }
            }
            Database.update(ContractsList,false);
        }
        catch(Exception e){
            System.debug('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        }
    }
    global void finish(Database.BatchableContext BC) {
    }
    global void execute(SchedulableContext sc){
        //Execute method of Schedulable, for Scheduling a class
        Database.executeBatch(new ContractsBatchClass());
    }
}