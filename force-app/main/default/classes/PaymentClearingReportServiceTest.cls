@IsTest
private class PaymentClearingReportServiceTest {
    
    private class MastercardMock implements HttpCalloutMock {
        
        private String scenario;
        
        MastercardMock(String scenario) {
            this.scenario = scenario;
        }
        
        public HttpResponse respond(HttpRequest request) {
            
            HttpResponse response = new HttpResponse();
            
            String requestBody = request.getBody();
            
            /*
* HTTP 500
*/
            if (scenario == 'ERROR_500') {
                
                response.setStatusCode(500);
                response.setStatus('Internal Server Error');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<S:Body>' +
                    '<S:Fault>' +
                    '<faultcode>S:Server</faultcode>' +
                    '<faultstring>java.lang.NullPointerException</faultstring>' +
                    '</S:Fault>' +
                    '</S:Body>' +
                    '</S:Envelope>'
                );
                
                return response;
            }
            
            /*
* Missing SOAP Body
*/
            if (scenario == 'NO_BODY') {
                
                response.setStatusCode(200);
                response.setStatus('OK');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '</S:Envelope>'
                );
                
                return response;
            }
            
            /*
* CREATE - Missing CreateVCNClearingsReportResponse
*/
            if (scenario == 'CREATE_NO_RESPONSE') {
                
                response.setStatusCode(200);
                response.setStatus('OK');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope ' +
                    'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<soapenv:Body>' +
                    '<SomeOtherResponse/>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                
                return response;
            }
            
            /*
* CREATE - Response exists but ReportId is blank
*/
            if (scenario == 'CREATE_NO_REPORT_ID') {
                
                response.setStatusCode(200);
                response.setStatus('OK');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope ' +
                    'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
                    'xmlns:ser="http://mastercard.com/sd/pc/service">' +
                    '<soapenv:Header/>' +
                    '<soapenv:Body>' +
                    '<ser:CreateVCNClearingsReportResponse>' +
                    '</ser:CreateVCNClearingsReportResponse>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                
                return response;
            }
            
            /*
* GET - Missing GetVCNClearingsReportResponse
*/
            if (scenario == 'GET_NO_RESPONSE') {
                
                response.setStatusCode(200);
                response.setStatus('OK');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<S:Body>' +
                    '<SomeOtherResponse/>' +
                    '</S:Body>' +
                    '</S:Envelope>'
                );
                
                return response;
            }
            
            /*
* Normal CREATE response
*/
            if (requestBody.contains('CreateVCNClearingsReportRequest')) {
                
                response.setStatusCode(200);
                response.setStatus('OK');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope ' +
                    'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
                    'xmlns:ser="http://mastercard.com/sd/pc/service">' +
                    '<soapenv:Header/>' +
                    '<soapenv:Body>' +
                    '<ser:CreateVCNClearingsReportResponse ' +
                    'ReportId="205552961">' +
                    '</ser:CreateVCNClearingsReportResponse>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                
                return response;
            }
            
            /*
* Normal GET response
*/
            if (requestBody.contains('GetVCNClearingsReport')) {
                
                response.setStatusCode(200);
                response.setStatus('OK');
                
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<S:Body>' +
                    '<GetVCNClearingsReportResponse ' +
                    'From="0" ' +
                    'HasMore="false" ' +
                    'To="1" ' +
                    'xmlns="http://mastercard.com/sd/pc/service">' +
                    
                    '<ReportStatus>Completed</ReportStatus>' +
                    
                    '<Transactions ' +
                    'PurchaseRequestId="29211109" ' +
                    'ApprovalCode="ABC123" ' +
                    'TxnDateTime="2026-09-10T10:30:00.000Z" ' +
                    'SettlementDate="2026-09-10T10:45:00.000Z" ' +
                    'MerchantName="TEST MERCHANT" ' +
                    'MerchantAmount="100.00" ' +
                    'VirtualCardNumber="XXXX-XXXX-XXXX-1234"' +
                    '/>' +
                    
                    '<ErrorMessage xsi:nil="true" ' +
                    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>' +
                    
                    '</GetVCNClearingsReportResponse>' +
                    '</S:Body>' +
                    '</S:Envelope>'
                );
                
                return response;
            }
            
            /*
* Default response
*/
            response.setStatusCode(400);
            response.setStatus('Bad Request');
            response.setBody('Unexpected request');
            
            return response;
        }
    }
    
    
    @IsTest
    static void testCreateClearingReport() {
        
        Account acc = new Account(
            Name = 'MRT3-38 Test Account'
        );
        
        insert acc;
        
        Payment__c payment = new Payment__c(
            Account__c = acc.Id,
            BOK_Purchase_Request_Id__c = '29211109',
            BOK_VCN_Id__c = '28274905',
            Credit_Card_Number__c = '5561206756658202'
        );
        
        insert payment;
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('SUCCESS')
        );
        
        Test.startTest();
        
        String reportId =
            PaymentClearingReportService.createClearingReport(
                payment.Id
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 ReportId: ' + reportId
        );
    }
    
    
    @IsTest
    static void testGetClearingReport() {
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('SUCCESS')
        );
        
        Test.startTest();
        
        PaymentClearingReportService.getClearingReport(
            '205552961'
        );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Get Clearing Report completed.'
        );
    }
    
    
    @IsTest
    static void testGetClearingReportHttpError() {
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('ERROR_500')
        );
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.getClearingReport(
                '205552961'
            );
            
        } catch (CalloutException e) {
            
            System.debug(
                'Expected HTTP 500: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testGetClearingReportBlankReportId() {
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.getClearingReport(
                ''
            );
            
        } catch (IllegalArgumentException e) {
            
            System.debug(
                'Expected blank Report Id error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testCreateClearingReportWithoutCreditCard() {
        
        Account acc = new Account(
            Name = 'MRT3-38 Test Account'
        );
        
        insert acc;
        
        Payment__c payment = new Payment__c(
            Account__c = acc.Id,
            BOK_Purchase_Request_Id__c = '29211109',
            BOK_VCN_Id__c = '28274905'
        );
        
        insert payment;
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.createClearingReport(
                payment.Id
            );
            
        } catch (AuraHandledException e) {
            
            System.debug(
                'Expected missing Credit Card error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testCreateClearingReportNoSoapBody() {
        
        Account acc = new Account(
            Name = 'MRT3-38 No Body Account'
        );
        
        insert acc;
        
        Payment__c payment = new Payment__c(
            Account__c = acc.Id,
            BOK_Purchase_Request_Id__c = '29211109',
            BOK_VCN_Id__c = '28274905',
            Credit_Card_Number__c = '5561206756658202'
        );
        
        insert payment;
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('NO_BODY')
        );
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.createClearingReport(
                payment.Id
            );
            
        } catch (CalloutException e) {
            
            System.debug(
                'Expected SOAP Body error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testCreateClearingReportNoResponseNode() {
        
        Account acc = new Account(
            Name = 'MRT3-38 No Response Account'
        );
        
        insert acc;
        
        Payment__c payment = new Payment__c(
            Account__c = acc.Id,
            BOK_Purchase_Request_Id__c = '29211109',
            BOK_VCN_Id__c = '28274905',
            Credit_Card_Number__c = '5561206756658202'
        );
        
        insert payment;
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('CREATE_NO_RESPONSE')
        );
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.createClearingReport(
                payment.Id
            );
            
        } catch (CalloutException e) {
            
            System.debug(
                'Expected missing Create response error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testCreateClearingReportNoReportId() {
        
        Account acc = new Account(
            Name = 'MRT3-38 No Report ID Account'
        );
        
        insert acc;
        
        Payment__c payment = new Payment__c(
            Account__c = acc.Id,
            BOK_Purchase_Request_Id__c = '29211109',
            BOK_VCN_Id__c = '28274905',
            Credit_Card_Number__c = '5561206756658202'
        );
        
        insert payment;
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('CREATE_NO_REPORT_ID')
        );
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.createClearingReport(
                payment.Id
            );
            
        } catch (CalloutException e) {
            
            System.debug(
                'Expected missing ReportId error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testGetClearingReportNoSoapBody() {
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('NO_BODY')
        );
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.getClearingReport(
                '205552961'
            );
            
        } catch (CalloutException e) {
            
            System.debug(
                'Expected SOAP Body error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
    
    
    @IsTest
    static void testGetClearingReportNoResponseNode() {
        
        Test.setMock(
            HttpCalloutMock.class,
            new MastercardMock('GET_NO_RESPONSE')
        );
        
        Test.startTest();
        
        try {
            
            PaymentClearingReportService.getClearingReport(
                '205552961'
            );
            
        } catch (CalloutException e) {
            
            System.debug(
                'Expected missing Get response error: ' +
                e.getMessage()
            );
        }
        
        Test.stopTest();
    }
}