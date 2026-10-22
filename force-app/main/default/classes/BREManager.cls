/**
* BREManager Class
* This class handles the construction and execution of business rule callouts.
* It builds JSON request payloads dynamically based on the provided parameters
* and handles HTTP POST requests to the Salesforce Business Rules Engine.
*/
public class BREManager {
    
    private static Map<String, String> responseCache =
    new Map<String, String>();

private static Map<String, Long> responseTimeCache =
    new Map<String, Long>();

    private static final Integer MAX_CACHE_SIZE = 500;

    private static String normalize(Object value){

    return value == null
        ? ''
        : String.valueOf(value).trim().toLowerCase();
}

    private static String buildCacheKey(
    String brName,
    String brType,
    Date effectiveDate,
    List<Map<String, Object>> parameters
){
    
    Map<String, Object> p =
        parameters != null && !parameters.isEmpty()
        ? parameters[0]
        : new Map<String, Object>();
    
    /*
     * RULE SPECIFIC CACHE KEYS
     */
    
    // =====================================================
    // State Insurance Guide
    // =====================================================
    
    if(brName == 'State_Insurance_Guide'){
        
        return
            brName +
            '|' +
            normalize(p.get('Product')) +
            '|' +
            normalize(p.get('Client')) +
            '|' +
            normalize(p.get('CoverageLevel')) +
            '|' +
            normalize(p.get('StateInput'));
    }
    
    // =====================================================
    // SecureOne State Matrix
    // =====================================================
    
    if(brName == 'SecureOne_State_Matrix'){
        
        return
            brName +
            '|' +
            normalize(p.get('StateSetName')) +
            '|' +
            normalize(p.get('StateProvince'));
    }
    
    // =====================================================
    // Options Sets
    // =====================================================
    
    if(brName == 'Options_Sets'){
        
        return
            brName +
            '|' +
            normalize(p.get('OptionsSetsInput')) +
            '|' +
            normalize(p.get('CoverageNameInput')) +
            '|' +
            normalize(p.get('OptionNameInput')) +
            '|' +
            normalize(p.get('RateClassInput'));
    }
    
    // =====================================================
    // Surcharge Sets
    // =====================================================
    
    if(brName == 'Surcharge_Sets'){
        
        return
            brName +
            '|' +
            normalize(p.get('SurchargeNameInput')) +
            '|' +
            normalize(p.get('CoverageNameInput')) +
            '|' +
            normalize(p.get('RateClassListInput')) +
            '|' +
            normalize(p.get('SurchargeSetsInput'));
    }
    
    // =====================================================
    // Rate Sets
    // =====================================================
    
    if(brName == 'Rate_Sets'){
        
        return
            brName +
            '|' +
            normalize(p.get('RateSetInput')) +
            '|' +
            normalize(p.get('CoverageNameInput')) +
            '|' +
            normalize(p.get('RateClassInput'));
    }
    
    /*
     * SAFE FALLBACK
     */
    
    String requestHash = EncodingUtil.convertToHex(
        Crypto.generateDigest(
            'MD5',
            Blob.valueOf(JSON.serialize(parameters))
        )
    );
    
    return
        brName +
        '|' +
        brType +
        '|' +
        String.valueOf(effectiveDate) +
        '|' +
        requestHash;
}

    /*Method Overloading*
 * Backward-compatible overload for existing BRE calls.
 * Existing callers across the org can continue using the old signature
 * without requiring logging metadata parameters.
 */
public static String runBRCallout(
    List<Map<String, Object>> parameters,
    Date effectiveDate,
    String brName,
    String brType,
    String typeOfCall
) {

    return runBRCallout(
        parameters,
        effectiveDate,
        brName,
        brType,
        typeOfCall,
        null,   // callerClass
        null,   // callerMethod
        null    // contractNumber
    );
}
    /**
* Executes a business rule callout to the specified endpoint with the given parameters.
*
* @param parameters   List of maps containing key-value pairs for input parameters.
* @param effectiveDate The effective date for the business rule execution.
* @param brName       The name of the business rule.
* @param brType       The type of the business rule (e.g., 'decision-matrices', 'expressionSet').
* @return             The response body from the HTTP callout as a string.
*/
    public static String runBRCallout(List<Map<String, Object>> parameters, Date effectiveDate, String brName, String brType, String typeOfCall, String callerClass, String callerMethod, String contractNumber) {
        //
        //TODO - Parameters to list - convert below logic where parameters[0] is written
        //
        //Debug Logs
        //Delete logs before deploying to prod
        System.debug(LoggingLevel.ERROR, '--- BREManager.runBRCallout() START ---');
        System.debug(LoggingLevel.ERROR, 'Received Parameters: ' + JSON.serializePretty(parameters));
        System.debug(LoggingLevel.ERROR, 'Effective Date: ' + String.valueOf(effectiveDate));
        System.debug(LoggingLevel.ERROR, 'BR Name: ' + brName);
        System.debug(LoggingLevel.ERROR, 'BR Type: ' + brType);
        System.debug(LoggingLevel.ERROR, 'Call Type: ' + typeOfCall);
        /*----------Debug Statement added to check the BR Call Limits before making the callout, 29-04-2026------------------*/
        
        System.debug(LoggingLevel.ERROR,
                     'BRE CALL START' +
                     ' | Rule=' + brName +
                     ' | Type=' + brType +
                     ' | CallType=' + typeOfCall +
                     ' | User=' + UserInfo.getName() +
                     ' | CalloutCount=' + Limits.getCallouts() +
                     ' | Inputs=' + JSON.serialize(parameters)
                    );
        
        /* Lightweight caller marker */
        System.debug(
            'Caller likely from rule=' + brName +
            ' | Callout#=' + Limits.getCallouts()
        );
        
        /* Transaction correlation id */
        System.debug(
            'TX Context | User=' + UserInfo.getUserId() +
            ' | Callout#=' + Limits.getCallouts()
        );
        
        /* Optional stack trace only if suspicious */
        if(Limits.getCallouts() > 5){
            try{
                Integer x = 1/0;
            }
            catch(Exception e){
                System.debug(
                    LoggingLevel.ERROR,
                    'BRE CALL STACK=' + e.getStackTraceString()
                );
            }
        }
        
        Long startMs = Datetime.now().getTime();
        /*----------Debug Statement added to check the BR Call Limits before making the callout, 29-04-2026------------------*/
        
        // Initialize JSON request payload
        Map<String, Object> jsonRequest = new Map<String, Object>();
        List<Map<String, Object>> inputsArray = new List<Map<String, Object>>();
        String endpointUrl;
        String cacheKey;
        
        // Build inputs based on the business rule type
        if (brType == 'decision-matrices') {
            inputsArray = buildDecisionMatricesInputs(parameters);
        } else if (brType == 'expressionSet') {
            inputsArray = buildExpressionSetInputs(parameters);
        }
        System.debug(LoggingLevel.ERROR, 'Inputs Array (After Build): ' + JSON.serializePretty(inputsArray));
        
        jsonRequest.put('inputs', inputsArray);
        
        // Add options to the JSON request
        Map<String, Object> options = new Map<String, Object>();
        options.put('useDatesOnly', true);
        options.put('effectiveDate', String.valueOf(effectiveDate) + 'T00:00:00Z');
        jsonRequest.put('options', options);

      /*  String requestHash = EncodingUtil.convertToHex(
    Crypto.generateDigest(
        'MD5',
        Blob.valueOf(JSON.serialize(jsonRequest))
    )
);*/

cacheKey = buildCacheKey(
    brName,
    brType,
    effectiveDate,
    parameters
);

System.debug(
    LoggingLevel.ERROR,
    'CACHE KEY GENERATED=' + cacheKey
);
        
        // Construct endpoint URL
        // Note: The API version (v62.0) is hardcoded. Consider storing this in a custom metadata type or custom setting.
        // For Internal call, SF_OMNI_API named credentials is used.
        if( typeOfCall == UtilityClass.IS_EXTERNAL_CALL){
            endpointUrl = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v62.0/connect/business-rules/' + brType + '/' + brName;
        }
        else if( typeOfCall == UtilityClass.IS_INTERNAL_CALL){
            endpointUrl = 'callout:SF_OMNI_API/services/data/v62.0/connect/business-rules/' + brType + '/' + brName;
        }
        System.debug('Endpoint URL: ' + endpointUrl);
        System.debug('Request Body: ' + JSON.serialize(jsonRequest));
        
        System.debug(
    LoggingLevel.ERROR,
    'CACHE CONTAINS=' +
    responseCache.containsKey(cacheKey)
);

        if(responseCache.containsKey(cacheKey)){

    Long cachedDuration =
        responseTimeCache.containsKey(cacheKey)
        ? responseTimeCache.get(cacheKey)
        : 0;

            //-----BRE Call Audit Code Block 1----
            //*Uncomment the BRELogger.log code block when you want to log or track the BRE Calls in the BRE Call Audit object.*
            //*BRE Call tracking functionality has been only built in UAT for now. It is getting built in QA but it is incomplete there.*
            
    /*BRELogger.log(
        brName,
        brType,
        typeOfCall,
        cachedDuration,
        'CACHE_HIT',
        true,
        parameters,
        callerClass,
        callerMethod,
        endpointUrl,
        contractNumber
    );*/
            //Both BRE Call Audit Code Blocks are important.
            
    System.debug(
        LoggingLevel.ERROR,
        'BRE CACHE HIT | Rule=' + brName
    );

    return responseCache.get(cacheKey);
}
        // Execute HTTP callout
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(jsonRequest));
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        
        Http http = new Http();
        
        /*----------Debug Statement, 29-04-2026------------------*/
        System.debug(LoggingLevel.ERROR,
                     'BRE REQUEST' +
                     ' | Endpoint=' + endpointUrl +
                     ' | Body=' + JSON.serialize(jsonRequest)
                    );
        /*----------Debug Statement, 29-04-2026------------------*/
        
        HttpResponse res = http.send(req);
        
        /*----------Debug Statement, 29-04-2026------------------*/
        Long durationMs = Datetime.now().getTime() - startMs;
        
        
        //-----BRE Call Audit Code Block 2----
            //*Uncomment the BRELogger.log code block when you want to log or track the BRE Calls in the BRE Call Audit object.*
            //*BRE Call tracking functionality has been only built in UAT for now. It is getting built in QA but it is incomplete there.*
        
        /*BRELogger.log(
            brName,
            brType,
            typeOfCall,
            durationMs,
            
            // Response Status
            res.getStatus(),
            
            // Cache Hit (future caching support)
            false,
            
            parameters,
            callerClass,
            callerMethod,
            endpointUrl,
            contractNumber
        );*/
        
        //Both BRE Call Audit Code Blocks are important.
        
        System.debug(LoggingLevel.ERROR,
                     'BRE CALL END' +
                     ' | Rule=' + brName +
                     ' | Status=' + res.getStatus() +
                     ' | DurationMs=' + durationMs +
                     ' | CalloutCount=' + Limits.getCallouts() +
                     ' | Response=' + res.getBody()
                    );
        
        /*----------Debug Statement, 29-04-2026------------------*/
        
        if(res.getStatus() == 'Created'){

    if(responseCache.size() < MAX_CACHE_SIZE){

        responseCache.put(
            cacheKey,
            res.getBody()
        );

        responseTimeCache.put(
            cacheKey,
            durationMs
        );
    }

    return res.getBody();
}

// Return response even for non-Created statuses
return res.getBody();
}
    
    /**
* Builds inputs for 'decision-matrices' type business rules.
*
* @param parameters List of maps containing key-value pairs for input parameters.
* @return           List of input maps for the JSON request.
*/
    private static List<Map<String, Object>> buildDecisionMatricesInputs(List<Map<String, Object>> parameters) {
        List<Map<String, Object>> inputsArray = new List<Map<String, Object>>();
        Map<String, Object> inputGroup = new Map<String, Object>();
        List<Map<String, Object>> inputList = new List<Map<String, Object>>();
        
        // TODO:
// Current implementation assumes single parameter map.
// Future enhancement:
// support multi-map bulk parameter processing safely.

        for (String key : parameters[0].keySet()) {
            Map<String, Object> input = new Map<String, Object>();
            input.put('name', key);
            input.put('value', parameters[0].get(key));
            inputList.add(input);
        }
        
        inputGroup.put('input', inputList);
        inputsArray.add(inputGroup);
        
        return inputsArray;
    }
    
    /**
* Builds inputs for 'expressionSet' type business rules.
*
* @param parameters List of maps containing key-value pairs for input parameters.
* @return           List of input maps for the JSON request.
*/
    private static List<Map<String, Object>> buildExpressionSetInputs(List<Map<String, Object>> parameters) {
        List<Map<String, Object>> inputsArray = new List<Map<String, Object>>();
        
        Map<String, Object> input = new Map<String, Object>();
        for (String key : parameters[0].keySet()) {
            input.put(key, parameters[0].get(key));
        }
     
        inputsArray.add(input);
        return inputsArray;
    }
}