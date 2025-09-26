/**
 * Created by Chris Meemken - Slalom on 3/25/2025.
 * Used to control Campaign Member functionality. 
 * Initial use is restricting users ability to delete/remove members, due to Salesforce limitations on deleting Campaign Member.
 */

trigger CampaignMemberTrigger on CampaignMember (before insert, after insert, before update, after update, before delete, after delete ){

    Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('CampaignMemberTrigger');

    if ((disable != null && disable.Disabled__c) || FeatureManagement.checkPermission('Disable_Flows')){
        System.debug('CampaignMember Trigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            CampaignMemberTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isUpdate){
            CampaignMemberTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            CampaignMemberTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    } else if (Trigger.isBefore){
        if (Trigger.isInsert){
            CampaignMemberTriggerHandler.beforeInsert(Trigger.new );
        } else if (Trigger.isUpdate){
            CampaignMemberTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            CampaignMemberTriggerHandler.beforeDelete(Trigger.old, Trigger.oldMap);
        }
    }        
}