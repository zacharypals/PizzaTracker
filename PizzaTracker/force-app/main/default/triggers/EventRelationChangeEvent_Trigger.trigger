trigger EventRelationChangeEvent_Trigger on EventRelationChangeEvent (after insert) {
    system.debug('in trigger');
    if ( FeatureManagement.checkPermission('Disable_Flows') ){
        System.debug('EventRelationChangeEvent_Trigger Disabled');
        return;
    }

    List<EventRelationChangeEvent> relationChanges = Trigger.New;
    
	for(EventRelationChangeEvent relationChange : Trigger.New){
            EventBus.ChangeEventHeader header = relationChange.ChangeEventHeader;
            system.debug('relationChange: '+relationChange);
            //if(relationChange.Object_Type_Name__c = 'Visit'){
                if(header.changetype == 'CREATE'){
                    
                }else if(header.changetype == 'DELETE'){
                    
                }
            //}
        }
}