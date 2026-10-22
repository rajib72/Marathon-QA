public without sharing class NotificationOutboxService {
    
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_FAILED = 'Failed';
    
    public static final String FAILURE_CUSTOMER_MAPPING =
        'Customer Mapping';
    
    private NotificationOutboxService() {
    }
    
    public class OutboxRequest {
        
        public String eventCode;
        public String eventKey;
        public String sourceObject;
        public String sourceRecordId;
        
        public Id customerId;
        public Id insurancePolicyId;
        public Id claimId;
        
        public Datetime eventTime;
        
        public String customerName;
        public String policyNumber;
        public String claimNumber;
        
        public String changedField;
        public String oldValue;
        public String newValue;
        public Date effectiveDate;
        
        public String requestPayload;
        public String customerMappingError;
        
        public OutboxRequest() {
            eventTime = System.now();
        }
    }
    
    public class CreationResult {
        
        public Integer insertedCount = 0;
        public Integer duplicateCount = 0;
        public Integer skippedCount = 0;
        public Integer failedCount = 0;
        
        public List<Id> insertedRecordIds = new List<Id>();
        public List<String> errors = new List<String>();
        
        public Boolean hasErrors() {
            return !errors.isEmpty();
        }
    }
    
    /**
* Creates notification outbox records in bulk.
*
* No HTTP callout is made by this method.
* No retry processing is performed by this method.
*/
    public static CreationResult createOutboxRecords(
        List<OutboxRequest> requests
    ) {
        CreationResult result = new CreationResult();
        
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        
        if (
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            result.skippedCount = requests.size();
            return result;
        }
        
        List<OutboxRequest> validRequests =
            new List<OutboxRequest>();
        
        Set<String> candidateKeys = new Set<String>();
        Set<String> keysSeenInCurrentExecution =
            new Set<String>();
        
        for (OutboxRequest request : requests) {
            String validationError =
                validateBasicRequest(request);
            
            if (validationError != null) {
                result.failedCount++;
                result.errors.add(validationError);
                continue;
            }
            
            Notification_Event_Mapping__mdt mapping =
                NotificationIntegrationConfigService.getActiveEventMapping(
                    request.eventCode
                );
            
            if (mapping == null) {
                result.skippedCount++;
                continue;
            }
            
            if (String.isBlank(request.eventKey)) {
                request.eventKey =
                    NotificationEventKeyGenerator.forRecordEvent(
                        request.eventCode,
                        Id.valueOf(
                            request.sourceRecordId
                        ),
                        request.changedField,
                        request.oldValue,
                        request.newValue,
                        request.eventTime
                    );
            }
            
            if (
                keysSeenInCurrentExecution.contains(
                    request.eventKey
                )
            ) {
                result.duplicateCount++;
                continue;
            }
            
            keysSeenInCurrentExecution.add(
                request.eventKey
            );
            
            candidateKeys.add(request.eventKey);
            validRequests.add(request);
        }
        
        if (validRequests.isEmpty()) {
            return result;
        }
        
        Set<String> existingKeys = new Set<String>();
        
        for (
            Customer_Notification_Outbox__c existingRecord :
            [
                SELECT Event_Key__c
                FROM Customer_Notification_Outbox__c
                WHERE Event_Key__c IN :candidateKeys
            ]
        ) {
            existingKeys.add(existingRecord.Event_Key__c);
        }
        
        List<Customer_Notification_Outbox__c> recordsToInsert =
            new List<Customer_Notification_Outbox__c>();
        
        for (OutboxRequest request : validRequests) {
            if (existingKeys.contains(request.eventKey)) {
                result.duplicateCount++;
                continue;
            }
            
            Notification_Event_Mapping__mdt mapping =
                NotificationIntegrationConfigService.getActiveEventMapping(
                    request.eventCode
                );
            
            Customer_Notification_Outbox__c outboxRecord =
                buildOutboxRecord(
                    request,
                    mapping
                );
            
            recordsToInsert.add(outboxRecord);
        }
        
        if (recordsToInsert.isEmpty()) {
            return result;
        }
        
        Database.SaveResult[] saveResults =
            Database.insert(
                recordsToInsert,
                false
            );
        
        for (
            Integer index = 0;
            index < saveResults.size();
            index++
        ) {
            Database.SaveResult saveResult =
                saveResults[index];
            
            Customer_Notification_Outbox__c attemptedRecord =
                recordsToInsert[index];
            
            if (saveResult.isSuccess()) {
                result.insertedCount++;
                result.insertedRecordIds.add(
                    saveResult.getId()
                );
                continue;
            }
            
            for (Database.Error saveError :
                 saveResult.getErrors()
                ) {
                    if (
                        saveError.getStatusCode() ==
                        StatusCode.DUPLICATE_VALUE
                    ) {
                        result.duplicateCount++;
                    } else {
                        result.failedCount++;
                        
                        result.errors.add(
                            'Unable to create notification outbox ' +
                            'record for event ' +
                            attemptedRecord.Event_Code__c +
                            ', source record ' +
                            attemptedRecord.Source_Record_Id__c +
                            '. Error: ' +
                            saveError.getMessage()
                        );
                    }
                }
        }
        
        return result;
    }
    
    private static Customer_Notification_Outbox__c
        buildOutboxRecord(
            OutboxRequest request,
            Notification_Event_Mapping__mdt mapping
        ) {
            
            Customer_Notification_Outbox__c outboxRecord =
                new Customer_Notification_Outbox__c();
            
            outboxRecord.Event_Id__c =
                NotificationEventKeyGenerator.generateEventId();
            
            outboxRecord.Event_Key__c =
                request.eventKey;
            
            outboxRecord.Event_Code__c =
                request.eventCode;
            
            outboxRecord.Notification_Category__c =
                mapping.Notification_Category__c;
            
            outboxRecord.Source_Object__c =request.sourceObject;
            
            outboxRecord.Source_Record_Id__c =
                request.sourceRecordId;
            
            outboxRecord.Event_Time__c =
                request.eventTime == null
                ? System.now()
                : request.eventTime;
            
            outboxRecord.Payload_Version__c =
                String.isNotBlank(
                    mapping.Payload_Version__c
                )
                ? mapping.Payload_Version__c
                : NotificationIntegrationConfigService.getPayloadVersion();
            
            outboxRecord.Customer__c =
                request.customerId;
            
            outboxRecord.Insurance_Policy__c = request.insurancePolicyId;
            
            outboxRecord.Claim__c =
                request.claimId;
            
            outboxRecord.Customer_Name__c =
                request.customerName;
            
            outboxRecord.Policy_Number__c =
                request.policyNumber;
            
            outboxRecord.Claim_Number__c =
                request.claimNumber;
            
            outboxRecord.Changed_Field__c =
                request.changedField;
            
            outboxRecord.Old_Value__c =
                request.oldValue;
            
            outboxRecord.New_Value__c =
                request.newValue;
            
            outboxRecord.Effective_Date__c =
                request.effectiveDate;
            
            outboxRecord.Attempt_Count__c = 0;
            
            if (String.isNotBlank(request.requestPayload)) {
                outboxRecord.Request_Payload__c =
                    request.requestPayload;
            }
            
            if (request.customerId == null) {
                outboxRecord.Status__c =
                    STATUS_FAILED;
                
                outboxRecord.Failure_Type__c =
                    FAILURE_CUSTOMER_MAPPING;
                
                outboxRecord.Error_Message__c =
                    String.isNotBlank(
                        request.customerMappingError
                    )
                    ? request.customerMappingError
                    : buildDefaultCustomerMappingError(
                        request
                    );
            } else {
                outboxRecord.Status__c =
                    STATUS_PENDING;
            }
            
            return outboxRecord;
        }
    
    private static String validateBasicRequest(
        OutboxRequest request
    ) {
        if (request == null) {
            return 'Notification outbox request cannot be null.';
        }
        
        if (String.isBlank(request.eventCode)) {
            return 'Notification eventCode is required.';
        }
        
        if (String.isBlank(request.sourceObject)) {
            return
                'Source object is required for event ' +
                request.eventCode +
                '.';
        }
        
        if (String.isBlank(request.sourceRecordId)) {
            return
                'Source record ID is required for event ' +
                request.eventCode +
                '.';
        }
        
        try {
            Id.valueOf(request.sourceRecordId);
        } catch (Exception ex) {
            return
                'Invalid source record ID for event ' +
                request.eventCode +
                ': ' +
                request.sourceRecordId;
        }
        
        return null;
    }
    
    private static String buildDefaultCustomerMappingError(
        OutboxRequest request
    ) {
        return
            'Insured customer mapping could not be resolved for ' +
            request.sourceObject +
            ' record ' +
            request.sourceRecordId +
            '. Expected customer mapping: ' +
            'InsurancePolicy.NameInsuredId.';
    }
}