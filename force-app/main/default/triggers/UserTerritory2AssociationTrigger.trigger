trigger UserTerritory2AssociationTrigger on UserTerritory2Association (before insert, after insert, before update, after update, after delete) {

Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('UserTerritory2AssociationTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('UserTerritory2AssociationTrigger Disabled');
        return;
    }
	
    if (Trigger.isBefore){
        if (Trigger.isInsert){
            UserTerritoryTriggerHandler.beforeInsert(Trigger.new);
        }else if (Trigger.isUpdate){
            UserTerritoryTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
    else if (Trigger.isAfter){
        if (Trigger.isInsert){
            System.debug('Hit UserTerritory2AssociationTrigger onAfterInsert');
            UserTerritoryTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        }else if (Trigger.isUpdate){
            System.debug('Hit UserTerritory2AssociationTrigger onAfterUpdate');
            UserTerritoryTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }else if (Trigger.isDelete){
            UserTerritoryTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    }
}