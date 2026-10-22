@IsTest
public class BRECallEventHandlerTest {

    @IsTest
    static void testHandleAfterInsertWithValidEvent() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        BRE_Call_Event__e evt = new BRE_Call_Event__e();
        evt.Rule_Name__c = 'Base Reserve Rule';
        evt.Rule_Type__c = 'Pricing';
        evt.Call_Type__c = 'BRE Call';
        evt.Source__c = 'Apex';
        evt.Caller_Class__c = 'BRELogger';
        evt.Caller_Method__c = 'log';
        evt.Method_Call_Count__c = 1;
        evt.Execution_Time__c = 100;
        evt.Response_Status__c = 'Success';
        evt.Transaction_Id__c = 'TXN-001';
        evt.Callout_Count__c = 5;
        evt.Cache_Hit__c = false;
        evt.Input_Size__c = 250;
        evt.Input_Hash__c = 'TESTHASH001';
        evt.Contract_Number__c = 'CON-001';
        evt.User_Id__c = UserInfo.getUserId();

        eventList.add(evt);

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }

    @IsTest
    static void testHandleAfterInsertWithNullList() {

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(null);
        Test.stopTest();
    }

    @IsTest
    static void testHandleAfterInsertWithEmptyList() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }

    @IsTest
    static void testEventIgnoredWhenRuleNameBlank() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        BRE_Call_Event__e evt = new BRE_Call_Event__e();
        evt.Rule_Name__c = '';
        evt.Rule_Type__c = 'Pricing';
        evt.Call_Type__c = 'BRE Call';
        evt.Execution_Time__c = 100;
        evt.Callout_Count__c = 5;
        evt.User_Id__c = UserInfo.getUserId();

        eventList.add(evt);

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }

    @IsTest
    static void testEventIgnoredWhenExecutionTimeLow() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        BRE_Call_Event__e evt = new BRE_Call_Event__e();
        evt.Rule_Name__c = 'Fast Rule';
        evt.Rule_Type__c = 'Validation';
        evt.Call_Type__c = 'Internal Call';
        evt.Execution_Time__c = 10;
        evt.Callout_Count__c = 5;
        evt.User_Id__c = UserInfo.getUserId();

        eventList.add(evt);

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }

    @IsTest
    static void testEventIgnoredWhenCalloutCountLow() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        BRE_Call_Event__e evt = new BRE_Call_Event__e();
        evt.Rule_Name__c = 'Low Volume Rule';
        evt.Rule_Type__c = 'Validation';
        evt.Call_Type__c = 'BRE Call';
        evt.Execution_Time__c = 100;
        evt.Callout_Count__c = 2;
        evt.User_Id__c = UserInfo.getUserId();

        eventList.add(evt);

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }

    @IsTest
    static void testMultipleEventsWithValidAndInvalidData() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        BRE_Call_Event__e validEvt = new BRE_Call_Event__e();
        validEvt.Rule_Name__c = 'Valid Rule';
        validEvt.Rule_Type__c = 'Pricing';
        validEvt.Call_Type__c = 'BRE Call';
        validEvt.Source__c = 'Apex';
        validEvt.Caller_Class__c = 'TestClass';
        validEvt.Caller_Method__c = 'testMethod';
        validEvt.Method_Call_Count__c = 1;
        validEvt.Execution_Time__c = 150;
        validEvt.Response_Status__c = 'Success';
        validEvt.Transaction_Id__c = 'TXN-VALID';
        validEvt.Callout_Count__c = 6;
        validEvt.Cache_Hit__c = true;
        validEvt.Input_Size__c = 500;
        validEvt.Input_Hash__c = 'VALIDHASH';
        validEvt.Contract_Number__c = 'CON-VALID';
        validEvt.User_Id__c = UserInfo.getUserId();

        BRE_Call_Event__e invalidEvt = new BRE_Call_Event__e();
        invalidEvt.Rule_Name__c = null;
        invalidEvt.Execution_Time__c = 5;
        invalidEvt.Callout_Count__c = 1;
        invalidEvt.User_Id__c = UserInfo.getUserId();

        eventList.add(validEvt);
        eventList.add(invalidEvt);

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }

    @IsTest
    static void testMoreThanMaxRecords() {

        List<BRE_Call_Event__e> eventList = new List<BRE_Call_Event__e>();

        for (Integer i = 0; i < 250; i++) {
            BRE_Call_Event__e evt = new BRE_Call_Event__e();
            evt.Rule_Name__c = 'Bulk Rule ' + i;
            evt.Rule_Type__c = 'Bulk';
            evt.Call_Type__c = 'BRE Call';
            evt.Source__c = 'Apex';
            evt.Caller_Class__c = 'BulkTestClass';
            evt.Caller_Method__c = 'bulkMethod';
            evt.Method_Call_Count__c = i;
            evt.Execution_Time__c = 100;
            evt.Response_Status__c = 'Success';
            evt.Transaction_Id__c = 'TXN-' + i;
            evt.Callout_Count__c = 5;
            evt.Cache_Hit__c = false;
            evt.Input_Size__c = 100;
            evt.Input_Hash__c = 'HASH' + i;
            evt.Contract_Number__c = 'CON-' + i;
            evt.User_Id__c = UserInfo.getUserId();

            eventList.add(evt);
        }

        Test.startTest();
        BRECallEventHandler.handleAfterInsert(eventList);
        Test.stopTest();
    }
}