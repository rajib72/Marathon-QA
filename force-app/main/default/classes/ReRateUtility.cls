/**
* ReRateUtility Class
* This class handles the reRate calculations for contract.
* It builds JSON request payloads dynamically based on the provided parameters
* and handles HTTP POST requests to the Salesforce Business Rules Engine.
*/
global class ReRateUtility implements Callable {   
    
    //Converts input parameter args to correct mapping. @parameter action: Stores method name that would be getting executed.
    public static Object call(String action, Map<String, Object> args) {
        Map<String, Object> input = (Map<String, Object>)args.get('input');
        Map<String, Object> output = (Map<String, Object>)args.get('output');
        Map<String, Object> options = (Map<String, Object>)args.get('options');        
        return invokeMethod(action, input, output, options);
    }
    
    //Handles correct mapping of action to it's associated method call.
    public static Object invokeMethod(String methodName, Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options){
        if (methodName.equals('rateSetContract')){
            rateSetContract(input, outMap, options);
        }
        else if (methodName.equals('createSquishVIN')){
            createSquishVIN(input, outMap, options);
        } 
      /*  else if (methodName.equals('createAllSquishVINs')) {
            createAllSquishVINs(input, outMap, options);
        } */
        else if (methodName.equals('reRateContract')){
            reRateContract(input, outMap, options);
        }
        else if (methodName.equals('coverageLevelOptions')){
            coverageLevelOptions(input, outMap);
        }
        return True;
    }
    
    //Calls Rate set expression set.
    public static void rateSetContract(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options){
        populateRateSetDetails(input, outMap, options);
    }
    
    //Method is used to re rate contracts. First, it calls rate set expression set to find correct rate set and other field values. 
    //Second, OptionSet expression set is called to find option cost.
    //Third, Surcharge set expression set is called to find any surcharge set.
    //Fourth, calls calculateNewDealerCost which calculates new dealer cost.
    //@paramater options: Stores all required field values for Contract record.
    public static void reRateContract(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options){
        populateRateSetDetails(input, outMap, options);
        populateOptionSetDetails(input, outMap, options);
        populateSurchargeSetDetails(input, outMap, options);
        populateAllocationCosts(input, outMap, options);
        calculateNewDealerCost(input, outMap, options);
    }
    
    //Method return a list of all coverage level to be mapped on picklist field on omnistudio UI.
    public static List<Map<String, Object>> coverageLevelOptions(Map<String, Object> inputMap, Map<String, Object> outMap) {
        List<Map<String, Object>> optionList = new List<Map<String, Object>>();
        for (Coverage_Level__c coverageLevel : [Select Id, Name from Coverage_Level__c where Name != NULL LIMIT 10000]) {
            Map<String, Object> option = new Map<String, Object>();
            option.put('name', coverageLevel.Id);
            option.put('value', coverageLevel.Name);
            optionList.add(option);
        }
        outMap.put('options', optionList);
        return optionList;
    }
    
    //Method return a list SquishVIN for a given VIN value.
    public static void createSquishVIN(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
        String vin = contractMap.get('VIN__c') != NULL ? String.valueOf(contractMap.get('VIN__c')) : '';
        String squishedVIN = '';
        if(vin.length()>8){
            squishedVIN =vin.subString(0,8) + '*' + vin.subString(9,11) + '******';
        }
        contractMap.put('squishedVIN', squishedVIN);
        outMap.put('Contract', contractMap);
    } 
    
    // Method generates a list of Squish VINs for a given VIN value and stores it in outMap
  /*  public static void createSquishVIN(Map<String, Object> input, Map<String, Object> outMap, Map<String, Object> options) {
        if (options == null || !options.containsKey('contract')) {
            return;
        }
        
        Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
        String vin = (contractMap != null && contractMap.get('VIN__c') != null)
            ? String.valueOf(contractMap.get('VIN__c'))
            : '';
        
        List<String> squishedVINList = new List<String>();
        
        if (!String.isBlank(vin) && vin.length() == 17) {
            // XXXXXXXX*XX******
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9,11) + '******');
            // XXXXXXXX*XXXXXXXX
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9));
            // XXXXXXXX*XXXXXXX*
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9,16) + '*');
            // XXXXXXXX*XXXXXX**
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9,15) + '**');
            // XXXXXXXX*XXXXX***
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9,14) + '***');
            // XXXXXXXX*XXXX****
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9,13) + '****');
            // XXXXXXXX*XXX*****
            squishedVINList.add(vin.substring(0,8) + '*' + vin.substring(9,12) + '*****');
        }
        
        // Store list of squished VINs inside contract map
        contractMap.put('squishedVIN', squishedVINList);
        outMap.put('Contract', contractMap);
    } */

    
    public static void populateRateSetDetails(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
        Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
        try {
            Set<Id> coverageLevelIdSet = new Set<Id> ();  
            Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
            if(contractMap.get('Coverage_Level__Id') !=null){
                coverageLevelIdSet.add((Id) contractMap.get('Coverage_Level__Id'));
            }
            
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE Id IN  : coverageLevelIdSet]);
            }
            if (contractMap!=NULL && options.get('Rate_Set')!=NULL) {
                parameter.put('RateSetInput', options.get('Rate_Set'));
                if(coverageLevelMap.get((Id) contractMap.get('Coverage_Level__Id')) != NULL){
                    parameter.put('CoverageNameInput', coverageLevelMap.get(String.valueOf((Id) contractMap.get('Coverage_Level__Id'))).Name);
                }
                parameter.put('ExpireTypeInput', contractMap.get('Up_To_or_Add__c'));
                parameter.put('TermMonthsInput', contractMap.get('Term_Months'));
                parameter.put('TermMilesInput', contractMap.get('Term_Miles'));
                parameter.put('MinMilesInput', contractMap.get('Sale_Mileage'));
                if(contractMap.get('Vehicle_Year__c') != NULL){
                    parameter.put('MinAgeInput', System.Today().Year()-Integer.valueOf(contractMap.get('Vehicle_Year__c')));
                } else {
                    parameter.put('MinAgeInput', 0);
                }
                parameter.put('RateClassInput', contractMap.get('Class__c'));
                parameter.put('DeductibleInput', contractMap.get('Deductible__c'));
                parameter.put('ResidenceTypeInput', contractMap.get('Residential_Type__c') == null ? '1' : contractMap.get('Residential_Type__c'));
                parameter.put('MinSquareFootInput', contractMap.get('Square_Foot__c') == null? 0 : contractMap.get('Square_Foot__c'));
                parameter.put('MinUnitInput', contractMap.get('Number_of_Units__c') == null ? 0 : contractMap.get('Number_of_Units__c'));
                parameters.add(parameter);
                String jsonStringRateSets = BREServiceHandlerBulkified.runBRCallout(parameters,Date.valueOf(String.valueOf(options.get('Sale_Date'))),'Rate_Sets', UtilityClass.BR_TYPE_EX, UtilityClass.IS_INTERNAL_CALL);
                if(jsonStringRateSets != null && jsonStringRateSets != '') {
                    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringRateSets);
                    if(jsonMap != NULL){ 
                        List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                        if (outputs != null && !outputs.isEmpty()) {
                            Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                            if (firstOutput != null) {
                                Map<String, Object> results = (Map<String, Object>) firstOutput.get('results');
                                if(results.size() == 0){
                                    contractMap.put('NoRateSetExist', TRUE);  
                                    contractMap.put('Reserve__c', 0.0);
                                    contractMap.put('Rate_Code__c', '');
                                    contractMap.put('Premium_Tax_Old__c', 0.0);
                                    contractMap.put('MBI_Seller_Commission__c', 0.0);
                                    contractMap.put('MaxMilesOutput__c',0.0);
                                    contractMap.put('MaxSquareFoot__c',0);
                                    contractMap.put('MaxUnitOutput__c',0);
                                    contractMap.put('MaxAge__c', 0);
                                } 
                                if(results.containsKey('BaseReserveOutput')){
                                    contractMap.put('Reserve__c', results.get('BaseReserveOutput'));
                                } 
                                if(results.containsKey('RateCodeOutput')){
                                    contractMap.put('Rate_Code__c', results.get('RateCodeOutput'));
                                }
                                if(results.containsKey('PremiumTaxOutput') && contractMap.get('Premium_Tax_Old__c') != NULL){
                                    contractMap.put('Premium_Tax_Old__c',  (Decimal) contractMap.get('Premium_Tax_Old__c') + (Decimal) results.get('PremiumTaxOutput'));
                                }
                                if(results.containsKey('CommissionOutput')){
                                    contractMap.put('MBI_Seller_Commission__c', results.get('CommissionOutput'));
                                }
                                if(results.containsKey('MaxMilesOutput')){
                                    contractMap.put('MaxMilesOutput__c',(Decimal) results.get('MaxMilesOutput'));
                                }
                                if(results.containsKey('MaxSquareFootOutput')){
                                    contractMap.put('MaxSquareFoot__c',(Decimal) results.get('MaxSquareFootOutput'));
                                }
                                if(results.containsKey('MaxUnitOutput')){
                                    contractMap.put('MaxUnitOutput__c',(Decimal) results.get('MaxUnitOutput'));
                                }
                                if(results.containsKey('MaxAgeOutput')){
                                    contractMap.put('MaxAge__c', (Decimal) results.get('MaxAgeOutput'));
                                }
                            }
                        }
                        
                    }
                }
            }
            outmap.put('Contract', contractMap);
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateOptionSetDetails(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
        Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
        Map<String, Object> results = new Map<String, Object> ();
        try {
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
            if(contractMap.get('Coverage_Level__Id') !=null){
                coverageLevelIdSet.add((Id) contractMap.get('Coverage_Level__Id'));
            }
            
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            
            String jsonStringOptionsSets ;
            if (contractMap!=NULL && options.get('Rate_Set')!=NULL && contractMap.get('Option_1') != NULL) {
                String contractOptions = String.valueOf(contractMap.get('Option_1'));
                List<String> optionList = contractOptions.split(';');
                Decimal optionCost = 0;
                // For loop for all the Options i.e. Option_1__c picklist values
                for(String OptionNameInput : optionList){
                    parameter.put('OptionsSetsInput', contractMap.get('Options_Sets__c'));
                    if(contractMap.get('Coverage_Level__Id') != NULL){
                        parameter.put('CoverageNameInput', coverageLevelMap.get((Id) contractMap.get('Coverage_Level__Id')).Name);
                    }
                    parameter.put('OptionNameInput', OptionNameInput);
                    parameter.put('MinTermMonthsInput', contractMap.get('Term_Months'));
                    parameter.put('MinTermMilesInput', contractMap.get('Term_Miles'));
                    //Calculate the Vehicle Age from Vehicle Year
                    if(contractMap.get('Vehicle_Year__c') != NULL){
                        parameter.put('MinVehicleAgeInput', System.Today().Year()-Integer.valueOf(contractMap.get('Vehicle_Year__c')));
                    } else {
                        parameter.put('MinVehicleAgeInput', 0);
                    }
                    parameter.put('MinVehicleMiles', contractMap.get('Sale_Mileage'));
                    parameter.put('UpToAddOnInput', contractMap.get('Up_To_or_Add__c'));
                    parameter.put('RateClassInput', contractMap.get('Class__c'));
                    parameter.put('MinResidenceSqFtInput', contractMap.get('Square_Foot__c') == null ? 0 : contractMap.get('Square_Foot__c'));
                    //Calculate the Residence Age from Year Built
                    if(contractMap.get('Year_Built__c') != NULL){
                        parameter.put('MinResidenceAgeInput', System.Today().Year()-Integer.valueOf(contractMap.get('Year_Built__c')));
                    } else {
                        parameter.put('MinResidenceAgeInput', 0);
                    }
                    parameters.add(parameter);
                    jsonStringOptionsSets = BREServiceHandlerBulkified.runBRCallout(parameters,Date.valueOf(String.valueOf(options.get('Sale_Date'))),'Options_Sets', UtilityClass.BR_TYPE_EX, UtilityClass.IS_INTERNAL_CALL);
                    if(jsonStringOptionsSets != null && jsonStringOptionsSets != '' ) {
                        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonStringOptionsSets);
                        if(jsonMap != NULL){ 
                            List<Object> outputs = (List<Object>) jsonMap.get('outputs');
                            if (outputs != null && !outputs.isEmpty()) {
                                Map<String, Object> firstOutput = (Map<String, Object>) outputs.get(0);
                                results = (Map<String, Object>) firstOutput.get('results');
                                if(results.size() == 0){ 
                                    contractMap.put('MaxTermMonths__c', 0);
                                    contractMap.put('MaxMilesOutput__c',0);
                                    contractMap.put('MaxVehicleMilesOutput__c',0);
                                    contractMap.put('MaxAge__c', 0);
                                    contractMap.put('MaxSquareFoot__c', 0);
                                    contractMap.put('MaxAge__c', 0);
                                    contractMap.put('Premium_Tax_Old__c', 0);
                                    contractMap.put('Options_Cost__c', 0);
                                } 
                                if (results != null ) {
                                    Decimal tempOptionCost = 0;  
                                    if(results.containsKey('MaxTermMonthsOutput')){
                                        contractMap.put('MaxTermMonths__c', (Decimal) results.get('MaxTermMonthsOutput'));
                                    } 
                                    if(results.containsKey('MaxTermMilesOutput')){
                                        contractMap.put('MaxMilesOutput__c',(Decimal) results.get('MaxTermMilesOutput'));
                                    }
                                    if(results.containsKey('MaxVehicleMilesOutput')){
                                        contractMap.put('MaxVehicleMilesOutput__c',(Decimal) results.get('MaxVehicleMilesOutput'));
                                    }
                                    if(results.containsKey('MaxVehicleAgeOutput') && (Decimal) results.get('MaxVehicleAgeOutput') > 0){
                                        contractMap.put('MaxAge__c', (Decimal) results.get('MaxVehicleAgeOutput'));
                                    }
                                    if(results.containsKey('MaxResidenceSqFtOutput')){
                                        contractMap.put('MaxSquareFoot__c', (Decimal) results.get('MaxResidenceSqFtOutput'));
                                    }
                                    if(results.containsKey('MaxResidenceAgeOutput') && (Decimal) results.get('MaxResidenceAgeOutput') > 0){
                                        contractMap.put('MaxAge__c', (Decimal) results.get('MaxResidenceAgeOutput'));
                                    }
                                    if(results.containsKey('PremiumTaxOutput') && contractMap.get('Premium_Tax_Old__c') != NULL){
                                        contractMap.put('Premium_Tax_Old__c' , (Decimal) contractMap.get('Premium_Tax_Old__c') + (Decimal) results.get('PremiumTaxOutput'));
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
                // Assign the Option Cost to Options_Cost__c 
                if(!optionList.isEmpty() && optionCost > 0){
                    contractMap.put('Options_Cost__c', optionCost);
                }
                else if(!optionList.isEmpty() && optionCost <= 0){
                    contractMap.put('Options_Cost__c', 0);
                }
            }
            outMap.put('Contract', contractMap);   
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateSurchargeSetDetails(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        String brType;
        Map<String, Object> parameter = new Map<String, Object>();
        List<Map<String, Object>> parameters = new List<Map<String, Object>>();
        Map<String, Map<String, Object>> vinDetails = new Map<String, Map<String, Object>>();
        List<String> vinNumbers = new List<String>();
        String coverageLevel;
        try {
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            
            //populating coverage level and vin into list variables
            Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
            if(contractMap.get('Coverage_Level__Id') !=null){
                coverageLevelIdSet.add((Id) contractMap.get('Coverage_Level__Id'));
            }
            if(contractMap.get('VIN__c') != NULL) {
                vinNumbers.add(String.valueOf(contractMap.get('VIN__c')));
            }            
            
            //querying coverage level records to populate Name field in parameters map
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            
            if(!vinNumbers.isEmpty()) {
                Map<String, String> driveTrainMapper = UtilityClass.getDriveTrainValue();
                vinDetails = VinUtility.getVinDetails(vinNumbers); 
                system.debug('VinDetails:' +vinDetails);
                system.debug('Vinnumbers:' +String.valueOf(contractMap.get('VIN__c')));
                if(vinDetails.size() > 0) {
                    
                    String vin = String.valueOf(contractMap.get('VIN__c'));
                    String combinedSurcharges = '';
                    //getting all the surcharge names as per the rules mentioned in MRT-393
                   /* String squishVin = VinUtility.createSquishVIN(vin);
                    if(vinDetails.containsKey(squishVin)) { 
                        if(vinDetails.get(squishVin).containsKey('mdl_yr__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c')) != null) {
                            contractMap.put('Vehicle_Year__c', String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c')));
                        }
                        if(vinDetails.get(squishVin).containsKey('mak_nm__c') && String.valueOf(vinDetails.get(squishVin).get('mak_nm__c')) != null) {
                            contractMap.put('Vehicle_Make' , String.valueOf(vinDetails.get(squishVin).get('mak_nm__c')));
                        }
                        if(vinDetails.get(squishVin).containsKey('mdl_desc__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_desc__c')) != null) {
                            contractMap.put('Vehicle_Model__c', String.valueOf(vinDetails.get(squishVin).get('mdl_desc__c')));
                        }
                        
                        if(vinDetails.get(squishVin).containsKey('trk_tng_rat_cd__c') &&
                        vinDetails.get(squishVin).get('trk_tng_rat_cd__c') != null) {
                            if(Boolean.valueOf(vinDetails.get(squishVin).get('trk_tng_rat_cd__c'))) {
                                combinedSurcharges += '1-Ton;';
                                contractMap.put('is_OverOneTon__c', true);
                            }
                        }
                        if(vinDetails.get(squishVin).containsKey('eng_fuel_desc__c') && vinDetails.get(squishVin).get('eng_fuel_desc__c') == 'Diesel') {
                            combinedSurcharges += 'Diesel;';
                            contractMap.put('is_Diesel__c', true);
                        }
                        if(vinDetails.get(squishVin).containsKey('eng_asp_trbl_chgr_cd__c') &&
                        vinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c') != null) {
                            if(Boolean.valueOf(vinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c'))) {
                                combinedSurcharges += 'Turbo;';
                                contractMap.put('is_Turbo__c', true);
                            }
                        }
                        if(vinDetails.get(squishVin).containsKey('drv_typ_cd__c')) {
                            String driveTrain = (String) vinDetails.get(squishVin).get('drv_typ_cd__c');
                            String driveTrainVal = driveTrainMapper.get(driveTrain);
                            if(driveTrainVal == '4WD' || driveTrainVal == '4FD' || driveTrainVal == '4RD') {
                                combinedSurcharges += '4WD;';
                                contractMap.put('Drivetrain__c', '4WD');
                            }
                            if(driveTrainVal == '4AWD' || driveTrainVal == 'AWD') {
                                combinedSurcharges += 'AWD;';
                                contractMap.put('Drivetrain__c', 'AWD');
                            }
                        }
                        if(vinDetails.get(squishVin).containsKey('TRIM_DESC__c') && vinDetails.get(squishVin).get('TRIM_DESC__c') != null) {
                            contractMap.put('Trim__c', (String) vinDetails.get(squishVin).get('TRIM_DESC__c'));
                        }
                        if(vinDetails.get(squishVin).containsKey('eng_asp_sup_chgr_cd__c') &&
                        vinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c') != null) {
                            if(Boolean.valueOf(vinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c'))) {
                                combinedSurcharges += 'Supercharger;';
                                contractMap.put('is_Supercharged__c', true);
                            }
                        }
                        if(vinDetails.get(squishVin).containsKey('BODY_STYLE_DESC__c') &&
                        String.valueOf(vinDetails.get(squishVin).get('BODY_STYLE_DESC__c')) != null) {
                            contractMap.put('Body_Style__c', String.valueOf(vinDetails.get(squishVin).get('BODY_STYLE_DESC__c')));
                        }
                    } */
                    
                    List<String> squishVinList = VinUtility.createAllSquishVINs(vin);
                    
                    for (String squishVin : squishVinList) {
                        if (vinDetails.containsKey(squishVin)) { 
                            if (vinDetails.get(squishVin).containsKey('mdl_yr__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c')) != null) {
                                contractMap.put('Vehicle_Year__c', String.valueOf(vinDetails.get(squishVin).get('mdl_yr__c')));
                            }
                            if (vinDetails.get(squishVin).containsKey('mak_nm__c') && String.valueOf(vinDetails.get(squishVin).get('mak_nm__c')) != null) {
                                contractMap.put('Vehicle_Make', String.valueOf(vinDetails.get(squishVin).get('mak_nm__c')));
                            }
                            if (vinDetails.get(squishVin).containsKey('mdl_desc__c') && String.valueOf(vinDetails.get(squishVin).get('mdl_desc__c')) != null) {
                                contractMap.put('Vehicle_Model__c', String.valueOf(vinDetails.get(squishVin).get('mdl_desc__c')));
                            }
                            
                            if (vinDetails.get(squishVin).containsKey('trk_tng_rat_cd__c') &&
                                vinDetails.get(squishVin).get('trk_tng_rat_cd__c') != null) {
                                    if (Boolean.valueOf(vinDetails.get(squishVin).get('trk_tng_rat_cd__c'))) {
                                        combinedSurcharges += '1-Ton;';
                                        contractMap.put('is_OverOneTon__c', true);
                                    }
                                }
                            
                            if (vinDetails.get(squishVin).containsKey('eng_fuel_desc__c') &&
                                vinDetails.get(squishVin).get('eng_fuel_desc__c') == 'Diesel') {
                                    combinedSurcharges += 'Diesel;';
                                    contractMap.put('is_Diesel__c', true);
                                }
                            
                            if (vinDetails.get(squishVin).containsKey('eng_asp_trbl_chgr_cd__c') &&
                                vinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c') != null) {
                                    if (Boolean.valueOf(vinDetails.get(squishVin).get('eng_asp_trbl_chgr_cd__c'))) {
                                        combinedSurcharges += 'Turbo;';
                                        contractMap.put('is_Turbo__c', true);
                                    }
                                }
                            
                            if (vinDetails.get(squishVin).containsKey('drv_typ_cd__c')) {
                                String driveTrain = (String) vinDetails.get(squishVin).get('drv_typ_cd__c');
                                String driveTrainVal = driveTrainMapper.get(driveTrain);
                                if (driveTrainVal == '4WD' || driveTrainVal == '4FD' || driveTrainVal == '4RD') {
                                    combinedSurcharges += '4WD;';
                                    contractMap.put('Drivetrain__c', '4WD');
                                }
                                if (driveTrainVal == '4AWD' || driveTrainVal == 'AWD') {
                                    combinedSurcharges += 'AWD;';
                                    contractMap.put('Drivetrain__c', 'AWD');
                                }
                            }
                            
                            if (vinDetails.get(squishVin).containsKey('TRIM_DESC__c') &&
                                vinDetails.get(squishVin).get('TRIM_DESC__c') != null) {
                                    contractMap.put('Trim__c', (String) vinDetails.get(squishVin).get('TRIM_DESC__c'));
                                }
                            
                            if (vinDetails.get(squishVin).containsKey('eng_asp_sup_chgr_cd__c') &&
                                vinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c') != null) {
                                    if (Boolean.valueOf(vinDetails.get(squishVin).get('eng_asp_sup_chgr_cd__c'))) {
                                        combinedSurcharges += 'Supercharger;';
                                        contractMap.put('is_Supercharged__c', true);
                                    }
                                }
                            
                            if (vinDetails.get(squishVin).containsKey('BODY_STYLE_DESC__c') &&
                                String.valueOf(vinDetails.get(squishVin).get('BODY_STYLE_DESC__c')) != null) {
                                    contractMap.put('Body_Style__c', String.valueOf(vinDetails.get(squishVin).get('BODY_STYLE_DESC__c')));
                                }
                            
                            // Once a match is found, no need to continue looping further VIN patterns
                            break;
                        }
                    } 

                    
                    //populating combinedSurcharges for Extended miles
                    if(contractMap.get('Sale_Mileage') != null) {
                        if(Integer.valueOf(contractMap.get('Sale_Mileage')) >= 5000 && Integer.valueOf(contractMap.get('Sale_Mileage')) <= 12000) {
                            combinedSurcharges += 'Extended Eligibility 5-12k;';
                        }
                        if(Integer.valueOf(contractMap.get('Sale_Mileage')) > 12000 && Integer.valueOf(contractMap.get('Sale_Mileage')) <= 24000) {
                            combinedSurcharges += 'Extended Eligibility 12-24k;';
                        }
                        if(Integer.valueOf(contractMap.get('Sale_Mileage')) > 24000 && Integer.valueOf(contractMap.get('Sale_Mileage')) <= 35000) {
                            combinedSurcharges += 'Extended Eligibility 24-35k;';
                        }
                        if(Integer.valueOf(contractMap.get('Sale_Mileage')) > 35000 && Integer.valueOf(contractMap.get('Sale_Mileage')) <= 50000) {
                            combinedSurcharges += 'Extended Eligibility 35-50k;';
                        }
                        if(Integer.valueOf(contractMap.get('Sale_Mileage')) > 50000 && Integer.valueOf(contractMap.get('Sale_Mileage')) <= 70000) {
                            combinedSurcharges += 'Extended Eligibility 50-70k;';
                        }
                    }
                    if(String.valueOf(contractMap.get('Product__c')) == 'Health CAR') {
                        combinedSurcharges += 'All Classes Surcharge;';
                    }
                    if(!String.isEmpty(combinedSurcharges)) {
                        combinedSurcharges = combinedSurcharges.Substring(0, combinedSurcharges.length()-1);
                    }
                    Decimal surchargeCost = 0;
                    List<String> surcharges = combinedSurcharges.split(';');
                    
                    //looping over surcharges applicable for particular contract and calling expression set API
                    for(String surcharge : surcharges) {
                        parameter.put('SurchargeNameInput', surcharge);
                        parameter.put('CoverageNameInput', coverageLevelMap.get((Id)contractMap.get('Coverage_Level__Id') ).Name);
                        parameter.put('MinTermMonthsInput', contractMap.get('Term_Months'));
                        parameter.put('MinTermMilesInput', contractMap.get('Term_Miles'));
                        parameter.put('MinVehicleMilesInput', contractMap.get('Sale_Mileage'));
                        if(contractMap.get('Vehicle_Year__c') != NULL){
                            parameter.put('MinVehicleAgeInput', System.Today().Year()-Integer.valueOf(contractMap.get('Vehicle_Year__c')));
                        }
                        parameter.put('RateClassListInput', contractMap.get('Class__c'));
                        parameter.put('SurchargeSetsInput', contractMap.get('Surcharge_Set__c'));
                        parameters.add(parameter);
                        String jsonStringRateSets = BREServiceHandlerBulkified.runBRCallout(parameters,Date.valueOf(String.valueOf(options.get('Sale_Date'))),'Surcharge_Sets', UtilityClass.BR_TYPE_EX, UtilityClass.IS_INTERNAL_CALL);
                        Map<String, Object> jsonMapRateSets = (Map<String, Object>) JSON.deserializeUntyped(jsonStringRateSets);
                        List<Object> outputsSurchargeSets = (List<Object>) jsonMapRateSets.get('outputs');
                        if (outputsSurchargeSets != null && !outputsSurchargeSets.isEmpty()) {
                            Map<String, Object> firstOutput = (Map<String, Object>) outputsSurchargeSets.get(0);
                            if (firstOutput != null) {
                                Map<String, Object> results = (Map<String, Object>) firstOutput.get('results');
                                if(results == null){
                                    contractMap.put('MaxTermMonths__c', 0);
                                    contractMap.put('MaxVehicleMilesOutput__c',0);
                                    contractMap.put('MaxAge__c', 0);
                                    contractMap.put('MaxTermMilesOutput__c', 0);
                                    contractMap.put('Premium_Tax_Old__c', 0);
                                    contractMap.put('Surcharge_Cost__c', 0);
                                    contractMap.put('Surcharges__c', 0);
                                }
                                
                                //if result is returned, populating contract fields
                                if (results != null) {
                                    if(results.containsKey('SurchargeCostOutput')){
                                        surchargeCost += (Decimal) results.get('SurchargeCostOutput');
                                    } 
                                    if(results.containsKey('MaxTermMonthsOutput')){
                                        contractMap.put('MaxTermMonths__c', (Decimal) results.get('MaxTermMonthsOutput'));
                                    }
                                    if(results.containsKey('MaxTermMilesOutput')){
                                        contractMap.put('MaxTermMilesOutput__c', (Decimal) results.get('MaxTermMilesOutput'));
                                    }
                                    if(results.containsKey('MaxVehicleMilesOutput') ){
                                        contractMap.put('MaxVehicleMilesOutput__c', (Decimal) results.get('MaxVehicleMilesOutput'));
                                    }
                                    if(results.containsKey('MaxVehicleAgeOutput')){
                                        contractMap.put('MaxAge__c', (Decimal) results.get('MaxVehicleAgeOutput'));
                                    }
                                    if(results.containsKey('PremiumTaxOutput') && contractMap.get('Premium_Tax_Old__c') != NULL){
                                        contractMap.put('Premium_Tax_Old__c',  (Decimal) contractMap.get('Premium_Tax_Old__c') + (Decimal) results.get('PremiumTaxOutput'));
                                    }
                                }
                            }
                        }
                    }
                    //populating combined surcharge cost for all surachrges related to a contract into field
                    contractMap.put('Surcharge_Cost__c', surchargeCost);
                    if(combinedSurcharges != NULL){
                        contractMap.put('Surcharges__c', combinedSurcharges);
                    }  
                    else{
                        contractMap.put('Surcharges__c', '');
                    }  
                }
                
                outMap.put('Contract', contractMap);
            }
        }
        catch(Exception e) {
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally {
            QDX_Log.publish();
        }
    }
    
    public static void populateAllocationCosts(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        try{
            if (options.get('contract') == null) {
                return;
            }
            Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
            // Create a set to collect unique filter values for bulk querying
            Set<Id> clientSet = new Set<Id>();
            Set<String> productSet = new Set<String>();
            Set<Id> coverageLevelIdSet = new Set<Id>();
            Set<String> coverageLevelSet = new Set<String>();
            Set<String> originalStateSet = new Set<String>();
            Set<String> insuranceCarrierSet = new Set<String>();
            Set<String> optionSet = new Set<String>();
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            
            // Extract necessary values from each contract
            if (contractMap != NULL) {
                if (contractMap.get('Client__c') != null) clientSet.add((Id)contractMap.get('Client__c'));
                if (contractMap.get('Product__c') != null) productSet.add(String.valueOf(contractMap.get('Product__c')));
                if (contractMap.get('Coverage_Level__Id') != null) coverageLevelIdSet.add((Id) contractMap.get('Coverage_Level__Id'));
                if (contractMap.get('Original_State__c') != null) originalStateSet.add(String.valueOf(contractMap.get('Original_State__c')));
                if (contractMap.get('Ins_Carrier__c') != null) insuranceCarrierSet.add(String.valueOf(contractMap.get('Ins_Carrier__c')));
                if (contractMap.get('Option_1__c') != null){
                 	optionSet = new Set<String>(String.valueOf(contractMap.get('Option_1__c')).split(';'));   
                }
            }
            
            //creates map of id and coverage level custom object so that Name can be retrieve.
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  :coverageLevelIdSet]);
            }
            
            for(Id coverageLevelId : coverageLevelMap.keySet()) {
                coverageLevelSet.add(coverageLevelMap.get(coverageLevelId).Name);
            }
            
            clientSet.remove(null);
            String clients = '\'' + String.join(clientSet, '\',\'') + '\''; // Convert to comma-separated string
            
            productSet.remove(null);
            String products = '\'' + String.join(productSet, '\',\'') + '\''; // Convert to comma-separated string
            
            coverageLevelSet.remove(null);
            String coverageLevels = '\'' + String.join(coverageLevelSet, '\',\'') + '\''; // Convert to comma-separated string
            
            originalStateSet.remove(null);
            originalStateSet.add(UtilityClass.INCLUDE_ALL);
            String originalStates = '\'' + String.join(originalStateSet, '\',\'') + '\''; // Convert to comma-separated string
            
            insuranceCarrierSet.remove(null);
            insuranceCarrierSet.add(UtilityClass.INCLUDE_ALL);
            String insuranceCarriers = '\'' + String.join(insuranceCarrierSet, '\',\'') + '\''; // Convert to comma-separated string
            
            optionSet.remove(null);
            optionSet.add(UtilityClass.INCLUDE_ALL);
            String optionValues = '\'' + String.join(optionSet, '\',\'') + '\''; // Convert to comma-separated string
            
            // Bulk query Allocation_Code__c once, instead of multiple times inside the loop
            String query ='SELECT Id, Name, Descriptor__c, Allocation_Amount__c, Client__r.Name, Product__c, Coverage_Level__c, States__c, Insurance_Carrier__c, is_Expense__c, Start_Date__c, End_Date__c, Option__c FROM Allocation_Code__c WHERE ';
            List<String> whereClauses = new List<String>();
            whereClauses.add('Client__c IN ('+clients+')');
            whereClauses.add('Product__c IN ('+products+')');
            whereClauses.add('Coverage_Level__c IN ('+coverageLevels+')');
            whereClauses.add('Insurance_Carrier__c INCLUDES ('+insuranceCarriers+')');
            whereClauses.add('States__c INCLUDES ('+originalStates+')');
            whereClauses.add('Option__c IN ('+optionValues+')');
            
            // Finalize query
            query += String.join(whereClauses, ' AND ');
            List<Allocation_Code__c> allocations = Database.query(query);
            
            // Create a mapping for easy lookup of allocation amounts
            Map<String, List<Allocation_Code__c>> allocationMap = new Map<String, List<Allocation_Code__c>>();
            
            for (Allocation_Code__c alloc : allocations) {
                String key = alloc.Client__c + '-' + alloc.Product__c + '-' + alloc.Coverage_Level__c;
                if (!allocationMap.containsKey(key)) {
                    allocationMap.put(key, new List<Allocation_Code__c>());
                }
                allocationMap.get(key).add(alloc);
            }
            
            // Iterate over contracts and calculate allocation amounts in bulk
            if (contractMap != NULL) {
                String key;
                if(coverageLevelMap != NULL &&  contractMap.get('Client__c') !=  NULL && contractMap.get('Product__c') != NULL && contractMap.get('Coverage_Level__Id') != NULL){
                    key = (Id)contractMap.get('Client__c') + '-' + String.valueOf(contractMap.get('Product__c')) + '-' + coverageLevelMap.get( (Id) contractMap.get('Coverage_Level__Id')).Name ;
                }
                if (allocationMap.containsKey(key)) {
                    Decimal totalProjected = 0;
                    Decimal totalExpense = 0;
                    
                    for (Allocation_Code__c alloc : allocationMap.get(key)) {
                        if((alloc.Start_Date__c <= Date.valueOf(String.valueOf(options.get('Sale_Date'))) 
                           && (alloc.End_Date__c == null || alloc.End_Date__c >= Date.valueOf(String.valueOf(options.get('Sale_Date'))))) && (alloc.States__c.contains(UtilityClass.INCLUDE_ALL) || alloc.States__c.contains(String.valueOf(contractMap.get('Original_State__c')))) && (alloc.Insurance_Carrier__c.contains(UtilityClass.INCLUDE_ALL) || alloc.Insurance_Carrier__c.contains(String.valueOf(contractMap.get('Ins_Carrier__c')))) && 
                          ((String.valueOf(contractMap.get('Option_1__c')) != null && String.valueOf(contractMap.get('Option_1__c')).contains(alloc.Option__c)) || alloc.Option__c.contains(UtilityClass.INCLUDE_ALL)) ) {
                            Decimal allocationAmount;
                            
                            // Return 0 if essential inputs are null
                            if (alloc.Name == null || alloc.Allocation_Amount__c == null) {
                                allocationAmount = 0;
                            }
                            
                            // Case 1: Allocation_Amount__c is a numeric value
                            if (Pattern.matches('\\d+(\\.\\d+)?', alloc.Allocation_Amount__c)) {
                                allocationAmount =  Decimal.valueOf(alloc.Allocation_Amount__c);
                            }
                            
                            // Case 2: Allocation_Amount__c matches Descriptor__c, return policy reserve
                            if (alloc.Allocation_Amount__c == alloc.Descriptor__c) {
                                allocationAmount = (Decimal) (contractMap.get('Reserve__c'));
                            }
                            
                            // Case 3: Allocation_Amount__c starts with 'S' (case-insensitive) and length < 5
                            if (alloc.Allocation_Amount__c.startsWithIgnoreCase('S') && alloc.Allocation_Amount__c.length() < 5) {
                                if (contractMap == null || alloc.Descriptor__c == null) {
                                    QDX_LOG.debug('Null policy or descriptor provided.');
                                    allocationAmount = 0;
                                }
                                
                                // Return values based on the descriptor
                                if (alloc.Descriptor__c == 'Premium Tax') {
                                    allocationAmount = (Decimal) contractMap.get('Premium_Tax_Old__c') != NULL ? (Decimal) contractMap.get('Premium_Tax_Old__c') : 0.0;
                                } else if (alloc.Descriptor__c == 'Seller Commission') {
                                    allocationAmount = (Decimal) contractMap.get('MBI_Seller_Commission__c')!= NULL ? (Decimal) contractMap.get('MBI_Seller_Commission__c') : 0.0;
                                }
                            }
                            
                            // Case 4: Evaluate Allocation_Amount__c as a formula
                            try {
                                // Build the formula using FormulaEval API
                                FormulaEval.FormulaBuilder formulaInstance = Formula.builder()
                                .withType(InsurancePolicy.SObjectType)  // Define context class
                                .withReturnType(FormulaEval.FormulaReturnType.DECIMAL) // Expecting Decimal return type
                                .withFormula(alloc.Allocation_Amount__c); // Formula expression      
                                InsurancePolicy insPolicy = new InsurancePolicy();
                                insPolicy.Reserve__c = contractMap.get('Reserve__c') != NULL ?  (Decimal) contractMap.get('Reserve__c') : 0.0;
                                insPolicy.Options_Cost__c = ( contractMap.get('Options_Cost__c') != NULL ? (Decimal) contractMap.get('Options_Cost__c') : 0.0); 
                                insPolicy.Surcharge_Cost__c = ( contractMap.get('Surcharge_Cost__c') != NULL ? (Decimal) contractMap.get('Surcharge_Cost__c') : 0.0 );
                                insPolicy.Allocation_Expense_Amount__c = ( contractMap.get('Allocation_Expense_Amount__c') != NULL ? (Decimal) contractMap.get('Allocation_Expense_Amount__c'): 0.0 ) ;
                                FormulaEval.FormulaInstance fInstance = formulaInstance.build();
                                Decimal formulaResult = (Decimal)fInstance.evaluate(insPolicy);         
                                allocationAmount =  formulaResult;
                            } catch (Exception formulaException) {
                                QDX_LOG.error('Formula evaluation failed: ' + formulaException.getMessage() +
                                ' at line ' + formulaException.getLineNumber());
                            }
                            if (alloc.is_Expense__c) {
                                totalExpense += allocationAmount;
                            } else {
                                totalProjected += allocationAmount;    
                            }
                        }
                    }
                    
                    // Assign computed values to contract fields
                    contractMap.put('Projected_Allocation_Cost__c' , totalProjected);
                    contractMap.put('Allocation_Expense_Amount__c' , totalExpense);
                    outMap.put('Contract', contractMap);
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
    
    public static void calculateNewDealerCost(Map<String,Object> input, Map<String,Object> outMap, Map<String,Object> options) {
        Map<String, Object> contractMap = (Map<String, Object>) options.get('contract');
        Decimal netDealerCost =  (contractMap.get('Reserve__c') != NULL ?  (Decimal) contractMap.get('Reserve__c') : 0.0)   + ( contractMap.get('Options_Cost__c') != NULL ? (Decimal) contractMap.get('Options_Cost__c') : 0.0) + ( contractMap.get('Surcharge_Cost__c') != NULL ? (Decimal) contractMap.get('Surcharge_Cost__c') : 0.0 ) + ( contractMap.get('Projected_Allocation_Cost__c') != NULL ? (Decimal) contractMap.get('Projected_Allocation_Cost__c'): 0.0 ) ;
        system.debug('Contract Map is'+ contractMap);
        system.debug('NetDealerCost'+netDealerCost);
        system.debug('Reserve cost'+contractMap.get('Reserve__c'));
        system.debug('Options cost'+contractMap.get('Options_Cost__c'));
        system.debug('Surcharge cost'+contractMap.get('Surcharge_Cost__c'));
        system.debug('Projected allocation cost'+contractMap.get('Projected_Allocation_Cost__c'));
        system.debug('allocation cost'+contractMap.get('Allocation_Expense_Amount__c'));
        contractMap.put('Net_Dealer_Cost__c', netDealerCost);
        outMap.put('Contract', contractMap);
    }
}