@IsTest
private class ContractIngestionServiceHomeTest {

    /*
     * Multi-purpose mock that handles:
     * 1. BRE callout
     * 2. FTP callout
     * 3. Pentaho callout
     */
    private class HomeWarrantyMultiCalloutMock
        implements HttpCalloutMock {

        private Boolean returnEndurance;

        HomeWarrantyMultiCalloutMock(Boolean returnEndurance) {
            this.returnEndurance = returnEndurance;
        }

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();

            /*
             * BRE Callout
             */
            if(endpoint != null &&
               endpoint.contains('business-rules')) {

                if(returnEndurance) {

                    res.setBody(
                        '{"outputs":[{"results":[' +
                        '{"name":"Client","value":"Endurance"}' +
                        ']}]}'
                    );

                } else {

                    res.setBody(
                        '{"outputs":[{"results":[' +
                        '{"name":"Client","value":"Consumers Choice"}' +
                        ']}]}'
                    );
                }

                return res;
            }

            /*
             * FTP Upload
             */
            if(endpoint != null &&
               endpoint.contains('FTP_Server')) {

                res.setBody('{"success":true}');
                return res;
            }

            /*
             * Pentaho Trigger
             */
            if(endpoint != null &&
               endpoint.contains('Carte_Connection')) {

                res.setBody('OK');
                return res;
            }

            res.setBody('{}');
            return res;
        }
    }

    /*
     * Creates a valid Home Warranty payload.
     */
    private static String getValidPayload() {

        return
        '{'+
        '"DealerProgramId":"321",'+
        '"SubDealerId":"HOMEQA001",'+
        '"ContractNumber":"HOME-TEST-0001",'+
        '"FirstName":"Tony",'+
        '"LastName":"Stark",'+
        '"MiddleName":"Edward",'+
        '"Prefix":"Mr.",'+
        '"Suffix":"Jr.",'+
        '"Phone1":"9876543210",'+
        '"Phone2":"9123456780",'+
        '"Email":"tony@test.com",'+
        '"Language":"en",'+
        '"MailingAddressLine1":"Address1",'+
        '"MailingAddressLine2":"Address2",'+
        '"MailingCity":"Malibu",'+
        '"MailingStateProvince":"CA",'+
        '"MailingPostalCode":"90265",'+
        '"ResidenceAddressLine1":"Address1",'+
        '"ResidenceAddressLine2":"Address2",'+
        '"ResidenceCity":"Malibu",'+
        '"ResidenceStateProvince":"CA",'+
        '"ResidencePostalCode":"90265",'+
        '"ResidenceType":"Single Family",'+
        '"YearBuilt":"2018",'+
        '"SquareFoot":"4500",'+
        '"NumberOfUnits":"1",'+
        '"PurchasePrice":"1500000.00",'+
        '"PurchaseDate":"06-15-2026",'+
        '"ContractTermMonths":"36",'+
        '"ValidationDays":"30",'+
        '"TaxAmount":"250.00",'+
        '"RetailCost":"2499.99",'+
        '"DealerCost":"1800.50",'+
        '"Deductible":"100.00",'+
        '"DownPaymentAmount":"299.99",'+
        '"LienHolderId":"LIEN001",'+
        '"FinancedTerm":"36",'+
        '"FinanceFirstPmtDate":"07-01-2026",'+
        '"FinanceLedgerBalance":"12000.00",'+
        '"ContractSaleDate":"05-27-2026",'+
        '"FulfillmentDate":"05-28-2026",'+
        '"Option1":"Pool",'+
        '"Option10":"Ice Maker"'+
        '}';
    }

    @IsTest
    static void testSuccessFlow() {

        Test.setMock(
            HttpCalloutMock.class,
            new HomeWarrantyMultiCalloutMock(true)
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI =
            '/services/apexrest/ContractIngestionServiceHome';

        req.httpMethod = 'POST';
        req.requestBody =
            Blob.valueOf(getValidPayload());

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();

        ContractIngestionServiceHome.receiveHomeWarrantyContractRequest();

        Test.stopTest();

        String body =
            res.responseBody.toString();

        System.assert(
            body.contains('"Status":"success"')
        );

        System.assertNotEquals(
            null,
            ContractIngestionServiceHome.latestHeaders
        );

        System.assertNotEquals(
            null,
            ContractIngestionServiceHome.latestRows
        );
    }

    @IsTest
    static void testInvalidDatatype() {

        String payload =
            getValidPayload()
            .replace('"SquareFoot":"4500"',
                     '"SquareFoot":"ABC"');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestBody = Blob.valueOf(payload);

        RestContext.request = req;
        RestContext.response = res;

        ContractIngestionServiceHome.receiveHomeWarrantyContractRequest();

        System.assert(
            res.responseBody.toString()
            .contains('Bad Request')
        );
    }

    @IsTest
    static void testMissingRequiredField() {

        String payload =
            getValidPayload()
            .replace('"FirstName":"Tony"',
                     '"FirstName":""');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestBody = Blob.valueOf(payload);

        RestContext.request = req;
        RestContext.response = res;

        ContractIngestionServiceHome.receiveHomeWarrantyContractRequest();

        System.assert(
            res.responseBody.toString()
            .contains('Null value received')
        );
    }

    @IsTest
    static void testInvalidDealerProgram() {

        Test.setMock(
            HttpCalloutMock.class,
            new HomeWarrantyMultiCalloutMock(false)
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestBody =
            Blob.valueOf(getValidPayload());

        RestContext.request = req;
        RestContext.response = res;

        ContractIngestionServiceHome.receiveHomeWarrantyContractRequest();

        System.assert(
            res.responseBody.toString()
            .contains('Invalid Dealer Program ID')
        );
    }

    @IsTest
    static void testCreateCSV() {

        List<String> headers =
            new List<String>{'A','B'};

        List<List<Object>> rows =
            new List<List<Object>>{
                new List<Object>{'1','2'}
            };

        String csv =
            ContractIngestionServiceHome.createCSV(headers, rows);

        System.assertEquals(
            'A,B\n1,2',
            csv
        );
    }

    @IsTest
    static void testDetermineClientName() {

        Test.setMock(
            HttpCalloutMock.class,
            new HomeWarrantyMultiCalloutMock(true)
        );

        String client =
            ContractIngestionServiceHome.determineClientName(
                    '321',
                    Date.today()
                );

        System.assertEquals(
            'Endurance',
            client
        );
    }

    @IsTest
    static void testConvertDateFormat() {

        System.assertEquals(
            '06/15/2026',
            ContractIngestionServiceHome.convertDateFormat(
                    '06-15-2026'
                )
        );
    }

    @IsTest
    static void testParseDate() {

        System.assertEquals(
            Date.newInstance(2026,6,15),
            ContractIngestionServiceHome.parseMMDDYYYYDate(
                    '06-15-2026'
                )
        );
    }

    @IsTest
    static void testCreateHttpRequest() {

        ContractIngestionServiceHome.ingestionSetting =
            Pentaho_Contract_Ingestion_Home_Setting__mdt.getInstance('Endurance');

        ContractIngestionServiceHome.runningInASandbox =
            true;

        HttpRequest req =
            ContractIngestionServiceHome.createHttpRequest(
                    'callout:FTP_Server',
                    'POST',
                    '"TEST"',
                    null
                );

        System.assertEquals(
            'POST',
            req.getMethod()
        );

        System.assert(
            req.getBody().contains('EnduranceHWIngest_')
        );
    }

    @IsTest
    static void testTriggerPentahoJob() {

        Test.setMock(
            HttpCalloutMock.class,
            new HomeWarrantyMultiCalloutMock(true)
        );

        Test.startTest();

        ContractIngestionServiceHome.triggerPentahoJob();

        Test.stopTest();

        System.assert(true);
    }
}