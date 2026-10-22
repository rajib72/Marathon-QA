/**

* @author: Saurabh Rawat

* @dateModified: 2024-07-04

* @description: Utility class to handle ROP alloations and logic

*/

public with sharing class RopAllocationUtilityCtrl {



    public class RopAllocationIntegrityException extends Exception {}



    private static final String ADMIN_CANCEL_FEE_DESCRIPTOR = 'Admin Cancel Fee';

    private static final String ADMIN_CANCEL_FEE_PAYEE = 'Marathon Administrative';

    private static final String ROP_PAYMENT_RETURN = 'R';



    // GLOBAL ROUNDING UTILITY (FUTURE-PROOF)=============

    private static Decimal roundCurrency(Decimal value) {

        if (value == null) return 0;

        return value.setScale(2, RoundingMode.HALF_UP);

    }



    private static Boolean addAdminCancelFeeRopAllocation(

        ROP__c rop,

        List<Allocation__c> allocationsToInsert

    ){

        if(

            rop == null ||

            rop.Contract__c == null ||

            rop.Cancel_Fee__c == null

        ){

            return false;

        }



        Decimal cancelFeeAmount = roundCurrency(rop.Cancel_Fee__c);



        if(cancelFeeAmount <= 0){

            return false;

        }



        Allocation__c cancelFeeAllocation = new Allocation__c();



        cancelFeeAllocation.Contract__c = rop.Contract__c;

        cancelFeeAllocation.Descriptor__c = ADMIN_CANCEL_FEE_DESCRIPTOR;

        cancelFeeAllocation.Allocation_Amount__c = cancelFeeAmount;

        cancelFeeAllocation.Max_Allocation_Amount__c = cancelFeeAmount;

        cancelFeeAllocation.Payee__c = ADMIN_CANCEL_FEE_PAYEE;

        cancelFeeAllocation.Payment_Return__c = ROP_PAYMENT_RETURN;

        cancelFeeAllocation.is_Expense__c = false;



        allocationsToInsert.add(cancelFeeAllocation);



        return true;

    }



    private static Decimal addAdminCancelFeeRopAllocationWrapper(

        List<ROP__c> rops,

        List<Allocation__c> allocationsToInsert

    ){

        Decimal totalCancelFee = 0;



        if(

            rops == null ||

            rops.isEmpty() ||

            allocationsToInsert == null

        ){

            return totalCancelFee;

        }



        for(ROP__c rop : rops){



            if(

                addAdminCancelFeeRopAllocation(

                    rop,

                    allocationsToInsert

                )

            ){

                totalCancelFee +=

                    roundCurrency(rop.Cancel_Fee__c);

            }

        }



        return roundCurrency(totalCancelFee);

    }



    // Retain the existing public API for existing callers.

    public static void startRopAllocations(List<ROP__c> ropRecords) {

        startRopAllocations(ropRecords, null);

    }



    // Returns ONLY confirmed successful pending-to-processed transitions.

    public static Integer startRopAllocations(List<ROP__c> ropRecords, Id batchJobId) {

        if (ropRecords == null || ropRecords.isEmpty()) return 0;

        Set<Id> inputIds = new Set<Id>();

        Set<Id> contractIds = new Set<Id>();

        for (ROP__c r : ropRecords) {

            if (r != null && r.Id != null && r.Contract__c != null) {

                inputIds.add(r.Id);

                contractIds.add(r.Contract__c);

            }

        }

        if (inputIds.isEmpty()) return 0;



        // One bulk parent lock provides common serialization for automatic and

        // manual batches. Do not use ORDER BY with FOR UPDATE (unsupported).

        Map<Id, InsurancePolicy> parents = new Map<Id, InsurancePolicy>([

            SELECT Id, Dealer_Program_Id__c

            FROM InsurancePolicy WHERE Id IN :contractIds FOR UPDATE

        ]);

        if (parents.size() != contractIds.size()) {

            throw new RopAllocationIntegrityException('A Contract required for ROP processing was not found.');

        }

        Map<Id, ROP__c> refreshed = new Map<Id, ROP__c>([

            SELECT Id, Contract__c, Contract__r.Cancel_Effective_Date__c,

                   Cancel_Date__c, ROP_Amount_Calculated__c, Cancel_Fee__c,

                   CreatedDate, Time_Processed__c, ROP_Allocation_Status__c

            FROM ROP__c WHERE Id IN :inputIds FOR UPDATE

        ]);



        // Pick the oldest still-pending ROP for each parent across the COMPLETE

        // queue, not just this (unordered) batch chunk.

        Map<Id, Id> oldestPendingByContract = new Map<Id, Id>();

        for (ROP__c candidate : [

            SELECT Id, Contract__c, CreatedDate

            FROM ROP__c

            WHERE Contract__c IN :contractIds

            AND Time_Processed__c = null

            AND (ROP_Allocation_Status__c = null OR ROP_Allocation_Status__c = 'Pending')

            ORDER BY Contract__c ASC, CreatedDate ASC, Id ASC

        ]) {

            if (!oldestPendingByContract.containsKey(candidate.Contract__c)) {

                oldestPendingByContract.put(candidate.Contract__c, candidate.Id);

            }

        }

        List<ROP__c> legacy = new List<ROP__c>();

        List<ROP__c> phase2 = new List<ROP__c>();

        for (ROP__c r : refreshed.values()) {

            // FOR UPDATE refreshes the row, but may not re-evaluate its WHERE;

            // explicitly verify state after the lock.

            if (r.Time_Processed__c != null || r.Contract__c == null ||

                r.ROP_Amount_Calculated__c == null ||

                (r.ROP_Allocation_Status__c != null && r.ROP_Allocation_Status__c != 'Pending') ||

                oldestPendingByContract.get(r.Contract__c) != r.Id) continue;

            if (parents.get(r.Contract__c).Dealer_Program_Id__c == null) legacy.add(r);

            else phase2.add(r);

        }

        if (legacy.isEmpty() && phase2.isEmpty()) return 0;

        // At most one selected ROP per Contract: no same-contract sum/fee duplication.

        if (!legacy.isEmpty()) processLegacyContracts(legacy);

        if (!phase2.isEmpty()) processContracts(phase2);



        Set<Id> selectedIds = new Set<Id>();

        for (ROP__c r : legacy) selectedIds.add(r.Id);

        for (ROP__c r : phase2) selectedIds.add(r.Id);

        List<ROP__c> statusUpdates = new List<ROP__c>();

        for (ROP__c r : [

            SELECT Id, Time_Processed__c FROM ROP__c WHERE Id IN :selectedIds

        ]) {

            if (r.Time_Processed__c == null) {

                throw new RopAllocationIntegrityException('ROP was not marked processed: ' + r.Id);

            }

            statusUpdates.add(new ROP__c(

                Id = r.Id,

                ROP_Allocation_Status__c = 'Processed',

                ROP_Allocation_Batch_Job_Id__c = batchJobId == null ? null : String.valueOf(batchJobId)

            ));

        }

        if (!statusUpdates.isEmpty()) update statusUpdates;

        return statusUpdates.size();

    }



    public static void processLegacyContracts(List<ROP__c> ropRecords) {

        if (ropRecords == null || ropRecords.isEmpty()) return;

        // Direct callers must not bypass the one-ROP-per-contract processing invariant.

        Set<Id> seen = new Set<Id>();

        for (ROP__c r : ropRecords) {

            if (!seen.add(r.Contract__c)) {

                throw new RopAllocationIntegrityException(

                    'Multiple legacy ROPs for the same Contract require startRopAllocations: ' + r.Contract__c

                );

            }

        }

        Savepoint legacySp = Database.setSavepoint();

        try{

            // NEW CHANGE - Prevent ROP allocation when no new funding exists

            Map<Id, Boolean> allocationEligibility =

                getAllocationEligibilityByContract(ropRecords);



            List<ROP__c> skippedRops = new List<ROP__c>();

            Set<Id> contractIdSet = new Set<Id>();

            Set<String> clientProgramCodeSet = new Set<String>();

            Set<String> ratingRecordSet = new Set<String>();

            List<InsurancePolicy> contracts = new List<InsurancePolicy>();

            List<Allocation__c> allocations = new List<Allocation__c>();

            List<Dealer_Cost_Allocation__c> dealerAllocations = new List<Dealer_Cost_Allocation__c>();

            Map<Id,InsurancePolicy> contractsMap = new Map<Id,InsurancePolicy>();

            Map<Id,List<ROP__c>> contractROPsMap = new Map<Id,List<ROP__c>>();

            Map<Id,Map<String,Allocation__c>> preExROPAllocMap = new Map<Id,Map<String,Allocation__c>>();

            Map<Id,Map<String,Allocation__c>> preExFUNAllocMap = new Map<Id,Map<String,Allocation__c>>();

            Map<String,Map<String,Dealer_Cost_Allocation__c>> dealerAllocMap = new Map<String,Map<String,Dealer_Cost_Allocation__c>>();

            Map<String, Decimal> groupedAllocationMap = new Map<String, Decimal>();

            Map<String, List<String>> ratingRecordIdsMap = new Map<String, List<String>>();

            List<Allocation__c> allocationsToInsert = new List<Allocation__c>();

            List<Allocation__c> allocationsToUpdate = new List<Allocation__c>();

            List<ROP__c> ropToUpdate = new List<ROP__c>();

            Map<Id, InsurancePolicy> contractToUpdate = new Map<Id, InsurancePolicy>();





            //fill ROP Records

            for(ROP__c eachROP : ropRecords){



                // NEW CHANGE

                if(

                    roundCurrency(eachROP.ROP_Amount_Calculated__c) == 0 ||

                    (eachROP.Contract__c != null &&

                     allocationEligibility.containsKey(eachROP.Contract__c) &&

                     allocationEligibility.get(eachROP.Contract__c) == false)

                ){

                    //eachROP.Time_Processed__c = Datetime.now();

                    eachROP.ROP_Amount_Calculated__c = 0;

                    eachROP.Cancel_Fee__c = 0;

                    skippedRops.add(eachROP);

                    continue;

                }



                if(String.isNotBlank(eachROP.Contract__c)){

                    contractIdSet.add(eachROP.Contract__c);

                    List<ROP__c> tempROPs = contractROPsMap.containskey(eachROP.Contract__c)?contractROPsMap.get(eachROP.Contract__c):new List<ROP__c>();

                    tempROPs.add(eachROP);

                    contractROPsMap.put(eachROP.Contract__c,tempROPs);

                    if(eachROP.Contract__r.Cancel_Effective_Date__c == null){

                        InsurancePolicy contractChange = contractToUpdate.containsKey(eachROP.Contract__c)

                            ? contractToUpdate.get(eachROP.Contract__c)

                            : new InsurancePolicy(Id = eachROP.Contract__c);

                        contractChange.Cancel_Effective_Date__c = eachROP.Cancel_Date__c;

                        contractToUpdate.put(eachROP.Contract__c, contractChange);

                    }

                }

            }



            //fetch Contracts

            if(contractIdSet.size() > 0){

                //Id autoWarrantyRTId = UtilityClass.getsObjectRecordTypeId('InsurancePolicy', 'Auto_Warranty');

                List<Id> autoWarrantyRTId = UtilityClass.getsObjectRecordTypeId('InsurancePolicy', new List<String>{'Auto_Warranty', 'Home_Warranty'});

                contracts = [Select Id, Client_Program_Code__c,Earned_Percent__c from InsurancePolicy where Id IN :contractIdSet

                             AND RecordTypeId =: autoWarrantyRTId LIMIT 45000];

                contractsMap = new Map<Id,InsurancePolicy>(contracts);

                allocations = [Select Id, Allocation_Amount__c, Allocation_Code__c,Contract__c, Allocation_Code__r.Name, Payment_Return__c from Allocation__c Where Contract__c IN :contractIdSet LIMIT 45000];



                //Fill Pre exisitng ROP Allocation Map

                for(Allocation__c each: allocations){

                    if(each.Payment_Return__c == 'R' && each.Allocation_Code__r != null && !String.isBlank(each.Allocation_Code__r.Name)){

                        Map<String,Allocation__c> tempAllocationMap = preExROPAllocMap.containsKey(each.Contract__c)?preExROPAllocMap.get(each.Contract__c):new Map<String,Allocation__c>();

                        tempAllocationMap.put(each.Allocation_Code__r.Name,each);

                        preExROPAllocMap.put(each.Contract__c,tempAllocationMap);    

                    }

                }



                //Fill Pre exisitng FUNDING Allocation Map

                for(Allocation__c each: allocations){

                    if(each.Payment_Return__c != 'R' && each.Allocation_Code__r != null && !String.isBlank(each.Allocation_Code__r.Name)){

                        Map<String,Allocation__c> tempAllocationMap = preExFUNAllocMap.containsKey(each.Contract__c)?preExFUNAllocMap.get(each.Contract__c):new Map<String,Allocation__c>();

                        tempAllocationMap.put(each.Allocation_Code__r.Name,each);

                        preExFUNAllocMap.put(each.Contract__c,tempAllocationMap);    

                        groupedAllocationMap.put(each.Contract__c+''+each.Allocation_Code__r.Name,

                                                 groupedAllocationMap.containsKey(each.Contract__c+''+each.Allocation_Code__r.Name)?

                                                 groupedAllocationMap.get(each.Contract__c+''+each.Allocation_Code__r.Name)+each.Allocation_Amount__c:each.Allocation_Amount__c);

                    }

                }

                //Fill Client Program Codes for querying Dealer Cost Allocations

                for(InsurancePolicy contract : contracts){

                    if(String.isNotBlank(contract.Client_Program_Code__c)){

                        clientProgramCodeSet.add(contract.Client_Program_Code__c);

                    }

                }

                //Fetch RatingRecordIDs with respect to Client Program Code

                if(clientProgramCodeSet.size() > 0){

                    ratingRecordIdsMap = ContractAllocationUtilityCtrl.fillProgramCodeDetails(clientProgramCodeSet);

                    if(ratingRecordIdsMap.size() > 0){

                        for(String clientProgramCode : ratingRecordIdsMap.keyset()){

                            ratingRecordSet.addAll(ratingRecordIdsMap.get(clientProgramCode));

                        }

                    }

                }



                dealerAllocations = [Select Id, Allocation_Amount__c, AllocationCode__c, RatingRecordID__c, Refundable__c from Dealer_Cost_Allocation__c Where RatingRecordID__c IN :ratingRecordSet AND Refundable__c = 'Y'];

                for(Dealer_Cost_Allocation__c eachAllocation : dealerAllocations){

                    Map<String,Dealer_Cost_Allocation__c> tempAllocationMap = dealerAllocMap.containsKey(eachAllocation.RatingRecordID__c)?dealerAllocMap.get(eachAllocation.RatingRecordID__c):new Map<String,Dealer_Cost_Allocation__c>();

                    tempAllocationMap.put(eachAllocation.AllocationCode__c,eachAllocation);

                    dealerAllocMap.put(eachAllocation.RatingRecordID__c,tempAllocationMap);

                }



                for(String contractId : preExFUNAllocMap.keyset()){

                    Map<String,Allocation__c> exAllocationMap = preExFUNAllocMap.get(contractId);

                    Boolean atLeastROPCreated = false;

                    // Admin Cancel Fee ROP Allocation

                    if(contractROPsMap.containsKey(contractId)){



                        for(ROP__c rop : contractROPsMap.get(contractId)){



                            Boolean cancelFeeAllocationCreated =

                                addAdminCancelFeeRopAllocation(

                                    rop,

                                    allocationsToInsert

                                );



                            if(cancelFeeAllocationCreated){

                                atLeastROPCreated = true;

                            }

                        }

                    }

                    for(String allocationCode : exAllocationMap.keyset()){



                        //insert new ROP Allocation

                        List<String> ratingrecordIds = ratingRecordIdsMap.containsKey(contractsMap.get(contractId).Client_Program_Code__c)?ratingRecordIdsMap.get(contractsMap.get(contractId).Client_Program_Code__c):new List<String>();

                        //considering there is going to be only 1 rating record at a time

                        if(ratingrecordIds.size() > 0){



                            String ratingRecordID = ratingrecordIds.get(0);    

                            Dealer_Cost_Allocation__c DealerAlloc = dealerAllocMap.containsKey(ratingRecordID) && dealerAllocMap.get(ratingRecordID).containsKey(allocationCode)?dealerAllocMap.get(ratingRecordID).get(allocationCode) : new Dealer_Cost_Allocation__c();



                            //check if Deal Cost Allocation is Non refundable

                            if(String.isNotBlank(DealerAlloc.Id) || allocationCode == '8004'){

                                Allocation__c newAllocation = new Allocation__c();

                                newAllocation.Allocation_Code__c = exAllocationMap.get(allocationCode).Allocation_Code__c;

                                Decimal earnedPercnt = contractsMap.get(contractId).Earned_Percent__c != null ? contractsMap.get(contractId).Earned_Percent__c:0;

                                Decimal Earned       = (allocationCode == '8004' && groupedAllocationMap.containsKey(contractId+''+allocationCode)? groupedAllocationMap.get(contractId+''+allocationCode):DealerAlloc.Allocation_Amount__c) * (earnedPercnt!= 0?earnedPercnt/100:0);

                                Decimal ROPAmount    =  groupedAllocationMap.containsKey(contractId+''+allocationCode)?groupedAllocationMap.get(contractId+''+allocationCode):0 - Earned;

                                //FIX: round before saving

                                newAllocation.Allocation_Amount__c = roundCurrency(ROPAmount);

                                newAllocation.Payment_Return__c = 'R';

                                newAllocation.Contract__c = contractId;

                                newAllocation.Reference_Allocation__c = exAllocationMap.get(allocationCode).Id;

                                if(preExROPAllocMap.containsKey(contractId) && preExROPAllocMap.get(contractId).containsKey(allocationCode)){

                                    //update existing allocation

                                    newAllocation.Id =  preExROPAllocMap.get(contractId).get(allocationCode).Id;

                                    allocationsToUpdate.add(newAllocation);

                                    atLeastROPCreated = true;

                                }else{

                                    allocationsToInsert.add(newAllocation);  

                                    atLeastROPCreated = true;

                                }

                            }



                        }



                    }

                    if(atLeastROPCreated == true){

                        ropToUpdate.addAll(contractROPsMap.get(contractId));

                        system.debug('------>' +ropToUpdate);

                    }

                }



                if(allocationsToInsert.size() > 0){

                    Database.insert(allocationsToInsert);

                }

                if(allocationsToUpdate.size() > 0){

                    Database.update(allocationsToUpdate);

                }



                // NEW CHANGE

                if(ropToUpdate.size() > 0){

                    system.debug('------>' +ropToUpdate);

                    for(ROP__c eachROP : ropToUpdate){

                        eachROP.Time_Processed__c = Datetime.now();

                    }

                    Database.update(ropToUpdate);    

                }

                //----------------------New Code--------------------------//



                // --- START PATCH: populate contract-level ROP fields for legacy (DSI) contracts ---

                Map<Id, Decimal> appliedByContract = new Map<Id, Decimal>();

                Map<Id, ROP__c> selectedLegacy = new Map<Id, ROP__c>();

                for (ROP__c selected : ropToUpdate) selectedLegacy.put(selected.Id, selected);

                for (ROP__c historic : [

                    SELECT Id, Contract__c, ROP_Amount_Calculated__c, Time_Processed__c

                    FROM ROP__c WHERE Contract__c IN :contractIdSet

                ]) {

                    if (historic.Time_Processed__c == null && !selectedLegacy.containsKey(historic.Id)) {

                        continue;

                    }

                    Decimal effectiveAmount = selectedLegacy.containsKey(historic.Id)

                        ? roundCurrency(selectedLegacy.get(historic.Id).ROP_Amount_Calculated__c)

                        : roundCurrency(historic.ROP_Amount_Calculated__c);

                    appliedByContract.put(historic.Contract__c,

                        (appliedByContract.containsKey(historic.Contract__c)

                            ? appliedByContract.get(historic.Contract__c) : 0) + effectiveAmount);

                }

                if (contractROPsMap != null && !contractROPsMap.isEmpty()) {

                    for (Id cId : contractROPsMap.keySet()) {

                        try {

                            List<ROP__c> ropsForContract = contractROPsMap.get(cId);

                            if (ropsForContract == null || ropsForContract.isEmpty()) continue;



                            Decimal totalAppliedROP = 0;



                            ROP__c latestRop;



                            for (ROP__c r : ropsForContract) {

                                if(

                                    latestRop == null ||

                                    r.CreatedDate > latestRop.CreatedDate

                                ){

                                    latestRop = r;

                                }

                            }



                            Decimal lastRopAmount = 0;

                            Decimal lastCancelFee = 0;



                            if(latestRop != null){



                                if(latestRop.ROP_Amount_Calculated__c != null){

                                    lastRopAmount = latestRop.ROP_Amount_Calculated__c;

                                }



                                if(latestRop.Cancel_Fee__c != null){

                                    lastCancelFee = latestRop.Cancel_Fee__c;

                                }

                            }



                            // Merge financial fields with any existing cancellation update.

                            InsurancePolicy ipToUpd = contractToUpdate.containsKey(cId)

                                ? contractToUpdate.get(cId)

                                : new InsurancePolicy(Id = cId);

                            ipToUpd.Applied_ROP_Amount__c = appliedByContract.containsKey(cId)

                                ? roundCurrency(appliedByContract.get(cId)) : 0;

                            ipToUpd.ROP_Amount__c = lastRopAmount;

                            ipToUpd.ROP_Cancel_Fee__c = lastCancelFee;

                            contractToUpdate.put(cId, ipToUpd);

                        } catch (Exception innerEx) {

                            throw innerEx;

                        }

                    }

                }

                // --- END PATCH ---





                if(contractToUpdate.size() > 0){

                    Database.update(contractToUpdate.values());

                }



            }

            // Both eligible and skipped ROPs must have a successful processing

            // marker. This also handles an ALL-skipped scope (no source Funding).

            if (!skippedRops.isEmpty()) {

                for (ROP__c skipped : skippedRops) skipped.Time_Processed__c = System.now();

                update skippedRops;

            }

        }catch(Exception e){

            Database.rollback(legacySp);

            QDX_Log.error('Exception Occurred: ' + e.getMessage() +

                          ' Line Number: ' + e.getLineNumber());

            QDX_Log.publish();

            throw e; // Never report failed legacy scopes as successful.

        }

    }



    private static Map<Id, Boolean> getAllocationEligibilityByContract(

        List<ROP__c> ropRecords

    ){

        Set<Id> contractIds = new Set<Id>();

        Set<Id> currentRopIds = new Set<Id>();



        for(ROP__c rop : ropRecords){

            if(rop.Contract__c != null){

                contractIds.add(rop.Contract__c);

            }



            if(rop.Id != null){

                currentRopIds.add(rop.Id);

            }

        }



        Map<Id, Datetime> previousROPMap = new Map<Id, Datetime>();



        for(ROP__c r : [

            SELECT Contract__c, Time_Processed__c

            FROM ROP__c

            WHERE Contract__c IN :contractIds

            AND Time_Processed__c != null

            AND Id NOT IN :currentRopIds

            ORDER BY Time_Processed__c DESC

        ]){

            if(!previousROPMap.containsKey(r.Contract__c)){

                previousROPMap.put(r.Contract__c, r.Time_Processed__c);

            }

        }



        Map<Id, Datetime> latestFundingMap = new Map<Id, Datetime>();



        for(Funding__c f : [

            SELECT Contract__c, Time_Processed__c

            FROM Funding__c

            WHERE Contract__c IN :contractIds

            AND Time_Processed__c != null

            ORDER BY Time_Processed__c DESC

        ]){

            if(!latestFundingMap.containsKey(f.Contract__c)){

                latestFundingMap.put(f.Contract__c, f.Time_Processed__c);

            }

        }



        Map<Id, Boolean> result = new Map<Id, Boolean>();



        for(Id contractId : contractIds){



            Datetime prevROP = previousROPMap.get(contractId);

            Datetime fundingTime = latestFundingMap.get(contractId);



            result.put(

                contractId,

                fundingTime != null &&

                (prevROP == null || fundingTime > prevROP)

            );

        }



        return result;

    }



    /**

* Processes ROP funding allocation for non-legacy (new) contracts.

* 

* This method:

* 1. Groups ROP records by Contract.

* 2. Queries related contract and allocation data.

* 3. Calculates refund allocation gaps based on existing refunds.

* 4. Determines and creates new refund allocations to meet earned targets.

* 5. Updates the processed contracts and ROP records accordingly.

* 

* @param ropRecords List of ROP__c records to process

*/

    /**
     * Per-code model for refundable Funding. A code can have many P rows
     * (split funding), but contributes at most ONE non-zero ROP return row.
     * Do not key this bucket by Descriptor: distinct codes may share it.
     */
    private class RefundableCodeBucket {
        Id codeId;
        String descriptor;
        Decimal funded = 0;
        Decimal maximum = 0;

        RefundableCodeBucket(Id sourceCode, String sourceDescriptor) {
            codeId = sourceCode;
            descriptor = sourceDescriptor;
        }
    }

    /**
     * Pure calculation helper. Expects P rows already filtered to the current
     * Contract/reinstatement cycle and sorted by code priority, CreatedDate, Id.
     * The latest NON-NULL maximum for each code is authoritative, while every
     * Funding amount for that code contributes to its funded total.
     *
     * Reserve remains a SINGLE balancing ROP row and Admin Cancel Fee remains
     * a separate standalone allocation; neither is returned by this helper.
     */
    @TestVisible
    private static List<Allocation__c> buildNonReserveReturnsByCode(
        Id contractId,
        List<Allocation__c> fundingRows,
        Decimal refundFraction
    ) {
        List<Allocation__c> results = new List<Allocation__c>();
        if (fundingRows == null || fundingRows.isEmpty()) return results;

        Map<Id, RefundableCodeBucket> bucketsByCode =
            new Map<Id, RefundableCodeBucket>();
        List<Id> orderedCodeIds = new List<Id>();

        for (Allocation__c paid : fundingRows) {
            if (paid.Allocation_Code__c == null) {
                throw new RopAllocationIntegrityException(
                    'Refundable Funding allocation has no Allocation Code: ' + paid.Id
                );
            }
            if (paid.Allocation_Amount__c == null ||
                String.isBlank(paid.Descriptor__c)) {
                throw new RopAllocationIntegrityException(
                    'Refundable Funding allocation has incomplete data: ' + paid.Id
                );
            }

            RefundableCodeBucket bucket = bucketsByCode.get(paid.Allocation_Code__c);
            if (bucket == null) {
                bucket = new RefundableCodeBucket(
                    paid.Allocation_Code__c, paid.Descriptor__c
                );
                bucketsByCode.put(paid.Allocation_Code__c, bucket);
                orderedCodeIds.add(paid.Allocation_Code__c);
            } else if (bucket.descriptor != paid.Descriptor__c) {
                // Do not silently combine different descriptors if the same
                // code has been reconfigured during the Funding history.
                throw new RopAllocationIntegrityException(
                    'Funding Allocation Code has inconsistent Descriptors: ' +
                    paid.Allocation_Code__c
                );
            }

            // Split P rows are combined; we do NOT generate one R row per P row.
            bucket.funded += paid.Allocation_Amount__c;
            // Repeated maximum values are NOT summed. Explicit zero is valid.
            if (paid.Max_Allocation_Amount__c != null) {
                bucket.maximum = paid.Max_Allocation_Amount__c;
            }
        }

        Decimal fraction = refundFraction == null ? 0 : refundFraction;
        for (Id codeId : orderedCodeIds) {
            RefundableCodeBucket bucket = bucketsByCode.get(codeId);
            if (bucket.descriptor == 'Reserve' ||
                bucket.descriptor == ADMIN_CANCEL_FEE_DESCRIPTOR) {
                continue;
            }

            // Preserve the existing earned/refundable calculation independently
            // for each code. This is not an unconditional -funded mirror.
            Decimal signedAmount = roundCurrency(
                -(bucket.funded - bucket.maximum * (1 - fraction))
            );
            if (signedAmount == 0) continue;

            results.add(new Allocation__c(
                Contract__c = contractId,
                Allocation_Code__c = bucket.codeId,
                Descriptor__c = bucket.descriptor,
                Allocation_Amount__c = signedAmount,
                Max_Allocation_Amount__c = null,
                Payment_Return__c = ROP_PAYMENT_RETURN
            ));
        }
        return results;
    }

    public static void processContracts(List<ROP__c> ropRecords) {

        if (ropRecords == null || ropRecords.isEmpty()) return;

        Savepoint sp = Database.setSavepoint();

        try {

            // Group ROPs by Contract Id

            Map<Id, List<ROP__c>> ropsByContractId = new Map<Id, List<ROP__c>>();

            Set<Id> contractIds = new Set<Id>();

            for (ROP__c rop : ropRecords) {

                if (!ropsByContractId.containsKey(rop.Contract__c)) {

                    ropsByContractId.put(rop.Contract__c, new List<ROP__c>());

                }

                if (!ropsByContractId.get(rop.Contract__c).isEmpty()) {

                    throw new RopAllocationIntegrityException(

                        'More than one ROP for a Contract must be serialized by startRopAllocations(): ' + rop.Contract__c

                    );

                }

                ropsByContractId.get(rop.Contract__c).add(rop);

                contractIds.add(rop.Contract__c);

            }



            // If no ROPs have related contracts, exit the method

            if (contractIds.isEmpty()) {

                return;

            }



            Map<Id, Boolean> allocationEligibility = getAllocationEligibilityByContract(ropRecords);



            // Query for all ROP__c records related to the contracts being processed

            Map<Id, List<ROP__c>> allRopsByContractId = new Map<Id, List<ROP__c>>();

            List<ROP__c> allRelatedRops = [

                SELECT Id, Contract__c, ROP_Amount_Calculated__c, Cancel_Fee__c,

                       CreatedDate, Time_Processed__c

                FROM ROP__c

                WHERE Contract__c IN :contractIds

            ];

            for(ROP__c rop : allRelatedRops){

                if(!allRopsByContractId.containsKey(rop.Contract__c)){

                    allRopsByContractId.put(rop.Contract__c, new List<ROP__c>());

                }

                allRopsByContractId.get(rop.Contract__c).add(rop);

            }



            // Query Contracts related to the ROPs

            Map<Id, InsurancePolicy> contractsByContractId = new Map<Id, InsurancePolicy>([

                SELECT Id, Earned_Percent__c, Earned_Reserve__c, Refund_Percent__c, Reinstatement_Date__c, 

                Cancel_Fee__c, ROP_Amount__c, Applied_ROP_Amount__c, Admin_Cost__c, Agent_Commision__c, ARF_Fee__c, 

                Broker_Commission__c, Ceding_Fee2__c, CLIP__c, Fulfillment_Fee__c, Maintenance_Admin_Fee__c, Obligor_Fee__c, Obligor_Tax__c, Contract_Term_Months__c,

                Offset_Surplus__c, Premium_Refund__c, Premium_Tax1__c, Processing_Fee__c, Reserve_Pack__c, Retention_Collection_Fee__c, 

                Roadside_Fee2__c, Seller_Commission__c, System_Fee__c, Legacy_Source__c, Down_Payment_Amount__c, PremiumAmount, Lien_Holder_Present__c, 

                Funded_Admin_Fee__c, Funded_Agent_Commission__c, Funded_ARF_Fee__c, Funded_Broker_Commission__c, Funded_Ceding_Fee__c, Funded_CLIP_Fee__c, Funded_Fulfillment_Fee__c, Funded_Maintenance_Admin_Fee__c, Funded_Obligor_Fee__c, Funded_Obligor_Tax__c, Funded_Offset_Surplus__c, Funded_Premium_Refund__c, Funded_Premium_Tax__c, Funded_Processing_Fee__c, Funded_Reserve_Pack__c, Funded_Retention_Collection_Fee__c, Funded_Roadside_Fee__c, Funded_Seller_Commission__c, Funded_System_Fee__c, Funded_Reserve__c

                FROM InsurancePolicy

                WHERE Id IN :contractIds

            ]);



            // Group refundable P rows by Contract; a later helper groups each
            // Contract by Allocation_Code__c, never by Descriptor__c.
            Map<Id, List<Allocation__c>> refundableFundingByContract =
                new Map<Id, List<Allocation__c>>();
            Map<Id, Boolean> hasReserveFunding = new Map<Id, Boolean>();

            // Retain the original reinstatement boundary: ignore P rows
            // created before Reinstatement_Date__c for a reinstated Contract.
            Map<Id, Datetime> contractReinstateDateMap = new Map<Id, Datetime>();
            for (InsurancePolicy contract : contractsByContractId.values()) {
                if (contract.Reinstatement_Date__c != null) {
                    contractReinstateDateMap.put(
                        contract.Id, contract.Reinstatement_Date__c
                    );
                }
            }

            List<Allocation__c> allAllocations = [
                SELECT Id, Allocation_Amount__c, Name, Descriptor__c,
                       Allocation_Code__r.Priority__c, Allocation_Code__c,
                       Contract__c, CreatedDate, Payment_Return__c,
                       Code_Refundable__c, Max_Allocation_Amount__c
                FROM Allocation__c
                WHERE Contract__c IN :contractIds
                  AND Payment_Return__c = 'P'
                  AND Code_Refundable__c = 'Y'
                ORDER BY Contract__c ASC, Allocation_Code__r.Priority__c ASC,
                         CreatedDate ASC, Id ASC
            ];

            for (Allocation__c paid : allAllocations) {
                Datetime reinstateDate =
                    contractReinstateDateMap.get(paid.Contract__c);
                if (reinstateDate != null && paid.CreatedDate < reinstateDate) {
                    continue;
                }
                if (!refundableFundingByContract.containsKey(paid.Contract__c)) {
                    refundableFundingByContract.put(
                        paid.Contract__c, new List<Allocation__c>()
                    );
                }
                refundableFundingByContract.get(paid.Contract__c).add(paid);
                if (paid.Descriptor__c == 'Reserve') {
                    hasReserveFunding.put(paid.Contract__c, true);
                }
            }

            List<Allocation__c> newAllocations = new List<Allocation__c>();



            // Loop through each contract and determine refund needs

            for (Id contractId : ropsByContractId.keySet()) {

                InsurancePolicy contract = contractsByContractId.get(contractId);

                if (contract == null) throw new RopAllocationIntegrityException('Contract missing: ' + contractId);

                List<Allocation__c> contractAllocations = new List<Allocation__c>();



                Boolean shouldCreateAllocations =

                    allocationEligibility.containsKey(contractId) &&

                    allocationEligibility.get(contractId);

                // A later ROP with no intervening funding has no eligible balance.

                // Fix stale positive amounts created simultaneously against the

                // same Net Funding; never create fee-only zero-refund allocations.

                for (ROP__c r : ropsByContractId.get(contractId)) {

                    if (!shouldCreateAllocations || roundCurrency(r.ROP_Amount_Calculated__c) == 0) {

                        r.ROP_Amount_Calculated__c = 0;

                        r.Cancel_Fee__c = 0;

                    }

                }

                // Calculate total ROP funds available to allocate for this contract

                ROP__c latestRop;



                for (ROP__c rop : ropsByContractId.get(contractId)) {



                    if(

                        latestRop == null ||

                        rop.CreatedDate > latestRop.CreatedDate

                    ){

                        latestRop = rop;

                    }

                }



                if(latestRop != null){

                    contract.ROP_Amount__c = latestRop.ROP_Amount_Calculated__c;

                    contract.ROP_Cancel_Fee__c = latestRop.Cancel_Fee__c;

                }



                // Calculate Applied_ROP_Amount__c as the sum of ROP_Amount_Calculated__c for ALL ROPs related to the Contract

                Decimal totalAppliedROP = 0;

                if(allRopsByContractId.containsKey(contractId)){

                    for(ROP__c relatedRop : allRopsByContractId.get(contractId)){

                        // Do not deduct future pending ROPs from Contract Net Funding.

                        // Count only already processed ROPs and the one being completed NOW.

                        ROP__c source = ropsByContractId.get(contractId)[0];

                        if (relatedRop.Id != source.Id && relatedRop.Time_Processed__c == null) {

                            continue;

                        }

                        totalAppliedROP += roundCurrency(

                            relatedRop.Id == source.Id

                                ? source.ROP_Amount_Calculated__c

                                : relatedRop.ROP_Amount_Calculated__c

                        );

                        //!= null ? relatedRop.ROP_Amount_Calculated__c : 0;

                        system.debug('-------> '+relatedRop.ROP_Amount_Calculated__c);

                        system.debug('-------> '+totalAppliedROP);

                    }

                }

                system.debug('-------> '+totalAppliedROP);

                contract.Applied_ROP_Amount__c = totalAppliedROP;

                system.debug('Current Contract values'+contract);



                //Changes : 25-06-2026

                //Changes : 25-06-2026

                // Only a positive, eligible ROP creates financial allocations.

                shouldCreateAllocations = shouldCreateAllocations &&

                    roundCurrency(ropsByContractId.get(contractId)[0].ROP_Amount_Calculated__c) > 0;



                if (shouldCreateAllocations) {
                    // Preserve the existing Reserve-source precondition.
                    if (!hasReserveFunding.containsKey(contractId)) {
                        throw new RopAllocationIntegrityException(
                            'Refundable Reserve Funding allocation missing for Contract: ' +
                            contractId
                        );
                    }

                    Decimal ropAmountTotal = 0;
                    for (ROP__c r : ropsByContractId.get(contractId)) {
                        ropAmountTotal += roundCurrency(r.ROP_Amount_Calculated__c);
                    }
                    ropAmountTotal = roundCurrency(ropAmountTotal);
                    Decimal refundFraction = contract.Refund_Percent__c == null
                        ? 0 : contract.Refund_Percent__c / 100;

                    // Exactly one R row for each funded Allocation Code (not
                    // each Funding row or Descriptor). Excludes Reserve and
                    // Admin Cancel Fee, which retain their special handling.
                    contractAllocations.addAll(buildNonReserveReturnsByCode(
                        contractId,
                        refundableFundingByContract.get(contractId),
                        refundFraction
                    ));

                    // Exactly once, after other fees and IMMEDIATELY BEFORE Reserve.

                    addAdminCancelFeeRopAllocationWrapper(

                        ropsByContractId.get(contractId), contractAllocations

                    );



                    // Reserve balances only THIS contract's current ROP allocations.

                    Decimal nonReserveTotal = 0;

                    for (Allocation__c a : contractAllocations) {

                        nonReserveTotal += roundCurrency(a.Allocation_Amount__c);

                    }

                    nonReserveTotal = roundCurrency(nonReserveTotal);

                    Decimal reserveAmount = roundCurrency(-ropAmountTotal - nonReserveTotal);

                    // Reserve remains one balancing row, with no Allocation Code.
                    if (reserveAmount != 0) {
                        contractAllocations.add(new Allocation__c(
                            Contract__c = contractId,
                            Descriptor__c = 'Reserve',
                            Allocation_Amount__c = reserveAmount,
                            Max_Allocation_Amount__c = null,
                            Payment_Return__c = ROP_PAYMENT_RETURN
                        ));
                    }

                    // Fail before inserting anything if there is no Reserve source,

                    // missing configuration or a financial reconciliation failure.

                    Decimal signedTotal = 0;

                    for (Allocation__c a : contractAllocations) {

                        signedTotal += roundCurrency(a.Allocation_Amount__c);

                    }

                    signedTotal = roundCurrency(signedTotal);

                    if (signedTotal != -ropAmountTotal) {

                        throw new RopAllocationIntegrityException(

                            'ROP allocation mismatch. Contract=' + contractId +

                            ' Expected=' + (-ropAmountTotal) +

                            ' Actual=' + signedTotal

                        );

                    }

                    newAllocations.addAll(contractAllocations);

                }



                // Preserve the existing policy: ROPs without new funding are

                // marked processed but must NOT create another allocation set.

                for (ROP__c r : ropsByContractId.get(contractId)) {

                    r.Time_Processed__c = System.now();

                    if (r.Cancel_Date__c != null) {

                        contract.Cancel_Effective_Date__c = r.Cancel_Date__c;

                    }

                }

            }

            Database.insert(newAllocations, true); // Insert refund allocations - All or none

            // START: Sohel Azmi - 27/03/26

            // ContractAllocationUtilityCtrl.updateContractAllocationFields(contractsByContractId);

            updateContractAllocationFields(contractsByContractId);

            // END: Sohel Azmi - 27/03/26

            for (InsurancePolicy c : contractsByContractId.values()) {

                System.debug(

                    'VALIDATION CHECK → ' +

                    'Legacy=' + c.Legacy_Source__c +

                    ' | Down=' + c.Down_Payment_Amount__c +

                    ' | Premium=' + c.PremiumAmount +

                    ' | Lien=' + c.Lien_Holder_Present__c

                );

            }

            Database.update(contractsByContractId.values(), true); // Update cancel dates - All or none

            Database.update(ropRecords, true); // Mark ROPs as processed - All or none

        } Catch(Exception e){

            Database.rollback(sp);

            Database.releaseSavepoint(sp);

            QDX_LOG.error('Error while processing ROP Allocation: ' + e.getMessage() +

                          ' | Line Number: ' + e.getLineNumber());

            throw e;

        } finally {

            QDX_LOG.publish();

        }

    }



    /**

* @description Separated logic to sum Allocation amounts based on Custom Metadata 

* and update the related InsurancePolicy records dynamically.

*/

    public static void updateContractAllocationFields(Map<Id, InsurancePolicy> contractsMap) {

        if (contractsMap == null || contractsMap.isEmpty()) return;



        // 1. Fetch metadata mapping

        List<ContractFundingAllocationFieldMapping__mdt> mappings = [

            SELECT Contract_Field_API__c, Descriptor__c 

            FROM ContractFundingAllocationFieldMapping__mdt 

            WHERE Descriptor__c != NULL

        ];



        if (mappings.isEmpty()) return;



        // 2. Aggregate Allocation amounts by Contract and Descriptor

        Map<Id, Map<String, Decimal>> allocSumsByContract = new Map<Id, Map<String, Decimal>>();



        for (AggregateResult ar : [

            SELECT Contract__c cId, Descriptor__c descr, SUM(Allocation_Amount__c) total

            FROM Allocation__c

            WHERE Contract__c IN :contractsMap.keySet()

            GROUP BY Contract__c, Descriptor__c

        ]) {

            Id cId = (Id) ar.get('cId');

            String descr = (String) ar.get('descr');

            Decimal total = (Decimal) ar.get('total');



            if (!allocSumsByContract.containsKey(cId)) {

                allocSumsByContract.put(cId, new Map<String, Decimal>());

            }

            allocSumsByContract.get(cId).put(descr, total);

        }



        // 3. Update the contract records dynamically

        for (InsurancePolicy contract : contractsMap.values()) {

            Map<String, Decimal> descriptorTotals = allocSumsByContract.get(contract.Id);



            for (ContractFundingAllocationFieldMapping__mdt mapping : mappings) {

                String targetField = mapping.Contract_Field_API__c;

                String descriptor = mapping.Descriptor__c;



                Decimal totalAmount = 0;

                if (descriptorTotals != null && descriptorTotals.containsKey(descriptor)) {

                    totalAmount = descriptorTotals.get(descriptor);

                }



                // 🔥 FIX: Centralized rounding (future-proof)

                contract.put(

                    targetField,

                    roundCurrency(totalAmount)

                );



            }

            Decimal reserveAmount = 0;

            if (descriptorTotals != null && descriptorTotals.containsKey('Reserve')) {

                reserveAmount = descriptorTotals.get('Reserve');

            }



            // 🔥 FIX: Apply rounding here as well

            contract.Funded_Reserve__c = roundCurrency(reserveAmount);

        }



        // Note: No Database.update() is needed here because processContracts 

        // already runs Database.update(contractsByContractId.values(), true); right after this!

    }



}