// The speaking pass: the system prompt, and the turn handed to the character.
//
// Both halves are keyed by the contact captured at send time, never by the selection: the
// player may be looking at somebody else by the time this renders.

module AiNpc

class AiNpcPassConversation extends AiNpcPassBuilder {
    let contactId: String;
    // Already taken from the pending store by the lane. Consuming is an act, and a builder
    // performs none.
    let pendingContext: String;
    let intent: String;
    let ask: String;
    let speaksFirst: Bool;

    static func Of(contactId: String, pendingContext: String, intent: String, ask: String,
                   speaksFirst: Bool) -> ref<AiNpcPassConversation> {
        let self = new AiNpcPassConversation();
        self.contactId = contactId;
        self.pendingContext = pendingContext;
        self.intent = intent;
        self.ask = ask;
        self.speaksFirst = speaksFirst;
        return self;
    }

    func Pass() -> String {
        return AiNpcLaneSpeaking();
    }

    func Instruction() -> String {
        return AiNpcBuildSystemPromptWith(this.contactId, this.pendingContext, this.intent,
            this.Recipe());
    }

    // The one place the choice is made. Measured 2026-08-23: a reason placed in <now> is an
    // afterthought in half the replies and dropped in the other half; in V's slot it is the
    // subject every time.
    func Ask() -> String {
        if this.speaksFirst {
            return AiNpcBuildUnpromptedTranscript(this.contactId, this.ask);
        }
        return AiNpcBuildTranscript(this.contactId, this.ask);
    }
}
