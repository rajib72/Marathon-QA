@IsTest(SeeAllData=true)
private class HomeClaimsInformationAPITest {

    /*
     * ------------------------------------------------------------
     * Helper method to execute the REST API
     * ------------------------------------------------------------
     */
    private static String executeApi(String requestBody) {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/HomeClaimsInformation';
        
        if (requestBody != null) {
            req.requestBody = Blob.valueOf(requestBody);
        }

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        HomeClaimsInformationAPI.getClaimsInformation();
        Test.stopTest();

        return res.responseBody != null
            ? res.responseBody.toString()
            : null;
    }


    /*
     * ------------------------------------------------------------
     * 1. SUCCESS - Home Warranty policy with claims
     * ------------------------------------------------------------
     */
    @IsTest
    static void testSuccessWithClaims() {

        InsurancePolicy policy = [
            SELECT Id,
                   Name,
                   Postal_Code__c,
                   RecordType.Name
            FROM InsurancePolicy
            WHERE RecordType.Name = 'Home Warranty'
            AND Postal_Code__c != null
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            policy,
            'A Home Warranty InsurancePolicy record is required for this test.'
        );

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'CoveredResidencePostalCode' => policy.Postal_Code__c
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
            Integer.valueOf(String.valueOf(response.get('status')))
        );

        System.assertEquals(
            '',
            String.valueOf(response.get('error'))
        );

        System.assertNotEquals(
            null,
            response.get('payload')
        );

        System.assertNotEquals(
            null,
            response.get('claims')
        );
    }


    /*
     * ------------------------------------------------------------
     * 2. SUCCESS - Verify claims mapping
     * ------------------------------------------------------------
     */
    @IsTest
    static void testSuccessClaimMapping() {

        InsurancePolicy policy = [
            SELECT Id,
                   Name,
                   Postal_Code__c,
                   RecordType.Name
            FROM InsurancePolicy
            WHERE RecordType.Name = 'Home Warranty'
            AND Postal_Code__c != null
            LIMIT 1
        ];

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
            LIMIT 1
        ];

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'CoveredResidencePostalCode' => policy.Postal_Code__c
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
         * If a claim exists, verify claim mapping.
         */
        if (!claims.isEmpty()) {

            Map<String, Object> claimResponse =
                (Map<String, Object>) responseClaims[0];

            System.assertEquals(
                claims[0].Name,
                String.valueOf(claimResponse.get('ClaimNumber'))
            );

            System.assertEquals(
                claims[0].Status,
                String.valueOf(claimResponse.get('Status'))
            );
        }
    }


    /*
     * ------------------------------------------------------------
     * 3. NULL REQUEST BODY
     * ------------------------------------------------------------
     */
    @IsTest
    static void testNullRequestBody() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.httpMethod = 'POST';
        req.requestUri =
            '/services/apexrest/HomeClaimsInformation';

        req.requestBody = null;

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        HomeClaimsInformationAPI.getClaimsInformation();
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
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ------------------------------------------------------------
     * 4. BLANK REQUEST BODY
     * ------------------------------------------------------------
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
            'Contract not found or null value received for required field',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ------------------------------------------------------------
     * 5. INVALID JSON
     * ------------------------------------------------------------
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
     * ------------------------------------------------------------
     * 6. MISSING CONTRACT NUMBER
     * ------------------------------------------------------------
     */
    @IsTest
    static void testMissingContractNumber() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => '',
                'CoveredResidencePostalCode' => '11612'
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
     * ------------------------------------------------------------
     * 7. MISSING POSTAL CODE
     * ------------------------------------------------------------
     */
    @IsTest
    static void testMissingPostalCode() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'HW1',
                'CoveredResidencePostalCode' => ''
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
     * ------------------------------------------------------------
     * 8. CONTRACT NUMBER > 80 CHARACTERS
     * ------------------------------------------------------------
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
                'CoveredResidencePostalCode' => '11612'
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
     * ------------------------------------------------------------
     * 9. POSTAL CODE > 20 CHARACTERS
     * ------------------------------------------------------------
     */
    @IsTest
    static void testPostalCodeMaximumLength() {

        String longPostalCode = '';

        for (Integer i = 0; i < 21; i++) {
            longPostalCode += '1';
        }

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'HW1',
                'CoveredResidencePostalCode' => longPostalCode
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
            'CoveredResidencePostalCode exceeds the maximum length of 20 characters',
            String.valueOf(response.get('error'))
        );
    }


    /*
     * ------------------------------------------------------------
     * 10. CONTRACT NOT FOUND
     * ------------------------------------------------------------
     */
    @IsTest
    static void testContractNotFound() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'INVALID123',
                'CoveredResidencePostalCode' => '11612'
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
            '11612',
            String.valueOf(payload.get('CoveredResidencePostalCode'))
        );
    }


    /*
     * ------------------------------------------------------------
     * 11. WRONG POSTAL CODE
     * ------------------------------------------------------------
     */
    @IsTest
    static void testWrongPostalCode() {

        InsurancePolicy policy = [
            SELECT Id,
                   Name,
                   Postal_Code__c
            FROM InsurancePolicy
            WHERE RecordType.Name = 'Home Warranty'
            AND Postal_Code__c != null
            LIMIT 1
        ];

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'CoveredResidencePostalCode' => '99999'
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
     * ------------------------------------------------------------
     * 12. VERIFY ERROR RESPONSE CLAIMS ARRAY
     * ------------------------------------------------------------
     */
    @IsTest
    static void testErrorResponseStructure() {

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => 'INVALID123',
                'CoveredResidencePostalCode' => '99999'
            }
        );

        String responseBody = executeApi(requestBody);

        Map<String, Object> response =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        List<Object> claims =
            (List<Object>) response.get('claims');

        System.assertNotEquals(
            null,
            claims
        );

        System.assertEquals(
            1,
            claims.size()
        );
    }


    /*
     * ------------------------------------------------------------
     * 13. VERIFY SUCCESS PAYLOAD
     * ------------------------------------------------------------
     */
    @IsTest
    static void testSuccessPayload() {

        InsurancePolicy policy = [
            SELECT Id,
                   Name,
                   Postal_Code__c
            FROM InsurancePolicy
            WHERE RecordType.Name = 'Home Warranty'
            AND Postal_Code__c != null
            LIMIT 1
        ];

        String requestBody = JSON.serialize(
            new Map<String, Object>{
                'ContractNumber' => policy.Name,
                'CoveredResidencePostalCode' => policy.Postal_Code__c
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
            policy.Postal_Code__c,
            String.valueOf(
                payload.get('CoveredResidencePostalCode')
            )
        );
    }
}