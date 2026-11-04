public with sharing class ReRateLWCController {

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

    public class ContractDataWrapper {
        @AuraEnabled public String clientName { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String rateSet { get; set; }
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
        @AuraEnabled public List<OptionItem> coverageOptions { get; set; }
    }

    @AuraEnabled
    public static ContractDataWrapper getInitialContractData(Id contractId) {
        ContractDataWrapper response = new ContractDataWrapper();
        response.coverageOptions = new List<OptionItem>();

        List<InsurancePolicy> policies = [
            SELECT Id,
                   RecordType.Name,
                   Client__c,
                   Product__c,
                   Coverage_Level__c,
                   Rate_Set__c,
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
        response.rateClass = policy.Class__c != null ? policy.Class__c : '';
        Boolean isHome = (policy.RecordType != null && policy.RecordType.Name == 'Home Warranty')
            || String.isNotBlank(policy.Residential_Type__c)
            || (policy.Product__c != null && policy.Product__c.containsIgnoreCase('Home'));
        response.productType = isHome ? 'Home' : 'Auto';
        response.saleMileage = policy.Vehicle_Mileage_at_Contract_Inception__c != null ? policy.Vehicle_Mileage_at_Contract_Inception__c : 0;
        response.vehicleAge = saleYear - vehicleYear;
        response.saleDate = effectiveSaleDate;
        response.currentCoverageId = policy.Coverage_Level__c != null ? String.valueOf(policy.Coverage_Level__c) : '';
        response.currentCoverageName = coverageName;
        response.currentTermMonths = policy.Contract_Term_Months__c != null ? String.valueOf(Integer.valueOf(policy.Contract_Term_Months__c)) : '';
        response.currentTermMiles = policy.Contract_Term_Mileage__c != null ? String.valueOf(Integer.valueOf(policy.Contract_Term_Mileage__c)) : '';
        response.currentDeductible = policy.Deductible__c != null ? String.valueOf(Integer.valueOf(policy.Deductible__c)) : '';

        response.coverageOptions = fetchEligibleCoverageLevels(clientName, response.productName, coverageName);
        return response;
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

        String matrixName = getMatrixNameFromMetadata(rateSet, coverageName);
        if (String.isBlank(matrixName)) {
            matrixName = generateMatrixName(rateSet, coverageName);
        }

        Datetime effectiveCheck = saleDate != null ? saleDate : Datetime.now();

        List<CalculationMatrixVersion> activeVersions = [
            SELECT Id
            FROM CalculationMatrixVersion
            WHERE (CalculationMatrix.Name = :matrixName OR CalculationMatrix.UniqueName = :matrixName)
            AND IsEnabled = true
            AND StartDateTime <= :effectiveCheck
            AND (EndDateTime = null OR EndDateTime >= :effectiveCheck)
            ORDER BY Rank ASC NULLS LAST, StartDateTime DESC, VersionNumber DESC
            LIMIT 1
        ];

        if (activeVersions.isEmpty()) {
            activeVersions = [
                SELECT Id
                FROM CalculationMatrixVersion
                WHERE (CalculationMatrix.Name = :matrixName OR CalculationMatrix.UniqueName = :matrixName)
                AND IsEnabled = true
                ORDER BY Rank ASC NULLS LAST, StartDateTime DESC, VersionNumber DESC
                LIMIT 1
            ];
        }

        if (activeVersions.isEmpty()) {
            return matchingRows;
        }

        Decimal checkMileage = saleMileage != null ? saleMileage : 0;
        Integer checkAge = vehicleAge != null ? vehicleAge : 0;
        String checkClass = rateClass != null ? rateClass.trim() : '';

        for (CalculationMatrixRow row : [
            SELECT Id, InputData, OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId = :activeVersions[0].Id
        ]) {
            if (String.isBlank(row.InputData) || String.isBlank(row.OutputData)) continue;

            Map<String, Object> inputData = (Map<String, Object>) JSON.deserializeUntyped(row.InputData);
            Map<String, Object> outputData = (Map<String, Object>) JSON.deserializeUntyped(row.OutputData);

            String rowCoverage = inputData.get('CoverageName') != null ? String.valueOf(inputData.get('CoverageName')).trim() : '';
            if (rowCoverage != coverageName) continue;

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
        for (DecisionMatrixMapping__mdt mdt : DecisionMatrixMapping__mdt.getAll().values()) {
            if (mdt.Table_Name__c == rateSet) {
                if (String.isBlank(coverageName) && mdt.Coverage_Level__c == null) {
                    return mdt.Decision_Matrix_Name__c;
                }
                if (String.isNotBlank(coverageName) && mdt.Coverage_Level__c == coverageName) {
                    return mdt.Decision_Matrix_Name__c;
                }
            }
        }
        return null;
    }

    private static String generateMatrixName(String rateSet, String coverageName) {
        String combined = rateSet + '_' + coverageName;
        combined = combined.replaceAll(' - ', '_').replaceAll('-', '_').replaceAll(' ', '_').replaceAll('\\(', '').replaceAll('\\)', '').replaceAll('\\.', '_');
        combined = combined.replaceAll('_+', '_');
        if (combined.equalsIgnoreCase('Health_CAR_23_31_79_Health_CAR')) return 'Health_CAR_Health_CAR';
        if (combined.equalsIgnoreCase('Health_CAR_23_31_79_Health_CAR_Validation')) return 'Health_CAR_Health_CAR_Validation';
        if (rateSet == 'MBI - Amtrust (CA)') combined = combined.replaceAll('MBI_Amtrust', 'MBI_AmTrust');
        return combined;
    }
}