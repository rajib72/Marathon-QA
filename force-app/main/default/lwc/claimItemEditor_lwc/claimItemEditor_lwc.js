import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USER_PROFILE_NAME_FIELD from '@salesforce/schema/User.Profile.Name';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    refreshTab
} from 'lightning/platformWorkspaceApi';
import LightningConfirm from 'lightning/confirm';
import VendorPricingDemoModal from 'c/vendorPricingDemoModal';

import CLAIM_ITEM_OBJECT from '@salesforce/schema/ClaimItem';
import STATUS_FIELD from '@salesforce/schema/ClaimItem.Status__c';
import CATEGORY_FIELD from '@salesforce/schema/ClaimItem.Category';
import DETAIL_TYPE_FIELD from '@salesforce/schema/ClaimItem.Detail_Type__c';
import REASON_FIELD from '@salesforce/schema/ClaimItem.Reason__c';

import getClaimItems from '@salesforce/apex/ClaimItemGridController.getClaimItems';
import getClaimDefaultDetails from '@salesforce/apex/ClaimItemGridController.getClaimDefaultDetails';
import searchPayeeAccounts from '@salesforce/apex/ClaimItemGridController.searchPayeeAccounts';
import searchCoverageLevelDetails from '@salesforce/apex/ClaimItemGridController.searchCoverageLevelDetails';
import saveClaimItems from '@salesforce/apex/ClaimItemGridController.saveClaimItems';
import deleteClaimItem from '@salesforce/apex/ClaimItemGridController.deleteClaimItem';

const SEARCH_DELAY_MS = 300;
const INACTIVE_CONTRACT_STATUSES = ['In Waiting', 'Cancelled', 'Expired'];

const INSPECTION_INVOICE_REQUIRED_STATUSES = [
    'Authorized',
    'Approved to Pay',
    'Paid'
];

// Preserves the current behavior if Reason__c metadata cannot be loaded.
const REASON_FALLBACK_OPTIONS = Object.freeze([
    { label: 'Waiting for Maintenance Records', value: 'Waiting for Maintenance Records' },
    { label: 'Waiting for Inspection', value: 'Waiting for Inspection' },
    { label: 'In Process (No Auth Given)', value: 'In Process (No Auth Given)' },
    { label: 'Invoice Received', value: 'Invoice Received' },
    { label: 'Invoice Received (OVR)', value: 'Invoice Received (OVR)' },
    { label: 'Waiting on Final Invoice', value: 'Waiting on Final Invoice' },
    { label: 'Waiting on Final Invoice (OVR)', value: 'Waiting on Final Invoice (OVR)' },
    { label: 'Pre-Existing Condition', value: 'Pre-Existing Condition' },
    { label: 'Party Warranty', value: 'Party Warranty' },
    { label: 'Continued Operation', value: 'Continued Operation' },
    { label: 'Loss of Fluids', value: 'Loss of Fluids' },
    { label: 'Modified Vehicle', value: 'Modified Vehicle' },
    { label: 'Misuse/Abuse', value: 'Misuse/Abuse' },
    { label: 'Lack of Maintenance', value: 'Lack of Maintenance' },
    { label: 'Inoperative Odometer', value: 'Inoperative Odometer' },
    { label: 'Commercial Usage', value: 'Commercial Usage' },
    { label: 'Covered Elsewhere', value: 'Covered Elsewhere' },
    { label: 'Factory Warranty Coverage', value: 'Factory Warranty Coverage' },
    { label: 'No Prior Auth', value: 'No Prior Auth' },
    { label: 'Non-Covered Part', value: 'Non-Covered Part' },
    { label: 'Limit of Liability Met', value: 'Limit of Liability Met' },
    { label: 'Expired Contract-Time', value: 'Expired Contract-Time' },
    { label: 'Expired Contract-Mileage', value: 'Expired Contract-Mileage' },
    { label: 'Customer Declined Repairs', value: 'Customer Declined Repairs' },
    { label: 'Shop Declined Repair', value: 'Shop Declined Repair' },
    { label: 'Relocated Vehicle', value: 'Relocated Vehicle' },
    { label: 'Inactivity', value: 'Inactivity' }
]);

export default class ClaimItemEditor_lwc extends LightningElement {
    @api recordId;
    // Feature is OFF by default; enable only on the QA Claim record page for a controlled demo.
    @api enablePricingDemo = false;

    @wire(IsConsoleNavigation)
    isConsoleNavigation;

    data = [];
    originalData = [];
    selectedRows = [];
    validationErrors = [];

    isLoading = false;
    isDirty = false;
    isAllSelected = false;

    isEditorExpanded = false;

    claimStatus;
    contractStatus;
    repairShopAccountId;
    repairShopAccountName;
    claimLaborRate;
    policyRecordTypeName;
    claimLaborTaxRate;
    claimPartsTaxRate;
    currentUserProfileName;

    statusOptions = [];
    categoryOptions = [];
    detailTypeOptions = [];
    reasonOptions = [...REASON_FALLBACK_OPTIONS];

    wiredResult;
    wiredClaimDefaultResult;
    flowInputVariables = [];

    showPicklistPopup = false;
    popupRowId;
    popupField;
    popupSelectedValue;
    popupOptions = [];
    popupFieldLabel;

    showLookupPopup = false;
    lookupRowId;
    lookupSearchTerm = '';
    lookupResults = [];
    lookupSelectedId = '';
    lookupSelectedName = '';
    isLookupSearching = false;
    lookupSearchTimer;
    lookupRequestSequence = 0;

    showPayeeLookupPopup = false;
    payeeRowId;
    payeeSearchTerm = '';
    payeeResults = [];
    payeeSelectedId = '';
    payeeSelectedName = '';
    isPayeeSearching = false;
    payeeSearchTimer;
    payeeRequestSequence = 0;

    showBokFlow = false;
    showAuthorizeAllLines = false;
    showConfirmAllocation = false;

    showMassUpdateModal = false;
    massStatus = '';
    massReason = '';
    massCategory = '';

    showAddJobDetailModal = false;
    selectedJobNumber = '';

    newRowCounter = 0;

    // UI demonstration only. No API callout or pricing DML is made by this component.
    get isVendorPricingPreviewDisabled() {
        return !this.enablePricingDemo || this.isLoading ||
            !this.isEditorExpanded ||
            !this.data.some((row) =>
                this.selectedRows.includes(row.uniqueKey) && row.Detail_Type__c === 'Part'
            );
    }

    get hasRows() {
        return this.data.length > 0;
    }

    get hasValidationErrors() {
        return this.validationErrors.length > 0;
    }

    get rowCountLabel() {
        const count = this.data.length;
        return `${count} ${count === 1 ? 'item' : 'items'}`;
    }

    get selectedCountLabel() {
        const count = this.selectedRows.length;
        return `${count} selected`;
    }

    get bulkUpdateLabel() {
        return this.selectedRows.length > 0
            ? `Bulk Update (${this.selectedRows.length})`
            : 'Bulk Update';
    }

    get isBulkUpdateDisabled() {

        /*
         * Bulk Update should remain clickable
         * when editor is collapsed because first click
         * is used only to expand the editor.
         */
        if (!this.isEditorExpanded) {
            return this.isLoading;
        }


        return (
            this.isLoading ||
            this.selectedRows.length === 0
        );
    }

    get showRequestInspection() {
        return Boolean(
            this.currentUserProfileName &&
            this.currentUserProfileName !== 'Roadside'
        );
    }

    get existingJobOptions() {
        const uniqueJobs = new Map();

        this.data.forEach((row) => {
            const jobNumber = String(row.Job_Number__c || '').trim();
            if (jobNumber && !uniqueJobs.has(jobNumber)) {
                uniqueJobs.set(jobNumber, {
                    label: `Job ${jobNumber}`,
                    value: jobNumber
                });
            }
        });

        return [...uniqueJobs.values()].sort((first, second) => {
            const firstNumber = Number(first.value);
            const secondNumber = Number(second.value);

            if (!Number.isNaN(firstNumber) && !Number.isNaN(secondNumber)) {
                return firstNumber - secondNumber;
            }

            return first.label.localeCompare(second.label);
        });
    }

    get isAddJobDetailDisabled() {
        /*
         * When the editor is collapsed, keep Add Job Detail clickable.
         * The first click is used to refresh the latest Claim Items and
         * expand the editor only. Once expanded, the existing rule remains:
         * at least one Job must exist before a Job Detail can be added.
         */
        if (!this.isEditorExpanded) {
            return this.isLoading;
        }

        return (
            this.isLoading ||
            this.existingJobOptions.length === 0
        );
    }

    get isAddJobDetailConfirmDisabled() {
        return !this.selectedJobNumber;
    }

    get isPartiallySelected() {
        return (
            this.data.length > 0 &&
            this.selectedRows.length > 0 &&
            this.selectedRows.length < this.data.length
        );
    }

    get hasLookupResults() {
        return this.lookupResults.length > 0;
    }

    get hasPayeeResults() {
        return this.payeeResults.length > 0;
    }

    get isLookupApplyDisabled() {
        return !this.lookupSelectedId;
    }

    get isPayeeApplyDisabled() {
        return !this.payeeSelectedId;
    }

    get isMassUpdateApplyDisabled() {
        return !(this.massStatus || this.massReason || this.massCategory);
    }

    get lookupSearchMessage() {
        const term = (this.lookupSearchTerm || '').trim();
        return term.length < 2
            ? 'Type at least 2 characters to search Loss Components.'
            : 'No matching Loss Components were found.';
    }

    get payeeSearchMessage() {
        const term = (this.payeeSearchTerm || '').trim();
        return term.length < 2
            ? 'Type at least 2 characters to search Account records.'
            : 'No matching Payees were found.';
    }

    renderedCallback() {
        const headerCheckbox = this.template.querySelector(
            'lightning-input[data-header-checkbox]'
        );

        if (headerCheckbox) {
            headerCheckbox.indeterminate = this.isPartiallySelected;
        }
    }

    disconnectedCallback() {
        window.clearTimeout(this.lookupSearchTimer);
        window.clearTimeout(this.payeeSearchTimer);
        this.lookupRequestSequence += 1;
        this.payeeRequestSequence += 1;
    }

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [USER_PROFILE_NAME_FIELD]
    })
    wiredCurrentUser({ data, error }) {
        if (data) {
            this.currentUserProfileName =
                getFieldValue(data, USER_PROFILE_NAME_FIELD);
        } else if (error) {
            this.currentUserProfileName = null;

            // eslint-disable-next-line no-console
            console.error(
                'Unable to determine current user profile.',
                error
            );
        }
    }

    @wire(getObjectInfo, { objectApiName: CLAIM_ITEM_OBJECT })
    claimItemObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$claimItemObjectInfo.data.defaultRecordTypeId',
        fieldApiName: DETAIL_TYPE_FIELD
    })
    wiredDetailTypePicklistValues({ data, error }) {
        if (data) {
            this.detailTypeOptions = this.mapPicklistValues(data.values);
        } else if (error) {
            this.showToast('Error', 'Error fetching Detail Type values.', 'error');
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$claimItemObjectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredStatusPicklistValues({ data, error }) {
        if (data) {
            this.statusOptions = this.mapPicklistValues(data.values);
        } else if (error) {
            this.showToast('Error', 'Error fetching Status values.', 'error');
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$claimItemObjectInfo.data.defaultRecordTypeId',
        fieldApiName: CATEGORY_FIELD
    })
    wiredCategoryPicklistValues({ data, error }) {
        if (data) {
            this.categoryOptions = this.mapPicklistValues(data.values);
        } else if (error) {
            this.showToast('Error', 'Error fetching Payee Type values.', 'error');
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$claimItemObjectInfo.data.defaultRecordTypeId',
        fieldApiName: REASON_FIELD
    })
    wiredReasonPicklistValues({ data, error }) {
        if (data) {
            this.reasonOptions = this.mapPicklistValues(data.values);
        } else if (error) {
            // Keep the existing hard-coded values as a compatibility fallback.
            // eslint-disable-next-line no-console
            console.error('Unable to load Reason__c metadata. Using fallback values.', error);
        }
    }

    /*@wire(getClaimDefaultDetails, { claimId: '$recordId' })
    wiredClaimDefaultDetails({ data, error }) {
        if (data) {
            this.claimStatus = data.claimStatus;
            this.contractStatus = data.contractStatus;
            this.claimLaborRate = data.claimLaborRate;
            this.policyRecordTypeName = data.policyRecordTypeName;
            this.repairShopAccountId = data.repairShopAccountId;
            this.repairShopAccountName = data.repairShopAccountName;
            this.claimLaborTaxRate = data.claimLaborTaxRate;
            this.claimPartsTaxRate = data.claimPartsTaxRate;

            this.recalculateAllRows();

            if (!this.isDirty) {
                this.originalData = this.cloneRows(this.data);
            }
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading Claim default details.', error);
        }
    }*/

    @wire(getClaimDefaultDetails, { claimId: '$recordId' })
    wiredClaimDefaultDetails(result) {
        this.wiredClaimDefaultResult = result;

        const { data, error } = result;

        if (data) {
            this.claimStatus = data.claimStatus;
            this.contractStatus = data.contractStatus;
            this.claimLaborRate = data.claimLaborRate;
            this.policyRecordTypeName = data.policyRecordTypeName;
            this.repairShopAccountId = data.repairShopAccountId;
            this.repairShopAccountName = data.repairShopAccountName;
            this.claimLaborTaxRate = data.claimLaborTaxRate;
            this.claimPartsTaxRate = data.claimPartsTaxRate;

            this.recalculateAllRows();

            if (!this.isDirty) {
                this.originalData = this.cloneRows(this.data);
            }
        } else if (error) {
            console.error(
                'Error loading Claim default details.',
                error
            );
        }
    }

    @wire(getClaimItems, { claimId: '$recordId' })
    wiredClaimItems(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.data = (data || []).map((row) => this.initializeRow(row));
            this.recalculateAllRows();
            this.originalData = this.cloneRows(this.data);
            this.selectedRows = [];
            this.isDirty = false;
            this.validationErrors = [];
            this.showAddJobDetailModal = false;
            this.selectedJobNumber = '';
            this.updateHeaderCheckboxState();
            this.restoreEditorStateAfterRefresh();

        } else if (error) {
            this.showToast('Error', 'Error loading Claim Items.', 'error');
            // eslint-disable-next-line no-console
            console.error('Error loading Claim Items.', error);
        }
    }

    mapPicklistValues(values = []) {
        return values.map((item) => ({
            label: item.label,
            value: item.value
        }));
    }

    cloneRows(rows) {
        return JSON.parse(JSON.stringify(rows || []));
    }

    initializeRow(row) {
        const initializedRow = {
            ...row,
            PayeeName: row.Payee_Name__r?.Name || '',
            PayeeRecordType: row.Payee_Name__r?.RecordType?.Name || '',
            CoverageLevelDetailName: row.Coverage_Level_Detail__r?.Name || '',
            uniqueKey: row.Id || `row-${Date.now()}-${Math.random()}`,
            isSelected: false,
            isRequestedRateManuallyChanged: false,
            isRequestedQuantityManuallyChanged: false,
            isDescriptionManuallyChanged: false,
            isRateManuallyChanged: false,
            Job_Number__cError: '',
            JobNumberReadOnlyClass: 'read-only-field job-number-field',
            Quantity__cError: '',
            Rate__cError: '',
            Invoice_Number__cError: '',
            PayeeErrorClass: 'lookup-control',
            LossDescriptionErrorClass: 'lookup-control',
            DetailTypeButtonClass: 'field-trigger',
            CategoryButtonClass: 'field-trigger',
            StatusButtonClass: 'field-trigger',
            ReasonButtonClass: 'field-trigger'
        };

        return this.updateRowPresentation(initializedRow);
    }

    updateRowPresentation(row) {
        const hasPayee = Boolean(row.PayeeName);
        const hasLossDescription = Boolean(row.CoverageLevelDetailName);
        const hasDetailType = Boolean(
            row.Detail_Type__c && row.Detail_Type__c !== 'Select Type'
        );
        const hasReason = Boolean(
            row.Reason__c && row.Reason__c !== '--Select Reason--'
        );

        return {
            ...row,
            CategoryDisplay: row.Category || 'Select Payee Type',
            DetailTypeDisplay: hasDetailType ? row.Detail_Type__c : 'Select Detail Type',
            StatusDisplay: row.Status__c || 'Select Status',
            ReasonDisplay: hasReason ? row.Reason__c : 'Select Reason',
            PayeeDisplay: hasPayee ? row.PayeeName : 'Search Payee',
            PayeeTextClass: hasPayee ? 'lookup-text' : 'lookup-placeholder',
            LossDescriptionDisplay: hasLossDescription
                ? row.CoverageLevelDetailName
                : 'Search Loss Component',
            LossDescriptionTextClass: hasLossDescription
                ? 'lookup-text'
                : 'lookup-placeholder',
            JobNumberReadOnlyClass: row.Job_Number__cError
                ? 'read-only-field job-number-field read-only-field_error'
                : 'read-only-field job-number-field',
            isPricingPartRow: row.Detail_Type__c === 'Part',
            rowClass: row.isSelected
                ? 'claim-item-record selected-row'
                : 'claim-item-record'
        };
    }

    clearFieldError(row, field) {
        const updatedRow = { ...row };

        switch (field) {
            case 'Job_Number__c':
                updatedRow.Job_Number__cError = '';
                updatedRow.JobNumberReadOnlyClass =
                    'read-only-field job-number-field';
                break;
            case 'Detail_Type__c':
                updatedRow.DetailTypeButtonClass = 'field-trigger';
                break;
            case 'Quantity__c':
                updatedRow.Quantity__cError = '';
                break;
            case 'Rate__c':
                updatedRow.Rate__cError = '';
                break;
            case 'Invoice_Number__c':
                updatedRow.Invoice_Number__cError = '';
                break;
            case 'Payee_Name__c':
                updatedRow.PayeeErrorClass = 'lookup-control';
                break;
            case 'Coverage_Level_Detail__c':
                updatedRow.LossDescriptionErrorClass = 'lookup-control';
                break;
            default:
                break;
        }

        return updatedRow;
    }

    markDirty() {
        this.isDirty = true;
    }

    get editorCollapseStorageKey() {
        return this.recordId
            ? `claimItemEditorCollapsed_${this.recordId}`
            : null;
    }

    async refreshClaimItemsBeforeExpand() {
        /*
         * Claim Items can be changed by processes outside this component
         * (for example, Payment Rescind can cancel the original line and
         * insert a new Requested clone).
         *
         * Refresh only when the editor is about to be reopened so the
         * latest server-side Claim Items are displayed. A temporary refresh
         * failure must never block the existing editor-opening behavior.
         */
        if (!this.wiredResult) {
            return;
        }

        try {
            await refreshApex(this.wiredResult);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error(
                'Unable to refresh Claim Items before opening the editor.',
                error
            );
        }
    }

    expandEditor() {
        this.isEditorExpanded = true;

        const storageKey = this.editorCollapseStorageKey;

        if (storageKey) {
            try {
                window.sessionStorage.removeItem(storageKey);
            } catch (error) {
                // Storage availability must never affect Claim Item editing.
                // eslint-disable-next-line no-console
                console.warn(
                    'Unable to clear Claim Item Editor UI state.',
                    error
                );
            }
        }
    }

    collapseEditorAfterSave() {
        this.isEditorExpanded = false;

        /*
         * The component currently refreshes the Salesforce console tab
         * after Save. Preserve the collapsed state across that refresh.
         */
        if (!this.isConsoleNavigation) {
            return;
        }

        const storageKey = this.editorCollapseStorageKey;

        if (!storageKey) {
            return;
        }

        try {
            window.sessionStorage.setItem(
                storageKey,
                'true'
            );
        } catch (error) {
            // Do not allow a browser-storage issue to affect a successful Save.
            // eslint-disable-next-line no-console
            console.warn(
                'Unable to preserve Claim Item Editor UI state.',
                error
            );
        }
    }

    restoreEditorStateAfterRefresh() {
        const storageKey = this.editorCollapseStorageKey;

        if (!storageKey) {
            return;
        }

        try {
            const shouldRemainCollapsed =
                window.sessionStorage.getItem(storageKey) === 'true';

            if (shouldRemainCollapsed) {
                this.isEditorExpanded = false;

                /*
                 * One-time state only. The editor is collapsed by default
                 * whenever the Claim record page is opened.
                 */
                window.sessionStorage.removeItem(storageKey);
            }
        } catch (error) {
            /*
             * The required default state is collapsed.
             * Storage issues must never cause the editor to open automatically.
             */
            this.isEditorExpanded = false;

            // eslint-disable-next-line no-console
            console.warn(
                'Unable to restore Claim Item Editor UI state.',
                error
            );
        }
    }

    dismissValidationErrors() {
        this.validationErrors = [];
    }

    focusValidationSummary() {
        window.requestAnimationFrame(() => {
            this.template.querySelector('[data-error-summary]')?.focus();
        });
    }

    normalizeTaxRate(value) {
        if (value === null || value === undefined || value === '') {
            return 0;
        }

        const rate = Number(value);
        if (Number.isNaN(rate)) {
            return 0;
        }

        return rate > 1 ? rate / 100 : rate;
    }

    recalculateAllRows() {
        if (!this.data.length) {
            return;
        }

        this.data = this.data.map((row) =>
            this.updateRowPresentation(this.calculateRowAmounts(row))
        );
    }

    calculateRowAmounts(row) {
        const updatedRow = { ...row };

        const quantity = this.isBlank(updatedRow.Quantity__c)
            ? 0
            : Number(updatedRow.Quantity__c);

        const rate = this.isBlank(updatedRow.Rate__c)
            ? 0
            : Number(updatedRow.Rate__c);

        const deductible = this.isBlank(updatedRow.Deductible__c)
            ? 0
            : Number(updatedRow.Deductible__c);

        const subtotal = quantity * rate;

        const hasLaborTaxRate =
            !this.isBlank(this.claimLaborTaxRate) &&
            !Number.isNaN(Number(this.claimLaborTaxRate));

        const hasPartsTaxRate =
            !this.isBlank(this.claimPartsTaxRate) &&
            !Number.isNaN(Number(this.claimPartsTaxRate));

        const existingCalculatedTax = this.isBlank(updatedRow.Tax_New__c)
            ? 0
            : Number(updatedRow.Tax_New__c);

        const explicitTax = this.isBlank(updatedRow.Tax__c)
            ? 0
            : Number(updatedRow.Tax__c);

        const isRepairShopPayee =
            Boolean(updatedRow.Payee_Name__c) &&
            Boolean(this.repairShopAccountId) &&
            updatedRow.Payee_Name__c === this.repairShopAccountId;

        let taxNew = 0;

        /*
         * Mirrors the Tax_New__c formula:
         *
         * IF Tax__c > 0.000001:
         *     Use Tax__c.
         *
         * ELSE IF Payee = Claim Repair Shop:
         *     Labor = Quantity × Rate × Labor Tax Rate.
         *     Part  = Quantity × Rate × Parts Tax Rate.
         *
         * ELSE:
         *     Use Tax__c.
         */
        if (explicitTax > 0.000001) {
            taxNew = explicitTax;
        } else if (isRepairShopPayee) {
            if (updatedRow.Detail_Type__c === 'Labor') {
                taxNew = hasLaborTaxRate
                    ? subtotal * this.normalizeTaxRate(this.claimLaborTaxRate)
                    : existingCalculatedTax;
            } else if (updatedRow.Detail_Type__c === 'Part') {
                taxNew = hasPartsTaxRate
                    ? subtotal * this.normalizeTaxRate(this.claimPartsTaxRate)
                    : existingCalculatedTax;
            } else {
                taxNew = 0;
            }
        } else {
            taxNew = explicitTax;
        }

        if (Number.isNaN(taxNew)) {
            taxNew = 0;
        }

        updatedRow.Subtotal__c = Number(subtotal.toFixed(2));

        updatedRow.Tax_New__c = Number(
            taxNew.toFixed(2)
        );

        updatedRow.NetClaim__c = Number(
            (subtotal + taxNew - deductible).toFixed(2)
        );

        return updatedRow;
    }

    applyRequestedFieldDefaults(row, changedField) {
    const updatedRow = { ...row };

    if (
        changedField === 'Coverage_Level_Detail__c' &&
        !updatedRow.isDescriptionManuallyChanged
    ) {
        updatedRow.Description = updatedRow.CoverageLevelDetailName || '';
    }

    // Preserve existing behavior for non-Labor items.
    // For Labor items, Req Rate must remain independent
    // from the Adj Rate.
    if (
        changedField === 'Rate__c' &&
        !updatedRow.isRequestedRateManuallyChanged &&
        !this.isLaborRow(updatedRow)
    ) {
        updatedRow.Processed_Parts__c = updatedRow.Rate__c;
    }

    if (
        changedField === 'Quantity__c' &&
        !updatedRow.isRequestedQuantityManuallyChanged
    ) {
        updatedRow.Gross_Quantity__c = updatedRow.Quantity__c;
    }

    return updatedRow;
}

    isAutoWarrantyClaim() {
        return this.policyRecordTypeName === 'Auto Warranty';
    }

    isLaborRow(row) {
        return row?.Detail_Type__c === 'Labor';
    }

    isBlank(value) {
        return value === null || value === undefined || value === '';
    }

    findPriorRowByJobNumber(currentRow) {
        if (!currentRow?.Job_Number__c) {
            return null;
        }

        const currentJobNo = String(currentRow.Job_Number__c).trim();

        return (
            this.data.find(
                (row) =>
                    row.uniqueKey !== currentRow.uniqueKey &&
                    row.Job_Number__c &&
                    String(row.Job_Number__c).trim() === currentJobNo &&
                    (row.Payee_Name__c || row.Coverage_Level_Detail__c)
            ) || null
        );
    }

    applyJobNumberDefaults(row, forceOverride = false) {
        const priorRow = this.findPriorRowByJobNumber(row);
        const updatedRow = { ...row };

        if (priorRow) {
            if (forceOverride || !updatedRow.Payee_Name__c) {
                updatedRow.Payee_Name__c = priorRow.Payee_Name__c || null;
                updatedRow.PayeeName = priorRow.PayeeName || '';
            }

            if (forceOverride || !updatedRow.Coverage_Level_Detail__c) {
                updatedRow.Coverage_Level_Detail__c =
                    priorRow.Coverage_Level_Detail__c || null;
                updatedRow.CoverageLevelDetailName =
                    priorRow.CoverageLevelDetailName || '';
            }

            return updatedRow;
        }

        if (forceOverride || !updatedRow.Payee_Name__c) {
            updatedRow.Payee_Name__c = this.repairShopAccountId || null;
            updatedRow.PayeeName = this.repairShopAccountName || '';
            updatedRow.isPayeeAutoPopulated = Boolean(this.repairShopAccountId);
        }

        if (forceOverride) {
            updatedRow.Coverage_Level_Detail__c = null;
            updatedRow.CoverageLevelDetailName = '';
        }

        return updatedRow;
    }

    applyLaborRateDefault(row) {
    const updatedRow = { ...row };

   
if (
    this.isLaborRow(updatedRow) &&
    this.claimLaborRate
) {

       
        // Default Adj Rate from Claim Labor Rate when Adj Rate is blank.
        if (
            this.isBlank(updatedRow.Rate__c) &&
            !updatedRow.isRateManuallyChanged
        ) {
            updatedRow.Rate__c = this.claimLaborRate;
        }

        // For Labor items, default Req Rate from Claim Labor Rate
        // when Req Rate has not been manually changed.
        if (
    (this.isBlank(updatedRow.Processed_Parts__c) ||
        Number(updatedRow.Processed_Parts__c) === 0) &&
    !updatedRow.isRequestedRateManuallyChanged
) {
    updatedRow.Processed_Parts__c = this.claimLaborRate;
}
    }

    return updatedRow;
}

    applyRowDefaults(row, forceJobOverride = false) {
        let updatedRow = this.applyJobNumberDefaults(row, forceJobOverride);
        updatedRow = this.applyLaborRateDefault(updatedRow);
        return updatedRow;
    }

    handleFieldChange(event) {
        const rowId = event.target.dataset.id;
        const field = event.target.dataset.field;
        let value = event.detail?.value ?? event.target.value;

        if (
            ['Rate__c', 'Quantity__c', 'Gross_Quantity__c', 'Processed_Parts__c', 'Deductible__c'].includes(field)
        ) {
            value = value === '' ? null : Number(value);
        }

        this.data = this.data.map((row) => {
            if (row.uniqueKey !== rowId) {
                return row;
            }

            let updatedRow = this.clearFieldError(
                {
                    ...row,
                    [field]: value
                },
                field
            );

            if (field === 'Processed_Parts__c') {
                updatedRow.isRequestedRateManuallyChanged = true;
            }

            if (field === 'Gross_Quantity__c') {
                updatedRow.isRequestedQuantityManuallyChanged = true;
            }

            if (field === 'Description') {
                updatedRow.isDescriptionManuallyChanged = true;
            }

            if (field === 'Rate__c') {
                updatedRow.isRateManuallyChanged = true;
                updatedRow = this.applyRequestedFieldDefaults(updatedRow, 'Rate__c');
                updatedRow = this.calculateRowAmounts(updatedRow);
            } else if (field === 'Quantity__c') {
                updatedRow = this.applyRequestedFieldDefaults(updatedRow, 'Quantity__c');
                updatedRow = this.calculateRowAmounts(updatedRow);
            } else if (field === 'Job_Number__c') {
                updatedRow = this.applyRowDefaults(updatedRow, true);
                updatedRow = this.applyRequestedFieldDefaults(
                    updatedRow,
                    'Coverage_Level_Detail__c'
                );
                updatedRow = this.calculateRowAmounts(updatedRow);
            } else if (field === 'Deductible__c') {
                updatedRow = this.calculateRowAmounts(updatedRow);
            }

            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
    }

    async handleOpenVendorPricingForSelection() {
        const selected = this.data.filter((row) =>
            this.selectedRows.includes(row.uniqueKey)
        );
        const parts = selected.filter((row) => row.Detail_Type__c === 'Part');
        if (!parts.length) {
            this.showToast('Select a Part', 'Select at least one Part Claim Item.', 'info');
            return;
        }
        if (parts.length !== selected.length) {
            this.showToast('Parts only',
                'Non-Part lines are excluded from this Parts Pricing preview.', 'info');
        }
        await this.openVendorPricingDemo(parts);
    }

    async handleOpenVendorPricingForRow(event) {
        const key = event.currentTarget.dataset.id;
        const row = this.data.find((item) => item.uniqueKey === key);
        if (!row || row.Detail_Type__c !== 'Part') return;
        await this.openVendorPricingDemo([row]);
    }

    async openVendorPricingDemo(rows) {
        if (!this.enablePricingDemo || this.isLoading || !rows || !rows.length) return;
        // Only a safe snapshot of draft values crosses into the modal.
        // Selected example quotes never flow back into this.data or saveClaimItems().
        const selectedLines = rows.map((row) => ({
            rowKey: String(row.uniqueKey),
            claimItemId: row.Id || null,
            jobNumber: String(row.Job_Number__c || ''),
            detailType: row.Detail_Type__c,
            partNumber: row.Part_Number__c || '',
            adjustedQuantity: row.Quantity__c,
            lossComponentName: row.CoverageLevelDetailName || '',
            description: row.Description || '',
            isUnsaved: !row.Id
        }));
        try {
            await VendorPricingDemoModal.open({
                label: 'Parts Pricing Comparison — Demonstration',
                size: 'large',
                selectedLines
            });
        } catch (error) {
            // An unavailable modal must not interrupt the editor's normal behavior.
            this.showToast('Pricing preview unavailable',
                error?.message || 'Unable to open the pricing preview.', 'error');
        }
    }

    handleRowSelection(event) {
        const rowId = event.target.dataset.id;
        const checked = event.target.checked;

        this.data = this.data.map((row) =>
            row.uniqueKey === rowId
                ? this.updateRowPresentation({ ...row, isSelected: checked })
                : row
        );

        this.selectedRows = this.data
            .filter((row) => row.isSelected)
            .map((row) => row.uniqueKey);

        this.updateHeaderCheckboxState();
    }

    handleSelectAll(event) {
        const shouldDeselectAll = event.target.indeterminate || this.isPartiallySelected;
        const checked = shouldDeselectAll ? false : event.target.checked;

        this.data = this.data.map((row) =>
            this.updateRowPresentation({ ...row, isSelected: checked })
        );

        this.selectedRows = checked
            ? this.data.map((row) => row.uniqueKey)
            : [];

        this.updateHeaderCheckboxState();
    }

    updateHeaderCheckboxState() {
        this.isAllSelected =
            this.data.length > 0 && this.selectedRows.length === this.data.length;
    }

    getNextAvailableJobNumber() {
        const usedJobNumbers = new Set(
            this.data
                .map((row) => Number.parseInt(row.Job_Number__c, 10))
                .filter((jobNumber) => Number.isInteger(jobNumber) && jobNumber > 0)
        );

        let nextJobNumber = 1;
        while (usedJobNumbers.has(nextJobNumber)) {
            nextJobNumber += 1;
        }

        return String(nextJobNumber);
    }

    getMostRecentJobNumber() {
        for (let index = this.data.length - 1; index >= 0; index -= 1) {
            const jobNumber = String(this.data[index].Job_Number__c || '').trim();
            if (jobNumber) {
                return jobNumber;
            }
        }

        return '';
    }

    buildNewRow(jobNumber) {
        this.newRowCounter += 1;

        let newRow = {
            uniqueKey: `new-${Date.now()}-${this.newRowCounter}`,
            isNew: true,
            isSelected: false,
            Job_Number__c: String(jobNumber),
            Detail_Type__c: 'Select Type',
            Description: '',
            Part_Number__c: '',
            Invoice_Number__c: '',
            Quantity__c: 1,
            Gross_Quantity__c: 1,
            Processed_Parts__c: 0,
            Rate__c: null,
            Status__c: 'Requested',
            Reason__c: '--Select Reason--',
            Category: '',
            NetClaim__c: 0,
            Tax_New__c: 0,
            Payee_Name__c: null,
            PayeeName: '',
            Coverage_Level_Detail__c: null,
            CoverageLevelDetailName: '',
            isPayeeAutoPopulated: false,
            isRateManuallyChanged: false,
            isRequestedRateManuallyChanged: false,
            isRequestedQuantityManuallyChanged: false,
            isDescriptionManuallyChanged: false,
            Job_Number__cError: '',
            JobNumberReadOnlyClass: 'read-only-field job-number-field',
            Quantity__cError: '',
            Rate__cError: '',
            Invoice_Number__cError: '',
            PayeeErrorClass: 'lookup-control',
            LossDescriptionErrorClass: 'lookup-control',
            DetailTypeButtonClass: 'field-trigger',
            CategoryButtonClass: 'field-trigger',
            StatusButtonClass: 'field-trigger',
            ReasonButtonClass: 'field-trigger'
        };

        newRow = this.applyRowDefaults(newRow, true);
        newRow = this.applyRequestedFieldDefaults(
            newRow,
            'Coverage_Level_Detail__c'
        );
        newRow = this.applyRequestedFieldDefaults(newRow, 'Rate__c');
        newRow = this.applyRequestedFieldDefaults(newRow, 'Quantity__c');
        newRow = this.calculateRowAmounts(newRow);

        return this.updateRowPresentation(newRow);
    }

    canAddClaimItem() {
        if (this.claimStatus === 'Closed') {
            this.showToast(
                'Error',
                'You must re-open the Claim before adding Claim Items.',
                'error'
            );
            return false;
        }

        return true;
    }

    /*handleAddJob() {
        if (!this.canAddClaimItem()) {
            return;
        }

        this.expandEditor();

        const nextJobNumber = this.getNextAvailableJobNumber();
        const newRow = this.buildNewRow(nextJobNumber);

        this.data = [
            ...this.data,
            newRow
        ];

        this.markDirty();
    }*/

    async handleAddJob() {
        if (!this.canAddClaimItem()) {
            return;
        }

        if (this.isLoading) {
            return;
        }

        this.isLoading = true;

        try {
            /*
             * If the editor is currently collapsed, refresh the Claim Items
             * before expanding it. This picks up records created or changed
             * outside this component, including Requested clones created by
             * the Payment Rescind process.
             */
            if (!this.isEditorExpanded) {
                await this.refreshClaimItemsBeforeExpand();
            }

            /*
             * Existing behavior:
             * Refresh Claim defaults before creating the row.
             * This ensures a newly-updated Repair Shop Account
             * is available immediately as the Payee.
             */
            if (this.wiredClaimDefaultResult) {
                await refreshApex(
                    this.wiredClaimDefaultResult
                );
            }

            this.expandEditor();

            const nextJobNumber =
                this.getNextAvailableJobNumber();

            const newRow =
                this.buildNewRow(nextJobNumber);

            this.data = [
                ...this.data,
                newRow
            ];

            this.markDirty();

        } catch (error) {
            // eslint-disable-next-line no-console
            console.error(
                'Unable to prepare Claim Item Editor.',
                error
            );

            this.showToast(
                'Error',
                error?.body?.message ||
                'Unable to load the latest Claim information.',
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    // Retained as a compatibility alias for any existing template reference.
    handleAddRow() {
        this.handleAddJob();
    }

    async openAddJobDetailModal() {

        if (!this.canAddClaimItem()) {
            return;
        }

        if (this.isLoading) {
            return;
        }

        /*
         * First click while editor is collapsed:
         * refresh the latest Claim Items, then expand the editor only.
         * Do not open the Add Job Detail modal on this first click.
         */
        if (!this.isEditorExpanded) {
            this.isLoading = true;

            try {
                await this.refreshClaimItemsBeforeExpand();
                this.expandEditor();
            } finally {
                this.isLoading = false;
            }

            return;
        }

        /*
         * Existing behavior remains unchanged once the editor is open.
         */
        const mostRecentJobNumber =
            this.getMostRecentJobNumber();

        if (!mostRecentJobNumber) {
            this.showToast(
                'Information',
                'Add a Job before adding a Job Detail.',
                'info'
            );

            return;
        }

        this.selectedJobNumber =
            mostRecentJobNumber;

        this.showAddJobDetailModal = true;
    }

    closeAddJobDetailModal() {
        this.showAddJobDetailModal = false;
        this.selectedJobNumber = '';
    }

    handleJobDetailSelection(event) {
        this.selectedJobNumber = event.detail.value;
    }

    confirmAddJobDetail() {
        if (!this.selectedJobNumber || !this.canAddClaimItem()) {
            return;
        }

        const newRow = this.buildNewRow(this.selectedJobNumber);
        this.data = [...this.data, newRow];
        this.markDirty();
        this.closeAddJobDetailModal();
    }

    buildValidationLabels() {
        const jobTotals = new Map();

        this.data.forEach((row) => {
            const jobNumber = String(row.Job_Number__c || '').trim();
            if (jobNumber) {
                jobTotals.set(jobNumber, (jobTotals.get(jobNumber) || 0) + 1);
            }
        });

        const jobOccurrences = new Map();

        return this.data.map((row, index) => {
            const jobNumber = String(row.Job_Number__c || '').trim();

            if (!jobNumber) {
                return `Claim Item ${index + 1}`;
            }

            const detailNumber = (jobOccurrences.get(jobNumber) || 0) + 1;
            jobOccurrences.set(jobNumber, detailNumber);

            return jobTotals.get(jobNumber) > 1
                ? `Job ${jobNumber} - Detail ${detailNumber}`
                : `Job ${jobNumber}`;
        });
    }

    validateRows() {
        const errors = [];
        const validationLabels = this.buildValidationLabels();

        this.data = this.data.map((row, index) => {
            const itemLabel = validationLabels[index];
            let updatedRow = {
                ...row,
                Job_Number__cError: '',
                JobNumberReadOnlyClass: 'read-only-field job-number-field',
                Quantity__cError: '',
                Rate__cError: '',
                Invoice_Number__cError: '',
                PayeeErrorClass: 'lookup-control',
                LossDescriptionErrorClass: 'lookup-control',
                DetailTypeButtonClass: 'field-trigger'
            };

            if (!updatedRow.Job_Number__c) {
                errors.push(`${itemLabel}: a system-assigned Job number is required.`);
                updatedRow.Job_Number__cError = 'error-field';
                updatedRow.JobNumberReadOnlyClass =
                    'read-only-field job-number-field read-only-field_error';
            }

            if (
                !updatedRow.Detail_Type__c ||
                updatedRow.Detail_Type__c === 'Select Type'
            ) {
                errors.push(`${itemLabel}: select a Detail Type.`);
                updatedRow.DetailTypeButtonClass =
                    'field-trigger field-trigger_error';
            }

            if (!updatedRow.Payee_Name__c && !this.repairShopAccountId) {
                errors.push(`${itemLabel}: select a Payee.`);
                updatedRow.PayeeErrorClass =
                    'lookup-control lookup-control_error';
            }

            if (!updatedRow.Coverage_Level_Detail__c) {
                errors.push(`${itemLabel}: select a Loss Component.`);
                updatedRow.LossDescriptionErrorClass =
                    'lookup-control lookup-control_error';
            }

            if (
                updatedRow.Quantity__c === null ||
                updatedRow.Quantity__c === undefined ||
                updatedRow.Quantity__c === '' ||
                updatedRow.Quantity__c <= 0
            ) {
                errors.push(`${itemLabel}: enter an Adjusted Quantity greater than 0.`);
                updatedRow.Quantity__cError = 'error-field';
            }
            //commented out by Swastika on 15th sept 2026
            /*if (
                this.isAutoWarrantyClaim() &&
                updatedRow.Detail_Type__c === 'Labor' &&
                this.isBlank(updatedRow.Rate__c) &&
                !updatedRow.isRateManuallyChanged &&
                this.claimLaborRate
            ) {
                updatedRow.Rate__c = this.claimLaborRate;
                updatedRow = this.applyRequestedFieldDefaults(updatedRow, 'Rate__c');
                updatedRow = this.calculateRowAmounts(updatedRow);
            } else if (
                updatedRow.Rate__c === null ||
                updatedRow.Rate__c === undefined ||
                updatedRow.Rate__c === '' ||
                updatedRow.Rate__c <= 0
            ) {
                errors.push(`${itemLabel}: enter an Adjusted Rate greater than 0.`);
                updatedRow.Rate__cError = 'error-field';
            }

            if (
                updatedRow.Detail_Type__c === 'Inspection' &&
                !updatedRow.Invoice_Number__c
            ) {
                errors.push(`${itemLabel}: Invoice Number is required for Inspection items.`);
                updatedRow.Invoice_Number__cError = 'error-field';
            }*/

            //added by Swastika on 15th sept 2026

            // Adjusted Rate is not required when Status = Denied
            // Adjusted Rate is not required when Status = Denied or Requested or cancelled
            if (
                !['Denied', 'Requested', 'Cancelled'].includes(updatedRow.Status__c)
            ) {

                if (
                    this.isAutoWarrantyClaim() &&
                    updatedRow.Detail_Type__c === 'Labor' &&
                    this.isBlank(updatedRow.Rate__c) &&
                    !updatedRow.isRateManuallyChanged &&
                    this.claimLaborRate
                ) {
                    updatedRow.Rate__c = this.claimLaborRate;
                    updatedRow = this.applyRequestedFieldDefaults(
                        updatedRow,
                        'Rate__c'
                    );
                    updatedRow = this.calculateRowAmounts(updatedRow);

                } else if (
                    updatedRow.Rate__c === null ||
                    updatedRow.Rate__c === undefined ||
                    updatedRow.Rate__c === '' ||
                    updatedRow.Rate__c <= 0
                ) {
                    errors.push(
                        `${itemLabel}: enter an Adjusted Rate greater than 0.`
                    );
                    updatedRow.Rate__cError = 'error-field';
                }
            }


            // Invoice Number is required only for Inspection items
            // when Status = Authorized, Approved to Pay, or Paid
            if (
                updatedRow.Detail_Type__c === 'Inspection' &&
                (
                    updatedRow.Status__c === 'Authorized' ||
                    updatedRow.Status__c === 'Approved to Pay' ||
                    updatedRow.Status__c === 'Paid'
                ) &&
                !String(updatedRow.Invoice_Number__c || '').trim()
            ) {
                errors.push(
                    `${itemLabel}: Invoice Number is required for Inspection items when Status is Authorized, Approved to Pay, or Paid.`
                );
                updatedRow.Invoice_Number__cError = 'error-field';
            }

            return this.updateRowPresentation(updatedRow);
        });

        this.validationErrors = [...new Set(errors)];
        return this.validationErrors;
    }

    async handleSave() {
        if (INACTIVE_CONTRACT_STATUSES.includes(this.contractStatus)) {
            this.showToast(
                'Error',
                'Claim Items cannot be modified because the Contract is not active.',
                'error'
            );
            return;
        }

        if (this.claimStatus === 'Closed') {
            this.showToast(
                'Error',
                'You must re-open the Claim in order to add or update a Claim Item.',
                'error'
            );
            return;
        }

        if (this.isLoading) {
            return;
        }

        const errors = this.validateRows();
        if (errors.length > 0) {
            this.focusValidationSummary();
            return;
        }

        this.isLoading = true;

        try {
            await saveClaimItems({
                claimId: this.recordId,
                items: this.data
            });

            this.showToast(
                'Success',
                'Claim Items saved successfully.',
                'success'
            );

            await refreshApex(this.wiredResult);

            this.isDirty = false;
            this.selectedRows = [];
            this.updateHeaderCheckboxState();

            /*
             * Collapse only after a completely successful save.
             * Validation/DML failures leave the editor open.
             */
            this.collapseEditorAfterSave();

            await this.refreshCurrentConsoleTab();
        } catch (error) {
            let errorMessage =
                error?.body?.pageErrors?.[0]?.message ||
                error?.body?.message ||
                error?.message ||
                'Error saving Claim Items.';

            if (
                errorMessage.includes(
                    'You cannot change the Job Name because this Job # already has a name'
                )
            ) {
                errorMessage =
                    'The Job Number is already associated with another Job Name. Use the existing Job Name or select a different Job Number.';
            }

            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.data = this.cloneRows(this.originalData).map((row) =>
            this.updateRowPresentation({ ...row, isSelected: false })
        );
        this.selectedRows = [];
        this.validationErrors = [];
        this.isDirty = false;
        this.closeAddJobDetailModal();
        this.updateHeaderCheckboxState();
        this.showToast('Cancelled', 'All unsaved changes were reverted.', 'info');
        this.isEditorExpanded = false;
    }

    async handleRequestInspection() {
        if (!this.recordId) {
            this.showToast(
                'Error',
                'Claim Id is not available.',
                'error'
            );
            return;
        }

        const omniScriptUrl =
            this.buildInspectionOmniScriptUrl();

        try {
            if (this.isConsoleNavigation) {
                const focusedTabInfo =
                    await getFocusedTabInfo();

                const parentTabId =
                    focusedTabInfo.isSubtab
                        ? focusedTabInfo.parentTabId
                        : focusedTabInfo.tabId;

                await openSubtab(
                    parentTabId,
                    {
                        url: omniScriptUrl,
                        focus: true
                    }
                );

                return;
            }

            window.open(
                omniScriptUrl,
                '_blank',
                'noopener'
            );
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error(
                'Unable to launch Request an Inspection.',
                error
            );

            this.showToast(
                'Error',
                'Unable to open Request an Inspection.',
                'error'
            );
        }
    }

    buildInspectionOmniScriptUrl() {
        const params = new URLSearchParams({
            omniscript__type: 'Claim',
            omniscript__subType: 'InspectionRequest',
            omniscript__language: 'English',
            omniscript__theme: 'lightning',
            omniscript__tabIcon: 'custom:custom18',
            omniscript__tabLabel: 'ClaimInspectionWorkflow',
            c__ContextId: this.recordId
        });

        return `/lightning/page/omnistudio/omniscript?${params.toString()}`;
    }

    createFlowInputVariables() {
        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.recordId
            }
        ];
    }

    handleCheckBokLines() {
        this.flowInputVariables = this.createFlowInputVariables();
        this.showBokFlow = true;
    }

    closeBokFlow() {
        this.showBokFlow = false;
    }

    handleFlowStatusChange(event) {
        if (['FINISHED', 'FINISHED_SCREEN'].includes(event.detail.status)) {
            this.closeBokFlow();
            this.showToast('Success', 'BOK check completed.', 'success');
            this.refreshGridAfterFlow();
        }
    }

    handleAuthorizeAllLines() {
        this.flowInputVariables = this.createFlowInputVariables();
        this.showAuthorizeAllLines = true;
    }

    closeAuthorizeAllLines() {
        this.showAuthorizeAllLines = false;
    }

    handleAuthorizeFlowStatusChange(event) {
        if (['FINISHED', 'FINISHED_SCREEN'].includes(event.detail.status)) {
            this.closeAuthorizeAllLines();
            this.refreshGridAfterFlow();
        }
    }

    handleConfirmAllocations() {
        this.flowInputVariables = this.createFlowInputVariables();
        this.showConfirmAllocation = true;
    }

    closeConfirmAllocation() {
        this.showConfirmAllocation = false;
    }

    handleAllocationFlowStatusChange(event) {
        if (['FINISHED', 'FINISHED_SCREEN'].includes(event.detail.status)) {
            this.closeConfirmAllocation();
            this.refreshGridAfterFlow();
        }
    }

    async refreshGridAfterFlow() {
        try {
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Error', 'Error refreshing Claim Items.', 'error');
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    openPicklistPopup(event) {
        const source = event.currentTarget;
        this.popupRowId = source.dataset.id;
        this.popupField = source.dataset.field;
        this.popupSelectedValue = source.dataset.value || '';

        switch (this.popupField) {
            case 'Detail_Type__c':
                this.popupOptions = this.detailTypeOptions;
                this.popupFieldLabel = 'Detail Type';
                break;
            case 'Status__c':
                this.popupOptions = this.statusOptions;
                this.popupFieldLabel = 'Status';
                break;
            case 'Reason__c':
                this.popupOptions = this.reasonOptions;
                this.popupFieldLabel = 'Reason';
                break;
            case 'Category':
                this.popupOptions = this.categoryOptions;
                this.popupFieldLabel = 'Payee Type';
                break;
            default:
                return;
        }

        this.showPicklistPopup = true;
    }

    handlePopupPicklistChange(event) {
        this.popupSelectedValue = event.detail.value;
    }

    applyPopupPicklistValue() {
        this.data = this.data.map((row) => {
            if (row.uniqueKey !== this.popupRowId) {
                return row;
            }

            let updatedRow = this.clearFieldError(
                {
                    ...row,
                    [this.popupField]: this.popupSelectedValue
                },
                this.popupField
            );

            //added by Swastika on 15th sept 2026

            if (this.popupField === 'Status__c') {

                // Denied and Requested items do not require Adjusted Rate
                if (
                    ['Denied', 'Requested', 'Cancelled'].includes(updatedRow.Status__c)
                ) {
                    updatedRow.Rate__cError = '';
                }

                // Invoice Number is not required unless the Inspection
                // item is Authorized, Approved to Pay, or Paid
                if (
                    !INSPECTION_INVOICE_REQUIRED_STATUSES.includes(
                        updatedRow.Status__c
                    )
                ) {
                    updatedRow.Invoice_Number__cError = '';
                }
            }

            if (this.popupField === 'Detail_Type__c') {
                updatedRow = this.applyRowDefaults(updatedRow);
                updatedRow = this.applyRequestedFieldDefaults(updatedRow, 'Rate__c');
                updatedRow = this.calculateRowAmounts(updatedRow);
            }

            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
        this.closePicklistPopup();
    }

    closePicklistPopup() {
        this.showPicklistPopup = false;
        this.popupRowId = null;
        this.popupField = null;
        this.popupSelectedValue = null;
        this.popupOptions = [];
        this.popupFieldLabel = null;
    }

    openLookupPopup(event) {
        const source = event.currentTarget;
        this.lookupRowId = source.dataset.id;
        this.lookupSearchTerm = '';
        this.lookupResults = [];
        this.lookupSelectedId = source.dataset.value || '';
        this.lookupSelectedName = source.dataset.label || '';
        this.isLookupSearching = false;
        this.showLookupPopup = true;
    }

    handleLookupSearch(event) {
        this.lookupSearchTerm = event.target.value || '';
        window.clearTimeout(this.lookupSearchTimer);
        this.lookupRequestSequence += 1;
        const requestId = this.lookupRequestSequence;
        const searchTerm = this.lookupSearchTerm.trim();

        if (searchTerm.length < 2) {
            this.lookupResults = [];
            this.isLookupSearching = false;
            return;
        }

        this.isLookupSearching = true;
        this.lookupResults = [];

        this.lookupSearchTimer = window.setTimeout(
            () => this.searchLossDescriptions(searchTerm, requestId),
            SEARCH_DELAY_MS
        );
    }

    async searchLossDescriptions(searchTerm, requestId) {
        try {
            const results = await searchCoverageLevelDetails({
                claimId: this.recordId,
                searchTerm
            });

            if (requestId !== this.lookupRequestSequence) {
                return;
            }

            this.lookupResults = (results || []).map((record) =>
                this.buildLookupResult(record, this.lookupSelectedId)
            );
        } catch (error) {
            if (requestId === this.lookupRequestSequence) {
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error searching Loss Components.',
                    'error'
                );
                // eslint-disable-next-line no-console
                console.error(error);
            }
        } finally {
            if (requestId === this.lookupRequestSequence) {
                this.isLookupSearching = false;
            }
        }
    }

    selectLookupValue(event) {
        this.lookupSelectedId = event.currentTarget.dataset.id;
        this.lookupSelectedName = event.currentTarget.dataset.name;
        this.lookupResults = this.lookupResults.map((record) =>
            this.buildLookupResult(record, this.lookupSelectedId)
        );
    }

    applyLookupValue() {
        if (!this.lookupSelectedId) {
            return;
        }

        this.data = this.data.map((row) => {
            if (row.uniqueKey !== this.lookupRowId) {
                return row;
            }

            let updatedRow = this.clearFieldError(
                {
                    ...row,
                    Coverage_Level_Detail__c: this.lookupSelectedId,
                    CoverageLevelDetailName: this.lookupSelectedName
                },
                'Coverage_Level_Detail__c'
            );

            updatedRow = this.applyRequestedFieldDefaults(
                updatedRow,
                'Coverage_Level_Detail__c'
            );

            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
        this.closeLookupPopup();
    }

    closeLookupPopup() {
        window.clearTimeout(this.lookupSearchTimer);
        this.lookupRequestSequence += 1;
        this.showLookupPopup = false;
        this.lookupRowId = null;
        this.lookupSearchTerm = '';
        this.lookupResults = [];
        this.lookupSelectedId = '';
        this.lookupSelectedName = '';
        this.isLookupSearching = false;
    }

    openPayeeLookupPopup(event) {
        const source = event.currentTarget;
        this.payeeRowId = source.dataset.id;
        this.payeeSearchTerm = '';
        this.payeeResults = [];
        this.payeeSelectedId = source.dataset.value || '';
        this.payeeSelectedName = source.dataset.label || '';
        this.isPayeeSearching = false;
        this.showPayeeLookupPopup = true;
    }

    handlePayeeLookupSearch(event) {
        this.payeeSearchTerm = event.target.value || '';
        window.clearTimeout(this.payeeSearchTimer);
        this.payeeRequestSequence += 1;
        const requestId = this.payeeRequestSequence;
        const searchTerm = this.payeeSearchTerm.trim();

        if (searchTerm.length < 2) {
            this.payeeResults = [];
            this.isPayeeSearching = false;
            return;
        }

        this.isPayeeSearching = true;
        this.payeeResults = [];

        this.payeeSearchTimer = window.setTimeout(
            () => this.searchPayees(searchTerm, requestId),
            SEARCH_DELAY_MS
        );
    }

    async searchPayees(searchTerm, requestId) {
        try {
            const results = await searchPayeeAccounts({ searchTerm });

            if (requestId !== this.payeeRequestSequence) {
                return;
            }

            this.payeeResults = (results || []).map((record) =>
                this.buildLookupResult(record, this.payeeSelectedId)
            );
        } catch (error) {
            if (requestId === this.payeeRequestSequence) {
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error searching Payees.',
                    'error'
                );
                // eslint-disable-next-line no-console
                console.error(error);
            }
        } finally {
            if (requestId === this.payeeRequestSequence) {
                this.isPayeeSearching = false;
            }
        }
    }

    buildLookupResult(record, selectedId) {
        const isSelected = record.Id === selectedId;
        return {
            Id: record.Id,
            Name: record.Name,
            isSelected,
            cssClass: isSelected
                ? 'lookup-result-row lookup-result-row_selected'
                : 'lookup-result-row'
        };
    }

    selectPayeeLookupValue(event) {
        this.payeeSelectedId = event.currentTarget.dataset.id;
        this.payeeSelectedName = event.currentTarget.dataset.name;
        this.payeeResults = this.payeeResults.map((record) =>
            this.buildLookupResult(record, this.payeeSelectedId)
        );
    }

    applyPayeeLookupValue() {
        if (!this.payeeSelectedId) {
            return;
        }

        this.data = this.data.map((row) => {
            if (row.uniqueKey !== this.payeeRowId) {
                return row;
            }

            let updatedRow = this.clearFieldError(
                {
                    ...row,
                    Payee_Name__c: this.payeeSelectedId,
                    PayeeName: this.payeeSelectedName
                },
                'Payee_Name__c'
            );

            updatedRow = this.calculateRowAmounts(updatedRow);
            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
        this.closePayeeLookupPopup();
    }

    closePayeeLookupPopup() {
        window.clearTimeout(this.payeeSearchTimer);
        this.payeeRequestSequence += 1;
        this.showPayeeLookupPopup = false;
        this.payeeRowId = null;
        this.payeeSearchTerm = '';
        this.payeeResults = [];
        this.payeeSelectedId = '';
        this.payeeSelectedName = '';
        this.isPayeeSearching = false;
    }

    clearPayeeValue(event) {
        event.stopPropagation();
        const rowId = event.currentTarget.dataset.id;

        this.data = this.data.map((row) => {
            if (row.uniqueKey !== rowId) {
                return row;
            }

            let updatedRow = this.clearFieldError(
                {
                    ...row,
                    Payee_Name__c: null,
                    PayeeName: ''
                },
                'Payee_Name__c'
            );
            updatedRow = this.calculateRowAmounts(updatedRow);
            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
    }

    clearLossDescriptionValue(event) {
        event.stopPropagation();
        const rowId = event.currentTarget.dataset.id;

        this.data = this.data.map((row) => {
            if (row.uniqueKey !== rowId) {
                return row;
            }

            let updatedRow = this.clearFieldError(
                {
                    ...row,
                    Coverage_Level_Detail__c: null,
                    CoverageLevelDetailName: ''
                },
                'Coverage_Level_Detail__c'
            );
            updatedRow = this.applyRequestedFieldDefaults(
                updatedRow,
                'Coverage_Level_Detail__c'
            );
            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
    }

    async openMassUpdateModal() {

        /*
         * First click from collapsed state:
         * refresh the latest Claim Items and expand the editor only.
         */
        if (!this.isEditorExpanded) {

            if (this.isLoading) {
                return;
            }

            this.isLoading = true;

            try {
                await this.refreshClaimItemsBeforeExpand();
                this.expandEditor();
            } finally {
                this.isLoading = false;
            }

            return;
        }

        /*
         * Existing behavior remains unchanged
         * after the editor is open.
         */
        if (!this.selectedRows.length) {
            this.showToast(
                'Warning',
                'Select at least one row first.',
                'warning'
            );

            return;
        }

        this.showMassUpdateModal = true;
    }

    closeMassUpdateModal() {
        this.showMassUpdateModal = false;
        this.massStatus = '';
        this.massReason = '';
        this.massCategory = '';
    }

    handleMassStatusChange(event) {
        this.massStatus = event.detail.value;
    }

    handleMassReasonChange(event) {
        this.massReason = event.detail.value;
    }

    handleMassCategoryChange(event) {
        this.massCategory = event.detail.value;
    }

    //commented out by Swastika on 15th sept 2026
    /*applyMassUpdate() {
        this.data = this.data.map((row) => {
            if (!this.selectedRows.includes(row.uniqueKey)) {
                return row;
            }

            const updatedRow = {
                ...row,
                Status__c: this.massStatus || row.Status__c,
                Reason__c: this.massReason || row.Reason__c,
                Category: this.massCategory || row.Category
            };

            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();
        this.showToast(
            'Success',
            'Selected rows were updated. Click Save Claim Items to commit the changes.',
            'success'
        );
        this.closeMassUpdateModal();
    }*/

    //added by Swastika on 15th sept 2026

    applyMassUpdate() {
        this.data = this.data.map((row) => {

            if (!this.selectedRows.includes(row.uniqueKey)) {
                return row;
            }

            let updatedRow = {
                ...row,
                Status__c: this.massStatus || row.Status__c,
                Reason__c: this.massReason || row.Reason__c,
                Category: this.massCategory || row.Category
            };


            if (this.massStatus) {

                if (
                    ['Denied', 'Requested', 'Cancelled'].includes(updatedRow.Status__c)
                ) {
                    updatedRow.Rate__cError = '';
                }

                if (
                    !INSPECTION_INVOICE_REQUIRED_STATUSES.includes(
                        updatedRow.Status__c
                    )
                ) {
                    updatedRow.Invoice_Number__cError = '';
                }
            }


            return this.updateRowPresentation(updatedRow);
        });

        this.markDirty();

        this.showToast(
            'Success',
            'Selected rows were updated. Click Save Claim Items to commit the changes.',
            'success'
        );

        this.closeMassUpdateModal();
    }

    async handleDeleteRow(event) {
        if (this.claimStatus === 'Closed') {
            this.showToast(
                'Error',
                'You must re-open the Claim before deleting Claim Items.',
                'error'
            );
            return;
        }

        const rowId = event.currentTarget.dataset.id;
        const rowToDelete = this.data.find((row) => row.uniqueKey === rowId);

        if (!rowToDelete) {
            return;
        }

        if (rowToDelete.Status__c === 'Paid') {
            this.showToast(
                'Error',
                'Cannot delete a Claim Item with status Paid.',
                'error'
            );
            return;
        }

        const confirmed = await LightningConfirm.open({
            label: 'Delete Claim Item',
            message: 'Are you sure you want to delete this Claim Item?',
            theme: 'warning'
        });

        if (!confirmed) {
            return;
        }

        const hadUnsavedChanges = this.isDirty;
        this.isLoading = true;

        try {
            if (rowToDelete.Id) {
                await deleteClaimItem({ claimItemId: rowToDelete.Id });
            }

            this.data = this.data.filter((row) => row.uniqueKey !== rowId);
            this.originalData = this.originalData.filter(
                (row) => row.uniqueKey !== rowId
            );
            this.selectedRows = this.selectedRows.filter((id) => id !== rowId);
            this.updateHeaderCheckboxState();

            if (!rowToDelete.Id) {
                this.markDirty();
            } else if (!hadUnsavedChanges) {
                await refreshApex(this.wiredResult);
            }

            this.showToast(
                'Success',
                'Claim Item deleted successfully.',
                'success'
            );
        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Error deleting Claim Item.',
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    async refreshCurrentConsoleTab() {
        try {
            if (this.isConsoleNavigation) {
                const focusedTab = await getFocusedTabInfo();
                await refreshTab(focusedTab.tabId, {
                    includeAllSubtabs: true
                });
            }
        } catch (error) {
            // A workspace refresh failure should not make a successful save fail.
            // eslint-disable-next-line no-console
            console.error('Error refreshing the current console tab.', error);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}