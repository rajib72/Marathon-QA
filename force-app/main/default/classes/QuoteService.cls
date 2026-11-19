/**
 * REST Resource class for executing quote requests
 * This class exposes a POST endpoint to quote requests
 * and returns a processed response.
 */
@RestResource(UrlMapping='/QuoteRequestService/*')
global class QuoteService {
    private class RateMatrixRowData {
    Map<String, Object> inputData;
    Map<String, Object> outputData;

    RateMatrixRowData(
        Map<String, Object> inputData,
        Map<String, Object> outputData
    ) {
        this.inputData = inputData;
        this.outputData = outputData;
    }
}

private static Map<Id, RateMatrixRowData> rateMatrixRowDataCache =
    new Map<Id, RateMatrixRowData>();
    public static Map<String, Map<String,String>> responseMap = new Map<String, Map<String,String>>();
    public static Map<String, List<Map<String,String>>> responseMapList = new Map<String, List<Map<String,String>>>();
    public static Map<String, String> vehicleMap = new Map<String,String>();
    public static RestRequest request = RestContext.request;

   
    private static Quote_Client_Config__mdt clientConfig;
    
   /**
 * Executes quote request
 * This method is invoked via an HTTP POST request.
 */

 //==========================================>commented by Joyita 6.11.26
   @HttpPost
    global static void processQuoteRequest() {
        // Initialize response objects
        
        RestResponse response = RestContext.response;
        QuoteService.EnduranceRequest requestObj;
        
        String responseStr = '';
        
        try {
            // Deserialize request body to QuoteService.EnduranceRequest object
            requestObj  = (QuoteService.EnduranceRequest) JSON.deserialize(
                request.requestBody.toString(), QuoteService.EnduranceRequest.class
            );

            
           
String requestedUpToOrAddOn = requestObj.UpToorAddOn;

QuoteService.ResponseGenerator successResponseObj;

if (String.isBlank(requestedUpToOrAddOn)) {

    // Generate both UpTo and AddOn quotes
    successResponseObj = generateAllQuoteRequest(requestObj);

} else {

    // Generate only the requested quote type
    successResponseObj =
        generateQuoteRequest(requestObj, requestedUpToOrAddOn);
}

responseStr = JSON.serialize(successResponseObj);


        } catch (Exception e) {
            // populating the error response
            if(requestObj == null) {
                Map<String, Object> tempMap = (Map<String, Object>) JSON.deserializeUntyped(request.requestBody.toString());
                vehicleMap.put('VIN', string.valueOf(tempMap.get('VIN')));
                vehicleMap.put('Vehicle_Mileage_at_Contract_Inception',  string.valueOf(tempMap.get('Vehicle_Mileage_at_Contract_Inception')));
                vehicleMap.put('Original_State',  string.valueOf(tempMap.get('Original_State')));
                vehicleMap.put('Option_1',  string.valueOf(tempMap.get('Option_1')));
                vehicleMap.put('Client',  string.valueOf(tempMap.get('Client')));
                responseStr = generateErrorResponse('Bad Request. Please send request with correct data type.');
            } else if(String.isEmpty(requestObj.VIN) || String.isEmpty(String.valueOf(requestObj.Vehicle_Mileage_at_Contract_Inception)) ||
                String.isEmpty(requestObj.Original_State) || String.isEmpty(requestObj.Client)) {
                responseStr = generateErrorResponse('Null value received for required field');
            } else {
                responseStr = generateErrorResponse(e.getMessage());
            }
            
            //log error
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
            
        } finally {
            // Ensure logs are published regardless of success or failure
            QDX_LOG.publish();
        }
        response.responseBody = Blob.valueOf(responseStr);
    }

    private static QuoteService.ResponseGenerator generateQuoteRequest(
        QuoteService.EnduranceRequest requestObj,
        String upToOrAddOn
    ) {
        requestObj.UpToorAddOn = upToOrAddOn;
        return calculateQuotes(requestObj);
    }

private static QuoteService.ResponseGenerator generateAllQuoteRequest(
    QuoteService.EnduranceRequest requestObj
) {
    String originalUpToOrAddOn = requestObj.UpToorAddOn;

    try {

        // Generate UpTo quotes first
        QuoteService.ResponseGenerator upToResponse =
            generateQuoteRequest(requestObj, 'UpTo');

        System.debug('UPTO RESPONSE STATUS: ' +
            (upToResponse == null ? null : upToResponse.status));

        System.debug('UPTO QUOTE COUNT: ' +
            (upToResponse == null || upToResponse.quotes == null
                ? 0
                : upToResponse.quotes.size()));

       if (upToResponse == null ||
    upToResponse.status != 200 ||
    upToResponse.quotes == null ||
    upToResponse.quotes.isEmpty()) {

    throw new QuoteConfigurationException(
        'Error generating UpTo quotes or no UpTo quotes found.'
    );
}

        // Generate AddOn quotes next
        QuoteService.ResponseGenerator addOnResponse =
            generateQuoteRequest(requestObj, 'AddOn');

        System.debug('ADDON RESPONSE STATUS: ' +
            (addOnResponse == null ? null : addOnResponse.status));

        System.debug('ADDON QUOTE COUNT: ' +
            (addOnResponse == null || addOnResponse.quotes == null
                ? 0
                : addOnResponse.quotes.size()));

        if (addOnResponse == null ||
    addOnResponse.status != 200 ||
    addOnResponse.quotes == null ||
    addOnResponse.quotes.isEmpty()) {

    throw new QuoteConfigurationException(
        'Error generating AddOn quotes or no AddOn quotes found.'
    );
}

        // Combine both responses
        QuoteService.ResponseGenerator combinedResponse =
            new QuoteService.ResponseGenerator();

        combinedResponse.status = 200;
        combinedResponse.error = '';
        combinedResponse.payload = upToResponse.payload;
        combinedResponse.quotes = new List<QuoteService.Quote>();

        if (upToResponse.quotes != null) {
            combinedResponse.quotes.addAll(upToResponse.quotes);
        }

        if (addOnResponse.quotes != null) {
            combinedResponse.quotes.addAll(addOnResponse.quotes);
        }

        System.debug('COMBINED QUOTE COUNT: ' +
            combinedResponse.quotes.size());

        return combinedResponse;

    } finally {
        // Restore the original request value
        requestObj.UpToorAddOn = originalUpToOrAddOn;
    }
}


 /*   
@HttpPost
global static void processQuoteRequest() {

    RestResponse response = RestContext.response;
    EnduranceRequest requestObj;
    String responseStr = '';

    try {

        requestObj = (EnduranceRequest) JSON.deserialize(
            request.requestBody.toString(),
            EnduranceRequest.class
        );

        ResponseGenerator successResponseObj =
            calculateQuotes(requestObj);

        responseStr = JSON.serialize(successResponseObj);

    } catch (Exception e) {

        if (requestObj == null) {

            Map<String, Object> tempMap =
                (Map<String, Object>) JSON.deserializeUntyped(
                    request.requestBody.toString()
                );

            vehicleMap.put('VIN', String.valueOf(tempMap.get('VIN')));
            vehicleMap.put(
                'Vehicle_Mileage_at_Contract_Inception',
                String.valueOf(
                    tempMap.get('Vehicle_Mileage_at_Contract_Inception')
                )
            );
            vehicleMap.put(
                'Original_State',
                String.valueOf(tempMap.get('Original_State'))
            );
            vehicleMap.put(
                'Option_1',
                String.valueOf(tempMap.get('Option_1'))
            );
            vehicleMap.put(
                'Client',
                String.valueOf(tempMap.get('Client'))
            );

            responseStr = generateErrorResponse(
                'Bad Request. Please send request with correct data type.'
            );

        } else if (
            String.isEmpty(requestObj.VIN) ||
            requestObj.Vehicle_Mileage_at_Contract_Inception == null ||
            String.isEmpty(requestObj.Original_State) ||
            String.isEmpty(requestObj.Client) ||
            String.isEmpty(requestObj.UpToorAddOn)
        ) {

            responseStr = generateErrorResponse(
                'Null value received for required field'
            );

        } else {

            responseStr = generateErrorResponse(e.getMessage());
        }

        QDX_LOG.error(
            'Message*****' + e.getMessage() +
            '@@@@@@@@@@Line Number*******' + e.getLineNumber()
        );

    } finally {

        QDX_LOG.publish();
    }

    response.responseBody = Blob.valueOf(responseStr);
}*/


/**
 * Shared calculation method.
 * Executes the existing Auto Decision Matrix logic
 * and returns the calculated quote response.
 */
public static ResponseGenerator calculateQuotes(
    EnduranceRequest requestObj
) {

    if (requestObj == null) {
        throw new QuoteConfigurationException(
            'Quote request cannot be null.'
        );
    }

    // Clear previous calculation data.
    responseMap.clear();
    responseMapList.clear();
    vehicleMap.clear();
    clientConfig = null;

    // Existing client configuration and Decision Matrix processing.
    clientConfig = getAutoClientConfig(requestObj.Client);
    validateAutoClientConfig(clientConfig);

    setup(requestObj);

    // Build the success response.
    ResponseGenerator successResponseObj =
        new ResponseGenerator();

    Payload payload = new Payload();

    List<Quote> quotes = new List<Quote>();

    successResponseObj.status = 200;
    successResponseObj.error = '';

    payload.VIN = vehicleMap.get('VIN');

    payload.Vehicle_Mileage_at_Contract_Inception =
        Integer.valueOf(
            vehicleMap.get('Vehicle_Mileage_at_Contract_Inception')
        );

    payload.Original_State = vehicleMap.get('Original_State');
    payload.Option_1 = vehicleMap.get('Option_1');
    payload.Client = vehicleMap.get('Client');
    payload.UpToorAddOn = requestObj.UpToorAddOn;

    // Build the quotes from the existing Decision Matrix results.
    for (String key : responseMap.keySet()) {

        if (!responseMapList.containsKey(key)) {
            continue;
        }

        for (Map<String, String> innerMap :
             responseMapList.get(key)) {

            String baseReserve =
                innerMap.get('BaseReserve RateCost') == null
                ? '0'
                : innerMap.get('BaseReserve RateCost');

            String surchargeCost =
                responseMap.get(key).get('SurchargeCost') == null
                ? '0'
                : responseMap.get(key).get('SurchargeCost');

            String allocationAmount =
                responseMap.get(key).get('Allocation Amount') == null
                ? '0'
                : responseMap.get(key).get('Allocation Amount');

            Decimal commission = 0;
            Decimal premiumTax = 0;

            if (
                responseMap.get(key).containsKey('Commission') &&
                responseMap.get(key).get('Commission') == 'true' &&
                innerMap.containsKey('Commission RateCost') &&
                Decimal.valueOf(
                    innerMap.get('Commission RateCost')
                ) > 0
            ) {
                commission = Decimal.valueOf(
                    innerMap.get('Commission RateCost')
                );
            }

            if (
                responseMap.get(key).containsKey('Premium Tax') &&
                responseMap.get(key).get('Premium Tax') == 'true' &&
                innerMap.containsKey('PremiumTax RateCost') &&
                Decimal.valueOf(
                    innerMap.get('PremiumTax RateCost')
                ) > 0
            ) {
                premiumTax = Decimal.valueOf(
                    innerMap.get('PremiumTax RateCost')
                );
            }

            Decimal netDealerCost =
                Decimal.valueOf(baseReserve) +
                Decimal.valueOf(surchargeCost) +
                Decimal.valueOf(allocationAmount) +
                commission +
                premiumTax;

            innerMap.put(
                'Net_Dealer_Cost',
                String.valueOf(netDealerCost)
            );

            innerMap.put(
                'Net_Dealer_Cost_Divide_By_12',
                String.valueOf(netDealerCost / 12)
            );

            Quote quote = new Quote();

            quote.Dealer_Program_Id = key;
            quote.Product = responseMap.get(key).get('Product');
            quote.Coverage_Level =
                responseMap.get(key).get('CoverageLevel');

            quote.New_Or_Used =
                responseMap.get(key).get('PurchaseType');

            quote.Contract_Term_Months =
                Integer.valueOf(
                    innerMap.get('TermMonths RateCost')
                );

            quote.Contract_Term_Mileage =
                Integer.valueOf(
                    innerMap.get('TermMiles RateCost')
                );

            quote.Validation_Days =
                Integer.valueOf(
                    responseMap.get(key).get('ValidationDays')
                );

            quote.Validation_Miles =
                Integer.valueOf(
                    responseMap.get(key).get('ValidationMiles')
                );

            quote.Deductible =
                Decimal.valueOf(
                    innerMap.get('Deductible RateCost')
                ).setScale(2, System.RoundingMode.HALF_UP);

            quote.Net_Dealer_Cost =
                netDealerCost.setScale(
                    2,
                    System.RoundingMode.HALF_UP
                );

            quote.Net_Dealer_Cost_Divide_By_12 =
                (netDealerCost / 12).setScale(
                    2,
                    System.RoundingMode.HALF_UP
                );

            quote.Surcharges =
                responseMap.get(key).get('Surcharges');

            quote.Rate_Class =
                innerMap.get('RateClass RateCost');

            quotes.add(quote);
        }
    }

    successResponseObj.payload = payload;
    successResponseObj.quotes = quotes;

    return successResponseObj;
}




    
    public static String generateErrorResponse(String errorMessage) {
        QuoteService.ErrorResponseGenerator errorResponseObj = new QuoteService.ErrorResponseGenerator();
        QuoteService.ErrorPayload errorPayload = new QuoteService.ErrorPayload();
        
        Map<String, Object> tempMap = (Map<String, Object>) JSON.deserializeUntyped(request.requestBody.toString());
        errorPayload.VIN =  string.valueOf(tempMap.get('VIN'));
        errorPayload.Vehicle_Mileage_at_Contract_Inception = tempMap.get('Vehicle_Mileage_at_Contract_Inception');
        errorPayload.Original_State = string.valueOf(tempMap.get('Original_State'));
        errorPayload.Option_1 = string.valueOf(tempMap.get('Option_1'));
        errorPayload.Client = string.valueOf(tempMap.get('Client'));
        errorPayload.UpToorAddOn = string.valueOf(tempMap.get('UpToorAddOn'));
        errorResponseObj.status = 400;
        errorResponseObj.error = errorMessage;
        errorResponseObj.payload = errorPayload;
        errorResponseObj.quotes = new List<QuoteService.Errorquotes>();
        
        return JSON.serialize(errorResponseObj);
    }
    
    private static Quote_Client_Config__mdt getAutoClientConfig(String clientName) {
        if(String.isBlank(clientName)) {
            return null;
        }

        for(Quote_Client_Config__mdt config : Quote_Client_Config__mdt.getAll().values()) {
            if(config.Active__c &&
                config.Auto_Enabled__c &&
                String.isNotBlank(config.Client_Name__c) &&
                config.Client_Name__c.equalsIgnoreCase(clientName)) {
                return config;
            }
        }

        return null;
    }

    private static void validateAutoClientConfig(Quote_Client_Config__mdt config) {
        if(config == null) {
            throw new QuoteConfigurationException('Client configuration not found or Auto quote service is not enabled for client.');
        }

        if(String.isBlank(config.Auto_Dealer_Lookup_Matrix__c)) {
            throw new QuoteConfigurationException('Auto Dealer Lookup Matrix is not configured for client.');
        }

        if(String.isBlank(config.Auto_State_Set_Guide_Matrix__c)) {
            throw new QuoteConfigurationException('Auto State Set Guide Matrix is not configured for client.');
        }

        if(String.isBlank(config.Auto_Coverage_Matrix__c)) {
            throw new QuoteConfigurationException('Auto Coverage Matrix is not configured for client.');
        }
    }

    /**
     * the main setup methods that invokes child methods to populate response map
     */
    public static Void setup(QuoteService.EnduranceRequest requestObj) {
        if(clientConfig == null) {
            clientConfig = getAutoClientConfig(requestObj.Client);
            validateAutoClientConfig(clientConfig);
        }

        //popuate vehicleMap global variable
        //String squishedVin = VinUtility.createSquishVIN(requestObj.VIN);
        List<String> squishVins = VinUtility.createAllSquishVINs(requestObj.VIN);
        String squishedVin = squishVins.isEmpty() ? null : squishVins[0];
        vehicleMap.put('squishVin', squishedVin);
        vehicleMap.put('VIN', requestObj.VIN);
        vehicleMap.put('Vehicle_Mileage_at_Contract_Inception', string.valueOf(requestObj.Vehicle_Mileage_at_Contract_Inception));
        vehicleMap.put('Original_State', requestObj.Original_State);
        vehicleMap.put('Option_1', requestObj.Option_1);
        vehicleMap.put('Client', requestObj.Client);
        
        //query Vin Detail object
        List<Vin_Detail__c> vinDetail = new List<Vin_Detail__c>([SELECT Id, MDL_YR__c, ENG_ASP_TRBL_CHGR_CD__c, ENG_ASP_SUP_CHGR_CD__c,
            ENG_FUEL_DESC__c, DRV_TYP_CD__c FROM Vin_Detail__c WHERE VIN_SIGNI_PATTRN_MASK__c =: squishedVin LIMIT 1]);
        if(!vinDetail.isEmpty()) {
            vehicleMap.put('MakeYear', vinDetail[0].MDL_YR__c);
            vehicleMap.put('Is Turbocharged?', vinDetail[0].ENG_ASP_TRBL_CHGR_CD__c == true ? 'Turbo' : '');
            vehicleMap.put('Is Supercharged?', vinDetail[0].ENG_ASP_SUP_CHGR_CD__c == true ? 'Supercharger' : '');
            vehicleMap.put('Fuel', vinDetail[0].ENG_FUEL_DESC__c);
            String driveTrainVal = (String) vinDetail[0].DRV_TYP_CD__c;
                if(driveTrainVal != null){
                    if(driveTrainVal == '4WD' || driveTrainVal == '4FD' || driveTrainVal == '4RD') {
                        vehicleMap.put('Drivetrain', '4WD');
                    }
                    else if(driveTrainVal == '4AWD' || driveTrainVal == 'AWD') {
                        vehicleMap.put('Drivetrain', 'AWD');
                    }
                }
            
        }
        //call DM methods to populate responseMap global variable
        dealerCodeLookup(requestObj.Client);
        vehicleClassLookup();
        //commented and added by Joyita 6.11.26
        rateCostLookup(requestObj.UpToorAddOn);
     // rateCostLookup();
        stateSetLookup(requestObj.Client);
        surchargeSetLookup();
        callCoverageLevelDM();
        if(clientConfig.Auto_Allocation_Enabled__c) {
            allocationCostLookup(requestObj.Client);
        }
    }
    
    /**
     * queries dealer code lookup DM and populates responseMap
     */
    public static Void dealerCodeLookup(String client) {

List<CalculationMatrix> dealerLookupRec = [
    SELECT Id,
        (SELECT Id
         FROM CalculationMatrixVersions
         WHERE IsEnabled = TRUE
         AND EndDateTime = NULL
         LIMIT 1)
    FROM CalculationMatrix
    WHERE UniqueName = :clientConfig.Auto_Dealer_Lookup_Matrix__c
];

if (dealerLookupRec.isEmpty() ||
    dealerLookupRec[0].CalculationMatrixVersions.isEmpty()) {
    throw new QuoteConfigurationException(
        'Configured Auto Dealer Lookup Matrix or its active version was not found.'
    );
}

String responseBody = ContractUtility.fetchLookupTableRows(
    dealerLookupRec[0].Id,
    dealerLookupRec[0].CalculationMatrixVersions[0].Id
);

        //deserialize the response
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> rows = (List<Object>) jsonMap.get('rows');
        if (rows != null && !rows.isEmpty()) {
            Map<String, String> rowDataFieldsMap = new Map<String, String>();
            for(Object data : rows) {
                Map<String, Object> row = (Map<String, Object>) data;
                Map<String, Object> rowData = (Map<String, Object>) row.get('rowData');
                if(rowData != null) {
                    if(String.valueOf(rowData.get('Client')) == client) {
                        Map<String,String> columntoData = new Map<String, String>();
                        columntoData.put('ClientAllocationTables', String.valueOf(rowData.get('ClientAllocationTables')));
                        columntoData.put('RateSet', String.valueOf(rowData.get('RateSet')));
                        columntoData.put('CoverageLevel', String.valueOf(rowData.get('CoverageLevel')));
                        columntoData.put('ClassGuide', String.valueOf(rowData.get('ClassGuide')));
                        columntoData.put('OptionSets', String.valueOf(rowData.get('OptionSets')));
                        columntoData.put('Product', String.valueOf(rowData.get('Product')));
                        columntoData.put('SurchargeSets', String.valueOf(rowData.get('SurchargeSets')));
                        columntoData.put('StateSet', String.valueOf(rowData.get('StateSet')));
                        
                        responseMap.put(String.valueOf(rowData.get('DealerProgramId')), columntoData);
                        //dealerCodeIdtoDetailsMap.put(String.valueOf(rowData.get('CoverageLevel')) + '#' + String.valueOf(rowData.get('Product')) + '#' + client, String.valueOf(rowData.get('DealerProgramId')));
                    }
                }
            }
        }
    }
    
    /**
     * queries vin class object and populates responseMap
     */
    public static Void vehicleClassLookup() {
        Map<String, String> dealerCodetoClassGuide = new Map<String, String>();
        for(String dealerCode : responseMap.keySet()) {
            dealerCodetoClassGuide.put(dealerCode, responseMap.get(dealerCode).get('ClassGuide'));
        }
        for(VIN_Class__c vinClass : [SELECT Id, Class__c, Class_Guide_Name__c FROM VIN_Class__c WHERE
            Squish_VIN__r.VIN_SIGNI_PATTRN_MASK__c =: vehicleMap.get('squishVin') AND Class_Guide_Name__c IN : dealerCodetoClassGuide.values()]) {
            for(String dealerCode : responseMap.keySet()) {
                if(vinClass.Class_Guide_Name__c == dealerCodetoClassGuide.get(dealerCode)) {
                    responseMap.get(dealerCode).put('class', vinClass.Class__c);
                }
            }
        }
    }
    
    /**
     * queries state set guide DM and populates responseMap
     */
    public static Void stateSetLookup(String client) {
List<CalculationMatrix> state_Set_GuideRec = [
    SELECT Id,
        (SELECT Id
         FROM CalculationMatrixVersions
         WHERE IsEnabled = TRUE
         AND EndDateTime = NULL
         LIMIT 1)
    FROM CalculationMatrix
    WHERE UniqueName = :clientConfig.Auto_State_Set_Guide_Matrix__c
];

if (state_Set_GuideRec.isEmpty() ||
    state_Set_GuideRec[0].CalculationMatrixVersions.isEmpty()) {
    throw new QuoteConfigurationException(
        'Configured Auto State Set Guide Matrix or its active version was not found.'
    );
}

Set<String> matrixNames = new Set<String>();
Map<String, Map<String, String>> uniqueNametoFieldDetails =
    new Map<String, Map<String, String>>();

// Instantiate HTTP request and response objects
String responseBody = ContractUtility.fetchLookupTableRows(
    state_Set_GuideRec[0].Id,
    state_Set_GuideRec[0].CalculationMatrixVersions[0].Id
);
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> rows = (List<Object>) jsonMap.get('rows');
        if (rows != null && !rows.isEmpty()) {
            Map<String, String> rowDataFieldsMap = new Map<String, String>();
            for(String key : responseMapList.keySet()) {
                for(Object data : rows) {
                    Map<String, Object> row = (Map<String, Object>) data;
                    Map<String, Object> rowData = (Map<String, Object>) row.get('rowData');
                    
                    //creates a key value mapping that will be used to populate responseMap
                    if(String.valueOf(rowData.get('Client')) == client) {
                        String matrixName = fetchMetadatabyTableName(String.valueOf(rowData.get('StateSet')), '').Decision_Matrix_Name__c;
                        matrixNames.add(matrixName);
                    }
                }
            }
            //queries state set DMs for each dealer code lookup record
            if(!matrixNames.isEmpty()) {
                Map<String, String> versionIdtoMatrixName = new Map<String, String>();
               for (CalculationMatrix matrixRecord : [
    SELECT Id, UniqueName,
        (SELECT Id
         FROM CalculationMatrixVersions
         WHERE IsEnabled = TRUE
         AND EndDateTime = NULL
         LIMIT 1)
    FROM CalculationMatrix
    WHERE UniqueName IN :matrixNames
]) {
    if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
        throw new QuoteConfigurationException(
            'Configured State Set Decision Matrix ' +
            matrixRecord.UniqueName +
            ' does not have an active version.'
        );
    }

    versionIdtoMatrixName.put(
        matrixRecord.CalculationMatrixVersions[0].Id,
        matrixRecord.UniqueName
    );
}

                Set<String> versionIds = versionIdtoMatrixName != null ? versionIdtoMatrixName.keySet() : null;
                if (!versionIds.isEmpty()) {
                    //iterating over matrix version records
                    for(String versionId : versionIds) {
                        String uniqueName = versionIdtoMatrixName.containsKey(versionId) ? versionIdtoMatrixName.get(versionId) : '';
                        //fetching related matrix rows records
                        for(CalculationMatrixRow matrixRecord : [SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId = : versionId]) {
                            Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                            Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                            
                            if(rowData != null && rowInputData  != null && String.valueOf(rowInputData.get('State')) == vehicleMap.get('Original_State')) {
                                rowDataFieldsMap = new Map<String, String>();
                                rowDataFieldsMap.put('Carrier', String.valueOf(rowData.get('Carrier')));
                                //adding row details per matrix record
                                uniqueNametoFieldDetails.put(uniqueName, rowDataFieldsMap);
                            }
                        }
                    }
                }
            }
            //populate response map
            if(uniqueNametoFieldDetails.size() > 0) {
                for(String key : uniqueNametoFieldDetails.keySet()) {
                    for(String dealerCodeId : responseMapList.keySet()) {
                        responseMap.get(dealerCodeId).putAll(uniqueNametoFieldDetails.get(key));
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
                if(String.isEmpty(coverageLevel)) {
                    obj =  metadataObj;
                } else if(metadataObj.Coverage_Level__c == coverageLevel){
                    obj =  metadataObj;
                }
            }
        }
        return obj;
    }
    
    /**
     * queries rate set guide DM and populates responseMap
     */
    public static Void rateCostLookup(String UpToorAddOn) {
        Map<String, List<String>> dealerCodeDetailsMap = new Map<String, List<String>>();
        Map<String, List<String>> concatinatedDetailsMap = new Map<String, List<String>>();
        //Map<String, Map<String, String>> uniqueNametoFieldDetails = new Map<String, Map<String, String>>();
        for(String key : responseMap.keySet()) {
            String rateSet = responseMap.get(key).get('RateSet');
            String coverageLevel = responseMap.get(key).get('CoverageLevel');
            String matrixName = fetchMetadatabyTableName(rateSet, coverageLevel).Decision_Matrix_Name__c;
            //populates map that stores matrix name for each row on dealer code lookup along with dealer code id as value
            if(dealerCodeDetailsMap.containsKey(matrixName)) {
                dealerCodeDetailsMap.get(matrixName).add(key);
            } else {
                dealerCodeDetailsMap.put(matrixName, new List<String>{key});
            }
            
            String coverageName = responseMap.get(key).get('CoverageLevel');
            String rateClass = responseMap.get(key).get('class');
            String minMiles = vehicleMap.get('Vehicle_Mileage_at_Contract_Inception');
            Decimal minMilesDecimal = minMiles.contains('.') ? Decimal.valueOf(minMiles) : Decimal.valueOf(minMiles + '.0');
            Integer makeYear = Integer.valueOf(vehicleMap.get('MakeYear'));
            String expireType = UpToorAddOn;
            String yearDiff = String.valueOf(System.today().year() - makeYear) + '.0';
            System.debug('===== RATE LOOKUP INPUT =====');
System.debug('UPTO OR ADDON: ' + UpToorAddOn);
System.debug('COVERAGE NAME: ' + coverageName);
System.debug('RATE CLASS: ' + rateClass);
System.debug('MIN MILES: ' + minMilesDecimal);
System.debug('YEAR DIFFERENCE: ' + yearDiff);
System.debug('MATRIX NAME: ' + matrixName);
            
            //creates a key that will be used to fetch the particular record from rate set DM
            String concatinatedStr = coverageName + '#' + rateClass + '#' + expireType + '#' + minMilesDecimal + '#' + yearDiff;
            if(concatinatedDetailsMap.containsKey(matrixName)) {
                concatinatedDetailsMap.get(matrixName).add(concatinatedStr);
            } else {
                concatinatedDetailsMap.put(matrixName, new List<String>{concatinatedStr});
            }
        }
        
       if (!dealerCodeDetailsMap.isEmpty()) {
    Map<String, String> versionIdtoMatrixName =
        new Map<String, String>();

    // Query Rate Set Decision Matrices and active versions
    List<CalculationMatrix> matrixRecordList = [
        SELECT Id, UniqueName,
            (
                SELECT Id
                FROM CalculationMatrixVersions
                WHERE IsEnabled = TRUE
                AND EndDateTime = NULL
                LIMIT 1
            )
        FROM CalculationMatrix
        WHERE UniqueName IN :dealerCodeDetailsMap.keySet()
    ];

    // Validate active versions and populate the map
    for (CalculationMatrix rec : matrixRecordList) {
    if (rec.CalculationMatrixVersions.isEmpty()) {
        throw new QuoteConfigurationException(
            'Rate Set Decision Matrix ' + rec.UniqueName +
            ' does not have an active version.'
        );
    }

    versionIdtoMatrixName.put(
        rec.CalculationMatrixVersions[0].Id,
        rec.UniqueName
    );
}
  if(!versionIdtoMatrixName.isEmpty()) {
                Set<String> versionIds = versionIdtoMatrixName.keySet();
                //iterating over matrix version records
                for(String versionId : versionIds) {
                    List<Map<String, String>> rowDataFieldsMapList = new List<Map<String, String>>();
                    String uniqueName = versionIdtoMatrixName.containsKey(versionId) ? versionIdtoMatrixName.get(versionId) : '';
                    //fetching related matrix rows records

for (CalculationMatrixRow matrixRecord : [
    SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId
    FROM CalculationMatrixRow
    WHERE CalculationMatrixVersionId = :versionId
]) {
    System.debug('CACHE SIZE: ' + rateMatrixRowDataCache.size());
System.debug('CACHE CONTAINS ROW: ' + rateMatrixRowDataCache.containsKey(matrixRecord.Id));
    RateMatrixRowData cachedRow;

    if (rateMatrixRowDataCache.containsKey(matrixRecord.Id)) {
        cachedRow = rateMatrixRowDataCache.get(matrixRecord.Id);
    } else {
        Map<String, Object> rowData =
            (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);

        Map<String, Object> rowInputData =
            (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);

        if (rowData != null && rowInputData != null) {
            cachedRow = new RateMatrixRowData(rowInputData, rowData);
            rateMatrixRowDataCache.put(matrixRecord.Id, cachedRow);
        }
    }

    if (cachedRow != null) {
        Map<String, Object> rowData = cachedRow.outputData;
        Map<String, Object> rowInputData = cachedRow.inputData;

        // Existing filtering logic - unchanged
        List<String> concatinatedValues =
            concatinatedDetailsMap.containsKey(uniqueName)
            ? concatinatedDetailsMap.get(uniqueName)[0].split('#')
            : null;
            System.debug('===== RATE MATRIX ROW CHECK =====');
System.debug('MATRIX UNIQUE NAME: ' + uniqueName);
System.debug('CONCATENATED VALUES: ' + concatinatedValues);
System.debug('ROW INPUT DATA: ' + rowInputData);
System.debug('ROW OUTPUT DATA: ' + rowData);

       
if (concatinatedValues != null) {

    Boolean coverageMatches =
        concatinatedValues[0] == String.valueOf(rowInputData.get('CoverageName'));

    Boolean rateClassMatches =
        concatinatedValues[1] == String.valueOf(rowInputData.get('RateClass'));

    Boolean expireTypeMatches =
        concatinatedValues[2] == String.valueOf(rowInputData.get('ExpireType'));

    Boolean minMilesMatches =
        Integer.valueOf(concatinatedValues[3]) >=
        Integer.valueOf(rowInputData.get('MinMiles'));

    Boolean maxMilesMatches =
        Integer.valueOf(concatinatedValues[3]) <=
        Integer.valueOf(rowData.get('MaxMiles'));

    Boolean minAgeMatches =
        Integer.valueOf(concatinatedValues[4]) >=
        Integer.valueOf(rowInputData.get('MinAge'));

    Boolean maxAgeMatches =
        Integer.valueOf(concatinatedValues[4]) <=
        Integer.valueOf(rowData.get('MaxAge'));

    if (String.valueOf(rowInputData.get('CoverageName')) == 'Elite Plus Used') {
        System.debug('COVERAGE MATCH: ' + coverageMatches);
        System.debug('RATE CLASS MATCH: ' + rateClassMatches);
        System.debug('EXPIRE TYPE MATCH: ' + expireTypeMatches);
        System.debug('MIN MILES MATCH: ' + minMilesMatches);
        System.debug('MAX MILES MATCH: ' + maxMilesMatches);
        System.debug('MIN AGE MATCH: ' + minAgeMatches);
        System.debug('MAX AGE MATCH: ' + maxAgeMatches);
    }

    if (coverageMatches && rateClassMatches && expireTypeMatches &&
        minMilesMatches && maxMilesMatches && minAgeMatches && maxAgeMatches) {

        System.debug('***** RATE MATRIX ROW MATCHED *****');

        Map<String, String> rowDataFieldsMap = new Map<String, String>();

        rowDataFieldsMap.put('MaxAge RateCost', String.valueOf(rowData.get('MaxAge')));
        rowDataFieldsMap.put('MaxMiles RateCost', String.valueOf(rowData.get('MaxMiles')));
        rowDataFieldsMap.put('BaseReserve RateCost', String.valueOf(rowData.get('BaseReserve')));
        rowDataFieldsMap.put('RateCode RateCost', String.valueOf(rowData.get('RateCode')));
        rowDataFieldsMap.put('Commission RateCost', String.valueOf(rowData.get('Commission')));
        rowDataFieldsMap.put('PremiumTax RateCost', String.valueOf(rowData.get('PremiumTax')));
        rowDataFieldsMap.put('ExpiryType RateCost', String.valueOf(rowInputData.get('ExpireType')));
        rowDataFieldsMap.put('TermMonths RateCost', String.valueOf(rowInputData.get('TermMonths')));
        rowDataFieldsMap.put('TermMiles RateCost', String.valueOf(rowInputData.get('TermMiles')));
        rowDataFieldsMap.put('Deductible RateCost', String.valueOf(rowInputData.get('Deductible')));
        rowDataFieldsMap.put('RateClass RateCost', String.valueOf(rowInputData.get('RateClass')));

        System.debug('ROW DATA FIELDS MAP LIST SIZE: ' + rowDataFieldsMapList.size());

        rowDataFieldsMapList.add(rowDataFieldsMap);

        System.debug('ROW DATA FIELDS MAP LIST SIZE: ' + rowDataFieldsMapList.size());
    }
}

    }
}


                    //populating response map
                    if(dealerCodeDetailsMap.containsKey(uniqueName)) {
                        for(String dealerCodeId : dealerCodeDetailsMap.get(uniqueName)) {
                            responseMapList.put(dealerCodeId, rowDataFieldsMapList);
                        }
                    }
                }
            }
        }
    
    }
    
    /**
     * queries surcharge set guide DM and populates responseMap
     */
    public static Void surchargeSetLookup() {
        Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
        Map<String, List<String>> concatinatedDetailsMap = new Map<String, List<String>>();
        for(String key : responseMapList.keySet()) {
            String surchargeSet = responseMap.get(key).get('SurchargeSets');
            String coverageLevel = responseMap.get(key).get('CoverageLevel');
            String matrixName = fetchMetadatabyTableName(surchargeSet, coverageLevel).Decision_Matrix_Name__c;
            matrixName = matrixName == null ? '' : matrixName;
            
            //populates map that stores matrix name for each row on dealer code lookup along with dealer code id as value
            dealerCodeDetailsMap.put(matrixName, key);
            String minMiles = vehicleMap.get('Vehicle_Mileage_at_Contract_Inception');
            Decimal minMilesDecimal = minMiles.contains('.') ? Decimal.valueOf(minMiles) : Decimal.valueOf(minMiles + '.0');
            Integer makeYear = Integer.valueOf(vehicleMap.get('MakeYear'));
            String yearDiff = String.valueOf(System.today().year() - makeYear) + '.0';
            
            //creates a key that will be used to fetch the particular record from surcharge set DM
            String concatinatedStr = coverageLevel + '#' + vehicleMap.get('Is Turbocharged?') + '#' + vehicleMap.get('Is Supercharged?') + '#' + vehicleMap.get('Fuel') + '#' + vehicleMap.get('Drivetrain') + '#' + minMilesDecimal + '#' + yearDiff;
            if(concatinatedDetailsMap.containsKey(matrixName)) {
                concatinatedDetailsMap.get(matrixName).add(concatinatedStr);
            } else {
                concatinatedDetailsMap.put(matrixName, new List<String>{concatinatedStr});
            }
        }
        
        if(!dealerCodeDetailsMap.isEmpty()) {
            Map<String, String> versionIdtoMatrixName = new Map<String, String>();
            //queries the rate set DM for each rate set in dealer code lookup row
            List<CalculationMatrix> matrixRecordList = new List<CalculationMatrix>();
            for (CalculationMatrix matrixRecord : [
    SELECT Id, UniqueName,
        (SELECT Id
         FROM CalculationMatrixVersions
         WHERE IsEnabled = TRUE
         AND EndDateTime = NULL
         LIMIT 1)
    FROM CalculationMatrix
    WHERE UniqueName IN :dealerCodeDetailsMap.keySet()
]) {
    if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
        throw new QuoteConfigurationException(
            'Surcharge Set Decision Matrix ' + matrixRecord.UniqueName +
            ' does not have an active version.'
        );
    }

    versionIdtoMatrixName.put(
        matrixRecord.CalculationMatrixVersions[0].Id,
        matrixRecord.UniqueName
    );
}
            Set<String> versionIds = versionIdtoMatrixName != null ? versionIdtoMatrixName.keySet() : null;
            if (!versionIds.isEmpty()) {
                //iterating over matrix version records
                for(String versionId : versionIds) {
                    Map<String, String> rowDataFieldsMap = new Map<String, String>();
                    List<String> surcharges = new List<String>();
                    Decimal surchargeCost = 0;
                    String uniqueName = versionIdtoMatrixName.containsKey(versionId) ? versionIdtoMatrixName.get(versionId) : '';
                    //fetching related matrix rows records
           for(CalculationMatrixRow matrixRecord : [
    SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId
    FROM CalculationMatrixRow
    WHERE CalculationMatrixVersionId = :versionId
]) {
    Map<String, Object> rowData =
        (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);

    Map<String, Object> rowInputData =
        (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                        //filtering records
                        if(rowData != null && rowInputData != null) {
                            List<String> concatinatedValues = concatinatedDetailsMap.containsKey(uniqueName) ? concatinatedDetailsMap.get(uniqueName)[0].split('#') : null;
                            if(concatinatedValues != null && concatinatedValues[0] == String.valueOf(rowInputData.get('CoverageName')) &&
                                Integer.valueOf(concatinatedValues[5]) >= Integer.valueOf(rowInputData.get('MinVehicleMiles')) && Integer.valueOf(concatinatedValues[5]) <= Integer.valueOf(rowData.get('MaxVehicleMiles')) &&
                                Integer.valueOf(concatinatedValues[6]) >= Integer.valueOf(rowInputData.get('MinVehicleAge')) && Integer.valueOf(concatinatedValues[6]) <= Integer.valueOf(rowData.get('MaxVehicleAge')) &&
                                (String.valueOf(rowInputData.get('SurchargeName')) == concatinatedValues[1] || String.valueOf(rowInputData.get('SurchargeName')) == concatinatedValues[2] ||
                                String.valueOf(rowInputData.get('SurchargeName')) == concatinatedValues[3] || String.valueOf(rowInputData.get('SurchargeName')) == concatinatedValues[4])) {
                                
                                surchargeCost += Decimal.valueOf(String.valueOf(rowData.get('SurchargeCost')));
                                surcharges.add(String.valueOf(rowInputData.get('SurchargeName')));
                                
                            }
                        }
                        //populating response map
                        rowDataFieldsMap.put('Surcharges', String.join(surcharges,';'));
                        rowDataFieldsMap.put('SurchargeCost', String.valueOf(surchargeCost));
                        if(dealerCodeDetailsMap.containsKey(uniqueName)) {
                            responseMap.get(dealerCodeDetailsMap.get(uniqueName)).putAll(rowDataFieldsMap);
                        }
                    }
                }
            }
        }
    }
    
    /**
     * queries coverage level DM and populates responseMap
     */
    public static Void callCoverageLevelDM() {
List<CalculationMatrix> coverageLevelRec = [
    SELECT Id,
        (SELECT Id
         FROM CalculationMatrixVersions
         WHERE IsEnabled = TRUE
         AND EndDateTime = NULL
         LIMIT 1)
    FROM CalculationMatrix
    WHERE UniqueName = :clientConfig.Auto_Coverage_Matrix__c
];

if (coverageLevelRec.isEmpty() ||
    coverageLevelRec[0].CalculationMatrixVersions.isEmpty()) {
    throw new QuoteConfigurationException(
        'Configured Auto Coverage Matrix or its active version was not found.'
    );
}

// Instantiate HTTP request and response objects
String responseBody = ContractUtility.fetchLookupTableRows(
    coverageLevelRec[0].Id,
    coverageLevelRec[0].CalculationMatrixVersions[0].Id
);
        
        Map<String, String> columntoData = new Map<String, String>();
        
        //deserialize response
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> rows = (List<Object>) jsonMap.get('rows');
        if (rows != null && !rows.isEmpty()) {
            Map<String, String> rowDataFieldsMap = new Map<String, String>();
            for(String key : responseMapList.keySet()) {
                String coverageLevel = responseMap.get(key).get('CoverageLevel');
                String Product = responseMap.get(key).get('Product');
                                                
                for(Object data : rows) {
                    Map<String, Object> row = (Map<String, Object>) data;
                    Map<String, Object> rowData = (Map<String, Object>) row.get('rowData');
                    
                    //populate responseMap
                    if(rowData != null) {
                        if(String.valueOf(rowData.get('CoverageLevel')) == coverageLevel && String.valueOf(rowData.get('Product')) == Product) {
                            columntoData.put('ValidationDays', String.valueOf(rowData.get('ValidationDays')));
                            columntoData.put('ValidationMiles', String.valueOf(rowData.get('ValidationMiles')));
                            columntoData.put('PurchaseType', String.valueOf(rowData.get('PurchaseType')));
                            responseMap.get(key).putAll(columntoData);
                        }
                    }
                }
            }
        }
    }
    
    /**
     * queries allocation code object and populates responseMap
     */
    public static void allocationCostLookup(String client) {
        String originalState = vehicleMap.containsKey('Original_State') ? '\'' + vehicleMap.get('Original_State') + '\'' : 'Include All';
        List<String> originalStateList = new List<String>{vehicleMap.containsKey('Original_State') ? vehicleMap.get('Original_State') : 'Include All'};
        String optionsString = vehicleMap.containsKey('Option_1') && vehicleMap.get('Option_1')!=null ? vehicleMap.get('Option_1') : '';
        Set<String> products = new Set<String>();
        Set<String> coverageLevels = new Set<String>();
        Set<String> options = new Set<String>();
        if (optionsString != '') {
            options = new Set<String>(optionsString.split(';'));
        }
        Set<String> carries = new Set<String>();
        Map<String, String> concatinatedDetailsMap = new Map<String, String>();
        String includeAll = 'Include All';
        Date todayDate = System.today();
        List<Account> clientRecord = new List<Account>([SELECT Id FROM Account WHERE Name =: client AND RecordType.DeveloperName = 'Selling_Agency' LIMIT 1]);
        
        //create filter variables
        for(String key : responseMap.keySet()) {
            String product, coverageLevel, carrier;
            product = responseMap.get(key).containsKey('Product') ? responseMap.get(key).get('Product') : '';
            coverageLevel = responseMap.get(key).containsKey('CoverageLevel') ? responseMap.get(key).get('CoverageLevel') : '';
            carrier = responseMap.get(key).containsKey('Carrier') ? responseMap.get(key).get('Carrier') : '';
            products.add(product);
            coverageLevels.add(coverageLevel);
            carries.add('\'' + carrier + '\'');
        }
        
        options.remove(null);
        options.add(UtilityClass.INCLUDE_ALL);
        String optionValues = '\'' + String.join(options, '\',\'') + '\''; // Convert to comma-separated string
        
        
        if(!products.isEmpty() && !coverageLevels.isEmpty() && !carries.isEmpty() && !clientRecord.isEmpty()) {
            //query allocation object record
            client = '\'' + String.escapeSingleQuotes(client) + '\'';
            String insCarrier = String.join(carries, ',');
            if(!originalState.contains('Include All')) {
                originalState += ',\'' + 'Include All' + '\'';
                originalStateList.add('Include All');
            }
            if(!insCarrier.contains('Include All')) {
                insCarrier += ',\'' + 'Include All' + '\'';
            }
            String productVal = '\'' + String.join(new List<String>(products), '\',\'') + '\'';
            String cvgLevel = '\'' + String.join(new List<String>(coverageLevels), '\',\'') + '\'';//String.join(coverageLevels, ',');
            
            String query = 'SELECT Id, Name, Client__c, Client__r.Name, Coverage_Level__c, Descriptor__c, Allocation_Amount__c, Product__c, Option__c, Term_Months__c, States__c, Insurance_Carrier__c ' +
                       'FROM Allocation_Code__c ' +
                       'WHERE Client__r.Name = ' + client + ' ' + 
                       'AND Coverage_Level__c IN (' + cvgLevel + ') ' +
                       'AND Product__c IN (' + productVal + ') ' +
                       'AND States__c INCLUDES (' + originalState + ') ' + 
                       'AND Insurance_Carrier__c INCLUDES (' + insCarrier + ') ' + 
                       'AND Descriptor__c != \'Reserve\' ' +
                       'AND Start_Date__c <= TODAY ' +
                       'AND (End_Date__c = NULL OR End_Date__c >= TODAY) AND Descriptor__c <> NULL';
            
            List<Allocation_Code__c> allocationCodes = Database.query(query);
            if(!allocationCodes.isEmpty()) {
                for(String key : responseMap.keySet()) {
                    String product, coverageLevel, carrier, termMonths;
                    product = responseMap.get(key).containsKey('Product') ? responseMap.get(key).get('Product') : '';
                    coverageLevel = responseMap.get(key).containsKey('CoverageLevel') ? responseMap.get(key).get('CoverageLevel') : '';
                    carrier = responseMap.get(key).containsKey('Carrier') ? responseMap.get(key).get('Carrier') : '';
                    termMonths = responseMap.get(key).containsKey('TermMonths RateCost') ? responseMap.get(key).get('TermMonths RateCost') : '';
                    
                    Decimal allocationAmount = 0;
                    for(Allocation_Code__c code : allocationCodes) {
                        if(code.Term_Months__c != null && code.Term_Months__c.equalsIgnoreCase('Include All') || termMonths == code.Term_Months__c) {
                            if(code.Client__c == clientRecord[0].Id && code.Product__c == product && code.Coverage_Level__c == coverageLevel &&
                                originalStateList.contains(code.States__c) && (code.Insurance_Carrier__c == carrier || code.Insurance_Carrier__c == 'Include All') && 
                                ((optionValues != null && optionValues.contains(code.Option__c)) || code.Option__c.contains(UtilityClass.INCLUDE_ALL)) ){
                                if(Pattern.matches('\\d+(\\.\\d+)?', code.Allocation_Amount__c) || code.Allocation_Amount__c.isNumeric()) {
                                    if(!code.Descriptor__c.equalsIgnoreCase('Seller Commission') || !code.Descriptor__c.equalsIgnoreCase('Premium Tax')) {
                                        allocationAmount += Decimal.valueOf(code.Allocation_Amount__c);
                                    }
                                } else {
                                    if(code.Descriptor__c.equalsIgnoreCase('Seller Commission')) {
                                        concatinatedDetailsMap.put('Commission', 'true');
                                    }
                                    if(code.Descriptor__c.equalsIgnoreCase('Premium Tax')) {
                                        concatinatedDetailsMap.put('Premium Tax', 'true');
                                    }
                                }
                            }
                        }
                    }
                    concatinatedDetailsMap.put('Allocation Amount', String.valueOf(allocationAmount));
                    responseMap.get(key).putAll(concatinatedDetailsMap);
                }
            }
        }
    }
    
    public class QuoteConfigurationException extends Exception {}

    //class that parses request body
    public class EnduranceRequest {
        public String VIN;
        public Integer Vehicle_Mileage_at_Contract_Inception;
        public String Original_State;
        public String Option_1;
        public String Client;
        public String UpToorAddOn;
    }
    
    //class that generates success response
    public class ResponseGenerator {
        public Integer status;
        public String error;
        public Payload payload;
        public Quote[] quotes;
    }
    
    //part of success response
    public class Payload {
        public String VIN;
        public Integer Vehicle_Mileage_at_Contract_Inception;
        public String Original_State;
        public String Option_1;
        public String Client;
        public String UpToorAddOn;
    }
    
    //part of success response
    public class Quote {
        public String Dealer_Program_Id;
        public String Product;
        public String Coverage_Level;
        public String New_Or_Used;
        public Integer Contract_Term_Months;
        public Integer Contract_Term_Mileage;
        public Integer Validation_Days;
        public Integer Validation_Miles;
        public Decimal Deductible;
        public Decimal Net_Dealer_Cost;
        public Decimal Net_Dealer_Cost_Divide_By_12;
        public String Surcharges;
        public String Rate_Class;
    }
    
    //class that generates error response
    public class ErrorResponseGenerator {
        public Integer status;
        public String error;
        public ErrorPayload payload;
        public Errorquotes[] quotes;
    }
    
    //part of error response
    public class ErrorPayload {
        public String VIN;
        public Object Vehicle_Mileage_at_Contract_Inception;
        public String Original_State;
        public String Option_1;
        public String Client;
        public String UpToorAddOn;
    }
    
    //part of error response
    public class Errorquotes {
    }
}