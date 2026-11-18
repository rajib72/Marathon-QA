/** Builds flat or nested JSON pricing bodies from a configured endpoint. */
public with sharing class VendorPricingRequestBuilder {
    private static final Pattern JSON_PATH =
        Pattern.compile('[a-zA-Z_][a-zA-Z0-9_]*(?:[.][a-zA-Z_][a-zA-Z0-9_]*)*');
    private static final Pattern VIN = Pattern.compile('(?i)[A-HJ-NPR-Z0-9]{17}');
    private static final Pattern STATE_CODE = Pattern.compile('[A-Z0-9]+');
    private static final Pattern POSTAL_CODE = Pattern.compile('(?i)[A-Z0-9][A-Z0-9 -]*');

    public class Options {
        public Map<String, String> searchVariantByRowKey = new Map<String, String>();
        public Map<String, String> preferenceContextByRowKey = new Map<String, String>();
        public List<String> catalogCodes = new List<String>();
        public List<String> shippingCodes = new List<String>();
        public List<String> warrantyCodes = new List<String>();
    }

    public class Issue {
        public String code;
        public String rowKey;
        public String message;

        public Issue(String code, String rowKey, String message) {
            this.code = code;
            this.rowKey = rowKey;
            this.message = message;
        }
    }

    public class PreparedRequest {
        public List<String> rowKeys = new List<String>();
        public Map<String, String> rowKeyByRequestKey = new Map<String, String>();
        public String jsonBody;
    }

    public class Result {
        public String endpointDeveloperName;
        public VendorPricingValidationService.Result validation;
        public List<Issue> issues = new List<Issue>();
        public List<PreparedRequest> requests = new List<PreparedRequest>();
    }

    private class MappingException extends Exception {
        public String code;
    }

    private class PreparedRow {
        public String rowKey;
        public String requestKey;
        public Map<String, Object> fields;

        public PreparedRow(String rowKey, String requestKey, Map<String, Object> fields) {
            this.rowKey = rowKey;
            this.requestKey = requestKey;
            this.fields = fields;
        }
    }

    public static Result preview(VendorPricingRequestContext context, String endpointName, Options options) {
        return prepare(context, endpointName, null, options, true, null);
    }

    public static Result build(
        VendorPricingRequestContext context, VendorEndpointResolver.Route route,
        Set<String> rowKeys, Options options
    ) {
        return prepare(context, route == null ? null : route.endpointDeveloperName,
            rowKeys == null ? new Set<String>() : rowKeys, options, false, null);
    }

    @TestVisible
    private static Result prepare(
        VendorPricingRequestContext context, String endpointName, Set<String> rowKeys,
        Options options, Boolean preview, VendorPricingMetadataRepository.RequestConfiguration config
    ) {
        Result result = new Result();
        result.endpointDeveloperName = endpointName;
        result.validation = VendorPricingValidationService.validate(context);
        if (result.validation.validRowKeys.isEmpty()) {
            return result;
        }
        if (String.isBlank(endpointName)) {
            result.issues.add(new Issue('ENDPOINT_REQUIRED', null, 'Select a configured pricing endpoint.'));
            return result;
        }
        if (config == null) {
            config = VendorPricingMetadataRepository.loadRequestConfiguration(endpointName, preview);
        }
        if (config.endpoint == null || config.vendor == null) {
            result.issues.add(new Issue('ENDPOINT_UNAVAILABLE', null, 'The pricing endpoint could not be resolved.'));
            return result;
        }
        if (preview != true && (config.endpoint.Active__c != true ||
            config.vendor.Active__c != true || config.vendor.Include_in_All_Vendor_Search__c != true)) {
            result.issues.add(new Issue('ENDPOINT_INACTIVE', null, 'The endpoint is unavailable for active pricing.'));
            return result;
        }
        if (options == null) {
            options = new Options();
        }

        try {
            String strategy = String.isBlank(config.endpoint.Request_Builder_Strategy__c)
                ? config.vendor.Default_Request_Builder__c : config.endpoint.Request_Builder_Strategy__c;
            if (strategy != 'NESTED_JSON' && strategy != 'FLAT_JSON') {
                throw problem('REQUEST_STRATEGY_UNSUPPORTED', 'Configure a supported JSON request builder strategy.');
            }
            Boolean flat = strategy == 'FLAT_JSON';
            String collectionPath = validateFieldConfiguration(config.fields, flat);
            Map<String, Object> sharedValues = requestValues(context);
            Map<String, Object> header = renderMappedFields(
                config, 'ROOT', sharedValues, null, null, null
            );

            List<PreparedRow> preparedRows = new List<PreparedRow>();
            Set<String> validKeys = new Set<String>(result.validation.validRowKeys);
            for (VendorPricingLineContext row : context.lines) {
                if (row == null || !validKeys.contains(row.rowKey) ||
                    (rowKeys != null && !rowKeys.contains(row.rowKey))) {
                    continue;
                }
                String searchKey = VendorEndpointResolver.searchKey(row, options.searchVariantByRowKey);
                if (VendorEndpointResolver.endpointRank(config.endpoint, searchKey) == 0) {
                    result.issues.add(new Issue('ENDPOINT_SEARCH_MODE_UNSUPPORTED', row.rowKey,
                        'The selected endpoint does not support this search mode.'));
                    continue;
                }
                String requestKey = String.valueOf(preparedRows.size() + 1);
                try {
                    Map<String, Object> rowValues = lineValues(row, options, searchKey, sharedValues);
                    String valueContext = options.preferenceContextByRowKey == null
                        ? null : options.preferenceContextByRowKey.get(row.rowKey);
                    Map<String, Object> fields = renderMappedFields(
                        config, 'PART_ITEM', rowValues, searchKey, valueContext, requestKey
                    );
                    preparedRows.add(new PreparedRow(row.rowKey, requestKey, fields));
                } catch (MappingException error) {
                    result.issues.add(new Issue(error.code, row.rowKey, error.getMessage()));
                }
            }
            result.requests = assembleBatches(config, collectionPath, header, preparedRows);
        } catch (MappingException error) {
            result.issues.add(new Issue(error.code, null, error.getMessage()));
        }
        return result;
    }

    private static String validateFieldConfiguration(List<Vendor_Field_Mapping__mdt> fields, Boolean flat) {
        if (fields.isEmpty()) {
            throw problem('REQUEST_MAPPINGS_REQUIRED', 'Configure outbound field mappings for this endpoint.');
        }
        String collectionPath;
        Boolean hasLineMapping = false;
        for (Vendor_Field_Mapping__mdt field : fields) {
            String path = field.Vendor_Field_Path__c;
            if (field.Transport_Location__c != 'BODY' ||
                (field.Record_Scope__c != 'ROOT' && field.Record_Scope__c != 'PART_ITEM')) {
                throw problem('REQUEST_MAPPING_SCOPE_UNSUPPORTED', 'Review the transport and scope of ' + field.DeveloperName + '.');
            }
            if (!validPath(path) || (flat && path.contains('.'))) {
                throw problem('REQUEST_FIELD_PATH_INVALID', 'Review the JSON path of ' + field.DeveloperName + '.');
            }
            String configuredCollection = String.isBlank(field.Collection_Path__c) ? null : field.Collection_Path__c;
            if (field.Record_Scope__c == 'ROOT') {
                if (configuredCollection != null || String.isNotBlank(field.Apply_To_Search_Modes__c)) {
                    throw problem('REQUEST_MAPPING_SCOPE_INVALID', 'Use row scope for collection or search-specific mappings.');
                }
                continue;
            }
            if ((configuredCollection != null && (flat || !validPath(configuredCollection))) ||
                (hasLineMapping && configuredCollection != collectionPath)) {
                throw problem('REQUEST_COLLECTION_INVALID', 'Use one common row collection path for the endpoint.');
            }
            collectionPath = configuredCollection;
            hasLineMapping = true;
        }
        return collectionPath;
    }

    private static Boolean validPath(String path) {
        return String.isNotBlank(path) && JSON_PATH.matcher(path).matches();
    }

    private static Map<String, Object> requestValues(VendorPricingRequestContext context) {
        String postal = context.repairShopPostalCode;
        Boolean positiveMileage = context.currentMileage != null && context.currentMileage > 0;
        return new Map<String, Object>{
            'CLAIM_ID' => context.claimId, 'POLICY_ID' => context.policyId,
            'VIN' => context.vin, 'CURRENT_MILEAGE' => context.currentMileage,
            'CURRENT_MILEAGE_WHEN_POSITIVE' => positiveMileage ? context.currentMileage : null,
            'SERVICE_CENTER_NAME' => context.repairShopName,
            'SERVICE_CENTER_STREET' => context.repairShopStreet,
            'SERVICE_CENTER_CITY' => context.repairShopCity,
            'SERVICE_CENTER_STATE_CODE' => context.repairShopState,
            'SERVICE_CENTER_COUNTRY_CODE' => context.repairShopCountry,
            'SERVICE_CENTER_POSTAL_CODE' => postal,
            'SERVICE_CENTER_POSTAL_CODE_COMPACT' => postal == null ? null :
                postal.replace('-', '').replace(' ', '')
        };
    }

    private static Map<String, Object> lineValues(
        VendorPricingLineContext row, Options options, String searchKey, Map<String, Object> sharedValues
    ) {
        Map<String, Object> values = sharedValues.clone();
        values.putAll(new Map<String, Object>{
            'CLAIM_ITEM_ID' => row.claimItemId, 'PART_NUMBER' => row.partNumber,
            'QUANTITY' => row.adjustedQuantity, 'LOSS_CATEGORY' => row.lossCategory,
            'LOSS_COMPONENT' => row.lossComponentName, 'DESCRIPTION' => row.description,
            'DETAIL_TYPE' => row.detailType, 'SEARCH_MODE' => row.searchMode,
            'SEARCH_TYPE' => searchKey.contains(':') ? searchKey.substring(searchKey.indexOf(':') + 1) : null,
            'PART_CATALOGS' => options.catalogCodes, 'SHIPPING_TYPES' => options.shippingCodes,
            'WARRANTY_DESCRIPTIONS' => options.warrantyCodes
        });
        return values;
    }

    private static Map<String, Object> renderMappedFields(
        VendorPricingMetadataRepository.RequestConfiguration config, String scope,
        Map<String, Object> source, String searchKey, String valueContext, String requestKey
    ) {
        Map<String, Object> fields = new Map<String, Object>();
        for (Vendor_Field_Mapping__mdt mapping : config.fields) {
            if (mapping.Record_Scope__c != scope ||
                (String.isNotBlank(mapping.Apply_To_Search_Modes__c) &&
                 VendorEndpointResolver.searchRank(mapping.Apply_To_Search_Modes__c, searchKey) == 0)) {
                continue;
            }
            Object value = resolveSource(mapping, source, requestKey);
            value = transform(mapping, value, valueContext, config.values);
            Boolean required = isRequired(mapping, searchKey);
            if (isBlankValue(value)) {
                if (required) {
                    throw fieldProblem('REQUEST_FIELD_REQUIRED', mapping);
                }
                if (value == null || mapping.Omit_When_Blank__c == true) {
                    continue;
                }
            }
            value = coerceAndValidate(mapping, value);
            if (fields.containsKey(mapping.Vendor_Field_Path__c)) {
                throw problem('REQUEST_FIELD_PATH_CONFLICT', 'Multiple mappings apply to one JSON path.');
            }
            fields.put(mapping.Vendor_Field_Path__c, value);
        }
        return fields;
    }

    private static Object resolveSource(Vendor_Field_Mapping__mdt field, Map<String, Object> source, String requestKey) {
        String reference = field.Source_Reference__c;
        if (field.Source_Type__c == 'CONSTANT') {
            return reference;
        }
        if (field.Source_Type__c == 'RUNTIME_SYSTEM') {
            if (reference == 'ROW_KEY') {
                return requestKey;
            }
            if (reference == 'EMPTY_STRING') {
                return '';
            }
        }
        if (field.Source_Type__c == 'REQUEST_CONTEXT') {
            String code = String.isBlank(reference) ? field.Internal_Field_Code__c : reference;
            if (source.containsKey(code)) {
                return source.get(code);
            }
        }
        throw problem('REQUEST_SOURCE_UNSUPPORTED', 'Review the source for ' + field.DeveloperName + '.');
    }

    private static Boolean isRequired(Vendor_Field_Mapping__mdt field, String searchKey) {
        if (field.Requirement_Mode__c == 'REQUIRED') {
            return true;
        }
        if (field.Requirement_Mode__c == 'OPTIONAL') {
            return false;
        }
        if (field.Requirement_Mode__c == 'CONDITIONAL' &&
            String.isNotBlank(field.Conditional_Requirement_Code__c) && searchKey != null) {
            return VendorEndpointResolver.searchRank(field.Conditional_Requirement_Code__c, searchKey) > 0;
        }
        throw problem('REQUEST_REQUIREMENT_UNSUPPORTED', 'Review the requirement mode for ' + field.DeveloperName + '.');
    }

    private static Object transform(
        Vendor_Field_Mapping__mdt field, Object value,
        String valueContext, List<Vendor_Value_Mapping__mdt> mappings
    ) {
        String mode = field.Transformation_Strategy__c;
        if (mode == 'VALUE_MAPPING') {
            return mappedValue(field, value, valueContext, mappings);
        }
        if (isBlankValue(value)) {
            return mode == 'DELIMITED_LIST' ? null : value;
        }
        if (String.isBlank(mode) || mode == 'NONE' || mode == 'INTEGER_QUANTITY' || mode == 'STRING_TO_DECIMAL') {
            return value;
        }
        if (mode == 'TRIM') {
            return String.valueOf(value).trim();
        }
        if (mode == 'UPPERCASE') {
            return String.valueOf(value).trim().toUpperCase();
        }
        if (mode == 'DELIMITED_LIST' && value instanceof List<String> && String.isNotBlank(field.List_Delimiter__c)) {
            List<String> translated = new List<String>();
            for (String option : (List<String>) value) {
                if (String.isBlank(option)) {
                    throw fieldProblem('REQUEST_FIELD_INVALID', field);
                }
                String literal = String.isBlank(field.Value_Mapping_Group__c) ? option.trim() :
                    mappedValue(field, option, valueContext, mappings);
                if (!translated.contains(literal)) {
                    translated.add(literal);
                }
            }
            return String.join(translated, field.List_Delimiter__c);
        }
        throw problem('REQUEST_TRANSFORMATION_UNSUPPORTED', 'Review the transformation for ' + field.DeveloperName + '.');
    }

    private static String mappedValue(
        Vendor_Field_Mapping__mdt field, Object value,
        String valueContext, List<Vendor_Value_Mapping__mdt> mappings
    ) {
        if (String.isBlank(field.Value_Mapping_Group__c)) {
            throw problem('REQUEST_VALUE_GROUP_REQUIRED', 'Configure a value group for ' + field.DeveloperName + '.');
        }
        Boolean blank = isBlankValue(value);
        String input = blank ? null : String.valueOf(value).trim();
        Vendor_Value_Mapping__mdt winner;
        Integer bestScope = -1;
        Decimal bestPriority;
        Boolean tied = false;
        for (Vendor_Value_Mapping__mdt entry : mappings) {
            Boolean scoped = String.isNotBlank(entry.Context_Code__c);
            if (entry.Mapping_Group__c != field.Value_Mapping_Group__c ||
                (scoped && entry.Context_Code__c != valueContext)) {
                continue;
            }
            String configured = entry.Internal_Value__c;
            Boolean matches = blank ? entry.Default_Mapping__c == true :
                String.isNotBlank(configured) && (entry.Case_Sensitive__c == true ?
                    configured.trim().equals(input) : configured.trim().equalsIgnoreCase(input));
            if (!matches) {
                continue;
            }
            Integer scope = (entry.Vendor_Endpoint__c == null ? 0 : 2) + (scoped ? 1 : 0);
            Decimal priority = entry.Priority__c == null ? 100 : entry.Priority__c;
            if (winner == null || scope > bestScope || (scope == bestScope && priority < bestPriority)) {
                winner = entry;
                bestScope = scope;
                bestPriority = priority;
                tied = false;
            } else if (scope == bestScope && priority == bestPriority) {
                tied = true;
            }
        }
        if (tied) {
            throw problem('REQUEST_VALUE_MAPPING_AMBIGUOUS', 'Multiple values match ' + field.Value_Mapping_Group__c + '.');
        }
        if (winner == null && blank) {
            return null;
        }
        if (winner == null || String.isBlank(winner.Vendor_Value__c)) {
            throw fieldProblem('REQUEST_VALUE_UNMAPPED', field);
        }
        return winner.Vendor_Value__c;
    }

    private static Boolean isBlankValue(Object value) {
        return value == null ||
            (value instanceof String && String.isBlank((String) value)) ||
            (value instanceof List<String> && ((List<String>) value).isEmpty());
    }

    private static Object coerceAndValidate(Vendor_Field_Mapping__mdt field, Object value) {
        String kind = field.Data_Type__c;
        if (kind == 'INTEGER' || kind == 'DECIMAL') {
            Decimal numericValue;
            try {
                numericValue = Decimal.valueOf(String.valueOf(value));
            } catch (TypeException error) {
                throw fieldProblem('REQUEST_FIELD_INVALID', field);
            }
            Boolean wholeNumber = numericValue == numericValue.setScale(0, System.RoundingMode.DOWN);
            if ((kind == 'INTEGER' && !wholeNumber) ||
                (field.Transformation_Strategy__c == 'INTEGER_QUANTITY' && !wholeNumber) ||
                (field.Minimum_Numeric_Value__c != null && numericValue < field.Minimum_Numeric_Value__c) ||
                (field.Maximum_Numeric_Value__c != null && numericValue > field.Maximum_Numeric_Value__c)) {
                throw fieldProblem('REQUEST_FIELD_INVALID', field);
            }
            if (field.Validation_Strategy__c == 'POSITIVE_INTEGER' && (!wholeNumber || numericValue <= 0)) {
                throw fieldProblem('REQUEST_FIELD_INVALID', field);
            }
            if (String.isNotBlank(field.Validation_Strategy__c) &&
                field.Validation_Strategy__c != 'NONE' && field.Validation_Strategy__c != 'POSITIVE_INTEGER') {
                throw problem('REQUEST_VALIDATION_UNSUPPORTED', 'Review the validator for ' + field.DeveloperName + '.');
            }
            return kind == 'INTEGER' ? numericValue.setScale(0) : numericValue;
        }
        if (kind == 'BOOLEAN') {
            String booleanText = String.valueOf(value).trim().toLowerCase();
            if (booleanText != 'true' && booleanText != 'false') {
                throw fieldProblem('REQUEST_FIELD_INVALID', field);
            }
            return booleanText == 'true';
        }
        if (kind == 'ARRAY' && value instanceof List<String>) {
            return value;
        }
        if (kind != 'STRING' || value instanceof List<String>) {
            throw problem('REQUEST_DATA_TYPE_UNSUPPORTED', 'Review the data type for ' + field.DeveloperName + '.');
        }
        String text = String.valueOf(value);
        validateText(field, text);
        return text;
    }

    private static void validateText(Vendor_Field_Mapping__mdt field, String text) {
        if (field.Minimum_Length__c != null && text.length() < field.Minimum_Length__c) {
            throw fieldProblem('REQUEST_FIELD_INVALID', field);
        }
        String mode = field.Validation_Strategy__c;
        Pattern matcher;
        if (mode == 'VIN') {
            matcher = VIN;
        } else if (mode == 'STATE_CODE') {
            matcher = STATE_CODE;
        } else if (mode == 'POSTAL_CODE') {
            matcher = POSTAL_CODE;
        } else if (String.isNotBlank(mode) && mode != 'NONE') {
            throw problem('REQUEST_VALIDATION_UNSUPPORTED', 'Review the validator for ' + field.DeveloperName + '.');
        }
        if (matcher != null && !matcher.matcher(text).matches()) {
            throw fieldProblem('REQUEST_FIELD_INVALID', field);
        }
        if (String.isNotBlank(field.Format_Pattern__c)) {
            Pattern configured;
            try {
                configured = Pattern.compile(field.Format_Pattern__c);
            } catch (Exception invalidPattern) {
                throw problem('REQUEST_PATTERN_INVALID', 'Review the pattern for ' + field.DeveloperName + '.');
            }
            if (!configured.matcher(text).matches()) {
                throw fieldProblem('REQUEST_FIELD_INVALID', field);
            }
        }
    }

    private static List<PreparedRequest> assembleBatches(
        VendorPricingMetadataRepository.RequestConfiguration config, String collectionPath,
        Map<String, Object> header, List<PreparedRow> rows
    ) {
        List<PreparedRequest> requests = new List<PreparedRequest>();
        Decimal maximum = config.endpoint.Maximum_Parts_Per_Request__c;
        if (maximum == null) {
            maximum = config.vendor.Maximum_Parts_Per_Request__c;
        }
        Integer size = 1;
        if (collectionPath != null && config.endpoint.Supports_Multi_Part_Request__c == true &&
            maximum != null && maximum > 0 && maximum == maximum.setScale(0, System.RoundingMode.DOWN)) {
            size = maximum >= rows.size() ? Math.max(rows.size(), 1) : maximum.intValue();
        }
        for (Integer offset = 0; offset < rows.size(); offset += size) {
            PreparedRequest request = new PreparedRequest();
            Map<String, Object> body = new Map<String, Object>();
            writeFields(body, header);
            List<Map<String, Object>> entries = new List<Map<String, Object>>();
            Integer batchEndExclusive = Math.min(offset + size, rows.size());
            for (Integer index = offset; index < batchEndExclusive; index++) {
                PreparedRow row = rows[index];
                request.rowKeys.add(row.rowKey);
                request.rowKeyByRequestKey.put(row.requestKey, row.rowKey);
                if (collectionPath == null) {
                    writeFields(body, row.fields);
                } else {
                    Map<String, Object> entry = new Map<String, Object>();
                    writeFields(entry, row.fields);
                    entries.add(entry);
                }
            }
            if (collectionPath != null) {
                writePath(body, collectionPath, entries);
            }
            if (body.isEmpty()) {
                throw problem('REQUEST_BODY_EMPTY', 'The endpoint mappings did not produce a request body.');
            }
            request.jsonBody = JSON.serialize(body);
            requests.add(request);
        }
        return requests;
    }

    private static void writeFields(Map<String, Object> body, Map<String, Object> fields) {
        for (String path : fields.keySet()) {
            writePath(body, path, fields.get(path));
        }
    }

    private static void writePath(Map<String, Object> body, String path, Object value) {
        List<String> parts = path.split('[.]');
        Map<String, Object> target = body;
        for (Integer index = 0; index < parts.size() - 1; index++) {
            String segment = parts[index];
            if (!target.containsKey(segment)) {
                target.put(segment, new Map<String, Object>());
            }
            Object branch = target.get(segment);
            if (!(branch instanceof Map<String, Object>)) {
                throw problem('REQUEST_FIELD_PATH_CONFLICT', 'Configured JSON paths overlap.');
            }
            target = (Map<String, Object>) branch;
        }
        String leaf = parts[parts.size() - 1];
        if (target.containsKey(leaf)) {
            throw problem('REQUEST_FIELD_PATH_CONFLICT', 'Configured JSON paths overlap.');
        }
        target.put(leaf, value);
    }

    private static MappingException fieldProblem(String code, Vendor_Field_Mapping__mdt field) {
        String message = String.isBlank(field.Validation_Message__c) ?
            'Review the input for ' + field.DeveloperName + '.' : field.Validation_Message__c;
        return problem(code, message);
    }

    private static MappingException problem(String code, String message) {
        MappingException error = new MappingException(message);
        error.code = code;
        return error;
    }
}