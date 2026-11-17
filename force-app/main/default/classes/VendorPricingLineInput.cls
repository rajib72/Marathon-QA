/**
 * User's CURRENT Claim Item Editor draft state for one selected row.
 * A ClaimItem Id is optional because the editor supports unsaved rows.
 * This DTO is used for read-only pricing context only; it cannot save Claim Items.
 */
public class VendorPricingLineInput {
    @AuraEnabled public String rowKey { get; set; }
    @AuraEnabled public Id claimItemId { get; set; }
    @AuraEnabled public String detailType { get; set; }
    @AuraEnabled public String partNumber { get; set; }
    @AuraEnabled public Decimal adjustedQuantity { get; set; }
    @AuraEnabled public Id coverageLevelDetailId { get; set; }
    @AuraEnabled public String description { get; set; }
}