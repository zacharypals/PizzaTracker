trigger EventTrigger on Event (before insert) {
    
    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('EventTrigger');
    
    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('EventTrigger Disabled');
        return;
    }
    
    if (Trigger.isAfter){
        if (Trigger.isInsert){
            EventTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            EventTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            EventTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            EventTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            EventTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            EventTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }
}