/**
* @author: Renuka Singh
* @dateModified: 2024-04-09
* @description: Schedular class to schedule batch class CloseClaimUpdateBatchClass
*/
global class ClaimUpdateBatchScheduler implements Schedulable {
    
    // Execute at regular intervals
    global void execute(SchedulableContext ctx){
        CloseClaimUpdateBatchClass batchCls = new CloseClaimUpdateBatchClass(); 
        database.executeBatch(batchCls);
    }
}