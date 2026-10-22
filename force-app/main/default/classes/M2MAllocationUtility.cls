/*******************************************************************************************
* @File Name          : M2MAllocationUtility.cls
* @Author             : Abhishek Jain
* @Description        : This class is used to create allocation record for the funding record on the contract using the allocation code.
* Change History:

* DATE         AUTHOR                      Change Description
----------    --------------------         ---------------------------------------------
05/22/2025     Abhishek jain               MRT-575 This class is used to create allocation record for the funding record on the contract using the allocation code.
******************************************************************************************/
public class M2MAllocationUtility {
    
    static Map<Id, Map<Integer, Allocation_Code__c>> allocPriorityByContractId = new Map<Id, Map<Integer, Allocation_Code__c>>(); //Stores allocation codes by priority for each Contract Id
    static Map<Id, Map<String, Decimal>> maxAllocByContractId = new Map<Id, Map<String, Decimal>>(); //Stores max allocation amounts per Allocation Code by Contract Id
    static Map<Id, List<Allocation_Code__c>> allocCodesByContractId = new Map<Id, List<Allocation_Code__c>>(); //Stores allocation codes by Contract Id
    static List<InsurancePolicy> insurancePoliciesList = new List<InsurancePolicy>();
    static Map<Id, InsurancePolicy> contractMap = new Map<Id, InsurancePolicy>();
    
    public static void distributeFundingToContracts(List<InsurancePolicy> insurancePolicies){
        insurancePoliciesList = insurancePolicies;
        contractMap.putAll(insurancePolicies);
        populateAllocationCodeMaps();
        processFundingRecords();
    }
    
    private static void populateAllocationCodeMaps(){
        
        try {
            // Sets to track unique insurance carriers and enforced states and term months for dynamic query filtering
            Set<String> insuranceCarriers = new Set<String>{UtilityClass.INCLUDE_ALL};
                Set<String> enforcedStates = new Set<String>{UtilityClass.INCLUDE_ALL};
                    Set<String> termMonths = new Set<String>{UtilityClass.INCLUDE_ALL, '1'};
                        Set<String> options = new Set<String>{UtilityClass.INCLUDE_ALL};
                        
                        for (InsurancePolicy policy : insurancePoliciesList) {
                            if(policy.Ins_Carrier__c!=null) insuranceCarriers.add(policy.Ins_Carrier__c);
                            if(policy.Original_State__c!=null) enforcedStates.add(policy.Original_State__c);
                            if(policy.Option_1__c!=null) {
                                options.addAll(new Set<String>(policy.Option_1__c.split(';')));
                            }
                        }
            
            String insuranceCarriersValues = '\'' + String.join(insuranceCarriers, '\',\'') + '\''; // Convert to comma-separated string
            
            String enforcedStatesValues = '\'' + String.join(enforcedStates, '\',\'') + '\''; // Convert to comma-separated string
            
            String termMonthsValues = '\'' + String.join(termMonths, '\',\'') + '\''; // Convert to comma-separated string      
            
            options.add(UtilityClass.INCLUDE_ALL);
            String optionValues = '\'' + String.join(options, '\',\'') + '\''; // Convert to comma-separated string
            
            // Construct dynamic SOQL query to fetch allocation codes
             String query = 'SELECT Id, Name, Priority__c, Allocation_Type__c, Start_Date__c, End_Date__c, ' +
                'Insurance_Carrier__c, States__c, Allocation_Amount__c, Descriptor__c, is_Expense__c, ' +
                'Client__c, Coverage_Level__c, Product__c, Contract_Type__c, Payee__c, Term_Months__c, Option__c ' +
                'FROM Allocation_Code__c WHERE ';
            
            List<String> whereClauses = new List<String>();
            
            // Add dynamic filtering conditions for Insurance Carrier and State
            whereClauses.add('Insurance_Carrier__c INCLUDES ('+insuranceCarriersValues+')');
            whereClauses.add('States__c INCLUDES ('+enforcedStatesValues+')');
            whereClauses.add('Term_Months__c IN ('+termMonthsValues+')');
            whereClauses.add('Option__c IN ('+optionValues+')');
            
            // Finalize query
            query += String.join(whereClauses, ' AND ') + ' ORDER BY Priority__c ASC';
            
            // Execute query and retrieve allocation codes
            List<Allocation_Code__c> allocationCodes = Database.query(query);
            if (!allocationCodes.isEmpty()) {
                // Process allocation codes and organize them into maps
                for (Allocation_Code__c allocCode : allocationCodes) {
                    for (InsurancePolicy policy : insurancePoliciesList) {
                        
                        if ((policy.Ins_Carrier__c != null && (allocCode.Insurance_Carrier__c.contains(policy.Ins_Carrier__c) || allocCode.Insurance_Carrier__c.contains(UtilityClass.INCLUDE_ALL) )) &&
                            (policy.Original_State__c != null && (allocCode.States__c.contains(policy.Original_State__c) || allocCode.States__c.contains(UtilityClass.INCLUDE_ALL) ) ) && 
                            ((policy.Contract_Term_Months__c!=null && String.valueOf(policy.Contract_Term_Months__c)==allocCode.Term_Months__c) || allocCode.Term_Months__c==UtilityClass.INCLUDE_ALL) 
                            && policy.Sale_Date__c != null && allocCode.Start_Date__c <= policy.Sale_Date__c && (allocCode.End_Date__c == null || allocCode.End_Date__c >= policy.Sale_Date__c)
                            && allocCode.Client__c != null && policy.Client__c != null && policy.Client__c == allocCode.Client__c
                            && allocCode.Coverage_Level__c != null && policy.Coverage_Level__c != null && policy.Coverage_Level__r.Name == allocCode.Coverage_Level__c
                            && allocCode.Product__c != null && policy.Product__c != null && policy.Product__c == allocCode.Product__c &&
                           ((policy.Option_1__c != null && policy.Option_1__c.contains(allocCode.Option__c)) || 
                                 allocCode.Option__c.contains(UtilityClass.INCLUDE_ALL)) )
                        {
                            // Populate allocPriorityByContractId
                            if (!allocPriorityByContractId.containsKey(policy.Id)) {
                                allocPriorityByContractId.put(policy.Id, new Map<Integer, Allocation_Code__c>());
                            }
                            allocPriorityByContractId.get(policy.Id).put(Integer.valueOf(allocCode.Priority__c), allocCode);
                            
                            // Populate maxAllocByContractId
                            if (!maxAllocByContractId.containsKey(policy.Id)) {
                                maxAllocByContractId.put(policy.Id, new Map<String, Decimal>());
                            }
                            maxAllocByContractId.get(policy.Id).put(allocCode.Id, ContractAllocationUtilityCtrl.calculateMaxAllocation(policy, allocCode));
                            
                            // Populate allocCodesByContractId
                            if (!allocCodesByContractId.containsKey(policy.Id)) {
                                allocCodesByContractId.put(policy.Id, new List<Allocation_Code__c>());
                            }
                            allocCodesByContractId.get(policy.Id).add(allocCode);
                        }
                    }
                }
            }
            
        } catch (Exception e) {
            // Log error details including message and line number
            QDX_LOG.error('Error in populateAllocationCodeMaps - Message: ' + e.getMessage() +
                          ', Line Number: ' + e.getLineNumber());
        } finally {
            // Ensure logs are always published
            QDX_LOG.publish();
        }
    }
    
    private static void processFundingRecords(){
        
        try {
            List<Allocation__c> allocationsToInsert = new List<Allocation__c>();
            Map<Id, InsurancePolicy> updateContractMap = new Map<Id, InsurancePolicy>();
            
            // Query funding records that need processing
            List<Funding__c> fundingRecords = [
                SELECT Id, Contract__c, Funded_Amount__c, CreatedDate
                FROM Funding__c
                WHERE Time_Processed__c = NULL AND Funded_Amount__c > 0 AND Contract__c IN :contractMap.keySet()
                ORDER BY CreatedDate
            ];
            
            for(Funding__c record : fundingRecords){
                Decimal  remainingFunding = record.Funded_Amount__c;
                
                if(allocPriorityByContractId.containsKey(record.Contract__c) && maxAllocByContractId.containsKey(record.Contract__c)){
                    
                    Map<Integer, Allocation_Code__c> priorityToAllocCodeMap = new Map<Integer, Allocation_Code__c>();
                    Map<String, Decimal> allocCodeToMaxAmountMap = new  Map<String, Decimal>();
                    
                    priorityToAllocCodeMap.putAll(allocPriorityByContractId.get(record.Contract__c));
                    allocCodeToMaxAmountMap.putAll(maxAllocByContractId.get(record.Contract__c));
                    List<Integer> sortedPriorities = new List<Integer>(priorityToAllocCodeMap.keySet());
                    sortedPriorities.sort();
                    
                    for(Integer key : sortedPriorities){
                        Allocation_Code__c allocCode = priorityToAllocCodeMap.get(key);
                        Decimal maxAllocationAmount = allocCodeToMaxAmountMap.get(allocCode.Id);
                        Decimal amountToBeFunded = Math.min(remainingFunding, maxAllocationAmount);
                        
                        Allocation__c newAlloc = new Allocation__c();
                        newAlloc.Allocation_Amount__c = amountToBeFunded;
                        newAlloc.Allocation_Code__c = allocCode.Id;
                        newAlloc.Contract__c = record.Contract__c;
                        newAlloc.Payment_Return__c = 'P';
                        newAlloc.Payee__c = allocCode.Payee__c;
                        newAlloc.is_Expense__c = allocCode.is_Expense__c;
                        newAlloc.Descriptor__c = allocCode.Descriptor__c;
                        newAlloc.Max_Allocation_Amount__c = amountToBeFunded;
                        
                        allocationsToInsert.add(newAlloc);
                        remainingFunding = remainingFunding - amountToBeFunded;
                        if(remainingFunding == 0){
                            break;
                        }
                    }  
                    updateContractMap.put(record.Contract__c, contractMap.get(record.Contract__c));
                }

                record.Time_Processed__c = system.Now();
               
            } 
            Database.update(fundingRecords, false);
            Database.insert(allocationsToInsert, false);
            ContractAllocationUtilityCtrl.updateContractAllocationFields(updateContractMap);
            Database.update(updateContractMap.values(), false);
        } catch (Exception e) {
            // Log error details
            QDX_LOG.error('Error in M2MAllocationUtility:processFundingRecords - Message: ' + e.getMessage() +
                          ', Line Number: ' + e.getLineNumber());
        } finally {
            // Ensure logs are always published
            QDX_LOG.publish();
        }
    }
}