import { LightningElement, api, wire } from 'lwc';
import { getPicklistValues } from "lightning/uiObjectInfoApi";
import Ethnicity__c from '@salesforce/schema/VIN_Detail__c.Ethnicity__c';
import getRecordVINDetails from '@salesforce/apex/ClassGuideBuilderController.getRecords'
import updateVinClassRecords from '@salesforce/apex/ClassGuideBuilderController.updateVinClassRecords'
import getMakesList from '@salesforce/apex/ClassGuideBuilderController.getMakes'
import No_Data_Error from '@salesforce/label/c.Class_Guide_Builder_No_Data_Error'
import Too_Many_Query_Rows_Error from '@salesforce/label/c.Class_Guide_Builder_Too_Many_Query_Rows_Error'
import Validation_Error from '@salesforce/label/c.Class_Guide_Builder_Validation_Error'
import Validation_Error_New_Class_Guide from '@salesforce/label/c.Class_Guide_Builder_Validation_Error_New_Class_Guide'
import Validation_Error_All_MakesModels from '@salesforce/label/c.Class_Guide_Builder_Validation_Error_All_MakesModels'
import Class_Guide_Builder_Class_Length_Error from '@salesforce/label/c.Class_Guide_Builder_Class_Length_Error'
import Success_Message_Insert from '@salesforce/label/c.Class_Guide_Builder_Success_Message_Insert'
import Master_Record_Type from '@salesforce/label/c.Master_Record_Type'
import Success_Message from '@salesforce/label/c.Class_Guide_Builder_Success_Message'
import No_records_to_update from '@salesforce/label/c.No_records_to_update_error_message'
import getClassBuilderNames from '@salesforce/apex/ClassGuideBuilderController.getClassBuilderNames'
import Error_Message from '@salesforce/label/c.Error_Message'
import Error_Message_No_Rate_Class_Defined from '@salesforce/label/c.Error_Message_No_Rate_Class_Defined'

export default class ClassGuideBuilder extends LightningElement {
    @api filterName;

    valueEthnicity;
    valueTrims;
    valueEngines;
    valueCylinders
    valueAspiration;
    valueFuel;
    valueDrive;
    valueTonnage;
    valueBodyStyle;
    valueVINPrefix;
    valueRate;
    valueNewClassGuide;
    valuePartner;

    placeholderMakes;
    placeholderModels;
    placeholdererrorText;
    placeholderSuccessText;
    placeholerClassGuideName;

    showEthinicityPicklist = false;
    showMakesPicklist = false;
    showModelsPicklist = false;
    showTrimsPicklist = false;
    showEnginesPicklist = false;
    showCylindersPicklist = false;
    showAspirationPicklist = false;
    showFuelPicklist = false;
    showDrivePicklist = false;
    showTonnagePicklist = false;
    showBodyStylePicklist = false;
    selectAllmodels = false;
    selectAllMakes = false;
    isSelectAll = false;
    isError = false;
    isSuccess = false;
    showClassGuideBuilderFilters = false
    showNewClassGuideFields = false;
    isLoading = false;

    fieldMap = new Map();
    fieldMapForfield = new Map();

    @api optionsEthnicity = [];
    @api optionsMakes = [];
    @api optionsModels = [];
    @api optionsBodyStyle = [];
    @api optionsTrims = [];
    @api optionsEngines = [];
    @api optionsAspiration = [];
    @api optionsCylinders = [];
    @api optionsFuel = [];
    @api optionsDrive = [];
    @api optionsTonnage = [];
    optionsclassGuideName = [];

    returnedRecords = [];
    filteredRecords = [];
    vinClassRecords = [];

    @api optionsYearPickList = [];
    @api minYear;
    @api maxYear;

    //Fetches Picklist options from field Ethnicity on Vin Detail object
    @wire(getPicklistValues, { recordTypeId: Master_Record_Type, fieldApiName: Ethnicity__c })
    picklistResults({ error, data }) {
        if (data) {
            this.optionsEthnicity = data.values.map(opt => { return { "label": opt.label, "value": opt.value, "show": true, "checked": false } });
        }
    }

    // Sets fieldMapForfield with className: fieldapiname, fieldapiname defined api name of field to retrive it from data list returned by apex controller
    // Sets Picklist for Aspiration to pre-defined values
    connectedCallback() {
        this.fieldMapForfield.set('makes-input-checkbox', { fieldapiname: ["MDL_DESC__c", "BODY_STYLE_DESC__c"] });
        this.fieldMapForfield.set('select-all-makes-unchecked', { fieldapiname: ["MDL_DESC__c", "BODY_STYLE_DESC__c"] });
        this.fieldMapForfield.set('model-input-checkbox', { fieldapiname: ["TRIM_DESC__c", "ENG_MDL_DESC__c", "DRV_TYP_CD__c", "TRK_TNG_RAT_CD__c", "ENG_CLNDR_RTR_CNT__c", "ENG_FUEL_DESC__c"] });
        this.fieldMapForfield.set('select-all-models-unchecked', { fieldapiname: ["TRIM_DESC__c", "ENG_MDL_DESC__c", "DRV_TYP_CD__c", "TRK_TNG_RAT_CD__c", "ENG_CLNDR_RTR_CNT__c", "ENG_FUEL_DESC__c"] });
        this.fieldMapForfield.set('bodyStyle-input-checkbox', { fieldapiname: ["MDL_DESC__c"] });
        this.fieldMapForfield.set('trims-input-checkbox', { fieldapiname: ["ENG_MDL_DESC__c", "DRV_TYP_CD__c", "TRK_TNG_RAT_CD__c", "ENG_CLNDR_RTR_CNT__c", "ENG_FUEL_DESC__c"] });
        this.fieldMapForfield.set('engines-input-checkbox', { fieldapiname: ["ENG_CLNDR_RTR_CNT__c", "ENG_FUEL_DESC__c"] });

        this.optionsAspiration.push({ "label": 'Is Supercharged', "value": 'ENG_ASP_SUP_CHGR_CD__c', "show": true, "checked": false });
        this.optionsAspiration.push({ "label": 'Is Turbocharged', "value": 'ENG_ASP_TRBL_CHGR_CD__c	', "show": true, "checked": false });
        this.optionsAspiration.push({ "label": 'Normally Aspirated', "value": 'Normally_Aspirated', "show": true, "checked": false });

        getClassBuilderNames()
            .then(result => {
                this.optionsclassGuideName = result.map(value => { return { "label": value, "value": value } })
                this.optionsclassGuideName.push({ "label": "New Class Guide", "value": "NewClassGuide" })
            })
            .catch(error => {
                console.log(error.message);
            })
    }

    //Dynamically shows all options only if Class Guide Name is selected and if the value is changed, resets all values for below filters.
    handleclassGuideNameChange(event) {
        try {
            this.placeholerClassGuideName = event.detail.value;
            if (this.placeholerClassGuideName == 'NewClassGuide') {
                this.showNewClassGuideFields = true;
            }
            else {
                this.showNewClassGuideFields = false;
            }
            this.showClassGuideBuilderFilters = true;
            this.resetAllOptions(event.target.className);
        }
        catch (error) {
            console.log(error.message);
        }
    }

    newClassGuideChange(event) {
        this.valueNewClassGuide = event.detail.value;
    }

    partnerChange(event) {
        this.valuePartner = event.detail.value;
    }

    resetAllOptions(className) {
        if (className.includes('classGuideName')) {
            this.optionsEthnicity.forEach((option) => option.checked = false);
            this.valueEthnicity = '';
            this.valuePartner = '';
            this.valueNewClassGuide = '';
        }
        this.selectAllMakes = false;
        this.selectAllmodels = false
        this.makesValue = '';
        this.modelsValue = '';
        this.placeholderMakes = '';
        this.placeholderModels = '';
        this.valueTrims = '';
        this.valueEngines = '';
        this.valueCylinders = '';
        this.valueAspiration = '';
        this.valueFuel = '';
        this.valueDrive = '';
        this.valueTonnage = '';
        this.valueBodyStyle = '';
        this.valueVINPrefix = '';
        this.optionsMakes = [];
        this.optionsModels = [];
        this.optionsBodyStyle = [];
        this.optionsEngines = [];
        this.optionsCylinders = [];
        this.optionsFuel = [];
        this.optionsTrims = [];
        this.optionsDrive = [];
        this.optionsTonnage = [];
    }

    //Handles on visibility of picklist options when clicked on input box.
    showPicklistLogic(event) {
        if (event.target.className.includes('model-input')) {
            this.showModelsPicklist = !this.showModelsPicklist;
        }
        else if (event.target.className.includes('ethnicity-input')) {
            this.showEthinicityPicklist = !this.showEthinicityPicklist;
        }
        else if (event.target.className.includes('makes-input')) {
            this.showMakesPicklist = !this.showMakesPicklist;
        }
        else if (event.target.className.includes('bodyStyle-input')) {
            this.showBodyStylePicklist = !this.showBodyStylePicklist;
        }
        else if (event.target.className.includes('trim-input')) {
            this.showTrimsPicklist = !this.showTrimsPicklist;
        }
        else if (event.target.className.includes('engines-input')) {
            this.showEnginesPicklist = !this.showEnginesPicklist;
        }
        else if (event.target.className.includes('cylinders-input')) {
            this.showCylindersPicklist = !this.showCylindersPicklist;
        }
        else if (event.target.className.includes('fuel-input')) {
            this.showFuelPicklist = !this.showFuelPicklist;
        }
        else if (event.target.className.includes('drive-input')) {
            this.showDrivePicklist = !this.showDrivePicklist;
        }
        else if (event.target.className.includes('tonnage-input')) {
            this.showTonnagePicklist = !this.showTonnagePicklist;
        }
        else if (event.target.className.includes('aspiration-input')) {
            this.showAspirationPicklist = !this.showAspirationPicklist;
        }


    }

    //Handles Ethnicity Changes
    handleChangeEthnicity(event) {
        this.valueEthnicity = event.detail.value;
        this.resetAllOptions(event.target.className);
        this.getMakes();
    }

    //The function is called when any of the checkbox is selected. Based on from where the event happened re-renders the picklist values. 
    onSelect(event) {
        try {
            let optionsList = [];
            let tempOptions = [];
            let className = '';
            let data = '';
            if (event.target.className.includes('ethnicity-input-checkbox')) {
                tempOptions = this.optionsEthnicity;
                optionsList.push(this.optionsMakes);
                optionsList.push(this.optionsModels);
                this.resetAllOptions(event.target.className);
                className = 'ethnicity-input-checkbox';
            }
            else if (event.target.className.includes('makes-input-checkbox') || event.target.className.includes('select-all-makes')) {
                this.optionsModels = [];
                this.optionsBodyStyle = [];
                this.optionsEngines = [];
                this.optionsCylinders = [];
                this.optionsFuel = [];
                this.optionsTrims = [];
                this.optionsDrive = [];
                this.optionsTonnage = [];
                this.selectAllMakes = false;
                tempOptions = this.optionsMakes;
                optionsList.push(this.optionsModels);
                optionsList.push(this.optionsBodyStyle);
                className = 'makes-input-checkbox';
                if (event.target.className.includes('makes-input-checkbox')) {
                    this.onSelectCheck(event, this.optionsMakes);
                }
                else if (event.target.className.includes('select-all-makes-unchecked')) {
                    this.selectAllMakes = true;
                    this.selectAllOptions(this.optionsMakes);
                    className = 'select-all-makes-unchecked';
                }
                else {
                    this.selectAllMakes = false;
                    this.removeAll(this.optionsMakes);
                }

            }
            else if (event.target.className.includes('model-input-checkbox') || event.target.className.includes('select-all-models')) {
                this.optionsTrims = [];
                this.optionsEngines = [];
                this.optionsDrive = [];
                this.optionsTonnage = [];
                this.optionsCylinders = [];
                this.optionsFuel = [];
                this.selectAllmodels = false;
                tempOptions = this.optionsModels;
                
                className = 'model-input-checkbox';
                if (event.target.className.includes('model-input-checkbox')) {
                    this.onSelectCheck(event, this.optionsModels);
                    var itemCount = this.optionsModels.filter((element) => element.checked).length;
                    if (itemCount == 0 && this.optionsModels.length > 0) {
                        optionsList = [];
                    }
                    else{
                        optionsList.push(this.optionsTrims);
                        optionsList.push(this.optionsEngines);
                        optionsList.push(this.optionsDrive);
                        optionsList.push(this.optionsTonnage);
                        optionsList.push(this.optionsCylinders);
                        optionsList.push(this.optionsFuel);
                    }                    
                }
                else if (event.target.className.includes('select-all-models-unchecked')) {
                    optionsList.push(this.optionsTrims);
                    optionsList.push(this.optionsEngines);
                    optionsList.push(this.optionsDrive);
                    optionsList.push(this.optionsTonnage);
                    optionsList.push(this.optionsCylinders);
                    optionsList.push(this.optionsFuel);
                    this.selectAllmodels = true;
                    this.selectAllOptions(this.optionsModels);
                    className = 'select-all-models-unchecked';
                }
                else {
                    this.selectAllmodels = false;
                    this.removeAll(this.optionsModels);
                }
                tempOptions = this.optionsModels.filter(element => element.checked);
            }
            else if (event.target.className.includes('bodyStyle-input-checkbox')) {
                this.optionsModels = [];
                this.optionsEngines = [];
                this.optionsCylinders = [];
                this.optionsFuel = [];
                this.optionsTrims = [];
                this.optionsDrive = [];
                this.optionsTonnage = [];
                tempOptions = this.optionsBodyStyle;
                optionsList.push(this.optionsModels);
                className = 'bodyStyle-input-checkbox';
                this.onSelectCheck(event, this.optionsBodyStyle);
            }
            else if (event.target.className.includes('trims-input-checkbox')) {
                this.optionsEngines = [];
                this.optionsCylinders = [];
                this.optionsFuel = [];
                this.optionsDrive = [];
                this.optionsTonnage = [];
                tempOptions = this.optionsTrims;
                optionsList.push(this.optionsEngines);
                optionsList.push(this.optionsDrive);
                optionsList.push(this.optionsTonnage);
                optionsList.push(this.optionsCylinders);
                optionsList.push(this.optionsFuel);

                className = 'trims-input-checkbox';
                this.onSelectCheck(event, this.optionsTrims);
            }
            else if (event.target.className.includes('engines-input-checkbox')) {
                this.optionsCylinders = [];
                this.optionsFuel = [];
                tempOptions = this.optionsEngines;
                optionsList.push(this.optionsCylinders);
                optionsList.push(this.optionsFuel);
                className = 'engines-input-checkbox';

                this.onSelectCheck(event, this.optionsEngines);
                tempOptions = this.optionsEngines.filter(element => element.checked);
            }
            else if (event.target.className.includes('fuel-input-checkbox')) {
                className = 'fuel-input-checkbox';

                this.onSelectCheck(event, this.optionsFuel);
            }
            else if (event.target.className.includes('cylinders-input-checkbox')) {
                className = 'cylinders-input-checkbox';

                this.onSelectCheck(event, this.optionsCylinders);
            }
            else if (event.target.className.includes('drive-input-checkbox')) {
                className = 'drive-input-checkbox';

                this.onSelectCheck(event, this.optionsDrive);
            }
            else if (event.target.className.includes('tonnage-input-checkbox')) {
                className = 'tonnage-input-checkbox';

                this.onSelectCheck(event, this.optionsTonnage);
            }
            else if (event.target.className.includes('aspiration-input-checkbox')) {
                className = 'aspiration-input-checkbox';
                this.onSelectCheck(event, this.optionsAspiration);
            }
            if (!className == '' && !className.includes('ethnicity-input-checkbox') && !className.includes('makes-input-checkbox') && !className.includes('select-all-makes-unchecked')) {
                data = this.filterData(this.filteredRecords, this.optionsMakes, this.optionsBodyStyle, this.optionsModels, this.optionsTrims, this.optionsEngines, this.optionsCylinders, this.optionsFuel, this.optionsDrive, this.optionsTonnage, this.optionsAspiration, '', '');
                optionsList.forEach((option, index) => this.populatePicklist(this.fieldMapForfield.get(className).fieldapiname[index], option, data, optionsList, index));
                this.setPlaceHolders(className);
            }
            else if (!className == '' && (className.includes('makes-input-checkbox') || className.includes('select-all-makes-unchecked'))) {
                this.setPlaceHolders(className);
                this.postSelect();
            }
            if (data.length == 0 && !className.includes('ethnicity-input-checkbox') && !className.includes('makes-input-checkbox') && !className.includes('select-all-makes-unchecked')) {
                this.isError = true;
                this.placeholdererrorText = No_Data_Error;
            }
            else if (!data.length == 0) {
                this.isError = false;
            }
        }
        catch (error) {
            console.log(error.message);
        }
    }

    //The function  is used to filter the data based on the selected options. The data is received from apex controller only when Ethnicity, and makes and called only once
    filterData(data, makes, bodyStyle, model, trims, engines, cylinders, fuel, drive, tonnage, aspiration, vinPrefix, rateClass) {
        try {
            if (makes != '' && makes != null) {
                let selectedOptions = makes.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.MAK_NM__c;
                        return selectedOptions.some(option => fieldValue && fieldValue.toString().toLowerCase() === option.value.toLowerCase()
                        );
                    });
                }
            }
            if (bodyStyle != '' && bodyStyle != null) {
                let selectedOptions = bodyStyle.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.BODY_STYLE_DESC__c;
                        return selectedOptions.some(option =>
                            fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase())
                        );
                    });
                }
            }
            if (model != '' && model != null) {
                let selectedOptions = model.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.MDL_DESC__c;
                        return selectedOptions.some(option =>
                            fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase())
                        );
                    });
                }
            }
            if (trims != '' && trims != null) {
                let selectedOptions = trims.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.TRIM_DESC__c;
                        return selectedOptions.some(option => {
                            if (option.value == '') {
                                return fieldValue == undefined;
                            }
                            else {
                                return fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase());
                            }
                        }
                        );
                    });
                }
            }
            if (engines != '' && engines != null) {
                let selectedOptions = engines.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.ENG_MDL_DESC__c;
                        return selectedOptions.some(option => {
                            if (option.value == '') {
                                return fieldValue == undefined;
                            }
                            else {
                                return fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase());
                            }
                        }

                        );
                    });
                }
            }
            if (cylinders != '' && cylinders != null) {
                let selectedOptions = cylinders.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.ENG_CLNDR_RTR_CNT__c;
                        return selectedOptions.some(option => {
                            if (option.value == '') {
                                return fieldValue == undefined;
                            }
                            else {
                                return fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase());
                            }
                        }

                        );
                    });
                }
            }
            if (fuel != '' && fuel != null) {
                let selectedOptions = fuel.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.ENG_FUEL_DESC__c;
                        return selectedOptions.some(option => {
                            if (option.value == '') {
                                return fieldValue == undefined;
                            }
                            else {
                                return fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase());
                            }
                        }

                        );
                    });
                }
            }
            if (drive != '' && drive != null) {
                let selectedOptions = drive.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.DRV_TYP_CD__c;
                        return selectedOptions.some(option => {
                            if (option.value == '') {
                                return fieldValue == undefined;
                            }
                            else {
                                return fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase());
                            }
                        }

                        );
                    });
                }
            }
            if (tonnage != '' && tonnage != null) {
                let selectedOptions = tonnage.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    data = data.filter(record => {
                        const fieldValue = record.TRK_TNG_RAT_CD__c;
                        return selectedOptions.some(option => {
                            if (option.value == '') {
                                return fieldValue == undefined;
                            }
                            else {
                                return fieldValue && (fieldValue.toString().toLowerCase() === option.value.toLowerCase());
                            }
                        }

                        );
                    });
                }
            }
            if (aspiration != '' && aspiration != null) {
                let dataAspiration = [];
                let dataSuperCharge = [];
                let dataTurbocharge = [];
                let dataTemp = [];
                let selectedOptions = aspiration.filter((element) => element.checked);
                if (!selectedOptions.length == 0) {
                    this.optionsAspiration.forEach(option => {
                        if (option.label == 'Normally Aspirated' && option.checked == true) {
                            dataAspiration = data.filter(record => {
                                return record.ENG_ASP_SUP_CHGR_CD__c == !option.checked && record.ENG_ASP_TRBL_CHGR_CD__c == !option.checked;
                            });
                        }
                        else if (option.label == 'Is Supercharged' && option.checked == true) {
                            dataSuperCharge = data.filter(record => {
                                return record.ENG_ASP_SUP_CHGR_CD__c == option.checked;
                            });
                        }
                        else if (option.label == 'Is Turbocharged' && option.checked == true) {
                            dataTurbocharge = data.filter(record => {
                                return record.ENG_ASP_TRBL_CHGR_CD__c == option.checked;
                            });
                        }

                    });
                    dataTemp = [...dataAspiration, ...dataSuperCharge, ...dataTurbocharge];
                    data = dataTemp;
                }
            }
            if (vinPrefix != '' && vinPrefix != null) {
                data = data.filter(record => {
                    const fieldValue = record.VIN_SIGNI_PATTRN_MASK__c;
                    return fieldValue.startsWith(this.valueVINPrefix);
                });
            }
            return data;
        }
        catch (error) {
            console.log(error.message);
        }

    }

    //Select all options if All Makes or All Models selected
    selectAllOptions(options) {
        try {
            options.forEach(element => element.checked = true);
        }
        catch (error) {
            console.log(error.message);
        }
    }

    //Select the checkbox for the selected option
    onSelectCheck(event, options) {
        try {
            options.find(option => option.label === event.target.value).checked = event.target.checked;
        }
        catch (error) {
            console.log(error.message);
        }

    }

    //handles onChange for Vin Prefix and Rate Class input
    populateOptionsText(event) {
        if (event.target.className.includes('vinPrefix-input')) {
            this.valueVINPrefix = event.target.value;
        }
        else if (event.target.className.includes('rateClass-input')) {
            this.valueRateClass = event.target.value;
        }
    }

    // Handles onclick of the Save button. First, filters the data based on selection from user. Then calls updateVinClass from apex controller and updates the vinclass
    saveClassGuide(event) {
        try {
            if ((this.valuePartner == '' || this.valueNewClassGuide == '' || this.valuePartner == undefined || this.valueNewClassGuide == undefined) && this.placeholerClassGuideName == 'NewClassGuide') {
                this.isError = true;
                this.placeholdererrorText = Validation_Error_New_Class_Guide;
            }
            else if (this.valueEthnicity == '' || this.valueEthnicity == undefined || this.makesValue == '' || this.makesValue == undefined || this.modelsValue == '' || this.modelsValue == undefined) {
                this.isError = true;
                this.placeholdererrorText = Validation_Error;
            }
            else if ( (this.makesValue == 'All Makes' && this.modelsValue == 'All Models') && (this.valueTrims == '' && this.valueDrive == '' && this.valueAspiration == '' && this.valueCylinders == '' && this.valueFuel == '' && this.valueDrive == '' && this.valueTonnage == '')){
                this.isError = true;
                this.placeholdererrorText = Validation_Error_All_MakesModels;
            }
            else if( this.valueRateClass != undefined && this.valueRateClass.length > 5 ){
                this.isError = true;
                this.placeholdererrorText = Class_Guide_Builder_Class_Length_Error;
            }
            else {
                this.isError = false;
                this.placeholdererrorText = '';
                let data = [];
                data = this.filterData(this.filteredRecords, this.optionsMakes, this.optionsBodyStyle, this.optionsModels, this.optionsTrims, this.optionsEngines, this.optionsCylinders, this.optionsFuel, this.optionsDrive, this.optionsTonnage, this.optionsAspiration, this.valueVINPrefix, '');
                this.updateVinClassRecord(data);
            }
        }
        catch (error) {
            console.log(error.message);
        }

    }

    // Creates picklist options dynamically based on the filtered data
    populatePicklist(className, options, result, optionsList, index) {
        try {
            optionsList[index].length = 0;
            let optionsModelSet = new Set();
            result.forEach(element => {
                if (element[className] == undefined) {
                    optionsModelSet.add('');
                }
                else {
                    optionsModelSet.add(element[className]);
                }

            });
            optionsModelSet.forEach((element) => {
                if (element == '') {
                    optionsList[index].push({ "label": '', "value": '', "show": true, "checked": false });
                }
                else {
                    optionsList[index].push({ "label": element, "value": element, "show": true, "checked": false });
                }
            });

        }
        catch (error) {
            console.log(error.message);
        }
    }

    // Handles the values to be shown in input box
    setPlaceHolders(className) {
        var itemCount = this.optionsMakes.filter((element) => element.checked).length;
        if (itemCount == this.optionsMakes.length && this.optionsMakes.length > 0) {
            this.selectAllMakes = true;
            this.makesValue = 'All Makes';
        }
        else {
            this.selectAllMakes = false;
            this.makesValue = this.optionsMakes.filter((element) => element.checked).map(element => element.label).join(', ');
        }
        itemCount = this.optionsModels.filter((element) => element.checked).length;
        if (itemCount == this.optionsModels.length && this.optionsModels.length > 0) {
            this.selectAllmodels = true;
            this.modelsValue = 'All Models';
        }
        else {
            this.selectAllmodels = false;
            this.modelsValue = this.optionsModels.filter((element) => element.checked).map(element => element.label).join(', ');
        }
        this.placeholderMakes = this.optionsMakes.filter((element) => element.checked).map(element => element.label).join(', ');
        this.placeholderModels = this.optionsModels.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueBodyStyle = this.optionsBodyStyle.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueTrims = this.optionsTrims.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueEngines = this.optionsEngines.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueAspiration = this.optionsAspiration.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueCylinders = this.optionsCylinders.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueFuel = this.optionsFuel.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueDrive = this.optionsDrive.filter((element) => element.checked).map(element => element.label).join(', ');
        this.valueTonnage = this.optionsTonnage.filter((element) => element.checked).map(element => element.label).join(', ');
    }

    // Removes check from all checkbox if user deselects All Makes or All Models
    removeAll(options) {
        options.forEach((option) => option.checked = false);
    }

    //Function calls getRecordVINDetails in apex controller to fetch the Vin detail records and returns the records.
    postSelect() {
        try {
            getRecordVINDetails({ ethnicity: this.valueEthnicity, makes: this.placeholderMakes })
                .then(result => {
                    this.returnedRecords = result;
                    this.filteredRecords = result;
                    this.optionsModels = [];
                    this.selectAllmodels = false;
                    let optionsModelsSet = new Set();
                    result.forEach(element => {
                        if (element != 'All Models') {
                            optionsModelsSet.add(element.MDL_DESC__c);
                        }
                    });
                    optionsModelsSet.forEach((element) => {
                        this.optionsModels.push({ "label": element, "value": element, "show": true, "checked": false });
                    });
                    this.optionsBodyStyle = [];
                    let optionsBodyStyleSet = new Set();
                    result.forEach(element => optionsBodyStyleSet.add(element.BODY_STYLE_DESC__c));
                    optionsBodyStyleSet.forEach((element) => {
                        this.optionsBodyStyle.push({ "label": element, "value": element, "show": true, "checked": false });
                    });
                    if (result.length == 0) {
                        this.isError = true;
                        this.placeholdererrorText = No_Data_Error;
                    }
                    else {
                        this.isError = false;
                        this.placeholdererrorText = '';
                    }
                })
                .catch(error => {
                    if (error.body.message == 'Too many query rows: 50001') {
                        this.isError = true;
                        this.placeholdererrorText = Too_Many_Query_Rows_Error;
                    }
                    console.log(error.body.message);
                });

        }
        catch (error) {
            console.log(error.message);
        }


    }

    //Function handles the update of Vin Class records for given Class Guide name and filtered data.
    updateVinClassRecord(data) {
        try {
            this.isLoading = true;
            var countSuccess = 0;
            if (data.length == 0) {
                this.isLoading = false;
                this.isError = true;
                this.placeholdererrorText = No_records_to_update;
            }
            else if (data.length > 50000) {
                this.isLoading = false;
                this.isError = true;
                this.placeholdererrorText = Too_Many_Query_Rows_Error;
            }

            else {
                const totalBatches = Math.ceil(data.length / 10000);
                for (let i = 0; i < totalBatches; i++) {
                    const batch = data.slice(i * 10000, (i + 1) * 10000);
                    try {
                        updateVinClassRecords({ classGuideName: this.placeholerClassGuideName, vinDetailIdString: batch, ethnicity: this.valueEthnicity, makes: this.makesValue, models: this.modelsValue, rateClass: this.valueRateClass, vinPrefix: this.valueVINPrefix, valueTrims: this.valueTrims, valueEngines: this.valueEngines, valueCylinders: this.valueCylinders, valueAspiration: this.valueAspiration, valueFuel: this.valueFuel, valueDrive: this.valueDrive, valueTonnage: this.valueTonnage, valueBodyStyle: this.valueBodyStyle, valuePartner: this.valuePartner, valueNewClassGuide: this.valueNewClassGuide })
                            .then(result => {
                                if (result == Success_Message || result == Success_Message_Insert) {
                                    countSuccess = countSuccess + 1;
                                    if (countSuccess == totalBatches) {
                                        this.isLoading = false;
                                        this.isSuccess = true;
                                        this.placeholderSuccessText = result == Success_Message ? Success_Message : Success_Message_Insert;
                                        setTimeout(() => {
                                            this.isSuccess = false;
                                            this.placeholderSuccessText = '';
                                            if (this.placeholerClassGuideName == 'NewClassGuide') {
                                                window.location.reload();
                                            }
                                        }, 5000);
                                        this.clearValuesAndOption();
                                    }
                                }
                                else if (result == No_records_to_update) {
                                    this.isLoading = false;
                                    this.isError = true;
                                    this.placeholdererrorText = No_records_to_update;
                                    setTimeout(() => {
                                        this.isError = false;
                                        this.placeholderSuccessText = '';
                                    }, 5000);
                                }
                                else {
                                    this.isLoading = false;
                                }
                            })
                            .catch(error => {
                                this.isLoading = false;
                                if (error.body.message == 'Too many query rows: 50001') {
                                    this.isError = true;
                                    this.placeholdererrorText = Too_Many_Query_Rows_Error;
                                }
                                else if (error.body.message == 'No Rate Class Defined') {
                                    this.isError = true;
                                    this.placeholdererrorText = Error_Message_No_Rate_Class_Defined;
                                }
                                else {
                                    this.isError = true;
                                    this.placeholdererrorText = Error_Message;
                                }
                                setTimeout(() => {
                                    this.isError = false;
                                    this.placeholdererrorText = '';
                                }, 5000);
                            })
                    }
                    catch (error) {
                        this.isLoading = false;
                        console.error(`Error in batch ${i + 1}:`, JSON.stringify(error.message));
                    }
                }
            }
        }
        catch (error) {
            this.isLoading = false;
            console.log(error.message);
        }

    }

    //This clear the values and option from the picklist and text box (except ethnicity and makes)
    clearValuesAndOption(className) {
        this.optionsModels.forEach((option) => option.checked = false);
        this.optionsBodyStyle.forEach((option) => option.checked = false);
        this.optionsAspiration.forEach((option) => option.checked = false);

        this.placeholderModels = '';
        this.modelsValue = '';
        this.valueTrims = '';
        this.valueEngines = '';
        this.valueCylinders = '';
        this.valueAspiration = '';
        this.valueFuel = '';
        this.valueDrive = '';
        this.valueTonnage = '';
        this.valueBodyStyle = '';
        this.valueVINPrefix = '';
        this.valueRateClass = '';
        
        this.optionsEngines = [];
        this.optionsCylinders = [];
        this.optionsFuel = [];
        this.optionsTrims = [];
        this.optionsDrive = [];
        this.optionsTonnage = [];
    }

    getMakes() {
        try {
            getMakesList({ ethnicity: this.valueEthnicity })
                .then(result => {
                    this.returnedRecords = result;
                    this.filteredRecords = result;
                    this.optionsMakes = [];
                    let optionsMakesSet = new Set();
                    result.forEach(element => {
                        if (element.Label != 'All Makes') {
                            optionsMakesSet.add(element.Label);
                        }
                    });
                    optionsMakesSet.forEach((element) => {
                        this.optionsMakes.push({ "label": element, "value": element, "show": true, "checked": false });
                    });
                    if (result.length == 0) {
                        this.isError = true;
                        this.placeholdererrorText = No_Data_Error;
                    }
                    else {
                        this.isError = false;
                        this.placeholdererrorText = '';
                    }
                })
                .catch(error => {
                    if (error.body.message == 'Too many query rows: 50001') {
                        this.isError = true;
                        this.placeholdererrorText = Too_Many_Query_Rows_Error;
                    }
                    console.log(error.body.message);
                });
        }
        catch (error) {
            console.log(error.message);
        }
    }
}