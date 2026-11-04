/**
* @author Sujit Dengale
* @dateModified 24-05-2024
* @description Trigger Handler on Contract-InsurancePolicy
*/
public class ContractTriggerHandler {
    /*private static final String NOTIFICATION_SOURCE_OBJECT =
        'InsurancePolicy';
    
    private static final String STATUS_FIELD =
        'Status';
    
    private static final String RERATE_DATE_FIELD =
        'ReRate_Date__c';
    
    private static final String FINANCED_STATUS_FIELD =
        'Financed_Status__c';
    
    private static final String VALUE_TRANSITION =
        'Value Transition';
    
    private static final String ANY_FIELD_CHANGE =
        'Any Field Change';
    
    private static final String EVENT_CONTRACT_CANCELLED =
        'CONTRACT_CANCELLED';
    
    private static final String EVENT_CONTRACT_EXPIRED =
        'CONTRACT_EXPIRED';
    
    private static final String EVENT_CONTRACT_UPDATED =
        'CONTRACT_UPDATED';
    
    private static final String EVENT_FINANCE_PAST_DUE =
        'FINANCE_PAST_DUE';
    
    private static final String EVENT_FINANCE_CURRENT =
        'FINANCE_CURRENT';*/
    
    public static void handleBeforeInsert(List<InsurancePolicy> newContracts) {
        findDuplicateContracts(newContracts);
        updateStatus(newContracts,NULL);
        setContractTnCCodeURL(newContracts, NULL);
        calculateAdminCost(newContracts, NULL, false);
        setInsuranceCarrierDetails(newContracts, NULL);
        populateAllocationCosts(newContracts);
        productCoverageLevelValidation(newContracts);
        contractRateValidation(newContracts);
        setNextCycleDateForM2MContracts(newContracts, NULL);
        setExpirationDate(newContracts);
        setRefundPercent(newContracts);
        setUnearnedPercent(newContracts); // ADDED ON 11/03/26
    }
    
    public static void handleBeforeUpdate(List<InsurancePolicy> newContracts, Map<Id,InsurancePolicy> oldContractMap){
        updateStatus(newContracts,oldContractMap);
        //contractRateValidation(newContracts,oldContractMap);
        calculateAdminCost(newContracts, oldContractMap, true);
        setInsuranceCarrierDetails(newContracts, oldContractMap);
        setNextCycleDateForM2MContracts(newContracts, oldContractMap);
        setExpirationDate(newContracts);
        validateCancelMilage(newContracts);
        setRefundPercent(newContracts);
        setUnearnedPercent(newContracts); // ADDED ON 11/03/26
    }
    
    public static void handleAfterInsert(List<InsurancePolicy> newContracts, Map<Id,InsurancePolicy> oldContractMap){ }
    
    /**
* Processes Insurance Policy notification events after the
* final record values have been saved.
*
* Notification failures must not block the underlying
* InsurancePolicy update.
*/
  /*  public static void handleAfterUpdate(List<InsurancePolicy> newContracts,Map<Id, InsurancePolicy> oldContractMap) {
        if (
            newContracts == null ||
            newContracts.isEmpty() ||
            oldContractMap == null ||
            oldContractMap.isEmpty()
        ) {
            return;
        }
        
        try {
            processContractNotificationEvents(
                newContracts,
                oldContractMap
            );
        } catch (Exception ex) {
            QDX_Log.error(
                'Insurance Policy notification processing failed. ' +
                'Message: ' + ex.getMessage() +
                ', Line: ' + ex.getLineNumber() +
                ', Stack Trace: ' + ex.getStackTraceString()
            );
            
            QDX_Log.publish();
        }
    }*/
    
    public static void updateStatus(List<InsurancePolicy> newContracts, Map<Id,InsurancePolicy> oldContractMap){
        // this method is used for the upadting status of Contracts
        
        for(InsurancePolicy contractRecord: newContracts){
            if(oldContractMap == NULL){
                Date effectiveDate = contractRecord.Effective_Date__c != NULL ? Date.newInstance(contractRecord.Effective_Date__c.year(), contractRecord.Effective_Date__c.month(), contractRecord.Effective_Date__c.day()) : NULL;
                if(contractRecord != NULL & contractRecord.Effective_Date__c != NULL &&
                   effectiveDate > System.Today()){
                       contractRecord.Status = UtilityClass.contractStatus_InWaiting;
                   }
                if(contractRecord != NULL & contractRecord.Effective_Date__c != NULL &&
                   effectiveDate <= System.Today()){
                       contractRecord.Status = UtilityClass.contractStatus_Active;
                   }
                /*if (
contractRecord.Product__c == 'SecureOne' &&
contractRecord.Sale_Date__c != null
) {
contractRecord.Contract_Funded_Date__c =
contractRecord.Sale_Date__c.addMonths(1);
}*/
                if(contractRecord.Product__c == 'SecureOne'){
                    System.debug('Contract Trigger Handler Fired');
                    System.debug('Sale date standard is '+contractRecord.SaleDate);
                    System.debug('Sale date Custom is '+contractRecord.Sale_Date__c);
                    //contractRecord.Contract_Funded_Date__c = System.today();
                    contractRecord.Contract_Funded_Date__c = contractRecord.SaleDate.date().addMonths(1);
                    //------Start-Earliest Contract Funded Date for Westlake 12/03/2026.-------------------------
                    contractRecord.Earliest_Contract_Funded_Date__c = contractRecord.Contract_Funded_Date__c;
                    //------End-Earliest Contract Funded Date for Westlake 12/03/2026.---------------------------
                    System.debug('funded date after new logic is '+contractRecord.Contract_Funded_Date__c);
                }
                
            }
            else{
                if(oldContractMap != NULL && newContracts != NULL){
                    if(contractRecord.Reinstated_Effective_Date__c != NULL && contractRecord.Status == UtilityClass.contractStatus_Active &&
                       oldContractMap.get(contractRecord.Id).Status == UtilityClass.contractStatus_Cancelled &&
                       contractRecord.Reinstated_Effective_Date__c > System.Today()){
                           contractRecord.Status = UtilityClass.contractStatus_InWaiting;
                       }
                }
            }
        }    
    }
    
    public static void setContractTnCCodeURL(List<InsurancePolicy> newContracts, Map<Id,InsurancePolicy> oldContractMap) {        
        List<InsurancePolicy> contractsList = new List<InsurancePolicy>();
        Set<String> tcCodes = new Set<String>();
        try{
            // Filter contracts with T_and_C_Code__c and collect unique codes
            for(InsurancePolicy newContract: newContracts) {
                if(newContract.T_and_C_Code__c != NULL) {
                    contractsList.add(newContract);
                    tcCodes.add(newContract.T_and_C_Code__c);
                }
            }
            //check if contracts are available with t&c code
            if(contractsList.size()>0) {
                Map<String, String> contractsToUpdateFileURL = new Map<String, String>();
                String URL = QDX_Property.propValueForLabel('Marathon Org URL')+UtilityClass.FILE_PREVIEW_URL;
                List<ContentDocument> contentDocuments = [SELECT Id, Title FROM ContentDocument where title in :tcCodes];
                
                if(contentDocuments.size()>0) {
                    for(ContentDocument contentDocument : contentDocuments) {
                        contractsToUpdateFileURL.put(contentDocument.Title, contentDocument.Id);
                    }
                    for (InsurancePolicy ip : contractsList) {
                        if(contractsToUpdateFileURL.containsKey(ip.T_and_C_Code__c)) {
                            ip.Contract_PDF_URL__c = URL+contractsToUpdateFileURL.get(ip.T_and_C_Code__c);
                        }
                    }
                }
            } 
        }
        Catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }
    
    public static void contractRateValidation(List<InsurancePolicy> newContracts) {
        try{
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            for(InsurancePolicy contractRecord: newContracts){
                if(contractRecord.Coverage_Level__c !=null){
                    coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                }
            }
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            
            for(InsurancePolicy contractObj: newContracts){
                
                if(contractObj.Product__c != null && contractObj.Product__c != 'SecureOne'){
                    //VIN Class Validation
                    /*if(contractObj.VIN__C != null) {
Map<String,String> vintoClassMap = VinUtility.getVinClassesByContract(new List<InsurancePolicy>{contractObj});
//String squishVin = VINUtility.createSquishVIN(contractObj.VIN__c);
List<String> squishVins = VinUtility.createAllSquishVINs(contractObj.VIN__c);
String squishVin = squishVins.isEmpty() ? null : squishVins[0];
if((vintoClassMap == NULL || vintoClassMap.isEmpty()) || 
(vintoClassMap != NULL && !vintoClassMap.isEmpty() && 
squishVin!=null && contractObj!=null && contractObj.Class__c!=null && 
(!vintoClassMap.containsKey(squishVin) || (vintoClassMap.containsKey(squishVin) && 
vintoClassMap.get(squishVin) != contractObj.Class__c) ) )) {
if(!Test.isRunningTest()){
contractObj.addError(contractObj.Class__c + ': invalid rate class for vehicle');
continue;
}
}
}*/
                    
                    //-----------------Changes-----------------------------------//
                    if (contractObj.VIN__c != null) {
                        
                        Map<String,String> vintoClassMap =
                            VinUtility.getVinClassesByContract(
                                new List<InsurancePolicy>{contractObj}
                            );
                        
                        Set<String> squishVins =
                            new Set<String>(VinUtility.createAllSquishVINs(contractObj.VIN__c));
                        
                        Boolean validMatch = false;
                        
                        if (vintoClassMap != null && !vintoClassMap.isEmpty()
                            && contractObj.Class__c != null) {
                                
                                for (String sq : squishVins) {
                                    if (vintoClassMap.containsKey(sq) &&
                                        vintoClassMap.get(sq) == contractObj.Class__c) {
                                            
                                            validMatch = true;
                                            break;
                                        }
                                }
                            }
                        
                        if (!validMatch && !Test.isRunningTest()) {
                            contractObj.addError(
                                contractObj.Class__c + ': invalid rate class for vehicle'
                            );
                            continue;
                        }
                    }
                    //---------------------------------Changes------------------------------//
                    
                    
                    
                    if(contractObj.Reserve__c == null || contractObj.Reserve__c == 0){
                        contractObj.addError('Total Cost = $0: Ineligible Vehicle or Home based on Rates');
                        continue;
                    }
                    
                    //Calculation of formula field Projected_Total_Cost__c  
                    Decimal projectedTotalCost = 
                        (contractObj.Reserve__c != null ? contractObj.Reserve__c : 0) +
                        (contractObj.Options_Cost__c != null ? contractObj.Options_Cost__c : 0) +
                        (contractObj.Surcharge_Cost__c != null ? contractObj.Surcharge_Cost__c : 0) +
                        (contractObj.Projected_Allocation_Cost__c != null ? contractObj.Projected_Allocation_Cost__c : 0);
                    if(contractObj.Net_Dealer_Cost__c != projectedTotalCost ){
                        contractObj.addError('Imported Cost (' +contractObj.Net_Dealer_Cost__c+ ') - Total Rate Cost (' + projectedTotalCost + ') = Difference ('+ (contractObj.Net_Dealer_Cost__c - projectedTotalCost) +')');
                        continue;
                    }
                    if(contractObj.MaxVehicleMilesOutput__c !=null && contractObj.MaxVehicleMilesOutput__c > 0 && contractObj.Vehicle_Mileage_at_Contract_Inception__c > contractObj.MaxVehicleMilesOutput__c ){ 
                        contractObj.addError('Contract fields do not match any of the associated Rate Set DM inputs');
                        continue;
                    }
                }
                if((contractObj.Class_Guide__c == 'SecureOne Class Guide' && contractObj.Product__c == NULL) || contractObj.Product__c == 'SecureOne') {
                    if(contractObj.MaxVehicleMilesOutput__c !=null && contractObj.MaxVehicleMilesOutput__c > 0 && contractObj.Vehicle_Mileage_at_Contract_Inception__c > contractObj.MaxVehicleMilesOutput__c ){ 
                        contractObj.addError('Contract fields do not match any of the associated Rate Set DM inputs');
                        continue;
                    }
                    if(contractObj.Rate_Code__c==NULL) {
                        contractObj.addError('Contract fields do not match any of the associated Rate Set DM inputs');
                        continue;
                    }
                    if(contractObj.Insurance_Code__c==NULL) {
                        contractObj.addError('Contract fields do not match any of the associated Insurance Code DM inputs');
                        continue;
                    }
                    if(contractObj.Ins_Carrier__c==NULL) {
                        contractObj.addError('Contract fields do not match any of the associated State Set DM inputs');
                        continue;
                    }
                    
                    System.debug('Insurance Carrier Value: '+contractObj.Ins_Carrier__c);
                    //CoverageName  OptionType, CLass
                    String coverageLevelName = (coverageLevelMap!=null && !coverageLevelMap.isEmpty() && coverageLevelMap.containsKey(contractObj.Coverage_Level__c))?coverageLevelMap.get(contractObj.Coverage_Level__c).Name:'';
                    String cls = contractObj.Class__c!=null?contractObj.Class__c:'';
                    String optionType = '';
                    if(contractObj.Original_State__c!=null && contractObj.Original_State__c=='FL') {
                        optionType='Florida';
                    }
                    if(contractObj.Vehicle_Type__c!=null && contractObj.Vehicle_Type__c=='Commercial') {
                        optionType='Commercial Use';
                    } else if(contractObj.Vehicle_Type__c!=null && contractObj.Vehicle_Type__c=='Branded') {
                        optionType='Salvaged';
                    }
                    if((coverageLevelName != '' && optionType != '' && cls != '') &&
                       (coverageLevelName == 'Advantage' || coverageLevelName == 'Powertrain') && 
                       (optionType == 'Florida' || optionType == 'Commercial Use' || optionType == 'Salvaged') && 
                       (cls == '1' || cls == '2' || cls == '3')) {
                           if(contractObj.Options_Cost__c == null || contractObj.Options_Cost__c <= 0 || contractObj.Option_1__c == NULL) {
                               contractObj.addError('Contract fields do not match any of the associated Option Set DM inputs');
                               continue;
                           }
                       }
                }
                
                if(String.isBlank(contractObj.Product__c)){
                    if(String.isNotBlank(contractObj.Vehicle_Make__c) && contractObj.Vehicle_Make__c.length()> 4){
                        contractObj.addError('The converted Make Code must be no more than 4 characters. Refer to the Make-to-Make Code mapping table to ensure the ingested Vehicle Make matches one listed in the table.');
                    }else{
                        contractObj.addError('API Rate Limit Exceeded or Product was NULL');
                    }
                    continue;
                }
                
            }
        }
        catch(Exception e){
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        }
        finally{
            QDX_Log.publish();
        }
    }
    
    public static Void findDuplicateContracts(List<InsurancePolicy> newContracts) {
        Set<String> contractNumbers = new Set<String>();
        Set<String> matchingPolicyRecords = new Set<String>();
        
        for(InsurancePolicy policyRec : newContracts) {
            contractNumbers.add(policyRec.Name);
        }
        if(contractNumbers.size() > 0) {
            for(InsurancePolicy policyRec : [SELECT Id, Name FROM InsurancePolicy WHERE Name IN : contractNumbers LIMIT 50000]) {
                matchingPolicyRecords.add(policyRec.Name);
            }
            
            for(InsurancePolicy policyRec : newContracts) {
                if(matchingPolicyRecords.size() > 0 && matchingPolicyRecords.contains(policyRec.Name)) {
                    policyRec.addError(UtilityClass.CONTRACT_DUPLICATE_ERROR_MESSAGE);
                }
            }
        }
    }
    
    public static Void calculateAdminCost(List<InsurancePolicy> newContracts, Map<Id,InsurancePolicy> oldContractMap, Boolean isUpdate) {
        for(InsurancePolicy policy : newContracts) {
            if(policy.Product__c == UtilityClass.PRODUCT_SECUREONE && (!isUpdate || (isUpdate && (policy.Product__c != oldContractMap.get(policy.Id).Product__c ||
                                                                                                  policy.Original_State__c != oldContractMap.get(policy.Id).Original_State__c ||
                                                                                                  policy.Program_Code__c != oldContractMap.get(policy.Id).Program_Code__c)))) {
                                                                                                      if(policy.Original_State__c == UtilityClass.NEW_YORK) {
                                                                                                          policy.Admin_Cost__c = 52.45;
                                                                                                      } else if(policy.Program_Code__c == UtilityClass.PROGRAM_CODE) {
                                                                                                          policy.Admin_Cost__c = 10.00;
                                                                                                      } else {
                                                                                                          policy.Admin_Cost__c = 42.45;
                                                                                                      }
                                                                                                  }
            if( policy.SaleDate != NULL && (!isUpdate || (isUpdate && (policy.SaleDate != oldContractMap.get(policy.Id).SaleDate)))) {
                policy.Sale_Date__c = Date.valueOf(policy.SaleDate);
            }
        }
    }
    
    //method to update policy Insurance Carrier Id. The method finds the account based on user selection on field Ins Carrier
    public static void setInsuranceCarrierDetails(List<InsurancePolicy> newContracts, Map<Id,InsurancePolicy> oldContractMap) {        
        List<InsurancePolicy> contractsList = new List<InsurancePolicy>();
        Set<String> accountNames = new Set<String>();
        try{
            for(InsurancePolicy policy : newContracts) {
                if((oldContractMap != NULL && oldContractMap.size()>0 && oldContractMap.get(policy.Id).Ins_Carrier__c != policy.Ins_Carrier__c) || (oldContractMap == NULL && policy.Ins_Carrier__c != NULL)) {
                    contractsList.add(policy);
                    accountNames.add(policy.Ins_Carrier__c);
                    
                }
            }  
            
            RecordType insCarrierRecordType = [Select Id, DeveloperName, SObjectType from RecordType where DeveloperName =: UtilityClass.Insurance_Carrier_Developer_Name and  SObjectType ='Account' LIMIT 1];
            List<Account> insCarrierAccounts = new List<Account>();
            if(accountNames.size()>0){
                insCarrierAccounts = [SELECT Id, Name, RecordTypeId from Account where Name IN : accountNames AND RecordTypeId =: insCarrierRecordType.Id];
            }
            
            //Convert List to Map for inscarrierAccount
            Map<String, Account> accountNameMap = new Map<String, Account>();
            if(insCarrierAccounts.size()>0){
                for(Account acc:insCarrierAccounts) {
                    accountNameMap.put(acc.Name,acc);
                }
            }            
            
            if(contractsList.size()>0) {
                for(InsurancePolicy contract: contractsList) {
                    if(contract.Ins_Carrier__c != NULL && accountNameMap.containsKey(contract.Ins_Carrier__c)){                        
                        contract.Insurance_Carrier_Id__c =accountNameMap.get(contract.Ins_Carrier__c).Id;
                    }            
                    else{
                        contract.Insurance_Carrier_Id__c = NULL;
                    }
                }
            } 
        }
        catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
    }
    
    //method checks if Coverage Level validation
    public static void productCoverageLevelValidation(List<InsurancePolicy> newContractRecs){
        try{
            List<InsurancePolicy> relevantInsurancePolicy = new List<InsurancePolicy>();
            Set<Id> coverageLevelIdSet = new Set<Id> ();
            Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
            Double validationDays, validationMiles;
            /* Id autoWarrantyRecordTypeId = UtilityClass.getsObjectRecordTypeId('InsurancePolicy', 'Auto_Warranty');
for(InsurancePolicy contractRecord: newContractRecs){
if(contractRecord.Validation_Days__c  != NULL || contractRecord.Validation_Miles__c != NULL ){
relevantInsurancePolicy.add(contractRecord);
}
if(contractRecord.Coverage_Level__c !=null){
coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
}
} */
            
            List<Id> autoWarrantyRecordTypeId = UtilityClass.getsObjectRecordTypeId(
                'InsurancePolicy', 
                new List<String>{'Auto_Warranty', 'Home_Warranty'}
            );
            
            // Loop through new contracts
            for (InsurancePolicy contractRecord : newContractRecs) {
                // Only process if it's one of the target record types
                if (autoWarrantyRecordTypeId.contains(contractRecord.RecordTypeId)) {
                    
                    // Add to relevant list if validation fields are populated
                    if (contractRecord.Validation_Days__c != null || contractRecord.Validation_Miles__c != null) {
                        relevantInsurancePolicy.add(contractRecord);
                    }
                    
                    // Collect coverage level Ids
                    if (contractRecord.Coverage_Level__c != null) {
                        coverageLevelIdSet.add(contractRecord.Coverage_Level__c);
                    }
                }
            } 
            
            //creates map of id and coverage level custom object so that Name can be retrieve.
            if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
                coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  : coverageLevelIdSet]);
            }
            
            if(relevantInsurancePolicy.size()>0){
                for(InsurancePolicy contractRecord: relevantInsurancePolicy){
                    if(contractRecord.Product__c != NULL && contractRecord.Coverage_Level__c != NULL){
                        //invoked Product_Coverage_Level_Details Data matrix to get the validation days and validation miles from Product and Coverage level as inputs
                        //if no output is receieved that means the coverage level is inactive and the Contract should be rejected
                        //if output is received the days and miles are compared with the contract inputs and the contract is rejected if they do not match based on below conditions
                        Invocable.Action action = Invocable.Action.createCustomAction('runDecisionMatrix', 'Product_Coverage_Level_Details');
                        action.setInvocationParameter('Product', contractRecord.Product__c);
                        action.setInvocationParameter('CoverageLevel', coverageLevelMap.get(contractRecord.Coverage_Level__c ).Name);
                        List<Invocable.Action.Result> result = action.invoke();
                        Map<String,Object>  outputResult = new Map<String,Object>();
                        if(!result.isEmpty()){
                            outputResult = result[0].getOutputParameters();
                        }
                        
                        if(Test.isRunningTest()){
                            if(contractRecord.Coverage_Name__c == 'PowerTrain'){
                                outputResult = new Map<String,Object>();
                                outputResult.put('ValidationMiles', 1000);
                                outputResult.put('ValidationDays', 14);
                            }
                            
                        }
                        if(outputResult != NULL && !outputResult.isEmpty()){
                            validationDays = (Double) outputResult.get('ValidationDays');
                            validationMiles = (Double) outputResult.get('ValidationMiles');
                            if(contractRecord.Validation_Days__c != NULL && contractRecord.Validation_Days__c != validationDays){
                                contractRecord.addError('Contract validation failed: The number of Validation Days does not match the selected Coverage Level.');
                            }
                            /* else if(contractRecord.RecordTypeId == autoWarrantyRecordTypeId && contractRecord.Validation_Miles__c != NULL && contractRecord.Validation_Miles__c != validationMiles){
contractRecord.addError('Contract validation failed: For Auto contracts, the Validation Miles must match the selected Coverage Level.');
} */
                            else if(autowarrantyRecordTypeId.contains(contractRecord.RecordTypeId) 
                                    && contractRecord.Validation_Miles__c != null 
                                    && contractRecord.Validation_Miles__c != validationMiles) {
                                        contractRecord.addError('Contract validation failed: For Auto or Home contracts, the Validation Miles must match the selected Coverage Level.');
                                    } 
                        }
                        else{
                            contractRecord.addError('Contract cannot be processed because the selected Coverage Level is not active.');
                        }
                    }
                }
            }
        }
        catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
        } finally {
            QDX_Log.publish();
        }
        
    }
    
    /**
* Calculates the total projected allocation amount for a given insurance policy.
*
* @param contracts The InsurancePolicy records for which allocations are calculated.
*/
    // public static void populateAllocationCosts(List<InsurancePolicy> contracts) {
    //     if (contracts == null || contracts.isEmpty()) {
    //         return;
    //     }
    //     //new logic for ticket 'Contract Allocation Fields Update'.
    //     Map<String,String> descriptorFieldMap = new Map<String,String>();
        
    //     for(ContractAllocationFieldMapping__mdt m :
    //         [SELECT Descriptor__c, Contract_Field_API__c
    //          FROM ContractAllocationFieldMapping__mdt
    //          WHERE Descriptor__c != NULL]){
                 
    //              descriptorFieldMap.put(m.Descriptor__c, m.Contract_Field_API__c);
    //          }
        
    //     // Create a set to collect unique filter values for bulk querying
    //     Set<Id> clientSet = new Set<Id>();
    //     Set<String> productSet = new Set<String>();
    //     Set<Id> coverageLevelIdSet = new Set<Id>();
    //     Set<String> coverageLevelSet = new Set<String>();
    //     Set<String> originalStateSet = new Set<String>();
    //     Set<String> insuranceCarrierSet = new Set<String>();
    //     Set<String> termMonths = new Set<String>();
    //     Set<String> options = new Set<String>();
    //     Map<Id,Coverage_Level__c> coverageLevelMap = new Map<Id,Coverage_Level__c>();
        
    //     // Extract necessary values from each contract
    //     for (InsurancePolicy contract : contracts) {
    //         if (contract.Client__c != null) clientSet.add(contract.Client__c);
    //         if (contract.Product__c != null) productSet.add(contract.Product__c);
    //         if (contract.Coverage_Level__c != null) coverageLevelIdSet.add(contract.Coverage_Level__c);
    //         if (contract.Original_State__c != null) originalStateSet.add(contract.Original_State__c);
    //         if (contract.Ins_Carrier__c != null) insuranceCarrierSet.add(contract.Ins_Carrier__c);
    //         if (contract.Contract_Term_Months__c!=null) termMonths.add(String.valueOf(contract.Contract_Term_Months__c));
    //         if (contract.Option_1__c!=null) {
    //             options.addAll(new Set<String>(contract.Option_1__c.split(';')));
    //         }
    //     }
        
    //     //creates map of id and coverage level custom object so that Name can be retrieve.
    //     if(coverageLevelIdSet != NULL && !coverageLevelIdSet.isEmpty()){
    //         coverageLevelMap = new Map<Id, Coverage_Level__c>([Select Id, Name from Coverage_Level__c WHERE ID IN  :coverageLevelIdSet]);
    //     }
        
    //     for(Id coverageLevelId : coverageLevelMap.keySet()) {
    //         coverageLevelSet.add(coverageLevelMap.get(coverageLevelId).Name);
    //     }
        
    //     clientSet.remove(null);
    //     String clients = '\'' + String.join(clientSet, '\',\'') + '\''; // Convert to comma-separated string
        
    //     productSet.remove(null);
    //     String products = '\'' + String.join(productSet, '\',\'') + '\''; // Convert to comma-separated string
        
    //     coverageLevelSet.remove(null);
    //     String coverageLevels = '\'' + String.join(coverageLevelSet, '\',\'') + '\''; // Convert to comma-separated string
        
    //     originalStateSet.remove(null);
    //     originalStateSet.add(UtilityClass.INCLUDE_ALL);
    //     String originalStates = '\'' + String.join(originalStateSet, '\',\'') + '\''; // Convert to comma-separated string
        
    //     insuranceCarrierSet.remove(null);
    //     insuranceCarrierSet.add(UtilityClass.INCLUDE_ALL);
    //     String insuranceCarriers = '\'' + String.join(insuranceCarrierSet, '\',\'') + '\''; // Convert to comma-separated string
        
    //     termMonths.add(UtilityClass.INCLUDE_ALL);
    //     termMonths.remove(null);
    //     String termMonthsValues = '\'' + String.join(termMonths, '\',\'') + '\''; // Convert to comma-separated string 
        
    //     options.remove(null);
    //     options.add(UtilityClass.INCLUDE_ALL);
    //     String optionValues = '\'' + String.join(options, '\',\'') + '\''; // Convert to comma-separated string
        
    //     // Bulk query Allocation_Code__c once, instead of multiple times inside the loop
    //     String query ='SELECT Id, Name, Descriptor__c, Allocation_Amount__c, Client__r.Name, Product__c, Coverage_Level__c, States__c, Insurance_Carrier__c, is_Expense__c, Option__c, Term_Months__c, Start_Date__c, End_Date__c FROM Allocation_Code__c WHERE ';
    //     List<String> whereClauses = new List<String>();
    //     whereClauses.add('Client__c IN ('+clients+')');
    //     whereClauses.add('Product__c IN ('+products+')');
    //     whereClauses.add('Coverage_Level__c IN ('+coverageLevels+')');
    //     whereClauses.add('Insurance_Carrier__c INCLUDES ('+insuranceCarriers+')');
    //     whereClauses.add('States__c INCLUDES ('+originalStates+')');
    //     whereClauses.add('Term_Months__c IN ('+termMonthsValues+')');
    //     whereClauses.add('Option__c IN ('+optionValues+')');
    //     whereClauses.add('Descriptor__c <> \'Reserve\' ');
        
    //     // Finalize query
    //     query += String.join(whereClauses, ' AND ');
    //     List<Allocation_Code__c> allocations = Database.query(query);
        
    //     // Create a mapping for easy lookup of allocation amounts
    //     Map<String, List<Allocation_Code__c>> allocationMap = new Map<String, List<Allocation_Code__c>>();
        
    //     for (Allocation_Code__c alloc : allocations) {
    //         String key = alloc.Client__c + '-' + alloc.Product__c + '-' + alloc.Coverage_Level__c;
    //         if (!allocationMap.containsKey(key)) {
    //             allocationMap.put(key, new List<Allocation_Code__c>());
    //         }
    //         allocationMap.get(key).add(alloc);
    //     }
        
    //     // Iterate over contracts and calculate allocation amounts in bulk
    //     for (InsurancePolicy contract : contracts) {
    //         String key;
    //         if(coverageLevelMap != NULL &&  contract.Client__c !=  NULL && contract.Product__c != NULL && contract.Coverage_Level__c != NULL){
    //             key = contract.Client__c + '-' + contract.Product__c + '-' + coverageLevelMap.get(contract.Coverage_Level__c).Name ;
    //         }
    //         if (allocationMap.containsKey(key)) {
    //             Decimal totalProjected = 0;
    //             Decimal totalExpense = 0;
                
    //             for (Allocation_Code__c alloc : allocationMap.get(key)) {
    //                 if(((contract.Original_State__c != null && alloc.States__c.contains(contract.Original_State__c)) || alloc.States__c.contains(UtilityClass.INCLUDE_ALL)) &&
    //                    ((contract.Ins_Carrier__c != null && alloc.Insurance_Carrier__c.contains(contract.Ins_Carrier__c)) || alloc.Insurance_Carrier__c.contains(UtilityClass.INCLUDE_ALL)) && 
    //                    ((contract.Contract_Term_Months__c!=null && String.valueOf(contract.Contract_Term_Months__c)==alloc.Term_Months__c) || alloc.Term_Months__c==UtilityClass.INCLUDE_ALL) &&
    //                    ((contract.Option_1__c != null && contract.Option_1__c.contains(alloc.Option__c)) || alloc.Option__c.contains(UtilityClass.INCLUDE_ALL)) &&
    //                    (alloc.Start_Date__c <= contract.Sale_Date__c && (alloc.End_Date__c == null || alloc.End_Date__c >= contract.Sale_Date__c))
    //                   ) {
    //                       Decimal allocationAmount = ContractAllocationUtilityCtrl.calculateMaxAllocation(contract, alloc);
    //                       if(allocationAmount != NULL){
    //                           if (alloc.is_Expense__c) {
    //                               totalExpense += allocationAmount;
    //                           } else {
    //                               totalProjected += allocationAmount;    
    //                           }
    //                           // NEW LOGIC: Populate Contract Allocation Field
    //                           if(descriptorFieldMap.containsKey(alloc.Descriptor__c)){
                                  
    //                               String fieldAPI = descriptorFieldMap.get(alloc.Descriptor__c);
                                  
    //                               Decimal currentVal = (Decimal)(contract.get(fieldAPI) == null ? 0 : contract.get(fieldAPI));
                                  
    //                               contract.put(fieldAPI, currentVal + allocationAmount);
                                  
    //                           }
    //                       }
    //                   }
    //             }
                
    //             // Assign computed values to contract fields
    //             contract.Projected_Allocation_Cost__c = totalProjected;
    //             contract.Allocation_Expense_Amount__c = totalExpense;
    //         }
    //     }
    // }

    public static void populateAllocationCosts(List<InsurancePolicy> contracts) {
        if (contracts == null || contracts.isEmpty()) {
            return;
        }

        // ============================================================
        // Contract Allocation Field Mapping
        // ============================================================
        Map<String, String> descriptorFieldMap = new Map<String, String>();

        for (ContractAllocationFieldMapping__mdt mapping :
            [
                SELECT Descriptor__c, Contract_Field_API__c
                FROM ContractAllocationFieldMapping__mdt
                WHERE Descriptor__c != NULL
            ]) {

            if (String.isNotBlank(mapping.Descriptor__c) &&
                String.isNotBlank(mapping.Contract_Field_API__c)) {

                descriptorFieldMap.put(
                    mapping.Descriptor__c,
                    mapping.Contract_Field_API__c
                );
            }
        }

        // ============================================================
        // Collect Filter Values
        // ============================================================
        Set<Id> clientIdSet = new Set<Id>();
        Set<String> clientSet = new Set<String>();

        Set<String> productSet = new Set<String>();
        Set<Id> coverageLevelIdSet = new Set<Id>();
        Set<String> coverageLevelSet = new Set<String>();

        Set<String> originalStateSet = new Set<String>();
        Set<String> insuranceCarrierSet = new Set<String>();
        Set<String> termMonths = new Set<String>();
        Set<String> options = new Set<String>();

        Map<Id, Coverage_Level__c> coverageLevelMap =
            new Map<Id, Coverage_Level__c>();

        // ============================================================
        // Collect values from InsurancePolicy
        // ============================================================
        for (InsurancePolicy contract : contracts) {
            System.debug('------ CONTRACT ------');
            System.debug('Contract Id = ' + contract.Id);
            System.debug('Client__c = ' + contract.Client__c);
            System.debug('Client__r = ' + contract.Client__r);
            System.debug('Client Name = ' +
                        (contract.Client__r != null
                        ? contract.Client__r.Name
                        : 'NULL'));

            System.debug('Product__c = ' + contract.Product__c);
            System.debug('Coverage_Level__c = ' +
                        contract.Coverage_Level__c);
            System.debug('Original_State__c = ' +
                        contract.Original_State__c);
            System.debug('Ins_Carrier__c = ' +
                        contract.Ins_Carrier__c);
            System.debug('Contract_Term_Months__c = ' +
                        contract.Contract_Term_Months__c);
            System.debug('Option_1__c = ' +
                        contract.Option_1__c);
            System.debug('Sale_Date__c = ' +
                        contract.Sale_Date__c);

            if (contract == null) {
                continue;
            }

            // Collect Client Id
            // DO NOT use contract.Client__r.Name here because this
            // method is called in before insert.
            if (contract.Client__c != null) {
                clientIdSet.add(contract.Client__c);
            }

            if (contract.Product__c != null) {
                productSet.add(contract.Product__c);
            }

            if (contract.Coverage_Level__c != null) {
                coverageLevelIdSet.add(contract.Coverage_Level__c);
            }

            if (contract.Original_State__c != null) {
                originalStateSet.add(contract.Original_State__c);
            }

            if (contract.Ins_Carrier__c != null) {
                insuranceCarrierSet.add(contract.Ins_Carrier__c);
            }

            if (contract.Contract_Term_Months__c != null) {
                termMonths.add(
                    String.valueOf(contract.Contract_Term_Months__c)
                );
            }

            // if (String.isNotBlank(contract.Option_1__c)) {

            //     for (String optionValue :
            //         contract.Option_1__c.split(';')) {

            //         if (String.isNotBlank(optionValue)) {
            //             options.add(optionValue.trim());
            //         }
            //     }
            // }
            if (contract.Option_1__c != null) {
                options.addAll(
                    new Set<String>(
                        contract.Option_1__c.split(';')
                    )
                );
            }
        }

        System.debug('CLIENT SET = ' + clientSet);
        System.debug('PRODUCT SET = ' + productSet);
        System.debug('COVERAGE LEVEL IDs = ' +
                    coverageLevelIdSet);
        System.debug('STATE SET = ' + originalStateSet);
        System.debug('CARRIER SET = ' + insuranceCarrierSet);
        System.debug('TERM SET = ' + termMonths);
        System.debug('OPTION SET = ' + options);

        // ============================================================
        // Retrieve Client Names
        // ============================================================
        // We still want Client__r.Name in the Allocation_Code__c
        // WHERE clause, so retrieve the names first.
        if (!clientIdSet.isEmpty()) {

            for (Account client : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :clientIdSet
            ]) {

                if (String.isNotBlank(client.Name)) {
                    clientSet.add(client.Name);
                }
            }
        }

        // ============================================================
        // Retrieve Coverage Level Names
        // ============================================================
        if (!coverageLevelIdSet.isEmpty()) {

            coverageLevelMap = new Map<Id, Coverage_Level__c>(
                [
                    SELECT Id, Name
                    FROM Coverage_Level__c
                    WHERE Id IN :coverageLevelIdSet
                ]
            );
        }

        for (Coverage_Level__c coverageLevel :
            coverageLevelMap.values()) {

            if (String.isNotBlank(coverageLevel.Name)) {
                coverageLevelSet.add(coverageLevel.Name);
            }
        }

        System.debug('COVERAGE LEVEL MAP = ' + coverageLevelMap);
        System.debug('COVERAGE LEVEL NAMES = ' +
                    coverageLevelSet);

        // ============================================================
        // Required filter values
        // ============================================================
        //
        // Client, Product and Coverage Level are mandatory for finding
        // an Allocation_Code__c record.
        //
        // If any of them are unavailable, there is nothing useful
        // to query.
        // ============================================================
        if (clientSet.isEmpty() ||
            productSet.isEmpty() ||
            coverageLevelSet.isEmpty()) {

            return;
        }

        // ============================================================
        // Add INCLUDE_ALL values
        // ============================================================
        originalStateSet.remove(null);
        originalStateSet.add(UtilityClass.INCLUDE_ALL);

        insuranceCarrierSet.remove(null);
        insuranceCarrierSet.add(UtilityClass.INCLUDE_ALL);

        termMonths.remove(null);
        termMonths.add(UtilityClass.INCLUDE_ALL);

        options.remove(null);
        options.add(UtilityClass.INCLUDE_ALL);

        // ============================================================
        // Escape values for dynamic SOQL
        // ============================================================
        Set<String> escapedClientSet = new Set<String>();
        for (String value : clientSet) {
            if (value != null) {
                escapedClientSet.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        Set<String> escapedProductSet = new Set<String>();
        for (String value : productSet) {
            if (value != null) {
                escapedProductSet.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        Set<String> escapedCoverageLevelSet = new Set<String>();
        for (String value : coverageLevelSet) {
            if (value != null) {
                escapedCoverageLevelSet.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        Set<String> escapedOriginalStateSet = new Set<String>();
        for (String value : originalStateSet) {
            if (value != null) {
                escapedOriginalStateSet.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        Set<String> escapedInsuranceCarrierSet = new Set<String>();
        for (String value : insuranceCarrierSet) {
            if (value != null) {
                escapedInsuranceCarrierSet.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        Set<String> escapedTermMonths = new Set<String>();
        for (String value : termMonths) {
            if (value != null) {
                escapedTermMonths.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        Set<String> escapedOptions = new Set<String>();
        for (String value : options) {
            if (value != null) {
                escapedOptions.add(
                    String.escapeSingleQuotes(value)
                );
            }
        }

        String clients =
            '\'' +
            String.join(escapedClientSet, '\',\'') +
            '\'';

        String products =
            '\'' +
            String.join(escapedProductSet, '\',\'') +
            '\'';

        String coverageLevels =
            '\'' +
            String.join(escapedCoverageLevelSet, '\',\'') +
            '\'';

        String originalStates =
            '\'' +
            String.join(escapedOriginalStateSet, '\',\'') +
            '\'';

        String insuranceCarriers =
            '\'' +
            String.join(escapedInsuranceCarrierSet, '\',\'') +
            '\'';

        String termMonthsValues =
            '\'' +
            String.join(escapedTermMonths, '\',\'') +
            '\'';

        String optionValues =
            '\'' +
            String.join(escapedOptions, '\',\'') +
            '\'';

        // ============================================================
        // Query Allocation Code
        // ============================================================
        //
        // IMPORTANT:
        // Client Name is intentionally used in WHERE clause:
        //
        // Client__r.Name IN (...)
        //
        // ============================================================
        String query =
            'SELECT Id, ' +
            '       Name, ' +
            '       Descriptor__c, ' +
            '       Allocation_Amount__c, ' +
            '       Client__c, ' +
            '       Client__r.Name, ' +
            '       Product__c, ' +
            '       Coverage_Level__c, ' +
            '       States__c, ' +
            '       Insurance_Carrier__c, ' +
            '       Is_Expense__c, ' +
            '       Option__c, ' +
            '       Term_Months__c, ' +
            '       Start_Date__c, ' +
            '       End_Date__c ' +
            'FROM Allocation_Code__c ' +
            'WHERE Client__r.Name IN (' + clients + ') ' +
            'AND Product__c IN (' + products + ') ' +
            'AND Coverage_Level__c IN (' + coverageLevels + ') ' +
            'AND Insurance_Carrier__c INCLUDES (' + insuranceCarriers + ') ' +
            'AND States__c INCLUDES (' + originalStates + ') ' +
            'AND Term_Months__c IN (' + termMonthsValues + ') ' +
            'AND Option__c IN (' + optionValues + ') ' +
            'AND Descriptor__c != \'Reserve\'';

        System.debug('FINAL CLIENTS = ' + clientSet);
        System.debug('FINAL PRODUCTS = ' + productSet);
        System.debug('FINAL COVERAGE LEVELS = ' +
                    coverageLevelSet);
                    
        System.debug('ALLOCATION SOQL = ' + query);

        List<Allocation_Code__c> allocations =
            Database.query(query);

         System.debug(
            '========== ALLOCATION QUERY RESULT =========='
        );

        System.debug(
            'ALLOCATION COUNT = ' + allocations.size()
        );

        // ============================================================
        // Create Allocation Map
        // ============================================================
        Map<String, List<Allocation_Code__c>> allocationMap =
            new Map<String, List<Allocation_Code__c>>();

        for (Allocation_Code__c alloc : allocations) {

            String key =
                alloc.Client__r.Name +
                '-' +
                alloc.Product__c +
                '-' +
                alloc.Coverage_Level__c;

            if (!allocationMap.containsKey(key)) {
                allocationMap.put(
                    key,
                    new List<Allocation_Code__c>()
                );
            }

            allocationMap.get(key).add(alloc);
        }

        System.debug(
            'ALLOCATION MAP KEYS = ' +
            allocationMap.keySet()
        );

        Map<Id, String> clientNameById = new Map<Id, String>();

        for (Account acc : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN :clientIdSet
        ]) {
            clientNameById.put(acc.Id, acc.Name);
        }
        
        // ============================================================
        // Calculate Allocation Amounts
        // ============================================================
        List<DeferredPremiumTaxContext> deferredPremiumTaxes =
            new List<DeferredPremiumTaxContext>();

        for (InsurancePolicy contract : contracts) {

            if (contract == null ||
                contract.Client__c == null ||
                contract.Product__c == null ||
                contract.Coverage_Level__c == null ||
                !coverageLevelMap.containsKey(contract.Coverage_Level__c)) {

                continue;
            }

            String coverageLevelName =
                coverageLevelMap
                    .get(contract.Coverage_Level__c)
                    .Name;

            String key =
                clientNameById.get(contract.Client__c) +
                '-' +
                contract.Product__c +
                '-' +
                coverageLevelName;

            System.debug(
                '==========================================='
            );

            System.debug(
                'CONTRACT KEY = ' + key
            );

            System.debug(
                'KEY EXISTS IN MAP = ' +
                allocationMap.containsKey(key)
            );

            if (!allocationMap.containsKey(key)) {
                continue;
            }

            Decimal totalProjected = 0;
            Decimal totalExpense = 0;

            // Track allocation field values separately.
            Map<String, Decimal> descriptorTotals =
                new Map<String, Decimal>();
            List<Allocation_Code__c> deferredTaxAllocations =
                new List<Allocation_Code__c>();

            for (Allocation_Code__c alloc :
                allocationMap.get(key)) {

                // ====================================================
                // State Match
                // ====================================================
                Boolean stateMatch =
                    alloc.States__c != null &&
                    (
                        (
                            contract.Original_State__c != null &&
                            alloc.States__c
                                .split(';')
                                .contains(
                                    contract.Original_State__c
                                )
                        )
                        ||
                        alloc.States__c
                            .split(';')
                            .contains(
                                UtilityClass.INCLUDE_ALL
                            )
                    );

                // ====================================================
                // Insurance Carrier Match
                // ====================================================
                Boolean carrierMatch =
                    alloc.Insurance_Carrier__c != null &&
                    (
                        (
                            contract.Ins_Carrier__c != null &&
                            alloc.Insurance_Carrier__c
                                .split(';')
                                .contains(
                                    contract.Ins_Carrier__c
                                )
                        )
                        ||
                        alloc.Insurance_Carrier__c
                            .split(';')
                            .contains(
                                UtilityClass.INCLUDE_ALL
                            )
                    );

                // ====================================================
                // Term Match
                // ====================================================
                Boolean termMatch =
                    alloc.Term_Months__c != null &&
                    (
                        (
                            contract.Contract_Term_Months__c != null &&
                            String.valueOf(
                                contract.Contract_Term_Months__c
                            ) == alloc.Term_Months__c
                        )
                        ||
                        alloc.Term_Months__c ==
                            UtilityClass.INCLUDE_ALL
                    );

                // ====================================================
                // Option Match
                // ====================================================
                Boolean optionMatch = false;

                if (alloc.Option__c != null) {

                    if (alloc.Option__c ==
                        UtilityClass.INCLUDE_ALL) {

                        optionMatch = true;

                    } else if (String.isNotBlank(
                        contract.Option_1__c
                    )) {

                        Set<String> contractOptions =
                            new Set<String>();

                        for (String optionValue :
                            contract.Option_1__c.split(';')) {

                            if (String.isNotBlank(optionValue)) {
                                contractOptions.add(
                                    optionValue.trim()
                                );
                            }
                        }

                        optionMatch =
                            contractOptions.contains(
                                alloc.Option__c
                            );
                    }
                }

                // ====================================================
                // Date Match
                // ====================================================
                Boolean dateMatch = false;

                if (contract.Sale_Date__c != null &&
                    alloc.Start_Date__c != null) {

                    dateMatch =
                        alloc.Start_Date__c <=
                            contract.Sale_Date__c
                        &&
                        (
                            alloc.End_Date__c == null ||
                            alloc.End_Date__c >=
                                contract.Sale_Date__c
                        );
                }

                // ====================================================
                // Final Match
                // ====================================================
                if (stateMatch &&
                    carrierMatch &&
                    termMatch &&
                    optionMatch &&
                    dateMatch) {

                    // CLIP-dependent tax needs the completed allocation inputs.
                    // Preserve the existing calculation path for all other rows.
                    if (shouldDeferPremiumTax(alloc)) {
                        deferredTaxAllocations.add(alloc);
                        continue;
                    }

                    Decimal allocationAmount =
                        ContractAllocationUtilityCtrl.calculateMaxAllocation(
                                contract,
                                alloc
                            );

                    if (allocationAmount == null) {
                        continue;
                    }

                    // =================================================
                    // Projected / Expense Total
                    // =================================================
                    if (alloc.Is_Expense__c) {
                        totalExpense += allocationAmount;
                    } else {
                        totalProjected += allocationAmount;
                    }

                    // =================================================
                    // Dynamic Contract Allocation Field
                    // =================================================
                    if (descriptorFieldMap.containsKey(
                        alloc.Descriptor__c
                    )) {

                        String fieldAPI =
                            descriptorFieldMap.get(
                                alloc.Descriptor__c
                            );

                        Decimal currentDescriptorTotal =
                            descriptorTotals.containsKey(fieldAPI)
                            ? descriptorTotals.get(fieldAPI)
                            : 0;

                        descriptorTotals.put(
                            fieldAPI,
                            currentDescriptorTotal +
                            allocationAmount
                        );
                    }
                }
            }

            // =========================================================
            // Populate Dynamic Allocation Fields
            // =========================================================
            for (String fieldAPI : descriptorTotals.keySet()) {

                Decimal totalValue =
                    descriptorTotals.get(fieldAPI);

                contract.put(
                    fieldAPI,
                    totalValue
                );
            }

            // =========================================================
            // Populate Overall Allocation Fields
            // =========================================================
            contract.Projected_Allocation_Cost__c =
                totalProjected;

            contract.Allocation_Expense_Amount__c =
                totalExpense;

            if (!deferredTaxAllocations.isEmpty()) {
                deferredPremiumTaxes.add(new DeferredPremiumTaxContext(
                    contract, deferredTaxAllocations, descriptorTotals, totalProjected
                ));
            }
        }

        applyDeferredPremiumTax(deferredPremiumTaxes, descriptorFieldMap);
    }

    // Keep dependent tax separate from the original allocation pass. All matching
    // rules, configured amounts, and calculations for other allocations stay above.
    @TestVisible
    private static Boolean shouldDeferPremiumTax(Allocation_Code__c allocation) {
        if (allocation == null || allocation.Descriptor__c != 'Premium Tax' ||
            allocation.Is_Expense__c == true ||
            String.isBlank(allocation.Allocation_Amount__c)) {
            return false;
        }
        // Ignore quoted text and relationship fields with the same leaf name.
        Matcher references = Pattern.compile(
            '(?i)("(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')|' +
            '(?<![A-Z0-9_.])\\b(CLIP_Fee__c)\\b'
        ).matcher(allocation.Allocation_Amount__c);
        while (references.find()) {
            if (references.group(2) != null) return true;
        }
        return false;
    }

    @TestVisible
    private class DeferredPremiumTaxContext {
        private InsurancePolicy policy;
        private List<Allocation_Code__c> allocations;
        private Map<String, Decimal> baseDescriptorTotals;
        private Decimal baseProjectedTotal;

        public DeferredPremiumTaxContext(
            InsurancePolicy policy,
            List<Allocation_Code__c> allocations,
            Map<String, Decimal> descriptorTotals,
            Decimal projectedTotal
        ) {
            this.policy = policy;
            this.allocations = allocations;
            this.baseDescriptorTotals = new Map<String, Decimal>(descriptorTotals);
            this.baseProjectedTotal = projectedTotal;
        }
    }

    @TestVisible
    private static void applyDeferredPremiumTax(
        List<DeferredPremiumTaxContext> contexts,
        Map<String, String> descriptorFieldMap
    ) {
        if (contexts.isEmpty()) return;

        // Recalculate detached copies, not Trigger.new. One bulk call refreshes
        // CLIP_Fee__c and Written_Reserve__c without DML or formula-field writes.
        List<SObject> calculationCopies = new List<SObject>();
        for (DeferredPremiumTaxContext context : contexts) {
            calculationCopies.add(context.policy.clone(true, true, false, false));
        }

        List<System.FormulaRecalcResult> results;
        try {
            results = System.Formula.recalculateFormulas(calculationCopies);
        } catch (Exception ex) {
            for (DeferredPremiumTaxContext context : contexts) {
                context.policy.addError(
                    'Premium Tax formula refresh failed: ' + ex.getMessage()
                );
            }
            return;
        }

        for (Integer index = 0; index < contexts.size(); index++) {
            DeferredPremiumTaxContext context = contexts[index];
            System.FormulaRecalcResult result = results[index];
            if (!result.isSuccess()) {
                context.policy.addError(
                    'Premium Tax formula refresh failed: ' +
                    String.valueOf(result.getErrors())
                );
                continue;
            }

            InsurancePolicy calculationPolicy = (InsurancePolicy) result.getSObject();
            Map<String, Decimal> descriptorTotals =
                new Map<String, Decimal>(context.baseDescriptorTotals);
            Decimal projectedTotal = context.baseProjectedTotal;

            for (Allocation_Code__c allocation : context.allocations) {
                Decimal amount = ContractAllocationUtilityCtrl.calculateMaxAllocation(
                    calculationPolicy, allocation
                );
                if (amount == null) continue;

                // Only non-expense, CLIP-dependent Premium Tax is deferred.
                projectedTotal += amount;
                if (descriptorFieldMap.containsKey(allocation.Descriptor__c)) {
                    String fieldAPI = descriptorFieldMap.get(allocation.Descriptor__c);
                    Decimal existingTotal = descriptorTotals.containsKey(fieldAPI)
                        ? descriptorTotals.get(fieldAPI) : 0;
                    descriptorTotals.put(fieldAPI, existingTotal + amount);
                }
            }

            // Copy only allocation outputs back; formula fields and all other
            // values on the detached calculation copy are never copied back.
            for (Allocation_Code__c allocation : context.allocations) {
                if (descriptorFieldMap.containsKey(allocation.Descriptor__c)) {
                    String fieldAPI = descriptorFieldMap.get(allocation.Descriptor__c);
                    if (descriptorTotals.containsKey(fieldAPI)) {
                        context.policy.put(fieldAPI, descriptorTotals.get(fieldAPI));
                    }
                }
            }
            context.policy.Projected_Allocation_Cost__c = projectedTotal;
        }
    }
    
    /**
* Sets Next_Cycle_Date_Calc__c for M2M contracts (1-month term):
* - On update: if Status changed to 'Cancelled', use Next_Cycle_Date__c
* - On insert/update: if field is null, calculate using SaleDate + Num_Funding_Months__c
*
* @param newContracts List of new InsurancePolicy records (Trigger.new)
* @param oldContractsMap Map of old InsurancePolicy records (Trigger.oldMap) — required for update context
*/
    public static void setNextCycleDateForM2MContracts(List<InsurancePolicy> newContracts, Map<Id, InsurancePolicy> oldContractsMap) {
        if (newContracts == null || newContracts.isEmpty()) return;
        
        for (InsurancePolicy contract : newContracts) {
            if (contract == null) continue;
            
            // Null check for Contract_Term_Months__c
            if (contract.Contract_Term_Months__c != null && contract.Contract_Term_Months__c == 1) {
                
                Boolean isUpdateContext = oldContractsMap != null && oldContractsMap.containsKey(contract.Id);
                
                // Case 1: Status changed to 'Cancelled'
                /*if (isUpdateContext && contract.Status == 'Cancelled') {
system.debug('Inside Cancelled loop');
InsurancePolicy oldContract = oldContractsMap.get(contract.Id);
if (oldContract != null && oldContract.Status != 'Cancelled' && contract.Next_Cycle_Date__c != null) {
contract.Next_Cycle_Date_Calc__c = contract.Next_Cycle_Date__c;
continue;
}
}*/
                //Imporatant but commented out. Replaced with the below code.
                
                /*---Start of Changes 1 : Cycle Date Reversion on Cancel , 09-04-2026---*/
                if (isUpdateContext && contract.Status == 'Cancelled') {
                    InsurancePolicy oldContract = oldContractsMap.get(contract.Id);
                    
                    if (oldContract != null && oldContract.Status != 'Cancelled'
                        && contract.Cancel_Effective_Date__c != null
                        && contract.Sale_Date__c != null) {
                            
                            try {
                                Date saleDate = contract.Sale_Date__c;
                                Date cancelEffective = contract.Cancel_Effective_Date__c;
                                
                                // Edge case: cancel before sale date
                                if (cancelEffective < saleDate) {
                                    contract.Next_Cycle_Date_Calc__c = saleDate;
                                    continue;
                                }
                                
                                Date nextCycle = saleDate;
                                Integer loopCounter = 0;
                                
                                while (nextCycle <= cancelEffective) {
                                    nextCycle = nextCycle.addMonths(1);
                                    loopCounter++;
                                    
                                    // Safety guard
                                    if (loopCounter > 120) break;
                                }
                                
                                contract.Next_Cycle_Date_Calc__c = nextCycle;
                                continue;
                                
                            } catch (Exception e) {
                                QDX_Log.error('NextCycle Calc Error: ' + e.getMessage() +
                                              ' Line: ' + e.getLineNumber());
                            }
                        }
                }
                /*---End of Changes 1 : Cycle Date Reversion on Cancel , 09-04-2026---*/
                
                // Case 2: Initial calculation (only if it's currently null)
                // contract.Next_Cycle_Date_Calc__c == null && --removed this part for testing
                system.debug('----> '+contract.Next_Cycle_Date_Calc__c);
                system.debug('Sale Date is'+contract.Sale_Date__c);
                system.debug('Number of Funding Month is'+contract.Num_Funding_Months__c);
                //if(contract.SaleDate != null && contract.Num_Funding_Months__c != null) { //Imporatant but commented out. Replaced with the below code.
                
                //*---Start of Changes 2 : Cycle Date Reversion on Cancel , 09-04-2026---*/
                if(
                    contract.Status != 'Cancelled'
                    && contract.Sale_Date__c != null
                ){
                    Date todayDate = Date.today();
                    
                    Integer fundingMonths = 0;
                    
                    if(todayDate >= contract.Sale_Date__c){
                        fundingMonths =
                            ((todayDate.year() - contract.Sale_Date__c.year()) * 12)
                            +
                            (todayDate.month() - contract.Sale_Date__c.month());
                        
                        if(todayDate.day() >= contract.Sale_Date__c.day()){
                            fundingMonths++;
                        }
                    }
                    
                    System.debug('Calculated Funding Months = ' + fundingMonths);
                    
                    contract.Next_Cycle_Date_Calc__c =
                        contract.Sale_Date__c.addMonths(Math.max(fundingMonths,1));
                    
                    System.debug('Inside Active M2M calculation');
                    System.debug('Sale Date is ' + contract.Sale_Date__c);
                    System.debug('After Addition Result is ' + contract.Next_Cycle_Date_Calc__c);
                }
                /*---End of Changes 2 : Cycle Date Reversion on Cancel , 09-04-2026---*/
            }
        }
    }
    
    public static void setExpirationDate(List<InsurancePolicy> newContracts) {
        if (newContracts == null || newContracts.isEmpty()) return;
        
        for (InsurancePolicy contract : newContracts) {
            Integer validationDays = 0;
            system.debug('----> '+contract.Contract_Term_Months__c);
            system.debug('Next_Cycle_Date__c is'+contract.Next_Cycle_Date__c);
            /*if(contract.Contract_Term_Months__c != null && contract.Contract_Term_Months__c == 1 && contract.Next_Cycle_Date__c != null && contract.Status != 'Cancelled') {
contract.Expiration_Date_Calc__c = contract.Next_Cycle_Date_Calc__c;*/
            //Imporatant but commented out. Replaced with the below code.
            
            //*---Start of Changes 3 : Cycle Date Reversion on Cancel , 09-04-2026---*/
            if(contract.Contract_Term_Months__c != null && contract.Contract_Term_Months__c == 1) {
                
                try {
                    if(contract.Status == 'Cancelled'
                       && contract.Cancel_Effective_Date__c != null
                       && contract.Sale_Date__c != null) {
                           
                           Date saleDate = contract.Sale_Date__c;
                           Date cancelEffective = contract.Cancel_Effective_Date__c;
                           
                           if (cancelEffective < saleDate) {
                               contract.Expiration_Date_Calc__c = saleDate;
                           } else {
                               
                               Date nextCycle = saleDate;
                               Integer loopCounter = 0;
                               
                               while (nextCycle <= cancelEffective) {
                                   nextCycle = nextCycle.addMonths(1);
                                   loopCounter++;
                                   
                                   if (loopCounter > 120) break;
                               }
                               
                               contract.Expiration_Date_Calc__c = nextCycle;
                           }
                           
                       } 
                    // Using Calc field instead of raw field
                    else if(contract.Next_Cycle_Date_Calc__c != null 
                            && contract.Status != 'Cancelled') {
                                
                                contract.Expiration_Date_Calc__c = contract.Next_Cycle_Date_Calc__c;
                            }
                    
                } catch (Exception e) {
                    QDX_Log.error('Expiration Calc Error: ' + e.getMessage() +
                                  ' Line: ' + e.getLineNumber());
                }
            }
            /*---End of Changes 3 : Cycle Date Reversion on Cancel , 09-04-2026---*/
            
            else if(contract.Contract_Term_Months__c != null && contract.Sale_Date__c!= null) {
                if(contract.Validation_Days__c != null){
                    validationDays = (Integer)contract.Validation_Days__c;
                    system.debug('--validationDays--> '+validationDays);
                }
                Date effectiveDate = contract.Sale_Date__c.addDays(validationDays);
                if(contract.Status != 'Cancelled'){
                    contract.Expiration_Date_Calc__c = effectiveDate.addMonths((Integer)contract.Contract_Term_Months__c);
                }
            }
        }
    }
    
    public static void validateCancelMilage(List<InsurancePolicy> newContracts) {
        if (newContracts == null || newContracts.isEmpty()) return;
        RecordType autoWarranty= [Select Id, DeveloperName, SObjectType from RecordType where DeveloperName ='Auto_Warranty' and  SObjectType ='InsurancePolicy' LIMIT 1];
        for (InsurancePolicy contract : newContracts) {
            if(contract.Status != null && contract.Status == 'Cancelled' && contract.Cancel_Mileage__c == null && 
               contract.Vehicle_Mileage_at_Contract_Inception__c != null && autoWarranty!=null && contract.RecordTypeId == autoWarranty.Id) {
                   contract.Cancel_Mileage__c = contract.Vehicle_Mileage_at_Contract_Inception__c;
               }
        }
    }
    
    public static void setRefundPercent(List<InsurancePolicy> newContracts) {
        if (newContracts == null || newContracts.isEmpty()) return;
        RecordType autoWarranty= [Select Id, DeveloperName, SObjectType from RecordType where DeveloperName ='Auto_Warranty' and  SObjectType ='InsurancePolicy' LIMIT 1];
        for (InsurancePolicy contract : newContracts) {
            // Skip if any required field is missing
            Integer validationDays = 0;
            if(contract.Validation_Days__c != null){
                validationDays = (Integer)contract.Validation_Days__c;
            }
            Date effectiveDate = contract.Sale_Date__c.addDays(validationDays);
            if (contract.Cancel_Effective_Date__c == null || effectiveDate  == null) {
                continue;
            }
            
            Decimal result;
            Boolean isAutoWarranty = autoWarranty != null && contract.RecordTypeId != null && contract.RecordTypeId == autoWarranty.Id;
            Boolean isCancelledBeforeEffective = contract.Cancel_Effective_Date__c < effectiveDate;
            
            if (isCancelledBeforeEffective) {
                result = 1;
            } else {
                Decimal refundDatePercent = contract.Refund_Date_Percent__c != null ? contract.Refund_Date_Percent__c : 0;
                Decimal refundMileagePercent = contract.Refund_Mileage_Percent__c != null ? contract.Refund_Mileage_Percent__c : 0;
                
                if (isAutoWarranty) {
                    result = (refundDatePercent <= refundMileagePercent) ? refundDatePercent : refundMileagePercent;
                } else {
                    result = refundDatePercent;
                }
            }
            
            result = result.setScale(4, RoundingMode.HALF_UP);
            
            contract.Refund_Percent_Calc__c = result;
        }
    }
    
    // ADDED ON 11/03/26
    public static void setUnearnedPercent(List<InsurancePolicy> contracts){
        
        if(contracts == null || contracts.isEmpty()) return;
        
        Date todayDate = Date.today();
        
        for(InsurancePolicy contract : contracts){
            
            if(contract.Expiration_Date_Calc__c == null) continue;
            
            Date startDate;
            
            // M2M contract logic
            if(contract.Contract_Term_Months__c == 1){
                startDate = contract.Expiration_Date_Calc__c.addMonths(-1);
            }
            else{
                if(contract.Sale_Date__c == null) continue;
                startDate = contract.Sale_Date__c;
            }
            
            contract.Earning_Start_Date__c = startDate;
        }
    }
    // ADDED ON 11/03/26
    
    
    /**
* Detects all qualifying Insurance Policy events and creates
* outbox records in bulk.
*
* Contract and Finance notifications are captured in real time
* but are intentionally left Pending for the scheduled noon
* notification dispatch.
*/
   /* private static void processContractNotificationEvents(
        List<InsurancePolicy> newContracts,
        Map<Id, InsurancePolicy> oldContractMap
    ) {
        if (
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return;
        }
        
        Map<String, Notification_Event_Mapping__mdt>
            mappingsByEventCode =
            getSupportedContractNotificationMappings();
        
        if (mappingsByEventCode.isEmpty()) {
            return;
        }
        
        List<InsurancePolicy> qualifyingContracts =
            new List<InsurancePolicy>();
        
        Set<Id> customerIds = new Set<Id>();
        
        for (InsurancePolicy newContract : newContracts) {
            InsurancePolicy oldContract =
                oldContractMap.get(newContract.Id);
            
            if (oldContract == null) {
                continue;
            }
            
            if (
                hasAnyQualifyingContractEvent(
                    newContract,
                    oldContract,
                    mappingsByEventCode
                )
            ) {
                qualifyingContracts.add(newContract);
                
                if (newContract.NameInsuredId != null) {
                    customerIds.add(
                        newContract.NameInsuredId
                    );
                }
            }
        }
        
        if (qualifyingContracts.isEmpty()) {
            return;
        }
        
        Map<Id, Account> customersById =
            queryCustomers(customerIds);
        
        Datetime eventTime = System.now();
        
        List<NotificationOutboxService.OutboxRequest>
            outboxRequests =
            new List<
            NotificationOutboxService.OutboxRequest
            >();
        
        for (
            InsurancePolicy newContract :
            qualifyingContracts
        ) {
            InsurancePolicy oldContract =
                oldContractMap.get(newContract.Id);
            
            Account customer =
                newContract.NameInsuredId == null
                ? null
                : customersById.get(
                    newContract.NameInsuredId
                );
            
            addContractStatusEvents(
                outboxRequests,
                newContract,
                oldContract,
                customer,
                mappingsByEventCode,
                eventTime
            );
            
            addContractUpdatedEvent(
                outboxRequests,
                newContract,
                oldContract,
                customer,
                mappingsByEventCode,
                eventTime
            );
            
            addFinanceStatusEvents(
                outboxRequests,
                newContract,
                oldContract,
                customer,
                mappingsByEventCode,
                eventTime
            );
        }
        
        if (outboxRequests.isEmpty()) {
            return;
        }
        
        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                outboxRequests
            );
        
        logContractNotificationCreationErrors(result);*/
        
        /*
* Contract and Finance notifications are intentionally
* not dispatched immediately.
*
* Successfully created outbox records remain Pending and
* are picked up by the scheduled noon notification process.

    }*/
    
    /**
* Retrieves and validates the five supported contract
* notification mappings.
*/
 /*   private static Map<
        String,
        Notification_Event_Mapping__mdt
        > getSupportedContractNotificationMappings() {
            
            Map<String, Notification_Event_Mapping__mdt> result =
                new Map<
                String,
                Notification_Event_Mapping__mdt
                >();
            
            addSupportedMapping(
                result,
                EVENT_CONTRACT_CANCELLED,
                STATUS_FIELD,
                VALUE_TRANSITION,
                'Cancelled'
            );
            
            addSupportedMapping(
                result,
                EVENT_CONTRACT_EXPIRED,
                STATUS_FIELD,
                VALUE_TRANSITION,
                'Expired'
            );
            
            addSupportedMapping(
                result,
                EVENT_CONTRACT_UPDATED,
                RERATE_DATE_FIELD,
                ANY_FIELD_CHANGE,
                null
            );
            
            addSupportedMapping(
                result,
                EVENT_FINANCE_PAST_DUE,
                FINANCED_STATUS_FIELD,
                VALUE_TRANSITION,
                'Past Due'
            );
            
            addSupportedMapping(
                result,
                EVENT_FINANCE_CURRENT,
                FINANCED_STATUS_FIELD,
                VALUE_TRANSITION,
                'Current'
            );
            
            return result;
        }
    
    private static void addSupportedMapping(
        Map<String, Notification_Event_Mapping__mdt>
        targetMap,
        String eventCode,
        String monitoredField,
        String detectionType,
        String targetValue
    ) {
        Notification_Event_Mapping__mdt mapping =
            NotificationIntegrationConfigService.getActiveEventMapping(eventCode);
        
        if (
            !isValidContractMapping(
                mapping,
                eventCode,
                monitoredField,
                detectionType,
                targetValue
            )
        ) {
            return;
        }
        
        targetMap.put(
            eventCode,
            mapping
        );
    }
    
    private static Boolean isValidContractMapping(
        Notification_Event_Mapping__mdt mapping,
        String expectedEventCode,
        String expectedMonitoredField,
        String expectedDetectionType,
        String expectedTargetValue
    ) {
        if (mapping == null) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Event_Code__c,
                expectedEventCode
            )
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Source_Object__c,
                NOTIFICATION_SOURCE_OBJECT
            )
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Monitored_Field__c,
                expectedMonitoredField
            )
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Detection_Type__c,
                expectedDetectionType
            )
        ) {
            return false;
        }
        
        if (expectedTargetValue == null) {
            return String.isBlank(
                mapping.Target_Value__c
            );
        }
        
        return equalsIgnoreCase(
            mapping.Target_Value__c,
            expectedTargetValue
        );
    }*/
    
    /**
* Determines whether a contract has at least one qualifying
* event before customer data is queried.
*/
  /*  private static Boolean hasAnyQualifyingContractEvent(
        InsurancePolicy newContract,
        InsurancePolicy oldContract,
        Map<String, Notification_Event_Mapping__mdt>
        mappingsByEventCode
    ) {
        if (
            isTransitionToMappedValue(
                oldContract.Status,
                newContract.Status,
                mappingsByEventCode.get(
                    EVENT_CONTRACT_CANCELLED
                )
            )
        ) {
            return true;
        }
        
        if (
            isTransitionToMappedValue(
                oldContract.Status,
                newContract.Status,
                mappingsByEventCode.get(
                    EVENT_CONTRACT_EXPIRED
                )
            )
        ) {
            return true;
        }
        
        if (
            mappingsByEventCode.containsKey(
                EVENT_CONTRACT_UPDATED
            ) &&
            oldContract.ReRate_Date__c !=
            newContract.ReRate_Date__c
        ) {
            return true;
        }
        
        if (
            isTransitionToMappedValue(
                oldContract.Financed_Status__c,
                newContract.Financed_Status__c,
                mappingsByEventCode.get(
                    EVENT_FINANCE_PAST_DUE
                )
            )
        ) {
            return true;
        }
        
        return isTransitionToMappedValue(
            oldContract.Financed_Status__c,
            newContract.Financed_Status__c,
            mappingsByEventCode.get(
                EVENT_FINANCE_CURRENT
            )
        );
    }
    
    private static Boolean isTransitionToMappedValue(
        String oldValue,
        String newValue,
        Notification_Event_Mapping__mdt mapping
    ) {
        if (
            mapping == null ||
            String.isBlank(newValue) ||
            oldValue == newValue
        ) {
            return false;
        }
        
        return equalsIgnoreCase(
            newValue,
            mapping.Target_Value__c
        );
    }*/
    
    /**
* Queries customer names in one SOQL query.
*/
 /*   private static Map<Id, Account> queryCustomers(
        Set<Id> customerIds
    ) {
        if (
            customerIds == null ||
            customerIds.isEmpty()
        ) {
            return new Map<Id, Account>();
        }
        
        return new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :customerIds
        ]);
    }*/
    
    /**
* Creates CONTRACT_CANCELLED and CONTRACT_EXPIRED events.
*/
/*    private static void addContractStatusEvents(
        List<NotificationOutboxService.OutboxRequest>
        outboxRequests,
        InsurancePolicy newContract,
        InsurancePolicy oldContract,
        Account customer,
        Map<String, Notification_Event_Mapping__mdt>
        mappingsByEventCode,
        Datetime eventTime
    ) {
        Notification_Event_Mapping__mdt cancelledMapping =
            mappingsByEventCode.get(
                EVENT_CONTRACT_CANCELLED
            );
        
        if (
            isTransitionToMappedValue(
                oldContract.Status,
                newContract.Status,
                cancelledMapping
            )
        ) {
            outboxRequests.add(
                buildContractOutboxRequest(
                    newContract,
                    customer,
                    cancelledMapping,
                    STATUS_FIELD,
                    oldContract.Status,
                    newContract.Status,
                    null,
                    eventTime
                )
            );
        }
        
        Notification_Event_Mapping__mdt expiredMapping =
            mappingsByEventCode.get(
                EVENT_CONTRACT_EXPIRED
            );
        
        if (
            isTransitionToMappedValue(
                oldContract.Status,
                newContract.Status,
                expiredMapping
            )
        ) {
            outboxRequests.add(
                buildContractOutboxRequest(
                    newContract,
                    customer,
                    expiredMapping,
                    STATUS_FIELD,
                    oldContract.Status,
                    newContract.Status,
                    null,
                    eventTime
                )
            );
        }
    }*/
    
    /**
* Creates CONTRACT_UPDATED whenever ReRate_Date__c changes,
* including:
*
* null -> date
* date -> different date
* date -> null
*/
 /*   private static void addContractUpdatedEvent(
        List<NotificationOutboxService.OutboxRequest>
        outboxRequests,
        InsurancePolicy newContract,
        InsurancePolicy oldContract,
        Account customer,
        Map<String, Notification_Event_Mapping__mdt>
        mappingsByEventCode,
        Datetime eventTime
    ) {
        Notification_Event_Mapping__mdt updatedMapping =
            mappingsByEventCode.get(
                EVENT_CONTRACT_UPDATED
            );
        
        if (
            updatedMapping == null ||
            oldContract.ReRate_Date__c ==
            newContract.ReRate_Date__c
        ) {
            return;
        }
        
        String oldDateValue =
            oldContract.ReRate_Date__c == null
            ? null
            : String.valueOf(
                oldContract.ReRate_Date__c
            );
        
        String newDateValue =
            newContract.ReRate_Date__c == null
            ? null
            : String.valueOf(
                newContract.ReRate_Date__c
            );
        
        outboxRequests.add(
            buildContractOutboxRequest(
                newContract,
                customer,
                updatedMapping,
                RERATE_DATE_FIELD,
                oldDateValue,
                newDateValue,
                newContract.ReRate_Date__c,
                eventTime
            )
        );
    }*/
    
    /**
* Creates FINANCE_PAST_DUE and FINANCE_CURRENT events.
*/
   /* private static void addFinanceStatusEvents(
      List<NotificationOutboxService.OutboxRequest>
        outboxRequests,
        InsurancePolicy newContract,
        InsurancePolicy oldContract,
        Account customer,
        Map<String, Notification_Event_Mapping__mdt>
        mappingsByEventCode,
        Datetime eventTime
    ) {
        Notification_Event_Mapping__mdt pastDueMapping =
            mappingsByEventCode.get(
                EVENT_FINANCE_PAST_DUE
            );
        
        if (
            isTransitionToMappedValue(
                oldContract.Financed_Status__c,
                newContract.Financed_Status__c,
                pastDueMapping
            )
        ) {
            outboxRequests.add(
                buildContractOutboxRequest(
                    newContract,
                    customer,
                    pastDueMapping,
                    FINANCED_STATUS_FIELD,
                    oldContract.Financed_Status__c,
                    newContract.Financed_Status__c,
                    null,
                    eventTime
                )
            );
        }
        
        Notification_Event_Mapping__mdt currentMapping =
            mappingsByEventCode.get(
                EVENT_FINANCE_CURRENT
            );
        
        if (
            isTransitionToMappedValue(
                oldContract.Financed_Status__c,
                newContract.Financed_Status__c,
                currentMapping
            )
        ) {
            outboxRequests.add(
                buildContractOutboxRequest(
                    newContract,
                    customer,
                    currentMapping,
                    FINANCED_STATUS_FIELD,
                    oldContract.Financed_Status__c,
                    newContract.Financed_Status__c,
                    null,
                    eventTime
                )
            );
        }
    }*/
    
    /**
* Builds one outbox request for one qualifying contract event.
*/
 /*   private static NotificationOutboxService.OutboxRequest
        buildContractOutboxRequest(
            InsurancePolicy contractRecord,
            Account customer,
            Notification_Event_Mapping__mdt mapping,
            String changedField,
            String oldValue,
            String newValue,
            Date effectiveDate,
            Datetime eventTime
        ) {
            NotificationOutboxService.OutboxRequest request =
                new NotificationOutboxService.OutboxRequest();
            
            request.eventCode =
                mapping.Event_Code__c;
            
            request.eventKey =
                NotificationEventKeyGenerator.forRecordEvent(
                    mapping.Event_Code__c,
                    contractRecord.Id,
                    changedField,
                    oldValue,
                    newValue,
                    eventTime
                );
            
            request.sourceObject =
                NOTIFICATION_SOURCE_OBJECT;
            
            request.sourceRecordId =
                String.valueOf(contractRecord.Id);
            
            request.customerId =
                contractRecord.NameInsuredId;
            
            request.insurancePolicyId =
                contractRecord.Id;
            
            request.eventTime =
                eventTime;
            
            request.customerName =
                customer == null
                ? null
                : customer.Name;
            
            request.policyNumber =
                contractRecord.Name;
            
            request.changedField =
                changedField;
            
            request.oldValue =
                oldValue;
            
            request.newValue =
                newValue;
            
            request.effectiveDate =
                effectiveDate;
            
            if (contractRecord.NameInsuredId == null) {
                request.customerMappingError =
                    'InsurancePolicy.NameInsuredId is blank. ' +
                    'The insured customer could not be resolved for the ' +
                    'contract notification. Insurance Policy Id: ' +
                    contractRecord.Id +
                    ', Event Code: ' +
                    mapping.Event_Code__c +
                    '.';
                
                return request;
            }
            
            request.requestPayload =
                buildContractWebhookPayload(
                    contractRecord,
                    customer,
                    mapping.Event_Code__c,
                    oldValue,
                    newValue,
                    eventTime
                );
            
            return request;
        }
    */
    /**
* Creates the event-specific webhook JSON snapshot.
*/
  /*  private static String buildContractWebhookPayload(
        InsurancePolicy contractRecord,
        Account customer,
        String eventCode,
        String oldValue,
        String newValue,
        Datetime eventTime
    ) {
        NotificationWebhookPayload payload =
            NotificationWebhookPayload.forRecordEvent(
                eventCode,
                contractRecord.NameInsuredId,
                contractRecord.Id,
                null,
                eventTime
            );
        
        payload.addAttribute(
            'customerName',
            customer == null
            ? null
            : customer.Name
        );
        
        payload.addAttribute(
            'policyNumber',
            contractRecord.Name
        );
        
        if (
            eventCode == EVENT_CONTRACT_CANCELLED ||
            eventCode == EVENT_CONTRACT_EXPIRED
        ) {
            payload.addAttribute(
                'status',
                contractRecord.Status
            );
        } else if (
            eventCode == EVENT_CONTRACT_UPDATED
        ) {*/
            /*
* Direct Map insertion is intentional.
*
* Unlike addAttribute(), this preserves the key even when
* one side of the ReRate date transition is null.
*/
  /*          payload.attributes.put(
                'oldReRateDate',
                oldValue
            );
            
            payload.attributes.put(
                'newReRateDate',
                newValue
            );
        } else if (
            eventCode == EVENT_FINANCE_PAST_DUE ||
            eventCode == EVENT_FINANCE_CURRENT
        ) {
            payload.addAttribute(
                'financedStatus',
                contractRecord.Financed_Status__c
            );
        }
        
        return payload.toJson();
    }
    
    private static void logContractNotificationCreationErrors(
        NotificationOutboxService.CreationResult result
    ) {
        if (
            result == null ||
            !result.hasErrors()
        ) {
            return;
        }
        
        for (String errorMessage : result.errors) {
            QDX_Log.error(
                'Insurance Policy Notification Outbox Error: ' +
                errorMessage
            );
        }
        
        QDX_Log.publish();
    }
    
    private static Boolean equalsIgnoreCase(
        String firstValue,
        String secondValue
    ) {
        return normalizeNotificationValue(firstValue) ==
            normalizeNotificationValue(secondValue);
    }
    
    private static String normalizeNotificationValue(
        String value
    ) {
        return String.isBlank(value)
            ? ''
            : value.trim().toUpperCase();
    }*/
}