import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab
} from 'lightning/platformWorkspaceApi';

export default class ClaimReimbursementLetterAction extends LightningElement {

    @api recordId;

    @wire(IsConsoleNavigation)
    isConsoleNavigation;

    isExecuting = false;

    @api
    invoke() {

        if (this.isExecuting) {
            return;
        }

        this.isExecuting = true;

        this.launchOmniScript()
            .catch((error) => {

                // eslint-disable-next-line no-console
                console.error(
                    'Unable to launch Claim Reimbursement Letter.',
                    error
                );

                this.showToast(
                    'Error',
                    'Unable to open Claim Reimbursement Letter.',
                    'error'
                );
            })
            .finally(() => {

                this.isExecuting = false;
            });
    }

    async launchOmniScript() {

        if (!this.recordId) {

            throw new Error(
                'Claim record Id is not available.'
            );
        }

        const omniScriptUrl =
            this.buildOmniScriptUrl();

        /*
         * Salesforce Console:
         * Open the OmniScript as a subtab beneath
         * the currently focused Claim tab.
         */
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

        /*
         * Standard Lightning navigation:
         * Open OmniScript in a new browser tab.
         */
        window.open(
            omniScriptUrl,
            '_blank',
            'noopener'
        );
    }

    buildOmniScriptUrl() {

        const params = new URLSearchParams({

            omniscript__type:
                'Claim',

            omniscript__subType:
                'GenerateReimbursementLetter',

            omniscript__language:
                'English',

            omniscript__theme:
                'lightning',

            omniscript__tabIcon:
                'custom:custom18',

            omniscript__tabLabel:
                'Claim - Reimbursement Letter',

            c__ContextId:
                this.recordId
        });

        return (
            '/lightning/page/omnistudio/omniscript?' +
            params.toString()
        );
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