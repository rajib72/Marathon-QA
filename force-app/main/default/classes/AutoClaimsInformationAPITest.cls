@IsTest(SeeAllData=true)
private class AutoClaimsInformationAPITest {

    /*
     * ============================================================
     * Helper method to execute the REST API
     * ============================================================
     */
    private static String executeApi(String requestBody) {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/AutoClaimsInformation';

        if (requestBody != null) {
            req.requestBody = Blob.valueOf(requestBody);
        }

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        AutoClaimsInformationAPI.getClaimsInformation();
        Test.stopTest();

        return res.responseBody != null
            ? res.responseBody.toString()
            : null;
    }


    /*
     * ============================================================
     * Helper: same formatting the API class applies to money fields
     * (PaidAmount / ApprovedAmount / RequestedAmount are all written
     * with .setScale(0).format(), so tests must compare against the
     * same transformed value rather than the raw Decimal).
     * ============================================================
     */
    private static String asApiAmount(Decimal value) {
        return value != null
            ? value.setScale(2).format()
            : '0.00';
    }


    /*
     * ============================================================
     * Helper method to get an existing Auto Warranty policy
     * ============================================================
     */
    private static InsurancePolicy getAutoPolicy() {

        List<InsurancePolicy> policies = [
            SELECT Id,
                   Name,
                   VIN__c
            FROM InsurancePolicy
            WHERE Name != null
            AND VIN__c != null
            LIMIT 1
        ];

        System.assert(
            !policies.isEmpty(),
            'An InsurancePolicy with Contract Number and VIN is required.'
        );

        return policies[0];
    }


    /*
     * ============================================================
     * 1. SUCCESS - Valid Contract + VIN
     * ============================================================
     */
    @IsTest
    static void testSuccessResponse() {

        InsurancePolicy policy = getAutoPolicy();

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'VIN' => policy.VIN__c
            }
        );

        String responseBody = executeApi(requestBody);

        System.assertNotEquals(
            null,
            responseBody,
            'Response body should not be null.'
        );

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            200,
            Integer.valueOf(String.valueOf(response.get('status'))),
            'Expected HTTP status 200.'
        );

        System.assertEquals(
            '',
            String.valueOf(response.get('error')),
            'Success response should have an empty error.'
        );

        System.assertNotEquals(
            null,
            response.get('payload'),
            'Payload should be present.'
        );

        System.assertNotEquals(
            null,
            response.get('claims'),
            'Claims should be present.'
        );
    }


    /*
     * ============================================================
     * 2. SUCCESS - Verify Payload
     * ============================================================
     */
    @IsTest
    static void testSuccessPayload() {

        InsurancePolicy policy = getAutoPolicy();

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'VIN' => policy.VIN__c
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        Map<String, Object> payload =
            (Map<String, Object>) response.get('payload');

        System.assertEquals(
            policy.Name,
            String.valueOf(payload.get('ContractNumber'))
        );

        System.assertEquals(
            policy.VIN__c,
            String.valueOf(payload.get('VIN'))
        );
    }


    /*
     * ============================================================
     * 3. SUCCESS - Verify Claim Mapping
     *
     * FIX: PaidAmount / ApprovedAmount are written by the API using
     * .setScale(0).format() (e.g. "100" not "100.00"). Compare
     * against that same transformed value instead of the raw
     * currency Decimal (which stringifies as "100.00").
     * ============================================================
     */
    @IsTest
    static void testClaimMapping() {

        InsurancePolicy policy = getAutoPolicy();

        List<Claim> claims = [
            SELECT Id,
                   Name,
                   Status,
                   Claim_Amount_Paid__c,
                   ApprovedAmount,
                   Latest_Date_Paid__c,
                   Denial_Reason__c
            FROM Claim
            WHERE PolicyNumberId = :policy.Id
            ORDER BY CreatedDate DESC
        ];

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'VIN' => policy.VIN__c
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            200,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        List<Object> responseClaims =
            (List<Object>) response.get('claims');

        System.assertNotEquals(
            null,
            responseClaims
        );

        /*
         * If claims exist, verify the first claim mapping.
         */
        if (!claims.isEmpty() && !responseClaims.isEmpty()) {

            Map<String, Object> apiClaim =
                (Map<String, Object>) responseClaims[0];

            System.assertEquals(
                claims[0].Name,
                String.valueOf(apiClaim.get('ClaimNumber'))
            );

            System.assertEquals(
                claims[0].Status,
                String.valueOf(apiClaim.get('Status'))
            );

            /*
             * Verify Paid Amount (formatted the same way the API formats it).
             */
            System.assertEquals(
                asApiAmount(claims[0].Claim_Amount_Paid__c),
                String.valueOf(apiClaim.get('PaidAmount'))
            );

            /*
             * Verify Approved Amount (formatted the same way the API formats it).
             */
            System.assertEquals(
                asApiAmount(claims[0].ApprovedAmount),
                String.valueOf(apiClaim.get('ApprovedAmount'))
            );

            /*
             * Verify Denial Reason.
             */
            String expectedDenial =
                claims[0].Denial_Reason__c != null
                    ? claims[0].Denial_Reason__c
                    : '';

            System.assertEquals(
                expectedDenial,
                String.valueOf(apiClaim.get('DenialReason'))
            );
        }
    }


    /*
     * ============================================================
     * 4. SUCCESS - Verify Date Formatting (Latest Paid Date present)
     * ============================================================
     */
    @IsTest
    static void testLatestPaidDateFormatting() {

        InsurancePolicy policy = getAutoPolicy();

        List<Claim> claims = [
            SELECT Id,
                   Name,
                   Latest_Date_Paid__c
            FROM Claim
            WHERE PolicyNumberId = :policy.Id
            AND Latest_Date_Paid__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        /*
         * If the org has a claim with a Latest Paid Date,
         * verify MM-DD-YYYY formatting.
         */
        if (!claims.isEmpty()) {

            String requestBody = JSON.serialize(
                new Map<String, Object>{
                    'ContractNumber' => policy.Name,
                    'VIN' => policy.VIN__c
                }
            );

            String responseBody = executeApi(requestBody);

            Map<String, Object> response =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            List<Object> responseClaims =
                (List<Object>) response.get('claims');

            System.assertNotEquals(
                null,
                responseClaims
            );

            Boolean dateFound = false;

            for (Object item : responseClaims) {

                Map<String, Object> apiClaim =
                    (Map<String, Object>) item;

                if (
                    String.valueOf(apiClaim.get('ClaimNumber'))
                    == claims[0].Name
                ) {

                    String expectedDate =
                        DateTime.newInstance(
                            claims[0].Latest_Date_Paid__c,
                            Time.newInstance(0, 0, 0, 0)
                        ).format('MM-dd-yyyy');

                    System.assertEquals(
                        expectedDate,
                        String.valueOf(
                            apiClaim.get('LatestPaidDate')
                        )
                    );

                    dateFound = true;
                    break;
                }
            }

            System.assertEquals(
                true,
                dateFound,
                'Claim with Latest Paid Date should be returned.'
            );
        }
    }


    /*
     * ============================================================
     * 4b. NEW - Verify Latest Paid Date is '' when field is null
     *
     * Covers the ELSE branch of the LatestPaidDate mapping, which
     * was previously untested.
     * ============================================================
     */
    @IsTest
    static void testNullLatestPaidDateFormatting() {

        InsurancePolicy policy = getAutoPolicy();

        List<Claim> claims = [
            SELECT Id,
                   Name,
                   Latest_Date_Paid__c
            FROM Claim
            WHERE PolicyNumberId = :policy.Id
            AND Latest_Date_Paid__c = null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!claims.isEmpty()) {

            String requestBody = JSON.serialize(
                new Map<String, Object>{
                    'ContractNumber' => policy.Name,
                    'VIN' => policy.VIN__c
                }
            );

            String responseBody = executeApi(requestBody);

            Map<String, Object> response =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            List<Object> responseClaims =
                (List<Object>) response.get('claims');

            for (Object item : responseClaims) {

                Map<String, Object> apiClaim =
                    (Map<String, Object>) item;

                if (
                    String.valueOf(apiClaim.get('ClaimNumber'))
                    == claims[0].Name
                ) {

                    System.assertEquals(
                        '',
                        String.valueOf(apiClaim.get('LatestPaidDate')),
                        'LatestPaidDate should be empty string when field is null.'
                    );

                    break;
                }
            }
        }
    }


    /*
     * ============================================================
     * 4c. NEW - Verify RequestedAmount maps from Claim.NetClaim__c
     * ============================================================
     */
    @IsTest
    static void testRequestedAmountMapping() {

        InsurancePolicy policy = getAutoPolicy();

        List<Claim> claims = [
            SELECT Id,
                   Name,
                   NetClaim__c
            FROM Claim
            WHERE PolicyNumberId = :policy.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!claims.isEmpty()) {

            String requestBody = JSON.serialize(
                new Map<String, Object>{
                    'ContractNumber' => policy.Name,
                    'VIN' => policy.VIN__c
                }
            );

            String responseBody = executeApi(requestBody);

            Map<String, Object> response =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            List<Object> responseClaims =
                (List<Object>) response.get('claims');

            for (Object item : responseClaims) {

                Map<String, Object> apiClaim =
                    (Map<String, Object>) item;

                if (
                    String.valueOf(apiClaim.get('ClaimNumber'))
                    == claims[0].Name
                ) {

                    System.assertEquals(
                        asApiAmount(claims[0].NetClaim__c),
                        String.valueOf(apiClaim.get('RequestedAmount')),
                        'RequestedAmount should map directly from NetClaim__c.'
                    );

                    break;
                }
            }
        }
    }


    /*
     * ============================================================
     * 4d. NEW - Verify CreatedDate formatting (MM-DD-YYYY)
     * ============================================================
     */
    @IsTest
    static void testCreatedDateFormatting() {

        InsurancePolicy policy = getAutoPolicy();

        List<Claim> claims = [
            SELECT Id,
                   Name,
                   CreatedDate
            FROM Claim
            WHERE PolicyNumberId = :policy.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!claims.isEmpty()) {

            String requestBody = JSON.serialize(
                new Map<String, Object>{
                    'ContractNumber' => policy.Name,
                    'VIN' => policy.VIN__c
                }
            );

            String responseBody = executeApi(requestBody);

            Map<String, Object> response =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            List<Object> responseClaims =
                (List<Object>) response.get('claims');

            for (Object item : responseClaims) {

                Map<String, Object> apiClaim =
                    (Map<String, Object>) item;

                if (
                    String.valueOf(apiClaim.get('ClaimNumber'))
                    == claims[0].Name
                ) {

                    String expectedCreatedDate =
                        claims[0].CreatedDate.format('MM-dd-yyyy');

                    System.assertEquals(
                        expectedCreatedDate,
                        String.valueOf(apiClaim.get('CreatedDate'))
                    );

                    break;
                }
            }
        }
    }


    /*
     * ============================================================
     * 4e. NEW - Policy with zero claims returns an empty claims array
     * (as opposed to the error-case single-empty-object array)
     * ============================================================
     */
    @IsTest
    static void testPolicyWithNoClaimsReturnsEmptyArray() {

        List<InsurancePolicy> candidatePolicies = [
            SELECT Id, Name, VIN__c
            FROM InsurancePolicy
            WHERE Name != null
            AND VIN__c != null
            AND Id NOT IN (SELECT PolicyNumberId FROM Claim WHERE PolicyNumberId != null)
            LIMIT 1
        ];

        if (!candidatePolicies.isEmpty()) {

            InsurancePolicy policy = candidatePolicies[0];

            String requestBody = JSON.serialize(
                new Map<String, Object>{
                    'ContractNumber' => policy.Name,
                    'VIN' => policy.VIN__c
                }
            );

            String responseBody = executeApi(requestBody);

            Map<String, Object> response =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            System.assertEquals(
                200,
                Integer.valueOf(String.valueOf(response.get('status')))
            );

            List<Object> responseClaims =
                (List<Object>) response.get('claims');

            System.assertEquals(
                0,
                responseClaims.size(),
                'Policy with no claims should return an empty claims array.'
            );
        }
    }


    /*
     * ============================================================
     * 5. NULL REQUEST BODY
     * ============================================================
     */
    @IsTest
    static void testNullRequestBody() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.httpMethod = 'POST';
        req.requestUri =
            '/services/apexrest/AutoClaimsInformation';

        req.requestBody = null;

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        AutoClaimsInformationAPI.getClaimsInformation();
        Test.stopTest();

        System.assertEquals(
            400,
            res.statusCode
        );

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(
            'Null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 6. BLANK REQUEST BODY
     * ============================================================
     */
    @IsTest
    static void testBlankRequestBody() {

        String responseBody = executeApi('');

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 7. INVALID JSON
     * ============================================================
     */
    @IsTest
    static void testInvalidJson() {

        String responseBody =
            executeApi('{invalid json}');

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Invalid request format',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 8. MISSING CONTRACT NUMBER
     * ============================================================
     */
    @IsTest
    static void testMissingContractNumber() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => '',
                'VIN' => '1GNEVJKW3KJ164801'
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 9. MISSING VIN
     * ============================================================
     */
    @IsTest
    static void testMissingVIN() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'EMBI2001213',
                'VIN' => ''
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 10. BOTH REQUIRED FIELDS MISSING
     * ============================================================
     */
    @IsTest
    static void testBothRequiredFieldsMissing() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => '',
                'VIN' => ''
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 11. CONTRACT NUMBER > 80 CHARACTERS
     * ============================================================
     */
    @IsTest
    static void testContractNumberMaximumLength() {

        String longContractNumber = '';

        for (Integer i = 0; i < 81; i++) {
            longContractNumber += 'A';
        }

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => longContractNumber,
                'VIN' => '1GNEVJKW3KJ164801'
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'ContractNumber exceeds the maximum length of 80 characters',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 12. VIN > 17 CHARACTERS
     * ============================================================
     */
    @IsTest
    static void testVINMaximumLength() {

        String longVIN = '';

        for (Integer i = 0; i < 18; i++) {
            longVIN += '1';
        }

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'EMBI2001213',
                'VIN' => longVIN
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'VIN exceeds the maximum length of 17 characters',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 13. CONTRACT NOT FOUND
     * ============================================================
     */
    @IsTest
    static void testContractNotFound() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'INVALID123',
                'VIN' => '1GNEVJKW3KJ164801'
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );

        Map<String, Object> payload =
            (Map<String, Object>) response.get('payload');

        System.assertEquals(
            'INVALID123',
            String.valueOf(payload.get('ContractNumber'))
        );

        System.assertEquals(
            '1GNEVJKW3KJ164801',
            String.valueOf(payload.get('VIN'))
        );
    }


    /*
     * ============================================================
     * 14. WRONG VIN
     * ============================================================
     */
    @IsTest
    static void testWrongVIN() {

        InsurancePolicy policy = getAutoPolicy();

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'VIN' => '11111111111111111'
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ============================================================
     * 15. ERROR RESPONSE STRUCTURE
     * ============================================================
     */
    @IsTest
    static void testErrorResponseStructure() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'INVALID123',
                'VIN' => '11111111111111111'
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        System.assertEquals(
            400,
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertNotEquals(
            null,
            response.get('payload')
        );

        System.assertNotEquals(
            null,
            response.get('claims')
        );

        List<Object> claims =
            (List<Object>) response.get('claims');

        System.assertEquals(
            1,
            claims.size()
        );
    }


    /*
     * ============================================================
     * 16. VERIFY SUCCESS CLAIM COUNT
     * ============================================================
     */
    @IsTest
    static void testSuccessClaimCount() {

        InsurancePolicy policy = getAutoPolicy();

        Integer expectedClaimCount = [
            SELECT COUNT()
            FROM Claim
            WHERE PolicyNumberId = :policy.Id
        ];

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'VIN' => policy.VIN__c
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        List<Object> responseClaims =
            (List<Object>) response.get('claims');

        System.assertEquals(
            expectedClaimCount,
            responseClaims.size(),
            'API should return all claims associated with the policy.'
        );
    }
}