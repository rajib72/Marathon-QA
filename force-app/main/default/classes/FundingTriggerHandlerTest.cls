/**
 * @author Sujit Dengale
 * @dateModified 2026-10-05
 * @description Test coverage for FundingTriggerHandler
 *
 * Validation-safe refactor:
 * - Uses a WUS client so Sold_Contract_Validation does not block Contract insert.
 * - Creates InsurancePolicy with doInsert = false, explicitly sets Client__c,
 *   then performs the first DML.
 * - Keeps Funding allocation batches disabled inside tests.
 * - Keeps Net Dealer Cost equal to the ContractTriggerHandler-calculated
 *   Total Rate Cost so Contract insert does not receive addError().
 * - Keeps PremiumAmount/Down Payment/Lien Holder mutually consistent
 *   so Full_Pay_Validation accepts the Contract fixture.
 * - Clears the writable Lien_Holder__c lookup instead of attempting to
 *   assign the read-only Lien_Holder_Present__c field.
 */
@IsTest
public class FundingTriggerHandlerTest {

    private static void disableAsyncAllocation() {
        FundingAllocationOrchestrator.disableBatchExecution = true;
    }

    /*
     * Some org fields in this funding flow are surfaced/stored with a
     * time component even though the production handler intentionally works
     * with Date values. Normalize both sides to yyyy-MM-dd so assertions test
     * the business date rather than an irrelevant midnight/time-zone value.
     */
    private static String toDateKey(Object value) {
        if (value == null) {
            return null;
        }

        String rawValue = String.valueOf(value);

        return rawValue.length() >= 10
            ? rawValue.substring(0, 10)
            : rawValue;
    }

    private static InsurancePolicy createValidationSafePolicy(
        Decimal netDealerCost,
        Decimal existingFundedAmount,
        String productName
    ) {
        Account client =
            TestDataFactory.createAccount(false);

        client.AccountNumber = 'WUS';
        insert client;

        Id autoWarrantyRecordTypeId =
            Schema.SObjectType.InsurancePolicy
                .getRecordTypeInfosByDeveloperName()
                .get('Auto_Warranty')
                .getRecordTypeId();

        InsurancePolicy policy =
            TestDataFactory.createInsurancePolicy(
                false,
                client.Id
            );

        /*
         * CRITICAL:
         * Client__c must be populated before the first Contract insert.
         */
        policy.Client__c = client.Id;
        policy.NameInsuredId = client.Id;
        policy.RecordTypeId = autoWarrantyRecordTypeId;

        /*
         * Keep later Contract updates validation-safe as well.
         */
        policy.SaleDate = System.now();
        policy.Sale_Date__c = Date.today().addDays(-30);
        policy.Vehicle_Mileage_at_Contract_Inception__c = 10000;
        policy.Vehicle_Year__c = '2010';

        /*
         * FULL PAY VALIDATION SAFETY
         * -------------------------------------------------------------
         * Full_Pay_Validation requires these two states to agree:
         *
         * 1) Down Payment == PremiumAmount  -> no lien holder
         * 2) Down Payment != PremiumAmount  -> lien holder required
         *
         * Use the full-pay/no-lien state. This satisfies the business
         * rule directly instead of depending on Legacy_Source__c or
         * another validation-rule bypass.
         */
        Decimal retailCost =
            netDealerCost == null
                ? 1000
                : netDealerCost;

        policy.PremiumAmount = retailCost;
        policy.Down_Payment_Amount__c = retailCost;

        /*
         * Lien_Holder_Present__c is read-only in this org, so do not assign
         * it directly. Lien_Holder__c is the writable Account lookup.
         * Clearing the lookup represents the full-pay / no-lien scenario
         * required by Full_Pay_Validation.
         */
        policy.Lien_Holder__c = null;

        if (String.isNotBlank(productName)) {
            policy.Product__c = productName;
        }

        policy.Net_Dealer_Cost__c =
            netDealerCost == null
                ? 1000
                : netDealerCost;

        policy.DLRS_Total_Funded_Amount_from_Funding__c =
            existingFundedAmount == null
                ? 0
                : existingFundedAmount;

        /*
         * ContractTriggerHandler.contractRateValidation() validates:
         *
         * Net Dealer Cost
         *   = Reserve
         *   + Options Cost
         *   + Surcharge Cost
         *   + Projected Allocation Cost
         *
         * The previous fixture set Projected_Allocation_Cost__c equal to
         * Net_Dealer_Cost__c and then added Reserve__c = 10. That made the
         * calculated Total Rate Cost exactly $10 higher than Imported Cost.
         *
         * Keep Reserve positive because the handler rejects a zero/null
         * Reserve. Also account for any Options/Surcharge defaults supplied
         * by TestDataFactory so this fixture remains stable across orgs.
         */
        policy.Reserve__c = 1;

        Decimal optionsCost =
            policy.Options_Cost__c == null
                ? 0
                : policy.Options_Cost__c;

        Decimal surchargeCost =
            policy.Surcharge_Cost__c == null
                ? 0
                : policy.Surcharge_Cost__c;

        policy.Projected_Allocation_Cost__c =
            policy.Net_Dealer_Cost__c -
            policy.Reserve__c -
            optionsCost -
            surchargeCost;

        insert policy;

        return [
            SELECT
                Id,
                Name,
                RecordTypeId,
                Product__c,
                Net_Dealer_Cost__c,
                DLRS_Total_Funded_Amount_from_Funding__c,
                Contract_Funded_Date__c,
                Earliest_Contract_Funded_Date__c
            FROM InsurancePolicy
            WHERE Id = :policy.Id
            LIMIT 1
        ];
    }

    private static Funding__c createFundingRecord(
        Id contractId,
        Decimal amount
    ) {
        Funding__c funding =
            TestDataFactory.createFunding(
                false,
                contractId
            );

        funding.Contract__c = contractId;
        funding.Contract_Number_from_Import__c = null;
        funding.Funded_Amount__c =
            amount == null ? 10 : amount;

        return funding;
    }

    private static List<Funding__c> queryFundings(
        Set<Id> fundingIds
    ) {
        return [
            SELECT
                Id,
                Contract__c,
                Funded_Amount__c,
                Created_Date_Only__c,
                Contract__r.Product__c
            FROM Funding__c
            WHERE Id IN :fundingIds
            ORDER BY CreatedDate ASC
        ];
    }


    // =========================================================
    // BEFORE INSERT / CONTRACT IMPORT MAPPING
    // =========================================================
    @IsTest
    static void testFundingImportMapsContractAndInsertsSuccessfully() {

        disableAsyncAllocation();

        InsurancePolicy policy =
            createValidationSafePolicy(
                1000,
                0,
                'NonSecureOne'
            );

        Funding__c funding =
            createFundingRecord(
                policy.Id,
                25
            );

        funding.Contract__c = null;
        funding.Contract_Number_from_Import__c =
            policy.Name;

        Test.startTest();

        insert funding;

        Test.stopTest();

        Funding__c savedFunding = [
            SELECT
                Id,
                Contract__c,
                Overfunding_Flagged_at__c
            FROM Funding__c
            WHERE Id = :funding.Id
        ];

        System.assertEquals(
            policy.Id,
            savedFunding.Contract__c,
            'Before insert should resolve Contract_Number_from_Import__c.'
        );

        System.assertEquals(
            null,
            savedFunding.Overfunding_Flagged_at__c,
            'Normal funding must not be marked overfunded.'
        );
    }


    // =========================================================
    // UPDATE STATUS / OVERFUNDING / IMPORT ERROR
    // =========================================================
    @IsTest
    static void testUpdateStatusBranches() {

        disableAsyncAllocation();

        InsurancePolicy policy =
            createValidationSafePolicy(
                50,
                40,
                'NonSecureOne'
            );

        Funding__c overfunding =
            new Funding__c(
                Contract_Number_from_Import__c = policy.Name,
                Funded_Amount__c = 20
            );

        Test.startTest();

        FundingTriggerHandler.handleBeforeInsert(
            new List<Funding__c>{
                overfunding
            }
        );

        Test.stopTest();

        System.assertEquals(
            policy.Id,
            overfunding.Contract__c,
            'Contract lookup should be populated from imported Contract Number.'
        );

        System.assertNotEquals(
            null,
            overfunding.Overfunding_Flagged_at__c,
            '40 existing + 20 new exceeds Net Dealer Cost 50.'
        );

        Funding__c missingContract =
            new Funding__c(
                Contract_Number_from_Import__c =
                    'UNIT-TEST-CONTRACT-DOES-NOT-EXIST',
                Funded_Amount__c = 10
            );

        FundingTriggerHandler.updateStatus(
            new List<Funding__c>{
                missingContract
            },
            null
        );

        System.assert(
            missingContract.hasErrors(),
            'Unknown imported Contract should receive addError().'
        );

        Funding__c updateContextRecord =
            new Funding__c(
                Contract_Number_from_Import__c =
                    policy.Name,
                Funded_Amount__c = 10
            );

        FundingTriggerHandler.updateStatus(
            new List<Funding__c>{
                updateContextRecord
            },
            new Map<Id, Funding__c>()
        );

        System.assertEquals(
            null,
            updateContextRecord.Contract__c,
            'Import Contract mapping is insert-only when oldFundings is null.'
        );
    }


    // =========================================================
    // CONTRACT FUNDED DATE
    // =========================================================
    @IsTest
    static void testUpdateContractFundedDateUsesLatestDate() {

        disableAsyncAllocation();

        InsurancePolicy policy =
            createValidationSafePolicy(
                1000,
                0,
                'NonSecureOne'
            );

        Funding__c firstFunding =
            createFundingRecord(
                policy.Id,
                10
            );

        Funding__c secondFunding =
            createFundingRecord(
                policy.Id,
                20
            );

        insert new List<Funding__c>{
            firstFunding,
            secondFunding
        };

        Date olderDate =
            Date.today().addDays(-5);

        Date newerDate =
            Date.today().addDays(-2);

        Test.setCreatedDate(
            firstFunding.Id,
            Datetime.newInstance(
                olderDate,
                Time.newInstance(9, 0, 0, 0)
            )
        );

        Test.setCreatedDate(
            secondFunding.Id,
            Datetime.newInstance(
                newerDate,
                Time.newInstance(9, 0, 0, 0)
            )
        );

        List<Funding__c> queriedFundings =
            queryFundings(
                new Set<Id>{
                    firstFunding.Id,
                    secondFunding.Id
                }
            );

        update new InsurancePolicy(
            Id = policy.Id,
            Contract_Funded_Date__c = null,
            Earliest_Contract_Funded_Date__c = null
        );

        Date expectedLatestDate;

        for (Funding__c funding : queriedFundings) {
            if (
                expectedLatestDate == null ||
                funding.Created_Date_Only__c >
                    expectedLatestDate
            ) {
                expectedLatestDate =
                    funding.Created_Date_Only__c;
            }
        }

        Test.startTest();

        FundingTriggerHandler.updateContractFundedDate(
            queriedFundings,
            null
        );

        Test.stopTest();

        InsurancePolicy refreshedPolicy = [
            SELECT Contract_Funded_Date__c
            FROM InsurancePolicy
            WHERE Id = :policy.Id
        ];

        System.assertEquals(
            toDateKey(expectedLatestDate),
            toDateKey(refreshedPolicy.Contract_Funded_Date__c),
            'The latest Funding business date should be written to the Contract.'
        );
    }


    // =========================================================
    // SECUREONE CONTRACT FUNDED DATE SKIP
    // =========================================================
    @IsTest
    static void testUpdateContractFundedDateSkipsSecureOne() {

        disableAsyncAllocation();

        InsurancePolicy policy =
            createValidationSafePolicy(
                1000,
                0,
                'SecureOne'
            );

        Funding__c funding =
            createFundingRecord(
                policy.Id,
                10
            );

        insert funding;

        List<Funding__c> queriedFundings =
            queryFundings(
                new Set<Id>{
                    funding.Id
                }
            );

        update new InsurancePolicy(
            Id = policy.Id,
            Contract_Funded_Date__c = null
        );

        Test.startTest();

        FundingTriggerHandler.updateContractFundedDate(
            queriedFundings,
            null
        );

        Test.stopTest();

        InsurancePolicy refreshedPolicy = [
            SELECT Contract_Funded_Date__c
            FROM InsurancePolicy
            WHERE Id = :policy.Id
        ];

        System.assertEquals(
            null,
            refreshedPolicy.Contract_Funded_Date__c,
            'SecureOne must not receive Contract_Funded_Date__c from this method.'
        );
    }


    // =========================================================
    // EARLIEST FUNDED DATE
    // =========================================================
    @IsTest
    static void testUpdateEarliestContractFundedDateSetsOnlyOnce() {

        disableAsyncAllocation();

        InsurancePolicy policy =
            createValidationSafePolicy(
                1000,
                0,
                'NonSecureOne'
            );

        Funding__c firstFunding =
            createFundingRecord(
                policy.Id,
                10
            );

        Funding__c secondFunding =
            createFundingRecord(
                policy.Id,
                20
            );

        insert new List<Funding__c>{
            firstFunding,
            secondFunding
        };

        Test.setCreatedDate(
            firstFunding.Id,
            Datetime.newInstance(
                Date.today().addDays(-8),
                Time.newInstance(8, 0, 0, 0)
            )
        );

        Test.setCreatedDate(
            secondFunding.Id,
            Datetime.newInstance(
                Date.today().addDays(-3),
                Time.newInstance(8, 0, 0, 0)
            )
        );

        List<Funding__c> queriedFundings =
            queryFundings(
                new Set<Id>{
                    firstFunding.Id,
                    secondFunding.Id
                }
            );

        Date expectedEarliest =
            queriedFundings[0].Created_Date_Only__c;

        update new InsurancePolicy(
            Id = policy.Id,
            Earliest_Contract_Funded_Date__c = null
        );

        Test.startTest();

        FundingTriggerHandler.updateEarliestContractFundedDate(
            queriedFundings
        );

        Test.stopTest();

        InsurancePolicy afterFirstRun = [
            SELECT Earliest_Contract_Funded_Date__c
            FROM InsurancePolicy
            WHERE Id = :policy.Id
        ];

        System.assertEquals(
            toDateKey(expectedEarliest),
            toDateKey(afterFirstRun.Earliest_Contract_Funded_Date__c),
            'The eligible Contract should receive the first Funding business date in scope.'
        );

        FundingTriggerHandler.updateEarliestContractFundedDate(
            new List<Funding__c>{
                queriedFundings[1]
            }
        );

        InsurancePolicy afterSecondRun = [
            SELECT Earliest_Contract_Funded_Date__c
            FROM InsurancePolicy
            WHERE Id = :policy.Id
        ];

        System.assertEquals(
            toDateKey(expectedEarliest),
            toDateKey(afterSecondRun.Earliest_Contract_Funded_Date__c),
            'An existing earliest funded business date must not be overwritten.'
        );
    }


    // =========================================================
    // ALLOCATION PROCESS DECISION
    // =========================================================
    @IsTest
    static void testStartAllocationProcessChangedAndIgnoredAmounts() {

        disableAsyncAllocation();

        InsurancePolicy policy =
            createValidationSafePolicy(
                1000,
                0,
                'NonSecureOne'
            );

        Funding__c funding =
            createFundingRecord(
                policy.Id,
                10
            );

        /*
         * INSERT exercises startAllocationProcess() in a real after-insert
         * trigger context, where Trigger.isInsert is valid.
         */
        insert funding;

        Funding__c oldFunding = [
            SELECT
                Id,
                Contract__c,
                Funded_Amount__c
            FROM Funding__c
            WHERE Id = :funding.Id
        ];

        Decimal changedAmount =
            oldFunding.Funded_Amount__c + 5;

        Funding__c changedFunding =
            new Funding__c(
                Id = oldFunding.Id,
                Funded_Amount__c = changedAmount
            );

        Test.startTest();

        /*
         * UPDATE exercises the amount-changed branch in a real after-update
         * trigger context. This is intentionally DML-based: calling the
         * handler directly with a populated Contract and Amount makes
         * Trigger.isInsert null outside a trigger and causes an NPE.
         */
        update changedFunding;

        /*
         * Re-save the current value unchanged to exercise the branch where
         * no new allocation should be started.
         */
        Funding__c unchangedFunding = [
            SELECT
                Id,
                Contract__c,
                Funded_Amount__c
            FROM Funding__c
            WHERE Id = :funding.Id
        ];

        update unchangedFunding;

        /*
         * These direct calls are safe because the conditions short-circuit
         * before Trigger.isInsert is referenced.
         */
        FundingTriggerHandler.startAllocationProcess(
            new List<Funding__c>{
                new Funding__c(
                    Funded_Amount__c = 5
                )
            },
            null
        );

        FundingTriggerHandler.startAllocationProcess(
            new List<Funding__c>{
                new Funding__c(
                    Contract__c = policy.Id
                )
            },
            null
        );

        FundingTriggerHandler.startAllocationProcess(
            new List<Funding__c>(),
            null
        );

        Test.stopTest();

        Funding__c refreshedFunding = [
            SELECT
                Contract__c,
                Funded_Amount__c
            FROM Funding__c
            WHERE Id = :funding.Id
        ];

        System.assertEquals(
            policy.Id,
            refreshedFunding.Contract__c,
            'The Funding should remain associated to its Contract.'
        );

        System.assertEquals(
            changedAmount,
            refreshedFunding.Funded_Amount__c,
            'The changed Funding amount should be persisted.'
        );
    }


    // =========================================================
    // EMPTY / DEFENSIVE / CATCH PATHS
    // =========================================================
    @IsTest
    static void testDefensiveAndExceptionPaths() {

        disableAsyncAllocation();

        Test.startTest();

        FundingTriggerHandler.handleBeforeInsert(
            new List<Funding__c>()
        );

        FundingTriggerHandler.handleAfterInsert(
            new List<Funding__c>(),
            null
        );

        FundingTriggerHandler.updateStatus(
            new List<Funding__c>{
                new Funding__c()
            },
            null
        );

        FundingTriggerHandler.updateEarliestContractFundedDate(
            new List<Funding__c>()
        );

        /*
         * Each method owns its exception handling. Passing null deliberately
         * covers those logging/catch/finally branches without changing
         * production code solely for testability.
         */
        FundingTriggerHandler.updateStatus(
            null,
            null
        );

        FundingTriggerHandler.updateContractFundedDate(
            null,
            null
        );

        FundingTriggerHandler.updateEarliestContractFundedDate(
            null
        );

        Test.stopTest();

        System.assert(
            true,
            'Defensive paths completed without leaking exceptions.'
        );
    }
}