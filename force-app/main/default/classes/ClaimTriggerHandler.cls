public without sharing class ClaimTriggerHandler {
    
    private static final String SOURCE_OBJECT = 'Claim';
    private static final String MONITORED_FIELD = 'Status';
    private static final String DETECTION_TYPE = 'Value Transition';
    
    private static final String EVENT_CLAIM_INITIATED =
        'CLAIM_INITIATED';
    
    private static final String TARGET_STATUS_OPEN =
        'Open';
    
    private static final String APP_STATUS_INITIATED =
        'Initiated';
    
    private ClaimTriggerHandler() {
    }
    
    /**
* Entry point from ClaimTrigger after insert.
*
* Salesforce Claim creation automatically starts with Status = Open.
* This represents CLAIM_INITIATED for the mobile application.
*/
    public static void handleAfterInsert(
        List<Claim> newClaims
    ) {
        
        if (
            newClaims == null ||
            newClaims.isEmpty()
        ) {
            return;
        }
        
        
        processClaimCreationNotifications(
            newClaims
        );
    }
    /**
* Entry point from ClaimTrigger after update.
*/
    public static void handleAfterUpdate(
        List<Claim> newClaims,
        Map<Id, Claim> oldClaimMap
    ) {
        if (
            newClaims == null ||
            newClaims.isEmpty() ||
            oldClaimMap == null ||
            oldClaimMap.isEmpty()
        ) {
            return;
        }
        
        processClaimStatusNotifications(
            newClaims,
            oldClaimMap
        );
    }
    
    /**
* Detects qualifying Claim Status transitions and creates
* notification outbox records in bulk.
*/
    private static void processClaimStatusNotifications(
        List<Claim> newClaims,
        Map<Id, Claim> oldClaimMap
    ) {
        if (
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return;
        }
        
        Map<String, Notification_Event_Mapping__mdt>
            mappingsByTargetStatus =
            getActiveMappingsByTargetStatus();
        
        if (mappingsByTargetStatus.isEmpty()) {
            return;
        }
        
        List<Claim> qualifyingClaims = new List<Claim>();
        Set<Id> insurancePolicyIds = new Set<Id>();
        
        for (Claim newClaim : newClaims) {
            Claim oldClaim = oldClaimMap.get(newClaim.Id);
            
            if (!isQualifyingStatusTransition(
                newClaim,
                oldClaim,
                mappingsByTargetStatus
            )) {
                continue;
            }
            
            qualifyingClaims.add(newClaim);
            
            if (newClaim.PolicyNumberId != null) {
                insurancePolicyIds.add(
                    newClaim.PolicyNumberId
                );
            }
        }
        
        if (qualifyingClaims.isEmpty()) {
            return;
        }
        
        Map<Id, InsurancePolicy> policiesById =
            queryInsurancePolicies(insurancePolicyIds);
        
        List<NotificationOutboxService.OutboxRequest>
            outboxRequests =
            buildOutboxRequests(
                qualifyingClaims,
                oldClaimMap,
                mappingsByTargetStatus,
                policiesById
            );
        
        if (outboxRequests.isEmpty()) {
            return;
        }
        
        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                outboxRequests
            );
        
        NotificationWebhookDispatcher.enqueue(
            result.insertedRecordIds
        );
    }
    
    /**
* Creates CLAIM_INITIATED notifications when a Claim
* is created directly with Status = Open.
*/
    private static void processClaimCreationNotifications(
        List<Claim> newClaims
    ) {
        
        
        if (
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return;
        }
        
        
        Notification_Event_Mapping__mdt mapping =
            NotificationIntegrationConfigService.getActiveEventMapping(
                EVENT_CLAIM_INITIATED
            );
        
        
        if (
            !isSupportedClaimMapping(mapping)
        ) {
            return;
        }
        
        
        List<Claim> qualifyingClaims =
            new List<Claim>();
        
        
        Set<Id> insurancePolicyIds =
            new Set<Id>();
        
        
        for (Claim claimRecord : newClaims) {
            
            
            if (
                claimRecord.Status != TARGET_STATUS_OPEN
            ) {
                continue;
            }
            
            
            qualifyingClaims.add(
                claimRecord
            );
            
            
            if (
                claimRecord.PolicyNumberId != null
            ) {
                insurancePolicyIds.add(
                    claimRecord.PolicyNumberId
                );
            }
        }
        
        
        if (
            qualifyingClaims.isEmpty()
        ) {
            return;
        }
        
        
        Map<Id, InsurancePolicy> policiesById =
            queryInsurancePolicies(
                insurancePolicyIds
            );
        
        
        List<NotificationOutboxService.OutboxRequest>
            requests =
            new List<NotificationOutboxService.OutboxRequest>();
        
        
        for (Claim claimRecord : qualifyingClaims) {
            
            
            InsurancePolicy policy =
                policiesById.get(
                    claimRecord.PolicyNumberId
                );
            
            
            Datetime eventTime =
                resolveEventTime(
                    claimRecord
                );
            
            
            NotificationOutboxService.OutboxRequest request =
                buildInsertClaimOutboxRequest(
                    claimRecord,
                    mapping,
                    policy,
                    eventTime
                );
            
            
            requests.add(
                request
            );
        }
        
        
        if (
            requests.isEmpty()
        ) {
            return;
        }
        
        
        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                requests
            );
        
        
        NotificationWebhookDispatcher.enqueue(
            result.insertedRecordIds
        );
    }
    
    /**
* Confirms that Claim.Status has genuinely changed to a configured
* qualifying target value.
*/
    private static Boolean isQualifyingStatusTransition(
        Claim newClaim,
        Claim oldClaim,
        Map<String, Notification_Event_Mapping__mdt>
        mappingsByTargetStatus
    ) {
        if (
            newClaim == null ||
            oldClaim == null ||
            String.isBlank(newClaim.Status)
        ) {
            return false;
        }
        
        if (oldClaim.Status == newClaim.Status) {
            return false;
        }
        
        return mappingsByTargetStatus.containsKey(
            normalizeKey(newClaim.Status)
        );
    }
    
    /**
* Reads and validates the active Claim mapping.
*
* Salesforce source condition:
* Claim.Status -> Open
*
* App notification event:
* CLAIM_INITIATED
*/
    private static Map<String, Notification_Event_Mapping__mdt>
        getActiveMappingsByTargetStatus()
    {
        Map<String, Notification_Event_Mapping__mdt> result =
            new Map<String, Notification_Event_Mapping__mdt>();
        
        Notification_Event_Mapping__mdt mapping =
            NotificationIntegrationConfigService.getActiveEventMapping(
                EVENT_CLAIM_INITIATED
            );
        
        if (!isSupportedClaimMapping(mapping)) {
            return result;
        }
        
        result.put(
            normalizeKey(mapping.Target_Value__c),
            mapping
        );
        
        return result;
    }
    
    private static Boolean isSupportedClaimMapping(
        Notification_Event_Mapping__mdt mapping
    ) {
        if (
            mapping == null ||
            String.isBlank(mapping.Event_Code__c) ||
            String.isBlank(mapping.Target_Value__c)
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Event_Code__c,
                EVENT_CLAIM_INITIATED
            )
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Source_Object__c,
                SOURCE_OBJECT
            )
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Monitored_Field__c,
                MONITORED_FIELD
            )
        ) {
            return false;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Detection_Type__c,
                DETECTION_TYPE
            )
        ) {
            return false;
        }
        
        /*
* The Salesforce status that represents the app's
* "Initiated" notification is Open.
*/
        return equalsIgnoreCase(
            mapping.Target_Value__c,
            TARGET_STATUS_OPEN
        );
    }
    
    /**
* Queries all related Insurance Policies and customers in one SOQL.
*/
    private static Map<Id, InsurancePolicy>
        queryInsurancePolicies(
            Set<Id> insurancePolicyIds
        )
    {
        if (
            insurancePolicyIds == null ||
            insurancePolicyIds.isEmpty()
        ) {
            return new Map<Id, InsurancePolicy>();
        }
        
        return new Map<Id, InsurancePolicy>([
            SELECT
            Id,
            Name,
            NameInsuredId,
            NameInsured.Name
            FROM InsurancePolicy
            WHERE Id IN :insurancePolicyIds
        ]);
    }
    
    /**
* Builds one outbox request for every qualifying Claim.
*/
    private static List<
        NotificationOutboxService.OutboxRequest
        > buildOutboxRequests(
            List<Claim> qualifyingClaims,
            Map<Id, Claim> oldClaimMap,
            Map<String, Notification_Event_Mapping__mdt>
            mappingsByTargetStatus,
            Map<Id, InsurancePolicy> policiesById
        ) {
            List<NotificationOutboxService.OutboxRequest>
                requests =
                new List<
                NotificationOutboxService.OutboxRequest
                >();
            
            for (Claim newClaim : qualifyingClaims) {
                Claim oldClaim = oldClaimMap.get(newClaim.Id);
                
                Notification_Event_Mapping__mdt mapping =
                    mappingsByTargetStatus.get(
                        normalizeKey(newClaim.Status)
                    );
                
                if (mapping == null) {
                    continue;
                }
                
                InsurancePolicy policy =
                    newClaim.PolicyNumberId == null
                    ? null
                    : policiesById.get(
                        newClaim.PolicyNumberId
                    );
                
                Datetime eventTime =
                    resolveEventTime(newClaim);
                
                NotificationOutboxService.OutboxRequest request =
                    buildBaseOutboxRequest(
                        newClaim,
                        oldClaim,
                        mapping,
                        eventTime
                    );
                
                populatePolicyAndCustomerInformation(
                    request,
                    newClaim,
                    policy
                );
                
                if (
                    policy != null &&
                    policy.NameInsuredId != null
                ) {
                    request.requestPayload =
                        buildWebhookPayload(
                            mapping.Event_Code__c,
                            newClaim,
                            policy,
                            eventTime
                        );
                }
                
                requests.add(request);
            }
            
            return requests;
        }
    
    private static NotificationOutboxService.OutboxRequest
        buildBaseOutboxRequest(
            Claim newClaim,
            Claim oldClaim,
            Notification_Event_Mapping__mdt mapping,
            Datetime eventTime
        )
    {
        NotificationOutboxService.OutboxRequest request =
            new NotificationOutboxService.OutboxRequest();
        
        request.eventCode = mapping.Event_Code__c;
        
        request.eventKey =
            NotificationEventKeyGenerator.forRecordEvent(
                mapping.Event_Code__c,
                newClaim.Id,
                MONITORED_FIELD,
                oldClaim.Status,
                newClaim.Status,
                eventTime
            );
        
        request.sourceObject = SOURCE_OBJECT;
        request.sourceRecordId =
            String.valueOf(newClaim.Id);
        
        request.claimId = newClaim.Id;
        request.claimNumber = newClaim.Name;
        
        request.insurancePolicyId =
            newClaim.PolicyNumberId;
        
        request.eventTime = eventTime;
        
        request.changedField = MONITORED_FIELD;
        request.oldValue = oldClaim.Status;
        request.newValue = newClaim.Status;
        
        return request;
    }
    
    private static NotificationOutboxService.OutboxRequest
buildInsertClaimOutboxRequest(
    Claim claimRecord,
    Notification_Event_Mapping__mdt mapping,
    InsurancePolicy policy,
    Datetime eventTime
) {


    NotificationOutboxService.OutboxRequest request =
        new NotificationOutboxService.OutboxRequest();


    request.eventCode =
        mapping.Event_Code__c;


    request.eventKey =
        NotificationEventKeyGenerator.forRecordEvent(
            mapping.Event_Code__c,
            claimRecord.Id,
            'Status',
            null,
            claimRecord.Status,
            eventTime
        );


    request.sourceObject =
        SOURCE_OBJECT;


    request.sourceRecordId =
        String.valueOf(
            claimRecord.Id
        );


    request.claimId =
        claimRecord.Id;


    request.claimNumber =
        claimRecord.Name;


    request.insurancePolicyId =
        claimRecord.PolicyNumberId;


    request.eventTime =
        eventTime;


    request.changedField =
        MONITORED_FIELD;


    request.oldValue =
        null;


    request.newValue =
        claimRecord.Status;



    populatePolicyAndCustomerInformation(
        request,
        claimRecord,
        policy
    );


    if (
        policy != null &&
        policy.NameInsuredId != null
    ) {

        request.requestPayload =
            buildWebhookPayload(
                mapping.Event_Code__c,
                claimRecord,
                policy,
                eventTime
            );
    }


    return request;
}
    
    /**
* Populates customer and policy snapshot details.
*
* Missing mappings are not ignored. The outbox service will create
* the event with Status = Failed and detailed failure information.
*/
    private static void populatePolicyAndCustomerInformation(
        NotificationOutboxService.OutboxRequest request,
        Claim claimRecord,
        InsurancePolicy policy
    ) {
        if (claimRecord.PolicyNumberId == null) {
            request.customerMappingError =
                'Claim.PolicyNumberId is blank. ' +
                'The related Insurance Policy and customer could not ' +
                'be resolved. Claim Id: ' +
                claimRecord.Id +
                '.';
            
            return;
        }
        
        if (policy == null) {
            request.customerMappingError =
                'The Insurance Policy referenced by ' +
                'Claim.PolicyNumberId could not be retrieved. ' +
                'Claim Id: ' +
                claimRecord.Id +
                ', PolicyNumberId: ' +
                claimRecord.PolicyNumberId +
                '.';
            
            return;
        }
        
        request.insurancePolicyId = policy.Id;
        request.policyNumber = policy.Name;
        request.customerId = policy.NameInsuredId;
        
        if (policy.NameInsuredId == null) {
            request.customerMappingError =
                'InsurancePolicy.NameInsuredId is blank. ' +
                'The insured customer could not be resolved for the ' +
                'Claim notification. Claim Id: ' +
                claimRecord.Id +
                ', Insurance Policy Id: ' +
                policy.Id +
                '.';
            
            return;
        }
        
        request.customerName =
            policy.NameInsured == null
            ? null
            : policy.NameInsured.Name;
    }
    
    /**
* Builds the JSON snapshot sent to the app.
*
* Salesforce Status = Open represents the app notification
* state "Initiated".
*/
    private static String buildWebhookPayload(
        String eventCode,
        Claim claimRecord,
        InsurancePolicy policy,
        Datetime eventTime
    ) {
        NotificationWebhookPayload payload =
            NotificationWebhookPayload.forRecordEvent(
                eventCode,
                policy.NameInsuredId,
                policy.Id,
                claimRecord.Id,
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
            claimRecord.Name
        ).addAttribute(
            'status',
            APP_STATUS_INITIATED
        );
        
        return payload.toJson();
    }
    
    /**
* The existing Claim before-save Flow sets
* Last_Status_Changed__c whenever Status changes.
*
* System.now() is retained as a safe fallback.
*/
    private static Datetime resolveEventTime(
        Claim claimRecord
    ) {
        return claimRecord.Last_Status_Changed__c != null
            ? claimRecord.Last_Status_Changed__c
            : System.now();
    }
    
    private static String normalizeKey(String value) {
        return String.isBlank(value)
            ? ''
            : value.trim().toUpperCase();
    }
    
    private static Boolean equalsIgnoreCase(
        String firstValue,
        String secondValue
    ) {
        return normalizeKey(firstValue) ==
            normalizeKey(secondValue);
    }
}