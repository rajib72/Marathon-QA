@IsTest(SeeAllData=false)
private class ContractAllocationUtilityCtrlTest {

    private static final String INCLUDE_ALL = 'Include All';
    private static final String PRODUCT = 'UT Product';
    private static final String CARRIER = 'UT Carrier';
    private static final String STATE_VALUE = 'TX';
    private static final String OPTION_VALUE = 'Standard';
    private static final Integer TERM_MONTHS = 12;

    // Program_Code__c is limited to 10 characters in QA.
    // Generate a deterministic, unique value within that limit for each test context.
    private static Integer programCodeSequence = 0;
    private static Integer contractNumberSequence = 0;

    // Some matching fields are calculated/read-only in QA. Keep deterministic
    // in-memory values for records passed directly to the controller.
    private static Map<Id, String> testStateByPolicyId =
        new Map<Id, String>();
    private static Map<Id, String> testClientProgramCodeByPolicyId =
        new Map<Id, String>();

    private class TestContext {
        Account client;
        Account lienHolder;
        Account payee;
        Coverage_Level__c coverage;
        InsurancePolicy policy;
        String product;
        String carrier;
        String stateValue;
        String optionValue;
        String clientProgramCode;
    }

    private static TestContext createContext(
        String suffix,
        Boolean isDsi,
        Integer termMonths
    ) {
        TestContext ctx = new TestContext();

        /*
         * Sold_Contract_Validation is an insert-only Contract validation.
         * For Client Account Numbers WLK/WFI/WUS, the rule explicitly
         * exempts the contract from the unrelated sold-contract field matrix.
         *
         * These tests validate Contract Allocation behavior, not Contract
         * intake completeness, so use the stable WUS business-rule branch.
         * Client__c is still populated on every policy below.
         */
        ctx.client = new Account(
            Name = 'UT Client ' + suffix,
            AccountNumber = 'WUS'
        );
        ctx.lienHolder = new Account(
            Name = 'UT Lien Holder ' + suffix,
            AccountNumber = 'FIN-' + suffix
        );
        ctx.payee = new Account(Name = 'UT Payee ' + suffix);

        // Allocation_Code__c.Client__c has a required lookup filter:
        // Account Record Type DeveloperName must equal Selling_Agency.
        ctx.client.RecordTypeId = getSellingAgencyAccountRecordTypeId();

        populateRequiredPrimitiveFields(ctx.client, null);
        populateRequiredPrimitiveFields(ctx.lienHolder, null);
        populateRequiredPrimitiveFields(ctx.payee, null);
        insert new List<Account>{ ctx.client, ctx.lienHolder, ctx.payee };

        ctx.coverage = new Coverage_Level__c();
        putIfCreateable(ctx.coverage, 'Name', 'UT Coverage ' + suffix);
        populateRequiredPrimitiveFields(ctx.coverage, null);
        insert ctx.coverage;

        ctx.product = getPreferredFieldValue(
            InsurancePolicy.SObjectType,
            'Product__c',
            PRODUCT
        );
        ctx.carrier = getPreferredFieldValue(
            InsurancePolicy.SObjectType,
            'Ins_Carrier__c',
            CARRIER
        );
        ctx.stateValue = getPreferredFieldValue(
            InsurancePolicy.SObjectType,
            'Original_State__c',
            STATE_VALUE
        );
        ctx.optionValue = getPreferredFieldValue(
            InsurancePolicy.SObjectType,
            'Option_1__c',
            OPTION_VALUE
        );

        InsurancePolicy policy = new InsurancePolicy();

        putIfCreateable(policy, 'PolicyName', 'UT Policy ' + suffix);
        putIfCreateable(
            policy,
            'PolicyNumber',
            'UT-' + suffix + '-' + String.valueOf(DateTime.now().getTime())
        );
        putIfCreateable(policy, 'AccountId', ctx.client.Id);

        // NameInsuredId is required for InsurancePolicy in QA.
        // Use the test client Account as the named insured.
        putIfCreateable(policy, 'NameInsuredId', ctx.client.Id);

        putIfCreateable(policy, 'EffectiveFrom', Date.today().addDays(-10));
        putIfCreateable(policy, 'EffectiveTo', Date.today().addYears(1));
        putPreferredPicklist(policy, 'Status', 'Active');

        policy.Client__c = ctx.client.Id;
        policy.Lien_Holder__c = ctx.lienHolder.Id;
        policy.Coverage_Level__c = ctx.coverage.Id;
        policy.Product__c = ctx.product;
        policy.Ins_Carrier__c = ctx.carrier;
        putIfCreateable(policy, 'Original_State__c', ctx.stateValue);
        policy.Contract_Term_Months__c = termMonths;
        policy.Option_1__c = ctx.optionValue;
        policy.Sale_Date__c = Date.today();
        policy.Legacy_Source__c = isDsi
            ? 'DSI'
            : getNonDsiLegacySourceValue();
        String testProgramCode = nextProgramCode();
        policy.Program_Code__c = testProgramCode;
        ctx.clientProgramCode =
            'CP' + testProgramCode.substring(2);

        putIfCreateable(
            policy,
            'Client_Program_Code__c',
            ctx.clientProgramCode
        );
        policy.Reserve__c = 635;
        policy.Funded_Reserve__c = 0;
        policy.DLRS_Total_Funded_Amount_from_Funding__c = 0;
        policy.Premium_Tax_Old__c = 11.11;
        policy.MBI_Seller_Commission__c = 22.22;
        policy.OT_Allocation__c = 33.33;

        putIfCreateable(policy, 'Written_Reserve__c', 635);
        populateRequiredPrimitiveFields(policy, ctx.client.Id);

        // QA validation and DLRS-triggered contract updates require both
        // Sale Date and Sale Odometer to be populated.
        applyRequiredContractValidationFields(policy);

        // Some QA automation validates a separate Contract Number field.
        // Override every writable Contract/Policy Number field with a unique
        // value after generic required-field population.
        applyUniqueContractIdentifiers(policy);

        insert policy;

        testStateByPolicyId.put(policy.Id, ctx.stateValue);
        testClientProgramCodeByPolicyId.put(
            policy.Id,
            ctx.clientProgramCode
        );

        ctx.policy = reloadPolicy(policy.Id);
        return ctx;
    }

    private static Id getSellingAgencyAccountRecordTypeId() {
        Schema.RecordTypeInfo sellingAgencyRecordType =
            Account.SObjectType
                .getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get('Selling_Agency');

        System.assertNotEquals(
            null,
            sellingAgencyRecordType,
            'Required Account record type Selling_Agency was not found.'
        );

        return sellingAgencyRecordType.getRecordTypeId();
    }

    private static String nextProgramCode() {
        programCodeSequence++;
        return 'UT' + String.valueOf(programCodeSequence).leftPad(8, '0');
    }

    private static InsurancePolicy reloadPolicy(Id policyId) {
        InsurancePolicy policy = [
            SELECT Id,
                   Name,
                   Client__c,
                   Lien_Holder__c,
                   Lien_Holder__r.AccountNumber,
                   Coverage_Level__c,
                   Coverage_Level__r.Name,
                   Product__c,
                   Ins_Carrier__c,
                   Original_State__c,
                   Contract_Term_Months__c,
                   Option_1__c,
                   Sale_Date__c,
                   Legacy_Source__c,
                   Program_Code__c,
                   Client_Program_Code__c,
                   Reserve__c,
                   Written_Reserve__c,
                   Funded_Reserve__c,
                   DLRS_Total_Funded_Amount_from_Funding__c,
                   Reinstatement_Date__c,
                   Admin_Cost__c,
                   Premium_Tax_Old__c,
                   MBI_Seller_Commission__c,
                   OT_Allocation__c
            FROM InsurancePolicy
            WHERE Id = :policyId
        ];

        return applyCalculatedTestFieldOverrides(policy);
    }

    private static InsurancePolicy applyCalculatedTestFieldOverrides(
        InsurancePolicy policy
    ) {
        if (policy == null || policy.Id == null) {
            return policy;
        }

        Map<String, Object> serializedPolicy =
            (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(policy)
            );

        if (testStateByPolicyId.containsKey(policy.Id)) {
            serializedPolicy.put(
                'Original_State__c',
                testStateByPolicyId.get(policy.Id)
            );
        }

        if (testClientProgramCodeByPolicyId.containsKey(policy.Id)) {
            serializedPolicy.put(
                'Client_Program_Code__c',
                testClientProgramCodeByPolicyId.get(policy.Id)
            );
        }

        return (InsurancePolicy) JSON.deserialize(
            JSON.serialize(serializedPolicy),
            InsurancePolicy.class
        );
    }

    private static Allocation_Code__c createAllocationCode(
        TestContext ctx,
        String codeName,
        Integer priority,
        String descriptor,
        String allocationType,
        Decimal maxAmount
    ) {
        return createAllocationCode(
            ctx,
            codeName,
            priority,
            descriptor,
            allocationType,
            maxAmount,
            'Auto'
        );
    }

    private static Allocation_Code__c createAllocationCode(
        TestContext ctx,
        String codeName,
        Integer priority,
        String descriptor,
        String allocationType,
        Decimal maxAmount,
        String contractType
    ) {
        Allocation_Code__c code = new Allocation_Code__c(
            Name = codeName,
            Priority__c = priority,
            Allocation_Type__c = allocationType,
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c = Date.today().addDays(30),
            Insurance_Carrier__c = INCLUDE_ALL,
            States__c = INCLUDE_ALL,
            Allocation_Amount__c = String.valueOf(maxAmount),
            Descriptor__c = descriptor,
            is_Expense__c = false,
            Client__c = ctx.client.Id,
            Coverage_Level__c = ctx.coverage.Name,
            Product__c = ctx.product,
            Contract_Type__c = contractType,
            Payee__c = ctx.payee.Id,
            Term_Months__c = INCLUDE_ALL,
            Option__c = INCLUDE_ALL
        );
        populateRequiredPrimitiveFields(code, null);
        insert code;
        return code;
    }

    private static Allocation_Code__c createReserve8004(TestContext ctx) {
        Allocation_Code__c reserveCode = new Allocation_Code__c(
            Name = '8004',
            Priority__c = 99,
            Allocation_Type__c = 'Reserve Split',
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c = Date.today().addDays(30),
            Insurance_Carrier__c = INCLUDE_ALL,
            States__c = INCLUDE_ALL,
            Allocation_Amount__c = '999999',
            Descriptor__c = 'Reserve',
            is_Expense__c = false,
            Client__c = ctx.client.Id,
            Coverage_Level__c = ctx.coverage.Name,
            Product__c = ctx.product,
            Contract_Type__c = 'Auto',
            Payee__c = ctx.payee.Id,
            Term_Months__c = INCLUDE_ALL,
            Option__c = INCLUDE_ALL
        );
        populateRequiredPrimitiveFields(reserveCode, null);
        insert reserveCode;
        return reserveCode;
    }

    private static Funding__c createFunding(
        Id contractId,
        Decimal amount,
        Boolean processed
    ) {
        Funding__c funding = new Funding__c(
            Contract__c = contractId,
            Funded_Amount__c = amount
        );
        if (processed) {
            funding.Time_Processed__c = System.now();
        }
        populateRequiredPrimitiveFields(funding, null);
        insert funding;
        return funding;
    }

    private static Allocation__c createAllocation(
        Id contractId,
        Id allocationCodeId,
        Decimal amount,
        String descriptor,
        String paymentReturn,
        Decimal maxAmount,
        Id payeeId,
        String feeLabel
    ) {
        Allocation__c allocation = new Allocation__c(
            Contract__c = contractId,
            Allocation_Code__c = allocationCodeId,
            Allocation_Amount__c = amount,
            Descriptor__c = descriptor,
            Payment_Return__c = paymentReturn,
            Max_Allocation_Amount__c = maxAmount,
            Payee__c = payeeId,
            is_Expense__c = false,
            Fee_Label_for_Summary_Reporting__c = feeLabel
        );
        populateRequiredPrimitiveFields(allocation, null);
        insert allocation;
        return allocation;
    }

    private static Funding__c reloadFunding(Id fundingId) {
        return [
            SELECT Id,
                   Contract__c,
                   Funded_Amount__c,
                   Time_Processed__c,
                   CreatedDate
            FROM Funding__c
            WHERE Id = :fundingId
        ];
    }

    private static Allocation__c reloadAllocation(Id allocationId) {
        return [
            SELECT Id,
                   Contract__c,
                   Allocation_Code__c,
                   Allocation_Code__r.Name,
                   Allocation_Amount__c,
                   Descriptor__c,
                   Payment_Return__c,
                   Payee__c,
                   is_Expense__c,
                   Max_Allocation_Amount__c,
                   Fee_Label_for_Summary_Reporting__c,
                   CreatedDate
            FROM Allocation__c
            WHERE Id = :allocationId
        ];
    }

    private static void injectFieldMappings(
        Map<String, String> descriptorToField
    ) {
        List<ContractFundingAllocationFieldMapping__mdt> rows =
            new List<ContractFundingAllocationFieldMapping__mdt>();

        for (String descriptor : descriptorToField.keySet()) {
            rows.add(
                new ContractFundingAllocationFieldMapping__mdt(
                    DeveloperName =
                        'UT_' + descriptor.replaceAll('[^a-zA-Z0-9]', '_'),
                    MasterLabel = 'UT ' + descriptor,
                    Descriptor__c = descriptor,
                    Contract_Field_API__c = descriptorToField.get(descriptor)
                )
            );
        }

        ContractAllocationUtilityCtrl.testFieldMappings = rows;
    }

    private static void clearInjectedMetadata() {
        programCodeSequence = 0;
        contractNumberSequence = 0;
        testStateByPolicyId.clear();
        testClientProgramCodeByPolicyId.clear();
        ContractAllocationUtilityCtrl.testRatingRecords = null;
        ContractAllocationUtilityCtrl.testPriorityRecords = null;
        ContractAllocationUtilityCtrl.testFieldMappings = null;
    }

    private static void putIfCreateable(
        SObject record,
        String fieldApiName,
        Object value
    ) {
        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult dfr = fields.get(fieldApiName).getDescribe();
        if (dfr.isCreateable() && !dfr.isCalculated() && value != null) {
            record.put(fieldApiName, value);
        }
    }

    private static void putBooleanIfCreateable(
        SObject record,
        String fieldApiName,
        Boolean value
    ) {
        if (
            record == null ||
            String.isBlank(fieldApiName) ||
            value == null
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult dfr =
            fields.get(fieldApiName).getDescribe();

        if (
            dfr.isCreateable() &&
            !dfr.isCalculated() &&
            dfr.getType() == Schema.DisplayType.Boolean
        ) {
            record.put(fieldApiName, value);
        }
    }

    private static void configureAccountRole(
        Account accountRecord,
        String roleName
    ) {
        if (accountRecord == null || String.isBlank(roleName)) {
            return;
        }

        List<String> candidates = getAccountRoleCandidates(roleName);
        Id matchingRecordTypeId = findMatchingAccountRecordTypeId(candidates);

        if (matchingRecordTypeId != null) {
            accountRecord.RecordTypeId = matchingRecordTypeId;
        }

        // Populate only exact active picklist matches. No fallback value is
        // used here because an unrelated value could violate another filter.
        for (String fieldApiName : new List<String>{
            'Type',
            'Account_Type__c',
            'AccountType__c',
            'Account_Category__c',
            'Category__c',
            'Role__c',
            'Account_Role__c'
        }) {
            putMatchingPicklistValue(
                accountRecord,
                fieldApiName,
                candidates
            );
        }

        putMatchingPicklistValue(
            accountRecord,
            'Status__c',
            new List<String>{ 'Active', 'Enabled' }
        );

        // These candidate fields are not guaranteed to be Checkbox fields in
        // every org. Set them only when the actual field type is Boolean.
        putBooleanIfCreateable(accountRecord, 'Active__c', true);
        putBooleanIfCreateable(accountRecord, 'Is_Active__c', true);

        String normalizedRole = normalizeIdentifier(roleName);
        if (normalizedRole == 'client') {
            putBooleanIfCreateable(accountRecord, 'Is_Client__c', true);
            putBooleanIfCreateable(accountRecord, 'IsClient__c', true);
        } else if (normalizedRole == 'payee') {
            putBooleanIfCreateable(accountRecord, 'Is_Payee__c', true);
            putBooleanIfCreateable(accountRecord, 'IsPayee__c', true);
        } else if (normalizedRole == 'lienholder') {
            putBooleanIfCreateable(
                accountRecord,
                'Is_Lien_Holder__c',
                true
            );
            putBooleanIfCreateable(
                accountRecord,
                'IsLienHolder__c',
                true
            );
        }
    }

    private static List<String> getAccountRoleCandidates(String roleName) {
        String normalizedRole = normalizeIdentifier(roleName);

        if (normalizedRole == 'client') {
            return new List<String>{
                'Client',
                'Client Account',
                'Client_Account',
                'Customer',
                'Customer Account'
            };
        }

        if (normalizedRole == 'payee') {
            return new List<String>{
                'Payee',
                'Vendor',
                'Provider'
            };
        }

        if (normalizedRole == 'lienholder') {
            return new List<String>{
                'Lien Holder',
                'Lien_Holder',
                'Lender',
                'Finance Company',
                'Finance'
            };
        }

        return new List<String>{ roleName };
    }

    private static Id findMatchingAccountRecordTypeId(
        List<String> candidates
    ) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }

        List<Schema.RecordTypeInfo> recordTypeInfos =
            Account.SObjectType.getDescribe().getRecordTypeInfos();

        // Prefer an exact normalized match first.
        for (String candidate : candidates) {
            String normalizedCandidate = normalizeIdentifier(candidate);

            for (Schema.RecordTypeInfo info : recordTypeInfos) {
                if (!info.isAvailable() || info.isMaster()) {
                    continue;
                }

                if (
                    normalizeIdentifier(info.getName()) == normalizedCandidate ||
                    normalizeIdentifier(info.getDeveloperName()) ==
                        normalizedCandidate
                ) {
                    return info.getRecordTypeId();
                }
            }
        }

        // Controlled fallback for names such as Marathon_Client_Account.
        for (String candidate : candidates) {
            String normalizedCandidate = normalizeIdentifier(candidate);

            for (Schema.RecordTypeInfo info : recordTypeInfos) {
                if (!info.isAvailable() || info.isMaster()) {
                    continue;
                }

                String normalizedName = normalizeIdentifier(info.getName());
                String normalizedDeveloperName =
                    normalizeIdentifier(info.getDeveloperName());

                if (
                    normalizedName.contains(normalizedCandidate) ||
                    normalizedDeveloperName.contains(normalizedCandidate)
                ) {
                    return info.getRecordTypeId();
                }
            }
        }

        return null;
    }

    private static void putMatchingPicklistValue(
        SObject record,
        String fieldApiName,
        List<String> preferredValues
    ) {
        if (
            record == null ||
            String.isBlank(fieldApiName) ||
            preferredValues == null ||
            preferredValues.isEmpty()
        ) {
            return;
        }

        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult dfr =
            fields.get(fieldApiName).getDescribe();

        if (
            !dfr.isCreateable() ||
            dfr.isCalculated() ||
            (
                dfr.getType() != Schema.DisplayType.Picklist &&
                dfr.getType() != Schema.DisplayType.MultiPicklist
            )
        ) {
            return;
        }

        for (String preferredValue : preferredValues) {
            String normalizedPreferred =
                normalizeIdentifier(preferredValue);

            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (
                    entry.isActive() &&
                    normalizeIdentifier(entry.getValue()) ==
                        normalizedPreferred
                ) {
                    record.put(fieldApiName, entry.getValue());
                    return;
                }
            }
        }
    }

    private static void applyRequiredContractValidationFields(
        InsurancePolicy policy
    ) {
        if (policy == null) {
            return;
        }

        // The org contains both standard and custom Sale Date variants.
        putIfCreateable(policy, 'SaleDate', Date.today());
        putIfCreateable(policy, 'Sale_Date__c', Date.today());

        Map<String, Schema.SObjectField> fields =
            InsurancePolicy.SObjectType.getDescribe().fields.getMap();

        for (String fieldApiName : fields.keySet()) {
            Schema.DescribeFieldResult dfr =
                fields.get(fieldApiName).getDescribe();

            if (
                !dfr.isCreateable() ||
                dfr.isCalculated() ||
                policy.get(fieldApiName) != null
            ) {
                continue;
            }

            String normalizedApiName =
                normalizeIdentifier(fieldApiName);
            String normalizedLabel =
                normalizeIdentifier(dfr.getLabel());

            Boolean isSaleOdometerField =
                normalizedApiName == 'saleodometer' ||
                normalizedLabel == 'saleodometer' ||
                normalizedApiName.contains('saleodometer') ||
                normalizedLabel.contains('saleodometer');

            if (!isSaleOdometerField) {
                continue;
            }

            Schema.DisplayType fieldType = dfr.getType();

            if (fieldType == Schema.DisplayType.Integer) {
                policy.put(fieldApiName, 1000);
            } else if (
                fieldType == Schema.DisplayType.Currency ||
                fieldType == Schema.DisplayType.Double ||
                fieldType == Schema.DisplayType.Percent
            ) {
                policy.put(fieldApiName, Decimal.valueOf('1000'));
            } else if (
                fieldType == Schema.DisplayType.String ||
                fieldType == Schema.DisplayType.TextArea ||
                fieldType == Schema.DisplayType.EncryptedString
            ) {
                policy.put(fieldApiName, '1000');
            } else if (
                fieldType == Schema.DisplayType.Picklist ||
                fieldType == Schema.DisplayType.MultiPicklist
            ) {
                for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                    if (entry.isActive()) {
                        policy.put(fieldApiName, entry.getValue());
                        break;
                    }
                }
            }
        }
    }

    private static void applyUniqueContractIdentifiers(
        InsurancePolicy policy
    ) {
        if (policy == null) {
            return;
        }

        contractNumberSequence++;
        String rawIdentifier =
            'UTC' +
            String.valueOf(contractNumberSequence).leftPad(7, '0');

        Map<String, Schema.SObjectField> fields =
            InsurancePolicy.SObjectType.getDescribe().fields.getMap();

        for (String fieldApiName : fields.keySet()) {
            Schema.DescribeFieldResult dfr =
                fields.get(fieldApiName).getDescribe();

            if (
                !dfr.isCreateable() ||
                dfr.isCalculated() ||
                dfr.getType() != Schema.DisplayType.String
            ) {
                continue;
            }

            String normalizedApiName =
                normalizeIdentifier(fieldApiName);
            String normalizedLabel =
                normalizeIdentifier(dfr.getLabel());

            Boolean isContractIdentifier =
                normalizedApiName == 'policynumber' ||
                normalizedApiName == 'contractnumber' ||
                normalizedApiName == 'contractno' ||
                normalizedApiName.contains('contractnumber') ||
                normalizedLabel == 'policynumber' ||
                normalizedLabel == 'contractnumber' ||
                normalizedLabel == 'contractno' ||
                normalizedLabel.contains('contractnumber');

            if (!isContractIdentifier) {
                continue;
            }

            String safeIdentifier = rawIdentifier;
            Integer maxLength = dfr.getLength();

            if (
                maxLength > 0 &&
                safeIdentifier.length() > maxLength
            ) {
                safeIdentifier = safeIdentifier.substring(
                    safeIdentifier.length() - maxLength
                );
            }

            policy.put(fieldApiName, safeIdentifier);
        }
    }

    private static String normalizeIdentifier(String value) {
        return String.isBlank(value)
            ? ''
            : value.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();
    }

    private static String getNonDsiLegacySourceValue() {
        Map<String, Schema.SObjectField> fields =
            InsurancePolicy.SObjectType.getDescribe().fields.getMap();

        if (!fields.containsKey('Legacy_Source__c')) {
            return 'UT';
        }

        Schema.DescribeFieldResult dfr =
            fields.get('Legacy_Source__c').getDescribe();

        if (
            dfr.getType() != Schema.DisplayType.Picklist &&
            dfr.getType() != Schema.DisplayType.MultiPicklist
        ) {
            return 'UT';
        }

        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry.isActive() && entry.getValue() != 'DSI') {
                return entry.getValue();
            }
        }

        return 'UT';
    }

    private static String getPreferredFieldValue(
        Schema.SObjectType objectType,
        String fieldApiName,
        String preferred
    ) {
        Map<String, Schema.SObjectField> fields =
            objectType.getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) {
            return preferred;
        }

        Schema.DescribeFieldResult dfr = fields.get(fieldApiName).getDescribe();
        Schema.DisplayType fieldType = dfr.getType();

        if (
            fieldType != Schema.DisplayType.Picklist &&
            fieldType != Schema.DisplayType.MultiPicklist
        ) {
            return preferred;
        }

        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == preferred) {
                return preferred;
            }
        }

        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return preferred;
    }

    private static void putPreferredPicklist(
        SObject record,
        String fieldApiName,
        String preferred
    ) {
        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult dfr = fields.get(fieldApiName).getDescribe();
        if (!dfr.isCreateable() || dfr.isCalculated()) {
            return;
        }

        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == preferred) {
                record.put(fieldApiName, preferred);
                return;
            }
        }

        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry.isActive()) {
                record.put(fieldApiName, entry.getValue());
                return;
            }
        }
    }

    private static void populateRequiredPrimitiveFields(
        SObject record,
        Id defaultAccountId
    ) {
        Map<String, Schema.SObjectField> fields =
            record.getSObjectType().getDescribe().fields.getMap();

        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult dfr = fields.get(fieldName).getDescribe();

            if (
                !dfr.isCreateable() ||
                dfr.isCalculated() ||
                dfr.isDefaultedOnCreate() ||
                dfr.isNillable() ||
                record.get(fieldName) != null
            ) {
                continue;
            }

            Schema.DisplayType fieldType = dfr.getType();

            if (
                fieldType == Schema.DisplayType.String ||
                fieldType == Schema.DisplayType.TextArea ||
                fieldType == Schema.DisplayType.EncryptedString
            ) {
                record.put(fieldName, 'UT');
            } else if (fieldType == Schema.DisplayType.Boolean) {
                record.put(fieldName, false);
            } else if (fieldType == Schema.DisplayType.Date) {
                record.put(fieldName, Date.today());
            } else if (fieldType == Schema.DisplayType.DateTime) {
                record.put(fieldName, System.now());
            } else if (fieldType == Schema.DisplayType.Integer) {
                record.put(fieldName, 1);
            } else if (
                fieldType == Schema.DisplayType.Currency ||
                fieldType == Schema.DisplayType.Double ||
                fieldType == Schema.DisplayType.Percent
            ) {
                record.put(fieldName, 1);
            } else if (fieldType == Schema.DisplayType.Email) {
                record.put(fieldName, 'unit.test@example.com');
            } else if (fieldType == Schema.DisplayType.Phone) {
                record.put(fieldName, '5550000000');
            } else if (fieldType == Schema.DisplayType.Url) {
                record.put(fieldName, 'https://example.com');
            } else if (
                fieldType == Schema.DisplayType.Picklist ||
                fieldType == Schema.DisplayType.MultiPicklist
            ) {
                for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                    if (entry.isActive()) {
                        record.put(fieldName, entry.getValue());
                        break;
                    }
                }
            } else if (
                fieldType == Schema.DisplayType.Reference &&
                defaultAccountId != null
            ) {
                // Populate any required lookup that accepts Account.
                // This includes standard InsurancePolicy fields such as
                // NameInsuredId in the QA org, while avoiding incompatible
                // lookup assignments.
                for (Schema.SObjectType referenceType : dfr.getReferenceTo()) {
                    if (referenceType.getDescribe().getName() == 'Account') {
                        record.put(fieldName, defaultAccountId);
                        break;
                    }
                }
            }
        }
    }

    @IsTest
    static void testMetadataReadersAndAllocationCodeGrouping() {
        clearInjectedMetadata();

        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>{
                new Rating_Record__mdt(
                    DeveloperName = 'UT_Active_1',
                    MasterLabel = 'UT Active 1',
                    ClientProgramCode__c = 'CP-1',
                    RatingRecordID__c = 'RR-1',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                ),
                new Rating_Record__mdt(
                    DeveloperName = 'UT_Active_2',
                    MasterLabel = 'UT Active 2',
                    ClientProgramCode__c = 'CP-1',
                    RatingRecordID__c = 'RR-2',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                ),
                new Rating_Record__mdt(
                    DeveloperName = 'UT_Expired',
                    MasterLabel = 'UT Expired',
                    ClientProgramCode__c = 'CP-1',
                    RatingRecordID__c = 'RR-OLD',
                    BegDate__c = Date.today().addDays(-10),
                    EndDate__c = Date.today().addDays(-5)
                )
            };

        Map<String, List<String>> ratingMap =
            ContractAllocationUtilityCtrl.fillProgramCodeDetails(
                new Set<String>{ 'CP-1' }
            );

        System.assertEquals(1, ratingMap.size());
        System.assertEquals(
            new Set<String>{ 'RR-1', 'RR-2' },
            new Set<String>(ratingMap.get('CP-1'))
        );

        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>{
                new Allocation_Priority__mdt(
                    DeveloperName = 'UT_P1',
                    MasterLabel = 'UT P1',
                    AllocationCode__c = 'A-1',
                    Priority__c = '1',
                    FinanceCode__c = 'FIN-1'
                ),
                new Allocation_Priority__mdt(
                    DeveloperName = 'UT_P2',
                    MasterLabel = 'UT P2',
                    AllocationCode__c = 'A-2',
                    Priority__c = '2',
                    FinanceCode__c = 'OTHER'
                )
            };

        Map<String, Allocation_Priority__mdt> priorities =
            ContractAllocationUtilityCtrl.fillAllocationCodePriorityDetails(
                new Set<String>{ 'A-1', 'A-2' },
                'FIN-1'
            );

        System.assertEquals(1, priorities.size());
        System.assertEquals('1', priorities.get('A-1').Priority__c);

        List<Dealer_Cost_Allocation__c> dealerRows =
            new List<Dealer_Cost_Allocation__c>{
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RR-1',
                    AllocationCode__c = 'A-1'
                ),
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RR-1',
                    AllocationCode__c = 'A-2'
                ),
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RR-2',
                    AllocationCode__c = 'A-3'
                )
            };

        Map<String, List<String>> grouped =
            ContractAllocationUtilityCtrl.fillAllocationCodeDetails(dealerRows);

        System.assertEquals(2, grouped.size());
        System.assertEquals(
            new Set<String>{ 'A-1', 'A-2' },
            new Set<String>(grouped.get('RR-1'))
        );
        System.assertEquals(
            new List<String>{ 'A-3' },
            grouped.get('RR-2')
        );

        clearInjectedMetadata();
    }

    @IsTest
    static void testCalculateMaxAllocationAndSupplementalValues() {
        InsurancePolicy policy = new InsurancePolicy(
            Reserve__c = 77.77,
            Premium_Tax_Old__c = 11.11,
            MBI_Seller_Commission__c = 22.22,
            OT_Allocation__c = 33.33
        );

        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(null, null)
        );
        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c()
            )
        );

        System.assertEquals(
            123.45,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'NUMERIC',
                    Allocation_Amount__c = '123.45',
                    Descriptor__c = 'Admin'
                )
            )
        );

        System.assertEquals(
            77.77,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'RESERVE',
                    Allocation_Amount__c = 'Reserve',
                    Descriptor__c = 'Reserve'
                )
            )
        );

        System.assertEquals(
            11.11,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'SUPP-1',
                    Allocation_Amount__c = 'S1',
                    Descriptor__c = 'Premium Tax'
                )
            )
        );
        System.assertEquals(
            22.22,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'SUPP-2',
                    Allocation_Amount__c = 's2',
                    Descriptor__c = 'Seller Commission'
                )
            )
        );
        System.assertEquals(
            33.33,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'SUPP-3',
                    Allocation_Amount__c = 'S3',
                    Descriptor__c = 'Obligor Tax'
                )
            )
        );

        System.assertEquals(
            87.77,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'FORMULA',
                    Allocation_Amount__c = 'Reserve__c + 10',
                    Descriptor__c = 'Formula'
                )
            )
        );

        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.calculateMaxAllocation(
                policy,
                new Allocation_Code__c(
                    Name = 'BAD-FORMULA',
                    Allocation_Amount__c = 'Not_A_Field__c +',
                    Descriptor__c = 'Formula'
                )
            )
        );

        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.getSupplementalValue(
                null,
                'S1',
                'Premium Tax'
            )
        );
        System.assertEquals(
            11.11,
            ContractAllocationUtilityCtrl.getSupplementalValue(
                policy,
                'S1',
                'Premium Tax'
            )
        );
        System.assertEquals(
            22.22,
            ContractAllocationUtilityCtrl.getSupplementalValue(
                policy,
                'S2',
                'Seller Commission'
            )
        );
        System.assertEquals(
            33.33,
            ContractAllocationUtilityCtrl.getSupplementalValue(
                policy,
                'S3',
                'Obligor Tax'
            )
        );
        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.getSupplementalValue(
                policy,
                'S4',
                'Unknown'
            )
        );
    }

    @IsTest
    static void testFetchRatingVsCustomAllocationAndComparable() {
        Dealer_Cost_Allocation__c d1 = new Dealer_Cost_Allocation__c(
            AllocationCode__c = 'A-1',
            Allocation_Amount__c = 100.126
        );
        Dealer_Cost_Allocation__c d2 = new Dealer_Cost_Allocation__c(
            AllocationCode__c = 'A-2',
            Allocation_Amount__c = 50.124
        );

        Map<String, Dealer_Cost_Allocation__c> dealerMap =
            new Map<String, Dealer_Cost_Allocation__c>{
                'A-1' => d1,
                'A-2' => d2
            };

        Map<String, Allocation_Priority__mdt> priorityMap =
            new Map<String, Allocation_Priority__mdt>{
                'A-1' => new Allocation_Priority__mdt(
                    AllocationCode__c = 'A-1',
                    Priority__c = '2',
                    FinanceCode__c = 'FIN'
                ),
                'A-2' => new Allocation_Priority__mdt(
                    AllocationCode__c = 'A-2',
                    Priority__c = '1',
                    FinanceCode__c = 'FIN'
                )
            };

        List<ContractAllocationUtilityCtrl.ContractAllocation> rows =
            ContractAllocationUtilityCtrl.fetchRatingvsCustomAllocation(
                new Set<String>{ 'A-1', 'A-2', 'A-3' },
                priorityMap,
                dealerMap
            );

        System.assertEquals(3, rows.size());
        System.assertEquals('A-2', rows[0].allocationCode);
        System.assertEquals(50.12, rows[0].allocationAmount);
        System.assertEquals('A-1', rows[1].allocationCode);
        System.assertEquals(100.13, rows[1].allocationAmount);
        System.assertEquals(100000, rows[2].priority);
        System.assertEquals(0, rows[0].compareTo('not a ContractAllocation'));
        System.assertEquals(-1, rows[0].compareTo(rows[1]));
        System.assertEquals(1, rows[2].compareTo(rows[1]));

        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.roundCurrency(null)
        );
        System.assertEquals(
            1.01,
            ContractAllocationUtilityCtrl.roundCurrency(1.005)
        );
        System.assertEquals(
            'reserve',
            ContractAllocationUtilityCtrl.normalizeRecoveryValue('  Reserve ')
        );
        System.assertEquals(
            '',
            ContractAllocationUtilityCtrl.normalizeRecoveryValue(null)
        );
    }

    @IsTest
    static void testPositiveFundingStandardAndReserveSplit() {
        clearInjectedMetadata();
        TestContext ctx = createContext('POS', false, TERM_MONTHS);

        createAllocationCode(
            ctx,
            'UT-ADMIN-POS',
            1,
            'Admin',
            'Fixed',
            100
        );
        createAllocationCode(
            ctx,
            'UT-RESERVE-POS',
            2,
            'Reserve',
            'Reserve Split',
            200
        );

        injectFieldMappings(
            new Map<String, String>{ 'Admin' => 'Admin_Cost__c' }
        );
        Funding__c funding = createFunding(ctx.policy.Id, 180, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        List<Allocation__c> allocations = [
            SELECT Allocation_Amount__c,
                   Descriptor__c,
                   Payment_Return__c,
                   Allocation_Code__c,
                   Max_Allocation_Amount__c
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY Descriptor__c
        ];

        System.assertEquals(2, allocations.size());

        Map<String, Decimal> amountByDescriptor = new Map<String, Decimal>();
        for (Allocation__c row : allocations) {
            amountByDescriptor.put(row.Descriptor__c, row.Allocation_Amount__c);
            System.assertEquals('P', row.Payment_Return__c);
        }

        System.assertEquals(100, amountByDescriptor.get('Admin'));
        System.assertEquals(80, amountByDescriptor.get('Reserve'));
        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);

        InsurancePolicy refreshedPolicy = reloadPolicy(ctx.policy.Id);
        System.assertEquals(
            180,
            refreshedPolicy.DLRS_Total_Funded_Amount_from_Funding__c
        );
        System.assertEquals(80, refreshedPolicy.Funded_Reserve__c);
        System.assertEquals(100, refreshedPolicy.Admin_Cost__c);

        clearInjectedMetadata();
    }

    @IsTest
    static void testExistingAllocationIsToppedUpOnlyToMaximum() {
        clearInjectedMetadata();
        TestContext ctx = createContext('TOPUP', false, TERM_MONTHS);

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-TOPUP',
            1,
            'Admin',
            'Fixed',
            100
        );

        createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            60,
            'Admin',
            'P',
            100,
            ctx.payee.Id,
            'Admin'
        );

        Funding__c funding = createFunding(ctx.policy.Id, 50, false);
        injectFieldMappings(
            new Map<String, String>{ 'Admin' => 'Admin_Cost__c' }
        );

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        AggregateResult result = [
            SELECT SUM(Allocation_Amount__c) total
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Allocation_Code__c = :adminCode.Id
            AND Payment_Return__c = 'P'
        ];

        System.assertEquals(100, (Decimal) result.get('total'));
        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);
        clearInjectedMetadata();
    }

    @IsTest
    static void testMultiplePendingFundingRecordsAreProcessedInOrder() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext('MULTI-FUND', false, TERM_MONTHS);

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-MULTI',
            1,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RESERVE-MULTI',
            2,
            'Reserve',
            'Reserve Split',
            100
        );

        Funding__c firstFunding = createFunding(ctx.policy.Id, 75, false);
        Funding__c secondFunding = createFunding(ctx.policy.Id, 75, false);
        Test.setCreatedDate(firstFunding.Id, System.now().addMinutes(-2));
        Test.setCreatedDate(secondFunding.Id, System.now().addMinutes(-1));

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            reloadFunding(firstFunding.Id).Time_Processed__c
        );
        System.assertNotEquals(
            null,
            reloadFunding(secondFunding.Id).Time_Processed__c
        );

        Map<Id, Decimal> totalsByCode = new Map<Id, Decimal>();
        for (AggregateResult row : [
            SELECT Allocation_Code__c,
                   SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Payment_Return__c = 'P'
            GROUP BY Allocation_Code__c
        ]) {
            totalsByCode.put(
                (Id) row.get('Allocation_Code__c'),
                (Decimal) row.get('amount')
            );
        }

        System.assertEquals(100, totalsByCode.get(adminCode.Id));
        System.assertEquals(50, totalsByCode.get(reserveCode.Id));
    }

    @IsTest
    static void testNegativeFundingCreatesRunningReserveLedgerBalance() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext('NEG', false, TERM_MONTHS);

        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RESERVE-NEG',
            1,
            'Reserve',
            'Fixed',
            635
        );

        update new InsurancePolicy(
            Id = ctx.policy.Id,
            Funded_Reserve__c = 635
        );

        createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            635,
            'Reserve',
            'P',
            635,
            ctx.payee.Id,
            'Reserve'
        );

        Funding__c negativeFunding = createFunding(
            ctx.policy.Id,
            -130,
            false
        );

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        Allocation__c reserveReturn = [
            SELECT Allocation_Amount__c,
                   Payment_Return__c,
                   Descriptor__c,
                   Max_Allocation_Amount__c
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Payment_Return__c = 'R'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals(505, reserveReturn.Allocation_Amount__c);
        System.assertEquals('Reserve', reserveReturn.Descriptor__c);
        System.assertNotEquals(
            null,
            reloadFunding(negativeFunding.Id).Time_Processed__c
        );

        InsurancePolicy refreshedPolicy = reloadPolicy(ctx.policy.Id);
        System.assertEquals(
            -130,
            refreshedPolicy.DLRS_Total_Funded_Amount_from_Funding__c
        );
    }

    @IsTest
    static void testExactReinstatementRecoveryMirrorsSignedRopAllocations() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext('REIN-EXACT', false, TERM_MONTHS);

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-REIN-EXACT',
            1,
            'Admin',
            'Fixed',
            500
        );
        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RESERVE-REIN-EXACT',
            2,
            'Reserve',
            'Fixed',
            500
        );

        DateTime reinstatementDate = System.now().addDays(-5);
        update new InsurancePolicy(
            Id = ctx.policy.Id,
            Funded_Reserve__c = 249.91,
            Reinstatement_Date__c = reinstatementDate
        );

        Funding__c historicalFunding = createFunding(
            ctx.policy.Id,
            470.80,
            true
        );
        Test.setCreatedDate(
            historicalFunding.Id,
            System.now().addDays(-30)
        );

        Allocation__c originalAdmin = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            220.89,
            'Admin',
            'P',
            500,
            ctx.payee.Id,
            'ORIGINAL-REIN-EXACT'
        );
        Test.setCreatedDate(
            originalAdmin.Id,
            System.now().addDays(-29)
        );

        Allocation__c originalReserve = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            249.91,
            'Reserve',
            'P',
            500,
            ctx.payee.Id,
            'ORIGINAL-REIN-EXACT'
        );
        Test.setCreatedDate(
            originalReserve.Id,
            System.now().addDays(-28)
        );

        Allocation__c adminRop = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            -220.89,
            'Admin',
            'R',
            500,
            ctx.payee.Id,
            'RECOVERY-REIN-EXACT'
        );
        Test.setCreatedDate(adminRop.Id, System.now().addDays(-10));

        Allocation__c reserveRop = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            162.05,
            'Reserve',
            'R',
            500,
            ctx.payee.Id,
            'RECOVERY-REIN-EXACT'
        );
        Test.setCreatedDate(reserveRop.Id, System.now().addDays(-9));

        // Keep this record processed so org automation cannot consume it
        // before this method directly tests the recovery planner.
        Funding__c reinstatementFunding = createFunding(
            ctx.policy.Id,
            58.84,
            true
        );

        List<Funding__c> fundingHistory = [
            SELECT Id,
                   Contract__c,
                   Funded_Amount__c,
                   CreatedDate,
                   Time_Processed__c
            FROM Funding__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY CreatedDate, Id
        ];

        List<Allocation__c> allAllocations = [
            SELECT Id,
                   Contract__c,
                   Allocation_Code__c,
                   Allocation_Code__r.Name,
                   Allocation_Amount__c,
                   Descriptor__c,
                   CreatedDate,
                   Payment_Return__c,
                   Payee__c,
                   is_Expense__c,
                   Max_Allocation_Amount__c,
                   Fee_Label_for_Summary_Reporting__c
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY CreatedDate, Id
        ];

        List<Allocation__c> ropAllocations = new List<Allocation__c>();
        for (Allocation__c row : allAllocations) {
            if (row.Payment_Return__c == 'R') {
                ropAllocations.add(row);
            }
        }

        InsurancePolicy policy = reloadPolicy(ctx.policy.Id);
        List<Allocation__c> planned = new List<Allocation__c>();
        Set<Id> recoveredContracts = new Set<Id>();

        Decimal remaining =
            ContractAllocationUtilityCtrl.processReinstatementRecovery(
                reloadFunding(reinstatementFunding.Id),
                policy,
                fundingHistory,
                ropAllocations,
                allAllocations,
                new Map<Integer, Allocation_Code__c>{
                    1 => adminCode,
                    2 => reserveCode
                },
                new Map<String, Decimal>{
                    adminCode.Name => 500,
                    reserveCode.Name => 500
                },
                planned,
                new Map<Id, Map<String, Decimal>>(),
                recoveredContracts
            );

        System.assertEquals(0, remaining);
        System.assertEquals(2, planned.size());

        Decimal adminRecovery = 0;
        Decimal reserveRecovery = 0;
        Decimal totalRecovery = 0;

        for (Allocation__c row : planned) {
            if (row.Descriptor__c == 'Admin') {
                adminRecovery += row.Allocation_Amount__c;
            } else if (row.Descriptor__c == 'Reserve') {
                reserveRecovery += row.Allocation_Amount__c;
            }
            totalRecovery += row.Allocation_Amount__c;
        }

        System.assertEquals(220.89, adminRecovery);
        System.assertEquals(-162.05, reserveRecovery);
        System.assertEquals(58.84, totalRecovery);
        System.assertEquals(87.86, policy.Funded_Reserve__c);
        System.assertEquals(
            true,
            recoveredContracts.contains(ctx.policy.Id)
        );
    }

    @IsTest
    static void testReinstatementMismatchDoesNotCreatePartialRecovery() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext('REIN-MISMATCH', false, TERM_MONTHS);

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-REIN-MISMATCH',
            1,
            'Admin',
            'Fixed',
            500
        );
        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RESERVE-REIN-MISMATCH',
            2,
            'Reserve',
            'Fixed',
            500
        );

        DateTime reinstatementDate = System.now().addDays(-5);
        update new InsurancePolicy(
            Id = ctx.policy.Id,
            Reinstatement_Date__c = reinstatementDate,
            Funded_Reserve__c = 249.91
        );

        Funding__c historicalFunding = createFunding(
            ctx.policy.Id,
            470.80,
            true
        );
        Test.setCreatedDate(historicalFunding.Id, System.now().addDays(-30));

        Allocation__c adminRop = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            -220.89,
            'Admin',
            'R',
            500,
            ctx.payee.Id,
            'RECOVERY-MISMATCH'
        );
        Test.setCreatedDate(adminRop.Id, System.now().addDays(-10));

        Allocation__c reserveRop = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            162.05,
            'Reserve',
            'R',
            500,
            ctx.payee.Id,
            'RECOVERY-MISMATCH'
        );
        Test.setCreatedDate(reserveRop.Id, System.now().addDays(-9));

        Funding__c currentFunding = createFunding(
            ctx.policy.Id,
            60,
            false
        );

        List<Funding__c> fundingHistory = [
            SELECT Id,
                   Contract__c,
                   Funded_Amount__c,
                   CreatedDate,
                   Time_Processed__c
            FROM Funding__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY CreatedDate
        ];

        List<Allocation__c> allAllocations = [
            SELECT Id,
                   Contract__c,
                   Allocation_Code__c,
                   Allocation_Code__r.Name,
                   Allocation_Amount__c,
                   Descriptor__c,
                   CreatedDate,
                   Payment_Return__c,
                   Payee__c,
                   is_Expense__c,
                   Max_Allocation_Amount__c,
                   Fee_Label_for_Summary_Reporting__c
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY CreatedDate
        ];

        List<Allocation__c> ropAllocations = new List<Allocation__c>();
        for (Allocation__c row : allAllocations) {
            if (row.Payment_Return__c == 'R') {
                ropAllocations.add(row);
            }
        }

        List<Allocation__c> planned = new List<Allocation__c>();
        Set<Id> recoveredContracts = new Set<Id>();
        InsurancePolicy policy = reloadPolicy(ctx.policy.Id);

        Decimal remaining =
            ContractAllocationUtilityCtrl.processReinstatementRecovery(
                reloadFunding(currentFunding.Id),
                policy,
                fundingHistory,
                ropAllocations,
                allAllocations,
                new Map<Integer, Allocation_Code__c>{
                    1 => adminCode,
                    2 => reserveCode
                },
                new Map<String, Decimal>{
                    adminCode.Name => 500,
                    reserveCode.Name => 500
                },
                planned,
                new Map<Id, Map<String, Decimal>>(),
                recoveredContracts
            );

        System.assertEquals(60, remaining);
        System.assertEquals(0, planned.size());
        System.assertEquals(false, recoveredContracts.contains(ctx.policy.Id));
        System.assertEquals(249.91, policy.Funded_Reserve__c);
    }

    @IsTest
    static void testReinstatementFallbackUsesLatestPaidAllocationBoundary() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext(
            'REIN-FALLBACK',
            false,
            TERM_MONTHS
        );

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-REIN-FALLBACK',
            1,
            'Admin',
            'Fixed',
            500
        );

        DateTime reinstatementDate = System.now().addDays(-5);
        update new InsurancePolicy(
            Id = ctx.policy.Id,
            Reinstatement_Date__c = reinstatementDate
        );

        Allocation__c paidBoundary = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            100,
            'Admin',
            'P',
            500,
            ctx.payee.Id,
            'FALLBACK-ORIGINAL'
        );
        Test.setCreatedDate(
            paidBoundary.Id,
            System.now().addDays(-20)
        );

        Allocation__c rop = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            -100,
            'Admin',
            'R',
            500,
            ctx.payee.Id,
            'FALLBACK-RECOVERY'
        );
        Test.setCreatedDate(rop.Id, System.now().addDays(-10));

        // No earlier processed Funding exists. The helper must use the
        // latest paid allocation before reinstatement as its boundary.
        Funding__c funding = createFunding(
            ctx.policy.Id,
            100,
            true
        );

        List<Funding__c> fundingHistory = [
            SELECT Id,
                   Contract__c,
                   Funded_Amount__c,
                   CreatedDate,
                   Time_Processed__c
            FROM Funding__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY CreatedDate, Id
        ];

        List<Allocation__c> allAllocations = [
            SELECT Id,
                   Contract__c,
                   Allocation_Code__c,
                   Allocation_Code__r.Name,
                   Allocation_Amount__c,
                   Descriptor__c,
                   CreatedDate,
                   Payment_Return__c,
                   Payee__c,
                   is_Expense__c,
                   Max_Allocation_Amount__c,
                   Fee_Label_for_Summary_Reporting__c
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            ORDER BY CreatedDate, Id
        ];

        List<Allocation__c> ropAllocations = new List<Allocation__c>();
        for (Allocation__c row : allAllocations) {
            if (row.Payment_Return__c == 'R') {
                ropAllocations.add(row);
            }
        }

        List<Allocation__c> planned = new List<Allocation__c>();
        Set<Id> recoveredContracts = new Set<Id>();

        Decimal remaining =
            ContractAllocationUtilityCtrl.processReinstatementRecovery(
                reloadFunding(funding.Id),
                reloadPolicy(ctx.policy.Id),
                fundingHistory,
                ropAllocations,
                allAllocations,
                new Map<Integer, Allocation_Code__c>{
                    1 => adminCode
                },
                new Map<String, Decimal>{
                    adminCode.Name => 500
                },
                planned,
                new Map<Id, Map<String, Decimal>>(),
                recoveredContracts
            );

        System.assertEquals(0, remaining);
        System.assertEquals(1, planned.size());
        System.assertEquals(100, planned[0].Allocation_Amount__c);
        System.assertEquals(
            adminCode.Id,
            planned[0].Allocation_Code__c
        );
        System.assertEquals(
            true,
            recoveredContracts.contains(ctx.policy.Id)
        );
    }

    @IsTest
    static void testRecoveryHelperGuardsAndAllocationCodeResolution() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext('HELPER', false, TERM_MONTHS);

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-HELPER',
            1,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RESERVE-HELPER',
            2,
            'Reserve',
            'Fixed',
            100
        );

        Map<Integer, Allocation_Code__c> codesByPriority =
            new Map<Integer, Allocation_Code__c>{
                1 => adminCode,
                2 => reserveCode
            };

        Allocation__c byId = new Allocation__c(
            Allocation_Code__c = adminCode.Id,
            Descriptor__c = 'Wrong Descriptor'
        );
        System.assertEquals(
            adminCode.Id,
            ContractAllocationUtilityCtrl.resolveRecoveryAllocationCode(
                byId,
                codesByPriority
            ).Id
        );

        Allocation__c byDescriptorAndPayee = new Allocation__c(
            Descriptor__c = ' reserve ',
            Payee__c = ctx.payee.Id
        );
        System.assertEquals(
            reserveCode.Id,
            ContractAllocationUtilityCtrl.resolveRecoveryAllocationCode(
                byDescriptorAndPayee,
                codesByPriority
            ).Id
        );

        Allocation__c byDescriptorOnly = new Allocation__c(
            Descriptor__c = 'ADMIN'
        );
        System.assertEquals(
            adminCode.Id,
            ContractAllocationUtilityCtrl.resolveRecoveryAllocationCode(
                byDescriptorOnly,
                codesByPriority
            ).Id
        );

        System.assertEquals(
            null,
            ContractAllocationUtilityCtrl.resolveRecoveryAllocationCode(
                new Allocation__c(Descriptor__c = 'Unknown'),
                codesByPriority
            )
        );
        System.assertEquals(
            null,
            ContractAllocationUtilityCtrl.resolveRecoveryAllocationCode(
                null,
                codesByPriority
            )
        );

        System.assertEquals(
            false,
            ContractAllocationUtilityCtrl.isPotentialRopReturnAllocation(null)
        );
        System.assertEquals(
            true,
            ContractAllocationUtilityCtrl.isPotentialRopReturnAllocation(
                new Allocation__c(
                    Payment_Return__c = 'R',
                    Allocation_Amount__c = -1
                )
            )
        );
        System.assertEquals(
            false,
            ContractAllocationUtilityCtrl.isPotentialRopReturnAllocation(
                new Allocation__c(
                    Payment_Return__c = 'R',
                    Allocation_Amount__c = 1
                )
            )
        );
        System.assertEquals(
            true,
            ContractAllocationUtilityCtrl.isPotentialReinstatementSourceAllocation(
                    new Allocation__c(
                        Payment_Return__c = 'R',
                        Allocation_Amount__c = 1
                    )
                )
        );
        System.assertEquals(
            false,
            ContractAllocationUtilityCtrl.isPotentialReinstatementSourceAllocation(
                    new Allocation__c(
                        Payment_Return__c = 'R',
                        Allocation_Amount__c = 0
                    )
                )
        );

        DateTime reinstateDate = System.now();
        Allocation__c olderPaid = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            10,
            'Admin',
            'P',
            100,
            ctx.payee.Id,
            'HELPER'
        );
        Test.setCreatedDate(olderPaid.Id, reinstateDate.addDays(-3));

        Allocation__c latestPaid = createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            20,
            'Admin',
            'P',
            100,
            ctx.payee.Id,
            'HELPER'
        );
        Test.setCreatedDate(latestPaid.Id, reinstateDate.addDays(-2));

        olderPaid = reloadAllocation(olderPaid.Id);
        latestPaid = reloadAllocation(latestPaid.Id);

        System.assertEquals(
            latestPaid.CreatedDate,
            ContractAllocationUtilityCtrl.findLatestPaidAllocationDateBeforeReinstatement(
                    new List<Allocation__c>{ olderPaid, latestPaid },
                    reinstateDate
                )
        );
        System.assertEquals(
            null,
            ContractAllocationUtilityCtrl.findLatestPaidAllocationDateBeforeReinstatement(
                    new List<Allocation__c>(),
                    reinstateDate
                )
        );

        List<Allocation__c> planned = new List<Allocation__c>();
        System.assertEquals(
            0,
            ContractAllocationUtilityCtrl.processReinstatementRecovery(
                null,
                reloadPolicy(ctx.policy.Id),
                new List<Funding__c>(),
                new List<Allocation__c>(),
                new List<Allocation__c>(),
                codesByPriority,
                new Map<String, Decimal>(),
                planned,
                new Map<Id, Map<String, Decimal>>(),
                new Set<Id>()
            )
        );

        Funding__c negativeFunding = createFunding(ctx.policy.Id, -5, false);
        System.assertEquals(
            -5,
            ContractAllocationUtilityCtrl.processReinstatementRecovery(
                reloadFunding(negativeFunding.Id),
                reloadPolicy(ctx.policy.Id),
                new List<Funding__c>(),
                new List<Allocation__c>(),
                new List<Allocation__c>(),
                codesByPriority,
                new Map<String, Decimal>(),
                planned,
                new Map<Id, Map<String, Decimal>>(),
                new Set<Id>()
            )
        );
    }

    @IsTest
    static void testAssignAllocationToContractWithInjectedMetadata() {
        clearInjectedMetadata();
        TestContext ctx = createContext('DSI', true, TERM_MONTHS);

        String adminCodeName = 'DSIADM01';
        createAllocationCode(
            ctx,
            adminCodeName,
            1,
            'Admin',
            'Fixed',
            100
        );
        createReserve8004(ctx);

        Dealer_Cost_Allocation__c dealerAllocation =
            new Dealer_Cost_Allocation__c(
                RatingRecordID__c = 'RDSI0001',
                AllocationCode__c = adminCodeName,
                Allocation_Amount__c = 100,
                Refundable__c = 'Y'
            );
        populateRequiredPrimitiveFields(dealerAllocation, null);
        insert dealerAllocation;

        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>{
                new Rating_Record__mdt(
                    DeveloperName = 'UT_DSI_RATING',
                    MasterLabel = 'UT DSI Rating',
                    ClientProgramCode__c = ctx.policy.Client_Program_Code__c,
                    RatingRecordID__c = 'RDSI0001',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                )
            };

        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>{
                new Allocation_Priority__mdt(
                    DeveloperName = 'UT_DSI_PRIORITY',
                    MasterLabel = 'UT DSI Priority',
                    AllocationCode__c = adminCodeName,
                    Priority__c = '1',
                    FinanceCode__c = ctx.lienHolder.AccountNumber
                )
            };

        injectFieldMappings(
            new Map<String, String>{ 'Admin' => 'Admin_Cost__c' }
        );
        Funding__c funding = createFunding(ctx.policy.Id, 150, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.assignAllocationtoContract(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        Map<String, Decimal> amountByCode = new Map<String, Decimal>();
        for (Allocation__c allocation : [
            SELECT Allocation_Amount__c,
                   Allocation_Code__r.Name
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
        ]) {
            amountByCode.put(
                allocation.Allocation_Code__r.Name,
                allocation.Allocation_Amount__c
            );
        }

        System.assertEquals(100, amountByCode.get(adminCodeName));
        System.assertEquals(50, amountByCode.get('8004'));
        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);
        System.assertEquals(100, reloadPolicy(ctx.policy.Id).Admin_Cost__c);

        clearInjectedMetadata();
    }

    @IsTest
    static void testAssignAllocationNoPriorityFullyFundsConfiguredBuckets() {
        clearInjectedMetadata();
        TestContext ctx = createContext('DSI-EQUAL-FULL', true, TERM_MONTHS);

        Allocation_Code__c firstCode = createAllocationCode(
            ctx,
            'DSIFULA1',
            10,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c secondCode = createAllocationCode(
            ctx,
            'DSIFULB1',
            20,
            'Fulfillment',
            'Fixed',
            50
        );
        Allocation_Code__c reserveCode = createReserve8004(ctx);

        List<Dealer_Cost_Allocation__c> dealerRows =
            new List<Dealer_Cost_Allocation__c>{
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RDFULL01',
                    AllocationCode__c = firstCode.Name,
                    Allocation_Amount__c = 100,
                    Refundable__c = 'Y'
                ),
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RDFULL01',
                    AllocationCode__c = secondCode.Name,
                    Allocation_Amount__c = 50,
                    Refundable__c = 'Y'
                )
            };
        for (Dealer_Cost_Allocation__c row : dealerRows) {
            populateRequiredPrimitiveFields(row, null);
        }
        insert dealerRows;

        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>{
                new Rating_Record__mdt(
                    DeveloperName = 'UT_DSI_EQUAL_FULL_RATING',
                    MasterLabel = 'UT DSI Equal Full Rating',
                    ClientProgramCode__c = ctx.policy.Client_Program_Code__c,
                    RatingRecordID__c = 'RDFULL01',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                )
            };
        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>();
        injectFieldMappings(new Map<String, String>());

        Funding__c funding = createFunding(ctx.policy.Id, 200, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.assignAllocationtoContract(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        Map<Id, Decimal> totalsByCode = new Map<Id, Decimal>();
        for (AggregateResult row : [
            SELECT Allocation_Code__c,
                   SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            GROUP BY Allocation_Code__c
        ]) {
            totalsByCode.put(
                (Id) row.get('Allocation_Code__c'),
                (Decimal) row.get('amount')
            );
        }

        System.assertEquals(100, totalsByCode.get(firstCode.Id));
        System.assertEquals(50, totalsByCode.get(secondCode.Id));
        System.assertEquals(50, totalsByCode.get(reserveCode.Id));
        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);

        clearInjectedMetadata();
    }

    @IsTest
    static void testAssignAllocationNoPriorityDistributesUnderfundingProportionally() {
        clearInjectedMetadata();
        TestContext ctx = createContext('DSI-EQUAL-PART', true, TERM_MONTHS);

        Allocation_Code__c firstCode = createAllocationCode(
            ctx,
            'DSIPRTA1',
            10,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c secondCode = createAllocationCode(
            ctx,
            'DSIPRTB1',
            20,
            'Fulfillment',
            'Fixed',
            100
        );
        createReserve8004(ctx);

        List<Dealer_Cost_Allocation__c> dealerRows =
            new List<Dealer_Cost_Allocation__c>{
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RDPART01',
                    AllocationCode__c = firstCode.Name,
                    Allocation_Amount__c = 100,
                    Refundable__c = 'Y'
                ),
                new Dealer_Cost_Allocation__c(
                    RatingRecordID__c = 'RDPART01',
                    AllocationCode__c = secondCode.Name,
                    Allocation_Amount__c = 100,
                    Refundable__c = 'Y'
                )
            };
        for (Dealer_Cost_Allocation__c row : dealerRows) {
            populateRequiredPrimitiveFields(row, null);
        }
        insert dealerRows;

        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>{
                new Rating_Record__mdt(
                    DeveloperName = 'UT_DSI_EQUAL_PART_RATING',
                    MasterLabel = 'UT DSI Equal Part Rating',
                    ClientProgramCode__c = ctx.policy.Client_Program_Code__c,
                    RatingRecordID__c = 'RDPART01',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                )
            };
        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>();
        injectFieldMappings(new Map<String, String>());

        Funding__c funding = createFunding(ctx.policy.Id, 50, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.assignAllocationtoContract(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        Set<Id> targetCodeIds = new Set<Id>{ firstCode.Id, secondCode.Id };
        Map<Id, Decimal> totalsByCode = new Map<Id, Decimal>();
        for (AggregateResult row : [
            SELECT Allocation_Code__c,
                   SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Allocation_Code__c IN :targetCodeIds
            GROUP BY Allocation_Code__c
        ]) {
            totalsByCode.put(
                (Id) row.get('Allocation_Code__c'),
                (Decimal) row.get('amount')
            );
        }

        System.assertEquals(25, totalsByCode.get(firstCode.Id));
        System.assertEquals(25, totalsByCode.get(secondCode.Id));
        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);

        clearInjectedMetadata();
    }

    @IsTest
    static void testAssignAllocationExistingPriorityBucketIsToppedUp() {
        clearInjectedMetadata();
        TestContext ctx = createContext('DSI-TOPUP', true, TERM_MONTHS);

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'DSITOP01',
            1,
            'Admin',
            'Fixed',
            100
        );
        createReserve8004(ctx);

        Dealer_Cost_Allocation__c dealerAllocation =
            new Dealer_Cost_Allocation__c(
                RatingRecordID__c = 'RDTOP001',
                AllocationCode__c = adminCode.Name,
                Allocation_Amount__c = 100,
                Refundable__c = 'Y'
            );
        populateRequiredPrimitiveFields(dealerAllocation, null);
        insert dealerAllocation;

        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>{
                new Rating_Record__mdt(
                    DeveloperName = 'UT_DSI_TOPUP_RATING',
                    MasterLabel = 'UT DSI Topup Rating',
                    ClientProgramCode__c = ctx.policy.Client_Program_Code__c,
                    RatingRecordID__c = 'RDTOP001',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                )
            };
        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>{
                new Allocation_Priority__mdt(
                    DeveloperName = 'UT_DSI_TOPUP_PRIORITY',
                    MasterLabel = 'UT DSI Topup Priority',
                    AllocationCode__c = adminCode.Name,
                    Priority__c = '1',
                    FinanceCode__c = ctx.lienHolder.AccountNumber
                )
            };
        injectFieldMappings(new Map<String, String>());

        Funding__c historicalFunding = createFunding(ctx.policy.Id, 60, true);
        Test.setCreatedDate(historicalFunding.Id, System.now().addDays(-10));
        createAllocation(
            ctx.policy.Id,
            adminCode.Id,
            60,
            'Admin',
            'P',
            100,
            ctx.payee.Id,
            'Admin'
        );
        Funding__c currentFunding = createFunding(ctx.policy.Id, 50, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.assignAllocationtoContract(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        AggregateResult adminTotal = [
            SELECT SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Allocation_Code__c = :adminCode.Id
            AND Payment_Return__c = 'P'
        ];
        AggregateResult reserveTotal = [
            SELECT SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Allocation_Code__r.Name = '8004'
            AND Payment_Return__c = 'P'
        ];

        System.assertEquals(100, (Decimal) adminTotal.get('amount'));
        System.assertEquals(10, (Decimal) reserveTotal.get('amount'));
        System.assertNotEquals(
            null,
            reloadFunding(currentFunding.Id).Time_Processed__c
        );

        clearInjectedMetadata();
    }

    @IsTest
    static void testPostReserveCalculationUpdatesAndInsertsReserve() {
        clearInjectedMetadata();

        TestContext firstCtx = createContext(
            'POST-RES-UPDATE',
            false,
            TERM_MONTHS
        );
        TestContext secondCtx = createContext(
            'POST-RES-INSERT',
            false,
            TERM_MONTHS
        );

        Allocation_Code__c firstAdmin = createAllocationCode(
            firstCtx,
            'UT-POST-ADMIN-1',
            1,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c secondAdmin = createAllocationCode(
            secondCtx,
            'UT-POST-ADMIN-2',
            1,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c reserve8004 = createReserve8004(firstCtx);

        createFunding(firstCtx.policy.Id, 200, true);
        createFunding(secondCtx.policy.Id, 200, true);
        createAllocation(
            firstCtx.policy.Id,
            firstAdmin.Id,
            100,
            'Admin',
            'P',
            100,
            firstCtx.payee.Id,
            'Admin'
        );
        createAllocation(
            secondCtx.policy.Id,
            secondAdmin.Id,
            100,
            'Admin',
            'P',
            100,
            secondCtx.payee.Id,
            'Admin'
        );

        Allocation__c existingReserve = createAllocation(
            firstCtx.policy.Id,
            reserve8004.Id,
            25,
            'Reserve',
            'P',
            999999,
            firstCtx.payee.Id,
            'Reserve'
        );

        Test.startTest();
        ContractAllocationUtilityCtrl.postReserveCalculation(
            new Map<String,
                List<ContractAllocationUtilityCtrl.ContractAllocation>>{
                String.valueOf(firstCtx.policy.Id) =>
                    new List<ContractAllocationUtilityCtrl.ContractAllocation>(),
                String.valueOf(secondCtx.policy.Id) =>
                    new List<ContractAllocationUtilityCtrl.ContractAllocation>()
            }
        );
        Test.stopTest();

        System.assertEquals(
            100,
            [
                SELECT Allocation_Amount__c
                FROM Allocation__c
                WHERE Id = :existingReserve.Id
            ].Allocation_Amount__c
        );

        Allocation__c insertedReserve = [
            SELECT Allocation_Amount__c,
                   Allocation_Code__r.Name
            FROM Allocation__c
            WHERE Contract__c = :secondCtx.policy.Id
            AND Allocation_Code__r.Name = '8004'
            LIMIT 1
        ];
        System.assertEquals(100, insertedReserve.Allocation_Amount__c);
    }

    @IsTest
    static void testUpdateContractAllocationFieldsCapAndM2MBehavior() {
        clearInjectedMetadata();
        injectFieldMappings(
            new Map<String, String>{ 'Admin' => 'Admin_Cost__c' }
        );

        TestContext annualCtx = createContext('FIELD-ANNUAL', false, 12);
        TestContext m2mCtx = createContext('FIELD-M2M', false, 1);

        Allocation_Code__c annualCode = createAllocationCode(
            annualCtx,
            'UT-FIELD-ANNUAL',
            1,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c m2mCode = createAllocationCode(
            m2mCtx,
            'UT-FIELD-M2M',
            1,
            'Admin',
            'Fixed',
            100
        );

        createAllocation(
            annualCtx.policy.Id,
            annualCode.Id,
            150,
            'Admin',
            'P',
            100,
            annualCtx.payee.Id,
            'Admin'
        );
        createAllocation(
            m2mCtx.policy.Id,
            m2mCode.Id,
            150,
            'Admin',
            'P',
            100,
            m2mCtx.payee.Id,
            'Admin'
        );

        InsurancePolicy annual = reloadPolicy(annualCtx.policy.Id);
        InsurancePolicy m2m = reloadPolicy(m2mCtx.policy.Id);
        Map<Id, InsurancePolicy> updates =
            new Map<Id, InsurancePolicy>{
                annual.Id => annual,
                m2m.Id => m2m
            };

        Test.startTest();
        ContractAllocationUtilityCtrl.updateContractAllocationFields(updates);
        Test.stopTest();

        System.assertEquals(
            100,
            updates.get(annual.Id).Admin_Cost__c
        );
        System.assertEquals(
            150,
            updates.get(m2m.Id).Admin_Cost__c
        );

        clearInjectedMetadata();
    }

    @IsTest
    static void testHomeAndHealthCarAllocationCodeMatching() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());

        TestContext homeCtx = createContext('HOME', false, TERM_MONTHS);
        TestContext healthCtx = createContext('HEALTH', false, TERM_MONTHS);

        Allocation_Code__c homeCode = createAllocationCode(
            homeCtx,
            'UT-HOME',
            1,
            'Admin',
            'Fixed',
            30,
            'Home'
        );
        Allocation_Code__c healthCode = createAllocationCode(
            healthCtx,
            'UT-HEALTH',
            1,
            'Admin',
            'Fixed',
            40,
            'Health CAR'
        );

        Funding__c homeFunding = createFunding(homeCtx.policy.Id, 30, false);
        Funding__c healthFunding = createFunding(
            healthCtx.policy.Id,
            40,
            false
        );

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{
                reloadPolicy(homeCtx.policy.Id),
                reloadPolicy(healthCtx.policy.Id)
            }
        );
        Test.stopTest();

        AggregateResult homeTotal = [
            SELECT SUM(Allocation_Amount__c) total
            FROM Allocation__c
            WHERE Contract__c = :homeCtx.policy.Id
            AND Allocation_Code__c = :homeCode.Id
        ];
        AggregateResult healthTotal = [
            SELECT SUM(Allocation_Amount__c) total
            FROM Allocation__c
            WHERE Contract__c = :healthCtx.policy.Id
            AND Allocation_Code__c = :healthCode.Id
        ];

        System.assertEquals(30, (Decimal) homeTotal.get('total'));
        System.assertEquals(40, (Decimal) healthTotal.get('total'));
        System.assertNotEquals(null, reloadFunding(homeFunding.Id).Time_Processed__c);
        System.assertNotEquals(
            null,
            reloadFunding(healthFunding.Id).Time_Processed__c
        );
    }

    @IsTest
    static void testSplitContractsByClientRoutesOtherContract() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext('SPLIT-OTHER', false, TERM_MONTHS);

        createAllocationCode(
            ctx,
            'UT-SPLIT-ADMIN',
            1,
            'Admin',
            'Fixed',
            25
        );
        Funding__c funding = createFunding(ctx.policy.Id, 25, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.splitContractsByClient(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Allocation__c
                WHERE Contract__c = :ctx.policy.Id
            ]
        );
    }

    @IsTest
    static void testSplitContractsByClientRoutesDsiContract() {
        clearInjectedMetadata();
        TestContext ctx = createContext('SPLIT-DSI', true, TERM_MONTHS);

        String adminCodeName = 'DSISPL01';
        createAllocationCode(
            ctx,
            adminCodeName,
            1,
            'Admin',
            'Fixed',
            100
        );
        createReserve8004(ctx);

        Dealer_Cost_Allocation__c dealerAllocation =
            new Dealer_Cost_Allocation__c(
                RatingRecordID__c = 'RDSPL001',
                AllocationCode__c = adminCodeName,
                Allocation_Amount__c = 100,
                Refundable__c = 'Y'
            );
        populateRequiredPrimitiveFields(dealerAllocation, null);
        insert dealerAllocation;

        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>{
                new Rating_Record__mdt(
                    DeveloperName = 'UT_SPLIT_DSI_RATING',
                    MasterLabel = 'UT Split DSI Rating',
                    ClientProgramCode__c = ctx.policy.Client_Program_Code__c,
                    RatingRecordID__c = 'RDSPL001',
                    BegDate__c = Date.today().addDays(-1),
                    EndDate__c = Date.today().addDays(1)
                )
            };
        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>{
                new Allocation_Priority__mdt(
                    DeveloperName = 'UT_SPLIT_DSI_PRIORITY',
                    MasterLabel = 'UT Split DSI Priority',
                    AllocationCode__c = adminCodeName,
                    Priority__c = '1',
                    FinanceCode__c = ctx.lienHolder.AccountNumber
                )
            };
        injectFieldMappings(new Map<String, String>());

        Funding__c funding = createFunding(ctx.policy.Id, 120, false);

        Test.startTest();
        ContractAllocationUtilityCtrl.splitContractsByClient(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        System.assertNotEquals(null, reloadFunding(funding.Id).Time_Processed__c);
        AggregateResult splitDsiTotal = [
            SELECT SUM(Allocation_Amount__c) total
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
        ];
        System.assertEquals(120, (Decimal) splitDsiTotal.get('total'));

        clearInjectedMetadata();
    }

    @IsTest
    static void testSplitContractsByClientRoutesM2mContract() {
        clearInjectedMetadata();
        TestContext ctx = createContext('SPLIT-M2M', false, 1);

        Test.startTest();
        ContractAllocationUtilityCtrl.splitContractsByClient(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        System.assertEquals(
            1,
            reloadPolicy(ctx.policy.Id).Contract_Term_Months__c
        );
    }

    @IsTest
    static void testPublicMethodsHandleEmptyCollections() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        ContractAllocationUtilityCtrl.testRatingRecords =
            new List<Rating_Record__mdt>();
        ContractAllocationUtilityCtrl.testPriorityRecords =
            new List<Allocation_Priority__mdt>();

        Test.startTest();
        ContractAllocationUtilityCtrl.assignAllocationtoContract(
            new List<InsurancePolicy>()
        );
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>()
        );
        ContractAllocationUtilityCtrl.splitContractsByClient(
            new List<InsurancePolicy>()
        );
        ContractAllocationUtilityCtrl.postReserveCalculation(
            new Map<String,
                List<ContractAllocationUtilityCtrl.ContractAllocation>>()
        );
        ContractAllocationUtilityCtrl.updateContractAllocationFields(
            new Map<Id, InsurancePolicy>()
        );
        Test.stopTest();

        System.assertEquals(true, true);
        clearInjectedMetadata();
    }

    @IsTest
    static void testBlankCodeRopReserveIsIncludedInFinalTopUp() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());

        TestContext ctx = createContext(
            'RES-LIFECYCLE',
            false,
            TERM_MONTHS
        );

        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RES-LIFECYCLE',
            1,
            'Reserve',
            'Reserve Split',
            1099
        );

        Datetime reinstatementDate = System.now().addDays(-5);
        update new InsurancePolicy(
            Id = ctx.policy.Id,
            Reinstatement_Date__c = reinstatementDate,
            Funded_Reserve__c = 337.86
        );

        Funding__c originalFunding = createFunding(
            ctx.policy.Id,
            650,
            true
        );
        Test.setCreatedDate(
            originalFunding.Id,
            System.now().addDays(-12)
        );

        Allocation__c originalReserveOne = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            37.86,
            'Reserve',
            'P',
            1099,
            ctx.payee.Id,
            'Reserve'
        );
        Test.setCreatedDate(
            originalReserveOne.Id,
            System.now().addDays(-11)
        );

        Allocation__c originalReserveTwo = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            50,
            'Reserve',
            'P',
            1099,
            ctx.payee.Id,
            'Reserve'
        );
        Test.setCreatedDate(
            originalReserveTwo.Id,
            System.now().addDays(-10)
        );

        Allocation__c originalReserveThree = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            200,
            'Reserve',
            'P',
            1099,
            ctx.payee.Id,
            'Reserve'
        );
        Test.setCreatedDate(
            originalReserveThree.Id,
            System.now().addDays(-9)
        );

        /*
         * Reproduces the UAT data condition: the ROP Reserve row carries the
         * correct signed amount but does not retain Allocation_Code__c.
         */
        Allocation__c blankCodeRopReserve = createAllocation(
            ctx.policy.Id,
            null,
            -186.32,
            'Reserve',
            'R',
            1099,
            ctx.payee.Id,
            'ROP Reserve'
        );
        Test.setCreatedDate(
            blankCodeRopReserve.Id,
            System.now().addDays(-7)
        );

        Funding__c reinstatementFunding = createFunding(
            ctx.policy.Id,
            505.74,
            true
        );
        Test.setCreatedDate(
            reinstatementFunding.Id,
            System.now().addDays(-4)
        );

        Allocation__c reinstatementReserve = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            186.32,
            'Reserve',
            'P',
            1099,
            ctx.payee.Id,
            'Reinstatement Reserve'
        );
        Test.setCreatedDate(
            reinstatementReserve.Id,
            System.now().addDays(-4)
        );

        Funding__c continuedFunding = createFunding(
            ctx.policy.Id,
            50,
            true
        );
        Test.setCreatedDate(
            continuedFunding.Id,
            System.now().addDays(-3)
        );

        Allocation__c continuedReserve = createAllocation(
            ctx.policy.Id,
            reserveCode.Id,
            50,
            'Reserve',
            'P',
            1099,
            ctx.payee.Id,
            'Continued Reserve'
        );
        Test.setCreatedDate(
            continuedReserve.Id,
            System.now().addDays(-3)
        );

        Set<Id> existingAllocationIds = new Map<Id, Allocation__c>([
            SELECT Id
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
        ]).keySet();

        Funding__c finalFunding = createFunding(
            ctx.policy.Id,
            1000,
            false
        );
        Test.setCreatedDate(
            finalFunding.Id,
            System.now().addDays(-1)
        );

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        List<Allocation__c> finalReserveAllocations = [
            SELECT Allocation_Amount__c,
                   Allocation_Code__c,
                   Descriptor__c,
                   Payment_Return__c
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Id NOT IN :existingAllocationIds
            AND Allocation_Code__c = :reserveCode.Id
            AND Descriptor__c = 'Reserve'
            AND Payment_Return__c = 'P'
        ];

        System.assertEquals(1, finalReserveAllocations.size());
        System.assertEquals(
            761.14,
            finalReserveAllocations[0].Allocation_Amount__c,
            'The final Reserve top-up must use the signed lifecycle balance, ' +
            'including the blank-code ROP Reserve amount.'
        );

        AggregateResult reserveLifecycleTotal = [
            SELECT SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Descriptor__c = 'Reserve'
        ];

        System.assertEquals(
            1099,
            (Decimal) reserveLifecycleTotal.get('amount')
        );
        System.assertEquals(
            1099,
            reloadPolicy(ctx.policy.Id).Funded_Reserve__c
        );
        System.assertNotEquals(
            null,
            reloadFunding(finalFunding.Id).Time_Processed__c
        );

        clearInjectedMetadata();
    }

    @IsTest
    static void testLifecycleResolverRejectsAmbiguousDescriptorAndPayee() {
        clearInjectedMetadata();
        TestContext ctx = createContext(
            'RES-AMBIGUOUS',
            false,
            TERM_MONTHS
        );

        Allocation_Code__c firstReserveCode = createAllocationCode(
            ctx,
            'UT-RES-AMB-1',
            1,
            'Reserve',
            'Reserve Split',
            500
        );
        Allocation_Code__c secondReserveCode = createAllocationCode(
            ctx,
            'UT-RES-AMB-2',
            2,
            'Reserve',
            'Reserve Split',
            500
        );

        Allocation__c blankCodeReturn = new Allocation__c(
            Contract__c = ctx.policy.Id,
            Descriptor__c = 'Reserve',
            Payment_Return__c = 'R',
            Allocation_Amount__c = -10,
            Payee__c = ctx.payee.Id
        );

        System.assertEquals(
            null,
            ContractAllocationUtilityCtrl.resolveLifecycleAllocationCodeName(
                blankCodeReturn,
                new Map<Integer, Allocation_Code__c>{
                    1 => firstReserveCode,
                    2 => secondReserveCode
                }
            ),
            'Ambiguous blank-code return rows must not be assigned to an ' +
            'arbitrary Allocation Code.'
        );

        clearInjectedMetadata();
    }

    @IsTest
    static void testThreePendingFundingRecordsDoNotOverfundReserveSplit() {
        clearInjectedMetadata();
        injectFieldMappings(new Map<String, String>());
        TestContext ctx = createContext(
            'MULTI-RESERVE',
            false,
            TERM_MONTHS
        );

        Allocation_Code__c adminCode = createAllocationCode(
            ctx,
            'UT-ADMIN-MULTI-RES',
            1,
            'Admin',
            'Fixed',
            100
        );
        Allocation_Code__c reserveCode = createAllocationCode(
            ctx,
            'UT-RES-MULTI-RES',
            2,
            'Reserve',
            'Reserve Split',
            100
        );

        Funding__c firstFunding = createFunding(
            ctx.policy.Id,
            75,
            false
        );
        Funding__c secondFunding = createFunding(
            ctx.policy.Id,
            75,
            false
        );
        Funding__c thirdFunding = createFunding(
            ctx.policy.Id,
            75,
            false
        );

        Test.setCreatedDate(
            firstFunding.Id,
            System.now().addMinutes(-3)
        );
        Test.setCreatedDate(
            secondFunding.Id,
            System.now().addMinutes(-2)
        );
        Test.setCreatedDate(
            thirdFunding.Id,
            System.now().addMinutes(-1)
        );

        Test.startTest();
        ContractAllocationUtilityCtrl.distributeFundingToContracts(
            new List<InsurancePolicy>{ reloadPolicy(ctx.policy.Id) }
        );
        Test.stopTest();

        Map<Id, Decimal> totalsByCode = new Map<Id, Decimal>();
        for (AggregateResult row : [
            SELECT Allocation_Code__c,
                   SUM(Allocation_Amount__c) amount
            FROM Allocation__c
            WHERE Contract__c = :ctx.policy.Id
            AND Payment_Return__c = 'P'
            GROUP BY Allocation_Code__c
        ]) {
            totalsByCode.put(
                (Id) row.get('Allocation_Code__c'),
                (Decimal) row.get('amount')
            );
        }

        System.assertEquals(100, totalsByCode.get(adminCode.Id));
        System.assertEquals(
            100,
            totalsByCode.get(reserveCode.Id),
            'The in-memory Reserve balance must be updated after every ' +
            'pending Funding record in the same execution.'
        );
        System.assertNotEquals(
            null,
            reloadFunding(firstFunding.Id).Time_Processed__c
        );
        System.assertNotEquals(
            null,
            reloadFunding(secondFunding.Id).Time_Processed__c
        );
        System.assertNotEquals(
            null,
            reloadFunding(thirdFunding.Id).Time_Processed__c
        );

        clearInjectedMetadata();
    }

}