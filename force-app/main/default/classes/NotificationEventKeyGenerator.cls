public class NotificationEventKeyGenerator {
    
    private static final String NULL_VALUE = '__NULL__';
    private static final String CLAIM_APPROVED_EVENT_CODE = 'CLAIM_APPROVED';
    
    private NotificationEventKeyGenerator() {
    }
    
    /**
* Generates a unique internal identifier for one outbox event.
*
* This value is used for internal tracing and may later be supplied
* to the app team as an idempotency or correlation identifier.
*/
    public static String generateEventId() {
        return EncodingUtil.convertToHex(
            Crypto.generateAesKey(128)
        );
    }
    
    /**
* Generates a deterministic key for a record-change event.
*
* The event timestamp allows the same record to legitimately
* re-enter the same qualifying status later and generate a new event.
*/
    public static String forRecordEvent(
        String eventCode,
        Id sourceRecordId,
        String changedField,
        String oldValue,
        String newValue,
        Datetime eventTime
    ) {
        validateRequiredValue(eventCode, 'eventCode');
        validateRequiredValue(
            sourceRecordId == null
            ? null
            : String.valueOf(sourceRecordId),
            'sourceRecordId'
        );
        
        Datetime resolvedEventTime =
            eventTime == null ? System.now() : eventTime;
        
        String canonicalValue = String.join(
            new List<String>{
                normalize(eventCode),
                    String.valueOf(sourceRecordId),
                    normalize(changedField),
                    normalizeNullable(oldValue),
                    normalizeNullable(newValue),
                    String.valueOf(resolvedEventTime.getTime())
                    },
            '|'
        );
        
        return generateHash(canonicalValue);
    }
    
    /**
* Generates the deterministic key for the Claim Approved
* notification.
*
* Only one CLAIM_APPROVED notification is permitted for each
* parent Claim, regardless of how many eligible Claim Items later
* transition to Authorized.
*
* The Claim Id is intentionally used instead of the ClaimItem Id,
* and no event timestamp is included.
*/
    public static String forClaimApproved(
        Id claimId
    ) {
        validateRequiredValue(
            claimId == null
            ? null
            : String.valueOf(claimId),
            'claimId'
        );
        
        String canonicalValue = String.join(
            new List<String>{
                CLAIM_APPROVED_EVENT_CODE,
                    String.valueOf(claimId)
                    },
            '|'
        );
        
        return generateHash(
            canonicalValue
        );
    }
    
    /**
* Generates a deterministic reminder key.
*
* One reminder is permitted per:
* InsurancePolicy + Expiration Date.
*
* If the expiration date later changes, the newly calculated date
* generates a different key and becomes independently eligible.
*/
    public static String forContractExpiryReminder(
        Id insurancePolicyId,
        Date expirationDate
    ) {
        validateRequiredValue(
            insurancePolicyId == null
            ? null
            : String.valueOf(insurancePolicyId),
            'insurancePolicyId'
        );
        
        validateRequiredValue(
            expirationDate == null
            ? null
            : String.valueOf(expirationDate),
            'expirationDate'
        );
        
        String canonicalValue = String.join(
            new List<String>{
                'CONTRACT_EXPIRY_REMINDER_90',
                    String.valueOf(insurancePolicyId),
                    String.valueOf(expirationDate)
                    },
            '|'
        );
        
        return generateHash(canonicalValue);
    }
    
    private static String generateHash(String canonicalValue) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(canonicalValue)
            )
        );
    }
    
    private static String normalize(String value) {
        return String.isBlank(value)
            ? ''
            : value.trim().toUpperCase();
    }
    
    private static String normalizeNullable(String value) {
        return value == null
            ? NULL_VALUE
            : value.trim();
    }
    
    private static void validateRequiredValue(
        String value,
        String parameterName
    ) {
        if (String.isBlank(value)) {
            throw new IllegalArgumentException(
                parameterName + ' is required.'
            );
        }
    }
}