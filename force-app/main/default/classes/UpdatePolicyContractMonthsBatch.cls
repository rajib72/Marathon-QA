public class UpdatePolicyContractMonthsBatch implements Database.Batchable<SObject> {
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
                Sale_Date__c,
                Cancel_Code__c,
                CancellationReasonType,
                Cancel_Mileage__c,
                Vehicle_Mileage_at_Contract_Inception__c,
                Cancel_Effective_Date__c,
                Expiration_Date__c,
                Status,
                Name,
                Client__r.AccountNumber,
                RecordType.DeveloperName,
                Contract_Term_Months__c
            FROM InsurancePolicy
            WHERE Sale_Date__c != NULL
              AND Contract_Term_Months__c = 1 AND Status != 'Cancelled'
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<InsurancePolicy> updates = new List<InsurancePolicy>();
        List<Id> skipped = new List<Id>();
        
        for (SObject sob : scope) {
            InsurancePolicy pc = (InsurancePolicy) sob;
            
            if (wouldFailValidationRule(pc)) {
                skipped.add(pc.Id);
                continue;
            }
            
            Integer months = calculateMonths(pc.Sale_Date__c);
            
            updates.add(new InsurancePolicy(
                Id = pc.Id,
                Number_of_Funding_Months__c = months
            ));
        }
        
        if (!updates.isEmpty()) {
            update updates;
        }
        
        if (!skipped.isEmpty()) {
            System.debug('UpdatePolicyContractMonthsBatch - skipped records due to validation rule: ' + skipped);
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        // optional logging or email
    }
    
    private Boolean wouldFailValidationRule(InsurancePolicy pc) {
        
        // VALIDATION RULE #1
        if (pc.RecordType == null || pc.RecordType.DeveloperName != 'Home_Warranty') {
            
            Boolean allowedCombo = (pc.Cancel_Code__c == '04 ROP Request' &&
                                    pc.CancellationReasonType == 'NON PAYMENT');
            
            if (!allowedCombo) {
                if (pc.Cancel_Mileage__c != null &&
                    pc.Vehicle_Mileage_at_Contract_Inception__c != null &&
                    pc.Cancel_Mileage__c < pc.Vehicle_Mileage_at_Contract_Inception__c) {
                        
                        return true;
                }
            }
        }
        
        // -----------------------
        // VALIDATION RULE #2 (STRONGER)
        // -----------------------
        Date ced = pc.Cancel_Effective_Date__c;
        Date sale = pc.Sale_Date__c;
        Date exp  = pc.Expiration_Date__c;
        
        // If Cancel Effective Date is present but either Sale or Expiration is missing,
        // treat as failing — validation can fire in this situation in many orgs.
        if (ced != null) {
            if (sale == null || exp == null) {
                return true;
            }
            // Now do the normal between check (inclusive allowed)
            if (ced < sale || ced > exp) {
                return true;
            }
        }
        
        // If ced is null, leave handling to RULE #3 which checks for blank ced if applicable.

        
        // VALIDATION RULE #3
        Boolean isCancelled = (pc.Status == 'Cancelled');
        String acct = pc.Client__r != null ? pc.Client__r.AccountNumber : null;
        
        Boolean acctNotAllowed =
            acct != 'WLK' &&
            acct != 'WFI' &&
            acct != 'WUS';
        
        Boolean rtMatched =
            pc.RecordType != null &&
            (pc.RecordType.DeveloperName == 'Home_Warranty' ||
             pc.RecordType.DeveloperName == 'Auto_Warranty');
        
        Boolean missingFields =
            String.isBlank(pc.Name) ||
            pc.Cancel_Effective_Date__c == null;
        
        if (isCancelled && acctNotAllowed && rtMatched && missingFields) {
            return true;
        }
        
        return false;
    }
    
    private Integer calculateMonths(Date saleDate) {
        if (saleDate == null || Date.today() < saleDate) {
            return 0;
        }
        
        Date today = Date.today();
        
        Integer months =
            (today.year() - saleDate.year()) * 12 +
            (today.month() - saleDate.month());
        
        if (today.day() >= saleDate.day()) {
            months += 1;
        }
        
        return months;
    }
}