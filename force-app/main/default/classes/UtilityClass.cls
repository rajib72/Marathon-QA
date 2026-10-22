/**
* @author Saurabh Rawat
* @dateModified 2024-04-22
* @description Common Utility for Constants and Utility functions
*/
public class UtilityClass {
    public static final String UNLIMITED_NOTES_EDITING_PERM_NAME = 'Unlimited_Notes_Editing';
    public static final String CONTENT_DOCUMENT_NOTES = 'SNOTE';
    public static final String NOTES_NOT_DELETABLE_ERR_MSG = 'You cannot remove a note that’s created more than 24 hours ago.';
    public static final string NOTES_NOT_EDITABLE_ERR_MSG = 'You cannot edit a note that’s created more than 24 hours ago.';
    public static final String BATCH_EXPIRED_CONTRACT_ERR_MSG = 'Processing error in the Contract Expiration job';
    public static final string contractStatus_Active='Active';
    public static final string contractStatus_InWaiting='In Waiting';
    public static final string contractStatus_Cancelled='Cancelled';
    public static final string contractStatus_Expired='Expired';
    public static final String ROP_MATCHINGCONTRACT_ERR_MSG = 'Matching contract is not found for contract number ';
    public static final String FILE_PREVIEW_URL = '/lightning/page/filePreview?selectedRecordId=';
    
    public static final String FUNDING_IMPORT_ERR_MSG = 'A matching contract (by contract number) was not found';
    public static final String FUNDING_FLOW_STARTED = 'Funding allocation job has been started';
    public static final String FUNDING_FLOW_JOB_RUNNING = 'Another allocation job is already running.  Please try it later.';
    public static final String FUNDING_FLOW_INTERNAL_ERR = 'An internal error has happened.  Please contact an administrator.';
    
    public static final String SHARE_TYPE_V = 'V';
    public static final String VISIBILITY_INTERNALUSERS = 'InternalUsers';
    public static final String METHOD_attachFileFromTCCode = 'attachFileFromTCCode';
    public static final String PRODUCT_SECUREONE = 'SecureOne';
    
    public static final String CONTRACT_CANCEL_CODE_04 = '04 ROP REQUEST';
    public static final String CONTRACT_CANCELLATION_REASON_TYPE_NON_PAYMENT = 'NON PAYMENT';
    public static final String CONTRACT_DUPLICATE_ERROR_MESSAGE = 'A duplicate Contract was found with the same Contract Number.';
    public static final String NEW_YORK = 'NY';
    public static final String PROGRAM_CODE = 'TRWL';
    public static final String MASTERCARD_QDX_PROPERTIES = 'MC Company Id,MC Consumer Key,MC Description,MC Expiration Date,MC Private Key,MC Purchase Template Id,MC Real Card Number,MC Real Card Number Alias,MC Supplier Id,MC URL,MC Validity Period';
    public static final String RULENAME = 'B';
    public static final String RULETYPE = 'A';
    public static final String TIMEZONE = 'America/Chicago';
    public static final String CURRENCYTYPE = 'B';
    public static final String CURRENCYCODE = '840';
    public static final String PERIOD = 'C';
    public static final String MAXTRANS = '1';
    public static final String DISABLECARDIMAGE = 'Y';
    public static final String PURCHASE_TYPE = 'BOKF Standard';
    public static final String VALIDFOR = '24';
    public static final String BR_TYPE_DM = 'decision-matrices';
    public static final String BR_TYPE_EX = 'expressionSet';
    public static final String Insurance_Carrier_Developer_Name = 'Insurance_Carrier';
    public static final String Service_Center_Developer_Name = 'Service_Center';
    public static final String INCLUDE_ALL = 'Include All';
    public static final String CANCELLED_BY_ADMINISTRATOR = 'CANCELLED BY ADMINISTRATOR';
    public static final String FLAT_CANCEL_FOR_TMU = 'FLAT CANCEL FOR TMU';
    public static final String INELIGIBLE_VEHICLE = 'INELIGIBLE VEHICLE';
    public static final String SALVAGED_BRANDED_TITLE = 'SALVAGED/BRANDED TITLE';
    public static final String NEW_CLASS_GUIDE = 'NewClassGuide';
    public static final String STANDARD_CANCEL_WINDOW_REFUND_CALC = 'Standard';
	public static final String DEDUCT_CLAIM_CANCEL_WINDOW_REFUND_CALC = 'Deduct Claims';
    public static final String NO_CANCEL_FEE_CANCEL_WINDOW_REFUND_CALC = 'No Cancel Fees';
    public static final String IS_INTERNAL_CALL = 'Internal Call';
    public static final String IS_EXTERNAL_CALL = 'External Call'; 
    
    
/** 
* @description: check current user have Unlimited_Notes_Editing custom permission
* */
    public static Boolean checkUnlimitedNoteEditingPerm(){
        return FeatureManagement.checkPermission(UNLIMITED_NOTES_EDITING_PERM_NAME);
   }

/** 
* @description: Format Exception Params into a log message format
* @param Exception Exception instance of a batch
* @param BatchJobId Current Batch Job Id
* @return String Log formatted Message
* */    
    public static String formatBatchErrorMessage(Exception batchException, String BatchJobId){
    String logMessage = '';
        if(batchException != null && String.isNotBlank(BatchJobId)){
            logMessage += String.format(
                'Subject: {0} Job Id: {1}.\n Message: {2} \n at line: {3}, \n Full StackTrace: {4}', 
            new List<Object>{BATCH_EXPIRED_CONTRACT_ERR_MSG, BatchJobId,batchException.getMessage(),
                batchException.getLineNumber(),batchException.getStackTraceString() }
        );
        }
        return logMessage;
    }

     /** 
* @description: check the trigger is active or not using metadata
* @param triggerObject object name
* */
    public static Boolean triggerActiveCheck (String triggerObject){    
        List<Trigger_Setting__mdt> setting = new List<Trigger_Setting__mdt>([SELECT Id, IsActive__c, Label FROM Trigger_Setting__mdt WHERE Label =: triggerObject]);
        if(!setting.isEmpty() && setting[0].IsActive__c) {
            return true;
        }else{
            return false;
        }
    }

     /** 
    * @description: return record type id from developer name of given object
    * @param object name, record type developername
    * */
   /* public static Id getsObjectRecordTypeId (String objectApiName, String developerName){    
        SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        Id recTypeId = objType.getDescribe().getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
        return recTypeId;
    } */
    
    public static List<Id> getsObjectRecordTypeId(String objectApiName, List<String> developerNames) {
        SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        Map<String, Schema.RecordTypeInfo> recTypeMap = objType.getDescribe().getRecordTypeInfosByDeveloperName();
        List<Id> recTypeId = new List<Id>();
        
        for(String devName : developerNames) {
            if(recTypeMap.containsKey(devName)) {
                recTypeId.add(recTypeMap.get(devName).getRecordTypeId());
            }
        }
        return recTypeId;
    } 
    
    //returns the map with Drivetrain field mapping for DecodeVin API
    public static Map<String, String> getDriveTrainValue() {
        return new Map<String, String>{'4FD' => '4WD', '4RD' => '4WD', '4WD' => '4WD', 'AWD' => 'AWD', 'FWD' => '2WD', 'RWD' => '2WD'};
    }
    
	
	// For weekly: list of day names; for monthly: ["15"]; for last day: ignored
	// This method is used for to calculate Next Start date based on Weekly or Monthly Selection
    public static Date getNextFollowupDate( Date currentDate, String recurrenceTypeObj, List<String> recurrenceDetail, Boolean isLast) {
        if(currentDate == NULL){
           currentDate = Date.today();
        }
        
        if (recurrenceTypeObj == 'Weekly') {
            return getNextWeeklyDate(currentDate, recurrenceDetail);
        } else if (recurrenceTypeObj == 'Monthly' && !isLast) {				//Not Last Day of Month
            Integer dayOfMonth = Integer.valueOf(recurrenceDetail[0]);
            return getNextMonthlyDate(currentDate, dayOfMonth);
        } else if (recurrenceTypeObj == 'Monthly' && isLast) {				// Last day of Month
            return getNextLastDayOfMonth(currentDate);
        } else {
            throw new IllegalArgumentException('Unsupported recurrence type');
        }
    }
    // Calculate the Next start date if Frequency is Weekly
    public static Date getNextWeeklyDate(Date currentDate, List<String> weekdays) {
        Map<String, Integer> weekdayMap = new Map<String, Integer>{
            'Sunday' => 0, 'Monday' => 1, 'Tuesday' => 2, 'Wednesday' => 3,
            'Thursday' => 4, 'Friday' => 5, 'Saturday' => 6
        };

        Integer currentDOW = currentDate.toStartOfWeek().daysBetween(currentDate);

        Date nextDate = null;

        for (String day : weekdays) {
            if (!weekdayMap.containsKey(day)) continue;
     			Integer targetDOW = weekdayMap.get(day);
            	Integer tempDays = targetDOW - currentDOW + 7;
            	Integer daysUntil = Math.mod(tempDays, 7);
            	if (daysUntil == 0) {
                	daysUntil = 7; // Skip current day
            	}
            	Date candidate = currentDate.addDays(daysUntil);
            	if (nextDate == null || candidate < nextDate) {
                	nextDate = candidate;
            	}
        }

        return nextDate;
    }

    // Calculate the Next start date if Frequency is Monthly and Day is not Last day of Month
    public static Date getNextMonthlyDate(Date currentDate, Integer targetDay) {
        Integer year = currentDate.year();
        Integer month = currentDate.month();
        Integer maxDays = Date.daysInMonth(year, month);

        Integer clampedDay = Math.min(targetDay, maxDays);
        Date candidate = Date.newInstance(year, month, clampedDay);

        if (candidate <= currentDate) {
            // Move to next month
            month++;
            if (month > 12) {
                month = 1;
                year++;
            }
            maxDays = Date.daysInMonth(year, month);
            clampedDay = Math.min(targetDay, maxDays);
            candidate = Date.newInstance(year, month, clampedDay);
        }

        return candidate;
    }
	
    // Calculate the Next start date if Frequency is Monthly and Day is Last day of Month
    public static Date getNextLastDayOfMonth(Date currentDate) {
        Integer year = currentDate.year();
        Integer month = currentDate.month();
        Integer lastDay = Date.daysInMonth(year, month);

        Date candidate = Date.newInstance(year, month, lastDay);
        if (candidate <= currentDate) {
            // Move to next month
            month++;
            if (month > 12) {
                month = 1;
                year++;
            }
            lastDay = Date.daysInMonth(year, month);
            candidate = Date.newInstance(year, month, lastDay);
        }
        return candidate;
    }
}