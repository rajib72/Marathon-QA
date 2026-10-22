/**
* @author: Saurabh Rawat
* @dateModified: 2024-07-16
* @description: This class manages the Payment record creation on the Claim Item status
*/
public WITHOUT SHARING class ClaimItemTriggerHandler {
    
    /**
* Function for handling actions before insert Trigger
*/    
    public static void handleBeforeInsert(List<ClaimItem> newClaims){
        setRateForLaborType(newClaims);
        updateClaimItem(newClaims);
        updateDeductibleDetails(newClaims);
        
    }
    
    /**
* Function for handling actions before update Trigger
*/    
    public static void handleBeforeUpdate(Map<Id,ClaimItem> oldMap, List<ClaimItem> newClaims){
        validateInvoiceNumberForAuthorizedStatus(newClaims);
        createPaymentRecord(oldMap,newClaims);
        updateClaimItem(newClaims);
    }
    
    /**
* Function for handling actions after update Trigger
*/     
    public static void handleAfterUpdate(
        Map<Id,ClaimItem> oldMap,
        List<ClaimItem> newClaims
    ){
        System.debug('called claim item trigger handler (handler) after update');
        
        updateClaimStatus(oldMap, newClaims);
        updateClaimRollupFields(oldMap, newClaims);
        updateAppliedDeductibleOnClaim(oldMap,newClaims);
        updateApprovedAmountOnClaim(oldMap, newClaims);

        //added by Joyita Sarkar 19.8.26
    generateAuthorizationNumber(oldMap, newClaims);
        
    }
    
    /**
* Function for handling actions after insert Trigger
*/     
    public static void handleAfterInsert(List<ClaimItem> newClaims){
        System.debug('called claim item trigger handler after insert');
        updateClaimRollupFields(NULL, newClaims);
        updateAppliedDeductibleOnClaim(NULL,newClaims);
         updateApprovedAmountOnClaim(NULL, newClaims);
    }
    
    /**commented by Joyita
* create payment record for updated claimItems

public static void createPaymentRecord(Map<Id,ClaimItem> oldMap,List<ClaimItem> claimItems){
try{
Set<Id> claimIdSet = new Set<Id>();
Map<String,ClaimItem> existingPayments = new Map<String,ClaimItem>();
Map<String,List<ClaimItem>> payeeClaimItems = new Map<String,List<ClaimItem>>();
Map<String,Payment__c> payeePayments = new Map<String,Payment__c>();
List<Payment__c> paymentsToInsert = new List<Payment__c>();
List<ClaimItem> itemsToUpdate = new List<ClaimItem>();
//Filtering ClaimItems with Wex__c  = true and Status = Approved to Pay and status is changed
for(ClaimItem ci : claimItems){
if(ci.Wex__c == false && (ci.Status__c == 'Approved to Pay' || ci.Status__c == 'Paid') && oldMap.get(ci.Id).Status__c != ci.Status__c){
claimIdSet.add(ci.ClaimId);
itemsToUpdate.add(ci);
}
}
if(itemsToUpdate.size() > 0){
List<ClaimItem> fetchedClaimItems = new List<ClaimItem>();
fetchedClaimItems= [SELECT Id, ClaimId, Payee_Name__c, Wex__c, Payment__c,Status__c FROM ClaimItem WHERE ClaimId IN :claimIdSet AND Wex__c = false AND Payment__c!=null];
//Creating Map of Exsiting Payee with Claim Id along with their ClaimItem details for Payment
for(ClaimItem each : fetchedClaimItems){
if(String.isNotBlank(each.Payee_Name__c)){
existingPayments.put(each.ClaimId+''+each.Payee_Name__c,each);    
}

}
//Grouping ClaimItems with the PayeeName 
for(ClaimItem each : itemsToUpdate){
if(String.isNotBlank(each.Payee_Name__c)){
List<ClaimItem> tempItems = payeeClaimItems.containsKey(each.Payee_Name__c)?payeeClaimItems.get(each.Payee_Name__c):new List<ClaimItem>();
tempItems.add(each);
payeeClaimItems.put(each.Payee_Name__c,tempItems);
}else{
List<ClaimItem> tempItems = payeeClaimItems.containsKey('none')?payeeClaimItems.get('none'):new List<ClaimItem>();
tempItems.add(each);
payeeClaimItems.put('none',tempItems);
}
}
//Attaching Old Payment or New Payment record as per the existing mapping of PayeeName
for(String payeeId :payeeClaimItems.keyset()){
if(payeeId != 'none'){
String uniqueKey = payeeClaimItems.get(payeeId).get(0).ClaimId + payeeId;
Payment__c newPayment  = new Payment__c();
newPayment.Account__c = payeeId;
if(existingPayments.containsKey(uniqueKey)){
newPayment.Id = existingPayments.get(uniqueKey).Payment__c;
}else{
paymentsToInsert.add(newPayment);
}    


payeePayments.put(uniqueKey,newPayment);
} 
}

if(paymentsToInsert.size() > 0){
database.insert(paymentsToInsert);
}
//Updating ClaimItems with the existing or new Payment Records
for(ClaimItem eachItem : itemsToUpdate){

eachItem.Payment__c = (String.isNotBlank(eachItem.Payee_Name__c) && payeePayments.containsKey(eachItem.ClaimId + ''+eachItem.Payee_Name__c))
?payeePayments.get(eachItem.ClaimId + ''+eachItem.Payee_Name__c).Id:null;

}
}
}catch(Exception e){
QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
QDX_Log.publish();
}
} */
    
    
    /**Added by Joyita 4.8.2026
* Create Payment records for Claim Items whose Status changes
* to Approved to Pay or Paid.
*
* Logic:
* 1. Claim Items becoming Paid in the SAME transaction
*    with the SAME Claim + Payee share ONE new Payment.
*
* 2. Claim Items for the SAME Payee that were paid in a
*    PREVIOUS transaction must NOT reuse the previous Payment.
*
* 3. This allows the same Payee to have multiple Payment records
*    when Claim Items are paid at different times.
*/
    public static void createPaymentRecord(
        Map<Id, ClaimItem> oldMap,
        List<ClaimItem> claimItems
    ) {
        
        try {
            
            Set<Id> claimIdSet = new Set<Id>();
            
            /*
* Stores Claim Items whose status changed to
* Approved to Pay or Paid in the CURRENT transaction.
*/
            List<ClaimItem> itemsToUpdate =
                new List<ClaimItem>();
            
            /*
* Groups current transaction Claim Items by:
*
* Claim Id + Payee
*
* Example:
*
* Claim A + Payee X
*     -> Claim Item 1
*     -> Claim Item 2
*
* Both will receive the SAME Payment.
*/
            Map<String, List<ClaimItem>> currentTransactionItems =
                new Map<String, List<ClaimItem>>();
            
            /*
* Payment records created in THIS transaction.
*
* Key:
* Claim Id + Payee
*/
            Map<String, Payment__c> currentTransactionPayments =
                new Map<String, Payment__c>();
            
            List<Payment__c> paymentsToInsert =
                new List<Payment__c>();
            
            
            /*
* STEP 1
*
* Identify only Claim Items whose Status changed
* in the current transaction.
*/
            for (ClaimItem ci : claimItems) {
                
                if (
                    ci.Wex__c == false &&
                    (
                        ci.Status__c == 'Approved to Pay' ||
                        ci.Status__c == 'Paid'
                    ) &&
                    oldMap.containsKey(ci.Id) &&
                    oldMap.get(ci.Id).Status__c != ci.Status__c
                ) {
                     //Payment Generation Issues with Customer Reimbursements/Check Payments start//
                    if (ci.Payment__c != null) {
    continue;
}
////Payment Generation Issues with Customer Reimbursements/Check Payments end//
                    
                    claimIdSet.add(ci.ClaimId);
                    
                    itemsToUpdate.add(ci);
                }
            }
            
            
            /*
* Nothing to process.
*/
            if (itemsToUpdate.isEmpty()) {
                return;
            }
            
            
            /*
* STEP 2
*
* Group ONLY the Claim Items being processed
* in the CURRENT transaction.
*
* We intentionally DO NOT query existing Payment__c
* records here.
*
* This is the key fix.
*/
            for (ClaimItem ci : itemsToUpdate) {
                
                if (ci.ClaimId == null) {
                    continue;
                }
                
                String payeeKey;
                
                if (String.isNotBlank(ci.Payee_Name__c)) {
                    
                    payeeKey =
                        String.valueOf(ci.ClaimId) +
                        '|' +
                        ci.Payee_Name__c;
                    
                } else {
                    
                    payeeKey =
                        String.valueOf(ci.ClaimId) +
                        '|none';
                }
                
                
                /*
* Get the existing group for this transaction.
*/
                List<ClaimItem> groupedItems;
                
                if (currentTransactionItems.containsKey(payeeKey)) {
                    
                    groupedItems =
                        currentTransactionItems.get(payeeKey);
                    
                } else {
                    
                    groupedItems =
                        new List<ClaimItem>();
                }
                
                
                /*
* Add current Claim Item to the group.
*/
                groupedItems.add(ci);
                
                currentTransactionItems.put(
                    payeeKey,
                    groupedItems
                );
            }
            
            
            /*
* STEP 3
*
* Create ONE NEW Payment record per
* Claim + Payee group in THIS transaction.
*
* IMPORTANT:
*
* We do NOT check whether a previous Payment
* already exists for this Claim + Payee.
*
* Therefore:
*
* Previous transaction:
* Payee A -> Payment P001
*
* New transaction:
* Payee A -> Payment P002
*
* This is the required behavior.
*/
            for (String payeeKey : currentTransactionItems.keySet()) {
                
                List<ClaimItem> groupedItems =
                    currentTransactionItems.get(payeeKey);
                
                if (
                    groupedItems == null ||
                    groupedItems.isEmpty()
                ) {
                    continue;
                }
                
                
                ClaimItem firstItem =
                    groupedItems.get(0);
                
                
                /*
* Do not create Payment for Claim Items
* without a Payee.
*
* Existing behavior preserved.
*/
                if (String.isBlank(firstItem.Payee_Name__c)) {
                    continue;
                }
                
                
                /*
* Create a BRAND NEW Payment.
*/
                Payment__c newPayment =
                    new Payment__c();
                
                newPayment.Account__c =
                    firstItem.Payee_Name__c;
                
                
                /*
* Add to insert list.
*/
                paymentsToInsert.add(newPayment);
                
                
                /*
* Keep reference so all Claim Items
* in this transaction group can be linked
* to the same Payment after insert.
*/
                currentTransactionPayments.put(
                    payeeKey,
                    newPayment
                );
            }
            
            
            /*
* STEP 4
*
* Insert all newly created Payment records.
*
* Salesforce will generate the Payment Number
* through the Payment Name / Auto Number logic.
*/
            if (!paymentsToInsert.isEmpty()) {
                
                Database.insert(
                    paymentsToInsert,
                    false
                );
            }
            
            
            /*
* STEP 5
*
* Link each Claim Item being processed
* to the NEW Payment created for the
* current transaction.
*/
            for (ClaimItem ci : itemsToUpdate) {
                
                if (ci.ClaimId == null) {
                    continue;
                }
                
                
                String payeeKey;
                
                if (String.isNotBlank(ci.Payee_Name__c)) {
                    
                    payeeKey =
                        String.valueOf(ci.ClaimId) +
                        '|' +
                        ci.Payee_Name__c;
                    
                } else {
                    
                    payeeKey =
                        String.valueOf(ci.ClaimId) +
                        '|none';
                }
                
                
                /*
* Get the Payment created for
* this current transaction group.
*/
                if (
                    currentTransactionPayments.containsKey(
                        payeeKey
                    )
                ) {
                    
                    Payment__c payment =
                        currentTransactionPayments.get(
                            payeeKey
                        );
                    
                    
                    /*
* Only link if Payment was successfully inserted.
*/
                    if (payment.Id != null) {
                        
                        ci.Payment__c =
                            payment.Id;
                    }
                }
            }
            
            
        } catch (Exception e) {
            
            QDX_Log.error(
                'Exception Occurred: ' +
                e.getMessage() +
                ' Line Number: ' +
                e.getLineNumber()
            );
            
            QDX_Log.publish();
        }
    }
    /**
* Update Parent claim status if all claim items are Paid, Denied, Cancelled, Closed
*/    
    public static void updateClaimStatus(Map<Id,ClaimItem> oldMap, List<ClaimItem> claimItems){
        try{
            List<String> statusCheckList = new List<String>{'Paid','Denied','Cancelled','Closed'};
                Set<Id> claimIdSet = new Set<Id>();
            Map<Id,Boolean> claimStatusCount = new Map<Id,Boolean>();
            Map<Id,Boolean> claimMasterStatusCount = new Map<Id,Boolean>();
            List<Claim> claimToUpdate = new List<Claim>();
            List<ClaimItem> fetchedClaimItems = new List<ClaimItem>();
            for(ClaimItem ci : claimItems){
                if(ci.Status__c != oldMap.get(ci.Id).Status__c){
                    claimIdSet.add(ci.ClaimId);    
                }
                
            }
            if(claimIdSet.size() > 0){
                fetchedClaimItems= [SELECT Id, ClaimId, Payee_Name__c, Wex__c, Payment__c,Status__c, Loss_Type__c FROM ClaimItem WHERE ClaimId IN :claimIdSet];
                
                for(ClaimItem eachItem : fetchedClaimItems){
                    Boolean isStatusCountMatch = claimStatusCount.containsKey(eachItem.ClaimId) && claimStatusCount.get(eachItem.ClaimId) == true && statusCheckList.contains(eachItem.Status__c) ? true :
                    (!claimStatusCount.containsKey(eachItem.ClaimId) && statusCheckList.contains(eachItem.Status__c) ) ?true : false  ;
                    if(eachItem.Status__c == 'Paid' && eachItem.Loss_Type__c != NULL && eachItem.Loss_Type__c != 'Inspection'){
                        claimMasterStatusCount.put(eachItem.ClaimId,true); 
                    }
                    claimStatusCount.put(eachItem.ClaimId,isStatusCountMatch);   
                    
                }
                for(String claimId : claimStatusCount.keyset()){
                    if(claimStatusCount.get(claimId) == true && claimMasterStatusCount.containsKey(claimId) && claimMasterStatusCount.get(claimId) == true){
                        Claim updateClaim = new Claim();
                        updateClaim.Id = claimId;
                        updateClaim.Status = 'Paid';
                        claimToUpdate.add(updateClaim);
                    }
                }
                
                if(claimToUpdate.size() > 0){
                    updateClaim(JSON.serialize(claimToUpdate));
                }
            }
        }catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
        }
    }
    @future
    public static void updateClaim(String jsonString){
        try{
            if(String.isNotBlank(jsonString)){
                List<Claim> claims = (List<Claim>)JSON.deserialize(jsonString,List<Claim>.class);
                if(claims.size() > 0){
                    Database.update(claims);
                }     
            }          
        }catch(Exception e){
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
        }
    }
    
    
    /**
* Sets the Rate__c field for ClaimItems of type 'Labor' based on the Labor_Rate__c of the associated Claim.
* 
* @param newClaims List of ClaimItem records to process.
*/
    
public static void setRateForLaborType(List<ClaimItem> newClaims) {
    Set<Id> claimIdSet = new Set<Id>();
    Map<Id,Claim> claimMap;

    for(ClaimItem claimItem : newClaims) {
        claimIdSet.add(claimItem.ClaimId);
    }

    claimMap = new Map<Id,Claim>([
        SELECT Id, Labor_Rate__c
        FROM Claim
        WHERE Id In :claimIdSet
    ]);

    for (ClaimItem claimItem : newClaims) {
        // Check if the ClaimItem is of type 'Labor'
        // and has a valid ClaimId and Labor_Rate__c
        if (
            'Labor'.equals(claimItem.Detail_Type__c) &&
            claimItem.ClaimId != null &&
            claimMap.containsKey(claimItem.ClaimId) &&
            claimItem.Rate__c == null &&
            claimMap.get(claimItem.ClaimId).Labor_Rate__c != null
        ) {
            // Set Rate__c only when it is blank
            claimItem.Rate__c =
                claimMap.get(claimItem.ClaimId).Labor_Rate__c;
        }
    }
}

    
    //Sets Job_Numbers__c, Loss_Categories__c, Loss_Components__c, Detail_Types__c, Latest_Date_Paid__c, Detail_Status__c, Detail_Status_Reasons__c, Payees__c, Last_Status_Changed__c, Detail_Tax__c on Claim Object
    public static void updateClaimRollupFields(Map<Id,ClaimItem> oldMap, List<ClaimItem> newClaims){
        try{
            
            Set<Id> claimIdSet = new Set<Id>();
            List<ClaimItem> claimItems = new List<ClaimItem>();
            Map<Id, Claim> allParentClaims = new Map<Id, Claim>();
            Map<Id, List<ClaimItem>> allClaimsItemMap = new Map<Id, List<ClaimItem>>();
            
            List<Claim> claimToUpdate = new List<Claim>();
            for(ClaimItem ci : newClaims){
                if((oldMap != NULL && oldMap.size() > 0 && 
                    (ci.Job_Number__c != oldMap.get(ci.Id).Job_Number__c || 
                     ci.Loss_Category__c != oldMap.get(ci.Id).Loss_Category__c || 
                     ci.Loss_Description__c != oldMap.get(ci.Id).Loss_Description__c || 
                     ci.Detail_Type__c != oldMap.get(ci.Id).Detail_Type__c ||                     
                     ci.Reason__c != oldMap.get(ci.Id).Reason__c || 
                     ci.Payee_Name__c != oldMap.get(ci.Id).Payee_Name__c ||
                     ci.Tax__c != oldMap.get(ci.Id).Tax__c ||
                     ci.Paid_Date__c != oldMap.get(ci.Id).Paid_Date__c)) ||
                   (oldMap == NULL && (
                       ci.Job_Number__c != NULL || 
                       ci.Loss_Category__c != NULL || 
                       ci.Loss_Description__c !=NULL ||
                       ci.Detail_Type__c != NULL ||                     
                       ci.Reason__c != NULL || 
                       ci.Payee_Name__c != NULL ||
                       ci.Tax__c !=NULL ||
                       ci.Paid_Date__c !=NULL)))
                {
                    claimIdSet.add(ci.ClaimId);
                    
                }
            }
            
            if(claimIdSet.size() > 0 ){
                for (ClaimItem ci : [SELECT Id, ClaimId ,Job_Number__c, Loss_Category__c, Loss_Description__r.Name,Payee_Name__r.Name,Detail_Type__c, Status__c, Reason__c, Payee_Name__c, Paid_Date__c, Tax__c, Tax_New__c,Payment__r.Name,Payment__c from ClaimItem where ClaimId IN :claimIdSet order by ClaimId, Paid_Date__c, Payment__r.Name DESC NULLS LAST, Loss_Category__c, Loss_Description__r.Name, Detail_Type__c, Status__c, Reason__c, Payee_Name__c]){
                    if(allClaimsItemMap.containsKey(ci.ClaimId)){
                        allClaimsItemMap.get(ci.ClaimId).add(ci);
                    } else {
                        allClaimsItemMap.put(ci.ClaimId, new List<ClaimItem>{ci});
                    }
                }
                allParentClaims = new Map<Id, Claim>([SELECT Id, Job_Numbers__c, Loss_Categories__c, Loss_Components__c, Detail_Types__c, Detail_Status__c, Detail_Status_Reasons__c, Payees__c, Last_Status_Changed__c, Detail_Tax__c, Latest_Date_Paid__c, Latest_Payment_Number__c from Claim where Id IN :claimIdSet]);    // -ABan Comment- need to check this line          
                List<Claim> claim = new List<Claim>();
                Set<String> jobNumbers = new Set<String>();
                Set<String> lossCategories = new Set<String>();
                Set<String> lossComponents = new Set<String>();
                Set<String> detailTypes = new Set<String>();
                Set<String> status = new Set<String>();
                Set<String> detailStatusReasons = new Set<String>();
                Set<String> payees = new Set<String>();
                Decimal detailTax = 0;
                Boolean firstEntry = false;
                Boolean firstPaymentEntry = false;
                if(allClaimsItemMap.size()>0){
                    System.debug('inside handler if loop'+allClaimsItemMap.size());
                    for( Id claimId : allClaimsItemMap.keySet()){
                        firstEntry = false;
                        firstPaymentEntry = false;
                        detailTax = 0.00;
                        for (ClaimItem ci : allClaimsItemMap.get(claimId)){
                            System.debug('Payment details payment name'+ci.Payment__r.Name);
                            if(ci.Job_Number__c != NULL){
                                jobNumbers.add(ci.Job_Number__c);
                            }
                            
                            if(ci.Loss_Category__c != NULL){
                                lossCategories.add(ci.Loss_Category__c);
                            }
                            if(ci.Loss_Description__r.Name != NULL){
                                lossComponents.add(ci.Loss_Description__r.Name);
                            }
                            if(ci.Detail_Type__c != NULL){
                                detailTypes.add(ci.Detail_Type__c);
                            }
                            if(ci.Status__c != NULL){
                                status.add(ci.Status__c);
                            }
                            if(ci.Reason__c != NULL){
                                detailStatusReasons.add(ci.Reason__c);
                            }
                            if(ci.Payee_Name__r.Name != NULL){
                                payees.add(ci.Payee_Name__r.Name);
                            }
                            // if(ci.Paid_Date__c != NULL && !firstEntry){
                            //     allParentClaims.get(claimId).Latest_Date_Paid__c = ci.Paid_Date__c;
                            //     firstEntry = true;
                            // }
                            if(ci.Paid_Date__c != NULL){
                                allParentClaims.get(claimId).Latest_Date_Paid__c = ci.Paid_Date__c;
                                firstEntry = true;
                            }
                            
                            if(ci.Payment__c != NULL && !firstPaymentEntry){
                                allParentClaims.get(claimId).Latest_Payment_Number__c = ci.Payment__r.Name; ////need to check this line    
                                firstPaymentEntry = true;
                                System.debug('Latest Payment Number---'+ci.Payment__r.Name);
                                QDX_Log.info('Latest Payment Number for Claim Id ' + claimId + ' : ' + ci.Payment__r.Name);
                            }
                            
                            detailTax += ci.Tax_New__c !=NULL ? ci.Tax_New__c : 0;
                            //detailTax += ci.Tax__c !=NULL ? ci.Tax__c : 0;
                        }
                        if(jobNumbers != NULL){
                            allParentClaims.get(claimId).Job_Numbers__c = jobNumbers.size();
                        }
                        
                        if(lossCategories != NULL){
                            allParentClaims.get(claimId).Loss_Categories__c = String.join(lossCategories,', ');
                        }
                        if(lossComponents != NULL){
                            allParentClaims.get(claimId).Loss_Components__c = String.join(lossComponents,', ');
                        }
                        if(detailTypes != NULL){
                            allParentClaims.get(claimId).Detail_Types__c = String.join(detailTypes,', ');
                        }
                        if(status != NULL){
                            allParentClaims.get(claimId).Detail_Status__c = String.join(status,', ');
                        }
                        if(detailStatusReasons != NULL){
                            allParentClaims.get(claimId).Detail_Status_Reasons__c = String.join(detailStatusReasons,', ');
                        }
                        if(payees != NULL){
                            allParentClaims.get(claimId).Payees__c = String.join(payees,', ');
                        }
                        allParentClaims.get(claimId).Detail_Tax__c = detailTax;
                    }
                }                    
            }
            
            if(allParentClaims.size() > 0){
                update allParentClaims.values();
            }
        }
        catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    /**
 * Calculates Claim Approved Amount based on Claim Items.
 *
 * Eligible Claim Item statuses:
 * - Authorized
 * - Approved to Pay
 * - Paid
 *
 * ApprovedAmount = SUM(NetClaim__c)
 * for all eligible Claim Items belonging to the Claim.
 */
public static void updateApprovedAmountOnClaim(
    Map<Id, ClaimItem> oldMap,
    List<ClaimItem> newClaims
) {
    try {
        Set<Id> claimIds = new Set<Id>();

        /*
         * Identify Claims that need recalculation.
         */
        for (ClaimItem ci : newClaims) {

            if (ci.ClaimId == null) {
                continue;
            }

            /*
             * Insert
             */
            if (oldMap == null) {
                claimIds.add(ci.ClaimId);
                continue;
            }

            /*
             * Update
             *
             * Recalculate when Status or NetClaim changes.
             */
            ClaimItem oldItem = oldMap.get(ci.Id);

            if (
                oldItem != null &&
                (
                    oldItem.Status__c != ci.Status__c ||
                    oldItem.NetClaim__c != ci.NetClaim__c ||
                    oldItem.ClaimId != ci.ClaimId
                )
            ) {
                claimIds.add(ci.ClaimId);

                /*
                 * Also handle the old Claim if ClaimId
                 * was changed.
                 */
                if (oldItem.ClaimId != null) {
                    claimIds.add(oldItem.ClaimId);
                }
            }
        }

        if (claimIds.isEmpty()) {
            return;
        }

        /*
         * Calculate total NetClaim for eligible Claim Items.
         */
        Map<Id, Decimal> approvedAmountByClaim =
            new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT
                ClaimId,
                SUM(NetClaim__c) totalApprovedAmount
            FROM ClaimItem
            WHERE ClaimId IN :claimIds
            AND Status__c IN (
                'Authorized',
                'Approved to Pay',
                'Paid'
            )
            GROUP BY ClaimId
        ]) {
            approvedAmountByClaim.put(
                (Id) ar.get('ClaimId'),
                (Decimal) ar.get('totalApprovedAmount')
            );
        }

        /*
         * Update parent Claims.
         *
         * If there are no eligible Claim Items,
         * set ApprovedAmount to 0.
         */
  List<Claim> claimsToUpdate = new List<Claim>();

Map<Id, Claim> existingClaims = new Map<Id, Claim>([
    SELECT Id, ApprovedAmount
    FROM Claim
    WHERE Id IN :claimIds
]);

for (Id claimId : claimIds) {

    Decimal approvedAmount =
        approvedAmountByClaim.containsKey(claimId)
        ? approvedAmountByClaim.get(claimId)
        : 0;

    Claim existingClaim = existingClaims.get(claimId);

    if (
        existingClaim != null &&
        existingClaim.ApprovedAmount != approvedAmount
    ) {
        claimsToUpdate.add(
            new Claim(
                Id = claimId,
                ApprovedAmount = approvedAmount
            )
        );
    }
}

if (!claimsToUpdate.isEmpty()) {
    update claimsToUpdate;
}

    } catch (Exception e) {

        QDX_Log.error(
            'Exception Occurred: ' +
            e.getMessage() +
            ' Line Number: ' +
            e.getLineNumber()
        );

        QDX_Log.publish();
    }
}
    
    /**
* Updates the ClaimItem record based on sibling ClaimItem records with the same Job Number.
*
* - If no sibling ClaimItem is found and Name is null, sets Name to Loss Description Name.
* - If a sibling exists and Name is null, assigns the first sibling's Loss Description Name.
* - If a sibling exists and Name differs, adds an error to prevent renaming.
* - Syncs Payee Name with the first sibling's value.
* - Calculates the total NetClaim amount for siblings with 'Paid' or 'Approved to Pay' status.
* - Logs a warning if total NetClaim exceeds the max allowed coverage.
* - Updates the Loss Description field.
*
* @param claimItem The ClaimItem record to update.
*/
    public static void updateClaimItem(List<ClaimItem> claimItems) {
        
        if (claimItems == null || claimItems.isEmpty()) {
            return;
        }
        
        // Collect ClaimIds and JobNumbers for bulk querying
        Set<Id> claimIds = new Set<Id>();
        Set<String> jobNumbers = new Set<String>();
        Set<Id> coverageLevelDetails = new Set<Id>();
        Map<String, String> lossCategoryMap = new Map<String, String> ();
        List<String> coverageLevelIdList = new List<String> ();
        
        /*for (ClaimItem ci : claimItems) {
            if (ci.ClaimId != null && ci.Job_Number__c != null) {
                claimIds.add(ci.ClaimId);
                jobNumbers.add(ci.Job_Number__c);
                coverageLevelDetails.add(ci.Coverage_Level_Detail__c);
            }
        }*/

        for (ClaimItem ci : claimItems) {

    if (ci.ClaimId != null) {
        claimIds.add(ci.ClaimId);
    }

    if (String.isNotBlank(ci.Job_Number__c)) {
        jobNumbers.add(ci.Job_Number__c);
    }

    if (ci.Coverage_Level_Detail__c != null) {
        coverageLevelDetails.add(
            ci.Coverage_Level_Detail__c
        );
    }
}
        
        Map<String, String> claimIdToPolicyIdMap = new Map<String, String>();
        Map<String, Coverage_Level_Detail__c> coverageLevelDetailMap = new Map<String, Coverage_Level_Detail__c>();
        Map<String, Coverage_Level_Detail__c> coverageLevelDetailMapForClaimLimit = new Map<String, Coverage_Level_Detail__c>();
        Map<Id, Claim> claimMap = new Map<Id, Claim>();
        for (Claim c : [SELECT Id, Repair_Shop_Account__c,PolicyNumber.DLRS_Total_Net_Claim__c, PolicyNumberId,
                        PolicyNumber.Coverage_Level__r.Max_Total_Claim_Amount__c, PolicyNumber.Deductible__c,
                        PolicyNumber.Coverage_Level__r.Max_Individual_Claim_Amount__c, PolicyNumber.NameInsuredId
                        FROM Claim WHERE Id IN :claimIds]) {
                            claimMap.put(c.Id, c);
                            claimIdToPolicyIdMap.put(c.Id, c.PolicyNumberId);
                        }
        
        // Query all sibling ClaimItem records in bulk
        Map<String, List<ClaimItem>> siblingMap = new Map<String, List<ClaimItem>>();
        for (ClaimItem sibling : [
            SELECT Id, Name, Loss_Description__r.Name, Loss_Category__c, Category, Payee_Name__c, 
            NetClaim__c, Status__c, Coverage_Level_Detail__c, Job_Number__c, ClaimId, Invoice_Number__c
            FROM ClaimItem
            WHERE ClaimId IN :claimIds
            AND Job_Number__c IN :jobNumbers
        ]) {
            String key = sibling.ClaimId + '-' + sibling.Job_Number__c;
            if (!siblingMap.containsKey(key)) {
                siblingMap.put(key, new List<ClaimItem>());
            }
            siblingMap.get(key).add(sibling);
            if(sibling.Coverage_Level_Detail__c!=null){
                coverageLevelDetails.add(sibling.Coverage_Level_Detail__c); 
            }
        }
        
        Map<String, String> coverageDetailToUniqueKeyMap = new Map<String, String>();
        Map<String, Coverage_Level_Detail__c> UniqueKeyToCoverageDetailLimitMap = new Map<String, Coverage_Level_Detail__c>();
        // Query Coverage_Level_Detail__c to set Map
        if (!coverageLevelDetails.isEmpty()) {
            for (Coverage_Level_Detail__c cld : [
                SELECT Id, Name, Max_Component_Coverage_Amt__c, Loss_Component__c, Loss_Component__r.Name , Loss_Category__c, Coverage_Level__c
                FROM Coverage_Level_Detail__c
                WHERE Id IN :coverageLevelDetails
            ]) {
                coverageLevelDetailMap.put(cld.Id, cld);
                
                lossCategoryMap.put(cld.Id, cld.Loss_Category__c);
                coverageLevelIdList.add(cld.Coverage_Level__c);
                coverageDetailToUniqueKeyMap.put(cld.Id, cld.Loss_Category__c+':'+cld.Coverage_Level__c);
            }
        }
        
        // Query Coverage_Level_Detail__c for Loss Category Claim Limits & Alerts
        if (!lossCategoryMap.values().isEmpty() && !coverageLevelIdList.isEmpty()) {
            for (Coverage_Level_Detail__c cld : [
                SELECT Id, Name, Max_Component_Coverage_Amt__c, Limit_Application__c, Coverage_Level__c, Loss_Component__c, Loss_Component__r.Name , Loss_Category_lu__r.Name, Loss_Category__c
                FROM Coverage_Level_Detail__c
                WHERE 
                Loss_Category_lu__r.Name IN : lossCategoryMap.values()
                AND Coverage_Level__c IN :coverageLevelIdList
                AND Loss_Component__c = NULL
            ]) {
                coverageLevelDetailMapForClaimLimit.put(cld.Id, cld);
                UniqueKeyToCoverageDetailLimitMap.put(cld.Loss_Category__c+':'+cld.Coverage_Level__c, cld);
            }
        }   
        
        Map<string, List<ClaimItem>> policyToClaimItemMap = new Map<string, List<ClaimItem>>();
        Map<string, List<ClaimItem>> claimToClaimItemMap = new Map<string, List<ClaimItem>>();
        for (ClaimItem sibling : [
            SELECT Id, NetClaim__c, ClaimId, Claim.PolicyNumberId, Loss_Category__c, Status__c, Invoice_Number__c
            FROM ClaimItem
            WHERE Claim.PolicyNumberId In :claimIdToPolicyIdMap.values()]) {
                
                string key = sibling.Claim.PolicyNumberId +'-'+ sibling.Loss_Category__c ;
                
                if (!policyToClaimItemMap.containsKey(key)) {
                    policyToClaimItemMap.put(key, new List<ClaimItem>());
                }
                policyToClaimItemMap.get(key).add(sibling);
                if (!claimToClaimItemMap.containsKey(sibling.ClaimId)) {
                    claimToClaimItemMap.put(sibling.ClaimId, new List<ClaimItem>());
                }
                claimToClaimItemMap.get(sibling.ClaimId).add(sibling);
            }
        
        // Process each ClaimItem
        for (ClaimItem claimItem : claimItems) {
            String key = claimItem.ClaimId + '-' + claimItem.Job_Number__c;
            List<ClaimItem> siblings = siblingMap.containsKey(key) ? siblingMap.get(key) : new List<ClaimItem>();
            String InvoiceNumber = '';
            // Remove itself from the siblings list
            List<ClaimItem> filteredSiblings = new List<ClaimItem>();
            for (ClaimItem sibling : siblings) {
                if (sibling.Id != claimItem.Id) {
                    filteredSiblings.add(sibling);
                    InvoiceNumber = sibling.Invoice_Number__c != null ? sibling.Invoice_Number__c : InvoiceNumber;
                }
            }
            siblings = filteredSiblings;
            
            // Assign Name based on conditions
            /*if (siblings.isEmpty()) {
                if(claimItem.Coverage_Level_Detail__c == null){
                    claimItem.addError('Loss Description is required.');
                }
                if (claimItem.Name == null) {
                    if(coverageLevelDetailMap.containsKey(claimItem.Coverage_Level_Detail__c)) {
                        claimItem.Name = coverageLevelDetailMap.get(claimItem.Coverage_Level_Detail__c).Loss_Component__r.Name;
                    }
                }
                if(claimMap.containsKey(claimItem.ClaimId) 
                   && claimItem.Category != null && claimItem.Category == '07'){
                       claimItem.Payee_Name__c = claimMap.get(claimItem.ClaimId).PolicyNumber.NameInsuredId;
                   }
                else if(claimItem.Payee_Name__c == null && claimMap.containsKey(claimItem.ClaimId)) {
                    claimItem.Payee_Name__c = claimMap.get(claimItem.ClaimId).Repair_Shop_Account__c;
                }
            } else {
                if (claimItem.Name == null && claimItem.Coverage_Level_Detail__c == null) {
                    claimItem.Coverage_Level_Detail__c = siblings[0].Coverage_Level_Detail__c;
                    claimItem.Name = siblings[0].Loss_Description__r.Name;
                } else if(claimItem.Name == null && claimItem.Coverage_Level_Detail__c != null) {
                    if(claimItem.Coverage_Level_Detail__c != siblings[0].Coverage_Level_Detail__c){
                        claimItem.addError('You cannot change the Job Name because this Job # already has a name.');
                    }
                    claimItem.Name = siblings[0].Loss_Description__r.Name;
                } else if (claimItem.Name != siblings[0].Loss_Description__r.Name) {
                    claimItem.addError('You cannot change the Job Name because this Job # already has a name.');
                }
                
                if (claimItem.Category == null && !siblings.isEmpty() && siblings[0].Category != null) {
                    claimItem.Category = siblings[0].Category;
                }
                if (claimItem.Invoice_Number__c == null && !siblings.isEmpty()) {
                    claimItem.Invoice_Number__c = InvoiceNumber;
                }
                if(claimMap.containsKey(claimItem.ClaimId) 
                   && claimItem.Category != null && claimItem.Category == '07'){
                       claimItem.Payee_Name__c = claimMap.get(claimItem.ClaimId).PolicyNumber.NameInsuredId;
                   }
                else if (claimItem.Payee_Name__c == null && !siblings.isEmpty() && siblings[0].Payee_Name__c != null) {
                    claimItem.Payee_Name__c = siblings[0].Payee_Name__c;
                } 
            }*/

            // Assign Claim Item Name and defaults
if (siblings.isEmpty()) {

    if (claimItem.Coverage_Level_Detail__c == null) {
        claimItem.addError('Loss Description is required.');
        continue;
    }

    /*
     * Resolve ClaimItem.Name safely.
     *
     * Primary:
     * Coverage Level Detail -> Loss Component -> Name
     *
     * Fallback:
     * Coverage Level Detail -> Name
     *
     * The fallback prevents REQUIRED_FIELD_MISSING [Name]
     * when a Coverage Level Detail does not have
     * Loss_Component__c populated.
     */
    if (String.isBlank(claimItem.Name)) {

        Coverage_Level_Detail__c selectedCoverageDetail =
            coverageLevelDetailMap.get(
                claimItem.Coverage_Level_Detail__c
            );

        if (selectedCoverageDetail != null) {

            if (
                selectedCoverageDetail.Loss_Component__c != null &&
                selectedCoverageDetail.Loss_Component__r != null &&
                String.isNotBlank(
                    selectedCoverageDetail
                        .Loss_Component__r
                        .Name
                )
            ) {
                claimItem.Name =
                    selectedCoverageDetail
                        .Loss_Component__r
                        .Name;
            } else {
                /*
                 * Important fallback.
                 *
                 * Example:
                 * Coverage Level Detail = Cooling
                 * Loss Component lookup = null
                 *
                 * ClaimItem.Name will still become "Cooling".
                 */
                claimItem.Name =
                    selectedCoverageDetail.Name;
            }
        }
    }

    /*
     * Final safety check.
     * Never allow Salesforce to fail with the generic
     * REQUIRED_FIELD_MISSING [Name] message.
     */
    if (String.isBlank(claimItem.Name)) {
        claimItem.addError(
            'Unable to determine the Claim Item Name from the selected Loss Component.'
        );
    }

    if (
        claimMap.containsKey(claimItem.ClaimId) &&
        claimItem.Category != null &&
        claimItem.Category == '07'
    ) {
        claimItem.Payee_Name__c =
            claimMap
                .get(claimItem.ClaimId)
                .PolicyNumber
                .NameInsuredId;

    } else if (
        claimItem.Payee_Name__c == null &&
        claimMap.containsKey(claimItem.ClaimId)
    ) {
        claimItem.Payee_Name__c =
            claimMap
                .get(claimItem.ClaimId)
                .Repair_Shop_Account__c;
    }

} else {

    ClaimItem firstSibling = siblings[0];

    /*
     * Use the actual ClaimItem.Name from the sibling.
     *
     * Do NOT depend on Loss_Description__r.Name because
     * Loss_Description__c may legitimately be null on
     * some older/existing records.
     */
    String siblingName = firstSibling.Name;

    if (
        String.isBlank(claimItem.Name) &&
        claimItem.Coverage_Level_Detail__c == null
    ) {
        claimItem.Coverage_Level_Detail__c =
            firstSibling.Coverage_Level_Detail__c;

        claimItem.Name =
            siblingName;

    } else if (
        String.isBlank(claimItem.Name) &&
        claimItem.Coverage_Level_Detail__c != null
    ) {

        if (
            firstSibling.Coverage_Level_Detail__c != null &&
            claimItem.Coverage_Level_Detail__c !=
                firstSibling.Coverage_Level_Detail__c
        ) {
            claimItem.addError(
                'You cannot change the Job Name because this Job # already has a name.'
            );
        }

        claimItem.Name =
            siblingName;

    } else if (
        String.isNotBlank(siblingName) &&
        claimItem.Name != siblingName
    ) {
        claimItem.addError(
            'You cannot change the Job Name because this Job # already has a name.'
        );
    }

    /*
     * Extra protection for old sibling records where Name
     * may unexpectedly be blank.
     */
    if (String.isBlank(claimItem.Name)) {

        Coverage_Level_Detail__c selectedCoverageDetail =
            coverageLevelDetailMap.get(
                claimItem.Coverage_Level_Detail__c
            );

        if (selectedCoverageDetail != null) {

            if (
                selectedCoverageDetail.Loss_Component__c != null &&
                selectedCoverageDetail.Loss_Component__r != null &&
                String.isNotBlank(
                    selectedCoverageDetail
                        .Loss_Component__r
                        .Name
                )
            ) {
                claimItem.Name =
                    selectedCoverageDetail
                        .Loss_Component__r
                        .Name;
            } else {
                claimItem.Name =
                    selectedCoverageDetail.Name;
            }
        }
    }

    if (String.isBlank(claimItem.Name)) {
        claimItem.addError(
            'Unable to determine the Claim Item Name from the selected Loss Component.'
        );
    }

    if (
        claimItem.Category == null &&
        firstSibling.Category != null
    ) {
        claimItem.Category =
            firstSibling.Category;
    }

    if (
        claimItem.Invoice_Number__c == null
    ) {
        claimItem.Invoice_Number__c =
            InvoiceNumber;
    }

    if (
        claimMap.containsKey(claimItem.ClaimId) &&
        claimItem.Category != null &&
        claimItem.Category == '07'
    ) {
        claimItem.Payee_Name__c =
            claimMap
                .get(claimItem.ClaimId)
                .PolicyNumber
                .NameInsuredId;

    } else if (
        claimItem.Payee_Name__c == null &&
        firstSibling.Payee_Name__c != null
    ) {
        claimItem.Payee_Name__c =
            firstSibling.Payee_Name__c;
    }
}
            
            // Calculate total NetClaim for siblings with 'Paid' or 'Approved to Pay' status
            Decimal currentItemNetClaim = claimItem.NetClaim__c;
            if(claimItem.Deductible__c != null && claimItem.Deductible__c >0){
                currentItemNetClaim = currentItemNetClaim - claimItem.Deductible__c;
            }
            else if(!claimToClaimItemMap.containsKey(claimItem.claimId) && claimMap.containsKey(claimItem.ClaimId)
                    && ((claimMap.get(claimItem.ClaimId).Repair_Shop_Account__c != null
                         && claimItem.Payee_Name__c == claimMap.get(claimItem.ClaimId).Repair_Shop_Account__c) 
                        || (claimMap.get(claimItem.ClaimId).PolicyNumber.NameInsuredId != null
                            && claimItem.Payee_Name__c == claimMap.get(claimItem.ClaimId).PolicyNumber.NameInsuredId
                            && (claimItem.Detail_Type__c == 'Part' || claimItem.Detail_Type__c == 'Labor' )))
                    && claimMap.get(claimItem.ClaimId).PolicyNumber?.Deductible__c != null 
                    && claimMap.get(claimItem.ClaimId).PolicyNumber.Deductible__c > 0 ){
                        currentItemNetClaim = currentItemNetClaim - claimMap.get(claimItem.ClaimId).PolicyNumber.Deductible__c;
                    }
            Decimal totalNetClaim = currentItemNetClaim;
            Decimal totalSiblingNetClaim = currentItemNetClaim;
            Decimal totalSiblingNetClaimByContract = currentItemNetClaim;
            Decimal totalSiblingNetClaimByClaim = currentItemNetClaim;
            String currentClaimLossCategory;
            if(!lossCategoryMap.values().isEmpty() && lossCategoryMap.containsKey(claimItem.Coverage_Level_Detail__c)){
                currentClaimLossCategory = lossCategoryMap.get(claimItem.Coverage_Level_Detail__c);
            }
            
            if(claimToClaimItemMap.containsKey(claimItem.claimId)){
                for (ClaimItem sibling : claimToClaimItemMap.get(claimItem.claimId)) {
                    if(sibling.Status__c != 'Denied' && sibling.Id != claimItem.Id) {
                        totalNetClaim += sibling.NetClaim__c;
                    }
                    if(sibling.Loss_Category__c == currentClaimLossCategory && sibling.Id != claimItem.Id) {
                        // c condition
                        totalSiblingNetClaimByClaim += sibling.NetClaim__c;
                    }
                    if(sibling.Id != claimItem.Id){
                        totalSiblingNetClaim += sibling.NetClaim__c;
                    }
                }
            }
            
            if(claimIdToPolicyIdMap.containsKey(claimItem.claimId) 
               && policyToClaimItemMap.containsKey(claimIdToPolicyIdMap.get(claimItem.claimId)+'-'+currentClaimLossCategory)){
                   for(ClaimItem sibling : policyToClaimItemMap.get(claimIdToPolicyIdMap.get(claimItem.claimId)+'-'+currentClaimLossCategory)){
                       
                       if(sibling.Id != claimItem.Id){
                           totalSiblingNetClaimByContract += sibling.NetClaim__c;
                       }
                   }
               }
            
            // Check if total NetClaim is less than zero or not
            //MRT-502
            if(totalSiblingNetClaim < 0){
                claimItem.Message__c = 'The Claim Item you\'re entering does not cover the deductible. This will cause the overall claim value to be negative unless another Claim Item is added to this job.';
            }
            // b condition, claimItem.NetClaim__c + SUM(claimItem.Claim.NetClaim__c) for all Contract's Claims
            else if( claimMap != NULL && claimMap.containsKey(claimItem.claimId) && 
                    claimMap.get(claimItem.claimId).PolicyNumber?.DLRS_Total_Net_Claim__c != NULL &&
                    claimMap.get(claimItem.claimId).PolicyNumber?.Coverage_Level__r?.Max_Total_Claim_Amount__c != NULL &&
                    (currentItemNetClaim + claimMap.get(claimItem.claimId).PolicyNumber.DLRS_Total_Net_Claim__c) > claimMap.get(claimItem.claimId).PolicyNumber.Coverage_Level__r.Max_Total_Claim_Amount__c){
                        claimItem.Message__c = 'This claim exceeds the claim limits for this contract, claim, or loss component. Confirm with your manager before completing.';
                    }
            // d Condition
            else if(claimMap != NULL && claimMap.containsKey(claimItem.claimId) && 
                    claimMap.get(claimItem.claimId).PolicyNumber?.Coverage_Level__r?.Max_Individual_Claim_Amount__c != NULL &&
                    (totalNetClaim > claimMap.get(claimItem.claimId).PolicyNumber.Coverage_Level__r.Max_Individual_Claim_Amount__c)){
                        claimItem.Message__c = 'This claim exceeds the claim limits for this contract, claim, or loss component. Confirm with your manager before completing.';
                    }
            // e condition, coverageLevelDetail.Max_Component_Coverage_Amt__c == null
            else if(coverageDetailToUniqueKeyMap != NULL && coverageDetailToUniqueKeyMap.containsKey(claimItem.Coverage_Level_Detail__c) &&
                    UniqueKeyToCoverageDetailLimitMap != null &&
                    UniqueKeyToCoverageDetailLimitMap.containsKey(coverageDetailToUniqueKeyMap.get(claimItem.Coverage_Level_Detail__c)) &&
                    UniqueKeyToCoverageDetailLimitMap.get(coverageDetailToUniqueKeyMap.get(claimItem.Coverage_Level_Detail__c)).Max_Component_Coverage_Amt__c != NULL){
                        
                        if(UniqueKeyToCoverageDetailLimitMap.get(coverageDetailToUniqueKeyMap.get(claimItem.Coverage_Level_Detail__c)).Limit_Application__c == 'Per Occurrence' &&
                           totalSiblingNetClaimByClaim >  UniqueKeyToCoverageDetailLimitMap.get(coverageDetailToUniqueKeyMap.get(claimItem.Coverage_Level_Detail__c)).Max_Component_Coverage_Amt__c){
                               claimItem.Message__c ='This claim exceeds the claim limits for this contract, claim, or loss component. Confirm with your manager before completing.';
                               
                           }// e condition
                        else if(UniqueKeyToCoverageDetailLimitMap.get(coverageDetailToUniqueKeyMap.get(claimItem.Coverage_Level_Detail__c)).Limit_Application__c == 'Aggregate' &&
                                totalSiblingNetClaimByContract >  UniqueKeyToCoverageDetailLimitMap.get(coverageDetailToUniqueKeyMap.get(claimItem.Coverage_Level_Detail__c)).Max_Component_Coverage_Amt__c){
                                    ClaimItem.Message__c ='This claim exceeds the claim limits for this contract, claim, or loss component. Confirm with your manager before completing.';
                                }
                        else{
                            claimItem.Message__c = '';
                        }
                    }
            else{
                claimItem.Message__c = '';
            }
            
            // Update the Loss_Description__c field
            /*if(coverageLevelDetailMap.containsKey(claimItem.Coverage_Level_Detail__c)) {
                claimItem.Loss_Description__c = coverageLevelDetailMap.get(claimItem.Coverage_Level_Detail__c).Loss_Component__c;    
            }*/

            if (
    claimItem.Coverage_Level_Detail__c != null &&
    coverageLevelDetailMap.containsKey(
        claimItem.Coverage_Level_Detail__c
    )
) {
    Coverage_Level_Detail__c selectedCoverageDetail =
        coverageLevelDetailMap.get(
            claimItem.Coverage_Level_Detail__c
        );

    if (selectedCoverageDetail.Loss_Component__c != null) {
        claimItem.Loss_Description__c =
            selectedCoverageDetail.Loss_Component__c;
    }
}
        }
    }
    
    public static void updateAppliedDeductibleOnClaim(Map<Id,ClaimItem> oldMap, List<ClaimItem> newClaims){
        Set<String> claimIdSet = new Set<String> ();
        List<ClaimItem> claimItemList = new List<ClaimItem> ();
        Map<Id,Claim> updateClaimByAppliedDeductible = new Map<Id,Claim> ();
        List<Claim> claimListToUpdate = new List<Claim> ();
        if(newClaims != NULL){
            for(ClaimItem items:newClaims){
                if(oldMap != NULL && oldMap.size() > 0 && 
                   oldMap.get(items.Id).claimId != NULL &&
                   (oldMap.get(items.Id).Detail_Type__c != items.Detail_Type__c ||
                    oldMap.get(items.Id).Deductible__c != items.Deductible__c ||
                    oldMap.get(items.Id).Subtotal__c != items.Subtotal__c )){
                        claimIdSet.add(items.claimId);
                    }
                if(items.ClaimId != NULL && oldMap == NULL){
                    claimIdSet.add(items.claimId);
                }
            }
        }
        if(claimIdSet != NULL){
            claimItemList = [Select Id, Name, ClaimId,Deductible__c,Detail_Type__c,Subtotal__c from ClaimItem WHERE ClaimId IN : claimIdSet];
        }
        if(claimItemList != NULL){ 
            for(ClaimItem claimItems: claimItemList){
                Claim claimObj = new Claim();
                claimObj.Id = claimItems.claimId;
                if(claimItems.Detail_Type__c != 'Deductible' && claimItems.deductible__c != NULL){
                    if (updateClaimByAppliedDeductible.containsKey(claimItems.claimId) ){
                        claimObj.Applied_Deductible__c = updateClaimByAppliedDeductible.get(claimItems.claimId).Applied_Deductible__c + claimItems.deductible__c;
                        updateClaimByAppliedDeductible.put(claimItems.claimId,claimObj);
                    }
                    else{
                        claimObj.Applied_Deductible__c = claimItems.Deductible__c;
                        updateClaimByAppliedDeductible.put(claimItems.claimId,claimObj);
                    }
                }
                if(claimItems.Detail_Type__c == 'Deductible' && claimItems.subtotal__c != NULL){
                    if(updateClaimByAppliedDeductible.containsKey(claimItems.claimId)){
                        claimObj.Applied_Deductible__c = updateClaimByAppliedDeductible.get(claimItems.claimId).Applied_Deductible__c + claimItems.subtotal__c;
                        updateClaimByAppliedDeductible.put(claimItems.claimId,claimObj);
                    }
                    else{
                        claimObj.Applied_Deductible__c = claimItems.subtotal__c;
                        updateClaimByAppliedDeductible.put(claimItems.claimId,claimObj);
                    }
                }
            }
        }
        
       if (!updateClaimByAppliedDeductible.isEmpty()) {

    Map<Id, Claim> existingClaims = new Map<Id, Claim>([
        SELECT Id, Applied_Deductible__c
        FROM Claim
        WHERE Id IN :updateClaimByAppliedDeductible.keySet()
    ]);

    for (Id claimId : updateClaimByAppliedDeductible.keySet()) {

        Claim calculatedClaim =
            updateClaimByAppliedDeductible.get(claimId);

        Claim existingClaim =
            existingClaims.get(claimId);

        if (
            existingClaim != null &&
            existingClaim.Applied_Deductible__c !=
            calculatedClaim.Applied_Deductible__c
        ) {
            claimListToUpdate.add(calculatedClaim);
        }
    }

    if (!claimListToUpdate.isEmpty()) {
        update claimListToUpdate;
    }
}
    }
    
    /**
* Sets the Deductible field for first ClaimItem record of a Claim.
* @param newClaims List of ClaimItem records to process.
*/
    /*public static void updateDeductibleDetails(List<ClaimItem> newClaims) {
        Set<Id> claimIdSet = new Set<Id>();
        Map<Id,Claim> claimMap = new  Map<Id,Claim>();
        Map<Id,ClaimItem> claimItemsMap;
        
        //Set all Parent Claim Ids
        for(ClaimItem claimItem : newClaims) {
            claimIdSet.add(claimItem.ClaimId);
        }
        //Get all Other ClaimItems for Same Claim
        if(!claimIdSet.isEmpty()){
            claimItemsMap =  new Map<Id,ClaimItem>([SELECT Id,ClaimId FROM ClaimItem WHERE ClaimId In :claimIdSet]);
            
            if(!claimItemsMap.isEmpty()){
                for(ClaimItem claimItem : claimItemsMap.values()) {
                    if(claimIdSet.contains(claimItem.ClaimId)){
                        claimIdSet.remove(claimItem.ClaimId);
                    }  
                }
            } 
            
            if (!claimIdSet.isEmpty()) {
                claimMap = new Map<Id,Claim>([SELECT Id, PolicyNumber.Deductible__c, PolicyNumber.NameInsuredId, Repair_Shop_Account__c FROM Claim WHERE Id In :claimIdSet]);
                
                //Iterate through all newClaims and set Deductible field if Payee of Claim Item Matches Reapir Shop of Claim
                for(ClaimItem claimItem : newClaims) {
                    if(!claimMap.isEmpty() && claimMap.containsKey(claimItem.ClaimId) && claimItem.Payee_Name__c!=null 
                       && (claimItem.Payee_Name__c == claimMap.get(claimItem.ClaimId).Repair_Shop_Account__c 
                           || (claimItem.Payee_Name__c == claimMap.get(claimItem.ClaimId).PolicyNumber.NameInsuredId 
                               && (claimItem.Detail_Type__c == 'Part' || claimItem.Detail_Type__c == 'Labor' )))) {
                                   claimItem.Deductible__c = claimMap.get(claimItem.ClaimId).PolicyNumber.Deductible__c;
                               }
                }
            }
        }
    }*/

    public static void updateDeductibleDetails(
    List<ClaimItem> newClaims
) {
    if (newClaims == null || newClaims.isEmpty()) {
        return;
    }

    Set<Id> claimIds = new Set<Id>();

    for (ClaimItem claimItem : newClaims) {
        if (claimItem.ClaimId != null) {
            claimIds.add(claimItem.ClaimId);
        }
    }

    if (claimIds.isEmpty()) {
        return;
    }

    /*
     * Find Claims that already have at least one Claim Item
     * in the database.
     *
     * Those Claims must NOT receive another automatic
     * deductible.
     */
    Set<Id> claimsWithExistingItems = new Set<Id>();

    for (AggregateResult result : [
        SELECT ClaimId claimId
        FROM ClaimItem
        WHERE ClaimId IN :claimIds
        GROUP BY ClaimId
    ]) {
        claimsWithExistingItems.add(
            (Id) result.get('claimId')
        );
    }

    /*
     * Only Claims having no previously saved Claim Items
     * are candidates for the initial deductible.
     */
    Set<Id> newClaimIds = new Set<Id>();

    for (Id claimId : claimIds) {
        if (!claimsWithExistingItems.contains(claimId)) {
            newClaimIds.add(claimId);
        }
    }

    if (newClaimIds.isEmpty()) {
        return;
    }

    Map<Id, Claim> claimMap = new Map<Id, Claim>([
        SELECT
            Id,
            PolicyNumber.Deductible__c,
            PolicyNumber.NameInsuredId,
            Repair_Shop_Account__c
        FROM Claim
        WHERE Id IN :newClaimIds
    ]);

    /*
     * Critical bulk-insert protection:
     *
     * Once one Claim Item receives the deductible for a
     * particular Claim, no other Claim Item from the same
     * Trigger.new collection can receive it.
     */
    Set<Id> deductibleAppliedClaimIds = new Set<Id>();

    for (ClaimItem claimItem : newClaims) {

        if (
            claimItem.ClaimId == null ||
            deductibleAppliedClaimIds.contains(
                claimItem.ClaimId
            ) ||
            !claimMap.containsKey(claimItem.ClaimId)
        ) {
            continue;
        }

        Claim parentClaim =
            claimMap.get(claimItem.ClaimId);

        if (
            claimItem.Payee_Name__c != null &&
            (
                claimItem.Payee_Name__c ==
                    parentClaim.Repair_Shop_Account__c
                ||
                (
                    claimItem.Payee_Name__c ==
                        parentClaim.PolicyNumber.NameInsuredId
                    &&
                    (
                        claimItem.Detail_Type__c == 'Part' ||
                        claimItem.Detail_Type__c == 'Labor'
                    )
                )
            )
        ) {
            claimItem.Deductible__c =
                parentClaim.PolicyNumber.Deductible__c;

            /*
             * Do not allow another Claim Item for this Claim
             * to receive the deductible in this transaction.
             */
            deductibleAppliedClaimIds.add(
                claimItem.ClaimId
            );
        }
    }
}
    
    /**
* Validates that all Claim Items moving to 'Authorized', 'Approved to Pay', or 'Paid' status
* have a non-null Invoice Number if their Payee Account is of type 'Inspection Company' or 'Subcontractor'.
*
* If any sibling Claim Item within the same Claim is moving to one of the target statuses
* and violates this rule (missing invoice for the required record type), all such Claim Items
* in that Claim will receive an error and cannot proceed.
*
* @param claimItems The list of ClaimItem records being updated in the before update context.
*/
    public static void validateInvoiceNumberForAuthorizedStatus(List<ClaimItem> claimItems) {
        // Collect ClaimIds for any ClaimItems being moved to a sensitive status
        Set<Id> claimIds = new Set<Id>();
        for (ClaimItem ci : claimItems) {
            if (ci.Status__c != null &&
                (ci.Status__c == 'Authorized' || ci.Status__c == 'Approved to Pay' || ci.Status__c == 'Paid')) {
                    claimIds.add(ci.ClaimId);
                }
        }
        
        if (!claimIds.isEmpty()) {
            // Only get siblings violating the condition (missing invoice + record type)
            Set<Id> claimIdsWithViolation = new Set<Id>();
            for (AggregateResult ar : [
                SELECT ClaimId
                FROM ClaimItem
                WHERE ClaimId IN :claimIds
                AND Invoice_Number__c = NULL
                AND Payee_Name__r.RecordType.DeveloperName IN ('Inspection_Company', 'Subcontractor')
                GROUP BY ClaimId
            ]) {
                claimIdsWithViolation.add((Id)ar.get('ClaimId'));
            }
            
            // Block all items in such Claims
            for (ClaimItem ci : claimItems) {
                if (!claimIdsWithViolation.isEmpty() && claimIdsWithViolation.contains(ci.ClaimId)) {
                    ci.addError('You must include the invoice number before Authorizing an Inspection or Subcontractor Claim Item. No Claim Items will move forward to Authorized.');
                }
            }
        }
    }

    //added by Joyita Sarkar 19.8.26
 /**
 * Generates Authorization Number on the parent Claim when a
 * Claim Item moves to Authorized status.
 *
 * Rules:
 * 1. Only execute when Claim Item status changes TO Authorized.
 * 2. Do not generate for Inspection Company payees.
 * 3. Do not regenerate if Claim already has Authorization Number.
 * 4. Authorization Number must be unique.
 */
public static void generateAuthorizationNumber(
    Map<Id, ClaimItem> oldMap,
    List<ClaimItem> newClaims
) {
    try {

        System.debug(
            '===== START generateAuthorizationNumber ====='
        );

        Set<Id> claimIds = new Set<Id>();

        /*
         * STEP 1:
         * Identify Claim Items whose Status changed TO Authorized.
         */
        for (ClaimItem ci : newClaims) {

            ClaimItem oldItem = oldMap.get(ci.Id);

            System.debug(
                'ClaimItem Id: ' + ci.Id +
                ' | Old Status: ' +
                (oldItem != null ? oldItem.Status__c : 'NULL') +
                ' | New Status: ' +
                ci.Status__c
            );

            if (
                ci.ClaimId != null &&
                ci.Status__c == 'Authorized' &&
                oldItem != null &&
                oldItem.Status__c != 'Authorized'
            ) {
                claimIds.add(ci.ClaimId);
            }
        }

        System.debug(
            'Claims identified for Authorization Number: ' +
            claimIds
        );

        if (claimIds.isEmpty()) {
            System.debug(
                'No Claim Item changed to Authorized.'
            );
            return;
        }

        /*
         * STEP 2:
         * Get the parent Claims.
         */
        Map<Id, Claim> claimMap =
            new Map<Id, Claim>([
                SELECT
                    Id,
                    Authorization_Number__c
                FROM Claim
                WHERE Id IN :claimIds
            ]);

        /*
         * STEP 3:
         * Get the Claim Items that changed to Authorized.
         */
        Set<Id> authorizedItemIds = new Set<Id>();

        for (ClaimItem ci : newClaims) {

            ClaimItem oldItem = oldMap.get(ci.Id);

            if (
                ci.Id != null &&
                ci.ClaimId != null &&
                ci.Status__c == 'Authorized' &&
                oldItem != null &&
                oldItem.Status__c != 'Authorized'
            ) {
                authorizedItemIds.add(ci.Id);
            }
        }

        if (authorizedItemIds.isEmpty()) {
            return;
        }

        List<ClaimItem> authorizedItems = [
            SELECT
                Id,
                ClaimId,
                Status__c,
                Payee_Name__c,
                Payee_Name__r.RecordType.Name,
                Payee_Name__r.RecordType.DeveloperName
            FROM ClaimItem
            WHERE Id IN :authorizedItemIds
        ];

        System.debug(
            'Authorized Claim Items found: ' +
            authorizedItems.size()
        );

        Set<Id> claimsToGenerate = new Set<Id>();

        /*
         * STEP 4:
         * Check Inspection Company and existing Authorization Number.
         */
        for (ClaimItem ci : authorizedItems) {

            System.debug(
                'Processing ClaimItem: ' + ci.Id +
                ' | Claim: ' + ci.ClaimId +
                ' | Payee: ' + ci.Payee_Name__c +
                ' | Payee Record Type: ' +
                (
                    ci.Payee_Name__r != null &&
                    ci.Payee_Name__r.RecordType != null
                    ? ci.Payee_Name__r.RecordType.Name
                    : 'NULL'
                )
            );

            if (ci.ClaimId == null) {
                continue;
            }

            /*
             * Do NOT generate Authorization Number
             * for Inspection Company.
             */
            if (
                ci.Payee_Name__r != null &&
                ci.Payee_Name__r.RecordType != null &&
                (
                    ci.Payee_Name__r.RecordType.Name ==
                        'Inspection Company'
                    ||
                    ci.Payee_Name__r.RecordType.DeveloperName ==
                        'Inspection_Company'
                )
            ) {
                System.debug(
                    'Skipping Authorization Number because ' +
                    'Payee is Inspection Company.'
                );

                continue;
            }

            /*
             * Do not regenerate an existing number.
             */
            Claim parentClaim = claimMap.get(ci.ClaimId);

            if (
                parentClaim != null &&
                String.isBlank(
                    parentClaim.Authorization_Number__c
                )
            ) {
                claimsToGenerate.add(ci.ClaimId);
            }
        }

        System.debug(
            'Claims requiring Authorization Number: ' +
            claimsToGenerate
        );

        if (claimsToGenerate.isEmpty()) {
            System.debug(
                'No Claims require Authorization Number.'
            );
            return;
        }

        /*
         * STEP 5:
         * Generate Authorization Numbers.
         */
        List<Claim> claimsToUpdate =
            new List<Claim>();

        for (Id claimId : claimsToGenerate) {

            Claim claimToUpdate =
                claimMap.get(claimId);

            if (claimToUpdate == null) {
                continue;
            }

            String authorizationNumber =
                'AUTH-' +
                EncodingUtil.convertToHex(
                    Crypto.generateAesKey(128)
                )
                .substring(0, 7)
                .toUpperCase();

            System.debug(
                'Generated Authorization Number for Claim ' +
                claimId +
                ': ' +
                authorizationNumber
            );

            claimToUpdate.Authorization_Number__c =
                authorizationNumber;

            claimsToUpdate.add(
                claimToUpdate
            );
        }

        /*
         * STEP 6:
         * Update Claims.
         */
        if (!claimsToUpdate.isEmpty()) {

            System.debug(
                'Updating Claims with Authorization Numbers: ' +
                claimsToUpdate
            );

            update claimsToUpdate;
        }

        System.debug(
            '===== END generateAuthorizationNumber ====='
        );

    } catch (Exception e) {

        System.debug(
            'ERROR generateAuthorizationNumber: ' +
            e.getMessage()
        );

        System.debug(
            'ERROR LINE: ' +
            e.getLineNumber()
        );

        QDX_Log.error(
            'Exception Occurred while generating Authorization Number: ' +
            e.getMessage() +
            ' Line Number: ' +
            e.getLineNumber()
        );

        QDX_Log.publish();
    }
}
}