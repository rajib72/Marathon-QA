/**
* Sends pending Customer Notification Outbox events to the
* Marathon Connect application webhook.
*
* Standard events are sent one request per outbox record.
*
* CONTRACT_EXPIRY_REMINDER_90 events are grouped into one request
* per Queueable execution while preserving duplicate customer IDs.
*
* No retry processing is included in the current implementation.
*/
public without sharing class NotificationWebhookDispatcher
implements Queueable, Database.AllowsCallouts {
    
    private static final String STATUS_PENDING =
        'Pending';
    
    private static final String STATUS_DELIVERED =
        'Delivered';
    
    private static final String STATUS_FAILED =
        'Failed';
    
    /*
* Contract and Finance notifications are dispatched through
* the scheduled noon process rather than in real time.
*
* Claim and Policy Reminder events are intentionally excluded.
*/
    private static final Set<String> SCHEDULED_NOTIFICATION_CATEGORIES =
        new Set<String>{
            'Policy',
                'Finance'
                };
                    
                    private static final String REMINDER_EVENT_CODE =
                    'CONTRACT_EXPIRY_REMINDER_90';
    
    private static final Integer CALLOUT_TIMEOUT_MS =
        10000;
    
    private static final Integer MAX_LONG_TEXT_LENGTH =
        32768;
    
    private List<Id> outboxRecordIds;
    
    private Boolean scheduledPendingMode = false;
    private Datetime scheduledCutoff;
    private Datetime scheduledCursorCreatedDate;
    private Id scheduledCursorRecordId;
    /**
* Creates a dispatcher for explicitly supplied outbox records.
*
* Explicit IDs reduce the possibility of two Queueable jobs
* selecting the same general Pending records.
*/
    public NotificationWebhookDispatcher(
        List<Id> outboxRecordIds
    ) {
        this.outboxRecordIds =
            normalizeRecordIds(outboxRecordIds);
        
        this.scheduledPendingMode = false;
    }
    
    /**
* Creates a scheduled dispatcher that processes Pending
* Policy and Finance notification events up to one fixed cutoff.
*
* The same cutoff is carried through all chained Queueables so
* records created after the noon run begins are never picked up
* during that day's processing.
*/
    private NotificationWebhookDispatcher(
        Datetime scheduledCutoff,
        Datetime scheduledCursorCreatedDate,
        Id scheduledCursorRecordId
    ) {
        if (scheduledCutoff == null) {
            throw new IllegalArgumentException(
                'scheduledCutoff is required.'
            );
        }
        
        this.outboxRecordIds = new List<Id>();
        this.scheduledPendingMode = true;
        this.scheduledCutoff = scheduledCutoff;
        this.scheduledCursorCreatedDate =
            scheduledCursorCreatedDate;
        this.scheduledCursorRecordId =
            scheduledCursorRecordId;
    }
    
    /**
* Enqueues the dispatcher only when at least one record ID exists.
*/
    public static Id enqueue(
        List<Id> outboxRecordIds
    ) {
        List<Id> normalizedIds =
            normalizeRecordIds(outboxRecordIds);
        
        if (normalizedIds.isEmpty()) {
            return null;
        }
        
        return System.enqueueJob(
            new NotificationWebhookDispatcher(
                normalizedIds
            )
        );
    }
    
    /**
* Starts the scheduled noon dispatch for Pending Policy and
* Finance notifications.
*
* scheduledCutoff represents the fixed boundary for the entire
* Queueable chain.
*/
  public static Id enqueueScheduledPolicyFinanceEvents(
        Datetime scheduledCutoff
    ) {
        if (scheduledCutoff == null) {
            throw new IllegalArgumentException(
                'scheduledCutoff is required.'
            );
        }
        
        return System.enqueueJob(
            new NotificationWebhookDispatcher(
                scheduledCutoff,
                null,
                null
            )
        );
    }
    
    public void execute(
        QueueableContext context
    ) {
        /*
* Scheduled mode is used only for Contract and Finance
* notifications waiting for the noon dispatch.
*/
        if (scheduledPendingMode) {
            if (
                !NotificationIntegrationConfigService.isIntegrationEnabled()
            ) {
                return;
            }
            
            executeScheduledPolicyFinanceDispatch(
                context
            );
            
            return;
        }
        
        /*
* Existing explicit-ID behavior is retained for
* real-time Claim events and reminder dispatch.
*/
        if (
            outboxRecordIds == null ||
            outboxRecordIds.isEmpty()
        ) {
            return;
        }
        
        if (
            !NotificationIntegrationConfigService.isIntegrationEnabled()
        ) {
            return;
        }
        
        executeExplicitIdDispatch(
            context
        );
    }
    
    /**
* Existing explicit-ID dispatch path.
*
* Used by real-time Claim notifications and by notification
* processes that already know the exact outbox record IDs.
*/
    private void executeExplicitIdDispatch(
        QueueableContext context
    ) {
        Integer maximumEvents =
            NotificationIntegrationConfigService.getMaximumEventsPerDispatch();
        
        RecordIdPartition partition =
            partitionRecordIds(
                outboxRecordIds,
                maximumEvents
            );
        
        List<Customer_Notification_Outbox__c>
            currentOutboxRecords =
            queryPendingOutboxRecords(
                partition.currentRecordIds
            );
        
        if (!currentOutboxRecords.isEmpty()) {
            dispatchCurrentRecords(
                currentOutboxRecords,
                context.getJobId()
            );
        }
        
        /*
* Preserve the existing bounded Queueable chaining
* behavior for explicit IDs.
*/
        if (!partition.remainingRecordIds.isEmpty()) {
            System.enqueueJob(
                new NotificationWebhookDispatcher(
                    partition.remainingRecordIds
                )
            );
        }
    }
    
    /**
* Processes Pending Policy and Finance events that existed at or
* before the fixed scheduled cutoff.
*
* Records created after the cutoff are intentionally left Pending
* for the next scheduled noon execution.
*/
    private void executeScheduledPolicyFinanceDispatch(
        QueueableContext context
    ) {
        Integer maximumEvents =
            NotificationIntegrationConfigService.getMaximumEventsPerDispatch();
        
        List<Customer_Notification_Outbox__c>
            currentOutboxRecords =
            queryScheduledPendingOutboxRecords(
                scheduledCutoff,
                scheduledCursorCreatedDate,
                scheduledCursorRecordId,
                maximumEvents
            );
        
        if (currentOutboxRecords.isEmpty()) {
            return;
        }
        
        /*
* Capture the cursor before dispatching. CreatedDate and Id are
* immutable and provide a stable position for the next job.
*/
        Customer_Notification_Outbox__c lastRecord =
            currentOutboxRecords[
                currentOutboxRecords.size() - 1
            ];
        
        Datetime nextCursorCreatedDate =
            lastRecord.CreatedDate;
        
        Id nextCursorRecordId =
            lastRecord.Id;
        
        dispatchCurrentRecords(
            currentOutboxRecords,
            context.getJobId()
        );
        
        /*
* When the full chunk was returned there may be additional
* eligible records. Chain exactly one child Queueable.
*
* The original cutoff is preserved for the complete chain.
*/
        if (
            currentOutboxRecords.size() ==
            maximumEvents
        ) {
            System.enqueueJob(
                new NotificationWebhookDispatcher(
                    scheduledCutoff,
                    nextCursorCreatedDate,
                    nextCursorRecordId
                )
            );
        }
    }
    
    /**
* Sends all records selected for the current Queueable execution.
*/
    private static void dispatchCurrentRecords(
        List<Customer_Notification_Outbox__c>
        outboxRecords,
        Id queueableJobId
    ) {
        Datetime attemptTime = System.now();
        
        String endpoint;
        
        try {
            endpoint =
                NotificationIntegrationConfigService.getCalloutEndpoint();
        } catch (Exception ex) {
            markAllAsConfigurationFailure(
                outboxRecords,
                attemptTime,
                ex
            );
            
            saveOutboxUpdates(
                outboxRecords,
                queueableJobId
            );
            
            return;
        }
        
        List<Customer_Notification_Outbox__c>
            reminderRecords =
            new List<
            Customer_Notification_Outbox__c
            >();
        
        for (
            Customer_Notification_Outbox__c outboxRecord :
            outboxRecords
        ) {
            if (
                equalsIgnoreCase(
                    outboxRecord.Event_Code__c,
                    REMINDER_EVENT_CODE
                )
            ) {
                reminderRecords.add(outboxRecord);
                continue;
            }
            
            dispatchStandardEvent(
                outboxRecord,
                endpoint,
                attemptTime
            );
        }
        
        if (!reminderRecords.isEmpty()) {
            dispatchReminderEvents(
                reminderRecords,
                endpoint,
                attemptTime
            );
        }
        
        saveOutboxUpdates(
            outboxRecords,
            queueableJobId
        );
    }
    
    /**
* Sends one standard Claim, Contract, or Finance event.
*/
    private static void dispatchStandardEvent(
        Customer_Notification_Outbox__c outboxRecord,
        String endpoint,
        Datetime attemptTime
    ) {
        initializeAttempt(
            outboxRecord,
            attemptTime
        );
        
        if (
            String.isBlank(
                outboxRecord.Request_Payload__c
            )
        ) {
            applyFailure(
                outboxRecord,
                new DispatchResult(
                    false,
                    null,
                    null,
                    'Configuration',
                    'Request_Payload__c is blank for event ' +
                    outboxRecord.Event_Code__c +
                    '. Outbox record Id: ' +
                    outboxRecord.Id +
                    '.'
                ),
                attemptTime
            );
            
            return;
        }
        
        DispatchResult result =
            sendWebhookRequest(
                endpoint,
                outboxRecord.Request_Payload__c
            );
        
        applyDispatchResult(
            outboxRecord,
            result,
            attemptTime
        );
    }
    
    /**
* Sends one grouped reminder request for the current Queueable
* execution.
*
* One customer ID is added for every qualifying outbox record.
* Duplicate customer IDs are intentionally preserved.
*/
    private static void dispatchReminderEvents(
        List<Customer_Notification_Outbox__c>
        reminderRecords,
        String endpoint,
        Datetime attemptTime
    ) {
        List<Id> customerIds = new List<Id>();
        
        List<Customer_Notification_Outbox__c>
            validReminderRecords =
            new List<
            Customer_Notification_Outbox__c
            >();
        
        Datetime reminderEventTime;
        
        for (
            Customer_Notification_Outbox__c reminderRecord :
            reminderRecords
        ) {
            initializeAttempt(
                reminderRecord,
                attemptTime
            );
            
            if (reminderRecord.Customer__c == null) {
                applyFailure(
                    reminderRecord,
                    new DispatchResult(
                        false,
                        null,
                        null,
                        'Customer Mapping',
                        'Customer__c is blank for reminder ' +
                        'outbox record ' +
                        reminderRecord.Id +
                        '.'
                    ),
                    attemptTime
                );
                
                continue;
            }
            
            customerIds.add(
                reminderRecord.Customer__c
            );
            
            validReminderRecords.add(
                reminderRecord
            );
            
            if (
                reminderEventTime == null ||
                (
                    reminderRecord.Event_Time__c != null &&
                    reminderRecord.Event_Time__c <
                    reminderEventTime
                )
            ) {
                reminderEventTime =
                    reminderRecord.Event_Time__c;
            }
        }
        
        if (validReminderRecords.isEmpty()) {
            return;
        }
        
        if (reminderEventTime == null) {
            reminderEventTime = attemptTime;
        }
        
        String requestBody;
        
        try {
            NotificationWebhookPayload payload =
                NotificationWebhookPayload.forContractExpiryReminder(
                    customerIds,
                    reminderEventTime
                );
            
            requestBody = payload.toJson();
        } catch (Exception ex) {
            DispatchResult payloadFailure =
                new DispatchResult(
                    false,
                    null,
                    null,
                    'Validation',
                    'Unable to build the grouped contract ' +
                    'expiry reminder payload. Message: ' +
                    ex.getMessage()
                );
            
            for (
                Customer_Notification_Outbox__c
                reminderRecord :
                validReminderRecords
            ) {
                applyFailure(
                    reminderRecord,
                    payloadFailure,
                    attemptTime
                );
            }
            
            return;
        }
        
        DispatchResult result =
            sendWebhookRequest(
                endpoint,
                requestBody
            );
        
        /*
* All outbox records represented in the same reminder
* request receive the same delivery result.
*/
        for (
            Customer_Notification_Outbox__c reminderRecord :
            validReminderRecords
        ) {
            /*
* Store the actual grouped request snapshot against
* every participating reminder outbox record.
*/
            reminderRecord.Request_Payload__c =
                truncateValue(
                    requestBody,
                    MAX_LONG_TEXT_LENGTH
                );
            
            applyDispatchResult(
                reminderRecord,
                result,
                attemptTime
            );
        }
    }
    
    /**
* Executes the HTTP POST callout.
*
* X-Webhook-Key is injected through the External Credential.
*/
    private static DispatchResult sendWebhookRequest(
        String endpoint,
        String requestBody
    ) {
        try {
            HttpRequest request = new HttpRequest();
            
            request.setEndpoint(endpoint);
            request.setMethod('POST');
            
            request.setHeader(
                'Content-Type',
                'application/json'
            );
            
            request.setHeader(
                'Accept',
                'application/json, text/plain'
            );
            
            request.setTimeout(
                CALLOUT_TIMEOUT_MS
            );
            
            request.setBody(requestBody);
            
            HttpResponse response =
                new Http().send(request);
            
            Integer statusCode =
               response.getStatusCode();
            
            String responseBody =
               response.getBody();
            
            if (
                NotificationIntegrationConfigService.isSuccessfulStatusCode(
                    statusCode
                )
            ) {
                return new DispatchResult(
                    true,
                    statusCode,
                    responseBody,
                    null,
                    null
                );
            }
            
            return new DispatchResult(
                false,
                statusCode,
                responseBody,
                classifyHttpFailure(statusCode),
                buildHttpErrorMessage(
                    statusCode,
                    responseBody
                )
            );
        } catch (CalloutException ex) {
            return new DispatchResult(
                false,
                null,
                null,
                isTimeoutException(ex)
                ? 'Timeout'
                : 'Unexpected Error',
                'Webhook callout failed. Message: ' +
                ex.getMessage()
            );
        } catch (Exception ex) {
            return new DispatchResult(
                false,
                null,
                null,
                'Unexpected Error',
                'Unexpected webhook dispatch failure. ' +
                'Message: ' +
                ex.getMessage() +
                ', Line: ' +
                ex.getLineNumber()
            );
        }
    }
    
    private static void initializeAttempt(
        Customer_Notification_Outbox__c outboxRecord,
        Datetime attemptTime
    ) {
        Decimal previousAttemptCount =
            outboxRecord.Attempt_Count__c == null
            ? 0
            : outboxRecord.Attempt_Count__c;
        
        outboxRecord.Attempt_Count__c =
            previousAttemptCount + 1;
        
        outboxRecord.Processing_Started_At__c =
            attemptTime;
        
        outboxRecord.Last_Attempt_At__c =
            attemptTime;
    }
    
    private static void applyDispatchResult(
        Customer_Notification_Outbox__c outboxRecord,
        DispatchResult result,
        Datetime attemptTime
    ) {
        if (result.success) {
            applySuccess(
                outboxRecord,
                result,
                attemptTime
            );
        } else {
            applyFailure(
                outboxRecord,
                result,
                attemptTime
            );
        }
    }
    
    private static void applySuccess(
        Customer_Notification_Outbox__c outboxRecord,
        DispatchResult result,
        Datetime attemptTime
    ) {
        outboxRecord.Status__c =
            STATUS_DELIVERED;
        
        outboxRecord.Delivered_At__c =
            attemptTime;
        
        outboxRecord.HTTP_Status_Code__c =
            result.httpStatusCode;
        
        outboxRecord.Response_Body__c =
            truncateValue(
                result.responseBody,
                MAX_LONG_TEXT_LENGTH
            );
        
        outboxRecord.Failure_Type__c = null;
        outboxRecord.Error_Message__c = null;
        outboxRecord.Next_Retry_At__c = null;
    }
    
    private static void applyFailure(
        Customer_Notification_Outbox__c outboxRecord,
        DispatchResult result,
        Datetime attemptTime
    ) {
        outboxRecord.Status__c =
            STATUS_FAILED;
        
        outboxRecord.Delivered_At__c =
            null;
        
        outboxRecord.HTTP_Status_Code__c =
            result.httpStatusCode;
        
        outboxRecord.Response_Body__c =
            truncateValue(
                result.responseBody,
                MAX_LONG_TEXT_LENGTH
            );
        
        outboxRecord.Failure_Type__c =
            result.failureType;
        
        outboxRecord.Error_Message__c =
            truncateValue(
                result.errorMessage,
                MAX_LONG_TEXT_LENGTH
            );
        
        /*
* Retry is intentionally not implemented in this phase.
*/
        outboxRecord.Next_Retry_At__c = null;
    }
    
    private static void markAllAsConfigurationFailure(
        List<Customer_Notification_Outbox__c>
        outboxRecords,
        Datetime attemptTime,
        Exception ex
    ) {
        DispatchResult result =
            new DispatchResult(
                false,
                null,
                null,
                'Configuration',
                'Webhook configuration could not be resolved. ' +
                'Message: ' +
                ex.getMessage()
            );
        
        for (
            Customer_Notification_Outbox__c outboxRecord :
            outboxRecords
        ) {
            initializeAttempt(
                outboxRecord,
                attemptTime
            );
            
            applyFailure(
                outboxRecord,
                result,
                attemptTime
            );
        }
    }
    
    /**
* Uses partial-success DML so that one unexpected outbox validation
* problem does not prevent the other response results from saving.
*/
    private static void saveOutboxUpdates(
        List<Customer_Notification_Outbox__c>
        outboxRecords,
        Id queueableJobId
    ) {
        if (
            outboxRecords == null ||
            outboxRecords.isEmpty()
        ) {
            return;
        }
        
        Database.SaveResult[] saveResults =
            Database.update(
                outboxRecords,
                false
            );
        
        Boolean hasLoggingErrors = false;
        
        for (
            Integer index = 0;
            index < saveResults.size();
            index++
        ) {
            if (saveResults[index].isSuccess()) {
                continue;
            }
            
            for (
                Database.Error saveError :
                saveResults[index].getErrors()
            ) {
                hasLoggingErrors = true;
                
                QDX_Log.error(
                    'Unable to update notification outbox ' +
                    'after webhook dispatch. Queueable Job Id: ' +
                    queueableJobId +
                    ', Outbox Record Id: ' +
                    outboxRecords[index].Id +
                    ', Error: ' +
                    saveError.getMessage()
                );
            }
        }
        
        if (hasLoggingErrors) {
            QDX_Log.publish();
        }
    }
    
    private static List<
        Customer_Notification_Outbox__c
        > queryPendingOutboxRecords(
            List<Id> recordIds
        ) {
            if (
                recordIds == null ||
                recordIds.isEmpty()
            ) {
                return new List<
                    Customer_Notification_Outbox__c
                    >();
            }
            
            return [
                SELECT
                Id,
                Event_Id__c,
                Event_Code__c,
                Event_Time__c,
                Customer__c,
                Insurance_Policy__c,
                Claim__c,
                Request_Payload__c,
                Status__c,
                Attempt_Count__c,
                Processing_Started_At__c,
                Last_Attempt_At__c,
                Next_Retry_At__c,
                Delivered_At__c,
                HTTP_Status_Code__c,
                Response_Body__c,
                Error_Message__c,
                Failure_Type__c,
                CreatedDate
                FROM Customer_Notification_Outbox__c
                WHERE
                Id IN :recordIds
                AND Status__c = :STATUS_PENDING
                ORDER BY CreatedDate ASC, Id ASC
            ];
        }
    
    /**
* Retrieves the next bounded set of Pending Policy and Finance
* notification events for the scheduled noon process.
*
* Claims are excluded because they are dispatched in real time.
* Policy Reminder records are excluded because the reminder batch
* handles those separately.
*/
    private static List<Customer_Notification_Outbox__c>
        queryScheduledPendingOutboxRecords(
            Datetime cutoff,
            Datetime cursorCreatedDate,
            Id cursorRecordId,
            Integer maximumEvents
        ) {
            if (cutoff == null) {
                return new List<
                    Customer_Notification_Outbox__c
                    >();
            }
            
            Integer safeMaximum =
                maximumEvents == null ||
                maximumEvents <= 0
                ? 50
                : Math.min(
                    maximumEvents,
                    100
                );
            
            /*
* First Queueable execution.
*/
            if (
                cursorCreatedDate == null ||
                cursorRecordId == null
            ) {
                return [
                    SELECT
                    Id,
                    Event_Id__c,
                    Event_Code__c,
                    Event_Time__c,
                    Notification_Category__c,
                    Customer__c,
                    Insurance_Policy__c,
                    Claim__c,
                    Request_Payload__c,
                    Status__c,
                    Attempt_Count__c,
                    Processing_Started_At__c,
                    Last_Attempt_At__c,
                    Next_Retry_At__c,
                    Delivered_At__c,
                    HTTP_Status_Code__c,
                    Response_Body__c,
                    Error_Message__c,
                    Failure_Type__c,
                    CreatedDate
                    FROM Customer_Notification_Outbox__c
                    WHERE
                    Status__c = :STATUS_PENDING
                    AND Notification_Category__c
                    IN :SCHEDULED_NOTIFICATION_CATEGORIES
                    AND CreatedDate <= :cutoff
                    ORDER BY CreatedDate ASC, Id ASC
                    LIMIT :safeMaximum
                ];
            }
            
            /*
* Chained Queueable execution.
*
* CreatedDate + Id provides deterministic pagination
* without OFFSET.
*/
            return [
                SELECT
                Id,
                Event_Id__c,
                Event_Code__c,
                Event_Time__c,
                Notification_Category__c,
                Customer__c,
                Insurance_Policy__c,
                Claim__c,
                Request_Payload__c,
                Status__c,
                Attempt_Count__c,
                Processing_Started_At__c,
                Last_Attempt_At__c,
                Next_Retry_At__c,
                Delivered_At__c,
                HTTP_Status_Code__c,
                Response_Body__c,
                Error_Message__c,
                Failure_Type__c,
                CreatedDate
                FROM Customer_Notification_Outbox__c
                WHERE
                Status__c = :STATUS_PENDING
                AND Notification_Category__c
                IN :SCHEDULED_NOTIFICATION_CATEGORIES
                AND CreatedDate <= :cutoff
                AND (
                    CreatedDate > :cursorCreatedDate
                    OR (
                        CreatedDate = :cursorCreatedDate
                        AND Id > :cursorRecordId
                    )
                )
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT :safeMaximum
            ];
        }
    
    private static RecordIdPartition partitionRecordIds(
        List<Id> allRecordIds,
        Integer maximumEvents
    ) {
        RecordIdPartition partition =
            new RecordIdPartition();
        
        Integer safeMaximum =
            maximumEvents == null ||
            maximumEvents <= 0
            ? 50
            : Math.min(maximumEvents, 100);
        
        for (
            Integer index = 0;
            index < allRecordIds.size();
            index++
        ) {
            if (index < safeMaximum) {
                partition.currentRecordIds.add(
                    allRecordIds[index]
                );
            } else {
                partition.remainingRecordIds.add(
                    allRecordIds[index]
                );
            }
        }
        
        return partition;
    }
    
    private static List<Id> normalizeRecordIds(
        List<Id> suppliedRecordIds
    ) {
        List<Id> result = new List<Id>();
        Set<Id> seenIds = new Set<Id>();
        
        if (suppliedRecordIds == null) {
            return result;
        }
        
        for (Id recordId : suppliedRecordIds) {
            if (
                recordId == null ||
                seenIds.contains(recordId)
            ) {
                continue;
            }
            
            seenIds.add(recordId);
            result.add(recordId);
        }
        
        return result;
    }
    
    private static String classifyHttpFailure(
        Integer statusCode
    ) {
        if (
            statusCode == 401 ||
            statusCode == 403
        ) {
            return 'Authentication';
        }
        
        if (statusCode == 429) {
            return 'Rate Limit';
        }
        
        if (
            statusCode != null &&
            statusCode >= 500
        ) {
            return 'Server Error';
        }
        
        if (
            statusCode == 404 ||
            statusCode == 405
        ) {
            return 'Configuration';
        }
        
        if (
            statusCode != null &&
            statusCode >= 400 &&
            statusCode < 500
        ) {
            return 'Validation';
        }
        
        return 'Unexpected Error';
    }
    
    private static String buildHttpErrorMessage(
        Integer statusCode,
        String responseBody
    ) {
        String message =
            'Webhook returned HTTP status ' +
            String.valueOf(statusCode) +
            '.';
        
        if (String.isNotBlank(responseBody)) {
            message +=
                ' Response: ' +
                responseBody;
        }
        
        return truncateValue(
            message,
            MAX_LONG_TEXT_LENGTH
        );
    }
    
    private static Boolean isTimeoutException(
        CalloutException ex
    ) {
        if (
            ex == null ||
            String.isBlank(ex.getMessage())
        ) {
            return false;
        }
        
        String normalizedMessage =
            ex.getMessage().toLowerCase();
        
        return normalizedMessage.contains(
            'timed out'
        ) ||
            normalizedMessage.contains(
                'timeout'
            );
    }
    
    private static String truncateValue(
        String value,
        Integer maximumLength
    ) {
        if (
            value == null ||
            maximumLength == null ||
            maximumLength <= 0 ||
            value.length() <= maximumLength
        ) {
            return value;
        }
        
        return value.substring(
            0,
            maximumLength
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
    
    private class RecordIdPartition {
        
        private List<Id> currentRecordIds =
            new List<Id>();
        
        private List<Id> remainingRecordIds =
            new List<Id>();
    }
    
    private class DispatchResult {
        
        private Boolean success;
        private Integer httpStatusCode;
        private String responseBody;
        private String failureType;
        private String errorMessage;
        
        private DispatchResult(
            Boolean success,
            Integer httpStatusCode,
            String responseBody,
            String failureType,
            String errorMessage
        ) {
            this.success = success;
            this.httpStatusCode = httpStatusCode;
            this.responseBody = responseBody;
            this.failureType = failureType;
            this.errorMessage = errorMessage;
        }
    }
}