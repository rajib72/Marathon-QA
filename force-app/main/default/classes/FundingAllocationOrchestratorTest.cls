@IsTest
private class FundingAllocationOrchestratorTest {

    @IsTest
    static void testStartAllocation() {

        Test.startTest();

        FundingAllocationOrchestrator.startAllocation();

        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id,
                   Status,
                   JobType,
                   ApexClass.Name
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchContractAllocation'
        ];

        System.assert(
            jobs.size() > 0,
            'BatchContractAllocation should have been queued.'
        );
    }
}