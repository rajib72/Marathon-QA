global class PolicyContractMonthsScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new UpdatePolicyContractMonthsBatch(), 200);
    }
}