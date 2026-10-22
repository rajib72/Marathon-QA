public class BRELogger {
    
    private static String transactionId;
    
    // Cache metadata setting per transaction
    private static Boolean loggingEnabled;
    
    // Cache metadata record per transaction
    private static BRE_Logging_Config__mdt configCache;
    
    private static Map<String, Integer> methodCallCounters =
        new Map<String, Integer>();
    
    public static Boolean isLoggingEnabled() {
        
        BRE_Logging_Config__mdt config = getConfig();
        
        return config != null &&
            config.Enable_Logging__c;
    }
    
    private static BRE_Logging_Config__mdt getConfig(){
        
        if(configCache == null){
            configCache =
                BRE_Logging_Config__mdt.getInstance('Default');
        }
        
        return configCache;
    }
    
    public static void log(
        String brName,
        String brType,
        String typeOfCall,
        Long durationMs,
        String responseStatus,
        Boolean cacheHit,
        List<Map<String, Object>> parameters,
        String callerClass,
        String callerMethod,
        String endpointUrl,
        String contractNumber
    ){
        if(!isLoggingEnabled()){
            return;
        }
        
        try{
            BRE_Logging_Config__mdt config = getConfig();
            
            if(config == null || !config.Enable_Logging__c){
                return;
            }
            
            Integer sampleRate = (Integer)config.Sample_Rate__c;
            if(sampleRate != null && sampleRate > 1){
                if(Math.mod(Limits.getCallouts(), sampleRate) != 0){
                    return;
                }
            }
            
            if(config.Log_Only_High_Volume__c &&
               Limits.getCallouts() < 5){
                   return;
               }
            
            // ✅ Safe Input Hash generation
            String inputHash = null;
            Integer inputSize = 0;
            try {
                if(parameters != null){
                    String inputJson = JSON.serialize(parameters);
                    inputSize = inputJson.length();
                    inputHash = EncodingUtil.convertToHex(
                        Crypto.generateDigest('MD5', Blob.valueOf(inputJson))
                    );
                }
            } catch(Exception ex){
                System.debug('Hash generation failed: ' + ex.getMessage());
            }
            
            BRE_Call_Event__e evt = new BRE_Call_Event__e(
                Rule_Name__c      = brName,
                Rule_Type__c      = brType,
                Call_Type__c      = typeOfCall,
                Execution_Time__c = durationMs,
                Response_Status__c= responseStatus,
                User_Id__c        = UserInfo.getUserId(),
                Source__c         = 'Apex',
                Transaction_Id__c = getTransactionId(),     
                Callout_Count__c  = Limits.getCallouts(),
                Caller_Class__c   = String.isBlank(callerClass)
                ? 'Unknown'
                : callerClass,
                
                Caller_Method__c  = String.isBlank(callerMethod)
                ? 'Unknown'
                : callerMethod,
                Method_Call_Count__c =
                getMethodCallCount(
                    (String.isBlank(callerMethod) ? 'UnknownMethod' : callerMethod)
                    + '-' +
                    (String.isBlank(contractNumber) ? 'NoContract' : contractNumber)
                ),
                Endpoint_URL__c   = endpointUrl,
                Contract_Number__c = contractNumber,
                Cache_Hit__c      = cacheHit,
                Input_Size__c     = inputSize,
                Input_Hash__c     = inputHash,
                Timestamp__c      = System.now()
            );
            
            EventBus.publish(evt);
            
        } catch(Exception e){
            System.debug('BRELogger error: ' + e.getMessage());
        }
    }
    
    private static String getTransactionId(){
        
        if(transactionId == null){
            transactionId =
                UserInfo.getUserId() +
                '-' +
                Datetime.now().getTime();
        }
        
        return transactionId;
    }
    
    private static Integer getMethodCallCount(String callerMethod){
        
        if(String.isBlank(callerMethod)){
            return 0;
        }
        
        if(!methodCallCounters.containsKey(callerMethod)){
            methodCallCounters.put(callerMethod, 1);
        } else {
            
            methodCallCounters.put(
                callerMethod,
                methodCallCounters.get(callerMethod) + 1
            );
        }
        
        return methodCallCounters.get(callerMethod);
    }
}