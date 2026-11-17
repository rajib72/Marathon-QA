@IsTest
private class VendorEndpointResolverTest {
    private static final Id A = 'm00000000000001';
    private static final Id B = 'm00000000000002';

    private static VendorPricingRequestContext pricingContext() {
        VendorPricingRequestContext context = new VendorPricingRequestContext();
        context.claimId = (Id)(Claim.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        context.vin = '1HGCM82633A004352';
        context.repairShopAccountId = '001000000000001';
        context.repairShopStreet = '100 Main St';
        context.repairShopCity = 'Los Angeles';
        context.repairShopState = 'CA';
        context.repairShopPostalCode = '90001';
        VendorPricingLineContext line = new VendorPricingLineContext();
        line.rowKey = 'line';
        line.detailType = 'Part';
        line.searchMode = 'PART_NUMBER';
        line.partNumber = 'P-123';
        line.adjustedQuantity = 1;
        context.lines.add(line);
        return context;
    }

    private static Vendor_Integration__mdt vendor(Id recordId, String name, Boolean includeInAll) {
        return (Vendor_Integration__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Id' => recordId, 'DeveloperName' => name, 'Active__c' => true,
            'Include_in_All_Vendor_Search__c' => includeInAll
        }), Vendor_Integration__mdt.class);
    }

    private static Vendor_Endpoint__mdt endpoint(Id vendorId, String name, String modes) {
        return (Vendor_Endpoint__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'Vendor__c' => vendorId, 'DeveloperName' => name, 'Active__c' => true,
            'Operation__c' => 'ESTIMATE', 'Invocation_Policy__c' => 'INITIAL_PRICING',
            'Supported_Search_Modes__c' => modes
        }), Vendor_Endpoint__mdt.class);
    }

    @IsTest
    static void matchesEveryConfiguredSupplierAndPrefersTheSpecificVariant() {
        VendorPricingMetadataRepository.EndpointConfiguration config =
            new VendorPricingMetadataRepository.EndpointConfiguration();
        config.vendors.add(vendor(A, 'SUPPLIER_A', true));
        config.vendors.add(vendor(B, 'SUPPLIER_B', true));
        Vendor_Endpoint__mdt broad = endpoint(A, 'GENERAL_PARTS', 'PART_NUMBER');
        broad.Is_Primary_Pricing_Endpoint__c = true;
        config.endpoints.add(broad);
        config.endpoints.add(endpoint(A, 'EXACT_PARTS', 'PART_NUMBER:MAKER'));
        config.endpoints.add(endpoint(B, 'OTHER_ESTIMATES', 'PART_NUMBER, LOSS_CATEGORY'));

        VendorEndpointResolver.Result result = VendorEndpointResolver.resolve(
            pricingContext(), new Map<String, String>{'line' => ' maker '}, config
        );

        System.assertEquals(2, result.rows[0].routes.size());
        System.assertEquals('EXACT_PARTS', result.rows[0].routes[0].endpointDeveloperName);
        System.assertEquals('OTHER_ESTIMATES', result.rows[0].routes[1].endpointDeveloperName);
        System.assertEquals('ESTIMATE', result.rows[0].routes[1].operation);
        System.assertEquals('PART_NUMBER:MAKER', result.rows[0].searchKey);
        System.assertEquals(0, result.rows[0].issues.size());
    }

    @IsTest
    static void preservesOtherSuppliersWhenOneIsAmbiguousAndUsesOptionalPrimary() {
        VendorPricingMetadataRepository.EndpointConfiguration config =
            new VendorPricingMetadataRepository.EndpointConfiguration();
        config.vendors.add(vendor(A, 'SUPPLIER_A', true));
        config.vendors.add(vendor(B, 'SUPPLIER_B', true));
        Vendor_Endpoint__mdt first = endpoint(A, 'FIRST', 'PART_NUMBER');
        config.endpoints.add(first);
        config.endpoints.add(endpoint(A, 'SECOND', 'PART_NUMBER'));
        config.endpoints.add(endpoint(B, 'OTHER', 'PART_NUMBER'));
        VendorPricingRequestContext context = pricingContext();

        VendorEndpointResolver.Result result = VendorEndpointResolver.resolve(context, null, config);
        System.assertEquals(1, result.rows[0].routes.size());
        System.assertEquals('SUPPLIER_B', result.rows[0].routes[0].vendorDeveloperName);
        System.assertEquals('AMBIGUOUS_PRICING_ENDPOINT', result.rows[0].issues[0].code);
        System.assertEquals('SUPPLIER_A', result.rows[0].issues[0].vendorDeveloperName);

        first.Is_Primary_Pricing_Endpoint__c = true;
        result = VendorEndpointResolver.resolve(context, null, config);
        System.assertEquals(2, result.rows[0].routes.size());
        System.assertEquals('FIRST', result.rows[0].routes[0].endpointDeveloperName);
        System.assertEquals(0, result.rows[0].issues.size());
    }

    @IsTest
    static void appliesActiveFlagsPolicyAndExistingCapabilityFlags() {
        VendorPricingMetadataRepository.EndpointConfiguration config =
            new VendorPricingMetadataRepository.EndpointConfiguration();
        config.vendors.add(vendor(A, 'SUPPLIER_A', true));
        config.vendors.add(vendor(B, 'SUPPLIER_B', false));
        config.endpoints.add(endpoint(B, 'OPTED_OUT', 'PART_NUMBER'));
        Vendor_Endpoint__mdt followUp = endpoint(A, 'AFTER_SELECTION', 'PART_NUMBER');
        followUp.Invocation_Policy__c = 'ON_DEMAND';
        config.endpoints.add(followUp);
        Vendor_Endpoint__mdt disabled = endpoint(A, 'DISABLED', 'PART_NUMBER');
        disabled.Active__c = false;
        config.endpoints.add(disabled);
        Vendor_Endpoint__mdt existing = endpoint(A, 'CONFIGURED', null);
        existing.Supports_Standard_Parts__c = true;
        existing.Supports_Vendor_SKU_Search__c = true;
        existing.Supports_Powertrain__c = true;
        existing.Supports_Terminology_Search__c = true;
        config.endpoints.add(existing);
        VendorPricingRequestContext context = pricingContext();

        VendorEndpointResolver.Result result = VendorEndpointResolver.resolve(context, null, config);
        System.assertEquals(1, result.rows[0].routes.size());
        System.assertEquals('CONFIGURED', result.rows[0].routes[0].endpointDeveloperName);
        System.assertEquals(1, VendorEndpointResolver.endpointRank(existing, 'PART_NUMBER:VENDOR_SKU'));
        System.assertEquals(1, VendorEndpointResolver.endpointRank(existing, 'PART_NUMBER:POWERTRAIN'));
        System.assertEquals(1, VendorEndpointResolver.endpointRank(existing, 'LOSS_CATEGORY'));

        existing.Active__c = false;
        result = VendorEndpointResolver.resolve(context, null, config);
        System.assertEquals('NO_ELIGIBLE_PRICING_ENDPOINT', result.rows[0].issues[0].code);
    }

    @IsTest
    static void usesExplicitModesForTheSharedLaborInputAndRetainsValidation() {
        VendorPricingMetadataRepository.EndpointConfiguration config =
            new VendorPricingMetadataRepository.EndpointConfiguration();
        config.vendors.add(vendor(A, 'SUPPLIER_A', true));
        config.endpoints.add(endpoint(A, 'TIME_LOOKUP', 'LABOR_TIME'));
        VendorPricingRequestContext context = pricingContext();
        VendorPricingLineContext labor = new VendorPricingLineContext();
        labor.rowKey = 'labor';
        labor.detailType = 'Labor';
        labor.searchMode = 'LABOR_TIME';
        context.lines.add(labor);
        context.lines[0].partNumber = null;
        VendorEndpointResolver.Result result = VendorEndpointResolver.resolve(context, null, config);

        System.assertEquals('PART_SEARCH_INPUT_REQUIRED', result.validation.lineResults[0].issues[0].code);
        System.assertEquals(1, result.rows.size());
        System.assertEquals('labor', result.rows[0].rowKey);
        System.assertEquals('TIME_LOOKUP', result.rows[0].routes[0].endpointDeveloperName);

        context.vin = null;
        result = VendorEndpointResolver.resolve(context, null, config);
        System.assert(result.validation.validRowKeys.isEmpty());
        System.assert(result.rows.isEmpty());
    }

    @IsTest
    static void exercisesTheOrgMetadataQueryFromThePublicEntryPoint() {
        VendorEndpointResolver.Result result = VendorEndpointResolver.resolve(pricingContext());
        System.assertEquals(new List<String>{'line'}, result.validation.validRowKeys);
        System.assertEquals(1, result.rows.size());
        System.assertEquals('PART_NUMBER', result.rows[0].searchKey);
        System.assertEquals(0, Limits.getDmlStatements());
        System.assertEquals(0, Limits.getCallouts());
    }
}