/**
* @description
* REST API to retrieve Claim Information for an Auto Warranty contract.
*
* Request:
* {
*     "ContractNumber": "EMBIXXXXXX",
*     "VIN": "1GNEVJKW3KJ164801"
* }
*
* Endpoint:
* /services/apexrest/AutoClaimsInformation/*
*/
@RestResource(urlMapping='/AutoClaimsInformation/*')
global with sharing class AutoClaimsInformationAPI {
    
    /*
* ============================================================
* REQUEST WRAPPER
* ============================================================
*/
    global class ClaimInformationRequest {
        
        public String ContractNumber;
        public String VIN;
    }
    
    
    /*
* ============================================================
* RESPONSE WRAPPER
* ============================================================
*/
    global class ClaimInformationResponse {
        
        public Integer status;
        public String error;
        public ClaimInformationPayload payload;
        public List<Object> claims;
    }
    
    
    /*
* ============================================================
* REQUEST PAYLOAD RESPONSE
* ============================================================
*/
    global class ClaimInformationPayload {
        
        public String ContractNumber;
        public String VIN;
    }
    
    
    /*
* ============================================================
* INDIVIDUAL CLAIM RESPONSE
* ============================================================
*/
    public class ClaimResponse {
        
        public String ClaimNumber;
        public String Status;
        public String PaidAmount;
       public String ApprovedAmount;
        public String RequestedAmount;
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
        
        ClaimInformationRequest requestData;
        
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
                    'Null value received for required field',
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
                    'Null value received for required field',
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
                    (ClaimInformationRequest) JSON.deserialize(
                        requestBody,
                        ClaimInformationRequest.class
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
                String.isBlank(requestData.VIN)) {
                    
                    sendErrorResponse(
                        res,
                        400,
                        'Contract not found or null value received for required field',
                        requestData != null
                        ? requestData.ContractNumber
                        : null,
                        requestData != null
                        ? requestData.VIN
                        : null
                    );
                    
                    return;
                }
            
            
            /*
* ----------------------------------------------------
* STEP 5: Validate character limits
*
* ContractNumber = Text(80)
* VIN           = Text(17)
* ----------------------------------------------------
*/
            if (requestData.ContractNumber.length() > 80) {
                
                sendErrorResponse(
                    res,
                    400,
                    'ContractNumber exceeds the maximum length of 80 characters',
                    requestData.ContractNumber,
                    requestData.VIN
                );
                
                return;
            }
            
            
            if (requestData.VIN.length() > 17) {
                
                sendErrorResponse(
                    res,
                    400,
                    'VIN exceeds the maximum length of 17 characters',
                    requestData.ContractNumber,
                    requestData.VIN
                );
                
                return;
            }
            
            
            /*
* ----------------------------------------------------
* STEP 6: Find matching Insurance Policy
*
* Auto:
*
* Contract Number -> InsurancePolicy.Name
* VIN             -> InsurancePolicy.VIN__c
* ----------------------------------------------------
*/
            List<InsurancePolicy> policies = [
                SELECT Id,
                Name,
                VIN__c
                FROM InsurancePolicy
                WHERE Name = :requestData.ContractNumber
                AND VIN__c = :requestData.VIN
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
                    requestData.VIN
                );
                
                return;
            }
            
            
            InsurancePolicy policy = policies[0];
            
            
            /*
* ----------------------------------------------------
* STEP 8: Find ALL Claims associated with the Policy
*
* Claim.PolicyNumberId -> InsurancePolicy.Id
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
* STEP 9: Prepare Claim response list
* ----------------------------------------------------
*/
            List<ClaimResponse> claimResponses =
                new List<ClaimResponse>();
            
            for (Claim claimRecord : claimRecords) {
                
                ClaimResponse claimResponse =
                    new ClaimResponse();
                
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
                
                
                /*
* Approved Amount
*/
// Approved Amount
claimResponse.ApprovedAmount =
    claimRecord.ApprovedAmount != null
    ? claimRecord.ApprovedAmount.setScale(2).format()
    : '0.00';

                
                /*
* Requested Amount
*
* Client requirement:
* Directly from Claim.NetClaim__c.
* No calculation.
*/
    claimResponse.RequestedAmount =
    claimRecord.NetClaim__c != null
    ? claimRecord.NetClaim__c.setScale(2).format()
    : '0.00';
                
                
                /*
* Latest Paid Date
*
* Requirement format:
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
                
                
                /*
* Created Date
*
* Requirement format:
* MM-DD-YYYY
*/
                claimResponse.CreatedDate =
                    claimRecord.CreatedDate != null
                    ? claimRecord.CreatedDate.format('MM-dd-yyyy')
                    : '';
                
                
                /*
* Add claim to response list
*/
                claimResponses.add(claimResponse);
            }
            
            
            /*
* ----------------------------------------------------
* STEP 11: Build successful response
* ----------------------------------------------------
*/
            ClaimInformationResponse response =
                new ClaimInformationResponse();
            
            response.status = 200;
            response.error = '';
            
            response.payload =
                new ClaimInformationPayload();
            
            response.payload.ContractNumber =
                requestData.ContractNumber;
            
            response.payload.VIN =
                requestData.VIN;
            
            response.claims =
                claimResponses;
            
            
            /*
* ----------------------------------------------------
* STEP 12: Return HTTP 200
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
                'VIN',
                response.payload.VIN != null
                ? response.payload.VIN
                : ''
            );
            
            gen.writeEndObject();
            
            // 4. claims
            gen.writeFieldName('claims');
            
            gen.writeStartArray();
            
            for (ClaimResponse claimResponse : claimResponses) {
                
                gen.writeStartObject();
                
                // ClaimNumber
                // ClaimNumber
gen.writeStringField(
    'ClaimNumber',
    claimResponse.ClaimNumber != null
    ? claimResponse.ClaimNumber
    : ''
);

// Status
gen.writeStringField(
    'Status',
    claimResponse.Status != null
    ? claimResponse.Status
    : ''
);

// PaidAmount
gen.writeStringField(
    'PaidAmount',
    claimResponse.PaidAmount != null
    ? claimResponse.PaidAmount
    : '0.00'
);

// ApprovedAmount
gen.writeStringField(
    'ApprovedAmount',
    claimResponse.ApprovedAmount != null
    ? claimResponse.ApprovedAmount
    : '0.00'
);

// RequestedAmount
gen.writeStringField(
    'RequestedAmount',
    claimResponse.RequestedAmount != null
    ? claimResponse.RequestedAmount
    : '0.00'
);

// LatestPaidDate
gen.writeStringField(
    'LatestPaidDate',
    claimResponse.LatestPaidDate != null
    ? claimResponse.LatestPaidDate
    : ''
);

// DenialReason
gen.writeStringField(
    'DenialReason',
    claimResponse.DenialReason != null
    ? claimResponse.DenialReason
    : ''
);

// CreatedDate
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
            
            res.responseBody =
                Blob.valueOf(
                    gen.getAsString()
                );
            
            
        } catch (Exception e) {
            
            /*
* ----------------------------------------------------
* STEP 13: Unexpected processing error
* ----------------------------------------------------
*/
            sendErrorResponse(
                res,
                500,
                'An unexpected error occurred during processing.',
                requestData != null
                ? requestData.ContractNumber
                : null,
                requestData != null
                ? requestData.VIN
                : null
            );
        }
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
        String vin
    ) {
        
        ClaimInformationResponse response =
            new ClaimInformationResponse();
        
        response.status = statusCode;
        response.error = errorMessage;
        
        
        /*
* Payload
*/
        response.payload =
            new ClaimInformationPayload();
        
        response.payload.ContractNumber =
            contractNumber != null
            ? contractNumber
            : '';
        
        response.payload.VIN =
            vin != null
            ? vin
            : '';
        
        
        /*
* Requirement example shows claims:
* [
*     {}
* ]
*
* Therefore create one empty ClaimResponse
* for the error response.
*/
        response.claims = new List<Object>();
        
        response.claims.add(new Map<String, Object>());
        
        
        res.statusCode = statusCode;
        
        res.addHeader(
            'Content-Type',
            'application/json'
        );
        
        JSONGenerator gen = JSON.createGenerator(false);
        
        gen.writeStartObject();
        
        // 1. status
        gen.writeNumberField(
            'status',
            statusCode
        );
        
        // 2. error
        gen.writeStringField(
            'error',
            errorMessage != null ? errorMessage : ''
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
            'VIN',
            vin != null
            ? vin
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
        
        res.responseBody =
            Blob.valueOf(
                gen.getAsString()
            );
    }
}