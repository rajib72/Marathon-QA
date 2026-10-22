import LightningDatatable from 'lightning/datatable';

import picklistTemplate
from './picklistTemplate.html';

export default class ClaimItemDatatable
extends LightningDatatable {

    static customTypes = {

        picklist: {

            template: picklistTemplate,

            standardCellLayout: true,

            typeAttributes: [
                'placeholder',
                'options',
                'value',
                'context',
                'fieldName'
            ]
        }
    };
}