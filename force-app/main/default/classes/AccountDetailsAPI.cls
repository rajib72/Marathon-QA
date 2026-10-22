@RestResource(urlMapping='/v1/accountDetails/contractHolders')
global with sharing class AccountDetailsAPI {

    private static final Integer DEFAULT_LIMIT = 50;
    private static final Integer MAX_LIMIT = 200;

    @HttpGet
    global static AccountListResponse getContractHolderAccounts() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // 🔹 Read & validate parameters
            Integer limitSize = getLimit(req);
            if (limitSize <= 0) {
                throw new AuraHandledException('Limit must be greater than 0');
            }

            Datetime snapshotTime = getSafeDatetime(req.params.get('snapshotTime'));
            if (snapshotTime == null) {
                snapshotTime = System.now();
            }

            Datetime lastCreatedDate = getSafeDatetime(req.params.get('lastCreatedDate'));
            String lastId = req.params.get('lastId');

            // 🔹 Base Query
            String baseQuery = 'SELECT Id, Name, PersonEmail, Phone, ' +
                'BillingStreet, BillingCity, BillingState, BillingPostalCode, ' +
                'RecordType.DeveloperName, FinServ__PrimaryLanguage__pc, CreatedDate ' +
                'FROM Account ' +
                'WHERE RecordType.DeveloperName = \'Contract_Holder\' ' +
                'AND CreatedDate <= :snapshotTime';

            // 🔹 Keyset Pagination
            if (lastCreatedDate != null && String.isNotBlank(lastId)) {
                baseQuery += ' AND (CreatedDate < :lastCreatedDate OR ' +
                             '(CreatedDate = :lastCreatedDate AND Id < :lastId))';
            }

            baseQuery += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC, Id DESC LIMIT :limitSize';

            // 🔹 Execute Query
            List<Account> accounts = Database.query(baseQuery);

            // 🔹 Transform
            List<AccountResponse> responseList = new List<AccountResponse>();
            for (Account acc : accounts) {
                responseList.add(buildResponse(acc));
            }

            // 🔹 Pagination Cursor
            String nextCreatedDate;
            String nextId;

            if (!accounts.isEmpty()) {
                Account lastRecord = accounts[accounts.size() - 1];
                nextCreatedDate = formatDatetimeISO(lastRecord.CreatedDate);
                nextId = lastRecord.Id;
            }

            Boolean hasMore = (accounts.size() == limitSize);

            // 🔹 Success Log (INFO style inside error method as per org pattern)
            QDX_LOG.error(
                'INFO: Account API Success | Records Returned: ' + accounts.size() +
                ' | Params: ' + JSON.serialize(req.params)
            );

            return new AccountListResponse(
                responseList,
                snapshotTime,
                nextCreatedDate,
                nextId,
                hasMore
            );

        } catch (Exception e) {

            // 🔥 Enhanced Error Logging
            QDX_LOG.error(
                'AccountDetailsAPI ERROR | Params: ' + JSON.serialize(req.params) +
                ' | Message: ' + e.getMessage() +
                ' | Line: ' + e.getLineNumber()
            );

            res.statusCode = 500;

            AccountListResponse resBody = new AccountListResponse();
            resBody.errorMessage = 'Internal server error';
            return resBody;

        } finally {
            QDX_Log.publish();
        }
    }

    // ================= HELPERS =================

    private static Integer getLimit(RestRequest req) {
        String val = req.params.get('limit');
        Integer limitSize = (val != null && val.isNumeric()) ? Integer.valueOf(val) : DEFAULT_LIMIT;
        return Math.min(limitSize, MAX_LIMIT);
    }

    // 🔹 Safe datetime parser
    private static Datetime getSafeDatetime(String val) {
        try {
            return (val != null) ? Datetime.valueOf(val) : null;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid datetime format');
        }
    }

    // 🔹 ISO formatter (important for frontend compatibility)
    private static String formatDatetimeISO(Datetime dt) {
        return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }

    private static AccountResponse buildResponse(Account acc) {
        AccountResponse res = new AccountResponse();

        res.Id = acc.Id;
        res.Name = acc.Name;
        res.Email = acc.PersonEmail;
        res.Phone = acc.Phone;
        res.Address = formatAddress(acc);
        res.RecordType = acc.RecordType.DeveloperName;
        res.PrimaryLanguage = acc.FinServ__PrimaryLanguage__pc;

        return res;
    }

    private static String formatAddress(Account acc) {
        List<String> parts = new List<String>();

        if (acc.BillingStreet != null) parts.add(acc.BillingStreet);
        if (acc.BillingCity != null) parts.add(acc.BillingCity);
        if (acc.BillingState != null) parts.add(acc.BillingState);
        if (acc.BillingPostalCode != null) parts.add(acc.BillingPostalCode);

        return String.join(parts, ', ');
    }

    // ================= RESPONSE CLASSES =================

    global class AccountResponse {
        public String Id;
        public String Name;
        public String Email;
        public String Phone;
        public String Address;
        public String RecordType;
        public String PrimaryLanguage;
    }

    global class AccountListResponse {
        public List<AccountResponse> accounts;
        public Datetime snapshotTime;
        public String nextCreatedDate;
        public String nextId;
        public Boolean hasMore;
        public String errorMessage;

        public AccountListResponse(
            List<AccountResponse> accounts,
            Datetime snapshotTime,
            String nextCreatedDate,
            String nextId,
            Boolean hasMore
        ) {
            this.accounts = accounts;
            this.snapshotTime = snapshotTime;
            this.nextCreatedDate = nextCreatedDate;
            this.nextId = nextId;
            this.hasMore = hasMore;
        }

        public AccountListResponse() {}
    }
}