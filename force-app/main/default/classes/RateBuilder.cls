/**
* @author: Sujit Dengale
* @dateModified: 18-04-2025
* @description: Apex class for implementation of Rate Builder
*/
public  class RateBuilder {
    
    @AuraEnabled(cacheable=true)
    public static String getAllClients() { 
        String responseBody;
        try{
            List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>([SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE LIMIT 1) FROM CalculationMatrix WHERE UniqueName = 'Dealer_Code_Lookup']);
            // Instantiate HTTP request and response objects
            if(!dealerLookupRec.isEmpty()){
               responseBody  = fetchLookupTableRows(dealerLookupRec[0].Id, dealerLookupRec[0].CalculationMatrixVersions[0].Id);
            }
            if(responseBody != null){
                System.debug('calling rateBuilder class'+responseBody);
                return responseBody;
            }
        }
        catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
            throw new AuraHandledException(System.Label.Error_Message);
        }
        return null;
    }
    
    public static String fetchLookupTableRows(String lookupTableId, String lookupTableVersionId) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        
        request.setHeader('Content-Type', 'application/json');
        String domainURL = URL.getOrgDomainUrl().toExternalForm();
        
      	String endpoint = 'callout:SF_OMNI_API/services/data/v62.0/connect/omnistudio/decision-matrices/' + lookupTableId + '/versions/' + lookupTableVersionId + '/rows';
        
        request.setEndpoint(endpoint);
        
        // Send the HTTP request and get the response
        HttpResponse response = http.send(request);
        return response.getBody();
    }
    
    //get Insurance Carrier details from related Allocation Code records
    @AuraEnabled(cacheable=true)
    public static List<String> getInsCarriers(String client, String product, String coverageLevel) {
        List<String> insCarrier = new List<String>();
        List<String> coverages = coverageLevel.split(';');
        for(Allocation_Code__c code : [SELECT Id, Name, Insurance_Carrier__c FROM Allocation_Code__c WHERE Product__c =:product AND Coverage_Level__c IN :coverages AND Client__r.Name =:client]){
            insCarrier.addAll(code.Insurance_Carrier__c.split(';'));
        }
        Set<String> insCarrierSet = new Set<String>(insCarrier);
        return new List<String>(insCarrierSet);
    }
    
    //get state details from related Allocation Code records
    @AuraEnabled(cacheable=true)
    public static List<String> getStates(String client, String product, String coverageLevel) {
        List<String> states = new List<String>();
        List<String> coverages = coverageLevel.split(';');
        for(Allocation_Code__c code : [SELECT Id, Name, States__c FROM Allocation_Code__c WHERE Product__c =:product AND Coverage_Level__c IN :coverages AND Client__r.Name =:client]){
            states.addAll(code.States__c.split(';'));
        }
        Set<String> stateSet = new Set<String>(states);
        return new List<String>(stateSet);
    }
    
    //get Contract Type details from related Coverage Level record
    @AuraEnabled(cacheable=true)
    public static String getContractType(String coverageLevel) {
        String returnValue = '';
        if(!String.isBlank(coverageLevel)) {
            String coverage = coverageLevel.split(';')[0];
            List<Coverage_Level__c> levels = new List<Coverage_Level__c>([SELECT Id, Contract_Type__c FROM Coverage_Level__c WHERE Name =: coverage]);
            returnValue = levels.size() > 0 ? levels[0].Contract_Type__c : '';
        }
        return returnValue;
    }
      
}