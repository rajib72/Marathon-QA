/**
* @author Saurabh Rawat
* @dateModified 2026-07-16
* @ModifiedBy Raj Sekhar Mukherjee
* @description Trigger Handler on ROP
*/

// Backup Date --- 27/03/26

public class ROPTriggerHandler {
    /**
* @param : newROPs: List of ROP__c records to be processed.
* @description: Handler method : execution : before Insert.
* */
    public static void handleBeforeInsert(List<ROP__c> newROPs) {
        matchContractDetail(newROPs);
        enforceNonNegativeRopAmounts(newROPs);
        updateContractsStatusToCancelled(newROPs);
    }
    public static void handleAfterInsert(List<ROP__c> newROPs){
        // Apply the refund rules where Cancel_Fee__c is not already populated.
        applyRefundRules(newROPs);
    }
    
    /**
* Ensures that an incoming ROP amount cannot be inserted
* with a value below zero.
*
* This validation is intentionally independent of Cancel_Fee__c
* and Contract__c so that all inserted ROP records are protected.
*/
    private static void enforceNonNegativeRopAmounts(List<ROP__c> rops) {
        if (rops == null || rops.isEmpty()) {
            return;
        }
        
        for (ROP__c rop : rops) {
            if (
                rop.ROP_Amount_Calculated__c != null &&
                rop.ROP_Amount_Calculated__c < 0
            ) {
                rop.ROP_Amount_Calculated__c = 0;
            }
        }
    }
    
    /**
* @param : newROPs: List of ROP__c records to be processed.
* @description: Ticket : MRT-68, Processes the list of ROP records to find matching contracts, Populates the contract lookup field if a matching contract is found, Adds an apex error if no matching contract is found.
* */
    public static void matchContractDetail(List<ROP__c> newROPs) {
        
        if (newROPs == null || newROPs.isEmpty()) {
            return;
        }
        
        Set<String> policyNumbers = new Set<String>();
        
        for (ROP__c rop : newROPs) {
            
            if (
                String.isNotBlank(
                    rop.Contract_Id_from_ROP__c
                )
            ) {
                policyNumbers.add(
                    rop.Contract_Id_from_ROP__c
                );
            }
        }
        
        Map<String, InsurancePolicy> contractDetailMap =
            policyNumbers.isEmpty()
            ? new Map<String, InsurancePolicy>()
            : ContractUtility.findContractsfromNumber(
                policyNumbers
            );
        
        for (ROP__c rop : newROPs) {
            
            if (
                String.isNotBlank(
                    rop.Contract_Id_from_ROP__c
                ) &&
                contractDetailMap.containsKey(
                    rop.Contract_Id_from_ROP__c
                )
            ) {
                
                rop.Contract__c =
                    contractDetailMap.get(
                        rop.Contract_Id_from_ROP__c
                    )
                    .Id;
                
            }
            else if (rop.Contract__c == null) {
                
                rop.addError(
                    UtilityClass.ROP_MATCHINGCONTRACT_ERR_MSG +
                    (
                        String.isNotBlank(
                            rop.Contract_Id_from_ROP__c
                        )
                        ? rop.Contract_Id_from_ROP__c
                        : ''
                    )
                );
            }
        }
    }
    
    /**
* @param : newROPs: List of ROP__c records to be processed.
* @description: Applies refund rules based on matching Metadata records.
* */
    private static void applyRefundRules(List<ROP__c> newROPs) {
        
        Set<Id> ropIDs = new Set<Id>();
        // Filter ROPs to process: must have a Contract__c and Cancel_Fee__c must be null
        List<ROP__c> ropsToProcess = new List<ROP__c>();
        Set<Id> contractIds = new Set<Id>();
        
        for(ROP__c rop : newROPs) {
            // Skip if Cancel_Fee__c is already populated
            // Skip if Contract__c is null
            if(rop.Cancel_Fee__c == null && rop.Contract__c != null) {
                //ropsToProcess.add(rop);
                contractIds.add(rop.Contract__c);
                ropIDs.add(rop.Id);
            }
        }
        
        // If no ROPs need processing or no contracts are linked, exit.
        if(ropIDs.isEmpty() || contractIds.isEmpty()) {
            return;
        }
        
        ropsToProcess = [
            SELECT Id, Contract__c, CreatedDate, Cancel_Fee__c, Claims_Paid__c,
            Legacy_ROP_Amount__c, Dealer_Cost__c,
            Cancel_Percent__c, ROP_Amount_Calculated__c,
            Cancel_Date__c, Payoff_Amount__c
            FROM ROP__c
            WHERE Id IN :ropIDs
        ];
        
     //   Set<Id> zeroCancelFeeRopIds = getZeroCancelFeeRopIds(ropsToProcess);
        
        // Query related InsurancePolicy records to get necessary fields for rule matching and calculations.
        Map<Id, InsurancePolicy> contractMap = new Map<Id, InsurancePolicy>(
            [SELECT Id, Product__c, SaleDate, Sale_Date__c, Original_State__c, Ins_Carrier__c, DLRS_Total_Net_Claim__c,
             Net_Funding__c, Calculated_Non_Refundable__c // Include fields for formula calculation
             FROM InsurancePolicy
             WHERE Id IN :contractIds]
        );
        
        
        List<CalculationMatrix> refundRuleMatrices = new List<CalculationMatrix>([SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE LIMIT 1) FROM CalculationMatrix WHERE UniqueName = 'ROP_Refund_Rules']);
        List<CalculationMatrixRow> rows = [SELECT Id, Name, InputData, OutputData FROM CalculationMatrixRow where CalculationMatrixVersionId =: refundRuleMatrices[0].CalculationMatrixVersions[0].Id];
        
        for(ROP__c rop : ropsToProcess) {
            InsurancePolicy relatedContract = contractMap.containsKey(rop.Contract__c)?contractMap.get(rop.Contract__c):null;
            if(relatedContract == null) {
                // Add error if contract not found in the query result (unexpected)
                if (!Test.isRunningTest()) {
                    rop.addError('Related Contract data not found for processing.');
                }
                continue; // Skip to the next ROP
            }
            Date saleDate = relatedContract.Sale_Date__c;
            Map<String, Object> selectedRow;
            Date closestFutureStartDate = null;
            Integer minPositiveDiff = null;
            for(CalculationMatrixRow row : rows) {
                
                System.debug('row.OutputData: '+row.OutputData);
                Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(row.OutputData);
                Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(row.InputData);
                Map<String, String> columntoData = new Map<String, String>();
                System.debug('rowData: '+rowData);
                if(rowData != null ) {
                    
                    if (rowInputData.containsKey('Product') && (String)rowInputData.get('Product') != relatedContract.Product__c) continue;
                    
                    String stateRule = rowData.containsKey('States')?(String)rowData.get('States'):null;
                    String carrierRule = rowData.containsKey('InsuranceCarrier')?(String)rowData.get('InsuranceCarrier'):null;
                    
                    Boolean stateMatch = (stateRule == relatedContract.Original_State__c || stateRule == 'Include All');
                    Boolean carrierMatch = (carrierRule == relatedContract.Ins_Carrier__c || carrierRule == 'Include All');
                    
                    if (stateMatch && carrierMatch) {
                        Date startDate = rowInputData.containsKey('StartDate') ? Date.valueOf((String) rowInputData.get('StartDate')) : null;
                        if (startDate != null  && saleDate != null && startDate <= saleDate) {
                            Integer diff = Math.abs(startDate.daysBetween(saleDate));
                            if (minPositiveDiff == null || diff < minPositiveDiff) {
                                minPositiveDiff = diff;
                                closestFutureStartDate = startDate;
                                selectedRow = rowData;
                            }
                        }
                    }
                }
            }
            if (selectedRow != null) {
                String preCancel = selectedRow.containsKey('PreCancelWindowRefundCalculation')?(String) selectedRow.get('PreCancelWindowRefundCalculation'):null;
                String postCancel = selectedRow.containsKey('PostCancelWindowRefundCalculation')?(String) selectedRow.get('PostCancelWindowRefundCalculation'):null;
                Decimal cancelFee = selectedRow.containsKey('CancelFee') && selectedRow.get('CancelFee') != null ? Decimal.valueOf(String.valueOf(selectedRow.get('CancelFee'))) : 0;
                Integer cancelWindow = selectedRow.containsKey('CancelWindow') && selectedRow.get('CancelWindow') != null ? Integer.valueOf(String.valueOf(selectedRow.get('CancelWindow'))) : 0;
                
                // Determine if inside the cancel window
                Integer daysSinceSale = saleDate.daysBetween(rop.Cancel_Date__c);
                
                Decimal netClaimAmount =
                    relatedContract.DLRS_Total_Net_Claim__c == null
                    ? 0
                    : relatedContract.DLRS_Total_Net_Claim__c;
                
                Boolean isInsideCancelWindow =
                    daysSinceSale <= cancelWindow &&
                    netClaimAmount == 0;
                
                // Apply refund calculation based on the rule and cancel window status
                if(isInsideCancelWindow) {
                    
                    if(preCancel == UtilityClass.STANDARD_CANCEL_WINDOW_REFUND_CALC){
                        rop.Cancel_Fee__c = 0;
                        rop.Claims_Paid__c = 0;
                    }
                    
                } else {
                    
                    /*
* Outside cancel window:
* Apply the matrix CancelFee by default.
* This is required because PostCancelWindow = 'No Deductions'
* should still allow CancelFee = 25 to apply.
*/
                    rop.Cancel_Fee__c = cancelFee;
                    rop.Claims_Paid__c = 0;
                    
                    if(postCancel == UtilityClass.DEDUCT_CLAIM_CANCEL_WINDOW_REFUND_CALC) {
                        rop.Claims_Paid__c = netClaimAmount;
                    }
                    
                    /*
* Only an explicit 'No Cancel Fee' value should zero the cancel fee.
* Do not treat 'No Deductions' as no cancel fee.
*/
                    if(
                        postCancel != null &&
                        postCancel.trim().equalsIgnoreCase('No Cancel Fee')
                    ){
                        rop.Cancel_Fee__c = 0;
                        rop.Claims_Paid__c = 0;
                    }
                }
                
                /*
* New client requirement:
* If this is a subsequent ROP and no Funding was created between
* the previous ROP CreatedDate and this ROP CreatedDate,
* force Cancel Fee to 0.
*/
           /*     if(zeroCancelFeeRopIds.contains(rop.Id)){
                    rop.Cancel_Fee__c = 0;
                }*/
                
                // Calculate ROP_Amount_Calculated__c based on the provided formula
                // Formula: IF(OR(Legacy_ROP_Amount__c <= 0,ISBLANK(Legacy_ROP_Amount__c)),Contract__r.Net_Funding__c - (Dealer_Cost__c * (1-Cancel_Percent__c )) - Cancel_Fee__c - Claims_Paid__c - Contract__r.Calculated_Non_Refundable__c, Legacy_ROP_Amount__c)
                if(rop.Legacy_ROP_Amount__c == null || rop.Legacy_ROP_Amount__c <= 0){
                    // New requirement:
                    // If this ROP has a previous ROP and no Funding was created between
                    // the previous ROP CreatedDate and this ROP CreatedDate,
                    // then force Cancel Fee to 0.
               /*     if(zeroCancelFeeRopIds.contains(rop.Id)){
                        rop.Cancel_Fee__c = 0;
                    }*/
                    // Use the calculation part of the formula
                    // Ensure Dealer_Cost__c, Cancel_Percent__c are not null before calculation
                    Decimal dealerCost = (rop.Dealer_Cost__c == null) ? 0 : rop.Dealer_Cost__c;
                    Decimal cancelPercent = (rop.Cancel_Percent__c == null) ? 0 : rop.Cancel_Percent__c/100;
                    Decimal netFunded = (relatedContract.Net_Funding__c == null) ? 0 : relatedContract.Net_Funding__c;
                    Decimal cancelFees = (rop.Cancel_Fee__c == null) ? 0 : rop.Cancel_Fee__c;
                    Decimal claimsPaid = (rop.Claims_Paid__c == null) ? 0 : rop.Claims_Paid__c;
                    Decimal calculatedNonRefundable = (relatedContract.Calculated_Non_Refundable__c == null) ? 0 : relatedContract.Calculated_Non_Refundable__c;
                    
                    rop.ROP_Amount_Calculated__c = netFunded - (dealerCost * (1 - cancelPercent)) - cancelFees - claimsPaid - calculatedNonRefundable;
                    
                }
                else {
                    // Use Legacy_ROP_Amount__c if it's populated and > 0
                    rop.ROP_Amount_Calculated__c = rop.Legacy_ROP_Amount__c;
                }
                
                /*
* Apply the zero floor before the Payoff cap.
* The local amount must always be written back to the ROP record,
* even when Payoff_Amount__c is blank.
*/
                Decimal finalRopAmount =
                    rop.ROP_Amount_Calculated__c == null
                    ? 0
                    : rop.ROP_Amount_Calculated__c;
                
                // MSM-65: ROP amount must never be less than zero.
                finalRopAmount = Math.max(0, finalRopAmount);
                
                /*
* When Payoff Amount is populated, use the lesser of:
* 1. The current calculated ROP amount
* 2. The Payoff Amount
*/
                if (
                    rop.Payoff_Amount__c != null &&
                    finalRopAmount > rop.Payoff_Amount__c
                ) {
                    finalRopAmount = rop.Payoff_Amount__c;
                }
                
                /*
* Final safety floor:
* This also prevents an invalid negative Payoff Amount
* from creating a negative ROP amount.
*/
                rop.ROP_Amount_Calculated__c =
                    Math.max(0, finalRopAmount);
                
                
            }
            //  NEW CHANGE: Apply Payoff logic
        }  
        
        
        Database.update(ropsToProcess, false);
    }
    
  /* private static Set<Id> getZeroCancelFeeRopIds(
        List<ROP__c> currentRops
    ){
        Set<Id> result = new Set<Id>();
        
        if(currentRops == null || currentRops.isEmpty()){
            return result;
        }
        
        Set<Id> contractIds = new Set<Id>();
        Set<Id> currentRopIds = new Set<Id>();
        Datetime maxCurrentCreatedDate;
        
        for(ROP__c rop : currentRops){
            if(rop.Contract__c == null || rop.CreatedDate == null){
                continue;
            }
            
            contractIds.add(rop.Contract__c);
            currentRopIds.add(rop.Id);
            
            if(
                maxCurrentCreatedDate == null ||
                rop.CreatedDate > maxCurrentCreatedDate
            ){
                maxCurrentCreatedDate = rop.CreatedDate;
            }
        }
        
        if(contractIds.isEmpty() || maxCurrentCreatedDate == null){
            return result;
        }
        
        Map<Id, List<ROP__c>> previousRopsByContractId =
            new Map<Id, List<ROP__c>>();
        
        for(ROP__c previousRop : [
            SELECT Id, Contract__c, CreatedDate
            FROM ROP__c
            WHERE Contract__c IN :contractIds
            AND Id NOT IN :currentRopIds
            AND CreatedDate < :maxCurrentCreatedDate
            ORDER BY CreatedDate DESC
        ]){
            if(!previousRopsByContractId.containsKey(previousRop.Contract__c)){
                previousRopsByContractId.put(
                    previousRop.Contract__c,
                    new List<ROP__c>()
                );
            }
            
            previousRopsByContractId
                .get(previousRop.Contract__c)
                .add(previousRop);
        }
        
        Map<Id, Datetime> previousRopCreatedDateByCurrentRopId =
            new Map<Id, Datetime>();
        
        Datetime minPreviousCreatedDate;
        Datetime maxPairCurrentCreatedDate;
        
        for(ROP__c currentRop : currentRops){
            if(currentRop.Contract__c == null || currentRop.CreatedDate == null){
                continue;
            }
            
            List<ROP__c> previousRops =
                previousRopsByContractId.get(currentRop.Contract__c);
            
            if(previousRops == null || previousRops.isEmpty()){
                continue;
            }
            
            for(ROP__c previousRop : previousRops){
                if(previousRop.CreatedDate < currentRop.CreatedDate){
                    
                    previousRopCreatedDateByCurrentRopId.put(
                        currentRop.Id,
                        previousRop.CreatedDate
                    );
                    
                    if(
                        minPreviousCreatedDate == null ||
                        previousRop.CreatedDate < minPreviousCreatedDate
                    ){
                        minPreviousCreatedDate = previousRop.CreatedDate;
                    }
                    
                    if(
                        maxPairCurrentCreatedDate == null ||
                        currentRop.CreatedDate > maxPairCurrentCreatedDate
                    ){
                        maxPairCurrentCreatedDate = currentRop.CreatedDate;
                    }
                    
                    break;
                }
            }
        }
        
        if(previousRopCreatedDateByCurrentRopId.isEmpty()){
            return result;
        }
        
        Map<Id, List<Funding__c>> fundingByContractId =
            new Map<Id, List<Funding__c>>();
        
        for(Funding__c funding : [
            SELECT Id, Contract__c, CreatedDate
            FROM Funding__c
            WHERE Contract__c IN :contractIds
            AND CreatedDate > :minPreviousCreatedDate
            AND CreatedDate < :maxPairCurrentCreatedDate
        ]){
            if(!fundingByContractId.containsKey(funding.Contract__c)){
                fundingByContractId.put(
                    funding.Contract__c,
                    new List<Funding__c>()
                );
            }
            
            fundingByContractId.get(funding.Contract__c).add(funding);
        }
        
        for(ROP__c currentRop : currentRops){
            
            Datetime previousRopCreatedDate =
                previousRopCreatedDateByCurrentRopId.get(currentRop.Id);
            
            if(previousRopCreatedDate == null){
                continue;
            }
            
            Boolean fundingExistsBetweenRops = false;
            
            List<Funding__c> relatedFundings =
                fundingByContractId.get(currentRop.Contract__c);
            
            if(relatedFundings != null){
                for(Funding__c funding : relatedFundings){
                    if(
                        funding.CreatedDate > previousRopCreatedDate &&
                        funding.CreatedDate < currentRop.CreatedDate
                    ){
                        fundingExistsBetweenRops = true;
                        break;
                    }
                }
            }
            
            if(!fundingExistsBetweenRops){
                result.add(currentRop.Id);
            }
        }
        
        return result;
    }*/
    
    public static void updateContractsStatusToCancelled(
        List<ROP__c> newROPs
    ) {
        if (newROPs == null || newROPs.isEmpty()) {
            return;
        }
        
        Set<Id> contractIds = new Set<Id>();
        
        for (ROP__c ropRecord : newROPs) {
            if (ropRecord.Contract__c != null) {
                contractIds.add(
                    ropRecord.Contract__c
                );
            }
        }
        
        if (contractIds.isEmpty()) {
            return;
        }
        
        Map<Id, InsurancePolicy> contractMap =
            new Map<Id, InsurancePolicy>([
                SELECT Id,
                Status
                FROM InsurancePolicy
                WHERE Id IN :contractIds
                AND Status !=
                :UtilityClass.contractStatus_Cancelled
            ]);
        
        if (contractMap.isEmpty()) {
            return;
        }
        
        List<InsurancePolicy> contractsToUpdate =
            new List<InsurancePolicy>();
        
        for (ROP__c ropRecord : newROPs) {
            
            if (
                ropRecord.Contract__c == null ||
                !contractMap.containsKey(
                    ropRecord.Contract__c
                )
            ) {
                continue;
            }
            
            InsurancePolicy contractToUpdate =
                new InsurancePolicy(
                    Id =
                    ropRecord.Contract__c,
                    
                    Status =
                    UtilityClass.contractStatus_Cancelled,
                    
                    Cancel_Code__c =
                    UtilityClass.CONTRACT_CANCEL_CODE_04,
                    
                    CancellationReasonType =
                    UtilityClass.CONTRACT_CANCELLATION_REASON_TYPE_NON_PAYMENT,
                    
                    Cancelled_By__c =
                    UserInfo.getName()
                );
            
            if (ropRecord.Cancel_Date__c != null) {
                contractToUpdate.Cancel_Reported_Date__c =
                    ropRecord.Cancel_Date__c;
                
                contractToUpdate.Cancel_Effective_Date__c =
                    ropRecord.Cancel_Date__c;
            }
            
            contractsToUpdate.add(
                contractToUpdate
            );
        }
        
        if (!contractsToUpdate.isEmpty()) {
            update contractsToUpdate;
        }
    }
    
    public static void startAllocationProcess(List<ROP__c> newROPs, Map<Id,ROP__c> oldROPs){
        
        Boolean shouldStartAllocation = false;
        
        for(ROP__c ropRec : newROPs){
            
            ROP__c oldRec = oldROPs != null ? oldROPs.get(ropRec.Id) : null;
            
            if( ropRec.Contract__c != null && ropRec.ROP_Amount_Calculated__c != null && (Trigger.isInsert || (oldRec != null && ropRec.ROP_Amount_Calculated__c != oldRec.ROP_Amount_Calculated__c))){
                shouldStartAllocation = true;
                break;
            }
        }
        
        if(shouldStartAllocation){
            ROPAllocationOrchestrator.startAllocation();
        }
    }
}