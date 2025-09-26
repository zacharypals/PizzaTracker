trigger ReferralTrigger on Referral__c (after update) {

    if ( FeatureManagement.checkPermission('Disable_Flows') ){
        System.debug('Referral Trigger Disabled');
        return;
    }

    if(Trigger.isAfter ) {
        if(Trigger.isUpdate) {
            ReferralTriggerHandler.CheckIfReferralStatusChanged(Trigger.New, Trigger.oldMap);
        }
    }

}