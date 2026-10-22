/**
* @author Saurabh Rawat
* @dateModified 2024-07-31 
* @description This class is used for formation of XML Nodes and data mapping
*/
public class PaymentCalloutHandler {
    
    /**
* Static method for fetching Credentials
* @param requests Key
* @return Key and Value pair of credentials
*/
    public static Map<String,QDX_Property> invokeMethod(){
        Map<String,QDX_Property> propertyMap = new Map<String,QDX_Property>();
        String qdxProps = UtilityClass.MASTERCARD_QDX_PROPERTIES;
        for(String str : qdxProps.split(',')) {
            propertyMap.put(str, QDX_Property.forLabel(str.trim()));
        }
        return propertyMap;
    }
    /**
* Static method for Parsing XML response body into Map
* @param requests Json Result
* @return Key and Value pair of credentials
*/
    public static Map<String,Object> parsedPurchaseLogResponse(Map<String, Object> jsonResult){
        Map<String,Object> vcnInformation_NODE = new Map<String,Object>();
        Map<String,Object> envelope_NODE = jsonResult.containsKey('Envelope')?(Map<String,Object>)jsonResult.get('Envelope'):new Map<String,Object>();
        if(envelope_NODE.size() > 0 && envelope_NODE.containsKey('Body')){
            Map<String,Object> body_NODE = (Map<String,Object>)envelope_NODE.get('Body');
            if(body_NODE.size() > 0 && body_NODE.containsKey('getPurchaseRequestDetail')){
                Map<String,Object> getPurchaseRequestDetail_NODE = (Map<String,Object>)body_NODE.get('getPurchaseRequestDetail');
                if(getPurchaseRequestDetail_NODE.size() > 0 && getPurchaseRequestDetail_NODE.containsKey('vcnInformation')){
                    vcnInformation_NODE = (Map<String,Object>)getPurchaseRequestDetail_NODE.get('vcnInformation');
                }
                if(getPurchaseRequestDetail_NODE.size() > 0 && getPurchaseRequestDetail_NODE.containsKey('errorMessage')) {
                    vcnInformation_NODE = (Map<String,Object>)getPurchaseRequestDetail_NODE.get('errorMessage');
                }
            }
        }
        return vcnInformation_NODE;
    }
    
    //new method for new integration on 25th aug 2026 by Swastika Dey
    public static Map<String, String> parsedPurchaseIdentifiers(
        Map<String, Object> jsonResult
    ) {
        Map<String, String> identifiers = new Map<String, String>();
        
        Map<String, Object> envelopeNode =
            jsonResult.containsKey('Envelope')
            ? (Map<String, Object>)jsonResult.get('Envelope')
            : new Map<String, Object>();
        
        if (
            envelopeNode.isEmpty() ||
            !envelopeNode.containsKey('Body')
        ) {
            return identifiers;
        }
        
        Map<String, Object> bodyNode =
            (Map<String, Object>)envelopeNode.get('Body');
        
        if (
            bodyNode == null ||
            !bodyNode.containsKey('getPurchaseRequestDetail')
        ) {
            return identifiers;
        }
        
        Map<String, Object> purchaseDetailNode =
            (Map<String, Object>)bodyNode.get(
                'getPurchaseRequestDetail'
            );
        
        if (purchaseDetailNode == null) {
            return identifiers;
        }
        
        // BOK Purchase Request Id
        if (
            purchaseDetailNode.containsKey('purchaseRequestId') &&
            purchaseDetailNode.get('purchaseRequestId') != null
        ) {
            identifiers.put(
                'purchaseRequestId',
                String.valueOf(
                    purchaseDetailNode.get('purchaseRequestId')
                )
            );
        }
        
        // BOK VCN Id
        if (
            purchaseDetailNode.containsKey('vcnInformation') &&
            purchaseDetailNode.get('vcnInformation') != null
        ) {
            Map<String, Object> vcnNode =
                (Map<String, Object>)
                purchaseDetailNode.get('vcnInformation');
            
            if (
                vcnNode.containsKey('Id') &&
                vcnNode.get('Id') != null
            ) {
                identifiers.put(
                    'vcnId',
                    String.valueOf(vcnNode.get('Id'))
                );
            }
        }
        
        return identifiers;
    }
    
    public static Map<String, Object> xmlToMap(String xml){
        
        //initialzing XML document
        Dom.Document doc = new Dom.Document();
        doc.load(xml);
        
        //getting the root element and parsing it recursively
        Dom.XMLNode root = doc.getRootElement();
        Object temp = parse(root);
        
        //map to store parsed data
        Map<String, Object> jsonResult = new Map<String, Object>{root.getName() => temp};
            
            //result map having data from the XML string as a map
            return jsonResult;
        
    }
    
    //method to recursively parse child nodes from XML document
    private static Object parse(Dom.XMLNode node){
        
        //map to store data of current XML node
        Map<String, Object> jsonResult = new Map<String, Object>();
        
        //getting list of child elements
        List<Dom.XMLNode> children = node.getChildElements();
        
        //if no child elements found, we simply return the text value
        if(children.isEmpty()){
            return node.getText();
        }
        
        //map to store occurence count of child elements against their names       
        Map<String, Integer> nodeNameCount = new Map<String, Integer>();
        
        //iterating over child elements and populating the count in map
        for(Dom.XMLNode child : children){
            
            String nodeName = child.getName();
            
            if(!nodeNameCount.containsKey(child.getName())){
                nodeNameCount.put(nodeName, 0);
            }
            
            Integer oldCount = nodeNameCount.get(nodeName);
            nodeNameCount.put(nodeName, oldCount + 1);
            
        }
        
        //iterating over child elements and parsing them recursively
        for(Dom.XMLNode child : children) {
            
            Object temp = parse(child);
            String nodeName = child.getName();
            
            //checking if this child is an array 
            Boolean childIsArray = (nodeNameCount.get(nodeName) > 1);
            
            //if child is array, save the values as array, else as strings. 
            if(childIsArray) {  
                
                if(jsonResult.get(nodeName) == null){
                    jsonResult.put(nodeName, new List<Object>{ temp });
                }
                else{
                    List<Object> tempList = (List<Object>)jsonResult.get(nodeName);
                    tempList.add(temp);
                    jsonResult.put(nodeName, tempList);
                }
                
            }
            else{
                jsonResult.put(nodeName, temp);
            }
        }
        
        //result map for current node
        return jsonResult;
        
    }
}