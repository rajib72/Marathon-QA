/**
* @author: Saurabh Rawat
* @dateModified: 2024-05-22
* @description: Test class for code coverage of class IntegrationProcedureInvocable.
*/
@isTest
public class IntegrationProcedureInvocableTest {

  @isTest
  static void testRunIntegrationServiceInvocable() {
    
       List<IntegrationProcedureInvocable.IntegrationProcedureInput> inputList = new List<IntegrationProcedureInvocable.IntegrationProcedureInput>();
       IntegrationProcedureInvocable.IntegrationProcedureInput input = new IntegrationProcedureInvocable.IntegrationProcedureInput();
        input.procedureAPIName = 'TestProcedureAPI';
        input.inputValue = 'TestId';
        inputList.add(input);
      
        Test.startTest();
        List<IntegrationProcedureInvocable.IntegrationProcedureOutput> result = IntegrationProcedureInvocable.runIntegrationServiceInvocable(inputList);
        Test.stopTest();
      
        System.assertEquals(1, result.size(), 'Expected one result');
        System.assertNotEquals(null, result[0].output, 'Output should not be null');
  }
}