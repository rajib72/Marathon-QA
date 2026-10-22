/**
 * Existing manual ROP Flow action. Scope intentionally remains ALL pending
 * records until client confirms whether list selection should be honored.
 */
global with sharing class ROPUtility {
    @TestVisible private static Boolean forceBatchSubmissionFailure = false;
    private class BatchSubmissionException extends Exception {}

    @InvocableMethod(label='ROP Batchable')
    global static List<FlowResponse> startRopAllocation(List<String> contextIdList) {
        FlowResponse response = new FlowResponse();
        List<FlowResponse> output = new List<FlowResponse>();
        try {
            Integer pending = [
                SELECT COUNT() FROM ROP__c
                WHERE Contract__c != null AND ROP_Amount_Calculated__c != null
                AND Time_Processed__c = null
                AND (ROP_Allocation_Status__c = null OR ROP_Allocation_Status__c = 'Pending')
            ];
            if (pending == 0) {
                response.isSuccess = false;
                response.message = 'No pending ROP records found for allocation.';
                output.add(response);
                return output;
            }
            List<AsyncApexJob> existing = [
                SELECT Id FROM AsyncApexJob
                WHERE ApexClass.Name = 'BatchRopAllocation'
                AND Status IN ('Holding','Preparing','Processing','Queued')
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                response.isSuccess = false;
                response.message = 'Another ROP allocation job is already running. Please try again later.';
                output.add(response);
                return output;
            }
            if (forceBatchSubmissionFailure) {
                throw new BatchSubmissionException('Simulated BatchRopAllocation submission failure.');
            }
            Database.executeBatch(new BatchRopAllocation(), BatchRopAllocation.BATCH_SIZE);
            response.isSuccess = true;
            // Retain the existing Flow-facing response contract.
            response.message = 'ROP allocation job has been started successfully for ' +
                pending + ' pending ROP record(s).';
            output.add(response);
        } catch (Exception e) {
            response.isSuccess = false;
            response.message = 'An internal error occurred while starting the ROP allocation job. Please contact your administrator.';
            output.add(response);
            QDX_Log.Requests req = new QDX_Log.Requests();
            req.errorMessage = response.message + ' Actual Error: ' + e.getMessage();
            req.flowName = 'Start ROP Allocation';
            QDX_Log.publishError(new List<QDX_Log.Requests>{ req });
        }
        return output;
    }
    global class FlowResponse {
        @InvocableVariable(required=true) global Boolean isSuccess;
        @InvocableVariable(required=true) global String message;
    }
}