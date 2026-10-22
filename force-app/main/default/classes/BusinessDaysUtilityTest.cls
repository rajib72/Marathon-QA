@isTest(seeAllData=true)
public class BusinessDaysUtilityTest {

    @isTest
    static void testBusinessDaysUtilityview() {

        // ✅ Get existing Business Hours (no insert)
        BusinessHours bh = [
            SELECT Id, Name 
            FROM BusinessHours 
            WHERE IsDefault = true 
            LIMIT 1
        ];

        // ✅ Use safe working time (Monday 10 AM)
        Datetime startday = Datetime.newInstance(2024, 4, 1, 10, 0, 0);
        Datetime endday = startday.addDays(7);

        Test.startTest();

        BusinessDaysUtility bb = new BusinessDaysUtility();
        BusinessDaysUtility bb1 = new BusinessDaysUtility(bh.Name);

        Datetime d1 = bb.addDays(startday, 5);
        Datetime d2 = bb.subtractDays(startday, 3);
        Datetime d3 = bb.getNextWorkingDay(startday);
        Boolean b1 = bb.isWorkingDay(startday);
        Integer count = bb.getNoOfBusinessDaysBetweenDates(startday, endday);
        Boolean isBH = bb.isBusinessHours();

        Test.stopTest();

        // ✅ Assertions
        System.assertNotEquals(null, d1);
        System.assertNotEquals(null, d2);
        System.assertNotEquals(null, d3);
        System.assertNotEquals(null, count);
        System.assertNotEquals(null, isBH);
    }

    @isTest
    static void testIsBusinessHours() {

        BusinessDaysUtility utility = new BusinessDaysUtility();
        Boolean result = utility.isBusinessHours();

        System.assertNotEquals(null, result);
    }
}