import {
    LightningElement,
    track
} from 'lwc';

import getClients
    from '@salesforce/apex/InternalQuoteRequestController.getClients';

import getProducts
    from '@salesforce/apex/InternalQuoteRequestController.getProducts';

import getOptions
    from '@salesforce/apex/InternalQuoteRequestController.getOptions';

import getQuotes
    from '@salesforce/apex/InternalQuoteRequestController.getQuotes';

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


    // ============================================================
    // DROPDOWN OPTIONS
    // ============================================================

    @track clientOptions = [];

    @track productOptions = [];

    @track optionOptions = [];

    @track stateOptions = [];


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

        this.initializeStateOptions();

        this.loadClients();

    }


    // ============================================================
    // STATE OPTIONS
    // ============================================================

    initializeStateOptions() {

        const states = [

            {
                label: 'AL',
                value: 'AL'
            },
            {
                label: 'AK',
                value: 'AK'
            },
            {
                label: 'AZ',
                value: 'AZ'
            },
            {
                label: 'AR',
                value: 'AR'
            },
            {
                label: 'CA',
                value: 'CA'
            },
            {
                label: 'CO',
                value: 'CO'
            },
            {
                label: 'CT',
                value: 'CT'
            },
            {
                label: 'DE',
                value: 'DE'
            },
            {
                label: 'FL',
                value: 'FL'
            },
            {
                label: 'GA',
                value: 'GA'
            },
            {
                label: 'HI',
                value: 'HI'
            },
            {
                label: 'ID',
                value: 'ID'
            },
            {
                label: 'IL',
                value: 'IL'
            },
            {
                label: 'IN',
                value: 'IN'
            },
            {
                label: 'IA',
                value: 'IA'
            },
            {
                label: 'KS',
                value: 'KS'
            },
            {
                label: 'KY',
                value: 'KY'
            },
            {
                label: 'LA',
                value: 'LA'
            },
            {
                label: 'ME',
                value: 'ME'
            },
            {
                label: 'MD',
                value: 'MD'
            },
            {
                label: 'MA',
                value: 'MA'
            },
            {
                label: 'MI',
                value: 'MI'
            },
            {
                label: 'MN',
                value: 'MN'
            },
            {
                label: 'MS',
                value: 'MS'
            },
            {
                label: 'MO',
                value: 'MO'
            },
            {
                label: 'MT',
                value: 'MT'
            },
            {
                label: 'NE',
                value: 'NE'
            },
            {
                label: 'NV',
                value: 'NV'
            },
            {
                label: 'NH',
                value: 'NH'
            },
            {
                label: 'NJ',
                value: 'NJ'
            },
            {
                label: 'NM',
                value: 'NM'
            },
            {
                label: 'NY',
                value: 'NY'
            },
            {
                label: 'NC',
                value: 'NC'
            },
            {
                label: 'ND',
                value: 'ND'
            },
            {
                label: 'OH',
                value: 'OH'
            },
            {
                label: 'OK',
                value: 'OK'
            },
            {
                label: 'OR',
                value: 'OR'
            },
            {
                label: 'PA',
                value: 'PA'
            },
            {
                label: 'RI',
                value: 'RI'
            },
            {
                label: 'SC',
                value: 'SC'
            },
            {
                label: 'SD',
                value: 'SD'
            },
            {
                label: 'TN',
                value: 'TN'
            },
            {
                label: 'TX',
                value: 'TX'
            },
            {
                label: 'UT',
                value: 'UT'
            },
            {
                label: 'VT',
                value: 'VT'
            },
            {
                label: 'VA',
                value: 'VA'
            },
            {
                label: 'WA',
                value: 'WA'
            },
            {
                label: 'WV',
                value: 'WV'
            },
            {
                label: 'WI',
                value: 'WI'
            },
            {
                label: 'WY',
                value: 'WY'
            }

        ];

        this.stateOptions = states;
    }


    // ============================================================
    // LOAD CLIENTS
    // ============================================================

    async loadClients() {

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

                    client: this.client,

                    product: this.product,

                    saleOdometer:
                        this.saleOdometer,

                    state:
                        this.state,

                    vin:
                        this.vin,

                    options:
                        this.selectedOptions

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

                    client: this.client,

                    product: this.product,

                    saleOdometer:
                        this.saleOdometer,

                    state:
                        this.state,

                    vin:
                        this.vin,

                    options:
                        this.selectedOptions

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

    validateForm() {

        let isValid = true;

        const requiredFields =
            this.template.querySelectorAll(
                'lightning-input, lightning-combobox'
            );

        requiredFields.forEach(field => {

            if (
                field.name === 'saleOdometer' ||
                field.name === 'vin' ||
                field.name === 'client' ||
                field.name === 'product' ||
                field.name === 'state'
            ) {

                if (!field.value) {

                    field.reportValidity();

                    isValid = false;

                }

            }

        });


        if (!isValid) {

            this.showError(
                'Missing Information',
                'Please complete all required fields.'
            );

        }

        return isValid;
    }


    // ============================================================
    // RESET
    // ============================================================

   
handleReset() {
    this.client = '';
    this.product = '';
    this.saleOdometer = '';
    this.state = '';
    this.vin = '';

    this.selectedOptions = [];
    this.productOptions = [];
    this.optionOptions = [];

    this.showOptionsDropdown = false;

    // Clear the actual input values in the UI.
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