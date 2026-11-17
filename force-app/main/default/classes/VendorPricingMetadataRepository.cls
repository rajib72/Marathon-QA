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

    public class EndpointConfiguration {
        public List<Vendor_Integration__mdt> vendors = new List<Vendor_Integration__mdt>();
        public List<Vendor_Endpoint__mdt> endpoints = new List<Vendor_Endpoint__mdt>();
    }

    public static EndpointConfiguration loadForEndpointResolution() {
        EndpointConfiguration result = new EndpointConfiguration();
        result.vendors = [
            SELECT Id, DeveloperName, Active__c, Include_in_All_Vendor_Search__c
            FROM Vendor_Integration__mdt
            ORDER BY DeveloperName
        ];
        result.endpoints = [
            SELECT Id, DeveloperName, Vendor__c, Active__c, Operation__c, Invocation_Policy__c,
                   Supported_Search_Modes__c, Is_Primary_Pricing_Endpoint__c,
                   Supports_Standard_Parts__c, Supports_Terminology_Search__c,
                   Supports_Vendor_SKU_Search__c, Supports_Powertrain__c
            FROM Vendor_Endpoint__mdt
            ORDER BY DeveloperName
        ];
        return result;
    }

    public class RequestConfiguration {
        public Vendor_Endpoint__mdt endpoint;
        public Vendor_Integration__mdt vendor;
        public List<Vendor_Field_Mapping__mdt> fields = new List<Vendor_Field_Mapping__mdt>();
        public List<Vendor_Value_Mapping__mdt> values = new List<Vendor_Value_Mapping__mdt>();
    }

    public static RequestConfiguration loadRequestConfiguration(String endpointName, Boolean includeDrafts) {
        RequestConfiguration result = new RequestConfiguration();
        List<Vendor_Endpoint__mdt> endpoints = [
            SELECT Id, DeveloperName, Vendor__c, Active__c, Invocation_Policy__c,
                   Request_Builder_Strategy__c, Supported_Search_Modes__c,
                   Supports_Standard_Parts__c, Supports_Terminology_Search__c,
                   Supports_Vendor_SKU_Search__c, Supports_Powertrain__c,
                   Supports_Multi_Part_Request__c, Maximum_Parts_Per_Request__c
            FROM Vendor_Endpoint__mdt
            WHERE DeveloperName = :endpointName AND Invocation_Policy__c = 'INITIAL_PRICING'
        ];
        if (endpoints.size() != 1 || endpoints[0].Vendor__c == null) {
            return result;
        }
        Vendor_Endpoint__mdt endpoint = endpoints[0];
        Id endpointId = endpoint.Id;
        Id vendorId = endpoint.Vendor__c;
        List<Vendor_Integration__mdt> vendors = [
            SELECT Id, DeveloperName, Active__c, Include_in_All_Vendor_Search__c,
                   Default_Request_Builder__c, Maximum_Parts_Per_Request__c
            FROM Vendor_Integration__mdt
            WHERE Id = :vendorId
        ];
        if (vendors.isEmpty()) {
            return result;
        }
        result.endpoint = endpoint;
        result.vendor = vendors[0];
        if (includeDrafts != true && (endpoint.Active__c != true ||
            result.vendor.Active__c != true || result.vendor.Include_in_All_Vendor_Search__c != true)) {
            return result;
        }
        for (Vendor_Field_Mapping__mdt mapping : [
            SELECT DeveloperName, Active__c, Internal_Field_Code__c, Vendor_Field_Path__c,
                   Record_Scope__c, Collection_Path__c, Transport_Location__c,
                   Source_Type__c, Source_Reference__c, Apply_To_Search_Modes__c,
                   Data_Type__c, Requirement_Mode__c, Conditional_Requirement_Code__c,
                   Omit_When_Blank__c, Transformation_Strategy__c, Value_Mapping_Group__c,
                   List_Delimiter__c, Validation_Strategy__c, Validation_Message__c,
                   Minimum_Length__c, Minimum_Numeric_Value__c, Maximum_Numeric_Value__c,
                   Format_Pattern__c
            FROM Vendor_Field_Mapping__mdt
            WHERE Vendor_Endpoint__c = :endpointId AND Direction__c = 'OUTBOUND'
            ORDER BY Sequence__c, DeveloperName
        ]) {
            if (includeDrafts == true || mapping.Active__c == true) {
                result.fields.add(mapping);
            }
        }
        for (Vendor_Value_Mapping__mdt mapping : [
            SELECT Active__c, Mapping_Group__c, Internal_Value__c, Vendor_Value__c,
                   Context_Code__c, Vendor_Endpoint__c, Case_Sensitive__c,
                   Default_Mapping__c, Priority__c
            FROM Vendor_Value_Mapping__mdt
            WHERE Vendor__c = :vendorId AND Direction__c IN ('OUTBOUND', 'BOTH')
        ]) {
            if ((includeDrafts == true || mapping.Active__c == true) &&
                (mapping.Vendor_Endpoint__c == null || mapping.Vendor_Endpoint__c == endpointId)) {
                result.values.add(mapping);
            }
        }
        return result;
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