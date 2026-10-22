@isTest
public with sharing class QDX_PropertyTest {
    @isTest static void itShouldReturnPropertyValue() {
        QDX_Property__mdt testProperty = new QDX_Property__mdt();
        testProperty.Label = 'TestProperty';
        testProperty.DeveloperName = 'TestProperty';
        testProperty.LongTextValue__c = 'Test value';
        testProperty.isDefault__c = true;

        QDX_Property.testProperty = testProperty;
        
        String myValue = QDX_Property.forLabel('TestProperty').value;
        Boolean isActive = QDX_Property.forLabel('TestProperty').isActive;
        Decimal myNumber = QDX_Property.forLabel('TestProperty').numberValue;
        String textValue = QDX_Property.forLabel('TestProperty').shortValue;
        Boolean foundRecord = QDX_Property.forLabel('TestProperty').isFound;

        System.assert(myValue == 'Test Value', 'No value found');
        System.assert(isActive == false, 'No boolean found');
        System.assert(myNumber == 0, 'No number found');
        
        //
        System.assert(
            QDX_Property.forLabel('TestProperty').text1 == '' &&
            QDX_Property.forLabel('TestProperty').text2 == '' &&
            QDX_Property.forLabel('TestProperty').text3 == '' &&
            QDX_Property.forLabel('TestProperty').text4 == '', 'Text fields are not empty');
        
        //
        String singleValue = QDX_Property.propValueForLabel('TestProperty');
        System.assert(singleValue == 'Test value', 'Single property value is incorrect');
        
        String[] multipleValues = QDX_Property.propValueForLabel(new String[]{'Test Property'});
        System.assert(multipleValues.size() == 1, 'List size mismatch');
        System.assert(multipleValues[0] == 'Test value', 'List property value is incorrect');
    }
}