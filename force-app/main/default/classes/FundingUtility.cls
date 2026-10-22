/**
* @author Sujit Dengale
* @dateModified 22-05-2024
* @description Invoke the fundingAsyncJob method from the Flow
*/
global class FundingUtility {
@InvocableMethod(label='Funding Batcheable')
    public static List<FlowResponse> fundingAsyncJob(List<String> contextIdList){
        FlowResponse response = new FlowResponse();
        List<FlowResponse> returnResponse = new List<FlowResponse>();
        try{
            List<AsyncApexJob> asyncList = [select Id, ApexClass.Name, Status from AsyncApexJob where ApexClass.Name = 'BatchContractAllocation' AND Status IN ('Holding','Preparing','Processing','Queued')];
            if(asyncList.isEmpty()){
                // return 'Funding allocation job has been started'
                if(contextIdList[0] != NULL){
                    // Database.executeBatch(new BatchContractAllocation('Eligible',contextIdList[0]),1);
                    Database.executeBatch(new BatchContractAllocation('Eligible',contextIdList[0]),3); // Ticket 'Update BatchContractAllocation & BatchRopAllocation Batch Size'
                } else {
                    // Database.executeBatch(new BatchContractAllocation('Eligible',NULL),1);
                    Database.executeBatch(new BatchContractAllocation('Eligible',NULL),3); // Ticket 'Update BatchContractAllocation & BatchRopAllocation Batch Size'
                }
                response.isSuccess = true;
                response.message = UtilityClass.FUNDING_FLOW_STARTED;
                returnResponse.add(response);
            }
            else if(!asyncList.isEmpty()){
                // return 'Another allocation job is already running.  Please try it later.'
                response.isSuccess = false;
                response.message = UtilityClass.FUNDING_FLOW_JOB_RUNNING;
                returnResponse.add(response);
            }
        }
        catch(Exception e){
            // return 'An internal error has happened.  Please contact an administrator.'
            response.isSuccess = false;
            response.message = UtilityClass.FUNDING_FLOW_INTERNAL_ERR;
            returnResponse.add(response);
            QDX_Log.Requests req = new QDX_Log.Requests();
            req.errorMessage = response.message;
            req.flowName = 'Funding Import File Process';
            QDX_Log.publishError(new List<QDX_Log.Requests> {req});
        }
        if(returnResponse!= NULL){
            return returnResponse;
        }
        else return NULL;
    }
    
    
    global class FlowResponse {
        @InvocableVariable(required=true)
        global boolean isSuccess;
        
        @InvocableVariable(required=true)
        global String message;
    }
}