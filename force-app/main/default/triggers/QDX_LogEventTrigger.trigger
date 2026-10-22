/*
* @author Qamar Islam (https://github.com/qislam)
*/
trigger QDX_LogEventTrigger on QDX_LogEvent__e (after insert) {

    if(UtilityClass.triggerActiveCheck('QDX_LogEvent__e')) {
        QDX_LogEventTriggerHandler.handleAfterInsert(Trigger.new);
    }
}