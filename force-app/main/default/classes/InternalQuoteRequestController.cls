public with sharing class InternalQuoteRequestController {

    // ============================================================
    // WRAPPER CLASSES
    // ============================================================

    public class DropdownOption {
        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public DropdownOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }


    public class QuoteResultWrapper {
        @AuraEnabled
        public String dealerProgramId;

        @AuraEnabled
        public String product;

        @AuraEnabled
        public String coverageLevel;

        @AuraEnabled
        public Integer contractTermMonths;

        @AuraEnabled
        public Integer validationDays;

        @AuraEnabled
        public Decimal deductible;

        @AuraEnabled
        public Decimal dealerCost;

        @AuraEnabled
        public Decimal monthlyDealerCost;

        @AuraEnabled
        public String waterWellPump;

        @AuraEnabled
        public String refrigeratorIceMaker;

        @AuraEnabled
        public String standAloneIceMaker;

        @AuraEnabled
        public String secondaryRefrigerator;

        @AuraEnabled
        public String secondaryFreezer;

        @AuraEnabled
        public String swimmingPool;

        @AuraEnabled
        public String spa;

        @AuraEnabled
        public String clothesWasherDryer;

        @AuraEnabled
        public String centralVac;

        @AuraEnabled
        public String garageDoorOpener;
    }


    // ============================================================
    // CONSTANTS
    // ============================================================

    private static final String MATRIX_TYPE_CALCULATION = 'CalculationMatrix';


    // ============================================================
    // GET CLIENTS
    // ============================================================

    @AuraEnabled(cacheable=true)
    public static List<DropdownOption> getClients() {

        List<DropdownOption> results = new List<DropdownOption>();

        Set<String> clientNames = new Set<String>();

        for (Quote_Client_Config__mdt config :
             Quote_Client_Config__mdt.getAll().values()) {

            if (config == null) {
                continue;
            }

            if (config.Active__c == true &&
                String.isNotBlank(config.Client_Name__c) &&
                String.isNotBlank(config.Dealer_Lookup_Matrix__c)) {

                clientNames.add(config.Client_Name__c);
            }
        }

        for (String clientName : clientNames) {
            results.add(
                new DropdownOption(
                    clientName,
                    clientName
                )
            );
        }

        results.sort(new DropdownOptionComparator());

        return results;
    }


    // ============================================================
    // GET PRODUCTS
    // ============================================================

@AuraEnabled(cacheable=true)
public static List<DropdownOption> getProducts(String client) {

    List<DropdownOption> results = new List<DropdownOption>();
    Set<String> products = new Set<String>();

    if (String.isBlank(client)) {
        return results;
    }

    Quote_Client_Config__mdt clientConfig = getClientConfig(client);

    if (clientConfig == null ||
        String.isBlank(clientConfig.Dealer_Lookup_Matrix__c)) {
        return results;
    }

    List<CalculationMatrix> matrices = [
        SELECT Id
        FROM CalculationMatrix
        WHERE UniqueName = :clientConfig.Dealer_Lookup_Matrix__c
        LIMIT 1
    ];

    if (matrices.isEmpty()) {
        return results;
    }

    List<CalculationMatrixVersion> versions = [
        SELECT Id
        FROM CalculationMatrixVersion
        WHERE CalculationMatrixId = :matrices[0].Id
          AND IsEnabled = true
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (versions.isEmpty()) {
        return results;
    }

    List<CalculationMatrixRow> rows = [
        SELECT Id, InputData, OutputData
        FROM CalculationMatrixRow
        WHERE CalculationMatrixVersionId = :versions[0].Id
    ];

    for (CalculationMatrixRow row : rows) {

        Map<String, Object> inputData = parseJson(row.InputData);
        Map<String, Object> outputData = parseJson(row.OutputData);

        // Check Client in OutputData first, then InputData.
        String rowClient = getStringValue(outputData, 'Client');

        if (String.isBlank(rowClient)) {
            rowClient = getStringValue(inputData, 'Client');
        }

        if (String.isBlank(rowClient) ||
            !rowClient.trim().equalsIgnoreCase(client.trim())) {
            continue;
        }

        // Check Product in OutputData first, then InputData.
        String product = getStringValue(outputData, 'Product');

        if (String.isBlank(product)) {
            product = getStringValue(inputData, 'Product');
        }

        if (String.isNotBlank(product)) {
            products.add(product.trim());
        }
    }

    for (String product : products) {
        results.add(new DropdownOption(product, product));
    }

    results.sort(new DropdownOptionComparator());

    return results;
}

    // ============================================================
    // GET OPTIONS
    // ============================================================
/*@AuraEnabled(cacheable=true)
public static List<DropdownOption> getOptions(
    String client,
    String product
) {
    List<DropdownOption> results = new List<DropdownOption>();

    if (String.isBlank(client) || String.isBlank(product)) {
        return results;
    }

    Quote_Client_Config__mdt config = getClientConfig(client);

    if (config == null ||
        String.isBlank(config.Dealer_Lookup_Matrix__c)) {
        return results;
    }

    Map<String, String> uniqueOptions = new Map<String, String>();

    for (CalculationMatrixRow row :
         getDealerLookupRows(config.Dealer_Lookup_Matrix__c)) {

        Map<String, Object> inputData = parseJson(row.InputData);
        Map<String, Object> outputData = parseJson(row.OutputData);

        String rowClient = getStringValue(outputData, 'Client');

        if (String.isBlank(rowClient)) {
            rowClient = getStringValue(inputData, 'Client');
        }

        String rowProduct = getStringValue(outputData, 'Product');

        if (String.isBlank(rowProduct)) {
            rowProduct = getStringValue(inputData, 'Product');
        }

        String optionSets = getStringValue(outputData, 'OptionSets');

        if (String.isBlank(optionSets)) {
            optionSets = getStringValue(inputData, 'OptionSets');
        }

        if (String.isBlank(rowClient) ||
            String.isBlank(rowProduct) ||
            !rowClient.trim().equalsIgnoreCase(client.trim()) ||
            !rowProduct.trim().equalsIgnoreCase(product.trim()) ||
            String.isBlank(optionSets)) {
            continue;
        }

        /*
         * Assumes OptionSets is a delimiter-separated text field.
         * Confirm the actual stored format before relying on this split.
         
        for (String optionName : optionSets.split('[,;\\n\\r]+')) {
            String cleanedOption = optionName == null
                ? ''
                : optionName.trim();

            if (String.isBlank(cleanedOption) ||
                cleanedOption.equalsIgnoreCase('Others')) {
                continue;
            }

            String optionKey = cleanedOption.toLowerCase();

            if (!uniqueOptions.containsKey(optionKey)) {
                uniqueOptions.put(optionKey, cleanedOption);
            }
        }
    }

    List<String> sortedOptions = uniqueOptions.values();
    sortedOptions.sort();

    for (String optionName : sortedOptions) {
        results.add(new DropdownOption(optionName, optionName));
    }

    results.sort(new DropdownOptionComparator());

    return results;
}*/


@AuraEnabled(cacheable=true)
public static List<DropdownOption> getOptions(
    String client,
    String product
) {
    List<DropdownOption> results = new List<DropdownOption>();

    if (String.isBlank(client) || String.isBlank(product)) {
        return results;
    }

    // 1. Get the active client configuration.
    Quote_Client_Config__mdt config = getClientConfig(client);

    if (config == null ||
        String.isBlank(config.Dealer_Lookup_Matrix__c)) {
        return results;
    }

    // 2. Read the Dealer Code Lookup matrix rows.
    List<CalculationMatrixRow> dealerRows =
        getDealerLookupRows(config.Dealer_Lookup_Matrix__c);

    // Prevent processing the same options matrix more than once.
    Set<String> processedMatrixNames = new Set<String>();

    // 3. Read the Decision Matrix Mapping metadata.
    Map<String, DecisionMatrixMapping__mdt> mappingsByKey =
        new Map<String, DecisionMatrixMapping__mdt>();

    for (DecisionMatrixMapping__mdt mapping :
         DecisionMatrixMapping__mdt.getAll().values()) {

        if (mapping == null ||
            String.isBlank(mapping.Table_Name__c) ||
            String.isBlank(mapping.Coverage_Level__c) ||
            String.isBlank(mapping.Decision_Matrix_Name__c)) {
            continue;
        }

        String mappingKey =
            mapping.Table_Name__c.trim().toLowerCase() +
            '|' +
            mapping.Coverage_Level__c.trim().toLowerCase();

        mappingsByKey.put(mappingKey, mapping);
    }

    // 4. Match the Client and Product in Dealer Code Lookup.
    for (CalculationMatrixRow row : dealerRows) {

        Map<String, Object> inputData = parseJson(row.InputData);
        Map<String, Object> outputData = parseJson(row.OutputData);

        // Check OutputData first, then InputData.
        String rowClient = getStringValue(outputData, 'Client');

        if (String.isBlank(rowClient)) {
            rowClient = getStringValue(inputData, 'Client');
        }

        String rowProduct = getStringValue(outputData, 'Product');

        if (String.isBlank(rowProduct)) {
            rowProduct = getStringValue(inputData, 'Product');
        }

        if (String.isBlank(rowClient) ||
            String.isBlank(rowProduct) ||
            !rowClient.trim().equalsIgnoreCase(client.trim()) ||
            !rowProduct.trim().equalsIgnoreCase(product.trim())) {
            continue;
        }

        // 5. Extract OptionSets and CoverageLevel.
        String optionSets = getStringValue(outputData, 'OptionSets');

        if (String.isBlank(optionSets)) {
            optionSets = getStringValue(inputData, 'OptionSets');
        }

        String coverageLevel =
            getStringValue(outputData, 'CoverageLevel');

        if (String.isBlank(coverageLevel)) {
            coverageLevel =
                getStringValue(inputData, 'CoverageLevel');
        }

        if (String.isBlank(optionSets) ||
            String.isBlank(coverageLevel)) {
            continue;
        }

        // 6. Resolve the actual options matrix.
        String mappingKey =
            optionSets.trim().toLowerCase() +
            '|' +
            coverageLevel.trim().toLowerCase();

        DecisionMatrixMapping__mdt mapping =
            mappingsByKey.get(mappingKey);

        if (mapping == null ||
            String.isBlank(mapping.Decision_Matrix_Name__c)) {
            continue;
        }

        String optionsMatrixName =
            mapping.Decision_Matrix_Name__c.trim();

        String matrixKey = optionsMatrixName.toLowerCase();

        if (processedMatrixNames.contains(matrixKey)) {
            continue;
        }

        processedMatrixNames.add(matrixKey);

        // 7. Read OptionName from the resolved options matrix.
        addOptionsFromMatrix(optionsMatrixName, results);
    }

    // 8. Remove blank and duplicate values, then sort.
    return removeDuplicateOptions(results);
}



    // ============================================================
    // GET QUOTES
    // ============================================================

    /*
     * This method is intentionally separated from QuoteServiceHome.
     *
     * We are NOT modifying QuoteServiceHome yet because its current
     * process requires ResidenceType, while the new MRT3-92 screen
     * does not collect ResidenceType.
     *
     * Once the correct ResidenceType source is confirmed, this method
     * will call the existing quote calculation logic.
     */

    @AuraEnabled
    public static List<QuoteResultWrapper> getQuotes(
        String client,
        String product,
        String saleOdometer,
        String state,
        String vin,
        List<String> options
    ) {

        if (String.isBlank(client)) {
            throw new AuraHandledException(
                'Client is required.'
            );
        }

        if (String.isBlank(product)) {
            throw new AuraHandledException(
                'Product is required.'
            );
        }

        if (String.isBlank(saleOdometer)) {
            throw new AuraHandledException(
                'Sale Odometer is required.'
            );
        }

        if (String.isBlank(state)) {
            throw new AuraHandledException(
                'State is required.'
            );
        }

        if (String.isBlank(vin)) {
            throw new AuraHandledException(
                'VIN is required.'
            );
        }

        /*
         * IMPORTANT:
         *
         * Do not hard-code ResidenceType here.
         *
         * QuoteServiceHome.rateCostLookupHW() uses ResidenceType
         * to identify the correct rate row.
         *
         * We will connect this method to the existing Endurance
         * ResidenceType logic once that source is identified.
         */

        throw new AuraHandledException(
            'Quote retrieval is not connected yet. ' +
            'Residence Type mapping from the existing Endurance ' +
            'quote flow is required before retrieving quotes.'
        );
    }


    // ============================================================
    // GET CLIENT CONFIG
    // ============================================================

    private static Quote_Client_Config__mdt getClientConfig(
        String client
    ) {

        if (String.isBlank(client)) {
            return null;
        }

        for (Quote_Client_Config__mdt config :
             Quote_Client_Config__mdt.getAll().values()) {

            if (config == null) {
                continue;
            }

            if (config.Active__c == true &&
                config.Client_Name__c == client) {

                return config;
            }
        }

        return null;
    }


    // ============================================================
    // GET DEALER LOOKUP MATRIX ROWS
    // ============================================================

    private static List<CalculationMatrixRow> getDealerLookupRows(
        String matrixName
    ) {

        List<CalculationMatrixRow> results =
            new List<CalculationMatrixRow>();

        if (String.isBlank(matrixName)) {
            return results;
        }

        List<CalculationMatrix> matrices = [
            SELECT Id,
                   UniqueName
            FROM CalculationMatrix
            WHERE UniqueName = :matrixName
            LIMIT 1
        ];

        if (matrices.isEmpty()) {
            return results;
        }

        CalculationMatrix matrix = matrices[0];

    /*    List<CalculationMatrixVersion> versions = [
            SELECT Id,
                   CalculationMatrixId,
                   IsEnabled
            FROM CalculationMatrixVersion
            WHERE CalculationMatrixId = :matrix.Id
              AND IsEnabled = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];*/

        
/*
 * VERSION SELECTION LOGIC:
 *
 * 1. Consider only enabled Calculation Matrix versions.
 * 2. StartDateTime must be less than or equal to the current date/time.
 * 3. EndDateTime must be blank or later than the current date/time.
 * 4. If multiple versions are eligible, select the version with the
 *    lowest Rank first (assuming lower Rank means higher priority).
 * 5. If multiple eligible versions have the same Rank, select the
 *    highest VersionNumber.
 *
 * This ensures that the currently effective, highest-priority version
 * is selected instead of simply selecting the most recently created
 * version.
 */
Datetime currentDateTime = System.now();

List<CalculationMatrixVersion> versions = [
    SELECT Id,
           CalculationMatrixId,
           IsEnabled,
           Rank,
           StartDateTime,
           EndDateTime,
           VersionNumber
    FROM CalculationMatrixVersion
    WHERE CalculationMatrixId = :matrix.Id
      AND IsEnabled = true
      AND StartDateTime <= :currentDateTime
      AND (EndDateTime = null OR EndDateTime > :currentDateTime)
    ORDER BY Rank ASC, VersionNumber DESC
    LIMIT 1
];

        if (versions.isEmpty()) {
            return results;
        }

        results = [
            SELECT Id,
                   CalculationMatrixVersionId,
                   InputData,
                   OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId = :versions[0].Id
        ];

        return results;
    }


    // ============================================================
    // ADD OPTIONS FROM DECISION MATRIX
    // ============================================================

    private static void addOptionsFromMatrix(
        String matrixName,
        List<DropdownOption> results
    ) {

        if (String.isBlank(matrixName)) {
            return;
        }

        List<CalculationMatrix> matrices = [
            SELECT Id,
                   UniqueName
            FROM CalculationMatrix
            WHERE UniqueName = :matrixName
            LIMIT 1
        ];

        if (matrices.isEmpty()) {
            return;
        }

        List<CalculationMatrixVersion> versions = [
            SELECT Id
            FROM CalculationMatrixVersion
            WHERE CalculationMatrixId = :matrices[0].Id
              AND IsEnabled = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return;
        }

        List<CalculationMatrixRow> rows = [
            SELECT Id,
                   InputData,
                   OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId = :versions[0].Id
        ];

        for (CalculationMatrixRow row : rows) {

            if (String.isBlank(row.InputData)) {
                continue;
            }

            Map<String, Object> inputData =
                parseJson(row.InputData);

            String optionName =
                getStringValue(inputData, 'OptionName');

            if (String.isBlank(optionName)) {
                continue;
            }

            /*
             * Requirement:
             * Do not include "Others".
             */
            if (optionName.equalsIgnoreCase('Others')) {
                continue;
            }

            results.add(
                new DropdownOption(
                    optionName,
                    optionName
                )
            );
        }
    }


    // ============================================================
    // JSON HELPERS
    // ============================================================

    private static Map<String, Object> parseJson(
        String jsonValue
    ) {

        if (String.isBlank(jsonValue)) {
            return new Map<String, Object>();
        }

        try {
            Object parsed =
                JSON.deserializeUntyped(jsonValue);

            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }

        } catch (Exception ex) {
            // Ignore malformed matrix rows.
        }

        return new Map<String, Object>();
    }


    private static String getStringValue(
        Map<String, Object> data,
        String key
    ) {

        if (data == null ||
            !data.containsKey(key) ||
            data.get(key) == null) {

            return null;
        }

        return String.valueOf(data.get(key));
    }


    // ============================================================
    // REMOVE DUPLICATE OPTIONS
    // ============================================================

    private static List<DropdownOption> removeDuplicateOptions(
        List<DropdownOption> source
    ) {

        Map<String, DropdownOption> uniqueOptions =
            new Map<String, DropdownOption>();

        for (DropdownOption option : source) {

            if (option == null ||
                String.isBlank(option.value)) {

                continue;
            }

          /*  if (!uniqueOptions.containsKey(option.value)) {
                uniqueOptions.put(
                    option.value,
                    option
                );
            }*/

            String optionKey = option.value.trim().toLowerCase();

            if (String.isNotBlank(optionKey) &&
                !optionKey.equalsIgnoreCase('Others') &&
                !uniqueOptions.containsKey(optionKey)) {

                uniqueOptions.put(
                    optionKey,
                    new DropdownOption(
                        option.value.trim(),
                        option.label == null ? option.value.trim() : option.label.trim()
                    )
                );
            }
        }

        List<DropdownOption> result =
            uniqueOptions.values();

        result.sort(new DropdownOptionComparator());

        return result;
    }


    // ============================================================
    // SORTING
    // ============================================================

    private class DropdownOptionComparator
        implements Comparator<DropdownOption> {

        public Integer compare(
            DropdownOption a,
            DropdownOption b
        ) {

            if (a == null && b == null) {
                return 0;
            }

            if (a == null) {
                return -1;
            }

            if (b == null) {
                return 1;
            }

            String aValue =
                a.label == null ? '' : a.label.toLowerCase();

            String bValue =
                b.label == null ? '' : b.label.toLowerCase();

            return aValue.compareTo(bValue);
        }
    }
}