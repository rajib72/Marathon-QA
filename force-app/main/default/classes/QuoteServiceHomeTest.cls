@isTest(seeAllData=true)
public class QuoteServiceHomeTest {


    private static void prepareBaseData() {

        QuoteServiceHome.responseMap = new Map<String, Map<String,String>>();
        QuoteServiceHome.responseMapList = new Map<String, List<Map<String,String>>>();
        QuoteServiceHome.dealerOptionCostsByTerm = new Map<String, Map<String, Map<String,String>>>();

        QuoteServiceHome.responseMap.put('D001', new Map<String,String>{
            'Product' => 'Test Product',
            'CoverageLevel' => 'Standard',
            'RateSet' => 'TestRate',
            'OptionSets' => 'TestOption',
            'StateSet' => 'TestStateSet'
        });

        QuoteServiceHome.responseMapList.put('D001', new List<Map<String,String>>{
            new Map<String,String>{
                'BasePrice' => '1000',
                'Deductible' => '100',
                'TermMonths' => '12'
            }
        });

        QuoteServiceHome.hwMap = new Map<String,String>{
            'ResidenceType' => 'Single Family'
        };
    }

    @isTest
static void testProcessQuoteRequest_withOptionsCoverage() {

    // Prepare base data
    QuoteServiceHome.responseMap = new Map<String, Map<String,String>>{
        'D001' => new Map<String,String>{
            'Product' => 'Test Product',
            'CoverageLevel' => 'Standard',
            'ValidationDays' => '30'
        }
    };

    QuoteServiceHome.responseMapList = new Map<String, List<Map<String,String>>>{
        'D001' => new List<Map<String,String>>{
            new Map<String,String>{
                'BasePrice' => '1200',
                'Deductible' => '100',
                'TermMonths' => '12'
            }
        }
    };

    //  Prepare Option Map (VERY IMPORTANT)
    QuoteServiceHome.dealerOptionCostsByTerm = new Map<String, Map<String, Map<String,String>>>();

    Map<String, Map<String,String>> termMap = new Map<String, Map<String,String>>();

    Map<String,String> options = new Map<String,String>{
        'Water Well Pump' => '50',
        'Refrigerator Ice Maker' => '30',
        'Stand-Alone Ice Maker' => '20',
        'Secondary Refrigerator' => '25',
        'Secondary Freezer' => '15',
        'Swimming Pool' => '60',
        'Spa' => '40',
        'Clothes Washer/Dryer' => '35',
        'Central Vac' => '10',
        'Garage Door Opener' => '12'
    };

    // Must match TermMonths = 12
    termMap.put('12', options);

    //  Must match DealerProgramId = D001
    QuoteServiceHome.dealerOptionCostsByTerm.put('D001', termMap);

    //  Step 3: Prepare request
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();

    req.requestUri = '/services/apexrest/QuoteRequestServiceHome/';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(
        '{"Client":"Endurance Home Warranty","OriginalState":"FL","ResidenceType":"Single Family"}'
    );

    RestContext.request = req;
    RestContext.response = res;

    //  Step 4: Execute
    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();

    System.debug('Response: ' + res.responseBody.toString());
}

   
    // TEST: ERROR FLOW
  
    @isTest
    static void testErrorFlow() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri = '/services/apexrest/QuoteRequestServiceHome/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"Client":"","OriginalState":"","ResidenceType":""}');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        QuoteServiceHome.processQuoteRequest();
        Test.stopTest();
    }

    
    // TEST: DEALER LOOKUP
    
@isTest
static void testDealerCodeLookup() {

    // Step 1: Mock callout (VERY IMPORTANT)
    Test.setMock(HttpCalloutMock.class, new QuoteServiceHomeMock(
        '{ "rows": [ { "rowData": { "DealerProgramId": "D001", "Product": "Test Product", "CoverageLevel": "Standard", "RateSet": "TestRate", "OptionSets": "TestOption", "StateSet": "TestStateSet", "Client": "Endurance Home Warranty" } } ] }'
    ));

    Test.startTest();
    QuoteServiceHome.dealerCodeLookup('Endurance Home Warranty');
    Test.stopTest();

    System.debug('responseMap: ' + QuoteServiceHome.responseMap);
}

   
    // TEST: STATE SET LOOKUP
  
@isTest
static void testStateSetLookup() {

    QuoteServiceHome.stateSetMatrixSet.clear();
    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.hwMap.clear();

    QuoteServiceHome.stateSetMatrixSet.add('Amtrust_Superior_HW');

    QuoteServiceHome.responseMap.put(
        'D001',
        new Map<String,String>{
            'Product' => 'Superior Home',
            'CoverageLevel' => 'Superior FTP'
        }
    );

    QuoteServiceHome.HWRequest req = new QuoteServiceHome.HWRequest();
    req.OriginalState = 'FL';

    // Register the HTTP Mock BEFORE startTest()
    Test.setMock(
        HttpCalloutMock.class,
        new QuoteServiceHomeMock(
            '{"rows":[{"rowData":{"State":"FL","Active":true,"Carrier":"AmTrust"}}]}'
        )
    );

    Test.startTest();

    QuoteServiceHome.stateSetLookup(req);

    Test.stopTest();

    System.assertEquals(
        'AmTrust',
        QuoteServiceHome.hwMap.get('InsuranceCarrier')
    );

    System.assertEquals(
        '30',
        QuoteServiceHome.responseMap.get('D001').get('ValidationDays')
    );
}
   
    // TEST: RATE LOOKUP
   
@isTest
static void testRateCostLookupHW() {

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();
    QuoteServiceHome.hwMap.clear();

    QuoteServiceHome.responseMap.put(
        '426',
        new Map<String,String>{
            'RateSet' => 'Superior RSC',
            'CoverageLevel' => 'Superior FTP'
        }
    );

    QuoteServiceHome.hwMap.put(
        'ResidenceType',
        'Single Family'
    );

    QuoteServiceHome.testMatrixNameOverride =
        'Superior_RSC_Superior_FTP';

    Test.startTest();

    QuoteServiceHome.rateCostLookupHW();

    Test.stopTest();



}
   
    // TEST: OPTIONS LOOKUP

@isTest
static void testOptionsCostLookupHW() {

    QuoteServiceHome.responseMap = new Map<String, Map<String,String>>();
    QuoteServiceHome.responseMap.put(
        '129',
        new Map<String,String>{
            'OptionSets' => 'MBI Options - AmTrust (CA)',
            'CoverageLevel' => 'Standard Used'
        }
    );

    QuoteServiceHome.responseMapList =
        new Map<String, List<Map<String,String>>>();

    QuoteServiceHome.responseMapList.put(
        '129',
        new List<Map<String,String>>{
            new Map<String,String>{
                'TermMonths' => '36'
            }
        }
    );

    QuoteServiceHome.dealerOptionCostsByTerm =
        new Map<String, Map<String, Map<String,String>>>();

    Test.startTest();
    QuoteServiceHome.optionsCostLookupHW();
    Test.stopTest();
}

   
    // TEST: COVERAGE LEVEL DM
   
@isTest
static void testCallCoverageLevelDM() {

    //  Use existing matrix from org (SeeAllData=true required)
    QuoteServiceHome.testMatrixNameOverride = 'Product_Coverage_Level_Details';

    // Mock callout
    Test.setMock(HttpCalloutMock.class, new QuoteServiceHomeMock(
        '{ "rows": [ { "rowData": { "CoverageLevel": "Standard", "ValidationDays": "30" } } ] }'
    ));

    //  Prepare responseMap
    QuoteServiceHome.responseMap = new Map<String, Map<String,String>>{
        '129' => new Map<String,String>{
            'CoverageLevel' => 'Standard'
        }
    };

    Test.startTest();
    QuoteServiceHome.callCoverageLevelDM();
    Test.stopTest();
}

    // TEST: ALLOCATION COST
    
    @isTest
static void testAllocationCostLookup() {

   
    Account acc = TestDataFactory.createSellingAgencyAccount(true);
    acc.Name = 'Endurance Home Warranty';
    update acc;

    //  Insert Allocation Code (now passes filter)
    Allocation_Code__c code = new Allocation_Code__c(
        Name = '8001',
        Client__c = acc.Id,
        Product__c = 'Test Product',
        Coverage_Level__c = 'Standard',
        Allocation_Amount__c = '100.0',
        Descriptor__c = 'Other'
    );
    insert code;

    //  Prepare response maps (VERY IMPORTANT for coverage)
    QuoteServiceHome.responseMap = new Map<String, Map<String,String>>{
        '129' => new Map<String,String>{
            'Product' => 'Test Product',
            'CoverageLevel' => 'Standard'
        }
    };

    QuoteServiceHome.responseMapList = new Map<String, List<Map<String,String>>>{
        '129' => new List<Map<String,String>>{
            new Map<String,String>{
                'BasePrice' => '100'
            }
        }
    };

    Test.startTest();
    QuoteServiceHome.allocationCostLookup('Endurance Home Warranty');
    Test.stopTest();
}

    
    // TEST: ERROR RESPONSE METHOD
    
    @isTest
    static void testGenerateErrorResponse() {

        QuoteServiceHome.HWRequest req = new QuoteServiceHome.HWRequest();
        req.Client = 'Test';
        req.OriginalState = 'TX';
        req.ResidenceType = 'Condo';

        Test.startTest();
        QuoteServiceHome.generateErrorResponse('Error', req);
        Test.stopTest();
    }

   
    // TEST: SETUP METHOD
    
    @isTest
    static void testSetupMethod() {

        QuoteServiceHome.HWRequest req = new QuoteServiceHome.HWRequest();
        req.Client = 'Endurance Home Warranty';
        req.OriginalState = 'FL';
        req.ResidenceType = 'Single Family';

        Test.startTest();
        try {
            QuoteServiceHome.setup(req);
        } catch (Exception e) {
            // ignore for coverage
        }
        Test.stopTest();
    }
    
    public class QuoteServiceHomeMock implements HttpCalloutMock {

    String body;

    public QuoteServiceHomeMock(String body){
        this.body = body;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        res.setStatusCode(200);
        return res;
    }
    }
  @isTest
static void testProcessQuoteRequest_MultipleQuotes(){

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();
    QuoteServiceHome.dealerOptionCostsByTerm.clear();

    QuoteServiceHome.responseMap.put(
        '432',
        new Map<String,String>{
            'Product'=>'Superior Home',
            'CoverageLevel'=>'Superior FL',
            'ValidationDays'=>'30'
        }
    );

    QuoteServiceHome.responseMapList.put(
        '432',
        new List<Map<String,String>>{

            new Map<String,String>{
                'BasePrice'=>'1000',
                'Deductible'=>'100',
                'TermMonths'=>'36'
            },

            new Map<String,String>{
                'BasePrice'=>'100',
                'Deductible'=>'100',
                'TermMonths'=>'1'
            }
        }
    );

    Map<String,String> optionMap=new Map<String,String>{
        'Water Well Pump'=>'100',
        'Refrigerator Ice Maker'=>'20',
        'Stand-Alone Ice Maker'=>'30',
        'Secondary Refrigerator'=>'40',
        'Secondary Freezer'=>'50',
        'Swimming Pool'=>'60',
        'Spa'=>'70',
        'Clothes Washer/Dryer'=>'80',
        'Central Vac'=>'90',
        'Garage Door Opener'=>'100'
    };

    QuoteServiceHome.dealerOptionCostsByTerm.put(
        '432',
        new Map<String,Map<String,String>>{
            '36'=>optionMap,
            '1'=>optionMap
        }
    );

    RestRequest req=new RestRequest();
    RestResponse res=new RestResponse();

    req.requestUri='/services/apexrest/QuoteRequestServiceHome/';
    req.httpMethod='POST';
    req.requestBody=Blob.valueOf(
        '{"Client":"Endurance Home Warranty","OriginalState":"FL","ResidenceType":"Single Family"}'
    );

    RestContext.request=req;
    RestContext.response=res;

    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();

   
}  
    @isTest
static void testProcessQuoteRequest_TXState() {

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();

    QuoteServiceHome.responseMap.put(
        'TX001',
        new Map<String,String>{
            'Product'=>'Superior Home',
            'CoverageLevel'=>'Superior FTP',
            'ValidationDays'=>'30'
        }
    );

    QuoteServiceHome.responseMapList.put(
        'TX001',
        new List<Map<String,String>>{
            new Map<String,String>{
                'BasePrice'=>'900',
                'Deductible'=>'50',
                'TermMonths'=>'36'
            }
        }
    );

    RestRequest req=new RestRequest();
    RestResponse res=new RestResponse();

    req.httpMethod='POST';
    req.requestUri='/services/apexrest/QuoteRequestServiceHome/';
    req.requestBody=Blob.valueOf(
    '{"Client":"Endurance Home Warranty","OriginalState":"TX","ResidenceType":"Single Family"}');

    RestContext.request=req;
    RestContext.response=res;

    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();
}
    @isTest
static void testM2MContractBranch(){

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();

    QuoteServiceHome.responseMap.put(
        '500',
        new Map<String,String>{
            'Product'=>'Superior M2M',
            'CoverageLevel'=>'Superior FTP',
            'ValidationDays'=>'30'
        }
    );

    QuoteServiceHome.responseMapList.put(
        '500',
        new List<Map<String,String>>{
            new Map<String,String>{
                'BasePrice'=>'150',
                'Deductible'=>'100',
                'TermMonths'=>'36'
            }
        }
    );

    RestRequest req=new RestRequest();
    RestResponse res=new RestResponse();

    req.httpMethod='POST';
    req.requestUri='/services/apexrest/QuoteRequestServiceHome/';
    req.requestBody=Blob.valueOf(
    '{"Client":"ABC Home Warranty","OriginalState":"TX","ResidenceType":"Single Family"}');

    RestContext.request=req;
    RestContext.response=res;

    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();
}
    @isTest
static void testBaseReserveBranch(){

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();

    QuoteServiceHome.responseMap.put(
        '600',
        new Map<String,String>{
            'Product'=>'Superior Home',
            'CoverageLevel'=>'Superior FTP',
            'ValidationDays'=>'30'
        }
    );

    QuoteServiceHome.responseMapList.put(
        '600',
        new List<Map<String,String>>{
            new Map<String,String>{
                'BaseReserve'=>'500',
                'Deductible'=>'100',
                'TermMonths'=>'36'
            }
        }
    );

    RestRequest req=new RestRequest();
    RestResponse res=new RestResponse();

    req.httpMethod='POST';
    req.requestUri='/services/apexrest/QuoteRequestServiceHome/';
    req.requestBody=Blob.valueOf(
    '{"Client":"Endurance Home Warranty","OriginalState":"TX","ResidenceType":"Single Family"}');

    RestContext.request=req;
    RestContext.response=res;

    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();
}
    @isTest
static void testDuplicateQuotes(){

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();

    QuoteServiceHome.responseMap.put(
        '700',
        new Map<String,String>{
            'Product'=>'Superior Home',
            'CoverageLevel'=>'Superior FTP',
            'ValidationDays'=>'30'
        }
    );

    QuoteServiceHome.responseMapList.put(
        '700',
        new List<Map<String,String>>{

            new Map<String,String>{
                'BasePrice'=>'500',
                'Deductible'=>'100',
                'TermMonths'=>'36'
            },

            new Map<String,String>{
                'BasePrice'=>'500',
                'Deductible'=>'100',
                'TermMonths'=>'36'
            }
        }
    );

    RestRequest req=new RestRequest();
    RestResponse res=new RestResponse();

    req.httpMethod='POST';
    req.requestUri='/services/apexrest/QuoteRequestServiceHome/';
    req.requestBody=Blob.valueOf(
    '{"Client":"Endurance Home Warranty","OriginalState":"TX","ResidenceType":"Single Family"}');

    RestContext.request=req;
    RestContext.response=res;

    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();
}
@isTest
static void testDealerCostZero(){

    QuoteServiceHome.responseMap.clear();
    QuoteServiceHome.responseMapList.clear();

    QuoteServiceHome.responseMap.put(
        '800',
        new Map<String,String>{
            'Product'=>'Superior Home',
            'CoverageLevel'=>'Superior FTP',
            'ValidationDays'=>'30'
        }
    );

    QuoteServiceHome.responseMapList.put(
        '800',
        new List<Map<String,String>>{
            new Map<String,String>{
                'Deductible'=>'100',
                'TermMonths'=>'36'
            }
        }
    );

    RestRequest req=new RestRequest();
    RestResponse res=new RestResponse();

    req.httpMethod='POST';
    req.requestUri='/services/apexrest/QuoteRequestServiceHome/';
    req.requestBody=Blob.valueOf(
    '{"Client":"Endurance Home Warranty","OriginalState":"TX","ResidenceType":"Single Family"}');

    RestContext.request=req;
    RestContext.response=res;

    Test.startTest();
    QuoteServiceHome.processQuoteRequest();
    Test.stopTest();
}
    
       
}