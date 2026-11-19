/** Executes prepared quote requests for one initial-pricing route at a time. */
public with sharing class VendorPricingCalloutService {
    public class BatchResult {
        public List<String> rowKeys;
        public Map<String, String> rowKeyByRequestKey;
        public VendorPricingHttpTransport.Response response;

        public BatchResult(
            VendorPricingRequestBuilder.PreparedRequest prepared,
            VendorPricingHttpTransport.Response response
        ) {
            this.rowKeys = prepared.rowKeys.clone();
            this.rowKeyByRequestKey = prepared.rowKeyByRequestKey.clone();
            this.response = response;
        }
    }

    public class Result {
        public VendorPricingValidationService.Result validation;
        public List<VendorPricingRequestBuilder.Issue> preparationIssues = new List<VendorPricingRequestBuilder.Issue>();
        public List<BatchResult> batches = new List<BatchResult>();
    }

    public static Result execute(
        VendorPricingRequestContext context,
        VendorEndpointResolver.Route route,
        Set<String> rowKeys,
        VendorPricingRequestBuilder.Options options
    ) {
        return execute(context, route, rowKeys, options, null);
    }

    public static Result execute(
        VendorPricingRequestContext context,
        VendorEndpointResolver.Route route,
        Set<String> rowKeys,
        VendorPricingRequestBuilder.Options options,
        String accessToken
    ) {
        if (route == null || route.endpointId == null) {
            Result result = new Result();
            result.preparationIssues.add(new VendorPricingRequestBuilder.Issue(
                'CALLOUT_ROUTE_REQUIRED', null, 'Select a resolved pricing route before sending a request.'
            ));
            return result;
        }
        VendorPricingRequestBuilder.Result prepared = VendorPricingRequestBuilder.build(context, route, rowKeys, options);
        VendorPricingMetadataRepository.CalloutConfiguration configuration = prepared.requests.isEmpty()
            ? null : VendorPricingMetadataRepository.loadForCallout(route.endpointId);
        return executePrepared(route, prepared, configuration, accessToken);
    }

    @TestVisible
    private static Result executePrepared(
        VendorEndpointResolver.Route route,
        VendorPricingRequestBuilder.Result prepared,
        VendorPricingMetadataRepository.CalloutConfiguration configuration,
        String accessToken
    ) {
        Result result = new Result();
        result.validation = prepared.validation;
        result.preparationIssues.addAll(prepared.issues);
        if (prepared.requests.isEmpty()) {
            return result;
        }
        if (!matchesActiveRoute(route, prepared, configuration)) {
            result.preparationIssues.add(new VendorPricingRequestBuilder.Issue(
                'CALLOUT_ROUTE_UNAVAILABLE', null, 'The resolved route is unavailable for active initial pricing.'
            ));
            return result;
        }
        Boolean resolveToken = accessToken == null &&
            VendorPricingAuthenticationService.appliesTo(configuration);
        for (VendorPricingRequestBuilder.PreparedRequest request : prepared.requests) {
            VendorPricingHttpTransport.Response response = resolveToken
                ? VendorPricingAuthenticationService.send(configuration, request.jsonBody)
                : VendorPricingHttpTransport.send(configuration, request.jsonBody, accessToken);
            result.batches.add(new BatchResult(request, response));
        }
        return result;
    }

    private static Boolean matchesActiveRoute(
        VendorEndpointResolver.Route route,
        VendorPricingRequestBuilder.Result prepared,
        VendorPricingMetadataRepository.CalloutConfiguration configuration
    ) {
        if (configuration == null || configuration.endpoint == null || configuration.vendor == null) {
            return false;
        }
        Vendor_Endpoint__mdt endpoint = configuration.endpoint;
        Vendor_Integration__mdt vendor = configuration.vendor;
        return endpoint.Active__c == true && vendor.Active__c == true &&
            vendor.Include_in_All_Vendor_Search__c == true &&
            endpoint.Invocation_Policy__c == 'INITIAL_PRICING' && endpoint.Id == route.endpointId &&
            endpoint.DeveloperName == route.endpointDeveloperName &&
            endpoint.DeveloperName == prepared.endpointDeveloperName &&
            endpoint.Operation__c == route.operation && endpoint.Vendor__c == vendor.Id &&
            vendor.DeveloperName == route.vendorDeveloperName;
    }
}