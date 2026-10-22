/**
* @author Waidehee Kuradkar
* @dateModified 2025-05-19
* @description Trigger on Vin Detail object
*/
trigger VINDetailTrigger on VIN_Detail__c (after insert,after update) {
    if(UtilityClass.triggerActiveCheck('VIN_Detail__c') ){
        if (Trigger.isAfter && Trigger.isInsert){
            VINDetailTriggerHandler.handleAfterInsert(Trigger.new, Trigger.oldMap, Trigger.isUpdate); 
        }  
        
        if (Trigger.isAfter && Trigger.isUpdate){
            VINDetailTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap, Trigger.isUpdate); 
        }             
    }

}