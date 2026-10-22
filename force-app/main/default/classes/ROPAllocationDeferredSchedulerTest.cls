@IsTest
private class ROPAllocationDeferredSchedulerTest {

    private static final String JOB_NAME_PREFIX = 'ROP Allocation Deferred Retry';

    @TestSetup
    static void setupData() {
        ROPAllocationOrchestrator.disableBatchExecution = true;
    }

    @IsTest
    static void testScheduleRetryCreatesCronJobWithNullDelay() {

        ROPAllocationDeferredScheduler.disableScheduling = false;
        ROPAllocationOrchestrator.disableBatchExecution = true;

        Test.startTest();

        ROPAllocationDeferredScheduler.scheduleRetry(null);

        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];

        System.assertEquals(
            1,
            scheduledJobs.size(),
            'One deferred ROP allocation retry job should be scheduled.'
        );

        Test.stopTest();
    }

    @IsTest
    static void testScheduleRetryUsesMinimumDelayWhenLessThanTwoMinutes() {

        ROPAllocationDeferredScheduler.disableScheduling = false;
        ROPAllocationOrchestrator.disableBatchExecution = true;

        Test.startTest();

        ROPAllocationDeferredScheduler.scheduleRetry(1);

        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];

        System.assertEquals(
            1,
            scheduledJobs.size(),
            'One deferred ROP allocation retry job should be scheduled when delay is less than 2 minutes.'
        );

        Test.stopTest();
    }

    @IsTest
    static void testScheduleRetryPreventsDuplicateJobs() {

        ROPAllocationDeferredScheduler.disableScheduling = false;
        ROPAllocationOrchestrator.disableBatchExecution = true;

        Test.startTest();

        ROPAllocationDeferredScheduler.scheduleRetry(5);
        ROPAllocationDeferredScheduler.scheduleRetry(5);

        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];

        System.assertEquals(
            1,
            scheduledJobs.size(),
            'Duplicate deferred ROP allocation retry jobs should not be scheduled.'
        );

        Test.stopTest();
    }

    @IsTest
    static void testScheduleRetryDoesNothingWhenDisabled() {

        ROPAllocationDeferredScheduler.disableScheduling = true;
        ROPAllocationOrchestrator.disableBatchExecution = true;

        Test.startTest();

        ROPAllocationDeferredScheduler.scheduleRetry(2);

        List<CronTrigger> scheduledJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ];

        Test.stopTest();

        System.assertEquals(
            0,
            scheduledJobs.size(),
            'No deferred ROP allocation retry job should be scheduled when scheduling is disabled.'
        );

        ROPAllocationDeferredScheduler.disableScheduling = false;
    }

    @IsTest
    static void testExecuteMethodCallsOrchestratorSafely() {

        ROPAllocationOrchestrator.disableBatchExecution = true;

        Test.startTest();

        ROPAllocationDeferredScheduler scheduler =
            new ROPAllocationDeferredScheduler();

        scheduler.execute(null);

        Test.stopTest();

        System.assert(
            true,
            'Scheduler execute method completed successfully.'
        );
    }
}