/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-14-2024
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
global class DataLoadContractsBatch implements Database.Batchable<sObject> {
    
    global Database.QueryLocator start(Database.BatchableContext BC) 
    {
        return Database.getQueryLocator('SELECT Id, Name, NetClaim__c, Claim_Amount_Paid__c, Parts_Cost__c, Labor_Cost__c, Other_Cost__c, Total_Tax__c, Applied_Deductible__c, PolicyNumberId, PolicyNumber.Coverage_Level__c FROM Claim ');
    }
    
    global void execute(Database.BatchableContext BC, List<Claim> claimList) 
    {
        Set<String> claimIdSet = new Set<String>();
        Map<String,Claim> claimMap = new Map<String,Claim>();
        Set<Id> coverageLevelSet = new Set<Id>();
        Map<Id,Id> claimIdWithCoverageLevelMap = new Map<Id,Id>();
        
        for(Claim cl : claimList) {
            claimMap.put(cl.Id,cl);
            claimIdSet.add(cl.Id);
            if(cl.PolicyNumberId!=null&&cl.PolicyNumber.Coverage_Level__c!=null) {
                coverageLevelSet.add(cl.PolicyNumber.Coverage_Level__c);
                claimIdWithCoverageLevelMap.put(cl.Id,cl.PolicyNumber.Coverage_Level__c);
            }
        }
        
        List<ClaimItem> claimItems = [
            SELECT Id, Name, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, Description, 
            ClaimId, quantity__c, rate__c, tax_new__c, detail_type__c, part_number__c, allocation_number__c, 
            payee_name__c, payee_number__c, parts__c, labor__c, sublet__c, towing__c, rental__c, tax__c, 
            deductible__c, status__c, reason__c, payment__c, subtotal__c, netclaim__c, wex__c, 
            Loss_Description__c, loss_category__c, paid_date__c, paid_by__c, processed_parts__c, processed_labor__c, 
            repair_shop_account_name__c, payment_allocation_confirmed_time__c, last_wex_error__c, claim_type__c, 
            adjustment__c, invoice_number__c, Claim.Parts_Tax_Rate__c, Claim.Labor_Tax_Rate__c
            FROM ClaimItem 
            Where ClaimId in :claimIdSet and Detail_Type__c = null];
            
        
        Set<Id> lossDescriptionIdSet = new Set<Id>();
        for(ClaimItem ci : claimItems) {
            if(ci.Loss_Description__c!=null){
            	lossDescriptionIdSet.add(ci.Loss_Description__c);    
            }
        }
        
        List<Coverage_Level_Detail__c> coverageDetailList = [Select Id, Name, Coverage_Level__c, Loss_Component__c from Coverage_Level_Detail__c Where Coverage_Level__c IN :coverageLevelSet and Loss_Component__c IN :lossDescriptionIdSet];
        Map<String,Coverage_Level_Detail__c> coverageDetailMap = new Map<String,Coverage_Level_Detail__c>();
        for(Coverage_Level_Detail__c detail : coverageDetailList) {
            if(detail.Coverage_Level__c!=null && detail.Loss_Component__c!=null){
                String key = detail.Coverage_Level__c +'-'+detail.Loss_Component__c;
                coverageDetailMap.put(key,detail);
            }
        }
        
        Map<Id,Double> claimWithNetClaim = new Map<Id,Double>();
        Map<Id,Double> paidClaimWithNetClaim = new Map<Id,Double>();
        Map<Id,Double> partsCost = new Map<Id,Double>();
        Map<Id,Double> laborCost = new Map<Id,Double>();
        Map<Id,Double> otherCost = new Map<Id,Double>();
        Map<Id,Double> totalTax = new Map<Id,Double>();
        Map<Id,Double> appliedDeductible = new Map<Id,Double>();
        Map<Id,Integer> claimWithMaxJobNumber = new Map<Id,Integer>();
        List<ClaimItem> newClaimItems = new List<ClaimItem>();

        for (ClaimItem oldClaimItem : claimItems) {
			String coverageKey = claimIdWithCoverageLevelMap.containsKey(oldClaimItem.ClaimId)&&oldClaimItem.Loss_Description__c!=null?claimIdWithCoverageLevelMap.get(oldClaimItem.ClaimId)+'-'+oldClaimItem.Loss_Description__c:null;
            if(!claimWithMaxJobNumber.containsKey(oldClaimItem.ClaimId)) {
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,1);
            } else {
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
            }
            
            Integer jobNumber = claimWithMaxJobNumber.get(oldClaimItem.ClaimId);
            
            boolean isPartsNull = false;
            // Process Parts__c
            if (oldClaimItem.Parts__c != null && oldClaimItem.Parts__c != 0) {
                ClaimItem partClaim = new ClaimItem();
                setGenericFieldsOnNewClaimItem(oldClaimItem,partClaim,jobNumber);
                partClaim.Rate__c = oldClaimItem.Parts__c!=null?oldClaimItem.Parts__c:0;
                partClaim.Detail_Type__c = 'Part';
                partClaim.Tax__c = oldClaimItem.Tax__c!=null?oldClaimItem.Tax__c:0; // Retain Tax__c if applicable
                partClaim.deductible__c = oldClaimItem.deductible__c!=null?oldClaimItem.deductible__c:0; 
                partClaim.Adjustment__c = oldClaimItem.Adjustment__c!=null?oldClaimItem.Adjustment__c:0;
                partClaim.Coverage_Level_Detail__c = coverageDetailMap.containsKey(coverageKey)?coverageDetailMap.get(coverageKey).Id:null;
                newClaimItems.add(partClaim);
                if(!partsCost.containsKey(oldClaimItem.ClaimId)) {
                    partsCost.put(oldClaimItem.ClaimId,0);
                }
                partsCost.put(oldClaimItem.ClaimId, partsCost.get(oldClaimItem.ClaimId) + ((partClaim.Quantity__c * partClaim.Rate__c) + partClaim.Adjustment__c));
                // Calculate the New Tax formula: (Quantity__c * Rate__c * Claim.Parts_Tax_Rate__c) + Tax__c
                Decimal tax = (partClaim.Quantity__c * partClaim.Rate__c * (oldClaimItem.Claim.Parts_Tax_Rate__c!=null?oldClaimItem.Claim.Parts_Tax_Rate__c:0)) + partClaim.Tax__c;
                if(!totalTax.containsKey(oldClaimItem.ClaimId)) {
                    totalTax.put(oldClaimItem.ClaimId,0);
                }
                totalTax.put(oldClaimItem.ClaimId, totalTax.get(oldClaimItem.ClaimId) + tax);
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
                jobNumber++;
            } else {
                isPartsNull = true;
            }

            // Process Labor__c
            if (oldClaimItem.Labor__c != null && oldClaimItem.Labor__c != 0) {
                ClaimItem laborClaim = new ClaimItem();
                setGenericFieldsOnNewClaimItem(oldClaimItem,laborClaim,jobNumber);
                laborClaim.Rate__c = oldClaimItem.Labor__c!=null?oldClaimItem.Labor__c:0;
                laborClaim.Detail_Type__c = 'Labor';
                laborClaim.Tax__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && oldClaimItem.Tax__c!=null) ? oldClaimItem.Tax__c : 0; // Retain Tax__c if Parts__c is null
                laborClaim.deductible__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && oldClaimItem.deductible__c!=null) ? oldClaimItem.deductible__c : 0; // Retain deductible__c if Parts__c is null
                laborClaim.Adjustment__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && oldClaimItem.Adjustment__c!=null) ? oldClaimItem.Adjustment__c : 0; 
                laborClaim.Processed_Parts__c = oldClaimItem.Processed_Labor__c; // Migrate Processed_Labor__c to Processed_Parts__c
                laborClaim.Coverage_Level_Detail__c = coverageDetailMap.containsKey(coverageKey)?coverageDetailMap.get(coverageKey).Id:null;
                newClaimItems.add(laborClaim);
                if(!laborCost.containsKey(oldClaimItem.ClaimId)) {
                    laborCost.put(oldClaimItem.ClaimId,0);
                }
                laborCost.put(oldClaimItem.ClaimId, laborCost.get(oldClaimItem.ClaimId) + ((laborClaim.Quantity__c * laborClaim.Rate__c) + laborClaim.Adjustment__c));
                // Calculate the New Tax formula: (Quantity__c * Rate__c * Claim.Labor_Tax_Rate__c) + Tax__c
                Decimal tax = (laborClaim.Quantity__c * laborClaim.Rate__c * (oldClaimItem.Claim.Labor_Tax_Rate__c!=null?oldClaimItem.Claim.Labor_Tax_Rate__c:0)) + laborClaim.Tax__c;
                if(!totalTax.containsKey(oldClaimItem.ClaimId)) {
                    totalTax.put(oldClaimItem.ClaimId,0);
                }
                totalTax.put(oldClaimItem.ClaimId, totalTax.get(oldClaimItem.ClaimId) + tax);
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
                jobNumber++;
            }

            // Process Sublet__c
            if (oldClaimItem.Sublet__c != null && oldClaimItem.Sublet__c != 0) {
                ClaimItem subletClaim = new ClaimItem();
                setGenericFieldsOnNewClaimItem(oldClaimItem,subletClaim,jobNumber);
                subletClaim.Rate__c = oldClaimItem.Sublet__c!=null?oldClaimItem.Sublet__c:0;
                subletClaim.Detail_Type__c = 'Sublet';
                subletClaim.Tax__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && oldClaimItem.Tax__c!=null) ? oldClaimItem.Tax__c : 0; // Retain Tax__c if Parts__c is null
                subletClaim.deductible__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && oldClaimItem.deductible__c!=null) ? oldClaimItem.deductible__c : 0; // Retain deductible__c if Parts__c is null
                subletClaim.Adjustment__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && oldClaimItem.Adjustment__c!=null) ? oldClaimItem.Adjustment__c : 0; 
                subletClaim.Coverage_Level_Detail__c = coverageDetailMap.containsKey(coverageKey)?coverageDetailMap.get(coverageKey).Id:null;
                newClaimItems.add(subletClaim);
                if(!otherCost.containsKey(oldClaimItem.ClaimId)) {
                    otherCost.put(oldClaimItem.ClaimId,0);
                }
                otherCost.put(oldClaimItem.ClaimId, otherCost.get(oldClaimItem.ClaimId) + ((subletClaim.Quantity__c * (subletClaim.Rate__c!=null?subletClaim.Rate__c:0)) + subletClaim.Adjustment__c));
                if(!totalTax.containsKey(oldClaimItem.ClaimId)) {
                    totalTax.put(oldClaimItem.ClaimId,0);
                }
                totalTax.put(oldClaimItem.ClaimId, totalTax.get(oldClaimItem.ClaimId) + subletClaim.Tax__c);
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
                jobNumber++;
            }

            // Process Towing__c
            if (oldClaimItem.Towing__c != null && oldClaimItem.Towing__c != 0) {
                ClaimItem towingClaim = new ClaimItem();
                setGenericFieldsOnNewClaimItem(oldClaimItem,towingClaim,jobNumber);
                towingClaim.Rate__c = oldClaimItem.Towing__c!=null?oldClaimItem.Towing__c:0;
                towingClaim.Detail_Type__c = 'Towing';
                towingClaim.Tax__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && oldClaimItem.Tax__c!=null) ? oldClaimItem.Tax__c : 0; // Retain Tax__c if Parts__c is null
                towingClaim.deductible__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && oldClaimItem.deductible__c!=null) ? oldClaimItem.deductible__c : 0; // Retain deductible__c if Parts__c is null
                towingClaim.Adjustment__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && oldClaimItem.Adjustment__c!=null) ? oldClaimItem.Adjustment__c : 0; 
                towingClaim.Coverage_Level_Detail__c = coverageDetailMap.containsKey(coverageKey)?coverageDetailMap.get(coverageKey).Id:null;
                newClaimItems.add(towingClaim);
                if(!otherCost.containsKey(oldClaimItem.ClaimId)) {
                    otherCost.put(oldClaimItem.ClaimId,0);
                }
                otherCost.put(oldClaimItem.ClaimId, otherCost.get(oldClaimItem.ClaimId) + ((towingClaim.Quantity__c * (towingClaim.Rate__c!=null?towingClaim.Rate__c:0)) + towingClaim.Adjustment__c));
                if(!totalTax.containsKey(oldClaimItem.ClaimId)) {
                    totalTax.put(oldClaimItem.ClaimId,0);
                }
                totalTax.put(oldClaimItem.ClaimId, totalTax.get(oldClaimItem.ClaimId) + towingClaim.Tax__c);
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
                jobNumber++;
            }

            // Process Rental__c
            if (oldClaimItem.Rental__c != null && oldClaimItem.Rental__c != 0) {
                ClaimItem rentalClaim = new ClaimItem();
                setGenericFieldsOnNewClaimItem(oldClaimItem,rentalClaim,jobNumber);
                rentalClaim.Rate__c = oldClaimItem.Rental__c!=null?oldClaimItem.Rental__c:0;
                rentalClaim.Detail_Type__c = 'Rental';
                rentalClaim.Tax__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && (oldClaimItem.Towing__c == null || oldClaimItem.Towing__c == 0) && oldClaimItem.Tax__c!=null) ? oldClaimItem.Tax__c : 0; // Retain Tax__c if Parts__c is null
                rentalClaim.deductible__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && (oldClaimItem.Towing__c == null || oldClaimItem.Towing__c == 0) && oldClaimItem.deductible__c!=null) ? oldClaimItem.deductible__c : 0; // Retain deductible__c if Parts__c is null
                rentalClaim.Adjustment__c = ( (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && (oldClaimItem.Towing__c == null || oldClaimItem.Towing__c == 0) && oldClaimItem.Adjustment__c!=null) ? oldClaimItem.Adjustment__c : 0; 
                rentalClaim.Coverage_Level_Detail__c = coverageDetailMap.containsKey(coverageKey)?coverageDetailMap.get(coverageKey).Id:null;
                newClaimItems.add(rentalClaim);
                if(!otherCost.containsKey(oldClaimItem.ClaimId)) {
                    otherCost.put(oldClaimItem.ClaimId,0);
                }
                otherCost.put(oldClaimItem.ClaimId, otherCost.get(oldClaimItem.ClaimId) + ((rentalClaim.Quantity__c * (rentalClaim.Rate__c!=null?rentalClaim.Rate__c:0)) + rentalClaim.Adjustment__c));
                if(!totalTax.containsKey(oldClaimItem.ClaimId)) {
                    totalTax.put(oldClaimItem.ClaimId,0);
                }
                totalTax.put(oldClaimItem.ClaimId, totalTax.get(oldClaimItem.ClaimId) + rentalClaim.Tax__c);
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
                jobNumber++;
            }
            
            //if all are none and tax is there then create other CI
            if (((oldClaimItem.Tax__c != null && oldClaimItem.Tax__c != 0) || (oldClaimItem.deductible__c != null && oldClaimItem.deductible__c != 0) || (oldClaimItem.Adjustment__c != null && oldClaimItem.Adjustment__c != 0)) && (oldClaimItem.Parts__c == null || oldClaimItem.Parts__c == 0) && (oldClaimItem.Labor__c == null || oldClaimItem.Labor__c == 0) && (oldClaimItem.Sublet__c == null || oldClaimItem.Sublet__c == 0) && (oldClaimItem.Towing__c == null || oldClaimItem.Towing__c == 0) && (oldClaimItem.Rental__c == null || oldClaimItem.Rental__c == 0)) {
                ClaimItem otherClaim = new ClaimItem();
                setGenericFieldsOnNewClaimItem(oldClaimItem,otherClaim,jobNumber);
                otherClaim.Detail_Type__c = 'Other';
                otherClaim.Tax__c = oldClaimItem.Tax__c!=null?oldClaimItem.Tax__c:0;
                otherClaim.deductible__c = oldClaimItem.deductible__c!=null?oldClaimItem.deductible__c:0;
                otherClaim.Adjustment__c = oldClaimItem.Adjustment__c!=null?oldClaimItem.Adjustment__c:0; 
                otherClaim.Coverage_Level_Detail__c = coverageDetailMap.containsKey(coverageKey)?coverageDetailMap.get(coverageKey).Id:null;
                newClaimItems.add(otherClaim);
                if(!otherCost.containsKey(oldClaimItem.ClaimId)) {
                    otherCost.put(oldClaimItem.ClaimId,0);
                }
                otherCost.put(oldClaimItem.ClaimId, otherCost.get(oldClaimItem.ClaimId) + ((otherClaim.Quantity__c * (otherClaim.Rate__c!=null?otherClaim.Rate__c:0)) + otherClaim.Adjustment__c));
                if(!totalTax.containsKey(oldClaimItem.ClaimId)) {
                    totalTax.put(oldClaimItem.ClaimId,0);
                }
                totalTax.put(oldClaimItem.ClaimId, totalTax.get(oldClaimItem.ClaimId) + otherClaim.Tax__c);
                claimWithMaxJobNumber.put(oldClaimItem.ClaimId,claimWithMaxJobNumber.get(oldClaimItem.ClaimId)+1);
                jobNumber++;
            }
            
            // Applied Deductible Calculation
            if(!appliedDeductible.containsKey(oldClaimItem.ClaimId)) {
                    appliedDeductible.put(oldClaimItem.ClaimId,0);
            }
            if (oldClaimItem.Detail_Type__c==null || oldClaimItem.Detail_Type__c != 'Deductible') {
                //Probably this would always be empty, but added cond as it is specified in the requirements.
                appliedDeductible.put(oldClaimItem.ClaimId, appliedDeductible.get(oldClaimItem.ClaimId) + (oldClaimItem.Deductible__c!=null?oldClaimItem.Deductible__c:0) );
            } else {
                appliedDeductible.put(oldClaimItem.ClaimId, appliedDeductible.get(oldClaimItem.ClaimId) + (oldClaimItem.Subtotal__c!=null?oldClaimItem.Subtotal__c:0) );
            }
        }

        
        Savepoint sp = Database.setSavepoint();
        try {
            // Insert new ClaimItem records and track the success    
            if (!newClaimItems.isEmpty()) {
                Database.insert(newClaimItems, true); // All or none
                // If new records are created, delete the old records
                Database.delete(claimItems, true); // All or none
                
                List<ClaimItem> claimItemsToGetNetClaim = [SELECT Id, ClaimId, NetClaim__c, Status__c FROM ClaimItem WHERE Id in :newClaimItems];
                for(ClaimItem ci : claimItemsToGetNetClaim){
                    if(claimWithNetClaim.containsKey(ci.ClaimId) && ci.NetClaim__c != null){
                        claimWithNetClaim.put(ci.ClaimId,claimWithNetClaim.get(ci.ClaimId)+ci.NetClaim__c);
                    } else {
                        claimWithNetClaim.put(ci.ClaimId,ci.NetClaim__c);
                    }
                    
                    if(ci.Status__c=='Paid'){
                        if(paidClaimWithNetClaim.containsKey(ci.ClaimId) && ci.NetClaim__c != null){
                            paidClaimWithNetClaim.put(ci.ClaimId,paidClaimWithNetClaim.get(ci.ClaimId)+ci.NetClaim__c);
                        } else {
                            paidClaimWithNetClaim.put(ci.ClaimId,ci.NetClaim__c);
                        }
                    }
                }
                for(Id cl : claimMap.keySet()) {
                    if(partsCost.containsKey(cl)) {
                        claimMap.get(cl).Parts_Cost__c = partsCost.get(cl);
                    }
                    if(laborCost.containsKey(cl)) {
                        claimMap.get(cl).Labor_Cost__c = laborCost.get(cl);
                    }
                    if(otherCost.containsKey(cl)) {
                        claimMap.get(cl).Other_Cost__c = otherCost.get(cl);
                    }
                    if(totalTax.containsKey(cl)) {
                        claimMap.get(cl).Total_Tax__c = totalTax.get(cl);
                    }
                    if(appliedDeductible.containsKey(cl)) {
                        claimMap.get(cl).Applied_Deductible__c = appliedDeductible.get(cl);
                    }
                    if(claimWithNetClaim.containsKey(cl)) {
                        claimMap.get(cl).NetClaim__c = claimWithNetClaim.get(cl); 
                    }
                    if(paidClaimWithNetClaim.containsKey(cl)){
                        claimMap.get(cl).Claim_Amount_Paid__c = paidClaimWithNetClaim.get(cl); 
                    }
                }
                Database.update(claimMap.values(), true); // All or none
            } 
        } catch (DmlException e) {
            Database.rollback(sp);
            Database.releaseSavepoint(sp);
            QDX_LOG.error('Error while processing ClaimItems: ' + e.getMessage());
        } finally {
            QDX_LOG.publish();
        }
    }
    
    global void finish(Database.BatchableContext BC) {  }
    
    public void setGenericFieldsOnNewClaimItem(ClaimItem oldCI, ClaimItem newCI, Integer jobNumber) {
        newCI.Name = oldCI.Name;
        newCI.Job_Number__c = String.valueOf(jobNumber);
        newCI.CreatedDate = oldCI.CreatedDate;
        newCI.CreatedById = oldCI.CreatedById;
        newCI.LastModifiedDate = oldCI.LastModifiedDate;
        newCI.LastModifiedById = oldCI.LastModifiedById;
        newCI.Description = oldCI.Description;
        newCI.ClaimId = oldCI.ClaimId;
        newCI.quantity__c = 1;
        newCI.part_number__c = oldCI.part_number__c;
        newCI.allocation_number__c = oldCI.allocation_number__c;
        newCI.payee_name__c = oldCI.payee_name__c;
        newCI.status__c = oldCI.status__c;
        newCI.reason__c = oldCI.reason__c;
        newCI.payment__c = oldCI.payment__c;
        newCI.wex__c = oldCI.wex__c;
        newCI.loss_description__c = oldCI.loss_description__c;
        newCI.paid_date__c = oldCI.paid_date__c;
        newCI.paid_by__c = oldCI.paid_by__c;
        newCI.processed_parts__c = oldCI.processed_parts__c;
        newCI.payment_allocation_confirmed_time__c = oldCI.payment_allocation_confirmed_time__c;
        newCI.last_wex_error__c = oldCI.last_wex_error__c;
        newCI.claim_type__c = oldCI.claim_type__c;
        newCI.invoice_number__c = oldCI.invoice_number__c;
    }
}