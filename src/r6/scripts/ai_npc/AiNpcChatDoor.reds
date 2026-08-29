// THE ONE PLACE A CONVERSATION OPENS AND CLOSES, whichever surface opens it.
//
// A session's shown contact IS the conversation: `Show` puts one on screen and `Close` takes
// it away. Everything that has to happen at those two moments happens here, so a surface
// cannot forget half of it -- and one did. The announcement lived in AiNpcSystem.ShowModChat,
// which is the phone's door and nobody else's, so AGENT LINK opened conversations that no
// listener ever saw and, worse, that never reached AiNpcMemoryService: idle compaction has
// exactly one trigger point and a terminal-only player never crossed it. Switching contact
// inside the phone was silent for the same reason -- SwitchChatTo repaints, it does not
// reopen.
//
// Above the session, not inside it. Rule 3b of docs/VIEW_ARCHITECTURE.md and check 8d of
// tools\lint.ps1 forbid AiNpcChatSession from reaching for a system, because the self-tests
// build a session at game start where no system exists yet; the extension registry and the
// memory service are both systems. So the announcement sits one cran up, in free functions,
// and the session stays a thing a test can hold.
//
// AiNpcConversationOpening is the whole decision, and it is pure so that the tests own it.
// Same shape as AiNpcSessionAccepts next door: what is left below it is the reaching.

module AiNpc

// Whether showing `requested` on a surface currently showing `shown` opens a conversation.
//
// An empty request is not an opening: a conversation named "" is a history nothing can read
// back, and it is the shape a widget hands over when its contact could not be resolved.
// Re-showing what is already up is not one either -- the phone rebuilds its chat on a HUD
// rebuild, and a listener counting openings would count those.
func AiNpcConversationOpening(shown: String, requested: String) -> Bool {
    if Equals(StrLen(requested), 0) {
        return false;
    }
    return NotEquals(shown, requested);
}

// Answers whether a conversation was opened, so a caller that guessed a contact can say no.
//
// The close of the previous thread is published FIRST and from here, which is what makes a
// contact switch a pair rather than a silence: a listener holding per-thread state gets the
// end of the old one before the start of the new one, in that order, on both surfaces.
func AiNpcOpenConversation(session: ref<AiNpcChatSession>, contactId: String) -> Bool {
    if !IsDefined(session) {
        return false;
    }

    let shown = session.GetShownContactId();
    if !AiNpcConversationOpening(shown, contactId) {
        if Equals(StrLen(contactId), 0) {
            AiNpcLog("Refused to open a conversation with no contact id.");
        }
        return false;
    }

    if NotEquals(StrLen(shown), 0) {
        AiNpcPublishConversationClosed(shown);
    }

    session.Show(contactId);
    AiNpcPublishConversationOpened(contactId);

    // The idle compaction's one trigger point: the moment the elapsed silence becomes readable
    // and the memory is about to be needed. The service declines on its own if nothing has
    // piled up.
    let memory = AiNpcGetMemoryService();
    if IsDefined(memory) {
        memory.NotifyConversationOpened(contactId);
    }
    return true;
}

// Close, not Show(""): the typing and busy flags belong to the conversation that is going
// away. A surface that comes back reads the lane for the real answer.
//
// Silent when nothing was shown, which is the ordinary case -- both surfaces clear their page
// before building the next one, so this runs on every navigation.
func AiNpcCloseConversation(session: ref<AiNpcChatSession>) -> Void {
    if !IsDefined(session) {
        return;
    }

    let shown = session.GetShownContactId();
    session.Close();
    if NotEquals(StrLen(shown), 0) {
        AiNpcPublishConversationClosed(shown);
    }
}
