/**
 * Checks the shared pricing inputs produced by VendorPricingContextService.
 * Endpoint-specific field formats, mappings and eligibility are checked downstream.
 */
public with sharing class VendorPricingValidationService {
    private static final Pattern VIN_PATTERN = Pattern.compile('(?i)[A-HJ-NPR-Z0-9]{17}');

    public class Issue {
        public String code;
        public String field;
        public String message;

        public Issue(String code, String field, String message) {
            this.code = code;
            this.field = field;
            this.message = message;
        }
    }

    public class LineResult {
        public String rowKey;
        public List<Issue> issues = new List<Issue>();

        public LineResult(String rowKey) {
            this.rowKey = rowKey;
        }
    }

    public class Result {
        public List<Issue> requestIssues = new List<Issue>();
        public List<LineResult> lineResults = new List<LineResult>();
        public List<String> validRowKeys = new List<String>();
    }

    public static Result validate(VendorPricingRequestContext context) {
        Result result = new Result();
        if (context == null) {
            result.requestIssues.add(new Issue(
                'CONTEXT_REQUIRED', 'context', 'Build the Claim pricing context first.'
            ));
            return result;
        }
        if (context.lines == null || context.lines.isEmpty()) {
            result.requestIssues.add(new Issue(
                'LINES_REQUIRED', 'lines', 'Select at least one Claim Item for pricing.'
            ));
            return result;
        }

        validateHeader(context, result.requestIssues);
        Boolean headerValid = result.requestIssues.isEmpty();

        for (VendorPricingLineContext line : context.lines) {
            LineResult lineResult = validateLine(line);
            result.lineResults.add(lineResult);
            if (headerValid && lineResult.issues.isEmpty()) {
                result.validRowKeys.add(lineResult.rowKey);
            }
        }
        return result;
    }

    private static void validateHeader(VendorPricingRequestContext context, List<Issue> issues) {
        if (context.claimId == null) {
            issues.add(new Issue('CLAIM_REQUIRED', 'claimId', 'Select a Claim for pricing.'));
        }
        if (String.isBlank(context.vin)) {
            issues.add(new Issue('VIN_REQUIRED', 'vin', 'Enter the VIN on the Contract.'));
        } else if (!VIN_PATTERN.matcher(context.vin.trim()).matches()) {
            issues.add(new Issue(
                'VIN_INVALID', 'vin',
                'Enter a 17-character VIN using digits and letters other than I, O and Q.'
            ));
        }

        Decimal mileage = context.currentMileage;
        if (mileage != null && (mileage < 0 || mileage > mileage.setScale(0, System.RoundingMode.DOWN))) {
            issues.add(new Issue(
                'MILEAGE_INVALID', 'currentMileage',
                'Enter current mileage as a whole number of zero or greater.'
            ));
        }

        if (context.repairShopAccountId == null) {
            issues.add(new Issue(
                'REPAIR_SHOP_REQUIRED', 'repairShopAccountId', 'Select a Repair Shop on the Claim.'
            ));
            return;
        }

        requireAddressField(issues, context.repairShopStreet,
            'REPAIR_SHOP_STREET_REQUIRED', 'repairShopStreet', 'billing street');
        requireAddressField(issues, context.repairShopCity,
            'REPAIR_SHOP_CITY_REQUIRED', 'repairShopCity', 'billing city');
        requireAddressField(issues, context.repairShopState,
            'REPAIR_SHOP_STATE_REQUIRED', 'repairShopState', 'billing state');
        requireAddressField(issues, context.repairShopPostalCode,
            'REPAIR_SHOP_ZIP_REQUIRED', 'repairShopPostalCode', 'billing ZIP code');
    }

    private static void requireAddressField(
        List<Issue> issues, String value, String code, String field, String label
    ) {
        if (String.isBlank(value)) {
            issues.add(new Issue(code, field, 'Enter the ' + label + ' on the Repair Shop Account.'));
        }
    }

    private static LineResult validateLine(VendorPricingLineContext line) {
        if (line == null || String.isBlank(line.rowKey)) {
            LineResult invalidLine = new LineResult(null);
            invalidLine.issues.add(new Issue(
                'ROW_KEY_REQUIRED', 'rowKey', 'Reselect the Claim Item row and try again.'
            ));
            return invalidLine;
        }

        LineResult result = new LineResult(line.rowKey);
        if (line.detailType == 'Part') {
            validatePart(line, result.issues);
        } else if (line.detailType != 'Labor') {
            result.issues.add(new Issue(
                'DETAIL_TYPE_UNSUPPORTED', 'detailType', 'Select Part or Labor for pricing.'
            ));
        }
        // Labor Time is supplied by the vendor lookup. Existing hours are irrelevant here.
        return result;
    }

    private static void validatePart(VendorPricingLineContext line, List<Issue> issues) {
        Decimal quantity = line.adjustedQuantity;
        if (quantity == null) {
            issues.add(new Issue(
                'PART_QUANTITY_REQUIRED', 'adjustedQuantity', 'Enter Adjusted Quantity for this part.'
            ));
        } else if (quantity <= 0 || quantity > quantity.setScale(0, System.RoundingMode.DOWN)) {
            issues.add(new Issue(
                'PART_QUANTITY_INVALID', 'adjustedQuantity',
                'Enter Adjusted Quantity as a positive whole number.'
            ));
        }

        if (String.isBlank(line.partNumber) && String.isBlank(line.lossCategory)) {
            issues.add(new Issue(
                'PART_SEARCH_INPUT_REQUIRED', 'searchMode',
                'Enter a Part Number or select a Loss Component with a Loss Category.'
            ));
        }
    }
}