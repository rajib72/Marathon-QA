import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

// Fields from Claim object
const FIELDS = [
    'Claim.Mileage_Validation_Message__c',
    'Claim.Mileage_Validation_Status__c'
];

export default class ClaimMileageErrorBanner extends LightningElement {
    @api recordId;

    showError = false;
    message;
    title;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            const message = data.fields.Mileage_Validation_Message__c.value;
            const status = data.fields.Mileage_Validation_Status__c.value;

            if (message) {
                this.message = message;
                this.title = this.getTitle(status);
                this.showError = true;
            } else {
                this.showError = false;
            }
        } else if (error) {
            // Debugging
            console.error('Error fetching Claim record:', error);
        }
    }

    getTitle(status) {
        if (status === 'Below Waiting Period') {
            return 'Waiting Period Warning';
        }
        if (status === 'Exceeded Mileage') {
            return 'Mileage Limit Exceeded';
        }
        return 'Warning';
    }

    handleClose() {
        this.showError = false;
    }
}