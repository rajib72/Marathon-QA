public with sharing class GoogleMapsController {
    
    @AuraEnabled(cacheable=true)
    public static String getGeocodeData(String address) {
        String apiKey = QDX_Property.propValueForLabel('Google Maps API Key');
        
        // URL for Google Geocoding API
        String url = 'https://maps.googleapis.com/maps/api/geocode/json?address=' + EncodingUtil.urlEncode(address, 'UTF-8') + '&key=' + apiKey;
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(url);
        request.setMethod('GET');
        
        HttpResponse response = http.send(request);
        if (response.getStatusCode() == 200) {
            // Return the response body (coordinates data)
            return response.getBody();
        } else {
            QDX_Log.error('Exception Occurred: ' + response.getStatus());
            QDX_Log.publish();
            throw new AuraHandledException('Error: ' + response.getStatus());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getNearbyServiceStations(Double lat, Double lng, String keyword) {
        String apiKey = QDX_Property.propValueForLabel('Google Maps API Key');
        // URL for Google Nearby API
        String url = 'https://places.googleapis.com/v1/places:searchNearby';
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(url);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('X-Goog-Api-Key', apiKey); 
        request.setHeader('X-Goog-FieldMask', 'places.location,places.id,places.displayName,places.formattedAddress,places.websiteUri,places.nationalPhoneNumber,places.shortFormattedAddress,places.postalAddress');
        
        // Set the body of the POST request (JSON payload), radius is set to 30 miles
        String requestBody = '{"includedTypes": ["'+ keyword+'"],' +
                             '"maxResultCount": 20,' +
                             '"locationRestriction": {' +
                             '"circle": {' +
                             '"center": {' +
                             '"latitude": '+ lat +',' +
                             '"longitude": '+ lng +
                             '},' +
                             '"radius": 48280.3' +
                             '}' +
                             '},' +
                             '"rankPreference": "DISTANCE"}';
        request.setBody(requestBody);
        HttpResponse response = http.send(request);
        
        if (response.getStatusCode() == 200) {
            // Return the response body (nearby service stations data)
            return response.getBody();
        } else {
            QDX_Log.error('Exception Occurred: ' + response.getStatus());
            QDX_Log.publish();
            throw new AuraHandledException('Error: ' + response.getStatus());
        }
    }

 
@AuraEnabled(cacheable=true)
public static String searchServiceCenterByPhone(String phoneNumber) {

    System.debug(LoggingLevel.INFO,
        'PHONE SEARCH - Input received: ' + phoneNumber
    );

    String apiKey =
        QDX_Property.propValueForLabel('Google Maps API Key');

    String url =
        'https://places.googleapis.com/v1/places:searchText';

    Http http = new Http();
    HttpRequest request = new HttpRequest();

    request.setEndpoint(url);
    request.setMethod('POST');

    request.setHeader('Content-Type', 'application/json');
    request.setHeader('X-Goog-Api-Key', apiKey);

    request.setHeader(
        'X-Goog-FieldMask',
        'places.location,places.id,places.displayName,' +
        'places.formattedAddress,places.websiteUri,' +
        'places.nationalPhoneNumber,places.shortFormattedAddress,' +
        'places.postalAddress'
    );



Map<String, Object> requestBody =
    new Map<String, Object>();

String digits = phoneNumber == null
    ? ''
    : phoneNumber.replaceAll('[^0-9]', '');

String normalizedPhone = digits;

if (digits.length() == 10) {
    normalizedPhone = '+1' + digits;
} else if (digits.length() == 11 && digits.startsWith('1')) {
    normalizedPhone = '+' + digits;
}

requestBody.put('textQuery', normalizedPhone);
requestBody.put('regionCode', 'US');

request.setBody(JSON.serialize(requestBody));



    System.debug(LoggingLevel.INFO,
        'PHONE SEARCH - Endpoint: ' + url
    );

    HttpResponse response = http.send(request);

    System.debug(LoggingLevel.INFO,
        'PHONE SEARCH - HTTP Status: ' +
        response.getStatusCode()
    );

    if (response.getStatusCode() == 200) {

        String responseBody = response.getBody();

        Map<String, Object> parsedResponse =
            (Map<String, Object>)
            JSON.deserializeUntyped(responseBody);

        List<Object> places =
            (List<Object>) parsedResponse.get('places');

        System.debug(LoggingLevel.INFO,
            'PHONE SEARCH - Number of places returned: ' +
            (places == null ? 0 : places.size())
        );

        if (places != null && !places.isEmpty()) {
            Map<String, Object> firstPlace =
                (Map<String, Object>) places[0];

            System.debug(LoggingLevel.INFO,
                'PHONE SEARCH - First result name: ' +
                JSON.serialize(firstPlace.get('displayName'))
            );

            System.debug(LoggingLevel.INFO,
                'PHONE SEARCH - First result address: ' +
                firstPlace.get('formattedAddress')
            );

            System.debug(LoggingLevel.INFO,
                'PHONE SEARCH - First result phone: ' +
                firstPlace.get('nationalPhoneNumber')
            );
        }

        return responseBody;

    } else {

        System.debug(LoggingLevel.ERROR,
            'PHONE SEARCH - Google API error: ' +
            response.getStatus()
        );

        QDX_Log.error(
            'Exception Occurred: ' + response.getStatus()
        );

        QDX_Log.publish();

        throw new AuraHandledException(
            'Error: ' + response.getStatus()
        );
    }
}


    //Method creates new Account record and updates the Claim record Repair_Shop_Account__c field with newly created account Id
    
@AuraEnabled
public static String insertAccount(String selectedServiceCenter, String claimRecordId) {
    try {
        List<LocationWrapper> data =
            (List<LocationWrapper>) JSON.deserialize(
                selectedServiceCenter,
                List<LocationWrapper>.class
            );

        if (data.isEmpty()) {
            throw new AuraHandledException('No service center was selected.');
        }

        Account serviceCenter;

        // Reuse an existing Salesforce Service Center Account.
        if (String.isNotBlank(data[0].accountId)) {
            List<Account> existingAccounts = [
                SELECT Id, Phone
                FROM Account
                WHERE Id = :data[0].accountId
                AND RecordType.DeveloperName = 'Service_Center'
                LIMIT 1
            ];

            if (existingAccounts.isEmpty()) {
                throw new AuraHandledException(
                    'The selected Service Center Account was not found.'
                );
            }

            serviceCenter = existingAccounts[0];
        }  else {
    // Preserve existing behavior for Google Places selections.
    Id recordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Service_Center')
        .getRecordTypeId();

    serviceCenter = new Account();
    serviceCenter.RecordTypeId = recordTypeId;
    serviceCenter.Name = data[0].title;
    serviceCenter.BillingStreet = data[0].location.Street;
    serviceCenter.BillingCity = data[0].location.City;
    serviceCenter.BillingState = data[0].location.State;
    serviceCenter.BillingPostalCode = data[0].location.PostalCode;
    serviceCenter.BillingCountry = data[0].location.Country;
    serviceCenter.Phone = data[0].phone;
    serviceCenter.Website = data[0].website;

    insert serviceCenter;
}
        // Update the Claim using the selected or newly created Account.
        Claim claimRecord = [
            SELECT Id, Repair_Shop_Account__c, Service_Phone_Number__c
            FROM Claim
            WHERE Id = :claimRecordId
            LIMIT 1
        ];

        claimRecord.Repair_Shop_Account__c = serviceCenter.Id;
        claimRecord.Service_Phone_Number__c = serviceCenter.Phone;

        update claimRecord;

        return System.Label.Google_Maps_Controller_Account_Success;

    } catch (Exception e) {
        QDX_Log.error(
            'Exception Occurred: ' + e.getMessage() +
            ' Line Number: ' + e.getLineNumber()
        );
        QDX_Log.publish();
        throw new AuraHandledException(e.getMessage());
    }
}


    @AuraEnabled
    public static List<ServiceCenterMapWrapper> getServiceCenterMapAccounts() {
        List<ServiceCenterMapWrapper> results =
            new List<ServiceCenterMapWrapper>();

        List<Account> accounts = [
            SELECT Id, Name,
                   BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry,
                   BillingLatitude, BillingLongitude,
                   Phone, Website, Repair_Fax__c, Email__c,
                   Rating, Labor_Rate__c,
                   Preferred__c, Known_Facility__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Service_Center'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 5
        ];

        String apiKey =
            QDX_Property.propValueForLabel('Google Maps API Key');

        Http http = new Http();

        for (Account acc : accounts) {
            ServiceCenterMapWrapper item =
                new ServiceCenterMapWrapper();

            item.Id = acc.Id;
            item.Name = acc.Name;
            item.BillingStreet = acc.BillingStreet;
            item.BillingCity = acc.BillingCity;
            item.BillingState = acc.BillingState;
            item.BillingPostalCode = acc.BillingPostalCode;
            item.BillingCountry = acc.BillingCountry;
            item.Phone = acc.Phone;
            item.Website = acc.Website;
            
item.repairFax = acc.Repair_Fax__c;
item.email = acc.Email__c;
item.rating = acc.Rating;
item.laborRate = acc.Labor_Rate__c;
item.preferred = acc.Preferred__c;
item.knownFacility = acc.Known_Facility__c;


            // Use saved coordinates when they already exist.
            if (acc.BillingLatitude != null &&
                acc.BillingLongitude != null) {
                item.BillingLatitude = acc.BillingLatitude;
                item.BillingLongitude = acc.BillingLongitude;
                results.add(item);
                continue;
            }

            // Build the address for geocoding.
            List<String> addressParts = new List<String>();

            if (String.isNotBlank(acc.BillingStreet))
                addressParts.add(acc.BillingStreet);
            if (String.isNotBlank(acc.BillingCity))
                addressParts.add(acc.BillingCity);
            if (String.isNotBlank(acc.BillingState))
                addressParts.add(acc.BillingState);
            if (String.isNotBlank(acc.BillingPostalCode))
                addressParts.add(acc.BillingPostalCode);
            if (String.isNotBlank(acc.BillingCountry))
                addressParts.add(acc.BillingCountry);

            if (addressParts.isEmpty()) {
                continue;
            }

            String address = String.join(addressParts, ', ');

            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                'https://maps.googleapis.com/maps/api/geocode/json' +
                '?address=' + EncodingUtil.urlEncode(address, 'UTF-8') +
                '&key=' + EncodingUtil.urlEncode(apiKey, 'UTF-8')
            );
            request.setMethod('GET');

            try {
                HttpResponse response = http.send(request);

                if (response.getStatusCode() != 200) {
                    System.debug(LoggingLevel.WARN,
                        'Geocoding failed for Account ' + acc.Id +
                        ': HTTP ' + response.getStatusCode());
                    continue;
                }

                Map<String, Object> body =
                    (Map<String, Object>)
                    JSON.deserializeUntyped(response.getBody());

                if (String.valueOf(body.get('status')) != 'OK') {
                    System.debug(LoggingLevel.WARN,
                        'No geocoding result for Account ' + acc.Id +
                        ': ' + String.valueOf(body.get('status')));
                    continue;
                }

                List<Object> geocodeResults =
                    (List<Object>) body.get('results');

                if (geocodeResults == null ||
                    geocodeResults.isEmpty()) {
                    continue;
                }

                Map<String, Object> firstResult =
                    (Map<String, Object>) geocodeResults[0];

                Map<String, Object> geometry =
                    (Map<String, Object>) firstResult.get('geometry');

                Map<String, Object> location =
                    (Map<String, Object>) geometry.get('location');

                item.BillingLatitude =
                    Decimal.valueOf(
                        String.valueOf(location.get('lat'))
                    ).doubleValue();

                item.BillingLongitude =
                    Decimal.valueOf(
                        String.valueOf(location.get('lng'))
                    ).doubleValue();

                results.add(item);

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'Geocoding error for Account ' + acc.Id +
                    ': ' + e.getMessage());
            }
        }

        return results;
    }

    
@AuraEnabled(cacheable=true)
public static List<Account> getServiceCenterAccounts() {
    return [
        SELECT Id,
               Name,
               BillingStreet,
               BillingCity,
               BillingState,
               BillingPostalCode,
               BillingCountry,
               BillingLatitude,
               BillingLongitude,
               Phone,
               Website,
               Repair_Fax__c,
               Email__c,
               Rating,
               Labor_Rate__c,
               Preferred__c,
               Known_Facility__c
        FROM Account
        WHERE RecordType.DeveloperName = 'Service_Center'
        WITH USER_MODE
        ORDER BY Name
        LIMIT 5
    ];
}


     // Inner class to map your JSON structure
     // Inner class to map your JSON structure
public class LocationWrapper {
    public Location location;
    public String value;
    public String title;
    public String description;
    public String id;
    public String address;
    public String phone;
    public String website;
    public String accountId;
}

    //class for google map location structure
    public class Location {
        public String Street;
        public String City;
        public String State;
        public String PostalCode;
        public String Country;
        public Double Latitude;
        public Double Longitude;
    }
    
    
public class ServiceCenterMapWrapper {
    @AuraEnabled public Id Id { get; set; }
    @AuraEnabled public String Name { get; set; }
    @AuraEnabled public String BillingStreet { get; set; }
    @AuraEnabled public String BillingCity { get; set; }
    @AuraEnabled public String BillingState { get; set; }
    @AuraEnabled public String BillingPostalCode { get; set; }
    @AuraEnabled public String BillingCountry { get; set; }
    @AuraEnabled public Double BillingLatitude { get; set; }
    @AuraEnabled public Double BillingLongitude { get; set; }
    @AuraEnabled public String Phone { get; set; }
    @AuraEnabled public String Website { get; set; }

    // Wrapper property names must be valid Apex identifiers.
    @AuraEnabled public String repairFax { get; set; }
    @AuraEnabled public String email { get; set; }
    @AuraEnabled public String rating { get; set; }
    @AuraEnabled public Decimal laborRate { get; set; }
    @AuraEnabled public Boolean preferred { get; set; }
    @AuraEnabled public Boolean knownFacility { get; set; }
}


}