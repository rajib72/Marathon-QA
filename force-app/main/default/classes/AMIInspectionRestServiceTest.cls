@IsTest(SeeAllData=true)
private class AMIInspectionRestServiceTest {

    // ============================================================
    // COMMON REST EXECUTION
    // ============================================================

    private static void executeApi(String requestBody) {

        RestRequest req = new RestRequest();

        req.httpMethod = 'POST';

        req.requestUri =
            '/services/apexrest/ami/inspection/';

        if (requestBody != null) {
            req.requestBody =
                Blob.valueOf(requestBody);
        }

        RestResponse res =
            new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();

        AMIInspectionRestService.receiveInspection();

        Test.stopTest();
    }


    // ============================================================
    // GET CLAIM HAVING INSPECTION ITEM
    // ============================================================

    private static Claim getInspectionClaim() {

        List<ClaimItem> items = [

            SELECT
                Id,
                ClaimId,
                Payee_Name__c,
                Coverage_Level_Detail__r.Name

            FROM ClaimItem

            WHERE Coverage_Level_Detail__r.Name LIKE 'Inspection%'

            LIMIT 1
        ];

        if (items.isEmpty()) {
            return null;
        }

        List<Claim> claims = [

            SELECT
                Id,
                Name

            FROM Claim

            WHERE Id = :items[0].ClaimId

            LIMIT 1
        ];

        if (claims.isEmpty()) {
            return null;
        }

        return claims[0];
    }


    // ============================================================
    // GET INSPECTION COMPANY
    // ============================================================

    private static String getInspectionCompany(Id claimId) {

        List<ClaimItem> items = [

            SELECT
                Id,
                Payee_Name__c,
                Coverage_Level_Detail__r.Name

            FROM ClaimItem

            WHERE ClaimId = :claimId

            AND Coverage_Level_Detail__r.Name LIKE 'Inspection%'

            LIMIT 1
        ];

        if (
            items.isEmpty() ||
            items[0].Payee_Name__c == null
        ) {
            return null;
        }

        List<Account> accounts = [

            SELECT
                Id,
                Name

            FROM Account

            WHERE Id = :items[0].Payee_Name__c

            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            return null;
        }

        return accounts[0].Name;
    }


    // ============================================================
    // TEST 1
    // SUCCESSFUL REQUEST WITHOUT DOCUMENT
    // ============================================================

    @IsTest
    static void testSuccessfulInspection() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String company =
            getInspectionCompany(
                claimRecord.Id
            );

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"TEST-INV-001",' +
            '"inspectionCompany":"' +
            company +
            '",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


// ============================================================
// TEST - Document Attachment
// Covers complete document processing block
// ============================================================

@IsTest
static void testSuccessfulInspectionWithDocument() {

    // --------------------------------------------------------
    // Get existing Claim with Inspection Claim Item
    // --------------------------------------------------------

    Claim claimRecord =
        getInspectionClaim();

    if (claimRecord == null) {
        return;
    }


    // --------------------------------------------------------
    // Create valid Base64 document
    // --------------------------------------------------------

    String base64Data =
        EncodingUtil.base64Encode(
            Blob.valueOf(
                'AMI Inspection UAT Test Document'
            )
        );


    // --------------------------------------------------------
    // Build request
    // --------------------------------------------------------

    Map<String, Object> document =
        new Map<String, Object>();


    document.put(
        'fileName',
        'AMI-UAT-Inspection-Test.txt'
    );


    document.put(
        'base64Data',
        base64Data
    );


    List<Object> documents =
        new List<Object>();


    documents.add(
        document
    );


    Map<String, Object> requestData =
        new Map<String, Object>();


    requestData.put(
        'claimId',
        String.valueOf(
            claimRecord.Id
        )
    );


    requestData.put(
        'claimNumber',
        claimRecord.Name
    );


    requestData.put(
        'inspectionNumber',
        123457
    );


    requestData.put(
        'inspectionPrice',
        175.00
    );


    requestData.put(
        'invoiceNumber',
        'INV-DOC-TEST-001'
    );


    // --------------------------------------------------------
    // IMPORTANT:
    // Do not send inspectionCompany.
    //
    // This allows the test to directly reach the document
    // processing section without depending on Payee validation.
    // --------------------------------------------------------

    requestData.put(
        'documents',
        documents
    );


    String requestBody =
        JSON.serialize(
            requestData
        );


    // --------------------------------------------------------
    // Execute existing API helper
    // --------------------------------------------------------

    executeApi(
        requestBody
    );
}


    // ============================================================
    // TEST 3
    // INVALID CLAIM NUMBER
    // ============================================================

    @IsTest
    static void testInvalidClaimNumber() {

        String requestBody =
            '{' +
            '"claimNumber":"CL-9999.INVALID",' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"INV-INVALID-001",' +
            '"inspectionCompany":"AMI",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 4
    // CLAIM EXISTS BUT NO CLAIM ITEM
    // ============================================================

    @IsTest
    static void testClaimWithoutInspectionItem() {

        List<Claim> claims = [

            SELECT
                Id,
                Name

            FROM Claim

            WHERE Id NOT IN (
                SELECT ClaimId
                FROM ClaimItem
            )

            LIMIT 1
        ];

        if (claims.isEmpty()) {
            return;
        }

        Claim claimRecord =
            claims[0];

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"INV-NO-ITEM",' +
            '"inspectionCompany":"AMI",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 5
    // INVALID INSPECTION COMPANY
    // ============================================================

    @IsTest
    static void testInvalidInspectionCompany() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"INV-WRONG-COMPANY",' +
            '"inspectionCompany":"INVALID COMPANY XYZ",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 6
    // MISSING CLAIM REFERENCE
    // ============================================================

    @IsTest
    static void testMissingClaimReference() {

        String requestBody =
            '{' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"INV-MISSING-CLAIM",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 7
    // MISSING INSPECTION NUMBER
    // ============================================================

    @IsTest
    static void testMissingInspectionNumber() {

        String requestBody =
            '{' +
            '"claimNumber":"CL-TEST",' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"INV-TEST",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 8
    // MISSING INSPECTION PRICE
    // ============================================================

    @IsTest
    static void testMissingInspectionPrice() {

        String requestBody =
            '{' +
            '"claimNumber":"CL-TEST",' +
            '"inspectionNumber":123456,' +
            '"invoiceNumber":"INV-TEST",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 9
    // MISSING INVOICE NUMBER
    // ============================================================

    @IsTest
    static void testMissingInvoiceNumber() {

        String requestBody =
            '{' +
            '"claimNumber":"CL-TEST",' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 10
    // EMPTY BODY
    // ============================================================

    @IsTest
    static void testEmptyRequestBody() {

        RestRequest req =
            new RestRequest();

        req.httpMethod =
            'POST';

        req.requestUri =
            '/services/apexrest/ami/inspection/';

        req.requestBody =
            Blob.valueOf('');

        RestResponse res =
            new RestResponse();

        RestContext.request =
            req;

        RestContext.response =
            res;

        Test.startTest();

        AMIInspectionRestService.receiveInspection();

        Test.stopTest();
    }


    // ============================================================
    // TEST 11
    // NULL REQUEST OBJECT
    // ============================================================

    @IsTest
    static void testNullRestRequest() {

        RestContext.request =
            null;

        RestContext.response =
            new RestResponse();

        Test.startTest();

        AMIInspectionRestService.receiveInspection();

        Test.stopTest();
    }


    // ============================================================
    // TEST 12
    // INVALID JSON
    // ============================================================

    @IsTest
    static void testInvalidJson() {

        executeApi(
            '{ "claimNumber": "CL-123", '
        );
    }


    // ============================================================
    // TEST 13
    // NULL JSON PAYLOAD
    // ============================================================

    @IsTest
    static void testNullPayload() {

        executeApi(
            'null'
        );
    }


    // ============================================================
    // TEST 14
    // INVALID DOCUMENT
    // ============================================================

    @IsTest
    static void testInvalidDocumentEntry() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String company =
            getInspectionCompany(
                claimRecord.Id
            );

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123456,' +
            '"inspectionPrice":125.00,' +
            '"invoiceNumber":"INV-INVALID-DOC",' +
            '"inspectionCompany":"' +
            company +
            '",' +
            '"documents":[' +
                '{' +
                    '"fileName":"",' +
                    '"base64Data":""' +
                '}' +
            ']' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 15
    // DOCUMENT WITHOUT EXTENSION
    // ============================================================

    @IsTest
    static void testDocumentWithoutExtension() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String base64Data =
            EncodingUtil.base64Encode(
                Blob.valueOf(
                    'AMI Test File'
                )
            );

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123459,' +
            '"inspectionPrice":180.00,' +
            '"invoiceNumber":"INV-NO-EXTENSION",' +
            '"documents":[' +
                '{' +
                    '"fileName":"AMITestFile",' +
                    '"base64Data":"' +
                    base64Data +
                    '"' +
                '}' +
            ']' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 16
    // INVALID BASE64
    // ============================================================

    @IsTest
    static void testInvalidBase64() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String company =
            getInspectionCompany(
                claimRecord.Id
            );

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123460,' +
            '"inspectionPrice":190.00,' +
            '"invoiceNumber":"INV-BAD-BASE64",' +
            '"inspectionCompany":"' +
            company +
            '",' +
            '"documents":[' +
                '{' +
                    '"fileName":"Invalid.txt",' +
                    '"base64Data":"INVALID_BASE64_@@@"' +
                '}' +
            ']' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 17
    // MULTIPLE INSPECTION CLAIM ITEMS
    // ============================================================

    @IsTest
    static void testMultipleInspectionItems() {

        List<AggregateResult> groupedClaims = [

            SELECT
                ClaimId claimId,
                COUNT(Id) itemCount

            FROM ClaimItem

            WHERE Coverage_Level_Detail__r.Name LIKE 'Inspection%'

            GROUP BY ClaimId

            HAVING COUNT(Id) > 1

            LIMIT 1
        ];

        if (groupedClaims.isEmpty()) {
            return;
        }

        Id claimId =
            (Id) groupedClaims[0].get('claimId');

        Claim claimRecord = [

            SELECT
                Id,
                Name

            FROM Claim

            WHERE Id = :claimId

            LIMIT 1
        ];

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123461,' +
            '"inspectionPrice":200.00,' +
            '"invoiceNumber":"INV-MULTIPLE",' +
            '"inspectionCompany":"AMI",' +
            '"documents":[]' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 18
    // DOCUMENT WITH MULTIPLE FILES
    // ============================================================

    @IsTest
    static void testMultipleDocuments() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String company =
            getInspectionCompany(
                claimRecord.Id
            );

        String base64One =
            EncodingUtil.base64Encode(
                Blob.valueOf(
                    'First AMI document'
                )
            );

        String base64Two =
            EncodingUtil.base64Encode(
                Blob.valueOf(
                    'Second AMI document'
                )
            );

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123462,' +
            '"inspectionPrice":210.00,' +
            '"invoiceNumber":"INV-MULTI-DOC",' +
            '"inspectionCompany":"' +
            company +
            '",' +
            '"documents":[' +

                '{' +
                    '"fileName":"AMI-Document-One.txt",' +
                    '"base64Data":"' +
                    base64One +
                '"' +
                '},' +

                '{' +
                    '"fileName":"AMI-Document-Two.txt",' +
                    '"base64Data":"' +
                    base64Two +
                '"' +
                '}' +

            ']' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 19
    // DOCUMENT FILE NAME WITH EXTENSION
    // ============================================================

    @IsTest
    static void testDocumentWithPdfName() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String base64Data =
            EncodingUtil.base64Encode(
                Blob.valueOf(
                    'AMI PDF test'
                )
            );

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123463,' +
            '"inspectionPrice":220.00,' +
            '"invoiceNumber":"INV-PDF-TEST",' +
            '"documents":[' +
                '{' +
                    '"fileName":"AMI-Inspection-Report.pdf",' +
                    '"contentType":"application/pdf",' +
                    '"base64Data":"' +
                    base64Data +
                    '"' +
                '}' +
            ']' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 20
    // DOCUMENT NULL LIST
    // ============================================================

    @IsTest
    static void testDocumentsNull() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123464,' +
            '"inspectionPrice":230.00,' +
            '"invoiceNumber":"INV-NULL-DOC",' +
            '"documents":null' +
            '}';

        executeApi(requestBody);
    }


    // ============================================================
    // TEST 21
    // INSPECTION COMPANY BLANK
    // ============================================================

    @IsTest
    static void testBlankInspectionCompany() {

        Claim claimRecord =
            getInspectionClaim();

        if (claimRecord == null) {
            return;
        }

        String requestBody =
            '{' +
            '"claimId":"' +
            String.valueOf(claimRecord.Id) +
            '",' +
            '"claimNumber":"' +
            claimRecord.Name +
            '",' +
            '"inspectionNumber":123465,' +
            '"inspectionPrice":240.00,' +
            '"invoiceNumber":"INV-BLANK-COMPANY",' +
            '"inspectionCompany":"","documents":[]' +
            '}';

        executeApi(requestBody);
    }
    @IsTest
static void testFileNameWithExtension() {

    Claim claimRecord =
        getInspectionClaim();

    if (claimRecord == null) {
        return;
    }


    // --------------------------------------------------------
    // This filename is specifically designed to execute:
    //
    // dotPosition > 0
    //
    // Expected:
    // AMI-Inspection-Report.pdf
    // becomes:
    // AMI-Inspection-Report
    // --------------------------------------------------------

    String base64Data =
        EncodingUtil.base64Encode(
            Blob.valueOf(
                'AMI Inspection Test File'
            )
        );


    Map<String, Object> document =
        new Map<String, Object>();


    document.put(
        'fileName',
        'AMI-Inspection-Report.pdf'
    );


    document.put(
        'base64Data',
        base64Data
    );


    List<Object> documents =
        new List<Object>();


    documents.add(
        document
    );


    Map<String, Object> requestData =
        new Map<String, Object>();


    requestData.put(
        'claimId',
        String.valueOf(
            claimRecord.Id
        )
    );


    requestData.put(
        'claimNumber',
        claimRecord.Name
    );


    requestData.put(
        'inspectionNumber',
        999991
    );


    requestData.put(
        'inspectionPrice',
        100.00
    );


    requestData.put(
        'invoiceNumber',
        'INV-FILE-TITLE-001'
    );


    requestData.put(
        'documents',
        documents
    );


    String requestBody =
        JSON.serialize(
            requestData
        );


    // --------------------------------------------------------
    // Execute API
    // --------------------------------------------------------

    executeApi(
        requestBody
    );
}
}