trigger FSLUserTerritory_Trigger on FSL__User_Territory__c (before insert,before update,before delete) {

    if ( FeatureManagement.checkPermission('Disable_Flows') ){
        System.debug('FSLUserTerritory_Trigger Disabled');
        return;
    }

    if(Trigger.isBefore){
        if(Trigger.isInsert){
            FSLUserTerritoryValidation.validateUserTerritoryInsert(Trigger.new);
        }else if(Trigger.isUpdate){
            FSLUserTerritoryValidation.validateUserTerritoryUpdate(Trigger.new,Trigger.oldMap);
        }else if(Trigger.isDelete){
            FSLUserTerritoryValidation.validateUserTerritoryDelete(Trigger.oldMap);
        }
    }
}