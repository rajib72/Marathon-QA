/**
* @author Raj Sekhar Mukherjee
* @dateModified 2026-07-06
* @description Deferred retry scheduler for ROP Auto Allocation.
*/
public with sharing class ROPAllocationDeferredScheduler implements Schedulable {
    
    @TestVisible
    private static Boolean disableScheduling = false;
    
    private static final String JOB_NAME_PREFIX = 'ROP Allocation Deferred Retry';
    
    public void execute(SchedulableContext sc) {
        ROPAllocationOrchestrator.startAllocation();
    }
    
    public static void scheduleRetry(Integer delayMinutes) {
        
        if (Test.isRunningTest() && disableScheduling) {
            return;
        }
        
        Integer minutesToAdd = delayMinutes == null || delayMinutes < 2
            ? 2
            : delayMinutes;
        
        String jobNameLike = JOB_NAME_PREFIX + '%';
        
        List<CronTrigger> existingJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :jobNameLike
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
            LIMIT 1
        ];
        
        if (!existingJobs.isEmpty()) {
            return;
        }
        
        Datetime runAt = System.now().addMinutes(minutesToAdd);
        
        String cronExp =
            '0 ' +
            runAt.minute() + ' ' +
            runAt.hour() + ' ' +
            runAt.day() + ' ' +
            runAt.month() + ' ? ' +
            runAt.year();
        
        System.schedule(
            JOB_NAME_PREFIX + ' - ' + runAt.format('yyyyMMddHHmmss'),
            cronExp,
            new ROPAllocationDeferredScheduler()
        );
    }
}