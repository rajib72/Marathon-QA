/**
 * @description Read-only validation of Vendor Pricing Custom Metadata configuration.
 * No vendor callouts or DML. Inactive drafts do not produce runtime-readiness errors.
 * Configuration integrity and live readiness are intentionally separate results.
 *
 * Multi-endpoint vendors do not require an arbitrarily chosen "primary" endpoint.
 * The configured invocation policy determines which endpoints serve initial pricing.
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
        // True if no errors were found in the configurations this audit evaluates.
        // Draft records remain outside readiness checks; this is not a full draft audit.
        public Boolean configurationValid = false;
        // True only when at least one vendor is active and the checked active config
        // has neither errors nor readiness warnings. Not proof of API connectivity.
        public Boolean runtimeReady = false;
        // Backward-compatible field used by Phase 1A consumers.
        public Boolean passesMetadataChecks = false;
    }

    public class VendorPricingAuditException extends Exception {}

    public static Result run() {
        return evaluate(VendorPricingMetadataRepository.loadForAudit());
    }

    /**
     * Pure validation of an in-memory snapshot; no org-dependent test records needed.
     */
    public static Result evaluate(VendorPricingMetadataRepository.Snapshot snapshot) {
        if (snapshot == null) {
            throw new VendorPricingAuditException('A metadata snapshot is required.');
        }

        Result result = new Result();
        result.vendorsChecked = snapshot.vendors.size();
        result.endpointsChecked = snapshot.endpoints.size();
        result.fieldsChecked = snapshot.fieldMappings.size();
        result.valuesChecked = snapshot.valueMappings.size();

        Map<Id, Vendor_Integration__mdt> vendorsById =
            new Map<Id, Vendor_Integration__mdt>();
        Map<Id, Vendor_Endpoint__mdt> endpointsById =
            new Map<Id, Vendor_Endpoint__mdt>();
        Map<Id, Integer> activeEndpointCount = new Map<Id, Integer>();
        Map<Id, Integer> quoteEndpointCount = new Map<Id, Integer>();
        Map<Id, Integer> outboundCount = new Map<Id, Integer>();
        Map<Id, Integer> inboundCount = new Map<Id, Integer>();
        Integer activeVendors = 0;

        for (Vendor_Integration__mdt vendor : snapshot.vendors) {
            if (vendor.Id != null) {
                vendorsById.put(vendor.Id, vendor);
            }
        }
        for (Vendor_Endpoint__mdt endpoint : snapshot.endpoints) {
            if (endpoint.Id != null) {
                endpointsById.put(endpoint.Id, endpoint);
            }
        }

        for (Vendor_Endpoint__mdt endpoint : snapshot.endpoints) {
            if (endpoint.Active__c != true) continue;

            // Deliberately validate the endpoint's own properties even when the
            // parent is missing; an early 'continue' hid an invalid URL before.
            Boolean parentExists = endpoint.Vendor__c != null &&
                vendorsById.containsKey(endpoint.Vendor__c);
            if (!parentExists) {
                add(result, 'ERROR', 'ACTIVE_ENDPOINT_PARENT_MISSING',
                    endpoint.DeveloperName,
                    'Active endpoint must reference an existing Vendor Integration.');
            } else if (vendorsById.get(endpoint.Vendor__c).Active__c != true) {
                add(result, 'ERROR', 'ACTIVE_ENDPOINT_INACTIVE_VENDOR',
                    endpoint.DeveloperName,
                    'Active endpoint has an inactive parent vendor.');
            }

            if (String.isBlank(endpoint.Relative_Path__c) ||
                !endpoint.Relative_Path__c.startsWith('/') ||
                endpoint.Relative_Path__c.startsWith('//') ||
                endpoint.Relative_Path__c.contains('://')) {
                add(result, 'ERROR', 'ENDPOINT_RELATIVE_PATH_INVALID',
                    endpoint.DeveloperName,
                    'Relative Path must start with one / and cannot be an absolute URL.');
            }
            if (String.isBlank(endpoint.HTTP_Method__c)) {
                add(result, 'ERROR', 'ENDPOINT_HTTP_METHOD_MISSING',
                    endpoint.DeveloperName,
                    'HTTP Method is required on active endpoints.');
            }

            if (parentExists) {
                increment(activeEndpointCount, endpoint.Vendor__c);
                if (isQuoteRequestEndpoint(endpoint)) {
                    increment(quoteEndpointCount, endpoint.Vendor__c);
                }
            }
        }

        for (Vendor_Field_Mapping__mdt mapping : snapshot.fieldMappings) {
            if (mapping.Active__c != true) continue;

            Boolean endpointExists = mapping.Vendor_Endpoint__c != null &&
                endpointsById.containsKey(mapping.Vendor_Endpoint__c);
            if (!endpointExists) {
                add(result, 'ERROR', 'FIELD_MAPPING_ENDPOINT_MISSING',
                    mapping.DeveloperName,
                    'Active field mapping must reference an existing endpoint.');
            }
            if (String.isBlank(mapping.Internal_Field_Code__c) ||
                String.isBlank(mapping.Vendor_Field_Path__c)) {
                add(result, 'ERROR', 'FIELD_MAPPING_PATH_MISSING',
                    mapping.DeveloperName,
                    'Internal Field Code and Vendor Field Path are required.');
            }
            if (mapping.Direction__c != 'OUTBOUND' &&
                mapping.Direction__c != 'INBOUND' &&
                mapping.Direction__c != 'ERROR') {
                add(result, 'ERROR', 'FIELD_MAPPING_DIRECTION_INVALID',
                    mapping.DeveloperName,
                    'Active field mapping requires OUTBOUND, INBOUND or ERROR.');
            }
            if (endpointExists) {
                if (mapping.Direction__c == 'OUTBOUND') {
                    increment(outboundCount, mapping.Vendor_Endpoint__c);
                } else if (mapping.Direction__c == 'INBOUND') {
                    increment(inboundCount, mapping.Vendor_Endpoint__c);
                }
            }
        }

        for (Vendor_Value_Mapping__mdt mapping : snapshot.valueMappings) {
            if (mapping.Active__c != true) continue;
            if (mapping.Vendor__c == null ||
                !vendorsById.containsKey(mapping.Vendor__c)) {
                add(result, 'ERROR', 'VALUE_MAPPING_VENDOR_MISSING',
                    mapping.DeveloperName,
                    'Active value mapping must reference an existing vendor.');
            }
            if (String.isBlank(mapping.Mapping_Group__c) ||
                String.isBlank(mapping.Internal_Value__c) ||
                String.isBlank(mapping.Vendor_Value__c)) {
                add(result, 'ERROR', 'VALUE_MAPPING_VALUES_MISSING',
                    mapping.DeveloperName,
                    'Active value mapping requires group, internal and vendor values.');
            }
        }

        for (Vendor_Integration__mdt vendor : snapshot.vendors) {
            if (vendor.Active__c != true) continue;
            activeVendors++;

            if (String.isBlank(vendor.Named_Credential_API_Name__c)) {
                add(result, 'ERROR', 'VENDOR_NAMED_CREDENTIAL_MISSING',
                    vendor.DeveloperName,
                    'Active vendor requires a Named Credential API Name.');
            }
            if (vendor.Id == null || !activeEndpointCount.containsKey(vendor.Id)) {
                add(result, 'ERROR', 'VENDOR_NO_ACTIVE_ENDPOINT',
                    vendor.DeveloperName,
                    'Active vendor requires at least one active endpoint.');
            }
            if (vendor.Id == null || !quoteEndpointCount.containsKey(vendor.Id)) {
                add(result, 'ERROR', 'VENDOR_NO_QUOTE_REQUEST_ENDPOINT',
                    vendor.DeveloperName,
                    'Active vendor requires an active quotation request endpoint; no global primary flag is needed.');
            }
        }

        for (Vendor_Endpoint__mdt endpoint : snapshot.endpoints) {
            if (endpoint.Active__c != true || !isQuoteRequestEndpoint(endpoint)) continue;
            // If the parent vendor is inactive, the corresponding error above is enough.
            if (endpoint.Vendor__c == null ||
                !vendorsById.containsKey(endpoint.Vendor__c) ||
                vendorsById.get(endpoint.Vendor__c).Active__c != true) continue;

            if (endpoint.Id == null || !outboundCount.containsKey(endpoint.Id)) {
                add(result, 'WARNING', 'QUOTE_ENDPOINT_NO_OUTBOUND_MAPPING',
                    endpoint.DeveloperName,
                    'No active OUTBOUND mapping; confirm that a supported explicit builder is configured.');
            }
            if (endpoint.Id == null || !inboundCount.containsKey(endpoint.Id)) {
                add(result, 'WARNING', 'QUOTE_ENDPOINT_NO_INBOUND_MAPPING',
                    endpoint.DeveloperName,
                    'No active INBOUND mapping; confirm that a supported explicit parser is configured.');
            }
        }

        result.configurationValid = (result.errorCount == 0);
        result.runtimeReady = activeVendors > 0 &&
            result.errorCount == 0 && result.warningCount == 0;
        result.passesMetadataChecks = result.runtimeReady;
        return result;
    }

    /**
     * Recognizes pricing discovery operations, without requiring one arbitrary
     * Is_Primary_Pricing_Endpoint__c on multi-search vendors such as C&K.
     * A later endpoint resolver will apply domain and search-mode eligibility.
     */
    @TestVisible
    private static Boolean isQuoteRequestEndpoint(Vendor_Endpoint__mdt endpoint) {
        if (String.isNotBlank(endpoint.Invocation_Policy__c)) {
            return endpoint.Invocation_Policy__c == 'INITIAL_PRICING';
        }
        // Older test fixtures and records can predate the invocation policy field.
        if (String.isBlank(endpoint.Operation__c)) return false;
        String operation = endpoint.Operation__c.trim().toUpperCase();
        if (new Set<String>{
            'GET_QUOTE', 'QUOTE_RETRIEVE', 'QUOTE_SUMMARY', 'QUOTE_STATUS',
            'DETAILED_PRICE_CHECK', 'TOKEN', 'TOKEN_REFRESH'
        }.contains(operation)) {
            return false;
        }
        return operation.contains('QUOTE') || operation.contains('PRICING');
    }

    private static void increment(Map<Id, Integer> counts, Id key) {
        if (key == null) return;
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }

    private static void add(Result report, String severity, String code,
                            String recordName, String message) {
        report.issues.add(new Issue(severity, code, recordName, message));
        if (severity == 'ERROR') report.errorCount++;
        else if (severity == 'WARNING') report.warningCount++;
    }
}