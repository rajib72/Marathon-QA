/**
 * REST Resource class for executing quote request for Rate Implementation Builder API
 * This class exposes a POST endpoint to quote request for Rate Implementation Builder API
 * and returns a processed response.
 */
@RestResource(UrlMapping='/RateImplementationBuilder/*')
global class RateBuilderAPI {
    
    public static Map<String, Map<String,String>> responseMap = new Map<String, Map<String,String>>();
    public static Map<String, String> requestDataMap = new Map<String,String>();
    public static Set<String> classGuideValues = new Set<String>();   
    public static Boolean isCountRequired = false;
    public static Integer offSet = 0;
    
    @HttpPost
    global static String processRateImplementation() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        RateBuilderAPI.RateRequest requestObj;
        
        String responseStr = '';
        
        try {
            // Deserialize request body to QuoteService.EnduranceRequest object
            requestObj  = (RateBuilderAPI.RateRequest) JSON.deserialize( request.requestBody.toString(), RateBuilderAPI.RateRequest.class);
            isCountRequired = request.params.containsKey('isCountRequired') ? Boolean.valueOf(request.params.get('isCountRequired')) : false;
            offSet = request.params.containsKey('offSet') ? Integer.valueOf(request.params.get('offSet')) : 0;
            responseStr = setup(requestObj);
        } catch (Exception e) {
            //log error
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
            generateErrorResponse(e.getMessage());
            
        } finally {
            // Ensure logs are published regardless of success or failure
            QDX_LOG.publish();
        }
        return responseStr;
    }
    
    //generates error response
    public static String generateErrorResponse(String errorMessage) {
        RateBuilderAPI.ErrorResponseGenerator errorResponseObj = new RateBuilderAPI.ErrorResponseGenerator();
        RateBuilderAPI.ErrorPayload errorPayload = new RateBuilderAPI.ErrorPayload();
        
        errorResponseObj.status = 400;
        errorResponseObj.error = errorMessage;
        errorResponseObj.payload = errorPayload;
        return JSON.serialize(errorResponseObj);
    }
    
    /**
    * the main setup methods that invokes child methods to populate response map
    */
    public static String setup(RateBuilderAPI.RateRequest requestObj) {
        String response = '';
        //popuate vehicleMap global variable
        requestDataMap.put('Client', requestObj.Client);
        requestDataMap.put('Product', requestObj.Product);
        requestDataMap.put('CoverageLevel', requestObj.CoverageLevel);
        requestDataMap.put('RequestType', requestObj.RequestType);
        requestDataMap.put('State', requestObj.State != null ? requestObj.State : '');
        requestDataMap.put('InsuranceCarrier', requestObj.InsuranceCarrier != null ? requestObj.InsuranceCarrier : '');
        
        //call DM methods to populate responseMap global variable
        if(requestObj != NULL && requestObj.RequestType == 'Dealer Cost Rates') {
            dealerCodeLookup(requestDataMap);
            response = rateSetsDMCall();
        } else if(requestObj != NULL && requestObj.RequestType == 'Rate Options') {
            dealerCodeLookup(requestDataMap);
            response = optionSetsDMCall();
        } else if(requestObj != NULL && requestObj.RequestType == 'Rate Surcharges') {
            dealerCodeLookup(requestDataMap);
            response = surchargeSetsDMCall();
        } else if(requestObj != NULL && requestObj.RequestType == 'State Eligibility') {
            dealerCodeLookup(requestDataMap);
            response = stateSetsDMCall();
        } else if(requestObj != NULL && requestObj.RequestType == 'Dealer Cost Breakout') {
            dealerCodeLookup(requestDataMap);
            response = dealerCostBreakoutRateSetsDMCall();
        } else if(requestObj != NULL && requestObj.RequestType == 'Squish VIN Class Guide') {
            dealerCodeLookup(requestDataMap);
            response = squishVINClassGuideCall();
        }
        return response;
    }
    
    /**
    * queries dealer code lookup DM and populates responseMap
    */
    public static Void dealerCodeLookup(Map<String, String> requestDataMap) {
        List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>([SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM CalculationMatrix WHERE UniqueName = 'Dealer_Code_Lookup']);
        
        for(CalculationMatrixRow row : [SELECT Id, Name, InputData, OutputData FROM CalculationMatrixRow where CalculationMatrixVersionId =: dealerLookupRec[0].CalculationMatrixVersions[0].Id]) {
            Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(row.OutputData);
            Map<String, String> columntoData = new Map<String, String>();
            if(rowData != null && requestDataMap != NULL) {
                if(String.valueOf(rowData.get('Client')) == requestDataMap.get('Client') && 
                    String.valueOf(rowData.get('Product')) == requestDataMap.get('Product') && (requestDataMap.get('CoverageLevel') == null ||
                    (requestDataMap.get('CoverageLevel') != null && requestDataMap.get('CoverageLevel').split(';').contains(String.valueOf(rowData.get('CoverageLevel')))))) {
                    Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(row.InputData);
                    
                    if(requestDataMap.get('RequestType') == 'Dealer Cost Rates') {
                        columntoData.put('CoverageLevel', String.valueOf(rowData.get('CoverageLevel')));
                        columntoData.put('Product', String.valueOf(rowData.get('Product'))); 
                        columntoData.put('Client', String.valueOf(rowData.get('Client')));
                        columntoData.put('RateSet', String.valueOf(rowData.get('RateSet')));
                        
                        responseMap.put(String.valueOf(rowInputData.get('DealerProgramId')), columntoData);
                    } else if(requestDataMap.get('RequestType') == 'Rate Options') {
                        columntoData.put('CoverageLevel', String.valueOf(rowData.get('CoverageLevel')));
                        columntoData.put('OptionSets', String.valueOf(rowData.get('OptionSets')));
                            
                        responseMap.put(String.valueOf(rowInputData.get('DealerProgramId')), columntoData);
                        
                    } else if(requestDataMap.get('RequestType') == 'Rate Surcharges') {
                        columntoData.put('CoverageLevel', String.valueOf(rowData.get('CoverageLevel')));
                        columntoData.put('SurchargeSets', String.valueOf(rowData.get('SurchargeSets')));
                        
                        responseMap.put(String.valueOf(rowInputData.get('DealerProgramId')), columntoData);
                        
                    } else if(requestDataMap.get('RequestType') == 'State Eligibility') {
                        columntoData.put('StateSet', String.valueOf(rowData.get('StateSet')));
                        columntoData.put('Product', String.valueOf(rowData.get('Product'))); 
                        columntoData.put('Client', String.valueOf(rowData.get('Client')));
                        
                        responseMap.put(String.valueOf(rowInputData.get('DealerProgramId')), columntoData);
                    } else if(requestDataMap.get('RequestType') == 'Dealer Cost Breakout') {
                        columntoData.put('CoverageLevel', String.valueOf(rowData.get('CoverageLevel')));
                        columntoData.put('RateSet', String.valueOf(rowData.get('RateSet')));
                        columntoData.put('Client', String.valueOf(rowData.get('Client')));
                        columntoData.put('Product', String.valueOf(rowData.get('Product')));
                        
                        responseMap.put(String.valueOf(rowInputData.get('DealerProgramId')), columntoData);
                    } else if(requestDataMap.get('RequestType') == 'Squish VIN Class Guide') {
                        columntoData.put('ClassGuide', String.valueOf(rowData.get('ClassGuide')));
                        
                        responseMap.put(String.valueOf(rowInputData.get('DealerProgramId')), columntoData);
                    }
                }
            }
        }
    }
    
    /**
     * queries metadata records and returns particular record
     */
    public static DecisionMatrixMapping__mdt fetchMetadatabyTableName(String tableName, String coverageLevel) {
        DecisionMatrixMapping__mdt obj = new DecisionMatrixMapping__mdt();
        for(DecisionMatrixMapping__mdt metadataObj : DecisionMatrixMapping__mdt.getAll().values()) {
            if(metadataObj.Table_Name__c == tableName) {
                if(String.isEmpty(coverageLevel) && metadataObj.Coverage_Level__c == NULL) {
                    obj =  metadataObj;
                }
                if(!String.isEmpty(coverageLevel) && metadataObj.Coverage_Level__c == coverageLevel) {
                    obj =  metadataObj;
                }
            }
        }
        return obj;
    }
    
    /**
     * queries rate set DM records and returns concated response
     */
    public static String rateSetsDMCall() {
        Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
        Set<String> uniqueValues = new Set<String>();
        Map<String, List<Allocation_Code__c>> allocationCodesMap = new Map<String, List<Allocation_Code__c>>();
        Map<String, String> valueMap;
        Map<String, String> dealerCodesMap = new Map<String, String>();
        if(!responseMap.isEmpty()) {
            for(String key : responseMap.keySet()) {
                valueMap = responseMap.get(key);
                for(String rateSet : valueMap.keySet()) {
                    String client = valueMap.get('Client');
                    String product = valueMap.get('Product');
                    String coverageLevel = valueMap.get('CoverageLevel');
                    String matrixName = fetchMetadatabyTableName(valueMap.get('RateSet'), valueMap.get('CoverageLevel')).Decision_Matrix_Name__c;
                    uniqueValues.add(matrixName);
                    dealerCodeDetailsMap.put(valueMap.get('CoverageLevel') + matrixName, key);
                    String uniqueKey = client + '#' + product + '#' + coverageLevel;
                    dealerCodesMap.put(key, uniqueKey);
                }
            }
        }
        String state = '\'' + String.escapeSingleQuotes(requestDataMap.get('State')) + '\'';
        if(!state.contains('Include All')) {
            state += ',\'' + 'Include All' + '\'';
        }
        String insCarrier = '\'' + String.escapeSingleQuotes(requestDataMap.get('InsuranceCarrier')) + '\'';
        if(!insCarrier.contains('Include All')) {
            insCarrier += ',\'' + 'Include All' + '\'';
        }
        String query = 'SELECT Name, Client__r.Name, Coverage_Level__c, Descriptor__c, Allocation_Amount__c, Product__c, Option__c, Term_Months__c ' +
                   'FROM Allocation_Code__c ' +
                   'WHERE Client__r.Name = \'' + String.escapeSingleQuotes(valueMap.get('Client')) + '\' ' + 
                   'AND Coverage_Level__c = \'' + String.escapeSingleQuotes(valueMap.get('CoverageLevel')) + '\' ' + 
                   'AND Product__c = \'' + String.escapeSingleQuotes(valueMap.get('Product')) + '\' ' + 
                   'AND States__c INCLUDES (' + state + ') ' + 
                   'AND Insurance_Carrier__c INCLUDES (' + insCarrier + ') ' + 
                   'AND Descriptor__c != \'Reserve\' ' +
                   'AND Start_Date__c <= TODAY ' +
                   'AND (End_Date__c = NULL OR End_Date__c >= TODAY) AND Descriptor__c <> NULL';
        for(Allocation_Code__c allocCode : Database.query(query)) {
            String key = allocCode.Client__r.Name + '#' + allocCode.Product__c + '#' + allocCode.Coverage_Level__c;
            if(allocationCodesMap.containsKey(key.toUpperCase())) {
                allocationCodesMap.get(key.toUpperCase()).add(allocCode);
            } else {
                allocationCodesMap.put(key.toUpperCase(), new List<Allocation_Code__c>{allocCode});
            }
        }
        String concatedString = '';
        List<String>concatedStringList = new list<String>();
        Map<String, String> versionIdtoMatrixName = new Map<String, String>();
        if(!dealerCodeDetailsMap.isEmpty()) {
            for(CalculationMatrix matrix : [SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM
                CalculationMatrix WHERE UniqueName IN : uniqueValues]) {
                versionIdtoMatrixName.put(matrix.CalculationMatrixVersions[0].Id, matrix.UniqueName);
            }
            if(!versionIdtoMatrixName.isEmpty()) {
                Set<String> versionIds = versionIdtoMatrixName.keySet();
                List<sObject> sObjectRows = (List<sObject>) Database.query('SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds');
                List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
                String dealerProgId, rateSet, coverageName, uptoAddOn, termMonths, termMiles, minMiles, maxMiles, minAge, maxAge, rateClass, rateCost, deductible, rateCode;
                for(CalculationMatrixRow matrixRecord : rows) {
                    Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                    Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                    if(rowData != null && rowInputData != null) {
                        dealerProgId = dealerCodeDetailsMap.get(String.valueOf(rowInputData.get('CoverageName')) + versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId));
                        rateSet = responseMap.get(dealerProgId).get('RateSet');
                        coverageName = String.valueOf(rowInputData?.get('CoverageName'));
                        uptoAddOn = String.valueOf(rowInputData?.get('ExpireType'));
                        termMonths = String.valueOf(rowInputData?.get('TermMonths'));
                        termMiles = String.valueOf(rowInputData?.get('TermMiles'));
                        minMiles = String.valueOf(rowInputData?.get('MinMiles'));
                        maxMiles = String.valueOf(rowData?.get('MaxMiles'));
                        minAge = String.valueOf(rowInputData?.get('MinAge'));
                        maxAge = String.valueOf(rowData?.get('MaxAge'));
                        rateClass = String.valueOf(rowInputData?.get('RateClass'));
                        rateCost = String.valueOf(rowData?.get('BaseReserve'));
                        deductible = String.valueOf(rowInputData?.get('Deductible'));
                        rateCode = String.valueOf(rowData?.get('RateCode'));
                        
                        Double allocationAmountperDealerRec = 0.00;
                        if(dealerCodesMap.containsKey(dealerProgId)) { 
                            String mapKey = dealerCodesMap.get(dealerProgId).toUpperCase();
                            if(allocationCodesMap.containsKey(mapKey)) {
                                for(Allocation_Code__c ac : allocationCodesMap.get(mapKey)) {
                                    if(ac.Term_Months__c != null && ac.Term_Months__c.equalsIgnoreCase('Include All') || termMonths == ac.Term_Months__c) {
                                        if (Pattern.matches('\\d+(\\.\\d+)?', ac.Allocation_Amount__c) || ac.Allocation_Amount__c.isNumeric()) {
                                            if(Double.valueOf(ac.Allocation_Amount__c) > 0 && ac.Option__c.equalsIgnoreCase('Include All')) {
                                                allocationAmountperDealerRec += Double.valueOf(ac.Allocation_Amount__c);
                                            } 
                                        } else {
                                            if(ac.Descriptor__c == 'Premium Tax') {
                                                allocationAmountperDealerRec += Double.valueOf(rowData?.get('PremiumTax'));
                                            }
                                            if(ac.Descriptor__c == 'Seller Commission') {
                                                allocationAmountperDealerRec += Double.valueOf(rowData?.get('Commission'));
                                            }
                                        }
                                    }
                                }
                            }
                            mapKey = '';
                        }
                        Double totalRateCost = Double.valueOf(rateCost) + allocationAmountperDealerRec;
                        concatedString = dealerProgId + '#' + coverageName + '#' + rateSet + '#' + uptoAddOn + '#' + termMonths + '#' + termMiles + '#' + minMiles + '#' + maxMiles + '#' + minAge + '#' + maxAge + '#' + rateClass + '#' + totalRateCost + '#' + deductible + '#' + rateCode;
                        concatedStringList.add(concatedString);
                    }
                }
            }
        }
        
        return String.join(concatedStringList, ',');
    }
    
    
    
    /**
     * queries rate set DM records and returns concated response
     */
    public static String dealerCostBreakoutRateSetsDMCall() {
        Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
        Set<String> uniqueValues = new Set<String>();
        Map<String, List<Allocation_Code__c>> allocationCodesMap = new Map<String, List<Allocation_Code__c>>();
        Map<String, String> dealerCodesMap = new Map<String, String>();
        Boolean isPremiumTax = false;
        Double premiumTaxValue = 0.00;
        if(!responseMap.isEmpty()) {
            String client = '', product = '', coverageLevel = '';
            for(String key : responseMap.keySet()) {
                Map<String, String> valueMap = responseMap.get(key);
                client = valueMap.get('Client');
                product = valueMap.get('Product');
                coverageLevel = valueMap.get('CoverageLevel');
                String matrixName = fetchMetadatabyTableName(valueMap.get('RateSet'), valueMap.get('CoverageLevel')).Decision_Matrix_Name__c;
                
                uniqueValues.add(matrixName);
                dealerCodeDetailsMap.put(valueMap.get('CoverageLevel') + matrixName, key);
                String uniqueKey = client + '#' + product + '#' + coverageLevel;
                dealerCodesMap.put(key, uniqueKey);
            }
            String state = '\'' + String.escapeSingleQuotes(requestDataMap.get('State')) + '\'';
            if(!state.contains('Include All')) {
                state += ',\'' + 'Include All' + '\'';
            }
            String insCarrier = '\'' + String.escapeSingleQuotes(requestDataMap.get('InsuranceCarrier')) + '\'';
            if(!insCarrier.contains('Include All')) {
                insCarrier += ',\'' + 'Include All' + '\'';
            }
            String query = 'SELECT Name, Client__r.Name, Coverage_Level__c, Descriptor__c, Allocation_Amount__c, Product__c, Option__c, Term_Months__c ' +
                       'FROM Allocation_Code__c ' +
                       'WHERE Client__r.Name = \'' + String.escapeSingleQuotes(client) + '\' ' + 
                       'AND Coverage_Level__c = \'' + String.escapeSingleQuotes(coverageLevel) + '\' ' + 
                       'AND Product__c = \'' + String.escapeSingleQuotes(product) + '\' ' + 
                       'AND States__c INCLUDES (' + state + ') ' + 
                       'AND Insurance_Carrier__c INCLUDES (' + insCarrier + ') ' + 
                       'AND Descriptor__c != \'Reserve\' ' +
                       'AND Start_Date__c <= TODAY ' +
                       'AND (End_Date__c = NULL OR End_Date__c >= TODAY) AND Descriptor__c <> NULL';
            for(Allocation_Code__c allocCode : Database.query(query)) {
                String key = allocCode.Client__r.Name + '#' + allocCode.Product__c + '#' + allocCode.Coverage_Level__c;
                if(allocationCodesMap.containsKey(key.toUpperCase())) {
                    allocationCodesMap.get(key.toUpperCase()).add(allocCode);
                } else {
                    allocationCodesMap.put(key.toUpperCase(), new List<Allocation_Code__c>{allocCode});
                }
            }
        }
        String concatedString = '';
        List<String>concatedStringList = new list<String>();
        Map<String, String> versionIdtoMatrixName = new Map<String, String>();
        if(!dealerCodeDetailsMap.isEmpty()) {
            for(CalculationMatrix matrix : [SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM
                CalculationMatrix WHERE UniqueName IN : uniqueValues]) {
                versionIdtoMatrixName.put(matrix.CalculationMatrixVersions[0].Id, matrix.UniqueName);
            }
            uniqueValues.clear();
            if(!versionIdtoMatrixName.isEmpty()) {
                Set<String> versionIds = versionIdtoMatrixName.keySet();
                if(isCountRequired) {
                    String rowCount = String.valueOf(Database.countQuery('SELECT count() FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds'));
                    
                    return rowCount;
                }
                List<sObject> sObjectRows = (List<sObject>) Database.query('SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds LIMIT 200 OFFSET ' + offSet);
                List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
                String dealerProgId = '', rateSet = '', coverageName = '', uptoAddOn = '', termMonths = '', termMiles = '', minMiles = '', maxMiles = '', minAge = '', maxAge = '', rateClass = '', reserveRateCost = '', deductible = '', rateCode = '';
                for(CalculationMatrixRow matrixRecord : rows) {
                    Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                    Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                    String allocationCodeString = '';
                    if(rowData != null && rowInputData != null) {
                        dealerProgId = dealerCodeDetailsMap.get(String.valueOf(rowInputData.get('CoverageName')) + versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId));
                        rateSet = responseMap.get(dealerProgId).get('RateSet');
                        coverageName = String.valueOf(rowInputData?.get('CoverageName'));
                        uptoAddOn = String.valueOf(rowInputData?.get('ExpireType'));
                        termMonths = String.valueOf(rowInputData?.get('TermMonths'));
                        termMiles = String.valueOf(rowInputData?.get('TermMiles'));
                        minMiles = String.valueOf(rowInputData?.get('MinMiles'));
                        maxMiles = String.valueOf(rowData?.get('MaxMiles'));
                        minAge = String.valueOf(rowInputData?.get('MinAge'));
                        maxAge = String.valueOf(rowData?.get('MaxAge'));
                        rateClass = String.valueOf(rowInputData?.get('RateClass'));
                        deductible = String.valueOf(rowInputData?.get('Deductible'));
                        rateCode = String.valueOf(rowData?.get('RateCode'));
                        reserveRateCost = String.valueOf(rowData?.get('BaseReserve'));
                        
                        rowInputData.clear();
                        
                        Double allocationAmountperDealerRec = 0.00;
                        List<String> allocationDetails = new List<String>();
                        String allocationDetailsStr = '';
                        if(dealerCodesMap.containsKey(dealerProgId)) { 
                            String mapKey = dealerCodesMap.get(dealerProgId).toUpperCase();
                            if(allocationCodesMap.containsKey(mapKey)) {
                                for(Allocation_Code__c ac : allocationCodesMap.get(mapKey)) {
                                    if(ac.Term_Months__c != null && ac.Term_Months__c.equalsIgnoreCase('Include All') || termMonths == ac.Term_Months__c) {
                                        if (Pattern.matches('\\d+(\\.\\d+)?', ac.Allocation_Amount__c) || ac.Allocation_Amount__c.isNumeric()) {
                                            if(Double.valueOf(ac.Allocation_Amount__c) > 0 && ac.Option__c.equalsIgnoreCase('Include All')) {
                                                allocationDetails.add(ac.Name + ' = ' + Double.valueOf(ac.Allocation_Amount__c));
                                                allocationAmountperDealerRec += Double.valueOf(ac.Allocation_Amount__c);
                                            } else {
                                                allocationDetails.add(ac.Name + ' = ' + 0);
                                            }
                                        } else {
                                            if(ac.Descriptor__c == 'Premium Tax') {
                                                allocationDetails.add(ac.Name + ' = ' + Double.valueOf(rowData?.get('PremiumTax')));
                                                allocationAmountperDealerRec += Double.valueOf(rowData?.get('PremiumTax'));
                                            }
                                            if(ac.Descriptor__c == 'Seller Commission') {
                                                allocationDetails.add(ac.Name + ' = ' + Double.valueOf(rowData?.get('Commission')));
                                                allocationAmountperDealerRec += Double.valueOf(rowData?.get('Commission'));
                                            }
                                            if(ac.Descriptor__c == 'Obligor Fee') {
                                                allocationDetails.add(ac.Name + ' = ' + Double.valueOf(rowData?.get('Obligor')));
                                                allocationAmountperDealerRec += Double.valueOf(rowData?.get('Obligor'));
                                            }
                                        }
                                    }
                                }
                            }
                            mapKey = '';
                        }
                        Double totalRateCost = Double.valueOf(reserveRateCost) + allocationAmountperDealerRec;
                        allocationDetailsStr = String.join(allocationDetails, ';');
                        concatedString = dealerProgId + '#' + coverageName + '#' + rateSet + '#' + uptoAddOn + '#' + termMonths + '#' + termMiles + '#' + minMiles + '#' + maxMiles + '#' + minAge + '#' + maxAge + '#' + rateClass + '#' + deductible + '#' + rateCode + '#' + reserveRateCost + '#' + allocationDetailsStr + '#' + allocationAmountperDealerRec + '#' + totalRateCost;
                        concatedStringList.add(concatedString);
                    }
                }
                versionIds.clear();
                dealerCodeDetailsMap.clear();
                dealerCodesMap.clear();
                allocationCodesMap.clear();
                versionIdtoMatrixName.clear();
            }
        }
        return String.join(concatedStringList, ',');        
    }
    
    /**
    * queries Options Set lookup DM and returns concated response
    */
    public static String optionSetsDMCall() {
        Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
        Set<String> uniqueValues = new Set<String>();
        if(!responseMap.isEmpty()) {
            for(String key : responseMap.keySet()) {
                Map<String, String> valueMap = responseMap.get(key);
                for(String rateSet : valueMap.keySet()) {
                    String matrixName = fetchMetadatabyTableName(valueMap.get('OptionSets'), valueMap.get('CoverageLevel')).Decision_Matrix_Name__c;
                    uniqueValues.add(matrixName);
                    dealerCodeDetailsMap.put(valueMap.get('CoverageLevel') + matrixName, key);
                }
            }
        }
        
        List<String> responseToPentaho = new List<String>();
        String concatedString = '';
        Map<String, String> versionIdtoMatrixName = new Map<String, String>();
        if(!dealerCodeDetailsMap.isEmpty()) {
            for(CalculationMatrix matrixRecord : [SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM CalculationMatrix WHERE UniqueName IN : uniqueValues]) {
                versionIdtoMatrixName.put(matrixRecord.CalculationMatrixVersions[0].Id, matrixRecord.UniqueName);
            }
            if(!versionIdtoMatrixName.isEmpty()) {
                Set<String> versionIds = versionIdtoMatrixName.keySet();
                List<sObject> sObjectRows = (List<sObject>) Database.query('SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds');
                List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
                String dealerProgId, optionSet, coverageName, uptoAddOn, minTermMonths, maxTermMonths, minTermMiles, maxTermMiles, minVehicleAge, maxVehicleAge, minVehicleMiles, maxVehicleMiles, optionClass, optionCost, autoApply, allowCheck;
                for(CalculationMatrixRow matrixRecord : rows) {
                    Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                    Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                    if(rowData != null && rowInputData != null) {
                        dealerProgId = dealerCodeDetailsMap.get(String.valueOf(rowInputData.get('CoverageName')) + versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId));
                        optionSet = rowInputData.containsKey('OptionName') ? String.valueOf(rowInputData.get('OptionName')) : '';
                        coverageName = rowInputData.containsKey('CoverageName') ? String.valueOf(rowInputData.get('CoverageName')) : '';
                        uptoAddOn = rowInputData.containsKey('UpToAddOn') ? String.valueOf(rowInputData.get('UpToAddOn')) : '';
                        minTermMonths = rowInputData.containsKey('MinTermMonths') ? String.valueOf(rowInputData.get('MinTermMonths')) : '';
                        maxTermMonths = rowData.containsKey('MaxTermMonths') ? String.valueOf(rowData.get('MaxTermMonths')) : '';
                        minTermMiles = rowInputData.containsKey('MinTermMiles') ? String.valueOf(rowInputData.get('MinTermMiles')) : '';
                        maxTermMiles = rowData.containsKey('MaxTermMiles') ? String.valueOf(rowData.get('MaxTermMiles')) : '';
                        
                        minVehicleAge = rowInputData.containsKey('MinVehicleAge') ? String.valueOf(rowInputData.get('MinVehicleAge')) : '';
                        maxVehicleAge = rowData.containsKey('MaxVehicleAge') ? String.valueOf(rowData.get('MaxVehicleAge')) : '';
                        minVehicleMiles = rowInputData.containsKey('MinVehicleMiles') ? String.valueOf(rowInputData.get('MinVehicleMiles')) : '';
                        maxVehicleMiles = rowData.containsKey('MaxVehicleMiles') ? String.valueOf(rowData.get('MaxVehicleMiles')) : '';
                        optionClass = rowInputData.containsKey('RateClass') ? String.valueOf(rowInputData.get('RateClass')) : '';
                        optionCost = rowData.containsKey('OptionCost') ? String.valueOf(rowData.get('OptionCost')) : '0';
                        autoApply = rowData.containsKey('AutoApply') ? String.valueOf(rowData.get('AutoApply')) : 'FALSE';
                        allowCheck = 'TRUE';
                        if(rowData.containsKey('PremiumTax')) {
                            optionCost = String.valueOf(Decimal.valueOf(optionCost) + (Decimal) rowData.get('PremiumTax') + (Decimal) rowData.get('Obligor'));
                        }
                        if(rowData.containsKey('MaintenanceAdminFee')) {
                            optionCost = String.valueOf(Decimal.valueOf(optionCost) + (Decimal) rowData.get('MaintenanceAdminFee'));
                        }
                        concatedString += dealerProgId + '#' + coverageName + '#' + optionSet + '#' + optionCost + '#' + uptoAddOn + '#' + minTermMonths + '#' + maxTermMonths + '#' + minTermMiles + '#' + maxTermMiles + '#' + minVehicleMiles + '#' + maxVehicleMiles + '#' + minVehicleAge + '#' + maxVehicleAge + '#' + optionClass + '#' + autoApply + '#' + allowCheck + '#' + '' + '#' + '' + '#' + '' + '#' + '' + ',';
                    }
                }
            }
        }
        return concatedString.removeEnd(',');
        
    }
    
    /**
    * queries Surchage Set lookup DM and returns concated response
    */
    public static String surchargeSetsDMCall() {
        Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
        Set<String> uniqueValues = new Set<String>();
        if(!responseMap.isEmpty()) {
            for(String key : responseMap.keySet()) {
                Map<String, String> valueMap = responseMap.get(key);
                for(String rateSet : valueMap.keySet()) {
                    String matrixName = fetchMetadatabyTableName(valueMap.get('SurchargeSets'), valueMap.get('CoverageLevel')).Decision_Matrix_Name__c;
                    uniqueValues.add(matrixName);
                    dealerCodeDetailsMap.put(valueMap.get('CoverageLevel') + matrixName, key);
                }
            }
        }
        
        List<String> responseToPentaho = new List<String>();
        String concatedString = '';
        Map<String, String> versionIdtoMatrixName = new Map<String, String>();
        if(!dealerCodeDetailsMap.isEmpty()) {
            for(CalculationMatrix matrix : [SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM
                CalculationMatrix WHERE UniqueName IN : uniqueValues]) {
                versionIdtoMatrixName.put(matrix.CalculationMatrixVersions[0].Id, matrix.UniqueName);
            }
            if(!versionIdtoMatrixName.isEmpty()) {
                Map<String, String> extendedValues = new Map<String, String>();
                extendedValues.put('Extended Eligibility 5-12k', '5000#12000');
                extendedValues.put('Extended Eligibility 12-24k', '12000#24000');
                extendedValues.put('Extended Eligibility 24-35k', '24000#35000');
                extendedValues.put('Extended Eligibility 35-50k', '35000#50000');
                extendedValues.put('Extended Eligibility 50-70k', '50000#70000');
                extendedValues.put('Extended Eligibility 35-70k', '35000#70000');
            
                Set<String> versionIds = versionIdtoMatrixName.keySet();
                List<sObject> sObjectRows = (List<sObject>) Database.query('SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds');
                List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
                String dealerProgId, coverageName, surchargeSet, surchargeCost, uptoAddOn, minTermMonths, maxTermMonths, minTermMiles, maxTermMiles, minVehicleMiles, maxVehicleMiles, minVehicleAge, maxVehicleAge, rateClass, minVehicleCylinders, maxVehicleCylinders, trimNameContains, awd, fourWD, turbo, superCharger, dieSel, hybrid, gps, oneTon;
                if (rows != null && !rows.isEmpty()) {
                    for(CalculationMatrixRow matrixRecord : rows) {
                        Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                        Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                        if(rowData != null && rowInputData != null) {
                            dealerProgId = dealerCodeDetailsMap.get(String.valueOf(rowInputData.get('CoverageName')) + versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId));
                            coverageName = rowInputData.containsKey('CoverageName') ? String.valueOf(rowInputData.get('CoverageName')) : '';
                            surchargeSet = rowInputData.containsKey('SurchargeName') ? String.valueOf(rowInputData.get('SurchargeName')) : '';
                            surchargeCost = rowData.containsKey('SurchargeCost') ? String.valueOf(rowData.get('SurchargeCost')) : '';
                            uptoAddOn = rowInputData.containsKey('UpToAddOn') ? String.valueOf(rowInputData.get('UpToAddOn')) : '';
                            minTermMonths = rowInputData.containsKey('MinTermMonths') ? String.valueOf(rowInputData.get('MinTermMonths')) : '';
                            maxTermMonths = rowData.containsKey('MaxTermMonths') ? String.valueOf(rowData.get('MaxTermMonths')) : '';
                            minTermMiles = rowInputData.containsKey('MinTermMiles') ? String.valueOf(rowInputData.get('MinTermMiles')) : '';
                            maxTermMiles = rowData.containsKey('MaxTermMiles') ? String.valueOf(rowData.get('MaxTermMiles')) : '';
                            
                            if(surchargeSet != null && surchargeSet.contains('Extended Eligibility') && extendedValues.containsKey(surchargeSet)) {
                                minVehicleMiles = extendedValues.get(surchargeSet).split('#')[0];
                                maxVehicleMiles = extendedValues.get(surchargeSet).split('#')[1];
                            } else {
                                minVehicleMiles = rowInputData.containsKey('MinVehicleMiles') ? String.valueOf(rowInputData.get('MinVehicleMiles')) : '';
                                maxVehicleMiles = rowData.containsKey('MaxVehicleMiles') ? String.valueOf(rowData.get('MaxVehicleMiles')) : '';
                            }
                            
                            minVehicleAge = rowInputData.containsKey('MinVehicleAge') ? String.valueOf(rowInputData.get('MinVehicleAge')) : '';
                            maxVehicleAge = rowData.containsKey('MaxVehicleAge') ? String.valueOf(rowData.get('MaxVehicleAge')) : '';
                            rateClass = rowInputData.containsKey('RateClassList') ? String.valueOf(rowInputData.get('RateClassList')) : '';
                            
                            if(rowData.containsKey('PremiumTax')) {
                                surchargeCost = String.valueOf(Decimal.valueOf(surchargeCost) + (Decimal) rowData.get('PremiumTax'));
                            }
                            
                            minVehicleCylinders = '0';
                            maxVehicleCylinders = '999';
                            trimNameContains = '';
                            awd = (rowInputData.containsKey('SurchargeName') && String.valueOf(rowInputData.get('SurchargeName')) == 'AWD') ? 'TRUE' : '';
                            fourWD = (rowInputData.containsKey('SurchargeName') && String.valueOf(rowInputData.get('SurchargeName')) == 'FWD') ? 'TRUE' : '';
                            turbo = (rowInputData.containsKey('SurchargeName') && String.valueOf(rowInputData.get('SurchargeName')) == 'Turbo') ? 'TRUE' : '';
                            superCharger = (rowInputData.containsKey('SurchargeName') && String.valueOf(rowInputData.get('SurchargeName')) == 'SuperCharger') ? 'TRUE' : '';
                            dieSel = (rowInputData.containsKey('SurchargeName') && String.valueOf(rowInputData.get('SurchargeName')) == 'Diesel') ? 'TRUE' : '';
                            hybrid = '';
                            gps = '';
                            oneTon = (rowInputData.containsKey('SurchargeName') && String.valueOf(rowInputData.get('SurchargeName')) == '1 Ton') ? 'TRUE' : '';
                            
                            concatedString += dealerProgId + '#' + coverageName + '#' + surchargeSet + '#' + surchargeCost + '#' + uptoAddOn + '#' + minTermMonths + '#' + maxTermMonths + '#' + minTermMiles + '#' + maxTermMiles + '#' + minVehicleMiles + '#' + maxVehicleMiles + '#' + minVehicleAge + '#' + maxVehicleAge + '#' + rateClass + '#' + minVehicleCylinders + '#' + maxVehicleCylinders + '#' + trimNameContains + '#' + awd + '#' + fourWD + '#' + turbo + '#' + superCharger + '#' + dieSel + '#' + hybrid + '#' + gps + '#' + oneTon + '#' + '' + '#' + '' + '#' + '' + '#' + '' + '#' + '' + '#' + '' + '#' + '' + '#' + '' + '#' + '' + ',';
                        }
                    }                    
                }
            }
        }
        return concatedString.removeEnd(',');
        
    }
    
    /**
    * queries State Set lookup DM and returns concated response
    */
    public static String stateSetsDMCall() {
        List<CalculationMatrix> state_Set_GuideRec = new List<CalculationMatrix>([SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM CalculationMatrix WHERE UniqueName = 'State_Set_Guide']);
        Set<String> stateSetDMName = new Set<String>();
        String concatedString = '';
        Map<String, String> versionIdtoMatrixName = new Map<String, String>();
        // Instantiate HTTP request and response objects
        String responseBody = ContractUtility.fetchLookupTableRows(state_Set_GuideRec[0].Id, state_Set_GuideRec[0].CalculationMatrixVersions[0].Id);
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> rows = (List<Object>) jsonMap.get('rows');
        if (rows != null && !rows.isEmpty()) {
            Map<String, String> rowDataFieldsMap = new Map<String, String>();
            for(String key : responseMap.keySet()) {
                Map<String, String> valueMap = responseMap.get(key);
                for(Object data : rows) {
                    Map<String, Object> row = (Map<String, Object>) data;
                    Map<String, Object> rowData = (Map<String, Object>) row.get('rowData');
                    //creates a key value mapping that will be used to populate responseMap
                    if(String.valueOf(rowData.get('Client')) == valueMap.get('Client') && String.valueOf(rowData.get('Product')) == valueMap.get('Product')) {
                        String matrixName = fetchMetadatabyTableName(String.valueOf(rowData.get('StateSet')), '').Decision_Matrix_Name__c;
                        
                        stateSetDMName.add(matrixName);
                    }
                }
            }
            //queries state set DMs for each dealer code lookup record
            if(!stateSetDMName.isEmpty()) {
                for(CalculationMatrix matrix : [SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) FROM CalculationMatrix WHERE UniqueName IN : stateSetDMName]) {
                    versionIdtoMatrixName.put(matrix.CalculationMatrixVersions[0].Id, matrix.UniqueName);
                }
                if(!versionIdtoMatrixName.isEmpty()) {
                    // Instantiate HTTP request and response objects
                    Set<String> versionIds = versionIdtoMatrixName.keySet();
                    List<sObject> sObjectRows = (List<sObject>) Database.query('SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds');
                    List<CalculationMatrixRow> matrixRows = (List<CalculationMatrixRow>) (sObjectRows);
                    if(matrixRows != null && !matrixRows.isEmpty()) {
                        String stateProvince, stateProvName, insCarrier, obligor, adminCompany, typeOfInsurance;
                        for(CalculationMatrixRow matrixRecord : matrixRows) {
                            Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                            Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                            if(rowData != null && rowInputData != null) {
                                stateProvince = rowInputData.containsKey('State') ? String.valueOf(rowInputData.get('State')) : '';
                                stateProvName = getStateFullName(stateProvince);
                                insCarrier = rowData.containsKey('Carrier') ? String.valueOf(rowData.get('Carrier')) : '';
                                obligor = rowData.containsKey('Obligor') ? String.valueOf(rowData.get('Obligor')) : '';
                                adminCompany = rowData.containsKey('Admin') ? String.valueOf(rowData.get('Admin')) : '';
                                typeOfInsurance = rowData.containsKey('InsuranceType') ? String.valueOf(rowData.get('InsuranceType')) : '';
                                concatedString += 'United States' + '#' + stateProvince + '#' + stateProvName + '#' + insCarrier + '#' + obligor + '#' + adminCompany + '#' + typeOfInsurance + ',';
                            }
                        }
                    }
                }
            }
        }
        return concatedString.removeEnd(',');
        
    }
    
    /**
    * queries Options Set lookup DM and returns concated response
    */
    public static String squishVINClassGuideCall() {
        Set<String> classGuideValues = new Set<String>();
        if(!responseMap.isEmpty()) {
            for(String key : responseMap.keySet()) {
                Map<String, String> valueMap = responseMap.get(key);
                for(String rateSet : valueMap.keySet()) {
                    classGuideValues.add('\'' + valueMap.get('ClassGuide') + '\'');
                }
            }
        }
        return String.join(classGuideValues, ',');
        
    }
    
    /**
    * returns full US state name from abbreviated name
    */
    public static String getStateFullName(String shortName) {
        Map<String, String> stateMap = new Map<String, String>();
        stateMap.put('AL', 'Alabama');
        stateMap.put('AK', 'Alaska');
        stateMap.put('AR', 'Arkansas');
        stateMap.put('AZ', 'Arizona');
        stateMap.put('CA', 'California');
        stateMap.put('CO', 'Colorado');
        stateMap.put('CT', 'Connecticut');
        stateMap.put('DE', 'Delaware');
        stateMap.put('DC', 'District of Columbia');
        stateMap.put('FL', 'Florida');
        stateMap.put('GA', 'Georgia');
        stateMap.put('HI', 'Hawaii');
        stateMap.put('ID', 'Idaho');
        stateMap.put('IL', 'Illinois');
        stateMap.put('IN', 'Indiana');
        stateMap.put('IA', 'Iowa');
        stateMap.put('KS', 'Kansas');
        stateMap.put('KY', 'Kentucky');
        stateMap.put('LA', 'Louisiana');
        stateMap.put('ME', 'Maine');
        stateMap.put('MD', 'Maryland');
        stateMap.put('MA', 'Massachusetts');
        stateMap.put('MI', 'Michigan');
        stateMap.put('MN', 'Minnesota');
        stateMap.put('MS', 'Mississippi');
        stateMap.put('MO', 'Missouri');
        stateMap.put('MT', 'Montana');
        stateMap.put('NE', 'Nebraska');
        stateMap.put('NV', 'Nevada');
        stateMap.put('NH', 'New Hampshire');
        stateMap.put('NJ', 'New Jersey');
        stateMap.put('NM', 'New Mexico');
        stateMap.put('NY', 'New York');
        stateMap.put('NC', 'North Carolina');
        stateMap.put('ND', 'North Dakota');
        stateMap.put('OH', 'Ohio');
        stateMap.put('OK', 'Oklahoma');
        stateMap.put('OR', 'Oregon');
        stateMap.put('PA', 'Pennsylvania');
        stateMap.put('RI', 'Rhode Island');
        stateMap.put('SC', 'South Carolina');
        stateMap.put('SD', 'South Dakota');
        stateMap.put('TN', 'Tennessee');
        stateMap.put('TX', 'Texas');
        stateMap.put('UT', 'Utah');
        stateMap.put('VT', 'Vermont');
        stateMap.put('VA', 'Virginia');
        stateMap.put('WA', 'Washington');
        stateMap.put('WV', 'West Virginia');
        stateMap.put('WI', 'Wisconsin');
        stateMap.put('WY', 'Wyoming');
        
        return stateMap.containsKey(shortName) ? stateMap.get(shortName) : '';
    }
    
    //class that parses request body
    public class RateRequest {
        public String Client;
        public String Product;
        public String CoverageLevel;
        public String RequestType;
        public String State;
        public String InsuranceCarrier;
    }
    
    //class that generates error response
    public class ErrorResponseGenerator {
        public Integer status;
        public String error;
        public ErrorPayload payload;
    }
    
    //part of error response
    public class ErrorPayload {
        public String Client;
        public String Product;
        public String CoverageLevel;
        public String RequestType;
        public String State;
        public String InsuranceCarrier;
    }
    
    
}