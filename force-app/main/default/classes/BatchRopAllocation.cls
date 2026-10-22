/**
 * Revised BatchRopAllocation QA candidate.
 * BATCH_SIZE/MAX_ITERATIONS preserved. Requires new ROP fields.
 */
public class BatchRopAllocation implements Database.Batchable<sObject>, Database.Stateful {
    public static final Integer MAX_ITERATIONS = 20;
    public static final Integer BATCH_SIZE = 5;
    private static final String ROP_FIELDS =
        'Id, Cancel_Date__c, Contract__c, Contract__r.Cancel_Effective_Date__c, ' +
        'ROP_Amount_Calculated__c, Cancel_Fee__c, CreatedDate, Time_Processed__c, ' +
        'ROP_Allocation_Status__c';
    private static final String ROP_FILTER =
        'Contract__c != null AND ROP_Amount_Calculated__c != null ' +
        'AND Time_Processed__c = null ' +
        'AND (ROP_Allocation_Status__c = null OR ROP_Allocation_Status__c = \'Pending\')';

    @TestVisible private Integer processedRopCount = 0;
    @TestVisible private Integer previousRemainingCount = -1;
    @TestVisible private Integer iterationCount = 0;
    @TestVisible private Boolean hadLockConflict = false;
    @TestVisible private Integer skippedOutOfOrder = 0;
    @TestVisible private static Boolean disableBatchChaining = false;

    public BatchRopAllocation() { this(-1, 0); }
    public BatchRopAllocation(Integer previousCount, Integer iteration) {
        previousRemainingCount = previousCount;
        iterationCount = iteration;
    }
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q = 'SELECT ' + ROP_FIELDS + ' FROM ROP__c WHERE ' + ROP_FILTER;
        if (Test.isRunningTest()) q += ' LIMIT 200';
        return Database.getQueryLocator(q);
    }
    public void execute(Database.BatchableContext bc, List<ROP__c> scope) {
        if (scope == null || scope.isEmpty()) return;
        Savepoint scopeSp = Database.setSavepoint();
        try {
            Integer completed = RopAllocationUtilityCtrl.startRopAllocations(scope, bc.getJobId());
            processedRopCount += completed;
            skippedOutOfOrder += scope.size() - completed;
        } catch (Exception e) {
            // Roll back BOTH legacy and phase-2 changes, including status updates.
            Database.rollback(scopeSp);
            String msg = e.getMessage() == null ? '' : e.getMessage().toLowerCase();
            Boolean lockFailure = msg.contains('unable_to_lock_row') ||
                msg.contains('unable to lock row') ||
                msg.contains('record currently unavailable') ||
                msg.contains('unable to obtain exclusive access');
            if (lockFailure) hadLockConflict = true;
            // Leave failed scope PENDING for explicit operator investigation;
            // do not claim that the batch processed it or automatically write Failed
            // to possibly locked rows. A durable error log belongs outside rollback.
            QDX_Log.publishLog(
                UtilityClass.formatBatchErrorMessage(e, bc.getJobId()),
                'BatchRopAllocation', 'ERROR', bc.getJobId()
            );
        }
    }
    public void finish(Database.BatchableContext bc) {
        Integer remaining = [
            SELECT COUNT() FROM ROP__c
            WHERE Contract__c != null AND ROP_Amount_Calculated__c != null
            AND Time_Processed__c = null
            AND (ROP_Allocation_Status__c = null OR ROP_Allocation_Status__c = 'Pending')
        ];
        QDX_LOG.debug('ROP finish: remaining=' + remaining +
            ', processed=' + processedRopCount + ', deferredByOrder=' +
            skippedOutOfOrder + ', iteration=' + iterationCount);
        QDX_LOG.publish();
        if (remaining == 0 || disableBatchChaining) return;
        if (iterationCount >= MAX_ITERATIONS) return;
        if (hadLockConflict) {
            ROPAllocationDeferredScheduler.scheduleRetry(2);
            return;
        }
        if (processedRopCount == 0) {
            // No automatic infinite retry on a permanently invalid record.
            QDX_LOG.error('ROP batch made no progress; pending ROPs require investigation.');
            QDX_LOG.publish();
            return;
        }
        if (previousRemainingCount >= 0 && remaining >= previousRemainingCount) return;
        Id currentJobId = bc.getJobId();
        List<AsyncApexJob> others = [
            SELECT Id FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchRopAllocation'
            AND Status IN ('Holding','Preparing','Processing','Queued')
            AND Id != :currentJobId LIMIT 1
        ];
        if (others.isEmpty()) {
            Database.executeBatch(new BatchRopAllocation(remaining, iterationCount + 1), BATCH_SIZE);
        } else {
            ROPAllocationDeferredScheduler.scheduleRetry(2);
        }
    }
}