public with sharing class ClaimItemGridController {
    
    @AuraEnabled(cacheable=true)
    public static List<ClaimItem> getClaimItems(Id claimId) {
        
        return [
            SELECT
            Id,
            Name,
            ClaimId,
            Job_Number__c,
            Detail_Type__c,
            Description,
            Part_Number__c,
            Invoice_Number__c,
            Quantity__c,
            Gross_Quantity__c,
            Processed_Parts__c,
            Rate__c,
            Status__c,
            Reason__c,
            Category,
            Payee_Name__c,
            Payee_Name__r.Name,
            Payee_Name__r.RecordType.Name,
            Loss_Description__c,
            Payment__c,
            Coverage_Level_Detail__c,
            Coverage_Level_Detail__r.Name,
            Tax__c,
            Tax_New__c,
            Subtotal__c,
            Deductible__c,
            NetClaim__c,
            Wex__c
            FROM ClaimItem
            WHERE ClaimId = :claimId
            ORDER BY CreatedDate ASC
        ];
    }
    
    @AuraEnabled
    public static void saveClaimItems(
        Id claimId,
        List<ClaimItem> items
    ) {
        
        if(items == null || items.isEmpty()) {
            return;
        }
        
        Claim claimRec = [
            SELECT
            Id,
            Labor_Rate__c,
            Repair_Shop_Account__c,
            PolicyNumber.RecordType.Name
            FROM Claim
            WHERE Id = :claimId
            LIMIT 1
        ];
        
        Boolean isAutoWarranty =
            claimRec.PolicyNumber != null &&
            claimRec.PolicyNumber.RecordType != null &&
            claimRec.PolicyNumber.RecordType.Name == 'Auto Warranty';
        
        List<ClaimItem> inserts = new List<ClaimItem>();
        
        List<ClaimItem> updates = new List<ClaimItem>();
        
        Set<Id> updateIds = new Set<Id>();
        
        Set<String> jobNumbers = new Set<String>();
        
        for(ClaimItem ci : items) {
            
            if(ci.Id != null) {
                
                updateIds.add(ci.Id);
                
            } else {
                ClaimItem newItem = new ClaimItem();
                
                newItem.ClaimId = claimId;
                newItem.Job_Number__c = ci.Job_Number__c;
                newItem.Detail_Type__c = ci.Detail_Type__c;
                newItem.Description = ci.Description;
                newItem.Part_Number__c = ci.Part_Number__c;
                newItem.Invoice_Number__c = ci.Invoice_Number__c;
                newItem.Quantity__c = ci.Quantity__c;
                newItem.Gross_Quantity__c = ci.Gross_Quantity__c;
                newItem.Processed_Parts__c = ci.Processed_Parts__c;
                newItem.Rate__c = ci.Rate__c;
                newItem.Status__c = ci.Status__c;
                newItem.Reason__c = ci.Reason__c;
                newItem.Category = ci.Category;
                newItem.Payee_Name__c = ci.Payee_Name__c;
                newItem.Coverage_Level_Detail__c =
                    ci.Coverage_Level_Detail__c;
                
                inserts.add(newItem);
            }
            
            if(String.isNotBlank(ci.Job_Number__c)) {
                jobNumbers.add(ci.Job_Number__c.trim());
            }
        }
        
        Map<String, ClaimItem> priorItemByJobNumber =
            new Map<String, ClaimItem>();
        
        if(!jobNumbers.isEmpty()) {
            
            for(ClaimItem oldItem : [
                SELECT
                Id,
                Job_Number__c,
                Payee_Name__c,
                Coverage_Level_Detail__c
                FROM ClaimItem
                WHERE ClaimId = :claimId
                AND Job_Number__c IN :jobNumbers
                AND (
                    Payee_Name__c != null
                    OR Coverage_Level_Detail__c != null
                )
                ORDER BY CreatedDate DESC
            ]) {
                
                String jobNo =
                    oldItem.Job_Number__c != null
                    ? oldItem.Job_Number__c.trim()
                    : null;
                
                if(
                    String.isNotBlank(jobNo) &&
                    !priorItemByJobNumber.containsKey(jobNo)
                ) {
                    priorItemByJobNumber.put(jobNo, oldItem);
                }
            }
        }
        
        Map<Id, ClaimItem> existingMap =
            new Map<Id, ClaimItem>();
        
        if(!updateIds.isEmpty()) {
            
            existingMap = new Map<Id, ClaimItem>([
                
                SELECT
                Id,
                ClaimId,
                Status__c,
                Invoice_Number__c,
                Category,
                Payee_Name__c,
                Detail_Type__c,
                Quantity__c,
                Gross_Quantity__c,
                Processed_Parts__c,
                Rate__c,
                Reason__c,
                Description,
                Part_Number__c,
                Job_Number__c,
                Loss_Description__c,
                Payment__c,
                Coverage_Level_Detail__c
                
                FROM ClaimItem
                
                WHERE Id IN :updateIds
            ]);
        }
        
        for(ClaimItem insertItem : inserts) {
            
            applyClaimItemDefaults(
                insertItem,
                priorItemByJobNumber,
                isAutoWarranty,
                claimRec.Labor_Rate__c,
                claimRec.Repair_Shop_Account__c
            );
        }
        
        for(ClaimItem draft : items) {
            
            if(draft.Id == null) {
                continue;
            }
            
            ClaimItem existing =
                existingMap.get(draft.Id);
            
            if(existing == null) {
                continue;
            }
            ClaimItem original = existing.clone();
            
            existing.Job_Number__c =
                draft.Job_Number__c;
            
            existing.Detail_Type__c =
                draft.Detail_Type__c;
            
            existing.Description =
                draft.Description;
            
            existing.Part_Number__c =
                draft.Part_Number__c;
            
            existing.Invoice_Number__c =
                draft.Invoice_Number__c;
            
            existing.Quantity__c =
                draft.Quantity__c;
            
            existing.Gross_Quantity__c =
                draft.Gross_Quantity__c;
            
            existing.Processed_Parts__c =
                draft.Processed_Parts__c;
            
            existing.Rate__c =
                draft.Rate__c;
            
            System.debug( 'Rate received from UI = ' + draft.Rate__c );
            
            existing.Status__c =
                draft.Status__c;
            
            existing.Reason__c =
                draft.Reason__c;
            
            existing.Category =
                draft.Category;
            
            existing.Payee_Name__c =
                draft.Payee_Name__c;
            
            existing.Coverage_Level_Detail__c =
                draft.Coverage_Level_Detail__c;
            
            applyClaimItemDefaultsForUpdate(
    existing,
    priorItemByJobNumber,
    claimRec.Repair_Shop_Account__c
);

// Add the record to updates only if a relevant field changed.
if (
    original.Job_Number__c != existing.Job_Number__c ||
    original.Detail_Type__c != existing.Detail_Type__c ||
    original.Description != existing.Description ||
    original.Part_Number__c != existing.Part_Number__c ||
    original.Invoice_Number__c != existing.Invoice_Number__c ||
    original.Quantity__c != existing.Quantity__c ||
    original.Gross_Quantity__c != existing.Gross_Quantity__c ||
    original.Processed_Parts__c != existing.Processed_Parts__c ||
    original.Rate__c != existing.Rate__c ||
    original.Status__c != existing.Status__c ||
    original.Reason__c != existing.Reason__c ||
    original.Category != existing.Category ||
    original.Payee_Name__c != existing.Payee_Name__c ||
    original.Coverage_Level_Detail__c !=
        existing.Coverage_Level_Detail__c
) {
    updates.add(existing);
}
        }
        
        if(!inserts.isEmpty()) {
            insert inserts;
        }
        
        if(!updates.isEmpty()) {
            update updates;
        }
    }
    
    private static void applyClaimItemDefaults(
        ClaimItem targetItem,
        Map<String, ClaimItem> priorItemByJobNumber,
        Boolean isAutoWarranty,
        Decimal claimLaborRate,
        Id repairShopAccountId
    ) {
        
        if(targetItem == null) {
            return;
        }
        
        String jobNo =
            targetItem.Job_Number__c != null
            ? targetItem.Job_Number__c.trim()
            : null;
        
        if(
            String.isNotBlank(jobNo) &&
            priorItemByJobNumber != null &&
            priorItemByJobNumber.containsKey(jobNo)
        ) {
            
            ClaimItem priorItem =
                priorItemByJobNumber.get(jobNo);
            
            if(
                targetItem.Payee_Name__c == null &&
                priorItem.Payee_Name__c != null
            ) {
                targetItem.Payee_Name__c =
                    priorItem.Payee_Name__c;
            }
            
            if(
                targetItem.Coverage_Level_Detail__c == null &&
                priorItem.Coverage_Level_Detail__c != null
            ) {
                targetItem.Coverage_Level_Detail__c =
                    priorItem.Coverage_Level_Detail__c;
            }
        }
        
        if (
            targetItem.Payee_Name__c == null &&
            repairShopAccountId != null
        ) {
            targetItem.Payee_Name__c = repairShopAccountId;
        }
        
        if(
            isAutoWarranty &&
            targetItem.Detail_Type__c == 'Labor' &&
            claimLaborRate != null &&
            targetItem.Rate__c == null
        ) {
            targetItem.Rate__c = claimLaborRate;
        }
    }
    
    private static void applyClaimItemDefaultsForUpdate(
        ClaimItem targetItem,
        Map<String, ClaimItem> priorItemByJobNumber,
        Id repairShopAccountId
    ) {
        if (targetItem == null) {
            return;
        }
        
        String jobNo =
            targetItem.Job_Number__c != null
            ? targetItem.Job_Number__c.trim()
            : null;
        
        if (
            String.isNotBlank(jobNo) &&
            priorItemByJobNumber != null &&
            priorItemByJobNumber.containsKey(jobNo)
        ) {
            ClaimItem priorItem =
                priorItemByJobNumber.get(jobNo);
            
            if (
                targetItem.Payee_Name__c == null &&
                priorItem.Payee_Name__c != null
            ) {
                targetItem.Payee_Name__c =
                    priorItem.Payee_Name__c;
            }
            
            if (
                targetItem.Coverage_Level_Detail__c == null &&
                priorItem.Coverage_Level_Detail__c != null
            ) {
                targetItem.Coverage_Level_Detail__c =
                    priorItem.Coverage_Level_Detail__c;
            }
        }
        
        if (
            targetItem.Payee_Name__c == null &&
            repairShopAccountId != null
        ) {
            targetItem.Payee_Name__c = repairShopAccountId;
        }
    }
    
    @AuraEnabled
    public static void authorizeClaimItems(
        List<Id> claimItemIds
    ) {
        
        List<ClaimItem> updates = [
            
            SELECT Id, Status__c
            
            FROM ClaimItem
            
            WHERE Id IN :claimItemIds
        ];
        
        for(ClaimItem ci : updates) {
            
            ci.Status__c = 'Authorized';
        }
        
        update updates;
    }
    
    @AuraEnabled
    public static void deleteClaimItem(Id claimItemId) {
        
        if(claimItemId == null) {
            throw new AuraHandledException('Claim Item Id is required.');
        }
        
        ClaimItem ci = [
            SELECT Id,Status__c
            FROM ClaimItem
            WHERE Id = :claimItemId
            LIMIT 1
        ];
        if (ci.Status__c == 'Paid') {
            throw new AuraHandledException(
                'Cannot delete a Claim Item with status Paid.'
            );
        }
        
        delete ci;
    }
    
    /*@AuraEnabled(cacheable=false)
public static List<Coverage_Level_Detail__c> searchCoverageLevelDetails(String searchTerm) {

String searchPattern = '%' + searchTerm + '%';

return [
SELECT Id, Name
FROM Coverage_Level_Detail__c
WHERE Name LIKE :searchPattern
ORDER BY Name
LIMIT 50
];
}*/
    
    //added by Swastika on 03/06/2026
    
    @AuraEnabled(cacheable=false)
    public static List<Coverage_Level_Detail__c> searchCoverageLevelDetails(
        Id claimId,
        String searchTerm
    ) {
        if (claimId == null) {
            return new List<Coverage_Level_Detail__c>();
        }
        
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<Coverage_Level_Detail__c>();
        }
        
        Claim claimRec = [
            SELECT Id,
            PolicyNumberId,
            PolicyNumber.Coverage_Level__c
            FROM Claim
            WHERE Id = :claimId
            LIMIT 1
        ];
        
        Id coverageLevelId =
            claimRec.PolicyNumber != null
            ? claimRec.PolicyNumber.Coverage_Level__c
            : null;
        
        if (coverageLevelId == null) {
            return new List<Coverage_Level_Detail__c>();
        }
        
        String searchPattern =
            '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        
        return [
            SELECT Id, Name
            FROM Coverage_Level_Detail__c
            WHERE Coverage_Level__c = :coverageLevelId
            AND Loss_Component__c != null
            AND Name LIKE :searchPattern
            ORDER BY Name
            LIMIT 50
        ];
    }
    
    @AuraEnabled(cacheable=false)
    public static List<Account> searchPayeeAccounts(String searchTerm) {
        
        if(String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<Account>();
        }
        
        String searchPattern =
            '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        
        return [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :searchPattern
            ORDER BY Name
            LIMIT 50
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getClaimDefaultDetails(Id claimId) {
        
        Map<String, Object> resultMap = new Map<String, Object>();
        
        if (claimId == null) {
            return resultMap;
        }
        
        Claim claimRec = [
            SELECT
            Id,
            Status,
            Labor_Rate__c,
            Labor_Tax_Rate__c,
            Parts_Tax_Rate__c,
            Repair_Shop_Account__c,
            Repair_Shop_Account__r.Name,
            PolicyNumber.RecordType.Name,
            PolicyNumber.Status
            FROM Claim
            WHERE Id = :claimId
            LIMIT 1
        ];
        
        resultMap.put('claimStatus', claimRec.Status);
        resultMap.put('contractStatus', claimRec.PolicyNumber != null ? claimRec.PolicyNumber.Status : null);
        resultMap.put('claimLaborRate', claimRec.Labor_Rate__c);
        resultMap.put(
            'policyRecordTypeName',
            claimRec.PolicyNumber != null && claimRec.PolicyNumber.RecordType != null
            ? claimRec.PolicyNumber.RecordType.Name
            : null
        );
        resultMap.put('repairShopAccountId', claimRec.Repair_Shop_Account__c);
        resultMap.put(
            'repairShopAccountName',
            claimRec.Repair_Shop_Account__r != null ? claimRec.Repair_Shop_Account__r.Name : null
        );
        resultMap.put('claimLaborTaxRate', claimRec.Labor_Tax_Rate__c);
        resultMap.put('claimPartsTaxRate', claimRec.Parts_Tax_Rate__c);
        
        return resultMap;
    }
}