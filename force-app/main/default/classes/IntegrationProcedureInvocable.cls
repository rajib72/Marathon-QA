/**
* @author Saurabh Rawat
* @dateModified 2024-05-23
* @description This class is used for invoking integration prcedure from apex.
*/
global with sharing class IntegrationProcedureInvocable{
    
/**
* Invocable method that runs an integration procedure.
* @param input List of IntegrationProcedureInput containing the procedure API name and input.
* @return List of IntegrationProcedureOutput containing the serialized result of the integration procedure.
*/
    @InvocableMethod(label = 'Integration Procedure')
    global static List < IntegrationProcedureOutput > runIntegrationServiceInvocable(List < IntegrationProcedureInput > input) {
        IntegrationProcedureOutput result = new IntegrationProcedureOutput();
        List<String> claimItemIds = new List<String>();
        for(IntegrationProcedureInput eachInput : input){
            claimItemIds.add(eachInput.inputValue);
        }
            // Create an output object to hold the result.
        
        // Run the integration procedure and serialize the output to JSON.
           
        result.output = JSON.serialize(
            omnistudio.IntegrationProcedureService.runIntegrationService(
                input[0].procedureAPIName,
                new Map <String, Object>{'Data' => claimItemIds},
                new Map <String, Object>()
            )
        ); 
        // Return the result wrapped in a list.
        return new List < IntegrationProcedureOutput >{result};
     }
    // Class to hold the input parameters for the invocable method.
    global class IntegrationProcedureInput
    {
        @InvocableVariable(label = 'Procedure Name') global String procedureAPIName;
        @InvocableVariable(label = 'Input') global String inputValue;
    }
    // Class to hold the output of the invocable method.
    global class IntegrationProcedureOutput
    {
        @InvocableVariable(label = 'Output') global String output;
    }
}