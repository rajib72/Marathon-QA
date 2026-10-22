/**
* @author Hitarth Trivedi
* @dateModified 05-29-2024
* @description Custom Token DataExtractor For Omnistudio Template for Claim Printout
*/
global class ClaimPrintoutTokenDataExtractor implements omnistudio.VlocityOpenInterface2 {
	
    global Object invokeMethod(String methodName, Map<String, Object> input, Map<String, Object> output, Map<String, Object> options) {
        Boolean success = false;
        if (methodName == 'getTokenData') {
            success = getTokenData(input, output, options);
        } 
        else {
            QDX_LOG.error('ClaimPrintoutTokenDataExtractor: Unsupported Method - '+methodName);
            QDX_LOG.publish();
        }
        return success;
    }
    private Boolean getTokenData(Map<String, Object> input, Map<String, Object> output, Map<String, Object> options) {        
        Boolean success = false;        
        success = getClaimTokenData(input, output, options);       
        return success;
    }
    
    /** 
     * @description: Method to prepare tokenMap with Claim, Contract, Payee and Payment details
     */
    private Boolean getClaimTokenData(Map<String, Object> input,Map<String, Object> output,Map<String, Object> options) { 
        Boolean success = false;  
		Map<String, Object> tokenMap = new Map<String, Object>();
        try {
            if(input.get('ContextId') != NULL ){
            	String claimId = (String) input.get('ContextId');
                
                //Get claim record from context request
                Claim claim = [SELECT id, Name, PolicyNumberId, CreatedDate, ReportDate, ReportNumber, Mileage__c, Labor_Rate__c, Claim_Type_Code_1__c, Claim_Type_Code_2__c, Complaints__c, Parts_Warranty__c, Repair_Number__c, Repair_Shop_Account__c, Cause__c FROM Claim where Id = :claimId LIMIT 1];
                if(claim != NULL && claim.Id != NULL){
                    //Set claim details on tokenMap
                    setClaimDetails(tokenMap, claim);
                    InsurancePolicy contract = [SELECT Id, Name, Client__c, VIN__c, Vehicle_Year__c, Vehicle_Make__c, Vehicle_Model__c, Vehicle_New_or_Used__c, SaleDate, Vehicle_Mileage_at_Contract_Inception__c, Deductible__c, Expiration_Mileage__c, Plan_Code__c, Lien_Holder__c, NameInsuredId, Expiration_Date__c FROM InsurancePolicy where Id =:claim.PolicyNumberId];
                    if(contract != NULL && contract.Id != NULL){
                        //Set Contract details on tokenMap
                        setContractDetails(tokenMap, contract);
                        //Set Payee Account and Payment details on tokenMap
                    	setPayeeAndPaymentDetails(tokenMap, claim);
                    }
                    tokenMap.put('CurrentDate', System.now().format('MM/dd/YYYY'));
                    tokenMap.put('CurrentTime', System.now().format('hh:mm:ss aa'));
        			tokenMap.put('ClaimNumber', nullCheck(claim.Name));
                	output.put('tokenMap', tokenMap);
            		success = true;
                }
            }
        }catch(exception e){
            QDX_LOG.error('Message*****'+e.getMessage()+'@@@@@@@@@@Line Number*******'+e.getLineNumber());
        } finally {
            QDX_LOG.publish();
        }
        return success;
    }
    
    /** 
     * @description: Method to set token data coming from Claim object
     */
    private void setClaimDetails(Map<String, Object> tokenMap, Claim claim){
    	tokenMap.put('ClaimCreatedDate',claim.CreatedDate!=NULL?claim.CreatedDate.format('MM/dd/YYYY'):'');
		tokenMap.put('ClaimReportDate',claim.ReportDate!=NULL?claim.ReportDate.format('MM/dd/YYYY'):'');
        tokenMap.put('ClaimReportNumber',nullCheck(claim.ReportNumber));
        tokenMap.put('ClaimMilage',nullCheck(claim.Mileage__c));
        tokenMap.put('ClaimLaborRate',nullCheck(claim.Labor_Rate__c));
        tokenMap.put('ClaimTypeCode1',nullCheck(claim.Claim_Type_Code_1__c));
        tokenMap.put('ClaimTypeCode2',nullCheck(claim.Claim_Type_Code_2__c));
        tokenMap.put('ClaimRepairNumber',nullCheck(claim.Repair_Number__c));
        
        if(claim.Repair_Shop_Account__c != NULL){
            //Query Repair Shop Account to get Name, address and phone details
            Account repairShopAccount = [SELECT Id, Name, Phone, Fax, BillingCity, BillingState, BillingPostalCode, BillingStreet, Repair_Contact__c FROM Account where Id =:claim.Repair_Shop_Account__c];
            System.debug('repairShopAccount:'+repairShopAccount);
            if(repairShopAccount != NULL){
                tokenMap.put('ClaimRepairShopAccount',nullCheck(repairShopAccount.Name));
        		tokenMap.put('ClaimRepairShopAccountStreet',nullCheck(repairShopAccount.BillingStreet));
        		tokenMap.put('ClaimRepairShopAccountCity',nullCheck(repairShopAccount.BillingCity));
        		tokenMap.put('ClaimRepairShopAccountState',nullCheck(repairShopAccount.BillingState));
        		tokenMap.put('ClaimRepairShopAccountZip',nullCheck(repairShopAccount.BillingPostalCode));
        		tokenMap.put('ClaimRepairShopAccountContact',nullCheck(repairShopAccount.Repair_Contact__c));
        		tokenMap.put('ClaimRepairShopAccountPhone',nullCheck(repairShopAccount.Phone));
        		tokenMap.put('ClaimRepairShopAccountFax',nullCheck(repairShopAccount.Fax));
            }
        }
        tokenMap.put('ClaimComplaints',nullCheck(claim.Complaints__c));
        tokenMap.put('ClaimRepairs',nullCheck(claim.Cause__c));
        tokenMap.put('ClaimPartsWarrenty',nullCheck(claim.Parts_Warranty__c));
    } 
    
    /** 
     * @description: Method to set token data coming from Contract object
     */
    private void setContractDetails(Map<String, Object> tokenMap, InsurancePolicy contract){
        //Query Account to get client account number
        String contractClientAccNum = '';
        String contractClientName = '';
        if(contract.Client__c!=NULL){
            Account clientAcc = [SELECT Id, AccountNumber, Name FROM Account where Id =:contract.Client__c];
            if(clientAcc != NULL && clientAcc.AccountNumber != NULL){
                contractClientAccNum = clientAcc.AccountNumber;
                contractClientName = clientAcc.Name;
            }
        }
                    
        //Query Account to get name insured
        String contractNameInsured = '';
        if(contract.NameInsuredId!=NULL){
            Account contractNameInsuredAcc = [SELECT Id, Name FROM Account where Id =:contract.NameInsuredId];
            if(contractNameInsuredAcc != NULL && contractNameInsuredAcc.Name != NULL){
                contractNameInsured = contractNameInsuredAcc.Name;
            }
        }
                   
        //Query Account to get Lien Holder Name
        String contractLienHolder = '';
        if(contract.Lien_Holder__c!=NULL){
            Account contractLienHolderAcc = [SELECT Id, Name FROM Account where Id =:contract.Lien_Holder__c];
            if(contractLienHolderAcc != NULL && contractLienHolderAcc.Name != NULL){
                contractLienHolder = contractLienHolderAcc.Name;
            }
    	}
        
        tokenMap.put('ContractClientName',nullCheck(contractClientName));
        tokenMap.put('ContractClient', nullCheck(contractClientAccNum));
        tokenMap.put('ContractPolicyNumber',nullCheck(contract.Name));
        tokenMap.put('ContractNameInsured',nullCheck(contractNameInsured));
        tokenMap.put('ContractVIN',nullCheck(contract.VIN__c));
        tokenMap.put('ContractVehicleYear',nullCheck(contract.Vehicle_Year__c));
        tokenMap.put('ContractVehicleMake',nullCheck(contract.Vehicle_Make__c));
        tokenMap.put('ContractVehicleModel',nullCheck(contract.Vehicle_Model__c));
        tokenMap.put('ContractVehicleNewUsed',nullCheck(contract.Vehicle_New_or_Used__c));
        tokenMap.put('ContractSaleDate',contract.SaleDate!=NULL?contract.SaleDate.format('MM/dd/YYYY'):'');
        tokenMap.put('ContractVehicleMilageAtInception',nullCheck(contract.Vehicle_Mileage_at_Contract_Inception__c));
        tokenMap.put('ContractDeductible',nullCheck(contract.Deductible__c));
        tokenMap.put('ContractExpirationDate', contract.Expiration_Date__c != NULL?((DateTime)contract.Expiration_Date__c).format('MM/dd/YYYY'):'');
        tokenMap.put('ContractExpirationMilage',nullCheck(contract.Expiration_Mileage__c));
        tokenMap.put('ContractFinanceCode',nullCheck(contractLienHolder));
        tokenMap.put('ContractPlanCode',nullCheck(contract.Plan_Code__c));
    }
    
    /** 
     * @description: Method to set token data coming from Payee(Account) and Payment objects
     */
    private void setPayeeAndPaymentDetails(Map<String, Object> tokenMap, Claim claim){
        List<Map<String,String>> Payment = new List<Map<String,String>>();
        Set<String> payeeIds = new Set<String>();
        List<ClaimItem> claimItemList = [SELECT Id, Payee_Name__c, Payment__c, Paid_By__c, Paid_Date__c, Wex__c, /*Parts__c, Labor__c, Sublet__c, Towing__c, Rental__c,*/ Tax__c, Tax_New__c, Subtotal__c, Deductible__c, NetClaim__c, Detail_Type__c FROM ClaimItem WHERE ClaimId = :claim.Id and Status__c ='Paid'];
        Map<ClaimItem,Map<String,String>> claimIdwithPayeeAndPayment = new Map<ClaimItem,Map<String,String>>{};
        Decimal totalClaimItemsParts=0;
        Decimal totalClaimItemsLabor=0;
        Decimal totalClaimItemsSublet=0;
        Decimal totalClaimItemsTowing=0;
        Decimal totalClaimItemsRentalCar=0;
        Decimal totalClaimItemsOther=0;
        Decimal totalClaimItemsTax=0;
        Decimal totalClaimItemsSubtotal=0;
        Decimal totalClaimItemsDeductible=0;
        Decimal totalClaimItemsNetClaim=0;
            
        //Set totals from ClaimItem
        //Prepare Set to get unique Payee & prepare map of ClaimItem with related Payee and Payment
        for(ClaimItem claimItem : claimItemList){
            Map<String,String> payeeAndPayment = new Map<String,String>();
            if(claimItem.Payee_Name__c != NULL){
                payeeIds.add(claimItem.Payee_Name__c);
                if(claimItem.Payment__c != NULL){
                    payeeAndPayment.put(claimItem.Payee_Name__c,claimItem.Payment__c);
                    claimIdwithPayeeAndPayment.put(claimItem,payeeAndPayment);
                }
            }
            //addition of calculation fields for all 'Paid' claimitems
            if(claimItem.Detail_Type__c == 'Part') {
                totalClaimItemsParts+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            } else if(claimItem.Detail_Type__c == 'Labor') {
                totalClaimItemsLabor+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            } else if(claimItem.Detail_Type__c == 'Sublet') {
                totalClaimItemsSublet+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            } else if(claimItem.Detail_Type__c == 'Towing') {
                totalClaimItemsTowing+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            } else if(claimItem.Detail_Type__c == 'Rental') {
                totalClaimItemsRentalCar+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            } else if(claimItem.Detail_Type__c == 'Other') {
                totalClaimItemsOther+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            }
            totalClaimItemsTax+=claimItem.Tax_New__c != NULL ? claimItem.Tax_New__c : 0;
            if(claimItem.Detail_Type__c != 'Deductible') {
            	totalClaimItemsSubtotal+=claimItem.Subtotal__c != NULL ? claimItem.Subtotal__c : 0;
            } 
            totalClaimItemsDeductible+=claimItem.Deductible__c!=null?claimItem.Deductible__c:0;
            totalClaimItemsNetClaim+=claimItem.NetClaim__c;
        }
        //totalClaimItemsNetClaim = totalClaimItemsSubtotal - totalClaimItemsDeductible;
        
        //Iterate over each unique Payee Account
        for(String payeeId : PayeeIds){
        	Account payeeAccount = [SELECT Id, AccountNumber, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, Phone FROM Account where Id  =:payeeId];
        	Map<String,String> payments = new Map<String,String>();
            ClaimItem claimItem;
            String paymentId='';
            Decimal claimItemsParts=0;
            Decimal claimItemsLabor=0;
            Decimal claimItemsSublet=0;
            Decimal claimItemsTowing=0;
            Decimal claimItemsRentalCar=0;
            Decimal claimItemsOther=0;
            Decimal claimItemsTax=0;
            Decimal claimItemsSubtotal=0;
            Decimal claimItemsDeductible=0;
            Decimal claimItemsNetClaim=0;
            
            payments.put('PayeeAccNo',payeeAccount.AccountNumber);
            payments.put('PayeeName',payeeAccount.Name);
            payments.put('PayeeStreet',payeeAccount.BillingStreet);
            payments.put('PayeeCity',payeeAccount.BillingCity);
            payments.put('PayeeState',payeeAccount.BillingState);
            payments.put('PayeeZip',payeeAccount.BillingPostalCode);
            payments.put('PayeePhone',payeeAccount.Phone);
            
            for(ClaimItem ci : claimIdwithPayeeAndPayment.keySet()){
                Map<String,String> p = claimIdwithPayeeAndPayment.get(ci);
                //Check if the payeeId(outer loop) is same as current payee(coming from ci)
                if(p.containsKey(payeeId) != NULL && p.get(payeeId) != NULL){
                    paymentId = p.get(payeeId);
                    claimItem = ci;
                    
                    if(ci.Detail_Type__c == 'Part') {
                		claimItemsParts+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		} else if(ci.Detail_Type__c == 'Labor') {
                		claimItemsLabor+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		} else if(ci.Detail_Type__c == 'Sublet') {
                		claimItemsSublet+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		} else if(ci.Detail_Type__c == 'Towing') {
                		claimItemsTowing+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		} else if(ci.Detail_Type__c == 'Rental') {
                		claimItemsRentalCar+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		} else if(ci.Detail_Type__c == 'Other') {
                		claimItemsOther+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		}
                    claimItemsTax+=ci.Tax_New__c != NULL ? ci.Tax_New__c : 0;
                    if(ci.Detail_Type__c != 'Deductible') {
            			claimItemsSubtotal+=ci.Subtotal__c != NULL ? ci.Subtotal__c : 0;
            		} 
                    claimItemsDeductible+=ci.Deductible__c != NULL ? ci.Deductible__c : 0;
            		claimItemsNetClaim+=ci.NetClaim__c != NULL ? ci.NetClaim__c : 0;
                }
            }
            
            if(paymentId != NULL && paymentId != ''){
                Payment__c pmt = [SELECT Id, Credit_Check__c, CheckNumber__c, Payment_Approval_Number__c, Payment_Approval_Name__c, Payment_Approval_Comment__c FROM Payment__c WHERE Id =:paymentId];
                if(pmt != NULL){
                    //Adding Payment detail - to be shown under Payee Details section
                    payments.put('PaymentCreditCheck',nullCheck(pmt.Credit_Check__c));
                    payments.put('PaymentCheckNumber',nullCheck(pmt.CheckNumber__c));
                    payments.put('PaymentApprovalNumber',nullCheck(pmt.Payment_Approval_Number__c));
                    payments.put('PaymentApprovalName',nullCheck(pmt.Payment_Approval_Name__c));
                    payments.put('PaymentApprovalComment',nullCheck(pmt.Payment_Approval_Comment__c));
                }
            }
            //Adding payment details for indivudial payee account
            if(claimItem != NULL){
                payments.put('ClaimPaidBy',nullCheck(claimItem.Paid_By__c));
                payments.put('ClaimPaidDate',nullCheck(String.valueOf(claimItem.Paid_Date__c)));
                payments.put('Wex',claimItem.Wex__c==true?'WEX':'');
                payments.put('ClaimItemsParts','$'+nullCheck(getCents(claimItemsParts)));
                payments.put('ClaimItemsLabor','$'+nullCheck(getCents(claimItemsLabor)));
                payments.put('ClaimItemsSublet','$'+nullCheck(getCents(claimItemsSublet)));
                payments.put('ClaimItemsTowing','$'+nullCheck(getCents(claimItemsTowing)));
                payments.put('ClaimItemsRentalCar','$'+nullCheck(getCents(claimItemsRentalCar)));
                payments.put('ClaimItemsOther','$'+nullCheck(getCents(claimItemsOther)));
                payments.put('ClaimItemsTax','$'+nullCheck(getCents(claimItemsTax)));
                payments.put('ClaimItemsSubtotal','$'+nullCheck(getCents(claimItemsSubtotal)));
                payments.put('ClaimItemsDeductible','$'+nullCheck(getCents(claimItemsDeductible)));
                payments.put('ClaimItemsNetClaim','$'+nullCheck(getCents(claimItemsNetClaim)));
        	}
            payment.add(payments);
        }
        //Adding total payment details
        tokenMap.put('ClaimItemsParts','$'+nullCheck(getCents(totalClaimItemsParts)));
        tokenMap.put('ClaimItemsLabor','$'+nullCheck(getCents(totalClaimItemsLabor)));
        tokenMap.put('ClaimItemsSublet','$'+nullCheck(getCents(totalClaimItemsSublet)));
        tokenMap.put('ClaimItemsTowing','$'+nullCheck(getCents(totalClaimItemsTowing)));
        tokenMap.put('ClaimItemsRentalCar','$'+nullCheck(getCents(totalClaimItemsRentalCar)));
        tokenMap.put('ClaimItemsOther','$'+nullCheck(getCents(totalClaimItemsOther)));
        tokenMap.put('ClaimItemsTax','$'+nullCheck(getCents(totalClaimItemsTax)));
        tokenMap.put('ClaimItemsSubtotal','$'+nullCheck(getCents(totalClaimItemsSubtotal)));
        tokenMap.put('ClaimItemsDeductible','$'+nullCheck(getCents(totalClaimItemsDeductible)));
        tokenMap.put('ClaimItemsNetClaim','$'+nullCheck(getCents(totalClaimItemsNetClaim)));
        tokenMap.put('Payment', payment);
    }
    
    /** 
     * @description: Method will return value with 2 decimal points
     * @example: input-80, output-80.00 | input-7.481, output-7.48 
     * 
     */
    private String getCents(Decimal x){
        String y = String.valueOf(x.setScale(2).format());
        if(y.contains('.')){
            return y;
        } else {
           	return y+'.00';
        }
	}
    
    /** 
     * @description: Method will return blank string if value is NULL
     */
    private String nullCheck(String token){
        if(token != NULL){
            return token;
        } else {
            return '';
        }
    }
    
    /** 
     * @description: Method will return blank string if value is NULL
     */
    private Decimal nullCheck(Decimal token){
        if(token != NULL){
            return token;
        } else {
            return 0;
        }
    }
    
}