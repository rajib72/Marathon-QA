@RestResource(UrlMapping='/QuoteRequestServiceHome/*')
global class QuoteServiceHome {

    @TestVisible
private static Quote_Client_Config__mdt clientConfig;
    
    public static Map<String, Map<String,String>> responseMap = new Map<String, Map<String,String>>();
    public static Map<String, List<Map<String,String>>> responseMapList = new Map<String, List<Map<String,String>>>();
    public static Map<String, Map<String, Map<String, String>>> dealerOptionCostsByTerm = new Map<String, Map<String, Map<String, String>>>();
    public static Map<String, String> hwMap = new Map<String,String>();
    public static Set<String> stateSetMatrixSet = new Set<String>();
    // Client constant used for client-specific business rules
    
    
    @TestVisible private static String testMatrixNameOverride = '';
    
    public class HWValidationException extends Exception {}
    
    @HttpPost
    global static void processQuoteRequest() {
        RestResponse response = RestContext.response;
        String responseStr = '';
        
        // 1. Declare req outside the try block so it survives into the catch block
        HWRequest req;
        
        try {
            req = (HWRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(), HWRequest.class
            );
            
            
            if(String.isBlank(req.Client) || String.isBlank(req.OriginalState) || String.isBlank(req.ResidenceType)){
                // Explicitly catches NULL or BLANK values
                responseStr = generateErrorResponse('Null value received for required field', req);
                response.responseBody = Blob.valueOf(responseStr);
                return;
            }
            
          clientConfig = getClientConfig(req.Client);

if (clientConfig == null) {
   
    responseStr = generateErrorResponse(
        'Unsupported or inactive client',
        req
    );
    response.responseBody = Blob.valueOf(responseStr);
    return;
}
            
            // Clear previous transaction/test data
responseMap.clear();
responseMapList.clear();
dealerOptionCostsByTerm.clear();
hwMap.clear();
stateSetMatrixSet.clear();

System.debug('===== CLIENT CONFIG =====');
System.debug('Client = ' + clientConfig.Client_Name__c);
System.debug('Active = ' + clientConfig.Active__c);
System.debug('Allocation Enabled = ' + clientConfig.Allocation_Enabled__c);
System.debug('Allow 12 Month Quotes = ' + clientConfig.Allow_12_Month_Quotes__c);
System.debug('Allow M2M = ' + clientConfig.Allow_M2M__c);
System.debug('Dealer Lookup Matrix = ' + clientConfig.Dealer_Lookup_Matrix__c);
System.debug('Coverage Matrix = ' + clientConfig.Coverage_Matrix__c);
System.debug('State Matrix = ' + clientConfig.State_Matrix__c);
System.debug('Default Contract Term = ' + clientConfig.Default_Contract_Term__c);
System.debug('Default Coverage = ' + clientConfig.Default_Coverage__c);
System.debug('Default Validation Days = ' + clientConfig.Default_Validation_Days__c);
System.debug('=========================');

if(!Test.isRunningTest()) {
    setup(req, clientConfig);
}
            
            HWResponse res = new HWResponse();
            res.status = 200;
            res.error = '';
            
            HWPayload payload = new HWPayload();
            payload.Client = req.Client;
            payload.OriginalState = req.OriginalState;
            payload.ResidenceType = req.ResidenceType;
            res.payload = payload;
            
            
            List<HWQuote> quotes = new List<HWQuote>();
            Set<String> uniqueKeys = new Set<String>();
            
            for(String key : responseMap.keySet()){
                if(responseMapList.containsKey(key)){
                    for(Map<String,String> rateRow : responseMapList.get(key)){
                        
                        
                        


                        
                        // Set contract term based on M2M configuration or client default term.
                        
                        Decimal dealerCost;
                        
                        
                        if(String.isNotBlank(rateRow.get('BasePrice'))){
                            dealerCost = Decimal.valueOf(rateRow.get('BasePrice'));
                        }else if(String.isNotBlank(rateRow.get('BaseReserve'))){
                            dealerCost = Decimal.valueOf(rateRow.get('BaseReserve'));
                        }else{
                            dealerCost = 0;
                        }
                        
HWQuote q = new HWQuote();
q.DealerProgramId = key;
q.Product = responseMap.get(key).get('Product');
q.CoverageLevel = responseMap.get(key).get('CoverageLevel');

String coverage = q.CoverageLevel;

if(String.isBlank(coverage)){
    continue;
}


/*************** QUOTE FILTER DEBUG START ***************/

System.debug('==============================================');
System.debug('===== QUOTE FILTER / CMDT CHECK START =====');
System.debug('Client            = ' + req.Client);
System.debug('Original State    = ' + req.OriginalState);
System.debug('Dealer Program    = ' + key);
System.debug('Product           = ' + q.Product);
System.debug('Coverage          = ' + coverage);

String debugRateSet =
    responseMap.get(key).get('RateSet');

System.debug('RateSet           = ' + debugRateSet);


/* Find Decision Matrix from CMDT */

List<DecisionMatrixMapping__mdt> debugMappings =
    fetchAllMetadataMatches(
        debugRateSet,
        coverage
    );

System.debug(
    'CMDT Mapping Count = ' +
    debugMappings.size()
);


for(DecisionMatrixMapping__mdt debugMapping :
    debugMappings){

    System.debug(
        'CMDT Table Name       = ' +
        debugMapping.Table_Name__c
    );

    System.debug(
        'CMDT Coverage Level   = ' +
        debugMapping.Coverage_Level__c
    );

    System.debug(
        'CMDT Decision Matrix  = ' +
        debugMapping.Decision_Matrix_Name__c
    );
}

System.debug('===== QUOTE FILTER / CMDT CHECK END =====');
System.debug('==============================================');

/*************** QUOTE FILTER DEBUG END ***************/
                        
if(
    clientConfig.Allow_M2M__c &&
    q.Product != null &&
    q.Product.toUpperCase().contains('M2M')
){
    q.ContractTermMonths = 1;
}
else{
    q.ContractTermMonths =
        String.isNotBlank(rateRow.get('TermMonths'))
        ? Integer.valueOf(rateRow.get('TermMonths'))
        : Integer.valueOf(
            String.valueOf(clientConfig.Default_Contract_Term__c)
        );
}
                        
                        String valDaysStr =
    responseMap.get(key).get('ValidationDays');

q.ValidationDays =
    String.isNotBlank(valDaysStr)
    ? Integer.valueOf(valDaysStr)
    : Integer.valueOf(
        String.valueOf(
            clientConfig.Default_Validation_Days__c
        )
    );
                        
                        String dedVal = rateRow.get('Deductible');
                        q.Deductible = String.isNotBlank(dedVal) ? Decimal.valueOf(dedVal) : 0;
                        
                        q.DealerCost = dealerCost.setScale(2);
                        if(q.ContractTermMonths != null && q.ContractTermMonths > 0) {
                            q.MonthlyDealerCost = (dealerCost / q.ContractTermMonths).setScale(2);
                        }
                        
                        String termStr = String.valueOf(q.ContractTermMonths);
                        
                        if (dealerOptionCostsByTerm.containsKey(key)) {
                            Map<String, Map<String, String>> termMap = dealerOptionCostsByTerm.get(key);
                            Map<String, String> opts;
                            
                            if (termMap.containsKey(termStr)) {
                                opts = termMap.get(termStr);
                            } else if (termMap.containsKey('36')) {
                                opts = termMap.get('36');
                            } else if (!termMap.values().isEmpty()) {
                                if(termMap.containsKey(termStr))
                                    opts = termMap.get(termStr);
                                
                                else if(termMap.containsKey('36'))
                                    opts = termMap.get('36');
                                
                                else if(termMap.containsKey('1'))
                                    opts = termMap.get('1');
                            }
                            
                            if (opts != null) {
                                q.WaterWellPump         = opts.get('Water Well Pump');
                                q.RefrigeratorIceMaker  = opts.get('Refrigerator Ice Maker');
                                q.StandAloneIceMaker    = opts.get('Stand-Alone Ice Maker');
                                q.SecondaryRefrigerator = opts.get('Secondary Refrigerator');
                                q.SecondaryFreezer      = opts.get('Secondary Freezer');
                                q.SwimmingPool          = opts.get('Swimming Pool');
                                q.Spa                   = opts.get('Spa');
                                q.ClothesWasherDryer    = opts.get('Clothes Washer/Dryer');
                                q.CentralVac            = opts.get('Central Vac');
                                q.GarageDoorOpener      = opts.get('Garage Door Opener');
                            }
                        }
                        
                        String uniqueKey = q.DealerProgramId + '-' + q.CoverageLevel + '-' + q.ContractTermMonths + '-' + q.Deductible;
                        System.debug('Unique Key = ' + uniqueKey);
                        System.debug('Already Exists = ' + uniqueKeys.contains(uniqueKey));
                        
                        if(!uniqueKeys.contains(uniqueKey)){
                            System.debug('============= FINAL QUOTE =============');
                            System.debug('DealerProgramId = ' + q.DealerProgramId);
                            System.debug('Product = ' + q.Product);
                            System.debug('Coverage = ' + q.CoverageLevel);
                            System.debug('TermMonths = ' + q.ContractTermMonths);
                            System.debug('ValidationDays = ' + q.ValidationDays);
                            System.debug('Deductible = ' + q.Deductible);
                            System.debug('DealerCost = ' + q.DealerCost);
                            System.debug('MonthlyDealerCost = ' + q.MonthlyDealerCost);
                            
                            System.debug('WaterWellPump = ' + q.WaterWellPump);
                            System.debug('RefrigeratorIceMaker = ' + q.RefrigeratorIceMaker);
                            System.debug('StandAloneIceMaker = ' + q.StandAloneIceMaker);
                            System.debug('SecondaryRefrigerator = ' + q.SecondaryRefrigerator);
                            System.debug('SecondaryFreezer = ' + q.SecondaryFreezer);
                            System.debug('SwimmingPool = ' + q.SwimmingPool);
                            System.debug('Spa = ' + q.Spa);
                            System.debug('ClothesWasherDryer = ' + q.ClothesWasherDryer);
                            System.debug('CentralVac = ' + q.CentralVac);
                            System.debug('GarageDoorOpener = ' + q.GarageDoorOpener);
                            System.debug('=======================================');
                            quotes.add(q);
                            
                            uniqueKeys.add(uniqueKey);
                        }
                    }
                }
            }
            
            // 2. NEW CHECK: If the user passed bad inputs (like "Single Familys"), quotes will be empty!
            if (quotes.isEmpty()) {
    throw new HWValidationException(
        'No quotes found for the supplied criteria.'
    );
}
            
            res.quotes = quotes;
            System.debug('============= FINAL QUOTES =============');
            System.debug('Total Quotes = ' + quotes.size());
            
            for(HWQuote q : quotes){
                System.debug(JSON.serializePretty(q));
            }
            
            System.debug('========================================');
            responseStr = buildSuccessResponse(res);
            System.debug('============= FINAL RESPONSE =============');
            System.debug(responseStr);
            System.debug('==========================================');
            
        } catch (HWValidationException ve) {
            System.debug('Validation Error = ' + ve.getMessage());
            // Echoes the bad request parameters straight back into the Error JSON
            responseStr = generateErrorResponse(ve.getMessage(), req);
        } catch(Exception e){
            System.debug('Exception = ' + e.getMessage());
            System.debug('Stack Trace = ' + e.getStackTraceString());
            responseStr = generateErrorResponse('An unexpected error occurred during processing.', req);
        }
        
        if(response != null) {
            // Optional: If you want the actual HTTP Status to match the JSON status, you can uncomment the line below:
            response.responseBody = Blob.valueOf(responseStr);
        }
    }

    //Added by Joyita Sarkar 22.10.26
    // ============================================================
// INTERNAL QUOTE RETRIEVAL FOR LWC
// Add immediately after processQuoteRequest()
// and before setup()
// ============================================================
public static List<HWQuote> getQuotesForInternalRequest(
    String client,
    String state,
    String residenceType,
    String product,
    List<String> options
) {
    if (String.isBlank(client) ||
        String.isBlank(state) ||
        String.isBlank(residenceType)) {
        throw new AuraHandledException(
            'Client, State, and Residence Type are required.'
        );
    }

    RestRequest previousRequest = RestContext.request;
    RestResponse previousResponse = RestContext.response;

    try {
        // Prepare an internal request using the existing REST contract.
        HWRequest requestData = new HWRequest();
        requestData.Client = client;
        requestData.OriginalState = state;
        requestData.ResidenceType = residenceType;

        RestRequest internalRequest = new RestRequest();
        internalRequest.requestUri = '/services/apexrest/QuoteRequestServiceHome/';
        internalRequest.httpMethod = 'POST';
        internalRequest.addHeader('Content-Type', 'application/json');
        internalRequest.requestBody = Blob.valueOf(
            JSON.serialize(requestData)
        );

        RestResponse internalResponse = new RestResponse();

        RestContext.request = internalRequest;
        RestContext.response = internalResponse;

        // Reuse the existing Home Warranty quote calculation.
        processQuoteRequest();

        if (internalResponse.responseBody == null) {
            throw new AuraHandledException(
                'Home Warranty quote service returned an empty response.'
            );
        }

        HWResponse responseData = (HWResponse) JSON.deserialize(
            internalResponse.responseBody.toString(),
            HWResponse.class
        );

        if (responseData == null ||
            responseData.quotes == null ||
            responseData.quotes.isEmpty()) {
            String errorMessage =
                responseData != null &&
                String.isNotBlank(responseData.error)
                ? responseData.error
                : 'No Home Warranty quotes were returned.';

            throw new AuraHandledException(errorMessage);
        }

        // Return all calculated quotes if no product filter is supplied.
        List<HWQuote> filteredQuotes = new List<HWQuote>();

        for (HWQuote quote : responseData.quotes) {
            if (quote == null) {
                continue;
            }

            if (String.isBlank(product) ||
                (quote.Product != null &&
                 quote.Product.equalsIgnoreCase(product))) {
                filteredQuotes.add(quote);
            }
        }
//added by Joyita Sarkar 10.11.26
        System.debug('Selected Product = [' + product + ']');
        System.debug('Returned Home Quotes = ' + responseData.quotes.size());

        for (HWQuote quote : responseData.quotes) {
            System.debug(
                'Dealer Program = ' + quote.DealerProgramId +
                ', Returned Product = [' + quote.Product + ']'
            );
        }

        if (filteredQuotes.isEmpty()) {
            throw new AuraHandledException(
                'No Home Warranty quotes were found for product: ' +
                product
            );
        }

        return filteredQuotes;

    } catch (AuraHandledException e) {
        throw e;
    } catch (Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'Internal Home Warranty quote error: ' +
            e.getMessage() + '\n' + e.getStackTraceString()
        );

        throw new AuraHandledException(
            'Unable to retrieve Home Warranty quotes. ' +
            e.getMessage()
        );
    } finally {
        // Restore the caller's REST context.
        RestContext.request = previousRequest;
        RestContext.response = previousResponse;
    }
}
    
public static void setup(
    HWRequest req,
    Quote_Client_Config__mdt clientConfig
){
    hwMap.put('Client', req.Client);
    hwMap.put('OriginalState', req.OriginalState);
    hwMap.put('ResidenceType', req.ResidenceType);

    dealerCodeLookup(
    req.Client,
    clientConfig.Dealer_Lookup_Matrix__c,
    clientConfig.State_Matrix__c
);

   stateSetLookup(
    req,
    clientConfig.Default_Validation_Days__c
);

    callCoverageLevelDM(
        clientConfig.Coverage_Matrix__c
    );

    rateCostLookupHW();

    optionsCostLookupHW();

    if(clientConfig.Allocation_Enabled__c){
        allocationCostLookup(req.Client);
    }
}
    
private static Quote_Client_Config__mdt getClientConfig(String clientName) {
    if (String.isBlank(clientName)) {
        return null;
    }

    for (Quote_Client_Config__mdt config :
         Quote_Client_Config__mdt.getAll().values()) {

        System.debug('Requested Client Name: [' + clientName + ']');
        System.debug('Metadata Developer Name: ' + config.DeveloperName);
        System.debug('Metadata Client Name: [' + config.Client_Name__c + ']');
        System.debug('Metadata Active: ' + config.Active__c);

        if (config.Active__c &&
            String.isNotBlank(config.Client_Name__c) &&
            config.Client_Name__c.equalsIgnoreCase(clientName)) {
            return config;
        }
    }

    return null;
}

 
    
    
    // DEALER LOOKUP
public static void dealerCodeLookup(
    String client,
    String dealerLookupMatrixName,
    String stateMatrixName
){
    List<CalculationMatrix> dealerLookupRec = [
        SELECT Id,
            (
                SELECT Id
                FROM CalculationMatrixVersions
                WHERE IsEnabled = TRUE
                AND EndDateTime = NULL
                LIMIT 1
            )
        FROM CalculationMatrix
        WHERE UniqueName = :dealerLookupMatrixName
    ];

    if (
    dealerLookupRec.isEmpty() ||
    dealerLookupRec[0].CalculationMatrixVersions.isEmpty()
) {
    throw new HWValidationException(
        'Dealer Lookup Matrix is missing or has no active version: '
        + dealerLookupMatrixName
    );
}

    String responseBody =
        ContractUtility.fetchLookupTableRows(
            dealerLookupRec[0].Id,
            dealerLookupRec[0].CalculationMatrixVersions[0].Id
        );

    Map<String, Object> jsonMap =
        (Map<String, Object>) JSON.deserializeUntyped(responseBody);

    List<Object> rows =
        (List<Object>) jsonMap.get('rows');

    for(Object data : rows){

        Map<String, Object> row =
            (Map<String, Object>) data;

        Map<String, Object> rowData =
            (Map<String, Object>) row.get('rowData');

       String matrixClient = rowData.get('Client') == null
    ? ''
    : String.valueOf(rowData.get('Client')).trim();

if (matrixClient.equalsIgnoreCase(
    client == null ? '' : client.trim()
)) {

            String dealerId =
                String.valueOf(rowData.get('DealerProgramId'));

            String coverageLvl =
                String.valueOf(rowData.get('CoverageLevel'));

            String rateSet =
                String.valueOf(rowData.get('RateSet'));

            String optionSet =
                String.valueOf(rowData.get('OptionSets'));

            Map<String,String> colMap =
                new Map<String,String>();

            colMap.put(
                'Product',
                String.valueOf(rowData.get('Product'))
            );

            colMap.put(
                'CoverageLevel',
                coverageLvl
            );

            colMap.put(
                'RateSet',
                rateSet
            );

            colMap.put(
                'OptionSets',
                optionSet
            );

            System.debug(
                '===== STATE MATRIX CONFIG CHECK ====='
            );

            System.debug(
                'Client = ' + client
            );

            // CHANGED: use method parameter instead of global clientConfig
            System.debug(
                'Configured State Matrix = ' + stateMatrixName
            );

            System.debug(
                'Dealer Matrix StateSet = ' + rowData.get('StateSet')
            );

            System.debug(
                '===================================='
            );

            String stateSetUniqueName = stateMatrixName;

            colMap.put(
                'StateSet',
                stateSetUniqueName
            );

            stateSetMatrixSet.add(
                stateSetUniqueName
            );

            responseMap.put(
                dealerId,
                colMap
            );

            System.debug(
                '================ DEALER LOOKUP ================'
            );

            System.debug(
                'DealerProgramId = ' + dealerId
            );

            System.debug(
                'Product = ' + colMap.get('Product')
            );

            System.debug(
                'Coverage = ' + coverageLvl
            );

            System.debug(
                'RateSet = ' + rateSet
            );

            System.debug(
                'OptionSet = ' + optionSet
            );

            System.debug(
                'StateSet = ' + stateSetUniqueName
            );

            System.debug(
                '==============================================='
            );
        }
    }
}
    
    // OPTIONS LOOKUP
    public static void optionsCostLookupHW() {
        Map<String, List<String>> dealerCodeDetailsMap = new Map<String, List<String>>();
        
        for(String key : responseMapList.keySet()) {
            String optionSet = responseMap.get(key).get('OptionSets');
            

            String coverageLevel = responseMap.get(key).get('CoverageLevel');
                        System.debug('===== OPTION SOURCE CHECK =====');
System.debug('Client = ' + clientConfig.Client_Name__c);
System.debug('Dealer Program = ' + key);
System.debug('Option Set = ' + optionSet);
System.debug('Coverage Level = ' + coverageLevel);
System.debug('================================');
            
            List<DecisionMatrixMapping__mdt> mdts = fetchAllMetadataMatches(optionSet, coverageLevel);
            
            for(DecisionMatrixMapping__mdt mdt : mdts) {
                String matrixName = mdt.Decision_Matrix_Name__c;
                if (String.isNotBlank(matrixName)) {
                    if (!dealerCodeDetailsMap.containsKey(matrixName)) {
                        dealerCodeDetailsMap.put(matrixName, new List<String>());
                    }
                    dealerCodeDetailsMap.get(matrixName).add(key);
                }
            }
        }
        
        if(!dealerCodeDetailsMap.isEmpty()) {
            Map<String, String> versionIdtoMatrixName = new Map<String, String>();
            
            for(CalculationMatrix matrixRecord : [
                SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1) 
                FROM CalculationMatrix WHERE UniqueName IN :dealerCodeDetailsMap.keySet()
            ]) {
                if (!matrixRecord.CalculationMatrixVersions.isEmpty()) {
                    versionIdtoMatrixName.put(matrixRecord.CalculationMatrixVersions[0].Id, matrixRecord.UniqueName);
                }
            }
            
            Set<String> versionIds = versionIdtoMatrixName.keySet();
            if (!versionIds.isEmpty()) {
                for(CalculationMatrixRow matrixRecord : [
                    SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId 
                    FROM CalculationMatrixRow WHERE CalculationMatrixVersionId IN :versionIds
                ]) {
                    String uniqueName = versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId);
                    Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.OutputData);
                    Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(matrixRecord.InputData);
                    
                    if(rowData != null && rowInputData != null && rowInputData.containsKey('OptionName')) {
                       String optionName = String.valueOf(rowInputData.get('OptionName'));

String defaultTerm =
    String.valueOf(clientConfig.Default_Contract_Term__c);

String term =
    rowInputData.containsKey('MinTermMonths')
    ? String.valueOf(rowInputData.get('MinTermMonths'))
    : defaultTerm;

System.debug('===== OPTION TERM CONFIG =====');
System.debug('Option Name = ' + optionName);
System.debug('Matrix MinTermMonths = ' + rowInputData.get('MinTermMonths'));
System.debug('Configured Default Contract Term = ' + defaultTerm);
System.debug('Final Option Term = ' + term);
System.debug('==============================');
                        
                        Decimal optionCost = rowData.get('OptionCost') != null ? Decimal.valueOf(String.valueOf(rowData.get('OptionCost'))) : 0;
                        Decimal premiumTax = rowData.get('PremiumTax') != null ? Decimal.valueOf(String.valueOf(rowData.get('PremiumTax'))) : 0;
                        Decimal obligorTax = rowData.get('ObligorTax') != null ? Decimal.valueOf(String.valueOf(rowData.get('ObligorTax'))) : 0;
                        
                        Decimal totalCost = optionCost + premiumTax + obligorTax;
                        String costStr = String.valueOf(totalCost.setScale(2));
                        
                        List<String> dealerCodes = dealerCodeDetailsMap.get(uniqueName);
                        if (dealerCodes != null) {
                            for (String dCode : dealerCodes) {
                                if (!dealerOptionCostsByTerm.containsKey(dCode)) {
                                    dealerOptionCostsByTerm.put(dCode, new Map<String, Map<String, String>>());
                                }
                                if (!dealerOptionCostsByTerm.get(dCode).containsKey(term)) {
                                    dealerOptionCostsByTerm.get(dCode).put(term, new Map<String, String>());
                                }
                                dealerOptionCostsByTerm.get(dCode).get(term).put(optionName, costStr);
                            }
                        }
                    }
                }
            }
        }
    }
    
    // RATE MATRIX
    public static void rateCostLookupHW(){
        Map<String, List<String>> dealerCodeToMatrix = new Map<String, List<String>>();
        
       for(String key : responseMap.keySet()){

    String rateSet =
        responseMap.get(key).get('RateSet');

    String coverage =
        responseMap.get(key).get('CoverageLevel');

    System.debug('================ RATE MATRIX MAPPING ================');
    System.debug('Dealer Code = ' + key);
    System.debug('RateSet = ' + rateSet);
    System.debug('Coverage = ' + coverage);

    List<DecisionMatrixMapping__mdt> mdts =
        fetchAllMetadataMatches(rateSet, coverage);

    System.debug('CMDT Mapping Count = ' + mdts.size());

    if(mdts.isEmpty()){
        System.debug(
            'NO DecisionMatrixMapping found for RateSet='
            + rateSet
            + ' Coverage='
            + coverage
        );
        continue;
    }

    String matrixName;

    for(DecisionMatrixMapping__mdt mdt : mdts){

        System.debug(
            'CMDT Mapping -> DeveloperName='
            + mdt.DeveloperName
            + ' | Table='
            + mdt.Table_Name__c
            + ' | Coverage='
            + mdt.Coverage_Level__c
            + ' | Matrix='
            + mdt.Decision_Matrix_Name__c
        );

        if(String.isNotBlank(mdt.Decision_Matrix_Name__c)){
            matrixName = mdt.Decision_Matrix_Name__c;
            break;
        }
    }

    if(String.isBlank(matrixName)){
        System.debug(
            'NO Decision Matrix Name found for RateSet='
            + rateSet
            + ' Coverage='
            + coverage
        );
        continue;
    }

    if(Test.isRunningTest() &&
       String.isNotBlank(testMatrixNameOverride)){

        matrixName = testMatrixNameOverride;
    }

    System.debug(
        'FINAL RATE MATRIX SELECTED = '
        + matrixName
    );

    if(!dealerCodeToMatrix.containsKey(matrixName)){
        dealerCodeToMatrix.put(
            matrixName,
            new List<String>()
        );
    }

    dealerCodeToMatrix.get(matrixName).add(key);
}
        
        if(dealerCodeToMatrix.isEmpty()) return;
        
        for(CalculationMatrix matrix : [
            SELECT Id, UniqueName, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1)
            FROM CalculationMatrix WHERE UniqueName IN :dealerCodeToMatrix.keySet()
        ]){
            if (matrix.CalculationMatrixVersions.isEmpty()) continue;
            String versionId = matrix.CalculationMatrixVersions[0].Id;
            
            List<CalculationMatrixRow> matrixRows = [
                SELECT InputData, OutputData FROM CalculationMatrixRow WHERE CalculationMatrixVersionId = :versionId
            ];
            
            for(String dealerCode : dealerCodeToMatrix.get(matrix.UniqueName)){
                System.debug('********************************');
                System.debug('Rate Matrix Name = ' + matrix.UniqueName);
                System.debug('********************************');
                List<Map<String,String>> rowList = new List<Map<String,String>>();
                String coverage = responseMap.get(dealerCode).get('CoverageLevel');
                String residence = hwMap.get('ResidenceType');
                
                for(CalculationMatrixRow row : matrixRows){
                    Map<String,Object> input = (Map<String,Object>)JSON.deserializeUntyped(row.InputData);
                    Map<String,Object> output = (Map<String,Object>)JSON.deserializeUntyped(row.OutputData);
                    
String inputCoverage = input.get('CoverageName') == null
    ? ''
    : String.valueOf(input.get('CoverageName')).trim();

String inputRes = input.get('ResidenceType') == null
    ? ''
    : String.valueOf(input.get('ResidenceType'))
        .replace(' ', '')
        .toLowerCase();
                    String reqCoverage = coverage != null ? coverage.trim() : '';
                    String reqRes = residence != null ? residence.replace(' ','').toLowerCase() : '';
                    
                    if(inputCoverage.equalsIgnoreCase(reqCoverage) && inputRes.equalsIgnoreCase(reqRes)){
                        System.debug('---------------------------');
                        System.debug('Coverage = ' + inputCoverage);
                        System.debug('Residence = ' + inputRes);
                        System.debug('TermMonths = ' + input.get('TermMonths'));
                        System.debug('InputData = ' + row.InputData);
                        Map<String,String> rateRow = new Map<String,String>();
                        rateRow.put('BaseReserve', String.valueOf(output.get('BaseReserve')));
                        rateRow.put('BasePrice', String.valueOf(output.get('BasePrice')));
                        rateRow.put('MaxAge', String.valueOf(output.get('MaxAge')));
                        rateRow.put('MaxMiles', String.valueOf(output.get('MaxUnit')));
                        rateRow.put('RateCode', String.valueOf(output.get('RateCode')));
                        rateRow.put('Commission', String.valueOf(output.get('Commission')));
                        rateRow.put('PremiumTax', String.valueOf(output.get('PremiumTax')));
                        rateRow.put('Deductible', String.valueOf(input.get('Deductible')));
                        rateRow.put('ExpireType', String.valueOf(input.get('ExpireType')));
                        rateRow.put('TermMiles', String.valueOf(input.get('TermMiles')));
                        rateRow.put('RateClass', String.valueOf(input.get('RateClass')));
                        rateRow.put('TermMonths', String.valueOf(input.get('TermMonths')));
                        System.debug('Insurance Carrier from hwMap = ' + hwMap.get('InsuranceCarrier'));
                        rateRow.put('InsuranceCarrier', hwMap.get('InsuranceCarrier'));
                        System.debug('Coverage = ' + inputCoverage);
                        System.debug('TermMonths = ' + input.get('TermMonths'));
                        System.debug('Product = ' + responseMap.get(dealerCode).get('Product'));
                        rowList.add(rateRow);
                    }
                }
                responseMapList.put(dealerCode, rowList);
            }
        }
    }
    
   public static void callCoverageLevelDM(
    String coverageMatrixName
){
    if(String.isBlank(coverageMatrixName)){
    throw new HWValidationException(
        'Coverage Matrix is not configured for client.'
    );
}
        List<CalculationMatrix> coverageRec = [
            SELECT Id, (SELECT Id FROM CalculationMatrixVersions WHERE IsEnabled = TRUE AND EndDateTime = NULL LIMIT 1)
            FROM CalculationMatrix
WHERE UniqueName = :coverageMatrixName
        ];
        
        if (
    coverageRec.isEmpty() ||
    coverageRec[0].CalculationMatrixVersions.isEmpty()
) {
    throw new HWValidationException(
        'Coverage Matrix is missing or has no active version: '
        + coverageMatrixName
    );
}
        String responseBody = ContractUtility.fetchLookupTableRows(coverageRec[0].Id, coverageRec[0].CalculationMatrixVersions[0].Id);
    System.debug(
    '===== RAW OPTION MATRIX RESPONSE ====='
);

System.debug(responseBody);

System.debug(
    '======================================'
);
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> rows = (List<Object>) jsonMap.get('rows');
        
        for(String key : responseMap.keySet()){
            String coverage = responseMap.get(key).get('CoverageLevel');
            for(Object data : rows){
                Map<String, Object> row = (Map<String, Object>) data;
                Map<String, Object> rowData = (Map<String, Object>) row.get('rowData');
                if(String.valueOf(rowData.get('CoverageLevel')) == coverage){
                    responseMap.get(key).put('ValidationDays', String.valueOf(rowData.get('ValidationDays')));
                    
                    System.debug('============= COVERAGE DM =============');
                    System.debug('DealerProgramId = ' + key);
                    System.debug('Coverage = ' + coverage);
                    System.debug('ValidationDays = ' + rowData.get('ValidationDays'));
                    System.debug('======================================');
                }
            }
        }
    }
    
    public static void allocationCostLookup(String client){
        
        List<Account> acc = [
            SELECT Id
            FROM Account
            WHERE Name = :client
            LIMIT 1
        ];
        
        if(acc.isEmpty()) return;
        
        List<Allocation_Code__c> codes = [
            SELECT Product__c,
            Coverage_Level__c,
            Allocation_Amount__c,
            Option__c,
            Descriptor__c,
            Term_Months__c,
            Insurance_Carrier__c,
            Start_Date__c,
            End_Date__c,
            Allocation_Type__c,
            Refundable__c
            FROM Allocation_Code__c
            WHERE Client__c = :acc[0].Id
            AND Start_Date__c <= TODAY
            AND (End_Date__c = NULL OR End_Date__c >= TODAY)
        ];
        
        System.debug('Total Allocation Records = ' + codes.size());
        
        for(String key : responseMap.keySet()){
            
            if(!responseMapList.containsKey(key)){
                continue;
            }
            
            for(Map<String,String> rateRow : responseMapList.get(key)){
                
                Decimal optionCost = 0;
                
                String quoteProduct  = responseMap.get(key).get('Product');
                String quoteCoverage = responseMap.get(key).get('CoverageLevel');
                String quoteTerm     = rateRow.get('TermMonths');
                String quoteCarrier  = rateRow.get('InsuranceCarrier');
                System.debug('================ CURRENT QUOTE ================');
                System.debug('Quote Product  = ' + quoteProduct);
                System.debug('Quote Coverage = ' + quoteCoverage);
                System.debug('Quote Term     = ' + quoteTerm);
                System.debug('Quote Carrier  = ' + quoteCarrier);
                System.debug('===============================================');
                for(Allocation_Code__c code : codes){
                    System.debug('---------------- Allocation Record ----------------');
                    System.debug('Descriptor = ' + code.Descriptor__c);
                    System.debug('Product    = ' + code.Product__c);
                    System.debug('Coverage   = ' + code.Coverage_Level__c);
                    System.debug('Term       = ' + code.Term_Months__c);
                    System.debug('Carrier    = ' + code.Insurance_Carrier__c);
                    System.debug('Amount     = ' + code.Allocation_Amount__c);
                    
                    if(code.Product__c != quoteProduct){
                        
                        System.debug(
                            'Skipped Product -> ' +
                            code.Descriptor__c
                        );
                        
                        continue;
                    }
                    if(code.Coverage_Level__c != quoteCoverage){
                        
                        System.debug(
                            'Skipped Coverage -> ' +
                            code.Descriptor__c
                        );
                        
                        continue;
                    }
                    
                    String allocationTerm = String.valueOf(code.Term_Months__c);
                    
                    Boolean termMatched =
                        allocationTerm.equalsIgnoreCase(quoteTerm) ||
                        allocationTerm.equalsIgnoreCase('Include All');
                    
                    if(!termMatched){
                        
                        System.debug(
                            'Skipped Term -> ' +
                            code.Descriptor__c
                        );
                        
                        continue;
                    }
                    
                    Boolean carrierMatched = false;
                    
                    if(String.isBlank(code.Insurance_Carrier__c)
                       || code.Insurance_Carrier__c.trim().equalsIgnoreCase('Include All')){
                           
                           carrierMatched = true;
                           
                       }else{
                           
                           List<String> carriers = code.Insurance_Carrier__c.split(';');
                           
                           for(String carrier : carriers){
                               
                               if(carrier.trim().equalsIgnoreCase(quoteCarrier)){
                                   carrierMatched = true;
                                   break;
                               }
                           }
                       }
                    System.debug('Quote Carrier      = ' + quoteCarrier);
                    System.debug('Allocation Carrier = ' + code.Insurance_Carrier__c);
                    System.debug('Carrier Matched    = ' + carrierMatched);
                    
                    if(!carrierMatched){
                        
                        System.debug(
                            'Skipped Carrier -> ' +
                            code.Descriptor__c
                        );
                        
                        continue;
                    }
                    
                
                    
                    String amount = String.valueOf(code.Allocation_Amount__c);
                    
                    if(String.isNotBlank(amount)){
                        
                        amount = amount.replace('$','')
                            .replace('S','')
                            .trim();
                    }
                    
Decimal allocationAmount = 0;

if(code.Descriptor__c.equalsIgnoreCase('Premium Tax')){

    if(String.isNotBlank(rateRow.get('PremiumTax'))){
        allocationAmount =
            Decimal.valueOf(rateRow.get('PremiumTax'));
    }

}
else if(code.Descriptor__c.equalsIgnoreCase('Seller Commission')){

    if(String.isNotBlank(rateRow.get('Commission'))){
        allocationAmount =
            Decimal.valueOf(rateRow.get('Commission'));
    }

}
else{

    String allocationAmountStr =
        String.valueOf(code.Allocation_Amount__c);

    if(String.isNotBlank(allocationAmountStr)){

        allocationAmountStr =
            allocationAmountStr.replace('$','')
                               .replace('S','')
                               .trim();
    }

if(String.isNotBlank(allocationAmountStr)){

    try{

        allocationAmount =
            Decimal.valueOf(allocationAmountStr);

    }catch(Exception e){

        System.debug(
            'Unable to parse Allocation Amount = '
            + allocationAmountStr
        );

        allocationAmount = 0;
    }
}
}


if(
    !code.Descriptor__c.equalsIgnoreCase('Seller Commission')
    &&
    !code.Descriptor__c.equalsIgnoreCase('Reserve')
){
    System.debug(
'Matched Id = ' + code.Id +
' | Descriptor = ' + code.Descriptor__c +
' | Amount = ' + allocationAmount +
' | Term = ' + code.Term_Months__c +
' | Carrier = ' + code.Insurance_Carrier__c
);

    optionCost += allocationAmount;
}

System.debug(
    'MATCHED -> '
    + code.Descriptor__c
    + ' = '
    + allocationAmount
);
                }
                
                Decimal baseReserve = 0;
                
                if(String.isNotBlank(rateRow.get('BaseReserve'))){
                    baseReserve = Decimal.valueOf(rateRow.get('BaseReserve'));
                }
                
                Decimal basePrice = 0;
                
                if(String.isNotBlank(rateRow.get('BasePrice'))){
                    basePrice = Decimal.valueOf(rateRow.get('BasePrice'));
                }
                
                Decimal dealerCostBase =
                    baseReserve > 0 ? baseReserve : basePrice;
                
                Decimal finalDealerCost =
                    dealerCostBase + optionCost;
                
                System.debug('BaseReserve = ' + baseReserve);
                System.debug('Allocation = ' + optionCost);
                System.debug('DealerCost = ' + finalDealerCost);
                
                rateRow.put(
                    'BasePrice',
                    String.valueOf(finalDealerCost)
                );
            }
        }
    }
    // MULTI-METADATA FETCH
public static List<DecisionMatrixMapping__mdt> fetchAllMetadataMatches(
    String tableName,
    String coverageLevel
) {
    List<DecisionMatrixMapping__mdt> matches =
        new List<DecisionMatrixMapping__mdt>();

    System.debug('===== DECISION MATRIX LOOKUP START =====');
    System.debug('Table Name = ' + tableName);
    System.debug('Coverage Level = ' + coverageLevel);

    for(DecisionMatrixMapping__mdt mdt :
        DecisionMatrixMapping__mdt.getAll().values()){

        if(mdt.Table_Name__c == tableName &&
           mdt.Coverage_Level__c == coverageLevel){

            matches.add(mdt);

            System.debug(
                'MATCH FOUND -> ' +
                'DeveloperName=' + mdt.DeveloperName +
                ', Table_Name=' + mdt.Table_Name__c +
                ', Coverage_Level=' + mdt.Coverage_Level__c +
                ', Decision_Matrix_Name=' + mdt.Decision_Matrix_Name__c
            );
        }
    }

    System.debug('Total CMDT Matches = ' + matches.size());
    System.debug('===== DECISION MATRIX LOOKUP END =====');

    return matches;
}
    
    global class HWRequest {
        public String Client;
        public String OriginalState;
        public String ResidenceType;
    }
    
    global class HWResponse {
        public Integer status;
        public String error;
        public HWPayload payload;
        public List<HWQuote> quotes;
    }
    
    global class HWPayload {
        public String Client;
        public String OriginalState;
        public String ResidenceType;
    }
    
    global class HWQuote {
        public String DealerProgramId;
        public String Product;
        public String CoverageLevel;
        public Integer ContractTermMonths;
        public Integer ValidationDays;
        public Decimal Deductible;
        public Decimal DealerCost;
        public Decimal MonthlyDealerCost;
        public String WaterWellPump;
        public String RefrigeratorIceMaker;
        public String StandAloneIceMaker;
        public String SecondaryRefrigerator;
        public String SecondaryFreezer;
        public String SwimmingPool;
        public String Spa;
        public String ClothesWasherDryer;
        public String CentralVac;
        public String GarageDoorOpener;
    }
    
    global class HWErrorResponse {
        public Integer status;
        public String error;
        public HWPayload payload;
        public List<Object> quotes;
    }
    
    // 3. Updated Error Response Method: Takes the preserved request to perfectly reflect inputs
    public static String generateErrorResponse(String msg, HWRequest req){
        HWErrorResponse err = new HWErrorResponse();
        err.status = 400;
        err.error = msg;
        
HWPayload payload = new HWPayload();

// Echo the values from the API request
payload.Client =
    req != null
    ? req.Client
    : null;

payload.OriginalState =
    req != null
    ? req.OriginalState
    : null;

payload.ResidenceType =
    req != null
    ? req.ResidenceType
    : null;

err.payload = payload;
        // Injects an empty Map so that it serializes as "{}" instead of an empty list "[]"
        err.quotes = new List<Object>{ new Map<String,Object>() };
            return buildErrorResponse(err);
        
    }
    
    private static String buildErrorResponse(HWErrorResponse err){
        
        JSONGenerator gen = JSON.createGenerator(false);
        
        gen.writeStartObject();
        
        gen.writeNumberField('status', err.status);
        
gen.writeStringField(
    'error',
    String.isBlank(err.error) ? 'Unknown error' : err.error
);

gen.writeFieldName('payload');

gen.writeStartObject();

gen.writeStringField(
    'Client',
    String.isBlank(err.payload.Client) ? '' : err.payload.Client
);

gen.writeStringField(
    'OriginalState',
    String.isBlank(err.payload.OriginalState) ? '' : err.payload.OriginalState
);

gen.writeStringField(
    'ResidenceType',
    String.isBlank(err.payload.ResidenceType) ? '' : err.payload.ResidenceType
);

gen.writeEndObject();
        
      
        
        gen.writeFieldName('quotes');
        
        gen.writeStartArray();
        
        gen.writeStartObject();
        
        gen.writeEndObject();
        
        gen.writeEndArray();
        
        gen.writeEndObject();
        
        return gen.getAsString();
    }
    
    private static String buildSuccessResponse(HWResponse res){
        
        JSONGenerator gen = JSON.createGenerator(false);
        
        gen.writeStartObject();
        
        gen.writeNumberField('status', res.status);
        
        gen.writeStringField('error', res.error);
        
        gen.writeFieldName('payload');
        
        gen.writeStartObject();
        
        gen.writeStringField('Client', res.payload.Client);
        gen.writeStringField('OriginalState', res.payload.OriginalState);
        gen.writeStringField('ResidenceType', res.payload.ResidenceType);
        
        gen.writeEndObject();
        
        gen.writeFieldName('quotes');
        
        gen.writeStartArray();
        
        for(HWQuote q : res.quotes){
            
            gen.writeStartObject();
            
            gen.writeStringField('DealerProgramId', q.DealerProgramId);
            
            gen.writeStringField('Product', q.Product);
            
            gen.writeStringField('CoverageLevel', q.CoverageLevel);
            
            gen.writeStringField('ContractTermMonths', String.valueOf(q.ContractTermMonths));
            
            gen.writeStringField('ValidationDays', String.valueOf(q.ValidationDays));
            
            gen.writeStringField('Deductible', q.Deductible == null ? '' : q.Deductible.setScale(2).toPlainString());
            
           gen.writeStringField('DealerCost', q.DealerCost == null ? '' : q.DealerCost.setScale(2).toPlainString());
            
           gen.writeStringField('MonthlyDealerCost', q.MonthlyDealerCost == null ? '' : q.MonthlyDealerCost.setScale(2).toPlainString());
            
            gen.writeStringField('WaterWellPump', q.WaterWellPump);
            
            gen.writeStringField('RefrigeratorIceMaker', q.RefrigeratorIceMaker);
            
            gen.writeStringField('StandAloneIceMaker', q.StandAloneIceMaker);
            
            gen.writeStringField('SecondaryRefrigerator', q.SecondaryRefrigerator);
            
            gen.writeStringField('SecondaryFreezer', q.SecondaryFreezer);
            
            gen.writeStringField('SwimmingPool', q.SwimmingPool);
            
            gen.writeStringField('Spa', q.Spa);
            
            gen.writeStringField('ClothesWasherDryer', q.ClothesWasherDryer);
            
            gen.writeStringField('CentralVac', q.CentralVac);
            
            gen.writeStringField('GarageDoorOpener', q.GarageDoorOpener);
            
            gen.writeEndObject();
        }
        
        gen.writeEndArray();
        
        gen.writeEndObject();
        
        return gen.getAsString();
    }
    
    public static void stateSetLookup(
    HWRequest req,
    Decimal defaultValidationDays
){
        
        if(stateSetMatrixSet.isEmpty()){
            throw new HWValidationException('State Set not found for given request');
        }
        
        List<CalculationMatrix> stateSetMatrixRec = [
            SELECT Id,
            UniqueName,
            (SELECT Id
             FROM CalculationMatrixVersions
             WHERE IsEnabled = TRUE
             AND EndDateTime = NULL
             LIMIT 1)
            FROM CalculationMatrix
            WHERE UniqueName IN :stateSetMatrixSet
        ];
        System.debug('StateSet Matrix = ' + QuoteServiceHome.stateSetMatrixSet);
        
        if(stateSetMatrixRec.isEmpty()){
            return;
        }
        
        for(CalculationMatrix matrix : stateSetMatrixRec){
            
            if(matrix.CalculationMatrixVersions.isEmpty()){
                continue;
            }
            
            String versionId = matrix.CalculationMatrixVersions[0].Id;
            
            String responseBody =
                ContractUtility.fetchLookupTableRows(matrix.Id, versionId);
            System.debug('******** RESPONSE BODY ********');
System.debug(responseBody);
            
            Map<String,Object> jsonMap =
                (Map<String,Object>)JSON.deserializeUntyped(responseBody);
            System.debug('******** JSON MAP ********');
System.debug(jsonMap);
            
            List<Object> rows =
                (List<Object>)jsonMap.get('rows');
            
            System.debug('******** ROWS ********');
System.debug(rows);
            
            Boolean isActive = false;
            
            for(Object data : rows){
                
                Map<String,Object> row =
                    (Map<String,Object>)data;
                
                Map<String,Object> rowData =
                    (Map<String,Object>)row.get('rowData');
                
                String stateFromMatrix =
                    String.valueOf(rowData.get('State'));
                
                Object activeVal =
                    rowData.get('Active');
                
                if(stateFromMatrix == req.OriginalState){
                    
                    if(activeVal != null &&
                       (Boolean.valueOf(activeVal) ||
                        String.valueOf(activeVal).equalsIgnoreCase('true'))){
                            
                            isActive = true;
                            
                            // Read Carrier from State Set
                            if(rowData.containsKey('Carrier')){
                                hwMap.put(
                                    'InsuranceCarrier',
                                    String.valueOf(rowData.get('Carrier'))
                                );
                            }
                            
                            System.debug('StateSet Row = ' + JSON.serializePretty(rowData));
                            System.debug('Carrier from State Set = ' + rowData.get('Carrier'));
                            System.debug('Saved in hwMap = ' + hwMap.get('InsuranceCarrier'));
                            
                            break;
                        }
                }
            }
            
            if(!isActive){
                throw new HWValidationException(
                    'Quote Request Failed: State '
                    + req.OriginalState
                    + ' is inactive or restricted.'
                );
            }
        }
        
        
       List<String> dealerIds =
    new List<String>(responseMap.keySet());

dealerIds.sort();

for(String key : dealerIds){

    if(!responseMap.get(key).containsKey('ValidationDays')){
        responseMap.get(key).put(
            'ValidationDays',
            String.valueOf(defaultValidationDays)
        );
    }
}
    }
    
    
}