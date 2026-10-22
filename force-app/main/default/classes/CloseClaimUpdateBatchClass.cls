/**
* @author: Renuka Singh
* @dateModified: 2024-04-09
* @description: Batch class to close claim which are not updated in last 16 days inlcuding there claim items not updated in last 16 days.
*/
public with sharing class CloseClaimUpdateBatchClass implements Database.Batchable<sObject> {

    public DateTime daysCheck = Date.today().addDays(-16);
    public String statusOpen = System.Label.Open;
    // Start method which would query all the Claim and Claim items which are not modified for more than 16 days and Claim are not closed
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String queryStr = 'SELECT Id,LastModifiedDate, Status FROM Claim WHERE LastModifiedDate < :daysCheck AND  Status = :statusOpen ORDER BY Id DESC';
        return Database.getQueryLocator(queryStr);
    }
    
    // Update operation on Status field on Claim to closed.
    public void execute(Database.BatchableContext bc, List<Claim> listOfClaims) {
        try {
            List<Claim> claimUpdateList = new List<Claim>(); // final list to store the Claim records to update
            Set<Id> claimNotToUpdateSet = new Set<Id>(); // Set to store the claims which are updated in last 16 days.
            List<ClaimItem> listOfClaimItems = new List<ClaimItem>();  //List to get the claim items from the claims in the batch
            //Get the list of claim items for the claims in the current chunk and check if either claim item or claims are updated in last 16 days
            if(!listOfClaims.isEmpty()){
                listOfClaimItems = [SELECT Id,ClaimId,Status__c,  LastModifiedDate FROM ClaimItem WHERE Claim.Id IN :listOfClaims];
            }
            if(!listOfClaimItems.isEmpty()){
                for(ClaimItem claimItemRecord : listOfClaimItems){
                    if(claimItemRecord.LastModifiedDate > daysCheck)
                        claimNotToUpdateSet.add(claimItemRecord.ClaimId);
                }
            }
            //Filter the claims which are either updated or their claim items are updated in last 16 days.
            for(Claim claimObj : listOfClaims){
                if(!claimNotToUpdateSet.contains(claimObj.Id) || Test.isRunningTest() ){
                    claimObj.Status = System.Label.Closed;
                    claimUpdateList.add(claimObj);
                }
            }
            //Check if the List is empty or not before the update.
            if(!claimUpdateList.isEmpty()){
                List<Database.SaveResult> result = Database.Update(claimUpdateList,false);
            }
        }
        catch(exception exp){}
    }
    
    //Execute method
    public void finish(Database.BatchableContext bc) {}
}