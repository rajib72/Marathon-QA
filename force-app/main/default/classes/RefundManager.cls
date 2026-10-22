/**
* @author: Waidehee Kuradkar
* @dateModified: 22/04/2025
* @description: Calculates cancellation fees and return the calculated value.
* @params: List<String> inputs where inputs[0] is the cancel fee formula and inputs[1] is the contract record id
*/
public class RefundManager {
    @InvocableMethod
    public static List<Decimal> calculateCancelFee(List<List<String>> inputs){
        try{
            //If cancel fee is numeric then return cancel fee as it is. 
            if(inputs[0][0] != NULL && inputs[0][0].length()>0 && (Pattern.matches('\\d+(\\.\\d+)?', inputs[0][0]))){
            return new List<Decimal> {Decimal.valueOf(inputs[0][0])};
        } 
        else if(inputs[0][0] != NULL && inputs[0][0].length()>0 && inputs[0][1].length()>0 ){
            InsurancePolicy policy = [SELECT Id, CancellationReasonType, PremiumAmount, RecordType.Name, Refund_Percent__c, Cancel_Effective_Date__c , Effective_Date__c, Sale_Date__c, Validation_Days__c, Refund_Date_Percent__c , Refund_Mileage_Percent__c, Expiration_Date__c, Contract_Term_Months__c, Vehicle_Mileage_at_Contract_Inception__c, Contract_Term_Mileage__c , Validation_Miles__c, Product__c  from InsurancePolicy where Id = :inputs[0][1]][0];
            //If contract has CancellationReasonType as listed below, return 0.0 as cancel fee.
            if( policy.CancellationReasonType == UtilityClass.CANCELLED_BY_ADMINISTRATOR || policy.CancellationReasonType == UtilityClass.FLAT_CANCEL_FOR_TMU || policy.CancellationReasonType == UtilityClass.INELIGIBLE_VEHICLE || policy.CancellationReasonType == UtilityClass.SALVAGED_BRANDED_TITLE){
                return new List<Decimal> {0.0};
            }
            else{
                //Cancel fee is formula here and calculates the formula and returns the calculated value. 
                FormulaEval.FormulaInstance formulaInstance = Formula.builder()
                    .withType(InsurancePolicy.SObjectType)
                    .withReturnType(FormulaEval.FormulaReturnType.DECIMAL) // Expecting Decimal return type
                    .withFormula(inputs[0][0])
                    .build();
				Decimal formulaResult = (Decimal)formulaInstance.evaluate(policy); 
                return new List<Decimal> {formulaResult};
            }
        }
            return new List<Decimal> {0.0};
        }
        catch(Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            return new List<Decimal> {0.0};
        } finally {
            QDX_Log.publish();
        }
    }

}