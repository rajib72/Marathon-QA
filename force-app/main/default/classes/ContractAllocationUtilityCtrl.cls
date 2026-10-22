/**
* @author: Saurabh Rawat
* @dateModified 16-07-2026
* @ModifiedBy Raj Sekhar Mukherjee
* @description: This class manages the allocation of contracts based on insurance policies, dealing with various aspects like fetching and assigning priorities, and handling financial distributions accordingly.
*/
public with sharing class ContractAllocationUtilityCtrl {
    
    // Test-only metadata seams. These remain null in production and therefore
    // do not alter production behavior.
    @TestVisible
    private static List<Rating_Record__mdt> testRatingRecords;
    
    @TestVisible
    private static List<Allocation_Priority__mdt> testPriorityRecords;
    
    @TestVisible
    private static List<ContractFundingAllocationFieldMapping__mdt> testFieldMappings;
    
    private static List<Rating_Record__mdt> getRatingRecords(
        Set<String> clientProgramCodes
    ) {
        if (Test.isRunningTest() && testRatingRecords != null) {
            List<Rating_Record__mdt> filtered = new List<Rating_Record__mdt>();
            
            for (Rating_Record__mdt row : testRatingRecords) {
                if (
                    row != null &&
                    clientProgramCodes.contains(row.ClientProgramCode__c) &&
                    row.BegDate__c != null &&
                    row.EndDate__c != null &&
                    row.BegDate__c <= System.today() &&
                    row.EndDate__c >= System.today()
                ) {
                    filtered.add(row);
                }
            }
            return filtered;
        }
        
        return [
            SELECT ProgramCode__c,
            Client__c,
            RatingRecordID__c,
            ClientProgramCode__c,
            BegDate__c,
            EndDate__c
            FROM Rating_Record__mdt
            WHERE ClientProgramCode__c IN :clientProgramCodes
            AND BegDate__c <= :System.today()
            AND EndDate__c >= :System.today()
        ];
    }
    
    private static List<Allocation_Priority__mdt> getAllocationPriorityRows(
        Set<String> allocationCodes,
        String financeCode
    ) {
        if (Test.isRunningTest() && testPriorityRecords != null) {
            List<Allocation_Priority__mdt> filtered =
                new List<Allocation_Priority__mdt>();
            
            for (Allocation_Priority__mdt row : testPriorityRecords) {
                if (
                    row != null &&
                    allocationCodes.contains(row.AllocationCode__c) &&
                    row.FinanceCode__c == financeCode
                ) {
                    filtered.add(row);
                }
            }
            return filtered;
        }
        
        return [
            SELECT AllocationCode__c,
            Priority__c,
            FinanceCode__c
            FROM Allocation_Priority__mdt
            WHERE AllocationCode__c IN :allocationCodes
            AND FinanceCode__c = :financeCode
        ];
    }
    
    private static List<ContractFundingAllocationFieldMapping__mdt>
        getFundingFieldMappings(Boolean descriptorRequired) {
            
            if (Test.isRunningTest() && testFieldMappings != null) {
                List<ContractFundingAllocationFieldMapping__mdt> filtered =
                    new List<ContractFundingAllocationFieldMapping__mdt>();
                
                for (
                    ContractFundingAllocationFieldMapping__mdt row :
                    testFieldMappings
                ) {
                    if (row == null) {
                        continue;
                    }
                    if (!descriptorRequired || row.Descriptor__c != null) {
                        filtered.add(row);
                    }
                }
                return filtered;
            }
            
            if (descriptorRequired) {
                return [
                    SELECT Contract_Field_API__c,
                    Descriptor__c
                    FROM ContractFundingAllocationFieldMapping__mdt
                    WHERE Descriptor__c != NULL
                ];
            }
            
            return [
                SELECT Contract_Field_API__c,
                Descriptor__c
                FROM ContractFundingAllocationFieldMapping__mdt
            ];
        }
    
    
    // =====================================================
    // GLOBAL ROUNDING UTILITY (FUTURE-PROOF)
    // =====================================================
    @TestVisible
    private static Decimal roundCurrency(Decimal value) {
        if (value == null) return 0;
        return value.setScale(2, RoundingMode.HALF_UP);
    }
    
    private static final String ADMIN_CANCEL_FEE_DESCRIPTOR =
        'Admin Cancel Fee';
    
    private static final String ADMIN_CANCEL_FEE_PAYEE =
        'Marathon Administrative';

    private static final String RESERVE_PACK_DESCRIPTOR =
        'Reserve Pack';
    
    // Fetches program codes and related rating record IDs.
    public static map<String, List<String>> fillProgramCodeDetails(Set<String> programCodeSet){
        Map<String, List<String>> ratingRecordIdsMap = new Map<String, List<String>>();
        for (Rating_Record__mdt record : getRatingRecords(programCodeSet)) {
            List<String> ratinglist = ratingRecordIdsMap.containsKey(record.ClientProgramCode__c)?ratingRecordIdsMap.get(record.ClientProgramCode__c):new List<String>();
            ratinglist.add(record.RatingRecordID__c);
            ratingRecordIdsMap.put(record.ClientProgramCode__c,ratinglist);
        }
        return ratingRecordIdsMap;
    }
    
    // Create a map of rating record IDs to allocation codes.
    public static map<String,List<String>> fillAllocationCodeDetails(List<Dealer_Cost_Allocation__c> records){
        Map<String, List<String>> allocationCodesMap = new Map<String, List<String>>();
        for (Dealer_Cost_Allocation__c record : records) {
            if(allocationCodesMap.containsKey(record.RatingRecordID__c)){
                allocationCodesMap.get(record.RatingRecordID__c).add(record.AllocationCode__c);
            }
            else{
                allocationCodesMap.put(record.RatingRecordID__c, new List<String>{record.AllocationCode__c});
            }
        }
        return allocationCodesMap;
    }
    
    // Fills the priority details for allocation codes.
    public static Map<String, Allocation_Priority__mdt> fillAllocationCodePriorityDetails( Set<String> insAllocationCodes,String FinanceCode) {
        Map<String, Allocation_Priority__mdt> priorityMap = new Map<String, Allocation_Priority__mdt>();
        for (
            Allocation_Priority__mdt record :
            getAllocationPriorityRows(insAllocationCodes, FinanceCode)
        ) {
            priorityMap.put(record.AllocationCode__c,record);
        }
        return priorityMap;
    }
    
    /**
* Assigns allocations to contracts based on insurance policies.
* @param insPolicyList A list of InsurancePolicy objects to process.
*/
    public static void assignAllocationtoContract (List<InsurancePolicy> insPolicyList){
        QDX_LOG.error('ENTERED assignAllocationtoContract');
        try{
            // Initialize sets to collect unique program and client program codes.
            Set<String> clientProgramCodeSet = new Set<String>();
            for(InsurancePolicy policyRec : insPolicyList){
                if(String.isNotBlank(policyRec.Client_Program_Code__c)){
                    clientProgramCodeSet.add(policyRec.Client_Program_Code__c);    
                }
                
            }
            // Retrieve a map of program codes to related rating record IDs.
            Map<String, List<String>> ratingRecordIdMap = fillProgramCodeDetails(clientProgramCodeSet);
            // Extract all unique rating record IDs for further processing.
            Set<String> uniqueRatingRecordIds = new Set<String>();
            for(List<String> each : ratingRecordIdMap.values()){
                uniqueRatingRecordIds.addAll(each);
            }
            // Query allocation details based on the unique rating record IDs.    
            List<Dealer_Cost_Allocation__c> records = [SELECT RatingRecordID__c, AllocationCode__c, Refundable__c,Allocation_Amount__c,Label_for_Fee_Amount_Rollup__c 
                                                       FROM Dealer_Cost_Allocation__c WHERE RatingRecordID__c IN :uniqueRatingRecordIds];
            // Create a map to associate each allocation code with its corresponding allocation record.
            Map<String,Dealer_Cost_Allocation__c> allocationCodeMap = new Map<String,Dealer_Cost_Allocation__c>();
            for (Dealer_Cost_Allocation__c record :records) {
                allocationCodeMap.put(record.AllocationCode__c, record);
            }
            // Map to fetch allocation codes related to rating record IDs.
            Map<String, List<String>> allocationCodesMap = fillAllocationCodeDetails(records);
            
            Set<String> allocationCodesToFetch = new Set<String>();
            Map<String,List<ContractAllocation>> contractCustomProgram = new Map<String,List<ContractAllocation>>();
            // Iterate through insurance policies to assign allocations.
            for(InsurancePolicy each : insPolicyList){
                Set<ContractAllocation> tempProgramCodes  = new Set<ContractAllocation>();
                //custom logic start
                set<string> insRatingIds = new set<String>();
                Set<String> insAllocationCodes = new Set<String>();
                
                if(ratingRecordIdMap.containsKey(each.Client_Program_Code__c)){
                    insRatingIds.addAll(ratingRecordIdMap.get(each.Client_Program_Code__c));    
                }
                
                //finding all the allocation codes related to a insurance
                for(String ratingIds : insRatingIds ){
                    if(allocationCodesMap.containsKey(ratingIds)){
                        insAllocationCodes.addAll(allocationCodesMap.get(ratingIds));      
                    }
                }
                Map<String, Allocation_Priority__mdt> insPriorityMap = new Map<String, Allocation_Priority__mdt>();
                if(insAllocationCodes.size() > 0 && String.isNotEmpty(each.Lien_Holder__c + each.Lien_Holder__r.AccountNumber ) ){
                    insPriorityMap = fillAllocationCodePriorityDetails(insAllocationCodes,each.Lien_Holder__r.AccountNumber);
                }
                
                List<ContractAllocation> contractAllocations = fetchRatingvsCustomAllocation(insAllocationCodes,insPriorityMap,allocationCodeMap);
                if(contractAllocations.size() > 0){
                    
                    tempProgramCodes.addAll(contractAllocations);   
                    
                    List<ContractAllocation> sortedOptions = new List<ContractAllocation>();
                    sortedOptions.addAll(tempProgramCodes);
                    sortedOptions.sort();
                    
                    Map<String,ContractAllocation> uniqueCustom = new Map<String,ContractAllocation>();
                    for(ContractAllocation eachCustom : sortedOptions){
                        allocationCodesToFetch.add(eachCustom.allocationCode);
                        eachCustom.contractId = each.Id;
                        if(each.Lien_Holder__c != null){
                            if(eachCustom.priority < 999 && eachCustom.financeCode ==  each.Lien_Holder__r.AccountNumber){
                                uniqueCustom.put(eachCustom.allocationCode,eachCustom);    
                            }else if(eachCustom.priority > 999){
                                uniqueCustom.put(eachCustom.allocationCode,eachCustom);    
                            }
                        }
                    }
                    contractCustomProgram.put(each.Id,uniqueCustom.values());
                    
                    
                    for (ContractAllocation ca : uniqueCustom.values()) {
                        
                    }
                }
                
            }//loop 2 ends
            
            
            // ############################################################
            // NEW: Contract Allocation Fields Mapping (ONE-TIME INGESTION)
            // ############################################################
            
            // Build Descriptor → SUM(Allocation Amount) mapping for each Contract
            Map<String, Map<String, Decimal>> descriptorTotalsByContract = new Map<String, Map<String, Decimal>>();
            
            Map<String, Allocation_Code__c> allocationCodeDetailsMap = new Map<String, Allocation_Code__c>();
            
            if (!allocationCodesToFetch.isEmpty()) {
                for (Allocation_Code__c ac : [
                    SELECT Name, Allocation_Amount__c, Descriptor__c
                    FROM Allocation_Code__c
                    WHERE Name IN :allocationCodesToFetch
                ]) {
                    allocationCodeDetailsMap.put(ac.Name, ac);
                    
                }
            }
            for (String contractId : contractCustomProgram.keySet()) {
                
                // Initialize once per contract
                descriptorTotalsByContract.put(contractId, new Map<String, Decimal>());
                
                Map<String, Decimal> dt = descriptorTotalsByContract.get(contractId);
                
                for (ContractAllocation ca : contractCustomProgram.get(contractId)) {
                    
                    // PRIMARY PATH
                    if (allocationCodeDetailsMap.containsKey(ca.allocationCode)) {
                        
                        Allocation_Code__c acd = allocationCodeDetailsMap.get(ca.allocationCode);
                        
                        
                        String descriptorValue = (acd.Descriptor__c != null) ? acd.Descriptor__c : '';
                        
                        Decimal amountToAdd = roundCurrency(
                            acd.Allocation_Amount__c != null
                            ? Decimal.valueOf(acd.Allocation_Amount__c)
                            : 0
                        );
                        
                        if (!dt.containsKey(descriptorValue)) {
                            dt.put(descriptorValue, amountToAdd);
                        } else {
                            dt.put(
                                descriptorValue,
                                roundCurrency(dt.get(descriptorValue) + amountToAdd)
                            );
                        }
                    }
                    
                    // FALLBACK
                    else {
                        
                        String descriptorValue = (ca.FeeLabel != null) ? ca.FeeLabel : '';
                        
                        Decimal amountToAdd = roundCurrency(ca.allocationAmount);
                        
                        if (!dt.containsKey(descriptorValue)) {
                            dt.put(descriptorValue, amountToAdd);
                        } else {
                            dt.put(
                                descriptorValue,
                                roundCurrency(dt.get(descriptorValue) + amountToAdd)
                            );
                        }
                    }
                }
                
            }
            
            
            // Fetch metadata (Descriptor → Contract Field mapping)
            List<ContractFundingAllocationFieldMapping__mdt> mappings =
                getFundingFieldMappings(false);
            
            // Prepare Contract updates
            List<InsurancePolicy> contractUpdates = new List<InsurancePolicy>();
            
            for (InsurancePolicy policyRec : insPolicyList) {
                
                if (!descriptorTotalsByContract.containsKey(policyRec.Id)) {
                    continue;
                }
                
                Map<String, Decimal> totals = descriptorTotalsByContract.get(policyRec.Id);
                
                for (ContractFundingAllocationFieldMapping__mdt m : mappings) {
                    
                    // descriptorKey is always metadata descriptor
                    String descriptorKey = m.Descriptor__c;
                    
                    // If Allocation Codes contributed value for this descriptor
                    if (totals.containsKey(descriptorKey)) {
                        
                        Decimal descriptorAmount = totals.get(descriptorKey);
                        
                        // 🔥 FIX: Use centralized rounding method
                        if (m.Contract_Field_API__c != null) {
                            policyRec.put(
                                m.Contract_Field_API__c,
                                roundCurrency(descriptorAmount)
                            );
                        }
                    }
                }
                
                
                contractUpdates.add(policyRec);
            }
            
            // Update Contracts once during ingestion
            if (!contractUpdates.isEmpty()) {
                update contractUpdates;
            }
            
            // ############################################################
            
            
            // Retrieve allocation codes based on names.
            Map<String,Allocation_Code__c> nameAllocationCodeMap = new  Map<String,Allocation_Code__c>();    
            for(Allocation_Code__c eachAllocationCode : [Select Id, Name from Allocation_Code__c Where Name IN :allocationCodesToFetch]){
                nameAllocationCodeMap.put(eachAllocationCode.Name,eachAllocationCode);
            } 
            
            // Actual allocation process begins here.          
            List<AggregateResult> groupedAllocations = new List<AggregateResult>();
            Map<String,Double> groupAllocationMap = new Map<String,Double>();
            for(Allocation__c allocation : [SELECT Id,Allocation_Amount__c,Contract__c,Contract__r.Program_Code__c, Allocation_Code__c, Allocation_Code__r.Name FROM Allocation__c WHERE Contract__c IN:insPolicyList]){
                Double calculatedAmount = groupAllocationMap.containsKey(allocation.Contract__c+''+allocation.Allocation_Code__r.Name)?groupAllocationMap.get(allocation.Contract__c+''+allocation.Allocation_Code__r.Name):0;
                calculatedAmount += allocation.Allocation_Amount__c;
                groupAllocationMap.put(allocation.Contract__c+''+allocation.Allocation_Code__r.Name,calculatedAmount);
            }
            
            
            // Lists for records to be updated or inserted.
            List<Allocation__c> allocationTobeUpdated = new List<Allocation__c>();
            List<Allocation__c> allocationTobeInsert = new List<Allocation__c>();
            List<Funding__c> fundsTobeUpdated = new   List<Funding__c>();
            
            // Map contracts to their funding amounts.
            Map<String,List<Funding__c>> fundingMap  = new Map<String,List<Funding__c>>();
            Map<String,Decimal> fundingAmountMap  = new Map<String,Decimal>();
            for(Funding__c fundRecord: [Select Id, Contract__c, Funded_Amount__c from Funding__c Where Contract__c IN :contractCustomProgram.keyset() AND Time_Processed__c = null AND Funded_Amount__c != 0 ORDER BY CreatedDate ASC]){
                List<Funding__c> funds = fundingMap.containsKey(fundRecord.Contract__c)?fundingMap.get(fundRecord.Contract__c):new List<Funding__c>();
                Decimal amountToAdd = fundingAmountMap.containsKey(fundRecord.Contract__c)? fundingAmountMap.get(fundRecord.Contract__c):0;
                funds.add(fundRecord);
                // 🔥 FIX: Round funded amounts before aggregation
                amountToAdd += roundCurrency(fundRecord.Funded_Amount__c);
                fundingMap.put(fundRecord.Contract__c,funds);
                fundingAmountMap.put(fundRecord.Contract__c,amountToAdd);
            }
            // Iterate through contracts for allocation and funding updates.
            for(String eachContractId : contractCustomProgram.keyset()){
                Decimal fundingAmount = fundingAmountMap.containsKey(eachContractId)?fundingAmountMap.get(eachContractId):0;
                Decimal initialFundingAmount = fundingAmountMap.containsKey(eachContractId)?fundingAmountMap.get(eachContractId):0;
                List<ContractAllocation> equalDistributionAllocation = new List<ContractAllocation>();
                Decimal totalRestAmount = 0;
                Decimal totalSpendAmount = 0;
                
                if(contractCustomProgram.containsKey(eachContractId)){
                    for(ContractAllocation each : contractCustomProgram.get(eachContractId)){
                        //checking for remaining funding amount
                        if(fundingAmount <= 0){
                            break;
                        }
                        Decimal amountToSpend = each.allocationAmount;
                        
                        // Case 1: If allocation exists, update it.
                        if(groupAllocationMap.containsKey(eachContractId+''+each.allocationCode) && each.priority < 99999){
                            if(groupAllocationMap.get(eachContractId+''+each.allocationCode)  < each.allocationAmount){
                                Decimal amountToAllocation = 0;
                                if((each.allocationAmount - groupAllocationMap.get(eachContractId+''+each.allocationCode)) > fundingAmount){
                                    amountToAllocation = (fundingAmount).setScale(2);
                                }else if((each.allocationAmount - groupAllocationMap.get(eachContractId+''+each.allocationCode)) < fundingAmount){
                                    amountToAllocation = (each.allocationAmount - groupAllocationMap.get(eachContractId+''+each.allocationCode)).setScale(2);
                                }
                                
                                totalSpendAmount += (amountToAllocation).setScale(2);
                                fundingAmount -= (amountToAllocation).setScale(2);
                                
                                Allocation__c newAllocation = new Allocation__c();
                                newAllocation.Allocation_Amount__c = (amountToAllocation).setScale(2);
                                newAllocation.Contract__c = eachContractId;
                                newAllocation.Fee_Label_for_Summary_Reporting__c = each.FeeLabel;
                                newAllocation.Allocation_Code__c = nameAllocationCodeMap.get(each.allocationCode).Id;
                                newAllocation.Payment_Return__c = 'P';
                                if( newAllocation.Allocation_Amount__c != 0){
                                    allocationTobeInsert.add(newAllocation);    
                                }
                                
                            }
                            
                        }else if// Case 2: No allocation but priority exists.
                            (each.priority < 99999){
                                //to check if amount is remaining
                                Allocation__c newAllocation = new Allocation__c();
                                newAllocation.Allocation_Amount__c = (each.allocationAmount <= fundingAmount?each.allocationAmount:fundingAmount).setScale(2);
                                newAllocation.Contract__c = eachContractId;
                                newAllocation.Allocation_Code__c = nameAllocationCodeMap.get(each.allocationCode).Id;
                                newAllocation.Payment_Return__c = 'P';
                                newAllocation.Fee_Label_for_Summary_Reporting__c = each.FeeLabel;
                                allocationTobeInsert.add(newAllocation);
                                totalSpendAmount += (each.allocationAmount <= fundingAmount?each.allocationAmount:fundingAmount).setScale(2);
                                fundingAmount -= (each.allocationAmount <= fundingAmount?each.allocationAmount:fundingAmount).setScale(2);
                                
                            }else //Case 3rd, No priority 
                            {
                                //check for existing allocation without priority
                                if(groupAllocationMap.containsKey(eachContractId+''+each.allocationCode)){
                                    if(groupAllocationMap.get(eachContractId+''+each.allocationCode) < each.allocationAmount){
                                        totalRestAmount += (each.allocationAmount - groupAllocationMap.get(eachContractId+''+each.allocationCode)).setScale(2);
                                        equalDistributionAllocation.add(each);
                                    }
                                }else{
                                    totalRestAmount += (amountToSpend).setScale(2);    
                                    equalDistributionAllocation.add(each);
                                }
                            }
                    }
                }
                // Distribute funds equally if needed.
                if(equalDistributionAllocation.size() > 0){
                    
                    //check if remainingbudget is overfunded for non priority allocations
                    if((initialFundingAmount - totalSpendAmount) >= totalRestAmount){
                        for(ContractAllocation each : equalDistributionAllocation){
                            
                            Allocation__c newAllocation = new Allocation__c();
                            //has Existing Allocation
                            if(groupAllocationMap.containsKey(eachContractId+''+each.allocationCode)){
                                //If existing allocation is not maxed
                                if(groupAllocationMap.get(eachContractId+''+each.allocationCode) < each.allocationAmount){
                                    
                                    totalSpendAmount += (each.allocationAmount - groupAllocationMap.get(eachContractId+''+each.allocationCode)).setScale(2);      
                                    newAllocation.Allocation_Amount__c = (each.allocationAmount - groupAllocationMap.get(eachContractId+''+each.allocationCode)).setScale(2);
                                    newAllocation.Contract__c = eachContractId;
                                    newAllocation.Allocation_Code__c = nameAllocationCodeMap.get(each.allocationCode).Id;
                                    newAllocation.Payment_Return__c = 'P';
                                    newAllocation.Fee_Label_for_Summary_Reporting__c = each.FeeLabel;
                                    if( newAllocation.Allocation_Amount__c != 0){
                                        allocationTobeInsert.add(newAllocation);    
                                    }
                                    
                                }
                            }else{
                                newAllocation.Allocation_Amount__c = (each.allocationAmount).setScale(2);
                                totalSpendAmount += (each.allocationAmount).setScale(2);
                                newAllocation.Contract__c = eachContractId;
                                newAllocation.Allocation_Code__c = nameAllocationCodeMap.get(each.allocationCode).Id;
                                newAllocation.Payment_Return__c = 'P';
                                newAllocation.Fee_Label_for_Summary_Reporting__c = each.FeeLabel;
                                allocationTobeInsert.add(newAllocation);
                            }
                        }
                    }else{
                        Decimal percentCalculate = ((initialFundingAmount - totalSpendAmount).setScale(2)/totalRestAmount.setScale(2)) * 100;
                        for(ContractAllocation each : equalDistributionAllocation){
                            Allocation__c newAllocation = new Allocation__c();
                            //has Existing Allocation
                            if(groupAllocationMap.containsKey(eachContractId+''+each.allocationCode)){
                                
                                newAllocation.Allocation_Amount__c = (((each.allocationAmount-groupAllocationMap.get(eachContractId+''+each.allocationCode)) * percentCalculate)/100).setScale(2);
                                totalSpendAmount += (((each.allocationAmount-groupAllocationMap.get(eachContractId+''+each.allocationCode)) * percentCalculate)/100).setScale(2);                              
                                newAllocation.Contract__c = eachContractId;
                                newAllocation.Allocation_Code__c = nameAllocationCodeMap.get(each.allocationCode).Id;
                                newAllocation.Payment_Return__c = 'P';
                                newAllocation.Fee_Label_for_Summary_Reporting__c = each.FeeLabel;
                                if( newAllocation.Allocation_Amount__c != 0){
                                    allocationTobeInsert.add(newAllocation);    
                                }
                            }else{
                                newAllocation.Allocation_Amount__c = ((each.allocationAmount * percentCalculate)/100).setScale(2);
                                totalSpendAmount += ((each.allocationAmount * percentCalculate)/100).setScale(2);
                                newAllocation.Contract__c = eachContractId;
                                newAllocation.Allocation_Code__c = nameAllocationCodeMap.get(each.allocationCode).Id;
                                newAllocation.Payment_Return__c = 'P';
                                newAllocation.Fee_Label_for_Summary_Reporting__c = each.FeeLabel;
                                allocationTobeInsert.add(newAllocation);
                            }
                        } 
                    }
                }
                // Update funding records.
                if(fundingMap.containsKey(eachContractId)){
                    for(Funding__c each : fundingMap.get(eachContractId)){
                        if(totalSpendAmount >= each.Funded_Amount__c){
                            totalSpendAmount -= each.Funded_Amount__c;
                            each.Time_Processed__c = System.now();
                            fundsTobeUpdated.add(each);
                        }else if(totalSpendAmount < each.Funded_Amount__c){
                            each.Time_Processed__c = System.now();
                            fundsTobeUpdated.add(each);
                            break;
                        }                    
                    } 
                }
            }
            // Perform database operations.
            if(fundsTobeUpdated.size() > 0){
                update fundsTobeUpdated;
            }
            if(allocationTobeInsert.size() > 0){
                insert allocationTobeInsert;
            }
            if(allocationTobeUpdated.size() > 0){
                update allocationTobeUpdated;
            }
            
            
            postReserveCalculation(contractCustomProgram);
            
            
        }catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
        }
    }
    
    public static void postReserveCalculation(Map<String,List<ContractAllocation>> contractCustomProgram){
        //Post process Fund Counting and Reserve calculation
        List<AggregateResult> contractFundsResult = new List<AggregateResult>();
        List<AggregateResult> contractAllocationResult = new List<AggregateResult>();
        List<Allocation__c> reserveAllocations = new List<Allocation__c>();
        Map<Id,List<Allocation__c>> contractReserveMap = new Map<Id,List<Allocation__c>>();
        Map<Id,Decimal> contractFundingMap = new Map<Id,Decimal>();
        Map<Id,Decimal> contractAllocationMap = new Map<Id,Decimal>();
        List<Allocation_Code__c> reserveAllocationCodes = new List<Allocation_Code__c>();
        List<Allocation__c> allocationToUpsert = new List<Allocation__c>();
        
        contractFundsResult = [Select SUM(Funded_Amount__c) FundedAmount, Contract__c from Funding__c WHere Contract__c IN :contractCustomProgram.keyset() GROUP by Contract__c LIMIT 2000];
        contractAllocationResult = [Select SUM(Allocation_Amount__c) AllocationAmount, Contract__c from Allocation__c WHere Payment_Return__c = 'P' AND Contract__c IN :contractCustomProgram.keyset() AND Allocation_Code__r.Name != '8004' GROUP by Contract__c LIMIT 2000];
        reserveAllocations = [Select Id,Contract__c, Allocation_Amount__c from Allocation__c Where Payment_Return__c = 'P' AND Allocation_Code__r.Name = '8004' AND Contract__c IN :contractCustomProgram.keyset() LIMIT 45000];
        reserveAllocationCodes  = [Select Id from Allocation_Code__c Where Name = '8004' LIMIT 1];
        
        for(Allocation__c reserve : reserveAllocations){
            
            if(!contractReserveMap.containsKey(reserve.Contract__c)){
                contractReserveMap.put(
                    reserve.Contract__c,
                    new List<Allocation__c>()
                );
            }
            contractReserveMap.get(reserve.Contract__c).add(reserve);
        }
        for(AggregateResult result : contractFundsResult){
            contractFundingMap.put(String.valueOf(result.get('Contract__c')),(Decimal)result.get('FundedAmount'));
        }
        for(AggregateResult result : contractAllocationResult){
            contractAllocationMap.put(String.valueOf(result.get('Contract__c')),(Decimal)result.get('AllocationAmount'));
        } 
        
        for(String contractId : contractCustomProgram.keyset()){
            if(contractFundingMap.containskey(contractId) && contractAllocationMap.containskey(contractId)){
                Decimal reserveAmount = contractFundingMap.get(contractId) - contractAllocationMap.get(contractId);
                Allocation__c reserveAllocation = new Allocation__c();
                
                if(contractReserveMap.containsKey(contractId)){
                    reserveAllocation =
                        contractReserveMap.get(contractId)[0];
                }
                reserveAllocation.Allocation_Amount__c = roundCurrency(reserveAmount);
                reserveAllocation.Allocation_Code__c   = reserveAllocationCodes.get(0).Id;
                reserveAllocation.Payment_Return__c    = 'P';
                if(!contractReserveMap.containskey(contractId)){
                    reserveAllocation.Contract__c = contractId;    
                }
                
                allocationToUpsert.add(reserveAllocation);
            }
        }
        Database.upsert(allocationToUpsert);
        
    }
    
    /**
* Fetches custom allocations for each rating.
* @param allocationCodesMap A map of rating IDs to allocation code, priorityMap A map of allocation codes to their priorities and allocationCodeMap A map of allocation codes to their details.
* @return A map of rating IDs to lists of custom contract allocations.
*/
    public static List<ContractAllocation> fetchRatingvsCustomAllocation(Set<String> allocationCodes,Map<String, Allocation_Priority__mdt> priorityMap,Map<String,Dealer_Cost_Allocation__c> allocationCodeMap){
        // Map to store custom allocations for each rating.
        // Iterate through allocation codes for each rating.
        List<ContractAllocation> tempList = new List<ContractAllocation>();
        // Create ContractAllocation objects for each allocation code.
        for(String allocationCode : allocationCodes){
            ContractAllocation newAllocation = new ContractAllocation();
            newAllocation.allocationCode = allocationCode;
            newAllocation.FeeLabel = allocationCodeMap.containsKey(allocationCode)?allocationCodeMap.get(allocationCode).Label_for_Fee_Amount_Rollup__c:'';
            // 🔥 FIX: Ensure source allocation values are rounded
            newAllocation.allocationAmount = allocationCodeMap.containsKey(allocationCode) ? roundCurrency(allocationCodeMap.get(allocationCode).Allocation_Amount__c) : 0;
            newAllocation.priority = priorityMap.containsKey(allocationCode)?Integer.valueOf(priorityMap.get(allocationCode).Priority__c):100000;
            newAllocation.financeCode = priorityMap.containsKey(allocationCode)?priorityMap.get(allocationCode).FinanceCode__c:'';
            tempList.add(newAllocation);
        }
        // Sort the list of custom allocations by priority.
        tempList.sort();        
        return tempList;
    }
    
    /**
* Splits a list of InsurancePolicy contracts into two categories: 
* SecureOne contracts and other contracts. 
* - SecureOne contracts are processed via assignAllocationtoContract().
* - Other contracts are processed via distributeFundingToContracts().
* 
* @param contracts List of InsurancePolicy objects to be categorized.
*/
    public static void splitContractsByClient(List<InsurancePolicy> contracts) {
        // Log the method entry
        QDX_LOG.debug('***Inside splitContractsByClient***');
        
        // Lists to categorize contracts
        List<InsurancePolicy> secureOneContracts = new List<InsurancePolicy>(); // Stores SecureOne contracts
        List<InsurancePolicy> otherContracts = new List<InsurancePolicy>(); // Stores non-SecureOne contracts
        List<InsurancePolicy> m2mContracts = new List<InsurancePolicy>(); //Stores non-SecureOne M2M contracts
        
        try {
            // Loop through each contract and categorize it based on the Product__c field
            for (InsurancePolicy contract : contracts) {
                
                if (contract.Legacy_Source__c == 'DSI') {
                    if(contract.Lien_Holder__c != null && contract.Program_Code__c != null){
                        secureOneContracts.add(contract); // Add to SecureOne list
                        //otherContracts.add(contract);
                    }
                } else if(contract.Contract_Term_Months__c == 1){
                    m2mContracts.add(contract);
                } else{
                    otherContracts.add(contract); // Add to Other list
                }
            }
            
            // If there are non-SecureOne contracts, process their funding allocation
            if (!otherContracts.isEmpty()) {
                distributeFundingToContracts(otherContracts);
            }
            
            // If there are SecureOne contracts, assign allocations
            if (!secureOneContracts.isEmpty()) {
                assignAllocationtoContract(secureOneContracts);
            }
            
            // If there are non-SecureOne M2M contracts, process their funding allocation
            if (!m2mContracts.isEmpty()) {
                M2MAllocationUtility.distributeFundingToContracts(m2mContracts);
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_LOG.publish();
        }
    }
    
    /**
* Distributes funding to a list of insurance policies by:
* 1. Fetching allocation codes and priorities.
* 2. Retrieving existing allocation records.
* 3. Processing funding records accordingly.
*
* @param insurancePolicies List of InsurancePolicy objects that require funding allocation.
*/
    public static void distributeFundingToContracts(List<InsurancePolicy> insurancePolicies) {
        QDX_LOG.debug('***Inside distributeFundingToContracts***');
        
        try {
            // Maps to store allocation data
            Map<Id, Map<Integer, Allocation_Code__c>> allocPriorityByContractId = new Map<Id, Map<Integer, Allocation_Code__c>>(); // Stores allocation codes by priority
            Map<Id, Map<String, Decimal>> maxAllocByContractId = new Map<Id, Map<String, Decimal>>(); // Stores max allocation amounts per contract
            Map<Id, List<Allocation_Code__c>> allocCodesByContractId = new Map<Id, List<Allocation_Code__c>>(); // Stores allocation codes by contract
            Map<Id, Map<String, Decimal>> existingAllocAmountsByContractId = new Map<Id, Map<String, Decimal>>(); // Stores existing allocation amounts per contract
            
            // Step 1: Fetch relevant allocation codes and populate maps
            populateAllocationCodeMaps(insurancePolicies, allocPriorityByContractId, maxAllocByContractId, allocCodesByContractId);
            
            // Step 2: Retrieve existing allocation records and populate the map
            fetchExistingAllocations(
                insurancePolicies,
                allocPriorityByContractId,
                existingAllocAmountsByContractId
            );
            
            // Step 3: Process funding records based on allocation data
            processFundingRecords(allocPriorityByContractId, maxAllocByContractId, existingAllocAmountsByContractId, insurancePolicies);
            
        } catch (Exception e) {
            // Log error details including message and line number
            QDX_LOG.error('Error in distributeFundingToContracts - Message: ' + e.getMessage() + ', Line Number: ' + e.getLineNumber());
        } finally {
            // Publish logs for tracking and debugging
            QDX_LOG.publish();
        }
    }
    
    /**
* Populates allocation-related maps by fetching Allocation_Code__c records
* based on the given list of InsurancePolicy objects.
*
* The function:
* 1. Extracts relevant contract IDs and policy attributes.
* 2. Constructs and executes a dynamic SOQL query to fetch Allocation_Code__c records.
* 3. Processes results and organizes them into three maps for prioritization, max allocation, and allocation codes.
*
* @param insurancePolicies List of InsurancePolicy objects to process.
* @param allocPriorityByContractId Map storing allocation codes by contract ID and priority.
* @param maxAllocByContractId Map storing max allocation amounts by contract ID and allocation name.
* @param allocCodesByContractId Map storing allocation codes by contract ID.
*/
    private static void populateAllocationCodeMaps(
        List<InsurancePolicy> insurancePolicies,
        Map<Id, Map<Integer, Allocation_Code__c>> allocPriorityByContractId,
        Map<Id, Map<String, Decimal>> maxAllocByContractId,
        Map<Id, List<Allocation_Code__c>> allocCodesByContractId
    ) {
        QDX_LOG.debug('***Inside populateAllocationCodeMaps***');
        
        try {
            // Sets to track unique insurance carriers, enforced states, term months and options for dynamic query filtering
            Set<String> insuranceCarriers = new Set<String>();
            Set<String> enforcedStates = new Set<String>();
            Set<String> termMonths = new Set<String>();
            Set<String> options = new Set<String>();
            
            // Extract contract IDs from insurance policies
            Set<Id> contractIds = new Set<Id>();
            Map<Id, InsurancePolicy> contractMap = new Map<Id, InsurancePolicy>();
            
            for (InsurancePolicy policy : insurancePolicies) {
                contractIds.add(policy.Id);
                contractMap.put(policy.Id, policy);
                if(policy.Ins_Carrier__c!=null) insuranceCarriers.add(policy.Ins_Carrier__c);
                if(policy.Original_State__c!=null) enforcedStates.add(policy.Original_State__c);
                if(policy.Contract_Term_Months__c!=null) termMonths.add(String.valueOf(policy.Contract_Term_Months__c));
                if(policy.Option_1__c!=null) {
                    options.addAll(new Set<String>(policy.Option_1__c.split(';')));
                }
            }
            
            // Include 'Include All' in carrier and state sets to cover broader matches
            insuranceCarriers.add(UtilityClass.INCLUDE_ALL);
            insuranceCarriers.remove(null);
            String insuranceCarriersValues = '\'' + String.join(insuranceCarriers, '\',\'') + '\''; // Convert to comma-separated string
            
            enforcedStates.add(UtilityClass.INCLUDE_ALL);
            enforcedStates.remove(null);
            String enforcedStatesValues = '\'' + String.join(enforcedStates, '\',\'') + '\''; // Convert to comma-separated string
            
            termMonths.add(UtilityClass.INCLUDE_ALL);
            termMonths.remove(null);
            String termMonthsValues = '\'' + String.join(termMonths, '\',\'') + '\''; // Convert to comma-separated string   
            
            options.add(UtilityClass.INCLUDE_ALL);
            options.remove(null);
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
            QDX_LOG.debug('Query: ' + query);
            
            // Execute query and retrieve allocation codes
            List<Allocation_Code__c> allocationCodes = Database.query(query);
            if (!allocationCodes.isEmpty()) {
                // Process allocation codes and organize them into maps
                for (Allocation_Code__c allocCode : allocationCodes) {
                    for (InsurancePolicy policy : insurancePolicies) {
                        if(allocCode.Start_Date__c <= policy.Sale_Date__c 
                           && (allocCode.End_Date__c == null || allocCode.End_Date__c >= policy.Sale_Date__c)){
                               
                               boolean contractTypeMatch = false;
                               
                               // Validate matching criteria for allocation
                               if (allocCode.Client__c != null && policy.Client__c != null && policy.Client__c == allocCode.Client__c &&
                                   ((policy.Option_1__c != null && policy.Option_1__c.contains(allocCode.Option__c)) || 
                                    allocCode.Option__c.contains(UtilityClass.INCLUDE_ALL) ) ) {
                                        
                                        if (allocCode.Contract_Type__c == 'Auto' &&
                                            allocCode.Product__c != null && policy.Product__c != null &&
                                            policy.Product__c == allocCode.Product__c &&
                                            allocCode.Coverage_Level__c != null && policy.Coverage_Level__c != null &&
                                            policy.Coverage_Level__r.Name == allocCode.Coverage_Level__c  &&
                                            ((policy.Ins_Carrier__c == null && allocCode.Insurance_Carrier__c.contains('No Insurance Carriers')) || 
                                             (policy.Ins_Carrier__c != null && (allocCode.Insurance_Carrier__c.contains(policy.Ins_Carrier__c) || allocCode.Insurance_Carrier__c.contains(UtilityClass.INCLUDE_ALL) ))) &&
                                            (policy.Original_State__c != null && (allocCode.States__c.contains(policy.Original_State__c) || allocCode.States__c.contains(UtilityClass.INCLUDE_ALL) ) ) && 
                                            ((policy.Contract_Term_Months__c!=null && String.valueOf(policy.Contract_Term_Months__c)==allocCode.Term_Months__c) || allocCode.Term_Months__c==UtilityClass.INCLUDE_ALL) )
                                        {
                                            contractTypeMatch = true;   
                                        } else if (allocCode.Contract_Type__c == 'Home' &&
                                                   allocCode.Coverage_Level__c != null && policy.Coverage_Level__c != null &&
                                                   policy.Coverage_Level__r.Name == allocCode.Coverage_Level__c &&
                                                   ((policy.Ins_Carrier__c == null && allocCode.Insurance_Carrier__c.contains('No Insurance Carriers')) || 
                                                    (policy.Ins_Carrier__c != null && (allocCode.Insurance_Carrier__c.contains(policy.Ins_Carrier__c) || allocCode.Insurance_Carrier__c.contains(UtilityClass.INCLUDE_ALL) ))) &&
                                                   (policy.Original_State__c != null && (allocCode.States__c.contains(policy.Original_State__c) || allocCode.States__c.contains(UtilityClass.INCLUDE_ALL) ) )  && 
                                                   ((policy.Contract_Term_Months__c!=null && String.valueOf(policy.Contract_Term_Months__c)==allocCode.Term_Months__c) || allocCode.Term_Months__c==UtilityClass.INCLUDE_ALL)) 
                                        {
                                            contractTypeMatch = true;
                                        } else if (allocCode.Contract_Type__c == 'Health CAR' &&
                                                   allocCode.Product__c != null && policy.Product__c != null &&
                                                   policy.Product__c == allocCode.Product__c &&
                                                   ((policy.Ins_Carrier__c == null && allocCode.Insurance_Carrier__c.contains('No Insurance Carriers')) || 
                                                    (policy.Ins_Carrier__c != null && (allocCode.Insurance_Carrier__c.contains(policy.Ins_Carrier__c) || allocCode.Insurance_Carrier__c.contains(UtilityClass.INCLUDE_ALL) ))) &&
                                                   (policy.Original_State__c != null && (allocCode.States__c.contains(policy.Original_State__c) || allocCode.States__c.contains(UtilityClass.INCLUDE_ALL) ) )  && 
                                                   ((policy.Contract_Term_Months__c!=null && String.valueOf(policy.Contract_Term_Months__c)==allocCode.Term_Months__c) || allocCode.Term_Months__c==UtilityClass.INCLUDE_ALL)) 
                                        {
                                            contractTypeMatch = true;
                                        }
                                    }
                               
                               if (contractTypeMatch) {
                                   Id contractId = policy.Id;
                                   
                                   // Populate allocPriorityByContractId
                                   if (!allocPriorityByContractId.containsKey(contractId)) {
                                       allocPriorityByContractId.put(contractId, new Map<Integer, Allocation_Code__c>());
                                   }
                                   allocPriorityByContractId.get(contractId).put(Integer.valueOf(allocCode.Priority__c), allocCode);
                                   
                                   // Populate maxAllocByContractId
                                   if (!maxAllocByContractId.containsKey(contractId)) {
                                       maxAllocByContractId.put(contractId, new Map<String, Decimal>());
                                   }
                                   maxAllocByContractId.get(contractId).put(allocCode.Name, calculateMaxAllocation(policy, allocCode));
                                   
                                   // Populate allocCodesByContractId
                                   if (!allocCodesByContractId.containsKey(contractId)) {
                                       allocCodesByContractId.put(contractId, new List<Allocation_Code__c>());
                                   }
                                   allocCodesByContractId.get(contractId).add(allocCode);
                               }
                           }
                    }
                }
            }
            
            // Debug logs to check processed data sizes
            QDX_LOG.debug('allocPriorityByContractId.size(): ' + allocPriorityByContractId.size());
            QDX_LOG.debug('maxAllocByContractId.size(): ' + maxAllocByContractId.size());
            QDX_LOG.debug('allocCodesByContractId.size(): ' + allocCodesByContractId.size());
            
        } catch (Exception e) {
            // Log error details including message and line number
            QDX_LOG.error('Error in populateAllocationCodeMaps - Message: ' + e.getMessage() +
                          ', Line Number: ' + e.getLineNumber());
        } finally {
            // Ensure logs are always published
            QDX_LOG.publish();
        }
    }
    
    /**
* Calculates the maximum allocation amount for a given InsurancePolicy and Allocation_Code__c.
*
* The function:
* 1. Returns 0 if any critical input is null.
* 2. Converts Allocation_Amount__c to Decimal if it's a numeric value.
* 3. Uses policy's Reserve__c if Allocation_Amount__c matches Descriptor__c.
* 4. Retrieves supplemental value if Allocation_Amount__c starts with 'S' and is short.
* 5. Evaluates Allocation_Amount__c as a formula if it's an expression.
*
* @param policy The InsurancePolicy associated with the allocation.
* @param allocationCode The Allocation_Code__c record containing allocation details.
* @return The calculated maximum allocation amount as a Decimal.
*/
    public static Decimal calculateMaxAllocation(InsurancePolicy policy, Allocation_Code__c allocationCode) {
        try {
            QDX_LOG.debug('***Inside calculateMaxAllocation***');
            
            // Return 0 if essential inputs are null
            if (policy == null || allocationCode == null || allocationCode.Name == null || allocationCode.Allocation_Amount__c == null) {
                return 0;
            }
            
            // Case 1: Allocation_Amount__c is a numeric value
            if (Pattern.matches('\\d+(\\.\\d+)?', allocationCode.Allocation_Amount__c)) {
                return Decimal.valueOf(allocationCode.Allocation_Amount__c);
            }
            
            // Case 2: Allocation_Amount__c matches Descriptor__c, return policy reserve
            if (allocationCode.Allocation_Amount__c == allocationCode.Descriptor__c) {
                return policy.Reserve__c;
            }
            
            // Case 3: Allocation_Amount__c starts with 'S' (case-insensitive) and length < 5
            if (allocationCode.Allocation_Amount__c.startsWithIgnoreCase('S') && allocationCode.Allocation_Amount__c.length() < 5) {
                return getSupplementalValue(policy, allocationCode.Allocation_Amount__c, allocationCode.Descriptor__c);
            }
            
            // Case 4: Evaluate Allocation_Amount__c as a formula
            try {
                // Build the formula using FormulaEval API
                FormulaEval.FormulaBuilder formulaInstance = Formula.builder()
                    .withType(InsurancePolicy.SObjectType)  // Define context class
                    .withReturnType(FormulaEval.FormulaReturnType.DECIMAL) // Expecting Decimal return type
                    .withFormula(allocationCode.Allocation_Amount__c); // Formula expression      
                
                FormulaEval.FormulaInstance fInstance = formulaInstance.build();
                Decimal formulaResult = (Decimal)fInstance.evaluate(policy);         
                return formulaResult == null ? 0 : formulaResult;
            } catch (Exception formulaException) {
                QDX_LOG.error('Formula evaluation failed: ' + formulaException.getMessage() +
                              ' at line ' + formulaException.getLineNumber());
            }
            
        } catch (Exception e) {
            // Log error details
            QDX_LOG.error('Error in calculateMaxAllocation - Message: ' + e.getMessage() +
                          ', Line Number: ' + e.getLineNumber());
        } finally {
            // Ensure logs are always published
            QDX_LOG.publish();
        }
        
        // Default return value in case of any failure
        return 0;
    }
    
    /**
* Retrieves a supplemental value from an InsurancePolicy based on the descriptor.
*
* The function:
* 1. Returns the `Premium_Tax_Old__c` field if the descriptor is 'Premium Tax'.
* 2. Returns the `MBI_Seller_Commission__c` field if the descriptor is 'Seller Commission'.
* 3. Defaults to returning 0 if no match is found or if an error occurs.
*
* @param policy The InsurancePolicy object from which to retrieve the value.
* @param resultName The result identifier (not used in current logic but reserved for future use).
* @param descriptor The descriptor that determines which field to return.
* @return The corresponding Decimal value from the policy or 0 if no match is found.
*/
    public static Decimal getSupplementalValue(InsurancePolicy policy, String resultName, String descriptor) {
        QDX_LOG.debug('***Inside getSupplementalValue***');
        
        try {
            // Validate input
            if (policy == null || descriptor == null) {
                QDX_LOG.debug('Null policy or descriptor provided.');
                return 0;
            }
            
            // Return values based on the descriptor
            if (descriptor == 'Premium Tax') {
                return policy.Premium_Tax_Old__c;
            } else if (descriptor == 'Seller Commission') {
                return policy.MBI_Seller_Commission__c;
            }
            //OT Allocation new field added
            else if (descriptor == 'Obligor Tax') {
                return policy.OT_Allocation__c;
            }
            
        } catch (Exception e) {
            // Log error details
            QDX_LOG.error('Error in getSupplementalValue - Message: ' + e.getMessage() +
                          ', Line Number: ' + e.getLineNumber());
        } finally {
            // Ensure logs are always published
            QDX_LOG.publish();
        }
        
        // Default return value if no match is found
        return 0;
    }
    
    /**
* Fetches existing allocation amounts for a list of insurance policies and populates a mapping.
*
* The function:
* 1. Extracts contract IDs from the given list of InsurancePolicy objects.
* 2. Queries Allocation__c records to get the total allocated amount per contract and allocation code.
* 3. Populates the `existingAllocAmountsByContractId` map with the retrieved data.
*
* @param insurancePolicies List of InsurancePolicy objects whose allocations need to be fetched.
* @param existingAllocAmountsByContractId Map storing allocation amounts by contract ID and allocation code.
*/
    @TestVisible
    private static void fetchExistingAllocations(
        List<InsurancePolicy> insurancePolicies,
        Map<Id, Map<Integer, Allocation_Code__c>>
        allocationCodesByContractId,
        Map<Id, Map<String, Decimal>>
        existingAllocAmountsByContractId
    ) {
        QDX_LOG.debug('***Inside fetchExistingAllocations***');
        
        try {
            Set<Id> contractIds = new Set<Id>();
            
            for (InsurancePolicy policy : insurancePolicies) {
                if (policy != null && policy.Id != null) {
                    contractIds.add(policy.Id);
                }
            }
            
            if (contractIds.isEmpty()) {
                QDX_LOG.debug(
                    'No contracts found to fetch existing allocations.'
                );
                return;
            }
            
            /*
* Rebuild the current signed lifecycle balance for every
* Allocation Code.
*
* Some ROP Allocation__c records do not retain Allocation_Code__c.
* Those records must not be discarded because their signed amounts
* are required when later funding determines how much remains
* available in a bucket.
*
* Resolution order:
* 1. Allocation's own Allocation Code.
* 2. A unique configured Descriptor/Payee match for ROP rows.
*/
            List<Allocation__c> allocationResults = [
                SELECT Id,
                Contract__c,
                Allocation_Amount__c,
                Descriptor__c,
                Payment_Return__c,
                Payee__c,
                Allocation_Code__c,
                Allocation_Code__r.Name,
                CreatedDate
                FROM Allocation__c
                WHERE Contract__c IN :contractIds
                ORDER BY CreatedDate ASC, Id ASC
            ];
            
            for (Allocation__c alloc : allocationResults) {
                if (
                    alloc.Contract__c == null ||
                    alloc.Allocation_Amount__c == null
                ) {
                    continue;
                }
                
                Map<Integer, Allocation_Code__c> contractCodes =
                    allocationCodesByContractId != null &&
                    allocationCodesByContractId.containsKey(
                        alloc.Contract__c
                    )
                    ? allocationCodesByContractId.get(alloc.Contract__c)
                    : new Map<Integer, Allocation_Code__c>();
                
                String effectiveAllocationCodeName =
                    resolveLifecycleAllocationCodeName(
                        alloc,
                        contractCodes
                    );
                
                if (String.isBlank(effectiveAllocationCodeName)) {
                    QDX_LOG.debug(
                        'Existing allocation excluded because its Allocation ' +
                        'Code could not be resolved.' +
                        ' AllocationId=' + alloc.Id +
                        ', ContractId=' + alloc.Contract__c +
                        ', Descriptor=' + alloc.Descriptor__c +
                        ', PaymentReturn=' + alloc.Payment_Return__c +
                        ', Amount=' + alloc.Allocation_Amount__c
                    );
                    continue;
                }
                
                if (
                    !existingAllocAmountsByContractId.containsKey(
                        alloc.Contract__c
                    )
                ) {
                    existingAllocAmountsByContractId.put(
                        alloc.Contract__c,
                        new Map<String, Decimal>()
                    );
                }
                
                Map<String, Decimal> currentBalances =
                    existingAllocAmountsByContractId.get(
                        alloc.Contract__c
                    );
                
                Decimal currentAmount =
                    currentBalances.containsKey(
                        effectiveAllocationCodeName
                    )
                    ? currentBalances.get(effectiveAllocationCodeName)
                    : 0;
                
                currentBalances.put(
                    effectiveAllocationCodeName,
                    roundCurrency(
                        currentAmount + alloc.Allocation_Amount__c
                    )
                );
            }
            
            QDX_LOG.debug(
                'Total contracts with existing allocations: ' +
                existingAllocAmountsByContractId.size()
            );
        } catch (Exception e) {
            QDX_LOG.error(
                'Error in fetchExistingAllocations - Message: ' +
                e.getMessage() +
                ', Line Number: ' +
                e.getLineNumber()
            );
        } finally {
            QDX_LOG.publish();
        }
    }
    
    /**
* @description
* Resolves the Allocation Code name used to rebuild a contract's signed
* lifecycle balance.
*
* ROP rows may have a blank Allocation_Code__c even though they represent
* a specific funding bucket. The method first uses stable lookup data and
* only falls back to configuration matching for ROP rows. Descriptor-only
* fallback is accepted only when it identifies one unique configured code.
*
* @param allocationRecord Allocation row being included in the lifecycle
* balance.
* @param allocationCodesByPriority Applicable contract Allocation Codes.
* @return Resolved Allocation Code name, or null when the row cannot be
* mapped safely.
*/
    @TestVisible
    private static String resolveLifecycleAllocationCodeName(
        Allocation__c allocationRecord,
        Map<Integer, Allocation_Code__c> allocationCodesByPriority
    ) {
        if (allocationRecord == null) {
            return null;
        }
        
        if (
            allocationRecord.Allocation_Code__c != null &&
            allocationRecord.Allocation_Code__r != null &&
            !String.isBlank(allocationRecord.Allocation_Code__r.Name)
        ) {
            return allocationRecord.Allocation_Code__r.Name;
        }
        
        /*
* Descriptor-based fallback is intentionally limited to return rows.
* Paid allocations without an Allocation Code are not silently
* attributed to a configured bucket.
*/
        if (
            allocationRecord.Payment_Return__c != 'R' ||
            allocationCodesByPriority == null ||
            allocationCodesByPriority.isEmpty()
        ) {
            return null;
        }
        
        String sourceDescriptor =
            normalizeRecoveryValue(allocationRecord.Descriptor__c);
        
        if (String.isBlank(sourceDescriptor)) {
            return null;
        }
        
        String sourcePayee =
            allocationRecord.Payee__c == null
            ? ''
            : normalizeRecoveryValue(
                String.valueOf(allocationRecord.Payee__c)
            );
        
        List<Integer> sortedPriorities =
            new List<Integer>(allocationCodesByPriority.keySet());
        sortedPriorities.sort();
        
        String exactPayeeCandidate;
        Boolean exactPayeeIsAmbiguous = false;
        String descriptorOnlyCandidate;
        Boolean descriptorIsAmbiguous = false;
        
        for (Integer priority : sortedPriorities) {
            Allocation_Code__c allocationCode =
                allocationCodesByPriority.get(priority);
            
            if (
                allocationCode == null ||
                String.isBlank(allocationCode.Name) ||
                normalizeRecoveryValue(allocationCode.Descriptor__c) !=
                sourceDescriptor
            ) {
                continue;
            }
            
            if (descriptorOnlyCandidate == null) {
                descriptorOnlyCandidate = allocationCode.Name;
            } else if (descriptorOnlyCandidate != allocationCode.Name) {
                descriptorIsAmbiguous = true;
            }
            
            String codePayee =
                allocationCode.Payee__c == null
                ? ''
                : normalizeRecoveryValue(
                    String.valueOf(allocationCode.Payee__c)
                );
            
            if (
                !String.isBlank(sourcePayee) &&
                sourcePayee == codePayee
            ) {
                if (exactPayeeCandidate == null) {
                    exactPayeeCandidate = allocationCode.Name;
                } else if (exactPayeeCandidate != allocationCode.Name) {
                    exactPayeeIsAmbiguous = true;
                }
            }
        }
        
        /*
* A fallback is accepted only when it identifies one unique code.
* Ambiguous configuration is excluded rather than assigning financial
* activity to an arbitrary bucket.
*/
        if (!String.isBlank(sourcePayee) && exactPayeeCandidate != null) {
            return exactPayeeIsAmbiguous
                ? null
                : exactPayeeCandidate;
        }
        
        return descriptorIsAmbiguous
            ? null
            : descriptorOnlyCandidate;
    }
    
    /**
* Processes funding records and allocates funds based on priority and existing allocations.
*
* The function:
* 1. Retrieves funding records that have not been processed.
* 2. Fetches existing reserve allocations.
* 3. Iterates over funding records and distributes available funding based on allocation priorities.
* 4. Updates contracts and funding records accordingly.
* 5. Performs DML operations to persist changes.
*
* @param allocPriorityByContractId Map of allocation codes sorted by priority for each contract.
* @param maxAllocByContractId Map of maximum allocation amounts per allocation code.
* @param existingAllocAmountsByContractId Map of existing allocation amounts per contract.
* @param insurancePolicies List of InsurancePolicy objects related to the contracts being processed.
*/
    /*   private static void processFundingRecords(
Map<Id, Map<Integer, Allocation_Code__c>> allocPriorityByContractId,
Map<Id, Map<String, Decimal>> maxAllocByContractId,
Map<Id, Map<String, Decimal>> existingAllocAmountsByContractId,
List<InsurancePolicy> insurancePolicies
) {
QDX_LOG.debug('***Inside processFundingRecords***');

try {
// Build a map for quick contract lookups
Map<Id, InsurancePolicy> contractMap = new Map<Id, InsurancePolicy>();
Map<Id, Datetime> contractReinstateDateMap = new Map<Id, Datetime>();
for (InsurancePolicy policy : insurancePolicies) {
contractMap.put(policy.Id, policy);
contractReinstateDateMap.put(policy.Id, policy.Reinstatement_Date__c);
}

// Query funding records that need processing
List<Funding__c> fundingRecords = [
SELECT Id, Contract__c, Funded_Amount__c, CreatedDate
FROM Funding__c
WHERE Time_Processed__c = NULL AND Funded_Amount__c > 0 AND Contract__c IN :contractMap.keySet()
ORDER BY CreatedDate
];

// Query all Allocation__c records and store them in a Map with Id as the key
List<Allocation__c> allocationList = [SELECT Id, Contract__c, Allocation_Amount__c, Descriptor__c, Allocation_Code__r.Name, CreatedDate, Payment_Return__c, Payee__c, is_Expense__c, Max_Allocation_Amount__c FROM Allocation__c where Contract__c in :contractMap.keySet()];
Map<Id,Map<String,Allocation__c>> allocationMapByContractId = new Map<Id,Map<String,Allocation__c>>();
Map<Id,List<Allocation__c>> allocationListByContractId = new Map<Id,List<Allocation__c>>();
//set allocationMapByContractId
for(Allocation__c alloc : allocationList) {
Datetime reinstateDate = contractReinstateDateMap.containsKey(alloc.Contract__c)?contractReinstateDateMap.get(alloc.Contract__c):null;
if (reinstateDate == null || reinstateDate <= alloc.CreatedDate) {   
if (!allocationMapByContractId.containsKey(alloc.Contract__c)) {
allocationMapByContractId.put(alloc.Contract__c, new Map<String, Allocation__c>());
}
// Get the inner map and put the Allocation__c record
allocationMapByContractId.get(alloc.Contract__c).put(alloc.Allocation_Code__r.Name, alloc);
}
if (!allocationListByContractId.containsKey(alloc.Contract__c)) {
allocationListByContractId.put(alloc.Contract__c, new List<Allocation__c>());
}
allocationListByContractId.get(alloc.Contract__c).add(alloc);
}

List<Allocation__c> allocationsToInsert = new List<Allocation__c>();
List<Funding__c> fundingRecordsToUpdate = new List<Funding__c>();
Map<Id,InsurancePolicy> contractsToUpdateMap = new Map<Id,InsurancePolicy>();

// Fetch existing reserve allocations per contract
Map<Id, Decimal> reserveAllocationSums = new Map<Id, Decimal>();

List<Allocation__c> reserveAllocations = [
SELECT Contract__c, Allocation_Amount__c,  CreatedDate
FROM Allocation__c
WHERE Allocation_Code__r.Allocation_Type__c = 'Reserve Split' AND Contract__c IN :contractMap.keySet()
];
for (Allocation__c alloc : reserveAllocations) {
Datetime reinstateDate = contractReinstateDateMap.containsKey(alloc.Contract__c)?contractReinstateDateMap.get(alloc.Contract__c):null;
if (reinstateDate == null || reinstateDate <= alloc.CreatedDate) {
Decimal currValue = reserveAllocationSums.containsKey(alloc.Contract__c)?reserveAllocationSums.get(alloc.Contract__c):0;
reserveAllocationSums.put(alloc.Contract__c, currValue + alloc.Allocation_Amount__c);
}
}

List<Allocation__c> allocationsToUpdate = new List<Allocation__c>();

List<ROP__c> allROPs = [SELECT Id, Contract__c, CreatedDate FROM ROP__c where Contract__c in :contractMap.keySet()];
Map<Id,ROP__c> latestROPByContractId = new Map<Id,ROP__c>();
for (ROP__c rop : allROPs) {
Datetime reinstateDate = contractReinstateDateMap.containsKey(rop.Contract__c)?contractReinstateDateMap.get(rop.Contract__c):null;
ROP__c latestROP = latestROPByContractId.containsKey(rop.Contract__c)?latestROPByContractId.get(rop.Contract__c):null;
//if(rop.CreatedDate <= reinstateDate) {
if (reinstateDate == null || rop.CreatedDate >= reinstateDate) {
if (latestROP == null || rop.CreatedDate > latestROP.CreatedDate) {
latestROPByContractId.put(rop.Contract__c,rop);
}
}
}

List<Id> isROPAllocationsCreated = new List<Id>();
// Process each funding record
for (Funding__c fundingRecord : fundingRecords) {
Datetime reinstateDate = contractReinstateDateMap.containsKey(fundingRecord.Contract__c)?contractReinstateDateMap.get(fundingRecord.Contract__c):null;
if(reinstateDate!=null && !isROPAllocationsCreated.contains(fundingRecord.Contract__c)) {

Allocation__c latestAlloc = null;
if(allocationListByContractId.containsKey(fundingRecord.Contract__c)) {
for (Allocation__c alloc : allocationListByContractId.get(fundingRecord.Contract__c)) {
if (alloc.Contract__c == fundingRecord.Contract__c && alloc.Payment_Return__c == 'P') {
if (latestAlloc == null || alloc.CreatedDate > latestAlloc.CreatedDate) {
latestAlloc = alloc;
}
}
}
}

if (latestAlloc != null && latestAlloc.CreatedDate < reinstateDate) {
// 1. Query for the most recent ROP__c record related to the contract --TODO Why is this needed?
ROP__c ropRecord = latestROPByContractId.containsKey(fundingRecord.Contract__c)?latestROPByContractId.get(fundingRecord.Contract__c):null;

// 2. Query Allocation__c records for the contract with Payment_Return__c = 'R'
//111 - iterate this loop on map from 111
List<Allocation__c> rAllocations = new List<Allocation__c>();
if (ropRecord == null) continue;
for (Allocation__c alloc : allocationListByContractId.get(fundingRecord.Contract__c)) {
if (alloc.Contract__c == fundingRecord.Contract__c && alloc.Payment_Return__c == 'R' 
&& alloc.CreatedDate >= ropRecord.CreatedDate) {
rAllocations.add(alloc);
}
}

// 3. For each of those R-flag allocations, create a new "P" allocation with negated amount
for (Allocation__c rAlloc : rAllocations) {
Allocation__c newAlloc = new Allocation__c();
newAlloc.Contract__c = rAlloc.Contract__c;
newAlloc.Allocation_Code__c = rAlloc.Allocation_Code__c;
newAlloc.Allocation_Amount__c = rAlloc.Allocation_Amount__c * -1;
newAlloc.Descriptor__c = rAlloc.Descriptor__c;
newAlloc.Payee__c = rAlloc.Payee__c;
newAlloc.is_Expense__c = rAlloc.is_Expense__c;
newAlloc.Payment_Return__c = 'P';
newAlloc.Max_Allocation_Amount__c = rAlloc.Max_Allocation_Amount__c;

allocationsToInsert.add(newAlloc);
}
isROPAllocationsCreated.add(fundingRecord.Contract__c);

// Timestamp the Funding__c record if needed
fundingRecord.Time_Processed__c = System.now();
fundingRecordsToUpdate.add(fundingRecord);

// Update DLRS_Total_Funded_Amount_from_Funding__c for the related contract
InsurancePolicy contractToUpdate;
if (contractsToUpdateMap.containsKey(fundingRecord.Contract__c)) {
contractToUpdate = contractsToUpdateMap.get(fundingRecord.Contract__c);
} else {
contractToUpdate = contractMap.get(fundingRecord.Contract__c);
}
contractToUpdate.DLRS_Total_Funded_Amount_from_Funding__c =
(contractToUpdate.DLRS_Total_Funded_Amount_from_Funding__c == null ? 0 : contractToUpdate.DLRS_Total_Funded_Amount_from_Funding__c)
+ fundingRecord.Funded_Amount__c;

contractsToUpdateMap.put(fundingRecord.Contract__c, contractToUpdate);
continue;
}
}
if (reinstateDate == null || reinstateDate <= fundingRecord.CreatedDate) {

Decimal remainingFunding = fundingRecord.Funded_Amount__c;
Id contractId = fundingRecord.Contract__c;
InsurancePolicy currentContract = contractMap.get(contractId);
if (!allocPriorityByContractId.containsKey(contractId)) {
fundingRecord.Time_Processed__c = System.now();
fundingRecordsToUpdate.add(fundingRecord);
continue; // Skip contracts with no allocation codes
}
// Get allocation codes sorted by priority
Map<Integer, Allocation_Code__c> allocationCodesByPriority = allocPriorityByContractId.get(contractId);
List<Integer> sortedPriorities = new List<Integer>(allocationCodesByPriority.keySet());
sortedPriorities.sort();
List<Allocation_Code__c> reserveSplitAllocCodes = new List<Allocation_Code__c>();
// Distribute funds based on allocation priority
for (Integer priority : sortedPriorities) {
Allocation_Code__c allocCode = allocationCodesByPriority.get(priority);
if(allocCode.Allocation_Type__c == 'Reserve Split') {
reserveSplitAllocCodes.add(allocCode);
} else {
String allocationCodeValue = allocCode.Name;
Decimal maxAllocationAmount = maxAllocByContractId.get(currentContract.Id).get(allocCode.Name);

// Get existing allocation amount (if any)
Decimal existingAllocationAmount = 0;
if (existingAllocAmountsByContractId.containsKey(contractId) &&
existingAllocAmountsByContractId.get(contractId).containsKey(allocationCodeValue)) {
existingAllocationAmount = existingAllocAmountsByContractId.get(contractId).get(allocationCodeValue);
}
// Calculate amount to be allocated
Decimal amountToBeFunded = 0;
if (existingAllocationAmount < maxAllocationAmount) {
amountToBeFunded = Math.min(remainingFunding, maxAllocationAmount - existingAllocationAmount);
}
// Create a new allocation if funding is available
if (amountToBeFunded > 0) {
allocationsToInsert.add(new Allocation__c(
Allocation_Amount__c = amountToBeFunded,
Allocation_Code__c = allocCode.Id,
Contract__c = contractId,
Payment_Return__c = 'P',
Payee__c = allocCode.Payee__c,
is_Expense__c = allocCode.is_Expense__c,
Descriptor__c = allocCode.Descriptor__c,
Max_Allocation_Amount__c = maxAllocationAmount
));
remainingFunding -= amountToBeFunded;

// Update existing allocation amounts map
if (!existingAllocAmountsByContractId.containsKey(contractId)) {
existingAllocAmountsByContractId.put(contractId, new Map<String, Decimal>());
}
existingAllocAmountsByContractId.get(contractId).put(allocationCodeValue, existingAllocationAmount + amountToBeFunded);
}
}
}

//below is new logic start
if(!reserveSplitAllocCodes.isEmpty()) {

// Get existing allocations for this contract to check what's already allocated
Map<String, Decimal> allocationAmountByDescriptor = existingAllocAmountsByContractId.get(contractId);
if (allocationAmountByDescriptor == null) {
allocationAmountByDescriptor = new Map<String, Decimal>(); // Initialize if no existing allocations
}

// Filter out allocation codes that are already fully allocated
List<Allocation_Code__c> allocCodesToSplit = new List<Allocation_Code__c>();
for (Allocation_Code__c allocCode : reserveSplitAllocCodes) {
Decimal maxAllocationAmount = maxAllocByContractId.get(currentContract.Id).get(allocCode.Name);
Decimal alreadyAllocated = allocationAmountByDescriptor.containsKey(allocCode.Name)
? allocationAmountByDescriptor.get(allocCode.Name)
: 0;

// Check if the total allocated amount for this descriptor is less than the Allocation_Amount__c defined on the Allocation Code
if (alreadyAllocated < (maxAllocationAmount != null ? maxAllocationAmount : 0)) {
allocCodesToSplit.add(allocCode);
}
}                       

// If all reserveSplitAllocCodes are fully allocated, timestamp the funding record and continue
if (!allocCodesToSplit.isEmpty()) {
for (Integer i = 0; i < allocCodesToSplit.size(); i++) {

Allocation_Code__c currentAllocCode = allocCodesToSplit[i];
Decimal maxAllocationAmount = maxAllocByContractId.get(currentContract.Id).get(currentAllocCode.Name);
// Calculate the number of allocation codes remaining to split funding among
Integer numberOfRemainingCodes = allocCodesToSplit.size() - i;

// Avoid division by zero if somehow the number of remaining codes is zero
Decimal splitAllocationAmount = (numberOfRemainingCodes > 0)
? remainingFunding / numberOfRemainingCodes
: 0;

// Get the total amount already allocated for this descriptor across all previous allocations
Decimal alreadyAllocatedTotal = allocationAmountByDescriptor.containsKey(currentAllocCode.Name)
? allocationAmountByDescriptor.get(currentAllocCode.Name)
: 0;

// Calculate the remaining amount needed for this specific allocation code based on its defined Allocation_Amount__c
Decimal amountNeededForThisCode = (maxAllocationAmount != null ? maxAllocationAmount : 0) - alreadyAllocatedTotal;

// Determine the actual amount to allocate in this step for this allocation code
// It's the minimum of the calculated split amount and the remaining amount needed for this code.
Decimal allocationAmountToUse = Math.min(splitAllocationAmount, amountNeededForThisCode);

// Ensure the allocation amount is not negative or zero if funding is depleted
// If remaining funding is zero, we can't allocate more
if (allocationAmountToUse < 0 || remainingFunding <= 0) {
allocationAmountToUse = 0;
}

if (allocationAmountToUse > 0) {
Allocation__c alloc = new Allocation__c();
alloc.Allocation_Amount__c = allocationAmountToUse;
alloc.Allocation_Code__c = currentAllocCode.Id;
alloc.Contract__c = contractId;
alloc.Payment_Return__c = 'P'; 
alloc.Payee__c = currentAllocCode.Payee__c;
alloc.is_Expense__c = currentAllocCode.is_Expense__c;
alloc.Descriptor__c = currentAllocCode.Descriptor__c;
alloc.Max_Allocation_Amount__c = maxAllocationAmount;

allocationsToInsert.add(alloc);

// Update the total allocated amount for this descriptor in the map
allocationAmountByDescriptor.put(currentAllocCode.Name, alreadyAllocatedTotal + allocationAmountToUse);

// Deduct the allocated amount from the remaining funding
remainingFunding -= allocationAmountToUse;
}

// If remaining funding is depleted, we can stop allocating
if (remainingFunding <= 0) {
break;
}
}
}
}
// Mark funding record as processed
fundingRecord.Time_Processed__c = System.now();

fundingRecordsToUpdate.add(fundingRecord);

// Update DLRS_Total_Funded_Amount_from_Funding__c for the related contract
InsurancePolicy contractToUpdate;
if (contractsToUpdateMap.containsKey(fundingRecord.Contract__c)) {
contractToUpdate = contractsToUpdateMap.get(fundingRecord.Contract__c);
} else {
contractToUpdate = contractMap.get(fundingRecord.Contract__c);
}
contractToUpdate.DLRS_Total_Funded_Amount_from_Funding__c =
(contractToUpdate.DLRS_Total_Funded_Amount_from_Funding__c == null ? 0 : contractToUpdate.DLRS_Total_Funded_Amount_from_Funding__c)
+ fundingRecord.Funded_Amount__c;

contractsToUpdateMap.put(fundingRecord.Contract__c, contractToUpdate);
}
}

// Perform bulk DML operations with partial success handling
if (!fundingRecordsToUpdate.isEmpty()) {
Database.update(fundingRecordsToUpdate, false);
}

if (!allocationsToInsert.isEmpty()) {
Database.insert(allocationsToInsert, false);
}

// Update allocation-related fields on contracts
updateContractAllocationFields(contractsToUpdateMap);

if (!contractsToUpdateMap.isEmpty()) {
Database.update(contractsToUpdateMap.values(), false);
}

} catch (Exception e) {
// Log error details
QDX_LOG.error('Error in processFundingRecords - Message: ' + e.getMessage() +
', Line Number: ' + e.getLineNumber());
} finally {
// Ensure logs are always published
QDX_LOG.publish();
}
} */
    
    /**
* @description Calculates Reserve Split funding distribution without SOQL/DML.
*
* Rules:
* 1. Split available funding as evenly as possible.
* 2. Never exceed any split Allocation Code's remaining capacity.
* 3. If one split reaches capacity, redistribute its excess to the
*    remaining eligible split(s).
* 4. Ensure allocated amounts total exactly to the available funding,
*    up to the total remaining split capacity.
* 5. Handle odd-cent amounts deterministically.
*/
    @TestVisible
    private static Map<Id, Decimal> calculateReserveSplitDistribution(
        List<Allocation_Code__c> reserveSplits,
        Decimal fundingAvailable,
        Map<String, Decimal> maxAmountsByCodeName,
        Map<String, Decimal> existingAmountsByCodeName
    ){
        Map<Id, Decimal> distributionByCodeId =
            new Map<Id, Decimal>();
        
        if(
            reserveSplits == null ||
            reserveSplits.isEmpty() ||
            fundingAvailable == null ||
            fundingAvailable <= 0
        ){
            return distributionByCodeId;
        }
        
        Decimal fundsRemaining =
            roundCurrency(fundingAvailable);
        
        Map<Id, Decimal> remainingCapacityByCodeId =
            new Map<Id, Decimal>();
        
        List<Allocation_Code__c> activeSplits =
            new List<Allocation_Code__c>();
        
        
        // ---------------------------------------------------------
        // 1. Determine remaining capacity of each Reserve Split
        // ---------------------------------------------------------
        for(Allocation_Code__c splitCode : reserveSplits){
            
            if(
                splitCode == null ||
                splitCode.Id == null ||
                String.isBlank(splitCode.Name)
            ){
                continue;
            }
            
            Decimal maxAmount =
                maxAmountsByCodeName != null &&
                maxAmountsByCodeName.containsKey(splitCode.Name) &&
                maxAmountsByCodeName.get(splitCode.Name) != null
                ? maxAmountsByCodeName.get(splitCode.Name)
                : 0;
            
            Decimal alreadyAllocated =
                existingAmountsByCodeName != null &&
                existingAmountsByCodeName.containsKey(splitCode.Name) &&
                existingAmountsByCodeName.get(splitCode.Name) != null
                ? existingAmountsByCodeName.get(splitCode.Name)
                : 0;
            
            Decimal remainingCapacity =
                roundCurrency(
                    maxAmount - alreadyAllocated
                );
            
            if(remainingCapacity <= 0){
                continue;
            }
            
            remainingCapacityByCodeId.put(
                splitCode.Id,
                remainingCapacity
            );
            
            distributionByCodeId.put(
                splitCode.Id,
                0
            );
            
            activeSplits.add(splitCode);
        }
        
        
        // ---------------------------------------------------------
        // 2. Waterfall / redistribution processing
        // ---------------------------------------------------------
        while(
            fundsRemaining > 0 &&
            !activeSplits.isEmpty()
        ){
            
            /*
* Always round DOWN here.
*
* Example:
* 78.27 / 2 = 39.135
*
* Base shares:
* 39.13 + 39.13
*
* Remaining penny is assigned separately below.
*/
            Decimal equalShare =
                (
                    fundsRemaining /
                    activeSplits.size()
                ).setScale(
                    2,
                    RoundingMode.DOWN
                );
            
            Boolean splitReachedCapacity = false;
            
            List<Allocation_Code__c> stillActive =
                new List<Allocation_Code__c>();
            
            
            /*
* First handle any split whose available capacity
* is less than or equal to the equal share.
*
* Once capped, its unallocated portion remains in
* fundsRemaining and is redistributed on the next pass.
*/
            for(Allocation_Code__c splitCode : activeSplits){
                
                Decimal remainingCapacity =
                    remainingCapacityByCodeId.get(
                        splitCode.Id
                    );
                
                if(
                    remainingCapacity != null &&
                    remainingCapacity > 0 &&
                    remainingCapacity <= equalShare
                ){
                    
                    Decimal amountToAllocate =
                        roundCurrency(
                            remainingCapacity
                        );
                    
                    Decimal existingPlanned =
                        distributionByCodeId.get(
                            splitCode.Id
                        );
                    
                    distributionByCodeId.put(
                        splitCode.Id,
                        roundCurrency(
                            existingPlanned +
                            amountToAllocate
                        )
                    );
                    
                    fundsRemaining =
                        roundCurrency(
                            fundsRemaining -
                            amountToAllocate
                        );
                    
                    remainingCapacityByCodeId.put(
                        splitCode.Id,
                        0
                    );
                    
                    splitReachedCapacity = true;
                    
                }else{
                    
                    stillActive.add(splitCode);
                }
            }
            
            
            /*
* A split was capped.
*
* Recalculate the equal share using only the
* remaining eligible split codes.
*/
            if(splitReachedCapacity){
                
                activeSplits = stillActive;
                continue;
            }
            
            
            // -----------------------------------------------------
            // 3. Nobody is capped — apply equal base share
            // -----------------------------------------------------
            if(equalShare > 0){
                
                for(Allocation_Code__c splitCode : activeSplits){
                    
                    Decimal remainingCapacity =
                        remainingCapacityByCodeId.get(
                            splitCode.Id
                        );
                    
                    Decimal amountToAllocate =
                        Math.min(
                            equalShare,
                            remainingCapacity
                        );
                    
                    amountToAllocate =
                        roundCurrency(
                            amountToAllocate
                        );
                    
                    if(amountToAllocate <= 0){
                        continue;
                    }
                    
                    Decimal existingPlanned =
                        distributionByCodeId.get(
                            splitCode.Id
                        );
                    
                    distributionByCodeId.put(
                        splitCode.Id,
                        roundCurrency(
                            existingPlanned +
                            amountToAllocate
                        )
                    );
                    
                    remainingCapacityByCodeId.put(
                        splitCode.Id,
                        roundCurrency(
                            remainingCapacity -
                            amountToAllocate
                        )
                    );
                    
                    fundsRemaining =
                        roundCurrency(
                            fundsRemaining -
                            amountToAllocate
                        );
                }
            }
            
            
            // -----------------------------------------------------
            // 4. Distribute rounding remainder one cent at a time
            // -----------------------------------------------------
            Boolean pennyAllocated = true;
            
            while(
                fundsRemaining >= 0.01 &&
                pennyAllocated
            ){
                
                pennyAllocated = false;
                
                for(Allocation_Code__c splitCode : activeSplits){
                    
                    if(fundsRemaining < 0.01){
                        break;
                    }
                    
                    Decimal remainingCapacity =
                        remainingCapacityByCodeId.get(
                            splitCode.Id
                        );
                    
                    if(
                        remainingCapacity == null ||
                        remainingCapacity < 0.01
                    ){
                        continue;
                    }
                    
                    Decimal existingPlanned =
                        distributionByCodeId.get(
                            splitCode.Id
                        );
                    
                    distributionByCodeId.put(
                        splitCode.Id,
                        roundCurrency(
                            existingPlanned + 0.01
                        )
                    );
                    
                    remainingCapacityByCodeId.put(
                        splitCode.Id,
                        roundCurrency(
                            remainingCapacity - 0.01
                        )
                    );
                    
                    fundsRemaining =
                        roundCurrency(
                            fundsRemaining - 0.01
                        );
                    
                    pennyAllocated = true;
                }
            }
            
            /*
* At this point the available funding has either been
* fully distributed or every active split is at capacity.
*/
            break;
        }
        
        
        return distributionByCodeId;
    }
    
    /**
 * @description
 * Reconciles Funded_Reserve_Pack__c with the actual signed
 * Reserve Pack Allocation__c ledger.
 *
 * This uses Allocation__c as the source of truth so the field
 * always matches the total of Reserve Pack allocations actually
 * persisted in Salesforce.
 *
 * No DML is performed here. The supplied InsurancePolicy records
 * are updated in memory and are persisted by the caller's existing
 * bulk update.
 */
@TestVisible
private static void reconcileFundedReservePack(
    Map<Id, InsurancePolicy> contractsToUpdateMap
){
    if(
        contractsToUpdateMap == null || contractsToUpdateMap.isEmpty()
    ){
        return;
    }

    Map<Id, Decimal> reservePackTotalsByContract =
        new Map<Id, Decimal>();

    for(AggregateResult ar : [
        SELECT
            Contract__c contractId,
            SUM(Allocation_Amount__c) totalAmount
        FROM Allocation__c
        WHERE Contract__c IN :contractsToUpdateMap.keySet()
        AND Descriptor__c = :'Reserve Pack'
        GROUP BY Contract__c
    ]){

        Id contractId =
            (Id)ar.get('contractId');

        Decimal totalAmount =
            (Decimal)ar.get('totalAmount');

        reservePackTotalsByContract.put(
            contractId,
            roundCurrency(
                totalAmount == null
                ? 0
                : totalAmount
            )
        );
    }

    for(Id contractId : reservePackTotalsByContract.keySet()){

        InsurancePolicy contractRecord =
            contractsToUpdateMap.get(contractId);

        if(contractRecord == null){
            continue;
        }

        contractRecord.Funded_Reserve_Pack__c =
            reservePackTotalsByContract.get(contractId);

        contractsToUpdateMap.put(
            contractId,
            contractRecord
        );
    }
}

    private static void processFundingRecords(
        Map<Id, Map<Integer, Allocation_Code__c>> allocPriorityByContractId,
        Map<Id, Map<String, Decimal>> maxAllocByContractId,
        Map<Id, Map<String, Decimal>> existingAllocAmountsByContractId,
        List<InsurancePolicy> insurancePolicies
    ) {
        QDX_LOG.error('ENTERED processFundingRecords');
        QDX_LOG.debug('***Inside processFundingRecords (PATCH v2)***');
        
        try {
            // Build quick contract lookup
            Map<Id, InsurancePolicy> contractMap = new Map<Id, InsurancePolicy>();
            Map<Id, Datetime> contractReinstateDateMap = new Map<Id, Datetime>();
            for (InsurancePolicy policy : insurancePolicies) {
                contractMap.put(policy.Id, policy);
                contractReinstateDateMap.put(policy.Id, policy.Reinstatement_Date__c);
            }
            
            // --- 1. Query pending Funding__c records
            List<Funding__c> fundingRecords = [
                SELECT Id, Contract__c, Funded_Amount__c, CreatedDate
                FROM Funding__c
                WHERE Time_Processed__c = NULL
                AND Funded_Amount__c != 0
                AND Contract__c IN :contractMap.keySet()
                ORDER BY CreatedDate ASC, Id ASC
            ];
            
            
            if (fundingRecords.isEmpty()) {
                QDX_LOG.debug('No Funding__c records found to process.');
                return;
            }
            
            Map<Id, List<Funding__c>> fundingByContractId =
                new Map<Id, List<Funding__c>>();
            
            for (Funding__c fundingHistory : [
                SELECT Id,
                Contract__c,
                Funded_Amount__c,
                CreatedDate,
                Time_Processed__c
                FROM Funding__c
                WHERE Contract__c IN :contractMap.keySet()
                AND Funded_Amount__c != null
                ORDER BY CreatedDate ASC, Id ASC
            ]) {
                
                if (fundingHistory.Contract__c == null) {
                    continue;
                }
                
                if (!fundingByContractId.containsKey(fundingHistory.Contract__c)) {
                    fundingByContractId.put(
                        fundingHistory.Contract__c,
                        new List<Funding__c>()
                    );
                }
                
                fundingByContractId.get(fundingHistory.Contract__c).add(fundingHistory);
            }
            
            // --- 2. Query related Allocations and map by Contract
            List<Allocation__c> allocationList = [
                SELECT Id,
                Contract__c,
                Allocation_Amount__c,
                Descriptor__c,
                Allocation_Code__c,
                Allocation_Code__r.Name,
                Allocation_Code__r.Descriptor__c,
                CreatedDate,
                Payment_Return__c,
                Payee__c,
                is_Expense__c,
                Max_Allocation_Amount__c,
                Reference_Allocation__c,
                Fee_Label_for_Summary_Reporting__c
                FROM Allocation__c
                WHERE Contract__c IN :contractMap.keySet()
                ORDER BY CreatedDate ASC, Id ASC
            ];
            Map<Id, List<Allocation__c>> rAllocationsByContractId = new Map<Id, List<Allocation__c>>();
            
            
            Map<Id, Map<String, Allocation__c>> allocationMapByContractId = new Map<Id, Map<String, Allocation__c>>();
            Map<Id, List<Allocation__c>> allocationListByContractId = new Map<Id, List<Allocation__c>>();
            
            
            for (Allocation__c alloc : allocationList) {
                
                if (isPotentialReinstatementSourceAllocation(alloc)) {
                    
                    if (!rAllocationsByContractId.containsKey(alloc.Contract__c)) {
                        rAllocationsByContractId.put(
                            alloc.Contract__c,
                            new List<Allocation__c>()
                        );
                    }
                    
                    rAllocationsByContractId.get(alloc.Contract__c).add(alloc);
                }
                Datetime reinstateDate = contractReinstateDateMap.get(alloc.Contract__c);
                
                if (
                    (reinstateDate == null || alloc.CreatedDate >= reinstateDate)
                    &&
                    alloc.Allocation_Code__r != null
                    &&
                    !String.isBlank(alloc.Allocation_Code__r.Name)
                ) {
                    if (!allocationMapByContractId.containsKey(alloc.Contract__c)) {
                        allocationMapByContractId.put(
                            alloc.Contract__c,
                            new Map<String, Allocation__c>()
                        );
                    }
                    
                    allocationMapByContractId
                        .get(alloc.Contract__c)
                        .put(alloc.Allocation_Code__r.Name, alloc);
                }
                if (!allocationListByContractId.containsKey(alloc.Contract__c))
                    allocationListByContractId.put(alloc.Contract__c, new List<Allocation__c>());
                allocationListByContractId.get(alloc.Contract__c).add(alloc);
                
            }
            
            // --- 3. Reserve allocations (for Reserve Split logic)
            Map<Id, Decimal> reserveAllocationSums = new Map<Id, Decimal>();
            List<Allocation__c> reserveAllocations = [
                SELECT Contract__c, Allocation_Amount__c, CreatedDate
                FROM Allocation__c
                WHERE Allocation_Code__r.Allocation_Type__c = 'Reserve Split'
                AND Contract__c IN :contractMap.keySet()
            ];
            for (Allocation__c alloc : reserveAllocations) {
                if (alloc.Contract__c == null) continue;
                
                Datetime reinstateDate = contractReinstateDateMap.get(alloc.Contract__c);
                if (reinstateDate == null || alloc.CreatedDate >= reinstateDate) {
                    Decimal existingSum = reserveAllocationSums.containsKey(alloc.Contract__c)
                        ? reserveAllocationSums.get(alloc.Contract__c)
                        : 0;
                    reserveAllocationSums.put(
                        alloc.Contract__c,
                        existingSum + alloc.Allocation_Amount__c
                    );
                }
            }
            
            
            // --- 4. Preload ROP data
            /*Map<Id, ROP__c> latestROPByContractId = new Map<Id, ROP__c>();
for (ROP__c rop : [
SELECT Id, Contract__c, CreatedDate
FROM ROP__c
WHERE Contract__c IN :contractMap.keySet()
]) {
Datetime reinstateDate = contractReinstateDateMap.get(rop.Contract__c);
if (reinstateDate == null || rop.CreatedDate >= reinstateDate) {
if (!latestROPByContractId.containsKey(rop.Contract__c)
|| rop.CreatedDate > latestROPByContractId.get(rop.Contract__c).CreatedDate) {
latestROPByContractId.put(rop.Contract__c, rop);
}
}
}*/
            
            // --- 5. Prepare DML lists
            List<Allocation__c> allocationsToInsert = new List<Allocation__c>();
            List<Funding__c> fundingRecordsToUpdate = new List<Funding__c>();
            Map<Id, InsurancePolicy> contractsToUpdateMap = new Map<Id, InsurancePolicy>();
            //Set<Id> ropHandledContracts = new Set<Id>();
            Set<Id> recoveredContracts = new Set<Id>();
            
            // --- 6. Main funding processing loop
            
            for (Funding__c funding : fundingRecords) {
                
                try {
                    Id contractId = funding.Contract__c;
                    if (contractId == null || !contractMap.containsKey(contractId)) {
                        QDX_LOG.error('Skipping Funding record ' + funding.Id + ' — missing or unknown Contract__c.');
                        continue;
                    }
                    InsurancePolicy currentContract = contractMap.get(contractId);
                    Datetime reinstateDate = contractReinstateDateMap.get(contractId);
                    Decimal remainingFunding =
                        processReinstatementRecovery(
                            
                            funding,
                            
                            currentContract,
                            
                            fundingByContractId.containsKey(contractId)
                            ? fundingByContractId.get(contractId)
                            : new List<Funding__c>(),
                            
                            rAllocationsByContractId.containsKey(contractId)
                            ? rAllocationsByContractId.get(contractId)
                            : new List<Allocation__c>(),
                            
                            allocationListByContractId.containsKey(contractId)
                            ? allocationListByContractId.get(contractId)
                            : new List<Allocation__c>(),
                            
                            allocPriorityByContractId.containsKey(contractId)
                            ? allocPriorityByContractId.get(contractId)
                            : new Map<Integer, Allocation_Code__c>(),
                            
                            maxAllocByContractId.containsKey(contractId)
                            ? maxAllocByContractId.get(contractId)
                            : new Map<String, Decimal>(),
                            
                            allocationsToInsert,
                            
                            existingAllocAmountsByContractId,
                            
                            recoveredContracts
                            
                        );
                    
                    
                    // =====================================================
                    // NEGATIVE FUNDING
                    // =====================================================
                    
                    if (remainingFunding < 0) {
                        
                        Decimal remainingToReverse =
                            Math.abs(remainingFunding);
                        
                        Allocation__c latestReserve;
                        
                        List<Allocation__c> latestReserveList = [
                            SELECT Id,
                            Contract__c,
                            Allocation_Code__c,
                            Allocation_Amount__c,
                            Descriptor__c,
                            Payee__c,
                            is_Expense__c,
                            Max_Allocation_Amount__c,
                            Payment_Return__c,
                            CreatedDate
                            FROM Allocation__c
                            WHERE Contract__c = :contractId
                            AND Descriptor__c = 'Reserve'
                            AND Allocation_Amount__c > 0
                            ORDER BY CreatedDate DESC
                            LIMIT 1
                        ];
                        
                        if(!latestReserveList.isEmpty()){
                            
                            latestReserve = latestReserveList[0];
                            
                            Decimal currentReserveBalance =
                                latestReserve.Allocation_Amount__c;
                            
                            Decimal newReserveBalance =
                                currentReserveBalance - Math.abs(remainingFunding);
                            
                            if(newReserveBalance < 0){
                                newReserveBalance = 0;
                            }
                            
                            allocationsToInsert.add(
                                new Allocation__c(
                                    Contract__c = latestReserve.Contract__c,
                                    Allocation_Code__c = latestReserve.Allocation_Code__c,
                                    Allocation_Amount__c = newReserveBalance,
                                    Descriptor__c = latestReserve.Descriptor__c,
                                    Payee__c = latestReserve.Payee__c,
                                    is_Expense__c = latestReserve.is_Expense__c,
                                    Payment_Return__c = 'R',
                                    Max_Allocation_Amount__c =(currentContract.Written_Reserve__c == null)? 0 : currentContract.Written_Reserve__c
                                )
                            );
                        }
                        // =====================================================
                        // Update Funded Reserve
                        // =====================================================
                        
                        InsurancePolicy updateContract =
                            contractsToUpdateMap.containsKey(contractId) ? contractsToUpdateMap.get(contractId) : currentContract;
                        
                        Decimal currentReserve =
                            updateContract.Funded_Reserve__c == null ? 0 : updateContract.Funded_Reserve__c;
                        
                        updateContract.Funded_Reserve__c =
                            currentReserve - (Math.abs(remainingFunding) - remainingToReverse);
                        
                        contractsToUpdateMap.put(
                            contractId,
                            updateContract
                        );
                        
                        // =====================================================
                        // Update existing allocation tracking
                        // =====================================================
                        
                        if(
                            existingAllocAmountsByContractId.containsKey(contractId)
                        ){
                            Map<String, Decimal> existingMap =
                                existingAllocAmountsByContractId.get(contractId);
                            
                            for(String allocName : existingMap.keySet()){
                                
                                Decimal existingValue =
                                    existingMap.get(allocName);
                                
                                if(existingValue > 0){
                                    
                                    Decimal reduction =
                                        Math.min(
                                            existingValue,
                                            Math.abs(remainingFunding)
                                        );
                                    
                                    existingMap.put(
                                        allocName,
                                        existingValue - reduction
                                    );
                                    
                                    break;
                                }
                            }
                        }
                        
                        // =====================================================
                        // Mark funding processed
                        // =====================================================
                        
                        funding.Time_Processed__c = System.now();
                        
                        fundingRecordsToUpdate.add(funding);
                        
                        // =====================================================
                        // Update DLRS field
                        // =====================================================
                        
                        updateContract.DLRS_Total_Funded_Amount_from_Funding__c =
                            (
                                updateContract.DLRS_Total_Funded_Amount_from_Funding__c == null
                            )? funding.Funded_Amount__c: updateContract.DLRS_Total_Funded_Amount_from_Funding__c + funding.Funded_Amount__c;
                        
                        contractsToUpdateMap.put(
                            contractId,
                            updateContract
                        );
                        
                        // =====================================================
                        // Skip positive funding logic
                        // =====================================================
                        
                        continue;
                    }
                    
                    // Skip contracts with no allocation codes
                    if (!allocPriorityByContractId.containsKey(contractId)) continue;
                    
                    // --- 6A. Handle ROP adjustment logic
                    /*if (reinstateDate != null && !ropHandledContracts.contains(contractId)) {
Allocation__c latestPaidAlloc;
if (allocationListByContractId.containsKey(contractId)) {
for (Allocation__c a : allocationListByContractId.get(contractId)) {
if (a.Payment_Return__c == 'P' &&
(latestPaidAlloc == null || a.CreatedDate > latestPaidAlloc.CreatedDate))
latestPaidAlloc = a;
}
}

if (latestPaidAlloc != null && latestPaidAlloc.CreatedDate < reinstateDate) {
ROP__c ropRecord = latestROPByContractId.get(contractId);
if (ropRecord != null && allocationListByContractId.containsKey(contractId)) {
for (Allocation__c rAlloc : allocationListByContractId.get(contractId)) {
if (rAlloc.Payment_Return__c == 'R' &&
rAlloc.CreatedDate >= ropRecord.CreatedDate) {
allocationsToInsert.add(new Allocation__c(
Contract__c = rAlloc.Contract__c,
Allocation_Code__c = rAlloc.Allocation_Code__c,
Allocation_Amount__c = -rAlloc.Allocation_Amount__c,
Descriptor__c = rAlloc.Descriptor__c,
Payee__c = rAlloc.Payee__c,
is_Expense__c = rAlloc.is_Expense__c,
Payment_Return__c = 'P',
Max_Allocation_Amount__c = rAlloc.Max_Allocation_Amount__c
));
}
}
}
ropHandledContracts.add(contractId);
}
}*/
                    
                    // --- 6B. Handle standard funding allocation
                    if (reinstateDate == null || funding.CreatedDate >= reinstateDate) {
                        Map<Integer, Allocation_Code__c> allocCodes = allocPriorityByContractId.get(contractId);
                        List<Integer> sortedPriorities = new List<Integer>(allocCodes.keySet());
                        sortedPriorities.sort();
                        
                        List<Allocation_Code__c> reserveSplits = new List<Allocation_Code__c>();
                        
                        for (Integer priority : sortedPriorities) {
                            Allocation_Code__c allocCode = allocCodes.get(priority);
                            if (allocCode == null) continue;
                            
                            if (allocCode.Allocation_Type__c == 'Reserve Split') {
                                reserveSplits.add(allocCode);
                                continue;
                            }
                            
                            // --- Safe retrievals ---
                            Map<String, Decimal> contractMaxMap = maxAllocByContractId.containsKey(contractId)
                                ? maxAllocByContractId.get(contractId)
                                : new Map<String, Decimal>();
                            Map<String, Decimal> existingMap = existingAllocAmountsByContractId.containsKey(contractId)
                                ? existingAllocAmountsByContractId.get(contractId)
                                : new Map<String, Decimal>();
                            
                            Decimal maxAmount = contractMaxMap.containsKey(allocCode.Name)
                                ? contractMaxMap.get(allocCode.Name)
                                : 0;
                            Decimal existing = existingMap.containsKey(allocCode.Name)
                                ? existingMap.get(allocCode.Name)
                                : 0;
                            QDX_LOG.error(
                                'Contract=' + contractId +
                                ', AllocCode=' + allocCode.Name +
                                ', RemainingFunding=' + remainingFunding +
                                ', MaxAmount=' + maxAmount +
                                ', Existing=' + existing
                            );
                            
                            if(maxAmount == null){
                                QDX_LOG.error(
                                    'NULL maxAmount for Contract=' +
                                    contractId +
                                    ', Allocation=' +
                                    allocCode.Name
                                );
                                continue;
                            }
                            
                            if(existing == null){
                                existing = 0;
                            }
                            Decimal allocAmount = Math.min(remainingFunding, maxAmount - existing);
                            if (allocAmount > 0) {
                                allocationsToInsert.add(new Allocation__c(
                                    Allocation_Amount__c = allocAmount,
                                    Allocation_Code__c = allocCode.Id,
                                    Contract__c = contractId,
                                    Payment_Return__c = 'P',
                                    Payee__c = allocCode.Payee__c,
                                    is_Expense__c = allocCode.is_Expense__c,
                                    Descriptor__c = allocCode.Descriptor__c,
                                    Max_Allocation_Amount__c = maxAmount
                                ));
                                remainingFunding -= allocAmount;
                                
                                if (!existingAllocAmountsByContractId.containsKey(contractId))
                                    existingAllocAmountsByContractId.put(contractId, new Map<String, Decimal>());
                                existingAllocAmountsByContractId.get(contractId).put(allocCode.Name, existing + allocAmount);
                                
                                // NEW: Dynamically update Funded_Reserve__c for non-split Reserve codes
                                //------------- Start - 05/03/2026--------------------------------------- 
                                
                                if (allocCode.Descriptor__c == 'Reserve') {
                                    InsurancePolicy updateContract = contractsToUpdateMap.containsKey(contractId)
                                        ? contractsToUpdateMap.get(contractId)
                                        : contractMap.get(contractId);
                                    
                                    Decimal currentFundedReserve = updateContract.Funded_Reserve__c != null ? updateContract.Funded_Reserve__c : 0;
                                    updateContract.Funded_Reserve__c = currentFundedReserve + allocAmount;
                                    
                                    contractsToUpdateMap.put(contractId, updateContract);
                                }
                                
                                //-------------- End - 05/03/2026-----------------------------------------
                                
                            }
                        }
                        
                        // =============================================================
                        // RESERVE SPLIT FUNDING DISTRIBUTION
                        // Handles:
                        // 1. Equal distribution
                        // 2. Capacity overflow redistribution
                        // 3. Odd-cent rounding
                        // =============================================================
                        QDX_LOG.debug(
                            'Contract=' + contractId +
                            ', reserveSplits=' + reserveSplits.size() +
                            ', maxMapExists=' +
                            maxAllocByContractId.containsKey(contractId) +
                            ', existingMapExists=' +
                            existingAllocAmountsByContractId.containsKey(contractId)
                        );
                        
                        if(
                            !reserveSplits.isEmpty() &&
                            remainingFunding > 0
                        ){
                            
                            Map<String, Decimal> contractMaxMap =
                                maxAllocByContractId.containsKey(contractId)
                                ? maxAllocByContractId.get(contractId)
                                : new Map<String, Decimal>();
                            
                            
                            /*
* Make sure the same in-memory lifecycle map is reused.
* This is important when multiple pending Funding records
* for one Contract are processed in the same execution.
*/
                            if(
                                !existingAllocAmountsByContractId
                                .containsKey(contractId)
                            ){
                                existingAllocAmountsByContractId.put(
                                    contractId,
                                    new Map<String, Decimal>()
                                );
                            }
                            
                            Map<String, Decimal> existingMap =
                                existingAllocAmountsByContractId.get(
                                    contractId
                                );
                            
                            
                            /*
* Calculate the complete distribution BEFORE inserting
* Allocation records.
*/
                            Map<Id, Decimal> reserveSplitDistribution =
                                calculateReserveSplitDistribution(
                                    reserveSplits,
                                    remainingFunding,
                                    contractMaxMap,
                                    existingMap
                                );
                            
                            
                            /*
* Create exactly one Allocation per Reserve Split code
* for this Funding record.
*
* Iterate the original reserveSplits list so existing
* priority/order remains deterministic.
*/
                            for(Allocation_Code__c splitCode : reserveSplits){
                                
                                Decimal splitAmount =
                                    reserveSplitDistribution.containsKey(
                                        splitCode.Id
                                    )
                                    ? reserveSplitDistribution.get(
                                        splitCode.Id
                                    )
                                    : 0;
                                
                                splitAmount =
                                    roundCurrency(splitAmount);
                                
                                
                                if(splitAmount <= 0){
                                    continue;
                                }
                                
                                
                                Decimal maxAmount =
                                    contractMaxMap.containsKey(splitCode.Name) &&
                                    contractMaxMap.get(splitCode.Name) != null
                                    ? contractMaxMap.get(splitCode.Name)
                                    : 0;
                                
                                
                                Decimal alreadyAllocated =
                                    existingMap.containsKey(splitCode.Name) &&
                                    existingMap.get(splitCode.Name) != null
                                    ? existingMap.get(splitCode.Name)
                                    : 0;
                                
                                
                                // -----------------------------------------------------
                                // Create Reserve Split Allocation
                                // -----------------------------------------------------
                                allocationsToInsert.add(
                                    new Allocation__c(
                                        Allocation_Amount__c =
                                        splitAmount,
                                        
                                        Allocation_Code__c =
                                        splitCode.Id,
                                        
                                        Contract__c =
                                        contractId,
                                        
                                        Payment_Return__c =
                                        'P',
                                        
                                        Payee__c =
                                        splitCode.Payee__c,
                                        
                                        is_Expense__c =
                                        splitCode.is_Expense__c,
                                        
                                        Descriptor__c =
                                        splitCode.Descriptor__c,
                                        
                                        Max_Allocation_Amount__c =
                                        maxAmount
                                    )
                                );
                                
                                
                                // -----------------------------------------------------
                                // Reduce current Funding
                                // -----------------------------------------------------
                                remainingFunding =
                                    roundCurrency(
                                        remainingFunding -
                                        splitAmount
                                    );
                                
                                
                                // -----------------------------------------------------
                                // Keep lifecycle balance synchronized
                                // -----------------------------------------------------
                                existingMap.put(
                                    splitCode.Name,
                                    roundCurrency(
                                        alreadyAllocated +
                                        splitAmount
                                    )
                                );
                                
                                
                                // -----------------------------------------------------
                                // Preserve existing Funded_Reserve__c behavior
                                // -----------------------------------------------------
                                if(splitCode.Descriptor__c == 'Reserve'){
                                    
                                    InsurancePolicy updateContract =
                                        contractsToUpdateMap.containsKey(
                                            contractId
                                        )
                                        ? contractsToUpdateMap.get(
                                            contractId
                                        )
                                        : contractMap.get(
                                            contractId
                                        );
                                    
                                    
                                    if(updateContract == null){
                                        
                                        QDX_LOG.error(
                                            'Contract not found in contract maps.' +
                                            ' ContractId=' +
                                            contractId
                                        );
                                        
                                    }else{
                                        
                                        Decimal currentFundedReserve =
                                            updateContract.Funded_Reserve__c != null
                                            ? updateContract.Funded_Reserve__c
                                            : 0;
                                        
                                        
                                        updateContract.Funded_Reserve__c =
                                            roundCurrency(
                                                currentFundedReserve +
                                                splitAmount
                                            );
                                        
                                        
                                        contractsToUpdateMap.put(
                                            contractId,
                                            updateContract
                                        );
                                    }
                                }
                                
                                
                                if(remainingFunding <= 0){
                                    break;
                                }
                            }
                        }
                        
                        // After all allocations & calculations succeed
                        if (allocationsToInsert.size() > 0 || funding.Funded_Amount__c != 0) {
                            funding.Time_Processed__c = System.now();
                            fundingRecordsToUpdate.add(funding);
                            
                            InsurancePolicy updateContract = contractsToUpdateMap.containsKey(contractId)
                                ? contractsToUpdateMap.get(contractId)
                                : currentContract;
                            
                            if(updateContract == null){
                                QDX_LOG.error(
                                    'Null updateContract before funding update. ContractId=' +
                                    contractId
                                );
                                continue;
                            }
                            
                            updateContract.DLRS_Total_Funded_Amount_from_Funding__c =
                                (updateContract.DLRS_Total_Funded_Amount_from_Funding__c == null ? 0 :
                                 updateContract.DLRS_Total_Funded_Amount_from_Funding__c)
                                + funding.Funded_Amount__c;
                            
                            contractsToUpdateMap.put(contractId, updateContract);
                        }
                        
                    }
                }catch (Exception rop) {
                    QDX_LOG.error(
                        'Funding record failed: ' +
                        funding.Id +
                        ' → ' +
                        rop.getMessage() +
                        ' Line=' +
                        rop.getLineNumber()
                    );
                }
            }
            
            // --- 7. Perform bulk DML
if (!fundingRecordsToUpdate.isEmpty()){
    Database.update(
        fundingRecordsToUpdate,
        false
    );
}

if (!allocationsToInsert.isEmpty()){
    Database.insert(
        allocationsToInsert,
        false
    );
}

/*
 * Preserve existing generic contract allocation field updates.
 */
updateContractAllocationFields(
    contractsToUpdateMap
);

/*
 * Reserve Pack must reconcile to the actual Allocation ledger.
 *
 * This is intentionally called AFTER
 * updateContractAllocationFields() so the generic metadata logic
 * cannot overwrite the correctly reconciled Reserve Pack value.
 */
reconcileFundedReservePack(
    contractsToUpdateMap
);

if (!contractsToUpdateMap.isEmpty()){
    Database.update(
        contractsToUpdateMap.values(),
        false
    );
}
            
        } catch (Exception e) {
            QDX_LOG.error('Error in processFundingRecords - ' + e.getMessage() +
                          ', Line: ' + e.getLineNumber());
        } finally {
            QDX_LOG.publish();
        }
    }
    
    /**
* @description
* Processes the first positive Funding__c record created after a contract
* reinstatement.
*
* When a contract is cancelled, ROP processing creates Payment_Return__c = 'R'
* Allocation__c records representing amounts returned from the original
* funding buckets. After reinstatement, the first positive Funding__c must
* restore those buckets by creating Payment_Return__c = 'P' allocations that
* exactly mirror the applicable ROP allocations with opposite signs.
*
* Example:
* - ROP Admin Fee allocation of -220.89 creates recovery allocation +220.89.
* - ROP Reserve allocation of +112.05 creates recovery allocation -112.05.
*
* The net total of all generated recovery allocations must exactly equal the
* first Funding__c.Funded_Amount__c received after reinstatement.
*
* This method intentionally:
* - Performs no SOQL.
* - Performs no DML.
* - Adds validated records to the caller's bulk insert collection.
* - Leaves negative funding unchanged for the existing negative-funding logic.
* - Runs only for the first positive funding after reinstatement.
* - Performs no proportional distribution, Reserve balancing, or normal
*   allocation-priority processing.
*
* @param funding
* The pending Funding__c record currently being processed.
*
* @param contractRecord
* The related InsurancePolicy containing reinstatement information.
*
* @param contractFundingHistory
* All positive and negative Funding__c records for the contract, ordered by
* CreatedDate. Used to identify the previous funding boundary and determine
* whether the current funding is the first positive funding after reinstatement.
*
* @param contractROPAllocations
* Candidate Payment_Return__c = 'R' Allocation__c records for the contract.
* The method applies the recovery date window before using these records.
*
* @param contractAllAllocations
* All Allocation__c records for the contract. Used only as a fallback when a
* reliable processed Funding__c record before reinstatement cannot be found.
*
* @param contractAllocationCodesByPriority
* Allocation Code configuration for the contract, keyed by priority. Used to
* resolve the applicable Allocation_Code__c when the ROP allocation does not
* retain its Allocation_Code__c lookup.
*
* @param contractMaxAllocationByCodeName
* Maximum configured allocation amount keyed by Allocation Code name. Used as
* a fallback when the source ROP allocation has no Max_Allocation_Amount__c.
*
* @param allocationsToInsert
* Shared bulk DML collection to which validated recovery Allocation__c records
* are added.
*
* @param existingAllocAmountsByContractId
* Current lifecycle allocation balances keyed by Contract and Allocation Code
* name. Updated in memory after recovery so later funding continues from the
* restored balances.
*
* @param recoveredContracts
* Transaction-scoped Contract Id set used to prevent duplicate reinstatement
* recovery when multiple pending Funding__c records for the same contract are
* processed in one batch execution.
*
* @return
* Returns 0 when reinstatement recovery fully consumes the current funding.
* Otherwise returns the original funding amount so the caller can continue
* through the existing standard or negative funding paths.
*/
    @TestVisible
    private static Decimal processReinstatementRecovery(
        Funding__c funding,
        InsurancePolicy contractRecord,
        List<Funding__c> contractFundingHistory,
        List<Allocation__c> contractROPAllocations,
        List<Allocation__c> contractAllAllocations,
        Map<Integer, Allocation_Code__c> contractAllocationCodesByPriority,
        Map<String, Decimal> contractMaxAllocationByCodeName,
        List<Allocation__c> allocationsToInsert,
        Map<Id, Map<String, Decimal>> existingAllocAmountsByContractId,
        Set<Id> recoveredContracts
    ) {
        // Validate the current Funding record before accessing its amount.
        if (funding == null || funding.Funded_Amount__c == null) {
            return 0;
        }
        
        Decimal originalFundingAmount =
            roundCurrency(funding.Funded_Amount__c);
        
        /*
* Reinstatement recovery applies only to positive Funding.
*
* Returning the original negative amount preserves the existing
* negative-funding processing path in processFundingRecords().
*/
        if (originalFundingAmount <= 0) {
            return originalFundingAmount;
        }
        
        /*
* Confirm that:
* - The contract exists.
* - A reinstatement date is present.
* - The current Funding was created on or after reinstatement.
*
* Funding outside this scope must continue through normal allocation.
*/
        if (
            contractRecord == null ||
            contractRecord.Id == null ||
            contractRecord.Reinstatement_Date__c == null ||
            funding.CreatedDate == null ||
            funding.CreatedDate < contractRecord.Reinstatement_Date__c
        ) {
            return originalFundingAmount;
        }
        
        /*
* Prevent the same contract from receiving reinstatement recovery more
* than once during the current batch transaction.
*/
        if (
            recoveredContracts != null &&
            recoveredContracts.contains(contractRecord.Id)
        ) {
            return originalFundingAmount;
        }
        
        // Recovery cannot be performed without source ROP allocation records.
        if (
            contractROPAllocations == null ||
            contractROPAllocations.isEmpty()
        ) {
            return originalFundingAmount;
        }
        
        Boolean hasEarlierPositiveFundingAfterReinstatement = false;
        Datetime previousFundingDate;
        
        /*
* Determine:
*
* 1. Whether the current Funding is the first positive Funding created
*    after reinstatement.
*
* 2. The latest processed positive Funding before reinstatement. This
*    timestamp defines the beginning of the applicable ROP recovery window.
*/
        if (contractFundingHistory != null) {
            for (Funding__c historicalFunding : contractFundingHistory) {
                if (
                    historicalFunding == null ||
                    historicalFunding.Id == funding.Id ||
                    historicalFunding.CreatedDate == null
                ) {
                    continue;
                }
                
                Decimal historicalAmount =
                    historicalFunding.Funded_Amount__c == null
                    ? 0
                    : historicalFunding.Funded_Amount__c;
                
                // Negative and zero-value funding do not define recovery eligibility.
                if (historicalAmount <= 0) {
                    continue;
                }
                
                /*
* Track the most recent processed positive Funding before
* reinstatement.
*/
                if (
                    historicalFunding.Time_Processed__c != null &&
                    historicalFunding.CreatedDate <
                    contractRecord.Reinstatement_Date__c
                ) {
                    if (
                        previousFundingDate == null ||
                        historicalFunding.CreatedDate > previousFundingDate
                    ) {
                        previousFundingDate =
                            historicalFunding.CreatedDate;
                    }
                }
                
                /*
* Any earlier positive Funding after reinstatement means the
* current record is not eligible for ROP mirror recovery.
*/
                if (
                    historicalFunding.CreatedDate >=
                    contractRecord.Reinstatement_Date__c &&
                    historicalFunding.CreatedDate < funding.CreatedDate
                ) {
                    hasEarlierPositiveFundingAfterReinstatement = true;
                }
            }
        }
        
        // Only the first positive Funding after reinstatement mirrors the ROP.
        if (hasEarlierPositiveFundingAfterReinstatement) {
            return originalFundingAmount;
        }
        
        /*
* Historical Funding data may be incomplete for older contracts.
*
* As a controlled fallback, use the latest positive paid allocation before
* reinstatement as the beginning of the recovery window.
*/
        if (previousFundingDate == null) {
            previousFundingDate =
                findLatestPaidAllocationDateBeforeReinstatement(
                    contractAllAllocations,
                    contractRecord.Reinstatement_Date__c
                );
        }
        
        // A reliable recovery window is required before selecting ROP allocations.
        if (previousFundingDate == null) {
            return originalFundingAmount;
        }
        
        List<Allocation__c> recoverySourceAllocations =
            new List<Allocation__c>();
        
        Decimal expectedRecoveryFundingAmount = 0;
        
        /*
* Select all eligible ROP allocations created:
*
* - After the latest positive Funding before reinstatement.
* - Before the contract reinstatement date.
*
* Both positive and negative ROP allocations are included because the
* recovery must reverse the sign of every source allocation.
*/
        for (Allocation__c rAlloc : contractROPAllocations) {
            if (!isPotentialReinstatementSourceAllocation(rAlloc)) {
                continue;
            }
            
            if (
                rAlloc.Contract__c != contractRecord.Id ||
                rAlloc.CreatedDate == null
            ) {
                continue;
            }
            
            if (
                rAlloc.CreatedDate <= previousFundingDate ||
                rAlloc.CreatedDate >= contractRecord.Reinstatement_Date__c
            ) {
                continue;
            }
            
            /*
* Reinstatement recovery always mirrors the source allocation with the
* opposite sign.
*/
            Decimal mirrorAmount =
                roundCurrency(rAlloc.Allocation_Amount__c * -1);
            
            if (mirrorAmount == 0) {
                continue;
            }
            
            recoverySourceAllocations.add(rAlloc);
            
            expectedRecoveryFundingAmount =
                roundCurrency(
                    expectedRecoveryFundingAmount + mirrorAmount
                );
        }
        
        if (recoverySourceAllocations.isEmpty()) {
            return originalFundingAmount;
        }
        
        /*
* Business validation:
*
* The client confirmed that the first positive Funding after reinstatement
* will always exactly equal the net signed total of the applicable ROP
* allocations.
*
* Do not perform a partial recovery or send an unmatched amount through
* the recovery path.
*/
        Decimal fundingDifference =
            roundCurrency(
                originalFundingAmount - expectedRecoveryFundingAmount
            );
        
        if (fundingDifference != 0) {
            QDX_LOG.error(
                'Reinstatement recovery skipped because Funding does not exactly ' +
                'match the signed ROP allocation total.' +
                ' ContractId=' + contractRecord.Id +
                ', FundingId=' + funding.Id +
                ', FundingAmount=' + originalFundingAmount +
                ', ROPMirrorTotal=' + expectedRecoveryFundingAmount +
                ', Difference=' + fundingDifference
            );
            
            return originalFundingAmount;
        }
        
        /*
* Build the complete recovery set locally before modifying the shared
* insert collection.
*
* This provides an all-or-nothing planning step. If an Allocation Code
* cannot be resolved, no incomplete recovery allocation set is submitted.
*/
        List<Allocation__c> plannedRecoveryAllocations =
            new List<Allocation__c>();
        
        /*
* Maintains positional alignment with plannedRecoveryAllocations so the
* in-memory lifecycle balance can be updated by Allocation Code name.
*/
        List<String> plannedAllocationCodeNames =
            new List<String>();
        
        Decimal plannedRecoveryTotal = 0;
        
        /*
* Tracks the signed Reserve amount generated by the reinstatement recovery.
*
* Funded_Reserve__c is maintained explicitly by the funding allocation
* process and is excluded from updateContractAllocationFields(). Therefore,
* any Reserve allocation created by this recovery method must also be applied
* directly to Funded_Reserve__c.
*
* Examples:
* - Recovery Reserve +100.00 increases Funded_Reserve__c by 100.00.
* - Recovery Reserve -162.05 decreases Funded_Reserve__c by 162.05.
*/
        Decimal reserveRecoveryAdjustment = 0;
        
        for (Allocation__c rAlloc : recoverySourceAllocations) {
            
            /*
* Admin Cancel Fee is a special standalone allocation.
*
* It intentionally has no Allocation_Code__c and therefore
* must not go through normal Allocation Code resolution.
*/
            Boolean isAdminCancelFee =
                normalizeRecoveryValue(rAlloc.Descriptor__c)
                ==
                normalizeRecoveryValue(
                    ADMIN_CANCEL_FEE_DESCRIPTOR
                );
            
            
            // =========================================================
            // Resolve Allocation Code for normal ROP allocation rows
            // =========================================================
            
            Allocation_Code__c targetAllocationCode;
            
            if (!isAdminCancelFee) {
                
                targetAllocationCode =
                    resolveRecoveryAllocationCode(
                        rAlloc,
                        contractAllocationCodesByPriority
                    );
                
                if (
                    targetAllocationCode == null &&
                    rAlloc.Allocation_Code__c == null
                ) {
                    
                    QDX_LOG.error(
                        'Unable to resolve Allocation Code for reinstatement recovery.' +
                        ' ContractId=' + contractRecord.Id +
                        ', SourceAllocationId=' + rAlloc.Id +
                        ', Descriptor=' + rAlloc.Descriptor__c
                    );
                    
                    return originalFundingAmount;
                }
            }
            
            
            // =========================================================
            // Resolve Allocation Code Id / Name
            // =========================================================
            
            Id allocationCodeId;
            String allocationCodeName;
            
            if (isAdminCancelFee) {
                
                /*
* Admin Cancel Fee intentionally has no Allocation Code.
*/
                allocationCodeId = null;
                allocationCodeName = null;
                
            } else {
                
                allocationCodeId =
                    rAlloc.Allocation_Code__c != null
                    ? rAlloc.Allocation_Code__c
                    : targetAllocationCode.Id;
                
                
                if (
                    targetAllocationCode != null &&
                    !String.isBlank(targetAllocationCode.Name)
                ) {
                    
                    allocationCodeName =
                        targetAllocationCode.Name;
                    
                } else if (rAlloc.Allocation_Code__r != null) {
                    
                    allocationCodeName =
                        rAlloc.Allocation_Code__r.Name;
                }
                
                
                /*
* Normal funding allocations require an Allocation Code
* Name so the lifecycle balance can be maintained.
*
* Admin Cancel Fee is intentionally exempt.
*/
                if (String.isBlank(allocationCodeName)) {
                    
                    QDX_LOG.error(
                        'Unable to determine Allocation Code Name for ' +
                        'reinstatement recovery.' +
                        ' ContractId=' + contractRecord.Id +
                        ', SourceAllocationId=' + rAlloc.Id
                    );
                    
                    return originalFundingAmount;
                }
            }
            
            
            // =========================================================
            // Exact signed reverse mirror
            // =========================================================
            
            Decimal recoveryAmount =
                roundCurrency(
                    rAlloc.Allocation_Amount__c * -1
                );
            
            if (recoveryAmount == 0) {
                continue;
            }
            
            
            // =========================================================
            // Descriptor
            // =========================================================
            
            String descriptorValue =
                !String.isBlank(rAlloc.Descriptor__c)
                ? rAlloc.Descriptor__c
                : (
                    targetAllocationCode != null
                    ? targetAllocationCode.Descriptor__c
                    : null
                );
                    
                    
                    // =========================================================
                    // Max Allocation Amount
                    // =========================================================
                    
                    Decimal maxAllocationAmount;
            
            if (isAdminCancelFee) {
                
                /*
* Exact reverse mirror:
*
* ROP:
* Allocation Amount     +50
* Max Allocation Amount +50
*
* Funding:
* Allocation Amount     -50
* Max Allocation Amount -50
*/
                maxAllocationAmount =
                    rAlloc.Max_Allocation_Amount__c != null
                    ? roundCurrency(
                        rAlloc.Max_Allocation_Amount__c * -1
                    )
                    : recoveryAmount;
                
            } else {
                
                /*
* Preserve existing behaviour for every other
* Allocation type.
*/
                maxAllocationAmount =
                    rAlloc.Max_Allocation_Amount__c;
                
                if (
                    maxAllocationAmount == null &&
                    contractMaxAllocationByCodeName != null &&
                    !String.isBlank(allocationCodeName) &&
                    contractMaxAllocationByCodeName.containsKey(
                        allocationCodeName
                    )
                ) {
                    
                    maxAllocationAmount =
                        contractMaxAllocationByCodeName.get(
                            allocationCodeName
                        );
                }
            }
            
            
            // =========================================================
            // Reserve impact
            // =========================================================
            
            if (
                normalizeRecoveryValue(descriptorValue)
                ==
                'reserve'
            ) {
                
                /*
* Do not recalculate Reserve here.
*
* The ROP allocation already contains the correctly
* balanced Reserve amount after removing Cancel Fee.
*
* Example:
*
* ROP Reserve     -585.60
* Funding mirror  +585.60
*/
                reserveRecoveryAdjustment =
                    roundCurrency(
                        reserveRecoveryAdjustment +
                        recoveryAmount
                    );
            }
            
            
            // =========================================================
            // Payee
            // =========================================================
            
            String payeeValue;
            
            if (rAlloc.Payee__c != null) {
                
                payeeValue =
                    rAlloc.Payee__c;
                
            } else if (isAdminCancelFee) {
                
                payeeValue =
                    ADMIN_CANCEL_FEE_PAYEE;
                
            } else {
                
                payeeValue =
                    targetAllocationCode != null
                    ? targetAllocationCode.Payee__c
                    : null;
            }
            
            
            // =========================================================
            // Expense
            // =========================================================
            
            Boolean isExpenseValue;
            
            if (isAdminCancelFee) {
                
                /*
* Admin Cancel Fee is confirmed as non-expense.
*/
                isExpenseValue = false;
                
            } else {
                
                isExpenseValue =
                    rAlloc.is_Expense__c != null
                    ? rAlloc.is_Expense__c
                    : (
                        targetAllocationCode != null
                        ? targetAllocationCode.is_Expense__c
                        : false
                    );
                        }
            
            
            // =========================================================
            // Create Funding mirror Allocation
            // =========================================================
            
            plannedRecoveryAllocations.add(
                new Allocation__c(
                    
                    Contract__c =
                    contractRecord.Id,
                    
                    /*
* NULL for Admin Cancel Fee.
* Existing value for normal allocations.
*/
                    Allocation_Code__c =
                    allocationCodeId,
                    
                    Allocation_Amount__c =
                    recoveryAmount,
                    
                    Descriptor__c =
                    descriptorValue,
                    
                    Payee__c =
                    payeeValue,
                    
                    is_Expense__c =
                    isExpenseValue,
                    
                    Payment_Return__c =
                    'P',
                    
                    Max_Allocation_Amount__c =
                    maxAllocationAmount,
                    
                    Fee_Label_for_Summary_Reporting__c =
                    rAlloc.Fee_Label_for_Summary_Reporting__c
                )
            );
            
            
            /*
* Keep positional alignment with
* plannedRecoveryAllocations.
*
* Admin Cancel Fee will intentionally contain NULL here.
*/
            plannedAllocationCodeNames.add(
                allocationCodeName
            );
            
            
            plannedRecoveryTotal =
                roundCurrency(
                    plannedRecoveryTotal +
                    recoveryAmount
                );
        }
        
        if (plannedRecoveryAllocations.isEmpty()) {
            return originalFundingAmount;
        }
        
        /*
* Final defensive validation:
*
* The net value of the planned recovery allocations must exactly equal the
* current Funding amount. No proportional calculation, Reserve adjustment,
* or balancing entry is permitted.
*/
        if (
            roundCurrency(
                originalFundingAmount - plannedRecoveryTotal
            ) != 0
        ) {
            QDX_LOG.error(
                'Reinstatement recovery validation failed.' +
                ' ContractId=' + contractRecord.Id +
                ', FundingId=' + funding.Id +
                ', FundingAmount=' + originalFundingAmount +
                ', PlannedRecoveryTotal=' + plannedRecoveryTotal
            );
            
            return originalFundingAmount;
        }
        
        /*
* Synchronize the contract-level Net Funded Reserve with the signed Reserve
* allocation created by reinstatement recovery.
*
* This update is intentionally performed only after the complete recovery
* plan has passed validation. The caller later adds this same InsurancePolicy
* instance to contractsToUpdateMap and persists it through the existing bulk
* contract update.
*
* Example:
* Current Funded Reserve:       249.91
* Recovery Reserve adjustment: -162.05
* Resulting Funded Reserve:      87.86
*/
        if (reserveRecoveryAdjustment != 0) {
            Decimal currentFundedReserve =
                contractRecord.Funded_Reserve__c == null
                ? 0
                : contractRecord.Funded_Reserve__c;
            
            contractRecord.Funded_Reserve__c =
                roundCurrency(
                    currentFundedReserve + reserveRecoveryAdjustment
                );
        }
        /*
* The recovery plan has passed all validation. Add the complete set to the
* caller's bulk insert collection.
*/
        allocationsToInsert.addAll(plannedRecoveryAllocations);
        
        /*
* Update the transaction-level lifecycle balances.
*
* This ensures that any later Funding processed for the contract continues
* from the restored bucket balances rather than restarting the allocation
* priority sequence.
*/
        if (!existingAllocAmountsByContractId.containsKey(contractRecord.Id)) {
            existingAllocAmountsByContractId.put(
                contractRecord.Id,
                new Map<String, Decimal>()
            );
        }
        
        Map<String, Decimal> existingMap =
            existingAllocAmountsByContractId.get(contractRecord.Id);
        
        for (
            Integer recoveryIndex = 0;
            recoveryIndex < plannedRecoveryAllocations.size();
            recoveryIndex++
        ) {
            
            String allocationCodeName =
                plannedAllocationCodeNames[recoveryIndex];
            
            
            /*
* Admin Cancel Fee is not an Allocation Code based
* funding bucket.
*
* Therefore it must not be added to the normal
* Allocation Code lifecycle balance map.
*/
            if (String.isBlank(allocationCodeName)) {
                continue;
            }
            
            
            Decimal recoveryAmount =
                plannedRecoveryAllocations[recoveryIndex]
                .Allocation_Amount__c;
            
            
            Decimal currentAllocatedAmount =
                existingMap.containsKey(allocationCodeName)
                ? existingMap.get(allocationCodeName)
                : 0;
            
            
            existingMap.put(
                allocationCodeName,
                roundCurrency(
                    currentAllocatedAmount +
                    recoveryAmount
                )
            );
        }
        
        /*
* Mark the contract as recovered for the current batch execution so another
* pending Funding record cannot repeat the ROP mirror operation.
*/
        if (recoveredContracts != null) {
            recoveredContracts.add(contractRecord.Id);
        }
        
        QDX_LOG.debug(
            'Exact reinstatement recovery completed.' +
            ' ContractId=' + contractRecord.Id +
            ', FundingId=' + funding.Id +
            ', FundingAmount=' + originalFundingAmount +
            ', ROPMirrorTotal=' + expectedRecoveryFundingAmount +
            ', ReserveRecoveryAdjustment=' + reserveRecoveryAdjustment +
            ', ResultingFundedReserve=' + contractRecord.Funded_Reserve__c +
            ', RecoveryAllocationCount=' +
            plannedRecoveryAllocations.size()
        );
        
        /*
* The full Funding amount has been represented by the recovery allocation
* set. Return zero so the current Funding does not enter normal positive
* funding allocation.
*/
        return 0;
    }
    
    /**
* @description
* Identifies allocation rows that are potential ROP return allocations.
*
* ROP return allocations in the current Marathon data model appear as:
* - Payment_Return__c = 'R'
* - Allocation_Amount__c < 0
*
* This intentionally excludes Negative Funding Reserve ledger rows because
* those rows use Payment_Return__c = 'R' but store a positive running Reserve
* balance.
*/
    @TestVisible
    private static Boolean isPotentialRopReturnAllocation(
        Allocation__c allocationRecord
    ) {
        return allocationRecord != null
            && allocationRecord.Payment_Return__c == 'R'
            && allocationRecord.Allocation_Amount__c != null
            && allocationRecord.Allocation_Amount__c < 0;
    }
    
    /**
* @description
* Identifies ROP allocation rows that may be used as the source of a
* reinstatement recovery.
*
* Unlike isPotentialRopReturnAllocation(), this method intentionally includes:
* - Negative ROP allocations, which must become positive during recovery.
* - Positive ROP allocations, such as a positive Reserve allocation, which
*   must become negative during recovery.
*
* The reinstatement method applies additional date-window and funding-total
* validation before using these records.
*/
    @TestVisible
    private static Boolean isPotentialReinstatementSourceAllocation(
        Allocation__c allocationRecord
    ) {
        return allocationRecord != null
            && allocationRecord.Payment_Return__c == 'R'
            && allocationRecord.Allocation_Amount__c != null
            && allocationRecord.Allocation_Amount__c != 0;
    }
    
    /**
* @description
* Finds the latest positive paid allocation before reinstatement.
*
* This is used as a fallback when a reliable previous Funding__c record cannot
* be identified. It allows reinstatement recovery to still work for contracts
* where historical funding records are incomplete but original positive
* allocations exist.
*/
    @TestVisible
    private static Datetime findLatestPaidAllocationDateBeforeReinstatement(
        List<Allocation__c> contractAllAllocations,
        Datetime reinstatementDate
    ) {
        if (
            contractAllAllocations == null ||
            contractAllAllocations.isEmpty() ||
            reinstatementDate == null
        ) {
            return null;
        }
        
        Datetime latestPaidAllocationDate;
        
        for (Allocation__c allocationRecord : contractAllAllocations) {
            
            if (
                allocationRecord == null ||
                allocationRecord.CreatedDate == null ||
                allocationRecord.Payment_Return__c != 'P' ||
                allocationRecord.Allocation_Amount__c == null ||
                allocationRecord.Allocation_Amount__c <= 0
            ) {
                continue;
            }
            
            if (allocationRecord.CreatedDate < reinstatementDate) {
                if (
                    latestPaidAllocationDate == null ||
                    allocationRecord.CreatedDate > latestPaidAllocationDate
                ) {
                    latestPaidAllocationDate = allocationRecord.CreatedDate;
                }
            }
        }
        
        return latestPaidAllocationDate;
    }
    
    /**
* @description
* Resolves the Allocation Code that should be used for a reinstatement recovery
* allocation.
*
* ROP allocation rows may not always retain Allocation_Code__c. When that
* happens, this method attempts to resolve the correct allocation code using
* Descriptor__c and Payee__c from the ROP allocation row.
*/
    @TestVisible
    private static Allocation_Code__c resolveRecoveryAllocationCode(
        Allocation__c recoveryAllocation,
        Map<Integer, Allocation_Code__c> allocationCodesByPriority
    ) {
        if (
            recoveryAllocation == null ||
            allocationCodesByPriority == null ||
            allocationCodesByPriority.isEmpty()
        ) {
            return null;
        }
        
        List<Integer> sortedPriorities =
            new List<Integer>(allocationCodesByPriority.keySet());
        
        sortedPriorities.sort();
        
        if (recoveryAllocation.Allocation_Code__c != null) {
            
            for (Integer priority : sortedPriorities) {
                
                Allocation_Code__c allocationCode =
                    allocationCodesByPriority.get(priority);
                
                if (
                    allocationCode != null &&
                    allocationCode.Id == recoveryAllocation.Allocation_Code__c
                ) {
                    return allocationCode;
                }
            }
        }
        
        String recoveryDescriptor =
            normalizeRecoveryValue(recoveryAllocation.Descriptor__c);
        
        String recoveryPayee =
            recoveryAllocation.Payee__c == null
            ? ''
            : normalizeRecoveryValue(String.valueOf(recoveryAllocation.Payee__c));
        
        if (String.isBlank(recoveryDescriptor)) {
            return null;
        }
        
        /*
* First attempt: match by Descriptor + Payee.
*/
        for (Integer priority : sortedPriorities) {
            
            Allocation_Code__c allocationCode =
                allocationCodesByPriority.get(priority);
            
            if (allocationCode == null) {
                continue;
            }
            
            String codeDescriptor =
                normalizeRecoveryValue(allocationCode.Descriptor__c);
            
            String codePayee =
                allocationCode.Payee__c == null
                ? ''
                : normalizeRecoveryValue(String.valueOf(allocationCode.Payee__c));
            
            if (
                codeDescriptor == recoveryDescriptor &&
                (
                    String.isBlank(recoveryPayee) ||
                    recoveryPayee == codePayee
                )
            ) {
                return allocationCode;
            }
        }
        
        /*
* Second attempt: match by Descriptor only.
*/
        for (Integer priority : sortedPriorities) {
            
            Allocation_Code__c allocationCode =
                allocationCodesByPriority.get(priority);
            
            if (allocationCode == null) {
                continue;
            }
            
            if (
                normalizeRecoveryValue(allocationCode.Descriptor__c)
                ==
                recoveryDescriptor
            ) {
                return allocationCode;
            }
        }
        
        return null;
    }
    
    /**
* @description
* Normalizes string values used for matching ROP allocation rows back to
* Allocation Code records.
*/
    @TestVisible
    private static String normalizeRecoveryValue(String value) {
        return String.isBlank(value)
            ? ''
            : value.trim().toLowerCase();
    }
    
    /* Updates contract allocation fields based on allocation descriptors using metadata mappings.
*
* The function:
* 1. Fetches metadata mappings that link allocation descriptors to contract fields.
* 2. Retrieves existing contract allocations grouped by descriptor.
* 3. Updates contract fields dynamically using metadata-based mappings.
* 4. Adds modified contracts to the `contractsToUpdate` list for bulk update.
*
* @param contractsToUpdate List of InsurancePolicy objects that need updates.
*/
    public static void updateContractAllocationFields(
        Map<Id,InsurancePolicy> contractsToUpdateMap
    ) {
        try {
            
            // Fetch metadata mappings (links between allocation descriptors & contract fields)
            List<ContractFundingAllocationFieldMapping__mdt> mappings =
                getFundingFieldMappings(true);
            if (mappings.isEmpty()) {
                QDX_LOG.debug('No mappings found in ContractFundingAllocationFieldMapping__mdt');
                return;
            }
            
            //Get Contract Reinstatement Dates
            Map<Id, Datetime> contractReinstateDateMap = new Map<Id, Datetime>();
            for (InsurancePolicy contract : contractsToUpdateMap.values()) {
                if(contract.Reinstatement_Date__c!=null){
                    contractReinstateDateMap.put(contract.Id, contract.Reinstatement_Date__c);
                }
                for (ContractFundingAllocationFieldMapping__mdt mapping : mappings) {
                    if (contract.get(mapping.Contract_Field_API__c) == null)
                        contract.put(mapping.Contract_Field_API__c,0);
                }
            }
            
            // Query to fetch contract allocations grouped by contract and descriptor
            List<Allocation__c> allocationResults = [
                SELECT Allocation_Code__r.Name, Allocation_Amount__c, Descriptor__c, Allocation_Code__r.Priority__c,
                Allocation_Code__c, Contract__c, CreatedDate, Max_Allocation_Amount__c
                FROM Allocation__c
                WHERE Contract__c IN :contractsToUpdateMap.keySet() 
                AND Allocation_Code__r.Descriptor__c != 'Reserve' 
                and Payment_Return__c  ='P'
            ];
            
            // Process allocation results and update contract fields dynamically
            for (Allocation__c alloc : allocationResults) {
                //Datetime reinstateDate = contractReinstateDateMap.containsKey(alloc.Contract__c)?contractReinstateDateMap.get(alloc.Contract__c):null;
                //if (reinstateDate == null || reinstateDate <= alloc.CreatedDate) {
                // Find the contract to update
                InsurancePolicy contract = contractsToUpdateMap.containsKey(alloc.Contract__c)?contractsToUpdateMap.get(alloc.Contract__c):null;
                
                if(contract!= null) {
                    // Match the allocation descriptor to a contract field via metadata
                    for (ContractFundingAllocationFieldMapping__mdt mapping : mappings) {
                        if (mapping.Descriptor__c == alloc.Descriptor__c) {  
                            String fieldName = mapping.Contract_Field_API__c;
                            if (fieldName!=null && fieldName!='') {
                                try {
                                    Decimal currentValue = (Decimal)(contract.get(fieldName) != null ? contract.get(fieldName) : 0);
                                    if(alloc.Max_Allocation_Amount__c >= (currentValue + alloc.Allocation_Amount__c) ) {
                                        contract.put(fieldName, currentValue + alloc.Allocation_Amount__c);
                                    } else {
                                        // START: PREVIOUS CODE
                                        // contract.put(fieldName, currentValue + alloc.Max_Allocation_Amount__c); 
                                        // END: PREVIOUS CODE  
                                        
                                        // START: Added On 4/3/26 By SOHEL AZMI 
                                        if(contract.Contract_Term_Months__c != 1)
                                            contract.put(fieldName, alloc.Max_Allocation_Amount__c);  
                                        else if(contract.Contract_Term_Months__c == 1)
                                            contract.put(fieldName, currentValue + alloc.Allocation_Amount__c);
                                        // END: Added On 4/3/26 By SOHEL AZMI
                                    }
                                } catch (Exception e) {
                                    QDX_LOG.debug('Error setting field: ' + fieldName + ' - ' + e.getMessage());
                                }
                            }
                            break; // Stop after first match
                        }
                    }
                    
                    if (!contractsToUpdateMap.containsKey(contract.Id)) {
                        contractsToUpdateMap.put(contract.Id,contract);
                    }
                }
                //}
            }
            /*
Entire method disabled as per new requirement:
Contract Allocation fields should be populated ONLY once
during Contract Ingestion using Allocation_Code__c amounts.
*/
        } catch (Exception e) {
            // Log error details
            QDX_LOG.error('Error in updateContractAllocationFields - Message: ' + e.getMessage() +
                          ', Line Number: ' + e.getLineNumber());
        } finally {
            // Ensure logs are always published
            QDX_LOG.publish();
        }
    }
    
    // Inner class to define the properties of Contract Allocation.
    public class ContractAllocation implements Comparable{
        public String allocationCode;
        public String FeeLabel;
        public Decimal allocationAmount;
        public Integer priority;
        public String financeCode;
        public String contractId;
        public Integer compareTo(Object otherObject) {
            // For additional type safety, check if otherObject is a SortableAccount
            // if not, throw a SortException
            if (!(otherObject instanceof ContractAllocation)) {
                return 0;
            }
            // Cast otherObject to SortableAccount and compare it
            ContractAllocation other = (ContractAllocation) otherObject;
            if (this.priority < other.priority) {
                return -1;
            }
            if (this.priority > other.priority) {
                return 1;
            }
            return 0;
        }
    }
}