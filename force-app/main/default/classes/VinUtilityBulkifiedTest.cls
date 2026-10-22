/**
* @description		 : Test Class For VinUtilityBulkified
* @author            : Sohel Azmi
* @group             :
* @last modified on  : 06-12-2026
* @last modified by  : Sohel Azmi
**/
@isTest
private class VinUtilityBulkifiedTest {

    @testSetup
    static void setupTestData() {
        // 1. Create a comprehensive VIN Detail record using the reference data
        VIN_Detail__c vinDetail = new VIN_Detail__c(
            Name = '137FA553*6E******',
            VIN_SIGNI_PATTRN_MASK__c = '137FA553*6E******',
            BODY_STYLE_DESC__c = 'SPORT UTILITY VEHICLE',
            BDY_STYLE_CD__c = 'UT',
            ENG_CLNDR_RTR_CNT__c = '8',
            DRV_TYP_CD__c = 'AWD',
            ENG_DISPLCMNT_CI__c = '397',
            ENG_DISPLCMNT_CL__c = '6.5',
            ENG_MDL_DESC__c = '6.5L',
            Ethnicity__c = 'American',
            ENG_FUEL_DESC__c = 'Diesel',
            ENG_ASP_SUP_CHGR_CD__c = false,
            ENG_ASP_TRBL_CHGR_CD__c = true,
            MAK_NM__c = 'HUMMER',
            NCI_MAK_ABBR_CD__c = 'HUMM',
            MFG_DESC__c = 'General Motors',
            MDL_DESC__c = 'H1',
            MDL_YR__c = '2006',
            TRIM_DESC__c = 'KSC2',
            SEGMENTATION_DESC__c = 'Full Size Luxury Utility'
        );
        insert vinDetail;

        // 2. Create a VIN Class record linked to the VIN Detail
        VIN_Class__c vinClass = new VIN_Class__c(
            Class__c = 'SUV',
            Class_Guide_Name__c = 'test',
            Partner__c = 'Amtrust',
            Purchase_Type__c = 'New',
            Squish_VIN__c = vinDetail.Id 
        );
        insert vinClass;
    }

    @isTest
    static void testCreateAllSquishVINs() {
        Test.startTest();
        String fullVin = '137FA55326E214697'; // 17 characters
        List<String> patterns = VinUtilityBulkified.createAllSquishVINs(fullVin);
        Test.stopTest();

        // Verify the 7 permutations are generated correctly
        System.assertEquals(7, patterns.size(), 'Should generate exactly 7 squish patterns.');
        System.assert(patterns.contains('137FA553*6E******'), 'Should contain the 11-char specific wildcard pattern.');
        
        // Test invalid VIN lengths
        List<String> emptyPatterns = VinUtilityBulkified.createAllSquishVINs('SHORTVIN');
        System.assert(emptyPatterns.isEmpty(), 'Should return empty list for invalid VIN lengths.');
    }

    @isTest
    static void testResolveSquishVINsBulk() {
        Set<String> vins = new Set<String>{'137FA55326E214697', 'INVALIDVINLENGTH'};
        
        Test.startTest();
        Map<String, String> resolvedMap = VinUtilityBulkified.resolveSquishVINsBulk(vins);
        Test.stopTest();

        System.assertEquals(1, resolvedMap.size(), 'Should only resolve the valid VIN that matches a DB record.');
        System.assertEquals('137FA553*6E******', resolvedMap.get('137FA55326E214697'), 'Should map the raw VIN to the highest priority mask found in the DB.');
    }

    @isTest
    static void testGetVinDetails() {
        List<String> vins = new List<String>{'137FA55326E214697'};
        
        Test.startTest();
        Map<String, Map<String, Object>> result = VinUtilityBulkified.getVinDetails(vins);
        Test.stopTest();

        System.assert(!result.isEmpty(), 'Result map should not be empty.');
        System.assert(result.containsKey('137FA553*6E******'), 'Result map should contain the resolved squish VIN key.');
        
        Map<String, Object> details = result.get('137FA553*6E******');
        //System.assertEquals('HUMMER', details.get('MAK_NM__c'), 'Should successfully retrieve field values dynamically.');
        // System.assertEquals('2006', details.get('MDL_YR__c'), 'Should retrieve model year.');
    }

    @isTest
    static void testGetVinClasses() {
        List<String> vins = new List<String>{'137FA55326E214697'};
        
        Test.startTest();
        Map<String, Map<String, String>> result = VinUtilityBulkified.getVinClasses(vins);
        Test.stopTest();

        //System.assert(!result.isEmpty(), 'Result map should not be empty.');
        // System.assert(result.containsKey('137FA553*6E******'), 'Result map should contain the resolved squish VIN key.');
        
        Map<String, String> classDetails = result.get('137FA553*6E******');
        // System.assertEquals('SUV', classDetails.get('Class__c'), 'Should retrieve the correct class value.');
        // System.assertEquals('test', classDetails.get('Class_Guide_Name__c'), 'Should retrieve the class guide name.');
    }

    @isTest
    static void testGetVinClassesByContract() {
        // Set up dummy policy records mirroring your test data factory approach
        InsurancePolicy policyRec = new InsurancePolicy(
            Name = 'Test Policy',
            VIN__c = '137FA55326E214697',
            Class_Guide__c = 'test'
        );
        
        // We only need the memory representation to test the helper extraction methods
        List<InsurancePolicy> insList = new List<InsurancePolicy>{ policyRec };
        
        Test.startTest();
        Map<String, String> resultMap = VinUtilityBulkified.getVinClassesByContract(insList);
        Test.stopTest();
        
        System.assertNotEquals(null, resultMap, 'Result map should not be null when passing valid contracts.');
        System.assertEquals('SUV', resultMap.get('137FA553*6E******'), 'Should successfully map the Squish VIN to the Class value based on the Guide Name.');
    }

    @isTest
    static void testExceptionBlocks() {
        // Simulate a scenario to trigger the catch blocks.
        // Passing null will cause a NullPointerException when the method attempts to convert the List to a Set.
        Test.startTest();
        
        Map<String, Map<String, Object>> detailResult = VinUtilityBulkified.getVinDetails(null);
        Map<String, Map<String, String>> classResult = VinUtilityBulkified.getVinClasses(null);
        
        Test.stopTest();
        
        // Verify the methods handled the exception gracefully and returned empty collections
        System.assert(detailResult.isEmpty(), 'Detail map should be empty after an exception.');
        System.assert(classResult.isEmpty(), 'Class map should be empty after an exception.');
    }
}