@IsTest(SeeAllData=true)
public class BRELoggerTest {

    @IsTest
    static void testLogWithAllValues() {

        List<Map<String, Object>> parameters = new List<Map<String, Object>>();

        Map<String, Object> param1 = new Map<String, Object>();
        param1.put('contractNumber', 'CON-001');
        param1.put('amount', 15000);
        param1.put('status', 'Active');

        parameters.add(param1);

        Test.startTest();

        BRELogger.log(
            'Base Reserve Rule',
            'Pricing',
            'BRE Callout',
            250,
            'Success',
            false,
            parameters,
            'BRELoggerTest',
            'testLogWithAllValues',
            'https://test.salesforce.com/bre/api',
            'CON-001'
        );

        Test.stopTest();
    }

    @IsTest
    static void testLogWithNullAndBlankValues() {

        Test.startTest();

        BRELogger.log(
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            '',
            '',
            null,
            null
        );

        Test.stopTest();
    }

    @IsTest
    static void testLogMultipleTimesForMethodCounter() {

        List<Map<String, Object>> parameters = new List<Map<String, Object>>();

        Map<String, Object> param1 = new Map<String, Object>();
        param1.put('inputName', 'Rate Code');
        param1.put('inputValue', 'RC001');

        parameters.add(param1);

        Test.startTest();

        BRELogger.log(
            'Rate Code Rule',
            'Rate',
            'BRE Callout',
            100,
            'Success',
            true,
            parameters,
            'BRELoggerTest',
            'sameMethodCall',
            'https://test.salesforce.com/bre/rate',
            'CON-002'
        );

        BRELogger.log(
            'Rate Code Rule',
            'Rate',
            'BRE Callout',
            120,
            'Success',
            true,
            parameters,
            'BRELoggerTest',
            'sameMethodCall',
            'https://test.salesforce.com/bre/rate',
            'CON-002'
        );

        Test.stopTest();
    }

    @IsTest
    static void testLogWithEmptyParameterList() {

        List<Map<String, Object>> parameters = new List<Map<String, Object>>();

        Test.startTest();

        BRELogger.log(
            'Empty Parameter Rule',
            'Validation',
            'Internal Call',
            50,
            'Completed',
            false,
            parameters,
            'BRELoggerTest',
            'testLogWithEmptyParameterList',
            'https://test.salesforce.com/bre/validate',
            'CON-003'
        );

        Test.stopTest();
    }
}