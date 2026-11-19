public with sharing class ReRateLWCController {

    private static final Set<String> OPTION_SET_KEYS = new Set<String>{
        'optionset', 'optionssets', 'optionsets', 'optionsetname', 'optionsetc', 'optionssetsc', 'optionssetsinput', 'optionsetinput'
    };

    private static final Set<String> OPTION_NAME_KEYS = new Set<String>{
        'optionname', 'option', 'options', 'optionnameinput', 'option1', 'optionvalue'
    };

    private static final Set<String> COVERAGE_KEYS = new Set<String>{
        'coveragename', 'coveragelevel', 'coverage', 'coveragenameinput'
    };

    public class OptionItem implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public OptionItem(String label, String value) {
            this.label = label;
            this.value = value;
        }

        public Integer compareTo(Object compareTo) {
            OptionItem other = (OptionItem) compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.compareTo(other.label);
        }
    }

    public class MatrixRowItem {
        @AuraEnabled public String termMonths { get; set; }
        @AuraEnabled public String termMiles { get; set; }
        @AuraEnabled public String deductible { get; set; }
        @AuraEnabled public Decimal minMiles { get; set; }
        @AuraEnabled public Decimal maxMiles { get; set; }
    }

    public class OptionSetResultWrapper {
        @AuraEnabled public String activeOptionSet { get; set; }
        @AuraEnabled public List<OptionItem> availableOptions { get; set; }
    }

    public class ContractDataWrapper {
        @AuraEnabled public String clientName { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String rateSet { get; set; }
        @AuraEnabled public String optionSet { get; set; }
        @AuraEnabled public String rateClass { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public Decimal saleMileage { get; set; }
        @AuraEnabled public Integer vehicleAge { get; set; }
        @AuraEnabled public Datetime saleDate { get; set; }
        @AuraEnabled public String currentCoverageId { get; set; }
        @AuraEnabled public String currentCoverageName { get; set; }
        @AuraEnabled public String currentTermMonths { get; set; }
        @AuraEnabled public String currentTermMiles { get; set; }
        @AuraEnabled public String currentDeductible { get; set; }
        @AuraEnabled public String currentOptions { get; set; }
        @AuraEnabled public List<OptionItem> coverageOptions { get; set; }
        @AuraEnabled public List<OptionItem> initialAvailableOptions { get; set; }
    }

    @AuraEnabled
    public static ContractDataWrapper getInitialContractData(Id contractId) {
        ContractDataWrapper response = new ContractDataWrapper();
        response.coverageOptions = new List<OptionItem>();
        response.initialAvailableOptions = new List<OptionItem>();

        List<InsurancePolicy> policies = [
            SELECT Id,
                   RecordType.Name,
                   Client__c,
                   Product__c,
                   Coverage_Level__c,
                   Rate_Set__c,
                   Options_Sets__c,
                   Option_1__c,
                   Sale_Date__c,
                   SaleDate,
                   Vehicle_Year__c,
                   Class__c,
                   Vehicle_Mileage_at_Contract_Inception__c,
                   Contract_Term_Months__c,
                   Contract_Term_Mileage__c,
                   Deductible__c,
                   Residential_Type__c
            FROM InsurancePolicy
            WHERE Id = :contractId
            LIMIT 1
        ];

        if (policies.isEmpty()) {
            return response;
        }

        InsurancePolicy policy = policies[0];

        String clientName = '';
        if (policy.Client__c != null) {
            List<Account> dealers = [SELECT Id, Name FROM Account WHERE Id = :policy.Client__c LIMIT 1];
            if (!dealers.isEmpty() && dealers[0].Name != null) {
                clientName = dealers[0].Name;
            }
        }

        String coverageName = '';
        if (policy.Coverage_Level__c != null) {
            List<Coverage_Level__c> covList = [SELECT Id, Name FROM Coverage_Level__c WHERE Id = :policy.Coverage_Level__c LIMIT 1];
            if (!covList.isEmpty()) {
                coverageName = covList[0].Name;
            }
        }

        Datetime effectiveSaleDate = Datetime.now();
        if (policy.Sale_Date__c != null) {
            effectiveSaleDate = Datetime.newInstance(
                policy.Sale_Date__c.year(),
                policy.Sale_Date__c.month(),
                policy.Sale_Date__c.day()
            );
        } else if (policy.SaleDate != null) {
            effectiveSaleDate = policy.SaleDate;
        }

        Integer saleYear = effectiveSaleDate.year();
        Integer vehicleYear = saleYear;
        if (String.isNotBlank(policy.Vehicle_Year__c) && policy.Vehicle_Year__c.isNumeric()) {
            vehicleYear = Integer.valueOf(policy.Vehicle_Year__c);
        }

        response.clientName = clientName;
        response.productName = policy.Product__c != null ? policy.Product__c : '';
        response.rateSet = policy.Rate_Set__c != null ? policy.Rate_Set__c : '';
        response.optionSet = policy.Options_Sets__c != null ? policy.Options_Sets__c : '';
        response.rateClass = policy.Class__c != null ? policy.Class__c : '';

        Boolean isHome = (policy.RecordType != null && policy.RecordType.Name == 'Home Warranty')
            || String.isNotBlank(policy.Residential_Type__c)
            || (policy.Product__c != null && policy.Product__c.containsIgnoreCase('Home'));
        response.productType = isHome ? 'Home' : 'Auto';
        response.vehicleAge = saleYear - vehicleYear;
        response.saleDate = effectiveSaleDate;

        /* --- AUTO-POPULATION FIELDS FROM EXISTING CONTRACT (COMMENTED OUT) ---
        response.saleMileage = policy.Vehicle_Mileage_at_Contract_Inception__c != null ? policy.Vehicle_Mileage_at_Contract_Inception__c : 0;
        response.currentCoverageId = policy.Coverage_Level__c != null ? String.valueOf(policy.Coverage_Level__c) : '';
        response.currentCoverageName = coverageName;
        response.currentTermMonths = policy.Contract_Term_Months__c != null ? String.valueOf(Integer.valueOf(policy.Contract_Term_Months__c)) : '';
        response.currentTermMiles = policy.Contract_Term_Mileage__c != null ? String.valueOf(Integer.valueOf(policy.Contract_Term_Mileage__c)) : '';
        response.currentDeductible = policy.Deductible__c != null ? String.valueOf(Integer.valueOf(policy.Deductible__c)) : '';
        response.currentOptions = policy.Option_1__c != null ? policy.Option_1__c : '';
        ------------------------------------------------------------------------ */

        response.coverageOptions = fetchEligibleCoverageLevels(clientName, response.productName, coverageName);

        OptionSetResultWrapper initialOptResult = evaluateOptionSetOptions(
            clientName,
            response.productName,
            response.optionSet,
            coverageName,
            false,
            effectiveSaleDate
        );
        response.optionSet = initialOptResult.activeOptionSet;
        response.initialAvailableOptions = initialOptResult.availableOptions;

        return response;
    }

    @AuraEnabled
    public static OptionSetResultWrapper getOptionsForCoverage(
        String clientName,
        String productName,
        String defaultOptionSet,
        String coverageId,
        Datetime saleDate
    ) {
        String coverageName = '';
        if (String.isNotBlank(coverageId)) {
            List<Coverage_Level__c> covLevels = [SELECT Id, Name FROM Coverage_Level__c WHERE Id = :coverageId LIMIT 1];
            if (!covLevels.isEmpty()) {
                coverageName = covLevels[0].Name;
            }
        }

        Datetime effectiveCheck = saleDate != null ? saleDate : Datetime.now();
        return evaluateOptionSetOptions(
            clientName,
            productName,
            defaultOptionSet,
            coverageName,
            true,
            effectiveCheck
        );
    }

    private static OptionSetResultWrapper evaluateOptionSetOptions(
        String clientName,
        String productName,
        String defaultOptionSet,
        String coverageName,
        Boolean strictCoverageFilter,
        Datetime effectiveCheck
    ) {
        OptionSetResultWrapper result = new OptionSetResultWrapper();
        result.activeOptionSet = defaultOptionSet != null ? defaultOptionSet.trim() : '';
        result.availableOptions = new List<OptionItem>();

        if (String.isNotBlank(clientName) && String.isNotBlank(productName) && String.isNotBlank(coverageName)) {
            String dealerMappedOptionSet = resolveOptionSetFromDealerLookup(clientName, productName, coverageName);
            if (String.isNotBlank(dealerMappedOptionSet)) {
                result.activeOptionSet = dealerMappedOptionSet;
            }
        }

        if (String.isBlank(result.activeOptionSet)
            || result.activeOptionSet.equalsIgnoreCase('N/A')
            || result.activeOptionSet.equalsIgnoreCase('None')) {
            return result;
        }

        Id versionId = resolveActiveMatrixVersionId(result.activeOptionSet, coverageName, effectiveCheck);
        if (versionId == null) {
            return result;
        }

        Set<String> coverageMatchedOptions = new Set<String>();
        Set<String> allMatrixOptions = new Set<String>();
        String targetOptionSet = decodeEntities(result.activeOptionSet).trim().toLowerCase();
        String targetCoverage = String.isNotBlank(coverageName) ? decodeEntities(coverageName).trim().toLowerCase() : '';

        for (CalculationMatrixRow row : [
            SELECT Id, InputData, OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId = :versionId
        ]) {
            if (String.isBlank(row.InputData)) continue;

            Map<String, Object> inputData = (Map<String, Object>) JSON.deserializeUntyped(row.InputData);
            Map<String, Object> outputData = String.isNotBlank(row.OutputData)
                ? (Map<String, Object>) JSON.deserializeUntyped(row.OutputData)
                : new Map<String, Object>();

            String rowOptionSet = extractByNormalizedKey(inputData, OPTION_SET_KEYS);
            if (String.isNotBlank(rowOptionSet) && !rowOptionSet.equalsIgnoreCase(targetOptionSet)) {
                continue;
            }

            String optionName = extractByNormalizedKey(inputData, OPTION_NAME_KEYS);
            if (String.isBlank(optionName)) {
                optionName = extractByNormalizedKey(outputData, OPTION_NAME_KEYS);
            }
            if (String.isBlank(optionName)
                || optionName.equalsIgnoreCase('N/A')
                || optionName.equalsIgnoreCase('None')) {
                continue;
            }

            allMatrixOptions.add(optionName);

            String rowCoverage = extractByNormalizedKey(inputData, COVERAGE_KEYS);
            if (String.isBlank(rowCoverage)
                || rowCoverage.equalsIgnoreCase('All')
                || rowCoverage.equalsIgnoreCase('Include All')
                || (String.isNotBlank(targetCoverage) && rowCoverage.equalsIgnoreCase(targetCoverage))) {
                coverageMatchedOptions.add(optionName);
            }
        }

        Set<String> finalOptionNames = coverageMatchedOptions;
        if (!strictCoverageFilter && finalOptionNames.isEmpty()) {
            finalOptionNames = allMatrixOptions;
        }

        for (String opt : finalOptionNames) {
            result.availableOptions.add(new OptionItem(opt, opt));
        }
        result.availableOptions.sort();

        return result;
    }

    private static String resolveOptionSetFromDealerLookup(String clientName, String productName, String coverageName) {
        List<CalculationMatrixVersion> dealerVersions = [
            SELECT Id
            FROM CalculationMatrixVersion
            WHERE (CalculationMatrix.UniqueName = 'Dealer_Code_Lookup' OR CalculationMatrix.Name = 'Dealer_Code_Lookup')
            AND IsEnabled = true
            ORDER BY Rank ASC NULLS LAST, StartDateTime DESC, VersionNumber DESC
            LIMIT 1
        ];

        if (dealerVersions.isEmpty()) {
            return '';
        }

        String targetClient = decodeEntities(clientName).trim().toLowerCase();
        String targetProduct = decodeEntities(productName).trim().toLowerCase();
        String targetCoverage = decodeEntities(coverageName).trim().toLowerCase();

        for (CalculationMatrixRow row : [
            SELECT Id, OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId = :dealerVersions[0].Id
        ]) {
            if (String.isBlank(row.OutputData)) continue;

            Map<String, Object> outMap = (Map<String, Object>) JSON.deserializeUntyped(row.OutputData);
            String rowClient = outMap.get('Client') != null ? decodeEntities(String.valueOf(outMap.get('Client'))).trim().toLowerCase() : '';
            String rowProduct = outMap.get('Product') != null ? decodeEntities(String.valueOf(outMap.get('Product'))).trim().toLowerCase() : '';
            String rowCov = outMap.get('CoverageLevel') != null ? decodeEntities(String.valueOf(outMap.get('CoverageLevel'))).trim().toLowerCase() : '';

            if (rowClient == targetClient && rowProduct == targetProduct && rowCov == targetCoverage) {
                String foundOptionSet = extractRawByNormalizedKey(outMap, OPTION_SET_KEYS);
                if (String.isNotBlank(foundOptionSet)) {
                    return foundOptionSet;
                }
            }
        }

        return '';
    }

    private static Id resolveActiveMatrixVersionId(String tableName, String coverageName, Datetime effectiveCheck) {
        List<String> candidateNames = new List<String>();

        String exactMdtName = getMatrixNameFromMetadata(tableName, coverageName);
        if (String.isNotBlank(exactMdtName)) {
            candidateNames.add(exactMdtName.trim());
        }

        String tableOnlyMdtName = getMatrixNameFromMetadata(tableName, null);
        if (String.isNotBlank(tableOnlyMdtName) && !candidateNames.contains(tableOnlyMdtName.trim())) {
            candidateNames.add(tableOnlyMdtName.trim());
        }

        if (String.isNotBlank(coverageName)) {
            String generatedWithCov = generateMatrixName(tableName, coverageName);
            if (String.isNotBlank(generatedWithCov) && !candidateNames.contains(generatedWithCov)) {
                candidateNames.add(generatedWithCov);
            }
        }

        String rawTableName = tableName.trim();
        if (!candidateNames.contains(rawTableName)) {
            candidateNames.add(rawTableName);
        }

        String sanitizedTableOnly = sanitizeMatrixName(rawTableName);
        if (String.isNotBlank(sanitizedTableOnly) && !candidateNames.contains(sanitizedTableOnly)) {
            candidateNames.add(sanitizedTableOnly);
        }

        if (!candidateNames.contains('Options_Sets')) {
            candidateNames.add('Options_Sets');
        }

        List<CalculationMatrixVersion> versions = [
            SELECT Id,
                   CalculationMatrix.Name,
                   CalculationMatrix.UniqueName,
                   StartDateTime,
                   EndDateTime
            FROM CalculationMatrixVersion
            WHERE (CalculationMatrix.Name IN :candidateNames OR CalculationMatrix.UniqueName IN :candidateNames)
            AND IsEnabled = true
            ORDER BY Rank ASC NULLS LAST, StartDateTime DESC, VersionNumber DESC
        ];

        if (versions.isEmpty()) {
            return null;
        }

        for (String candidate : candidateNames) {
            for (CalculationMatrixVersion v : versions) {
                Boolean nameMatches = (v.CalculationMatrix.Name != null && v.CalculationMatrix.Name.equalsIgnoreCase(candidate))
                    || (v.CalculationMatrix.UniqueName != null && v.CalculationMatrix.UniqueName.equalsIgnoreCase(candidate));
                Boolean dateMatches = v.StartDateTime <= effectiveCheck
                    && (v.EndDateTime == null || v.EndDateTime >= effectiveCheck);
                if (nameMatches && dateMatches) {
                    return v.Id;
                }
            }
            for (CalculationMatrixVersion v : versions) {
                Boolean nameMatches = (v.CalculationMatrix.Name != null && v.CalculationMatrix.Name.equalsIgnoreCase(candidate))
                    || (v.CalculationMatrix.UniqueName != null && v.CalculationMatrix.UniqueName.equalsIgnoreCase(candidate));
                if (nameMatches) {
                    return v.Id;
                }
            }
        }

        return versions[0].Id;
    }

    private static List<OptionItem> fetchEligibleCoverageLevels(String clientName, String productName, String fallbackCoverageName) {
        List<OptionItem> options = new List<OptionItem>();
        Set<String> validCoverageNames = new Set<String>();

        if (String.isNotBlank(clientName) && String.isNotBlank(productName)) {
            List<CalculationMatrixVersion> dealerVersions = [
                SELECT Id
                FROM CalculationMatrixVersion
                WHERE (CalculationMatrix.UniqueName = 'Dealer_Code_Lookup' OR CalculationMatrix.Name = 'Dealer_Code_Lookup')
                AND IsEnabled = true
                ORDER BY Rank ASC NULLS LAST, StartDateTime DESC, VersionNumber DESC
                LIMIT 1
            ];

            if (!dealerVersions.isEmpty()) {
                String targetClient = decodeEntities(clientName).trim().toLowerCase();
                String targetProduct = decodeEntities(productName).trim().toLowerCase();

                for (CalculationMatrixRow row : [
                    SELECT Id, OutputData
                    FROM CalculationMatrixRow
                    WHERE CalculationMatrixVersionId = :dealerVersions[0].Id
                ]) {
                    if (String.isBlank(row.OutputData)) continue;

                    Map<String, Object> outMap = (Map<String, Object>) JSON.deserializeUntyped(row.OutputData);
                    String rowClient = outMap.get('Client') != null ? decodeEntities(String.valueOf(outMap.get('Client'))).trim().toLowerCase() : '';
                    String rowProduct = outMap.get('Product') != null ? decodeEntities(String.valueOf(outMap.get('Product'))).trim().toLowerCase() : '';

                    if (rowClient == targetClient && rowProduct == targetProduct) {
                        Object covObj = outMap.get('CoverageLevel');
                        if (covObj != null && String.isNotBlank(String.valueOf(covObj))) {
                            validCoverageNames.add(decodeEntities(String.valueOf(covObj)).trim());
                        }
                    }
                }
            }
        }

        if (validCoverageNames.isEmpty() && String.isNotBlank(fallbackCoverageName)) {
            validCoverageNames.add(fallbackCoverageName.trim());
        }

        if (!validCoverageNames.isEmpty()) {
            for (Coverage_Level__c cov : [
                SELECT Id, Name
                FROM Coverage_Level__c
                WHERE Name IN :validCoverageNames
                ORDER BY Name ASC
            ]) {
                options.add(new OptionItem(cov.Name, cov.Id));
            }
        }

        return options;
    }

    @AuraEnabled
    public static List<MatrixRowItem> getEligibleMatrixRows(
        String rateSet,
        String coverageId,
        Decimal saleMileage,
        Integer vehicleAge,
        String rateClass,
        Datetime saleDate
    ) {
        List<MatrixRowItem> matchingRows = new List<MatrixRowItem>();

        if (String.isBlank(rateSet) || String.isBlank(coverageId)) {
            return matchingRows;
        }

        List<Coverage_Level__c> covLevels = [SELECT Id, Name FROM Coverage_Level__c WHERE Id = :coverageId LIMIT 1];
        if (covLevels.isEmpty()) {
            return matchingRows;
        }
        String coverageName = covLevels[0].Name;

        Datetime effectiveCheck = saleDate != null ? saleDate : Datetime.now();
        Id activeVersionId = resolveActiveMatrixVersionId(rateSet, coverageName, effectiveCheck);
        if (activeVersionId == null) {
            return matchingRows;
        }

        Decimal checkMileage = saleMileage != null ? saleMileage : 0;
        Integer checkAge = vehicleAge != null ? vehicleAge : 0;
        String checkClass = rateClass != null ? rateClass.trim() : '';

        for (CalculationMatrixRow row : [
            SELECT Id, InputData, OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId = :activeVersionId
        ]) {
            if (String.isBlank(row.InputData) || String.isBlank(row.OutputData)) continue;

            Map<String, Object> inputData = (Map<String, Object>) JSON.deserializeUntyped(row.InputData);
            Map<String, Object> outputData = (Map<String, Object>) JSON.deserializeUntyped(row.OutputData);

            String rowCoverage = inputData.get('CoverageName') != null ? String.valueOf(inputData.get('CoverageName')).trim() : '';
            if (String.isNotBlank(rowCoverage) && rowCoverage != coverageName) continue;

            Decimal minMiles = parseDecimal(inputData.get('MinMiles'), 0);
            Decimal maxMiles = parseDecimal(outputData.get('MaxMiles'), 9999999);
            if (checkMileage < minMiles) continue;
            if (checkMileage > maxMiles) continue;

            Decimal minAge = parseDecimal(inputData.get('MinAge'), 0);
            Decimal maxAge = parseDecimal(outputData.get('MaxAge'), 999);
            if (checkAge < minAge) continue;
            if (checkAge > maxAge) continue;

            String matrixRateClass = inputData.get('RateClass') != null ? String.valueOf(inputData.get('RateClass')).trim() : '';
            if (String.isNotBlank(matrixRateClass) && String.isNotBlank(checkClass) && matrixRateClass != checkClass) {
                continue;
            }

            MatrixRowItem item = new MatrixRowItem();
            item.termMonths = inputData.get('TermMonths') != null ? String.valueOf(inputData.get('TermMonths')).trim() : '';
            item.termMiles = inputData.get('TermMiles') != null ? String.valueOf(inputData.get('TermMiles')).trim() : '';
            item.deductible = inputData.get('Deductible') != null ? cleanCurrency(String.valueOf(inputData.get('Deductible'))) : '';
            item.minMiles = minMiles;
            item.maxMiles = maxMiles;
            matchingRows.add(item);
        }

        return matchingRows;
    }

    private static String extractByNormalizedKey(Map<String, Object> dataMap, Set<String> targetNormalizedKeys) {
        String raw = extractRawByNormalizedKey(dataMap, targetNormalizedKeys);
        if (String.isBlank(raw) || raw.equalsIgnoreCase('null')) {
            return '';
        }
        return raw;
    }

    private static String extractRawByNormalizedKey(Map<String, Object> dataMap, Set<String> targetNormalizedKeys) {
        if (dataMap == null) return '';
        for (String key : dataMap.keySet()) {
            if (key == null) continue;
            String normalized = key.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();
            if (targetNormalizedKeys.contains(normalized) && dataMap.get(key) != null) {
                String val = decodeEntities(String.valueOf(dataMap.get(key))).trim();
                if (String.isNotBlank(val)) {
                    return val;
                }
            }
        }
        return '';
    }

    private static Decimal parseDecimal(Object val, Decimal defaultVal) {
        if (val == null) return defaultVal;
        String str = String.valueOf(val).replace('$', '').replace(',', '').trim();
        if (String.isBlank(str)) return defaultVal;
        try {
            return Decimal.valueOf(str);
        } catch (Exception e) {
            return defaultVal;
        }
    }

    private static String cleanCurrency(String rawVal) {
        if (String.isBlank(rawVal)) return '';
        String cleaned = rawVal.replace('$', '').replace(',', '').trim();
        if (cleaned.endsWith('.00')) {
            cleaned = cleaned.substring(0, cleaned.length() - 3);
        }
        return cleaned;
    }

    private static String decodeEntities(String inputStr) {
        if (String.isBlank(inputStr)) return '';
        return inputStr
            .replace('&amp;', '&')
            .replace('&#39;', '\'')
            .replace('&quot;', '"');
    }

    private static String getMatrixNameFromMetadata(String rateSet, String coverageName) {
        if (String.isBlank(rateSet)) return null;
        String cleanTable = rateSet.trim();
        String cleanCov = String.isNotBlank(coverageName) ? coverageName.trim() : '';

        for (DecisionMatrixMapping__mdt mdt : DecisionMatrixMapping__mdt.getAll().values()) {
            if (mdt.Table_Name__c != null && mdt.Table_Name__c.trim().equalsIgnoreCase(cleanTable)) {
                if (String.isBlank(cleanCov) && String.isBlank(mdt.Coverage_Level__c)) {
                    return mdt.Decision_Matrix_Name__c;
                }
                if (String.isNotBlank(cleanCov)
                    && String.isNotBlank(mdt.Coverage_Level__c)
                    && mdt.Coverage_Level__c.trim().equalsIgnoreCase(cleanCov)) {
                    return mdt.Decision_Matrix_Name__c;
                }
            }
        }
        return null;
    }

    private static String sanitizeMatrixName(String rawName) {
        if (String.isBlank(rawName)) return '';
        String cleaned = rawName.replaceAll(' - ', '_').replaceAll('-', '_').replaceAll(' ', '_').replaceAll('\\(', '').replaceAll('\\)', '').replaceAll('\\.', '_');
        return cleaned.replaceAll('_+', '_');
    }

    private static String generateMatrixName(String rateSet, String coverageName) {
        String combined = rateSet + '_' + coverageName;
        combined = sanitizeMatrixName(combined);
        if (combined.equalsIgnoreCase('Health_CAR_23_31_79_Health_CAR')) return 'Health_CAR_Health_CAR';
        if (combined.equalsIgnoreCase('Health_CAR_23_31_79_Health_CAR_Validation')) return 'Health_CAR_Health_CAR_Validation';
        if (rateSet == 'MBI - Amtrust (CA)') combined = combined.replaceAll('MBI_Amtrust', 'MBI_AmTrust');
        return combined;
    }
}