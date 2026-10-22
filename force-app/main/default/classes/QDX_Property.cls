/*
* @author Qamar Islam (https://github.com/qislam)
* @description This class is for standard property.
*/
public with sharing class QDX_Property {
    public String value {
        get {
            if (this.value == null) {
                this.value = this.textValue;
            }
            return this.value;
        }
        private set;
    }

    public String textValue {
        get {
            if (this.textValue == null) {
                this.textValue = this.selectedProperty?.TextValue__c;
                if (String.isNotBlank(this.selectedProperty?.LongTextValue__c)) {
                    this.textValue = this.selectedProperty?.LongTextValue__c;
                }
                if (this.textValue == null) { this.textValue = ''; }
            }
            return this.textValue;
        }
        private set;
    }

    public String shortValue {
        get {
            if (this.shortValue == null) {
                this.shortValue = this.selectedProperty?.TextValue__c;
                if (this.shortValue == null) {
                    this.shortValue = '';
                }
            }
            return this.shortValue;
        }
        private set;
    }

    public String text1 {
        get {
            if (this.text1 == null) {
                this.text1 = this.selectedProperty?.Text_1__c;
                if (this.text1 == null) {
                    this.text1 = '';
                }
            }
            return this.text1;
        }
        private set;
    }

    public String text2 {
        get {
            if (this.text2 == null) {
                this.text2 = this.selectedProperty?.Text_2__c;
                if (this.text2 == null) {
                    this.text2 = '';
                }
            }
            return this.text2;
        }
        private set;
    }

    public String text3 {
        get {
            if (this.text3 == null) {
                this.text3 = this.selectedProperty?.Text_3__c;
                if (this.text3 == null) {
                    this.text3 = '';
                }
            }
            return this.text3;
        }
        private set;
    }

    public String text4 {
        get {
            if (this.text4 == null) {
                this.text4 = this.selectedProperty?.Text_4__c;
                if (this.text4 == null) {
                    this.text4 = '';
                }
            }
            return this.text4;
        }
        private set;
    }

    public Decimal numberValue {
        get {
            if (this.numberValue == null) {
                this.numberValue = this.selectedProperty?.NumberValue__c;
                if (this.numberValue == null) {
                    this.numberValue = 0;
                }
            }
            return this.numberValue;
        }
        private set;
    }

    public Boolean isActive {
        get {
            if (this.isActive == null) {
                this.isActive = this.selectedProperty?.isActive__c;
                if (this.isActive == null) { this.isActive = false; }
            }
            return this.isActive;
        }
        private set;
    }

    public Boolean isFound {
        get {
            if (this.isFound == null) {
                this.isFound = false;
                if (this.selectedProperty != null) { this.isFound = true; }
            }
            return this.isFound;
        }
        private set;
    }

    public DateTime dateTimeField {
        get {
            if (this.dateTimeField == null) {
                this.dateTimeField = this.selectedProperty?.DateTimeValue__c;
                if (this.dateTimeField == null) { this.dateTimeField = null; }
            }
            return this.dateTimeField;
        }
        private set;
    }

    public static QDX_Property forLabel(String propertyLabel) {
        return new QDX_Property(propertyLabel);
    }

    @AuraEnabled
    public static string propValueForLabel(String propertyLabel){
        return QDX_Property.forLabel(propertyLabel).value;
    }

    @InvocableMethod(label='Property Value For Label' description='Returns the property value for the given label')
    public static String[] propValueForLabel(String[] propertyLabels) {
        return new String[]{QDX_Property.forLabel(propertyLabels[0]).value};
    }

    public QDX_Property__mdt selectedProperty;
    @TestVisible private static QDX_Property__mdt testProperty;

    public QDX_Property(String propertyLabel) {
        System.Domain domainObj = DomainParser.parse(URL.getSalesforceBaseUrl().toExternalForm());
        String sandboxName = domainObj.getSandboxName();
        String instanceName = sandboxName == null ? 'PRODUCTION' : sandboxName.toUpperCase();

        QDX_Property__mdt[] properties = [
            SELECT DeveloperName
            , Label
            , MasterLabel
            , TextValue__c
            , LongTextValue__c
            , NumberValue__c
            , isActive__c
            , isDefault__c
            , ProfileId__c
            , UserName__c
            , QDX_SF_Instance__c
            , QDX_SF_Instance__r.DeveloperName
            , Text_1__c
            , Text_2__c
            , Text_3__c
            , Text_4__c
            , DateTimeValue__c
            FROM QDX_Property__mdt
            WHERE Label = :propertyLabel
            ORDER BY UserName__c NULLS LAST
            , ProfileId__c NULLS LAST
            , QDX_SF_Instance__c NULLS LAST
        ];

        if (Test.isRunningTest() && testProperty != null) {
            properties.add(testProperty);
        }

        for (QDX_Property__mdt current : properties) {
            if (current.UserName__c == UserInfo.getUserName() && current.QDX_SF_Instance__r.DeveloperName == instanceName) { selectedProperty = current; break; }
            
            if (current.ProfileId__c == UserInfo.getProfileId() && current.QDX_SF_Instance__r.DeveloperName == instanceName) { selectedProperty = current; break; }
            
            if (String.isBlank(current.UserName__c) && String.isBlank(current.ProfileId__c) && current.QDX_SF_Instance__r.DeveloperName == instanceName) { selectedProperty = current; break; }
            
            if (current.isDefault__c) {
                selectedProperty = current;
            }
        }
    }
}