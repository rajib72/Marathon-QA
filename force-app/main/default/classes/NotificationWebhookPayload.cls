public class NotificationWebhookPayload {

    public static final String CONTRACT_EXPIRY_REMINDER_EVENT =
        'CONTRACT_EXPIRY_REMINDER_90';

    public String eventCode { get; set; }
    public String customerId { get; set; }
    public String policyId { get; set; }
    public String claimId { get; set; }
    public String eventTime { get; set; }
    public Map<String, Object> attributes { get; set; }

    public class PayloadValidationException extends Exception {
    }

    public NotificationWebhookPayload() {
        attributes = new Map<String, Object>();
    }

    /**
     * Creates a normal record-specific notification payload.
     *
     * Used for:
     * CLAIM_INITIATED
     * CLAIM_APPROVED
     * CONTRACT_CANCELLED
     * CONTRACT_EXPIRED
     * CONTRACT_UPDATED
     * FINANCE_PAST_DUE
     * FINANCE_CURRENT
     */
    public static NotificationWebhookPayload forRecordEvent(
        String eventCode,
        Id customerId,
        Id policyId,
        Id claimId,
        Datetime eventDateTime
    ) {
        NotificationWebhookPayload payload =
            new NotificationWebhookPayload();

        payload.eventCode = eventCode;
        payload.customerId =
            customerId == null ? null : String.valueOf(customerId);
        payload.policyId =
            policyId == null ? null : String.valueOf(policyId);
        payload.claimId =
            claimId == null ? null : String.valueOf(claimId);
        payload.eventTime = formatEventTime(eventDateTime);

        return payload;
    }

    /**
     * Creates the customer-list payload required by the app team
     * for the 90-day contract-expiration reminder.
     */
public static NotificationWebhookPayload forContractExpiryReminder(
    List<Id> customerIds,
    Datetime eventDateTime
) {
    NotificationWebhookPayload payload =
        new NotificationWebhookPayload();

    payload.eventCode = CONTRACT_EXPIRY_REMINDER_EVENT;
    payload.eventTime = formatEventTime(eventDateTime);

    List<String> customerIdList = new List<String>();

    if (customerIds != null) {
        for (Id customerId : customerIds) {
            if (customerId != null) {
                customerIdList.add(String.valueOf(customerId));
            }
        }
    }

    /*
     * Do not convert this list to a Set.
     * One customer ID may intentionally appear multiple times when
     * multiple contracts belonging to that customer qualify.
     */
    payload.addAttribute(
        'customer_sf_id_list',
        customerIdList
    );

    return payload;
}

    /**
     * Adds an attribute when both its name and value are available.
     */
    public NotificationWebhookPayload addAttribute(
        String attributeName,
        Object attributeValue
    ) {
        if (
            String.isNotBlank(attributeName) &&
            attributeValue != null
        ) {
            attributes.put(attributeName, attributeValue);
        }

        return this;
    }

    /**
     * Performs event-specific payload validation.
     */
    public void validate() {
        List<String> validationErrors = new List<String>();

        if (String.isBlank(eventCode)) {
            validationErrors.add('eventCode is required');
        }

        if (String.isBlank(eventTime)) {
            validationErrors.add('eventTime is required');
        }

        if (attributes == null) {
            attributes = new Map<String, Object>();
        }

        if (eventCode == CONTRACT_EXPIRY_REMINDER_EVENT) {
            validateContractExpiryReminder(validationErrors);
        } else {
            validateRecordEvent(validationErrors);
        }

        if (!validationErrors.isEmpty()) {
            throw new PayloadValidationException(
                String.join(validationErrors, '; ')
            );
        }
    }

    private void validateRecordEvent(
        List<String> validationErrors
    ) {
        if (String.isBlank(customerId)) {
            validationErrors.add('customerId is required');
        }

        if (String.isBlank(policyId)) {
            validationErrors.add('policyId is required');
        }

        if (
            String.isNotBlank(eventCode) &&
            eventCode.startsWith('CLAIM_') &&
            String.isBlank(claimId)
        ) {
            validationErrors.add(
                'claimId is required for Claim notification events'
            );
        }
    }

    private void validateContractExpiryReminder(
        List<String> validationErrors
    ) {
        if (
            !attributes.containsKey('customer_sf_id_list') ||
            attributes.get('customer_sf_id_list') == null
        ) {
            validationErrors.add(
                'customer_sf_id_list is required for ' +
                CONTRACT_EXPIRY_REMINDER_EVENT
            );
            return;
        }

        try {
            List<String> customerIdList =
                (List<String>) attributes.get(
                    'customer_sf_id_list'
                );

            if (
                customerIdList == null ||
                customerIdList.isEmpty()
            ) {
                validationErrors.add(
                    'customer_sf_id_list must contain at least ' +
                    'one customer Salesforce ID'
                );
            }
        } catch (Exception ex) {
            validationErrors.add(
                'customer_sf_id_list must be a list of ' +
                'Salesforce customer IDs'
            );
        }
    }

    /**
     * Serializes the payload and omits null top-level fields.
     *
     * Therefore customerId, policyId and claimId will not appear
     * in the contract-reminder payload.
     */
    public String toJson() {
        validate();
        return JSON.serialize(this, true);
    }

    /**
     * The app examples currently use:
     * yyyy-MM-ddTHH:mm:ss
     *
     * The value is generated in UTC but the current app contract
     * does not include a timezone suffix.
     */
    public static String formatEventTime(
        Datetime eventDateTime
    ) {
        Datetime valueToFormat =
            eventDateTime == null
                ? System.now()
                : eventDateTime;

        return valueToFormat.formatGmt(
            'yyyy-MM-dd\'T\'HH:mm:ss'
        );
    }
}