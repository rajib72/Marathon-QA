import {
    LightningElement,
    track,wire
} from 'lwc';

import getClients
    from '@salesforce/apex/InternalQuoteRequestController.getClients';

import getProducts
    from '@salesforce/apex/InternalQuoteRequestController.getProducts';

import getOptions
    from '@salesforce/apex/InternalQuoteRequestController.getOptions';

import getQuotes
    from '@salesforce/apex/InternalQuoteRequestController.getQuotes';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import REPORT_REQUEST_OBJECT
    from '@salesforce/schema/Report_Request__c';

import STATE_FIELD
    from '@salesforce/schema/Report_Request__c.State__c';

import getResidenceTypes
    from '@salesforce/apex/InternalQuoteRequestController.getResidenceTypes';

import {
    ShowToastEvent
} from 'lightning/platformShowToastEvent';

import {
    NavigationMixin
} from 'lightning/navigation';


export default class InternalQuoteRequest
    extends NavigationMixin(LightningElement) {


    // ============================================================
    // FORM VALUES
    // ============================================================

    @track client = '';

    @track product = '';

    @track saleOdometer = '';

    @track state = '';

    @track vin = '';
    

    @track selectedOptions = [];
    @track quoteType = '';
    @track residenceType = '';

    @track quoteTypeOptions = [
    { label: 'Auto', value: 'Auto' },
    {  label: 'Home', value: 'Home' }
];

// Populate these with the actual residence types accepted by Apex.
@track residenceTypeOptions = [];


    // ============================================================
    // DROPDOWN OPTIONS
    // ============================================================

    @track clientOptions = [];

    @track productOptions = [];

    @track optionOptions = [];

    @track stateOptions = [];
    
    // DYNAMIC STATE PICKLIST
recordTypeId;

@wire(getObjectInfo, {
    objectApiName: REPORT_REQUEST_OBJECT
})
wiredObjectInfo({ data, error }) {
    if (data) {
        this.recordTypeId = data.defaultRecordTypeId;
    } else if (error) {
        this.showError(
            'Error loading State configuration',
            this.getErrorMessage(error)
        );
    }
}

@wire(getPicklistValues, {
    recordTypeId: '$recordTypeId',
    fieldApiName: STATE_FIELD
})
wiredStateValues({ data, error }) {
    if (data) {
        this.stateOptions = data.values.map(item => ({
            label: item.label,
            value: item.value
        }));
    } else if (error) {
        this.showError(
            'Error loading States',
            this.getErrorMessage(error)
        );
    }
}


    // ============================================================
    // UI STATE
    // ============================================================

    @track isLoading = false;

    @track isLoadingClients = false;

    @track showOptionsDropdown = false;


    // ============================================================
    // LIFECYCLE
    // ============================================================

    connectedCallback() {

     //   this.initializeStateOptions();


       // this.loadClients();

    }



    // ============================================================
    // LOAD CLIENTS
    // ============================================================

  /*  async loadClients() {

        this.isLoadingClients = true;

        try {

            const result = await getClients();

            this.clientOptions =
                result || [];

        } catch (error) {

            this.showError(
                'Error loading clients',
                this.getErrorMessage(error)
            );

        } finally {

            this.isLoadingClients = false;

        }
    }*/


        
async loadClients() {
    if (!this.quoteType) {
        this.clientOptions = [];
        this.client = '';
        return;
    }

    this.isLoadingClients = true;

    try {
        const result = await getClients({
            quoteType: this.quoteType
        });

        this.clientOptions = result || [];
    } catch (error) {
        this.clientOptions = [];
        this.showError(
            'Error loading clients',
            this.getErrorMessage(error)
        );
    } finally {
        this.isLoadingClients = false;
    }
}




    // ============================================================
    // CLIENT CHANGE
    // ============================================================

    async handleClientChange(event) {

        this.client =
            event.detail.value;

        /*
         * Reset everything dependent on Client.
         */

        this.product = '';
        this.residenceType = '';
        this.residenceTypeOptions = []; 

        this.productOptions = [];

        this.selectedOptions = [];

        this.optionOptions = [];

        this.showOptionsDropdown = false;

        if (!this.client) {
            return;
        }

        this.isLoading = true;

        try {

            const result =
                await getProducts({
                    client: this.client
                });

            this.productOptions =
                result || [];

        } catch (error) {

            this.showError(
                'Error loading products',
                this.getErrorMessage(error)
            );

        } finally {

            this.isLoading = false;

        }
    }


    // ============================================================
    // PRODUCT CHANGE
    // ============================================================

    
async handleProductChange(event) {
    this.product = event.detail.value;

    // Clear options selected for the previous product.
    this.selectedOptions = [];
    this.optionOptions = [];
    this.showOptionsDropdown = false;

    if (!this.client || !this.product) {
        return;
    }

    this.isLoading = true;

    try {
        const result = await getOptions({
            client: this.client,
            product: this.product
        });
        console.log('Selected Client:', this.client);
        console.log('Selected Product:', this.product);
        console.log('Options returned from Apex:', JSON.stringify(result));

        this.optionOptions = (result || [])
            .filter(option =>
                option &&
                option.value &&
                option.value.trim().toLowerCase() !== 'others'
            )
            .map(option => ({
                label: option.label,
                value: option.value,
                checked: false
            }));

        this.showOptionsDropdown = this.optionOptions.length > 0;
        // Load Residence Type values for Home products.
        await this.loadResidenceTypes();

    } catch (error) {
        this.showOptionsDropdown = false;

        this.showError(
            'Error loading options',
            this.getErrorMessage(error)
        );

    } finally {
        this.isLoading = false;
    }
}



async loadResidenceTypes() {
    // Residence Type is applicable only to Home.
    if (
        this.quoteType !== 'Home' ||
        !this.client ||
        !this.product
    ) {
        this.residenceType = '';
        this.residenceTypeOptions = [];
        return;
    }

    // Clear stale values from the previous product.
    this.residenceType = '';
    this.residenceTypeOptions = [];

    try {
        const result = await getResidenceTypes({
            client: this.client,
            product: this.product
        });

        console.log(
            'Residence Type - Client:',
            this.client
        );
        console.log(
            'Residence Type - Product:',
            this.product
        );
        console.log(
            'Residence Type - Apex result:',
            JSON.stringify(result)
        );

        this.residenceTypeOptions = (result || [])
            .filter(option =>
                option &&
                option.value &&
                option.label
            )
            .map(option => ({
                label: option.label,
                value: option.value
            }));

        console.log(
            'Residence Type - Dropdown options:',
            JSON.stringify(this.residenceTypeOptions)
        );

        if (this.residenceTypeOptions.length === 0) {
            console.warn(
                'No Residence Type values returned for the selected client and product.'
            );
        }
    } catch (error) {
        this.residenceTypeOptions = [];

        this.showError(
            'Error loading Residence Types',
            this.getErrorMessage(error)
        );
    }
}



    // ============================================================
    // INPUT CHANGE
    // ============================================================

    handleInputChange(event) {

        const fieldName =
            event.target.name;

        const value =
            event.target.value;

        if (fieldName === 'saleOdometer') {

            this.saleOdometer = value;

        } else if (fieldName === 'vin') {

            this.vin = value;

        }

    }


    // ============================================================
    // STATE CHANGE
    // ============================================================

    handleStateChange(event) {

        this.state =
            event.detail.value;

    }

    // ============================================================
// QUOTE TYPE CHANGE
// ============================================================

async handleQuoteTypeChange(event) {
    this.quoteType = event.detail.value;

    // Clear selections dependent on Quote Type.
    this.client = '';
    this.product = '';
    this.selectedOptions = [];

    // Clear dependent dropdown options.
    this.clientOptions = [];
    this.productOptions = [];
    this.optionOptions = [];
    this.showOptionsDropdown = false;

    // Clear quote-type-specific fields.
    this.residenceType = '';
    this.residenceTypeOptions = [];
    this.saleOdometer = '';
    this.vin = '';

    // Clear the corresponding UI input values.
    const fields = this.template.querySelectorAll('lightning-input');

    fields.forEach(field => {
        if (
            field.name === 'saleOdometer' ||
            field.name === 'vin'
        ) {
            field.value = null;
        }
    });

    // Load clients matching the selected Quote Type.
    await this.loadClients();
}



// ============================================================
// RESIDENCE TYPE CHANGE
// ============================================================

handleResidenceTypeChange(event) {
    this.residenceType = event.detail.value;
}


    // ============================================================
    // OPTIONS DROPDOWN
    // ============================================================

    toggleOptionsDropdown() {

        if (this.isOptionsDisabled) {
            return;
        }

        this.showOptionsDropdown =
            !this.showOptionsDropdown;

    }


    // ============================================================
    // OPTION CHANGE
    // ============================================================

    handleOptionChange(event) {

        const selectedValue =
            event.target.value;

        const checked =
            event.target.checked;

        /*
         * Update selected option list.
         */

        if (checked) {

            if (!this.selectedOptions.includes(selectedValue)) {

                this.selectedOptions = [
                    ...this.selectedOptions,
                    selectedValue
                ];

            }

        } else {

            this.selectedOptions =
                this.selectedOptions.filter(
                    option => option !== selectedValue
                );

        }


        /*
         * Update visual checkbox state.
         */

        this.optionOptions =
            this.optionOptions.map(option => {

                if (option.value === selectedValue) {

                    return {
                        ...option,
                        checked: checked
                    };

                }

                return option;

            });

    }


    // ============================================================
    // GET QUOTES
    // ============================================================

    async handleGetQuotes() {

        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;

        try {

            const result =
                await getQuotes({
                     quoteType: this.quoteType,

                    client: this.client,

                    product: this.product,

                    saleOdometer:
                        this.saleOdometer,

                    state:
                        this.state,

                    vin:
                        this.vin,

                    options:
                        this.selectedOptions,
                    residenceType:
                    this.residenceType

                });


            /*
             * MRT3-93 will use these quote results.
             *
             * For now we keep the results in session storage
             * and navigate to the Quote Results component/page.
             */

            sessionStorage.setItem(
                'internalQuoteResults',
                JSON.stringify(result || [])
            );


            sessionStorage.setItem(
                'internalQuoteRequest',
                JSON.stringify({
                    quoteType: this.quoteType,

                    client: this.client,

                    product: this.product,

                    saleOdometer:
                        this.saleOdometer,

                    state:
                        this.state,

                    vin:
                        this.vin,

                    options:
                        this.selectedOptions,
                    residenceType: this.residenceType

                })
            );


            this.dispatchEvent(
                new CustomEvent(
                    'quotesretrieved',
                    {
                        detail: {
                            quotes: result || []
                        }
                    }
                )
            );


            this.showSuccess(
                'Quotes retrieved successfully.'
            );


        } catch (error) {

            this.showError(
                'Unable to retrieve quotes',
                this.getErrorMessage(error)
            );

        } finally {

            this.isLoading = false;

        }
    }


  // ============================================================
// FORM VALIDATION
// ============================================================
/*
validateForm() {
    let isValid = true;

    // Validate Quote Type
    if (!this.quoteType) {
        isValid = false;
    }

    // Validate common required fields
    const commonFields = [
        'client',
        'product',
        'state'
    ];

    commonFields.forEach(fieldName => {
        const field = this.template.querySelector(
            `[name="${fieldName}"]`
        );

        if (!field || !field.value) {
            if (field) {
                field.reportValidity();
            }
            isValid = false;
        }
    });

    // Validate Auto-specific fields
    if (
        this.quoteType &&
        this.quoteType.toLowerCase() === 'auto'
    ) {
        ['saleOdometer', 'vin'].forEach(fieldName => {
            const field = this.template.querySelector(
                `[name="${fieldName}"]`
            );

            if (!field || !field.value || !field.value.trim()) {
                if (field) {
                    field.reportValidity();
                }
                isValid = false;
            }
        });
    }

    // Home Warranty: Residence Type is optional.
    // Do not block submission if it is blank.

    if (!isValid) {
        this.showError(
            'Missing Information',
            'Please complete all required fields for the selected quote type.'
        );
    }

    return isValid;
}*/


validateForm() {
    console.log('Quote Type:', this.quoteType);
    console.log('Client:', this.client);
    console.log('Product:', this.product);
    console.log('State:', this.state);
    console.log('Sale Odometer:', this.saleOdometer);
    console.log('VIN:', this.vin);
    console.log('Residence Type:', this.residenceType);

    const missingFields = [];

    // Common required fields
    if (!this.quoteType) {
        missingFields.push('Quote Type');
    }

    if (!this.client) {
        missingFields.push('Client');
    }

    if (!this.product) {
        missingFields.push('Product');
    }

    if (!this.state) {
        missingFields.push('State');
    }

    // Auto-specific required fields
    if (this.isAuto) {
        if (!String(this.saleOdometer ?? '').trim()) {
            missingFields.push('Sale Odometer');
        }

        if (!String(this.vin ?? '').trim()) {
            missingFields.push('VIN');
        }
    }

    // Home Warranty-specific required field
    if (this.isHomeWarranty && !this.residenceType) {
        missingFields.push('Residence Type');
    }

    if (missingFields.length > 0) {
        this.showError(
            'Missing Information',
            'Please complete: ' + missingFields.join(', ') + '.'
        );

        return false;
    }

    return true;
}


    // ============================================================
    // RESET
    // ============================================================


handleReset() {
    this.quoteType = '';
    this.client = '';
    this.product = '';
    this.saleOdometer = '';
    this.state = '';
    this.vin = '';
    this.residenceType = '';
    this.residenceTypeOptions = [];

    this.selectedOptions = [];

    this.clientOptions = [];
    this.productOptions = [];
    this.optionOptions = [];

    this.showOptionsDropdown = false;

    const fields = this.template.querySelectorAll(
        'lightning-input, lightning-combobox'
    );

    fields.forEach(field => {
        if (field.type === 'checkbox') {
            field.checked = false;
        } else {
            field.value = null;
        }
    });
}




    // ============================================================
    // GETTERS
    // ============================================================

    get isProductDisabled() {

        return !this.client ||
            this.isLoading;
    }


    get isOptionsDisabled() {

        return !this.product ||
            this.isLoading;
    }


    get hasOptions() {

        return this.optionOptions &&
            this.optionOptions.length > 0;
    }


    get optionsDisplayText() {

        if (!this.selectedOptions ||
            this.selectedOptions.length === 0) {

            return 'Select Options';

        }

        return `${this.selectedOptions.length} option(s) selected`;
    }


    get optionsTextClass() {

        if (!this.selectedOptions ||
            this.selectedOptions.length === 0) {

            return 'placeholder-text';

        }

        return 'selected-options-text';
    }


    get isAuto() {  
    return this.quoteType === 'Auto';
    }

    get isHomeWarranty() {
        return this.quoteType === 'Home';
    }


    // ============================================================
    // TOASTS
    // ============================================================

    showSuccess(message) {

        this.dispatchEvent(
            new ShowToastEvent({

                title: 'Success',

                message: message,

                variant: 'success'

            })
        );

    }


    showError(title, message) {

        this.dispatchEvent(
            new ShowToastEvent({

                title: title,

                message: message,

                variant: 'error'

            })
        );

    }


    // ============================================================
    // ERROR MESSAGE
    // ============================================================

    getErrorMessage(error) {

        if (!error) {
            return 'Unknown error occurred.';
        }

        if (
            error.body &&
            error.body.message
        ) {

            return error.body.message;

        }

        if (error.message) {

            return error.message;

        }

        return 'Unknown error occurred.';

    }

}