trigger AccountTrigger on Account(before insert, after insert, before update, after update, before delete, after delete ){

    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('AccountTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('Account Trigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            AccountTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            AccountTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            AccountTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            AccountTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            AccountTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            AccountTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }
}