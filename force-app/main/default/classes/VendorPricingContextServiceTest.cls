/** Pure in-memory tests: no DML, vendor callouts, or SeeAllData=true. */
@IsTest
private class VendorPricingContextServiceTest {
    private static final Id CLAIM_ID = '0Zk000000000001';
    private static final Id SAVED_ID = '0dq000000000001';
    private static final Id DETAIL_ID = 'a8G000000000001';
    private static final Id COVERAGE_ID = 'a8H000000000001';

    private static VendorPricingRequestContext header() {
        VendorPricingRequestContext context = new VendorPricingRequestContext();
        context.claimId = CLAIM_ID;
        context.coverageLevelId = COVERAGE_ID;
        context.vin = '1HGCM82633A004352';
        context.currentMileage = 30500;
        context.repairShopCountry = null;
        return context;
    }

    private static VendorPricingLineInput input(
        String key, Id itemId, String detailType, String partNumber,
        Decimal quantity, Id coverageDetail
    ) {
        VendorPricingLineInput v = new VendorPricingLineInput();
        v.rowKey = key;
        v.claimItemId = itemId;
        v.detailType = detailType;
        v.partNumber = partNumber;
        v.adjustedQuantity = quantity;
        v.coverageLevelDetailId = coverageDetail;
        v.description = 'Customer entered description';
        return v;
    }

    private static Coverage_Level_Detail__c detail(String category, Id coverageId) {
        // Formula fields in mock sObjects are populated through deserialize,
        // not illegal DML or direct assignment to read-only fields.
        return (Coverage_Level_Detail__c) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'attributes' => new Map<String, Object>{'type' => 'Coverage_Level_Detail__c'},
                'Id' => String.valueOf(DETAIL_ID),
                'Loss_Category__c' => category,
                'Coverage_Level__c' => String.valueOf(coverageId),
                'Loss_Component__r' => new Map<String, Object>{
                    'attributes' => new Map<String, Object>{'type' => 'Loss_Component__c'},
                    'Name' => 'Transmission'
                }
            }), Coverage_Level_Detail__c.class
        );
    }

    private static Map<Id, Coverage_Level_Detail__c> details() {
        return new Map<Id, Coverage_Level_Detail__c>{
            DETAIL_ID => detail('Powertrain', COVERAGE_ID)
        };
    }

    private static Map<Id, ClaimItem> authorizedSaved() {
        return new Map<Id, ClaimItem>{
            SAVED_ID => new ClaimItem(Id = SAVED_ID)
        };
    }

    @IsTest static void unsavedPartWithPartNumberUsesPartNumberMode() {
        VendorPricingRequestContext result = VendorPricingContextService.assemble(
            header(), new Map<Id, ClaimItem>(), details(),
            new List<VendorPricingLineInput>{input('new-row-1', null, 'Part', '  ABC-123  ', 2, DETAIL_ID)}
        );
        System.assertEquals(1, result.lines.size());
        System.assertEquals(false, result.lines[0].persisted);
        System.assertEquals('ABC-123', result.lines[0].partNumber);
        System.assertEquals('PART_NUMBER', result.lines[0].searchMode);
        System.assertEquals('Powertrain', result.lines[0].lossCategory);
        System.assertEquals('Transmission', result.lines[0].lossComponentName);
        System.assertEquals(2, result.lines[0].adjustedQuantity);
    }

    @IsTest static void unsavedPartWithoutPartNumberUsesCategory() {
        VendorPricingRequestContext result = VendorPricingContextService.assemble(
            header(), new Map<Id, ClaimItem>(), details(),
            new List<VendorPricingLineInput>{input('new-2', null, 'Part', null, 1, DETAIL_ID)}
        );
        System.assertEquals('LOSS_CATEGORY', result.lines[0].searchMode);
        System.assertEquals('Powertrain', result.lines[0].lossCategory);
    }

    @IsTest static void savedAndLaborRowsAreSupportedTogether() {
        List<VendorPricingLineInput> lines = new List<VendorPricingLineInput>{
            input('saved-row', SAVED_ID, 'Part', '5555', 2, DETAIL_ID),
            input('new-labor', null, 'Labor', null, 1.5, null)
        };
        VendorPricingRequestContext result = VendorPricingContextService.assemble(
            header(), authorizedSaved(), details(), lines
        );
        System.assertEquals(2, result.lines.size());
        System.assertEquals(true, result.lines[0].persisted);
        System.assertEquals(SAVED_ID, result.lines[0].claimItemId);
        System.assertEquals('LABOR_TIME', result.lines[1].searchMode);
        System.assertEquals(1.5, result.lines[1].adjustedQuantity);
        System.assertEquals(null, result.repairShopCountry); // no silent USA fallback
    }

    @IsTest static void missingSearchInformationIsLeftForValidator() {
        VendorPricingRequestContext result = VendorPricingContextService.assemble(
            header(), new Map<Id, ClaimItem>(), new Map<Id, Coverage_Level_Detail__c>(),
            new List<VendorPricingLineInput>{input('new-3', null, 'Part', '', null, null)}
        );
        System.assertEquals('UNRESOLVED', result.lines[0].searchMode);
        System.assertEquals(null, result.lines[0].adjustedQuantity);
    }

    @IsTest static void wrongCoverageLevelIsRejected() {
        try {
            Map<Id, Coverage_Level_Detail__c> incorrect =
                new Map<Id, Coverage_Level_Detail__c>{
                    DETAIL_ID => detail('Powertrain', 'a8H000000000002')
                };
            VendorPricingContextService.assemble(header(), new Map<Id, ClaimItem>(), incorrect,
                new List<VendorPricingLineInput>{input('row', null, 'Part', null, 1, DETAIL_ID)});
            System.assert(false, 'Expected coverage check.');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assert(ex.getMessage().contains('outside the Claim coverage'));
        }
    }

    @IsTest static void inaccessibleCoverageDetailIsRejected() {
        try {
            VendorPricingContextService.assemble(header(), new Map<Id, ClaimItem>(),
                new Map<Id, Coverage_Level_Detail__c>(),
                new List<VendorPricingLineInput>{input('row', null, 'Part', null, 1, DETAIL_ID)});
            System.assert(false, 'Expected inaccessible detail.');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assert(ex.getMessage().contains('not accessible'));
        }
    }

    @IsTest static void unauthorizedSavedClaimItemIsRejected() {
        try {
            VendorPricingContextService.assemble(header(), new Map<Id, ClaimItem>(),
                new Map<Id, Coverage_Level_Detail__c>(),
                new List<VendorPricingLineInput>{input('row', SAVED_ID, 'Part', '123', 1, null)});
            System.assert(false, 'Expected unauthorized item.');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assert(ex.getMessage().contains('does not belong'));
        }
    }

    @IsTest static void invalidInputAndDuplicateKeysRejected() {
        assertInputRejected(null, new List<VendorPricingLineInput>{input('1', null, 'Part', 'a', 1, null)});
        assertInputRejected(CLAIM_ID, null);
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>());
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>{null});
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>{input('', null, 'Part', 'a', 1, null)});
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>{input(' ', null, 'Part', 'a', 1, null)});
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>{
            input('duplicate', null, 'Part', 'a', 1, null),
            input('duplicate', null, 'Part', 'b', 1, null)
        });
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>{
            input('one', SAVED_ID, 'Part', 'a', 1, null),
            input('two', SAVED_ID, 'Part', 'b', 1, null)
        });
        assertInputRejected(CLAIM_ID, new List<VendorPricingLineInput>{
            input('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                  null, 'Part', 'a', 1, null)
        });
        List<VendorPricingLineInput> tooMany = new List<VendorPricingLineInput>();
        for (Integer i = 0; i < 101; i++) {
            tooMany.add(input('key-' + i, null, 'Part', 'a', 1, null));
        }
        assertInputRejected(CLAIM_ID, tooMany);
    }

    private static void assertInputRejected(Id claimId, List<VendorPricingLineInput> selected) {
        try {
            VendorPricingContextService.checkInput(claimId, selected);
            System.assert(false, 'Expected ContextException');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest static void missingContextAndSourceMapsRejected() {
        try {
            VendorPricingContextService.assemble(null, new Map<Id, ClaimItem>(),
                new Map<Id, Coverage_Level_Detail__c>(),
                new List<VendorPricingLineInput>{input('one', null, 'Part', 'x', 1, null)});
            System.assert(false, 'Expected context error');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assert(ex.getMessage().contains('context is required'));
        }
        try {
            VendorPricingContextService.assemble(header(), null,
                new Map<Id, Coverage_Level_Detail__c>(),
                new List<VendorPricingLineInput>{input('one', null, 'Part', 'x', 1, null)});
            System.assert(false, 'Expected maps error');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assert(ex.getMessage().contains('maps are required'));
        }
    }

    @IsTest static void claimHeaderIsMappedFromSobjects() {
        Claim claimRow = (Claim) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'attributes' => new Map<String,Object>{'type' => 'Claim'},
                'Id' => String.valueOf(CLAIM_ID),
                'PolicyNumberId' => '0YT000000000001',
                'Mileage__c' => 50001,
                'Repair_Shop_Account__c' => '001000000000001',
                'PolicyNumber' => new Map<String,Object>{
                    'attributes' => new Map<String,Object>{'type'=>'InsurancePolicy'},
                    'VIN__c' => ' 1HGCM82633A004352 ',
                    'Coverage_Level__c' => String.valueOf(COVERAGE_ID)
                },
                'Repair_Shop_Account__r' => new Map<String,Object>{
                    'attributes' => new Map<String,Object>{'type'=>'Account'},
                    'Name' => ' Repair Facility ',
                    'BillingStreet' => ' 100 Main St ',
                    'BillingCity' => ' Austin ',
                    'BillingState' => ' TX ',
                    'BillingPostalCode' => ' 78724 ',
                    'BillingCountry' => null
                }
            }), Claim.class
        );
        VendorPricingRequestContext result = VendorPricingContextService.fromClaim(claimRow);
        System.assertEquals(CLAIM_ID, result.claimId);
        System.assertEquals(COVERAGE_ID, result.coverageLevelId);
        System.assertEquals('1HGCM82633A004352', result.vin);
        System.assertEquals(50001, result.currentMileage);
        System.assertEquals('Austin', result.repairShopCity);
        System.assertEquals('100 Main St', result.repairShopStreet);
        System.assertEquals('TX', result.repairShopState);
        System.assertEquals('78724', result.repairShopPostalCode);
        System.assertEquals(null, result.repairShopCountry);
        System.assertEquals(0, result.lines.size());
    }


    /** Returns a hydrated in-memory Claim compatible with fromClaim. */
    private static Claim fakeClaim(Boolean withPolicy, Boolean withShop) {
        Map<String, Object> record = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Claim' },
            'Id' => String.valueOf(CLAIM_ID),
            'Mileage__c' => 25000
        };
        if (withPolicy) {
            record.put('PolicyNumberId', '0YT000000000001');
            record.put('PolicyNumber', new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'InsurancePolicy' },
                'VIN__c' => ' 1HGCM82633A004352 ',
                'Coverage_Level__c' => String.valueOf(COVERAGE_ID)
            });
        }
        if (withShop) {
            record.put('Repair_Shop_Account__c', '001000000000001');
            record.put('Repair_Shop_Account__r', new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                'Name' => ' Repair Shop ',
                'BillingStreet' => ' 20 Elm Street ',
                'BillingCity' => ' Austin ',
                'BillingState' => ' TX ',
                'BillingPostalCode' => ' 78701 ',
                'BillingCountry' => ' USA '
            });
        }
        return (Claim) JSON.deserialize(JSON.serialize(record), Claim.class);
    }

    /**
     * Supplies only in-memory records, never queries a live QA record.
     * The service's public build() method still performs all ownership,
     * row, coverage and normalization checks.
     */
    private class FakeDataProvider extends VendorPricingContextService.DataProvider {
        public List<Claim> claims = new List<Claim>();
        public Map<Id, ClaimItem> saved = new Map<Id, ClaimItem>();
        public Map<Id, Coverage_Level_Detail__c> coverage =
            new Map<Id, Coverage_Level_Detail__c>();
        public Integer claimsCalled = 0;
        public Integer savedCalled = 0;
        public Integer detailsCalled = 0;

        public override List<Claim> loadClaim(Id claimId) {
            claimsCalled++;
            return claims;
        }
        public override Map<Id, ClaimItem> loadSavedItems(
            Set<Id> requestedSavedIds, Id claimId
        ) {
            savedCalled++;
            return saved;
        }
        public override Map<Id, Coverage_Level_Detail__c> loadDetails(
            Set<Id> detailIds
        ) {
            detailsCalled++;
            return coverage;
        }
    }

    @IsTest
    static void buildSavedAndUnsavedRowsFromInjectedSources() {
        FakeDataProvider fake = new FakeDataProvider();
        fake.claims.add(fakeClaim(true, true));
        fake.saved.put(SAVED_ID, new ClaimItem(Id = SAVED_ID));
        fake.coverage.put(DETAIL_ID, detail('Powertrain', COVERAGE_ID));
        VendorPricingContextService.providerForTest = fake;
        try {
            List<VendorPricingLineInput> selected = new List<VendorPricingLineInput>{
                input(' saved ', SAVED_ID, 'Part', ' SKU-22 ', 2, DETAIL_ID),
                input('unsaved', null, 'Part', null, 3, DETAIL_ID),
                input('labor', null, 'Labor', null, 1.5, null)
            };
            VendorPricingRequestContext context =
                VendorPricingContextService.build(CLAIM_ID, selected);
            System.assertEquals(3, context.lines.size());
            System.assertEquals('PART_NUMBER', context.lines[0].searchMode);
            System.assertEquals('saved', context.lines[0].rowKey);
            System.assertEquals(true, context.lines[0].persisted);
            System.assertEquals('LOSS_CATEGORY', context.lines[1].searchMode);
            System.assertEquals('LABOR_TIME', context.lines[2].searchMode);
            System.assertEquals('1HGCM82633A004352', context.vin);
            System.assertEquals('78701', context.repairShopPostalCode);
            System.assertEquals('USA', context.repairShopCountry);
            System.assertEquals(1, fake.claimsCalled);
            System.assertEquals(1, fake.savedCalled);
            System.assertEquals(1, fake.detailsCalled);
        } finally {
            VendorPricingContextService.providerForTest = null;
        }
    }

    @IsTest
    static void buildUnsavedWithoutLookupAvoidsExtraQueries() {
        FakeDataProvider fake = new FakeDataProvider();
        fake.claims.add(fakeClaim(false, false));
        VendorPricingContextService.providerForTest = fake;
        try {
            VendorPricingRequestContext context = VendorPricingContextService.build(
                CLAIM_ID,
                new List<VendorPricingLineInput>{
                    input('unsaved', null, 'Part', '123', 1, null)
                }
            );
            System.assertEquals(1, context.lines.size());
            System.assertEquals('PART_NUMBER', context.lines[0].searchMode);
            System.assertEquals(null, context.vin);
            System.assertEquals(null, context.coverageLevelId);
            System.assertEquals(null, context.repairShopPostalCode);
            System.assertEquals(1, fake.claimsCalled);
            System.assertEquals(0, fake.savedCalled);
            System.assertEquals(0, fake.detailsCalled);
        } finally {
            VendorPricingContextService.providerForTest = null;
        }
    }

    @IsTest
    static void buildFailsWhenClaimIsNotAccessible() {
        FakeDataProvider fake = new FakeDataProvider();
        VendorPricingContextService.providerForTest = fake;
        try {
            try {
                VendorPricingContextService.build(CLAIM_ID,
                    new List<VendorPricingLineInput>{
                        input('row', null, 'Part', 'X', 1, null)
                    });
                System.assert(false, 'Missing Claim must throw.');
            } catch (VendorPricingContextService.ContextException ex) {
                System.assert(ex.getMessage().contains('Claim not found'));
            }
        } finally {
            VendorPricingContextService.providerForTest = null;
        }
    }

    @IsTest
    static void buildFailsWhenSavedItemDoesNotBelongToClaim() {
        FakeDataProvider fake = new FakeDataProvider();
        fake.claims.add(fakeClaim(true, false));
        VendorPricingContextService.providerForTest = fake;
        try {
            try {
                VendorPricingContextService.build(CLAIM_ID,
                    new List<VendorPricingLineInput>{
                        input('saved', SAVED_ID, 'Part', 'X', 1, null)
                    });
                System.assert(false, 'Missing saved row must throw.');
            } catch (VendorPricingContextService.ContextException ex) {
                System.assert(ex.getMessage().contains('does not belong'));
            }
            System.assertEquals(1, fake.savedCalled);
            System.assertEquals(0, fake.detailsCalled);
        } finally {
            VendorPricingContextService.providerForTest = null;
        }
    }

    @IsTest
    static void buildFailsForMissingCoverageDetail() {
        FakeDataProvider fake = new FakeDataProvider();
        fake.claims.add(fakeClaim(true, false));
        VendorPricingContextService.providerForTest = fake;
        try {
            try {
                VendorPricingContextService.build(CLAIM_ID,
                    new List<VendorPricingLineInput>{
                        input('unsaved', null, 'Part', null, 1, DETAIL_ID)
                    });
                System.assert(false, 'Missing Coverage Detail must throw.');
            } catch (VendorPricingContextService.ContextException ex) {
                System.assert(ex.getMessage().contains('not accessible'));
            }
            System.assertEquals(1, fake.detailsCalled);
            System.assertEquals(0, fake.savedCalled);
        } finally {
            VendorPricingContextService.providerForTest = null;
        }
    }

    @IsTest
    static void nullCategoryAndComponentFallsBackToUnresolved() {
        Coverage_Level_Detail__c minimalDetail =
            new Coverage_Level_Detail__c(Id = DETAIL_ID, Coverage_Level__c = COVERAGE_ID);
        VendorPricingRequestContext result = VendorPricingContextService.assemble(
            header(), new Map<Id, ClaimItem>(),
            new Map<Id, Coverage_Level_Detail__c>{ DETAIL_ID => minimalDetail },
            new List<VendorPricingLineInput>{ input('x', null, 'Part', null, 1, DETAIL_ID) }
        );
        System.assertEquals('UNRESOLVED', result.lines[0].searchMode);
        System.assertEquals(null, result.lines[0].lossComponentName);
        System.assertEquals(null, result.lines[0].lossCategory);
    }

    @IsTest
    static void blankCategoryAndUnexpectedDetailTypeStayUnresolved() {
        VendorPricingRequestContext result = VendorPricingContextService.assemble(
            header(), new Map<Id, ClaimItem>(), details(),
            new List<VendorPricingLineInput>{ input('x', null, 'Other', null, 1, DETAIL_ID) }
        );
        System.assertEquals('UNRESOLVED', result.lines[0].searchMode);
    }

    @IsTest
    static void actualQueryProviderReturnsNoRecordsForSyntheticIds() {
        // Covers the production USER_MODE query boundaries without relying
        // on any existing Claim/Claim Item/coverage data in QA or Production.
        VendorPricingContextService.DataProvider provider =
            new VendorPricingContextService.DataProvider();
        System.assertEquals(0, provider.loadClaim(CLAIM_ID).size());
        System.assertEquals(0,
            provider.loadSavedItems(new Set<Id>{SAVED_ID}, CLAIM_ID).size());

        Id candidateDetailId = Id.valueOf(
            Coverage_Level_Detail__c.SObjectType.getDescribe().getKeyPrefix() +
            '000000000001'
        );
        System.assertEquals(0,
            provider.loadDetails(new Set<Id>{candidateDetailId}).size());
    }

    @IsTest
    static void defaultProviderThrowsForNonexistentClaim() {
        // Covers the public entry point's real query provider path.
        VendorPricingContextService.providerForTest = null;
        try {
            VendorPricingContextService.build(CLAIM_ID,
                new List<VendorPricingLineInput>{
                    input('row', null, 'Part', 'X', 1, null)
                });
            System.assert(false, 'Expected non-existing Claim.');
        } catch (VendorPricingContextService.ContextException ex) {
            System.assert(ex.getMessage().contains('Claim not found'));
        }
    }

}