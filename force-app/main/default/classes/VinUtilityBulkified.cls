/**
* @description		 : Used to get VIn Detail and VIN Classes records as per provided Vin numbers in bulk
* @author            : Sohel Azmi
* @group             :
* @last modified on  : 06-12-2026
* @last modified by  : Sohel Azmi
**/
public class VinUtilityBulkified {
    
    // NEW BULK METHOD
    public static Map<String, String> resolveSquishVINsBulk(Set<String> vins) {
        Map<String, String> vinToSquishMap = new Map<String, String>();
        Set<String> allPatterns = new Set<String>();
        Map<String, List<String>> vinToPatternsMap = new Map<String, List<String>>();

        // 1. Generate all possible wildcard patterns in memory (0 SOQL)
        for (String vin : vins) {
            if (String.isNotBlank(vin)) {
                List<String> patterns = createAllSquishVINs(vin);
                if (!patterns.isEmpty()) {
                    allPatterns.addAll(patterns);
                    vinToPatternsMap.put(vin, patterns);
                }
            }
        }

        if (allPatterns.isEmpty()) return vinToSquishMap;

        // 2. Query the database exactly ONCE for all possible matching patterns
        Set<String> validMasksInDb = new Set<String>();
        for (VIN_Detail__c detail : [SELECT VIN_SIGNI_PATTRN_MASK__c FROM VIN_Detail__c WHERE VIN_SIGNI_PATTRN_MASK__c IN :allPatterns]) {
            validMasksInDb.add(detail.VIN_SIGNI_PATTRN_MASK__c);
        }

        // 3. Map the correct, highest-priority mask back to the original VIN
        for (String vin : vinToPatternsMap.keySet()) {
            for (String pattern : vinToPatternsMap.get(vin)) {
                if (validMasksInDb.contains(pattern)) {
                    vinToSquishMap.put(vin, pattern);
                    break; // Mimics old LIMIT 1 behavior by stopping at the first valid match
                }
            }
        }

        return vinToSquishMap;
    }

    public static List<String> createAllSquishVINs(String vin) {
        List<String> patterns = new List<String>();
        if (String.isBlank(vin) || vin.length() != 17) {
            return patterns;
        }
        // XXXXXXXX*XX******
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9,11) + '******');
        // XXXXXXXX*XXXXXXXX
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9));
        // XXXXXXXX*XXXXXXX*
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9,16) + '*');
        // XXXXXXXX*XXXXXX**
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9,15) + '**');
        // XXXXXXXX*XXXXX***
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9,14) + '***');
        // XXXXXXXX*XXXX****
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9,13) + '****');
        // XXXXXXXX*XXX*****
        patterns.add(vin.substring(0,8) + '*' + vin.substring(9,12) + '*****');
        return patterns;
    }
    
    /********************************************
    * UPDATED — VIN Detail Query With Bulk Resolver
    ********************************************/
    /*public static Map<String, Map<String, Object>> getVinDetails(List<String> vins) {
        Map<String, Map<String, Object>> resultMap = new Map<String, Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap = VIN_Detail__c.SObjectType.getDescribe().fields.getMap();
        
        try {
            // 🚀 Call the new Bulk Resolver (1 SOQL)
            Map<String, String> resolvedVinsMap = resolveSquishVINsBulk(new Set<String>(vins));
            Set<String> resolvedPatterns = new Set<String>(resolvedVinsMap.values());
            
            if (!resolvedPatterns.isEmpty()) {
                // 🚀 Fetch Details (1 SOQL)
                for (VIN_Detail__c detail : [
                    SELECT Id, Name, BODY_STYLE_DESC__c, BDY_STYLE_CD__c, ENG_CLNDR_RTR_CNT__c,
                    DRV_TYP_CD__c, ENG_DISPLCMNT_CI__c, ENG_DISPLCMNT_CL__c, ENG_MDL_DESC__c, Ethnicity__c,
                    ENG_FUEL_DESC__c, ENG_ASP_SUP_CHGR_CD__c, ENG_ASP_TRBL_CHGR_CD__c, MAK_NM__c,
                    NCI_MAK_ABBR_CD__c, MFG_DESC__c, MDL_DESC__c, MDL_YR__c, OPT1_TRIM_DESC__c,
                    OPT2_TRIM_DESC__c, OPT3_TRIM_DESC__c, OPT4_TRIM_DESC__c, VIN_SIGNI_PATTRN_MASK__c,
                    TRK_TNG_RAT_CD__c, TRANS_CD__c, TRIM_DESC__c, SEGMENTATION_DESC__c
                    FROM VIN_Detail__c
                    WHERE VIN_SIGNI_PATTRN_MASK__c IN :resolvedPatterns
                ]) {
                    Map<String, Object> fieldValueMap = new Map<String, Object>();
                    for (String fieldName : fieldMap.keySet()) {
                        if (fieldName.contains('__c') || fieldName == 'Name' || fieldName == 'Id') {
                            fieldValueMap.put(fieldName, detail.get(fieldName));
                        }
                    }
                    resultMap.put(detail.VIN_SIGNI_PATTRN_MASK__c, fieldValueMap);
                }
            }
        } catch (Exception ex) {
            QDX_Log.Requests errorReq = new QDX_Log.Requests();
            errorReq.errorMessage = ex.getMessage();
            errorReq.flowName = 'VinUtilityTwo.getVinDetails';
            QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
        }
        return resultMap;
    }*/
    
    /********************************************
    * UPDATED — VIN Class Query With Bulk Resolver
    ********************************************/
    /*public static Map<String, Map<String, String>> getVinClasses(List<String> vins) {
        Map<String, Map<String, String>> resultMap = new Map<String, Map<String, String>>();
        Map<String, Schema.SObjectField> fieldMap = VIN_Class__c.SObjectType.getDescribe().fields.getMap();
        
        try {
            // Call the new Bulk Resolver (1 SOQL)
            Map<String, String> resolvedVinsMap = resolveSquishVINsBulk(new Set<String>(vins));
            Set<String> resolvedPatterns = new Set<String>(resolvedVinsMap.values());
            
            if (!resolvedPatterns.isEmpty()) {
                // Fetch Details (1 SOQL)
                for (VIN_Class__c vinClass : [
                    SELECT Id, Name, Class__c, Class_Guide_Name__c, Partner__c, Purchase_Type__c,
                    Squish_VIN__c, Squish_VIN__r.Name
                    FROM VIN_Class__c
                    WHERE Squish_VIN__r.Name IN :resolvedPatterns
                ]) {
                    Map<String, String> valueMap = new Map<String, String>();
                    for (String fieldName : fieldMap.keySet()) {
                        if (fieldName.contains('__c') || fieldName == 'Name' || fieldName == 'Id') {
                            valueMap.put(fieldName, (String) vinClass.get(fieldName));
                        }
                    }
                    resultMap.put(vinClass.Squish_VIN__r.Name, valueMap);
                }
            }
        } catch (Exception ex) {
            QDX_Log.Requests errorReq = new QDX_Log.Requests();
            errorReq.errorMessage = ex.getMessage();
            errorReq.flowName = 'VinUtilityTwo.getVinClasses';
            QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
        }
        return resultMap;
    }*/
    
    /********************************************
    * FIXED — VIN Detail Query With Bulk Resolver
    ********************************************/
    public static Map<String, Map<String, Object>> getVinDetails(List<String> vins) {
        Map<String, Map<String, Object>> resultMap = new Map<String, Map<String, Object>>();
        
        try {
            Map<String, String> resolvedVinsMap = resolveSquishVINsBulk(new Set<String>(vins));
            Set<String> resolvedPatterns = new Set<String>(resolvedVinsMap.values());
            
            if (!resolvedPatterns.isEmpty()) {
                for (VIN_Detail__c detail : [
                    SELECT Id, Name, BODY_STYLE_DESC__c, BDY_STYLE_CD__c, ENG_CLNDR_RTR_CNT__c,
                    DRV_TYP_CD__c, ENG_DISPLCMNT_CI__c, ENG_DISPLCMNT_CL__c, ENG_MDL_DESC__c, Ethnicity__c,
                    ENG_FUEL_DESC__c, ENG_ASP_SUP_CHGR_CD__c, ENG_ASP_TRBL_CHGR_CD__c, MAK_NM__c,
                    NCI_MAK_ABBR_CD__c, MFG_DESC__c, MDL_DESC__c, MDL_YR__c, OPT1_TRIM_DESC__c,
                    OPT2_TRIM_DESC__c, OPT3_TRIM_DESC__c, OPT4_TRIM_DESC__c, VIN_SIGNI_PATTRN_MASK__c,
                    TRK_TNG_RAT_CD__c, TRANS_CD__c, TRIM_DESC__c, SEGMENTATION_DESC__c
                    FROM VIN_Detail__c
                    WHERE VIN_SIGNI_PATTRN_MASK__c IN :resolvedPatterns
                ]) {
                    Map<String, Object> fieldValueMap = new Map<String, Object>();
                    Map<String, Object> populatedFields = detail.getPopulatedFieldsAsMap();
                    
                    for (String fieldName : populatedFields.keySet()) {
                        // Force lowercase for strict matching with STAGE 8 mapped keys
                        fieldValueMap.put(fieldName.toLowerCase(), populatedFields.get(fieldName));
                    }
                    resultMap.put(detail.VIN_SIGNI_PATTRN_MASK__c, fieldValueMap);
                }
            }
        } catch (Exception ex) {
            QDX_Log.Requests errorReq = new QDX_Log.Requests();
            errorReq.errorMessage = ex.getMessage();
            errorReq.flowName = 'VinUtilityBulkified.getVinDetails';
            QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
        }
        return resultMap;
    }
    
    /********************************************
    * FIXED — VIN Class Query With Bulk Resolver
    ********************************************/
    public static Map<String, Map<String, String>> getVinClasses(List<String> vins) {
        Map<String, Map<String, String>> resultMap = new Map<String, Map<String, String>>();
        
        try {
            Map<String, String> resolvedVinsMap = resolveSquishVINsBulk(new Set<String>(vins));
            Set<String> resolvedPatterns = new Set<String>(resolvedVinsMap.values());
            
            if (!resolvedPatterns.isEmpty()) {
                for (VIN_Class__c vinClass : [
                    SELECT Id, Name, Class__c, Class_Guide_Name__c, Partner__c, Purchase_Type__c,
                    Squish_VIN__c, Squish_VIN__r.Name
                    FROM VIN_Class__c
                    WHERE Squish_VIN__r.Name IN :resolvedPatterns
                ]) {
                    Map<String, String> valueMap = new Map<String, String>();
                    Map<String, Object> populatedFields = vinClass.getPopulatedFieldsAsMap();
                    
                    for (String fieldName : populatedFields.keySet()) {
                        valueMap.put(fieldName.toLowerCase(), String.valueOf(populatedFields.get(fieldName)));
                    }
                    
                    resultMap.put(vinClass.Squish_VIN__r.Name, valueMap);
                }
            }
        } catch (Exception ex) {
            QDX_Log.Requests errorReq = new QDX_Log.Requests();
            errorReq.errorMessage = ex.getMessage();
            errorReq.flowName = 'VinUtilityBulkified.getVinClasses';
            QDX_Log.publishError(new List<QDX_Log.Requests> {errorReq});
        }
        return resultMap;
    }
    
    // VIN Classes by Contract
    public static Map<String,String> getVinClassesByContract(List<InsurancePolicy> newContractRecs){
        Set<String> squishVinsSet = new Set<String>();
        Set<String> guideNameSet = new Set<String>();
        for(InsurancePolicy contracts: newContractRecs){
            if(contracts != null && contracts.VIN__c != null){
                squishVinsSet.addAll(createAllSquishVINs(contracts.VIN__c));
                if(contracts.Class_Guide__c != null){
                    guideNameSet.add(contracts.Class_Guide__c);
                }
            }
        }
        if(!squishVinsSet.isEmpty() || !guideNameSet.isEmpty()){
            return getVinClassByClassGuide(guideNameSet, squishVinsSet);
        }
        return null;
    }
    
    public static Map<String,String> getVinClassByClassGuide(Set<String> guideNameSet, Set<String> squishVinsSet){
        Map<String,String> vinDetailsMap  = new Map<String,String>();
        List<VIN_Class__c> vinClassList = [
            SELECT Id, Class__c, Squish_VIN__r.Name
            FROM VIN_Class__c 
            WHERE Class_Guide_Name__c IN :guideNameSet 
              AND Squish_VIN__r.Name IN :squishVinsSet
        ];
        if(!vinClassList.isEmpty()){
            for(VIN_Class__c vinRecord: vinClassList){
                vinDetailsMap.put(vinRecord.Squish_VIN__r.Name, vinRecord.Class__c);
            }
            if(vinDetailsMap != null && !vinDetailsMap.isEmpty()){
                return vinDetailsMap;
            }
        }
        return null;
    }
}