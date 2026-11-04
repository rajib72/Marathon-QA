/**
 * Read-only access to the four approved Vendor Pricing CMDTs.
 * This is an internal repository, not an LWC-exposed controller.
 * The bulk load is intended for administrator configuration audits.
 * Runtime quote execution will use selectively scoped repository methods.
 */
public with sharing class VendorPricingMetadataRepository {
    public class Snapshot {
        public List<Vendor_Integration__mdt> vendors = new List<Vendor_Integration__mdt>();
        public List<Vendor_Endpoint__mdt> endpoints = new List<Vendor_Endpoint__mdt>();
        public List<Vendor_Field_Mapping__mdt> fieldMappings = new List<Vendor_Field_Mapping__mdt>();
        public List<Vendor_Value_Mapping__mdt> valueMappings = new List<Vendor_Value_Mapping__mdt>();
    }

    public static Snapshot loadForAudit() {
        Snapshot result = new Snapshot();

        result.vendors = [
            SELECT Id, DeveloperName, MasterLabel,
                   Active__c, Configuration_Status__c,
                   Named_Credential_API_Name__c,
                   Include_in_All_Vendor_Search__c
            FROM Vendor_Integration__mdt
            ORDER BY DeveloperName
        ];
        result.endpoints = [
            SELECT Id, DeveloperName, MasterLabel, Active__c,
                   Vendor__c, Operation__c, HTTP_Method__c,
                   Relative_Path__c, Requires_Authentication__c,
                   Is_Primary_Pricing_Endpoint__c, Invocation_Policy__c
            FROM Vendor_Endpoint__mdt
            ORDER BY DeveloperName
        ];
        result.fieldMappings = [
            SELECT Id, DeveloperName, Active__c,
                   Vendor_Endpoint__c, Direction__c,
                   Internal_Field_Code__c, Vendor_Field_Path__c
            FROM Vendor_Field_Mapping__mdt
            ORDER BY DeveloperName
        ];
        result.valueMappings = [
            SELECT Id, DeveloperName, Active__c,
                   Vendor__c, Vendor_Endpoint__c, Direction__c,
                   Mapping_Group__c, Internal_Value__c, Vendor_Value__c
            FROM Vendor_Value_Mapping__mdt
            ORDER BY DeveloperName
        ];
        return result;
    }
}