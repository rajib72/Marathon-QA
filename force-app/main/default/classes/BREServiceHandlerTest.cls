@IsTest
private class BREServiceHandlerTest {

    private static final String TEST_ACCOUNT_NUMBER = 'WUS';
    private static final String TEST_COVERAGE_NAME = 'EZ Elite - FL';

    @TestSetup
    static void setupReferenceData() {
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;

        Account testAccount = TestDataFactory.createAccount(false);
        testAccount.AccountNumber = TEST_ACCOUNT_NUMBER;
        testAccount.FirstName = 'Spanish';
        testAccount.LastName = 'Service Center';
        testAccount.BillingStreet = '123 BRE Test Street';
        testAccount.BillingCity = 'Columbus';
        testAccount.BillingState = 'FL';
        testAccount.BillingPostalCode = '43004';
        testAccount.Phone = '6145551234';
        Database.insert(testAccount, dmlOptions);

        insert new Coverage_Level__c(
            Name = TEST_COVERAGE_NAME
        );
    }

    private static Account getTestAccount() {
        return [
            SELECT Id,
                   Name,
                   AccountNumber,
                   BillingState
            FROM Account
            WHERE AccountNumber = :TEST_ACCOUNT_NUMBER
            LIMIT 1
        ];
    }

    private static Coverage_Level__c getCoverageLevel() {
        return [
            SELECT Id, Name
            FROM Coverage_Level__c
            WHERE Name = :TEST_COVERAGE_NAME
            LIMIT 1
        ];
    }

    private static Id getAutoWarrantyRecordTypeId() {
        Schema.RecordTypeInfo rtInfo =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty');

        System.assertNotEquals(
            null,
            rtInfo,
            'Auto_Warranty record type must exist.'
        );

        return rtInfo.getRecordTypeId();
    }

    private static Id getHomeWarrantyRecordTypeId() {
        Schema.RecordTypeInfo rtInfo =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Home_Warranty');

        System.assertNotEquals(
            null,
            rtInfo,
            'Home_Warranty record type must exist.'
        );

        return rtInfo.getRecordTypeId();
    }

    /*
     * BREServiceHandler mutates records supplied to it; it does not require
     * InsurancePolicy DML. Keeping these records in memory deliberately avoids
     * coupling this unit test to Sold_Contract_Validation or unrelated
     * Contract-trigger validations.
     */
    private static InsurancePolicy buildAutoPolicy(String policyName) {
        Account testAccount = getTestAccount();
        Coverage_Level__c coverageLevel = getCoverageLevel();

        InsurancePolicy policyRec = new InsurancePolicy();

        policyRec.Name = policyName;
        policyRec.RecordTypeId = getAutoWarrantyRecordTypeId();
        policyRec.Client__c = testAccount.Id;
        policyRec.NameInsuredId = testAccount.Id;
        policyRec.Dealer__c = testAccount.Id;
        policyRec.Dealer_Program_Id__c = '259';

        policyRec.SaleDate = System.now();
        policyRec.Sale_Date__c = Date.today();

        policyRec.Coverage_Level__c = coverageLevel.Id;
        policyRec.Vehicle_Make__c = 'ACUR';
        policyRec.Contract_Term_Mileage__c = 24000;
        policyRec.Contract_Term_Months__c = 24;
        policyRec.Vehicle_Mileage_at_Contract_Inception__c = 50002;
        policyRec.Vehicle_Year__c =
            String.valueOf(Date.today().year() - 5);

        policyRec.Option_1__c = 'Salvaged';
        policyRec.Is_Commercial__c = true;
        policyRec.Product__c = 'SecureOne';
        policyRec.Rate_Set__c = 'EZ FL M2M DM VSC AMT';
        policyRec.Options_Sets__c =
            'EZ FL M2M DM VSC AMT Options';
        policyRec.Surcharge_Set__c =
            'EZ FL M2M DM VSC AMT Surcharges';

        policyRec.Up_To_or_Add__c = 'UpTo';
        policyRec.Class__c = '8';
        policyRec.Deductible__c = 100;
        policyRec.Ins_Carrier__c =
            'AmericanResourceInsuranceCompany';
        policyRec.State__c = 'FL';
        policyRec.Year_Built__c =
            String.valueOf(Date.today().year() - 10);

        return policyRec;
    }

    @IsTest
    static void calculateRateDetails() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-RATE-DETAILS');

        BREServiceHandler.contractStateMap.clear();
        BREServiceHandler.contractStateMap.put(
            policyRec.Name,
            'FL'
        );

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new RateDetailsMock()
        );

        BREServiceHandler.calculateRateDetails(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertEquals(
            1000,
            policyRec.Net_Dealer_Cost__c,
            'Final Total Rate should populate Net Dealer Cost.'
        );
        System.assertEquals('UT-RATE', policyRec.Rate_Code__c);
        System.assertEquals('8', policyRec.Class__c);
        System.assertEquals(
            'Technology Insurance Company',
            policyRec.Ins_Carrier__c
        );
        System.assertEquals('UT Obligor', policyRec.Obligor__c);
        System.assertEquals('UT Admin', policyRec.Admin__c);
    }

    @IsTest
    static void retriveDealerCode() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-DEALER-CODE');

        Account testAccount = getTestAccount();
        Coverage_Level__c coverageLevel = getCoverageLevel();

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new DealerCodeMock(testAccount.Name)
        );

        BREServiceHandler.retrieveDealerCodeData(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertEquals(
            coverageLevel.Id,
            policyRec.Coverage_Level__c,
            'Coverage Level should map from the Dealer Code response.'
        );
        System.assertEquals(
            testAccount.Id,
            policyRec.Client__c,
            'Client should map from the Dealer Code response.'
        );
        System.assertEquals(
            'Unit Test Reinsurance',
            policyRec.Reinsurance_Company__c
        );
        System.assertEquals(
            'MAC DM VSC 8 CLASS AMTRUST',
            policyRec.Class_Guide__c
        );
    }

    @IsTest
    static void testStateInsurance() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-STATE-INS');

        BREServiceHandler.contractStateMap.clear();
        BREServiceHandler.contractStateMap.put(
            policyRec.Name,
            'FL'
        );

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new StateInsuranceGuideMock()
        );

        BREServiceHandler.populateStateInsuranceDetails(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertEquals(
            'Technology Insurance Company',
            policyRec.Ins_Carrier__c
        );
        System.assertEquals('UT Obligor', policyRec.Obligor__c);
        System.assertEquals('UT Admin', policyRec.Admin__c);
        System.assertEquals('UT Insurance Type', policyRec.Ins_Type__c);
    }

    @IsTest
    static void testRateSetsMethod() {
        InsurancePolicy policyWithVehicleYear =
            buildAutoPolicy('BRE-RATE-SET-YEAR');

        InsurancePolicy policyWithoutVehicleYear =
            buildAutoPolicy('BRE-RATE-SET-NO-YEAR');
        policyWithoutVehicleYear.Vehicle_Year__c = null;

        List<InsurancePolicy> policies =
            new List<InsurancePolicy>{
                policyWithVehicleYear,
                policyWithoutVehicleYear
            };

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new ExpressionSetMock()
        );

        BREServiceHandler.populateRateSetDetails(policies);

        Test.stopTest();

        System.assertEquals(
            69,
            policyWithVehicleYear.Reserve__c
        );
        System.assertEquals(
            'MTMFLEZELT8',
            policyWithVehicleYear.Rate_Code__c
        );
        System.assertEquals(
            1,
            policyWithVehicleYear.Premium_Tax_Old__c
        );
        System.assertEquals(
            2,
            policyWithVehicleYear.OT_Allocation__c
        );
        System.assertEquals(
            2.8,
            policyWithVehicleYear.MBI_Seller_Commission__c
        );
    }

    @IsTest
    static void OptionsSetsTestMethod() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-OPTION-SET');

        // Two options exercise the aggregation loop.
        policyRec.Option_1__c = 'Salvaged;Rideshare';

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new OptionsSetMock()
        );

        BREServiceHandler.populateOptionSetDetails(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertEquals(
            5,
            policyRec.Options_Cost__c,
            'Two mocked option rows at 2.5 each should aggregate to 5.'
        );
        System.assertEquals(
            2,
            policyRec.Premium_Tax_Old__c
        );
        System.assertEquals(
            4,
            policyRec.OT_Allocation__c
        );
    }

    @IsTest
    static void testSurchargeSetDetails() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-SURCHARGE');

        String vin = '1HGCM82633A123456';

        /*
         * Seed a matching squish mask so VinUtility can resolve the VIN.
         * The first mask mirrors the standard VIN squish priority.
         */
        String mask =
            vin.substring(0, 8) +
            '*' +
            vin.substring(9, 11) +
            '******';

        VIN_Detail__c vinDetail =
            TestDataFactory.createVinDetail(false);

        vinDetail.Name = mask;
        vinDetail.VIN_SIGNI_PATTRN_MASK__c = mask;
        insert vinDetail;

        policyRec.VIN__c = vin;
        policyRec.Vehicle_Mileage_at_Contract_Inception__c = 6000;
        policyRec.Product__c = 'Health CAR';
        policyRec.Surcharge_Cost__c = 0;

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new SurchargeDetailsMock()
        );

        BREServiceHandler.populateSurchargeSetDetails(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            policyRec.Surcharges__c,
            'Resolved VIN should allow applicable surcharge names to be built.'
        );
        System.assert(
            policyRec.Surcharges__c.contains(
                'Extended Eligibility 5-12k'
            ),
            'Mileage based surcharge should be included.'
        );
        System.assert(
            policyRec.Surcharges__c.contains(
                'All Classes Surcharge'
            ),
            'Health CAR should include the All Classes surcharge.'
        );
        System.assertEquals(
            5,
            policyRec.Surcharge_Cost__c,
            'Two surcharge rows at 2.5 each should aggregate to 5.'
        );
    }

    @IsTest
    static void populateStateInsuranceDetailsTestMethod() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-STATE-DETAILS');

        BREServiceHandler.contractStateMap.clear();
        BREServiceHandler.contractStateMap.put(
            policyRec.Name,
            'FL'
        );

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new StateInsuranceMock()
        );

        BREServiceHandler.populateStateInsuranceDetails(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertEquals('UT Admin 2', policyRec.Admin__c);
        System.assertEquals(
            'UT Insurance Type 2',
            policyRec.Ins_Type__c
        );
    }

    @IsTest
    static void testPopulateOriginalState() {
        Account testAccount = getTestAccount();

        InsurancePolicy dealerStatePolicy =
            buildAutoPolicy('BRE-STATE-DEALER');

        InsurancePolicy namedInsuredFallback =
            buildAutoPolicy('BRE-STATE-NAMED-INSURED');
        namedInsuredFallback.Dealer__c = null;

        InsurancePolicy homeWarranty =
            new InsurancePolicy(
                Name = 'BRE-HOME-STATE',
                RecordTypeId = getHomeWarrantyRecordTypeId(),
                State__c = 'TX'
            );

        InsurancePolicy homeWarrantyWithoutState =
            new InsurancePolicy(
                Name = 'BRE-HOME-NO-STATE',
                RecordTypeId = getHomeWarrantyRecordTypeId()
            );

        Test.startTest();

        BREServiceHandler.populateOriginalState(
            new List<InsurancePolicy>{
                dealerStatePolicy,
                namedInsuredFallback,
                homeWarranty,
                homeWarrantyWithoutState
            }
        );

        Test.stopTest();

        System.assertEquals(
            testAccount.BillingState,
            BREServiceHandler.contractStateMap.get(
                dealerStatePolicy.Name
            )
        );
        System.assertEquals(
            testAccount.BillingState,
            BREServiceHandler.contractStateMap.get(
                namedInsuredFallback.Name
            )
        );
        System.assertEquals(
            'TX',
            BREServiceHandler.contractStateMap.get(
                homeWarranty.Name
            )
        );
        System.assertEquals(
            null,
            BREServiceHandler.contractStateMap.get(
                homeWarrantyWithoutState.Name
            )
        );
    }

    @IsTest
    static void testPopulateInsuranceCodeDirect() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-INSURANCE-CODE');

        BREServiceHandler.contractStateMap.clear();
        BREServiceHandler.contractStateMap.put(
            policyRec.Name,
            'FL'
        );

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new InsuranceCodeMock()
        );

        BREServiceHandler.populateInsuranceCode(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertEquals(
            'UT-INS',
            policyRec.Insurance_Code__c
        );
    }

    @IsTest
    static void testExecuteBusinessRulePipeline() {
        InsurancePolicy policyRec = new InsurancePolicy();

        policyRec.Name = 'BRE-PIPELINE';
        policyRec.RecordTypeId = getHomeWarrantyRecordTypeId();
        policyRec.State__c = 'TX';
        policyRec.SaleDate = System.now();

        policyRec.Premium_Tax_Old__c = 9;
        policyRec.OT_Allocation__c = 8;
        policyRec.Options_Cost__c = 7;
        policyRec.Surcharge_Cost__c = 6;

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new PipelineNameValueMock()
        );

        List<InsurancePolicy> result =
            BREServiceHandler.executeBusinessRule(
                new List<InsurancePolicy>{ policyRec }
            );

        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(
            0,
            policyRec.Premium_Tax_Old__c
        );
        System.assertEquals(
            0,
            policyRec.OT_Allocation__c
        );
        System.assertEquals(
            0,
            policyRec.Options_Cost__c
        );
        System.assertEquals(
            0,
            policyRec.Surcharge_Cost__c
        );
        System.assertEquals(
            'TX',
            BREServiceHandler.contractStateMap.get(
                policyRec.Name
            )
        );
    }

    @IsTest
    static void testEmptyCollectionsAndExceptionGuards() {
        Test.startTest();

        BREServiceHandler.populateOriginalState(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.populateInsuranceCode(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.calculateRateDetails(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.retrieveDealerCodeData(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.populateStateInsuranceDetails(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.populateRateSetDetails(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.populateOptionSetDetails(
            new List<InsurancePolicy>()
        );
        BREServiceHandler.populateSurchargeSetDetails(
            new List<InsurancePolicy>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            BREServiceHandler.contractStateMap.size()
        );
    }

    @IsTest
    static void testHandledExceptionPaths() {
        InsurancePolicy policyRec =
            buildAutoPolicy('BRE-EXCEPTION-PATHS');

        BREServiceHandler.contractStateMap.clear();
        BREServiceHandler.contractStateMap.put(
            policyRec.Name,
            'FL'
        );

        Test.startTest();
        Test.setMock(
            HttpCalloutMock.class,
            new MalformedJsonMock()
        );

        // Each public method owns its own exception handling.
        BREServiceHandler.populateInsuranceCode(
            new List<InsurancePolicy>{ policyRec }
        );
        BREServiceHandler.calculateRateDetails(
            new List<InsurancePolicy>{ policyRec }
        );
        BREServiceHandler.retrieveDealerCodeData(
            new List<InsurancePolicy>{ policyRec }
        );
        BREServiceHandler.populateStateInsuranceDetails(
            new List<InsurancePolicy>{ policyRec }
        );
        BREServiceHandler.populateRateSetDetails(
            new List<InsurancePolicy>{ policyRec }
        );
        BREServiceHandler.populateOptionSetDetails(
            new List<InsurancePolicy>{ policyRec }
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            policyRec,
            'Handled BRE parsing errors must not escape to the caller.'
        );
    }


    // =========================================================
    // HTTP MOCKS
    // =========================================================

    private class InsuranceCodeMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            List<Object> results = new List<Object>{
                new Map<String, Object>{
                    'name' => 'InsuranceCode',
                    'value' => 'UT-INS'
                }
            };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class DealerCodeMock implements HttpCalloutMock {
        private String clientName;

        DealerCodeMock(String clientName) {
            this.clientName = clientName;
        }

        public HTTPResponse respond(HTTPRequest req) {
            List<Object> results = new List<Object>{
                new Map<String, Object>{
                    'name' => 'CoverageLevel',
                    'value' => TEST_COVERAGE_NAME
                },
                new Map<String, Object>{
                    'name' => 'Product',
                    'value' => 'SecureOne'
                },
                new Map<String, Object>{
                    'name' => 'Client',
                    'value' => clientName
                },
                new Map<String, Object>{
                    'name' => 'RateSet',
                    'value' => 'EZ FL M2M DM VSC AMT'
                },
                new Map<String, Object>{
                    'name' => 'OptionSets',
                    'value' => 'EZ FL M2M DM VSC AMT Options'
                },
                new Map<String, Object>{
                    'name' => 'SurchargeSets',
                    'value' => 'EZ FL M2M DM VSC AMT Surcharges'
                },
                new Map<String, Object>{
                    'name' => 'ClassGuide',
                    'value' => 'MAC DM VSC 8 CLASS AMTRUST'
                },
                new Map<String, Object>{
                    'name' => 'ReinsuranceCompany',
                    'value' => 'Unit Test Reinsurance'
                }
            };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class RateDetailsMock implements HttpCalloutMock {
        private Integer callNumber = 0;

        public HTTPResponse respond(HTTPRequest req) {
            callNumber++;

            if (callNumber == 1) {
                Map<String, Object> results =
                    new Map<String, Object>{
                        'Option_Cost' => 2.8,
                        'Rate_Set' => 'UT Rate Set',
                        'Product' => 'SecureOne',
                        'Rate_Code' => 'UT-RATE',
                        'Class_Guide' => 'UT Class Guide',
                        'Rate_Class' => '8',
                        'Rate_Cost' => 69.0,
                        'Expire_Type' => 'UpTo',
                        'Option' => 'Salvaged',
                        'Deductible' => 100.0,
                        'Max_Miles' => 150000.0,
                        'Final_Total_Rate' => 1000.0
                    };

                return jsonResponse(
                    new Map<String, Object>{
                        'outputs' => new List<Object>{
                            new Map<String, Object>{
                                'results' => results
                            }
                        }
                    }
                );
            }

            List<Object> results = new List<Object>{
                new Map<String, Object>{
                    'name' => 'InsuranceCarrier',
                    'value' => 'Technology Insurance Company'
                },
                new Map<String, Object>{
                    'name' => 'Obligor',
                    'value' => 'UT Obligor'
                },
                new Map<String, Object>{
                    'name' => 'AdminCompany',
                    'value' => 'UT Admin'
                },
                new Map<String, Object>{
                    'name' => 'TypeOfInsurance',
                    'value' => 'UT Insurance Type'
                }
            };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class StateInsuranceGuideMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> results =
                new Map<String, Object>{
                    'CarrierOutput' =>
                        'Technology Insurance Company',
                    'ObligorOutput' => 'UT Obligor',
                    'AdminOutput' => 'UT Admin',
                    'InsuranceTypeOutput' =>
                        'UT Insurance Type'
                };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class ExpressionSetMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> results =
                new Map<String, Object>{
                    'BaseReserveOutput' => 69.0,
                    'RateCodeOutput' => 'MTMFLEZELT8',
                    'PremiumTaxOutput' => 1.0,
                    'ObligorTaxOutput' => 2.0,
                    'CommissionOutput' => 2.8,
                    'MaxMilesOutput' => 150000.0,
                    'MaxSquareFootOutput' => 2800.0,
                    'MaxUnitOutput' => 4.0,
                    'MaxAgeOutput' => 20.0
                };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class OptionsSetMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> results =
                new Map<String, Object>{
                    'MaxTermMonthsOutput' => 120.0,
                    'MaxTermMilesOutput' => 150000.0,
                    'MaxVehicleMilesOutput' => 150000.0,
                    'MaxVehicleAgeOutput' => 20.0,
                    'MaxResidenceSqFtOutput' => 10000.0,
                    'MaxResidenceAgeOutput' => 100.0,
                    'PremiumTaxOutput' => 1.0,
                    'ObligorTaxOutput' => 2.0,
                    'OptionCostOutput' => 2.5
                };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class SurchargeDetailsMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> results =
                new Map<String, Object>{
                    'SurchargeCostOutput' => 2.5,
                    'MaxTermMonthsOutput' => 120.0,
                    'MaxTermMilesOutput' => 150000.0,
                    'MaxVehicleMilesOutput' => 150000.0,
                    'MaxVehicleAgeOutput' => 20.0,
                    'PremiumTaxOutput' => 1.0,
                    'ObligorTaxOutput' => 2.0
                };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class StateInsuranceMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> results =
                new Map<String, Object>{
                    'CarrierOutput' =>
                        'AmericanResourceInsuranceCompany',
                    'ObligorOutput' => 'UT Obligor 2',
                    'AdminOutput' => 'UT Admin 2',
                    'InsuranceTypeOutput' =>
                        'UT Insurance Type 2'
                };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class PipelineNameValueMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            List<Object> results = new List<Object>{
                new Map<String, Object>{
                    'name' => 'InsuranceCode',
                    'value' => 'UT-PIPE'
                },
                new Map<String, Object>{
                    'name' => 'InsuranceCarrier',
                    'value' => 'Technology Insurance Company'
                },
                new Map<String, Object>{
                    'name' => 'Obligor',
                    'value' => 'UT Obligor'
                },
                new Map<String, Object>{
                    'name' => 'AdminCompany',
                    'value' => 'UT Admin'
                },
                new Map<String, Object>{
                    'name' => 'TypeOfInsurance',
                    'value' => 'UT Type'
                }
            };

            return jsonResponse(
                new Map<String, Object>{
                    'outputs' => new List<Object>{
                        new Map<String, Object>{
                            'results' => results
                        }
                    }
                }
            );
        }
    }

    private class MalformedJsonMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{bad json');
            return res;
        }
    }

    private static HTTPResponse jsonResponse(
        Map<String, Object> payload
    ) {
        HTTPResponse res = new HTTPResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(200);
        res.setStatus('OK');
        res.setBody(JSON.serialize(payload));
        return res;
    }
}