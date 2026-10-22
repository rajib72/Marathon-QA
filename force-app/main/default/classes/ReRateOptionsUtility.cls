global class ReRateOptionsUtility implements Callable {
    
    global Object call(String action, Map<String, Object> args) {
        Map<String, Object> input = (Map<String, Object>)args.get('input');
        Map<String, Object> output = (Map<String, Object>)args.get('output');
        
        try {
            if (action == 'getCoverageLevelOptions') {
                getCoverageLevelOptions(input, output);
            } else if (action == 'getTermMonthOptions') {
                getMatrixDependentOptions(input, output, 'TermMonths');
            } else if (action == 'getTermMileOptions') {
                getMatrixDependentOptions(input, output, 'TermMiles');
            } else if (action == 'getDeductibleOptions') {
                getMatrixDependentOptions(input, output, 'Deductible');
            }
        } catch (Exception ex) {
            QDX_LOG.error('Error in ReRateOptionsUtility: ' + ex.getMessage() + ' Line: ' + ex.getLineNumber());
            output.put('error', ex.getMessage());
        }
        return true;
    }

    /**
     * 1. Fetches Coverage Levels by evaluating the Dealer_Code_Lookup matrix via standard BRE Callout
     */
    private void getCoverageLevelOptions(Map<String, Object> input, Map<String, Object> output) {
        // In OmniScript, 'input' contains the full data JSON for Custom Option Sources
        Map<String, Object> contractNode = (Map<String, Object>) input.get('Contract');
        if (contractNode == null || contractNode.get('Client__c') == null) return;
        
        // Find Dealer via Client ID
        List<Account> dealers = [SELECT AccountNumber FROM Account WHERE Id = :String.valueOf(contractNode.get('Client__c')) LIMIT 1];
        if (dealers.isEmpty() || String.isBlank(dealers[0].AccountNumber)) return;

        Datetime saleDate = Datetime.now();
        if (input.get('Sale_Date') != null) {
            saleDate = Datetime.valueOf(String.valueOf(input.get('Sale_Date')) + ' 00:00:00');
        }

        List<Map<String, Object>> paramBatch = new List<Map<String, Object>>();
        paramBatch.add(new Map<String, Object>{ 'DealerProgramId' => Integer.valueOf(dealers[0].AccountNumber) });
        
        // Execute standard BRE callout just like BREServiceHandlerBulkified
        String dealerJsonString = BREServiceHandlerBulkified.runBRCallout(
            paramBatch, saleDate, 'Dealer_Code_Lookup', UtilityClass.BR_TYPE_DM, UtilityClass.IS_INTERNAL_CALL
        );
        
        Set<String> coverageLevelNames = new Set<String>();
        if (String.isNotBlank(dealerJsonString)) {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(dealerJsonString);
            List<Object> outputs = (List<Object>) jsonMap.get('outputs');
            if (outputs != null && !outputs.isEmpty()) {
                Map<String, Object> outputRecord = (Map<String, Object>) outputs[0];
                if (outputRecord.containsKey('results')) {
                    List<Object> results = (List<Object>) outputRecord.get('results');
                    for (Object resultObj : results) {
                        Map<String, Object> result = (Map<String, Object>) resultObj;
                        if (result.get('name') == 'CoverageLevel') {
                            coverageLevelNames.add((String) result.get('value'));
                        }
                    }
                }
            }
        }
        
        List<Map<String, Object>> optionList = new List<Map<String, Object>>();
        if (!coverageLevelNames.isEmpty()) {
            for (Coverage_Level__c covLevel : [SELECT Id, Name FROM Coverage_Level__c WHERE Name IN :coverageLevelNames ORDER BY Name ASC]) {
                optionList.add(new Map<String, Object>{ 'name' => covLevel.Id, 'value' => covLevel.Name });
            }
        }
        output.put('options', optionList);
    }

    /**
     * 2. Extracts dependent options directly from the active Pricing Decision Matrix rows
     */
    private void getMatrixDependentOptions(Map<String, Object> input, Map<String, Object> output, String targetColumn) {
        String rateSet = (String) input.get('Rate_Set');
        
        // Get the current UI Step node values
        Map<String, Object> stepNode = (Map<String, Object>) input.get('ReRateFieldsForNotSecureOneProducts');
        if (stepNode == null) return;
        
        String coverageId = (String) stepNode.get('Coverage_Name_NonSecureOne');
        String selectedMonths = (String) stepNode.get('Term_Months_NonSecureOne');
        String selectedMiles = (String) stepNode.get('Term_Miles_NonSecureOne');

        if (String.isBlank(rateSet) || String.isBlank(coverageId)) return;

        // Resolve Coverage ID to Name
        List<Coverage_Level__c> covLevels = [SELECT Name FROM Coverage_Level__c WHERE Id = :coverageId LIMIT 1];
        if (covLevels.isEmpty()) return;
        String coverageName = covLevels[0].Name;

        // Generate matrix name following established BRE mapping patterns
        String matrixName = generateMatrixName(rateSet, coverageName);

        Datetime saleDate = input.get('Sale_Date') != null ? Datetime.valueOf(String.valueOf(input.get('Sale_Date')) + ' 00:00:00') : Datetime.now();
        Datetime effectiveDate = BREServiceHandlerBulkified.getEffectiveStartDate(matrixName, UtilityClass.BR_TYPE_DM, saleDate);

        // Fetch Active Matrix Version
        List<CalculationMatrixVersion> activeVersions = [
            SELECT Id FROM CalculationMatrixVersion 
            WHERE IsEnabled = true AND StartDateTime <= :effectiveDate AND CalculationMatrix.Name = :matrixName 
            ORDER BY StartDateTime DESC LIMIT 1
        ];

        if (activeVersions.isEmpty()) return;

        // Fetch rows to find valid combinations
        List<CalculationMatrixRow> matrixRows = [SELECT InputData FROM CalculationMatrixRow WHERE CalculationMatrixVersionId = :activeVersions[0].Id];
        Set<String> distinctValues = new Set<String>();
        
        for (CalculationMatrixRow row : matrixRows) {
            if (String.isNotBlank(row.InputData)) {
                Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(row.InputData);
                
                if (!rowData.containsKey('CoverageName') || String.valueOf(rowData.get('CoverageName')) != coverageName) continue;
                
                // Dependency Filtering
                if (targetColumn == 'TermMiles' && String.isNotBlank(selectedMonths)) {
                    if (rowData.containsKey('TermMonths') && String.valueOf(rowData.get('TermMonths')) != selectedMonths) continue;
                }
                if (targetColumn == 'Deductible') {
                    if (String.isNotBlank(selectedMonths) && rowData.containsKey('TermMonths') && String.valueOf(rowData.get('TermMonths')) != selectedMonths) continue;
                    if (String.isNotBlank(selectedMiles) && rowData.containsKey('TermMiles') && String.valueOf(rowData.get('TermMiles')) != selectedMiles) continue;
                }

                if (rowData.containsKey(targetColumn) && rowData.get(targetColumn) != null) {
                    distinctValues.add(String.valueOf(rowData.get(targetColumn)));
                }
            }
        }
        
        List<Map<String, String>> options = new List<Map<String, String>>();
        List<String> sortedList = new List<String>(distinctValues);
        sortedList.sort(); 
        for (String val : sortedList) {
            options.add(new Map<String, String>{ 'name' => val, 'value' => val });
        }
        output.put('options', options);
    }

    private String generateMatrixName(String rateSet, String coverageName) {
        String combined = rateSet + '_' + coverageName;
        combined = combined.replaceAll(' - ', '_').replaceAll('-', '_').replaceAll(' ', '_').replaceAll('\\(', '').replaceAll('\\)', '').replaceAll('\\.', '_');
        combined = combined.replaceAll('_+', '_'); 
        
        if (combined.equalsIgnoreCase('Health_CAR_23_31_79_Health_CAR')) return 'Health_CAR_Health_CAR';
        if (combined.equalsIgnoreCase('Health_CAR_23_31_79_Health_CAR_Validation')) return 'Health_CAR_Health_CAR_Validation';
        if (rateSet == 'MBI - Amtrust (CA)') combined = combined.replaceAll('MBI_Amtrust', 'MBI_AmTrust');
        
        return combined;
    }
}