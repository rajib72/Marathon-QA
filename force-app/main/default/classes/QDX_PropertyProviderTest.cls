/**
* @author: Saurabh Rawat
* @dateModified: 2024-05-22
* @description: Test class for code coverage of class QDX_PropertyProvider.
*/
@isTest
public with sharing class QDX_PropertyProviderTest {
    @isTest
    public static Void testCall() {
        Map<String,Map<String,Object>> args = new Map<String,Map<String,Object>>();
        Map<String,Object> result = new Map<String,Object>();
        args.put('input', new Map<String,Object>{'label'=>'WIS_URL'});
        args.put('output', new Map<String,Object>());
        args.put('options', new Map<String,Object>());
        QDX_PropertyProvider provider = new QDX_PropertyProvider();
        result = (Map<String,Object>)provider.call('invokeMethod', args);
        System.assert(result.get('username') != null , 'The username in the result should not be null when calling the invokeMethod with the given arguments.');
    }
    @isTest
    public static void testInvokeMethodWEX() {
        Map<String,Map<String,Object>> args = new Map<String,Map<String,Object>>();
        Map<String,Object> result = new Map<String,Object>();
        args.put('input', new Map<String,Object>{'label'=>'WEX_URL'});
        args.put('output', new Map<String,Object>());
        args.put('options', new Map<String,Object>());

        QDX_PropertyProvider provider = new QDX_PropertyProvider();
        result = (Map<String,Object>)provider.call('invokeMethodWEX', args);
        System.assertEquals('MarathonGroup', result.get('orgGroupLoginId'), 'WEX_URL is not set');
    }
    @isTest
    public static void testCallLogMethod() {
        Map<String,Map<String,Object>> args = new Map<String,Map<String,Object>>();
        Map<String,Object> result = new Map<String,Object>();
        args.put('input', new Map<String,Object>{'label'=>'LOG_METHOD'});
        args.put('output', new Map<String,Object>());
        args.put('options', new Map<String,Object>());

        QDX_PropertyProvider provider = new QDX_PropertyProvider();
        result = (Map<String,Object>)provider.call('callLogMethod', args);
        System.assert(result == null , 'The result should be null when calling the callLogMethod with the given arguments.');
    }
    @isTest
    public static void testAddDelay() {
        Map<String,Map<String,Object>> args = new Map<String,Map<String,Object>>();
        Map<String,Object> result = new Map<String,Object>();
        args.put('input', new Map<String,Object>{'label'=>'DELAY_METHOD'});
        args.put('output', new Map<String,Object>());
        args.put('options', new Map<String,Object>());

        QDX_PropertyProvider provider = new QDX_PropertyProvider();
        Test.startTest();
        result = (Map<String,Object>)provider.call('addDelay', args);
        Test.stopTest();
        System.assert(result == null, 'The result should be null when calling the addDelay method with the given arguments.');
    }
}