import { LightningElement, wire, track, api } from 'lwc';
import { getRecord } from "lightning/uiRecordApi";
import getGeocodeData from '@salesforce/apex/GoogleMapsController.getGeocodeData';
import getNearbyServiceStations from '@salesforce/apex/GoogleMapsController.getNearbyServiceStations';
import searchServiceCenterByPhone from '@salesforce/apex/GoogleMapsController.searchServiceCenterByPhone';
import insertAccount from '@salesforce/apex/GoogleMapsController.insertAccount';
const FIELDS = ["Claim.PolicyNumber.Address_1__c", "Claim.PolicyNumber.City__c", "Claim.PolicyNumber.Postal_Code__c", "Claim.PolicyNumber.State__c", "Claim.PolicyNumber.NameInsured.BillingStreet", "Claim.PolicyNumber.NameInsured.BillingCity", "Claim.PolicyNumber.NameInsured.BillingState", "Claim.PolicyNumber.NameInsured.BillingPostalCode", "Claim.PolicyNumber.RecordType.Name", "Claim.PolicyNumber.NameInsured.BillingCountry"];
import Account_Success from '@salesforce/label/c.Google_Maps_Controller_Account_Success'
import Error_Message from '@salesforce/label/c.Error_Message'
import No_Location_Found_Error from'@salesforce/label/c.Google_Maps_API_No_Location_Found_Error'
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from "lightning/platformShowToastEvent";

//The lwc provides the user with the ability to search for Reapir shop. 
// On load, the lwc will render default location. If the contract is ‘Auto Warranty’, the default location is the Customers Address. If the contract is ‘Home Warranty’, the default location is the residential address.
// The user can also search for a location by address by clicking on the search button. 
// lwc then renders the list of nearby Repair shop and view them as markers on the map. Users then can select from the list or the map markers as the input value of the ‘Repair Shop Account’ field on the Claim and the Repair Shop Account’s Account fields.
export default class SearchPreferredServiceCenters extends LightningElement {
    
    serviceCompany;
    location;
    street;
    city;
    postalCode;
    state;
    country;
    phone;
    repairShopName
    serviceStations;
    billingStreet;
    billingCity;
    billingPostalCode;
    billingState;
    billingCountry;
    selectedServiceCenter = [];
    accountAddressFound;
    isMarkerSelected = false;
    center;
    keyword;
    modalWidthAdjusted = false;
    @api recordId;
    @track mapMarkers = [];

    //Fetches Claim record data
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({error , data }){   
        if(data){
            if(data.fields.PolicyNumber.value.fields.RecordType.value.fields.Name.value === 'Auto Warranty' && 
                (data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingStreet.value ||
                 data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingCity.value ||
                 data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingState.value ||
                 data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingPostalCode.value ||
                 data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingCountry.value
                )){
                    this.keyword ='car_repair';
                    this.accountAddressFound = true;
                    this.billingStreet = data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingStreet.value != undefined ? data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingStreet.value : '';
                    this.billingCity = data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingCity.value != undefined ? data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingCity.value : '';
                    this.billingPostalCode = data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingPostalCode.value != undefined ? data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingPostalCode.value : '';
                    this.billingState = data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingState.value != undefined ? data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingState.value : '';
                    this.billingCountry = data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingCountry.value != undefined ? data.fields.PolicyNumber.value.fields.NameInsured.value.fields.BillingCountry.value : '';
            }
            else if(data.fields.PolicyNumber.value.fields.RecordType.value.fields.Name.value === 'Home Warranty' &&
                (data.fields.PolicyNumber.value.fields.Address_1__c.value || 
                    data.fields.PolicyNumber.value.fields.City__c.value || 
                    data.fields.PolicyNumber.value.fields.Postal_Code__c.value || 
                    data.fields.PolicyNumber.value.fields.State__c.value)
            ){
                this.keyword ='plumber\",\"electrician';
                this.accountAddressFound = true;
                this.billingStreet = data.fields.PolicyNumber.value.fields.Address_1__c.value != undefined ? data.fields.PolicyNumber.value.fields.Address_1__c.value : '';
                this.billingCity = data.fields.PolicyNumber.value.fields.City__c.value != undefined ? data.fields.PolicyNumber.value.fields.City__c.value : '';
                this.billingPostalCode = data.fields.PolicyNumber.value.fields.Postal_Code__c.value != undefined ? data.fields.PolicyNumber.value.fields.Postal_Code__c.value : '';
                this.billingState = data.fields.PolicyNumber.value.fields.State__c.value != undefined ? data.fields.PolicyNumber.value.fields.State__c.value : '';
                
            }
            if(this.accountAddressFound){
                this.serviceCompany = ''+this.billingStreet+ ' '+ this.billingCity +' ' + this.billingState +' '+ this.billingPostalCode;
                this.handleSearch();
            }    
        }   
        else if(error){
            this.isError = true;
            this.placeholdererrorText = Error_Message;
            setTimeout(() => {
                this.isError = false;
                this.placeholdererrorText = '';}, 10000);
        }
    }

    // Sets modal width to constant of 900px
    renderedCallback(){
        if( this.modalSizeadjusted == false){
            
            let modal = document.querySelectorAll(".slds-modal__container");
            modal[0].style.minWidth = "900px";
            this.modalWidthAdjusted = true;
        }
        let awsmodal = document.querySelectorAll(".slds-modal__header ");
        awsmodal[0].style.top = "0%";
    }

    // Handles on click handler on Repair shop list and markers
    handleMarkerSelect(event) {
        this.selectedServiceCenter = this.mapMarkers.filter(element => {
            return element.value == event.target.selectedMarkerValue
        });
        if(this.selectedServiceCenter[0].title == 'Your Location'){
            this.selectedServiceCenter = [];
            this.repairShopName = '';
            this.street = '';
            this.city = '';
            this.state = '';
            this.postalCode = '';
            this.country = '';
            this.phone = '';
            this.isMarkerSelected = false;
        }
        else{
            this.repairShopName = this.selectedServiceCenter[0].title;
            this.street = this.selectedServiceCenter[0].location.Street;
            this.city = this.selectedServiceCenter[0].location.City;
            this.state = this.selectedServiceCenter[0].location.State;
            this.postalCode = this.selectedServiceCenter[0].location.PostalCode;
            this.country = this.selectedServiceCenter[0].location.Country;
            this.phone = this.selectedServiceCenter[0].phone;
            this.isMarkerSelected = true;
        }    
    }

    // Handles on click handler on search button. Passes selectedServiceCenter and claimRecordId to create new account and update associated Claim record.
    handleSaveSelection(){
        insertAccount({selectedServiceCenter: JSON.stringify(this.selectedServiceCenter), claimRecordId: this.recordId})
        .then(result => {
            if( result == Account_Success){
                const evt = new ShowToastEvent({
                    title: Account_Success,
                    variant: "success",
                  });
                  this.dispatchEvent(evt);
                setTimeout(() => {
                    window.location.reload();        
                }, 5000)                       
            }
        })
        .catch(error => {
            var title = Error_Message;
            if(error.body.message.includes("FIELD_CUSTOM_VALIDATION_EXCEPTION")){       
                title = error.body.message.split("EXCEPTION,")[1]?.trim();      
                title = title.replace(/: \[\]$/, "");
            }
            const evt = new ShowToastEvent({
                title: title,
                variant: "error",
              });
            this.dispatchEvent(evt);
        });
    }


    handleServiceCompanyChange(event) {
        this.serviceCompany = event.target.value;
    }
    isPhoneNumber(value) {
    const phoneDigits = value.replace(/\D/g, '');

    return phoneDigits.length >= 10;
}

    // method calls the Google Geocoding API  to get the latitude and longitude of the address.
    // Post latitude and longitude retrival, calls Google Nearby API to get nearby service stations and update the map markers.
    // Passes the markers to the map to render them on the map.
    async handleSearch() {
    try {
        this.selectedServiceCenter = [];
        this.repairShopName = '';
        this.street = '';
        this.city = '';
        this.state = '';
        this.postalCode = '';
        this.country = '';
        this.phone = '';

        if (!this.serviceCompany) {
            return;
        }

        /*
         * PHONE NUMBER SEARCH
         */
        if (this.isPhoneNumber(this.serviceCompany)) {

            const phoneSearchResult = await searchServiceCenterByPhone({
                phoneNumber: this.serviceCompany
            });

            const phoneSearchData = JSON.parse(phoneSearchResult);

            if (
                phoneSearchData.places &&
                phoneSearchData.places.length > 0
            ) {

                this.mapMarkers = [];

                phoneSearchData.places.forEach(place => {

                    if (
                        place?.location &&
                        place?.formattedAddress
                    ) {

                        this.mapMarkers.push({
                            location: {
                                Street:
                                    place?.postalAddress?.addressLines
                                        ? place.postalAddress.addressLines.join(', ')
                                        : '',

                                City:
                                    place?.postalAddress?.locality || '',

                                State:
                                    place?.postalAddress?.administrativeArea || '',

                                PostalCode:
                                    place?.postalAddress?.postalCode || '',

                                Country:
                                    place.formattedAddress
                                        ? place.formattedAddress.substring(
                                            place.formattedAddress.lastIndexOf(',') + 1
                                        ).trim()
                                        : '',

                                Latitude:
                                    place.location.latitude,

                                Longitude:
                                    place.location.longitude
                            },

                            value: place.id,

                            title:
                                place?.displayName?.text || '',

                            description:
                                place?.shortFormattedAddress || '',

                            id:
                                place.id,

                            address:
                                place.formattedAddress,

                            phone:
                                place?.nationalPhoneNumber || '',

                            website:
                                place?.websiteUri || ''
                        });

                    }
                });

                if (this.mapMarkers.length > 0) {

                    this.center = this.mapMarkers[0];

                    this.accountAddressFound = true;

                } else {

                    this.accountAddressFound = false;

                    const evt = new ShowToastEvent({
                        title: No_Location_Found_Error,
                        variant: "error"
                    });

                    this.dispatchEvent(evt);
                }

            } else {

                const evt = new ShowToastEvent({
                    title: No_Location_Found_Error,
                    variant: "error"
                });

                this.dispatchEvent(evt);
            }

            return;
        }

        /*
         * EXISTING ADDRESS SEARCH
         */
        const geocodeResult = await getGeocodeData({
            address: this.serviceCompany
        });

        const geocodeData = JSON.parse(geocodeResult);

        if (
            geocodeData.results &&
            geocodeData.results.length > 0
        ) {

            const location =
                geocodeData.results[0].geometry.location;

            const serviceStationsResult =
                await getNearbyServiceStations({
                    lat: location.lat,
                    lng: location.lng,
                    keyword: this.keyword
                });

            const serviceStationsData =
                JSON.parse(serviceStationsResult);

            this.mapMarkers = [];

            this.createMarkers(
                location.lat,
                location.lng,
                serviceStationsData.places,
                geocodeData
            ).forEach(marker => {
                this.mapMarkers.push(marker);
            });

            this.accountAddressFound = true;

        } else {

            const evt = new ShowToastEvent({
                title: No_Location_Found_Error,
                variant: "error"
            });

            this.dispatchEvent(evt);
        }

    } catch (error) {

        console.error('Search Error:', error);

        const evt = new ShowToastEvent({
            title: Error_Message,
            variant: "error"
        });

        this.dispatchEvent(evt);
    }
}

    //Creates Map markers to render them on the map.
    createMarkers(userLat, userLng, serviceStations, geoCodedata) {
        var serviceStationMarkers =[];
        var userMarker = [];

        var address = geoCodedata.results[0].formatted_address;
        var street = address.split(',');
        this.billingStreet = street[0];
        this.billingCity = street[1];
        this.billingState = geoCodedata.results[0].address_components.find( x => x.types.includes('administrative_area_level_1')) != undefined ? geoCodedata.results[0].address_components.find( x => x.types.includes('administrative_area_level_1')).long_name : '';
        this.billingCountry = street[3];
        this.billingPostalCode = geoCodedata.results[0].address_components.find( x => x.types.includes('postal_code')) != undefined ? geoCodedata.results[0].address_components.find( x => x.types.includes('postal_code')).long_name : '';
        userMarker = {
            location: {
                Street: this.billingStreet != undefined ? this.billingStreet : '',
                City: this.billingCity != undefined ? this.billingCity : '',                
                State: this.billingState != undefined ? this.billingState : '',                
                PostalCode: this.billingPostalCode != undefined? this.billingPostalCode : '',                
                Country: this.billingCountry != undefined ? this.billingCountry : '',
                Latitude: userLat,
                Longitude: userLng,
            },
            title: 'Your Location',
            description: this.serviceCompany,
            id: this.serviceCompany,
            icon: 'utility:pinned',
            mapIcon: {
                path: 'M 0,0 C -2,-20 -10,-22 -10,-30 A 10,10 0 1,1 10,-30 C 10,-22 2,-20 0,0 Z ' + // Outer pin shape
                      'M 0,-30 m -3,0 a 3,3 0 1,0 6,0 a 3,3 0 1,0 -6,0', // Black center dot
                fillColor: '#00cc00',
                fillOpacity: 1,
                strokeOpacity: 1,
                strokeColor: '#000000',
                strokeWeight: 1,
                scale: 1.2,
                // anchor: { x: 15, y: 30 }
            }
        };
        this.center = userMarker;
        serviceStations.forEach(element => {
            if(  element?.postalAddress?.addressLines && element?.postalAddress?.locality && element?.postalAddress?.administrativeArea && element?.postalAddress?.postalCode && element?.formattedAddress 
                && element?.location?.latitude && element?.location?.longitude){
                    serviceStationMarkers.push({
                        location: {
                            Street: element.postalAddress.addressLines != undefined? element.postalAddress.addressLines.join(", "): '',
                            City: element.postalAddress.locality,
                            State: element.postalAddress.administrativeArea,
                            PostalCode: element.postalAddress.postalCode,
                            Country: element.formattedAddress.substring(element.formattedAddress.lastIndexOf(',') + 1).trim(),
                            Latitude: element.location.latitude,
                            Longitude: element.location.longitude,
                        },
                        value: element.id,
                        title: element?.displayName?.text ?? '',
                        description: element?.shortFormattedAddress ?? '',                
                        id: element.id,
                        address: element.formattedAddress,
                        phone: element?.nationalPhoneNumber ?? '',
                        website: element?.websiteUri ?? '',
                        
                } );
            }
        }
        );
        return [userMarker, ...serviceStationMarkers];
    }

    get mapMarkersHasElements(){
        return this.mapMarkers.length > 0;
    }

}