/** Resolves initial pricing endpoints for the shared pricing context. */
public with sharing class VendorEndpointResolver {
    public class Issue {
        public String code;
        public String vendorDeveloperName;
        public String message;

        public Issue(String code, String vendorDeveloperName, String message) {
            this.code = code;
            this.vendorDeveloperName = vendorDeveloperName;
            this.message = message;
        }
    }

    public class Route {
        public String vendorDeveloperName;
        public String operation;
        public Id endpointId;
        public String endpointDeveloperName;

        public Route(String vendorDeveloperName, Vendor_Endpoint__mdt endpoint) {
            this.vendorDeveloperName = vendorDeveloperName;
            this.operation = endpoint.Operation__c;
            this.endpointId = endpoint.Id;
            this.endpointDeveloperName = endpoint.DeveloperName;
        }
    }

    public class RowPlan {
        public String rowKey;
        public String searchMode;
        public String searchKey;
        public List<Route> routes = new List<Route>();
        public List<Issue> issues = new List<Issue>();
    }

    public class Result {
        public VendorPricingValidationService.Result validation;
        public List<RowPlan> rows = new List<RowPlan>();
    }

    public static Result resolve(VendorPricingRequestContext context) {
        return resolve(context, null);
    }

    public static Result resolve(VendorPricingRequestContext context, Map<String, String> searchVariantByRowKey) {
        return resolve(context, searchVariantByRowKey, null);
    }

    @TestVisible
    private static Result resolve(
        VendorPricingRequestContext context, Map<String, String> searchVariantByRowKey,
        VendorPricingMetadataRepository.EndpointConfiguration configuration
    ) {
        Result result = new Result();
        result.validation = VendorPricingValidationService.validate(context);
        if (result.validation.validRowKeys.isEmpty()) {
            return result;
        }
        if (configuration == null) {
            configuration = VendorPricingMetadataRepository.loadForEndpointResolution();
        }
        Map<Id, List<Vendor_Endpoint__mdt>> endpointsByVendorId = new Map<Id, List<Vendor_Endpoint__mdt>>();
        for (Vendor_Endpoint__mdt endpoint : configuration.endpoints) {
            if (endpoint.Active__c != true || endpoint.Invocation_Policy__c != 'INITIAL_PRICING' ||
                endpoint.Vendor__c == null) {
                continue;
            }
            if (!endpointsByVendorId.containsKey(endpoint.Vendor__c)) {
                endpointsByVendorId.put(endpoint.Vendor__c, new List<Vendor_Endpoint__mdt>());
            }
            endpointsByVendorId.get(endpoint.Vendor__c).add(endpoint);
        }

        Set<String> validKeys = new Set<String>(result.validation.validRowKeys);
        for (VendorPricingLineContext line : context.lines) {
            if (line == null || !validKeys.contains(line.rowKey)) {
                continue;
            }
            RowPlan plan = new RowPlan();
            plan.rowKey = line.rowKey;
            plan.searchMode = line.searchMode;
            plan.searchKey = searchKey(line, searchVariantByRowKey);
            for (Vendor_Integration__mdt vendor : configuration.vendors) {
                if (vendor.Active__c == true && vendor.Include_in_All_Vendor_Search__c == true &&
                    endpointsByVendorId.containsKey(vendor.Id)) {
                    resolveVendor(plan, vendor, endpointsByVendorId.get(vendor.Id));
                }
            }
            if (plan.routes.isEmpty() && plan.issues.isEmpty()) {
                plan.issues.add(new Issue(
                    'NO_ELIGIBLE_PRICING_ENDPOINT', null,
                    'No eligible initial pricing endpoint is configured for this row.'
                ));
            }
            result.rows.add(plan);
        }
        return result;
    }

    private static void resolveVendor(
        RowPlan plan, Vendor_Integration__mdt vendor, List<Vendor_Endpoint__mdt> endpoints
    ) {
        Vendor_Endpoint__mdt winner;
        Integer bestRank = 0;
        Boolean tied = false;
        for (Vendor_Endpoint__mdt endpoint : endpoints) {
            Integer match = endpointRank(endpoint, plan.searchKey);
            if (match == 0) {
                continue;
            }
            Integer rank = match * 2 + (endpoint.Is_Primary_Pricing_Endpoint__c == true ? 1 : 0);
            if (rank > bestRank) {
                winner = endpoint;
                bestRank = rank;
                tied = false;
            } else if (rank == bestRank) {
                tied = true;
            }
        }
        if (tied) {
            plan.issues.add(new Issue(
                'AMBIGUOUS_PRICING_ENDPOINT', vendor.DeveloperName,
                'Multiple endpoints match this search. Review the vendor endpoint search modes.'
            ));
        } else if (winner != null) {
            plan.routes.add(new Route(vendor.DeveloperName, winner));
        }
    }

    public static String searchKey(VendorPricingLineContext line, Map<String, String> searchVariantByRowKey) {
        if (String.isBlank(line.searchMode)) {
            return null;
        }
        String mode = line.searchMode.trim().toUpperCase();
        String variant = searchVariantByRowKey == null ? null : searchVariantByRowKey.get(line.rowKey);
        return String.isBlank(variant) ? mode : mode + ':' + variant.trim().toUpperCase();
    }

    // A qualified search match takes precedence over a matching base mode.
    public static Integer searchRank(String configuredModes, String searchKey) {
        if (String.isBlank(configuredModes) || String.isBlank(searchKey)) {
            return 0;
        }
        Integer separator = searchKey.indexOf(':');
        String baseMode = separator < 0 ? searchKey : searchKey.substring(0, separator);
        Integer rank = 0;
        for (String token : configuredModes.split(',')) {
            String configured = token.trim().toUpperCase();
            if (configured == searchKey && configured.contains(':')) {
                return 2;
            }
            if (configured == baseMode) {
                rank = 1;
            }
        }
        return rank;
    }

    public static Integer endpointRank(Vendor_Endpoint__mdt endpoint, String searchKey) {
        if (String.isNotBlank(endpoint.Supported_Search_Modes__c)) {
            return searchRank(endpoint.Supported_Search_Modes__c, searchKey);
        }
        if (searchKey == 'PART_NUMBER:VENDOR_SKU') {
            return endpoint.Supports_Vendor_SKU_Search__c == true ? 1 : 0;
        }
        if (searchKey == 'PART_NUMBER:POWERTRAIN') {
            return endpoint.Supports_Powertrain__c == true ? 1 : 0;
        }
        if (searchKey == 'PART_NUMBER' || searchKey == 'PART_NUMBER:OEM') {
            return endpoint.Supports_Standard_Parts__c == true ? 1 : 0;
        }
        if (searchKey == 'LOSS_CATEGORY') {
            return endpoint.Supports_Terminology_Search__c == true ? 1 : 0;
        }
        return 0;
    }
}