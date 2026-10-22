/**
* @author Sujit Dengale
* @dateModified 2026-10-05
* @ModifiedBy Raj Sekhar Mukherjee
* @description Validation-safe and focused test coverage for FundingUtility.
*
* Design notes:
* - FundingUtility itself does not require Contract/Funding/Allocation test data.
* - The previous tests created InsurancePolicy records only to obtain a context Id,
*   which made this unit test dependent on Sold_Contract_Validation and other
*   InsurancePolicy validation rules.
* - These tests exercise FundingUtility's actual control-flow branches directly:
*      1) non-null context Id -> batch submitted
*      2) null context Id     -> batch submitted
*      3) existing batch      -> duplicate submission blocked
*      4) invalid input       -> catch/error response
*/
@IsTest
public class FundingUtilityTest {
    
    /**
* Returns a syntactically valid InsurancePolicy Id without inserting a
* Contract. This covers the non-null context branch without invoking
* InsurancePolicy validation rules.
*/
    private static String syntheticPolicyId() {
        
        String prefix =
            InsurancePolicy.SObjectType
            .getDescribe()
            .getKeyPrefix();
        
        System.assertNotEquals(
            null,
            prefix,
            'InsurancePolicy must have an Id prefix.'
        );
        
        return prefix + '000000000001';
    }
    
    /**
* Normal success path with a NON-NULL context Id.
*
* No Contract record is required by FundingUtility itself. The synthetic
* Id prevents Sold_Contract_Validation from becoming an unrelated test
* dependency.
*/
    @IsTest
    private static void FundingTriggerHandlerTestMethod() {
        
        List<String> contextIdList =
            new List<String>{
                syntheticPolicyId()
                    };
                        
                        Test.startTest();
        
        List<FundingUtility.FlowResponse> response =
            FundingUtility.fundingAsyncJob(
                contextIdList
            );
        
        Test.stopTest();
        
        System.assertEquals(
            1,
            response.size(),
            'Exactly one Flow response should be returned.'
        );
        
        System.assertEquals(
            true,
            response[0].isSuccess,
            'A Funding allocation job should be submitted.'
        );
        
        System.assertEquals(
            UtilityClass.FUNDING_FLOW_STARTED,
            response[0].message,
            'The success response should use the configured Funding message.'
        );
    }
    
    /**
* Deterministically covers the catch block.
*
* FundingUtility dereferences contextIdList[0] when no job is running.
* An empty list therefore throws inside the method and must be converted
* into the standard internal-error FlowResponse.
*/
    @IsTest
    private static void FundingTriggerHandlerTestMethod1() {
        
        Test.startTest();
        
        List<FundingUtility.FlowResponse> response =
            FundingUtility.fundingAsyncJob(
                new List<String>()
            );
        
        Test.stopTest();
        
        System.assertEquals(
            1,
            response.size(),
            'The exception path should still return one Flow response.'
        );
        
        System.assertEquals(
            false,
            response[0].isSuccess,
            'Invalid input should be converted into a controlled failure.'
        );
        
        System.assertEquals(
            UtilityClass.FUNDING_FLOW_INTERNAL_ERR,
            response[0].message,
            'The catch path should return the standard internal-error message.'
        );
    }
    
    /**
* Covers the "another BatchContractAllocation job is already running"
* branch.
*
* The first invocation enqueues one batch. Before Test.stopTest(), that
* AsyncApexJob is visible as queued/holding/preparing/processing, so the
* second invocation must refuse to enqueue another batch.
*/
    @IsTest
    private static void FundingTriggerHandlerTestMethod2() {
        
        Test.startTest();
        
        List<FundingUtility.FlowResponse> firstResponse =
            FundingUtility.fundingAsyncJob(
                new List<String>{ null }
            );
        
        List<FundingUtility.FlowResponse> secondResponse =
            FundingUtility.fundingAsyncJob(
                new List<String>{ null }
            );
        
        Test.stopTest();
        
        System.assertEquals(
            1,
            firstResponse.size(),
            'The first invocation should return one response.'
        );
        
        System.assertEquals(
            true,
            firstResponse[0].isSuccess,
            'The first invocation should submit the batch.'
        );
        
        System.assertEquals(
            1,
            secondResponse.size(),
            'The duplicate invocation should return one response.'
        );
        
        System.assertEquals(
            false,
            secondResponse[0].isSuccess,
            'A second allocation batch must not be submitted while one is active.'
        );
        
        System.assertEquals(
            UtilityClass.FUNDING_FLOW_JOB_RUNNING,
            secondResponse[0].message,
            'The duplicate-job branch should return the configured running-job message.'
        );
    }
    
    /**
* Explicitly covers the NULL-context branch in FundingUtility.
*/
    @IsTest
    private static void FundingTriggerHandlerTestMethod3() {
        
        Test.startTest();
        
        List<FundingUtility.FlowResponse> response =
            FundingUtility.fundingAsyncJob(
                new List<String>{ null }
            );
        
        Test.stopTest();
        
        System.assertEquals(
            1,
            response.size(),
            'Exactly one Flow response should be returned.'
        );
        
        System.assertEquals(
            true,
            response[0].isSuccess,
            'A null context should still start the general Eligible allocation batch.'
        );
        
        System.assertEquals(
            UtilityClass.FUNDING_FLOW_STARTED,
            response[0].message,
            'The null-context success branch should return the standard success message.'
        );
    }
}