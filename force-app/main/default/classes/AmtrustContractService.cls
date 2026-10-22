/**
* @author Sujit Dengale
* @dateModified 22-07-2025
* @description -AmtrustContractService call from Pentaho to get the contract details
*/
@RestResource(UrlMapping='/AmtrustContractService/*')
global class AmtrustContractService {
    
    public static Map<String, String> requestDataMap = new Map<String, String>();
    public static Map<String, String> responseMap = new Map<String, String>();
    
    @HttpPost
    global static String processRateImplementation() {
        AmtrustContractService.APIRequest requestObj;
        String responseStr = '';
		RestResponse res = RestContext.response;
        
        try {
            requestObj = (AmtrustContractService.APIRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(),
                AmtrustContractService.APIRequest.class
            );
            responseStr = setup(requestObj);
        } catch (Exception e) {
            QDX_LOG.error('Message*****' + e.getMessage() + '@@@@@@@@@@Line Number*******' + e.getLineNumber());
            responseStr = generateErrorResponse(e.getMessage());
        } finally {
            QDX_LOG.publish();
        }
        return responseStr;
    }
    // method to fetch the contract ids based on request Type
    global static String setup(AmtrustContractService.APIRequest requestObj) {
        String response = '';
        requestDataMap.put('RequestType', requestObj.RequestType);
        
        if (requestObj != null && requestObj.RequestType == 'ContractHomeReport') {
            String recordTypeDeveloperName = 'Home_Warranty';
            return fetchContractIDs(recordTypeDeveloperName);
        }
        if (requestObj != null && requestObj.RequestType == 'ContractAutoReport') {
            String recordTypeDeveloperName = 'Auto_Warranty';
            return fetchContractIDs(recordTypeDeveloperName);
        }
        return null;
    }
    
    global class APIRequest {
        global String RequestType;
    }
    
    public static String generateErrorResponse(String errorMessage) {
        AmtrustContractService.ErrorResponseGenerator errorResponseObj = new AmtrustContractService.ErrorResponseGenerator();
        errorResponseObj.status = 400;
        errorResponseObj.error = errorMessage;
        return JSON.serialize(errorResponseObj);
    }
    
    public class ErrorResponseGenerator {
        public Integer status;
        public String error;
    }
    
    // Method to query the records and return response
    public static String fetchContractIDs(String recordTypeDeveloperName) {
        List<String> carriers = new List<String>{
            'Security National Insurance Company',
            'Technology Insurance Company',
            'Wesco Insurance Company'
        };
        
        List<InsurancePolicy> contractRecords = [
            SELECT Id, Contract_Term_Months__c, Next_Cycle_Date__c, Earliest_Contract_Funded_Date__c,
                   Reinstatement_Date__c,
                   (SELECT Id, CreatedDate FROM Fundings__r)
            FROM InsurancePolicy
            WHERE
                (
                    (Contract_Term_Months__c = 1 AND Next_Cycle_Date__c = THIS_MONTH)
                    OR Earliest_Contract_Funded_Date__c = LAST_MONTH
                    OR Reinstatement_Date__c = LAST_MONTH
                )
                AND Ins_Carrier__c IN :carriers
                AND RecordType.DeveloperName  = :recordTypeDeveloperName
            LIMIT 50000
        ];
        
        Set<String> validContractIds = new Set<String>();
        
        for (InsurancePolicy oneContract : contractRecords) {
		
			if(oneContract.Earliest_Contract_Funded_Date__c != NULL &&  isFromLastMonth(oneContract.Earliest_Contract_Funded_Date__c)){
				validContractIds.add('\'' + oneContract.Id + '\'');
				continue;
			}
			if(oneContract.Reinstatement_Date__c != NULL && isFromLastMonth(oneContract.Reinstatement_Date__c.date())){
				validContractIds.add('\'' + oneContract.Id + '\'');
				continue;
			}
		
		
            if( oneContract.Next_Cycle_Date__c != NULL  && oneContract.Contract_Term_Months__c != NULL  && oneContract.Contract_Term_Months__c == 1 &&
				isFromThisMonth(oneContract.Next_Cycle_Date__c)){ 
				
				for(Funding__c fundingRecord: oneContract.fundings__r){
					if(isFromLastMonth(fundingRecord.CreatedDate.date())){
						 validContractIds.add('\'' + oneContract.Id + '\'');
						continue;
					}
				}
                 
            }
            
            
             
        }
        if(! validContractIds.isEmpty() && validContractIds != NULL){
            return String.join(validContractIds, ',');
        }
         return null;
        
    }
    
    // check the date if it's from Last Month
    public static Boolean isFromLastMonth(Date inputDate) {
    Date today = Date.today();

    // Get the first and last day of last month
    Date firstDayOfThisMonth = Date.newInstance(today.year(), today.month(), 1);
    Date firstDayOfLastMonth = firstDayOfThisMonth.addMonths(-1);
    Date lastDayOfLastMonth = firstDayOfThisMonth.addDays(-1);

    // Return true if the input date falls in last month
    return inputDate >= firstDayOfLastMonth && inputDate <= lastDayOfLastMonth;
}

    // check the date if it's from This Month
    public static Boolean isFromThisMonth(Date inputDate) {
    if (inputDate == null) return false; // null is not in this month
    
    Date today = Date.today();
    Date firstDayOfThisMonth = Date.newInstance(today.year(), today.month(), 1);
    Date lastDayOfThisMonth = firstDayOfThisMonth.addMonths(1).addDays(-1);
    
    return inputDate >= firstDayOfThisMonth && inputDate <= lastDayOfThisMonth;
}

}