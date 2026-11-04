@IsTest
private class VendorPricingMetadataAuditTest {
    @IsTest
    static void emptySnapshotIsNotLiveReady() {
        VendorPricingMetadataRepository.Snapshot snapshot =
            new VendorPricingMetadataRepository.Snapshot();
        Test.startTest();
        VendorPricingMetadataAudit.Result result =
            VendorPricingMetadataAudit.evaluate(snapshot);
        Test.stopTest();
        System.assertEquals(0, result.errorCount);
        System.assertEquals(false, result.passesMetadataChecks);
    }

    @IsTest
    static void inactiveDraftDoesNotCauseReadinessErrors() {
        VendorPricingMetadataRepository.Snapshot snapshot =
            new VendorPricingMetadataRepository.Snapshot();
        snapshot.vendors.add(new Vendor_Integration__mdt(
            DeveloperName = 'TEAL', Active__c = false
        ));
        VendorPricingMetadataAudit.Result result =
            VendorPricingMetadataAudit.evaluate(snapshot);
        System.assertEquals(1, result.vendorsChecked);
        System.assertEquals(0, result.errorCount);
        System.assertEquals(false, result.passesMetadataChecks);
    }

    @IsTest
    static void activeVendorWithNoConfigurationIsRejected() {
        VendorPricingMetadataRepository.Snapshot snapshot =
            new VendorPricingMetadataRepository.Snapshot();
        snapshot.vendors.add(new Vendor_Integration__mdt(
            DeveloperName = 'TEST_VENDOR', Active__c = true
        ));
        VendorPricingMetadataAudit.Result result =
            VendorPricingMetadataAudit.evaluate(snapshot);
        System.assertEquals(3, result.errorCount);
        Set<String> codes = new Set<String>();
        for (VendorPricingMetadataAudit.Issue issue : result.issues) codes.add(issue.code);
        System.assert(codes.contains('VENDOR_NAMED_CREDENTIAL_MISSING'));
        System.assert(codes.contains('VENDOR_NO_ACTIVE_ENDPOINT'));
        System.assert(codes.contains('VENDOR_NO_PRIMARY_QUOTE_ENDPOINT'));
    }

    @IsTest
    static void orphanActiveEndpointAndIncompleteMappingsAreRejected() {
        VendorPricingMetadataRepository.Snapshot snapshot =
            new VendorPricingMetadataRepository.Snapshot();
        snapshot.endpoints.add(new Vendor_Endpoint__mdt(
            DeveloperName = 'TEST_ENDPOINT', Active__c = true,
            HTTP_Method__c = 'POST', Relative_Path__c = 'https://unsafe.example/api'
        ));
        snapshot.fieldMappings.add(new Vendor_Field_Mapping__mdt(
            DeveloperName = 'TEST_FIELD', Active__c = true
        ));
        snapshot.valueMappings.add(new Vendor_Value_Mapping__mdt(
            DeveloperName = 'TEST_VALUE', Active__c = true
        ));
        VendorPricingMetadataAudit.Result result =
            VendorPricingMetadataAudit.evaluate(snapshot);
        System.assertEquals(5, result.errorCount);
    }

    @IsTest
    static void nullSnapshotIsNotAllowed() {
        try {
            VendorPricingMetadataAudit.evaluate(null);
            System.assert(false, 'Expected exception');
        } catch (VendorPricingMetadataAudit.VendorPricingAuditException ex) {
            System.assert(ex.getMessage().contains('snapshot'));
        }
    }
}