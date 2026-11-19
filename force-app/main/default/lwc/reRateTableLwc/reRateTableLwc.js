import { LightningElement, track } from 'lwc';
import { OmniscriptBaseMixin } from 'omnistudio/omniscriptBaseMixin';
import getInitialContractData from '@salesforce/apex/ReRateLWCController.getInitialContractData';
import getEligibleMatrixRows from '@salesforce/apex/ReRateLWCController.getEligibleMatrixRows';
import getOptionsForCoverage from '@salesforce/apex/ReRateLWCController.getOptionsForCoverage';

export default class ReRateTableLwc extends OmniscriptBaseMixin(LightningElement) {
    @track coverageOptions = [];
    @track monthOptions = [];
    @track mileOptions = [];
    @track deductibleOptions = [];
    @track optionItems = [];

    @track selectedCoverageId = '';
    @track selectedCoverageName = '';
    // @track saleMileage = 0; // Commented out default 0 so Sale Odometer starts blank
    @track saleMileage = null;
    @track selectedMonths = '';
    @track selectedMiles = '';
    @track selectedDeductible = '';
    @track selectedOptions = [];
    @track activeOptionSet = '';
    @track noMatchingRowsWarning = false;

    contractContext = {};
    eligibleMatrixRows = [];
    mileageDebounceTimeout;

    get isAutoProduct() {
        return this.contractContext.productType !== 'Home';
    }

    get hasOptionItems() {
        return this.optionItems && this.optionItems.length > 0;
    }

    connectedCallback() {
        const contextId = this.omniJsonData ? (this.omniJsonData.ContextId || this.omniJsonData.contractId) : null;
        if (contextId) {
            this.loadInitialData(contextId);
        }
    }

    async loadInitialData(contractId) {
        try {
            const data = await getInitialContractData({ contractId: contractId });
            this.contractContext = data;
            this.coverageOptions = data.coverageOptions || [];
            this.activeOptionSet = data.optionSet || '';

            const initialOpts = data.initialAvailableOptions || [];
            this.optionItems = initialOpts.map(opt => ({
                label: opt.label,
                value: opt.value,
                checked: false
            }));

            /* --- AUTO-POPULATION FROM EXISTING CONTRACT ON LOAD (COMMENTED OUT) ---
            this.saleMileage = data.saleMileage || 0;
            this.selectedCoverageId = data.currentCoverageId || '';
            this.selectedCoverageName = data.currentCoverageName || '';
            if (data.currentOptions) {
                const savedOpts = data.currentOptions.split(';').map(s => s.trim()).filter(Boolean);
                const validValues = this.optionItems.map(o => o.value);
                this.selectedOptions = savedOpts.filter(val => validValues.includes(val));
                this.optionItems = this.optionItems.map(item => ({
                    ...item,
                    checked: this.selectedOptions.includes(item.value)
                }));
            }

            if (this.selectedCoverageId) {
                await this.loadMatrixRows(true);
            }
            ------------------------------------------------------------------------- */

            this.syncToOmniScript();
        } catch (error) {
            console.error('Error loading initial contract data:', error);
        }
    }

    async loadMatrixRows(isInitialLoad = false) {
        if (!this.selectedCoverageId) return;

        try {
            this.eligibleMatrixRows = await getEligibleMatrixRows({
                rateSet: this.contractContext.rateSet,
                coverageId: this.selectedCoverageId,
                saleMileage: this.saleMileage !== null && this.saleMileage !== '' ? Number(this.saleMileage) : 0,
                vehicleAge: this.contractContext.vehicleAge,
                rateClass: this.contractContext.rateClass,
                saleDate: this.contractContext.saleDate
            });

            this.noMatchingRowsWarning = this.eligibleMatrixRows.length === 0;
            this.buildMonthOptions(isInitialLoad);
            this.syncToOmniScript();
        } catch (error) {
            console.error('Error loading matrix rows:', error);
        }
    }

    async refreshOptionsForCoverage() {
        if (!this.selectedCoverageId) return;

        try {
            const optResult = await getOptionsForCoverage({
                clientName: this.contractContext.clientName,
                productName: this.contractContext.productName,
                defaultOptionSet: this.contractContext.optionSet,
                coverageId: this.selectedCoverageId,
                saleDate: this.contractContext.saleDate
            });

            this.activeOptionSet = optResult.activeOptionSet || '';
            const fetchedOptions = optResult.availableOptions || [];
            const validValues = fetchedOptions.map(o => o.value);

            // Restrict selection strictly to options valid in the updated Option Set
            this.selectedOptions = this.selectedOptions.filter(val => validValues.includes(val));

            this.optionItems = fetchedOptions.map(opt => ({
                label: opt.label,
                value: opt.value,
                checked: this.selectedOptions.includes(opt.value)
            }));

            this.syncToOmniScript();
        } catch (error) {
            console.error('Error refreshing options for coverage:', error);
        }
    }

    buildMonthOptions(isInitialLoad = false) {
        const uniqueMonths = [...new Set(this.eligibleMatrixRows.map(r => r.termMonths).filter(Boolean))];
        uniqueMonths.sort((a, b) => Number(a) - Number(b));
        this.monthOptions = uniqueMonths.map(m => ({ label: m, value: m }));

        /* --- AUTO-POPULATION OF TERM MONTHS (COMMENTED OUT) ---
        if (isInitialLoad && this.contractContext.currentTermMonths && uniqueMonths.includes(this.contractContext.currentTermMonths)) {
            this.selectedMonths = this.contractContext.currentTermMonths;
        } else if (!uniqueMonths.includes(this.selectedMonths)) {
            this.selectedMonths = uniqueMonths.length === 1 ? uniqueMonths[0] : '';
        }
        --------------------------------------------------------- */
        if (!uniqueMonths.includes(this.selectedMonths)) {
            this.selectedMonths = '';
        }

        if (this.isAutoProduct) {
            this.buildMileOptions(isInitialLoad);
        } else {
            this.selectedMiles = '';
            this.mileOptions = [];
            this.buildDeductibleOptions(isInitialLoad);
        }
    }

    buildMileOptions(isInitialLoad = false) {
        const filteredByMonth = this.selectedMonths
            ? this.eligibleMatrixRows.filter(r => r.termMonths === this.selectedMonths)
            : [];

        const uniqueMiles = [...new Set(filteredByMonth.map(r => r.termMiles).filter(Boolean))];
        uniqueMiles.sort((a, b) => Number(a) - Number(b));
        this.mileOptions = uniqueMiles.map(m => ({ label: m, value: m }));

        /* --- AUTO-POPULATION OF TERM MILES (COMMENTED OUT) ---
        if (isInitialLoad && this.contractContext.currentTermMiles && uniqueMiles.includes(this.contractContext.currentTermMiles)) {
            this.selectedMiles = this.contractContext.currentTermMiles;
        } else if (!uniqueMiles.includes(this.selectedMiles)) {
            this.selectedMiles = uniqueMiles.length === 1 ? uniqueMiles[0] : '';
        }
        -------------------------------------------------------- */
        if (!uniqueMiles.includes(this.selectedMiles)) {
            this.selectedMiles = '';
        }

        this.buildDeductibleOptions(isInitialLoad);
    }

    buildDeductibleOptions(isInitialLoad = false) {
        let filteredRows = this.selectedMonths
            ? this.eligibleMatrixRows.filter(r => r.termMonths === this.selectedMonths)
            : [];

        if (this.isAutoProduct) {
            filteredRows = this.selectedMiles
                ? filteredRows.filter(r => r.termMiles === this.selectedMiles)
                : [];
        }

        const uniqueDeductibles = [...new Set(filteredRows.map(r => r.deductible).filter(Boolean))];
        uniqueDeductibles.sort((a, b) => Number(a) - Number(b));
        this.deductibleOptions = uniqueDeductibles.map(d => ({ label: '$' + d, value: d }));

        /* --- AUTO-POPULATION OF DEDUCTIBLE (COMMENTED OUT) ---
        if (isInitialLoad && this.contractContext.currentDeductible && uniqueDeductibles.includes(this.contractContext.currentDeductible)) {
            this.selectedDeductible = this.contractContext.currentDeductible;
        } else if (!uniqueDeductibles.includes(this.selectedDeductible)) {
            this.selectedDeductible = uniqueDeductibles.length === 1 ? uniqueDeductibles[0] : '';
        }
        -------------------------------------------------------- */
        if (!uniqueDeductibles.includes(this.selectedDeductible)) {
            this.selectedDeductible = '';
        }
    }

    async handleCoverageChange(event) {
        this.selectedCoverageId = event.detail.value;
        const found = this.coverageOptions.find(opt => opt.value === this.selectedCoverageId);
        this.selectedCoverageName = found ? found.label : '';
        this.selectedMonths = '';
        this.selectedMiles = '';
        this.selectedDeductible = '';

        await Promise.all([
            this.loadMatrixRows(false),
            this.refreshOptionsForCoverage()
        ]);
    }

    handleMileageChange(event) {
        this.saleMileage = event.detail.value !== '' && event.detail.value !== null ? Number(event.detail.value) : null;
        window.clearTimeout(this.mileageDebounceTimeout);
        this.mileageDebounceTimeout = window.setTimeout(() => {
            this.loadMatrixRows(false);
        }, 300);
    }

    handleMonthChange(event) {
        this.selectedMonths = event.detail.value;
        this.selectedMiles = '';
        this.selectedDeductible = '';
        if (this.isAutoProduct) {
            this.buildMileOptions(false);
        } else {
            this.buildDeductibleOptions(false);
        }
        this.syncToOmniScript();
    }

    handleMileChange(event) {
        this.selectedMiles = event.detail.value;
        this.selectedDeductible = '';
        this.buildDeductibleOptions(false);
        this.syncToOmniScript();
    }

    handleDeductibleChange(event) {
        this.selectedDeductible = event.detail.value;
        this.syncToOmniScript();
    }

    handleOptionChange(event) {
        const optionVal = event.target.name;
        const isChecked = event.target.checked;

        if (isChecked) {
            if (!this.selectedOptions.includes(optionVal)) {
                this.selectedOptions = [...this.selectedOptions, optionVal];
            }
        } else {
            this.selectedOptions = this.selectedOptions.filter(val => val !== optionVal);
        }

        this.optionItems = this.optionItems.map(item => ({
            ...item,
            checked: this.selectedOptions.includes(item.value)
        }));

        this.syncToOmniScript();
    }

    syncToOmniScript() {
        const existingStepData = (this.omniJsonData && this.omniJsonData.ReRateFieldsForNotSecureOneProducts)
            ? this.omniJsonData.ReRateFieldsForNotSecureOneProducts
            : {};

        const option1Formatted = this.selectedOptions.length > 0 ? this.selectedOptions.join(';') : null;

        const updatedStepNode = {
            ...existingStepData,
            Coverage_Name_NonSecureOne: this.selectedCoverageId,
            Coverage_Label_NonSecureOne: this.selectedCoverageName,
            Sale_Mileage_NonSecureOne: this.isAutoProduct && this.saleMileage !== '' && this.saleMileage !== null ? Number(this.saleMileage) : null,
            Term_Months_NonSecureOne: this.selectedMonths !== '' ? Number(this.selectedMonths) : null,
            Term_Miles_NonSecureOne: this.isAutoProduct && this.selectedMiles !== '' ? Number(this.selectedMiles) : null,
            Deductible__c: this.selectedDeductible !== '' ? Number(this.selectedDeductible) : null,
            Option_1_NonSecureOne: option1Formatted,
            Options_Sets_NonSecureOne: this.activeOptionSet || null,
            IsCommercial: this.selectedOptions.includes('Commercial Use')
        };

        this.omniApplyCallResp({
            Coverage_Name_NonSecureOne: this.selectedCoverageId,
            ReRateFieldsForNotSecureOneProducts: updatedStepNode
        });
    }
}