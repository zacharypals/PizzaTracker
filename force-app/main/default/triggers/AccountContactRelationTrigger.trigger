/**
 * Created by jim.hladek on 10/18/2024.
 */

trigger AccountContactRelationTrigger on AccountContactRelation (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('AccountContactTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('Account Contact Relationship Trigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            AccountContactRelationTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            AccountContactRelationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            AccountContactRelationTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            AccountContactRelationTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}