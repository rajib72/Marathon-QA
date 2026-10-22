import { api, LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAllClients from '@salesforce/apex/RateBuilder.getAllClients';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import RecordSuccess from '@salesforce/label/c.RecordSuccess'
import RecordFailed from '@salesforce/label/c.RecordFailed'
import Error_Message from '@salesforce/label/c.Error_Message'
import getInsCarriers from '@salesforce/apex/RateBuilder.getInsCarriers';
import getStates from '@salesforce/apex/RateBuilder.getStates';
import getContractType from '@salesforce/apex/RateBuilder.getContractType';
import { CloseActionScreenEvent } from 'lightning/actions';
export default class RateBuilder extends NavigationMixin(LightningElement) {
    @track picklistOptions = [];
    productPicklist = [];
    coverageLevelPicklist = [];
    insCarriers = [];
    states = [];
    selectedProduct;
    selectedClient;
    selectedCarrier;
    selectedState;
    coverageLevel;
    coverageLevelValue;
    fields;
    clientProductCoverageMap = new Map();
    isClientSelected = false;
    isProductSelected = false;
    isCoverageSelected = false;
    isFieldsEntered = false;

    isWeekly = false;
    isMonthly = false;
    isRateImplementationBuilder = false;
    otherFields = false;
    dateCheck = false;
    submitButtonVisible = false;
    showCoverageLevel = false;
    selectAllCoverageLevel = false;
    @track isRefresh = false;
    productVar = '';
    contractType = '';

    connectedCallback() {

    }

    get showInsCarrier() {
        return this.insCarriers.length > 0;
    }

    get showState() {
        return this.states.length > 0;
    }

    // Assign a Client once Component is loaded
    @wire(getAllClients)
    wiredPicklistValues({ error, data }) {
        if (data) {
            try {
                //this.picklistOptions = data.map(value => ({ label: value, value: value }));

                const temp = JSON.parse(data);
                const mapData = temp.rows.map(row => {
                    const { Client, Product, CoverageLevel } = row.rowData;
                    return { Client, Product, CoverageLevel };
                });

                var Client1;
                var Product1;
                var CoverageLevel1;
                temp.rows.forEach(row => {
                    const { Client, Product, CoverageLevel } = row.rowData;
                    if (!this.clientProductCoverageMap.has(Client)) {
                        Client1 = this.decodeHtmlEntities(Client);
                        this.clientProductCoverageMap.set(Client1, new Map());
                    }

                    const productMap = this.clientProductCoverageMap.get(Client1);

                    // If product not in the productMap, add it
                    Product1 = this.decodeHtmlEntities(Product);
                    if (!productMap.has(Product)) {
                        productMap.set(Product1, new Set());
                    }
                    CoverageLevel1 = this.decodeHtmlEntities(Product);
                    const coverageSet = productMap.get(Product);
                    coverageSet.add(CoverageLevel);
                });
                //clientProductCoverageMap1 = clientProductCoverageMap;
                // Access the Data

                var options = [];
                this.clientProductCoverageMap.forEach((products, client) => {
                    options.push({ label: client, value: client });
                });
                this.error = undefined;
            }
            catch (error) {
                console.log('Error in wire::: ' + error.message + '  line no:' + error.lineNumber);
                this.handleError();
            }
        } else if (error) {
            this.error = error;
            this.handleError();
        }
        this.picklistOptions = options;
        this.sortOptions();
    }

    // Remove the encoded character and add special symbol based on matches
    decodeHtmlEntities(str) {
        return str
            .replaceAll('&#39;', "'")
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');
    }

    // Assign a Carrier
    handleCarrierChange(event) {
        try {
            this.selectedCarrier = event.detail.value;
        } catch (error) {
            this.handleError();
        }

    }

    // Assign a State
    handleStateChange(event) {
        try {
            this.selectedState = event.detail.value;
        } catch (error) {
            this.handleError();
        }

    }

    // Assign a Product based on Client Changes
    handleClientChange(event) {
        try {
            var productOptions = [];
            this.selectedClient = event.detail.value;
            this.clientProductCoverageMap.forEach((products, client) => {

                products.forEach((coverageLevels, product) => {
                    if (this.selectedClient == client) {
                        productOptions.push({ label: product, value: product });
                    }
                });
            });
            this.productPicklist = productOptions;
            this.selectedProduct = productOptions ? productOptions[0].value : null;
            this.coverageLevel = null;
            this.selectAllCoverageLevel = false;
            this.coverageLevelValue = null;
            this.isClientSelected = false;

            this.fetchInsCarriersnStates();
        } catch (error) {
            this.handleError();
        }

    }

    // Assign a coverage level based on Product changes
    productPicklistChange(event) {
        try {
            this.selectedProduct = event.detail.value;
            var coverageOptions = [];

            this.clientProductCoverageMap.forEach((products, client) => {
                if (this.selectedClient == client) {
                    products.forEach((coverageLevels, product) => {
                        if (this.selectedProduct == product) {
                            coverageLevels.forEach(coverage => {
                                coverageOptions.push({ label: coverage, value: coverage, checked: false });
                            })

                        }
                    });
                }
            });
            this.coverageLevelPicklist = coverageOptions;
            this.selectAllCoverageLevel = false;
            this.coverageLevel = null;
            this.coverageLevelValue = null;
            this.isProductSelected = false;

            this.fetchInsCarriersnStates();
        } catch (error) {
            this.handleError();
        }

    }

    async fetchInsCarriersnStates() {
        try {
            if(!this.selectedClient || !this.selectedProduct || !this.coverageLevel) {
                this.insCarriers = [];
                this.states = [];
                return;
            }
            const insCarrierValues = await getInsCarriers({client: this.selectedClient, product: this.selectedProduct,
                coverageLevel: this.coverageLevel});
            const staterValues = await getStates({client: this.selectedClient, product: this.selectedProduct,
                coverageLevel: this.coverageLevel});
            
            var carrierOptions = [];
            var stateOptions = [];

            /*insCarrierValues.forEach(function(carrier) {
                carrierOptions.push({ label: carrier, value: carrier, checked: false });
            });*/
            for (const carrier of insCarrierValues) {
                carrierOptions.push({ label: carrier, value: carrier, checked: false });
            }
            for (const state of staterValues) {
                stateOptions.push({ label: state, value: state, checked: false });
            }
            this.insCarriers = carrierOptions;
            this.states = stateOptions;

        } catch (error) {
            this.handleError();
        }

    }

    async fetchContractType() {
        try {
            this.contractType = await getContractType({coverageLevel: this.coverageLevel});
        } catch (error) {
            this.handleError();
        }

    }

    // onClick method to show/hide coverage level
    showCoverageLevelLogic(){
        this.showCoverageLevel = !this.showCoverageLevel;
    }

    // Deselects all coverage level when 'Select All' is unchecked
    onDeselectAll(){
        this.isCoverageSelected = false;
        this.selectAllCoverageLevel = false;
        this.coverageLevelPicklist.forEach(element => element.checked = false);
        this.coverageLevel = null;
        this.coverageLevelValue = null;
    }

    // Selects all coverage level when 'Select All' is checked
    onSelectAll(){
        this.isCoverageSelected = true;
        this.selectAllCoverageLevel = true;
        this.coverageLevelPicklist.forEach(element => element.checked = true);
        this.coverageLevel = this.coverageLevelPicklist.filter((element) => element.checked).map(element => element.label).join(';');
        this.coverageLevelValue = 'All Coverage Levels';
        if(this.productVar != this.selectedProduct) {
            this.productVar = this.selectedProduct;
            this.fetchContractType();
        }
        this.fetchInsCarriersnStates();
    }

    // When a coverage level is selected, checks that option
    onSelect(event){
        this.isCoverageSelected = false;
        this.coverageLevelPicklist.find(option => option.label === event.target.value).checked = event.target.checked;
        var itemCount = this.coverageLevelPicklist.filter((element) => element.checked).length;
        if (itemCount == this.coverageLevelPicklist.length && this.coverageLevelPicklist.length > 0) {
            this.selectAllCoverageLevel = true;
            this.coverageLevelValue = 'All Coverage Levels';
        }
        else {
            this.selectAllCoverageLevel = false;
            this.coverageLevelValue = this.coverageLevelPicklist.filter((element) => element.checked).map(element => element.label).join(', ');
        }  
        this.coverageLevel = this.coverageLevelPicklist.filter((element) => element.checked).map(element => element.label).join(';');  
        if(this.productVar != this.selectedProduct) {
            this.productVar = this.selectedProduct;
            this.fetchContractType();
        }
        this.fetchInsCarriersnStates();
    }

    // When success occurs from Salesforce, navigate to Record Object Home Page
    handleSuccess(event) {
        try {
            // Show a toast message
            this.submitButtonVisible = false;
            this.isClientSelected = false;
            this.isProductSelected = false;
            const toastEvent = new ShowToastEvent({
                title: 'Success!',
                message: RecordSuccess,
                variant: 'success',
                mode: 'dismissable',
            });
            this.dispatchEvent(toastEvent);

            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Report_Request__c',
                    actionName: 'home',
                },
            });
            
          } catch (error) {
            console.error('Error in handleAction:', error);
          } 

    }

    // In case of failure show toast message
    handleError() {
        try {
            const toastEvent = new ShowToastEvent({
                title: 'Failed!',
                message: Error_Message,
                variant: 'error',
                mode: 'dismissable',
            });
            this.dispatchEvent(toastEvent);
    
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Report_Request__c',
                    actionName: 'home',
                },
            });
          } catch (error) {
            console.error('Error in handleAction:', error);
          }
        


    }

    // When any issue occurs, navigate to Record Object Home Page
    errorNavigate(event) {
        const error = event.detail;

        console.error('Error in lightning-record-edit-form:', error);
        try {
            const toastEvent = new ShowToastEvent({
                title: 'Failed!',
                message: RecordFailed,
                variant: 'error',
                mode: 'dismissable',
            });
            this.dispatchEvent(toastEvent);
    
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Report_Request__c',
                    actionName: 'home',
                },
            });
          } catch (error) {
            console.error('Error in handleAction:', error);
          }

    }
    submitAction(event) {
        if (!this.selectedClient) {
            this.isClientSelected = true;
        }
        if (!this.selectedProduct) {
            this.isProductSelected = true;
        }
        if (!this.coverageLevel) {
            this.isCoverageSelected = true;
        }
        if(! this.fields){
            this.isFieldsEntered = true;
        }

    }

    callReportRequestHomePage() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Report_Request__c',
                actionName: 'home',
            },
        });
    }

    frequncyChange(event) {
        if (event.detail.value == 'Weekly') {
            this.isMonthly = false;
            this.isWeekly = true;
        }
        if (event.detail.value == 'Monthly') {
            this.isWeekly = false;
            this.isMonthly = true;
        }
        if (event.detail.value != 'Weekly' && event.detail.value != 'Monthly' && event.detail.value != '' && event.detail.value != null ) {
            this.isMonthly = false;
            this.isWeekly = false;
        }
        if(event.detail.value == 'Weekly' || event.detail.value == 'Monthly' || event.detail.value == 'Once'){
            this.dateCheck = true;
        }
        if(event.detail.value == 'Now' || event.detail.value == '' || event.detail.value == null){
            this.dateCheck = false;
        }
    }

    //Sorting the Clients alphabetically
    sortOptions() {
        if (this.picklistOptions && this.picklistOptions.length > 1) {
            this.picklistOptions.sort((a, b) => {
                if (a.label < b.label) {
                    return -1;
                }
                if (a.label > b.label) {
                    return 1;
                }
                return 0;
            });
        }
    }

    // When Report type changes, clear the fields and unhide the submit button
    reportTypeChange(event){
        this.isClientSelected = false;
        this.isProductSelected = false;
        this.isMonthly = false;
        this.isWeekly = false;
        this.dateCheck = false;
        this.selectedClient = null;
        this.selectedProduct = null;
        this.coverageLevel = null;
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        inputFields.forEach(field => {
            if (field.fieldName === 'Fields__c' || field.fieldName === 'Object__c' || field.fieldName === 'Filters__c' || field.fieldName === 'Group_By__c' || field.fieldName === 'Frequency__c'
                || field.fieldName === 'Client__c' || field.fieldName === 'Product__c' || field.fieldName === 'Coverage_Levels__c'
            ) {
                field.value = null; // this clears the field in the UI
            }
        });
        if(event.detail.value == 'Rate Implementation Builder' ){
            this.isRateImplementationBuilder = true;
            this.otherFields = false;
            this.submitButtonVisible = true;
            this.isRefresh = true;
        }
        if(event.detail.value != 'Rate Implementation Builder'){
            this.isRateImplementationBuilder = false;
            this.otherFields = true;
            this.submitButtonVisible = true;
            this.isRefresh = true;
        }
        if(event.detail.value == '' || event.detail.value == null){
            this.isRateImplementationBuilder = false;
            this.otherFields = false;
        }
    }

    fieldChange(event){
            if(event.detail.value != '' && event.detail.value != null){
                this.isFieldsEntered = true;
            }
    }
}