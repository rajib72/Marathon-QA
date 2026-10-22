/*******************************************************************************************
* @File Name          : S3FileMigrationBatch.cls
* @Author             : Abhishek Jain
* @Description        : This Batch Class used to Upload Files FRom salesforce to AmazonAWS3. 
And Creates V2_AWS3__File__c object record to display files in salesforce from AmazonAWS3.
* Change History:

* DATE         AUTHOR                      Change Description
----------    --------------------         ---------------------------------------------
05/09/2025     Abhishek jain               MRT-628 This Batch Class used to Upload Files FRom salesforce to AmazonAWS3. 
And Creates V2_AWS3__File__c object record to display files in salesforce from AmazonAWS3
******************************************************************************************/
global class S3FileMigrationBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Schedulable {
    
    //get all the files which are related to InsurancePolicy or Claim object
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT 
            ContentDocumentId, 
            LinkedEntityId, 
            LinkedEntity.Type, 
            LinkedEntity.Name
            FROM ContentDocumentLink
            WHERE LinkedEntity.Type IN ('InsurancePolicy', 'Claim') order by ContentDocument.LastModifiedDate 
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<ContentDocumentLink> scope) {
        try {
            Map<Id, ContentVersion> documentIdToVersionMap = new Map<Id, ContentVersion>();
            Map<Id, V2_AWS3__File__c> documentIdToaws3Map = new Map<Id, V2_AWS3__File__c>();
            List<Id> deleteDocumentList = new List<Id>();
            List<Id> documentIdList = new List<Id>();
            
            //create list of contentDocumentId
            for(ContentDocumentLink link : scope){
                documentIdList.add(link.ContentDocumentId); 
            }
            
            //Fetch List of ContentVersion using above list of contentDocumentId
            List<ContentVersion> versionList = new List<ContentVersion>([SELECT 
                                                                         Id, 
                                                                         Title,
                                                                         VersionData, 
                                                                         FileExtension,
                                                                         ContentDocumentId
                                                                         FROM ContentVersion 
                                                                         WHERE ContentDocumentId IN :documentIdList
                                                                         AND FileExtension != 'snote']);
            
            if(!versionList.isEmpty()){ 
                //Prepare a map where the contentDocumentId is key and ContentVersion Record used as value
                ////Later we use this map to get required information from contentVersion using the contentDocumentId
                for(ContentVersion version : versionList){ 
                    documentIdToVersionMap.put(version.ContentDocumentId, version);
                }
                
                for (ContentDocumentLink link : scope) {
                    try {
                        //Will skip the below code if the ContentVersion record not exist for the ContentDocumentId
                        if(!documentIdToVersionMap.containsKey(link.ContentDocumentId)){
                            continue; 
                        }
                        // Construct a filename
                        String extension = documentIdToVersionMap.get(link.ContentDocumentId)?.FileExtension;
                        //Removing space,dot nad extension from the ContentVersion.Title If there are any and store in the anme variable
                        String Name = (documentIdToVersionMap.get(link.ContentDocumentId)?.Title)?.replaceAll('.'+extension,'')?.replaceAll('\\.','')?.replaceAll('/','-')?.replaceAll('#','');
                        Name = EncodingUtil.urlEncode(Name, 'UTF-8').replace('+', '%20');
                        String fileName = Name + '.' + extension;
                        
                        // Create the path or key for AmazonAWS3
                        String folderPrefix = link.LinkedEntity.Type +'/';
                        String recordName = EncodingUtil.urlEncode(link.LinkedEntity.Name, 'UTF-8').replace('+', '%20') + '/';
                        String s3Key = folderPrefix + recordName + fileName;
                        
                        // Function used to upload files from salesforce to the Amazons3. We make a callout in this method.
                        uploadToS3(s3Key, documentIdToVersionMap.get(link.ContentDocumentId).VersionData);
                        //prepare a map where contentDocumentId is key and V2_AWS3__File__c record is value
                        documentIdToaws3Map.put(link.ContentDocumentId, createAWSFileRecord(fileName, extension, link.LinkedEntityId, s3Key));
                        
                    }Catch(Exception e) {
                        QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber() + 'Trace'+e.getStackTraceString());
                    } finally {
                        QDX_Log.publish();
                    }
                }
                
                //insert V2_AWS3__File__c records
                //We add the relevant contentDocunetId to the deleteDocumentList variable if the record is successfully inserted.
                // The associated contentDocunetId is not added to the deleteDocumentList variable if the record is not successfully inserted.
                if(!documentIdToaws3Map.values().isEmpty()){
                    Database.insert(documentIdToaws3Map.values(), false);
                    for(Id key : documentIdToaws3Map.keySet()){
                        if(documentIdToaws3Map.get(key)?.Id != null){
                            deleteDocumentList.add(key); 
                        }
                    }
                }
                //delete contentDocument record using the contentDocumnetId stored in the deleteDocumentList
                //With its help, we eliminate only contentdocument records for which a V2_AWS3__File__c record has been generated.
                if(!deleteDocumentList.isEmpty()){
                    List<ContentDocument> docList = [SELECT Id FROM ContentDocument WHERE Id IN :deleteDocumentList];
                    Database.delete(docList, false);
                }
            }
        }Catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }
    
    global void finish(Database.BatchableContext bc) {}
    
    //Create V2_AWS3__File__c record
    private V2_AWS3__File__c createAWSFileRecord(String fileName, String extension, String recordId, String path) {
        V2_AWS3__File__c aws = new V2_AWS3__File__c();
        fileName = EncodingUtil.urlDecode(fileName, 'UTF-8');
        aws.V2_AWS3__File_Name__c = fileName;
        aws.V2_AWS3__File_Type__c = extension;
        //getting AWS3 URL from QdxProperty metadata
        path= EncodingUtil.urlDecode(path, 'UTF-8');
        aws.V2_AWS3__File_URL__c =  QDX_Property.propValueForLabel('Marathon AWS3 URL') + '/' + path; 
        aws.V2_AWS3__File_Version__c = 0 ;
        aws.V2_AWS3__Related_To__c = recordId;
        aws.V2_AWS3__Package_Type__c = 'AwsS3' ;
        return aws;
    }
    
    //make a callout to AmazonAWS3 to upload file
    private void uploadToS3(String key, Blob fileBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:AmazonS3FileMigration/' + key); // named credential
        req.setMethod('PUT');
        req.setHeader('Content-Type', 'application/pdf');
        req.setBodyAsBlob(fileBody);
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new CalloutException('S3 Upload failed: ' + res.getBody());
        }
    }
    
    public void execute(SchedulableContext sc) {
        // Schedule the batch job
        Database.executeBatch(new S3FileMigrationBatch(), 99); //for callout , we limit this to 99
        
        // Schedule the batch job using System.schedule()
        //String cronExpression = '0 0 12 * * ?'; // Schedule at 12:00 PM every day
        //String cronExpression = '0 0 * * * ?'; // Schedule at every hour
        //System.schedule('My Batch Job', cronExpression, new MyBatchSched());
    }
}