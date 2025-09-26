trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {

    if ( FeatureManagement.checkPermission('Disable_Flows') ){
        System.debug('ContentDocumentLink Trigger Disabled');
        return;
    }

    // Handle After Insert
       if(Trigger.isAfter && Trigger.isInsert){
        
       }

}