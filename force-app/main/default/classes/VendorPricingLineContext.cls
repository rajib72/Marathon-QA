/**
 * Normalized line used by downstream validation and vendor request builders.
 * searchMode is a context hint, NOT a vendor-specific API searchType value.
 */
public class VendorPricingLineContext {
    @AuraEnabled public String rowKey { get; set; }
    @AuraEnabled public Id claimItemId { get; set; }
    @AuraEnabled public Boolean persisted { get; set; }
    @AuraEnabled public String detailType { get; set; }
    @AuraEnabled public String partNumber { get; set; }
    @AuraEnabled public Decimal adjustedQuantity { get; set; }
    @AuraEnabled public Id coverageLevelDetailId { get; set; }
    @AuraEnabled public String lossCategory { get; set; }
    @AuraEnabled public String lossComponentName { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public String searchMode { get; set; }
}