/**
* @author Saurabh Rawat
* @dateModified 2024-04-25
* @description Batch class to update the status of expired contracts.
*/
global class UpdateExpiredContractBatch implements Database.Batchable<sObject>,Schedulable {
    
    /**
     * Method to generate the query locator for retrieving contract records to update.
     * @param BC The batchable context.
     * @return The query locator.
     */
    global Database.QueryLocator start(Database.BatchableContext BC) {
        string StatusValue = UtilityClass.contractStatus_Active;
        Date TodayDate = System.Today(); 
        String query = 'SELECT Id,Name,Status,Expiration_Date__c, Contract_Term_Months__c FROM InsurancePolicy WHERE Status = :StatusValue AND Expiration_Date__c <:TodayDate AND Contract_Term_Months__c !=1';
        return Database.getQueryLocator(query);
    }
    
    /**
     * Method to update the status of expired contracts.
     * @param BC The batchable context.
     * @param scope The scope of records to process.
     */
    global void execute(Database.BatchableContext BC, List<InsurancePolicy> scope) {
        try{
            for (InsurancePolicy policy : scope) {
                policy.Status = UtilityClass.contractStatus_Expired; 
            }
            Database.update(scope,false);
        }
        catch(Exception e){
            QDX_Log.publishLog(UtilityClass.formatBatchErrorMessage(e,BC.getJobId()),'UpdateExpiredContractBatch','ERROR', BC.getJobId());
        }
    }
    
    /**
     * Method executed after batch completes.
     * @param BC The batchable context.
     */
    global void finish(Database.BatchableContext BC) {
    }
   global void execute(SchedulableContext sc){
        UpdateExpiredContractBatch b = new UpdateExpiredContractBatch(); 
        Database.executeBatch(b);
    }
}