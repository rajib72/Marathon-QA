/**
* @author: Saurabh Rawat
* @description:
* Test class for PaymentIntegrationHandler.
*
* Updated for the OLDER PaymentIntegrationHandler implementation.
*
* Validation-safe for:
* - Prevent_Processing_of_Ineligible_Claims
* - Basic_Fields_Validation / Required Auto Fields validation
*
* The Claim is fully populated BEFORE any ClaimItem DML can cause
* DLRS/ClaimItem automation to update the parent Claim.
*/
@IsTest
public class PaymentIntegrationHandlerTest {
    
    /* =========================================================
COMMON TEST HELPERS
========================================================= */
    
    /**
* Enables the existing Claim Item validation bypass.
*/
    private static void enableClaimItemValidationBypass() {
        
        ValidationBypass__c bypass =
            ValidationBypass__c.getOrgDefaults();
        
        if (bypass == null) {
            bypass = new ValidationBypass__c();
        }
        
        bypass.Bypass_ClaimItem_Validation__c = true;
        
        upsert bypass;
    }
    
    
    /**
* Returns first active picklist value for a Claim field.
*
* Avoids hard coding org-specific picklist values.
*/
    private static String getFirstActiveClaimPicklistValue(
        String fieldApiName
    ) {
        
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Claim.fields.getMap();
        
        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }
        
        Schema.DescribeFieldResult fieldDescribe =
            fieldMap.get(fieldApiName).getDescribe();
        
        for (
            Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        
        return null;
    }
    
    
    /**
* Creates an Insurance Policy with a deterministic eligibility window.
*
* The previous version inserted the TestDataFactory policy immediately and
* then tried to make the Claim fit whatever dates/mileage the target org
* happened to produce. That is environment-dependent and is the reason the
* class can pass in QA but fail during UAT/PROD validation.
*/
    private static InsurancePolicy createEligiblePolicy(Id accountId) {
        
        InsurancePolicy policyRec =
            TestDataFactory.createInsurancePolicy(
                false,
                accountId
            );
        
        Date todayDate = Date.today();
        
        // Deterministic date window: today is always eligible.
        putIfCreateable(
            policyRec,
            'Sale_Date__c',
            todayDate.addDays(-60)
        );
        
        putIfCreateable(
            policyRec,
            'Effective_Date__c',
            todayDate.addDays(-30)
        );
        
        putIfCreateable(
            policyRec,
            'Expiration_Date__c',
            todayDate.addDays(365)
        );
        
        // Keep standard SaleDate aligned where it is writeable.
        putIfCreateable(
            policyRec,
            'SaleDate',
            todayDate.addDays(-60)
        );
        
        // Deterministic Auto Warranty mileage window.
        putIfCreateable(
            policyRec,
            'Vehicle_Mileage_at_Contract_Inception__c',
            1000
        );
        
        putIfCreateable(
            policyRec,
            'Effective_Mileage__c',
            1000
        );
        
        putIfCreateable(
            policyRec,
            'Expiration_Mileage__c',
            100000
        );
        
        // Older PaymentIntegrationHandler reads VIN from the parent policy.
        putIfCreateable(
            policyRec,
            'VIN__c',
            '1HGCM66554A033052'
        );
        
        // Insurance_Code__c is Text(4) in the target org.
        // Keep the test value within the field length so CI/CD does not fail.
        putIfCreateable(
            policyRec,
            'Insurance_Code__c',
            'TST1'
        );
        
        insert policyRec;
        
        return policyRec;
    }
    
    
    /**
* Creates a Service Center account that can safely be used by
* Claim.Repair_Shop_Account__c.
*
* A separate Service Center is used instead of the Inspection Company
* payee because UAT may enforce a lookup filter on Repair Shop Account.
*/
    private static Account createRepairShopAccount() {
        
        Account repairShop =
            new Account();
        
        Map<String, Schema.RecordTypeInfo> recordTypes =
            Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName();
        
        if (recordTypes.containsKey('Service_Center')) {
            repairShop.RecordTypeId =
                recordTypes.get('Service_Center').getRecordTypeId();
        }
        
        repairShop.Name =
            'Payment Integration Test Repair Shop';
        
        repairShop.AccountNumber =
            'PAY-REPAIR-001';
        
        repairShop.BillingStreet =
            '100 Test Street';
        
        repairShop.BillingCity =
            'Chicago';
        
        repairShop.BillingState =
            'IL';
        
        repairShop.BillingPostalCode =
            '60601';
        
        repairShop.BillingCountry =
            'USA';
        
        repairShop.Phone =
            '3125550100';
        
        repairShop.Website =
            'https://example.com';
        
        repairShop.Email__c =
            'repairshop@test.com';
        
        insert repairShop;
        
        return repairShop;
    }
    
    
    /**
* Creates a Claim that is guaranteed to fall inside the deterministic
* Insurance Policy eligibility window created above and also satisfies
* the UAT Required Auto Fields validation before ClaimItem/DLRS DML.
*/
    private static Claim createEligibleClaim(
        Id policyId,
        Id repairShopAccountId,
        Boolean populateRepairEmail
    ) {
        
        Claim claimRec =
            TestDataFactory.createClaim(
                false,
                policyId
            );
        
        claimRec.Name =
            'PAYMENT-TEST-CLAIM';
        
        claimRec.PolicyNumberId =
            policyId;
        
        /*
* REQUIRED AUTO FIELD: Repair Shop Account.
*
* This must be populated before ClaimItem insert/update because
* DLRS can update the parent Claim and re-evaluate Claim validation.
*/
        claimRec.Repair_Shop_Account__c =
            repairShopAccountId;
        
        /*
* The policy helper creates:
* Sale Date      = today - 60
* Effective Date = today - 30
* Expiration     = today + 365
*
* Therefore today is safely inside the valid period.
*/
        setDateOrDateTimeField(
            claimRec,
            'ReportDate',
            Date.today()
        );
        
        /*
* The policy helper creates the valid mileage range
* 1,000 <= mileage < 100,000.
*/
        claimRec.Mileage__c =
            5000;
        
        // REQUIRED AUTO FIELD: Labor Rate.
        claimRec.Labor_Rate__c =
            25;
        
        // REQUIRED AUTO FIELD: Repair Order Number.
        claimRec.ReportNumber =
            'RO-PAYMENT-TEST';
        
        String drivenOrTowed =
            getFirstActiveClaimPicklistValue(
                'Driven_or_Towed_In__c'
            );
        
        if (drivenOrTowed != null) {
            claimRec.Driven_or_Towed_In__c =
                drivenOrTowed;
        }
        
        String partsWarranty =
            getFirstActiveClaimPicklistValue(
                'Parts_Warranty__c'
            );
        
        if (partsWarranty != null) {
            claimRec.Parts_Warranty__c =
                partsWarranty;
        }
        
        if (populateRepairEmail) {
            claimRec.Repair_Email__c =
                'repairshop@test.com';
        }
        
        insert claimRec;
        
        return claimRec;
    }
    
    
    /**
* Sets a field only when it exists and is createable in the target org.
* This keeps the test stable across metadata versions without masking
* validation logic in the production class.
*/
    private static void putIfCreateable(
        SObject record,
        String fieldApiName,
        Object value
    ) {
        
        Map<String, Schema.SObjectField> fieldMap =
            record
            .getSObjectType()
            .getDescribe()
            .fields
            .getMap();
        
        if (!fieldMap.containsKey(fieldApiName)) {
            return;
        }
        
        Schema.DescribeFieldResult fieldDescribe =
            fieldMap
            .get(fieldApiName)
            .getDescribe();
        
        if (
            fieldDescribe.isCreateable() &&
            !fieldDescribe.isCalculated() &&
            !fieldDescribe.isAutoNumber()
        ) {
            record.put(
                fieldApiName,
                value
            );
        }
    }
    
    
    /**
* Handles ReportDate safely whether the field is Date or DateTime.
*/
    private static void setDateOrDateTimeField(
        SObject record,
        String fieldApiName,
        Date value
    ) {
        
        Schema.SObjectField fieldToken =
            record
            .getSObjectType()
            .getDescribe()
            .fields
            .getMap()
            .get(fieldApiName);
        
        Schema.DisplayType fieldType =
            fieldToken
            .getDescribe()
            .getType();
        
        if (fieldType == Schema.DisplayType.DateTime) {
            record.put(
                fieldApiName,
                Datetime.newInstance(
                    value,
                    Time.newInstance(
                        12,
                        0,
                        0,
                        0
                    )
                )
            );
        } else {
            record.put(
                fieldApiName,
                value
            );
        }
    }
    
    
    /**
* Common Payment Integration test data.
*/
    private class PaymentTestData {
        
        Account customerAccount;
        
        Account payeeAccount;
        
        Account repairShopAccount;
        
        InsurancePolicy policy;
        
        Claim claim;
        
        ClaimItem claimItem;
    }
    
    
    private static PaymentTestData createPaymentTestData(
        Boolean populateRepairEmail
    ) {
        
        enableClaimItemValidationBypass();
        
        
        PaymentTestData data =
            new PaymentTestData();
        
        
        /* -----------------------------------------------------
Customer
----------------------------------------------------- */
        
       data.customerAccount =
    TestDataFactory.createAccount(
        false
    );

data.customerAccount.AccountNumber =
    'WUS';

data.customerAccount.FirstName =
    'Payment';

data.customerAccount.LastName =
    'Test Customer';

data.customerAccount.BillingStreet =
    '100 Test Street';

data.customerAccount.BillingCity =
    'Chicago';

data.customerAccount.BillingState =
    'IL';

data.customerAccount.BillingPostalCode =
    '60601';

data.customerAccount.Phone =
    '3125550100';

insert data.customerAccount;
        
        
        /* -----------------------------------------------------
Payee / Inspection Company
----------------------------------------------------- */
        
        data.payeeAccount =
            TestDataFactory.createInspectionCompanyAccount(
                false
            );
        
        data.payeeAccount.Name =
            'AMI Duplicate';
        
        data.payeeAccount.BillingCity =
            'San Francisco';
        
        data.payeeAccount.BillingCountry =
            'USA';
        
        data.payeeAccount.BillingPostalCode =
            '60661';
        
        data.payeeAccount.BillingState =
            'IL';
        
        data.payeeAccount.Email__c =
            'test@test.com';
        
        data.payeeAccount.BillingStreet =
            '9 East Madison Street';
        
        insert data.payeeAccount;
        
        
        /* -----------------------------------------------------
Repair Shop / Service Center
----------------------------------------------------- */
        
        data.repairShopAccount =
            createRepairShopAccount();
        
        
        /* -----------------------------------------------------
Insurance Policy
----------------------------------------------------- */
        
        data.policy =
            createEligiblePolicy(
                data.customerAccount.Id
            );
        
        
        /* -----------------------------------------------------
Validation-safe Claim
----------------------------------------------------- */
        
        data.claim =
            createEligibleClaim(
                data.policy.Id,
                data.repairShopAccount.Id,
                populateRepairEmail
            );
        
        
        /* -----------------------------------------------------
Claim Item
----------------------------------------------------- */
        
        /*
* IMPORTANT:
* Create the ClaimItem WITHOUT DML first. Populate the fields needed
* by the test before insert so ClaimItem triggers/DLRS only fire once
* against a fully valid parent Claim and a complete ClaimItem.
*/
        data.claimItem =
            TestDataFactory.createClaimItem(
                false,
                data.claim.Id
            );
        
        
        data.claimItem.Payee_Name__c =
            data.payeeAccount.Id;
        
        data.claimItem.Status__c =
            'Authorized';
        
        data.claimItem.Wex__c =
            true;
        
        data.claimItem.Invoice_Number__c =
            '12345';
        
        data.claimItem.Quantity__c =
            2;
        
        data.claimItem.Rate__c =
            5;
        
        data.claimItem.Net_Claim_Stamped__c =
            2;
        
        
        insert data.claimItem;
        
        
        /*
* Requery so execute() receives the stored database
* version of the Claim Item.
*/
        data.claimItem = [
            SELECT
            Id,
            ClaimId,
            Payee_Name__c,
            Status__c,
            Wex__c,
            Invoice_Number__c,
            Quantity__c,
            Rate__c,
            NetClaim__c,
            Net_Claim_Stamped__c,
            Payment__c,
            Last_WEX_Error__c
            FROM ClaimItem
            WHERE Id = :data.claimItem.Id
            LIMIT 1
        ];
        
        
        return data;
    }
    
    
    private static List<PaymentIntegrationHandler.Request>
        createRequest(
            ClaimItem claimItem
        ) {
            
            PaymentIntegrationHandler.Request request =
                new PaymentIntegrationHandler.Request();
            
            request.claimItemList =
                new List<ClaimItem>{
                    claimItem
                        };
                            
                            
                            return new List<
                            PaymentIntegrationHandler.Request
                            >{
                                request
                                    };
                                        }
    
    
    /* =========================================================
SUCCESS
========================================================= */
    
    @IsTest
    static void testExecuteSuccess() {
        
        /*
* Leave Repair Email blank so the
* is_Payment_via_Fax__c branch is exercised.
*
* The Claim is eligible, so that Claim update
* will no longer fail the eligibility validation.
*/
        PaymentTestData data =
            createPaymentTestData(
                false
            );
        
        
        List<PaymentIntegrationHandler.Request>
            requestList =
            createRequest(
                data.claimItem
            );
        
        
        Test.setMock(
            HttpCalloutMock.class,
            new PaymentCalloutMock2(
                true,
                200
            )
        );
        
        
        Test.startTest();
        
        List<PaymentIntegrationHandler.Response>
            responses =
            PaymentIntegrationHandler.execute(
                requestList
            );
        
        Test.stopTest();
        
        
        System.assertNotEquals(
            null,
            responses
        );
        
        System.assertEquals(
            1,
            responses.size()
        );
        
        System.assertEquals(
            'Success',
            responses[0].outputResponse,
            'Successful Mastercard response should return Success.'
        );
        
        
        ClaimItem updatedItem = [
            SELECT
            Id,
            Status__c,
            Payment__c,
            Last_WEX_Error__c
            FROM ClaimItem
            WHERE Id = :data.claimItem.Id
        ];
        
        
        System.assertEquals(
            'Paid',
            updatedItem.Status__c
        );
        
        System.assertNotEquals(
            null,
            updatedItem.Payment__c
        );
        
        System.assertEquals(
            null,
            updatedItem.Last_WEX_Error__c
        );
        
        
        List<Payment__c> payments = [
            SELECT
            Id,
            Account__c,
            Credit_Card_Number__c,
            Credit_Card_CVC__c,
            Credit_Card_Expiration__c
            FROM Payment__c
            WHERE Account__c =
            :data.payeeAccount.Id
        ];
        
        
        System.assertEquals(
            1,
            payments.size(),
            'One payment should have been created.'
        );
    }
    
    
    /* =========================================================
BUSINESS / PARSING ERROR
========================================================= */
    
    @IsTest
    static void testExecuteError() {
        
        PaymentTestData data =
            createPaymentTestData(
                true
            );
        
        
        List<PaymentIntegrationHandler.Request>
            requestList =
            createRequest(
                data.claimItem
            );
        
        
        Test.setMock(
            HttpCalloutMock.class,
            new PaymentCalloutMock1(
                false,
                200
            )
        );
        
        
        Test.startTest();
        
        List<PaymentIntegrationHandler.Response>
            responses =
            PaymentIntegrationHandler.execute(
                requestList
            );
        
        Test.stopTest();
        
        
        System.assertNotEquals(
            null,
            responses
        );
        
        System.assertEquals(
            1,
            responses.size()
        );
        
        System.assertEquals(
            'Error',
            responses[0].outputResponse
        );
        
        
        List<Payment__c> payments = [
            SELECT Id
            FROM Payment__c
            WHERE Account__c =
            :data.payeeAccount.Id
        ];
        
        
        System.assertEquals(
            0,
            payments.size()
        );
        
        
        ClaimItem updatedClaimItem = [
            SELECT
            Payment__c
            FROM ClaimItem
            WHERE Id = :data.claimItem.Id
        ];
        
        
        System.assertEquals(
            null,
            updatedClaimItem.Payment__c
        );
    }
    
    
    /* =========================================================
HTTP/API ERROR
========================================================= */
    
    @IsTest
    static void testExecuteAPIError() {
        
        PaymentTestData data =
            createPaymentTestData(
                true
            );
        
        
        List<PaymentIntegrationHandler.Request>
            requestList =
            createRequest(
                data.claimItem
            );
        
        
        Test.setMock(
            HttpCalloutMock.class,
            new PaymentCalloutMock1(
                false,
                400
            )
        );
        
        
        Test.startTest();
        
        List<PaymentIntegrationHandler.Response>
            responses =
            PaymentIntegrationHandler.execute(
                requestList
            );
        
        Test.stopTest();
        
        
        System.assertEquals(
            1,
            responses.size()
        );
        
        System.assertEquals(
            'Error',
            responses[0].outputResponse
        );
        
        
        List<Payment__c> payments = [
            SELECT Id
            FROM Payment__c
            WHERE Account__c =
            :data.payeeAccount.Id
        ];
        
        
        System.assertEquals(
            0,
            payments.size()
        );
        
        
        ClaimItem updatedClaimItem = [
            SELECT
            Payment__c,
            Last_WEX_Error__c
            FROM ClaimItem
            WHERE Id = :data.claimItem.Id
        ];
        
        
        System.assertEquals(
            null,
            updatedClaimItem.Payment__c
        );
        
        
        System.assertNotEquals(
            null,
            updatedClaimItem.Last_WEX_Error__c,
            'API failure information should be stored on the Claim Item.'
        );
    }
    
    
    /* =========================================================
SUCCESS WITH MASTERCARD RESPONSE
========================================================= */
    
    @IsTest
    static void testExecuteSuccessMethod() {
        
        PaymentTestData data =
            createPaymentTestData(
                true
            );
        
        
        List<PaymentIntegrationHandler.Request>
            requestList =
            createRequest(
                data.claimItem
            );
        
        
        Test.setMock(
            HttpCalloutMock.class,
            new PaymentCalloutMock2(
                true,
                200
            )
        );
        
        
        Test.startTest();
        
        List<PaymentIntegrationHandler.Response>
            responses =
            PaymentIntegrationHandler.execute(
                requestList
            );
        
        Test.stopTest();
        
        
        System.assertEquals(
            1,
            responses.size()
        );
        
        System.assertEquals(
            'Success',
            responses[0].outputResponse
        );
        
        
        List<Payment__c> payments = [
            SELECT
            Id,
            Account__c,
            Credit_Card_Number__c,
            Credit_Card_CVC__c,
            Credit_Card_Expiration__c
            FROM Payment__c
            WHERE Account__c =
            :data.payeeAccount.Id
        ];
        
        
        System.assertEquals(
            1,
            payments.size(),
            'Expected Payment__c record to be created.'
        );
        
        
        ClaimItem updatedClaimItem = [
            SELECT
            Status__c,
            Payment__c
            FROM ClaimItem
            WHERE Id = :data.claimItem.Id
        ];
        
        
        System.assertEquals(
            'Paid',
            updatedClaimItem.Status__c
        );
        
        System.assertNotEquals(
            null,
            updatedClaimItem.Payment__c
        );
    }
    
    
    /* =========================================================
CALLOUT EXCEPTION
========================================================= */
    
    @IsTest
    static void testExecuteException() {
        
        PaymentTestData data =
            createPaymentTestData(
                true
            );
        
        
        List<PaymentIntegrationHandler.Request>
            requestList =
            createRequest(
                data.claimItem
            );
        
        
        Test.setMock(
            HttpCalloutMock.class,
            new PaymentCalloutMock3()
        );
        
        
        Test.startTest();
        
        List<PaymentIntegrationHandler.Response>
            responses =
            PaymentIntegrationHandler.execute(
                requestList
            );
        
        Test.stopTest();
        
        
        System.assertNotEquals(
            null,
            responses
        );
        
        System.assertEquals(
            1,
            responses.size()
        );
        
        System.assertEquals(
            'Error',
            responses[0].outputResponse,
            'Callout exception should result in Error.'
        );
    }
    
    
    /* =========================================================
OUTER DEFENSIVE EXCEPTION
========================================================= */
    
    @IsTest
    static void testExecuteInvalidRequest() {
        
        Test.startTest();
        
        List<PaymentIntegrationHandler.Response>
            responses =
            PaymentIntegrationHandler.execute(
                new List<
                PaymentIntegrationHandler.Request
                >()
            );
        
        Test.stopTest();
        
        
        System.assertEquals(
            1,
            responses.size()
        );
        
        System.assertEquals(
            'Error',
            responses[0].outputResponse
        );
    }
    
    
    /* =========================================================
getTruncatedValue()
========================================================= */
    
    @IsTest
    static void testGetTruncatedValue() {
        
        String shortValue =
            'Test Value';
        
        System.assertEquals(
            shortValue,
            PaymentIntegrationHandler.getTruncatedValue(
                shortValue
            )
        );
        
        
        String longValue =
            '1234567890123456789012345678901234567890' +
            '1234567890123456789012345678901234567890' +
            'EXTRA';
        
        
        String truncated =
            PaymentIntegrationHandler.getTruncatedValue(
                longValue
            );
        
        
        System.assertEquals(
            80,
            truncated.length()
        );
        
        
        System.assertEquals(
            '',
            PaymentIntegrationHandler.getTruncatedValue(
                null
            )
        );
        
        
        System.assertEquals(
            '',
            PaymentIntegrationHandler.getTruncatedValue(
                ''
            )
        );
    }
    
    
    /* =========================================================
HTTP MOCK 1
========================================================= */
    
    public class PaymentCalloutMock1
        implements HttpCalloutMock {
            
            Boolean isSuccess;
            
            Integer statusCode;
            
            
            public PaymentCalloutMock1(
                Boolean isSuccess,
                Integer statusCode
            ) {
                
                this.isSuccess =
                    isSuccess;
                
                this.statusCode =
                    statusCode;
            }
            
            
            public HttpResponse respond(
                HttpRequest req
            ) {
                
                HttpResponse res =
                    new HttpResponse();
                
                
                res.setHeader(
                    'Content-Type',
                    'text/xml'
                );
                
                
                res.setBody(
                    '<?xml version="1.0" encoding="utf-8"?>' +
                    '<soap:Envelope ' +
                    'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
                    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                    'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
                    '<soap:Body>' +
                    '<CreatePurchaseLogResponse ' +
                    'xmlns="http://aocsolutions.com/EncompassWebServices/">' +
                    '<CreatePurchaseLogResult>' +
                    '<ResponseCode>' +
                    (
                        this.isSuccess
                        ? 'Success'
                        : 'Error'
                    ) +
                    '</ResponseCode>' +
                    '<Description>' +
                    'Purchase Log submitted, card issued and credit limit updated successfully.' +
                    '</Description>' +
                    '<PurchaseLogUniqueID>' +
                    '5JPZ8173JCQ6BTR8K7' +
                    '</PurchaseLogUniqueID>' +
                    '<CreditLimit>' +
                    '2200.00' +
                    '</CreditLimit>' +
                    '<Card>' +
                    '<CardNumber>' +
                    '5550716041004429' +
                    '</CardNumber>' +
                    '<CVC2>' +
                    '832' +
                    '</CVC2>' +
                    '<ExpirationDate>' +
                    '2029-07-01T00:00:00' +
                    '</ExpirationDate>' +
                    '</Card>' +
                    '</CreatePurchaseLogResult>' +
                    '</CreatePurchaseLogResponse>' +
                    '</soap:Body>' +
                    '</soap:Envelope>'
                );
                
                
                res.setStatusCode(
                    statusCode
                );
                
                
                return res;
            }
        }
    
    
    /* =========================================================
HTTP MOCK 2
========================================================= */
    
    public class PaymentCalloutMock2
        implements HttpCalloutMock {
            
            Boolean isSuccess;
            
            Integer statusCode;
            
            
            public PaymentCalloutMock2(
                Boolean isSuccess,
                Integer statusCode
            ) {
                
                this.isSuccess =
                    isSuccess;
                
                this.statusCode =
                    statusCode;
            }
            
            
            public HttpResponse respond(
                HttpRequest req
            ) {
                
                HttpResponse res =
                    new HttpResponse();
                
                
                res.setHeader(
                    'Content-Type',
                    'text/xml'
                );
                
                
                res.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<S:Body>' +
                    '<ns2:getPurchaseRequestDetail ' +
                    'xmlns="http://mastercard.com/sd/pc/service" ' +
                    'xmlns:ns2="http://mastercard.com/sd/pc2/service">' +
                    
                    '<ns2:purchaseRequestId>' +
                    '24557181' +
                    '</ns2:purchaseRequestId>' +
                    
                    '<ns2:requestStatus>' +
                    'Approved' +
                    '</ns2:requestStatus>' +
                    
                    '<ns2:PurchaseRequestTemplateDetails>' +
                    '<ns2:templateId>54713</ns2:templateId>' +
                    
                    '<ns2:fullTemplateRuleDetails>' +
                    '<ns2:ruleName>B</ns2:ruleName>' +
                    '<ns2:ruleType>A</ns2:ruleType>' +
                    
                    '<ns2:templateControl ' +
                    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                    'xsi:type="ns2:templateAmountRangeControl2">' +
                    '<ns2:minAmount>0.1</ns2:minAmount>' +
                    '<ns2:maxAmount>0.1</ns2:maxAmount>' +
                    '<ns2:strictPreAuthCheck>false</ns2:strictPreAuthCheck>' +
                    '<ns2:negate>false</ns2:negate>' +
                    '<ns2:currencyType>B</ns2:currencyType>' +
                    '</ns2:templateControl>' +
                    
                    '</ns2:fullTemplateRuleDetails>' +
                    '</ns2:PurchaseRequestTemplateDetails>' +
                    
                    '<ns2:vcnInformation>' +
                    '<ns2:Id>23700017</ns2:Id>' +
                    '<ns2:Pan>5561209093339411</ns2:Pan>' +
                    '<ns2:Expiry>2701</ns2:Expiry>' +
                    '<ns2:Avv>251</ns2:Avv>' +
                    '<ns2:Status>S</ns2:Status>' +
                    '<ns2:EVCNIndicator>false</ns2:EVCNIndicator>' +
                    '</ns2:vcnInformation>' +
                    
                    '<ns2:supplierDetails>' +
                    '<ns2:supplierId>58915</ns2:supplierId>' +
                    '<ns2:supplierEmails>' +
                    'test@test.com' +
                    '</ns2:supplierEmails>' +
                    '<ns2:notifySupplier>true</ns2:notifySupplier>' +
                    '</ns2:supplierDetails>' +
                    
                    '</ns2:getPurchaseRequestDetail>' +
                    '</S:Body>' +
                    '</S:Envelope>'
                );
                
                
                res.setStatusCode(
                    statusCode
                );
                
                
                return res;
            }
        }
    
    
    /* =========================================================
HTTP MOCK 3
========================================================= */
    
    public class PaymentCalloutMock3
        implements HttpCalloutMock {
            
            public HttpResponse respond(
                HttpRequest req
            ) {
                
                throw new CalloutException(
                    'Simulated Exception'
                );
            }
        }
}