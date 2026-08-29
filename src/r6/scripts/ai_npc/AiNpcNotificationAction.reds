// What the message notification's open key does, when the message is ours.
//
// The game shows an SMS popup with a prompt to open the thread it announces; on a keyboard
// that key is T (action NotificationOpenSMS, mapping NotificationSMS_Button). The popup runs
// whatever action it was handed, so the key is not something a mod binds -- it is something a
// mod ANSWERS, by handing over the right action.
//
// Vanilla's own OpenPhoneMessageAction cannot serve: it opens a JOURNAL thread, found from
// PhoneMessageNotificationViewData.contactHash, which nothing in this mod writes -- so the
// phone comes up on no thread at all. Filling the hash in would not help either: a
// conversation this mod drives is not a journal thread, and for a shipped contact the hash
// would open CDPR's own messenger on the same character, a second empty conversation next to
// the real one. So the identity travels as the contact id, in the action.
//
// It EXTENDS the vanilla action rather than its base. Overriding Execute on
// GenericNotificationBaseAction compiles too, and works if the game dispatches virtually;
// extending OpenPhoneMessageAction does not need that assumption, since an action of this type
// still IS one and a cast on the game's side finds what it expects. It also inherits the one
// job this mod cannot do itself -- taking the phone out goes through PhoneSystem internals no
// mod can reach -- called through super when, and only when, the phone has to move.
module AiNpc

public class AiNpcOpenChatNotificationAction extends OpenPhoneMessageAction {
    // Who wrote. The one thing the notification must carry: it is pushed precisely when no
    // surface is showing this conversation, so "the contact on screen" is by definition
    // somebody else.
    public let contactId: String;

    // The player pressed it.
    //
    // Two outcomes, and the difference is whether a contact list exists yet. When one does,
    // the chat opens on the spot and the phone must NOT be touched -- calling super there
    // would navigate away from the screen just opened. When one does not, the request leaves a
    // note and the phone is raised; the note is answered by the contact list on its way up.
    public func Execute(userData: ref<IScriptable>) -> Void {
        if AiNpcRequestChatFromNotification(this.contactId) {
            return;
        }
        super.Execute(userData);
    }
}

// The action a notification for `contactId` must carry.
//
// Built here rather than at the push site so that the push site stays what it is -- a function
// that draws a popup -- and so that there is one place to read what the open key will do.
func AiNpcNotificationOpenAction(contactId: String, phoneSystem: wref<PhoneSystem>) -> ref<OpenPhoneMessageAction> {
    let action = new AiNpcOpenChatNotificationAction();
    action.contactId = contactId;
    action.m_phoneSystem = phoneSystem;
    return action;
}
