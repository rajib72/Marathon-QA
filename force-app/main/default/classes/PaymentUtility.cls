/**
* @author: Hitarth Trivedi
* @dateModified: 09-09-2024
* @description: 
* Links payments to claim items by setting the payment ID on the claim items
* and updating their statuses to 'Paid'. It also updates the processed date 
* on the related payments.
*/
public class PaymentUtility {
    
    public static void linkPaymentsToClaimItems(Map<Id, List<ClaimItem>> paymentClaimItemMap) {
        // List to hold claim items that need to be updated
        List<ClaimItem> claimItemsToUpdate = new List<ClaimItem>();
        
        // List to hold payments that need to be updated
        List<Payment__c> paymentsToUpdate = new List<Payment__c>();

        // Iterate over each payment ID in the map
        for(Id paymentId : paymentClaimItemMap.keySet()) {
        	List<ClaimItem> claimItems = paymentClaimItemMap.get(paymentId);
            
            // Set payment details on each related claim item
            for (ClaimItem claimItem : claimItems) {
                claimItem.Payment__c = paymentId;          // Link the payment to the claim item
                claimItem.Status__c = 'Paid';              // Set status to 'Paid'
                claimItem.Paid_Date__c = Date.today();     // Set the paid date to today's date
                claimItemsToUpdate.add(claimItem);         // Add to update list
            }
            
            // Payment__c record for processing date update
            Payment__c payment = new Payment__c();
            payment.Id = paymentId;                       // Set the payment ID
            payment.Date_Processed__c = DateTime.now();   // Set the processed date to current date/time
            paymentsToUpdate.add(payment);                // Add to update list
        }
        
        // Update ClaimItem and Payment records (with partial success allowed)
        Database.update(claimItemsToUpdate, false);
        Database.update(paymentsToUpdate, false);
    }
}