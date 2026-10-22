/**
 * @description
 * Handles Claim Item processing when a Payment is cancelled.
 *
 * When a Payment changes to Cancelled:
 * 1. Related Claim Items are updated to Cancelled.
 * 2. Each affected Claim Item is cloned.
 * 3. Each cloned Claim Item is set to Requested.
 */
public with sharing class PaymentClaimItemUtility {

    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final String STATUS_REQUESTED = 'Requested';


    /**
     * Processes all Claim Items related to cancelled Payments.
     *
     * @param cancelledPaymentIds Payment IDs whose status changed
     *        to Cancelled.
     */
    public static void handleCancelledPayments(
        Set<Id> cancelledPaymentIds
    ) {

        /*
         * ----------------------------------------------------
         * Validate input
         * ----------------------------------------------------
         */
        if (
            cancelledPaymentIds == null ||
            cancelledPaymentIds.isEmpty()
        ) {
            return;
        }


        /*
         * ----------------------------------------------------
         * Get ClaimItem fields dynamically.
         * ----------------------------------------------------
         *
         * We do not use FIELDS(ALL).
         *
         * A Map with a lower-case key is used so that fields
         * cannot be added more than once even if the field
         * names differ only by case.
         */
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.ClaimItem.fields.getMap();

        Map<String, String> uniqueFieldNames =
            new Map<String, String>();


        /*
         * ----------------------------------------------------
         * Add readable and non-calculated fields.
         * ----------------------------------------------------
         */
        for (String fieldName : fieldMap.keySet()) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (
                fieldDescribe.isAccessible() &&
                !fieldDescribe.isCalculated()
            ) {

                /*
                 * Use lower-case field name as the map key.
                 *
                 * Example:
                 * ID
                 * Id
                 * id
                 *
                 * All would resolve to the same key.
                 */
                String normalizedFieldName =
                    fieldName.toLowerCase();

                if (
                    !uniqueFieldNames.containsKey(
                        normalizedFieldName
                    )
                ) {
                    uniqueFieldNames.put(
                        normalizedFieldName,
                        fieldName
                    );
                }
            }
        }


        /*
         * ----------------------------------------------------
         * Make sure required fields exist exactly once.
         * ----------------------------------------------------
         *
         * We first check the normalized map.
         * Therefore these fields cannot be duplicated.
         */
        if (
            !uniqueFieldNames.containsKey('id')
        ) {
            uniqueFieldNames.put(
                'id',
                'Id'
            );
        }

        if (
            !uniqueFieldNames.containsKey('payment__c')
        ) {
            uniqueFieldNames.put(
                'payment__c',
                'Payment__c'
            );
        }

        if (
            !uniqueFieldNames.containsKey('status__c')
        ) {
            uniqueFieldNames.put(
                'status__c',
                'Status__c'
            );
        }

        /*
         * Loss Description:
         *
         * Field Label:
         * Loss Description
         *
         * Field API Name:
         * Coverage_Level_Detail__c
         */
        if (
            !uniqueFieldNames.containsKey(
                'coverage_level_detail__c'
            )
        ) {
            uniqueFieldNames.put(
                'coverage_level_detail__c',
                'Coverage_Level_Detail__c'
            );
        }


        /*
         * ----------------------------------------------------
         * Convert unique field names to a List.
         * ----------------------------------------------------
         */
        List<String> fieldNames =
            new List<String>();

        fieldNames.addAll(
            uniqueFieldNames.values()
        );


        /*
         * ----------------------------------------------------
         * Build Claim Item SOQL.
         * ----------------------------------------------------
         */
        String claimItemQuery =
            'SELECT ' +
            String.join(fieldNames, ',') +
            ' FROM ClaimItem' +
            ' WHERE Payment__c IN :cancelledPaymentIds';


        /*
         * ----------------------------------------------------
         * Debug the final query.
         *
         * This is intentionally included so that we can
         * verify the exact SOQL generated in QA.
         * ----------------------------------------------------
         */
        System.debug(
            LoggingLevel.ERROR,
            'PaymentClaimItemUtility - Claim Item Query: ' +
            claimItemQuery
        );


        /*
         * ----------------------------------------------------
         * Query Claim Items related to cancelled Payments.
         * ----------------------------------------------------
         */
        List<ClaimItem> affectedClaimItems =
            Database.query(claimItemQuery);


        /*
         * ----------------------------------------------------
         * Nothing to process.
         * ----------------------------------------------------
         */
        if (
            affectedClaimItems == null ||
            affectedClaimItems.isEmpty()
        ) {
            return;
        }


        /*
         * ----------------------------------------------------
         * Lists for DML operations.
         * ----------------------------------------------------
         */
        List<ClaimItem> claimItemsToUpdate =
            new List<ClaimItem>();

        List<ClaimItem> claimItemsToClone =
            new List<ClaimItem>();


        /*
         * ----------------------------------------------------
         * Process each Claim Item.
         * ----------------------------------------------------
         */
        for (
            ClaimItem originalClaimItem :
            affectedClaimItems
        ) {

            /*
             * ------------------------------------------------
             * Do not process Claim Items that are already
             * Cancelled.
             * ------------------------------------------------
             */
            if (
                originalClaimItem.Status__c ==
                STATUS_CANCELLED
            ) {
                continue;
            }


            /*
             * ------------------------------------------------
             * Update ORIGINAL Claim Item.
             * ------------------------------------------------
             *
             * Use a sparse SObject containing only the fields
             * that need to be updated.
             */
            ClaimItem claimItemUpdate =
                new ClaimItem();

            claimItemUpdate.Id =
                originalClaimItem.Id;

            claimItemUpdate.Status__c =
                STATUS_CANCELLED;

            claimItemsToUpdate.add(
                claimItemUpdate
            );


            /*
             * ------------------------------------------------
             * Clone ORIGINAL Claim Item.
             * ------------------------------------------------
             */
            ClaimItem clonedClaimItem =
                originalClaimItem.clone(
                    false, // preserveId
                    false, // isDeepClone
                    false, // preserveReadonlyTimestamps
                    false  // preserveAutonumber
                );


            /*
             * ------------------------------------------------
             * Set cloned Claim Item to Requested.
             * ------------------------------------------------
             */
            clonedClaimItem.Status__c =
                STATUS_REQUESTED;


            /*
             * ------------------------------------------------
             * Preserve Loss Description.
             * ------------------------------------------------
             *
             * Loss Description field:
             * Coverage_Level_Detail__c
             */
            clonedClaimItem.Coverage_Level_Detail__c =
                originalClaimItem.Coverage_Level_Detail__c;


            /*
             * The cloned Claim Item should not retain
             * the cancelled Payment.
             */
            clonedClaimItem.Payment__c = null;


            /*
             * Add cloned Claim Item to INSERT list.
             */
            claimItemsToClone.add(
                clonedClaimItem
            );
        }


        /*
         * ----------------------------------------------------
         * Update ORIGINAL Claim Items.
         * ----------------------------------------------------
         */
        if (
            !claimItemsToUpdate.isEmpty()
        ) {
            update claimItemsToUpdate;
        }


        if (
            !claimItemsToClone.isEmpty()
        ) {

            SObjectAccessDecision accessDecision =
                Security.stripInaccessible(
                    AccessType.CREATABLE,
                    claimItemsToClone
                );


            /*
             * Get sanitized records.
             */
            List<SObject> sanitizedRecords =
                accessDecision.getRecords();


            /*
             * Convert sanitized SObjects back to ClaimItem.
             */
            List<ClaimItem> sanitizedClaimItems =
                new List<ClaimItem>();


            for (
                SObject sanitizedRecord :
                sanitizedRecords
            ) {

                sanitizedClaimItems.add(
                    (ClaimItem) sanitizedRecord
                );
            }


            /*
             * ------------------------------------------------
             * Insert cloned Claim Items.
             * ------------------------------------------------
             */
            if (
                !sanitizedClaimItems.isEmpty()
            ) {

                insert sanitizedClaimItems;
            }
        }
    }
}