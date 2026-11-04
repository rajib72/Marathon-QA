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
/*
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
    }*/


@AuraEnabled(cacheable=true)
public static List<DropdownOption> getClients(String quoteType) {
    List<DropdownOption> results = new List<DropdownOption>();

    if (String.isBlank(quoteType)) {
        return results;
    }

    String businessLine;

    if (quoteType.equalsIgnoreCase('Auto')) {
        businessLine = 'Auto';
    } else if (quoteType.equalsIgnoreCase('Home') || quoteType.equalsIgnoreCase('HomeWarranty')) {
        businessLine = 'Home';
    } else {
        return results;
    }

    for (Account acc : [
        SELECT Id, Name
        FROM Account
        WHERE RecordType.Name = 'Selling Agency'
          AND Active__c = 'Yes'
          AND Business_Line__c = :businessLine
        ORDER BY Name
    ]) {
        if (String.isNotBlank(acc.Name)) {
            results.add(new DropdownOption(acc.Name, acc.Name));
        }
    }

    return results;
}
    // ============================================================
    // GET PRODUCTS
    // ============================================================
@AuraEnabled(cacheable=true)
public static List<DropdownOption> getProducts(String client) {
    List<DropdownOption> results = new List<DropdownOption>();

    if (String.isBlank(client)) {
        return results;
    }

    List<CalculationMatrixRow> rows =
        getDealerLookupRows('Dealer_Code_Lookup');

    for (CalculationMatrixRow row : rows) {
        if (String.isBlank(row.OutputData)) {
            continue;
        }

        Map<String, Object> outputData = parseJson(row.OutputData);

        String rowClient = getStringValue(outputData, 'Client');
        String product = getStringValue(outputData, 'Product');

        if (
            String.isNotBlank(rowClient) &&
            rowClient.equalsIgnoreCase(client) &&
            String.isNotBlank(product)
        ) {
            results.add(new DropdownOption(product, product));
        }
    }

    return removeDuplicateOptions(results);
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

    // 1. Always read the shared Dealer_Code_Lookup matrix directly.
    List<CalculationMatrixRow> dealerRows =
        getDealerLookupRows('Dealer_Code_Lookup');

    if (dealerRows.isEmpty()) {
        return results;
    }

    // 2. Index the mapping metadata by OptionSets + CoverageLevel.
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

    // 3. Match the selected Client and Product in Dealer_Code_Lookup.
    Set<String> processedMatrixNames = new Set<String>();

    for (CalculationMatrixRow row : dealerRows) {
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

        if (String.isBlank(rowClient) ||
            String.isBlank(rowProduct) ||
            !rowClient.trim().equalsIgnoreCase(client.trim()) ||
            !rowProduct.trim().equalsIgnoreCase(product.trim())) {
            continue;
        }

        // 4. Read OptionSets and CoverageLevel from the matching row.
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

        // 5. Resolve the options matrix using DecisionMatrixMapping__mdt.
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

        // 6. Retrieve options for this coverage level.
        addOptionsFromMatrix(
            optionsMatrixName,
            coverageLevel,
            results
        );
    }

    // 7. Remove blanks/duplicates and sort the final dropdown.
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
/*
@AuraEnabled
public static List<QuoteResultWrapper> getQuotes(
    String quoteType,
    String client,
    String product,
    String saleOdometer,
    String state,
    String vin,
    List<String> options,
    String residenceType
) {
    // Common validations
    if (String.isBlank(quoteType)) {
        throw new AuraHandledException('Quote Type is required.');
    }

    if (String.isBlank(client)) {
        throw new AuraHandledException('Client is required.');
    }

    if (String.isBlank(product)) {
        throw new AuraHandledException('Product is required.');
    }

    if (String.isBlank(state)) {
        throw new AuraHandledException('State is required.');
    }

    // ============================================================
    // AUTO QUOTES
    // Keep the existing Auto behavior unchanged
    // ============================================================
    if (quoteType.equalsIgnoreCase('Auto')) {
        if (String.isBlank(saleOdometer)) {
            throw new AuraHandledException(
                'Sale Odometer is required for Auto quotes.'
            );
        }

        if (String.isBlank(vin)) {
            throw new AuraHandledException(
                'VIN is required for Auto quotes.'
            );
        }

        throw new AuraHandledException(
            'Auto quote calculation has not been connected yet.'
        );
    }

    // ============================================================
    // HOME WARRANTY QUOTES
    // ============================================================
    if (
        quoteType.equalsIgnoreCase('Home Warranty') ||
        quoteType.equalsIgnoreCase('HomeWarranty')
    ) {
        if (String.isBlank(residenceType)) {
            throw new AuraHandledException(
                'Residence Type is required for Home Warranty quotes.'
            );
        }

        try {
            // Retrieve calculated Home Warranty quotes from the service.
            List<QuoteServiceHome.HWQuote> homeQuotes =
                QuoteServiceHome.getQuotesForInternalRequest(
                    client,
                    state,
                    residenceType,
                    product,
                    options
                );

            // Convert the service response into the LWC wrapper.
            List<QuoteResultWrapper> results =
                new List<QuoteResultWrapper>();

            if (homeQuotes == null || homeQuotes.isEmpty()) {
                return results;
            }

            for (QuoteServiceHome.HWQuote homeQuote : homeQuotes) {
                if (homeQuote == null) {
                    continue;
                }

                QuoteResultWrapper result = new QuoteResultWrapper();

                result.dealerProgramId = homeQuote.DealerProgramId;
                result.product = homeQuote.Product;
                result.coverageLevel = homeQuote.CoverageLevel;
                result.contractTermMonths = homeQuote.ContractTermMonths;
                result.validationDays = homeQuote.ValidationDays;
                result.deductible = homeQuote.Deductible;
                result.dealerCost = homeQuote.DealerCost;
                result.monthlyDealerCost = homeQuote.MonthlyDealerCost;

                result.waterWellPump = homeQuote.WaterWellPump;
                result.refrigeratorIceMaker = homeQuote.RefrigeratorIceMaker;
                result.standAloneIceMaker = homeQuote.StandAloneIceMaker;
                result.secondaryRefrigerator = homeQuote.SecondaryRefrigerator;
                result.secondaryFreezer = homeQuote.SecondaryFreezer;
                result.swimmingPool = homeQuote.SwimmingPool;
                result.spa = homeQuote.Spa;
                result.clothesWasherDryer = homeQuote.ClothesWasherDryer;
                result.centralVac = homeQuote.CentralVac;
                result.garageDoorOpener = homeQuote.GarageDoorOpener;

                results.add(result);
            }

            return results;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Home Warranty quote retrieval failed: ' +
                e.getMessage() + '\n' + e.getStackTraceString()
            );

            throw new AuraHandledException(
                'Unable to retrieve Home Warranty quotes. ' +
                'Please contact your Salesforce administrator.'
            );
        }
    }

    // ============================================================
    // UNSUPPORTED QUOTE TYPE
    // ============================================================
    throw new AuraHandledException(
        'Unsupported Quote Type: ' + quoteType
    );
}*/



@AuraEnabled
public static List<QuoteResultWrapper> getQuotes(
    String quoteType,
    String client,
    String product,
    String saleOdometer,
    String state,
    String vin,
    List<String> options,
    String residenceType
) {
    // Common validations
    if (String.isBlank(quoteType)) {
        throw new AuraHandledException('Quote Type is required.');
    }

    if (String.isBlank(client)) {
        throw new AuraHandledException('Client is required.');
    }

    if (String.isBlank(product)) {
        throw new AuraHandledException('Product is required.');
    }

    if (String.isBlank(state)) {
        throw new AuraHandledException('State is required.');
    }

    // ============================================================
    // AUTO QUOTES
    // Keep the existing Auto behavior unchanged
    // ============================================================
    if (quoteType.equalsIgnoreCase('Auto')) {
        if (String.isBlank(saleOdometer)) {
            throw new AuraHandledException(
                'Sale Odometer is required for Auto quotes.'
            );
        }

        if (String.isBlank(vin)) {
            throw new AuraHandledException(
                'VIN is required for Auto quotes.'
            );
        }

        throw new AuraHandledException(
            'Auto quote calculation has not been connected yet.'
        );
    }

    // ============================================================
    // HOME WARRANTY QUOTES
    // Residence Type is optional
    // ============================================================
    if (
        quoteType.equalsIgnoreCase('Home') ||
        quoteType.equalsIgnoreCase('HomeWarranty')
    ) {
        try {
            // Retrieve Home Warranty quotes.
            // Residence Type may be null or blank.
            List<QuoteServiceHome.HWQuote> homeQuotes =
                QuoteServiceHome.getQuotesForInternalRequest(
                    client,
                    state,
                    residenceType,
                    product,
                    options
                );

            List<QuoteResultWrapper> results =
                new List<QuoteResultWrapper>();

            if (homeQuotes == null || homeQuotes.isEmpty()) {
                return results;
            }

            for (QuoteServiceHome.HWQuote homeQuote : homeQuotes) {
                if (homeQuote == null) {
                    continue;
                }

                QuoteResultWrapper result = new QuoteResultWrapper();

                result.dealerProgramId = homeQuote.DealerProgramId;
                result.product = homeQuote.Product;
                result.coverageLevel = homeQuote.CoverageLevel;
                result.contractTermMonths = homeQuote.ContractTermMonths;
                result.validationDays = homeQuote.ValidationDays;
                result.deductible = homeQuote.Deductible;
                result.dealerCost = homeQuote.DealerCost;
                result.monthlyDealerCost = homeQuote.MonthlyDealerCost;

                result.waterWellPump = homeQuote.WaterWellPump;
                result.refrigeratorIceMaker = homeQuote.RefrigeratorIceMaker;
                result.standAloneIceMaker = homeQuote.StandAloneIceMaker;
                result.secondaryRefrigerator = homeQuote.SecondaryRefrigerator;
                result.secondaryFreezer = homeQuote.SecondaryFreezer;
                result.swimmingPool = homeQuote.SwimmingPool;
                result.spa = homeQuote.Spa;
                result.clothesWasherDryer = homeQuote.ClothesWasherDryer;
                result.centralVac = homeQuote.CentralVac;
                result.garageDoorOpener = homeQuote.GarageDoorOpener;

                results.add(result);
            }

            return results;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Home Warranty quote retrieval failed: ' +
                e.getMessage() + '\n' + e.getStackTraceString()
            );

            throw new AuraHandledException(
                'Unable to retrieve Home Warranty quotes. ' +
                'Please contact your Salesforce administrator.'
            );
        }
    }

    // ============================================================
    // UNSUPPORTED QUOTE TYPE
    // ============================================================
    throw new AuraHandledException(
        'Unsupported Quote Type: ' + quoteType
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
    String coverageLevel,
    List<DropdownOption> results
) {
    if (String.isBlank(matrixName) ||
        String.isBlank(coverageLevel) ||
        results == null) {
        return;
    }

    // 1. Find the mapped options decision matrix.
    List<CalculationMatrix> matrices = [
        SELECT Id, UniqueName
        FROM CalculationMatrix
        WHERE UniqueName = :matrixName
        LIMIT 1
    ];

    if (matrices.isEmpty()) {
        System.debug(
            LoggingLevel.WARN,
            'Options matrix not found: ' + matrixName
        );
        return;
    }

    Datetime currentDateTime = System.now();

    // 2. Find an enabled, currently effective version.
    List<CalculationMatrixVersion> versions = [
        SELECT Id,
               CalculationMatrixId,
               IsEnabled,
               Rank,
               StartDateTime,
               EndDateTime,
               VersionNumber
        FROM CalculationMatrixVersion
        WHERE CalculationMatrixId = :matrices[0].Id
          AND IsEnabled = true
          AND (
              StartDateTime = null
              OR StartDateTime <= :currentDateTime
          )
          AND (
              EndDateTime = null
              OR EndDateTime > :currentDateTime
          )
        ORDER BY Rank ASC NULLS LAST,
                 VersionNumber DESC
        LIMIT 1
    ];

    if (versions.isEmpty()) {
        System.debug(
            LoggingLevel.WARN,
            'No enabled and effective version found for: '
            + matrixName
        );
        return;
    }

    // 3. Read enabled rows from the selected version.
    List<CalculationMatrixRow> rows = [
        SELECT Id,
               InputData,
               OutputData,
               IsVersionEnabled
        FROM CalculationMatrixRow
        WHERE CalculationMatrixVersionId = :versions[0].Id
          AND IsVersionEnabled = true
    ];

    // 4. Extract options for the requested coverage level.
    for (CalculationMatrixRow row : rows) {
        Map<String, Object> inputData = parseJson(row.InputData);
        Map<String, Object> outputData = parseJson(row.OutputData);

        String rowCoverage =
            getStringValue(inputData, 'CoverageName');

        if (String.isBlank(rowCoverage)) {
            rowCoverage =
                getStringValue(outputData, 'CoverageName');
        }

        String optionName =
            getStringValue(inputData, 'OptionName');

        if (String.isBlank(optionName)) {
            optionName =
                getStringValue(outputData, 'OptionName');
        }

        if (String.isBlank(rowCoverage) ||
            String.isBlank(optionName)) {
            continue;
        }

        if (!rowCoverage.trim().equalsIgnoreCase(
            coverageLevel.trim()
        )) {
            continue;
        }

        optionName = optionName.trim();

        // Do not display Others.
        if (optionName.equalsIgnoreCase('Others')) {
            continue;
        }

        results.add(
            new DropdownOption(optionName, optionName)
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

    
    // ============================================================
    // GET RESIDENCE TYPES FOR HOME WARRANTY
    // ============================================================

@AuraEnabled(cacheable=true)
public static List<DropdownOption> getResidenceTypes(
    String client,
    String product
) {
    List<DropdownOption> results = new List<DropdownOption>();
    Map<String, String> uniqueResidenceTypes = new Map<String, String>();

    if (String.isBlank(client) || String.isBlank(product)) {
        return results;
    }

    // 1. Get the client configuration.
    Quote_Client_Config__mdt config = getClientConfig(client);

    if (config == null) {
        return results;
    }

    // Use the Auto-specific lookup for Auto clients.
    // Keep the original lookup for Home Warranty clients.
    String dealerLookupMatrix;

    if (config.Auto_Enabled__c == true) {
        dealerLookupMatrix = config.Auto_Dealer_Lookup_Matrix__c;
    } else {
        dealerLookupMatrix = config.Dealer_Lookup_Matrix__c;
    }

    if (String.isBlank(dealerLookupMatrix)) {
        return results;
    }

    // 2. Read dealer lookup rows.
    List<CalculationMatrixRow> dealerRows =
        getDealerLookupRows(dealerLookupMatrix);

        System.debug(LoggingLevel.ERROR,
        'HOME ResidenceType - Client: ' + client +
        ', Product: ' + product +
        ', Dealer Matrix: ' + dealerLookupMatrix +
        ', Dealer Rows: ' + dealerRows.size()
    );

    // 3. Index mappings by table name and coverage level.
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

        String key =
            mapping.Table_Name__c.trim().toLowerCase() + '|' +
            mapping.Coverage_Level__c.trim().toLowerCase();

        mappingsByKey.put(key, mapping);
    }

    // 4. Find rate matrices for the selected client and product.
    Set<String> rateMatrixNames = new Set<String>();

    for (CalculationMatrixRow row : dealerRows) {
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

        if (String.isBlank(rowClient) ||
            String.isBlank(rowProduct) ||
            !rowClient.trim().equalsIgnoreCase(client.trim()) ||
            !rowProduct.trim().equalsIgnoreCase(product.trim())) {
            continue;
        }

        String rateSet = getStringValue(outputData, 'RateSet');
        if (String.isBlank(rateSet)) {
            rateSet = getStringValue(inputData, 'RateSet');
        }

        String coverageLevel =
            getStringValue(outputData, 'CoverageLevel');

        if (String.isBlank(coverageLevel)) {
            coverageLevel =
                getStringValue(inputData, 'CoverageLevel');
        }

        if (String.isBlank(rateSet) ||
            String.isBlank(coverageLevel)) {
            continue;
        }

        String mappingKey =
            rateSet.trim().toLowerCase() + '|' +
            coverageLevel.trim().toLowerCase();

        DecisionMatrixMapping__mdt mapping =
            mappingsByKey.get(mappingKey);

        if (mapping != null &&
            String.isNotBlank(mapping.Decision_Matrix_Name__c)) {
            rateMatrixNames.add(
                mapping.Decision_Matrix_Name__c.trim()
            );
        }
    }

    System.debug(LoggingLevel.ERROR,
    'HOME ResidenceType - Rate Matrix Names: ' + rateMatrixNames
);

    if (rateMatrixNames.isEmpty()) {
        return results;
    }

    // 5. Resolve rate matrices.
    Map<Id, String> matrixNameById = new Map<Id, String>();

    for (CalculationMatrix matrix : [
        SELECT Id, UniqueName
        FROM CalculationMatrix
        WHERE UniqueName IN :rateMatrixNames
    ]) {
        matrixNameById.put(matrix.Id, matrix.UniqueName);
    }

    if (matrixNameById.isEmpty()) {
        return results;
    }

   /* // 6. Read enabled versions that are currently effective.
    Datetime currentDateTime = System.now();
    Set<Id> versionIds = new Set<Id>();

    for (CalculationMatrixVersion version : [
        SELECT Id
        FROM CalculationMatrixVersion
        WHERE CalculationMatrixId IN :matrixNameById.keySet()
          AND IsEnabled = true
          AND StartDateTime <= :currentDateTime
          AND (EndDateTime = null OR EndDateTime > :currentDateTime)
    ]) {
        versionIds.add(version.Id);
    }

    if (versionIds.isEmpty()) {
        return results;
    }*/

    // Step 6: Get enabled matrix versions.
// Keep this consistent with QuoteServiceHome.rateCostLookupHW().
Set<Id> versionIds = new Set<Id>();

for (CalculationMatrixVersion version : [
    SELECT Id
    FROM CalculationMatrixVersion
    WHERE CalculationMatrixId IN :matrixNameById.keySet()
      AND IsEnabled = true
      AND EndDateTime = null
]) {
    versionIds.add(version.Id);
}


if (versionIds.isEmpty()) {
    return results;
}

System.debug(LoggingLevel.ERROR,
    'HOME ResidenceType - Matrix IDs: ' + matrixNameById.keySet() +
    ', Enabled Version IDs: ' + versionIds
);

    // 7. Extract ResidenceType from either InputData or OutputData.
    for (CalculationMatrixRow row : [
        SELECT InputData, OutputData
        FROM CalculationMatrixRow
        WHERE CalculationMatrixVersionId IN :versionIds
    ]) {
        Map<String, Object> inputData = parseJson(row.InputData);
        Map<String, Object> outputData = parseJson(row.OutputData);

        String residenceType =
            getStringValue(inputData, 'ResidenceType');

        if (String.isBlank(residenceType)) {
            residenceType =
                getStringValue(outputData, 'ResidenceType');
        }

        if (String.isBlank(residenceType)) {
            continue;
        }

        residenceType = residenceType.trim();
        String normalizedKey = residenceType.toLowerCase();

        if (!uniqueResidenceTypes.containsKey(normalizedKey)) {
            uniqueResidenceTypes.put(normalizedKey, residenceType);
        }
    }

    System.debug(LoggingLevel.ERROR,
    'HOME ResidenceType - Unique Values: ' + uniqueResidenceTypes
);

    // 8. Return sorted options.
    List<String> sortedResidenceTypes =
        uniqueResidenceTypes.values();

    sortedResidenceTypes.sort();

    for (String residenceType : sortedResidenceTypes) {
        results.add(
            new DropdownOption(residenceType, residenceType)
        );
    }

    results.sort(new DropdownOptionComparator());

    return results;
}

}