/**
* @author Raj Sekhar Mukherjee
* @dateModified 19-06-2026
* @ModifiedBy Raj Sekhar Mukherjee
* @description Code coverage for the class - FundingAllocationOrchestrator
*/

public with sharing class FundingAllocationOrchestrator {
    
    @TestVisible
    static Boolean disableBatchExecution = false;
    
    //private static Boolean alreadyInvoked = false;
    
    public static void startAllocation() {
        
        if(Test.isRunningTest() && disableBatchExecution){
            return;
        }
        
        //if(alreadyInvoked){
        //    return;
        //}
        
        //alreadyInvoked = true;
        
        List<AsyncApexJob> runningJobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BatchContractAllocation'
            AND Status IN ('Holding','Preparing','Processing','Queued')
            LIMIT 1
        ];
        
        if(runningJobs.isEmpty()) {
            Database.executeBatch(
                new BatchContractAllocation('Eligible', null),
                3
            );
        }
    }
}