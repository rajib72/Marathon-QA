/**
* @description
* REST API to retrieve Claim Information for a Home Warranty contract.
*
* Request:
* {
*     "ContractNumber": "EHWXXXXXX",
*     "CoveredResidencePostalCode": "XXXXX"
* }
*
* Endpoint:
* /services/apexrest/HomeClaimsInformation/*
*/
@RestResource(urlMapping='/HomeClaimsInformation/*')
global with sharing class HomeClaimsInformationAPI {
    /*
* ============================================================
* REQUEST WRAPPER
* ============================================================
*/
    global class HomeClaimInformationRequest {
        
        public String ContractNumber;
        public String CoveredResidencePostalCode;
    }
    
    
    /*
* ============================================================
* RESPONSE WRAPPER
* ============================================================
*/
    global class HomeClaimInformationResponse {
        
        public Integer status;
        public String error;
        public HomeClaimInformationPayload payload;
        public List<Object> claims;
    }
    
    
    /*
* ============================================================
* REQUEST PAYLOAD RESPONSE
* ============================================================
*/
    global class HomeClaimInformationPayload {
        
        public String ContractNumber;
        public String CoveredResidencePostalCode;
    }
    
    
    /*
* ============================================================
* INDIVIDUAL CLAIM RESPONSE
* ============================================================
*/
    global class HomeClaimResponse {
        
        public String ClaimNumber;
        public String Status;
        public String  PaidAmount;
        public String  ApprovedAmount;
        public String  RequestedAmount;
        public String LatestPaidDate;
        public String DenialReason;
        public String CreatedDate;
    }
    
    
    /*
* ============================================================
* POST METHOD
* ============================================================
*/
    @HttpPost
    global static void getClaimsInformation() {
        
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        HomeClaimInformationRequest requestData;
try {
            
            /*
* ----------------------------------------------------
* STEP 1: Validate request body
* ----------------------------------------------------
*/
            if (req == null || req.requestBody == null) {
                
                sendErrorResponse(
                    res,
                    400,
                    'Contract not found or null value received for required field',
                    null,
                    null
                );
                
                return;
            }
            
            
            /*
* ----------------------------------------------------
* STEP 2: Read request body
* ----------------------------------------------------
*/
            String requestBody = req.requestBody.toString();
            
            if (String.isBlank(requestBody)) {
                
                sendErrorResponse(
                    res,
                    400,
                    'Contract not found or null value received for required field',
                    null,
                    null
                );
                
                return;
            }
            
            
            /*
* ----------------------------------------------------
* STEP 3: Deserialize JSON request
* ----------------------------------------------------
*/
            try {
                
                requestData =
                    (HomeClaimInformationRequest) JSON.deserialize(
                        requestBody,
                        HomeClaimInformationRequest.class
                    );
                
          } catch (Exception jsonException) {
    
    sendErrorResponse(
        res,
        400,
        'Invalid request format',
        null,
        null
    );
    
    return;
}
            
            
            /*
* ----------------------------------------------------
* STEP 4: Validate required fields
* ----------------------------------------------------
*/
            if (requestData == null ||
                String.isBlank(requestData.ContractNumber) ||
                String.isBlank(requestData.CoveredResidencePostalCode)) {
                    
                    sendErrorResponse(
                        res,
                        400,
                        'Contract not found or null value received for required field',
                        requestData != null
                        ? requestData.ContractNumber
                        : null,
                        requestData != null
                        ? requestData.CoveredResidencePostalCode
                        : null
                    );
                    
                    return;
                }
            
            
            /*
* ----------------------------------------------------
* STEP 5: Validate character limits
*
* ContractNumber = Text(80)
* CoveredResidencePostalCode = Text(20)
* ----------------------------------------------------
*/
            if (requestData.ContractNumber.length() > 80) {
                
                sendErrorResponse(
                    res,
                    400,
                    'ContractNumber exceeds the maximum length of 80 characters',
                    requestData.ContractNumber,
                    requestData.CoveredResidencePostalCode
                );
                
                return;
            }
            
            
            if (requestData.CoveredResidencePostalCode.length() > 20) {
                
                sendErrorResponse(
                    res,
                    400,
                    'CoveredResidencePostalCode exceeds the maximum length of 20 characters',
                    requestData.ContractNumber,
                    requestData.CoveredResidencePostalCode
                );
                
                return;
            }
            
            
            /*
* ----------------------------------------------------
* STEP 6: Find matching Home Warranty Insurance Policy
*
* Home:
*
* Contract Number
*     -> InsurancePolicy.Name
*
* Covered Residence Postal Code
*     -> InsurancePolicy.Postal_Code__c
*
* Home Product
*     -> RecordType.Name = Home Warranty
* ----------------------------------------------------
*/
            List<InsurancePolicy> policies = [
                SELECT Id,
                Name,
                Postal_Code__c,
                RecordType.Name
                FROM InsurancePolicy
                WHERE Name = :requestData.ContractNumber
                AND Postal_Code__c = :requestData.CoveredResidencePostalCode
                AND RecordType.Name = 'Home Warranty'
                LIMIT 1
            ];
            
            
            /*
* ----------------------------------------------------
* STEP 7: Policy not found
* ----------------------------------------------------
*/
            if (policies.isEmpty()) {
                
                sendErrorResponse(
                    res,
                    400,
                    'Contract not found or null value received for required field',
                    requestData.ContractNumber,
                    requestData.CoveredResidencePostalCode
                );
                
                return;
            }
            
            
            /*
* ----------------------------------------------------
* STEP 8: Get matching Insurance Policy
* ----------------------------------------------------
*/
            InsurancePolicy policy = policies[0];

            /*
* ----------------------------------------------------
* STEP 9: Find ALL Claims associated with Policy
*
* Claim.PolicyNumberId
*          ->
* InsurancePolicy.Id
* ----------------------------------------------------
*/
            List<Claim> claimRecords = [
                SELECT Id,
                Name,
                Status,
                Claim_Amount_Paid__c,
                ApprovedAmount,
                NetClaim__c,
                Latest_Date_Paid__c,
                Denial_Reason__c,
                CreatedDate
                FROM Claim
                WHERE PolicyNumberId = :policy.Id
                ORDER BY CreatedDate DESC
            ];
            /*
* ----------------------------------------------------
* STEP 10: Prepare Claim response list
* ----------------------------------------------------
*/
            List<HomeClaimResponse> claimResponses =
                new List<HomeClaimResponse>();
            
            
            /*
* ----------------------------------------------------
* STEP 11: Map Salesforce Claim -> API Response
* ----------------------------------------------------
*/
            for (Claim claimRecord : claimRecords) {
                
                HomeClaimResponse claimResponse =
                    new HomeClaimResponse();
                
                
                /*
* Claim Number
*/
                claimResponse.ClaimNumber =
                    claimRecord.Name;
                
                
                /*
* Claim Status
*/
                claimResponse.Status =
                    claimRecord.Status;
                
                
                /*
* Paid Amount
*/
                claimResponse.PaidAmount =
                    claimRecord.Claim_Amount_Paid__c != null
                    ? claimRecord.Claim_Amount_Paid__c.setScale(2).format()
                    : '0.00';
                
                claimResponse.ApprovedAmount =
                    claimRecord.ApprovedAmount != null
                    ? claimRecord.ApprovedAmount.setScale(2).format()
                    : '0.00';
                
                claimResponse.RequestedAmount =
                    claimRecord.NetClaim__c != null
                    ? claimRecord.NetClaim__c.setScale(2).format()
                    : '0.00';
                
                /*
* Latest Paid Date
*
* Requirement:
* MM-DD-YYYY
*/
                if (claimRecord.Latest_Date_Paid__c != null) {
                    
                    claimResponse.LatestPaidDate =
                        DateTime.newInstance(
                            claimRecord.Latest_Date_Paid__c,
                            Time.newInstance(0, 0, 0, 0)
                        ).format('MM-dd-yyyy');
                    
                } else {
                    
                    claimResponse.LatestPaidDate = '';
                }
                
                
                /*
* Denial Reason
*/
                claimResponse.DenialReason =
                    claimRecord.Denial_Reason__c != null
                    ? claimRecord.Denial_Reason__c
                    : '';
                
                claimResponse.CreatedDate =
                    claimRecord.CreatedDate.format('MM-dd-yyyy');
                
                
                claimResponses.add(claimResponse);
            }
            
            
            /*
* ----------------------------------------------------
* STEP 12: Build successful response
* ----------------------------------------------------
*/
            HomeClaimInformationResponse response =
                new HomeClaimInformationResponse();
            
            response.status = 200;
            response.error = '';
            
            
            /*
* Payload
*/
            response.payload =
                new HomeClaimInformationPayload();
            
            response.payload.ContractNumber =
                requestData.ContractNumber;
            
            response.payload.CoveredResidencePostalCode =
                requestData.CoveredResidencePostalCode;
            
            
            /*
* Claims
*/
            response.claims =
                new List<Object>();
            
            for (HomeClaimResponse claimResponse : claimResponses) {
                response.claims.add(claimResponse);
            }
            
            
            /*
* ----------------------------------------------------
* STEP 13: Return HTTP 200
* ----------------------------------------------------
*/
            res.statusCode = 200;
            
            res.addHeader(
                'Content-Type',
                'application/json'
            );
            
            JSONGenerator gen = JSON.createGenerator(false);
            
            gen.writeStartObject();
            
            // 1. status
            gen.writeNumberField(
                'status',
                response.status
            );
            
            // 2. error
            gen.writeStringField(
                'error',
                response.error != null ? response.error : ''
            );
            
            // 3. payload
            gen.writeFieldName('payload');
            
            gen.writeStartObject();
            
            gen.writeStringField(
                'ContractNumber',
                response.payload.ContractNumber != null
                ? response.payload.ContractNumber
                : ''
            );
            
            gen.writeStringField(
                'CoveredResidencePostalCode',
                response.payload.CoveredResidencePostalCode != null
                ? response.payload.CoveredResidencePostalCode
                : ''
            );
            
            gen.writeEndObject();
            
            // 4. claims
            gen.writeFieldName('claims');
            
            gen.writeStartArray();
            
            for (HomeClaimResponse claimResponse : claimResponses) {
                
                gen.writeStartObject();
                
                // 1. ClaimNumber
                gen.writeStringField(
                    'ClaimNumber',
                    claimResponse.ClaimNumber != null
                    ? claimResponse.ClaimNumber
                    : ''
                );
                
                // 2. Status
                gen.writeStringField(
                    'Status',
                    claimResponse.Status != null
                    ? claimResponse.Status
                    : ''
                );
                
                // 3. PaidAmount
                gen.writeStringField(
                    'PaidAmount',
                    claimResponse.PaidAmount != null
                    ? claimResponse.PaidAmount
                    : '0.00'
                );
                
                // 4. ApprovedAmount
                gen.writeStringField(
                    'ApprovedAmount',
                    claimResponse.ApprovedAmount != null
                    ? claimResponse.ApprovedAmount
                    : '0.00'
                );
                // 5. RequestedAmount
                gen.writeStringField(
                    'RequestedAmount',
                    claimResponse.RequestedAmount != null
                    ? claimResponse.RequestedAmount
                    : '0.00'
                );
                // 5. LatestPaidDate
                gen.writeStringField(
                    'LatestPaidDate',
                    claimResponse.LatestPaidDate != null
                    ? claimResponse.LatestPaidDate
                    : ''
                );
                
                // 6. DenialReason
                gen.writeStringField(
                    'DenialReason',
                    claimResponse.DenialReason != null
                    ? claimResponse.DenialReason
                    : ''
                );
                // 8. CreatedDate
                gen.writeStringField(
                    'CreatedDate',
                    claimResponse.CreatedDate != null
                    ? claimResponse.CreatedDate
                    : ''
                );
                
                gen.writeEndObject();
            }
            
            gen.writeEndArray();
            
            gen.writeEndObject();
            
            String finalResponseBody =
                gen.getAsString();
            
            res.responseBody =
                Blob.valueOf(
                    finalResponseBody
                );

        } catch (Exception ex) {
            
            sendErrorResponse(
                res,
                500,
                'An unexpected error occurred during processing.',
                requestData != null
                ? requestData.ContractNumber
                : null,
                requestData != null
                ? requestData.CoveredResidencePostalCode
                : null
            );
        }
        
        /*
* ============================================================
* END OF getClaimsInformation()
* ============================================================
*/
    }
    
    /*
* ============================================================
* ERROR RESPONSE METHOD
* ============================================================
*/
    private static void sendErrorResponse(
        RestResponse res,
        Integer statusCode,
        String errorMessage,
        String contractNumber,
        String coveredResidencePostalCode
    ) {
        
        res.statusCode = statusCode;
        
        res.addHeader(
            'Content-Type',
            'application/json'
        );
        
        JSONGenerator gen =
            JSON.createGenerator(false);
        
        gen.writeStartObject();
        
        // 1. status
        gen.writeNumberField(
            'status',
            statusCode
        );
        
        // 2. error
        gen.writeStringField(
            'error',
            errorMessage != null
            ? errorMessage
            : ''
        );
        
        // 3. payload
        gen.writeFieldName('payload');
        
        gen.writeStartObject();
        
        gen.writeStringField(
            'ContractNumber',
            contractNumber != null
            ? contractNumber
            : ''
        );
        
        gen.writeStringField(
            'CoveredResidencePostalCode',
            coveredResidencePostalCode != null
            ? coveredResidencePostalCode
            : ''
        );
        
        gen.writeEndObject();
        
        // 4. claims
        gen.writeFieldName('claims');
        
        gen.writeStartArray();
        
        gen.writeStartObject();
        gen.writeEndObject();
        
        gen.writeEndArray();
        
        gen.writeEndObject();
        
        
        String finalResponseBody =
            gen.getAsString();
        
        res.responseBody =
            Blob.valueOf(
                finalResponseBody
            );
    }
}