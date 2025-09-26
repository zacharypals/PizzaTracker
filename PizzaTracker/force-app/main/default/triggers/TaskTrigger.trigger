/**
 * Created by jim.hladek on 10/8/2024.
 */

trigger TaskTrigger on Task (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('TaskTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('TaskTrigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            TaskTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            TaskTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            TaskTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            TaskTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            TaskTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            TaskTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }
}