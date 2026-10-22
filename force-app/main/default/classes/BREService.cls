/**
* @description		 : REST Resource class for executing business rules on Insurance Policies.
* 						This class exposes a POST endpoint to process InsurancePolicy objects
* 						and returns a processed response.
* @author            : Sohel Azmi
* @group             :
* @last modified on  : 06-12-2026
* @last modified by  : Sohel Azmi
**/

@RestResource(UrlMapping='/BusinessRuleService/*')
global class BREService {
	
    /**
     * Inner class to represent the JSON response structure.
     */
    public class ApiResponse {
        // Old Code: START
        // public Map<String, Object> response = new Map<String, Object>();
        // Old Code: END
        
        // ADDED BY: SOHEL : BRE CALLOUT REDUCTION
        public List<Map<String, Object>> response = new List<Map<String, Object>>();
        // ADDED BY: SOHEL : BRE CALLOUT REDUCTION
    }
    
    /**
     * Executes business rules for the provided InsurancePolicy.
     * This method is invoked via an HTTP POST request.
     *
     * Endpoint: /BusinessRuleService/executeBusinessRules
     *
     * Request Body: JSON representation of an InsurancePolicy object.
     * Response Body: JSON response with processed data or error message.
     */
    @HttpPost
    global static void executeBusinessRules() {
        // Initialize response objects
        ApiResponse apiResponse = new ApiResponse();
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        
		// Begin Andy added: to print the request
        // String jsonString = JSON.serializePretty(request.requestBody.toString());
        String jsonString = request.requestBody.toString();
        System.debug(jsonString);
        
        // End Andy added:

        try {
            // Andy added: to process list of insurance policies in request payload 
            List<InsurancePolicy> insurancePolicyList = (List<InsurancePolicy>) JSON.deserialize(
                request.requestBody.toString(), List<InsurancePolicy>.class);

/*            
            // Deserialize request body to InsurancePolicy object
            InsurancePolicy insurancePolicy  = (InsurancePolicy) JSON.deserialize(
                request.requestBody.toString(), InsurancePolicy.class
            );


            // Prepare list for processing
            List<InsurancePolicy> insurancePolicyList = new List<InsurancePolicy>{ insurancePolicy };

            // Execute business rules and get processed results
            // List<InsurancePolicy> processedPolicies = BREServiceHandler.executeBusinessRule(insurancePolicyList);
*/            
            // New Bulkified Method Call - Sohel Azmi
            List<InsurancePolicy> processedPolicies = BREServiceHandlerBulkified.executeBusinessRule(insurancePolicyList);

            if (!processedPolicies.isEmpty()) {
                // Extract and serialize the first contract's response
                // Old Code: START
                // apiResponse.response = (Map<String, Object>) JSON.deserializeUntyped(
                //     JSON.serialize(processedPolicies[0])
                // );
                // Old Code: END

                // ADDED BY: SOHEL : BRE CALLOUT REDUCTION
                for(InsurancePolicy pp: processedPolicies) {
                     Map<String, Object> tempMap = new Map<String, Object>();
                     tempMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(pp));
                     apiResponse.response.add(tempMap);
                }
                
                System.debug('@@@DEBUG:: ' + JSON.serialize(apiResponse.response));
                
                // response.responseBody = Blob.valueOf(JSON.serialize(processedPolicies));
                // ADDED BY: SOHEL : BRE CALLOUT REDUCTION
            } else {
                QDX_LOG.debug('No contracts returned after processing.');
            }

            // Set successful response
            response.responseBody = Blob.valueOf(JSON.serialize(apiResponse.response));
            response.statusCode = 200;
            response.addHeader('Content-Type', 'application/json');

        } catch (Exception e) {
            // Log and handle errors
            QDX_LOG.error('Error executing business rules: ' + e.getMessage() + ' | Request Body: ' + request.requestBody.toString());
            
            // Old Code: START
            // Set error response
            // apiResponse.response.put('status', 'error');
            // apiResponse.response.put('message', 'An error occurred while processing the request: ' + e.getMessage());
            // Old Code: END
            
            // ADDED BY: SOHEL : BRE CALLOUT REDUCTION
            Map<String, Object> errResp = new Map<String, Object>();
            errResp.put('status', 'error');
            errResp.put('message', 'An error occurred while processing the request: ' + e.getMessage());
            apiResponse.response.add(errResp);
            // ADDED BY: SOHEL : BRE CALLOUT REDUCTION
            
            response.responseBody = Blob.valueOf(JSON.serialize(apiResponse.response));
            response.statusCode = 500;
            response.addHeader('Content-Type', 'application/json');
        } finally {
            // Ensure logs are published regardless of success or failure
            QDX_LOG.publish();
        }
    }
}