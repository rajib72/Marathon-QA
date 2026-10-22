/**
 * REST Resource class for Endurance Home Warranty Contract ingestion.
 *
 * PURPOSE:
 * This endpoint receives Home Warranty contract payloads from Endurance,
 * validates the payload, converts it into CSV format,
 * uploads it to the SFTP server,
 * and triggers Pentaho ingestion processing.
 *
 * This class is intentionally modeled after the existing
 * ContractIngestionService class used for Auto products,
 * but adapted for Home Warranty-specific payload structures.
 */
@RestResource(urlMapping='/ContractIngestionServiceHome/*')
global with sharing class ContractIngestionServiceHome {

    /*
     * Custom Metadata setting used for FTP configuration.
     */
    public static Pentaho_Contract_Ingestion_Home_Setting__mdt ingestionSetting;

    /*
     * Tracks sandbox vs production environment
     * so the correct FTP path can be used.
     */
    public static Boolean runningInASandbox;

    /*
     * Stores latest processed CSV headers and rows.
     * Extremely useful during debugging/log analysis.
     */
    public static List<String> latestHeaders { get; set; }
    public static List<Object> latestRows { get; set; }

    /**
     * Main REST endpoint.
     *
     * FLOW:
     * 1. Deserialize request
     * 2. Validate request
     * 3. Determine client
     * 4. Generate CSV
     * 5. Upload to SFTP
     * 6. Trigger Pentaho job
     * 7. Return response
     */
    @HttpPost
    global static void receiveHomeWarrantyContractRequest() {

        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;

        String responseBody = '';

        HomeWarrantyRequest requestBody;

        try {

            /*
             * Deserialize incoming JSON request body
             */
            requestBody = (HomeWarrantyRequest) JSON.deserialize(
                request.requestBody.toString(),
                HomeWarrantyRequest.class
            );

            /*
             * Validate request payload
             */
            if (!validateRequestBody(requestBody)) {

                responseBody =
                    '{"Status":"fail",' +
                    '"code":"400",' +
                    '"Message":"Bad Request. Please send request with correct data type.",' +
                    '"ContractNumber":"' + requestBody.ContractNumber + '"}';

                response.responseBody = Blob.valueOf(responseBody);
                return;
            }

            /*
             * Validate mandatory fields
             */
            if (!hasRequiredFields(requestBody)) {

                responseBody =
                    '{"Status":"fail",' +
                    '"code":"400",' +
                    '"Message":"Null value received for required field.",' +
                    '"ContractNumber":"' + requestBody.ContractNumber + '"}';

                response.responseBody = Blob.valueOf(responseBody);
                return;
            }

            /*
             * Detect current org type
             */
            runningInASandbox =
                [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;

            /*
             * Convert contract sale date into actual Date
             * for Dealer Program lookup logic.
             */
            Date contractSaleDate =
                parseMMDDYYYYDate(requestBody.ContractSaleDate);

            /*
             * Determine client using existing BRE logic.
             */
            String clientName =
                determineClientName(
                    requestBody.DealerProgramId,
                    contractSaleDate
                );

            /*
             * Only allow Endurance client requests.
             */
            if (clientName != 'Endurance') {

                responseBody =
                    '{"Status":"fail",' +
                    '"code":"400",' +
                    '"Message":"Invalid Dealer Program ID",' +
                    '"ContractNumber":"' + requestBody.ContractNumber + '"}';

                response.responseBody = Blob.valueOf(responseBody);
                return;
            }

            /*
             * Load FTP/SFTP configuration
             */
            ingestionSetting =
                Pentaho_Contract_Ingestion_Home_Setting__mdt.getInstance('Endurance');

            /*
             * Convert dates into Pentaho-required format.
             */
            normalizeDateFields(requestBody);

            /*
             * Create CSV and upload to SFTP
             */
            ingestHomeWarrantyContract(requestBody);

            /*
             * Trigger Pentaho Carte job
             */
            triggerPentahoJob();

            /*
             * Success response
             */
            responseBody =
                '{"Status":"success",' +
                '"code":"200",' +
                '"Message":"Request received successfully!",' +
                '"ContractNumber":"' + requestBody.ContractNumber + '"}';

        } catch (Exception e) {

            /*
             * Centralized exception logging.
             */
            QDX_LOG.error(
                'Error in ContractIngestionServiceHome: ' +
                e.getMessage() +
                ' | Line: ' + e.getLineNumber() +
                ' | Request Body: ' + request.requestBody.toString()
            );

            responseBody =
                '{"Status":"FAILURE",' +
                '"code":"400",' +
                '"Message":"Error occurred. ' + e.getMessage() + '",' +
                '"ContractNumber":"' +
                (requestBody != null ? requestBody.ContractNumber : '') +
                '"}';

        } finally {

            /*
             * Always publish logs.
             */
            QDX_LOG.publish();
        }

        response.responseBody = Blob.valueOf(responseBody);
    }

    /**
     * Validates required fields.
     */
    private static Boolean hasRequiredFields(HomeWarrantyRequest req) {

        return
            !String.isBlank(req.DealerProgramId) &&
            !String.isBlank(req.FirstName) &&
            !String.isBlank(req.LastName) &&
            !String.isBlank(req.MailingAddressLine1) &&
            !String.isBlank(req.MailingCity) &&
            !String.isBlank(req.MailingStateProvince) &&
            !String.isBlank(req.MailingPostalCode) &&
            !String.isBlank(req.ResidenceAddressLine1) &&
            !String.isBlank(req.ResidenceCity) &&
            !String.isBlank(req.ResidenceStateProvince) &&
            !String.isBlank(req.ResidencePostalCode) &&
            !String.isBlank(req.ResidenceType) &&
            !String.isBlank(req.YearBuilt) &&
            !String.isBlank(req.SquareFoot) &&
            !String.isBlank(req.NumberOfUnits) &&
            !String.isBlank(req.ContractTermMonths) &&
            !String.isBlank(req.RetailCost) &&
            !String.isBlank(req.DealerCost) &&
            !String.isBlank(req.Deductible) &&
            !String.isBlank(req.DownPaymentAmount) &&
            !String.isBlank(req.ContractSaleDate);
    }

    /**
     * Validates data types.
     */
    public static Boolean validateRequestBody(HomeWarrantyRequest req) {

        Boolean validDate =
            isValidDate(req.ContractSaleDate);

        return
            isNumeric(req.SquareFoot) &&
            isNumeric(req.NumberOfUnits) &&
            isNumeric(req.ContractTermMonths) &&
            isDecimal(req.RetailCost) &&
            isDecimal(req.DealerCost) &&
            isDecimal(req.Deductible) &&
            isDecimal(req.DownPaymentAmount) &&
            validDate;
    }

    /**
     * Converts date fields from:
     * MM-DD-YYYY
     * to:
     * MM/DD/YYYY
     *
     * Pentaho expects slash format.
     */
    private static void normalizeDateFields(HomeWarrantyRequest req) {

        req.ContractSaleDate =
            convertDateFormat(req.ContractSaleDate);

        req.FulfillmentDate =
            convertDateFormat(req.FulfillmentDate);

        req.PurchaseDate =
            convertDateFormat(req.PurchaseDate);

        req.FinanceFirstPmtDate =
            convertDateFormat(req.FinanceFirstPmtDate);
    }

    /**
     * Creates CSV and uploads to SFTP.
     */
    public static void ingestHomeWarrantyContract(
        HomeWarrantyRequest req
    ) {

        List<String> headers = new List<String>{
            'DealerProgramId',
            'SubDealerId',
            'ContractNumber',
            'FirstName',
            'LastName',
            'MiddleName',
            'Prefix',
            'Suffix',
            'Phone1',
            'Phone2',
            'Email',
            'Language',

            'MailingAddressLine1',
            'MailingAddressLine2',
            'MailingCity',
            'MailingStateProvince',
            'MailingPostalCode',

            'ResidenceAddressLine1',
            'ResidenceAddressLine2',
            'ResidenceCity',
            'ResidenceStateProvince',
            'ResidencePostalCode',

            'ResidenceType',
            'YearBuilt',
            'SquareFoot',
            'NumberOfUnits',

            'PurchasePrice',
            'PurchaseDate',

            'ContractTermMonths',
            'ValidationDays',

            'TaxAmount',
            'RetailCost',
            'DealerCost',
            'Deductible',
            'DownPaymentAmount',

            'LienHolderId',
            'FinancedTerm',
            'FinanceFirstPmtDate',
            'FinanceLedgerBalance',

            'ContractSaleDate',
            'FulfillmentDate',

            'Option1',
            'Option2',
            'Option3',
            'Option4',
            'Option5',
            'Option6',
            'Option7',
            'Option8',
            'Option9',
            'Option10'
        };

        /*
         * CSV row values in exact same order as headers.
         */
        List<Object> row = new List<Object>{
            req.DealerProgramId,
            req.SubDealerId,
            req.ContractNumber,
            req.FirstName,
            req.LastName,
            req.MiddleName,
            req.Prefix,
            req.Suffix,
            req.Phone1,
            req.Phone2,
            req.Email,
            req.Language,

            req.MailingAddressLine1,
            req.MailingAddressLine2,
            req.MailingCity,
            req.MailingStateProvince,
            req.MailingPostalCode,

            req.ResidenceAddressLine1,
            req.ResidenceAddressLine2,
            req.ResidenceCity,
            req.ResidenceStateProvince,
            req.ResidencePostalCode,

            req.ResidenceType,
            req.YearBuilt,
            req.SquareFoot,
            req.NumberOfUnits,

            req.PurchasePrice,
            req.PurchaseDate,

            req.ContractTermMonths,
            req.ValidationDays,

            req.TaxAmount,
            req.RetailCost,
            req.DealerCost,
            req.Deductible,
            req.DownPaymentAmount,

            req.LienHolderId,
            req.FinancedTerm,
            req.FinanceFirstPmtDate,
            req.FinanceLedgerBalance,

            req.ContractSaleDate,
            req.FulfillmentDate,

            req.Option1,
            req.Option2,
            req.Option3,
            req.Option4,
            req.Option5,
            req.Option6,
            req.Option7,
            req.Option8,
            req.Option9,
            req.Option10
        };

        List<List<Object>> rowList = new List<List<Object>>();
        rowList.add(row);

        latestHeaders = headers;
        latestRows = row;

        String csvBody =
            createCSV(headers, rowList);

        /*
         * Upload generated CSV to SFTP server.
         */
        callSFTPServerAPI(
            'callout:FTP_Server',
            'POST',
            JSON.serialize(
                EncodingUtil.base64Encode(
                    Blob.valueOf(csvBody)
                )
            ),
            null
        );
    }

    /**
     * Creates CSV content.
     */
    public static String createCSV(
        List<String> headers,
        List<List<Object>> rows
    ) {

        String csv =
            String.join(headers, ',') + '\n';

        Integer index = 0;

        for (List<Object> row : rows) {

            csv += String.join(row, ',');

            if (index < rows.size() - 1) {
                csv += '\n';
            }

            index++;
        }

        return csv;
    }

    /**
     * Determines client using BRE logic.
     *
     * Reused from existing Auto ingestion architecture.
     */
    public static String determineClientName(
        String dealerProgramId,
        Date contractSaleDate
    ) {

        Map<String, Object> parameter =
            new Map<String, Object>();

        parameter.put(
            'DealerProgramId',
            Integer.valueOf(dealerProgramId)
        );

        List<Map<String, Object>> parameters =
            new List<Map<String, Object>>();

        parameters.add(parameter);

        String jsonString =
            BREManager.runBRCallout(
                parameters,
                contractSaleDate,
                'Dealer_Code_Lookup',
                UtilityClass.BR_TYPE_DM,
                UtilityClass.IS_EXTERNAL_CALL
            );

        if (String.isBlank(jsonString)) {
            return '';
        }

        Map<String, Object> jsonMap =
            (Map<String, Object>)
            JSON.deserializeUntyped(jsonString);

        List<Object> outputs =
            (List<Object>) jsonMap.get('outputs');

        for (Object outputObj : outputs) {

            Map<String, Object> output =
                (Map<String, Object>) outputObj;

            List<Object> results =
                (List<Object>) output.get('results');

            for (Object resultObj : results) {

                Map<String, Object> result =
                    (Map<String, Object>) resultObj;

                if (
                    result.containsKey('name') &&
                    String.valueOf(result.get('name')) == 'Client'
                ) {
                    return String.valueOf(result.get('value'));
                }
            }
        }

        return '';
    }

    /**
     * Creates HTTP request and uploads file.
     */
    public static HttpResponse callSFTPServerAPI(
        String endpoint,
        String method,
        String body,
        String downloadPath
    ) {

        HttpRequest req =
            createHttpRequest(
                endpoint,
                method,
                body,
                downloadPath
            );

        Http http = new Http();

        return http.send(req);
    }

    /**
     * Constructs SFTP HTTP request.
     */
    @TestVisible
    private static HttpRequest createHttpRequest(
        String endpoint,
        String method,
        String body,
        String downloadPath
    ) {

        HttpRequest req = new HttpRequest();

        req.setEndpoint(endpoint);
        req.setMethod(method);

        req.setHeader('ftp-host', ingestionSetting.FTP_Host__c);
        req.setHeader('ftp-type', 'SFTP');
        req.setHeader('username', '{!$Credential.Username}');
        req.setHeader('password', '{!$Credential.Password}');
        req.setHeader('port', ingestionSetting.FTP_Port__c);
        req.setHeader('Content-Type', 'application/json');

        if (String.isNotBlank(body)) {

            String filePath =
                runningInASandbox
                ? ingestionSetting.FTP_File_Path_Sandbox__c
                : ingestionSetting.FTP_File_Path_Production__c;

            String fileName =
                'EnduranceHWIngest_' +
                Datetime.now().format('yyyy-MM-dd_HHmmssSSS') +
                '.csv';

            String requestBody =
                '[{' +
                '"path":"' + filePath + '",' +
                '"fileName":"' + fileName + '",' +
                '"body":' + body +
                '}]';

            req.setBody(requestBody);
        }

        req.setTimeout(120000);

        return req;
    }

    /**
     * Triggers Pentaho Carte job.
     */
    public static void triggerPentahoJob() {

        HttpRequest req = new HttpRequest();

        req.setMethod('GET');
        req.setEndpoint('callout:Carte_Connection');

        Http http = new Http();

        http.send(req);
    }

    /*
     * =========================
     * HELPER METHODS
     * =========================
     */

    private static Boolean isNumeric(String val) {

        try {
            Integer.valueOf(val);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isDecimal(String val) {

        try {
            Decimal.valueOf(val);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isValidDate(String dateVal) {

        return !String.isBlank(dateVal) && dateVal.contains('-');
    }

    @TestVisible
    private static String convertDateFormat(String dateVal) {

        if (String.isBlank(dateVal)) {
            return '';
        }

        List<String> parts = dateVal.split('-');

        if (parts.size() != 3) {
            return dateVal;
        }

        return parts[0] + '/' + parts[1] + '/' + parts[2];
    }

    @TestVisible
    private static Date parseMMDDYYYYDate(String dateVal) {

        if (String.isBlank(dateVal)) {
            return null;
        }

        List<String> parts = dateVal.split('-');

        if (parts.size() != 3) {
            return null;
        }

        return Date.valueOf(
            parts[2] + '-' +
            parts[0] + '-' +
            parts[1]
        );
    }

    /*
     * Custom exception class.
     */
    public class FileMakerException extends Exception {}

    /**
     * Request wrapper class.
     *
     * Represents incoming Home Warranty payload.
     */
    global class HomeWarrantyRequest {

        public String DealerProgramId;
        public String SubDealerId;
        public String ContractNumber;

        public String FirstName;
        public String LastName;
        public String MiddleName;
        public String Prefix;
        public String Suffix;

        public String Phone1;
        public String Phone2;
        public String Email;
        public String Language;

        public String MailingAddressLine1;
        public String MailingAddressLine2;
        public String MailingCity;
        public String MailingStateProvince;
        public String MailingPostalCode;

        public String ResidenceAddressLine1;
        public String ResidenceAddressLine2;
        public String ResidenceCity;
        public String ResidenceStateProvince;
        public String ResidencePostalCode;

        public String ResidenceType;
        public String YearBuilt;
        public String SquareFoot;
        public String NumberOfUnits;

        public String PurchasePrice;
        public String PurchaseDate;

        public String ContractTermMonths;
        public String ValidationDays;

        public String TaxAmount;
        public String RetailCost;
        public String DealerCost;
        public String Deductible;
        public String DownPaymentAmount;

        public String LienHolderId;
        public String FinancedTerm;
        public String FinanceFirstPmtDate;
        public String FinanceLedgerBalance;

        public String ContractSaleDate;
        public String FulfillmentDate;

        public String Option1;
        public String Option2;
        public String Option3;
        public String Option4;
        public String Option5;
        public String Option6;
        public String Option7;
        public String Option8;
        public String Option9;
        public String Option10;
    }
}