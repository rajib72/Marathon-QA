trigger BRECallEventTrigger on BRE_Call_Event__e (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        BRECallEventHandler.handleAfterInsert(Trigger.New);
    }
}