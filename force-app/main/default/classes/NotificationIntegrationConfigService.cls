public with sharing class NotificationIntegrationConfigService {

    private static final String CONFIG_DEVELOPER_NAME = 'Marathon_Connect';
    private static final Integer DEFAULT_MAX_EVENTS_PER_DISPATCH = 50;

    private static Notification_Integration_Config__mdt cachedConfig;
    private static Map<String, Notification_Event_Mapping__mdt> cachedMappingsByEventCode;
    private static Set<Integer> cachedSuccessStatusCodes;

    @TestVisible
    private static Notification_Integration_Config__mdt testConfigOverride;

    @TestVisible
    private static Map<String, Notification_Event_Mapping__mdt> testMappingsOverride;

    public class NotificationConfigurationException extends Exception {
    }

    /**
     * Returns the primary integration configuration metadata record.
     */
    public static Notification_Integration_Config__mdt getConfig() {
        if (testConfigOverride != null) {
            return testConfigOverride;
        }

        if (cachedConfig == null) {
            cachedConfig =
                Notification_Integration_Config__mdt.getInstance(
                    CONFIG_DEVELOPER_NAME
                );
        }

        return cachedConfig;
    }

    /**
     * Returns whether the overall notification integration is enabled.
     *
     * Missing configuration is treated as disabled so that a metadata issue
     * does not unnecessarily block Claim or Insurance Policy transactions.
     */
    public static Boolean isIntegrationEnabled() {
        Notification_Integration_Config__mdt config = getConfig();

        return config != null && config.Is_Enabled__c == true;
    }

    /**
     * Returns one active event mapping using the app-defined event code.
     */
    public static Notification_Event_Mapping__mdt getActiveEventMapping(
        String eventCode
    ) {
        if (String.isBlank(eventCode)) {
            return null;
        }

        return getActiveEventMappingsByCode().get(
            normalizeEventCode(eventCode)
        );
    }

    /**
     * Returns whether a specific event is currently active.
     */
    public static Boolean isEventEnabled(String eventCode) {
        return getActiveEventMapping(eventCode) != null;
    }

    /**
     * Returns all active event mappings keyed by Event_Code__c.
     */
    public static Map<String, Notification_Event_Mapping__mdt>
        getActiveEventMappingsByCode() {

        if (testMappingsOverride != null) {
            return copyMappings(testMappingsOverride);
        }

        if (cachedMappingsByEventCode == null) {
            cachedMappingsByEventCode =
                new Map<String, Notification_Event_Mapping__mdt>();

            for (
                Notification_Event_Mapping__mdt mapping :
                Notification_Event_Mapping__mdt.getAll().values()
            ) {
                if (
                    mapping.Is_Active__c == true &&
                    String.isNotBlank(mapping.Event_Code__c)
                ) {
                    cachedMappingsByEventCode.put(
                        normalizeEventCode(mapping.Event_Code__c),
                        mapping
                    );
                }
            }
        }

        return copyMappings(cachedMappingsByEventCode);
    }

    /**
     * Builds the endpoint used by HttpRequest.setEndpoint().
     *
     * Example:
     * callout:Marathon_Connect_Webhook/api/webhooks/notification
     */
    public static String getCalloutEndpoint() {
        Notification_Integration_Config__mdt config =
            requireValidCalloutConfig();

        return 'callout:' +
            config.Named_Credential__c.trim() +
            normalizeWebhookPath(config.Webhook_Path__c);
    }

    public static String getNamedCredentialName() {
        Notification_Integration_Config__mdt config = getConfig();

        return config == null
            ? null
            : config.Named_Credential__c;
    }

    public static String getWebhookPath() {
        Notification_Integration_Config__mdt config = getConfig();

        return config == null
            ? null
            : normalizeWebhookPath(config.Webhook_Path__c);
    }

    public static String getPayloadVersion() {
        Notification_Integration_Config__mdt config = getConfig();

        if (
            config == null ||
            String.isBlank(config.Payload_Version__c)
        ) {
            return '1.0';
        }

        return config.Payload_Version__c.trim();
    }

    public static String getEnvironment() {
        Notification_Integration_Config__mdt config = getConfig();

        return config == null
            ? null
            : config.Environment__c;
    }

    /**
     * Returns the configured maximum number of events processed by one
     * dispatcher execution.
     *
     * The value is capped at 100 because Apex permits a maximum of
     * 100 callouts in one transaction.
     */
    public static Integer getMaximumEventsPerDispatch() {
        Notification_Integration_Config__mdt config = getConfig();

        if (
            config == null ||
            config.Maximum_Events_Per_Dispatch__c == null
        ) {
            return DEFAULT_MAX_EVENTS_PER_DISPATCH;
        }

        Integer configuredValue =
            config.Maximum_Events_Per_Dispatch__c.intValue();

        if (configuredValue <= 0) {
            return DEFAULT_MAX_EVENTS_PER_DISPATCH;
        }

        return Math.min(configuredValue, 100);
    }

    /**
     * Returns the configured successful HTTP response codes.
     *
     * Invalid or blank metadata falls back to HTTP 200 and 202.
     */
    public static Set<Integer> getSuccessStatusCodes() {
        if (cachedSuccessStatusCodes == null) {
            cachedSuccessStatusCodes = new Set<Integer>();

            Notification_Integration_Config__mdt config = getConfig();

            if (
                config != null &&
                String.isNotBlank(config.Success_Status_Codes__c)
            ) {
                for (
                    String statusCodeValue :
                    config.Success_Status_Codes__c.split(',')
                ) {
                    String trimmedValue = statusCodeValue.trim();

                    if (String.isBlank(trimmedValue)) {
                        continue;
                    }

                    try {
                        cachedSuccessStatusCodes.add(
                            Integer.valueOf(trimmedValue)
                        );
                    } catch (Exception ex) {
                        // Ignore an invalid individual metadata value.
                    }
                }
            }

            if (cachedSuccessStatusCodes.isEmpty()) {
                cachedSuccessStatusCodes.add(200);
                cachedSuccessStatusCodes.add(202);
            }
        }

        Set<Integer> result = new Set<Integer>();
        result.addAll(cachedSuccessStatusCodes);
        return result;
    }

    public static Boolean isSuccessfulStatusCode(Integer statusCode) {
        return statusCode != null &&
            getSuccessStatusCodes().contains(statusCode);
    }

    /**
     * Validates configuration fields required for a webhook callout.
     */
    private static Notification_Integration_Config__mdt
        requireValidCalloutConfig() {

        Notification_Integration_Config__mdt config = getConfig();

        if (config == null) {
            throw new NotificationConfigurationException(
                'Notification Integration Config metadata record ' +
                CONFIG_DEVELOPER_NAME +
                ' was not found.'
            );
        }

        if (config.Is_Enabled__c != true) {
            throw new NotificationConfigurationException(
                'The notification integration is currently disabled.'
            );
        }

        List<String> missingFields = new List<String>();

        if (String.isBlank(config.Named_Credential__c)) {
            missingFields.add('Named_Credential__c');
        }

        if (String.isBlank(config.Webhook_Path__c)) {
            missingFields.add('Webhook_Path__c');
        }

        if (!missingFields.isEmpty()) {
            throw new NotificationConfigurationException(
                'Notification integration configuration is incomplete. ' +
                'Missing fields: ' +
                String.join(missingFields, ', ')
            );
        }

        return config;
    }

    private static String normalizeEventCode(String eventCode) {
        return eventCode == null
            ? null
            : eventCode.trim().toUpperCase();
    }

    private static String normalizeWebhookPath(String webhookPath) {
        if (String.isBlank(webhookPath)) {
            return '';
        }

        String normalizedPath = webhookPath.trim();

        return normalizedPath.startsWith('/')
            ? normalizedPath
            : '/' + normalizedPath;
    }

    private static Map<String, Notification_Event_Mapping__mdt>
        copyMappings(
            Map<String, Notification_Event_Mapping__mdt> sourceMappings
        ) {

        Map<String, Notification_Event_Mapping__mdt> result =
            new Map<String, Notification_Event_Mapping__mdt>();

        if (sourceMappings != null) {
            result.putAll(sourceMappings);
        }

        return result;
    }

    @TestVisible
    private static void resetCache() {
        cachedConfig = null;
        cachedMappingsByEventCode = null; 
        cachedSuccessStatusCodes = null;
        testConfigOverride = null;
        testMappingsOverride = null;
    }
}