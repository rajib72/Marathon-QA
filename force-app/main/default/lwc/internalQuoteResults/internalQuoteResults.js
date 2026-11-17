import { LightningElement, track } from 'lwc';

export default class InternalQuoteResults extends LightningElement {

    @track request = {};
    @track quotes = [];

    isLoading = true;
    errorMessage = '';

    columns = [
        {
            label: 'Dealer Program ID',
            fieldName: 'dealerProgramId',
            type: 'text'
        },
        {
            label: 'Product',
            fieldName: 'product',
            type: 'text'
        },
        {
            label: 'Coverage Level',
            fieldName: 'coverageLevel',
            type: 'text'
        },
        {
            label: 'New / Used',
            fieldName: 'newOrUsed',
            type: 'text'
        },
        {
            label: 'Contract Term (Months)',
            fieldName: 'contractTermMonths',
            type: 'number'
        },
        {
            label: 'Contract Term (Mileage)',
            fieldName: 'contractTermMileage',
            type: 'number'
        },
        {
            label: 'Validation Days',
            fieldName: 'validationDays',
            type: 'number'
        },
        {
            label: 'Validation Miles',
            fieldName: 'validationMiles',
            type: 'number'
        },
        {
            label: 'Deductible',
            fieldName: 'deductible',
            type: 'currency'
        },
        {
            label: 'Net Dealer Cost',
            fieldName: 'dealerCost',
            type: 'currency'
        },
        {
            label: 'Monthly Dealer Cost',
            fieldName: 'monthlyDealerCost',
            type: 'currency'
        },
        {
            label: 'Surcharges',
            fieldName: 'surcharges',
            type: 'text'
        },
        {
            label: 'Rate Class',
            fieldName: 'rateClass',
            type: 'text'
        },
        {
            label: 'Water Well Pump',
            fieldName: 'waterWellPump',
            type: 'text'
        },
        {
            label: 'Refrigerator Ice Maker',
            fieldName: 'refrigeratorIceMaker',
            type: 'text'
        },
        {
            label: 'Stand Alone Ice Maker',
            fieldName: 'standAloneIceMaker',
            type: 'text'
        },
        {
            label: 'Secondary Refrigerator',
            fieldName: 'secondaryRefrigerator',
            type: 'text'
        },
        {
            label: 'Secondary Freezer',
            fieldName: 'secondaryFreezer',
            type: 'text'
        },
        {
            label: 'Swimming Pool',
            fieldName: 'swimmingPool',
            type: 'text'
        },
        {
            label: 'Spa',
            fieldName: 'spa',
            type: 'text'
        },
        {
            label: 'Clothes Washer / Dryer',
            fieldName: 'clothesWasherDryer',
            type: 'text'
        },
        {
            label: 'Central Vac',
            fieldName: 'centralVac',
            type: 'text'
        },
        {
            label: 'Garage Door Opener',
            fieldName: 'garageDoorOpener',
            type: 'text'
        }
    ];

    connectedCallback() {
        this.loadResults();
    }

    loadResults() {
        try {
            const storedRequest =
                sessionStorage.getItem('internalQuoteRequest');

            const storedResults =
                sessionStorage.getItem('internalQuoteResults');

            if (storedRequest) {
                this.request = JSON.parse(storedRequest);
            }

            if (!storedResults) {
                this.quotes = [];
                return;
            }

            const parsedResults = JSON.parse(storedResults);

            // Supports either a direct list or a response containing quotes.
            let resultList = [];

            if (Array.isArray(parsedResults)) {
                resultList = parsedResults;
            } else if (parsedResults && Array.isArray(parsedResults.quotes)) {
                resultList = parsedResults.quotes;
            }

            // Handle a response containing an error.
            if (parsedResults && !Array.isArray(parsedResults)) {
                if (
                    parsedResults.status &&
                    Number(parsedResults.status) !== 200
                ) {
                    this.errorMessage =
                        parsedResults.error || 'Unable to retrieve quotes.';
                    return;
                }

                if (parsedResults.error) {
                    this.errorMessage = parsedResults.error;
                    return;
                }
            }

            this.quotes = resultList
                .filter(item => item && Object.keys(item).length > 0)
                .map((item, index) => ({
                    ...item,
                    rowKey: String(index + 1)
                }));

        } catch (error) {
            this.errorMessage =
                'Unable to load quote results. Please retrieve the quotes again.';

            // eslint-disable-next-line no-console
            console.error('Quote results loading error:', error);

        } finally {
            this.isLoading = false;
        }
    }

    get hasRequest() {
        return this.request &&
            Object.keys(this.request).length > 0;
    }

    get hasQuotes() {
        return this.quotes && this.quotes.length > 0;
    }

    get quoteCount() {
        return this.quotes.length;
    }

    get showNoResults() {
        return !this.isLoading &&
            !this.errorMessage &&
            !this.hasQuotes;
    }

    get isAuto() {
        return this.request?.quoteType === 'Auto';
    }

    get isHome() {
        return this.request?.quoteType === 'Home';
    }

    get hasOptions() {
        return Array.isArray(this.request?.options) &&
            this.request.options.length > 0;
    }

    get optionsDisplay() {
        return this.request?.options
            ? this.request.options.join(', ')
            : '';
    }
}