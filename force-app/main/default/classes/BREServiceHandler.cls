/**
* @description       :
* @author            : ChangeMeIn@UserSettingsUnder.SFDoc
* @group             :
* @last modified on  : 06-27-2025
* @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public class BREServiceHandler {
    public static Map<String, String> contractStateMap = new Map<String, String>();
    /**
* @method executeBusinessRule
* @description Orchestrates the execution of various business rules for a list of insurance policies.
* @param contracts List of insurance policy records to process.
*/
    public static List<InsurancePolicy> executeBusinessRule(List<InsurancePolicy> contracts) {
        //system.debug('INSIDE BRE SERVICE HANDLER');
        contractStateMap.clear();

        for(InsurancePolicy con : contracts){
        con.Premium_Tax_Old__c = 0;
        con.OT_Allocation__c = 0;
        con.Options_Cost__c = 0;
        con.Surcharge_Cost__c = 0;
    }
        System.debug(LoggingLevel.ERROR,
                     'BRE PIPELINE START | Policies=' + contracts.size());
        
        Integer beforeCalls;
        Integer afterCalls;
        
        // ---------------- Stage 1 ----------------
        System.debug('STAGE 1 populateOriginalState');
        beforeCalls = Limits.getCallouts();
        
        populateOriginalState(contracts);
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED populateOriginalState=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 2 ----------------
        System.debug('STAGE 2 populateInsuranceCode');
        beforeCalls = Limits.getCallouts();
        
        populateInsuranceCode(contracts); //1st
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED populateInsuranceCode=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 3 ----------------
        System.debug('STAGE 3 retrieveDealerCodeData');
        beforeCalls = Limits.getCallouts();
        
        retrieveDealerCodeData(contracts); //2nd
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED retrieveDealerCodeData=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 4 ----------------
        System.debug('STAGE 4 calculateRateDetails');
        beforeCalls = Limits.getCallouts();
        
        calculateRateDetails(contracts); //3rd
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED calculateRateDetails=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 5 ----------------
        System.debug('STAGE 5 populateStateInsuranceDetails');
        beforeCalls = Limits.getCallouts();
        
        populateStateInsuranceDetails(contracts); //4th
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED populateStateInsuranceDetails=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 6 ----------------
        System.debug('STAGE 6 populateRateSetDetails');
        beforeCalls = Limits.getCallouts();
        
        populateRateSetDetails(contracts); //5th
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED populateRateSetDetails=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 7 ----------------
        System.debug('STAGE 7 populateOptionSetDetails');
        beforeCalls = Limits.getCallouts();
        
        populateOptionSetDetails(contracts); //6th
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED populateOptionSetDetails=' +
                     (afterCalls-beforeCalls));
        
        
        // ---------------- Stage 8 ----------------
        System.debug('STAGE 8 populateSurchargeSetDetails');
        beforeCalls = Limits.getCallouts();
        
        populateSurchargeSetDetails(contracts); //7th
        
        afterCalls = Limits.getCallouts();
        System.debug('CALLS USED populateSurchargeSetDetails=' +
                     (afterCalls-beforeCalls));
        
        
        System.debug(
            LoggingLevel.ERROR,
            'TOTAL CALLOUTS THIS TRANSACTION=' +
            Limits.getCallouts()
        );
        
        System.debug(
            LoggingLevel.ERROR,
            'BRE PIPELINE END'
        );
        
        return contracts;
    }
    
    public static void populateInsuranceCode(List<InsurancePolicy> contracts) {
        //System.debug('Inside populate insurance code'+contracts);
        String brType;
        
        try{
            Map<Id, Account> accountIdMap = new Map<Id, Account> ();
            Set<Id> accountIdSet = new Set<Id> ();
            for(InsurancePolicy contractRecord: contracts){
                if(contractRecord.Client__c != NULL){
                    accountIdSet.add(contractRecord.Client__c);
                }
            }
            if(accountIdSet != NULL && !accountIdSet.isEmpty()){
                accountIdMap = new Map<Id, Account>([Select Id, AccountNumber from Account WHERE ID IN  : accountIdSet]);
            }
            for(InsurancePolicy contractRecord: contracts) {
                Map<String, Object> parameter = new Map<String, Object>();
                List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                parameter.put('Client', (contractRecord.Client__c != null && accountIdMap.containsKey(contractRecord.Client__c)) ? accountIdMap.get(contractRecord.Client__c).AccountNumber : '');
                parameter.put('State', contractStateMap.get(contractRecord.Name));
                parameters.add(parameter);
                String response = BREManager.runBRCallout(parameters,contractRecord.SaleDate.date(),'Insurance_Codes', UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','populateInsuranceCode', contractRecord.Name);
                if(response != null && response != '') {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(response);
                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                    if (outputs != null && !outputs.isEmpty()) {
                        Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                        if (firstOutput != null && firstOutput.containsKey('results')) {
                            List<Object> results = (List<Object>) firstOutput.get('results');
                            if (results != null && !results.isEmpty()) {
                                for (Object resultObj : results) {
                                    Map<String, Object> result = (Map<String, Object>) resultObj;
                                    if (result.containsKey('name') && result.get('name').equals('InsuranceCode')) {
                                        contractRecord.Insurance_Code__c = (String) result.get('value');
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void calculateRateDetails(List<InsurancePolicy> contracts) {
        String brType;
        
        try {
            Map<Id, Account> accountIdMap = new Map<Id, Account> ();
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            Set<Id> accountIdSet = new Set<Id> ();
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            for(InsurancePolicy contractRecord: contracts){
                if(contractRecord.NameInsuredId != NULL){
                    accountIdSet.add(contractRecord.NameInsuredId);
                }
                if(contractRecord.Coverage_Level__c !=null){
                    coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                }
            }
            if(accountIdSet != NULL && !accountIdSet.isEmpty()){
                accountIdMap = new Map<Id, Account>([Select Id, AccountNumber, BillingState from Account WHERE ID IN  : accountIdSet]);
            }
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            for(InsurancePolicy contract: contracts) {
                Map<String, Object> parameter = new Map<String, Object>();
                List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                if (contract.Coverage_Level__c != NULL){
                    parameter.put('Vehicle_Make', contract.Vehicle_Make__c);
                    parameter.put('Coverage_Name',coverageLevelMap.get(contract.Coverage_Level__c ).Name);
                    parameter.put('Term_Miles', contract.Contract_Term_Mileage__c);
                    parameter.put('Term_Months', contract.Contract_Term_Months__c);
                    parameter.put('Sale_Mileage', contract.Vehicle_Mileage_at_Contract_Inception__c);
                    //parameter.put('Option_1', contract.Option_1__c);
                    parameter.put('Vehicle_Type', contract.Vehicle_Type__c);
                    //parameter.put('Expiry_Type', contract.Up_To_or_Add__c);
                    parameter.put('Is_Commercial', contract.Is_Commercial__c);
                    parameter.put('Billing_State', contractStateMap.get(contract.Name));
                    parameters.add(parameter);
                    String resultWLKRATE = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'WLK_Rate', UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','calculateRateDetails', contract.Name);
                    if(resultWLKRATE != null && resultWLKRATE != '') {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(resultWLKRATE);
                        List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                        if (outputs != null && !outputs.isEmpty()) {
                            Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                            if (firstOutput != null && firstOutput.containsKey('results')) {
                                Map<String, Object> results = (Map<String, Object>) firstOutput.get('results');
                                if(results.containsKey('Option_Cost')){
                                    contract.Options_Cost__c = (double) results.get('Option_Cost');
                                }
                                if(results.containsKey('Rate_Set')){
                                    contract.Rate_Set__c = (String) results.get('Rate_Set');
                                }
                                if(results.containsKey('Product')){
                                    contract.Product__c = (String) results.get('Product');
                                }
                                if(results.containsKey('Rate_Code')){
                                    contract.Rate_Code__c = (String) results.get('Rate_Code');
                                }
                                if(results.containsKey('Class_Guide')){
                                    contract.Class_Guide__c = (String) results.get('Class_Guide');
                                }
                                if(results.containsKey('Rate_Class')){
                                    contract.Class__c = (String) results.get('Rate_Class');
                                }
                                if(results.containsKey('Rate_Cost')){
                                    contract.Reserve__c =(Decimal) results.get('Rate_Cost');
                                }
                                if(results.containsKey('Expire_Type')){
                                    contract.Up_To_or_Add__c = (String) results.get('Expire_Type');
                                }
                                if (contract.Product__c == 'SecureOne') {
                                    contract.DLRS_Total_Funded_Amount_from_Funding__c = contract.Net_Dealer_Cost__c;
                                    //contract.Contract_Funded_Date__c = System.today().addMonths(1);
                                    if(contract.SaleDate != null){
                                        contract.Contract_Funded_Date__c = contract.SaleDate.date().addMonths(1);
                                        //------Start-Earliest Contract Funded Date for Westlake 12/03/2026.-------------------------
                                        contract.Earliest_Contract_Funded_Date__c = contract.Contract_Funded_Date__c;
                                        //------End-Earliest Contract Funded Date for Westlake 12/03/2026.---------------------------
                                    }
                                    
                                }
                                if(results.containsKey('Option')){
                                    contract.Option_1__c = (String) results.get('Option');
                                }
                                if(results.containsKey('Deductible')){
                                    contract.Deductible__c = (double) results.get('Deductible');
                                }
                                if(results.containsKey('Max_Miles')){
                                    contract.MaxVehicleMilesOutput__c = (double) results.get('Max_Miles');
                                }
                                
                                contract.Net_Dealer_Cost__c = (double) results.get('Final_Total_Rate');
                            }
                        }
                    }
                }
                parameter.put('StateSetName', contract.Product__c );
                parameter.put('StateProvince', contractStateMap.get(contract.Name));
                parameters.add(parameter);
                String secureOneStateMatrixResponse = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'SecureOne_State_Matrix',UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','calculateRateDetails', contract.Name);
                if(secureOneStateMatrixResponse!=null && secureOneStateMatrixResponse!=''){
                    Map<String, Object> jsonMapSOSM = (Map<String, Object>) JSON.deserializeUntyped(secureOneStateMatrixResponse);
                    List<Object> outputsSOSM = (List<Object>) jsonMapSOSM.get('outputs');
                    if (outputsSOSM != null && !outputsSOSM.isEmpty()) {
                        Map<String, Object> firstOutput = (Map<String, Object>) outputsSOSM.get(0);
                        if (firstOutput != null && firstOutput.containsKey('results')) {
                            List<Object> results = (List<Object>) firstOutput.get('results');
                            if (results != null && !results.isEmpty()) {
                                for (Object resultObj : results) {
                                    Map<String, Object> result = (Map<String, Object>) resultObj;
                                    if(result.containsKey('name') && result.get('name').equals('InsuranceCarrier')){
                                        contract.Ins_Carrier__c = (String) result.get('value');
                                    }
                                    if(result.containsKey('name') && result.get('name').equals('Obligor')){
                                        contract.Obligor__c = (String) result.get('value');
                                    }
                                    if(result.containsKey('name') && result.get('name').equals('AdminCompany')){
                                        contract.Admin__c = (String) result.get('value');
                                    }
                                    if(result.containsKey('name') && result.get('name').equals('TypeOfInsurance')){
                                        contract.Ins_Type__c = (String) result.get('value');
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void retrieveDealerCodeData(List<InsurancePolicy> contracts) {
        String brType;
        
        
        // Sets for collecting unique coverage levels and clients for batch querying
        Set<String> coverageLevelSet = new Set<String>();
        Set<String> clientSet = new Set<String>();
        
        // Maps to associate Dealer Program IDs with Coverage Levels and Clients for easy lookup
        Map<String, String> coverageLevelMap = new Map<String, String>();
        Map<String, String> clientMap = new Map<String, String>();
        
        try {
            // Iterate over each new contract to process and retrieve data
            for (InsurancePolicy contract : contracts) {
                
                Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                
                if(contract.Dealer_Program_Id__c!=null){
                    parameter.put('DealerProgramId', Integer.valueOf(contract.Dealer_Program_Id__c));
                    parameters.add(parameter);
                    /*--------------30-04-2026--------------------*/
                    
                    System.debug(
                        'Calling BRE Rule: Dealer_Code_Lookup'
                    );
                    
                    /*---------------30-04-2026-------------------*/
                    String jsonString = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'Dealer_Code_Lookup', UtilityClass.BR_TYPE_DM, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','retrieveDealerCodeData', contract.Name);
                    // ✅ NEW call for Reinsurance Company
                    
                    /*--------------30-04-2026-------------------*/
                    
                    System.debug(
                        'Calling BRE Rule: Reinsurance_Company'
                    );
                    
                    /*--------------30-04-2026-------------------*/
                    String reinsJsonString = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'Reinsurance_Company',UtilityClass.BR_TYPE_DM,UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','retrieveDealerCodeData', contract.Name);
                    if (reinsJsonString != null && reinsJsonString != '') {
                        
                        Map<String, Object> reinsJsonMap =
                            (Map<String, Object>) JSON.deserializeUntyped(reinsJsonString);
                        
                        List<Object> reinsOutputs =
                            (List<Object>) reinsJsonMap.get('outputs');
                        
                        if (reinsOutputs != null && !reinsOutputs.isEmpty()) {
                            
                            Map<String, Object> firstOutput =
                                (Map<String, Object>) reinsOutputs.get(0);
                            
                            if (firstOutput.containsKey('results')) {
                                
                                List<Object> reinsResults =
                                    (List<Object>) firstOutput.get('results');
                                
                                for (Object resultObj : reinsResults) {
                                    
                                    Map<String, Object> result =
                                        (Map<String, Object>) resultObj;
                                    
                                    if (result != null &&
                                        'ReinsuranceCompany'.equals(result.get('name'))) {
                                            
                                            contract.Reinsurance_Company__c =
                                                (String) result.get('value');
                                        }
                                    
                                }
                            }
                        }
                    }
                    
                    // Parse the JSON string
                    if(jsonString!=null && jsonString!=''){
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
                        
                        System.debug('BRE PARSED MAP = ' + jsonMap);
                        // Extract the outputs list
                        List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                        if (outputs != null && !outputs.isEmpty()) {
                            // Get the first output
                            Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                            if (firstOutput != null && firstOutput.containsKey('results')) {
                                // Get the results list
                                List<Object> results = (List<Object>) firstOutput.get('results');
                                for (Object resultObj : results) {
                                    Map<String, Object> result = (Map<String, Object>) resultObj;
                                    if (result != null && !result.isEmpty()) {
                                        if (result.containsKey('name') && result.get('name').equals('CoverageLevel')) {
                                            // Extract and validate 'CoverageLevel' output
                                            coverageLevelSet.add((String) result.get('value'));
                                            coverageLevelMap.put(contract.Dealer_Program_Id__c, (String) result.get('value'));
                                        }
                                        if(result.containsKey('name') && result.get('name').equals('Product')){
                                            // Extract and validate 'Product' output, updating contract record
                                            contract.Product__c = (String) result.get('value');
                                        }
                                        if(result.containsKey('name') && result.get('name').equals('Client')){
                                            // Extract and validate 'Client' output
                                            String val = (String) result.get('value');
                                            clientSet.add(val.unescapeHtml4());
                                            clientMap.put(contract.Dealer_Program_Id__c, val.unescapeHtml4());
                                        }
                                        if(result.containsKey('name') && result.get('name').equals('RateSet')){
                                            // Extract and validate 'RateSet' output, updating contract record
                                            contract.Rate_Set__c = (String) result.get('value');
                                        }
                                        if(result.containsKey('name') && result.get('name').equals('OptionSets')){
                                            // Extract and validate 'OptionsSets' output, updating contract record
                                            contract.Options_Sets__c = (String) result.get('value');
                                        }
                                        if(result.containsKey('name') && result.get('name').equals('SurchargeSets')){
                                            // Extract and validate 'SurchargeSet' output, updating contract record
                                            contract.Surcharge_Set__c = (String) result.get('value');
                                        }
                                        if(result.containsKey('name') && result.get('name').equals('ClassGuide')){
                                            // Populating Class_Guide MRT-389 Change
                                            contract.Class_Guide__c = (String) result.get('value');
                                        }
                                        
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Query related records based on unique sets collected
            List<Coverage_Level__c> coverageLevelList = [
                SELECT Id, Name FROM Coverage_Level__c WHERE Name IN :coverageLevelSet
            ];
            List<Account> clientList = [
                SELECT Id, Name FROM Account WHERE Name IN :clientSet
            ];
            
            // Map queried data back to contract records
            for (InsurancePolicy contractRecord : contracts) {
                if (contractRecord != null && contractRecord.Dealer_Program_Id__c != null) {
                    String dealerProgramId = contractRecord.Dealer_Program_Id__c;
                    
                    // Map Coverage Level to contract if available
                    if (coverageLevelMap.containsKey(dealerProgramId)) {
                        for (Coverage_Level__c cvgLevel : coverageLevelList) {
                            if (cvgLevel.Name == coverageLevelMap.get(dealerProgramId)) {
                                contractRecord.Coverage_Level__c = cvgLevel.Id;
                                break;
                            }
                        }
                    }
                    
                    // Map Client Account to contract if available
                    if (clientMap.containsKey(dealerProgramId)) {
                        for (Account clientAcc : clientList) {
                            if (clientAcc.Name == clientMap.get(dealerProgramId)) {
                                contractRecord.Client__c = clientAcc.Id;
                                break;
                            }
                        }
                    }
                }
            }
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateStateInsuranceDetails(List<InsurancePolicy> contracts) {
        //System.debug('Inside populate state insurance details');
        String brType;
        
        try {
            Set<Id> clientIdSet = new Set<Id> ();
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            Map<Id, Account> clientIdMap = new Map<Id, Account> ();
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            //Preparing set of Clients and Coverage Level details
            for(InsurancePolicy contractRecord: contracts){
                if(contractRecord.Client__c != NULL){
                    clientIdSet.add(contractRecord.Client__c);
                }
                if(contractRecord.Coverage_Level__c !=NULL){
                    coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                }
            }
            //Query related Client and Coverage Level details
            if(clientIdSet != NULL && !clientIdSet.isEmpty()){
                clientIdMap = new Map<Id, Account>([Select Id, Name from Account WHERE ID IN : clientIdSet]);
            }
            //System.debug(LoggingLevel.ERROR, 'Client map: ' + JSON.serializePretty(clientIdMap));
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN : coverageLevelIdSet]);
            }
            //System.debug(LoggingLevel.ERROR, 'Coverage level map: ' + JSON.serializePretty(coverageLevelMap));
            
            for(InsurancePolicy contract: contracts){
                //System.debug(LoggingLevel.ERROR, '--- Checking contract: ' + contract.Name + ' ---');
                //System.debug(LoggingLevel.ERROR, 'Client__c: ' + contract.Client__c);
                //System.debug(LoggingLevel.ERROR, 'Coverage_Level__c: ' + contract.Coverage_Level__c);
                //System.debug(LoggingLevel.ERROR, 'State from contractStateMap: ' + contractStateMap.get(contract.Name));
                //System.debug(LoggingLevel.ERROR, 'clientIdMap contains Client__c? ' + clientIdMap.containsKey(contract.Client__c));
                //System.debug(LoggingLevel.ERROR, 'coverageLevelMap contains Coverage_Level__c? ' + coverageLevelMap.containsKey(contract.Coverage_Level__c));
                //System.debug(LoggingLevel.ERROR, 'Product__c: ' + contract.Product__c);
                
                //below this code is not running
                Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                if(contract.Product__c != NULL && contract.Client__c != NULL && contract.Coverage_Level__c != NULL && contractStateMap.get(contract.Name) != NULL && clientIdMap.containsKey(contract.Client__c) && coverageLevelMap.containsKey(contract.Coverage_Level__c)){
                    parameter.put('Product', contract.Product__c);
                    parameter.put('Client', clientIdMap.get(contract.Client__c).Name);
                    parameter.put('CoverageLevel', coverageLevelMap.get(contract.Coverage_Level__c).Name);
                    parameter.put('StateInput', contractStateMap.get(contract.Name));
                    parameter.put('ActiveInput', true);
                    parameters.add(parameter);
                    String response = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'State_Insurance_Guide', UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','populateStateInsuranceDetails', contract.Name);
                    //System.debug(LoggingLevel.ERROR, 'BRE callout raw response for contract ' + contract.Name + ': ' + (response == null ? 'NULL' : response));
                    if(response != null && response != '') {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(response);
                        List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                        if (outputs != null && !outputs.isEmpty()) {
                            Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                            if (firstOutput != null && firstOutput.containsKey('results')) {
                                Map<String, Object> results = (Map<String, Object>) firstOutput.get('results');
                                //System.debug('Results in populateStateInsDetails: ' + results);
                                //System.debug('Results (JSON): ' + JSON.serializePretty(results));
                                if (results.containsKey('CarrierOutput')) {
                                    contract.Ins_Carrier__c = (String) results.get('CarrierOutput');
                                }
                                if (results.containsKey('ObligorOutput')) {
                                    contract.Obligor__c = (String) results.get('ObligorOutput');
                                }
                                if (results.containsKey('AdminOutput')) {
                                    contract.Admin__c = (String) results.get('AdminOutput');
                                }
                                if (results.containsKey('InsuranceTypeOutput')) {
                                    contract.Ins_Type__c = (String) results.get('InsuranceTypeOutput');
                                    //System.debug('Ins type'+(String) results.get('InsuranceTypeOutput'));
                                    //System.debug('Ins type output from SF '+contract.Ins_Type__c);
                                    
                                }
                                //StateSetNameOutput also comes as output but it was never set in earlier logic
                            }
                        }
                    }
                }
            }
        } catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateRateSetDetails(List<InsurancePolicy> contracts) {
        
        Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
        Map<String, Map<String, Object>> vinDetails = new Map<String, Map<String, Object>>();
        List<String> vinNumbers = new List<String>();
        try {
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            for(InsurancePolicy contractRecord: contracts){
                if(contractRecord.Coverage_Level__c !=null){
                    coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                }
                if(contractRecord.VIN__c != NULL) {
                    vinNumbers.add(contractRecord.VIN__c);
                }
            }
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            if(!vinNumbers.isEmpty()) {
                vinDetails = VinUtility.getVinDetails(vinNumbers);
            }
            for (InsurancePolicy contract : contracts) {
                Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                if (contract!=NULL && contract.Rate_Set__c!=NULL) {
                    if(contract.VIN__c!=NULL){
                        String vin = contract.VIN__c;
                        //Fetch the VIN Record
                        //String squishVin = VinUtility.createSquishVIN(vin);
                        //List<String> squishVins = VinUtility.createAllSquishVINs(vin);
                        //String squishVin = !squishVins.isEmpty() ? squishVins[0] : null;
                        String squishVin = VinUtility.resolveSquishVIN(vin);
                        
                        if(vinDetails!= NULL && vinDetails.containsKey(squishVin)) {
                            if(vinDetails.get(squishVin).containsKey('mdl_yr__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c')) != null) {
                                contract.Vehicle_Year__c = String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c'));
                            }
                        }
                    }
                    parameter.put('RateSetInput', contract.Rate_Set__c);
                    if(contract.Coverage_Level__c != NULL){
                        parameter.put('CoverageNameInput', coverageLevelMap.get(contract.Coverage_Level__c ).Name);
                    }
                    if(contract.Up_To_or_Add__c != NULL){
                        parameter.put('ExpireTypeInput', contract.Up_To_or_Add__c.trim());
                    }
                    parameter.put('TermMonthsInput', contract.Contract_Term_Months__c);
                    parameter.put('TermMilesInput', contract.Contract_Term_Mileage__c);
                    parameter.put('MinMilesInput', contract.Vehicle_Mileage_at_Contract_Inception__c);
                    // if(contract.Vehicle_Year__c != NULL){
                    //     parameter.put('MinAgeInput', System.Today().Year()-Integer.valueOf(contract.Vehicle_Year__c));//need to check this
                    // } 
                    if(contract.Vehicle_Year__c != NULL && contract.SaleDate != NULL){
                        parameter.put('MinAgeInput', contract.SaleDate.date().year()-Integer.valueOf(contract.Vehicle_Year__c));//need to check this
                    } 
                    else {
                        parameter.put('MinAgeInput', 0);
                    }
                    parameter.put('RateClassInput', contract.Class__c);
                    parameter.put('DeductibleInput', contract.Deductible__c);
                    parameter.put('ResidenceTypeInput', contract.Residential_Type__c == null ? '1' : contract.Residential_Type__c);
                    parameter.put('MinSquareFootInput', contract.Square_Foot__c == null? 0 : contract.Square_Foot__c);
                    parameter.put('MinUnitInput', contract.Number_of_Units__c == null ? 0 : contract.Number_of_Units__c);
                    parameters.add(parameter);
                    String jsonStringRateSets = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'Rate_Sets', UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','populateRateSetDetails', contract.Name);
                    if(jsonStringRateSets != null && jsonStringRateSets != '') {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringRateSets);
                        if(jsonMap != NULL){
                            List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                            if (outputs != null && !outputs.isEmpty()) {
                                Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                                if (firstOutput != null && firstOutput.containsKey('results')) {
                                    Map<String, Object> results = (Map<String, Object>) firstOutput.get('results');
                                    if(results.containsKey('BaseReserveOutput')){
                                        contract.Reserve__c =(Decimal) results.get('BaseReserveOutput');
                                    }
                                    if(results.containsKey('RateCodeOutput')){
                                        contract.Rate_Code__c = (String) results.get('RateCodeOutput');
                                    }
                                    if(results.containsKey('PremiumTaxOutput')){
                                        if(contract.Premium_Tax_Old__c != null) {
                                            contract.Premium_Tax_Old__c = contract.Premium_Tax_Old__c + (Decimal) results.get('PremiumTaxOutput');
                                        } else {
                                            contract.Premium_Tax_Old__c = (Decimal) results.get('PremiumTaxOutput');
                                            //System.debug('----->'+results);
                                        }
                                    }
                                    if(results.containsKey('ObligorTaxOutput')){
                                        if(contract.OT_Allocation__c != null) {
                                            contract.OT_Allocation__c = contract.OT_Allocation__c + (Decimal) results.get('ObligorTaxOutput');
                                        } else {
                                            contract.OT_Allocation__c = (Decimal) results.get('ObligorTaxOutput');
                                            //System.debug('----->'+results);
                                        }
                                    }
                                    if(results.containsKey('CommissionOutput')){
                                        contract.MBI_Seller_Commission__c = (Decimal) results.get('CommissionOutput');
                                    }
                                    /*Commenting this logic since this will be set as part of MRT-394/Allocation Stories
if(contract.Ins_Carrier__c != NULL && contract.Ins_Carrier__c != 'AmericanResourceInsuranceCompany'){
if(results.containsKey('AdminFeeAmTrustOutput')){
contract.Admin_Cost__c = (Decimal) results.get('AdminFeeAmTrustOutput');
}
if(results.containsKey('CLIPFeeAmTrustOutput')){
contract.CLIP_Fee_Old__c = (Decimal) results.get('CLIPFeeAmTrustOutput');
}
}
if(contract.Ins_Carrier__c != NULL && contract.Ins_Carrier__c == 'AmericanResourceInsuranceCompany'){
if(results.containsKey('AdminFeeARICOutput')){
contract.Admin_Cost__c = (Decimal) results.get('AdminFeeARICOutput');
}
if(results.containsKey('CLIPFeeARICOutput')){
contract.CLIP_Fee_Old__c = (Decimal) results.get('CLIPFeeARICOutput');
}
}
if(contract.Ins_Carrier__c == NULL){
if(results.containsKey('AdminFeeNMOutput')){
contract.Admin_Cost__c = (Decimal) results.get('AdminFeeNMOutput');
}
}
*/
                                    if(results.containsKey('MaxMilesOutput')){
                                        contract.MaxMilesOutput__c = (Decimal) results.get('MaxMilesOutput');
                                    }
                                    if(results.containsKey('MaxSquareFootOutput')){
                                        contract.MaxSquareFoot__c = (Decimal) results.get('MaxSquareFootOutput');
                                    }
                                    if(results.containsKey('MaxUnitOutput')){
                                        contract.MaxUnitOutput__c = (Decimal) results.get('MaxUnitOutput');
                                    }
                                    if(results.containsKey('MaxAgeOutput')){
                                        contract.MaxAge__c = (Decimal) results.get('MaxAgeOutput');
                                    }
                                }
                            }
                        }
                    }
                    
                }
            }
            
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateOptionSetDetails(List<InsurancePolicy> contracts) {
        
        Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
        Map<String, Object> results = new Map<String, Object> ();
        try {
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            for(InsurancePolicy contractRecord: contracts){
                if(contractRecord.Coverage_Level__c !=null){
                    coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                }
            }
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            for (InsurancePolicy contract : contracts) {
                
                String jsonStringOptionsSets ;
                if (contract!=NULL && contract.Rate_Set__c!=NULL && contract.Option_1__c != NULL) {
                    String Options = contract.Option_1__c;
                    List<String> optionList = Options.split(';');
                    
                    System.debug(
                        LoggingLevel.ERROR,
                        'OPTIONS LOOP COUNT=' +
                        optionList.size() +
                        ' | Contract=' + contract.Name
                    );
                    
                    Decimal optionCost = 0;
                    // For loop for all the Options i.e. Option_1__c picklist values
                    for(String OptionNameInput : optionList){
                        Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                        if(String.isNotBlank(OptionNameInput)){
                            parameter.put('OptionsSetsInput', contract.Options_Sets__c);
                            if(contract.Coverage_Level__c != NULL){
                                parameter.put('CoverageNameInput', coverageLevelMap.get(contract.Coverage_Level__c ).Name);
                            }
                            parameter.put('OptionNameInput', OptionNameInput);
                            parameter.put('MinTermMonthsInput', contract.Contract_Term_Months__c);
                            parameter.put('MinTermMilesInput', contract.Contract_Term_Mileage__c);
                            System.debug('Contract custom Sale Date is'+contract.Sale_Date__c);
                            System.debug('Contract Sale Date is'+contract.SaleDate);
                            //Calculate the Vehicle Age from Vehicle Year
                            // if(contract.Vehicle_Year__c != NULL){
                            if(contract.SaleDate != null && contract.Vehicle_Year__c != NULL){
                                // parameter.put('MinVehicleAgeInput', System.Today().Year()-Integer.valueOf(contract.Vehicle_Year__c));
                                Integer saleYear = contract.SaleDate.date().year();
                                Integer vehicleYear = Integer.valueOf(contract.Vehicle_Year__c);
                                Integer minVehicleAge = saleYear - vehicleYear;
                                
                                // System.debug('SaleDate (Datetime): ' + contract.SaleDate);
                                // System.debug('Sale Year: ' + saleYear);
                                // System.debug('Vehicle Year: ' + vehicleYear);
                                System.debug('MinVehicleAgeInput: ' + minVehicleAge);
                                parameter.put('MinVehicleAgeInput',contract.SaleDate.date().year() - Integer.valueOf(contract.Vehicle_Year__c));
                            } else {
                                parameter.put('MinVehicleAgeInput', 0);
                            }
                            parameter.put('MinVehicleMiles', contract.Vehicle_Mileage_at_Contract_Inception__c);
                            if(contract.Up_To_or_Add__c != NULL){
                                parameter.put('UpToAddOnInput', contract.Up_To_or_Add__c.trim());
                            }
                            parameter.put('RateClassInput', contract.Class__c);
                            parameter.put('MinResidenceSqFtInput', contract.Square_Foot__c == null ? 0 : contract.Square_Foot__c);
                            //Calculate the Residence Age from Year Built
                            if(contract.Year_Built__c != NULL){
                                parameter.put('MinResidenceAgeInput', System.Today().Year()-Integer.valueOf(contract.Year_Built__c));
                            } else {
                                parameter.put('MinResidenceAgeInput', 0);
                            }
                            parameters.add(parameter);
                            
                            /*---------------------30-04-2026--------------------------------------*/
                            
                            System.debug(
                                'Calling BRE Rule: Options_Sets'
                            );
                            
                            /*---------------------30-04-2026--------------------------------------*/
                            jsonStringOptionsSets = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'Options_Sets', UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','populateOptionSetDetails', contract.Name);
                            if(jsonStringOptionsSets != null && jsonStringOptionsSets != '' ) {
                                Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringOptionsSets);
                                if(jsonMap != NULL){
                                    List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                                    if (outputs != null && !outputs.isEmpty()) {
                                        Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                                        if(firstOutput!=null && firstOutput.containsKey('results')){
                                            results = (Map<String, Object>) firstOutput.get('results');
                                            if (results != null ) {
                                                Decimal tempOptionCost = 0;
                                                if(results.containsKey('MaxTermMonthsOutput')){
                                                    contract.MaxTermMonths__c =(Decimal) results.get('MaxTermMonthsOutput');
                                                }
                                                if(results.containsKey('MaxTermMilesOutput')){
                                                    contract.MaxMilesOutput__c = (Decimal) results.get('MaxTermMilesOutput');
                                                }
                                                if(results.containsKey('MaxVehicleMilesOutput')){
                                                    contract.MaxVehicleMilesOutput__c = (Decimal) results.get('MaxVehicleMilesOutput');
                                                }
                                                if(results.containsKey('MaxVehicleAgeOutput') && (Decimal) results.get('MaxVehicleAgeOutput') > 0){
                                                    contract.MaxAge__c = (Decimal) results.get('MaxVehicleAgeOutput');
                                                }
                                                if(results.containsKey('MaxResidenceSqFtOutput')){
                                                    contract.MaxSquareFoot__c = (Decimal) results.get('MaxResidenceSqFtOutput');
                                                }
                                                if(results.containsKey('MaxResidenceAgeOutput') && (Decimal) results.get('MaxResidenceAgeOutput') > 0){
                                                    contract.MaxAge__c = (Decimal) results.get('MaxResidenceAgeOutput');
                                                }
                                                if(results.containsKey('PremiumTaxOutput')){
                                                    if(contract.Premium_Tax_Old__c != null) {
                                                        contract.Premium_Tax_Old__c = contract.Premium_Tax_Old__c + (Decimal) results.get('PremiumTaxOutput');
                                                    } else {
                                                        contract.Premium_Tax_Old__c = (Decimal) results.get('PremiumTaxOutput');
                                                    }
                                                }
                                                if(results.containsKey('ObligorTaxOutput')){
                                                    if(contract.OT_Allocation__c != null) {
                                                        contract.OT_Allocation__c = contract.OT_Allocation__c + (Decimal) results.get('ObligorTaxOutput');
                                                    } else {
                                                        contract.OT_Allocation__c = (Decimal) results.get('ObligorTaxOutput');
                                                    }
                                                }
                                                // Calculate the Option Cost for all the Options
                                                if(results.containsKey('OptionCostOutput')){
                                                    tempOptionCost = (Decimal) results.get('OptionCostOutput');
                                                    optionCost = optionCost + tempOptionCost;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Assign the Option Cost to Options_Cost__c
                    if(!optionList.isEmpty() && optionCost > 0){
                        contract.Options_Cost__c = optionCost;
                    }
                }
            }
            
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateSurchargeSetDetails(List<InsurancePolicy> contracts) {
        String brType;
        
        Map<String, Map<String, Object>> vinDetails = new Map<String, Map<String, Object>>();
        List<String> vinNumbers = new List<String>();
        String coverageLevel;
        try {
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            
            //populating coverage level and vin into list variables
            for(InsurancePolicy contractRecord: contracts){
                if(contractRecord.Coverage_Level__c != null){
                    coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                }
                if(contractRecord.VIN__c != NULL) {
                    vinNumbers.add(contractRecord.VIN__c);
                }
            }
            
            //querying coverage level records to populate Name field in parameters map
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            
            if(!vinNumbers.isEmpty()) {
                Map<String, String> driveTrainMapper = UtilityClass.getDriveTrainValue();
                vinDetails = VinUtility.getVinDetails(vinNumbers);
                if(vinDetails.size() > 0) {
                    for(InsurancePolicy contract: contracts) {
                        
                        String combinedSurcharges = '';
                        if(contract.VIN__c!=NULL){
                            String vin = contract.VIN__c;
                            //getting all the surcharge names as per the rules mentioned in MRT-393
                            //String squishVin = VinUtility.createSquishVIN(vin);
                            //List<String> squishVins = VinUtility.createAllSquishVINs(vin);
                            //String squishVin = !squishVins.isEmpty() ? squishVins[0] : null;
                            String squishVin = VinUtility.resolveSquishVIN(vin);
                            
                            if(vinDetails.containsKey(squishVin)) {
                                if(vinDetails.get(squishVin).containsKey('mdl_yr__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c')) != null) {
                                    contract.Vehicle_Year__c = String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c'));
                                }
                                if(vinDetails.get(squishVin).containsKey('mak_nm__c') && String.valueOf(vinDetails.get(squishVin).get('mak_nm__c')) != null) {
                                    contract.Vehicle_Make__c = String.valueOf(vinDetails.get(squishVin).get('mak_nm__c'));
                                }
                                if(vinDetails.get(squishVin).containsKey('mdl_desc__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_desc__c')) != null) {
                                    contract.Vehicle_Model__c = String.valueOf(vinDetails.get(squishVin).get('mdl_desc__c'));
                                }
                                
                                /*if(vinDetails.get(squishVin).containsKey('trk_tng_rat_cd__c') &&
vinDetails.get(squishVin).get('trk_tng_rat_cd__c') != null) {

if(Boolean.valueOf(vinDetails.get(squishVin).get('trk_tng_rat_cd__c'))) {
combinedSurcharges += '1-Ton;';
contract.is_OverOneTon__c = true;
}
}
*/
                                /*----------------------------Changes--------------------------------*/
                                if(vinDetails.get(squishVin).containsKey('trk_tng_rat_cd__c') &&
                                   vinDetails.get(squishVin).get('trk_tng_rat_cd__c') != null) {
                                       
                                       String tonnageCode = String.valueOf(
                                           vinDetails.get(squishVin).get('trk_tng_rat_cd__c')
                                       );
                                       
                                       if (tonnageCode == 'D' || tonnageCode == 'E' || tonnageCode == 'F') {
                                           combinedSurcharges += '1 Ton;';
                                           contract.is_OverOneTon__c = true;
                                       }
                                   }
                                /*------------------------------Changes------------------------------*/
                                
                                if(vinDetails.get(squishVin).containsKey('eng_fuel_desc__c') && vinDetails.get(squishVin).get('eng_fuel_desc__c') == 'Diesel') {
                                    combinedSurcharges += 'Diesel;';
                                    contract.is_Diesel__c = true;
                                }
                                if(vinDetails.get(squishVin).containsKey('eng_asp_trbl_chgr_cd__c') &&
                                   vinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c') != null) {
                                       if(Boolean.valueOf(vinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c'))) {
                                           combinedSurcharges += 'Turbo;';
                                           contract.is_Turbo__c = true;
                                       }
                                   }
                                if(vinDetails.get(squishVin).containsKey('drv_typ_cd__c')) {
                                    String driveTrain = (String) vinDetails.get(squishVin).get('drv_typ_cd__c');
                                    String driveTrainVal = driveTrainMapper.get(driveTrain);
                                    if(driveTrainVal == '4WD' || driveTrainVal == '4FD' || driveTrainVal == '4RD') {
                                        combinedSurcharges += '4WD;';
                                        contract.Drivetrain__c = '4WD';
                                    }
                                    if(driveTrainVal == '4AWD' || driveTrainVal == 'AWD') {
                                        combinedSurcharges += 'AWD;';
                                        contract.Drivetrain__c = 'AWD';
                                    }
                                }
                                if(vinDetails.get(squishVin).containsKey('trim_desc__c') && vinDetails.get(squishVin).get('trim_desc__c') != null) {
                                    contract.Trim__c = (String) vinDetails.get(squishVin).get('trim_desc__c');
                                }
                                if(vinDetails.get(squishVin).containsKey('eng_asp_sup_chgr_cd__c') &&
                                   vinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c') != null) {
                                       if(Boolean.valueOf(vinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c'))) {
                                           combinedSurcharges += 'Supercharger;';
                                           contract.is_Supercharged__c = true;
                                       }
                                   }
                                if(vinDetails.get(squishVin).containsKey('body_style_desc__c') &&
                                   String.valueOf(vinDetails.get(squishVin).get('body_style_desc__c')) != null) {
                                       contract.Body_Style__c = String.valueOf(vinDetails.get(squishVin).get('body_style_desc__c'));
                                   }
                            }
                        }
                        
                        //populating combinedSurcharges for Extended miles
                        if(contract.Vehicle_Mileage_at_Contract_Inception__c != null) {
                            if(contract.Vehicle_Mileage_at_Contract_Inception__c >= 5000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 12000) {
                                combinedSurcharges += 'Extended Eligibility 5-12k;';
                            }
                            if(contract.Vehicle_Mileage_at_Contract_Inception__c > 12000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 24000) {
                                combinedSurcharges += 'Extended Eligibility 12-24k;';
                            }
                            if(contract.Vehicle_Mileage_at_Contract_Inception__c > 24000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 35000) {
                                combinedSurcharges += 'Extended Eligibility 24-35k;';
                            }
                            if(contract.Vehicle_Mileage_at_Contract_Inception__c > 35000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 50000) {
                                combinedSurcharges += 'Extended Eligibility 35-50k;';
                            }
                            if(contract.Vehicle_Mileage_at_Contract_Inception__c > 50000 && contract.Vehicle_Mileage_at_Contract_Inception__c <= 70000) {
                                combinedSurcharges += 'Extended Eligibility 50-70k;';
                            }
                        }
                        if(contract.Product__c == 'Health CAR') {
                            combinedSurcharges += 'All Classes Surcharge;';
                        }
                        if(!String.isEmpty(combinedSurcharges)) {
                            combinedSurcharges = combinedSurcharges.Substring(0, combinedSurcharges.length()-1);
                        }
                        if(combinedSurcharges != NULL){
                            contract.Surcharges__c = combinedSurcharges;
                        }
                        Decimal surchargeCost = 0;
                        List<String> surcharges = combinedSurcharges.split(';');
                        /*------------------30-04-2026-----------------------------*/
                        
                        System.debug(
                            LoggingLevel.ERROR,
                            'SURCHARGE LOOP COUNT=' +
                            surcharges.size() +
                            ' | Contract=' + contract.Name
                        );
                        
                        /*------------------30-04-2026-----------------------------*/
                        
                        
                        //looping over surcharges applicable for particular contract and calling expression set API
                        for(String surcharge : surcharges) {
                            Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
                            parameter.put('SurchargeNameInput', surcharge);
                            if(coverageLevelMap != NULL && contract.Coverage_Level__c != NULL && coverageLevelMap.containsKey(contract.Coverage_Level__c)){
                                parameter.put('CoverageNameInput', coverageLevelMap.get(contract.Coverage_Level__c ).Name);
                            }
                            parameter.put('MinTermMonthsInput', contract.Contract_Term_Months__c);
                            parameter.put('MinTermMilesInput', contract.Contract_Term_Mileage__c);
                            parameter.put('MinVehicleMilesInput', contract.Vehicle_Mileage_at_Contract_Inception__c);
                            // if(contract.Vehicle_Year__c != NULL){
                            //     parameter.put('MinVehicleAgeInput', System.Today().Year()-Integer.valueOf(contract.Vehicle_Year__c));
                            // }
                            if(contract.Vehicle_Year__c != NULL && contract.SaleDate != null){
                                parameter.put('MinVehicleAgeInput', contract.SaleDate.date().year()-Integer.valueOf(contract.Vehicle_Year__c));
                            }
                            
                            parameter.put('RateClassListInput', contract.Class__c);
                            parameter.put('SurchargeSetsInput', contract.Surcharge_Set__c);
                            parameters.add(parameter);
                            
                            /*------------------30-04-2026------------------------*/
                            
                            System.debug(
                                'Calling BRE Rule: Surcharge_Sets'
                            );
                            
                            /*-------------------30-04-2026-----------------------*/
                            
                            
                            String jsonStringRateSets = BREManager.runBRCallout(parameters,contract.SaleDate.date(),'Surcharge_Sets', UtilityClass.BR_TYPE_EX, UtilityClass.IS_EXTERNAL_CALL, 'BREServiceHandler','populateSurchargeSetDetails', contract.Name);
                            if(jsonStringRateSets!=null && jsonStringRateSets!=''){
                                Map<String, Object> jsonMapRateSets = (Map<String, Object>) JSON.deserializeUntyped(jsonStringRateSets);
                                List<Object> outputsSurchargeSets = (List<Object>) jsonMapRateSets.get('outputs');
                                if (outputsSurchargeSets != null && !outputsSurchargeSets.isEmpty()) {
                                    Map<String, Object> firstOutput = (Map<String, Object>) outputsSurchargeSets.get(0);
                                    if (firstOutput != null && firstOutput.containsKey('results')) {
                                        Map<String, Object> results = (Map<String, Object>) firstOutput.get('results');
                                        
                                        //if result is returned, populating contract fields
                                        if (results != null) {
                                            if(results.containsKey('SurchargeCostOutput')){
                                                surchargeCost += (Decimal) results.get('SurchargeCostOutput');
                                            }
                                            if(results.containsKey('MaxTermMonthsOutput')){
                                                contract.MaxTermMonths__c = (Decimal) results.get('MaxTermMonthsOutput');
                                            }
                                            if(results.containsKey('MaxTermMilesOutput')){
                                                contract.MaxTermMilesOutput__c = (Decimal) results.get('MaxTermMilesOutput');
                                            }
                                            if(results.containsKey('MaxVehicleMilesOutput') ){
                                                contract.MaxVehicleMilesOutput__c = (Decimal) results.get('MaxVehicleMilesOutput');
                                            }
                                            if(results.containsKey('MaxVehicleAgeOutput')){
                                                contract.MaxAge__c = (Decimal) results.get('MaxVehicleAgeOutput');
                                            }
                                            if(results.containsKey('PremiumTaxOutput')){
                                                if(contract.Premium_Tax_Old__c != null) {
                                                    contract.Premium_Tax_Old__c = contract.Premium_Tax_Old__c + (Decimal) results.get('PremiumTaxOutput');
                                                } else {
                                                    contract.Premium_Tax_Old__c = (Decimal) results.get('PremiumTaxOutput');
                                                }
                                            }
                                            if(results.containsKey('ObligorTaxOutput')){
                                                if(contract.OT_Allocation__c != null) {
                                                    contract.OT_Allocation__c = contract.OT_Allocation__c + (Decimal) results.get('ObligorTaxOutput');
                                                } else {
                                                    contract.OT_Allocation__c = (Decimal) results.get('ObligorTaxOutput');
                                                    //System.debug('----->'+results);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        //populating combined surcharge cost for all surachrges related to a contract into field
                        contract.Surcharge_Cost__c = surchargeCost;
                    }
                }
            }
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    // public static Void populateOriginalState(List<InsurancePolicy> contracts) {
    //     Set<String> dealerSet = new Set<String>();
    //     Set<String> namedInsuredSet = new Set<String>();
    //     Map<Id, String> accRecs = new Map<Id, String>();
    //     Map<String, Account> namedInsuredRecs = new Map<String, Account>();
    //     Id recordTypeId = Schema.SObjectType.InsurancePolicy.getRecordTypeInfosByDeveloperName().get('Auto_Warranty').getRecordTypeId();
    
    //     for(InsurancePolicy contract : contracts) {
    //         if(contract.Dealer__c != null) {
    //             dealerSet.add(contract.Dealer__c);
    //         }
    //         if(contract.NameInsuredId != null) {
    //             namedInsuredSet.add(contract.NameInsuredId);
    //         }
    //     }
    
    //     for(Account acc : [SELECT Id, Name, BillingState FROM Account WHERE Id IN : dealerSet OR Id IN : namedInsuredSet]) {
    //         accRecs.put(acc.Id, acc.BillingState);
    //     }
    
    //     for(InsurancePolicy contract : contracts) {
    //         if(contract.RecordTypeId == recordTypeId) {
    //             if(contract.Dealer__c != null && dealerSet.contains(contract.Dealer__c)) {
    //                 contractStateMap.put(contract.Name, accRecs.containsKey(contract.Dealer__c) ? accRecs.get(contract.Dealer__c) : '');
    //             } else if(contract.NameInsuredId != null && namedInsuredSet.contains(contract.NameInsuredId)) {
    //                 contractStateMap.put(contract.Name, accRecs.containsKey(contract.NameInsuredId) ? accRecs.get(contract.NameInsuredId) : '');
    //             }
    //         } else {
    //             if(contract.State__c != null) {
    //                 contractStateMap.put(contract.Name, contract.State__c);
    //             }
    //         }
    //     }
    // }
    public static Void populateOriginalState(List<InsurancePolicy> contracts) {
        
        //System.debug(LoggingLevel.ERROR, '=== populateOriginalState() START ===');
        //System.debug(LoggingLevel.ERROR, 'Contracts received: ' + JSON.serializePretty(contracts));
        
        Set<String> dealerSet = new Set<String>();
        Set<String> namedInsuredSet = new Set<String>();
        Map<Id, String> accRecs = new Map<Id, String>();
        
        Id recordTypeId = Schema.SObjectType.InsurancePolicy
            .getRecordTypeInfosByDeveloperName()
            .get('Auto_Warranty')
            .getRecordTypeId();
        
        //System.debug(LoggingLevel.ERROR, 'Auto_Warranty RecordTypeId: ' + recordTypeId);
        
        // 1️⃣ FIRST LOOP — COLLECT KEYS
        for (InsurancePolicy contract : contracts) {
            
            //System.debug(LoggingLevel.ERROR, '--- CONTRACT DEBUG START ---');
            //System.debug(LoggingLevel.ERROR, 'Contract Name: ' + contract.Name);
            //System.debug(LoggingLevel.ERROR, 'Dealer__c: ' + contract.Dealer__c);
            //System.debug(LoggingLevel.ERROR, 'NameInsuredId: ' + contract.NameInsuredId);
            //System.debug(LoggingLevel.ERROR, 'RecordTypeId: ' + contract.RecordTypeId);
            //System.debug(LoggingLevel.ERROR, 'State__c: ' + contract.State__c);
            
            if (contract.Dealer__c != null) {
                dealerSet.add(contract.Dealer__c);
            }
            if (contract.NameInsuredId != null) {
                namedInsuredSet.add(contract.NameInsuredId);
            }
            
            //System.debug(LoggingLevel.ERROR, '--- CONTRACT DEBUG END ---');
        }
        
        //System.debug(LoggingLevel.ERROR, 'Dealer Set: ' + dealerSet);
        //System.debug(LoggingLevel.ERROR, 'Named Insured Set: ' + namedInsuredSet);
        
        // 2️⃣ QUERY ACCOUNTS
        if (!dealerSet.isEmpty() || !namedInsuredSet.isEmpty()) {
            List<Account> accList = [
                SELECT Id, Name, BillingState 
                FROM Account 
                WHERE Id IN :dealerSet OR Id IN :namedInsuredSet
            ];
            
            //System.debug(LoggingLevel.ERROR, 'Accounts from query: ' + JSON.serializePretty(accList));
            
            for (Account acc : accList) {
                accRecs.put(acc.Id, acc.BillingState);
            }
        }
        
        //System.debug(LoggingLevel.ERROR, 'accRecs (Id -> BillingState): ' + accRecs);
        
        // 3️⃣ SECOND LOOP — POPULATE contractStateMap
        // for (InsurancePolicy contract : contracts) {
        
        //     //System.debug(LoggingLevel.ERROR, 'Evaluating State Mapping for contract: ' + contract.Name);
        
        //     if (contract.RecordTypeId == recordTypeId) {
        
        //         //System.debug(LoggingLevel.ERROR, 'RecordType MATCHED Auto_Warranty');
        
        //         if (contract.Dealer__c != null && dealerSet.contains(contract.Dealer__c)) {
        //             //System.debug(LoggingLevel.ERROR, 'Using Dealer__c for State lookup');
        //             //System.debug(LoggingLevel.ERROR, 'BillingState found: ' + accRecs.get(contract.Dealer__c));
        
        //             contractStateMap.put(
        //                 contract.Name,
        //             accRecs.containsKey(contract.Dealer__c) ? accRecs.get(contract.Dealer__c) : null
        //                 );
        //         } else if (contract.NameInsuredId != null && namedInsuredSet.contains(contract.NameInsuredId)) {
        //             //System.debug(LoggingLevel.ERROR, 'Using NameInsuredId for State lookup');
        //             //System.debug(LoggingLevel.ERROR, 'BillingState found: ' + accRecs.get(contract.NameInsuredId));
        
        //             contractStateMap.put(
        //                 contract.Name,
        //             accRecs.containsKey(contract.NameInsuredId) ? accRecs.get(contract.NameInsuredId) : null
        //                 );
        //         } else {
        //             //System.debug(LoggingLevel.ERROR, '❌ No Dealer or Named Insured mapping matched');
        //         }
        
        //     } else {
        //         //System.debug(LoggingLevel.ERROR, 'RecordType != Auto_Warranty');
        
        //         if (contract.State__c != null) {
        //             //System.debug(LoggingLevel.ERROR, 'Using contract.State__c directly');
        //             contractStateMap.put(contract.Name, contract.State__c);
        //         } else {
        //             //System.debug(LoggingLevel.ERROR, '❌ contract.State__c is NULL');
        //         }
        //     }
        
        //     //System.debug(LoggingLevel.ERROR, 'contractStateMap[' + contract.Name + '] = ' + contractStateMap.get(contract.Name));
        // }
        for (InsurancePolicy contract : contracts) {
            //System.debug(LoggingLevel.ERROR, 'Evaluating State Mapping for contract: ' + contract.Name);
            
            if (contract.RecordTypeId == recordTypeId) {
                //System.debug(LoggingLevel.ERROR, 'RecordType MATCHED Auto_Warranty');
                
                String stateFromDealer = null;
                String stateFromNamedInsured = null;
                
                if (contract.Dealer__c != null && accRecs.containsKey(contract.Dealer__c)) {
                    stateFromDealer = accRecs.get(contract.Dealer__c);
                }
                
                if (contract.NameInsuredId != null && accRecs.containsKey(contract.NameInsuredId)) {
                    stateFromNamedInsured = accRecs.get(contract.NameInsuredId);
                }
                
                //System.debug(LoggingLevel.ERROR, 'Dealer BillingState: ' + stateFromDealer);
                //System.debug(LoggingLevel.ERROR, 'NamedInsured BillingState: ' + stateFromNamedInsured);
                String finalState;
                
                if (stateFromDealer != null && stateFromDealer != '') {
                    finalState = stateFromDealer;
                    //System.debug(LoggingLevel.ERROR, 'Using Dealer BillingState');
                } else if (stateFromNamedInsured != null && stateFromNamedInsured != '') {
                    finalState = stateFromNamedInsured;
                    //System.debug(LoggingLevel.ERROR, 'Using NamedInsured BillingState because Dealer is null');
                } else {
                    finalState = null;
                    //System.debug(LoggingLevel.ERROR, '❌ Both Dealer and NamedInsured BillingState are NULL');
                }
                
                contractStateMap.put(contract.Name, finalState);
            }
            else {
                // original fallback logic for other record types
                if (contract.State__c != null) {
                    contractStateMap.put(contract.Name, contract.State__c);
                } else {
                    contractStateMap.put(contract.Name, null);
                }
            }
            
            //System.debug(LoggingLevel.ERROR, 'Final State assigned: ' + contractStateMap.get(contract.Name));
        }
        
        //System.debug(LoggingLevel.ERROR, '=== FINAL contractStateMap ===');
        //System.debug(LoggingLevel.ERROR, JSON.serializePretty(contractStateMap));
        
        //System.debug(LoggingLevel.ERROR, '=== populateOriginalState() END ===');
    }
    
    
}