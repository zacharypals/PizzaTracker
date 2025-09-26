trigger OpportunityTrigger on Opportunity (after update) {

    if ( FeatureManagement.checkPermission('Disable_Flows') ){
        System.debug('OpportunityTrigger Disabled');
        return;
    }
    
    if (Trigger.isAfter){
        if (Trigger.isUpdate){
            OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}