/**
 * @description       : 
 * @author            : Hitarth Trivedi
 * @group             : 
 * @last modified on  : 08-27-2024
 * @last modified by  : Hitarth Trivedi
**/
global class BatchContractUpdates implements Database.Batchable<sObject>, Schedulable {
	global void execute(SchedulableContext sc) {
        //Execute method of Schedulable, for Scheduling a class
        Database.executeBatch(new BatchContractUpdates());
    }
    //Query all non Secure One records 
    global Database.QueryLocator start(Database.BatchableContext BC) {
        Date todayDate = System.Today(); 
        String product = UtilityClass.PRODUCT_SECUREONE;
        String query = 'SELECT Id, DLRS_Total_Funded_Amount_from_Funding__c from InsurancePolicy WHERE Product__c <> :product';
        return Database.getQueryLocator(query);
    }
    
    global void execute(Database.BatchableContext BC, List<InsurancePolicy> ContractsList) {
        List<InsurancePolicy> contractsToUpdate = new List<InsurancePolicy>();
        try {
            Set<Id> contractIds = new Set<Id>();
            for(InsurancePolicy contract : ContractsList) {
                contractIds.add(contract.Id);
            }
            //Populate the total Funded Amount from Funding record to respective contract
            List<AggregateResult> groupedResults = [select sum(Funded_Amount__c) SumAmount, Contract__c from Funding__c WHERE Contract__c IN :contractIds group by Contract__c];
            for(AggregateResult result : groupedResults) {
                Decimal sumAmount = (Decimal)result.get('SumAmount');
                String contractId = (String)result.get('Contract__c');
            	if(sumAmount!= NULL && sumAmount>0) {
                    InsurancePolicy contract = new InsurancePolicy();
                    contract.Id = contractId;
                    contract.DLRS_Total_Funded_Amount_from_Funding__c = sumAmount;
                	contractsToUpdate.add(contract);
            	}
        	}
            if(contractsToUpdate.size()>0) {
                Database.update(contractsToUpdate, false);
            }
        } Catch(Exception e) {
       		QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
       	    QDX_Log.publish();
        }
        
    }
    
    global void finish(Database.BatchableContext BC) { }
}