// A conversation the player has asked for, waiting for a phone that can show it.
//
// The problem it exists for: the message notification's open key is pressed while the phone is
// PUT AWAY. There is no contact list yet, so there is nowhere to draw a chat -- OpenChat
// refuses, correctly, and always will. The screen the chat needs is built a few frames later,
// by the game, in response to the same key press.
//
// So the intent has to outlive the press by exactly one screen. That is all this holds: one
// contact id, taken once, by whoever builds that screen.
//
// SINGLE SHOT, AND THAT IS THE WHOLE SAFETY ARGUMENT. A note that could be read twice would
// reopen a conversation the player had just backed out of; a note with no owner would fire on
// a contact list the player reached ten minutes later for another reason. Take() clears as it
// answers, and Drop() exists so the one caller who knows the phone is gone can say so.
module AiNpc

public class AiNpcPhoneOpenIntent {
    private let m_contactId: String;

    // Note that the player wants this conversation as soon as a contact list exists.
    //
    // Overwrites rather than queues. Two notifications answered before either screen arrived
    // means the player pressed twice, and the second press is the one they meant -- a queue
    // would open the first and leave the second to fire on a later, unrelated contact list.
    public func Arm(contactId: String) -> Void {
        this.m_contactId = contactId;
    }

    public func IsArmed() -> Bool {
        return StrLen(this.m_contactId) > 0;
    }

    // The contact, once. Empty when nothing was asked for, which is the ordinary answer.
    public func Take() -> String {
        let contactId = this.m_contactId;
        this.m_contactId = "";
        return contactId;
    }

    // Forget it. Called when the phone goes away without ever showing a contact list: the
    // press it came from is spent, and a note kept past that point is a chat that opens by
    // itself the next time the player takes their phone out.
    public func Drop() -> Void {
        this.m_contactId = "";
    }
}
