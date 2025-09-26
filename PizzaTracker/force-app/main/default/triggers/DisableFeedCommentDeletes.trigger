/**
 * Author: Marcus Ericsson - mericsson@salesforce.com
 */
trigger DisableFeedCommentDeletes on FeedComment (before delete) {

if ( FeatureManagement.checkPermission('Disable_Flows') ){
    System.debug('DisableFeedCommentDelete Trigger Disabled');
    return;
}


    if (!DisableChatterDeleteDelegate.allowDelete()) {
        for(FeedComment f : Trigger.old){
            f.addError('Your administrator has disabled Chatter post and comment deletions.'); 
        }
    }
}