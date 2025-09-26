trigger ContactTrigger on Contact(before insert, after insert, before update, after update, before delete, after delete ){

    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('ContactTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('Contact Trigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            ContactTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            ContactTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            ContactTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            ContactTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            ContactTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            ContactTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }
}