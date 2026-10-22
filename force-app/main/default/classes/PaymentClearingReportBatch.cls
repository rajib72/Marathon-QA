global class PaymentClearingReportBatch
    implements Database.Batchable<SObject>,
               Database.AllowsCallouts {

    global Database.QueryLocator start(
        Database.BatchableContext bc
    ) {

        return Database.getQueryLocator([
            SELECT Id,
                   BOK_Purchase_Request_Id__c,
                   BOK_VCN_Id__c,
                   Credit_Card_Number__c,
                   Credit_Card_Confirmation_Number__c,
                   Credit_Card_Date_Ran__c
            FROM Payment__c
            WHERE BOK_Purchase_Request_Id__c != NULL
              AND Credit_Card_Confirmation_Number__c = NULL
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<Payment__c> payments
    ) {

        for (Payment__c payment : payments) {

            // Credit Card Number cannot be filtered in SOQL,
            // so check it here instead.
            if (String.isBlank(payment.Credit_Card_Number__c)) {
                System.debug(
                    LoggingLevel.INFO,
                    'MRT3-38 Skipping Payment because Credit Card Number is blank: ' +
                    payment.Id
                );
                continue;
            }

            try {

                Date fromDate = Date.today().addDays(-2);
                Date toDate = Date.today();

                System.debug(
                    LoggingLevel.INFO,
                    'MRT3-38 Processing Payment: ' +
                    payment.Id
                );

                String reportId =
                    PaymentClearingReportService.createClearingReport(
                        payment.Id,
                        fromDate,
                        toDate
                    );

                System.debug(
                    LoggingLevel.INFO,
                    'MRT3-38 Clearing Report Created. ReportId: ' +
                    reportId
                );

                PaymentClearingReportService.getClearingReport(
                    reportId
                );

            } catch (Exception e) {

                System.debug(
                    LoggingLevel.ERROR,
                    'MRT3-38 Error processing Payment ' +
                    payment.Id +
                    ': ' +
                    e.getMessage()
                );
            }
        }
    }

    global void finish(
        Database.BatchableContext bc
    ) {

        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Payment Clearing Report Batch completed.'
        );
    }
}