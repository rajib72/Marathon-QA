/**
* @author Jigar Trivedi
* @dateModified 2024-07-31 Saurabh Rawat
* @description This class is used for handling payment integration via an invocable Apex method.
*/
public with sharing class PaymentIntegrationHandler{
    
    /**
* Invocable method to handle payment integration.
* @param requests List of Request object containing ClaimItem lists.
* @return List of Response object indicating success or error for each request.
*/
    @InvocableMethod(label = 'PaymentInvocableCallout')
    public static List<Response> execute(List<Request> requests){
        List<Response> responses = new List<Response>();
        try{
            Set<Id> claimItemIDs = new Set<Id>();
            Set<Id> claimIdSet = new Set<Id>();
            List<AggregateResult> results = new List<AggregateResult>();
            List<ClaimItem> claimItems = new List<ClaimItem>();
            Map<Id,Claim> claimMap = new Map<Id,Claim>();
            Map<String,Decimal> PayeeGroupedAmount = new Map<String,Decimal>();
            Map<String,String> ClaimPayeeRequestMap = new Map<String,String>();
            Map<String,QDX_Property> credsMap = PaymentCalloutHandler.invokeMethod();
            Map<String,Map<String,Object>> payeeClaimResponseMap = new Map<String,Map<String,Object>>();
            Map<String,Payment__c> payeeClaimPaymentMap = new Map<String,Payment__c>();
            Set<Id> payeeIds = new Set<Id>();
            Map<Id, Account> payeeDetails = new Map<Id, Account>();
            String claimId;
            Claim claimObj = new Claim();
            //Extracting Claim and CLaimItems
            for(ClaimItem each : requests.get(0).claimItemList){
                claimItemIDs.add(each.Id);
                claimIdSet.add(each.ClaimId);
            }
            claimId = requests.get(0).claimItemList[0].ClaimId;
            if(claimIdSet.size() > 0){
                //Fetch claim for Contract Number and Claim Id
                claimMap = new Map<Id,Claim>([Select Id, Name, PolicyNumber.Name, PolicyNumberId, Repair_Email__c, PolicyNumber.Insurance_Code__c, PolicyNumber.NameInsured.Name, PolicyNumber.Client__r.Name, PolicyNumber.VIN__c from Claim Where Id IN :claimIdSet]);    
                List<Id> claimIds = new List<Id> (claimMap.keySet());
                if(claimMap.get(claimIds[0]).Repair_Email__c == null) {
                    claimObj = new Claim(Id = claimIds[0]);
                    claimObj.is_Payment_via_Fax__c = true;
                }
                //Fetch Amount Grouped by CLaim and Payee
                results = [Select SUM(NetClaim__c) groupedAmount, Payee_Name__c, Payee_Name__r.Name payeeName from ClaimItem Where Id IN :claimItemIDs GROUP BY Payee_Name__c, Payee_Name__r.Name LIMIT 2000];
                //If There are such Records Either have Email or Fax then proceed for callout
                if(results.size() > 0){
                    String payeeName;
                    Decimal netClaimTotal = 0.0;
                    for(AggregateResult result : results) {
                        payeeName = String.valueOf(result.get('Payee_Name__c'));
                        Double netClaim = Double.valueOf(result.get('groupedAmount'));
                        netClaimTotal = Decimal.valueOf(netClaim).setScale(2, System.RoundingMode.HALF_UP);
                        PayeeGroupedAmount.put(payeeName + '-'+ claimId, netClaimTotal);
                        payeeIds.add(String.valueOf(result.get('Payee_Name__c')));
                    }
                    if(!payeeIds.isEmpty()) {
                        for(Account acc : [SELECT Id, Name FROM Account WHERE ID IN : payeeIds]) {
                            payeeDetails.put(acc.Id, acc);
                        }
                    }
                    
                    //looping on Grouped Payee Amount for creation of request body
                    for(String payeeClaimId : PayeeGroupedAmount.keyset()){
                        //Creating Request Map for Value Assignment
                        String payeeId = payeeClaimId.split('-').get(0);
                        String deliveryMethod = '';
                        String requestBody = generateXML(credsMap, payeeId, claimId, claimMap, PayeeGroupedAmount, payeeDetails);
                        ClaimPayeeRequestMap.put(payeeClaimId,requestBody);
                    }
                    // Perform Callout and Map Credit Card information
                    for(String PayeeClaimId : ClaimPayeeRequestMap.keyset()){
                        Map<String,String> tempResponseMap = new Map<String,String>();
                        try{
                            HttpResponse response = OAuthRequestGenerator.sendRequest(ClaimPayeeRequestMap.get(PayeeClaimId));
                            
                            //added by Swastika on 19th August 2026
                            System.debug('========== BOK STATUS CODE ==========');
                            System.debug(response.getStatusCode());
                            
                            System.debug('========== BOK RESPONSE BODY ==========');
                            System.debug(response.getBody());
                            
                            System.debug('========== BOK CORRELATION ID ==========');
                            System.debug(response.getHeader('correlation-id'));
                            
                            if(response.getStatusCode() == 200 && String.isNotBlank(response.getBody())){
                                //Map<String, Object> CreatePurchaseLogResult_NODE = PaymentCalloutHandler.parsedPurchaseLogResponse(PaymentCalloutHandler.xmlToMap(response.getBody()));
                                Map<String, Object> parsedResponse =
                                    PaymentCalloutHandler.xmlToMap(
                                        response.getBody()
                                    );
                                
                                Map<String, Object> CreatePurchaseLogResult_NODE =
                                    PaymentCalloutHandler.parsedPurchaseLogResponse(
                                        parsedResponse
                                    );
                                
                                Map<String, String> bokIdentifiers =
                                    PaymentCalloutHandler.parsedPurchaseIdentifiers(
                                        parsedResponse
                                    );
                                // Temporary debug for BOK identifiers
                                System.debug('========== BOK PURCHASE REQUEST ID ==========');
                                System.debug(bokIdentifiers.get('purchaseRequestId'));
                                
                                System.debug('========== BOK VCN ID ==========');
                                System.debug(bokIdentifiers.get('vcnId'));
                                //Check if Returned status is Success
                                if(CreatePurchaseLogResult_NODE!= null && CreatePurchaseLogResult_NODE.size() > 0 && CreatePurchaseLogResult_NODE.containsKey('Status') && CreatePurchaseLogResult_NODE.get('Status') == 'S'){
                                    tempResponseMap.put('status','success');
                                    Payment__c newPayment = new Payment__c();
                                    newPayment.Account__c = PayeeClaimId.split('-').get(0);
                                    newPayment.Credit_Card_Number__c = CreatePurchaseLogResult_NODE.containsKey('Pan')?(String)CreatePurchaseLogResult_NODE.get('Pan'):'';
                                    newPayment.Credit_Card_CVC__c = CreatePurchaseLogResult_NODE.containsKey('Avv')?(String)CreatePurchaseLogResult_NODE.get('Avv'):''; 
                                    newPayment.BOK_Purchase_Request_Id__c =
                                        bokIdentifiers.containsKey('purchaseRequestId')
                                        ? bokIdentifiers.get('purchaseRequestId')
                                        : null;
                                    
                                    newPayment.BOK_VCN_Id__c =
                                        bokIdentifiers.containsKey('vcnId')
                                        ? bokIdentifiers.get('vcnId')
                                        : null;
                                    if(CreatePurchaseLogResult_NODE.containsKey('Expiry') &&  String.isNotBlank((String)CreatePurchaseLogResult_NODE.get('Expiry'))){
                                        String expiryDate = (String)CreatePurchaseLogResult_NODE.get('Expiry');
                                        String year = '20' + expiryDate.left(2);
                                        String month = expiryDate.right(2);
                                        newPayment.Credit_Card_Expiration__c = Date.newInstance(Integer.valueOf(year), Integer.valueOf(month), 1);
                                    }
                                    payeeClaimPaymentMap.put(PayeeClaimId,newPayment);
                                }else{
                                    //log QDX Error specific to API
                                    String errorCode = CreatePurchaseLogResult_NODE.containsKey('errorCode') ? String.valueOf(CreatePurchaseLogResult_NODE.get('errorCode')) : '';
                                    String errorDescription = CreatePurchaseLogResult_NODE.containsKey('errorDescription') ? String.valueOf(CreatePurchaseLogResult_NODE.get('errorDescription')) : '';
                                    tempResponseMap.put('status','error');
                                    tempResponseMap.put('response','Code:' + errorCode + 'Desc:' + errorDescription + 'correlation-id:' + response.getHeader('correlation-id'));
                                    QDX_Log.Requests errorReq = new QDX_Log.Requests();
                                    errorReq.errorMessage = errorCode + '. ' + errorDescription;
                                    errorReq.flowName = 'PaymentIntegrationhandler.cls';
                                    QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
                                }
                            }else{
                                tempResponseMap.put('status','error');
                                tempResponseMap.put('response','API callout error: Response Code:'+response.getStatusCode() + 'Error Description: ' + response.getBody() + 'correlation-id: ' + response.getHeader('correlation-id'));
                                QDX_Log.Requests errorReq = new QDX_Log.Requests();
                                errorReq.errorMessage = 'API callout error: Response Code: '+response.getStatusCode() + 'Error Description: ' + response.getBody() + 'correlation-id: ' + response.getHeader('correlation-id');
                                errorReq.flowName = 'PaymentIntegrationhandler.cls';
                                QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
                                //log QDX errror specific to API Request format
                            }
                            payeeClaimResponseMap.put(PayeeClaimId,tempResponseMap);
                        }catch(Exception ex){
                            QDX_Log.Requests errorReq = new QDX_Log.Requests();
                            errorReq.errorMessage = 'error: '+ex.getMessage() + 'at line: '+ex.getLineNumber();
                            errorReq.flowName = 'PaymentIntegrationhandler.cls';
                            QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
                        }
                    }
                } 
                //If There are some payment records then insert it
                if(!payeeClaimPaymentMap.isEmpty()){
                    Database.insert(payeeClaimPaymentMap.values());
                }
                Integer successCount = 0;
                //Update CLaim Items with Payment
                for(ClaimItem each : requests.get(0).claimItemList){
                    if(payeeClaimPaymentMap != null && !payeeClaimPaymentMap.containsKey(each.Payee_Name__c + '-' + each.ClaimId) ){//check If Payment is present for certain Payee and Claim
                        each.Last_WEX_Error__c =((Map<String,String>) payeeClaimResponseMap.get(each.Payee_Name__c + '-' + each.ClaimId)).get('response').abbreviate(255);
                    }else if(payeeClaimPaymentMap != null && payeeClaimPaymentMap.containsKey(each.Payee_Name__c + '-' + each.ClaimId)){//check If Payment is present
                        each.Payment__c = payeeClaimPaymentMap.get(each.Payee_Name__c + '-' + each.ClaimId).Id;
                        each.Last_WEX_Error__c = null;
                        each.Status__c = 'Paid';
                        successCount++;
                    }
                }
                //Update Claim Items
                if(requests.get(0).claimItemList.size() > 0){
                    Database.update(requests.get(0).claimItemList);
                }
                if(claimObj.is_Payment_via_Fax__c == true) {
                    Database.update(claimObj, false);
                }
                responses.add( new Response(successCount == requests.get(0).claimItemList.size()?'Success':successCount < requests.get(0).claimItemList.size() && successCount > 0? 'Partial': 'Error') );
            }
        } catch(Exception ex){
            // Log exceptions.
            responses.add( new Response('Error') );
            QDX_LOG.error('Exception occured: '+ex);
            QDX_Log.Requests errorReq = new QDX_Log.Requests();
            errorReq.errorMessage = ex.getmessage() + '' + ex.getStackTraceString();
            errorReq.flowName = 'PaymentIntegrationhandler.cls';
            QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
        }
        return responses;
    }
    
    /**
* Generates the XML based on the set variables.
* @return The XML as a string.
*/
    public Static String generateXML(Map<String,QDX_Property> credsMap, String payeeId, String claimId, Map<Id,Claim> claimMap, Map<String,Double> PayeeGroupedAmount, Map<Id, Account> payeeDetails) {
        // Custom fields
        List<Map<String, String>> templateCustomFields = new List<Map<String, String>>();
        String shopName = payeeDetails.containsKey(payeeId) ? payeeDetails.get(payeeId).Name : '';
        String claimNumber = claimMap.containsKey(claimId) ? claimMap.get(claimId).Name : '';
        String policyNumber = claimMap.containsKey(claimId) ? claimMap.get(claimId).PolicyNumber.Name : '';
        String client = claimMap != null && claimMap.containsKey(claimId) && claimMap.get(claimId).PolicyNumber.Client__r.Name != null ? getTruncatedValue(claimMap.get(claimId).PolicyNumber.Client__r.Name) : '';
        
        templateCustomFields.add(new Map<String, String> {'Purchase Type' => (String) UtilityClass.PURCHASE_TYPE});
        templateCustomFields.add(new Map<String, String> {'ClaimNumber' => claimNumber});
        templateCustomFields.add(new Map<String, String> {'ContractNumber' => getTruncatedValue(policyNumber)});
        templateCustomFields.add(new Map<String, String> {'Client' => client});
        templateCustomFields.add(new Map<String, String> {'Shop Name' => getTruncatedValue(shopName)});
        if(claimMap.get(claimId).PolicyNumber.Insurance_Code__c!=Null){
            templateCustomFields.add(new Map<String, String> {'Insurance Code' => claimMap.get(claimId).PolicyNumber.Insurance_Code__c});
        }
        if(claimMap.get(claimId).PolicyNumber.VIN__c!=Null){
            templateCustomFields.add(new Map<String, String> {'VIN Number' => claimMap.get(claimId).PolicyNumber.VIN__c});
        }
        
        String mcRealCardNumber = credsMap.get('MC Real Card Number').textValue;
        String mcRealCardNumberAlias = credsMap.get('MC Real Card Number Alias').textValue;
        String mcCompanyId = credsMap.get('MC Company Id').textValue;
        String mcSupplierId = credsMap.get('MC Supplier Id').textValue;
        String mcPurchaseTemplateId = credsMap.get('MC Purchase Template Id').textValue;
        Integer mcValidityPeriod = Integer.valueOf(credsMap.get('MC Validity Period').numberValue);
        String mcDescription = credsMap.get('MC Description').textValue;
        String mcConsumerKey = credsMap.get('MC Consumer Key').textValue;
        String mcPrivateKey = credsMap.get('MC Private Key').textValue;
        String today = String.valueOf(Date.today());
        Date toBusinessDay = Date.valueOf(new BusinessDaysUtility().addDays(System.now(), 3));
        String toDate = String.valueOf(toBusinessDay);
        Double netClaim = PayeeGroupedAmount.get(payeeId + '-' + claimId);
        String supplierEmail = String.valueOf(claimMap.get(claimId).Repair_Email__c) != null ? String.valueOf(claimMap.get(claimId).Repair_Email__c) : UserInfo.getUserEmail();
        Dom.Document doc = new Dom.Document();
        
        // Root Envelope
        String ser = 'http://mastercard.com/sd/pc2/service';
        String ser1 = 'http://mastercard.com/sd/pc/service';
        String soapenv = 'http://schemas.xmlsoap.org/soap/envelope/';
        String wsu = 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd';
        Dom.XmlNode envelope = doc.createRootElement('Envelope', soapenv, 'soapenv');
        envelope.setNamespace('ser', ser);
        envelope.setNamespace('ser1', ser1);
        envelope.addChildElement('soapenv:Header', null, null);
        
        // Body
        Dom.XmlNode body = envelope.addChildElement('soapenv:Body', null, null);
        body.setNamespace('wsu', wsu);
        
        // Request structure
        Dom.XmlNode request = body.addChildElement('ser:submitPurchaseRequestRequest', null, null);
        Dom.XmlNode submitPurchaseRequest = request.addChildElement('ser:SubmitPurchaseRequest', null, null);
        
        // RCN Data
        Dom.XmlNode rcnData = submitPurchaseRequest.addChildElement('ser:RCNData', null, null);
        rcnData.addChildElement('ser1:rcnId', null, null).addTextNode(mcRealCardNumber);
        rcnData.addChildElement('ser1:rcnAlias', null, null).addTextNode(mcRealCardNumberAlias);
        
        // Company ID and Validity
        submitPurchaseRequest.addChildElement('ser:companyId', null, null).addTextNode(mcCompanyId);
        submitPurchaseRequest.addChildElement('ser:validFor', null, null).addTextNode(UtilityClass.VALIDFOR);
        submitPurchaseRequest.addChildElement('ser:description', null, null).addTextNode(mcDescription);
        
        // Template Details
        Dom.XmlNode templateDetails = submitPurchaseRequest.addChildElement('ser:TemplateDetails2', null, null);
        templateDetails.addChildElement('ser:templateId', null, null).addTextNode(mcPurchaseTemplateId);
        
        // Full Template Rule Details
        Dom.XmlNode fullTemplateRuleDetails = templateDetails.addChildElement('ser:fullTemplateRuleDetails', null, null);
        fullTemplateRuleDetails.addChildElement('ser:ruleName', null, null).addTextNode(UtilityClass.RULENAME);
        fullTemplateRuleDetails.addChildElement('ser:ruleType', null, null).addTextNode(UtilityClass.RULETYPE);
        
        // Template Validity Period Control
        Dom.XmlNode validityControl = fullTemplateRuleDetails.addChildElement('ser:templateControl', null, null);
        validityControl.setAttribute('xsi:type', 'ser:templateValidityPeriodControl2');
        validityControl.setNamespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance');
        validityControl.addChildElement('ser:from', null, null).addTextNode(today);
        validityControl.addChildElement('ser:to', null, null).addTextNode(toDate);
        validityControl.addChildElement('ser:timeZone', null, null).addTextNode(UtilityClass.TIMEZONE);
        
        // Template Amount Range Control
        Dom.XmlNode amountControl = fullTemplateRuleDetails.addChildElement('ser:templateControl', null, null);
        amountControl.setAttribute('xsi:type', 'ser:templateAmountRangeControl2');
        amountControl.setNamespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance');
        amountControl.addChildElement('ser:minAmount', null, null).addTextNode(String.valueOf(netClaim));
        amountControl.addChildElement('ser:maxAmount', null, null).addTextNode(String.valueOf(netClaim));
        amountControl.addChildElement('ser:strictPreAuthCheck', null, null).addTextNode(String.valueOf(false));
        amountControl.addChildElement('ser:negate', null, null).addTextNode(String.valueOf(false));
        amountControl.addChildElement('ser:currencyType', null, null).addTextNode(UtilityClass.CURRENCYTYPE);
        amountControl.addChildElement('ser:currencyCode', null, null).addTextNode(UtilityClass.CURRENCYCODE);
        
        // Velocity Control
        Dom.XmlNode velocityControl = fullTemplateRuleDetails.addChildElement('ser:templateControl', null, null);
        velocityControl.setAttribute('xsi:type', 'ser:VelocityControlType2');
        velocityControl.setNamespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance');
        velocityControl.addChildElement('ser:maxTrans', null, null).addTextNode(String.valueOf(UtilityClass.MAXTRANS));
        velocityControl.addChildElement('ser:cumulativeLimit', null, null).addTextNode(String.valueOf(netClaim));
        velocityControl.addChildElement('ser:period', null, null).addTextNode(UtilityClass.PERIOD);
        
        // Template Custom Fields
        Dom.XmlNode customFieldsNode = templateDetails.addChildElement('ser:templateCustomField', null, null);
        Integer i = 0;
        for (Map<String, String> field : templateCustomFields) {
            List<String> keys = new List<String>(field.keySet());
            Dom.XmlNode fieldNode = customFieldsNode.addChildElement('ser:templateCustomField', null, null);
            fieldNode.addChildElement('ser1:customFieldName', null, null).addTextNode(keys[0]);
            fieldNode.addChildElement('ser1:customFieldValue', null, null).addTextNode(field.get(keys[0]));
            i++;
        }
        
        // Supplier Details
        Dom.XmlNode supplierDetails = submitPurchaseRequest.addChildElement('ser:supplierDetails', null, null);
        supplierDetails.addChildElement('ser:supplierId', null, null).addTextNode(mcSupplierId);
        supplierDetails.addChildElement('ser:supplierEmails', null, null).addTextNode(supplierEmail);
        supplierDetails.addChildElement('ser:notifySupplier', null, null).addTextNode(String.valueOf(true));
        
        // Disable Card Image
        submitPurchaseRequest.addChildElement('ser:disableCardImage', null, null).addTextNode(UtilityClass.DISABLECARDIMAGE);
        // Return the XML as a string
        return doc.toXmlString();
    }
    
    public Static String getTruncatedValue(String val) {
        String retValue;
        if(!String.isEmpty(val)) {
            retValue = val.length() > 80 ? val.substring(0,80) : val;
        } else {
            retValue = '';
        }
        return retValue;
    }
    
    /**
* Class to represent the request structure for the invocable method.
*/
    public class Request {
        @InvocableVariable(label = 'ClaimItemList' required = true)
        public List<ClaimItem> claimItemList;
    }
    
    /**
* Class to represent the response structure for the invocable method.
*/
    public class Response {
        @InvocableVariable(label = 'ResponseVar')
        public String outputResponse;
        public Response(String outputResponse){
            this.outputResponse = outputResponse;
        }
    }
}