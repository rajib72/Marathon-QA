/**
* Scheduled orchestration and batch processing for non-Claim
* Marathon Connect notifications.
*
* The Schedulable entry point runs around noon Central Time and:
* 1. Starts dispatch of Pending Contract and Finance notifications
*    that existed when the scheduled run began.
* 2. Starts the 90-day Contract Expiry Reminder batch.
*
* The Batchable implementation creates reminder outbox records for
* Insurance Policies whose Expiration_Date_Calc__c is exactly the
* configured number of days from the batch execution date.
*
* Claim notifications are not handled here because they continue
* to be dispatched in real time.
*/
public without sharing class ContractExpiryReminderBatch
implements Database.Batchable<SObject>,
Schedulable,
Database.Stateful {
    
    private static final String EVENT_CODE =
        'CONTRACT_EXPIRY_REMINDER_90';
    
    private static final String SOURCE_OBJECT =
        'InsurancePolicy';
    
    private static final String MONITORED_FIELD =
        'Expiration_Date_Calc__c';
    
    private static final String DETECTION_TYPE =
        'Date Offset';
    
    private static final Integer DEFAULT_BATCH_SIZE = 200;
    
    private Integer qualifyingContractCount = 0;
    private Integer insertedOutboxCount = 0;
    private Integer duplicateCount = 0;
    private Integer skippedCount = 0;
    private Integer serviceFailureCount = 0;
    private Integer missingCustomerCount = 0;
    
    /**
* Entry point used by Scheduled Apex.
*
* The exact schedule will be configured later after the client
* confirms the execution time and US timezone.
*/
    /**
* Entry point used by Scheduled Apex.
*
* This method is intended to run once daily around 12:00 PM
* U.S. Central Time.
*
* The cutoff is captured once at the beginning of the scheduled
* transaction and is passed to the Policy/Finance dispatcher.
* Records created after this cutoff remain Pending for the next
* scheduled run.
*/
    public void execute(SchedulableContext context) {
        if (
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return;
        }
        
        /*
* Capture one fixed cutoff for this scheduled execution.
*
* All chained Policy/Finance Queueables retain this same
* cutoff so notifications created after the scheduled run
* begins cannot accidentally be sent during this run.
*/
        Datetime dispatchCutoff = System.now();
        
        /*
* Dispatch Pending Contract and Finance notification events
* that existed at or before this run's cutoff.
*
* Claim notifications are excluded by the dispatcher and
* continue to be sent in real time.
*/
        NotificationWebhookDispatcher.enqueueScheduledPolicyFinanceEvents(
            dispatchCutoff
        );
        
        /*
* Run the existing 90-day Contract Expiry Reminder process.
*
* Reminder outbox records created by the batch continue to be
* dispatched through the existing explicit-ID dispatcher path.
*/
        Database.executeBatch(
            new ContractExpiryReminderBatch(),
            DEFAULT_BATCH_SIZE
        );
    }
    
    /**
* Identifies the exact expiration date using the active
* Notification Event Mapping metadata record.
*/
    public Database.QueryLocator start(
        Database.BatchableContext context
    ) {
        Notification_Event_Mapping__mdt reminderMapping =
            getValidatedReminderMapping();
        
        if (
            reminderMapping == null ||
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return getEmptyQueryLocator();
        }
        
        Integer offsetDays =
            reminderMapping.Date_Offset_Days__c.intValue();
        
        Date targetExpirationDate =
            Date.today().addDays(offsetDays);
        
        return Database.getQueryLocator([
            SELECT
            Id,
            Name,
            Status,
            NameInsuredId,
            NameInsured.Name,
            Expiration_Date_Calc__c
            FROM InsurancePolicy
            WHERE Expiration_Date_Calc__c =
            :targetExpirationDate
        ]);
    }
    
    /**
* Processes one batch scope and creates one outbox record for
* every qualifying Insurance Policy.
*/
    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        Notification_Event_Mapping__mdt reminderMapping =
            getValidatedReminderMapping();
        
        if (
            reminderMapping == null ||
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            skippedCount += scope.size();
            return;
        }
        
        Datetime eventTime = System.now();
        
        List<NotificationOutboxService.OutboxRequest>
            outboxRequests =
            new List<
            NotificationOutboxService.OutboxRequest
            >();
        
        for (SObject scopeRecord : scope) {
            InsurancePolicy contractRecord =
                (InsurancePolicy) scopeRecord;
            
            /*
* Cancelled and Expired contracts must not receive the
* 90-day expiration reminder.
*/
            if (isExcludedContractStatus(
                contractRecord.Status
            )) {
                skippedCount++;
                continue;
            }
            
            if (
                contractRecord.Expiration_Date_Calc__c ==
                null
            ) {
                skippedCount++;
                continue;
            }
            
            qualifyingContractCount++;
            
            NotificationOutboxService.OutboxRequest request =
                buildReminderOutboxRequest(
                    contractRecord,
                    reminderMapping,
                    eventTime
                );
            
            if (contractRecord.NameInsuredId == null) {
                missingCustomerCount++;
            }
            
            outboxRequests.add(request);
        }
        
        if (outboxRequests.isEmpty()) {
            return;
        }
        
        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                outboxRequests
            );
        
        insertedOutboxCount += result.insertedCount;
        duplicateCount += result.duplicateCount;
        skippedCount += result.skippedCount;
        serviceFailureCount += result.failedCount;
        
        logCreationErrors(
            context.getJobId(),
            result
        );
        
        NotificationWebhookDispatcher.enqueue(
            result.insertedRecordIds
        );
    }
    
    
    public void finish(
        Database.BatchableContext context
    ) {
        System.debug(
            LoggingLevel.INFO,
            'Contract Expiry Reminder Batch completed. ' +
            'Job Id: ' + context.getJobId() +
            ', Qualifying Contracts: ' +
            qualifyingContractCount +
            ', Outbox Records Inserted: ' +
            insertedOutboxCount +
            ', Duplicate Events Skipped: ' +
            duplicateCount +
            ', Records Skipped: ' +
            skippedCount +
            ', Missing Customer Mappings: ' +
            missingCustomerCount +
            ', Service Failures: ' +
            serviceFailureCount
        );
        
        /*
* The webhook dispatcher will be implemented separately.
* Therefore, successfully created records remain Pending.
*/
    }
    
    /**
* Creates one outbox request per qualifying Insurance Policy.
*
* Multiple contracts belonging to the same customer intentionally
* create multiple outbox records.
*/
    private static NotificationOutboxService.OutboxRequest
        buildReminderOutboxRequest(
            InsurancePolicy contractRecord,
            Notification_Event_Mapping__mdt mapping,
            Datetime eventTime
        ) {
            NotificationOutboxService.OutboxRequest request =
                new NotificationOutboxService.OutboxRequest();
            
            request.eventCode =
                mapping.Event_Code__c;
            
            /*
* One reminder is allowed for each unique combination of:
*
* Insurance Policy Id + Expiration Date
*/
            request.eventKey =
                NotificationEventKeyGenerator.forContractExpiryReminder(
                    contractRecord.Id,
                    contractRecord
                    .Expiration_Date_Calc__c
                );
            
            request.sourceObject =
                SOURCE_OBJECT;
            
            request.sourceRecordId =
                String.valueOf(contractRecord.Id);
            
            request.customerId =
                contractRecord.NameInsuredId;
            
            request.insurancePolicyId =
                contractRecord.Id;
            
            request.eventTime =
                eventTime;
            
            request.customerName =
                contractRecord.NameInsured == null
                ? null
                : contractRecord.NameInsured.Name;
            
            request.policyNumber =
                contractRecord.Name;
            
            request.changedField =
                MONITORED_FIELD;
            
            request.oldValue = null;
            
            request.newValue =
                String.valueOf(
                    contractRecord
                    .Expiration_Date_Calc__c
                );
            
            request.effectiveDate =
                contractRecord
                .Expiration_Date_Calc__c;
            
            if (contractRecord.NameInsuredId == null) {
                request.customerMappingError =
                    'InsurancePolicy.NameInsuredId is blank. ' +
                    'The insured customer could not be resolved for the ' +
                    '90-day contract expiration reminder. ' +
                    'Insurance Policy Id: ' +
                    contractRecord.Id +
                    ', Policy Number: ' +
                    contractRecord.Name +
                    ', Expiration Date: ' +
                    contractRecord.Expiration_Date_Calc__c +
                    '.';
            }
            
            /*
* Request_Payload__c intentionally remains blank here.
*
* NotificationWebhookDispatcher collects the reminder outbox
* records and creates the required customer_sf_id_list payload
* in bounded bulk groups at dispatch time.
*/
            return request;
        }
    
    /**
* Reads and validates the reminder Custom Metadata record.
*/
    private static Notification_Event_Mapping__mdt
        getValidatedReminderMapping()
    {
        Notification_Event_Mapping__mdt mapping =
            NotificationIntegrationConfigService.getActiveEventMapping(EVENT_CODE);
        
        if (mapping == null) {
            return null;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Event_Code__c,
                EVENT_CODE
            )
        ) {
            return null;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Source_Object__c,
                SOURCE_OBJECT
            )
        ) {
            return null;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Monitored_Field__c,
                MONITORED_FIELD
            )
        ) {
            return null;
        }
        
        if (
            !equalsIgnoreCase(
                mapping.Detection_Type__c,
                DETECTION_TYPE
            )
        ) {
            return null;
        }
        
        if (
            mapping.Date_Offset_Days__c == null ||
            mapping.Date_Offset_Days__c <= 0
        ) {
            return null;
        }
        
        return mapping;
    }
    
    private static Boolean isExcludedContractStatus(
        String contractStatus
    ) {
        String normalizedStatus =
            normalizeValue(contractStatus);
        
        return normalizedStatus == 'CANCELLED' ||
            normalizedStatus == 'EXPIRED';
    }
    
    private static void logCreationErrors(
        Id batchJobId,
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
                'Contract Expiry Reminder Outbox Error. ' +
                'Batch Job Id: ' +
                batchJobId +
                '. Error: ' +
                errorMessage
            );
        }
        
        QDX_Log.publish();
    }
    
    private static Database.QueryLocator
        getEmptyQueryLocator()
    {
        return Database.getQueryLocator(
            'SELECT Id ' +
            'FROM InsurancePolicy ' +
            'WHERE Id = null'
        );
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