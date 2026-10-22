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
    String apiKey = QDX_Property.propValueForLabel('Google Maps API Key');

    String url = 'https://places.googleapis.com/v1/places:searchText';

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

    Map<String, Object> requestBody = new Map<String, Object>();
    requestBody.put('textQuery', phoneNumber);

    request.setBody(JSON.serialize(requestBody));

    HttpResponse response = http.send(request);

    if (response.getStatusCode() == 200) {
        return response.getBody();
    } else {
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
    public static string insertAccount(String selectedServiceCenter, String claimRecordId){
        try {
            List<LocationWrapper> data = (List<LocationWrapper>) JSON.deserialize(selectedServiceCenter, List<LocationWrapper>.class);
            if (!data.isEmpty()) {       
                Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Service_Center').getRecordTypeId();         
                Account serviceCenter = new Account();
                serviceCenter.RecordTypeId = recordTypeId;
                serviceCenter.Name = data[0].title;
                serviceCenter.BillingStreet = data[0].location.Street;
                serviceCenter.BillingCity = data[0].location.City;
                serviceCenter.BillingState = data[0].location.State;
                serviceCenter.BillingPostalCode = data[0].location.PostalCode;
                serviceCenter.BillingCountry = data[0].location.Country;
                serviceCenter.Phone = data[0].phone;
                serviceCenter.Website = data[0].Website;

                Database.insert(serviceCenter);

                Claim claimRecord = [SELECT Id, Repair_Shop_Account__c from Claim where Id =:claimRecordId LIMIT 1][0];
                if( claimRecord != null){                    
                claimRecord.Repair_Shop_Account__c = serviceCenter.Id;
                claimRecord.Service_Phone_Number__c = data[0].phone;
                Database.update(claimRecord);
                }
            }
            return System.Label.Google_Maps_Controller_Account_Success;
        } catch (Exception e) {
            QDX_Log.error('Exception Occurred: ' +e.getMessage()+ 'Line Number: '+e.getLineNumber());
            QDX_Log.publish();
            throw new AuraHandledException(e.getMessage());
        }
    }

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
}