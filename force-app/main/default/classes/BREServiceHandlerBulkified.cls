/**
* @description		 : Process the contracts in batches to bulkify the ingestion process
* @author            : Sohel Azmi
* @group             :
* @last modified on  : 06-12-2026
* @last modified by  : Sohel Azmi
**/
public class BREServiceHandlerBulkified {   
    public static Map<String, String> contractStateMap = new Map<String, String>();
    
    // ==========================================
    // CENTRAL DATA CACHES
    // ==========================================
    public static Map<Id, Account> accountCache = new Map<Id, Account>();
    public static Map<Id, Coverage_Level__c> covLevelCache = new Map<Id, Coverage_Level__c>();
    public static Map<String, String> squishVinCache = new Map<String, String>();
    public static Map<String, Map<String, Object>> globalVinDetails = new Map<String, Map<String, Object>>();
    public static Map<String, String> globalDriveTrainMapper = new Map<String, String>();

    // ==========================================
    // CHUNKING LOGIC & PIPELINE ENTRY
    // ==========================================
    public static List<InsurancePolicy> executeBusinessRule(List<InsurancePolicy> contracts) {
        // System.debug(LoggingLevel.ERROR, 'BRE PIPELINE START | Total Policies=' + contracts.size());
        
        List<InsurancePolicy> finalProcessed = new List<InsurancePolicy>();
        Integer chunkSize = 200;
        
        for (Integer i = 0; i < contracts.size(); i += chunkSize) {
            List<InsurancePolicy> chunk = new List<InsurancePolicy>();
            for (Integer j = i; j < Math.min(i + chunkSize, contracts.size()); j++) {
                chunk.add(contracts[j]);
            }
            
            // System.debug(LoggingLevel.ERROR, 'PROCESSING CHUNK: ' + ((i / chunkSize) + 1) + ' | Size: ' + chunk.size());
            processChunk(chunk);
            finalProcessed.addAll(chunk);
        }
        
        System.debug(LoggingLevel.ERROR, 'TOTAL CALLOUTS THIS TRANSACTION= ' + Limits.getCallouts());
        System.debug(LoggingLevel.ERROR, 'TOTAL SOQL THIS TRANSACTION= ' + Limits.getQueries());
        System.debug(LoggingLevel.ERROR, 'TOTAL HEAP SIZE THIS TRANSACTION= ' + Limits.getHeapSize());
        // System.debug(LoggingLevel.ERROR, 'BRE PIPELINE END');
        
        return finalProcessed;
    }

    private static void processChunk(List<InsurancePolicy> contracts) {

        for (InsurancePolicy contract : contracts) {
            if (contract.Options_Cost__c == null) contract.Options_Cost__c = 0;
            if (contract.Surcharge_Cost__c == null) contract.Surcharge_Cost__c = 0;
            if (contract.Premium_Tax_Old__c == null) contract.Premium_Tax_Old__c = 0;
            if (contract.OT_Allocation__c == null) contract.OT_Allocation__c = 0;
        }
        
        // System.debug(LoggingLevel.ERROR,'PRE-FETCHING BULK DATA CACHES');
        prefetchData(contracts);

        // System.debug(LoggingLevel.ERROR,'STAGE 1 populateOriginalState');
        populateOriginalState(contracts);
        
        // System.debug(LoggingLevel.ERROR, 'STAGE 2 populateInsuranceCode');
        populateInsuranceCode(contracts); 
        
        // System.debug(LoggingLevel.ERROR,'STAGE 3 retrieveDealerCodeData');
        retrieveDealerCodeData(contracts); 
        
        // System.debug(LoggingLevel.ERROR,'STAGE 4 calculateRateDetails');
        calculateRateDetails(contracts); 
        
        // System.debug(LoggingLevel.ERROR,'STAGE 5 populateStateInsuranceDetails');
        populateStateInsuranceDetails(contracts); 
        
        // System.debug(LoggingLevel.ERROR,'STAGE 6 populateRateSetDetails');
        populateRateSetDetails(contracts); 
        
        // System.debug(LoggingLevel.ERROR,'STAGE 7 populateOptionSetDetails');
        populateOptionSetDetails(contracts); 
        
        // System.debug(LoggingLevel.ERROR,'STAGE 8 populateSurchargeSetDetails');
        populateSurchargeSetDetails(contracts); 
    }
    
    // ==========================================
    // BULK DATA PRE-FETCH
    // ==========================================
    private static void prefetchData(List<InsurancePolicy> contracts) {
        Set<Id> accIds = new Set<Id>();
        Set<Id> covIds = new Set<Id>();
        List<String> vins = new List<String>();

        for (InsurancePolicy p : contracts) {
            if (p.Dealer__c != null) accIds.add(p.Dealer__c);
            if (p.NameInsuredId != null) accIds.add(p.NameInsuredId);
            if (p.Client__c != null) accIds.add(p.Client__c);
            if (p.Coverage_Level__c != null) covIds.add(p.Coverage_Level__c);
            if (p.VIN__c != null) vins.add(p.VIN__c);
        }

        if (!accIds.isEmpty()) {
            accountCache.putAll([SELECT Id, Name, AccountNumber, BillingState FROM Account WHERE Id IN :accIds]);
        }
        if (!covIds.isEmpty()) {
            covLevelCache.putAll([SELECT Id, Name FROM Coverage_Level__c WHERE Id IN :covIds]);
        }
        if (globalDriveTrainMapper.isEmpty()) {
            globalDriveTrainMapper = UtilityClass.getDriveTrainValue();
        }
        
        // THE FIX: Routing to VinUtilityTwo to resolve 200+ VINs in memory (1 SOQL)
        if (!vins.isEmpty()) {
            globalVinDetails = VinUtilityBulkified.getVinDetails(vins);
            squishVinCache.putAll(VinUtilityBulkified.resolveSquishVINsBulk(new Set<String>(vins)));
        }
    }

    // ==========================================
    // STAGE 1: populateOriginalState
    // ==========================================
    public static void populateOriginalState(List<InsurancePolicy> contracts) {
        try {
            Id recordTypeId = Schema.SObjectType.InsurancePolicy.getRecordTypeInfosByDeveloperName().get('Auto_Warranty').getRecordTypeId();
        
            for (InsurancePolicy contract : contracts) {
                if (contract.RecordTypeId == recordTypeId) {
                    String stateFromDealer = null;
                    String stateFromNamedInsured = null;
                    
                    if (contract.Dealer__c != null && accountCache.containsKey(contract.Dealer__c)) {
                        stateFromDealer = accountCache.get(contract.Dealer__c).BillingState;
                    }
                    if (contract.NameInsuredId != null && accountCache.containsKey(contract.NameInsuredId)) {
                        stateFromNamedInsured = accountCache.get(contract.NameInsuredId).BillingState;
                    }
                    
                    String finalState = String.isNotBlank(stateFromDealer) ? stateFromDealer : stateFromNamedInsured;
                    contractStateMap.put(contract.Name, finalState);
                } else {
                    contractStateMap.put(contract.Name, contract.State__c);
                }
            }
        } catch (Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 2: populateInsuranceCode
    // ==========================================
    public static void populateInsuranceCode(List<InsurancePolicy> contracts) {
        try {
            String brNameIC = 'Insurance_Codes';
            Map<Datetime, List<Map<String, Object>>> dmParamBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> dmContractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                Map<String, Object> parameter = new Map<String, Object>();
                String accountNumber = (contract.Client__c != null && accountCache.containsKey(contract.Client__c)) 
                    ? accountCache.get(contract.Client__c).AccountNumber : '';
                
                parameter.put('Client', accountNumber);
                parameter.put('State', contractStateMap.get(contract.Name));
                
                Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                Datetime bucketKey = getEffectiveStartDate(brNameIC, UtilityClass.BR_TYPE_DM, saleDate);
                
                if (bucketKey != null) {
                    if (!dmParamBatchesMap.containsKey(bucketKey)) {
                        dmParamBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                        dmContractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                    }
                    dmParamBatchesMap.get(bucketKey).add(parameter);
                    dmContractBatchesMap.get(bucketKey).add(contract);
                }
            }

            for (Datetime bucketKey : dmParamBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = dmParamBatchesMap.get(bucketKey);
                List<InsurancePolicy> contractBatch = dmContractBatchesMap.get(bucketKey);
                
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String dmResponse = runBRCallout(paramBatch, executionDate, brNameIC, UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL);

                if (String.isNotBlank(dmResponse)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(dmResponse);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                List<Object> resultsList = (List<Object>) outputRecord.get('results');
                                if (resultsList != null && !resultsList.isEmpty()) {
                                    for (Object resultObj : resultsList) {
                                        Map<String, Object> resultItem = (Map<String, Object>) resultObj;
                                        if (resultItem.containsKey('name') && resultItem.get('name') == 'InsuranceCode') {
                                            contract.Insurance_Code__c = (String) resultItem.get('value');
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 3: retrieveDealerCodeData
    // ==========================================
    public static void retrieveDealerCodeData(List<InsurancePolicy> contracts) {
        Set<String> coverageLevelSet = new Set<String>();
        Set<String> clientSet = new Set<String>();
        
        Map<String, String> coverageLevelMap = new Map<String, String>();
        Map<String, String> clientMap = new Map<String, String>();
        
        try {
            String brNameReins = 'Reinsurance_Company';
            String brNameDealer = 'Dealer_Code_Lookup';

            Map<Datetime, List<Map<String, Object>>> paramBatchesReins = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> contractBatchesReins = new Map<Datetime, List<InsurancePolicy>>();

            Map<Datetime, List<Map<String, Object>>> paramBatchesDealer = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> contractBatchesDealer = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                if (contract.Dealer_Program_Id__c != null) {
                    Map<String, Object> parameter = new Map<String, Object>();
                    parameter.put('DealerProgramId', Integer.valueOf(contract.Dealer_Program_Id__c));
                    
                    Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                    
                    Datetime bucketKeyReins = getEffectiveStartDate(brNameReins, UtilityClass.BR_TYPE_DM, saleDate);
                    if (bucketKeyReins != null) {
                        if (!paramBatchesReins.containsKey(bucketKeyReins)) {
                            paramBatchesReins.put(bucketKeyReins, new List<Map<String, Object>>());
                            contractBatchesReins.put(bucketKeyReins, new List<InsurancePolicy>());
                        }
                        paramBatchesReins.get(bucketKeyReins).add(parameter);
                        contractBatchesReins.get(bucketKeyReins).add(contract);
                    }

                    Datetime bucketKeyDealer = getEffectiveStartDate(brNameDealer, UtilityClass.BR_TYPE_DM, saleDate);
                    if (bucketKeyDealer != null) {
                        if (!paramBatchesDealer.containsKey(bucketKeyDealer)) {
                            paramBatchesDealer.put(bucketKeyDealer, new List<Map<String, Object>>());
                            contractBatchesDealer.put(bucketKeyDealer, new List<InsurancePolicy>());
                        }
                        paramBatchesDealer.get(bucketKeyDealer).add(parameter);
                        contractBatchesDealer.get(bucketKeyDealer).add(contract);
                    }
                }
            }

            // CALL 1: Reinsurance_Company Batches
            for (Datetime bucketKey : paramBatchesReins.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesReins.get(bucketKey);
                List<InsurancePolicy> contractBatch = contractBatchesReins.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String reinsJsonString = runBRCallout(paramBatch, executionDate, brNameReins, UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(reinsJsonString)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(reinsJsonString);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                List<Object> results = (List<Object>) outputRecord.get('results');
                                if (results != null) {
                                    for (Object resultObj : results) {
                                        Map<String, Object> result = (Map<String, Object>) resultObj;
                                        if (result.get('name') == 'ReinsuranceCompany') {
                                            contract.Reinsurance_Company__c = (String) result.get('value');
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // CALL 2: Dealer_Code_Lookup Batches
            for (Datetime bucketKey : paramBatchesDealer.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesDealer.get(bucketKey);
                List<InsurancePolicy> contractBatch = contractBatchesDealer.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String dealerJsonString = runBRCallout(paramBatch, executionDate, brNameDealer, UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(dealerJsonString)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(dealerJsonString);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                List<Object> results = (List<Object>) outputRecord.get('results');
                                if (results != null) {
                                    for (Object resultObj : results) {
                                        Map<String, Object> result = (Map<String, Object>) resultObj;
                                        String resultName = (String) result.get('name');
                                        String resultValue = (String) result.get('value');
                                        
                                        if (resultName == 'CoverageLevel') {
                                            coverageLevelSet.add(resultValue);
                                            coverageLevelMap.put(contract.Dealer_Program_Id__c, resultValue);
                                        }
                                        if (resultName == 'Product') contract.Product__c = resultValue;
                                        if (resultName == 'Client') {
                                            String unescapedClient = resultValue.unescapeHtml4();
                                            clientSet.add(unescapedClient);
                                            clientMap.put(contract.Dealer_Program_Id__c, unescapedClient);
                                        }
                                        if (resultName == 'RateSet') contract.Rate_Set__c = resultValue;
                                        if (resultName == 'OptionSets') contract.Options_Sets__c = resultValue;
                                        if (resultName == 'SurchargeSets') contract.Surcharge_Set__c = resultValue;
                                        if (resultName == 'ClassGuide') contract.Class_Guide__c = resultValue;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ADD NEWLY DISCOVERED LOOKUPS TO CENTRAL CACHE
            if (!coverageLevelSet.isEmpty()) {
                List<Coverage_Level__c> freshCovs = [SELECT Id, Name FROM Coverage_Level__c WHERE Name IN :coverageLevelSet];
                covLevelCache.putAll(freshCovs);
            }
            if (!clientSet.isEmpty()) {
                List<Account> freshAccs = [SELECT Id, Name, AccountNumber, BillingState FROM Account WHERE Name IN :clientSet];
                accountCache.putAll(freshAccs);
            }
            
            for (InsurancePolicy contractRecord : contracts) {
                if (contractRecord != null && contractRecord.Dealer_Program_Id__c != null) {
                    String dealerProgramId = contractRecord.Dealer_Program_Id__c;
                    
                    if (coverageLevelMap.containsKey(dealerProgramId)) {
                        for (Coverage_Level__c cvgLevel : covLevelCache.values()) {
                            if (cvgLevel.Name == coverageLevelMap.get(dealerProgramId)) {
                                contractRecord.Coverage_Level__c = cvgLevel.Id;
                                break;
                            }
                        }
                    }
                    if (clientMap.containsKey(dealerProgramId)) {
                        for (Account clientAcc : accountCache.values()) {
                            if (clientAcc.Name == clientMap.get(dealerProgramId)) {
                                contractRecord.Client__c = clientAcc.Id;
                                break;
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 4: calculateRateDetails
    // ==========================================
    public static void calculateRateDetails(List<InsurancePolicy> contracts) {
        try {
            // --- STAGE A: 'WLK_Rate' (Expression Set) ---
            String brNameWLK = 'WLK_Rate';

            Map<Datetime, List<Map<String, Object>>> paramBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> contractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                Map<String, Object> parameter = new Map<String, Object>();
                if (contract.Coverage_Level__c != null && covLevelCache.containsKey(contract.Coverage_Level__c)) {
                    parameter.put('Vehicle_Make', contract.Vehicle_Make__c);
                    parameter.put('Coverage_Name', covLevelCache.get(contract.Coverage_Level__c).Name);
                    parameter.put('Term_Miles', contract.Contract_Term_Mileage__c);
                    parameter.put('Term_Months', contract.Contract_Term_Months__c);
                    parameter.put('Sale_Mileage', contract.Vehicle_Mileage_at_Contract_Inception__c);
                    parameter.put('Vehicle_Type', contract.Vehicle_Type__c);
                    parameter.put('Is_Commercial', contract.Is_Commercial__c);
                    parameter.put('Billing_State', contractStateMap.get(contract.Name));
                }

                Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                Datetime bucketKey = getEffectiveStartDate(brNameWLK, UtilityClass.BR_TYPE_EX, saleDate);

                if (bucketKey != null) {
                    if (!paramBatchesMap.containsKey(bucketKey)) {
                        paramBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                        contractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                    }
                    paramBatchesMap.get(bucketKey).add(parameter);
                    contractBatchesMap.get(bucketKey).add(contract);
                }
            }

            for (Datetime bucketKey : paramBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesMap.get(bucketKey);
                List<InsurancePolicy> contractBatch = contractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String resultWLKRATE = runBRCallout(paramBatch, executionDate, brNameWLK, UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(resultWLKRATE)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(resultWLKRATE);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                Map<String, Object> results = (Map<String, Object>) outputRecord.get('results');
                                
                                if (results.containsKey('Option_Cost')) contract.Options_Cost__c = (Double) results.get('Option_Cost');
                                if (results.containsKey('Rate_Set')) contract.Rate_Set__c = (String) results.get('Rate_Set');
                                if (results.containsKey('Product')) contract.Product__c = (String) results.get('Product');
                                if (results.containsKey('Rate_Code')) contract.Rate_Code__c = (String) results.get('Rate_Code');
                                if (results.containsKey('Class_Guide')) contract.Class_Guide__c = (String) results.get('Class_Guide');
                                if (results.containsKey('Rate_Class')) contract.Class__c = (String) results.get('Rate_Class');
                                if (results.containsKey('Rate_Cost')) contract.Reserve__c = (Decimal) results.get('Rate_Cost');
                                if (results.containsKey('Expire_Type')) contract.Up_To_or_Add__c = (String) results.get('Expire_Type');
                                
                                if (contract.Product__c == 'SecureOne') {
                                    contract.DLRS_Total_Funded_Amount_from_Funding__c = contract.Net_Dealer_Cost__c;
                                    if (contract.SaleDate != null) {
                                        contract.Contract_Funded_Date__c = contract.SaleDate.date().addMonths(1);
                                        contract.Earliest_Contract_Funded_Date__c = contract.Contract_Funded_Date__c;
                                    }
                                }
                                
                                if (results.containsKey('Option')) contract.Option_1__c = (String) results.get('Option');
                                if (results.containsKey('Deductible')) contract.Deductible__c = (Double) results.get('Deductible');
                                if (results.containsKey('Max_Miles')) contract.MaxVehicleMilesOutput__c = (Double) results.get('Max_Miles');
                                // if (results.containsKey('Final_Total_Rate')) contract.Net_Dealer_Cost__c = (Double) results.get('Final_Total_Rate');
                                // START:: ADDED ON 01-09-26 BY SOHEL 
                                if (results.containsKey('Final_Total_Rate')) {
                                    Double finalRate = (Double) results.get('Final_Total_Rate');
                                    if (finalRate != null && finalRate > 0) {
                                        contract.Net_Dealer_Cost__c = finalRate;
                                    }
                                }
                                // END:: ADDED ON 01-09-26 BY SOHEL 
                            }
                        }
                    }
                }
            }

            // --- STAGE B: 'SecureOne_State_Matrix' (Decision Matrix) ---
            String brNameSOSM = 'SecureOne_State_Matrix';

            Map<Datetime, List<Map<String, Object>>> dmParamBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> dmContractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                Map<String, Object> parameter = new Map<String, Object>();
                parameter.put('StateSetName', contract.Product__c);
                parameter.put('StateProvince', contractStateMap.get(contract.Name));
                
                Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                Datetime bucketKey = getEffectiveStartDate(brNameSOSM, UtilityClass.BR_TYPE_DM, saleDate);
                
                if (bucketKey != null) {
                    if (!dmParamBatchesMap.containsKey(bucketKey)) {
                        dmParamBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                        dmContractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                    }
                    dmParamBatchesMap.get(bucketKey).add(parameter);
                    dmContractBatchesMap.get(bucketKey).add(contract);
                }
            }

            for (Datetime bucketKey : dmParamBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = dmParamBatchesMap.get(bucketKey);
                List<InsurancePolicy> contractBatch = dmContractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String secureOneStateMatrixResponse = runBRCallout(paramBatch, executionDate, brNameSOSM, UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(secureOneStateMatrixResponse)) {
                    Map<String, Object> jsonMapSOSM = (Map<String, Object>) JSON.deserializeUntyped(secureOneStateMatrixResponse);
                    List<Object> outputsSOSM = (List<Object>) jsonMapSOSM.get('outputs');
                    
                    if (outputsSOSM != null && outputsSOSM.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputsSOSM.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputsSOSM[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                List<Object> results = (List<Object>) outputRecord.get('results');
                                if (results != null) {
                                    for (Object resultObj : results) {
                                        Map<String, Object> result = (Map<String, Object>) resultObj;
                                        String resultName = (String) result.get('name');
                                        String resultValue = (String) result.get('value');
                                        
                                        if (resultName == 'InsuranceCarrier') contract.Ins_Carrier__c = resultValue;
                                        if (resultName == 'Obligor') contract.Obligor__c = resultValue;
                                        if (resultName == 'AdminCompany') contract.Admin__c = resultValue;
                                        if (resultName == 'TypeOfInsurance') contract.Ins_Type__c = resultValue;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 5: populateStateInsuranceDetails
    // ==========================================
    public static void populateStateInsuranceDetails(List<InsurancePolicy> contracts) {
        try {
            String brName = 'State_Insurance_Guide';
            Map<Datetime, List<Map<String, Object>>> paramBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> contractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                if (contract.Product__c != null && contract.Client__c != null && contract.Coverage_Level__c != null && 
                    contractStateMap.get(contract.Name) != null && accountCache.containsKey(contract.Client__c) && 
                    covLevelCache.containsKey(contract.Coverage_Level__c)) {
                    
                    Map<String, Object> parameter = new Map<String, Object>();
                    parameter.put('Product', contract.Product__c);
                    parameter.put('Client', accountCache.get(contract.Client__c).Name);
                    parameter.put('CoverageLevel', covLevelCache.get(contract.Coverage_Level__c).Name);
                    parameter.put('StateInput', contractStateMap.get(contract.Name));
                    parameter.put('ActiveInput', true);
                    
                    Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                    Datetime bucketKey = getEffectiveStartDate(brName, UtilityClass.BR_TYPE_EX, saleDate);
                    
                    if (bucketKey != null) {
                        if (!paramBatchesMap.containsKey(bucketKey)) {
                            paramBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                            contractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                        }
                        paramBatchesMap.get(bucketKey).add(parameter);
                        contractBatchesMap.get(bucketKey).add(contract);
                    }
                }
            }

            for (Datetime bucketKey : paramBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesMap.get(bucketKey);
                List<InsurancePolicy> contractBatch = contractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String response = runBRCallout(paramBatch, executionDate, brName, UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(response)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(response);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                Map<String, Object> results = (Map<String, Object>) outputRecord.get('results');
                                if (results.containsKey('CarrierOutput')) contract.Ins_Carrier__c = (String) results.get('CarrierOutput');
                                if (results.containsKey('ObligorOutput')) contract.Obligor__c = (String) results.get('ObligorOutput');
                                if (results.containsKey('AdminOutput')) contract.Admin__c = (String) results.get('AdminOutput');
                                if (results.containsKey('InsuranceTypeOutput')) contract.Ins_Type__c = (String) results.get('InsuranceTypeOutput');
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 6: populateRateSetDetails
    // ==========================================
    public static void populateRateSetDetails(List<InsurancePolicy> contracts) {
        try {
            String brName = 'Rate_Sets';
            Map<Datetime, List<Map<String, Object>>> paramBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> contractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                if (contract != null && contract.Rate_Set__c != null) {
                    if (contract.VIN__c != null) {
                        String vin = contract.VIN__c;
                        String squishVin = squishVinCache.get(vin);
                        
                        if (globalVinDetails != null && globalVinDetails.containsKey(squishVin)) {
                            if (globalVinDetails.get(squishVin).containsKey('mdl_yr__c') && String.valueOf(globalVinDetails.get(squishVin).get('mdl_yr__c')) != null) {
                                contract.Vehicle_Year__c = String.valueOf(globalVinDetails.get(squishVin).get('mdl_yr__c'));
                            }
                        }
                    }

                    Map<String, Object> parameter = new Map<String, Object>();
                    parameter.put('RateSetInput', contract.Rate_Set__c);
                    if (contract.Coverage_Level__c != null && covLevelCache.containsKey(contract.Coverage_Level__c)) {
                        parameter.put('CoverageNameInput', covLevelCache.get(contract.Coverage_Level__c).Name);
                    }
                    if (contract.Up_To_or_Add__c != null) parameter.put('ExpireTypeInput', contract.Up_To_or_Add__c.trim());
                    
                    parameter.put('TermMonthsInput', contract.Contract_Term_Months__c);
                    parameter.put('TermMilesInput', contract.Contract_Term_Mileage__c);
                    parameter.put('MinMilesInput', contract.Vehicle_Mileage_at_Contract_Inception__c);
                    
                    if (contract.Vehicle_Year__c != null && contract.SaleDate != null) {
                        parameter.put('MinAgeInput', contract.SaleDate.date().year() - Integer.valueOf(contract.Vehicle_Year__c));
                    } else {
                        parameter.put('MinAgeInput', 0);
                    }
                    
                    parameter.put('RateClassInput', contract.Class__c);
                    parameter.put('DeductibleInput', contract.Deductible__c);
                    parameter.put('ResidenceTypeInput', contract.Residential_Type__c == null ? '1' : contract.Residential_Type__c);
                    parameter.put('MinSquareFootInput', contract.Square_Foot__c == null ? 0 : contract.Square_Foot__c);
                    parameter.put('MinUnitInput', contract.Number_of_Units__c == null ? 0 : contract.Number_of_Units__c);
                    
                    Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                    Datetime bucketKey = getEffectiveStartDate(brName, UtilityClass.BR_TYPE_EX, saleDate);
                    
                    if (bucketKey != null) {
                        if (!paramBatchesMap.containsKey(bucketKey)) {
                            paramBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                            contractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                        }
                        paramBatchesMap.get(bucketKey).add(parameter);
                        contractBatchesMap.get(bucketKey).add(contract);
                    }
                }
            }

            for (Datetime bucketKey : paramBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesMap.get(bucketKey);
                List<InsurancePolicy> contractBatch = contractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = contractBatch[0].SaleDate != null ? contractBatch[0].SaleDate : Datetime.now();
                String jsonStringRateSets = runBRCallout(paramBatch, executionDate, brName, UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(jsonStringRateSets)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringRateSets);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == contractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = contractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                Map<String, Object> results = (Map<String, Object>) outputRecord.get('results');
                                if (results.containsKey('BaseReserveOutput')) contract.Reserve__c = (Decimal) results.get('BaseReserveOutput');
                                if (results.containsKey('RateCodeOutput')) contract.Rate_Code__c = (String) results.get('RateCodeOutput');
                                
                                if (results.containsKey('PremiumTaxOutput')) {
                                    if (contract.Premium_Tax_Old__c != null) contract.Premium_Tax_Old__c += (Decimal) results.get('PremiumTaxOutput');
                                    else contract.Premium_Tax_Old__c = (Decimal) results.get('PremiumTaxOutput');
                                }
                                if (results.containsKey('ObligorTaxOutput')) {
                                    if (contract.OT_Allocation__c != null) contract.OT_Allocation__c += (Decimal) results.get('ObligorTaxOutput');
                                    else contract.OT_Allocation__c = (Decimal) results.get('ObligorTaxOutput');
                                }
                                if (results.containsKey('CommissionOutput')) contract.MBI_Seller_Commission__c = (Decimal) results.get('CommissionOutput');
                                if (results.containsKey('MaxMilesOutput')) contract.MaxMilesOutput__c = (Decimal) results.get('MaxMilesOutput');
                                if (results.containsKey('MaxSquareFootOutput')) contract.MaxSquareFoot__c = (Decimal) results.get('MaxSquareFootOutput');
                                if (results.containsKey('MaxUnitOutput')) contract.MaxUnitOutput__c = (Decimal) results.get('MaxUnitOutput');
                                if (results.containsKey('MaxAgeOutput')) contract.MaxAge__c = (Decimal) results.get('MaxAgeOutput');
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 7: populateOptionSetDetails
    // ==========================================
    public static void populateOptionSetDetails(List<InsurancePolicy> contracts) {
        try {
            String brName = 'Options_Sets';

            Map<Datetime, List<Map<String, Object>>> paramBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> flatContractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                if (contract != null && contract.Rate_Set__c != null && contract.Option_1__c != null) {
                    List<String> optionList = contract.Option_1__c.split(';');
                    
                    if (!optionList.isEmpty() && contract.Options_Cost__c == null) contract.Options_Cost__c = 0;
                    
                    for (String OptionNameInput : optionList) {
                        if (String.isNotBlank(OptionNameInput)) {
                            Map<String, Object> parameter = new Map<String, Object>();
                            parameter.put('OptionsSetsInput', contract.Options_Sets__c);
                            if (contract.Coverage_Level__c != null && covLevelCache.containsKey(contract.Coverage_Level__c)) {
                                parameter.put('CoverageNameInput', covLevelCache.get(contract.Coverage_Level__c).Name);
                            }
                            
                            parameter.put('OptionNameInput', OptionNameInput);
                            parameter.put('MinTermMonthsInput', contract.Contract_Term_Months__c);
                            parameter.put('MinTermMilesInput', contract.Contract_Term_Mileage__c);
                            
                            if (contract.SaleDate != null && contract.Vehicle_Year__c != null) {
                                parameter.put('MinVehicleAgeInput', contract.SaleDate.date().year() - Integer.valueOf(contract.Vehicle_Year__c));
                            } else {
                                parameter.put('MinVehicleAgeInput', 0);
                            }
                            parameter.put('MinVehicleMiles', contract.Vehicle_Mileage_at_Contract_Inception__c);
                            
                            if (contract.Up_To_or_Add__c != null) parameter.put('UpToAddOnInput', contract.Up_To_or_Add__c.trim());
                            parameter.put('RateClassInput', contract.Class__c);
                            parameter.put('MinResidenceSqFtInput', contract.Square_Foot__c == null ? 0 : contract.Square_Foot__c);
                            
                            if (contract.Year_Built__c != null) {
                                parameter.put('MinResidenceAgeInput', System.Today().year() - Integer.valueOf(contract.Year_Built__c));
                            } else {
                                parameter.put('MinResidenceAgeInput', 0);
                            }
                            
                            Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                            Datetime bucketKey = getEffectiveStartDate(brName, UtilityClass.BR_TYPE_EX, saleDate);
                            
                            if (bucketKey != null) {
                                if (!paramBatchesMap.containsKey(bucketKey)) {
                                    paramBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                                    flatContractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                                }
                                paramBatchesMap.get(bucketKey).add(parameter);
                                flatContractBatchesMap.get(bucketKey).add(contract);
                            }
                        }
                    }
                }
            }

            for (Datetime bucketKey : paramBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesMap.get(bucketKey);
                List<InsurancePolicy> flatContractBatch = flatContractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Integer maxInputs = 200;
                
                for (Integer i = 0; i < paramBatch.size(); i += maxInputs) {
                    List<Map<String, Object>> subParamBatch = new List<Map<String, Object>>();
                    List<InsurancePolicy> subContractBatch = new List<InsurancePolicy>();
                    
                    Integer endIndex = Math.min(i + maxInputs, paramBatch.size());
                    for (Integer j = i; j < endIndex; j++) {
                        subParamBatch.add(paramBatch[j]);
                        subContractBatch.add(flatContractBatch[j]);
                    }
                    
                    Datetime executionDate = subContractBatch[0].SaleDate != null ? subContractBatch[0].SaleDate : Datetime.now();
                    String jsonStringOptionsSets = runBRCallout(subParamBatch, executionDate, brName, UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL);
                    
                    if (String.isNotBlank(jsonStringOptionsSets)) {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringOptionsSets);
                        List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                        
                        if (outputs != null && outputs.size() == subContractBatch.size()) {
                            for (Integer k = 0; k < outputs.size(); k++) {
                                Map<String, Object> outputRecord = (Map<String, Object>) outputs[k];
                                InsurancePolicy contract = subContractBatch[k]; // Extracting from the sub-chunk
                                
                                if (outputRecord.containsKey('results')) {
                                    Map<String, Object> results = (Map<String, Object>) outputRecord.get('results');
                                    
                                    if (results.containsKey('MaxTermMonthsOutput')) contract.MaxTermMonths__c = (Decimal) results.get('MaxTermMonthsOutput');
                                    if (results.containsKey('MaxTermMilesOutput')) contract.MaxMilesOutput__c = (Decimal) results.get('MaxTermMilesOutput');
                                    if (results.containsKey('MaxVehicleMilesOutput')) contract.MaxVehicleMilesOutput__c = (Decimal) results.get('MaxVehicleMilesOutput');
                                    if (results.containsKey('MaxVehicleAgeOutput') && (Decimal) results.get('MaxVehicleAgeOutput') > 0) {
                                        contract.MaxAge__c = (Decimal) results.get('MaxVehicleAgeOutput');
                                    }
                                    if (results.containsKey('MaxResidenceSqFtOutput')) contract.MaxSquareFoot__c = (Decimal) results.get('MaxResidenceSqFtOutput');
                                    if (results.containsKey('MaxResidenceAgeOutput') && (Decimal) results.get('MaxResidenceAgeOutput') > 0) {
                                        contract.MaxAge__c = (Decimal) results.get('MaxResidenceAgeOutput');
                                    }
                                    
                                    if (results.containsKey('PremiumTaxOutput')) {
                                        if (contract.Premium_Tax_Old__c != null) contract.Premium_Tax_Old__c += (Decimal) results.get('PremiumTaxOutput');
                                        else contract.Premium_Tax_Old__c = (Decimal) results.get('PremiumTaxOutput');
                                    }
                                    if (results.containsKey('ObligorTaxOutput')) {
                                        if (contract.OT_Allocation__c != null) contract.OT_Allocation__c += (Decimal) results.get('ObligorTaxOutput');
                                        else contract.OT_Allocation__c = (Decimal) results.get('ObligorTaxOutput');
                                    }
                                    if (results.containsKey('OptionCostOutput')) {
                                        contract.Options_Cost__c += (Decimal) results.get('OptionCostOutput');
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // STAGE 8: populateSurchargeSetDetails
    // ==========================================
    /* public static void populateSurchargeSetDetails(List<InsurancePolicy> contracts) {
        try {
            String brName = 'Surcharge_Sets';
            Map<Datetime, List<Map<String, Object>>> paramBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> flatContractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                String combinedSurcharges = '';
                
                if (contract.VIN__c != null && !globalVinDetails.isEmpty()) {
                    String vin = contract.VIN__c;
                    String squishVin = squishVinCache.get(vin);
                    
                    if (globalVinDetails.containsKey(squishVin)) {
                        if (globalVinDetails.get(squishVin).containsKey('mdl_yr__c') && String.valueOf(globalVinDetails.get(squishVin).get('mdl_yr__c')) != null) {
                            contract.Vehicle_Year__c = String.valueOf(globalVinDetails.get(squishVin).get('mdl_yr__c'));
                        }
                        if (globalVinDetails.get(squishVin).containsKey('mak_nm__c') && String.valueOf(globalVinDetails.get(squishVin).get('mak_nm__c')) != null) {
                            contract.Vehicle_Make__c = String.valueOf(globalVinDetails.get(squishVin).get('mak_nm__c'));
                        }
                        if (globalVinDetails.get(squishVin).containsKey('mdl_desc__c') && String.valueOf(globalVinDetails.get(squishVin).get('mdl_desc__c')) != null) {
                            contract.Vehicle_Model__c = String.valueOf(globalVinDetails.get(squishVin).get('mdl_desc__c'));
                        }
                        if (globalVinDetails.get(squishVin).containsKey('trk_tng_rat_cd__c') && globalVinDetails.get(squishVin).get('trk_tng_rat_cd__c') != null) {
                            String tonnageCode = String.valueOf(globalVinDetails.get(squishVin).get('trk_tng_rat_cd__c'));
                            if (tonnageCode == 'D' || tonnageCode == 'E' || tonnageCode == 'F') {
                                combinedSurcharges += '1 Ton;';
                                contract.is_OverOneTon__c = true;
                            } else {
                                contract.is_OverOneTon__c = false;
                            }
                        } else {
                            contract.is_OverOneTon__c = false;
                        }

                        if (globalVinDetails.get(squishVin).containsKey('eng_fuel_desc__c') && globalVinDetails.get(squishVin).get('eng_fuel_desc__c') == 'Diesel') {
                            combinedSurcharges += 'Diesel;';
                            contract.is_Diesel__c = true;
                        } else {
                            contract.is_Diesel__c = false;
                        }

                        if (globalVinDetails.get(squishVin).containsKey('eng_asp_trbl_chgr_cd__c') && globalVinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c') != null) {
                            if (Boolean.valueOf(globalVinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c'))) {
                                combinedSurcharges += 'Turbo;';
                                contract.is_Turbo__c = true;
                            } else {
                                contract.is_Turbo__c = false;
                            }
                        } else {
                            contract.is_Turbo__c = false;
                        }

                        if (globalVinDetails.get(squishVin).containsKey('drv_typ_cd__c')) {
                            String driveTrain = (String) globalVinDetails.get(squishVin).get('drv_typ_cd__c');
                            String driveTrainVal = globalDriveTrainMapper.get(driveTrain);
                            if (driveTrainVal == '4WD' || driveTrainVal == '4FD' || driveTrainVal == '4RD') {
                                combinedSurcharges += '4WD;';
                                contract.Drivetrain__c = '4WD';
                            }
                            if (driveTrainVal == '4AWD' || driveTrainVal == 'AWD') {
                                combinedSurcharges += 'AWD;';
                                contract.Drivetrain__c = 'AWD';
                            }
                        }
                        if (globalVinDetails.get(squishVin).containsKey('trim_desc__c') && globalVinDetails.get(squishVin).get('trim_desc__c') != null) {
                            contract.Trim__c = (String) globalVinDetails.get(squishVin).get('trim_desc__c');
                        }
                        if (globalVinDetails.get(squishVin).containsKey('eng_asp_sup_chgr_cd__c') && globalVinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c') != null) {
                            if (Boolean.valueOf(globalVinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c'))) {
                                combinedSurcharges += 'Supercharger;';
                                contract.is_Supercharged__c = true;
                            } else {
                                contract.is_Supercharged__c = false;
                            }
                        } else {
                            contract.is_Supercharged__c = false;
                        }

                        if (globalVinDetails.get(squishVin).containsKey('body_style_desc__c') && String.valueOf(globalVinDetails.get(squishVin).get('body_style_desc__c')) != null) {
                            contract.Body_Style__c = String.valueOf(globalVinDetails.get(squishVin).get('body_style_desc__c'));
                        }
                    }
                }
                
                if (contract.Vehicle_Mileage_at_Contract_Inception__c != null) {
                    if (contract.Vehicle_Mileage_at_Contract_Inception__c >= 5000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 12000) combinedSurcharges += 'Extended Eligibility 5-12k;';
                    if (contract.Vehicle_Mileage_at_Contract_Inception__c > 12000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 24000) combinedSurcharges += 'Extended Eligibility 12-24k;';
                    if (contract.Vehicle_Mileage_at_Contract_Inception__c > 24000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 35000) combinedSurcharges += 'Extended Eligibility 24-35k;';
                    if (contract.Vehicle_Mileage_at_Contract_Inception__c > 35000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 50000) combinedSurcharges += 'Extended Eligibility 35-50k;';
                    if (contract.Vehicle_Mileage_at_Contract_Inception__c > 50000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 70000) combinedSurcharges += 'Extended Eligibility 50-70k;';
                }
                if (contract.Product__c == 'Health CAR') combinedSurcharges += 'All Classes Surcharge;';
                if (!String.isEmpty(combinedSurcharges)) combinedSurcharges = combinedSurcharges.substring(0, combinedSurcharges.length()-1);
                if (combinedSurcharges != null) contract.Surcharges__c = combinedSurcharges;
                
                List<String> surcharges = String.isNotBlank(combinedSurcharges) ? combinedSurcharges.split(';') : new List<String>();
                if (!surcharges.isEmpty()) contract.Surcharge_Cost__c = 0;

                for (String surcharge : surcharges) {
                    if (String.isNotBlank(surcharge)) {
                        Map<String, Object> parameter = new Map<String, Object>();
                        parameter.put('SurchargeNameInput', surcharge);
                        if (contract.Coverage_Level__c != null && covLevelCache.containsKey(contract.Coverage_Level__c)) {
                            parameter.put('CoverageNameInput', covLevelCache.get(contract.Coverage_Level__c).Name);
                        }
                        parameter.put('MinTermMonthsInput', contract.Contract_Term_Months__c);
                        parameter.put('MinTermMilesInput', contract.Contract_Term_Mileage__c);
                        parameter.put('MinVehicleMilesInput', contract.Vehicle_Mileage_at_Contract_Inception__c);
                        
                        if (contract.Vehicle_Year__c != null && contract.SaleDate != null) {
                            parameter.put('MinVehicleAgeInput', contract.SaleDate.date().year() - Integer.valueOf(contract.Vehicle_Year__c));
                        }
                        parameter.put('RateClassListInput', contract.Class__c);
                        parameter.put('SurchargeSetsInput', contract.Surcharge_Set__c);
                        
                        Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                        Datetime bucketKey = getEffectiveStartDate(brName, UtilityClass.BR_TYPE_EX, saleDate);
                        
                        if (bucketKey != null) {
                            if (!paramBatchesMap.containsKey(bucketKey)) {
                                paramBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                                flatContractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                            }
                            paramBatchesMap.get(bucketKey).add(parameter);
                            flatContractBatchesMap.get(bucketKey).add(contract);
                        }
                    }
                }
            }

            for (Datetime bucketKey : paramBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesMap.get(bucketKey);
                List<InsurancePolicy> flatContractBatch = flatContractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                Datetime executionDate = flatContractBatch[0].SaleDate != null ? flatContractBatch[0].SaleDate : Datetime.now();
                String jsonStringSurchargeSets = runBRCallout(paramBatch, executionDate, brName, UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL);
                
                if (String.isNotBlank(jsonStringSurchargeSets)) {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringSurchargeSets);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    
                    if (outputs != null && outputs.size() == flatContractBatch.size()) {
                        for (Integer i = 0; i < outputs.size(); i++) {
                            Map<String, Object> outputRecord = (Map<String, Object>) outputs[i];
                            InsurancePolicy contract = flatContractBatch[i];
                            
                            if (outputRecord.containsKey('results')) {
                                Map<String, Object> results = (Map<String, Object>) outputRecord.get('results');
                                
                                if (results.containsKey('SurchargeCostOutput')) contract.Surcharge_Cost__c += (Decimal) results.get('SurchargeCostOutput');
                                if (results.containsKey('MaxTermMonthsOutput')) contract.MaxTermMonths__c = (Decimal) results.get('MaxTermMonthsOutput');
                                if (results.containsKey('MaxTermMilesOutput')) contract.MaxTermMilesOutput__c = (Decimal) results.get('MaxTermMilesOutput');
                                if (results.containsKey('MaxVehicleMilesOutput')) contract.MaxVehicleMilesOutput__c = (Decimal) results.get('MaxVehicleMilesOutput');
                                if (results.containsKey('MaxVehicleAgeOutput')) contract.MaxAge__c = (Decimal) results.get('MaxVehicleAgeOutput');
                                
                                if (results.containsKey('PremiumTaxOutput')) {
                                    if (contract.Premium_Tax_Old__c != null) contract.Premium_Tax_Old__c += (Decimal) results.get('PremiumTaxOutput');
                                    else contract.Premium_Tax_Old__c = (Decimal) results.get('PremiumTaxOutput');
                                }
                                if (results.containsKey('ObligorTaxOutput')) {
                                    if (contract.OT_Allocation__c != null) contract.OT_Allocation__c += (Decimal) results.get('ObligorTaxOutput');
                                    else contract.OT_Allocation__c = (Decimal) results.get('ObligorTaxOutput');
                                }
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    } */
    
    // ==========================================
    // STAGE 8: populateSurchargeSetDetails
    // ==========================================
    public static void populateSurchargeSetDetails(List<InsurancePolicy> contracts) {
        try {
            String brName = 'Surcharge_Sets';
            Map<Datetime, List<Map<String, Object>>> paramBatchesMap = new Map<Datetime, List<Map<String, Object>>>();
            Map<Datetime, List<InsurancePolicy>> flatContractBatchesMap = new Map<Datetime, List<InsurancePolicy>>();

            for (InsurancePolicy contract : contracts) {
                contract.is_OverOneTon__c = false;
                contract.is_Diesel__c = false;
                contract.is_Turbo__c = false;
                contract.is_Supercharged__c = false;

                String combinedSurcharges = '';
                
                if (contract.VIN__c != null && !globalVinDetails.isEmpty()) {
                    String squishVin = squishVinCache.get(contract.VIN__c);
                    
                    if (squishVin != null && globalVinDetails.containsKey(squishVin)) {
                        Map<String, Object> vDetails = globalVinDetails.get(squishVin);
                        
                        if(vDetails.containsKey('mdl_yr__c') && vDetails.get('mdl_yr__c') != null) contract.Vehicle_Year__c = String.valueOf(vDetails.get('mdl_yr__c'));
                        if(vDetails.containsKey('mak_nm__c') && vDetails.get('mak_nm__c') != null) contract.Vehicle_Make__c = String.valueOf(vDetails.get('mak_nm__c'));
                        if(vDetails.containsKey('mdl_desc__c') && vDetails.get('mdl_desc__c') != null) contract.Vehicle_Model__c = String.valueOf(vDetails.get('mdl_desc__c'));
                        
                        if(vDetails.containsKey('trk_tng_rat_cd__c') && vDetails.get('trk_tng_rat_cd__c') != null) {
                            String tonnageCode = String.valueOf(vDetails.get('trk_tng_rat_cd__c'));
                            if (tonnageCode == 'D' || tonnageCode == 'E' || tonnageCode == 'F') {
                                combinedSurcharges += '1 Ton;';
                                contract.is_OverOneTon__c = true;
                            }
                        }
                        if(vDetails.containsKey('eng_fuel_desc__c') && String.valueOf(vDetails.get('eng_fuel_desc__c')) == 'Diesel') {
                            combinedSurcharges += 'Diesel;';
                            contract.is_Diesel__c = true;
                        }
                        if(vDetails.containsKey('eng_asp_trbl_chgr_cd__c') && vDetails.get('eng_asp_trbl_chgr_cd__c') != null && Boolean.valueOf(String.valueOf(vDetails.get('eng_asp_trbl_chgr_cd__c')))) {
                            combinedSurcharges += 'Turbo;';
                            contract.is_Turbo__c = true;
                        }
                        if(vDetails.containsKey('drv_typ_cd__c') && vDetails.get('drv_typ_cd__c') != null) {
                            String driveTrainVal = globalDriveTrainMapper.get((String) vDetails.get('drv_typ_cd__c'));
                            if(driveTrainVal == '4WD' || driveTrainVal == '4FD' || driveTrainVal == '4RD') {
                                combinedSurcharges += '4WD;';
                                contract.Drivetrain__c = '4WD';
                            } else if(driveTrainVal == '4AWD' || driveTrainVal == 'AWD') {
                                combinedSurcharges += 'AWD;';
                                contract.Drivetrain__c = 'AWD';
                            }
                        }
                        if(vDetails.containsKey('trim_desc__c') && vDetails.get('trim_desc__c') != null) contract.Trim__c = String.valueOf(vDetails.get('trim_desc__c'));
                        
                        if(vDetails.containsKey('eng_asp_sup_chgr_cd__c') && vDetails.get('eng_asp_sup_chgr_cd__c') != null && Boolean.valueOf(String.valueOf(vDetails.get('eng_asp_sup_chgr_cd__c')))) {
                            combinedSurcharges += 'Supercharger;';
                            contract.is_Supercharged__c = true;
                        }
                        if(vDetails.containsKey('body_style_desc__c') && vDetails.get('body_style_desc__c') != null) contract.Body_Style__c = String.valueOf(vDetails.get('body_style_desc__c'));
                    }
                }
                
                // Restored Old Eligibility Logic Exactly
                if(contract.Vehicle_Mileage_at_Contract_Inception__c != null) {
                    Decimal m = contract.Vehicle_Mileage_at_Contract_Inception__c;
                    if(m >= 5000 && m <= 12000) combinedSurcharges += 'Extended Eligibility 5-12k;';
                    else if(m > 12000 && m <= 24000) combinedSurcharges += 'Extended Eligibility 12-24k;';
                    else if(m > 24000 && m <= 35000) combinedSurcharges += 'Extended Eligibility 24-35k;';
                    else if(m > 35000 && m <= 50000) combinedSurcharges += 'Extended Eligibility 35-50k;';
                    else if(m > 50000 && m <= 70000) combinedSurcharges += 'Extended Eligibility 50-70k;';
                }
                
                if(contract.Product__c == 'Health CAR') combinedSurcharges += 'All Classes Surcharge;';
                
                if(String.isNotBlank(combinedSurcharges)) {
                    combinedSurcharges = combinedSurcharges.substring(0, combinedSurcharges.length() - 1); 
                    contract.Surcharges__c = combinedSurcharges;
                    
                    List<String> surcharges = combinedSurcharges.split(';');
                    for(String surcharge : surcharges) {
                        if(String.isNotBlank(surcharge)){
                            Map<String, Object> parameter = new Map<String, Object>();
                            parameter.put('SurchargeNameInput', surcharge);
                            if(contract.Coverage_Level__c != null && covLevelCache.containsKey(contract.Coverage_Level__c)) {
                                parameter.put('CoverageNameInput', covLevelCache.get(contract.Coverage_Level__c).Name);
                            }
                            parameter.put('MinTermMonthsInput', contract.Contract_Term_Months__c);
                            parameter.put('MinTermMilesInput', contract.Contract_Term_Mileage__c);
                            parameter.put('MinVehicleMilesInput', contract.Vehicle_Mileage_at_Contract_Inception__c);
                            
                            if(contract.Vehicle_Year__c != null && contract.SaleDate != null && contract.Vehicle_Year__c != 'null'){
                                parameter.put('MinVehicleAgeInput', contract.SaleDate.date().year() - Integer.valueOf(contract.Vehicle_Year__c));
                            }
                            parameter.put('RateClassListInput', contract.Class__c);
                            parameter.put('SurchargeSetsInput', contract.Surcharge_Set__c);
                            
                            Datetime saleDate = contract.SaleDate != null ? contract.SaleDate : Datetime.now();
                            Datetime bucketKey = getEffectiveStartDate(brName, UtilityClass.BR_TYPE_EX, saleDate);
                            
                            if (bucketKey != null) {
                                if (!paramBatchesMap.containsKey(bucketKey)) {
                                    paramBatchesMap.put(bucketKey, new List<Map<String, Object>>());
                                    flatContractBatchesMap.put(bucketKey, new List<InsurancePolicy>());
                                }
                                paramBatchesMap.get(bucketKey).add(parameter);
                                flatContractBatchesMap.get(bucketKey).add(contract);
                            }
                        }
                    }
                }
            }

            Integer maxInputs = 200;

            for (Datetime bucketKey : paramBatchesMap.keySet()) {
                List<Map<String, Object>> paramBatch = paramBatchesMap.get(bucketKey);
                List<InsurancePolicy> flatContractBatch = flatContractBatchesMap.get(bucketKey);
                if (paramBatch.isEmpty()) continue;

                for (Integer i = 0; i < paramBatch.size(); i += maxInputs) {
                    List<Map<String, Object>> subParamBatch = new List<Map<String, Object>>();
                    List<InsurancePolicy> subContractBatch = new List<InsurancePolicy>();
                    
                    Integer endIndex = Math.min(i + maxInputs, paramBatch.size());
                    for (Integer j = i; j < endIndex; j++) {
                        subParamBatch.add(paramBatch[j]);
                        subContractBatch.add(flatContractBatch[j]);
                    }
                    
                    Datetime executionDate = subContractBatch[0].SaleDate != null ? subContractBatch[0].SaleDate : Datetime.now();
                    String jsonStringSurchargeSets = runBRCallout(subParamBatch, executionDate, brName, UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL);
                    
                    if (String.isNotBlank(jsonStringSurchargeSets)) {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringSurchargeSets);
                        List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                        
                        if (outputs != null && outputs.size() == subContractBatch.size()) {
                            for (Integer k = 0; k < outputs.size(); k++) {
                                Map<String, Object> outputRecord = (Map<String, Object>) outputs[k];
                                InsurancePolicy contract = subContractBatch[k];
                                
                                if (outputRecord.containsKey('results')) {
                                    Map<String, Object> results = (Map<String, Object>) outputRecord.get('results');
                                    
                                    if (results.containsKey('SurchargeCostOutput')) {
                                        Decimal cost = (Decimal) results.get('SurchargeCostOutput');
                                        contract.Surcharge_Cost__c = (contract.Surcharge_Cost__c == null) ? cost : contract.Surcharge_Cost__c + cost;
                                    }
                                    if (results.containsKey('MaxTermMonthsOutput')) contract.MaxTermMonths__c = (Decimal) results.get('MaxTermMonthsOutput');
                                    if (results.containsKey('MaxTermMilesOutput')) contract.MaxTermMilesOutput__c = (Decimal) results.get('MaxTermMilesOutput');
                                    if (results.containsKey('MaxVehicleMilesOutput')) contract.MaxVehicleMilesOutput__c = (Decimal) results.get('MaxVehicleMilesOutput');
                                    if (results.containsKey('MaxVehicleAgeOutput')) contract.MaxAge__c = (Decimal) results.get('MaxVehicleAgeOutput');
                                    
                                    if (results.containsKey('PremiumTaxOutput')) {
                                        Decimal tax = (Decimal) results.get('PremiumTaxOutput');
                                        contract.Premium_Tax_Old__c = (contract.Premium_Tax_Old__c != null) ? contract.Premium_Tax_Old__c + tax : tax;
                                    }
                                    if (results.containsKey('ObligorTaxOutput')) {
                                        Decimal tax = (Decimal) results.get('ObligorTaxOutput');
                                        contract.OT_Allocation__c = (contract.OT_Allocation__c != null) ? contract.OT_Allocation__c + tax : tax;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Error populateSurchargeSetDetails: '+e.getMessage()+' Line: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }

    // ==========================================
    // HELPER METHODS
    // ==========================================
    
    public class VersionCache {
        public Datetime startDate;
        public Datetime endDate;
        public VersionCache(Datetime startDate, Datetime endDate) {
            this.startDate = startDate;
            this.endDate = endDate;
        }
    }
    
    public static Map<String, List<VersionCache>> brVersionCache = new Map<String, List<VersionCache>>();

    public static Datetime getEffectiveStartDate(String brName, String brType, Datetime saleDate) {
        Datetime targetDate = saleDate != null ? saleDate : Datetime.now();
        
        if (!brVersionCache.containsKey(brName)) {
            List<VersionCache> versions = new List<VersionCache>();
            
            try {
                String query = '';
                if (brType == UtilityClass.BR_TYPE_DM) {
                    query = 'SELECT StartDateTime, EndDateTime FROM CalculationMatrixVersion WHERE IsEnabled = true AND CalculationMatrixId IN (SELECT Id FROM CalculationMatrix WHERE Name = :brName) ORDER BY StartDateTime DESC';
                } else if (brType == UtilityClass.BR_TYPE_EX) {
                    query = 'SELECT StartDateTime, EndDateTime FROM ExpressionSetVersion WHERE IsActive = true AND ExpressionSetId IN (SELECT Id FROM ExpressionSet WHERE Name = :brName) ORDER BY StartDateTime DESC';
                }
                
                if (String.isNotBlank(query)) {
                    for (SObject sObj : Database.query(query)) {
                        versions.add(new VersionCache((Datetime)sObj.get('StartDateTime'), (Datetime)sObj.get('EndDateTime')));
                    }
                }
            } catch (Exception e) {
                QDX_LOG.error('Failed to query versions for BR ' + brName + ': ' + e.getMessage());
            }
            
            brVersionCache.put(brName, versions);
        }

        for (VersionCache vc : brVersionCache.get(brName)) {
            if (targetDate >= vc.startDate && (vc.endDate == null || targetDate <= vc.endDate)) {
                return vc.startDate; 
            }
        }
        
        return targetDate; 
    }

    public static String runBRCallout(List<Map<String, Object>> parameters, Datetime effectiveDate, String brName, String brType, String typeOfCall) {
        if (parameters == null || parameters.isEmpty()) return null; 

        Map<String, Object> jsonRequest = new Map<String, Object>();
        List<Map<String, Object>> inputsArray = new List<Map<String, Object>>();
        String endpointUrl;
        
        if (brType == UtilityClass.BR_TYPE_DM) {
            inputsArray = buildDecisionMatricesInputs(parameters);
        } else if (brType == UtilityClass.BR_TYPE_EX) {
            inputsArray = buildExpressionSetInputs(parameters);
        }
        
        jsonRequest.put('inputs', inputsArray);
        
        Map<String, Object> options = new Map<String, Object>();
        options.put('useDatesOnly', true);
        options.put('effectiveDate', effectiveDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''));
        jsonRequest.put('options', options);
        
        if (typeOfCall == UtilityClass.IS_EXTERNAL_CALL) {
            endpointUrl = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v62.0/connect/business-rules/' + brType + '/' + brName;
        } else {
            endpointUrl = 'callout:SF_OMNI_API/services/data/v62.0/connect/business-rules/' + brType + '/' + brName;
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(jsonRequest));
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatus() == 'Created' || res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            return res.getBody();
        }
        
        System.debug(LoggingLevel.ERROR, 'BRE CALLOUT FAILED: ' + res.getBody());
        return null;
    }

    private static List<Map<String, Object>> buildDecisionMatricesInputs(List<Map<String, Object>> parameters) {
        List<Map<String, Object>> inputsArray = new List<Map<String, Object>>();
        for (Map<String, Object> paramMap : parameters) {
            Map<String, Object> inputGroup = new Map<String, Object>();
            List<Map<String, Object>> inputList = new List<Map<String, Object>>();
            
            for (String key : paramMap.keySet()) {
                Map<String, Object> input = new Map<String, Object>();
                input.put('name', key);
                input.put('value', paramMap.get(key));
                inputList.add(input);
            }
            inputGroup.put('input', inputList);
            inputsArray.add(inputGroup);
        }
        return inputsArray;
    }

    private static List<Map<String, Object>> buildExpressionSetInputs(List<Map<String, Object>> parameters) {
        return parameters;
    }
}