global class ReRateOptionsUtility implements Callable {

    // ============================================================
    // CALLABLE ENTRY POINT
    // ============================================================

    global Object call(String action, Map<String, Object> args) {

        Map<String, Object> input =
            (Map<String, Object>) args.get('input');

        Map<String, Object> output =
            (Map<String, Object>) args.get('output');

        if (input == null) {
            input = new Map<String, Object>();
        }

        if (output == null) {
            output = new Map<String, Object>();
        }
        
        System.debug('INPUT : ' + input);

        try {

            if (action == 'getCoverageLevelOptions') {

                return getCoverageLevelOptions(input, output);

            } else if (action == 'getTermMonthOptions') {

                return getMatrixDependentOptions(
                    input, output, 'TermMonths'
                );

            } else if (action == 'getTermMileOptions') {

                return getMatrixDependentOptions(
                    input, output, 'TermMiles'
                );

            } else if (action == 'getDeductibleOptions') {

                return getMatrixDependentOptions(
                    input, output, 'Deductible'
                );
            }

            return null;

        } catch (Exception ex) {

            QDX_LOG.error(
                'Error in ReRateOptionsUtility: ' +
                ex.getMessage() +
                ' Line: ' + ex.getLineNumber()
            );

            output.put('error', ex.getMessage());

            output.put(
                'options',
                new List<Map<String, Object>>()
            );

            return output.get('options');
        }
    }


    // ============================================================
    // GET INSURANCE POLICY
    // ============================================================

    private InsurancePolicy getPolicyRecord(
        Map<String, Object> input
    ) {

        String contextId = (String) input.get('ContextId');

        if (String.isBlank(contextId)) {
            contextId = (String) input.get('contractId');
        }

        if (String.isBlank(contextId)) {
            return null;
        }

        List<InsurancePolicy> policies = [
            SELECT Client__c,
                   Product__c,
                   Vehicle_Year__c,
                   Class__c,
                   Rate_Set__c,
                   SaleDate
            FROM InsurancePolicy
            WHERE Id = :contextId
            LIMIT 1
        ];
        
        System.debug('POLICIES : ' + policies[0].Id);

        return policies.isEmpty() ? null : policies[0];
    }


    // ============================================================
    // 1. COVERAGE LEVEL OPTIONS
    // DIRECT SOQL - NO BRE CALLOUT
    // ============================================================

    private List<Map<String, Object>> getCoverageLevelOptions(
        Map<String, Object> input,
        Map<String, Object> output
    ) {

        List<Map<String, Object>> optionList =
            new List<Map<String, Object>>();

        Set<String> validCoverageNames = new Set<String>();

        // 1. Get Insurance Policy
        InsurancePolicy policy = getPolicyRecord(input);

        if (policy == null ||
            policy.Client__c == null ||
            String.isBlank(policy.Product__c)) {

            output.put('options', optionList);
            return optionList;
        }

        // 2. Get Client Account
        List<Account> dealers = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :policy.Client__c
            LIMIT 1
        ];

        if (dealers.isEmpty() ||
            String.isBlank(dealers[0].Name)) {

            output.put('options', optionList);
            return optionList;
        }

        String clientName =
            dealers[0].Name.trim().toLowerCase();

        String productName =
            policy.Product__c.trim().toLowerCase();

        System.debug(
            LoggingLevel.ERROR,
            'Coverage Matrix Client: ' + clientName
        );

        System.debug(
            LoggingLevel.ERROR,
            'Coverage Matrix Product: ' + productName
        );

        // 3. Retrieve Dealer Code Lookup Matrix Rows
        List<CalculationMatrixRow> matrixRows = [
            SELECT Id,
                   InputData,
                   OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersion.ApiName =
                'Dealer_Code_Lookup_V4'
        ];

        System.debug(
            LoggingLevel.ERROR,
            'Dealer Matrix Rows Found: ' + matrixRows.size()
        );

        // 4. Match Client + Product
        for (CalculationMatrixRow matrixRow : matrixRows) {

            if (String.isBlank(matrixRow.OutputData)) {
                continue;
            }

            Map<String, Object> outputData =
                (Map<String, Object>)
                JSON.deserializeUntyped(matrixRow.OutputData);

            Object clientValue = outputData.get('Client');

            Object productValue = outputData.get('Product');

            if (clientValue == null ||
                productValue == null) {
                continue;
            }

            String matrixClient =
                String.valueOf(clientValue)
                    .trim()
                    .toLowerCase();

            String matrixProduct =
                String.valueOf(productValue)
                    .trim()
                    .toLowerCase();

            if (matrixClient != clientName ||
                matrixProduct != productName) {
                continue;
            }

            System.debug(
                LoggingLevel.ERROR,
                'Matching Dealer Matrix Row: ' + matrixRow.Id
            );

            // 5. Extract Coverage Level
            Object coverageValue =
                outputData.get('CoverageLevel');

            if (coverageValue != null &&
                String.isNotBlank(String.valueOf(coverageValue))) {

                validCoverageNames.add(
                    String.valueOf(coverageValue).trim()
                );
            }
        }

        System.debug(
            LoggingLevel.ERROR,
            'Matched Coverage Names: ' +
            JSON.serialize(validCoverageNames)
        );

        // 6. Retrieve Coverage Level Records
        if (!validCoverageNames.isEmpty()) {

            for (Coverage_Level__c covLevel : [
                SELECT Id, Name
                FROM Coverage_Level__c
                WHERE Name IN :validCoverageNames
                ORDER BY Name ASC
            ]) {

                Map<String, Object> optionMap =
                    new Map<String, Object>();

                optionMap.put('name', covLevel.Id);
                optionMap.put('value', covLevel.Name);

                optionList.add(optionMap);
            }
        }
        
        System.debug('OPTIONS : ' + optionList);

        // 7. Return Options
        output.put('options', optionList);

        System.debug(
            LoggingLevel.ERROR,
            'Final Coverage Options: ' +
            JSON.serializePretty(optionList)
        );

        return optionList;
    }


    // ============================================================
    // 2. TERM MONTHS / TERM MILES / DEDUCTIBLE OPTIONS
    // EXISTING MATRIX FILTERING LOGIC PRESERVED
    // ============================================================

    private List<Map<String, Object>> getMatrixDependentOptions(
        Map<String, Object> input,
        Map<String, Object> output,
        String targetColumn
    ) {

        List<Map<String, Object>> options =
            new List<Map<String, Object>>();

        // Query baseline data
        InsurancePolicy policy = getPolicyRecord(input);

        if (policy == null) {
            output.put('options', options);
            return options;
        }

        String rateSet = policy.Rate_Set__c;

        Datetime saleDate =
            policy.SaleDate != null
            ? policy.SaleDate
            : Datetime.now();

        // Calculate Vehicle Age
        Integer saleYear = saleDate.year();

        Integer vehicleYear = saleYear;

        if (String.isNotBlank(policy.Vehicle_Year__c)) {
            vehicleYear = Integer.valueOf(policy.Vehicle_Year__c);
        }

        Integer vehicleAge = saleYear - vehicleYear;

        String rateClass =
            policy.Class__c != null
            ? policy.Class__c
            : '';

        // Extract UI Node
        Map<String, Object> stepNode =
            (Map<String, Object>)
            input.get('ReRateFieldsForNotSecureOneProducts');

        if (stepNode == null) {
            output.put('options', options);
            return options;
        }

        String coverageId =
            (String) stepNode.get('Coverage_Name_NonSecureOne');

        String selectedMonths =
            (String) stepNode.get('Term_Months_NonSecureOne');

        String selectedMiles =
            (String) stepNode.get('Term_Miles_NonSecureOne');

        // Sale Mileage
        Decimal saleMileage =
            stepNode.get('Sale_Mileage_NonSecureOne') != null
            ? Decimal.valueOf(
                String.valueOf(
                    stepNode.get('Sale_Mileage_NonSecureOne')
                )
            )
            : 0;

        if (String.isBlank(rateSet) ||
            String.isBlank(coverageId)) {

            output.put('options', options);
            return options;
        }

        // Resolve Coverage Name
        String coverageName = coverageId;

        if (coverageId.startsWith('a8H') ||
            coverageId.length() == 15 ||
            coverageId.length() == 18) {

            List<Coverage_Level__c> covLevels = [
                SELECT Name
                FROM Coverage_Level__c
                WHERE Id = :coverageId
                LIMIT 1
            ];

            if (covLevels.isEmpty()) {
                output.put('options', options);
                return options;
            }

            coverageName = covLevels[0].Name;
        }

        // Get Matrix Name
        String matrixName =
            getMatrixNameFromMetadata(rateSet, coverageName);

        if (String.isBlank(matrixName)) {
            matrixName = generateMatrixName(
                rateSet, coverageName
            );
        }

        // Existing effective-date logic retained
        Datetime effectiveDate =
            BREServiceHandlerBulkified.getEffectiveStartDate(
                matrixName,
                UtilityClass.BR_TYPE_DM,
                saleDate
            );

        // Retrieve active Matrix Version
        List<CalculationMatrixVersion> activeVersions = [
            SELECT Id
            FROM CalculationMatrixVersion
            WHERE IsEnabled = true
            AND StartDateTime <= :effectiveDate
            AND CalculationMatrix.Name = :matrixName
            ORDER BY StartDateTime DESC
            LIMIT 1
        ];

        if (activeVersions.isEmpty()) {
            output.put('options', options);
            return options;
        }

        // Retrieve Matrix Rows
        List<CalculationMatrixRow> matrixRows = [
            SELECT InputData, OutputData
            FROM CalculationMatrixRow
            WHERE CalculationMatrixVersionId =
                :activeVersions[0].Id
        ];

        Set<String> distinctValues = new Set<String>();

        for (CalculationMatrixRow row : matrixRows) {

            if (String.isBlank(row.InputData) ||
                String.isBlank(row.OutputData)) {
                continue;
            }

            Map<String, Object> rowInputData =
                (Map<String, Object>)
                JSON.deserializeUntyped(row.InputData);

            Map<String, Object> rowOutputData =
                (Map<String, Object>)
                JSON.deserializeUntyped(row.OutputData);

            if (!rowInputData.containsKey('CoverageName') ||
                String.valueOf(rowInputData.get('CoverageName'))
                    != coverageName) {

                continue;
            }

            Decimal minMiles =
                rowInputData.containsKey('MinMiles') &&
                rowInputData.get('MinMiles') != null
                ? Decimal.valueOf(
                    String.valueOf(rowInputData.get('MinMiles'))
                )
                : 0;

            Decimal maxMiles =
                rowOutputData.containsKey('MaxMiles') &&
                rowOutputData.get('MaxMiles') != null
                ? Decimal.valueOf(
                    String.valueOf(rowOutputData.get('MaxMiles'))
                )
                : 999999;

            if (saleMileage < minMiles ||
                saleMileage > maxMiles) {
                continue;
            }

            Decimal minAge =
                rowInputData.containsKey('MinAge') &&
                rowInputData.get('MinAge') != null
                ? Decimal.valueOf(
                    String.valueOf(rowInputData.get('MinAge'))
                )
                : 0;

            Decimal maxAge =
                rowOutputData.containsKey('MaxAge') &&
                rowOutputData.get('MaxAge') != null
                ? Decimal.valueOf(
                    String.valueOf(rowOutputData.get('MaxAge'))
                )
                : 99;

            if (vehicleAge < minAge ||
                vehicleAge > maxAge) {
                continue;
            }

            String matrixRateClass =
                rowInputData.containsKey('RateClass') &&
                rowInputData.get('RateClass') != null
                ? String.valueOf(rowInputData.get('RateClass'))
                : '';

            if (String.isNotBlank(matrixRateClass) &&
                matrixRateClass != rateClass) {
                continue;
            }

            if (targetColumn == 'TermMiles' &&
                String.isNotBlank(selectedMonths)) {

                if (rowInputData.containsKey('TermMonths') &&
                    String.valueOf(
                        rowInputData.get('TermMonths')
                    ) != selectedMonths) {

                    continue;
                }
            }

            if (targetColumn == 'Deductible') {

                if (String.isNotBlank(selectedMonths) &&
                    rowInputData.containsKey('TermMonths') &&
                    String.valueOf(
                        rowInputData.get('TermMonths')
                    ) != selectedMonths) {

                    continue;
                }

                if (String.isNotBlank(selectedMiles) &&
                    rowInputData.containsKey('TermMiles') &&
                    String.valueOf(
                        rowInputData.get('TermMiles')
                    ) != selectedMiles) {

                    continue;
                }
            }

            if (rowInputData.containsKey(targetColumn) &&
                rowInputData.get(targetColumn) != null) {

                distinctValues.add(
                    String.valueOf(
                        rowInputData.get(targetColumn)
                    )
                );
            }
        }

        // Prepare Options
        List<String> sortedList =
            new List<String>(distinctValues);

        sortedList.sort();

        for (String val : sortedList) {

            Map<String, Object> optionMap =
                new Map<String, Object>();

            optionMap.put('name', val);
            optionMap.put('value', val);

            options.add(optionMap);
        }

        output.put('options', options);

        return options;
    }


    // ============================================================
    // 3. MATRIX NAME FROM CUSTOM METADATA
    // ============================================================

    private String getMatrixNameFromMetadata(
        String rateSet,
        String coverageName
    ) {

        for (DecisionMatrixMapping__mdt mdt :
             DecisionMatrixMapping__mdt.getAll().values()) {

            if (mdt.Table_Name__c == rateSet) {

                if (String.isBlank(coverageName) &&
                    mdt.Coverage_Level__c == null) {

                    return mdt.Decision_Matrix_Name__c;
                }

                if (String.isNotBlank(coverageName) &&
                    mdt.Coverage_Level__c == coverageName) {

                    return mdt.Decision_Matrix_Name__c;
                }
            }
        }

        return null;
    }


    // ============================================================
    // 4. GENERATE MATRIX NAME
    // ============================================================

    private String generateMatrixName(
        String rateSet,
        String coverageName
    ) {

        String combined = rateSet + '_' + coverageName;

        combined = combined
            .replaceAll(' - ', '_')
            .replaceAll('-', '_')
            .replaceAll(' ', '_')
            .replaceAll('\\(', '')
            .replaceAll('\\)', '')
            .replaceAll('\\.', '_');

        combined = combined.replaceAll('_+', '_');

        if (combined.equalsIgnoreCase(
            'Health_CAR_23_31_79_Health_CAR'
        )) {
            return 'Health_CAR_Health_CAR';
        }

        if (combined.equalsIgnoreCase(
            'Health_CAR_23_31_79_Health_CAR_Validation'
        )) {
            return 'Health_CAR_Health_CAR_Validation';
        }

        if (rateSet == 'MBI - Amtrust (CA)') {
            combined = combined.replaceAll(
                'MBI_Amtrust',
                'MBI_AmTrust'
            );
        }

        return combined;
    }
}