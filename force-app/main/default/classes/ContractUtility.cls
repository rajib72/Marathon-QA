/**
 * @author Saurabh Rawat
 * @dateModified 2024-05-06
 * @description Utility class for handling operations related to contract.
 */
public class ContractUtility {
    
    /** Finds Contracts based on a list of policy numbers and return a map of policy number to Contract Ids.
     *  @param policyNumbers List of policy numbers to search for.
     *  @return Map containing the map of policy numbers to Contract Ids.
     */
    
    
    public static Map<String,InsurancePolicy> findContractsfromNumber(Set<String> policyNumbers){
        Map<String,InsurancePolicy> contractNameMap = new Map<String,InsurancePolicy> ();
        
        if(policyNumbers != null && policyNumbers.size()>0){
            // Query contracts where their Name matches any of the policy numbers. 
            List<InsurancePolicy> matchingContracts = [SELECT Id, Name,DLRS_Total_Funded_Amount_from_Funding__c,Net_Dealer_Cost__c FROM InsurancePolicy WHERE Name IN: policyNumbers];
            
            for(InsurancePolicy contract: matchingContracts){
                // Populate the map with Name as key and contract id as value.
                contractNameMap.put(contract.Name, contract);
            }
        }
        // return the map containing the mapping from policy numbers to contract Ids.
        return contractNameMap;
    }
    
    /**
     * generic methods that queries DM rows
     */
    public static String fetchLookupTableRows(String lookupTableId, String lookupTableVersionId) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        // Set HTTP method (e.g., POST or GET based on service mehtod)
        request.setMethod('GET');
        
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        
        // Set the endpoint URL for the decision matrix service
        String domainURL = URL.getOrgDomainUrl().toExternalForm();
        request.setEndpoint(domainURL + '/services/data/v62.0/connect/omnistudio/decision-matrices/' + lookupTableId + '/versions/' + lookupTableVersionId + '/rows');
        
        // Send the HTTP request and get the response
        HttpResponse response = http.send(request);
        return response.getBody();
    }
    
    
    /**
     * Calculates the refund amount for each contract in the list based on the total premium amount.
     * @param contractRefundInfo List of RefundRequest containing the contract information.
     * @return List of RefundRequest with updated refund amounts.
     */
@InvocableMethod(label='Calculate Refund Amount')
  public static List<RefundRequest> calculateRefundAmount(List<RefundRequest> contractRefundInfo) {
      for(RefundRequest contract : contractRefundInfo){
          contract.RefundAmount = (contract.TotalPremiumAmount!=null?contract.TotalPremiumAmount:0) *  0.5;
      }  
    return contractRefundInfo;
}
    /**
     * Inner class representing a request for a refund on a contract.
     */
    
   public class RefundRequest {
    @InvocableVariable(required=true)
     public String contractId;
    @InvocableVariable 
     public Double TotalPremiumAmount;
    @InvocableVariable
     public Double RefundAmount;
   }
}