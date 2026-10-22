import {
    LightningElement,
    api
} from 'lwc';

import rescindPayment
    from '@salesforce/apex/PaymentRescindController.rescindPayment';

import {
    ShowToastEvent
} from 'lightning/platformShowToastEvent';

import {
    CloseActionScreenEvent
} from 'lightning/actions';

import {
    RefreshEvent
} from 'lightning/refresh';

import {
    notifyRecordUpdateAvailable
} from 'lightning/uiRecordApi';


export default class PaymentRescindAction
    extends LightningElement {

    @api
    recordId;

    isLoading = false;


    async handleRescind() {

        if (
            !this.recordId ||
            this.isLoading
        ) {
            return;
        }

        this.isLoading = true;

        try {

            const result =
                await rescindPayment({
                    paymentId:
                        this.recordId
                });

            if (
                result &&
                result.success
            ) {

                this.showToast(
                    'Success',
                    result.message ||
                    'Payment cancelled successfully.',
                    'success'
                );

                /*
                 * Apex updated Payment__c directly.
                 * Notify Lightning Data Service so components
                 * displaying the Payment receive fresh data.
                 */
                await notifyRecordUpdateAvailable([
                    {
                        recordId:
                            this.recordId
                    }
                ]);

                /*
                 * Refresh the record page.
                 */
                this.dispatchEvent(
                    new RefreshEvent()
                );

                /*
                 * Close Quick Action.
                 */
                this.dispatchEvent(
                    new CloseActionScreenEvent()
                );

            } else {

                this.showToast(
                    'Error',
                    'Cancellation request was unable to be processed',
                    'error'
                );
            }

        } catch (error) {

            console.error(
                'Payment rescind error:',
                error
            );

            this.showToast(
                'Error',
                this.getErrorMessage(
                    error
                ),
                'error'
            );

        } finally {

            this.isLoading =
                false;
        }
    }


    handleClose() {

        if (
            this.isLoading
        ) {
            return;
        }

        this.dispatchEvent(
            new CloseActionScreenEvent()
        );
    }


    getErrorMessage(
        error
    ) {

        if (
            error &&
            error.body &&
            error.body.message
        ) {
            return error.body.message;
        }

        return 'Cancellation request was unable to be processed';
    }


    showToast(
        title,
        message,
        variant
    ) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}