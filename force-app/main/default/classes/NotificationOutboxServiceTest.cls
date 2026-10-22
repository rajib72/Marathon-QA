@IsTest
private class NotificationOutboxServiceTest {

    @TestSetup
    static void createTestData() {
        insert new Account(
            Name = 'Notification Test Customer'
        );
    }

    @IsTest
    static void shouldCreatePendingOutboxRecord() {
        configureMetadata();

        Account customer = [
            SELECT Id, Name
            FROM Account
            LIMIT 1
        ];

        Datetime eventTime = System.now();

        NotificationOutboxService.OutboxRequest request =
            new NotificationOutboxService.OutboxRequest();

        request.eventCode = 'CLAIM_APPROVED';

        request.eventKey =
            NotificationEventKeyGenerator.forRecordEvent(
                    request.eventCode,
                    customer.Id,
                    'Status',
                    'Initiated',
                    'Approved',
                    eventTime
                );

        request.sourceObject = 'Claim';
        request.sourceRecordId =
            String.valueOf(customer.Id);

        request.customerId = customer.Id;
        request.eventTime = eventTime;
        request.customerName = customer.Name;
        request.claimNumber = 'TEST-CLAIM';
        request.changedField = 'Status';
        request.oldValue = 'Initiated';
        request.newValue = 'Approved';

        Test.startTest();

        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                    new List<
                        NotificationOutboxService.OutboxRequest
                    >{ request }
                );

        Test.stopTest();

        System.assertEquals(
            1,
            result.insertedCount
        );

        Customer_Notification_Outbox__c outboxRecord = [
            SELECT
                Event_Code__c,
                Event_Key__c,
                Customer__c,
                Status__c,
                Old_Value__c,
                New_Value__c
            FROM Customer_Notification_Outbox__c
            WHERE Event_Key__c = :request.eventKey
            LIMIT 1
        ];

        System.assertEquals(
            'CLAIM_APPROVED',
            outboxRecord.Event_Code__c
        );

        System.assertEquals(
            customer.Id,
            outboxRecord.Customer__c
        );

        System.assertEquals(
            'Pending',
            outboxRecord.Status__c
        );

        System.assertEquals(
            'Initiated',
            outboxRecord.Old_Value__c
        );

        System.assertEquals(
            'Approved',
            outboxRecord.New_Value__c
        );
    }

    @IsTest
    static void shouldPreventDuplicateOutboxRecord() {
        configureMetadata();

        Account customer = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Datetime eventTime = System.now();

        NotificationOutboxService.OutboxRequest request =
            new NotificationOutboxService.OutboxRequest();

        request.eventCode = 'CLAIM_APPROVED';

        request.eventKey =
            NotificationEventKeyGenerator.forRecordEvent(
                    request.eventCode,
                    customer.Id,
                    'Status',
                    'Initiated',
                    'Approved',
                    eventTime
                );

        request.sourceObject = 'Claim';
        request.sourceRecordId =
            String.valueOf(customer.Id);

        request.customerId = customer.Id;
        request.eventTime = eventTime;

        NotificationOutboxService.createOutboxRecords(
                new List<
                    NotificationOutboxService.OutboxRequest
                >{ request }
            );

        Test.startTest();

        NotificationOutboxService.CreationResult secondResult =
            NotificationOutboxService.createOutboxRecords(
                    new List<
                        NotificationOutboxService.OutboxRequest
                    >{ request }
                );

        Test.stopTest();

        System.assertEquals(
            0,
            secondResult.insertedCount
        );

        System.assertEquals(
            1,
            secondResult.duplicateCount
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Customer_Notification_Outbox__c
                WHERE Event_Key__c = :request.eventKey
            ]
        );
    }

    @IsTest
    static void shouldCreateFailedRecordForMissingCustomer() {
        configureMetadata();

        Account sourceRecord = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        NotificationOutboxService.OutboxRequest request =
            new NotificationOutboxService.OutboxRequest();

        request.eventCode = 'CONTRACT_CANCELLED';

        request.eventKey =
            NotificationEventKeyGenerator.forRecordEvent(
                    request.eventCode,
                    sourceRecord.Id,
                    'Status',
                    'Active',
                    'Cancelled',
                    System.now()
                );

        request.sourceObject =
            'InsurancePolicy';

        request.sourceRecordId =
            String.valueOf(sourceRecord.Id);

        request.changedField = 'Status';
        request.oldValue = 'Active';
        request.newValue = 'Cancelled';

        Test.startTest();

        NotificationOutboxService.CreationResult result =
            NotificationOutboxService.createOutboxRecords(
                    new List<
                        NotificationOutboxService.OutboxRequest
                    >{ request }
                );

        Test.stopTest();

        System.assertEquals(
            1,
            result.insertedCount
        );

        Customer_Notification_Outbox__c outboxRecord = [
            SELECT
                Status__c,
                Failure_Type__c,
                Error_Message__c
            FROM Customer_Notification_Outbox__c
            WHERE Event_Key__c = :request.eventKey
            LIMIT 1
        ];

        System.assertEquals(
            'Failed',
            outboxRecord.Status__c
        );

        System.assertEquals(
            'Customer Mapping',
            outboxRecord.Failure_Type__c
        );

        System.assert(
            String.isNotBlank(
                outboxRecord.Error_Message__c
            )
        );
    }

    private static void configureMetadata() {
        NotificationIntegrationConfigService.resetCache();

        Notification_Integration_Config__mdt config =
            new Notification_Integration_Config__mdt();

        config.Is_Enabled__c = true;
        config.Named_Credential__c =
            'Marathon_Connect_Webhook';

        config.Webhook_Path__c =
            '/api/webhooks/notification';

        config.Success_Status_Codes__c =
            '200,202';

        config.Payload_Version__c = '1.0';

        NotificationIntegrationConfigService.testConfigOverride = config;

        Map<String, Notification_Event_Mapping__mdt>
            mappings =
            new Map<
                String,
                Notification_Event_Mapping__mdt
            >();

        mappings.put(
            'CLAIM_APPROVED',
            createMapping(
                'CLAIM_APPROVED',
                'Claim'
            )
        );

        mappings.put(
            'CONTRACT_CANCELLED',
            createMapping(
                'CONTRACT_CANCELLED',
                'Policy'
            )
        );

        NotificationIntegrationConfigService.testMappingsOverride = mappings;
    }

    private static Notification_Event_Mapping__mdt
        createMapping(
            String eventCode,
            String notificationCategory
        ) {

        Notification_Event_Mapping__mdt mapping =
            new Notification_Event_Mapping__mdt();

        mapping.Event_Code__c = eventCode;
        mapping.Notification_Category__c =
            notificationCategory;

        mapping.Payload_Version__c = '1.0';
        mapping.Is_Active__c = true;

        return mapping;
    }
}