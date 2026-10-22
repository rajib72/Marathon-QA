/**
 * @description
 * Unit tests for GoogleMapsController.
 *
 * Covers:
 * - Successful Google Geocode callout
 * - Failed Google Geocode callout
 * - Successful Nearby Places callout
 * - Failed Nearby Places callout
 * - Successful Service Center Account creation
 * - Claim Repair Shop update
 * - Empty Service Center payload
 * - Invalid payload / exception handling
 *
 * Design Note:
 * These tests intentionally do NOT create an InsurancePolicy for
 * insertAccount() tests because GoogleMapsController does not require one.
 *
 * This prevents unrelated Claim eligibility validation rules from making
 * the unit test environment-dependent during CI/CD deployments.
 */
@IsTest
public class GoogleMapsControllerTest {

    /* =========================================================
       TEST DATA HELPER
       ========================================================= */

    /**
     * Creates the minimum Claim required by GoogleMapsController.
     *
     * No InsurancePolicy is deliberately assigned because the controller
     * under test does not depend on one.
     */
    private static Claim createTestClaim() {

        Claim claimRec = new Claim();

        claimRec.Name =
            'Google Maps Test Claim';

        claimRec.ReportDate =
            System.now();

        insert claimRec;

        return claimRec;
    }


    /* =========================================================
       GENERIC HTTP MOCK
       ========================================================= */

    private class GoogleMapsMock
        implements HttpCalloutMock {

        private Integer statusCode;
        private String responseBody;
        private String statusText;


        GoogleMapsMock(
            Integer statusCode,
            String responseBody
        ) {

            this.statusCode =
                statusCode;

            this.responseBody =
                responseBody;

            this.statusText =
                statusCode == 200
                ? 'OK'
                : 'Internal Server Error';
        }


        public HttpResponse respond(
            HttpRequest request
        ) {

            HttpResponse response =
                new HttpResponse();

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setStatusCode(
                statusCode
            );

            response.setStatus(
                statusText
            );

            response.setBody(
                responseBody
            );

            return response;
        }
    }


    /* =========================================================
       GEOCODE - SUCCESS
       ========================================================= */

    @IsTest
    static void testGetGeocodeDataSuccess() {

        String mockResponse =
            '{' +
                '"results":[' +
                    '{' +
                        '"formatted_address":"Melbourne, Australia",' +
                        '"geometry":{' +
                            '"location":{' +
                                '"lat":-37.8136,' +
                                '"lng":144.9631' +
                            '}' +
                        '}' +
                    '}' +
                '],' +
                '"status":"OK"' +
            '}';


        Test.setMock(
            HttpCalloutMock.class,
            new GoogleMapsMock(
                200,
                mockResponse
            )
        );


        Test.startTest();

        String result =
            GoogleMapsController.getGeocodeData(
                'Melbourne'
            );

        Test.stopTest();


        System.assertNotEquals(
            null,
            result,
            'Geocode response should not be null.'
        );

        System.assert(
            result.contains('"lat"'),
            'Response should contain latitude.'
        );

        System.assert(
            result.contains('"lng"'),
            'Response should contain longitude.'
        );
    }


    /* =========================================================
       GEOCODE - FAILURE
       ========================================================= */

    @IsTest
    static void testGetGeocodeDataFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleMapsMock(
                500,
                '{"error":"Google API failure"}'
            )
        );


        Boolean exceptionThrown =
            false;


        Test.startTest();

        try {

            GoogleMapsController.getGeocodeData(
                'Invalid Address'
            );

        } catch (AuraHandledException ex) {

            exceptionThrown =
                true;
        }

        Test.stopTest();


        System.assertEquals(
            true,
            exceptionThrown,
            'AuraHandledException should be thrown for a failed Geocode response.'
        );
    }


    /* =========================================================
       NEARBY PLACES - SUCCESS
       ========================================================= */

    @IsTest
    static void testGetNearbyServiceStationsSuccess() {

        String mockResponse =
            '{' +
                '"places":[' +
                    '{' +
                        '"id":"TEST_PLACE_001",' +
                        '"nationalPhoneNumber":"0478 777 777",' +
                        '"formattedAddress":"777 Test Street, Melbourne",' +
                        '"location":{' +
                            '"latitude":-37.8044,' +
                            '"longitude":144.9631' +
                        '},' +
                        '"websiteUri":"https://testdata.example",' +
                        '"displayName":{' +
                            '"text":"Test Service Center",' +
                            '"languageCode":"en"' +
                        '}' +
                    '}' +
                ']' +
            '}';


        Test.setMock(
            HttpCalloutMock.class,
            new GoogleMapsMock(
                200,
                mockResponse
            )
        );


        Test.startTest();

        String result =
            GoogleMapsController.getNearbyServiceStations(
                Double.valueOf('-37.8044'),
                Double.valueOf('144.9631'),
                'car_repair'
            );

        Test.stopTest();


        System.assertNotEquals(
            null,
            result,
            'Nearby Places response should not be null.'
        );

        System.assert(
            result.contains(
                'formattedAddress'
            ),
            'Nearby result should contain a formatted address.'
        );
    }


    /* =========================================================
       NEARBY PLACES - FAILURE
       ========================================================= */

    @IsTest
    static void testGetNearbyServiceStationsFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleMapsMock(
                500,
                '{"error":"Places API failure"}'
            )
        );


        Boolean exceptionThrown =
            false;


        Test.startTest();

        try {

            GoogleMapsController.getNearbyServiceStations(
                Double.valueOf('-37.8044'),
                Double.valueOf('144.9631'),
                'car_repair'
            );

        } catch (AuraHandledException ex) {

            exceptionThrown =
                true;
        }

        Test.stopTest();


        System.assertEquals(
            true,
            exceptionThrown,
            'AuraHandledException should be thrown when Nearby Places API fails.'
        );
    }


    /* =========================================================
       INSERT SERVICE CENTER - SUCCESS
       ========================================================= */

    @IsTest
    static void testInsertAccount() {

        /*
         * IMPORTANT:
         *
         * GoogleMapsController does NOT need an InsurancePolicy.
         *
         * Therefore do not introduce unrelated Policy eligibility
         * validation into this unit test.
         */
        Claim claimRec =
            createTestClaim();


        String serviceCenterLocation =
            '[' +
                '{' +
                    '"location":{' +
                        '"Street":"583-585 Elizabeth St",' +
                        '"City":"Melbourne",' +
                        '"State":"Victoria",' +
                        '"PostalCode":"3000",' +
                        '"Country":"Australia",' +
                        '"Latitude":-37.8046904,' +
                        '"Longitude":144.9582857' +
                    '},' +
                    '"value":"ChIJq8IXiSZd1moRnXWAMb-NywU",' +
                    '"title":"EBIKE Quick Aces Drive",' +
                    '"description":"583-585 Elizabeth St, Melbourne",' +
                    '"id":"ChIJq8IXiSZd1moRnXWAMb-NywU",' +
                    '"address":"583-585 Elizabeth St, Melbourne VIC 3000, Australia",' +
                    '"phone":"0478 781 090",' +
                    '"website":"https://lithiumbicycle.com.au/"' +
                '}' +
            ']';


        Test.startTest();

        String result =
            GoogleMapsController.insertAccount(
                serviceCenterLocation,
                claimRec.Id
            );

        Test.stopTest();


        System.assertEquals(
            System.Label.Google_Maps_Controller_Account_Success,
            result,
            'Service Center Account should be created successfully.'
        );


        /* -----------------------------------------------------
           Verify Claim
           ----------------------------------------------------- */

        Claim updatedClaim = [
            SELECT
                Id,
                Repair_Shop_Account__c,
                Service_Phone_Number__c
            FROM Claim
            WHERE Id = :claimRec.Id
            LIMIT 1
        ];


        System.assertNotEquals(
            null,
            updatedClaim.Repair_Shop_Account__c,
            'New Service Center should be assigned to the Claim.'
        );


        System.assertEquals(
            '0478 781 090',
            updatedClaim.Service_Phone_Number__c,
            'Service phone number should be copied to the Claim.'
        );


        /* -----------------------------------------------------
           Verify newly-created Service Center Account
           ----------------------------------------------------- */

        Account serviceCenter = [
            SELECT
                Id,
                Name,
                RecordType.DeveloperName,
                BillingStreet,
                BillingCity,
                BillingState,
                BillingPostalCode,
                BillingCountry,
                Phone,
                Website
            FROM Account
            WHERE Id =
                :updatedClaim.Repair_Shop_Account__c
            LIMIT 1
        ];


        System.assertEquals(
            'Service_Center',
            serviceCenter.RecordType.DeveloperName,
            'The Account should use the Service Center record type.'
        );


        System.assertEquals(
            'EBIKE Quick Aces Drive',
            serviceCenter.Name
        );


        System.assertEquals(
            '583-585 Elizabeth St',
            serviceCenter.BillingStreet
        );


        System.assertEquals(
            'Melbourne',
            serviceCenter.BillingCity
        );


        System.assertEquals(
            'Victoria',
            serviceCenter.BillingState
        );


        System.assertEquals(
            '3000',
            serviceCenter.BillingPostalCode
        );


        System.assertEquals(
            'Australia',
            serviceCenter.BillingCountry
        );


        System.assertEquals(
            '0478 781 090',
            serviceCenter.Phone
        );


        System.assertEquals(
            'https://lithiumbicycle.com.au/',
            serviceCenter.Website
        );
    }


    /* =========================================================
       INSERT SERVICE CENTER - EMPTY PAYLOAD
       ========================================================= */

    @IsTest
    static void testInsertAccountEmptyLocations() {

        /*
         * Same isolation principle:
         *
         * No Account -> InsurancePolicy -> Claim hierarchy is
         * necessary just to test an empty Google Maps payload.
         */
        Claim claimRec =
            createTestClaim();


        Test.startTest();

        String result =
            GoogleMapsController.insertAccount(
                '[]',
                claimRec.Id
            );

        Test.stopTest();


        System.assertEquals(
            System.Label.Google_Maps_Controller_Account_Success,
            result,
            'Empty location payload should safely return the success label.'
        );


        Claim unchangedClaim = [
            SELECT
                Id,
                Repair_Shop_Account__c
            FROM Claim
            WHERE Id = :claimRec.Id
            LIMIT 1
        ];


        System.assertEquals(
            null,
            unchangedClaim.Repair_Shop_Account__c,
            'No Service Center should be assigned for an empty payload.'
        );
    }


    /* =========================================================
       INSERT SERVICE CENTER - INVALID JSON
       ========================================================= */

    @IsTest
    static void testInsertAccountInvalidPayload() {

        Boolean exceptionThrown =
            false;


        Test.startTest();

        try {

            GoogleMapsController.insertAccount(
                'INVALID_JSON',
                null
            );

        } catch (AuraHandledException ex) {

            exceptionThrown =
                true;
        }

        Test.stopTest();


        System.assertEquals(
            true,
            exceptionThrown,
            'Invalid JSON should be surfaced as an AuraHandledException.'
        );
    }


    /* =========================================================
       INSERT SERVICE CENTER - INVALID CLAIM
       ========================================================= */

    @IsTest
    static void testInsertAccountInvalidClaimId() {

        String serviceCenterLocation =
            '[' +
                '{' +
                    '"location":{' +
                        '"Street":"100 Test Street",' +
                        '"City":"Austin",' +
                        '"State":"TX",' +
                        '"PostalCode":"78701",' +
                        '"Country":"United States"' +
                    '},' +
                    '"title":"Invalid Claim Service Center",' +
                    '"phone":"5555555555",' +
                    '"website":"https://example.com"' +
                '}' +
            ']';


        Boolean exceptionThrown =
            false;


        /*
         * Generate a syntactically valid Claim Id that does
         * not exist in the database.
         */
        Claim temporaryClaim =
            createTestClaim();

        Id invalidClaimId =
            temporaryClaim.Id;

        delete temporaryClaim;


        Test.startTest();

        try {

            GoogleMapsController.insertAccount(
                serviceCenterLocation,
                String.valueOf(
                    invalidClaimId
                )
            );

        } catch (AuraHandledException ex) {

            exceptionThrown =
                true;
        }

        Test.stopTest();


        System.assertEquals(
            true,
            exceptionThrown,
            'Missing Claim should be handled through the controller exception path.'
        );
    }
}