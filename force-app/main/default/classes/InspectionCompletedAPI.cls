@RestResource(urlMapping='/inspection/completed/*')
global with sharing class InspectionCompletedAPI {

    @HttpPost
    global static void receiveInspection() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        ResponseWrapper response = new ResponseWrapper();

        res.addHeader('Content-Type', 'application/json');

        try {

            //===============================
            // Read Request Body
            //===============================
            if(req.requestBody == null ||
   req.requestBody.size() == 0){

    res.statusCode = 400;

    response.success = false;
    response.message = 'Request body is required';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}



            String requestBody = req.requestBody.toString();

            System.debug(
    LoggingLevel.INFO,
    'Inspection Request :: ' + requestBody
);

            InspectionRequest request =
                (InspectionRequest)JSON.deserialize(
                    requestBody,
                    InspectionRequest.class
                );

            //===============================
            // Validate Claim Number
            //===============================

           if(String.isBlank(request.claimNumber)){

    res.statusCode = 400;

    response.success = false;

    response.message = 'Claim Number is required';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}

if(String.isBlank(request.inspectionId)){

    res.statusCode = 400;

    response.success = false;

    response.message = 'Inspection Id is required';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}

if(request.inspectionPrice == null){

    res.statusCode = 400;

    response.success = false;

    response.message = 'Inspection Price is required';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}
            if(String.isBlank(request.invoiceNumber)){

    res.statusCode = 400;

    response.success = false;

    response.message = 'Invoice Number is required';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}
            if(String.isBlank(request.inspectionNumber)){

    res.statusCode = 400;

    response.success = false;

    response.message =
        'Inspection Number is required';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}

            //===============================
            // Find Claim
            //===============================

            List<Claim> claimList = [

                SELECT  Id,
                        Name,
                        Status,
                        ReportDate,
                        Summary,
                        Description__c,
                        SourceSystem,
                        SourceSystemIdentifier

                FROM Claim

                WHERE Name = :request.claimNumber

                LIMIT 1
            ];

            if(claimList.isEmpty()){

                res.statusCode = 404;

                response.success = false;
                response.message =
                    'Claim not found : ' + request.claimNumber;

                res.responseBody =
                    Blob.valueOf(JSON.serialize(response));

                return;

            }

            Claim claimRecord = claimList[0];


            //=========================================
            // Update Available Claim Fields
            //=========================================

           

            if(request.inspectionDate != null)
                claimRecord.ReportDate = request.inspectionDate;

            if(!String.isBlank(request.summary))
                claimRecord.Summary = request.summary;

            if(!String.isBlank(request.description))
                claimRecord.Description__c = request.description;

            if(!String.isBlank(request.inspectionCompany))
                claimRecord.SourceSystem = request.inspectionCompany;

            if(!String.isBlank(request.inspectionId))
                claimRecord.SourceSystemIdentifier =
                    request.inspectionId;

          

            //=========================================
            //Decimal inspectionNumberValue;

//=========================================================
// Find Inspection Request Claim Item
//=========================================================

Decimal inspectionNumberValue;

try {

    inspectionNumberValue =
        Decimal.valueOf(request.inspectionNumber);

}
catch(Exception ex) {

    res.statusCode = 400;

    response.success = false;

    response.message =
        'Invalid Inspection Number: '
        + request.inspectionNumber;

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}

//=========================================================
// Find Inspection Request Claim Item
//=========================================================

List<ClaimItem> claimItems = [

    SELECT Id,
           Invoice_Number__c,
           Status__c,
           Paid_Date__c,
           Allocation_Number__c

    FROM ClaimItem

    WHERE ClaimId = :claimRecord.Id
    AND Allocation_Number__c = :inspectionNumberValue

    LIMIT 1
];


//=========================================================
// Validate Claim Item
//=========================================================

if(claimItems.isEmpty()) {

    res.statusCode = 404;

    response.success = false;

    response.message =
        'Inspection Request Claim Item not found for Inspection Number: '
        + request.inspectionNumber;

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));

    return;
}


//=========================================================
// Get Claim Item
//=========================================================

ClaimItem item = claimItems[0];


//=========================================
// Download Inspection Files
//=========================================

List<DownloadedFile> downloadedFiles =
    new List<DownloadedFile>();

if(request.files != null &&
   !request.files.isEmpty()){

    downloadedFiles =
        downloadInspectionFiles(request.files);
}


//=========================================
// Update Inspection Request Claim Item
//=========================================

item.Invoice_Number__c =
    request.invoiceNumber;

item.Status__c =
    'Paid';

item.Paid_Date__c =
    Date.today();

update item;


//=========================================
// Update Claim
//=========================================

update claimRecord;


//=========================================
// Attach Inspection Files
//=========================================

if(!downloadedFiles.isEmpty()){

    attachDownloadedFiles(
        claimRecord.Id,
        downloadedFiles
    );
}


//=========================================
// Success Response
//=========================================

res.statusCode = 200;

response.success = true;

response.claimId =
    claimRecord.Id;

response.claimNumber =
    claimRecord.Name;

response.message =
    'Inspection processed successfully';

res.responseBody =
    Blob.valueOf(
        JSON.serialize(response)
    );}
catch(QueryException ex){

    res.statusCode = 404;

    response.success = false;
    response.message = 'Unable to locate the requested record.';

    res.responseBody =
        Blob.valueOf(JSON.serialize(response));
}
        
        
catch(Exception ex){

    res.statusCode = 500;

    response.success = false;

    response.message = ex.getMessage();

}

    }

    //=========================================================
    // Request Wrapper
    //=========================================================

    global class InspectionRequest{

        public String claimNumber;

        public String inspectionId;
        public String invoiceNumber;
        public String inspectionNumber;

        public String inspectionCompany;

        public String inspectionStatus;

        public Decimal inspectionPrice;

        public Datetime inspectionDate;

        public String summary;

        public String description;

        public List<FileWrapper> files;
    }

    //=========================================================
    // File Wrapper
    //=========================================================

    global class FileWrapper{

        public String fileName;

        public String fileUrl;
    }
    global class DownloadedFile{

    public String fileName;

    public Blob fileBody;
}

    //=========================================================
    // Response Wrapper
    //=========================================================

    global class ResponseWrapper{

        public Boolean success;

        public String message;

        public Id claimId;

        public String claimNumber;
    }
        //=========================================================
    // Attach Inspection Files to Claim
    //=========================================================
private static List<DownloadedFile> downloadInspectionFiles(
    List<FileWrapper> files
){

    List<DownloadedFile> downloadedFiles =
        new List<DownloadedFile>();

    for(FileWrapper file : files){

        if(String.isBlank(file.fileUrl)){
            continue;
        }

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(file.fileUrl);
        request.setMethod('GET');
        request.setTimeout(120000);

        HttpResponse response =
            new Http().send(request);

        if(response.getStatusCode() != 200){

            throw new CalloutException(
                'Unable to download inspection file: '
                + file.fileName
            );
        }

        DownloadedFile downloadedFile =
            new DownloadedFile();

        downloadedFile.fileName =
            String.isBlank(file.fileName)
            ? 'Inspection File'
            : file.fileName;

        downloadedFile.fileBody =
            response.getBodyAsBlob();

        downloadedFiles.add(downloadedFile);
    }

    return downloadedFiles;
}
    
    private static void attachDownloadedFiles(
    Id claimId,
    List<DownloadedFile> files
){

    for(DownloadedFile file : files){

        ContentVersion cv =
            new ContentVersion();

        cv.Title =
            file.fileName;

        cv.PathOnClient =
            file.fileName;

        cv.VersionData =
            file.fileBody;

        insert cv;

        cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        ContentDocumentLink cdl =
            new ContentDocumentLink();

        cdl.LinkedEntityId =
            claimId;

        cdl.ContentDocumentId =
            cv.ContentDocumentId;

        cdl.ShareType =
            'V';

        cdl.Visibility =
            'AllUsers';

        insert cdl;
    }
}
   


    //=========================================================
    // Future Enhancement
    //=========================================================

    /*
        After new fields are created,
        add below logic.

        ----------------------------------------

        Find Inspection Request Claim Item

        Example

        Claim_Item__c item = [

            SELECT Id,
                   Inspection_Price__c,
                   Status__c

            FROM Claim_Item__c

            WHERE Claim__c = :claimId

            LIMIT 1

        ];

        item.Inspection_Price__c =
            request.inspectionPrice;

        item.Status__c = 'Paid';

        update item;
//=========================================
// Attach Inspection Files
//=========================================

if(!downloadedFiles.isEmpty()){

    attachDownloadedFiles(
        claimRecord.Id,
        downloadedFiles
    );
}

        ----------------------------------------

        Update Claim fields

        claim.Inspection_ID__c

        claim.Inspection_Company__c

        claim.Inspection_Status__c

        claim.Inspection_Price__c

        claim.Inspection_Completed_Date__c

    */
    
    
    


}