/**
 * Internal normalized Salesforce context shared by vendor adapters.
 * Contains no credentials, no API-specific field names, no pricing calculation.
 */
public class VendorPricingRequestContext {
    @AuraEnabled public Id claimId { get; set; }
    @AuraEnabled public Id policyId { get; set; }
    @AuraEnabled public Id coverageLevelId { get; set; }
    @AuraEnabled public String vin { get; set; }
    @AuraEnabled public Decimal currentMileage { get; set; }
    @AuraEnabled public Id repairShopAccountId { get; set; }
    @AuraEnabled public String repairShopName { get; set; }
    @AuraEnabled public String repairShopStreet { get; set; }
    @AuraEnabled public String repairShopCity { get; set; }
    @AuraEnabled public String repairShopState { get; set; }
    @AuraEnabled public String repairShopPostalCode { get; set; }
    @AuraEnabled public String repairShopCountry { get; set; }
    @AuraEnabled public List<VendorPricingLineContext> lines { get; set; }

    public VendorPricingRequestContext() {
        lines = new List<VendorPricingLineContext>();
    }
}