/**
 * In-memory Custom Metadata unit tests. No DML, callouts or SeeAllData=true.
 * Synthetic metadata IDs are used only to exercise relationship logic.
 */
@IsTest
private class VendorPricingMetadataAuditTest {
    // Custom Metadata IDs have the m00 prefix; JSON builds realistic in-memory
    // records without trying to perform DML on __mdt objects.
    private static final String VENDOR_ID = 'm00000000000001';
    private static final String ENDPOINT_ID = 'm00000000000003';
    private static final String TOKEN_ENDPOINT_ID = 'm00000000000004';

    private static VendorPricingMetadataRepository.Snapshot fresh() {
        return new VendorPricingMetadataRepository.Snapshot();
    }

    private static Vendor_Integration__mdt vendor(String id, Boolean active,
                                                  String credential) {
        return (Vendor_Integration__mdt) JSON.deserialize(JSON.serialize(
            new Map<String, Object>{
                'Id' => id,
                'DeveloperName' => 'TEST_VENDOR',
                'Active__c' => active,
                'Named_Credential_API_Name__c' => credential
            }), Vendor_Integration__mdt.class);
    }

    private static Vendor_Endpoint__mdt endpoint(String id, String vendorId,
                                                 Boolean active, String operation,
                                                 String method, String path) {
        return (Vendor_Endpoint__mdt) JSON.deserialize(JSON.serialize(
            new Map<String, Object>{
                'Id' => id,
                'DeveloperName' => 'TEST_ENDPOINT',
                'Vendor__c' => vendorId,
                'Active__c' => active,
                'Operation__c' => operation,
                'HTTP_Method__c' => method,
                'Relative_Path__c' => path,
                'Is_Primary_Pricing_Endpoint__c' => false
            }), Vendor_Endpoint__mdt.class);
    }

    private static Vendor_Field_Mapping__mdt fieldMapping(String endpointId,
                                                           String direction,
                                                           String code,
                                                           String path) {
        return (Vendor_Field_Mapping__mdt) JSON.deserialize(JSON.serialize(
            new Map<String, Object>{
                'DeveloperName' => 'TEST_FIELD',
                'Active__c' => true,
                'Vendor_Endpoint__c' => endpointId,
                'Direction__c' => direction,
                'Internal_Field_Code__c' => code,
                'Vendor_Field_Path__c' => path
            }), Vendor_Field_Mapping__mdt.class);
    }

    private static Vendor_Value_Mapping__mdt valueMapping(String vendorId,
                                                           String groupCode,
                                                           String internalValue,
                                                           String vendorValue) {
        return (Vendor_Value_Mapping__mdt) JSON.deserialize(JSON.serialize(
            new Map<String, Object>{
                'DeveloperName' => 'TEST_VALUE',
                'Active__c' => true,
                'Vendor__c' => vendorId,
                'Mapping_Group__c' => groupCode,
                'Internal_Value__c' => internalValue,
                'Vendor_Value__c' => vendorValue
            }), Vendor_Value_Mapping__mdt.class);
    }

    private static Set<String> codes(VendorPricingMetadataAudit.Result r) {
        Set<String> result = new Set<String>();
        for (VendorPricingMetadataAudit.Issue issue : r.issues) {
            result.add(issue.code);
        }
        return result;
    }

    @IsTest static void emptySnapshotIsNotRuntimeReady() {
        VendorPricingMetadataAudit.Result r =
            VendorPricingMetadataAudit.evaluate(fresh());
        System.assertEquals(0, r.errorCount);
        System.assertEquals(0, r.warningCount);
        System.assertEquals(0, r.vendorsChecked);
        System.assertEquals(true, r.configurationValid);
        System.assertEquals(false, r.runtimeReady);
        System.assertEquals(false, r.passesMetadataChecks);
    }

    @IsTest static void inactiveDraftDoesNotCauseReadinessErrors() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, false, null));
        s.endpoints.add(endpoint(ENDPOINT_ID, VENDOR_ID, false,
                                 'QUOTE_CREATE', null, null));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(1, r.vendorsChecked);
        System.assertEquals(1, r.endpointsChecked);
        System.assertEquals(0, r.errorCount);
        System.assertEquals(true, r.configurationValid);
        System.assertEquals(false, r.runtimeReady);
    }

    @IsTest static void activeVendorWithoutAnyEndpointIsRejected() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, true, null));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(3, r.errorCount, JSON.serialize(r.issues));
        Set<String> issueCodes = codes(r);
        System.assert(issueCodes.contains('VENDOR_NAMED_CREDENTIAL_MISSING'));
        System.assert(issueCodes.contains('VENDOR_NO_ACTIVE_ENDPOINT'));
        System.assert(issueCodes.contains('VENDOR_NO_QUOTE_REQUEST_ENDPOINT'));
        System.assertEquals(false, r.runtimeReady);
    }

    @IsTest static void orphanEndpointAndIncompleteMappingsAreRejected() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.endpoints.add(endpoint(ENDPOINT_ID, null, true, 'OTHER',
                                 'POST', 'https://unsafe.example/api'));
        s.fieldMappings.add(fieldMapping(null, 'OUTBOUND', null, null));
        s.valueMappings.add(valueMapping(null, null, null, null));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        // 2 endpoint errors (missing parent, absolute URL), 2 field errors
        // (missing endpoint, path), and 2 value errors (vendor, values).
        System.assertEquals(6, r.errorCount, JSON.serialize(r.issues));
        System.assertEquals(1, r.fieldsChecked);
        System.assertEquals(1, r.valuesChecked);
        System.assert(codes(r).contains('ENDPOINT_RELATIVE_PATH_INVALID'));
        System.assert(codes(r).contains('FIELD_MAPPING_PATH_MISSING'));
    }

    @IsTest static void activeEndpointWithInactiveVendorAndMissingMethod() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, false, 'NC_TEST'));
        s.endpoints.add(endpoint(ENDPOINT_ID, VENDOR_ID, true,
                                 'TOKEN', null, '//invalid'));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(3, r.errorCount, JSON.serialize(r.issues));
        System.assert(codes(r).contains('ACTIVE_ENDPOINT_INACTIVE_VENDOR'));
        System.assert(codes(r).contains('ENDPOINT_HTTP_METHOD_MISSING'));
    }

    @IsTest static void quoteEndpointWithoutFieldMappingsHasWarnings() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, true, 'NC_TEST'));
        s.endpoints.add(endpoint(ENDPOINT_ID, VENDOR_ID, true,
                                 'QUOTE_CREATE', 'POST', '/api/quote'));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(0, r.errorCount, JSON.serialize(r.issues));
        System.assertEquals(2, r.warningCount);
        System.assertEquals(true, r.configurationValid);
        System.assertEquals(false, r.runtimeReady);
        System.assert(codes(r).contains('QUOTE_ENDPOINT_NO_OUTBOUND_MAPPING'));
        System.assert(codes(r).contains('QUOTE_ENDPOINT_NO_INBOUND_MAPPING'));
    }

    @IsTest static void quoteEndpointDoesNotNeedPrimaryFlag() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, true, 'NC_TEST'));
        s.endpoints.add(endpoint(TOKEN_ENDPOINT_ID, VENDOR_ID, true,
                                 'TOKEN', 'POST', '/api/token'));
        s.endpoints.add(endpoint(ENDPOINT_ID, VENDOR_ID, true,
                                 'QUOTE_CREATE', 'POST', '/api/quote'));
        s.fieldMappings.add(fieldMapping(ENDPOINT_ID, 'OUTBOUND', 'VIN', 'vin'));
        s.fieldMappings.add(fieldMapping(ENDPOINT_ID, 'INBOUND', 'TOTAL_PRICE', 'totalPrice'));
        s.fieldMappings.add(fieldMapping(ENDPOINT_ID, 'ERROR', 'ERROR_MESSAGE', 'message'));
        s.valueMappings.add(valueMapping(VENDOR_ID, 'COUNTRY_CODE', 'US', 'USA'));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(0, r.errorCount, JSON.serialize(r.issues));
        System.assertEquals(0, r.warningCount, JSON.serialize(r.issues));
        System.assertEquals(true, r.configurationValid);
        System.assertEquals(true, r.runtimeReady);
        System.assertEquals(true, r.passesMetadataChecks);
    }

    @IsTest static void tokenEndpointAloneIsNotSufficientForPricing() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, true, 'NC_TEST'));
        s.endpoints.add(endpoint(TOKEN_ENDPOINT_ID, VENDOR_ID, true,
                                 'TOKEN', 'POST', '/api/token'));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(1, r.errorCount, JSON.serialize(r.issues));
        System.assert(codes(r).contains('VENDOR_NO_QUOTE_REQUEST_ENDPOINT'));
        System.assertEquals(false, r.runtimeReady);
    }

    @IsTest static void invalidDirectionIsRejectedWithoutHidingValidLinks() {
        VendorPricingMetadataRepository.Snapshot s = fresh();
        s.vendors.add(vendor(VENDOR_ID, true, 'NC_TEST'));
        s.endpoints.add(endpoint(ENDPOINT_ID, VENDOR_ID, true,
                                 'OEM_QUOTE', 'POST', '/api/oem'));
        s.fieldMappings.add(fieldMapping(ENDPOINT_ID, 'BAD', 'VIN', 'vin'));
        VendorPricingMetadataAudit.Result r = VendorPricingMetadataAudit.evaluate(s);
        System.assertEquals(1, r.errorCount, JSON.serialize(r.issues));
        System.assert(codes(r).contains('FIELD_MAPPING_DIRECTION_INVALID'));
    }

    @IsTest static void noQuoteOperationsAreExcluded() {
        for (String code : new List<String>{
            'TOKEN', 'TOKEN_REFRESH', 'GET_QUOTE', 'QUOTE_RETRIEVE',
            'QUOTE_SUMMARY', 'QUOTE_STATUS', 'DETAILED_PRICE_CHECK'
        }) {
            System.assertEquals(false,
                VendorPricingMetadataAudit.isQuoteRequestEndpoint(
                    new Vendor_Endpoint__mdt(Operation__c = code)), code);
        }
        System.assertEquals(false,
            VendorPricingMetadataAudit.isQuoteRequestEndpoint(new Vendor_Endpoint__mdt()));
        for (String code : new List<String>{
            'QUOTE_CREATE', 'QUOTE_CREATE_SIMPLE', 'OEM_QUOTE',
            'POWERTRAIN_QUOTE', 'UNIVERSAL_QUOTE', 'LABOR_PRICING'
        }) {
            System.assertEquals(true,
                VendorPricingMetadataAudit.isQuoteRequestEndpoint(
                    new Vendor_Endpoint__mdt(Operation__c = code)), code);
        }
    }

    @IsTest static void nullSnapshotThrowsFriendlyException() {
        try {
            VendorPricingMetadataAudit.evaluate(null);
            System.assert(false, 'Expected VendorPricingAuditException');
        } catch (VendorPricingMetadataAudit.VendorPricingAuditException ex) {
            System.assert(ex.getMessage().contains('snapshot'));
        }
    }

    @IsTest static void explicitInvocationPolicyDeterminesEndpointRole() {
        Vendor_Endpoint__mdt initial = new Vendor_Endpoint__mdt(
            Operation__c = 'ESTIMATE', Invocation_Policy__c = 'INITIAL_PRICING'
        );
        Vendor_Endpoint__mdt followUp = new Vendor_Endpoint__mdt(
            Operation__c = 'QUOTE_CREATE', Invocation_Policy__c = 'ON_DEMAND'
        );
        System.assert(VendorPricingMetadataAudit.isQuoteRequestEndpoint(initial));
        System.assert(!VendorPricingMetadataAudit.isQuoteRequestEndpoint(followUp));
    }

    @IsTest static void repositoryLoadAndRunSmokeTest() {
        Test.startTest();
        VendorPricingMetadataAudit.Result report = VendorPricingMetadataAudit.run();
        Test.stopTest();
        System.assertNotEquals(null, report);
        System.assert(report.vendorsChecked >= 0);
        System.assert(report.endpointsChecked >= 0);
        System.assert(report.fieldsChecked >= 0);
        System.assert(report.valuesChecked >= 0);
    }
}