/**
 * Phase 1B-1: read-only construction of normalized pricing context.
 * - Bulk safe: one Claim query, one ClaimItem query, one Coverage Detail query.
 * - Supports both persisted ClaimItems and unsaved editor rows.
 * - Uses user's CURRENT LWC draft values for pricing; does not write them.
 * - Verifies persisted ClaimItem IDs belong to the supplied Claim.
 * - No callouts, no DML, no tax/rate/Payee changes.
 *
 * A separate validation service will enforce vendor-specific mandatory fields.
 */
public with sharing class VendorPricingContextService {
    private static final Integer MAX_LINES = 100; // defensive transaction limit, not a pricing business rule

    public class ContextException extends Exception {}


    /**
     * Injectable read-only query boundary.
     * Default implementation uses exactly the same USER_MODE queries as before.
     * Tests replace the provider with in-memory records; no SeeAllData or
     * Claim/Policy/ClaimItem DML is needed to exercise the complete build flow.
     */
    public virtual class DataProvider {
        public virtual List<Claim> loadClaim(Id claimId) {
            return [
                SELECT Id, PolicyNumberId, PolicyNumber.VIN__c,
                       PolicyNumber.Coverage_Level__c,
                       Mileage__c, Repair_Shop_Account__c,
                       Repair_Shop_Account__r.Name,
                       Repair_Shop_Account__r.BillingStreet,
                       Repair_Shop_Account__r.BillingCity,
                       Repair_Shop_Account__r.BillingState,
                       Repair_Shop_Account__r.BillingPostalCode,
                       Repair_Shop_Account__r.BillingCountry
                FROM Claim
                WHERE Id = :claimId
                WITH USER_MODE
                LIMIT 1
            ];
        }

        public virtual Map<Id, ClaimItem> loadSavedItems(
            Set<Id> requestedSavedIds, Id claimId
        ) {
            return new Map<Id, ClaimItem>([
                SELECT Id, ClaimId, Coverage_Level_Detail__c,
                       Detail_Type__c, Part_Number__c, Quantity__c, Description
                FROM ClaimItem
                WHERE Id IN :requestedSavedIds AND ClaimId = :claimId
                WITH USER_MODE
            ]);
        }

        public virtual Map<Id, Coverage_Level_Detail__c> loadDetails(
            Set<Id> detailIds
        ) {
            return new Map<Id, Coverage_Level_Detail__c>([
                SELECT Id, Name, Loss_Category__c, Coverage_Level__c,
                       Loss_Component__c, Loss_Component__r.Name
                FROM Coverage_Level_Detail__c
                WHERE Id IN :detailIds
                WITH USER_MODE
            ]);
        }
    }

    // Dependency injection is restricted to Apex tests. Never persists.
    @TestVisible private static DataProvider providerForTest;

    public static VendorPricingRequestContext build(
        Id claimId,
        List<VendorPricingLineInput> selectedLines
    ) {
        checkInput(claimId, selectedLines);

        DataProvider provider = providerForTest == null
            ? new DataProvider() : providerForTest;
        List<Claim> claimRows = provider.loadClaim(claimId);
        if (claimRows.isEmpty()) {
            throw new ContextException('Claim not found or not accessible.');
        }

        Set<Id> requestedSavedIds = new Set<Id>();
        for (VendorPricingLineInput input : selectedLines) {
            if (input.claimItemId != null) requestedSavedIds.add(input.claimItemId);
        }

        Map<Id, ClaimItem> savedById = new Map<Id, ClaimItem>();
        if (!requestedSavedIds.isEmpty()) {
            savedById = provider.loadSavedItems(requestedSavedIds, claimId);
            if (savedById.size() != requestedSavedIds.size()) {
                throw new ContextException(
                    'A selected Claim Item is not accessible or does not belong to this Claim.'
                );
            }
        }

        Set<Id> detailIds = new Set<Id>();
        for (VendorPricingLineInput input : selectedLines) {
            Id selectedDetail = input.coverageLevelDetailId;
            if (selectedDetail != null) detailIds.add(selectedDetail);
        }

        Map<Id, Coverage_Level_Detail__c> detailById =
            new Map<Id, Coverage_Level_Detail__c>();
        if (!detailIds.isEmpty()) {
            detailById = provider.loadDetails(detailIds);
        }

        VendorPricingRequestContext header = fromClaim(claimRows[0]);
        return assemble(header, savedById, detailById, selectedLines);
    }

    @TestVisible
    private static VendorPricingRequestContext fromClaim(Claim claimRow) {
        VendorPricingRequestContext context = new VendorPricingRequestContext();
        context.claimId = claimRow.Id;
        context.policyId = claimRow.PolicyNumberId;
        context.coverageLevelId = claimRow.PolicyNumber == null
            ? null : claimRow.PolicyNumber.Coverage_Level__c;
        context.vin = claimRow.PolicyNumber == null
            ? null : normalize(claimRow.PolicyNumber.VIN__c);
        context.currentMileage = claimRow.Mileage__c;
        context.repairShopAccountId = claimRow.Repair_Shop_Account__c;
        Account shop = claimRow.Repair_Shop_Account__r;
        if (shop != null) {
            context.repairShopName = normalize(shop.Name);
            context.repairShopStreet = normalize(shop.BillingStreet);
            context.repairShopCity = normalize(shop.BillingCity);
            context.repairShopState = normalize(shop.BillingState);
            context.repairShopPostalCode = normalize(shop.BillingPostalCode);
            context.repairShopCountry = normalize(shop.BillingCountry);
        }
        // Deliberately do not inject USA here: fallback is vendor-specific
        // and will be applied by the outbound value-mapping/validation layer.
        return context;
    }

    /** In-memory seam to test business context mapping without org-dependent DML. */
    @TestVisible
    private static VendorPricingRequestContext assemble(
        VendorPricingRequestContext context,
        Map<Id, ClaimItem> savedById,
        Map<Id, Coverage_Level_Detail__c> detailById,
        List<VendorPricingLineInput> selectedLines
    ) {
        if (context == null || context.claimId == null) {
            throw new ContextException('Claim context is required.');
        }
        checkInput(context.claimId, selectedLines);
        if (savedById == null || detailById == null) {
            throw new ContextException('Source record maps are required.');
        }

        context.lines = new List<VendorPricingLineContext>();
        for (VendorPricingLineInput input : selectedLines) {
            Id detailId = input.coverageLevelDetailId;
            if (input.claimItemId != null && !savedById.containsKey(input.claimItemId)) {
                throw new ContextException('A selected Claim Item does not belong to this Claim.');
            }
            if (detailId != null && !detailById.containsKey(detailId)) {
                throw new ContextException('Selected Loss Component is not accessible.');
            }

            VendorPricingLineContext row = new VendorPricingLineContext();
            row.rowKey = input.rowKey.trim();
            row.claimItemId = input.claimItemId;
            row.persisted = (input.claimItemId != null);
            row.detailType = normalize(input.detailType);
            row.partNumber = normalize(input.partNumber);
            row.adjustedQuantity = input.adjustedQuantity;
            row.coverageLevelDetailId = detailId;
            row.description = normalize(input.description);

            if (detailId != null) {
                Coverage_Level_Detail__c detail = detailById.get(detailId);
                if (context.coverageLevelId != null &&
                    detail.Coverage_Level__c != context.coverageLevelId) {
                    throw new ContextException('Selected Loss Component is outside the Claim coverage.');
                }
                row.lossCategory = normalize(detail.Loss_Category__c);
                if (detail.Loss_Component__r != null) {
                    row.lossComponentName = normalize(detail.Loss_Component__r.Name);
                }
            }

            // Search mode is only a normalized hint, not a vendor enum.
            if (row.detailType == 'Labor') row.searchMode = 'LABOR_TIME';
            else if (row.detailType == 'Part' && String.isNotBlank(row.partNumber)) {
                row.searchMode = 'PART_NUMBER';
            } else if (row.detailType == 'Part' && String.isNotBlank(row.lossCategory)) {
                row.searchMode = 'LOSS_CATEGORY';
            } else row.searchMode = 'UNRESOLVED';

            context.lines.add(row);
        }
        return context;
    }

    @TestVisible
    private static void checkInput(Id claimId, List<VendorPricingLineInput> lines) {
        if (claimId == null) throw new ContextException('Claim Id is required.');
        if (lines == null || lines.isEmpty()) {
            throw new ContextException('Select at least one Claim Item for pricing.');
        }
        if (lines.size() > MAX_LINES) {
            throw new ContextException('Too many selected rows for one pricing request.');
        }
        Set<String> keys = new Set<String>();
        Set<Id> ids = new Set<Id>();
        for (VendorPricingLineInput input : lines) {
            if (input == null || String.isBlank(input.rowKey) ||
                input.rowKey.length() > 128) {
                throw new ContextException('Every selected row requires a valid row key.');
            }
            String key = input.rowKey.trim();
            if (keys.contains(key)) {
                throw new ContextException('Duplicate selected row key: ' + key);
            }
            keys.add(key);
            if (input.claimItemId != null) {
                if (ids.contains(input.claimItemId)) {
                    throw new ContextException('A saved Claim Item was selected twice.');
                }
                ids.add(input.claimItemId);
            }
        }
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}