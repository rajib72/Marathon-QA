/**
* @author Raj Sekhar Mukherjee
* @dateModified 2026-09-22
* @ModifiedBy Raj Sekhar Mukherjee
* @description Allocation Orchestrator for ROP
*/
public with sharing class ROPAllocationOrchestrator {
    @TestVisible static Boolean disableBatchExecution = false;
    public static void startAllocation() {
        if (Test.isRunningTest() && disableBatchExecution) return;
        Integer pending = [
            SELECT COUNT() FROM ROP__c
            WHERE Contract__c != null AND ROP_Amount_Calculated__c != null
            AND Time_Processed__c = null
            AND (ROP_Allocation_Status__c = null OR ROP_Allocation_Status__c = 'Pending')
        ];
        if (pending == 0) return;
        List<AsyncApexJob> running = [
            SELECT Id FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
            AND Status IN ('Holding', 'Preparing', 'Processing', 'Queued')
            LIMIT 1
        ];
        if (running.isEmpty()) {
            Database.executeBatch(new BatchRopAllocation(), BatchRopAllocation.BATCH_SIZE);
        } else {
            ROPAllocationDeferredScheduler.scheduleRetry(2);
        }
    }
}