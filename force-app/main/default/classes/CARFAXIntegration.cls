global with sharing class CARFAXIntegration implements Callable {
	
    public Object call(String action, Map<String,Object> args){
        Map<String,Object> result = new Map<String,Object>();
        Map<String,Object> input = (Map<String,Object>)args.get('input');
        Map<String,Object> output = (Map<String,Object>)args.get('output');
        Map<String,Object> options = (Map<String,Object>)args.get('options');
        result = (Map<String,Object>)invokeMethod(action, input, output, options);
        return result;
    }
    
    private Object invokeMethod(String methodName, Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
      
        QDX_LOG.debug('input: '+input);
        if(methodName == 'getCarFaxFile'){
            return (Map<String,Object>)getCarFaxFile(output, input.get('ClaimId').toString(), input.get('VIN').toString());
        }
        return '';
    }
    
    
    public static Object getCarFaxFile(Map<String,Object> output, String claimId, String vin){
        
        try{
        	HTTP h = new HTTP();
			HTTPRequest request = new HTTPRequest();
        	request.setMethod('GET');
        	String CARFAXURL = QDX_Property.propValueForLabel('CARFAX_PDF_URL');
        	String CARFAXUsername = QDX_Property.propValueForLabel('CARFAX_Username');
       		request.setEndpoint(CARFAXURL+'?uid='+CARFAXUsername+'&vin='+vin+'&referenceNumber='+claimId);
			HTTPResponse resp = h.send(request);
            
			if(resp.getStatusCode()==200){
        	
            	ContentVersion fileToUpload = new ContentVersion();
    			fileToUpload.ContentLocation = 'S'; // Salesforce. The other option is: 'E'
            
            	Claim clm = [SELECT id, PolicyNumberId,Usage_Count__c FROM Claim where Id = :claimId LIMIT 1];
                if(clm.Id != NULL){
                	InsurancePolicy contract = [select id, Client__r.AccountNumber, Name from InsurancePolicy where Id = :clm.PolicyNumberId];
                    if(contract.Id != NULL){
                        fileToUpload.title = contract.Client__r.AccountNumber+' - '+contract.Name+' - '+ Datetime.now().format('MM/dd/yyyy');
            			fileToUpload.pathOnClient = contract.Client__r.AccountNumber+' - '+contract.Name+' - '+ Datetime.now().format('MM/dd/yyyy')+'.pdf';
            			QDX_LOG.debug('fileToUpload.title: '+fileToUpload.title);
                		fileToUpload.versionData = resp.getBodyAsBlob();
    					Database.insert(fileToUpload);
 			
                		// Create a ContentDocument Link Record
 						// First get the content document Id from ContentVersion
 						Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id =:fileToUpload.Id].ContentDocumentId;

                        if(contentDocumentId != NULL){
                        	//Create ContentDocumentLink
							ContentDocumentLink linkToRecord = new ContentDocumentLink();
							linkToRecord.ContentDocumentId = contentDocumentId;
							linkToRecord.LinkedEntityId = claimId; // RecordID of the patent
							linkToRecord.ShareType = 'I'; // Inferred permission
            				Database.insert(linkToRecord);
            				String contentDocumentURL = QDX_Property.propValueForLabel('Marathon Org URL');
            				contentDocumentURL += UtilityClass.FILE_PREVIEW_URL + contentDocumentId;
            				output.put('contentDocumentId',contentDocumentId);
            				output.put('contentDocumentURL',contentDocumentURL);
            				output.put('isSuccess',true);
                            if(clm.Usage_Count__c != NULL){
                                clm.Usage_Count__c =  clm.Usage_Count__c + 1;
                            }
                            else{
                                clm.Usage_Count__c =  1;
                            }
                            clm.Date_Processed__c = System.now();
                            update clm;
                        }
                    }
                }    
        	} 
            if(output.get('isSuccess') == null){
            	output.put('isSuccess',false);
            }
    	}Catch(Exception ex){
        	QDX_LOG.error('Exception occured: '+ex);
        } finally{
            QDX_Log.publish();
        }
        return output;
    }
}