//Created Date: 11.20.2024
//Created By: Chris Meemken - Slalom

trigger NoteTrigger on ContentDocument (before insert, after insert, before update, after update, before delete, after delete ) {

    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('NoteTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('NoteTrigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            NoteTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            NoteTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            NoteTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            NoteTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            NoteTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            NoteTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }
}