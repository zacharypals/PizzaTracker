trigger VisitorTrigger on Visitor (after insert, after delete) {

    //Disable_Apex_Triggers__mdt disable = Disable_Apex_Triggers__mdt.getInstance('VisitorTrigger');

    //if (disable != null && disable.Disabled__c){
    //    return;
    //}

    if ( FeatureManagement.checkPermission('Disable_Flows') ){
        System.debug('VisitorTrigger Disabled');
        return;
    }

    if (Trigger.isAfter){
        if (Trigger.isInsert){
            VisitorTriggerHandler.afterInsert(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete){
            VisitorTriggerHandler.afterDelete(Trigger.old, Trigger.oldMap);
        }
    }
}