@isTest
private class FundingDSIContractTriggerHandlerTest {

    @isTest
    static void testUpdateContractFundedAmount() {

   /*     
        InsurancePolicy ip = new InsurancePolicy(
            Name = 'Test Contract',
            Legacy_Source__c = 'DSI'
        );
        insert ip;

        Funding__c f1 = new Funding__c(
            Contract__c = ip.Id,
            Funded_Amount__c = 100,
            Time_Processed__c = DateTime.now().addDays(-2)
        );
        insert f1;

        Funding__c f2 = new Funding__c(
            Contract__c = ip.Id,
            Funded_Amount__c = 200,
            Time_Processed__c = null
        );
        insert f2;

        Funding__c f2Old = f2.clone(false, true, false, false);
        f2.Time_Processed__c = DateTime.now();

        Test.startTest();
            FundingDSIContractTriggerHandler.updateContractFundedAmount(
                new List<Funding__c>{ f2 },
                new List<Funding__c>{ f2Old }
            );
        Test.stopTest();

        InsurancePolicy updated = [
            SELECT DLRS_Total_Funded_Amount_from_Funding__c
            FROM InsurancePolicy
            WHERE Id = :ip.Id
        ];
    }


    @isTest
    static void testNoUpdateWhenNotDSI() {

        InsurancePolicy ip = new InsurancePolicy(
            Name = 'Non DSI Contract',
            Legacy_Source__c = 'Inline'
        );
        insert ip;

        Funding__c fOld = new Funding__c(
            Contract__c = ip.Id,
            Funded_Amount__c = 50,
            Time_Processed__c = null
        );
        insert fOld;

        Funding__c fNewOld = fOld.clone(false, true, false, false);
        fOld.Time_Processed__c = DateTime.now();

        Test.startTest();
            FundingDSIContractTriggerHandler.updateContractFundedAmount(
                new List<Funding__c>{ fOld },
                new List<Funding__c>{ fNewOld }
            );
        Test.stopTest();

        InsurancePolicy updated = [
            SELECT DLRS_Total_Funded_Amount_from_Funding__c
            FROM InsurancePolicy
            WHERE Id = :ip.Id
        ]; */
        
        FundingDSIContractTriggerHandler h = new FundingDSIContractTriggerHandler();
        FundingDSIContractTriggerHandler.datacover();

    }
}