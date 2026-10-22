@RestResource(urlMapping='/ami/inspection/*')
global with sharing class AMIInspectionRestService {

  
    // REQUEST WRAPPER
 

    global class InspectionRequest {

        
        global String claimNumber;
        global Decimal inspectionPrice;
        global String invoiceNumber;

        global String inspectionCompany;

        global List<InspectionDocument> documents;
    }



    // DOCUMENT WRAPPER


    global class InspectionDocument {

        global String fileName;
        global String contentType;
        global String base64Data;
    }



    // RESPONSE WRAPPER
  

    global class InspectionResponse {

    global Boolean success;
    global String message;
    global Id claimItemId;
    global Integer documentsAttached;

    global InspectionResponse(
        Boolean success,
        String message,
        Id claimItemId,
        Integer documentsAttached
    ) {
        this.success = success;
        this.message = message;
        this.claimItemId = claimItemId;
        this.documentsAttached = documentsAttached;
    }
}


  
    // RESULT WRAPPER


  private class ProcessResult {

    Boolean success;
    Integer statusCode;
    String message;

    Id claimItemId;

    Integer documentsAttached;

        ProcessResult(
            Boolean success,
            Integer statusCode,
            String message
        ) {
            this.success = success;
            this.statusCode = statusCode;
            this.message = message;
            this.documentsAttached = 0;
        }
    }


  
    // REST API


    @HttpPost
    global static void receiveInspection() {

        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;

        response.addHeader(
            'Content-Type',
            'application/json'
        );

        try {

          
            // Validate Request
         

            if (
                request == null ||
                request.requestBody == null ||
                String.isBlank(
                    request.requestBody.toString()
                )
            ) {

                sendResponse(
                    response,
                    400,
                    new InspectionResponse(
                        false,
                        'Request body is required.',
                        null,
                        0
                    )
                );

                return;
            }


         
            // Deserialize JSON
        

            InspectionRequest inspectionRequest;

            try {

                inspectionRequest =
                    (InspectionRequest) JSON.deserialize(
                        request.requestBody.toString(),
                        InspectionRequest.class
                    );

            } catch (Exception ex) {

                sendResponse(
                    response,
                    400,
                    new InspectionResponse(
                        false,
                        'Invalid JSON payload: ' +
                        ex.getMessage(),
                        null,
                        0
                    )
                );

                return;
            }


         
            // Process Inspection
           

            ProcessResult result =
                processInspection(
                    inspectionRequest
                );


System.debug('### AMI claimNumber received = ' + inspectionRequest.claimNumber);
           
            // Return Response
          

            sendResponse(
                response,
                result.statusCode,
                new InspectionResponse(
                    result.success,
                    result.message,
                   
                    result.claimItemId,
                    result.documentsAttached
                )
            );

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.ERROR,
                'AMI Inspection API Error: ' +
                ex.getMessage()
            );

            System.debug(
                LoggingLevel.ERROR,
                ex.getStackTraceString()
            );

            sendResponse(
                response,
                500,
                new InspectionResponse(
                    false,
                    'Unexpected error while processing inspection.',
                    null,
                    0
                )
            );
        }
    }



    // MAIN BUSINESS LOGIC
   

    private static ProcessResult processInspection(
        InspectionRequest requestData
    ) {

        ProcessResult result =
            new ProcessResult(
                false,
                400,
                ''
            );


     
        // 1. Validate Request
        

        if (requestData == null) {

            result.message =
                'Request payload is required.';

            return result;
        }


       if (String.isBlank(requestData.claimNumber)) {
    result.message = 'Claim Number is required.';
    return result;
}


    
   


        if (
            requestData.inspectionPrice == null
        ) {

            result.message =
                'Inspection Price is required.';

            return result;
        }


        if (
            String.isBlank(requestData.invoiceNumber)
        ) {

            result.message =
                'Invoice Number is required.';

            return result;
        }


        
   
      


// 2. Find Claim using Claim Number


Claim claimRecord;

System.debug(
    '### Looking for Claim Number = ' +
    requestData.claimNumber
);

List<Claim> claims = [
    SELECT
        Id,
        Name
    FROM Claim
    WHERE Name = :requestData.claimNumber
    LIMIT 1
];

System.debug(
    '### Claim query returned = ' +
    claims.size()
);

if (claims.isEmpty()) {

    result.statusCode = 404;

    result.message =
        'Claim not found for Claim Number: ' +
        requestData.claimNumber;

    return result;
}

claimRecord = claims[0];

System.debug(
    '### Claim found. Id = ' +
    claimRecord.Id
);

System.debug(
    '### Claim found. Name = ' +
    claimRecord.Name
);





      
        // 3. Find Inspection Claim Item
     


System.debug(
    '### BEFORE INSPECTION CLAIM ITEM QUERY'
);

List<ClaimItem> inspectionItems = [
    SELECT
        Id,
        Name,
        ClaimId,
        Category,
        Detail_Type__c,
        Coverage_Level_Detail__c,
        Coverage_Level_Detail__r.Name,
        Status__c,
        Rate__c,
        Invoice_Number__c,
        Payee_Name__c
    FROM ClaimItem
    WHERE ClaimId = :claimRecord.Id
    AND Coverage_Level_Detail__r.Name LIKE 'Inspection%'
    LIMIT 2
];

System.debug(
    '### AFTER INSPECTION CLAIM ITEM QUERY'
);

System.debug(
    '### Inspection Claim Items found = ' +
    inspectionItems.size()
);
        if (!inspectionItems.isEmpty()) {

    System.debug(
        '### Inspection Claim Item Id = ' +
        inspectionItems[0].Id
    );

    System.debug(
        '### Inspection Claim Item Name = ' +
        inspectionItems[0].Name
    );

    System.debug(
        '### Coverage Level Detail Name = ' +
        inspectionItems[0].Coverage_Level_Detail__r.Name
    );

    System.debug(
        '### Payee Name Id = ' +
        inspectionItems[0].Payee_Name__c
    );
}

       
        // No Inspection Claim Item
      

        if (
            inspectionItems.isEmpty()
        ) {

            result.statusCode = 404;

            result.message =
                'No Inspection Claim Item found for Claim: ' +
                claimRecord.Name;

            return result;
        }


      
        // Multiple Inspection Claim Items
        

        if (
            inspectionItems.size() > 1
        ) {

            result.statusCode = 409;

            result.message =
                'Multiple Inspection Claim Items found for Claim: ' +
                claimRecord.Name +
                '. Unable to determine the correct Claim Item.';

            return result;
        }


        ClaimItem inspectionItem =
            inspectionItems[0];


        result.claimItemId =
            inspectionItem.Id;


    
        // 4. Validate Inspection Company
       

        if (
            !String.isBlank(
                requestData.inspectionCompany
            )
        ) {

            if (
                inspectionItem.Payee_Name__c == null
            ) {

                result.statusCode = 400;

                result.message =
                    'Inspection Company is not populated on the ' +
                    'Inspection Claim Item.';

                return result;
            }


            List<Account> accounts = [

                SELECT
                    Id,
                    Name

                FROM Account

                WHERE Id = :inspectionItem.Payee_Name__c

                LIMIT 1
            ];


            if (
                accounts.isEmpty()
            ) {

                result.statusCode = 400;

                result.message =
                    'Inspection Company could not be identified.';

                return result;
            }


            if (
                accounts[0].Name !=
                requestData.inspectionCompany
            ) {

                result.statusCode = 409;

                result.message =
                    'Inspection Company does not match the ' +
                    'Inspection Claim Item.';

                return result;
            }
        }

        // 5. Update Inspection Claim Item

       inspectionItem.Rate__c =
    requestData.inspectionPrice;


        inspectionItem.Invoice_Number__c =
            requestData.invoiceNumber;


        // Business Requirement:
        //
        // Once inspection price is successfully received,
        // Claim Item should become Paid.

        inspectionItem.Status__c =
            'Paid';


        update inspectionItem;


      
        // 6. Attach Documents to Claim
      

        if (
            requestData.documents != null &&
            !requestData.documents.isEmpty()
        ) {

            List<ContentVersion> filesToInsert =
                new List<ContentVersion>();


            for (
                InspectionDocument document :
                requestData.documents
            ) {

                // Ignore invalid document entries.

                if (
                    String.isBlank(
                        document.fileName
                    ) ||
                    String.isBlank(
                        document.base64Data
                    )
                ) {

                    continue;
                }


                ContentVersion file =
                    new ContentVersion();


                file.Title =
                    getFileTitle(
                        document.fileName
                    );


                file.PathOnClient =
                    document.fileName;


                file.VersionData =
                    EncodingUtil.base64Decode(
                        document.base64Data
                    );


                filesToInsert.add(file);
            }


         
            // Insert Files
           

            if (
                !filesToInsert.isEmpty()
            ) {

                insert filesToInsert;


             
                // Get ContentDocument Ids
              

                Set<Id> contentVersionIds =
                    new Set<Id>();


                for (
                    ContentVersion file :
                    filesToInsert
                ) {

                    contentVersionIds.add(
                        file.Id
                    );
                }


                List<ContentVersion> insertedFiles = [

                    SELECT
                        Id,
                        ContentDocumentId

                    FROM ContentVersion

                    WHERE Id IN :contentVersionIds
                ];


              
                // Link Files to Claim
              

                List<ContentDocumentLink> documentLinks =
                    new List<ContentDocumentLink>();


                for (
                    ContentVersion file :
                    insertedFiles
                ) {

                    ContentDocumentLink documentLink =
                        new ContentDocumentLink();


                    documentLink.ContentDocumentId =
                        file.ContentDocumentId;


                    documentLink.LinkedEntityId =
                        claimRecord.Id;


                    documentLink.ShareType =
                        'V';


                    documentLink.Visibility =
                        'AllUsers';


                    documentLinks.add(
                        documentLink
                    );
                }


                if (
                    !documentLinks.isEmpty()
                ) {

                    insert documentLinks;


                    result.documentsAttached =
                        documentLinks.size();
                }
            }
        }


       
        // 7. Successful Processing
       

        result.success = true;

        result.statusCode = 200;

        result.message =
            'Inspection processed successfully.';

        return result;
    }


   
    // FILE TITLE
   

    private static String getFileTitle(
        String fileName
    ) {

        if (
            String.isBlank(fileName)
        ) {

            return 'AMI Inspection Document';
        }


        Integer dotPosition =
            fileName.lastIndexOf('.');


        if (
            dotPosition > 0
        ) {

            return fileName.substring(
                0,
                dotPosition
            );
        }


        return fileName;
    }


   
    // SEND RESPONSE
    

    private static void sendResponse(
        RestResponse response,
        Integer statusCode,
        InspectionResponse responseBody
    ) {

        response.statusCode =
            statusCode;


        response.responseBody =
            Blob.valueOf(
                JSON.serialize(
                    responseBody
                )
            );
    }
}