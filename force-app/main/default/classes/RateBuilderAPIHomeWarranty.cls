/**
 * REST Resource class for executing quote request for Rate Implementation Builder API
 * This class exposes a POST endpoint to quote request for Rate Implementation Builder API
 * and returns a processed response.
 */
@RestResource(UrlMapping='/RateImplementationBuilderHW/*')
global class RateBuilderAPIHomeWarranty {
  public static Map<String, Map<String, String>> responseMap = new Map<String, Map<String, String>>();
  public static Map<String, String> requestDataMap = new Map<String, String>();
  public static Set<String> classGuideValues = new Set<String>();
  public static Boolean isCountRequired = false;
  public static Integer offSet = 0;

  @HttpPost
  global static String processRateImplementation() {
    RestRequest request = RestContext.request;
    RestResponse response = RestContext.response;
    RateBuilderAPIHomeWarranty.RateRequest requestObj;

    String responseStr = '';

    try {
      System.debug('@@@DEBUG:: request body from pentaho: ' + request.requestBody.toString());
      // Deserialize request body to QuoteService.EnduranceRequest object
      requestObj = (RateBuilderAPIHomeWarranty.RateRequest) JSON.deserialize(
        request.requestBody.toString(),
        RateBuilderAPIHomeWarranty.RateRequest.class
      );
      isCountRequired = request.params.containsKey('isCountRequired')
        ? Boolean.valueOf(request.params.get('isCountRequired'))
        : false;
      offSet = request.params.containsKey('offSet')
        ? Integer.valueOf(request.params.get('offSet'))
        : 0;
      responseStr = setup(requestObj);
    } catch (Exception e) {
      //log error
      QDX_LOG.error(
        'Message*****' +
          e.getMessage() +
          '@@@@@@@@@@Line Number*******' +
          e.getLineNumber()
      );
      generateErrorResponse(e.getMessage());
    } finally {
      // Ensure logs are published regardless of success or failure
      QDX_LOG.publish();
    }
    System.debug('@@@responseStr: ' + responseStr);
    return responseStr;
  }

  //generates error response
  public static String generateErrorResponse(String errorMessage) {
    RateBuilderAPIHomeWarranty.ErrorResponseGenerator errorResponseObj = new RateBuilderAPIHomeWarranty.ErrorResponseGenerator();
    RateBuilderAPIHomeWarranty.ErrorPayload errorPayload = new RateBuilderAPIHomeWarranty.ErrorPayload();

    errorResponseObj.status = 400;
    errorResponseObj.error = errorMessage;
    errorResponseObj.payload = errorPayload;
    return JSON.serialize(errorResponseObj);
  }

  /**
   * the main setup methods that invokes child methods to populate response map
   */
  public static String setup(
    RateBuilderAPIHomeWarranty.RateRequest requestObj
  ) {
    String response = '';
    //popuate vehicleMap global variable
    requestDataMap.put('Client', requestObj.Client);
    requestDataMap.put('Product', requestObj.Product);
    requestDataMap.put('CoverageLevel', requestObj.CoverageLevel);
    requestDataMap.put('RequestType', requestObj.RequestType);
    requestDataMap.put(
      'State',
      requestObj.State != null ? requestObj.State : ''
    );
    requestDataMap.put(
      'InsuranceCarrier',
      requestObj.InsuranceCarrier != null ? requestObj.InsuranceCarrier : ''
    );
    requestDataMap.put(
      'EffectiveDate',
      String.valueOf(requestObj.EffectiveDate)
    ); //Rate Builder: Report Request Outputs Based on Effective Date

    //call DM methods to populate responseMap global variable
    if (requestObj != null && requestObj.RequestType == 'Dealer Cost Rates') {
      dealerCodeLookup(requestDataMap);
      response = rateSetsDMCall();
    } else if (requestObj != null && requestObj.RequestType == 'Rate Options') {
      dealerCodeLookup(requestDataMap);
      response = optionSetsDMCall();
    } else if (
      requestObj != null &&
      requestObj.RequestType == 'Rate Surcharges'
    ) {
      dealerCodeLookup(requestDataMap);
      response = surchargeSetsDMCall();
    } else if (
      requestObj != null &&
      requestObj.RequestType == 'State Eligibility'
    ) {
      dealerCodeLookup(requestDataMap);
      response = stateSetsDMCall();
    } else if (
      requestObj != null &&
      requestObj.RequestType == 'Dealer Cost Breakout'
    ) {
      dealerCodeLookup(requestDataMap);
      response = dealerCostBreakoutRateSetsDMCall();
    }
    return response;
  }

  /**
   * queries dealer code lookup DM and populates responseMap
   */
  public static Void dealerCodeLookup(Map<String, String> requestDataMap) {
    List<CalculationMatrix> dealerLookupRec = new List<CalculationMatrix>(
      [
        SELECT
          Id,
          (
            SELECT Id
            FROM CalculationMatrixVersions
            WHERE IsEnabled = TRUE AND EndDateTime = NULL
            LIMIT 1
          )
        FROM CalculationMatrix
        WHERE UniqueName = 'Dealer_Code_Lookup'
      ]
    );

    for (CalculationMatrixRow row : [
      SELECT Id, Name, InputData, OutputData
      FROM CalculationMatrixRow
      WHERE
        CalculationMatrixVersionId = :dealerLookupRec[0]
          .CalculationMatrixVersions[0]
          .Id
    ]) {
      Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(
        row.OutputData
      );
      Map<String, String> columntoData = new Map<String, String>();
      System.debug(
        '@@@RateBuilderAPIHomeWarranty : Line no. 95: rowData Value: ' + rowData
      ); // 19-03-2026

      if (rowData != null && requestDataMap != null) {
        if (
          String.valueOf(rowData.get('Client')) ==
          requestDataMap.get('Client') &&
          String.valueOf(rowData.get('Product')) ==
          requestDataMap.get('Product') &&
          (requestDataMap.get('CoverageLevel') == null ||
          (requestDataMap.get('CoverageLevel') != null &&
          requestDataMap.get('CoverageLevel')
            .split(';')
            .contains(String.valueOf(rowData.get('CoverageLevel')))))
        ) {
          Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(
            row.InputData
          );

          if (requestDataMap.get('RequestType') == 'Dealer Cost Rates') {
            columntoData.put(
              'CoverageLevel',
              String.valueOf(rowData.get('CoverageLevel'))
            );
            columntoData.put('Product', String.valueOf(rowData.get('Product')));
            columntoData.put('Client', String.valueOf(rowData.get('Client')));
            columntoData.put('RateSet', String.valueOf(rowData.get('RateSet')));

            responseMap.put(
              String.valueOf(rowInputData.get('DealerProgramId')),
              columntoData
            );
          } else if (requestDataMap.get('RequestType') == 'Rate Options') {
            columntoData.put(
              'CoverageLevel',
              String.valueOf(rowData.get('CoverageLevel'))
            );
            columntoData.put(
              'OptionSets',
              String.valueOf(rowData.get('OptionSets'))
            );

            System.debug(
              '@@@RateBuilderAPIHomeWarranty: Line no. 114: rowData[Coveragelevel] Value: ' +
              rowData.get('CoverageLevel')
            ); //19-03-2026
            System.debug(
              '@@@RateBuilderAPIHomeWarranty: Line no. 115: rowData[optionSets] Value: ' +
              rowData.get('optionSets')
            ); //19-03-2026

            responseMap.put(
              String.valueOf(rowInputData.get('DealerProgramId')),
              columntoData
            );
          } else if (requestDataMap.get('RequestType') == 'Rate Surcharges') {
            columntoData.put(
              'CoverageLevel',
              String.valueOf(rowData.get('CoverageLevel'))
            );
            columntoData.put(
              'SurchargeSets',
              String.valueOf(rowData.get('SurchargeSets'))
            );

            responseMap.put(
              String.valueOf(rowInputData.get('DealerProgramId')),
              columntoData
            );
          } else if (requestDataMap.get('RequestType') == 'State Eligibility') {
            columntoData.put(
              'StateSet',
              String.valueOf(rowData.get('StateSet'))
            );
            columntoData.put('Product', String.valueOf(rowData.get('Product')));
            columntoData.put('Client', String.valueOf(rowData.get('Client')));

            responseMap.put(
              String.valueOf(rowInputData.get('DealerProgramId')),
              columntoData
            );
          } else if (
            requestDataMap.get('RequestType') == 'Dealer Cost Breakout'
          ) {
            columntoData.put(
              'CoverageLevel',
              String.valueOf(rowData.get('CoverageLevel'))
            );
            columntoData.put('RateSet', String.valueOf(rowData.get('RateSet')));
            columntoData.put('Client', String.valueOf(rowData.get('Client')));
            columntoData.put('Product', String.valueOf(rowData.get('Product')));

            responseMap.put(
              String.valueOf(rowInputData.get('DealerProgramId')),
              columntoData
            );
          } else if (
            requestDataMap.get('RequestType') == 'Squish VIN Class Guide'
          ) {
            columntoData.put(
              'ClassGuide',
              String.valueOf(rowData.get('ClassGuide'))
            );

            responseMap.put(
              String.valueOf(rowInputData.get('DealerProgramId')),
              columntoData
            );
          }
        }
      }
    }
  }

  /**
   * queries metadata records and returns a list of matched records dynamically
   */
  public static List<DecisionMatrixMapping__mdt> fetchMetadatabyTableName(
    String tableName,
    String coverageLevel
  ) {
    List<DecisionMatrixMapping__mdt> objList = new List<DecisionMatrixMapping__mdt>();

    for (
      DecisionMatrixMapping__mdt metadataObj : DecisionMatrixMapping__mdt.getAll()
        .values()
    ) {
      if (metadataObj.Table_Name__c == tableName) {
        // If coverage level is empty, match records where coverage level is null
        if (
          String.isEmpty(coverageLevel) && metadataObj.Coverage_Level__c == null
        ) {
          objList.add(metadataObj);
        }
        // If coverage level is provided, match exactly
        else if (
          !String.isEmpty(coverageLevel) &&
          metadataObj.Coverage_Level__c == coverageLevel
        ) {
          objList.add(metadataObj);
        }
      }
    }
    return objList;
  }

  /**
   * queries rate set DM records and returns concated response
   */
  public static String rateSetsDMCall() {
    // New Requirment Added on 17-03-26 for ticket Rate Builder: Report Request Outputs Based on Effective Date

    Date effectiveDate = Date.today();

    if (
      requestDataMap.containsKey('EffectiveDate') &&
      requestDataMap.get('EffectiveDate') != null
    ) {
      effectiveDate = Date.valueOf(requestDataMap.get('EffectiveDate'));
    }

    String effDateStr = String.valueOf(effectiveDate);
    Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
    Set<String> uniqueValues = new Set<String>();
    Map<String, List<Allocation_Code__c>> allocationCodesMap = new Map<String, List<Allocation_Code__c>>();
    Map<String, String> valueMap;
    Map<String, String> dealerCodesMap = new Map<String, String>();
    if (!responseMap.isEmpty()) {
      for (String key : responseMap.keySet()) {
        valueMap = responseMap.get(key);
        for (String rateSet : valueMap.keySet()) {
          String client = valueMap.get('Client');
          String product = valueMap.get('Product');
          String coverageLevel = valueMap.get('CoverageLevel');

          // Fetch dynamic list of metadata records
          for (
            DecisionMatrixMapping__mdt mdt : fetchMetadatabyTableName(
              valueMap.get('RateSet'),
              valueMap.get('CoverageLevel')
            )
          ) {
            String matrixName = mdt.Decision_Matrix_Name__c;
            uniqueValues.add(matrixName);
            dealerCodeDetailsMap.put(
              valueMap.get('CoverageLevel') + matrixName,
              key
            );
          }

          String uniqueKey =
    valueMap.get('Client') + '#' +
    valueMap.get('Product') + '#' +
    valueMap.get('CoverageLevel');
          dealerCodesMap.put(key, uniqueKey);
        }
      }
    }
    String state =
      '\'' +
      String.escapeSingleQuotes(requestDataMap.get('State')) +
      '\'';
    if (!state.contains('Include All')) {
      state += ',\'' + 'Include All' + '\'';
    }
    String insCarrier =
      '\'' +
      String.escapeSingleQuotes(requestDataMap.get('InsuranceCarrier')) +
      '\'';
    if (!insCarrier.contains('Include All')) {
      insCarrier += ',\'' + 'Include All' + '\'';
    }
    String query =
      'SELECT Name, Client__r.Name, Coverage_Level__c, Descriptor__c, Allocation_Amount__c, Product__c, Option__c, Term_Months__c ' +
      'FROM Allocation_Code__c ' +
      'WHERE Client__r.Name = \'' +
      String.escapeSingleQuotes(valueMap.get('Client')) +
      '\' ' +
      'AND Coverage_Level__c = \'' +
      String.escapeSingleQuotes(valueMap.get('CoverageLevel')) +
      '\' ' +
      'AND Product__c = \'' +
      String.escapeSingleQuotes(valueMap.get('Product')) +
      '\' ' +
      'AND States__c INCLUDES (' +
      state +
      ') ' +
      'AND Insurance_Carrier__c INCLUDES (' +
      insCarrier +
      ') ' +
      'AND Descriptor__c != \'Reserve\' ' +
      'AND Start_Date__c <= :effectiveDate ' +
      'AND (End_Date__c = NULL OR End_Date__c >= :effectiveDate) ' +
      'AND Descriptor__c <> NULL';

    // AND Start_Date__c <= ' + effDateStr + '
    //AND (End_Date__c = NULL OR End_Date__c >= ' + effDateStr + ') /// New Requirment Added on 17-03-26 for ticket Rate Builder: Report Request Outputs Based on Effective Date
    for (Allocation_Code__c allocCode : Database.query(query)) {
      String key =
        allocCode.Client__r.Name +
        '#' +
        allocCode.Product__c +
        '#' +
        allocCode.Coverage_Level__c;
      if (allocationCodesMap.containsKey(key.toUpperCase())) {
        allocationCodesMap.get(key.toUpperCase()).add(allocCode);
      } else {
        allocationCodesMap.put(
          key.toUpperCase(),
          new List<Allocation_Code__c>{ allocCode }
        );
      }
    }
    String concatedString = '';
    List<String> concatedStringList = new List<String>();
    Map<String, String> versionIdtoMatrixName = new Map<String, String>();
    if (!dealerCodeDetailsMap.isEmpty()) {
      // ✅ NEW BLOCK HERE
      List<CalculationMatrix> matrices = [
        SELECT
          Id,
          UniqueName,
          (
            SELECT Id, StartDateTime, EndDateTime
            FROM CalculationMatrixVersions
            WHERE IsEnabled = TRUE
            ORDER BY StartDateTime DESC
          )
        FROM CalculationMatrix
        WHERE UniqueName IN :uniqueValues
      ];

      for (CalculationMatrix matrixRecord : matrices) {
        if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
          continue;
        }

        Datetime effDT = Datetime.newInstance(
          effectiveDate.year(),
          effectiveDate.month(),
          effectiveDate.day()
        );

        for (
          CalculationMatrixVersion ver : matrixRecord.CalculationMatrixVersions
        ) {
          if (
            ver.StartDateTime <= effDT &&
            (ver.EndDateTime == null ||
            ver.EndDateTime >= effDT)
          ) {
            versionIdtoMatrixName.put(ver.Id, matrixRecord.UniqueName);

            break;
          }
        }
      }
      // existing code continues
      if (!versionIdtoMatrixName.isEmpty()) {
        Set<String> versionIds = versionIdtoMatrixName.keySet();
        List<sObject> sObjectRows = (List<sObject>) Database.query(
          'SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds'
        );
        List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
        String minUnit,
          maxUnit,
          residenceType,
          dealerProgId,
          rateSet,
          coverageName,
          termMonths,
          MinSquareFoot,
          MaxSquareFoot,
          minAge,
          maxAge,
          rateCost,
          deductible,
          rateCode;
        for (CalculationMatrixRow matrixRecord : rows) {
          Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(
            matrixRecord.OutputData
          );
          Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(
            matrixRecord.InputData
          );
          if (rowData != null && rowInputData != null) {
            dealerProgId = dealerCodeDetailsMap.get(
              String.valueOf(rowInputData.get('CoverageName')) +
              versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId)
            );
            if (dealerProgId == null || !responseMap.containsKey(dealerProgId)) {
    continue;
}

rateSet = responseMap.get(dealerProgId).get('RateSet');
            coverageName = String.valueOf(rowInputData?.get('CoverageName'));
            termMonths = String.valueOf(rowInputData?.get('TermMonths'));
            MinSquareFoot = String.valueOf(rowInputData?.get('MinSquareFoot'));
            MaxSquareFoot = String.valueOf(rowData?.get('MaxSquareFoot'));
            minAge = String.valueOf(rowInputData?.get('MinAge'));
            maxAge = String.valueOf(rowData?.get('MaxAge'));
            minUnit = String.valueOf(rowInputData?.get('MinUnit'));
            maxUnit = String.valueOf(rowData?.get('MaxUnit'));
            rateCost = String.valueOf(rowData?.get('BaseReserve'));
            deductible = String.valueOf(rowInputData?.get('Deductible'));
            residenceType = String.valueOf(rowInputData?.get('ResidenceType'));
            rateCode = String.valueOf(rowData?.get('RateCode'));

            Double allocationAmountperDealerRec = 0.00;
            if (dealerCodesMap.containsKey(dealerProgId)) {
              String mapKey = dealerCodesMap.get(dealerProgId).toUpperCase();
              if (allocationCodesMap.containsKey(mapKey)) {
                for (Allocation_Code__c ac : allocationCodesMap.get(mapKey)) {
                  if (
                    ac.Term_Months__c != null &&
                    ac.Term_Months__c.equalsIgnoreCase('Include All') ||
                    termMonths == ac.Term_Months__c
                  ) {
                    if (
                      Pattern.matches(
                        '\\d+(\\.\\d+)?',
                        ac.Allocation_Amount__c
                      ) || ac.Allocation_Amount__c.isNumeric()
                    ) {
                      if (
                        Double.valueOf(ac.Allocation_Amount__c) > 0 &&
                        ac.Option__c.equalsIgnoreCase('Include All')
                      ) {
                        allocationAmountperDealerRec += Double.valueOf(
                          ac.Allocation_Amount__c
                        );
                      }
                    } else {
                      if (ac.Descriptor__c == 'Premium Tax') {
                        allocationAmountperDealerRec += Double.valueOf(
                          rowData?.get('PremiumTax')
                        );
                      }
                      if (ac.Descriptor__c == 'Seller Commission') {
                        allocationAmountperDealerRec += Double.valueOf(
                          rowData?.get('Commission')
                        );
                      }
                      // === START OF NEW ADDITION: Obligor Tax Allocation ===
                      if (ac.Descriptor__c == 'Obligor Tax') {
                        allocationAmountperDealerRec += Double.valueOf(
                          rowData?.get('ObligorTax')
                        );
                      }
                      // === END OF NEW ADDITION ===
                    }
                  }
                }
              }
              mapKey = '';
            }
            Double totalRateCost =
              Double.valueOf(rateCost) + allocationAmountperDealerRec;
            concatedString =
              dealerProgId +
              '#' +
              coverageName +
              '#' +
              rateSet +
              '#' +
              termMonths +
              '#' +
              MinSquareFoot +
              '#' +
              MaxSquareFoot +
              '#' +
              minAge +
              '#' +
              maxAge +
              '#' +
              minUnit +
              '#' +
              maxUnit +
              '#' +
              totalRateCost +
              '#' +
              deductible +
              '#' +
              residenceType +
              '#' +
              rateCode;
            concatedStringList.add(concatedString);
          }
        }
      }
    }

    return String.join(concatedStringList, ',');
  }

  /**
   * queries rate set DM records and returns concated response
   */
  public static String dealerCostBreakoutRateSetsDMCall() {
    // New Requirment Added on 17-03-26 for ticket Rate Builder: Report Request Outputs Based on Effective Date

    Date effectiveDate = Date.today();

    if (
      requestDataMap.containsKey('EffectiveDate') &&
      requestDataMap.get('EffectiveDate') != null
    ) {
      effectiveDate = Date.valueOf(requestDataMap.get('EffectiveDate'));
    }

    String effDateStr = String.valueOf(effectiveDate);
    Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
    Set<String> uniqueValues = new Set<String>();
    Map<String, List<Allocation_Code__c>> allocationCodesMap = new Map<String, List<Allocation_Code__c>>();
    Map<String, String> dealerCodesMap = new Map<String, String>();
    Boolean isPremiumTax = false;
    Double premiumTaxValue = 0.00;
    if (!responseMap.isEmpty()) {
      Set<String> clientSet = new Set<String>();
Set<String> productSet = new Set<String>();
Set<String> coverageSet = new Set<String>();

for (String key : responseMap.keySet()) {

    Map<String, String> valueMap = responseMap.get(key);
    if (valueMap == null) continue;

    clientSet.add(valueMap.get('Client'));
    productSet.add(valueMap.get('Product'));
    coverageSet.add(valueMap.get('CoverageLevel'));

        // Fetch dynamic list of metadata records
        for (
          DecisionMatrixMapping__mdt mdt : fetchMetadatabyTableName(
            valueMap.get('RateSet'),
            valueMap.get('CoverageLevel')
          )
        ) {
          String matrixName = mdt.Decision_Matrix_Name__c;
          uniqueValues.add(matrixName);
          dealerCodeDetailsMap.put(
    valueMap.get('CoverageLevel').trim().toUpperCase() + '#' +
    matrixName.trim().toUpperCase(),
    key
);
        }

        String uniqueKey =
    valueMap.get('Client') + '#' +
    valueMap.get('Product') + '#' +
    valueMap.get('CoverageLevel');
        dealerCodesMap.put(key, uniqueKey);
      }
      String state =
        '\'' +
        String.escapeSingleQuotes(requestDataMap.get('State')) +
        '\'';
      if (!state.contains('Include All')) {
        state += ',\'' + 'Include All' + '\'';
      }
      String insCarrier =
        '\'' +
        String.escapeSingleQuotes(requestDataMap.get('InsuranceCarrier')) +
        '\'';
      if (!insCarrier.contains('Include All')) {
        insCarrier += ',\'' + 'Include All' + '\'';
      }
      String query =
    'SELECT Name, Client__r.Name, Coverage_Level__c, Descriptor__c, Allocation_Amount__c, Product__c, Option__c, Term_Months__c ' +
    'FROM Allocation_Code__c ' +
    'WHERE Client__r.Name IN :clientSet ' +   // <-- space added
    'AND Coverage_Level__c IN :coverageSet ' +
    'AND Product__c IN :productSet ' +
        'AND States__c INCLUDES (' +
        state +
        ') ' +
        'AND Insurance_Carrier__c INCLUDES (' +
        insCarrier +
        ') ' +
        'AND Descriptor__c != \'Reserve\' ' +
        'AND Start_Date__c <= :effectiveDate ' +
        'AND (End_Date__c = NULL OR End_Date__c >= :effectiveDate) ' +
        'AND Descriptor__c <> NULL';
      // New Requirment Added on 17-03-26 for ticket Rate Builder: Report Request Outputs Based on Effective Date

      for (Allocation_Code__c allocCode : Database.query(query)) {
        String key =
          allocCode.Client__r.Name +
          '#' +
          allocCode.Product__c +
          '#' +
          allocCode.Coverage_Level__c;
        if (allocationCodesMap.containsKey(key.toUpperCase())) {
          allocationCodesMap.get(key.toUpperCase()).add(allocCode);
        } else {
          allocationCodesMap.put(
            key.toUpperCase(),
            new List<Allocation_Code__c>{ allocCode }
          );
        }
      }
    }
    String concatedString = '';
    List<String> concatedStringList = new List<String>();
    Map<String, String> versionIdtoMatrixName = new Map<String, String>();
    if (!dealerCodeDetailsMap.isEmpty()) {
List<CalculationMatrix> matrices = [
    SELECT Id, UniqueName,
        (
            SELECT Id, StartDateTime, EndDateTime
            FROM CalculationMatrixVersions
            WHERE IsEnabled = TRUE
            ORDER BY StartDateTime DESC
        )
    FROM CalculationMatrix
    WHERE UniqueName IN :uniqueValues
];

for (CalculationMatrix matrixRecord : matrices) {

    if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
        continue;
    }

    Datetime effDT = Datetime.newInstance(
        effectiveDate.year(),
        effectiveDate.month(),
        effectiveDate.day()
    );

    for (CalculationMatrixVersion ver :
         matrixRecord.CalculationMatrixVersions) {

        if (
            ver.StartDateTime <= effDT &&
            (ver.EndDateTime == null ||
             ver.EndDateTime >= effDT)
        ) {

            versionIdtoMatrixName.put(
                ver.Id,
                matrixRecord.UniqueName
            );

            break;
        }
    }
}
      uniqueValues.clear();
      if (!versionIdtoMatrixName.isEmpty()) {
        Set<String> versionIds = versionIdtoMatrixName.keySet();
        if (isCountRequired) {
          String rowCount = String.valueOf(
            Database.countQuery(
              'SELECT count() FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds'
            )
          );

          return rowCount;
        }
        List<sObject> sObjectRows = (List<sObject>) Database.query(
          'SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds LIMIT 200 OFFSET ' +
          offSet
        );
        List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
        String minUnit = '',
          maxUnit = '',
          residenceType = '',
          minSquareFoot = '',
          maxSquareFoot = '',
          dealerProgId = '',
          rateSet = '',
          coverageName = '',
          termMonths = '',
          minMiles = '',
          maxMiles = '',
          minAge = '',
          maxAge = '',
          rateClass = '',
          reserveRateCost = '',
          deductible = '',
          rateCode = '';
        for (CalculationMatrixRow matrixRecord : rows) {
          Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(
            matrixRecord.OutputData
          );
          Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(
            matrixRecord.InputData
          );
          String allocationCodeString = '';
          if (rowData != null && rowInputData != null) {
            String coverageKey =
    String.valueOf(rowInputData.get('CoverageName')).trim().toUpperCase();

String matrixKey =
    versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId)
        .trim().toUpperCase();

dealerProgId = dealerCodeDetailsMap.get(
    coverageKey + '#' + matrixKey
);
if (dealerProgId == null || !responseMap.containsKey(dealerProgId)) {
    continue;
}
            rateSet = responseMap.get(dealerProgId).get('RateSet');
            coverageName = String.valueOf(rowInputData?.get('CoverageName'));
            termMonths = String.valueOf(rowInputData?.get('TermMonths'));
            minSquareFoot = String.valueOf(rowInputData?.get('MinSquareFoot'));
            maxSquareFoot = String.valueOf(rowData?.get('MaxSquareFoot'));
            minAge = String.valueOf(rowInputData?.get('MinAge'));
            maxAge = String.valueOf(rowData?.get('MaxAge'));
            minUnit = String.valueOf(rowInputData?.get('MinUnit'));
            maxUnit = String.valueOf(rowData?.get('MaxUnit'));
            rateClass = String.valueOf(rowInputData?.get('RateClass')) != null
              ? String.valueOf(rowInputData?.get('RateClass'))
              : '';
            deductible = String.valueOf(rowInputData?.get('Deductible'));
            rateCode = String.valueOf(rowData?.get('RateCode'));
            reserveRateCost = String.valueOf(rowData?.get('BaseReserve'));
            residenceType = rowInputData.get('ResidenceType') != null
    ? String.valueOf(rowInputData.get('ResidenceType'))
    : String.valueOf(rowData.get('ResidenceType'));

            //rowInputData.clear();

            Double allocationAmountperDealerRec = 0.00;
            List<String> allocationDetails = new List<String>();
            String allocationDetailsStr = '';
            if (dealerCodesMap.containsKey(dealerProgId)) {
              String mapKey = dealerCodesMap.get(dealerProgId).toUpperCase();
              if (allocationCodesMap.containsKey(mapKey)) {
                for (Allocation_Code__c ac : allocationCodesMap.get(mapKey)) {
                  if (
                    ac.Term_Months__c != null &&
                    ac.Term_Months__c.equalsIgnoreCase('Include All') ||
                    termMonths == ac.Term_Months__c
                  ) {
                    if (
                      Pattern.matches(
                        '\\d+(\\.\\d+)?',
                        ac.Allocation_Amount__c
                      ) || ac.Allocation_Amount__c.isNumeric()
                    ) {
                      if (
                        Double.valueOf(ac.Allocation_Amount__c) > 0 &&
                        ac.Option__c.equalsIgnoreCase('Include All')
                      ) {
                        allocationDetails.add(
                          ac.Name +
                            ' = ' +
                            Double.valueOf(ac.Allocation_Amount__c)
                        );
                        allocationAmountperDealerRec += Double.valueOf(
                          ac.Allocation_Amount__c
                        );
                      } else {
                        allocationDetails.add(ac.Name + ' = ' + 0);
                      }
                    } else {
                      if (ac.Descriptor__c == 'Premium Tax') {
                        allocationDetails.add(
                          ac.Name +
                            ' = ' +
                            Double.valueOf(rowData?.get('PremiumTax'))
                        );
                        allocationAmountperDealerRec += Double.valueOf(
                          rowData?.get('PremiumTax')
                        );
                      }
                      if (ac.Descriptor__c == 'Seller Commission') {
                        allocationDetails.add(
                          ac.Name +
                            ' = ' +
                            Double.valueOf(rowData?.get('Commission'))
                        );
                        allocationAmountperDealerRec += Double.valueOf(
                          rowData?.get('Commission')
                        );
                      }
                      // === START OF NEW ADDITION: Obligor Tax Detail Allocation ===
                      if (ac.Descriptor__c == 'Obligor Tax') {
                        allocationDetails.add(
                          ac.Name +
                            ' = ' +
                            Double.valueOf(rowData?.get('ObligorTax'))
                        );
                        allocationAmountperDealerRec += Double.valueOf(
                          rowData?.get('ObligorTax')
                        );
                      }
                      // === END OF NEW ADDITION ===
                    }
                  }
                }
              }
              mapKey = '';
            }
            Double totalRateCost =
              Double.valueOf(reserveRateCost) + allocationAmountperDealerRec;
            allocationDetailsStr = String.join(allocationDetails, ';');
            concatedString =
              dealerProgId +
              '#' +
              coverageName +
              '#' +
              rateSet +
              '#' +
              termMonths +
              '#' +
              minSquareFoot +
              '#' +
              maxSquareFoot +
              '#' +
              minAge +
              '#' +
              maxAge +
              '#' +
              minUnit +
              '#' +
              maxUnit +
              '#' +
              rateClass +
              '#' +
              deductible +
              '#' +
              residenceType +
              '#' +
              rateCode +
              '#' +
              reserveRateCost +
              '#' +
              allocationDetailsStr +
              '#' +
              allocationAmountperDealerRec +
              '#' +
              totalRateCost;
            concatedStringList.add(concatedString);
          }
        }
        versionIds.clear();
        dealerCodeDetailsMap.clear();
        dealerCodesMap.clear();
        allocationCodesMap.clear();
        versionIdtoMatrixName.clear();
      }
    }
    return String.join(concatedStringList, ',');
  }

  /**
   * queries Options Set lookup DM and returns concated response
   */
  public static String optionSetsDMCall() {
    Date effectiveDate = Date.today();

    String effDate = requestDataMap.get('EffectiveDate');

    if (!String.isBlank(effDate)) {
      effectiveDate = Date.valueOf(effDate);
    }

    Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
    Set<String> uniqueValues = new Set<String>();

    if (!responseMap.isEmpty()) {
      for (String key : responseMap.keySet()) {
        Map<String, String> valueMap = responseMap.get(key);

        for (String rateSet : valueMap.keySet()) {
          for (
            DecisionMatrixMapping__mdt mdt : fetchMetadatabyTableName(
              valueMap.get('OptionSets'),
              valueMap.get('CoverageLevel')
            )
          ) {
            String matrixName = mdt.Decision_Matrix_Name__c;

            uniqueValues.add(matrixName);

            dealerCodeDetailsMap.put(
              valueMap.get('CoverageLevel') + matrixName,
              key
            );
          }
        }
      }
    }

    List<String> responseToPentaho = new List<String>();
    String concatedString = '';

    Map<String, String> versionIdtoMatrixName = new Map<String, String>();

    // FIX START — dynamic version selection

    System.debug('@@@ DEBUG:: dealerCodeDetailsMap: ' + dealerCodeDetailsMap);
    System.debug('@@@ DEBUG:: uniqueValues: ' + uniqueValues);

    if (!dealerCodeDetailsMap.isEmpty()) {
      List<CalculationMatrix> matrices = [
        SELECT
          Id,
          UniqueName,
          (
            SELECT Id, StartDateTime, EndDateTime
            FROM CalculationMatrixVersions
            WHERE IsEnabled = TRUE
            ORDER BY StartDateTime DESC
          )
        FROM CalculationMatrix
        WHERE UniqueName IN :uniqueValues
      ];

      for (CalculationMatrix matrixRecord : matrices) {
        if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
          continue;
        }

        for (
          CalculationMatrixVersion ver : matrixRecord.CalculationMatrixVersions
        ) {
          Date startDate = ver.StartDateTime.dateGmt();
          Date endDate = ver.EndDateTime != null
            ? ver.EndDateTime.dateGmt()
            : null;

          if (
            startDate <= effectiveDate &&
            (endDate == null ||
            endDate >= effectiveDate)
          ) {
            versionIdtoMatrixName.put(ver.Id, matrixRecord.UniqueName);
            System.debug('@@@ DEBUG:: versionIdtoMatrixName: ' + matrixRecord.UniqueName);
            break;
          }
        }
      }

      // FIX END

      if (!versionIdtoMatrixName.isEmpty()) {
        Set<String> versionIds = versionIdtoMatrixName.keySet();

        List<sObject> sObjectRows = (List<sObject>) Database.query(
          'SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId ' +
            'FROM CalculationMatrixRow ' +
            'WHERE CalculationMatrixVersionId IN :versionIds'
        );

        List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);

        String minResidenceUnits,
          maxResidenceUnits,
          dealerProgId,
          optionSet,
          coverageName,
          minTermMonths,
          maxTermMonths,
          minResidenceSqFt,
          maxResidenceSqFt,
          minResidenceAge,
          maxResidenceAge,
          optionCost,
          autoApply,
          allowCheck,
          residenceTypeList;

        for (CalculationMatrixRow matrixRecord : rows) {
          Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(
            matrixRecord.OutputData
          );

          Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(
            matrixRecord.InputData
          );

          if (rowData != null && rowInputData != null) {
            dealerProgId = dealerCodeDetailsMap.get(
              String.valueOf(rowInputData.get('CoverageName')) +
              versionIdtoMatrixName.get(matrixRecord.CalculationMatrixVersionId)
            );

            optionSet = rowInputData.containsKey('OptionName')
              ? String.valueOf(rowInputData.get('OptionName'))
              : '';

            coverageName = rowInputData.containsKey('CoverageName')
              ? String.valueOf(rowInputData.get('CoverageName'))
              : '';

            minTermMonths = rowInputData.containsKey('MinTermMonths')
              ? String.valueOf(rowInputData.get('MinTermMonths'))
              : '';

            maxTermMonths = rowData.containsKey('MaxTermMonths')
              ? String.valueOf(rowData.get('MaxTermMonths'))
              : '';

            minResidenceSqFt = rowInputData.containsKey('MinResidenceSqFt')
              ? String.valueOf(rowInputData.get('MinResidenceSqFt'))
              : '';

            maxResidenceSqFt = rowData.containsKey('MaxResidenceSqFt')
              ? String.valueOf(rowData.get('MaxResidenceSqFt'))
              : '';

            minResidenceAge = rowInputData.containsKey('MinResidenceAge')
              ? String.valueOf(rowInputData.get('MinResidenceAge'))
              : '';

            maxResidenceAge = rowData.containsKey('MaxResidenceAge')
              ? String.valueOf(rowData.get('MaxResidenceAge'))
              : '';

            optionCost = rowData.containsKey('OptionCost')
              ? String.valueOf(rowData.get('OptionCost'))
              : '0';

            autoApply = rowData.containsKey('AutoApply')
              ? String.valueOf(rowData.get('AutoApply'))
              : 'FALSE';

            allowCheck = 'TRUE';

            if (rowData.containsKey('PremiumTax')) {
              optionCost = String.valueOf(
                Decimal.valueOf(optionCost) +
                (Decimal) rowData.get('PremiumTax')
              );
            }

            if (rowData.containsKey('ObligorTax')) {
              optionCost = String.valueOf(
                Decimal.valueOf(optionCost) +
                (Decimal) rowData.get('ObligorTax')
              );
            }

            if (rowData.containsKey('MaintenanceAdminFee')) {
              optionCost = String.valueOf(
                Decimal.valueOf(optionCost) +
                (Decimal) rowData.get('MaintenanceAdminFee')
              );
            }

            minResidenceUnits = '0';
            maxResidenceUnits = '999';
            residenceTypeList = '';

            concatedString +=
              dealerProgId +
              '#' +
              coverageName +
              '#' +
              optionSet +
              '#' +
              optionCost +
              '#' +
              minTermMonths +
              '#' +
              maxTermMonths +
              '#' +
              minResidenceSqFt +
              '#' +
              maxResidenceSqFt +
              '#' +
              minResidenceAge +
              '#' +
              maxResidenceAge +
              '#' +
              minResidenceUnits +
              '#' +
              maxResidenceUnits +
              '#' +
              autoApply +
              '#' +
              residenceTypeList +
              '#' +
              allowCheck +
              '#' +
              '' +
              '#' +
              '' +
              ',';
          }
        }
      }
    }

    return concatedString.removeEnd(',');
  }

  /**
   * queries Surchage Set lookup DM and returns concated response
   */
  public static String surchargeSetsDMCall() {
    Date effectiveDate = Date.today();

    String effDate = requestDataMap.get('EffectiveDate');

    if (!String.isBlank(effDate)) {
      effectiveDate = Date.valueOf(effDate);
    }
    Map<String, String> dealerCodeDetailsMap = new Map<String, String>();
    Set<String> uniqueValues = new Set<String>();
    if (!responseMap.isEmpty()) {
      for (String key : responseMap.keySet()) {
        Map<String, String> valueMap = responseMap.get(key);
        for (String rateSet : valueMap.keySet()) {
          // Fetch dynamic list of metadata records
          for (
            DecisionMatrixMapping__mdt mdt : fetchMetadatabyTableName(
              valueMap.get('SurchargeSets'),
              valueMap.get('CoverageLevel')
            )
          ) {
            String matrixName = mdt.Decision_Matrix_Name__c;
            uniqueValues.add(matrixName);
            dealerCodeDetailsMap.put(
              valueMap.get('CoverageLevel') + matrixName,
              key
            );
          }
        }
      }
    }

    List<String> responseToPentaho = new List<String>();
    String concatedString = '';
    Map<String, String> versionIdtoMatrixName = new Map<String, String>();
    if (!dealerCodeDetailsMap.isEmpty()) {
      List<CalculationMatrix> matrices = [
  SELECT
    Id,
    UniqueName,
    (
      SELECT Id, StartDateTime, EndDateTime
      FROM CalculationMatrixVersions
      WHERE IsEnabled = TRUE
      ORDER BY StartDateTime DESC
    )
  FROM CalculationMatrix
  WHERE UniqueName IN :uniqueValues
];

for (CalculationMatrix matrixRecord : matrices) {

  if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
    continue;
  }

  Datetime effDT = Datetime.newInstance(
    effectiveDate.year(),
    effectiveDate.month(),
    effectiveDate.day()
  );

  for (CalculationMatrixVersion ver :
       matrixRecord.CalculationMatrixVersions) {

    if (
      ver.StartDateTime <= effDT &&
      (ver.EndDateTime == null ||
       ver.EndDateTime >= effDT)
    ) {

      versionIdtoMatrixName.put(
        ver.Id,
        matrixRecord.UniqueName
      );

      break;
    }
  }
}
      if (!versionIdtoMatrixName.isEmpty()) {
        Set<String> versionIds = versionIdtoMatrixName.keySet();
        List<sObject> sObjectRows = (List<sObject>) Database.query(
          'SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds'
        );
        List<CalculationMatrixRow> rows = (List<CalculationMatrixRow>) (sObjectRows);
        String dealerProgId,
          coverageName,
          surchargeSet,
          surchargeCost,
          minTermMonths,
          maxTermMonths,
          minResidenceSqFt,
          maxResidenceSqFt,
          minResidenceAge,
          maxResidenceAge,
          minResidenceUnits,
          maxResidenceUnits;
        if (rows != null && !rows.isEmpty()) {
          for (CalculationMatrixRow matrixRecord : rows) {
            Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(
              matrixRecord.OutputData
            );
            Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(
              matrixRecord.InputData
            );
            if (rowData != null && rowInputData != null) {
              dealerProgId = dealerCodeDetailsMap.get(
                String.valueOf(rowInputData.get('CoverageName')) +
                versionIdtoMatrixName.get(
                  matrixRecord.CalculationMatrixVersionId
                )
              );
              coverageName = rowInputData.containsKey('CoverageName')
                ? String.valueOf(rowInputData.get('CoverageName'))
                : '';
              surchargeSet = rowInputData.containsKey('SurchargeName')
                ? String.valueOf(rowInputData.get('SurchargeName'))
                : '';
              surchargeCost = rowData.containsKey('SurchargeCost')
                ? String.valueOf(rowData.get('SurchargeCost'))
                : '';
              minTermMonths = rowInputData.containsKey('MinTermMonths')
                ? String.valueOf(rowInputData.get('MinTermMonths'))
                : '';
              maxTermMonths = rowData.containsKey('MaxTermMonths')
                ? String.valueOf(rowData.get('MaxTermMonths'))
                : '';
              minResidenceSqFt = rowInputData.containsKey('MinResidenceSqFt')
                ? String.valueOf(rowInputData.get('MinResidenceSqFt'))
                : '';
              maxResidenceSqFt = rowData.containsKey('MaxResidenceSqFt')
                ? String.valueOf(rowData.get('MaxResidenceSqFt'))
                : '';
              minResidenceAge = rowInputData.containsKey('MinResidenceAge')
                ? String.valueOf(rowInputData.get('MinResidenceAge'))
                : '';
              maxResidenceAge = rowData.containsKey('MaxResidenceAge')
                ? String.valueOf(rowData.get('MaxResidenceAge'))
                : '';

              minResidenceUnits = rowInputData.containsKey('MinResidenceUnits')
                ? String.valueOf(rowInputData.get('MinResidenceUnits'))
                : '';
              maxResidenceUnits = rowData.containsKey('MaxResidenceUnits')
                ? String.valueOf(rowData.get('MaxResidenceUnits'))
                : '';

              if (rowData.containsKey('PremiumTax')) {
                surchargeCost = String.valueOf(
                  Decimal.valueOf(surchargeCost) +
                  (Decimal) rowData.get('PremiumTax')
                );
              }

              concatedString +=
                dealerProgId +
                '#' +
                coverageName +
                '#' +
                surchargeSet +
                '#' +
                surchargeCost +
                '#' +
                minTermMonths +
                '#' +
                maxTermMonths +
                '#' +
                minResidenceSqFt +
                '#' +
                maxResidenceSqFt +
                '#' +
                minResidenceAge +
                '#' +
                maxResidenceAge +
                '#' +
                minResidenceUnits +
                '#' +
                maxResidenceUnits +
                '#' +
                '';
            }
          }
        }
      }
    }
    return concatedString.removeEnd(',');
  }

  /**
   * queries State Set lookup DM and returns concated response
   */
  public static String stateSetsDMCall() {
    Date effectiveDate = Date.today();

    String effDate = requestDataMap.get('EffectiveDate');

    if (!String.isBlank(effDate)) {
      effectiveDate = Date.valueOf(effDate);
    }
List<CalculationMatrix> state_Set_GuideRec = [
  SELECT Id,
    (
      SELECT Id, StartDateTime, EndDateTime
      FROM CalculationMatrixVersions
      WHERE IsEnabled = TRUE
      ORDER BY StartDateTime DESC
    )
  FROM CalculationMatrix
  WHERE UniqueName = 'State_Set_Guide'
];

CalculationMatrixVersion selectedStateGuideVersion;

if (!state_Set_GuideRec.isEmpty()) {

  Datetime effDT = Datetime.newInstance(
    effectiveDate.year(),
    effectiveDate.month(),
    effectiveDate.day()
  );

  for (CalculationMatrixVersion ver :
       state_Set_GuideRec[0].CalculationMatrixVersions) {

    if (
      ver.StartDateTime <= effDT &&
      (ver.EndDateTime == null ||
       ver.EndDateTime >= effDT)
    ) {
      selectedStateGuideVersion = ver;
      break;
    }
  }
}
    Set<String> stateSetDMName = new Set<String>();
    String concatedString = '';
    Map<String, String> versionIdtoMatrixName = new Map<String, String>();
    // Instantiate HTTP request and response objects
    String responseBody = '';

    if (
      !state_Set_GuideRec.isEmpty() &&
      !state_Set_GuideRec[0].CalculationMatrixVersions.isEmpty()
    ) {
      responseBody = ContractUtility.fetchLookupTableRows(
        state_Set_GuideRec[0].Id,
        selectedStateGuideVersion.Id
      );
    } else {
      return ''; // or handle gracefully
    }
    Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );
    List<Object> rows = (List<Object>) jsonMap.get('rows');
    if (rows != null && !rows.isEmpty()) {
      Map<String, String> rowDataFieldsMap = new Map<String, String>();
      for (String key : responseMap.keySet()) {
        Map<String, String> valueMap = responseMap.get(key);
        for (Object data : rows) {
          Map<String, Object> row = (Map<String, Object>) data;
          Map<String, Object> rowData = (Map<String, Object>) row.get(
            'rowData'
          );
          //creates a key value mapping that will be used to populate responseMap
          if (
            String.valueOf(rowData.get('Client')) == valueMap.get('Client') &&
            String.valueOf(rowData.get('Product')) == valueMap.get('Product')
          ) {
            // Fetch dynamic list of metadata records
            for (
              DecisionMatrixMapping__mdt mdt : fetchMetadatabyTableName(
                String.valueOf(rowData.get('StateSet')),
                ''
              )
            ) {
              stateSetDMName.add(mdt.Decision_Matrix_Name__c);
            }
          }
        }
      }
      //queries state set DMs for each dealer code lookup record
      if (!stateSetDMName.isEmpty()) {

  List<CalculationMatrix> matrices = [
    SELECT Id, UniqueName,
      (
        SELECT Id, StartDateTime, EndDateTime
        FROM CalculationMatrixVersions
        WHERE IsEnabled = TRUE
        ORDER BY StartDateTime DESC
      )
    FROM CalculationMatrix
    WHERE UniqueName IN :stateSetDMName
  ];

  for (CalculationMatrix matrixRecord : matrices) {

    if (matrixRecord.CalculationMatrixVersions.isEmpty()) {
      continue;
    }

    Datetime effDT = Datetime.newInstance(
      effectiveDate.year(),
      effectiveDate.month(),
      effectiveDate.day()
    );

    for (CalculationMatrixVersion ver :
         matrixRecord.CalculationMatrixVersions) {

      if (
        ver.StartDateTime <= effDT &&
        (ver.EndDateTime == null ||
         ver.EndDateTime >= effDT)
      ) {

        versionIdtoMatrixName.put(
          ver.Id,
          matrixRecord.UniqueName
        );

        break;
      }
    }
  }
        if (!versionIdtoMatrixName.isEmpty()) {
          // Instantiate HTTP request and response objects
          Set<String> versionIds = versionIdtoMatrixName.keySet();
          List<sObject> sObjectRows = (List<sObject>) Database.query(
            'SELECT Id, Name, InputData, OutputData, CalculationMatrixVersionId FROM CalculationMatrixRow where CalculationMatrixVersionId IN :versionIds'
          );
          List<CalculationMatrixRow> matrixRows = (List<CalculationMatrixRow>) (sObjectRows);
          if (matrixRows != null && !matrixRows.isEmpty()) {
            String stateProvince,
              stateProvName,
              insCarrier,
              obligor,
              adminCompany,
              typeOfInsurance;
            for (CalculationMatrixRow matrixRecord : matrixRows) {
              Map<String, Object> rowData = (Map<String, Object>) JSON.deserializeUntyped(
                matrixRecord.OutputData
              );
              Map<String, Object> rowInputData = (Map<String, Object>) JSON.deserializeUntyped(
                matrixRecord.InputData
              );
              if (rowData != null && rowInputData != null) {
                stateProvince = rowInputData.containsKey('State')
                  ? String.valueOf(rowInputData.get('State'))
                  : '';
                stateProvName = getStateFullName(stateProvince);
                insCarrier = rowData.containsKey('Carrier')
                  ? String.valueOf(rowData.get('Carrier'))
                  : '';
                obligor = rowData.containsKey('Obligor')
                  ? String.valueOf(rowData.get('Obligor'))
                  : '';
                adminCompany = rowData.containsKey('Admin')
                  ? String.valueOf(rowData.get('Admin'))
                  : '';
                typeOfInsurance = rowData.containsKey('InsuranceType')
                  ? String.valueOf(rowData.get('InsuranceType'))
                  : '';
                concatedString +=
                  'United States' +
                  '#' +
                  stateProvince +
                  '#' +
                  stateProvName +
                  '#' +
                  insCarrier +
                  '#' +
                  obligor +
                  '#' +
                  adminCompany +
                  '#' +
                  typeOfInsurance +
                  ',';
              }
            }
          }
        }
      }
    }
    return concatedString.removeEnd(',');
  }

  /**
   * returns full US state name from abbreviated name
   */
  public static String getStateFullName(String shortName) {
    Map<String, String> stateMap = new Map<String, String>();
    stateMap.put('AL', 'Alabama');
    stateMap.put('AK', 'Alaska');
    stateMap.put('AR', 'Arkansas');
    stateMap.put('AZ', 'Arizona');
    stateMap.put('CA', 'California');
    stateMap.put('CO', 'Colorado');
    stateMap.put('CT', 'Connecticut');
    stateMap.put('DE', 'Delaware');
    stateMap.put('DC', 'District of Columbia');
    stateMap.put('FL', 'Florida');
    stateMap.put('GA', 'Georgia');
    stateMap.put('HI', 'Hawaii');
    stateMap.put('ID', 'Idaho');
    stateMap.put('IL', 'Illinois');
    stateMap.put('IN', 'Indiana');
    stateMap.put('IA', 'Iowa');
    stateMap.put('KS', 'Kansas');
    stateMap.put('KY', 'Kentucky');
    stateMap.put('LA', 'Louisiana');
    stateMap.put('ME', 'Maine');
    stateMap.put('MD', 'Maryland');
    stateMap.put('MA', 'Massachusetts');
    stateMap.put('MI', 'Michigan');
    stateMap.put('MN', 'Minnesota');
    stateMap.put('MS', 'Mississippi');
    stateMap.put('MO', 'Missouri');
    stateMap.put('MT', 'Montana');
    stateMap.put('NE', 'Nebraska');
    stateMap.put('NV', 'Nevada');
    stateMap.put('NH', 'New Hampshire');
    stateMap.put('NJ', 'New Jersey');
    stateMap.put('NM', 'New Mexico');
    stateMap.put('NY', 'New York');
    stateMap.put('NC', 'North Carolina');
    stateMap.put('ND', 'North Dakota');
    stateMap.put('OH', 'Ohio');
    stateMap.put('OK', 'Oklahoma');
    stateMap.put('OR', 'Oregon');
    stateMap.put('PA', 'Pennsylvania');
    stateMap.put('RI', 'Rhode Island');
    stateMap.put('SC', 'South Carolina');
    stateMap.put('SD', 'South Dakota');
    stateMap.put('TN', 'Tennessee');
    stateMap.put('TX', 'Texas');
    stateMap.put('UT', 'Utah');
    stateMap.put('VT', 'Vermont');
    stateMap.put('VA', 'Virginia');
    stateMap.put('WA', 'Washington');
    stateMap.put('WV', 'West Virginia');
    stateMap.put('WI', 'Wisconsin');
    stateMap.put('WY', 'Wyoming');

    return stateMap.containsKey(shortName) ? stateMap.get(shortName) : '';
  }

  //class that parses request body
  public class RateRequest {
    public String Client;
    public String Product;
    public String CoverageLevel;
    public String RequestType;
    public String State;
    public String InsuranceCarrier;
    public Date EffectiveDate; // New Requirment Added on 17-03-26 for ticket Rate Builder: Report Request Outputs Based on Effective Date
  }

  //class that generates error response
  public class ErrorResponseGenerator {
    public Integer status;
    public String error;
    public ErrorPayload payload;
  }

  //part of error response
  public class ErrorPayload {
    public String Client;
    public String Product;
    public String CoverageLevel;
    public String RequestType;
    public String State;
    public String InsuranceCarrier;
  }
}