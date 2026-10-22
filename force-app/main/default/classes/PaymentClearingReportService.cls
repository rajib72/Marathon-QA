public with sharing class PaymentClearingReportService {
    
    public static String createClearingReport(Id paymentId, Date fromDate, Date toDate) {
        
        Payment__c payment = [
            SELECT
            Id,
            BOK_Purchase_Request_Id__c,
            BOK_VCN_Id__c,
            Credit_Card_Number__c
            FROM Payment__c
            WHERE Id = :paymentId
            LIMIT 1
        ];
        
        if (String.isBlank(payment.Credit_Card_Number__c)) {
            throw new AuraHandledException(
                'Credit Card Number / VCN is not available on the Payment.'
            );
        }
        
        String formattedFromDate =
            String.valueOf(fromDate.year()) + '-' +
            String.valueOf(fromDate.month()).leftPad(2, '0') + '-' +
            String.valueOf(fromDate.day()).leftPad(2, '0');
        
        String formattedToDate =
            String.valueOf(toDate.year()) + '-' +
            String.valueOf(toDate.month()).leftPad(2, '0') + '-' +
            String.valueOf(toDate.day()).leftPad(2, '0');
        
        String xmlPayload =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope ' +
            'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:ser="http://mastercard.com/sd/pc/service">' +
            '<soapenv:Header/>' +
            '<soapenv:Body>' +
            '<ser:CreateVCNClearingsReportRequest' +
            ' FromDate="' + formattedFromDate + '"' +
            ' ToDate="' + formattedToDate + '"' +
            ' FromTime="00:00"' +
            ' ToTime="23:59"' +
            ' Timezone="US/Pacific"' +
            ' TransactionType="All"' +
            ' Pan="' + payment.Credit_Card_Number__c + '"' +
            '/>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Clearing Report request generated successfully for Payment: ' +
            payment.Id
        );
        
        HttpResponse response =
    OAuthRequestGenerator.sendReportingRequest(xmlPayload);
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Clearing Report HTTP Status: ' +
            response.getStatusCode()
        );
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Clearing Report Response: ' +
            response.getBody()
        );
        
        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {
                
                throw new CalloutException(
                    'Mastercard Clearing Report request failed. ' +
                    'HTTP Status: ' + response.getStatusCode()
                );
            }
        
        Dom.Document responseDocument = new Dom.Document();
        responseDocument.load(response.getBody());
        
        Dom.XMLNode envelopeNode =
            responseDocument.getRootElement();
        
        Dom.XMLNode bodyNode = null;
        
        for (Dom.XMLNode child : envelopeNode.getChildElements()) {
            if (child.getName() == 'Body') {
                bodyNode = child;
                break;
            }
        }
        
        if (bodyNode == null) {
            throw new CalloutException(
                'Mastercard response does not contain SOAP Body.'
            );
        }
        
        Dom.XMLNode reportResponseNode = null;
        
        for (Dom.XMLNode child : bodyNode.getChildElements()) {
            if (
                child.getName() ==
                'CreateVCNClearingsReportResponse'
            ) {
                reportResponseNode = child;
                break;
            }
        }
        
        if (reportResponseNode == null) {
            throw new CalloutException(
                'CreateVCNClearingsReportResponse was not found.'
            );
        }
        
        String reportId =
            reportResponseNode.getAttributeValue(
                'ReportId',
                null
            );
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Mastercard ReportId: ' + reportId
        );
        
        if (String.isBlank(reportId)) {
            throw new CalloutException(
                'Mastercard did not return a ReportId.'
            );
        }
        
        return reportId;
    }
    
    public static void getClearingReport(String reportId) {
        
        if (String.isBlank(reportId)) {
            throw new IllegalArgumentException(
                'Report Id is required.'
            );
        }
        
        String xmlPayload =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope ' +
            'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:ser="http://mastercard.com/sd/pc/service">' +
            '<soapenv:Header/>' +
            '<soapenv:Body>' +
            '<ser:GetVCNClearingsReportRequest ' +
            'ReportId="' + reportId + '"' +
            ' From="0"' +
            ' To="99"' +
            '/>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Get Clearing Report - ReportId: ' + reportId
        );
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 GET REPORT XML: ' + xmlPayload
        );
        
        HttpResponse response =
    OAuthRequestGenerator.sendReportingRequest(xmlPayload);
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Get Clearing Report HTTP Status: ' +
            response.getStatusCode()
        );
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Get Clearing Report Response: ' +
            response.getBody()
        );
        
        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {
                
                throw new CalloutException(
                    'Mastercard Get Clearing Report failed. HTTP Status: ' +
                    response.getStatusCode() +
                    '. Response: ' +
                    response.getBody()
                );
            }
        
        Dom.Document doc = new Dom.Document();
        doc.load(response.getBody());
        
        Dom.XMLNode envelopeNode =
            doc.getRootElement();
        
        Dom.XMLNode bodyNode = null;
        
        for (Dom.XMLNode child : envelopeNode.getChildElements()) {
            
            if (child.getName() == 'Body') {
                bodyNode = child;
                break;
            }
        }
        
        if (bodyNode == null) {
            
            throw new CalloutException(
                'Mastercard response does not contain SOAP Body.'
            );
        }
        
        Dom.XMLNode reportNode = null;
        
        for (Dom.XMLNode child : bodyNode.getChildElements()) {
            
            if (
                child.getName() ==
                'GetVCNClearingsReportResponse'
            ) {
                reportNode = child;
                break;
            }
        }
        
        if (reportNode == null) {
            
            throw new CalloutException(
                'GetVCNClearingsReportResponse was not found.'
            );
        }
        
        String reportStatus = null;
String hasMore = null;

Map<String, String> approvalCodeByPurchaseRequest =
    new Map<String, String>();

Map<String, Datetime> transactionDateByPurchaseRequest =
    new Map<String, Datetime>();

Set<String> purchaseRequestIds =
    new Set<String>();

for (Dom.XMLNode child : reportNode.getChildElements()) {

    if (child.getName() == 'ReportStatus') {

        reportStatus = child.getText();

    } else if (child.getName() == 'Transactions') {

        String purchaseRequestId =
            child.getAttributeValue(
                'PurchaseRequestId',
                null
            );

        String approvalCode =
            child.getAttributeValue(
                'ApprovalCode',
                null
            );

        String txnDateTime =
            child.getAttributeValue(
                'TxnDateTime',
                null
            );

        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Transaction PurchaseRequestId: ' +
            purchaseRequestId
        );

        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Transaction ApprovalCode: ' +
            approvalCode
        );

        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Transaction TxnDateTime: ' +
            txnDateTime
        );

        if (String.isNotBlank(purchaseRequestId)) {

            purchaseRequestIds.add(
                purchaseRequestId
            );

            if (String.isNotBlank(approvalCode)) {

                approvalCodeByPurchaseRequest.put(
                    purchaseRequestId,
                    approvalCode
                );
            }
            
            if (String.isNotBlank(txnDateTime)) {
                
                Datetime transactionDateTime =
                    parseMastercardTransactionDateTime(
                        txnDateTime
                    );
                
                if (transactionDateTime != null) {
                    
                    transactionDateByPurchaseRequest.put(
                        purchaseRequestId,
                        transactionDateTime
                    );
                }
            }
        }
    }
}

if (!purchaseRequestIds.isEmpty()) {

    List<Payment__c> paymentsToUpdate =
        new List<Payment__c>();

    List<Payment__c> payments = [
        SELECT
            Id,
            BOK_Purchase_Request_Id__c,
            Credit_Card_Confirmation_Number__c,
            Credit_Card_Date_Ran__c
        FROM Payment__c
        WHERE BOK_Purchase_Request_Id__c
        IN :purchaseRequestIds
    ];

    for (Payment__c payment : payments) {

        String purchaseRequestId =
            payment.BOK_Purchase_Request_Id__c;

        if (
            approvalCodeByPurchaseRequest.containsKey(
                purchaseRequestId
            )
        ) {

            payment.Credit_Card_Confirmation_Number__c =
                approvalCodeByPurchaseRequest.get(
                    purchaseRequestId
                );
        }

        if (
            transactionDateByPurchaseRequest.containsKey(
                purchaseRequestId
            )
        ) {

            payment.Credit_Card_Date_Ran__c =
                transactionDateByPurchaseRequest.get(
                    purchaseRequestId
                );
        }

        Boolean paymentChanged = false;
        
        if (
            approvalCodeByPurchaseRequest.containsKey(
                purchaseRequestId
            )
        ) {
            
            payment.Credit_Card_Confirmation_Number__c =
                approvalCodeByPurchaseRequest.get(
                    purchaseRequestId
                );
            
            paymentChanged = true;
        }
        
        if (
            transactionDateByPurchaseRequest.containsKey(
                purchaseRequestId
            )
        ) {
            
            payment.Credit_Card_Date_Ran__c =
                transactionDateByPurchaseRequest.get(
                    purchaseRequestId
                );
            
            paymentChanged = true;
        }
        
        if (paymentChanged) {
            
            paymentsToUpdate.add(payment);
        }
    }

    if (!paymentsToUpdate.isEmpty()) {

        update paymentsToUpdate;

        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Payments updated from Mastercard clearing report: ' +
            paymentsToUpdate.size()
        );
    }
}
        
        hasMore =
            reportNode.getAttributeValue(
                'HasMore',
                null
            );
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 Report Status: ' +
            reportStatus
        );
        
        System.debug(
            LoggingLevel.INFO,
            'MRT3-38 HasMore: ' +
            hasMore
        );
    }
    
    private static Datetime parseMastercardTransactionDateTime(
    String txnDateTime
) {

    if (String.isBlank(txnDateTime)) {
        return null;
    }

    String value =
        txnDateTime.trim();

    /*
     * If Mastercard provides an explicit timezone
     * such as Z, +00:00 or -07:00, preserve it.
     */
    if (
        value.endsWith('Z') ||
        value.contains('+') ||
        (
            value.length() > 19 &&
            value.substring(19, 20) == '-'
        )
    ) {

        try {

            return (Datetime)
                JSON.deserialize(
                    '"' + value + '"',
                    Datetime.class
                );

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'MRT3-38 Unable to parse Mastercard TxnDateTime: ' +
                value +
                ' Error: ' +
                e.getMessage()
            );

            return null;
        }
    }

    /*
     * Mastercard report is requested with:
     *
     * Timezone="US/Pacific"
     *
     * If Mastercard returns the timestamp without
     * an explicit timezone, treat the value as
     * US/Pacific and convert it to UTC for Salesforce.
     */
    try {

        String normalizedValue =
            value.replace('T', ' ');

        Datetime pacificAsGmt =
            Datetime.valueOfGmt(
                normalizedValue
            );

        TimeZone pacificTimeZone =
            TimeZone.getTimeZone(
                'America/Los_Angeles'
            );

        Integer offset =
            pacificTimeZone.getOffset(
                pacificAsGmt
            );

        Datetime utcDateTime =
            pacificAsGmt.addSeconds(
                -1 * offset / 1000
            );

        /*
         * Re-check the offset to account for
         * daylight-saving transitions.
         */
        Integer correctedOffset =
            pacificTimeZone.getOffset(
                utcDateTime
            );

        if (correctedOffset != offset) {

            utcDateTime =
                pacificAsGmt.addSeconds(
                    -1 * correctedOffset / 1000
                );
        }

        return utcDateTime;

    } catch (Exception e) {

        System.debug(
            LoggingLevel.ERROR,
            'MRT3-38 Unable to parse Mastercard TxnDateTime: ' +
            value +
            ' Error: ' +
            e.getMessage()
        );

        return null;
    }
}
}