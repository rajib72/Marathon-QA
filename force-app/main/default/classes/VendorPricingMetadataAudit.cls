/**
 * Checks configuration integrity without making any vendor callouts or DML.
 * Inactive draft records intentionally do not generate readiness errors.
 * Records must never be activated merely to make the audit pass.
 */
public with sharing class VendorPricingMetadataAudit {
    public class Issue {
        public String severity;
        public String code;
        public String recordName;
        public String message;
        public Issue(String severity, String code, String recordName, String message) {
            this.severity = severity;
            this.code = code;
            this.recordName = recordName;
            this.message = message;
        }
    }

    public class Result {
        public Integer vendorsChecked = 0;
        public Integer endpointsChecked = 0;
        public Integer fieldsChecked = 0;
        public Integer valuesChecked = 0;
        public List<Issue> issues = new List<Issue>();
        public Integer errorCount = 0;
        public Integer warningCount = 0;
        public Boolean passesMetadataChecks = false;
    }

    public static Result run() {
        return evaluate(VendorPricingMetadataRepository.loadForAudit());
    }

    /** Pure validator: tests can supply in-memory metadata without SeeAllData. */
    public static Result evaluate(VendorPricingMetadataRepository.Snapshot snapshot) {
        if (snapshot == null) {
            throw new VendorPricingAuditException('A metadata snapshot is required.');
        }
        Result out = new Result();
        out.vendorsChecked = snapshot.vendors.size();
        out.endpointsChecked = snapshot.endpoints.size();
        out.fieldsChecked = snapshot.fieldMappings.size();
        out.valuesChecked = snapshot.valueMappings.size();

        Map<Id, Vendor_Integration__mdt> vendorsById = new Map<Id, Vendor_Integration__mdt>();
        Map<Id, Vendor_Endpoint__mdt> endpointsById = new Map<Id, Vendor_Endpoint__mdt>();
        Map<Id, Integer> activeEndpointCount = new Map<Id, Integer>();
        Map<Id, Integer> primaryEndpointCount = new Map<Id, Integer>();
        Map<Id, Integer> outboundCount = new Map<Id, Integer>();
        Map<Id, Integer> inboundCount = new Map<Id, Integer>();
        Integer eligibleVendorCount = 0;

        for (Vendor_Integration__mdt vendor : snapshot.vendors) {
            if (vendor.Id != null) vendorsById.put(vendor.Id, vendor);
        }
        for (Vendor_Endpoint__mdt endpoint : snapshot.endpoints) {
            if (endpoint.Id != null) endpointsById.put(endpoint.Id, endpoint);
            if (endpoint.Active__c != true) continue;

            if (endpoint.Vendor__c == null || !vendorsById.containsKey(endpoint.Vendor__c)) {
                add(out, 'ERROR', 'ACTIVE_ENDPOINT_PARENT_MISSING', endpoint.DeveloperName,
                    'Active endpoint must reference an existing Vendor Integration record.');
                continue;
            }
            Vendor_Integration__mdt parent = vendorsById.get(endpoint.Vendor__c);
            if (parent.Active__c != true) {
                add(out, 'ERROR', 'ACTIVE_ENDPOINT_INACTIVE_VENDOR', endpoint.DeveloperName,
                    'Deactivate this endpoint until its parent vendor is approved and active.');
            }
            if (String.isBlank(endpoint.Relative_Path__c) ||
                !endpoint.Relative_Path__c.startsWith('/') ||
                endpoint.Relative_Path__c.startsWith('//') ||
                endpoint.Relative_Path__c.contains('://')) {
                add(out, 'ERROR', 'ENDPOINT_RELATIVE_PATH_INVALID', endpoint.DeveloperName,
                    'Relative Path must be a path beginning with /, not an absolute URL.');
            }
            if (String.isBlank(endpoint.HTTP_Method__c)) {
                add(out, 'ERROR', 'ENDPOINT_HTTP_METHOD_MISSING', endpoint.DeveloperName,
                    'HTTP Method is required for an active endpoint.');
            }
            increment(activeEndpointCount, endpoint.Vendor__c);
            if (endpoint.Is_Primary_Pricing_Endpoint__c == true) {
                increment(primaryEndpointCount, endpoint.Vendor__c);
            }
        }

        for (Vendor_Field_Mapping__mdt mapping : snapshot.fieldMappings) {
            if (mapping.Active__c != true) continue;
            if (mapping.Vendor_Endpoint__c == null ||
                !endpointsById.containsKey(mapping.Vendor_Endpoint__c)) {
                add(out, 'ERROR', 'FIELD_MAPPING_ENDPOINT_MISSING', mapping.DeveloperName,
                    'Active field mapping must reference an existing Vendor Endpoint.');
                continue;
            }
            if (String.isBlank(mapping.Internal_Field_Code__c) ||
                String.isBlank(mapping.Vendor_Field_Path__c)) {
                add(out, 'ERROR', 'FIELD_MAPPING_PATH_MISSING', mapping.DeveloperName,
                    'Internal Field Code and Vendor Field Path are required on an active mapping.');
            }
            if (mapping.Direction__c == 'OUTBOUND') increment(outboundCount, mapping.Vendor_Endpoint__c);
            if (mapping.Direction__c == 'INBOUND') increment(inboundCount, mapping.Vendor_Endpoint__c);
        }

        for (Vendor_Value_Mapping__mdt mapping : snapshot.valueMappings) {
            if (mapping.Active__c != true) continue;
            if (mapping.Vendor__c == null || !vendorsById.containsKey(mapping.Vendor__c)) {
                add(out, 'ERROR', 'VALUE_MAPPING_VENDOR_MISSING', mapping.DeveloperName,
                    'Active value mapping must reference an existing Vendor Integration.');
            }
            if (String.isBlank(mapping.Mapping_Group__c) ||
                String.isBlank(mapping.Internal_Value__c) ||
                String.isBlank(mapping.Vendor_Value__c)) {
                add(out, 'ERROR', 'VALUE_MAPPING_VALUES_MISSING', mapping.DeveloperName,
                    'Active value mapping requires Group, Internal Value and Vendor Value.');
            }
        }

        for (Vendor_Integration__mdt vendor : snapshot.vendors) {
            if (vendor.Active__c != true) continue;
            eligibleVendorCount++;
            if (String.isBlank(vendor.Named_Credential_API_Name__c)) {
                add(out, 'ERROR', 'VENDOR_NAMED_CREDENTIAL_MISSING', vendor.DeveloperName,
                    'Active vendor must specify a Named Credential API Name.');
            }
            if (!activeEndpointCount.containsKey(vendor.Id)) {
                add(out, 'ERROR', 'VENDOR_NO_ACTIVE_ENDPOINT', vendor.DeveloperName,
                    'Active vendor must have at least one active endpoint.');
            }
            if (!primaryEndpointCount.containsKey(vendor.Id)) {
                add(out, 'ERROR', 'VENDOR_NO_PRIMARY_QUOTE_ENDPOINT', vendor.DeveloperName,
                    'Active vendor must have at least one primary pricing endpoint.');
            }
        }

        for (Vendor_Endpoint__mdt endpoint : snapshot.endpoints) {
            if (endpoint.Active__c != true || endpoint.Is_Primary_Pricing_Endpoint__c != true) continue;
            if (!outboundCount.containsKey(endpoint.Id)) {
                add(out, 'WARNING', 'PRIMARY_ENDPOINT_NO_OUTBOUND_MAPPING', endpoint.DeveloperName,
                    'No active OUTBOUND field mapping is configured. Verify if an explicit builder is intended.');
            }
            if (!inboundCount.containsKey(endpoint.Id)) {
                add(out, 'WARNING', 'PRIMARY_ENDPOINT_NO_INBOUND_MAPPING', endpoint.DeveloperName,
                    'No active INBOUND field mapping is configured. Verify if an explicit parser is intended.');
            }
        }

        // Diagnostic readiness is intentionally conservative: it is not an API connectivity test.
        out.passesMetadataChecks = eligibleVendorCount > 0 && out.errorCount == 0 && out.warningCount == 0;
        return out;
    }

    private static void increment(Map<Id, Integer> values, Id key) {
        if (key == null) return;
        values.put(key, (values.containsKey(key) ? values.get(key) : 0) + 1);
    }
    private static void add(Result report, String severity, String code,
                            String recordName, String message) {
        report.issues.add(new Issue(severity, code, recordName, message));
        if (severity == 'ERROR') report.errorCount++;
        else if (severity == 'WARNING') report.warningCount++;
    }
    public class VendorPricingAuditException extends Exception {}
}