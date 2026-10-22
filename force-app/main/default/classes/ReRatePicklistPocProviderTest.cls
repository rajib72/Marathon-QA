/**
 * @description Verifies the contract of the Phase 1 native OmniScript
 *              Select provider without creating or modifying org data.
 */
@IsTest
private class ReRatePicklistPocProviderTest {

    private static Map<String, Object> makeArgs(Map<String, Object> output) {
        return new Map<String, Object> {
            'input' => new Map<String, Object> { 'LanguageCode' => 'en_US' },
            'output' => output,
            'options' => new Map<String, Object>()
        };
    }

    @IsTest
    static void testTermMonthsOptions() {
        Map<String, Object> output = new Map<String, Object>();

        Test.startTest();
        Object result = new ReRatePicklistPocProvider().call(
            'getTermMonths', makeArgs(output)
        );
        Test.stopTest();

        System.assertEquals(true, result, 'Term Months action must succeed.');
        System.assert(output.containsKey('options'), 'Expected options key.');

        List<Map<String, String>> options =
            (List<Map<String, String>>) output.get('options');
        System.assertEquals(3, options.size(), 'Expected three month values.');
        System.assertEquals('12', options[0].get('name'));
        System.assertEquals('12 months', options[0].get('value'));
        System.assertEquals('24', options[1].get('name'));
        System.assertEquals('36', options[2].get('name'));
    }

    @IsTest
    static void testTermMilesDependency() {
        Map<String, Object> output = new Map<String, Object>();

        Test.startTest();
        Object result = new ReRatePicklistPocProvider().call(
            'getTermMiles', makeArgs(output)
        );
        Test.stopTest();

        System.assertEquals(true, result, 'Term Miles action must succeed.');
        System.assert(output.containsKey('dependency'), 'Expected dependency key.');

        Map<String, List<Map<String, String>>> dependency =
            (Map<String, List<Map<String, String>>>) output.get('dependency');

        System.assertEquals(3, dependency.size());
        System.assertEquals(2, dependency.get('12').size());
        System.assertEquals('12000', dependency.get('12')[0].get('name'));
        System.assertEquals('24000', dependency.get('12')[1].get('name'));
        System.assertEquals('24000', dependency.get('24')[0].get('name'));
        System.assertEquals('36000', dependency.get('24')[1].get('name'));
        System.assertEquals('36000', dependency.get('36')[0].get('name'));
        System.assertEquals('60000', dependency.get('36')[1].get('name'));
    }

    @IsTest
    static void testUnsupportedActionDoesNotWriteOutput() {
        Map<String, Object> output = new Map<String, Object>();
        Object result = new ReRatePicklistPocProvider().call(
            'notSupported', makeArgs(output)
        );
        System.assertEquals(false, result);
        System.assertEquals(0, output.size());
    }

    @IsTest
    static void testInvalidInvocationHandled() {
        ReRatePicklistPocProvider provider = new ReRatePicklistPocProvider();
        System.assertEquals(false, provider.call('getTermMonths', null));
        System.assertEquals(false, provider.call('', makeArgs(new Map<String, Object>())));
        System.assertEquals(false, provider.call('getTermMiles', new Map<String, Object>()));
    }
}