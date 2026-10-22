/*******************************************************************************************
* @File Name          : S3FileMigrationBatchTest.cls
* @Author             : Abhishek Jain
* @Description        : Test Class used to test or cover S3FileMigrationBatch class.
* Change History:
*
* DATE         AUTHOR                      Change Description
* ----------   --------------------        ---------------------------------------------
* 05/09/2025   Abhishek Jain               MRT-628 Test Class used to test or cover
*                                           S3FileMigrationBatch class.
******************************************************************************************/
@isTest
private class S3FileMigrationBatchTest {
    
    
    // =========================================================
    // MOCK HTTP RESPONSE
    // =========================================================
    class MockHttpResponseGenerator
        implements HttpCalloutMock {
        
        public HTTPResponse respond(
            HTTPRequest req
        ) {
            
            HttpResponse res =
                new HttpResponse();
            
            res.setHeader(
                'Content-Type',
                'application/json'
            );
            
            res.setBody(
                '{"message":"File uploaded"}'
            );
            
            res.setStatusCode(200);
            
            return res;
        }
    }
    
    
    // =========================================================
    // TEST SETUP
    // =========================================================
    @testSetup
    static void SetData() {
        
        
        // =====================================================
        // CUSTOMER / CLIENT ACCOUNT
        //
        // IMPORTANT:
        // Do not allow TestDataFactory to insert immediately.
        // We need to make the Account validation-safe first.
        // =====================================================
        Account testRecord =
            TestDataFactory.createAccount(
                false
            );
        
        
        /*
         * WUS prevents this unrelated S3 migration test from
         * entering the general Sold Contract required-fields
         * validation.
         */
        testRecord.AccountNumber =
            'WUS';
        
        
        testRecord.FirstName =
            'S3';
        
        testRecord.LastName =
            'Migration Test';
        
        
        testRecord.BillingStreet =
            '100 Test Street';
        
        testRecord.BillingCity =
            'Chicago';
        
        testRecord.BillingState =
            'IL';
        
        testRecord.BillingPostalCode =
            '60601';
        
        testRecord.Phone =
            '3125550100';
        
        
        insert testRecord;
        
        
        // =====================================================
        // INSURANCE POLICY
        //
        // IMPORTANT:
        // false prevents createInsurancePolicy() from inserting
        // the incomplete Contract immediately.
        // =====================================================
        InsurancePolicy policy =
            TestDataFactory.createInsurancePolicy(
                false,
                testRecord.Id
            );
        
        
        // =====================================================
        // EXPLICIT ACCOUNT RELATIONSHIPS
        // =====================================================
        policy.Client__c =
            testRecord.Id;
        
        policy.NameInsuredId =
            testRecord.Id;
        
        
        // =====================================================
        // SALE DATE
        // =====================================================
        policy.SaleDate =
            System.now();
        
        policy.Sale_Date__c =
            Date.today();
        
        
        // =====================================================
        // INSERT POLICY
        //
        // The remaining Policy fields come from
        // TestDataFactory.createInsurancePolicy().
        // =====================================================
        insert policy;
        
        
        // =====================================================
        // CONTENT DOCUMENT / CONTENT VERSION
        // =====================================================
        TestDataFactory.createContentDocument(
            true,
            policy.Id
        );
    }
    
    
    // =========================================================
    // TEST SCHEDULER
    // =========================================================
    static testMethod void testScheduler() {
        
        
        // Mock S3 callout
        Test.setMock(
            HttpCalloutMock.class,
            new MockHttpResponseGenerator()
        );
        
        
        Test.startTest();
        
        
        String cronExp =
            '0 0 12 * * ?';
        
        
        System.schedule(
            'Test S3 Scheduler',
            cronExp,
            new S3FileMigrationBatch()
        );
        
        
        Test.stopTest();
        
        
        // =====================================================
        // VALIDATE SCHEDULED JOB
        // =====================================================
        CronTrigger ct = [
            SELECT
                Id,
                CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name =
                'Test S3 Scheduler'
            LIMIT 1
        ];
        
        
        System.assertEquals(
            'Test S3 Scheduler',
            ct.CronJobDetail.Name
        );
    }
}