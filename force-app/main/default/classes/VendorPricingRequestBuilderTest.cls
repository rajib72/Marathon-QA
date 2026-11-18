@IsTest
private class VendorPricingRequestBuilderTest {
    private static VendorPricingRequestContext contextWithRows() {
        VendorPricingRequestContext context = new VendorPricingRequestContext();
        context.claimId = (Id)(Claim.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        context.vin = '1HGCM82633A004352';
        context.repairShopAccountId = '001000000000001';
        context.repairShopStreet = '100 Main St';
        context.repairShopCity = 'Los Angeles';
        context.repairShopState = 'CA';
        context.repairShopPostalCode = '90001';
        context.lines.add(row('saved', 'PART_NUMBER', 'P-123'));
        context.lines.add(row('draft', 'LOSS_CATEGORY', null));
        context.lines.add(row('stock', 'PART_NUMBER', 'STOCK-10'));
        return context;
    }

    private static VendorPricingLineContext row(String key, String mode, String partNumber) {
        VendorPricingLineContext line = new VendorPricingLineContext();
        line.rowKey = key;
        line.detailType = 'Part';
        line.searchMode = mode;
        line.partNumber = partNumber;
        line.lossCategory = 'Brakes';
        line.adjustedQuantity = 2.00;
        return line;
    }

    private static VendorPricingMetadataRepository.RequestConfiguration configuration(
        String strategy, String searchModes
    ) {
        VendorPricingMetadataRepository.RequestConfiguration config =
            new VendorPricingMetadataRepository.RequestConfiguration();
        config.vendor = new Vendor_Integration__mdt(
            Active__c = true, Include_in_All_Vendor_Search__c = true,
            Default_Request_Builder__c = strategy, Maximum_Parts_Per_Request__c = 2
        );
        config.endpoint = new Vendor_Endpoint__mdt(
            Active__c = true, Invocation_Policy__c = 'INITIAL_PRICING',
            Supported_Search_Modes__c = searchModes
        );
        return config;
    }

    private static Vendor_Field_Mapping__mdt field(
        String code, String path, String kind, String scope, String collectionPath
    ) {
        return new Vendor_Field_Mapping__mdt(
            Active__c = true, Internal_Field_Code__c = code, Vendor_Field_Path__c = path,
            Record_Scope__c = scope, Collection_Path__c = collectionPath,
            Transport_Location__c = 'BODY', Source_Type__c = 'REQUEST_CONTEXT',
            Data_Type__c = kind, Requirement_Mode__c = 'REQUIRED'
        );
    }

    private static Vendor_Value_Mapping__mdt value(String groupName, String input, String output) {
        return new Vendor_Value_Mapping__mdt(
            Active__c = true, Mapping_Group__c = groupName, Internal_Value__c = input,
            Vendor_Value__c = output, Priority__c = 100
        );
    }

    private static VendorPricingRequestBuilder.Options options() {
        VendorPricingRequestBuilder.Options result = new VendorPricingRequestBuilder.Options();
        result.searchVariantByRowKey.put('saved', 'MAKER');
        result.searchVariantByRowKey.put('stock', 'STOCK');
        return result;
    }

    private static VendorPricingMetadataRepository.RequestConfiguration nestedConfiguration() {
        VendorPricingMetadataRepository.RequestConfiguration config =
            configuration('NESTED_JSON', 'PART_NUMBER:MAKER, PART_NUMBER:STOCK, LOSS_CATEGORY');
        config.endpoint.Supports_Multi_Part_Request__c = true;
        config.fields.add(field('VIN', 'request.vehicle', 'STRING', 'ROOT', null));
        Vendor_Field_Mapping__mdt country =
            field('SERVICE_CENTER_COUNTRY_CODE', 'request.destination.market', 'STRING', 'ROOT', null);
        country.Transformation_Strategy__c = 'VALUE_MAPPING';
        country.Value_Mapping_Group__c = 'MARKET';
        config.fields.add(country);
        Vendor_Value_Mapping__mdt fallback = value('MARKET', 'LOCAL', 'REGION-01');
        fallback.Default_Mapping__c = true;
        config.values.add(fallback);

        String collectionPath = 'request.lines';
        config.fields.add(field('QUANTITY', 'units', 'INTEGER', 'PART_ITEM', collectionPath));
        Vendor_Field_Mapping__mdt key = field('REQUEST_ROW_KEY', 'ref', 'STRING', 'PART_ITEM', collectionPath);
        key.Source_Type__c = 'RUNTIME_SYSTEM';
        key.Source_Reference__c = 'ROW_KEY';
        config.fields.add(key);

        Vendor_Field_Mapping__mdt partNumber = field('PART_NUMBER', 'query.part', 'STRING', 'PART_ITEM', collectionPath);
        partNumber.Apply_To_Search_Modes__c = 'PART_NUMBER';
        config.fields.add(partNumber);
        Vendor_Field_Mapping__mdt maker = field('SEARCH_TYPE', 'query.mode', 'STRING', 'PART_ITEM', collectionPath);
        maker.Apply_To_Search_Modes__c = 'PART_NUMBER:MAKER';
        maker.Transformation_Strategy__c = 'VALUE_MAPPING';
        maker.Value_Mapping_Group__c = 'FIND_MODE';
        config.fields.add(maker);
        config.values.add(value('FIND_MODE', 'MAKER', 'manufacturer_lookup'));
        Vendor_Field_Mapping__mdt stock = field('SEARCH_TYPE', 'query.mode', 'STRING', 'PART_ITEM', collectionPath);
        stock.Apply_To_Search_Modes__c = 'PART_NUMBER:STOCK';
        stock.Source_Type__c = 'RUNTIME_SYSTEM';
        stock.Source_Reference__c = 'EMPTY_STRING';
        stock.Requirement_Mode__c = 'OPTIONAL';
        config.fields.add(stock);
        Vendor_Field_Mapping__mdt category = field('LOSS_CATEGORY', 'query.mode', 'STRING', 'PART_ITEM', collectionPath);
        category.Apply_To_Search_Modes__c = 'LOSS_CATEGORY';
        config.fields.add(category);
        return config;
    }

    private static VendorPricingMetadataRepository.RequestConfiguration flatConfiguration() {
        VendorPricingMetadataRepository.RequestConfiguration config = configuration('FLAT_JSON', 'PART_NUMBER');
        config.fields.add(field('VIN', 'vehicleId', 'STRING', 'ROOT', null));
        config.fields.add(field('PART_NUMBER', 'itemCode', 'STRING', 'PART_ITEM', null));
        config.fields.add(field('QUANTITY', 'count', 'INTEGER', 'PART_ITEM', null));
        return config;
    }

    private static Map<String, Object> body(VendorPricingRequestBuilder.PreparedRequest request) {
        return (Map<String, Object>) JSON.deserializeUntyped(request.jsonBody);
    }

    private static Map<String, Object> nested(Map<String, Object> body, String key) {
        return (Map<String, Object>) body.get(key);
    }

    @IsTest
    static void buildsDifferentRequestsWithTheSameApexAndConfigurationChangesOnly() {
        VendorPricingRequestContext context = contextWithRows();
        VendorPricingRequestBuilder.Result flat = VendorPricingRequestBuilder.prepare(
            context, 'SUPPLIER_B_LOOKUP', new Set<String>{'saved'}, options(), false, flatConfiguration()
        );
        System.assertEquals(0, flat.issues.size());
        System.assertEquals(1, flat.requests.size());
        Map<String, Object> flatBody = body(flat.requests[0]);
        System.assertEquals('P-123', flatBody.get('itemCode'));
        System.assertEquals('1HGCM82633A004352', flatBody.get('vehicleId'));
        System.assert(!(flatBody.get('count') instanceof String));
        System.assertEquals(2.0, Decimal.valueOf(String.valueOf(flatBody.get('count'))));

        VendorPricingRequestBuilder.Result nestedResult = VendorPricingRequestBuilder.prepare(
            context, 'SUPPLIER_A_LOOKUP', null, options(), true, nestedConfiguration()
        );
        System.assertEquals(0, nestedResult.issues.size(), JSON.serialize(nestedResult.issues));
        System.assertEquals(2, nestedResult.requests.size());
        System.assertEquals(new List<String>{'saved', 'draft'}, nestedResult.requests[0].rowKeys);
        System.assertEquals('draft', nestedResult.requests[0].rowKeyByRequestKey.get('2'));
        System.assertEquals(new List<String>{'stock'}, nestedResult.requests[1].rowKeys);
        Map<String, Object> envelope = nested(body(nestedResult.requests[0]), 'request');
        System.assertEquals('REGION-01', nested(envelope, 'destination').get('market'));
        List<Object> rows = (List<Object>) envelope.get('lines');
        System.assertEquals(2, rows.size());
        System.assertEquals('manufacturer_lookup', nested((Map<String, Object>) rows[0], 'query').get('mode'));
        System.assertEquals('Brakes', nested((Map<String, Object>) rows[1], 'query').get('mode'));
        List<Object> second = (List<Object>) nested(body(nestedResult.requests[1]), 'request').get('lines');
        System.assertEquals('', nested((Map<String, Object>) second[0], 'query').get('mode'));
    }

    @IsTest
    static void readsOnlyActiveRoutesForBuildAndAllowsDraftsForPreview() {
        VendorPricingMetadataRepository.RequestConfiguration config = flatConfiguration();
        config.vendor.Active__c = false;
        VendorPricingRequestContext context = contextWithRows();
        Set<String> onlyOne = new Set<String>{'saved'};

        VendorPricingRequestBuilder.Result result = VendorPricingRequestBuilder.prepare(
            context, 'LOOKUP', onlyOne, null, false, config
        );
        System.assertEquals('ENDPOINT_INACTIVE', result.issues[0].code);
        System.assert(result.requests.isEmpty());

        result = VendorPricingRequestBuilder.prepare(context, 'LOOKUP', onlyOne, null, true, config);
        System.assertEquals(1, result.requests.size());
        System.assertEquals(new List<String>{'saved'}, result.requests[0].rowKeys);
    }

    @IsTest
    static void appliesMappedSelectionValuesAndSeparatesUnmappedRows() {
        VendorPricingMetadataRepository.RequestConfiguration config = nestedConfiguration();
        Vendor_Field_Mapping__mdt catalog =
            field('PART_CATALOGS', 'query.selection', 'STRING', 'PART_ITEM', 'request.lines');
        catalog.Transformation_Strategy__c = 'DELIMITED_LIST';
        catalog.Value_Mapping_Group__c = 'CHOICES';
        catalog.List_Delimiter__c = '+';
        config.fields.add(catalog);
        Vendor_Value_Mapping__mdt standard = value('CHOICES', 'FIRST', 'A');
        standard.Context_Code__c = 'STANDARD';
        config.values.add(standard);
        config.values.add(value('CHOICES', 'SECOND', 'B'));
        VendorPricingRequestBuilder.Options options = options();
        options.catalogCodes = new List<String>{'first', 'SECOND', 'FIRST'};
        options.preferenceContextByRowKey.put('saved', 'STANDARD');

        VendorPricingRequestBuilder.Result result = VendorPricingRequestBuilder.prepare(
            contextWithRows(), 'LOOKUP', null, options, true, config
        );
        System.assertEquals(1, result.requests.size());
        System.assertEquals(new List<String>{'saved'}, result.requests[0].rowKeys);
        System.assertEquals(2, result.issues.size());
        System.assertEquals('REQUEST_VALUE_UNMAPPED', result.issues[0].code);
        System.assertEquals('draft', result.issues[0].rowKey);
        List<Object> entries = (List<Object>) nested(body(result.requests[0]), 'request').get('lines');
        System.assertEquals('A+B', nested((Map<String, Object>) entries[0], 'query').get('selection'));
    }

    @IsTest
    static void enforcesConfiguredRangesAndPatternsPerRow() {
        VendorPricingMetadataRepository.RequestConfiguration config = flatConfiguration();
        config.fields[1].Format_Pattern__c = 'P-[0-9]+';
        config.fields[2].Maximum_Numeric_Value__c = 5;
        config.fields[2].Validation_Strategy__c = 'POSITIVE_INTEGER';
        VendorPricingRequestContext context = contextWithRows();
        context.lines[0].adjustedQuantity = 6;
        context.lines.add(row('pass', 'PART_NUMBER', 'P-777'));

        VendorPricingRequestBuilder.Result result = VendorPricingRequestBuilder.prepare(
            context, 'LOOKUP', null, null, true, config
        );
        System.assertEquals(1, result.requests.size());
        System.assertEquals('pass', result.requests[0].rowKeys[0]);
        System.assertEquals('REQUEST_FIELD_INVALID', result.issues[0].code);
        System.assertEquals('ENDPOINT_SEARCH_MODE_UNSUPPORTED', result.issues[1].code);
        System.assertEquals('REQUEST_FIELD_INVALID', result.issues[2].code);
    }

    @IsTest
    static void reportsPathAndMappingConflictsWithoutWritingABody() {
        VendorPricingMetadataRepository.RequestConfiguration config = flatConfiguration();
        config.fields[1].Vendor_Field_Path__c = 'vehicleId';
        VendorPricingRequestBuilder.Result result = VendorPricingRequestBuilder.prepare(
            contextWithRows(), 'LOOKUP', new Set<String>{'saved'}, null, true, config
        );
        System.assertEquals('REQUEST_FIELD_PATH_CONFLICT', result.issues[0].code);
        System.assert(result.requests.isEmpty());

        config.fields[1].Vendor_Field_Path__c = 'invalid[0]';
        result = VendorPricingRequestBuilder.prepare(contextWithRows(), 'LOOKUP', null, null, true, config);
        System.assertEquals('REQUEST_FIELD_PATH_INVALID', result.issues[0].code);
    }

    @IsTest
    static void reportsTiedValueMappingsAndSkipsBlankOptionalFields() {
        VendorPricingMetadataRepository.RequestConfiguration config = nestedConfiguration();
        Vendor_Field_Mapping__mdt mileage = field('CURRENT_MILEAGE', 'request.miles', 'INTEGER', 'ROOT', null);
        mileage.Requirement_Mode__c = 'OPTIONAL';
        mileage.Source_Reference__c = 'CURRENT_MILEAGE_WHEN_POSITIVE';
        config.fields.add(mileage);
        VendorPricingRequestContext context = contextWithRows();
        context.currentMileage = 0;

        VendorPricingRequestBuilder.Result result = VendorPricingRequestBuilder.prepare(
            context, 'LOOKUP', new Set<String>{'saved'}, options(), true, config
        );
        System.assertEquals(false, nested(body(result.requests[0]), 'request').containsKey('miles'));

        config.values.add(value('FIND_MODE', 'MAKER', 'another_mode'));
        result = VendorPricingRequestBuilder.prepare(
            context, 'LOOKUP', new Set<String>{'saved'}, options(), true, config
        );
        System.assertEquals('REQUEST_VALUE_MAPPING_AMBIGUOUS', result.issues[0].code);
        System.assert(result.requests.isEmpty());
    }

    @IsTest
    static void checksMissingSetupAndSharedValidationFromThePublicMethods() {
        VendorPricingRequestContext context = contextWithRows();
        VendorPricingRequestBuilder.Result result =
            VendorPricingRequestBuilder.preview(context, 'ZZ_NONEXISTENT_PRICING_TEMPLATE', null);
        System.assertEquals('ENDPOINT_UNAVAILABLE', result.issues[0].code);

        result = VendorPricingRequestBuilder.build(context, null, null, null);
        System.assertEquals('ENDPOINT_REQUIRED', result.issues[0].code);

        context.vin = null;
        result = VendorPricingRequestBuilder.preview(context, 'LOOKUP', null);
        System.assertEquals('VIN_REQUIRED', result.validation.requestIssues[0].code);
        System.assert(result.requests.isEmpty());
        System.assertEquals(0, Limits.getDmlStatements());
        System.assertEquals(0, Limits.getCallouts());
    }
}