/**
 * Created by jim.hladek on 11/4/2024.
 */

trigger ServiceAppointmentTrigger on ServiceAppointment (before insert, before update, before delete, after insert, after update, after delete) {
    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('ServiceAppointmentTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('ServiceApointmentTrigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            ServiceAppointmentTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            ServiceAppointmentTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            ServiceAppointmentTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            ServiceAppointmentTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            ServiceAppointmentTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            ServiceAppointmentTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }
}