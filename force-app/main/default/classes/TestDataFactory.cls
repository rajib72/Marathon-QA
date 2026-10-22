/**
* @author: Renuka Singh
* @dateModified: 2024-05-08
* @description: Test data apex class to create and reuse the methods for test data across test classes.
*/
@isTest
public with sharing class TestDataFactory {
    public static Account createAccount(Boolean insertCheck){
        Id personAccRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
        Account testAcc = new Account( FirstName = 'Marathon',LastName ='Account', Type = 'Site',RecordTypeId = personAccRecTypeId, BillingState = 'TX', BillingStreet = 'Fox ST', BillingCity = 'Austin', BillingPostalCode = '30001' );
        if(insertCheck){
            insert testAcc;
        }
        return testAcc;
    }
    public static Account createSellingAgencyAccount(Boolean insertCheck){
        Id personAccRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Selling Agency').getRecordTypeId();
        Account testAcc = new Account( Name = 'Marathon', Type = '03 - TOWING',RecordTypeId = personAccRecTypeId, BillingState = 'TX', BillingStreet = 'Fox ST', BillingCity = 'Austin', BillingPostalCode = '30001' );
        if(insertCheck){
            insert testAcc;
        }
        return testAcc;
    }
    public static InsurancePolicy createInsurancePolicy(Boolean insertCheck,Id accId){
        
        Coverage_Level__c coverageLevel = new Coverage_Level__c();
        coverageLevel.name = 'Coverage Level Name Test Data';
        insert coverageLevel; 
        createVinDetail(true);
        InsurancePolicy testInsPolicy = new InsurancePolicy(Name='TEST1234555', PolicyName= 'MBPolicy', NameInsuredId  = accId, Option_1__c = 'Salvaged',
                                                            Contract_Term_Months__c = 12,
                                                            Coverage_Name__c = 'PowerTrain',
                                                            Vehicle_Mileage_at_Contract_Inception__c = 100000,
                                                            Contract_Term_Mileage__c = 12000,
                                                            Is_Commercial__c = true,
                                                            Vehicle_Make__c = 'ACUR',
                                                            Net_Dealer_Cost__c = 700,
                                                            Product__c = 'SecureOne',
                                                            VIN__c = 'TestVin1A34123456',
                                                            Insurance_Code__c = 'KNB',
                                                            Coverage_Level__c = coverageLevel.Id, SaleDate = System.today(),Vehicle_Year__c = '2023',
                                                            Dealer_Program_Id__c = '1', Up_To_or_Add__c = 'UpTo', Class__c = 'SUV',
                                                            PremiumAmount = 690, Down_Payment_Amount__c = 90, Deductible__c = 89, Fulfillment_Date__c = System.today(),
                                                            Ins_Carrier__c = 'Technology Insurance Company',
                                                            Rate_Code__c = '1'
                                                            );
        
        if(insertCheck){
            insert testInsPolicy;
        }
        return testInsPolicy;
    }
    
    public static ROP__c createROP(Boolean insertCheck){
        ROP__c testROP = new ROP__c(Policy_Number__c = 'Policy001',Contract_Id_from_ROP__c = 'Policy001');
        if(insertCheck){
            insert testROP;
        }
        return testROP;
    }
    
    public static Claim createClaim(Boolean insertCheck,Id insPolicyId){
        Claim testClaim = new Claim(PolicyNumberId  = insPolicyId, Name = '12345',status = 'Open',ReportDate = Date.today() , ReportNumber = '8888', Labor_Rate__c = 10,Mileage__c = 10 );
        if(insertCheck){
            insert testClaim;
        }
        return testClaim;
    }
    public static ClaimItem createClaimItem(Boolean insertCheck,Id claimRecId){
        Loss_Category__c lossCat = new Loss_Category__c();
        lossCat.Claim_Loss_Type__c = 'Benefit';
        lossCat.Target_Type__c ='Residential';
        insert lossCat;
        
        Loss_Component__c lossCompObj = new Loss_Component__c();
        lossCompObj.Loss_Category__c=lossCat.Id;
        lossCompObj.Type__c = 'Other';
        insert lossCompObj;
        
        Coverage_Level__c coverageLevelObj = new Coverage_Level__c();
        coverageLevelObj.Name ='Test Obj';
        insert coverageLevelObj;
        
        Coverage_Level_Detail__c coverageObj = new Coverage_Level_Detail__c();
        coverageObj.Name ='Test';
        coverageObj.Limit_Application__c = 'Aggregate';
        coverageObj.Loss_Component__c = lossCompObj.Id;
        coverageObj.Coverage_Level__c = coverageLevelObj.Id;
        insert coverageObj;
        ClaimItem testClaimItem = new ClaimItem(ClaimId  = claimRecId, Name = '12345', Status__c = 'Requested',Coverage_Level_Detail__c=coverageObj.Id);
        if(insertCheck){
            insert testClaimItem;
        }
        return testClaimItem;
    }
    
    public static User createStandardUser(Boolean insertCheck){
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User nonAdminUser = new User(
            ProfileId = standardProfile.Id,
            LastName = 'Test',
            Email = 'test@example.com',
            Username = 'tesasdadt@exaadsdample.com',
            Alias = 'test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        if(insertCheck){
            insert nonAdminUser;
        }
        return nonAdminUser;
    }
    public static Dealer_Cost_Allocation__c createDealerCostAllocation(Boolean insertCheck){
        Dealer_Cost_Allocation__c testDCA = new Dealer_Cost_Allocation__c(RatingRecordID__c = 'RatingRecord1', AllocationCode__c = 'All1', Allocation_Amount__c = 100.0, Refundable__c = 'N');
        if(insertCheck){
            insert testDCA;
        }
        return testDCA;
    }
    public static Account createDealerAccount(Boolean insertCheck){
        Id personAccRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId();
        Account testAcc = new Account(Name ='Dealer Account', Type = 'Site',RecordTypeId = personAccRecTypeId );
        if(insertCheck){
            insert testAcc;
        }
        return testAcc;
    }
    public static Account createInspectionCompanyAccount(Boolean insertCheck){
        Id insComAccRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Inspection Company').getRecordTypeId();
        Account testAcc = new Account(Name ='AMI',AccountNumber='WLK',Phone='9999999999', Address_2__c='Pune,Mumbai,Ahmadabad',Repair_Contact__c='Contact2',Type = 'Analyst',RecordTypeId = insComAccRecTypeId);
        if(insertCheck){
            insert testAcc;
        }
        return testAcc;
    }
    public static Allocation_Code__c createAllocationCode(Boolean insertCheck){
        Allocation_Code__c testAllocationCode = new Allocation_Code__c(Name = '8001');
        if(insertCheck){
            insert testAllocationCode;
        }
        return testAllocationCode;
    }
    public static Allocation__c createAllocation(Boolean insertCheck,Id contractId,Id allocationCode){
        Allocation__c testAllocation = new Allocation__c(Contract__c = contractId, Allocation_Amount__c = 5, Allocation_Code__c = allocationCode);
        if(insertCheck){
            insert testAllocation;
        }
        return testAllocation;
    }
    public static Funding__c createFunding(Boolean insertCheck,Id contractId){
        Funding__c testFunding = new Funding__c(Contract__c = contractId,Funded_Amount__c=1000);
        if(insertCheck){
            insert testFunding;
        }
        return testFunding;
    }
    
    
    public static Payment__c createPayment(Boolean insertCheck){
        Payment__c testPayment = new Payment__c();
        if(insertCheck){
            insert testPayment;
        }
        return testPayment;
    }


    public static Payment__c createPayment2(Boolean insertCheck,Id accId){
        Payment__c testPayment = new Payment__c(Account__c = accId);
        if(insertCheck){
            insert testPayment;
        }
        return testPayment;
    }

    public static ClaimItem createClaimItem2(Boolean insertCheck,Id claimRecId,Id payeeName,Id paymentId, String status){
        Loss_Category__c lossCat = new Loss_Category__c();
        lossCat.Claim_Loss_Type__c = 'Benefit';
        lossCat.Target_Type__c ='Residential';
        insert lossCat;
        
        Loss_Component__c lossCompObj = new Loss_Component__c();
        lossCompObj.Loss_Category__c=lossCat.Id;
        lossCompObj.Type__c = 'Other';
        insert lossCompObj;
        
        Coverage_Level__c coverageLevelObj = new Coverage_Level__c();
        coverageLevelObj.Name ='Test Obj';
        insert coverageLevelObj;
        
        Coverage_Level_Detail__c coverageObj = new Coverage_Level_Detail__c();
        coverageObj.Name ='Test';
        coverageObj.Limit_Application__c = 'Aggregate';
        coverageObj.Loss_Component__c = lossCompObj.Id;
        coverageObj.Coverage_Level__c = coverageLevelObj.Id;
        insert coverageObj;
        ClaimItem testClaimItem = new ClaimItem(ClaimId  = claimRecId, Payee_Name__c = payeeName, Name = '12345', Status__c = status, Wex__c = false, Payment__c = paymentId,
                                               Coverage_Level_Detail__c=coverageObj.Id);
        if(insertCheck){
            insert testClaimItem;
        }
        return testClaimItem;
    }
    
    public static ContentDocumentLink createContentDocument(Boolean insertCheck, Id accId){
         ContentVersion contentVersion = new ContentVersion(
            Title = 'TSOP1', 
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test content data for document')
        );
        insert contentVersion;
        
        contentVersion = [SELECT Id, contentDocumentId FROM contentVersion WHERE Id = :contentVersion.Id LIMIT 1];
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink(
            ContentDocumentId = contentVersion.contentDocumentId,
            LinkedEntityId = accId, 
            ShareType = 'V'  
        );
        if(insertCheck){
            insert contentDocumentLink;
        }
        return contentDocumentLink;
    }
    
    public static VIN_Detail__c createVinDetail(Boolean insertCheck){
        VIN_Detail__c vinDetailObj = new VIN_Detail__c(MDL_YR__c = '2008', MAK_NM__c = 'CHEVROLET',MDL_DESC__c = 'EXPRESS G1500', BDY_STYLE_CD__c = 'PV', 
                                                       BODY_STYLE_DESC__c = 'VAN PASSENGER', DRV_TYP_CD__c = 'RWD' , MFG_DESC__c = 'General Motors',
                                                       ENG_FUEL_DESC__c = 'Gas',NCI_MAK_ABBR_CD__c = 'CHEV' ,Ethnicity__c = 'American', VIN_SIGNI_PATTRN_MASK__c ='TestVin1*34******');
        if(insertCheck){
            List<VIN_Detail__c> vinDetailList = [SELECT Id FROM VIN_Detail__c WHERE VIN_SIGNI_PATTRN_MASK__c = 'TestVin1*34******' LIMIT 1];
            if(vinDetailList.isEmpty()){
                insert vinDetailObj;
            }
        }
        return vinDetailObj;
    }
    
    public static VIN_Class__c  createVinClass(Boolean insertCheck, Id vinDetailId){
        VIN_Class__c vinClassObj = new VIN_Class__c(Partner__c = 'Amtrust', Class_Guide_Name__c = 'ABC', Class__c = 'A');
        vinClassObj.Squish_VIN__c = vinDetailId;
        if(insertCheck){
            insert vinClassObj;
        }
        return vinClassObj;
    }
    
    
    
    public static ClaimItem createClaimItem3(Boolean insertCheck,Id claimRecId, Id lossComponentId){
        Loss_Category__c lossCat = new Loss_Category__c();
        lossCat.Claim_Loss_Type__c = 'Benefit';
        lossCat.Target_Type__c ='Residential';
        insert lossCat;
        
        Loss_Component__c lossCompObj = new Loss_Component__c();
        lossCompObj.Loss_Category__c=lossCat.Id;
        lossCompObj.Type__c = 'Other';
        insert lossCompObj;
        
        Coverage_Level__c coverageLevelObj = new Coverage_Level__c();
        coverageLevelObj.Name ='Test Obj';
        insert coverageLevelObj;
        
        Coverage_Level_Detail__c coverageObj = new Coverage_Level_Detail__c();
        coverageObj.Name ='Test';
        coverageObj.Limit_Application__c = 'Aggregate';
        coverageObj.Loss_Component__c = lossCompObj.Id;
        coverageObj.Coverage_Level__c = coverageLevelObj.Id;
        insert coverageObj;
        ClaimItem testClaimItem = new ClaimItem(ClaimId  = claimRecId, Name = '12345', Status__c = 'Requested', Job_Number__c = '3', Loss_Description__c = lossComponentId, Detail_Type__c ='Labor', Reason__c = 'Waiting for Inspection', Tax__c = 5.00,Coverage_Level_Detail__c=coverageObj.Id);
        if(insertCheck){
            insert testClaimItem;
        }
        return testClaimItem;
    }
    
    public static Loss_Category__c createLossCategory(Boolean insertCheck){
        Loss_Category__c testlossCategory = new Loss_Category__c(Name = '12345', Claim_Loss_Type__c = 'Repair', Target_Type__c = 'Residential');
        if(insertCheck){
            insert testlossCategory;
        }
        return testlossCategory;
    }
    
    public static Loss_Component__c createLossComponent(Boolean insertCheck, Id LossCategoryId){
        Loss_Component__c testlossComponent = new Loss_Component__c(Loss_Category__c = LossCategoryId, Name = 'Loss Component 1', Type__c = 'Other');
        if(insertCheck){
            insert testlossComponent;
        }
        return testlossComponent;
    }
    
    public static Report_request__c createReportRequest(Boolean inInsert){
        Report_Request__c requestReport = new Report_Request__c(Report_Type__c = 'CancelLog - NonCommVehicle', Components__c = 'Summary',
                                                               Client__c = 'Abenity', Product__c ='Health CAR', Coverage_Levels__c='Health CAR', Status__c ='Requested');
        
        if(inInsert){
            insert requestReport;
        }
        return requestReport;
    }
}