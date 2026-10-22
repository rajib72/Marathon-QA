/*
* @author Qamar Islam (https://github.com/qislam)
* @description This class is for standard property.
*/
global without sharing class QDX_PropertyProvider implements Callable {
    String propertyLabel;
    /**
     * Main call method that routes to specific actions based on the action parameter.
     */
    public Object call(String action, Map<String,Object> args){
        Map<String,Object> result = new Map<String,Object>();
        Map<String,Object> input = (Map<String,Object>)args.get('input');
        Map<String,Object> output = (Map<String,Object>)args.get('output');
        Map<String,Object> options = (Map<String,Object>)args.get('options');
        propertyLabel = String.valueOf(input.get('label'));
        
        if(action == 'invokeMethod') {
            result = (Map<String,Object>)invokeMethod(propertyLabel, input, output, options);
        }
        else if(action == 'invokeMethodWEX') {
            result = (Map<String,Object>)invokeMethodWEX(propertyLabel, input, output, options);
        }
        else if(action == 'addDelay') {
            result = (Map<String,Object>)addDelay(propertyLabel, input, output, options);
        }
        else{
             result = (Map<String,Object>)callLogMethod(action, input, output, options);
        }
        return result;
    }
    /**
     * Invokes a method based on the method name and retrieves necessary credentials.
     */
    private Object invokeMethod(String methodName, Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
        String username = '';
        String password = '';
        List<String> creds = new List<String>();
        QDX_Property obj = QDX_Property.forLabel(methodName);
        String endpointURL = obj.shortValue;
        // Split credentials if available.
        if(!String.isBlank(obj.textValue) && obj.textValue.contains(':')) {
            creds = obj.textValue.split(':');
        }
        if(!creds.isEmpty()) {
            username = creds[0];
            password = creds[1];
        }
        // Populate output map.
        output.put('endpoint', endpointURL);
        output.put('username', username);
        output.put('password', password);
        return output;
    }
    /**
     * Invokes a WEX-specific method and retrieves additional information and credentials.
     */
    private Object invokeMethodWEX(String methodName, Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
        String username = '';
        String password = '';
        String orgGroupLoginId = '';
        List<String> creds = new List<String>();
        QDX_Property obj = QDX_Property.forLabel(methodName);
        String endpointURL = obj.shortValue;
        String creditLimit = obj.text1;
        String accountType = obj.text2;
        String bankNumber = obj.text3;
        String companyNumber = obj.text4;
        // Split credentials if available.
        if(!String.isBlank(obj.textValue) && obj.textValue.contains(':')) {
            creds = obj.textValue.split(':');
        }
        if(!creds.isEmpty()) {
            orgGroupLoginId = creds[0];
            username = creds[1];
            password = creds[2];
        }
        // Populate output map.
        output.put('endpoint', endpointURL);
        output.put('username', username);
        output.put('password', password);
        output.put('orgGroupLoginId', orgGroupLoginId);
        output.put('creditLimit', creditLimit);
        output.put('accountType', accountType);
        output.put('bankNumber', bankNumber);
        output.put('companyNumber', companyNumber);
        return output;
    }
    /**
     * Logs an error message using QDX_Log.
     */
    private Object callLogMethod(String methodName, Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
        QDX_Log.Requests req = new QDX_Log.Requests();
        req.errorMessage = JSON.serialize(input);
        req.flowName = 'IP Step name: WEXPaymentRequest '+methodName;
        // Publish the error log.
        QDX_Log.publishError(new List<QDX_Log.Requests> {req});
        return null;
    }
    /**
     * Adds a delay of 5 seconds.
     */
    private Object addDelay(String methodName, Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
        datetime myStartDateTime = datetime.now();
		DateTime newDateTime = myStartDateTime.addSeconds(5);
        // Busy-wait loop for delay.
        while (datetime.now() < newDateTime ) {
        // sleeping here...sort of
        }
        return null;
    }
}