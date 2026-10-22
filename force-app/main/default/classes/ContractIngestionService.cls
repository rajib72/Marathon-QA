/**
* REST Resource class for executing business rules on Insurance Policies.
* This class exposes a POST endpoint to process InsurancePolicy objects
* and returns a processed response.
*/
@RestResource(UrlMapping='/ContractIngestionService/*')
global class ContractIngestionService {
    public static Pentaho_Contract_Ingestion_Setting__mdt ingestionSetting;
    public static Boolean runningInASandbox;
    //added two list to get the Debug log
    public static List<String> latestHeaders { get; set; }
    public static List<Object> latestRows { get; set; }
    /**
* HTTP Post method that processes the Endurance request.
*/
    @HttpPost
    global static Void receiveContractRequest() {
        String returnBody = '';
        // Initialize response objects
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        ContractIngestionService.EnduranceRequest requestBody;
        try {
            requestBody  = (ContractIngestionService.EnduranceRequest) JSON.deserialize(
                request.requestBody.toString(), ContractIngestionService.EnduranceRequest.class
            );
            if(validateRequestBody(requestBody)) {
                if(!String.isEmpty(requestBody.DealerProgramId) && !String.isEmpty(requestBody.FirstName) && !String.isEmpty(requestBody.LastName) &&
                   !String.isEmpty(requestBody.AddressLine1) && !String.isEmpty(requestBody.City) && !String.isEmpty(requestBody.StateProvAbbrev) &&
                   !String.isEmpty(requestBody.PostalCode) && !String.isEmpty(requestBody.VIN) && !String.isEmpty(requestBody.CurrentOdometer) &&
                   !String.isEmpty(requestBody.UpToorAddOn) && !String.isEmpty(requestBody.TermMonths) && !String.isEmpty(requestBody.TermMiles) &&
                   !String.isEmpty(requestBody.RateClass) && !String.isEmpty(requestBody.RetailCost) && !String.isEmpty(requestBody.NetAdminCost) &&
                   !String.isEmpty(requestBody.Deductible) && !String.isEmpty(requestBody.DownPaymentAmount) && !String.isEmpty(requestBody.ContractSaleDate)) {
                       
                       runningInASandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
                       List<String> dateString = (requestBody.ContractSaleDate != null || requestBody.ContractSaleDate != '') ? requestBody.ContractSaleDate.split('-') : new List<String>();
                       Date contractSaleDate = dateString.size() > 0 ? Date.valueOf(dateString[2] + '-' + dateString[0] + '-' + dateString[1]) : null;
                       String clientName = determineClientName(requestBody.DealerProgramId, contractSaleDate);
                       requestBody.ContractSaleDate = dateString.size() > 0 ? dateString[0] + '/' + dateString[1] + '/' + dateString[2] : '';
                       if(!String.isEmpty(requestBody.FulfillmentDate)){
                           List<String> fulfillmentdateString = (requestBody.FulfillmentDate != null || requestBody.FulfillmentDate != '') ? requestBody.FulfillmentDate.split('-') : new List<String>();
                           requestBody.FulfillmentDate = fulfillmentdateString.size() > 0 ? fulfillmentdateString[0] + '/' + fulfillmentdateString[1] + '/' + fulfillmentdateString[2] : '';
                       }
                       
                       if(clientName == 'Endurance') {
                           ingestionSetting = Pentaho_Contract_Ingestion_Setting__mdt.getInstance('Endurance');
                           ingestEnduranceContract(requestBody);
                           triggerPentahoJob();
                           returnBody = '{"Status":"success", "code": "200", "Message":"Request received successfully!", "ContractNumber": "' + requestBody.ContractNumber + '"}';
                       } else {
                           returnBody = '{"Status":"fail", "code": "400", "Message":"Invalid Dealer Program ID", "ContractNumber": "' + requestBody.ContractNumber + '"}';
                       }
                   } else {
                       returnBody = '{"Status":"fail", "code": "400","Message":"Null value received for required field.", "ContractNumber": "' + requestBody.ContractNumber + '"}';
                   }
            } else {
                returnBody = '{"Status":"fail", "code": "400","Message":"Bad Request. Please send request with correct data type.", "ContractNumber": "' + requestBody.ContractNumber + '"}';
            }
        } catch (Exception e) {
            // Log and handle errors
            QDX_LOG.error('Error executing Contract Ingestion Service: ' + e.getMessage() + ' | Request Body: ' + request.requestBody.toString() + ' | line: ' + e.getLineNumber()+'Rows value'+JSON.serializePretty(latestRows));
            returnBody = '{"Status":"FAILURE", "code": "400","Message":"Error occurred. ' + e.getMessage() + '", "ContractNumber": "' + requestBody.ContractNumber + '"}';
            System.debug('Rows: ' + latestRows);
        } finally {
            // Ensure logs are published regardless of success or failure
            QDX_LOG.publish();
        }
        response.responseBody = Blob.valueOf(returnBody);
    }
    
    /**
@description validates request body for correct data type
*/
    public static Boolean validateRequestBody(ContractIngestionService.EnduranceRequest requestBody) {
        Boolean isValidRequest = true;
        Boolean isValidContractSaleDate = (requestBody.ContractSaleDate == null || requestBody.ContractSaleDate == '' || (requestBody.ContractSaleDate != null && !requestBody.ContractSaleDate.contains('-'))) ? false : true;
        
        if(!requestBody.CurrentOdometer.isNumeric() || !requestBody.TermMonths.isNumeric() 
           || !requestBody.TermMiles.isNumeric()  || !isDecimal(requestBody.RetailCost) 
           || !isDecimal(requestBody.NetAdminCost)  || !isDecimal(requestBody.Deductible) 
           || !isDecimal(requestBody.DownPaymentAmount)  || !isValidContractSaleDate) {
               isValidRequest = false;
           }
        return isValidRequest;
    }
    
    /**
@description checks if string is a decimal number (including an integer) or not
*/
    public static Boolean isDecimal(String str){
        Boolean returnValue;
        try{
            Decimal.valueOf(str);
            returnValue = TRUE; 
        } catch (Exception e) {
            returnValue = FALSE;
        }
        return returnValue;
    }
    
    /**
@description creating a csv file from request body and uploading to SFTP server
*/
    public static Void ingestEnduranceContract(ContractIngestionService.EnduranceRequest requestBody) {
        
        // ADD — reformat optional date fields the same way ContractSaleDate is handled
        if (!String.isEmpty(requestBody.VehiclePurchaseDate)) {
            List<String> d = requestBody.VehiclePurchaseDate.split('-');
            requestBody.VehiclePurchaseDate = d.size() > 0 ? d[0] + '/' + d[1] + '/' + d[2] : '';
        }
        if (!String.isEmpty(requestBody.VehicleLastServiceDate)) {
            List<String> d = requestBody.VehicleLastServiceDate.split('-');
            requestBody.VehicleLastServiceDate = d.size() > 0 ? d[0] + '/' + d[1] + '/' + d[2] : '';
        }
        if (!String.isEmpty(requestBody.FinanceFirstPmtDate)) {
            List<String> d = requestBody.FinanceFirstPmtDate.split('-');
            requestBody.FinanceFirstPmtDate = d.size() > 0 ? d[0] + '/' + d[1] + '/' + d[2] : '';
        }
        
        List<List<Object>> rowList = new List<List<Object>>();
        List<String> headers = new List<String>{'DealerProgramId', 'SubDealerId', 'ContractNumber', 'FirstName', 'LastName', 'MiddleName', 'Prefix', 'Suffix', 'Phone1', 'Phone2', 'Email', 'Language', 'AddressLine1', 'AddressLine2', 'City', 'StateProvAbbrev', 'PostalCode', 'VIN', 'CurrentOdometer', 'VehiclePurchasePrice', 'VehiclePurchaseDate', 'VehicleLastServiceDate', 'UpToorAddOn', 'TermMonths', 'TermMiles', 'RateClass', 'WaitingPeriodDays', 'WaitingPeriodMiles', 'TaxAmount', 'RetailCost', 'NetAdminCost', 'Deductible', 'DownPaymentAmount', 'LienHolderId', 'FinancedTerm', 'FinanceFirstPmtDate', 'FinanceLedgerBalance', 'ContractSaleDate', 'FulfillmentDate', 'OptionName1', 'OptionName2', 'OptionName3', 'OptionName4', 'OptionName5'};
            List<Object> rows = new List<Object>{requestBody.DealerProgramId, '', requestBody.ContractNumber, requestBody.FirstName, requestBody.LastName, requestBody.MiddleName,  requestBody.Prefix, requestBody.Suffix,  requestBody.Phone1, requestBody.Phone2, requestBody.Email, requestBody.Language, requestBody.AddressLine1, requestBody.AddressLine2, requestBody.City, requestBody.StateProvAbbrev, requestBody.PostalCode, requestBody.VIN, requestBody.CurrentOdometer, requestBody.VehiclePurchasePrice, requestBody.VehiclePurchaseDate, requestBody.VehicleLastServiceDate, requestBody.UpToorAddOn, requestBody.TermMonths, requestBody.TermMiles, requestBody.RateClass, requestBody.WaitingPeriodDays, requestBody.WaitingPeriodMiles, requestBody.TaxAmount, requestBody.RetailCost, requestBody.NetAdminCost, requestBody.Deductible, requestBody.DownPaymentAmount, requestBody.LienHolderId, requestBody.FinancedTerm, requestBody.FinanceFirstPmtDate, requestBody.FinanceLedgerBalance, requestBody.ContractSaleDate, requestBody.FulfillmentDate, requestBody.Option1, requestBody.Option2, requestBody.Option3, requestBody.Option4, requestBody.Option5};
                rowList.add(rows);
        //assigning to the public list
        latestHeaders = new List<String>(headers);
        latestRows    = new List<Object>(rows);
        String fileBody = createCSV(headers, rowList, '');
        HttpResponse res = callSFTPServerAPI('callout:FTP_Server', 'POST', JSON.serialize(EncodingUtil.base64Encode(Blob.valueOf(fileBody))), null);
    }
    
    /**
@description fetches the client name from DM based on the dealer program id
*/
    public static String determineClientName(String dealerProgramId, DateTime contractSaleDate) {
        Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
        String clientName = '';
        parameter.put('DealerProgramId', Integer.valueOf(dealerProgramId));
        parameters.add(parameter);
        String jsonString = BREManager.runBRCallout(parameters,contractSaleDate.date(),'Dealer_Code_Lookup', UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL);
        // Parse the JSON string
        if(String.isNotBlank(jsonString)){
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
            // Extract the outputs list
            List<Object> outputs = (List<Object>) jsonMap.get('outputs');
            if (outputs != null && !outputs.isEmpty()) {
                // Get the first output
                Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                if (firstOutput != null) {
                    // Get the results list
                    List<Object> results = (List<Object>) firstOutput.get('results');
                    for (Object resultObj : results) {
                        Map<String, Object> result = (Map<String, Object>) resultObj;
                        if (result != null && !result.isEmpty()) {
                            if(result.containsKey('name') && result.get('name').equals('Client')){
                                // Extract and validate 'Client' output
                                clientName = (String) result.get('value');
                            }
                        }
                    }
                }
            }
        }
        return clientName;
    }
    
    /**
@description create a CSV file from a list of Object Lists each Object List is a row in a list of lists. Each Object is a cell in the CSV
*/
    public static String createCSV(List<String> csvHeaders, List<List<Object>> csvRowList, String title){
        String headerRow = String.join(csvHeaders,',') + '\n';
        String concantenatedStr = headerRow;
        Integer i = 0;
        Integer rowListSize = csvRowList.size();
        for(List<Object> row :csvRowList){
            if(csvHeaders.size() != row.size()) throw new FileMakerException('The row size needs to be the same size as the header');//check the row list is the same size as the header list
            concantenatedStr += String.join(row, ',');
            i++;
            if(i != rowListSize) concantenatedStr += '\n';//add new line
        }
        title += '.csv';
        return concantenatedStr;
    }
    
    public static HttpResponse callSFTPServerAPI(String endpoint, String http_method, String http_body, String downloadPath){
        HttpRequest req = createHttpRequest(endpoint, http_method, http_body, downloadPath);
        Http httpreq = new Http();
        return httpreq.send(req);
    }
    
    private static HttpRequest createHttpRequest(String endpoint, String method, String body, String downloadPath){
        HttpRequest req = new HttpRequest();
        req.setHeader('ftp-host', ingestionSetting.FTP_Host__c);
        req.setHeader('ftp-type', 'SFTP');
        req.setHeader('username', '{!$Credential.Username}');
        req.setHeader('password', '{!$Credential.Password}');
        req.setHeader('port', ingestionSetting.FTP_Port__c);
        req.setHeader('Content-Type', 'application/json');
        req.setEndpoint(endpoint);
        req.setMethod(method);
        if(String.isNotBlank(body) && String.isNotEmpty(body)){
            String filePath = runningInASandbox == false ? ingestionSetting.FTP_File_Path_Production__c : ingestionSetting.FTP_File_Path_Sandbox__c;
            // Set body
            String fileName = 'EnduranceIngest_' + DateTime.Now().format('yyyy-MM-dd_HHmmssSSS') + '.csv';
            String reqBody = '[{"path":"' + filePath + '", "fileName":"' + fileName + '", "body": ' + body + ' }]';
            req.setBody(reqBody);
        }
        if(String.isNotBlank(downloadPath) && String.isNotEmpty(downloadPath)) {
            req.setHeader('path', downloadPath);
        }
        req.setTimeout(120000);
        return req;
    }
    
    public static void triggerPentahoJob() {
        // Instantiate HTTP request and response objects
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        // Set HTTP method (e.g., POST or GET based on your Pentaho job setup)
        request.setMethod('GET');
        
        // Set the endpoint URL for the Pentaho job
        request.setEndpoint('callout:Carte_Connection');
        
        // Send the HTTP request and get the response
        HttpResponse response = http.send(request);
    }
    
    public class FileMakerException extends Exception{}
    
    public class EnduranceRequest{
        public String DealerProgramId;
        public String ContractNumber;
        public String FirstName;
        public String LastName;
        
        //  ADD THESE — previously missing, so JSON.deserialize() was discarding them
        public String MiddleName;
        public String Prefix;
        public String Suffix;
        public String Phone1;
        public String Phone2;
        public String Email;
        public String Language;
        
        public String AddressLine1;
        public String AddressLine2;  //  Also add this for completeness
        public String City;
        public String StateProvAbbrev;
        public String PostalCode;
        public String VIN;
        public String Make;
        public String Model;
        public String Trim;
        public String Option1;
        public String Option2;
        public String Option3;
        public String Option4;
        public String Option5;
        public String CurrentOdometer;
        
        //  ADD THESE
        public String VehiclePurchasePrice;
        public String VehiclePurchaseDate;
        public String VehicleLastServiceDate;
        
        public String UpToorAddOn;
        public String TermMonths;
        public String TermMiles;
        public String RateClass;
        public String RetailCost;
        public String NetAdminCost;
        public String Deductible;
        public String DownPaymentAmount;
        public String ContractSaleDate;
        public String FulfillmentDate;
        //added field for null waiting-period-days and waiting-period-miles issue in pentaho
        public String WaitingPeriodDays;
        public String WaitingPeriodMiles;
        public String LienHolderId;
        
        public String TaxAmount;
        public String FinancedTerm;
        public String FinanceFirstPmtDate;
        public String FinanceLedgerBalance;
        
        public EnduranceRequest parse(String json){
            return (EnduranceRequest) System.JSON.deserialize(json, EnduranceRequest.class);
        }
    }
}