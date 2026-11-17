@IsTest
private class VendorPricingValidationServiceTest {
    private static final String VALID_VIN = '1HGCM82633A004352';

    private static VendorPricingRequestContext validHeader() {
        VendorPricingRequestContext context = new VendorPricingRequestContext();
        context.claimId = (Id)(Claim.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        context.vin = VALID_VIN;
        context.repairShopAccountId = '001000000000001';
        context.repairShopStreet = '100 Main St';
        context.repairShopCity = 'Los Angeles';
        context.repairShopState = 'CA';
        context.repairShopPostalCode = '90001';
        return context;
    }

    private static VendorPricingLineContext part(String rowKey, Decimal quantity) {
        VendorPricingLineContext line = new VendorPricingLineContext();
        line.rowKey = rowKey;
        line.detailType = 'Part';
        line.partNumber = 'ABC-123';
        line.adjustedQuantity = quantity;
        line.searchMode = 'PART_NUMBER';
        return line;
    }

    private static List<String> codes(List<VendorPricingValidationService.Issue> issues) {
        List<String> result = new List<String>();
        for (VendorPricingValidationService.Issue issue : issues) {
            result.add(issue.code);
        }
        return result;
    }

    @IsTest
    static void acceptsSavedPartAndUnsavedCategoryFallback() {
        VendorPricingRequestContext context = validHeader();
        context.vin = '  ' + VALID_VIN.toLowerCase() + '  ';
        context.repairShopCountry = ' ';

        VendorPricingLineContext saved = part('saved', 2.00);
        saved.claimItemId = (Id)(ClaimItem.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        saved.persisted = true;
        saved.lossCategory = 'Brakes';
        context.lines.add(saved);

        VendorPricingLineContext draft = part('draft', 1);
        draft.partNumber = '  ';
        draft.persisted = false;
        draft.lossCategory = 'Cooling';
        draft.searchMode = 'LOSS_CATEGORY';
        context.lines.add(draft);

        String originalContext = JSON.serialize(context);
        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'saved', 'draft'}, result.validRowKeys);
        System.assertEquals(0, result.requestIssues.size());
        System.assertEquals(2, result.lineResults.size());
        System.assertEquals(0, result.lineResults[0].issues.size());
        System.assertEquals(0, result.lineResults[1].issues.size());
        System.assertEquals(originalContext, JSON.serialize(context), 'Validation should leave the input intact.');
    }

    @IsTest
    static void preservesValidRowsAndReportsAllIssuesForInvalidRows() {
        VendorPricingRequestContext context = validHeader();
        VendorPricingLineContext incomplete = part('incomplete', null);
        incomplete.partNumber = '  ';
        incomplete.lossCategory = '  ';
        incomplete.searchMode = 'UNRESOLVED';
        VendorPricingLineContext inspection = part('inspection', 1);
        inspection.detailType = 'Inspection';
        context.lines.addAll(new List<VendorPricingLineContext>{
            part('first', 1), incomplete, inspection, part('last', 2)
        });

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'first', 'last'}, result.validRowKeys);
        System.assertEquals(0, result.requestIssues.size());
        System.assertEquals('incomplete', result.lineResults[1].rowKey);
        System.assertEquals(new List<String>{'PART_QUANTITY_REQUIRED', 'PART_SEARCH_INPUT_REQUIRED'},
            codes(result.lineResults[1].issues));
        System.assertEquals('adjustedQuantity', result.lineResults[1].issues[0].field);
        System.assertEquals('inspection', result.lineResults[2].rowKey);
        System.assertEquals(new List<String>{'DETAIL_TYPE_UNSUPPORTED'}, codes(result.lineResults[2].issues));
    }

    @IsTest
    static void rejectsNonPositiveOrFractionalPartQuantity() {
        VendorPricingRequestContext context = validHeader();
        context.lines.addAll(new List<VendorPricingLineContext>{
            part('zero', 0), part('negative', -1), part('fraction', 1.25), part('whole', 3.00)
        });

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'whole'}, result.validRowKeys);
        for (Integer index = 0; index < 3; index++) {
            System.assertEquals(new List<String>{'PART_QUANTITY_INVALID'},
                codes(result.lineResults[index].issues), result.lineResults[index].rowKey);
        }
    }

    @IsTest
    static void acceptsLaborBeforeHoursAreReturned() {
        VendorPricingRequestContext context = validHeader();
        Integer index = 0;
        for (Decimal hours : new List<Decimal>{null, 0, 1.25}) {
            VendorPricingLineContext line = new VendorPricingLineContext();
            line.rowKey = 'labor-' + index;
            line.detailType = 'Labor';
            line.searchMode = 'LABOR_TIME';
            line.adjustedQuantity = hours;
            context.lines.add(line);
            index++;
        }

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'labor-0', 'labor-1', 'labor-2'}, result.validRowKeys);
        System.assertEquals(0, result.requestIssues.size());
    }

    @IsTest
    static void rejectsMissingOrMalformedVins() {
        VendorPricingRequestContext context = validHeader();
        context.lines.add(part('part', 1));

        context.vin = ' ';
        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);
        System.assertEquals(new List<String>{'VIN_REQUIRED'}, codes(result.requestIssues));
        System.assertEquals(0, result.validRowKeys.size());

        for (String invalidVin : new List<String>{
            '1HGCM82633A00435', '1HGCM82633A0043522', '1HGCM82633A-04352',
            '1IGCM82633A004352', '1OGCM82633A004352', '1QGCM82633A004352'
        }) {
            context.vin = invalidVin;
            result = VendorPricingValidationService.validate(context);
            System.assertEquals(new List<String>{'VIN_INVALID'}, codes(result.requestIssues), invalidVin);
            System.assertEquals(0, result.validRowKeys.size());
        }
    }

    @IsTest
    static void reportsEachMissingAddressFieldOnALinkedShop() {
        VendorPricingRequestContext context = validHeader();
        context.repairShopStreet = null;
        context.repairShopCity = ' ';
        context.repairShopState = null;
        context.repairShopPostalCode = null;
        context.lines.add(part('part', 1));

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{
            'REPAIR_SHOP_STREET_REQUIRED', 'REPAIR_SHOP_CITY_REQUIRED',
            'REPAIR_SHOP_STATE_REQUIRED', 'REPAIR_SHOP_ZIP_REQUIRED'
        }, codes(result.requestIssues));
        System.assertEquals('repairShopPostalCode', result.requestIssues[3].field);
        System.assertEquals(0, result.validRowKeys.size());
    }

    @IsTest
    static void requiresALinkedRepairShop() {
        VendorPricingRequestContext context = validHeader();
        context.repairShopAccountId = null;
        context.vin = null;
        context.lines.add(part('part', 1));

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'VIN_REQUIRED', 'REPAIR_SHOP_REQUIRED'},
            codes(result.requestIssues));
        System.assertEquals(0, result.validRowKeys.size());
    }

    @IsTest
    static void acceptsOptionalMileageAndChecksProvidedValues() {
        VendorPricingRequestContext context = validHeader();
        context.lines.add(part('part', 1));

        for (Decimal validMileage : new List<Decimal>{null, 0, 45000.00}) {
            context.currentMileage = validMileage;
            VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);
            System.assertEquals(new List<String>{'part'}, result.validRowKeys);
        }
        for (Decimal invalidMileage : new List<Decimal>{-1, 45000.25}) {
            context.currentMileage = invalidMileage;
            VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);
            System.assertEquals(new List<String>{'MILEAGE_INVALID'}, codes(result.requestIssues));
            System.assertEquals(0, result.validRowKeys.size());
        }
    }

    @IsTest
    static void requiresContextClaimAndSelectedRows() {
        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(null);
        System.assertEquals(new List<String>{'CONTEXT_REQUIRED'}, codes(result.requestIssues));

        VendorPricingRequestContext context = validHeader();
        result = VendorPricingValidationService.validate(context);
        System.assertEquals(new List<String>{'LINES_REQUIRED'}, codes(result.requestIssues));

        context.lines = null;
        result = VendorPricingValidationService.validate(context);
        System.assertEquals(new List<String>{'LINES_REQUIRED'}, codes(result.requestIssues));

        context.claimId = null;
        context.lines = new List<VendorPricingLineContext>{part('part', 1)};
        result = VendorPricingValidationService.validate(context);
        System.assertEquals(new List<String>{'CLAIM_REQUIRED'}, codes(result.requestIssues));
        System.assertEquals(0, result.validRowKeys.size());
    }

    @IsTest
    static void reportsRowsWithoutKeysAndKeepsOtherRows() {
        VendorPricingRequestContext context = validHeader();
        context.lines.addAll(new List<VendorPricingLineContext>{null, part('  ', 1), part('part', 1)});

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'part'}, result.validRowKeys);
        System.assertEquals(3, result.lineResults.size());
        System.assertEquals(new List<String>{'ROW_KEY_REQUIRED'}, codes(result.lineResults[0].issues));
        System.assertEquals(new List<String>{'ROW_KEY_REQUIRED'}, codes(result.lineResults[1].issues));
    }

    @IsTest
    static void sharedFailureBlocksAllRowsWhileKeepingRowDiagnostics() {
        VendorPricingRequestContext context = validHeader();
        context.repairShopPostalCode = null;
        context.lines.addAll(new List<VendorPricingLineContext>{part('valid', 1), part('invalid', 0)});

        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(new List<String>{'REPAIR_SHOP_ZIP_REQUIRED'}, codes(result.requestIssues));
        System.assertEquals(0, result.validRowKeys.size());
        System.assertEquals(0, result.lineResults[0].issues.size());
        System.assertEquals(new List<String>{'PART_QUANTITY_INVALID'}, codes(result.lineResults[1].issues));
    }

    @IsTest
    static void validatesOneHundredRowsInOrderWithoutIo() {
        VendorPricingRequestContext context = validHeader();
        List<String> expectedRowKeys = new List<String>();
        for (Integer index = 0; index < 100; index++) {
            String rowKey = 'row-' + index;
            expectedRowKeys.add(rowKey);
            context.lines.add(part(rowKey, 1));
        }

        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer calloutsBefore = Limits.getCallouts();
        VendorPricingValidationService.Result result = VendorPricingValidationService.validate(context);

        System.assertEquals(expectedRowKeys, result.validRowKeys);
        System.assertEquals(100, result.lineResults.size());
        System.assertEquals(queriesBefore, Limits.getQueries());
        System.assertEquals(dmlBefore, Limits.getDmlStatements());
        System.assertEquals(calloutsBefore, Limits.getCallouts());
    }
}