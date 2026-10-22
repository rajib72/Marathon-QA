global class PaymentClearingReportScheduler
    implements Schedulable {

    global void execute(SchedulableContext sc) {

        Database.executeBatch(
            new PaymentClearingReportBatch(),
            40
        );
    }
}