/**
 * REST Resource class for executing quote request for Rate Implementation Builder API
 * This class exposes a POST endpoint to quote request for Rate Implementation Builder API
 * and returns a processed response.
 */
@RestResource(UrlMapping='/TabularReportQuery/*')
global class TabularReportQueryService {
    
    public static Map<String, Map<String,String>> responseMap = new Map<String, Map<String,String>>(); 
    public static Boolean isCountRequired = false;
    public static Integer offSet = 0;
    
    @HttpPost
    global static String executeReportQuery() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        TabularReportQueryService.RateRequest requestObj;
        
        String responseStr = '';
        
        try {
            // Deserialize request body to QuoteService.EnduranceRequest object
            requestObj  = (TabularReportQueryService.RateRequest) JSON.deserialize( request.requestBody.toString(), TabularReportQueryService.RateRequest.class);
            if(requestObj.reportRequestId != null) {
                List<Report_Request__c> reportReqRecord = new List<Report_Request__c>([SELECT Id, Fields__c, Object__c, Filters__c, Group_By__c, Order_By__c FROM
                    Report_Request__c WHERE Id =: requestObj.reportRequestId]);
               
                if(reportReqRecord.size() > 0 && reportReqRecord[0].Fields__c != null && reportReqRecord[0].Object__c != null) {
                    String query = 'SELECT ' + reportReqRecord[0].Fields__c + ' FROM ' + reportReqRecord[0].Object__c;
                    if(reportReqRecord[0].Filters__c != null) {
                        query += ' WHERE ' + reportReqRecord[0].Filters__c;
                    }
                    if(reportReqRecord[0].Group_By__c != null) {
                        query += ' GROUP BY ' + reportReqRecord[0].Group_By__c;
                    }
                    if(reportReqRecord[0].Order_By__c != null) {
                        query += ' ORDER BY ' + reportReqRecord[0].Order_By__c;
                    }
                    List<sObject> records = Database.query(query);
                   
                    if(!records.isEmpty()) {
                        // Split the fields string into a list for easy iteration
                        List<String> fieldList = reportReqRecord[0].Fields__c.split(',');
                        String sObjectStr = reportReqRecord[0].Object__c;
                        String fieldHeaderStr = '';
                        
                        List<String> fieldValueStrList = new List<String>();
                        
                        // Iterate over the list of fields to fetch labels
                        for (String fieldName : fieldList) {
                            fieldHeaderStr += getFieldLabel(sObjectStr, fieldName.trim()) + '#';
                        }
                        fieldHeaderStr = fieldHeaderStr.substring(0, fieldHeaderStr.length() - 1);
                       
                        // Iterate over each record returned by the query
                        for (SObject record : records) {
                            String fieldValueStr = '';
                            /* Use a map to store field values for the current record
                            Map<String, String> fieldValues = new Map<String, String>();*/
                                                                                  
                            // Iterate over the list of fields
                            for (String fieldName : fieldList) {
                                // Get the value of the current field using SObject's get() method
                                Object fieldValue = record.get(fieldName.trim());
                                
                                // Convert the field value to a string and store it in the map
                                if (fieldValue != null) {
                                    //fieldValues.put(fieldName.trim(), String.valueOf(fieldValue));
                                    fieldValueStr += String.valueOf(fieldValue) + '#';
                                }
                            }
                            fieldValueStr = fieldValueStr.substring(0, fieldValueStr.length() - 1);
                            fieldValueStrList.add(fieldValueStr);
                        }
                        responseStr = fieldHeaderStr + ',' + String.join(fieldValueStrList, ',');
                    }
                }
            }
        } catch (Exception e) {
            //log error
  
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
            responseStr = generateErrorResponse(e.getMessage());
            
        } finally {
            // Ensure logs are published regardless of success or failure
            QDX_LOG.publish();
        }
        return responseStr;
    }
    
    public static String getFieldLabel(String sObjectName, String fieldApiName) {
        
        // 1. Get the SObject Describe Result
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(sObjectName).getDescribe();
        
        // 2. Get the Field Map
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        
        // Check if the field exists in the map
        if (fieldMap.containsKey(fieldApiName.toLowerCase())) {
            
            // 3. Get the Field Describe Result
            Schema.SObjectField fieldToken = fieldMap.get(fieldApiName.toLowerCase());
            
            // 4. Get the Field Label
            return fieldToken.getDescribe().getLabel();
        }
        
        // Return null or an appropriate message if the field is not found
        return null; 
    }
    
    //generates error response
    public static String generateErrorResponse(String errorMessage) {
        TabularReportQueryService.ErrorResponseGenerator errorResponseObj = new TabularReportQueryService.ErrorResponseGenerator();
        
        errorResponseObj.status = 400;
        errorResponseObj.error = errorMessage;
        return JSON.serialize(errorResponseObj);
    }
    
    //class that parses request body
    public class RateRequest {
        public String reportRequestId;
    }
    
    //class that generates error response
    public class ErrorResponseGenerator {
        public Integer status;
        public String error;
    }
}