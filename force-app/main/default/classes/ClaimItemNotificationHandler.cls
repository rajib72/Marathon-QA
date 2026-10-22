public without sharing class ClaimItemNotificationHandler {

    private static final String EVENT_CLAIM_APPROVED =
        'CLAIM_APPROVED';

    private static final String SOURCE_OBJECT =
        'ClaimItem';

    private static final String MONITORED_FIELD =
        'Status__c';

    private static final String DETECTION_TYPE =
        'Value Transition';

    private static final String STATUS_AUTHORIZED =
        'Authorized';

    private static final String INSPECTION_COMPANY_RECORD_TYPE =
        'Inspection_Company';

    private static final String APP_STATUS_APPROVED =
        'Approved';

    private ClaimItemNotificationHandler() {
    }

    /**
     * Entry point from ClaimItemTrigger after update.
     *
     * Notification processing is isolated from the existing
     * ClaimItemTriggerHandler business logic.
     */
    public static void handleAfterUpdate(
        Map<Id, ClaimItem> oldMap,
        List<ClaimItem> newClaimItems
    ) {
        try {
            processClaimApprovedNotification(
                oldMap,
                newClaimItems
            );
        } catch (Exception e) {
            /*
             * Notification processing must not intentionally
             * break the existing Claim Item transaction.
             */
            QDX_Log.error(
                'CLAIM_APPROVED notification processing failed. ' +
                'Message: ' +
                e.getMessage() +
                ', Line Number: ' +
                e.getLineNumber()
            );

            QDX_Log.publish();
        }
    }

    /**
     * Creates the real-time CLAIM_APPROVED notification when
     * the first eligible Claim Item for a Claim transitions
     * to Authorized.
     *
     * Inspection Company Claim Items are excluded.
     */
    private static void processClaimApprovedNotification(
        Map<Id, ClaimItem> oldMap,
        List<ClaimItem> newClaimItems
    ) {
        if (
            oldMap == null ||
            oldMap.isEmpty() ||
            newClaimItems == null ||
            newClaimItems.isEmpty() ||
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return;
        }

        Notification_Event_Mapping__mdt mapping =
            getValidatedClaimApprovedMapping();

        if (mapping == null) {
            return;
        }

        Set<Id> currentAuthorizedItemIds =
            new Set<Id>();

        Set<Id> candidateClaimIds =
            new Set<Id>();

        /*
         * Detect only genuine Status transitions to Authorized
         * in the current transaction.
         */
        for (ClaimItem newItem : newClaimItems) {
            ClaimItem oldItem =
                oldMap.get(newItem.Id);

            if (
                oldItem == null ||
                newItem.ClaimId == null ||
                oldItem.Status__c == newItem.Status__c ||
                !equalsIgnoreCase(
                    newItem.Status__c,
                    STATUS_AUTHORIZED
                )
            ) {
                continue;
            }

            currentAuthorizedItemIds.add(
                newItem.Id
            );

            candidateClaimIds.add(
                newItem.ClaimId
            );
        }

        if (currentAuthorizedItemIds.isEmpty()) {
            return;
        }

        /*
         * Query currently Authorized Claim Items for affected Claims.
         *
         * This allows us to:
         * 1. determine the Payee Record Type;
         * 2. identify an earlier eligible Authorized Claim Item;
         * 3. obtain Claim, Policy and insured customer information.
         */
        List<ClaimItem> authorizedItems = [
            SELECT
                Id,
                ClaimId,
                Status__c,
                Payee_Name__c,
                Payee_Name__r.RecordType.DeveloperName,
                Claim.Name,
                Claim.PolicyNumberId,
                Claim.PolicyNumber.Name,
                Claim.PolicyNumber.NameInsuredId,
                Claim.PolicyNumber.NameInsured.Name
            FROM ClaimItem
            WHERE
                ClaimId IN :candidateClaimIds
                AND Status__c = :STATUS_AUTHORIZED
            ORDER BY ClaimId ASC, Id ASC
        ];

        Map<Id, ClaimItem> firstCurrentEligibleItemByClaim =
            new Map<Id, ClaimItem>();

        Set<Id> claimsWithPriorEligibleAuthorizedItem =
            new Set<Id>();

        for (ClaimItem item : authorizedItems) {

            /*
             * Inspection Company Claim Items do not participate
             * in CLAIM_APPROVED eligibility.
             */
            if (isInspectionCompanyPayee(item)) {
                continue;
            }

            if (
                currentAuthorizedItemIds.contains(
                    item.Id
                )
            ) {
                if (
                    !firstCurrentEligibleItemByClaim
                        .containsKey(item.ClaimId)
                ) {
                    firstCurrentEligibleItemByClaim.put(
                        item.ClaimId,
                        item
                    );
                }
            } else {
                /*
                 * Another eligible Claim Item was already
                 * Authorized before this transaction.
                 */
                claimsWithPriorEligibleAuthorizedItem.add(
                    item.ClaimId
                );
            }
        }

        if (firstCurrentEligibleItemByClaim.isEmpty()) {
            return;
        }

        Set<Id> eligibleClaimIds =
            new Set<Id>();

        eligibleClaimIds.addAll(
            firstCurrentEligibleItemByClaim.keySet()
        );

        eligibleClaimIds.removeAll(
            claimsWithPriorEligibleAuthorizedItem
        );

        if (eligibleClaimIds.isEmpty()) {
            return;
        }

        /*
         * Protect Claims for which CLAIM_APPROVED was already
         * recorded, including events generated under an earlier
         * implementation.
         */
        Set<Id> alreadyNotifiedClaimIds =
            queryClaimsWithExistingApprovedNotification(
                eligibleClaimIds
            );

        Datetime eventTime =
            System.now();

        List<NotificationOutboxService.OutboxRequest>
            outboxRequests =
            new List<
                NotificationOutboxService.OutboxRequest
            >();

        for (Id claimId : eligibleClaimIds) {

            if (
                alreadyNotifiedClaimIds.contains(
                    claimId
                )
            ) {
                continue;
            }

            ClaimItem claimItem =
                firstCurrentEligibleItemByClaim.get(
                    claimId
                );

            ClaimItem oldItem =
                oldMap.get(claimItem.Id);

            NotificationOutboxService.OutboxRequest request =
                buildClaimApprovedOutboxRequest(
                    claimItem,
                    oldItem,
                    mapping,
                    eventTime
                );

            outboxRequests.add(request);
        }

        if (outboxRequests.isEmpty()) {
            return;
        }

        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                outboxRequests
            );

        logCreationErrors(result);

        /*
         * Claim notifications remain real time.
         */
        NotificationWebhookDispatcher.enqueue(
            result.insertedRecordIds
        );
    }

    /**
     * Validates that CLAIM_APPROVED metadata represents
     * ClaimItem.Status__c -> Authorized.
     */
    private static Notification_Event_Mapping__mdt
        getValidatedClaimApprovedMapping()
    {
        Notification_Event_Mapping__mdt mapping =
            NotificationIntegrationConfigService.getActiveEventMapping(
                    EVENT_CLAIM_APPROVED
                );

        if (mapping == null) {
            return null;
        }

        if (
            !equalsIgnoreCase(
                mapping.Event_Code__c,
                EVENT_CLAIM_APPROVED
            ) ||
            !equalsIgnoreCase(
                mapping.Source_Object__c,
                SOURCE_OBJECT
            ) ||
            !equalsIgnoreCase(
                mapping.Monitored_Field__c,
                MONITORED_FIELD
            ) ||
            !equalsIgnoreCase(
                mapping.Detection_Type__c,
                DETECTION_TYPE
            ) ||
            !equalsIgnoreCase(
                mapping.Target_Value__c,
                STATUS_AUTHORIZED
            )
        ) {
            return null;
        }

        return mapping;
    }

    private static Boolean isInspectionCompanyPayee(
        ClaimItem claimItem
    ) {
        return
            claimItem != null &&
            claimItem.Payee_Name__r != null &&
            claimItem.Payee_Name__r.RecordType != null &&
            equalsIgnoreCase(
                claimItem.Payee_Name__r
                    .RecordType.DeveloperName,
                INSPECTION_COMPANY_RECORD_TYPE
            );
    }

    private static Set<Id>
        queryClaimsWithExistingApprovedNotification(
            Set<Id> claimIds
        )
    {
        Set<Id> result =
            new Set<Id>();

        if (
            claimIds == null ||
            claimIds.isEmpty()
        ) {
            return result;
        }

        for (
            Customer_Notification_Outbox__c outboxRecord :
            [
                SELECT Claim__c
                FROM Customer_Notification_Outbox__c
                WHERE
                    Claim__c IN :claimIds
                    AND Event_Code__c =
                        :EVENT_CLAIM_APPROVED
            ]
        ) {
            if (outboxRecord.Claim__c != null) {
                result.add(
                    outboxRecord.Claim__c
                );
            }
        }

        return result;
    }

    private static NotificationOutboxService.OutboxRequest
        buildClaimApprovedOutboxRequest(
            ClaimItem claimItem,
            ClaimItem oldItem,
            Notification_Event_Mapping__mdt mapping,
            Datetime eventTime
        )
    {
        NotificationOutboxService.OutboxRequest request =
            new NotificationOutboxService.OutboxRequest();

        request.eventCode =
            mapping.Event_Code__c;

        /*
         * Stable Claim-level key prevents more than one
         * CLAIM_APPROVED event for the same Claim.
         */
        request.eventKey =
            NotificationEventKeyGenerator.forClaimApproved(
                    claimItem.ClaimId
                );

        request.sourceObject =
            SOURCE_OBJECT;

        request.sourceRecordId =
            String.valueOf(
                claimItem.Id
            );

        request.claimId =
            claimItem.ClaimId;

        request.claimNumber =
            claimItem.Claim == null
                ? null
                : claimItem.Claim.Name;

        request.eventTime =
            eventTime;

        request.changedField =
            MONITORED_FIELD;

        request.oldValue =
            oldItem == null
                ? null
                : oldItem.Status__c;

        request.newValue =
            claimItem.Status__c;

        if (claimItem.Claim == null) {
            request.customerMappingError =
                'The parent Claim could not be resolved for the ' +
                'CLAIM_APPROVED notification. Claim Item Id: ' +
                claimItem.Id +
                '.';

            return request;
        }

        request.insurancePolicyId =
            claimItem.Claim.PolicyNumberId;

        if (
            claimItem.Claim.PolicyNumberId == null
        ) {
            request.customerMappingError =
                'Claim.PolicyNumberId is blank. ' +
                'The Insurance Policy and customer could not be ' +
                'resolved for the CLAIM_APPROVED notification. ' +
                'Claim Id: ' +
                claimItem.ClaimId +
                ', Claim Item Id: ' +
                claimItem.Id +
                '.';

            return request;
        }

        InsurancePolicy policy =
            claimItem.Claim.PolicyNumber;

        if (policy == null) {
            request.customerMappingError =
                'The Insurance Policy referenced by the Claim ' +
                'could not be resolved for the CLAIM_APPROVED ' +
                'notification. Claim Id: ' +
                claimItem.ClaimId +
                ', Policy Id: ' +
                claimItem.Claim.PolicyNumberId +
                '.';

            return request;
        }

        request.policyNumber =
            policy.Name;

        request.customerId =
            policy.NameInsuredId;

        request.customerName =
            policy.NameInsured == null
                ? null
                : policy.NameInsured.Name;

        if (policy.NameInsuredId == null) {
            request.customerMappingError =
                'InsurancePolicy.NameInsuredId is blank. ' +
                'The insured customer could not be resolved for ' +
                'the CLAIM_APPROVED notification. Claim Id: ' +
                claimItem.ClaimId +
                ', Insurance Policy Id: ' +
                claimItem.Claim.PolicyNumberId +
                '.';

            return request;
        }

        request.requestPayload =
            buildClaimApprovedWebhookPayload(
                claimItem,
                policy,
                mapping.Event_Code__c,
                eventTime
            );

        return request;
    }

    /**
     * Salesforce source Status = Authorized.
     * App-facing notification Status = Approved.
     */
    private static String buildClaimApprovedWebhookPayload(
        ClaimItem claimItem,
        InsurancePolicy policy,
        String eventCode,
        Datetime eventTime
    ) {
        NotificationWebhookPayload payload =
            NotificationWebhookPayload.forRecordEvent(
                eventCode,
                policy.NameInsuredId,
                policy.Id,
                claimItem.ClaimId,
                eventTime
            );

        payload.addAttribute(
            'customerName',
            policy.NameInsured == null
                ? null
                : policy.NameInsured.Name
        ).addAttribute(
            'policyNumber',
            policy.Name
        ).addAttribute(
            'claimNumber',
            claimItem.Claim == null
                ? null
                : claimItem.Claim.Name
        ).addAttribute(
            'status',
            APP_STATUS_APPROVED
        );

        return payload.toJson();
    }

    private static void logCreationErrors(
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
                'CLAIM_APPROVED notification outbox error: ' +
                errorMessage
            );
        }

        QDX_Log.publish();
    }

    private static Boolean equalsIgnoreCase(
        String firstValue,
        String secondValue
    ) {
        return normalizeValue(firstValue) ==
            normalizeValue(secondValue);
    }

    private static String normalizeValue(
        String value
    ) {
        return String.isBlank(value)
            ? ''
            : value.trim().toUpperCase();
    }
}