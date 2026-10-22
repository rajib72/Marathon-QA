/**
* @author Sujit Dengale
* @dateModified 19-06-2026
* @ModifiedBy Raj Sekhar Mukherjee
* @description Trigger on Funding Object
*/
public class FundingTriggerHandler {
    public static void handleBeforeInsert(List<Funding__c> newFundings){
        updateStatus(newFundings,NULL);
    }
    
    public static void handleAfterInsert(List<Funding__c> newFundings, Map<Id,Funding__c> oldFundingsMap) {
        updateContractFundedDate(newFundings,oldFundingsMap);
        updateEarliestContractFundedDate(newFundings);
        //adding comment to check cicd
    }
    
    public static void updateStatus(List<Funding__c> newFundings, Map<Id,Funding__c> oldFundings){
        // this method is used for the upadting status of Contracts
        try{
            Set<String> policyNumbers = New Set<String> ();
            Map<String, InsurancePolicy> contractDetailMap = new Map<String, InsurancePolicy> ();
            if(oldFundings == NULL && ! newFundings.isEmpty()){
                for(Funding__c fundingRecord: newFundings){
                    if(fundingRecord.Contract_Number_from_Import__c != NULL){
                        policyNumbers.add(fundingRecord.Contract_Number_from_Import__c);
                    }
                }
            }
            if(!policyNumbers.isEmpty()){
                contractDetailMap = ContractUtility.findContractsfromNumber(policyNumbers);
                for(Funding__c fundingRecord: newFundings){
                    if(!contractDetailMap.isEmpty() && 
                       contractDetailMap.containsKey(fundingRecord.Contract_Number_from_Import__c)){
                           fundingRecord.Contract__c = contractDetailMap.get(fundingRecord.Contract_Number_from_Import__c).Id;
                           if(fundingRecord.Funded_Amount__c+contractDetailMap.get(fundingRecord.Contract_Number_from_Import__c).DLRS_Total_Funded_Amount_from_Funding__c > contractDetailMap.get(fundingRecord.Contract_Number_from_Import__c).Net_Dealer_Cost__c){
                               fundingRecord.Overfunding_Flagged_at__c = System.Now();
                           }
                       }
                    else{
                        fundingRecord.addError(UtilityClass.FUNDING_IMPORT_ERR_MSG);
                    }
                }
            }
        }
        catch(Exception e){
            QDX_Log.Requests req = new QDX_Log.Requests();
            req.errorMessage = e.getmessage();
            req.flowName = 'Trigger: Funding Import File Process';
            QDX_Log.publishError(new List<QDX_Log.Requests> {req});
        }
    }
    
    public static void updateContractFundedDate(List<Funding__c> newFundings, Map<Id,Funding__c> oldFundings){
        //Set Contract_Funded_Date__c for Non SecureOne Contracts
        Map<Id,Date> contractFundingMap = new Map<Id,Date>();
        Set<Id> contractsToUpdate = new Set<Id>();
        try {
            //Prepare a Map with Contract ID to update with the fundedDate value
            for(Funding__c funding : newFundings) {
                if(funding.Contract__c != NULL && funding.Created_Date_Only__c != NULL && funding.Contract__r.Product__c != 'SecureOne') {
                    if(contractFundingMap.containsKey(funding.Contract__c)) {
                        if(contractFundingMap.get(funding.Contract__c) < funding.Created_Date_Only__c ) {
                            contractFundingMap.put(funding.Contract__c,funding.Created_Date_Only__c);
                        }
                    } else {
                        contractFundingMap.put(funding.Contract__c,funding.Created_Date_Only__c);
                    }
                    contractsToUpdate.add(funding.Contract__c);
                }
            }
            //If the prepared Map is not empty then update the Contracts
            if(contractFundingMap.size()>0) {
                /* Id autoWarrantyRTId = UtilityClass.getsObjectRecordTypeId('InsurancePolicy', 'Auto_Warranty');
List<InsurancePolicy> contractsList = [SELECT Id FROM InsurancePolicy WHERE Id IN :contractsToUpdate AND RecordTypeId =: autoWarrantyRTId];
for(InsurancePolicy contract : contractsList) {
contract.Contract_Funded_Date__c = contractFundingMap.get(contract.Id);
}
Database.update(contractsList, false); */
                
                List<Id> autoWarrantyRTIds = UtilityClass.getsObjectRecordTypeId('InsurancePolicy', new List<String>{'Auto_Warranty', 'Home_Warranty'});
                List<InsurancePolicy> contractsList = [SELECT Id FROM InsurancePolicy 
                                                       WHERE Id IN :contractsToUpdate 
                                                       AND RecordTypeId IN :autoWarrantyRTIds];
                for(InsurancePolicy contract : contractsList) {
                    contract.Contract_Funded_Date__c = contractFundingMap.get(contract.Id);
                }
                Database.update(contractsList, false); 
                
            } 
        } Catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }
    //new method added to populate earliest funded date
    public static void updateEarliestContractFundedDate(List<Funding__c> newFundings){
        try {
            // Collect Contract Ids from the new Fundings
            Set<Id> contractIds = new Set<Id>();
            for(Funding__c f : newFundings){
                if(f.Contract__c != null && f.Created_Date_Only__c != null){
                    contractIds.add(f.Contract__c);
                }
            }
            
            if(contractIds.isEmpty()) return;
            
            // Fetch Contracts where Earliest_Contract_Funded_Date__c is NULL
            List<InsurancePolicy> contractsToUpdate = [
                SELECT Id, Earliest_Contract_Funded_Date__c
                FROM InsurancePolicy
                WHERE Id IN :contractIds
                AND Earliest_Contract_Funded_Date__c = NULL
            ];
            
            // Prepare a map for earliest created date per contract
            Map<Id, Date> earliestFundingMap = new Map<Id, Date>();
            for(Funding__c f : newFundings){
                if(f.Contract__c != null && f.Created_Date_Only__c != null){
                    // only set once per contract in this transaction
                    if(!earliestFundingMap.containsKey(f.Contract__c)){
                        earliestFundingMap.put(f.Contract__c, f.Created_Date_Only__c);
                    }
                }
            }
            
            // Assign earliest funding date to eligible contracts
            for(InsurancePolicy c : contractsToUpdate){
                if(earliestFundingMap.containsKey(c.Id)){
                    c.Earliest_Contract_Funded_Date__c = earliestFundingMap.get(c.Id);
                }
            }
            
            if(!contractsToUpdate.isEmpty()){
                update contractsToUpdate;
            }
        } catch (Exception e){
            QDX_Log.error('Error in updateEarliestContractFundedDate: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }
    
    public static void startAllocationProcess(List<Funding__c> newFundings, Map<Id, Funding__c> oldFundings) {
        
        Boolean shouldStartAllocation = false;
        
        for(Funding__c fundingRec : newFundings){
            
            Funding__c oldRec = oldFundings != null ? oldFundings.get(fundingRec.Id) : null;
            
            if( fundingRec.Contract__c != null && fundingRec.Funded_Amount__c != null &&
               ( Trigger.isInsert || ( oldRec != null && fundingRec.Funded_Amount__c != oldRec.Funded_Amount__c))){
                   shouldStartAllocation = true;
                   break;
               }
        }
        
        if(shouldStartAllocation){
            FundingAllocationOrchestrator.startAllocation();
        }
    }
}