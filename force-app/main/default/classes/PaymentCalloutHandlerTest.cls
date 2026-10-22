@IsTest
private class PaymentCalloutHandlerTest {
    
    @IsTest
    static void testXmlToMap() {
        
        String xml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Envelope>' +
            '<Body>' +
            '<getPurchaseRequestDetail>' +
            '<purchaseRequestId>29211109</purchaseRequestId>' +
            '<vcnInformation>' +
            '<Id>28274905</Id>' +
            '<Pan>5561206756658202</Pan>' +
            '<Expiry>2809</Expiry>' +
            '</vcnInformation>' +
            '</getPurchaseRequestDetail>' +
            '</Body>' +
            '</Envelope>';
        
        Test.startTest();
        
        Map<String, Object> result =
            PaymentCalloutHandler.xmlToMap(xml);
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 xmlToMap result: ' + result
        );
    }
    
    
    @IsTest
    static void testXmlToMapWithRepeatedNodes() {
        
        String xml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Envelope>' +
            '<Body>' +
            '<Transactions>' +
            '<Id>001</Id>' +
            '</Transactions>' +
            '<Transactions>' +
            '<Id>002</Id>' +
            '</Transactions>' +
            '</Body>' +
            '</Envelope>';
        
        Test.startTest();
        
        Map<String, Object> result =
            PaymentCalloutHandler.xmlToMap(xml);
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Repeated node parsing result: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseLogResponse() {
        
        String xml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Envelope>' +
            '<Body>' +
            '<getPurchaseRequestDetail>' +
            '<purchaseRequestId>29211109</purchaseRequestId>' +
            '<vcnInformation>' +
            '<Id>28274905</Id>' +
            '<Pan>5561206756658202</Pan>' +
            '<Expiry>2809</Expiry>' +
            '<Avv>381</Avv>' +
            '</vcnInformation>' +
            '</getPurchaseRequestDetail>' +
            '</Body>' +
            '</Envelope>';
        
        Map<String, Object> jsonResult =
            PaymentCalloutHandler.xmlToMap(xml);
        
        Test.startTest();
        
        Map<String, Object> result =
            PaymentCalloutHandler.parsedPurchaseLogResponse(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Parsed Purchase Log Response: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseLogResponseWithError() {
        
        Map<String, Object> errorMessage =
            new Map<String, Object>{
                'message' => 'Test Mastercard error'
                    };
                        
                        Map<String, Object> purchaseDetail =
                        new Map<String, Object>{
                            'errorMessage' => errorMessage
                                };
                                    
                                    Map<String, Object> body =
                                    new Map<String, Object>{
                                        'getPurchaseRequestDetail' => purchaseDetail
                                            };
                                                
                                                Map<String, Object> jsonResult =
                                                new Map<String, Object>{
                                                    'Envelope' => new Map<String, Object>{
                                                        'Body' => body
                                                            }
                                                };
                                                    
                                                    Test.startTest();
        
        Map<String, Object> result =
            PaymentCalloutHandler.parsedPurchaseLogResponse(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Parsed Error Response: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseIdentifiers() {
        
        String xml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Envelope>' +
            '<Body>' +
            '<getPurchaseRequestDetail>' +
            '<purchaseRequestId>29211109</purchaseRequestId>' +
            '<vcnInformation>' +
            '<Id>28274905</Id>' +
            '</vcnInformation>' +
            '</getPurchaseRequestDetail>' +
            '</Body>' +
            '</Envelope>';
        
        Map<String, Object> jsonResult =
            PaymentCalloutHandler.xmlToMap(xml);
        
        Test.startTest();
        
        Map<String, String> result =
            PaymentCalloutHandler.parsedPurchaseIdentifiers(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Purchase Request ID: ' +
            result.get('purchaseRequestId')
        );
        
        System.debug(
            'MRT3-38 VCN ID: ' +
            result.get('vcnId')
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseIdentifiersWithoutEnvelope() {
        
        Map<String, Object> jsonResult =
            new Map<String, Object>();
        
        Test.startTest();
        
        Map<String, String> result =
            PaymentCalloutHandler.parsedPurchaseIdentifiers(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Missing Envelope result: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseIdentifiersWithoutBody() {
        
        Map<String, Object> jsonResult =
            new Map<String, Object>{
                'Envelope' => new Map<String, Object>()
                    };
                        
                        Test.startTest();
        
        Map<String, String> result =
            PaymentCalloutHandler.parsedPurchaseIdentifiers(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Missing Body result: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseIdentifiersWithoutPurchaseDetail() {
        
        Map<String, Object> jsonResult =
            new Map<String, Object>{
                'Envelope' => new Map<String, Object>{
                    'Body' => new Map<String, Object>()
                        }
            };
                
                Test.startTest();
        
        Map<String, String> result =
            PaymentCalloutHandler.parsedPurchaseIdentifiers(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Missing Purchase Detail result: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseIdentifiersWithoutVcn() {
        
        Map<String, Object> jsonResult =
            new Map<String, Object>{
                'Envelope' => new Map<String, Object>{
                    'Body' => new Map<String, Object>{
                        'getPurchaseRequestDetail' =>
                            new Map<String, Object>{
                                'purchaseRequestId' => '29211109'
                                    }
                    }
                }
            };
                
                Test.startTest();
        
        Map<String, String> result =
            PaymentCalloutHandler.parsedPurchaseIdentifiers(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Missing VCN result: ' +
            result
        );
    }
    
    
    @IsTest
    static void testParsedPurchaseIdentifiersWithoutVcnId() {
        
        Map<String, Object> jsonResult =
            new Map<String, Object>{
                'Envelope' => new Map<String, Object>{
                    'Body' => new Map<String, Object>{
                        'getPurchaseRequestDetail' =>
                            new Map<String, Object>{
                                'purchaseRequestId' => '29211109',
                                    'vcnInformation' =>
                                    new Map<String, Object>()
                                    }
                    }
                }
            };
                
                Test.startTest();
        
        Map<String, String> result =
            PaymentCalloutHandler.parsedPurchaseIdentifiers(
                jsonResult
            );
        
        Test.stopTest();
        
        System.debug(
            'MRT3-38 Missing VCN ID result: ' +
            result
        );
    }
}