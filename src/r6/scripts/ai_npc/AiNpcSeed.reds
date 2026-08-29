// Giving a conversation a starting point. A provider describes who a contact is; this
// describes what has already been said.
//
// The case that forced it: a mod pushes an unsolicited SMS through its own phone UI, the
// player opens the free-text chat to answer, and the chat is empty. One conversation stored
// once and read by both screens is the fix; duplicating the text into both is not.
//
// Three entry points, for three different things to seed:
//
//   AiNpcSeedMessage   something that was said. Shown in the chat, sent to the model.
//   AiNpcSeedContext   something that is true. Never shown, injected into <now> once.
//   AiNpcOpenChatOn    open the chat on a given contact, from anywhere.
//
// All three are safe outside a session and before the contact has been used: they return
// false rather than failing. AiNpcRequestChatFromNotification at the bottom is not public
// API -- it is the same opening, asked for from this mod's own SMS popup.

/// Messages ///

// Appends to a contact's history as if it had been exchanged: displayed in the chat, carried
// in the transcript, persisted, undoable. Seeding is not sending -- nothing here pushes a
// notification or opens anything, because the mod that owns the contact has its own idea of
// how a message reaches the player.
//
// Refreshes the chat when it is open on that contact: without it, a message seeded while the
// player is reading the thread appears only after a close and reopen.
module AiNpc

// The author is announced, never stored. sourceId reaches the listeners and stops there: a
// listener has to tell its own writes from everyone else's, and every other use of
// attribution is equally session-bound.
//
// Storing it would buy one thing more -- retracting a line written in an earlier session --
// and there is no such operation, because what was said stays: a mod being uninstalled does
// not un-happen the conversation the player had. An author naming a mod no longer installed
// invites code that branches on whether it still is.
func AiNpcSeedMessage(contactId: String, text: String, fromPlayer: Bool, opt sourceId: String) -> Bool {
    if Equals(StrLen(contactId), 0) || Equals(StrLen(text), 0) {
        return false;
    }

    // Through AiNpcAppendMessage rather than the store, because that is where a message
    // entering a thread is announced: reaching past it would make a seeded line the one kind
    // no listener hears about.
    if !AiNpcAppendMessage(contactId, text, fromPlayer, sourceId) {
        return false;
    }
    AiNpcLog(s"Seeded a message into '\(contactId)' (fromPlayer=\(fromPlayer)).");

    // A rebuild from the store rather than a published reply: a published reply is drawn as
    // the character speaking, and this can seed a message from V. The store knows who said it.
    let system = GetAiNpcSystem();
    if IsDefined(system) {
        let view = system.GetPhoneView();
        if IsDefined(view) && Equals(view.GetShownContactId(), contactId) {
            view.RefreshConversation();
        }
    }
    return true;
}

/// Context ///

// Facts the character should know before answering, injected into <now> for the next
// generation on this contact and then dropped. Never displayed, never part of the transcript,
// and it does not survive a save: for what is true right now, where GetLiveContext on a
// provider is for what is true continuously.
//
// Scoped to a contact, because context pushed for one character can sit unconsumed and a
// single pending slot would hand it to whoever is opened next.
//
// sourceId keys the line so a second mod seeding for the same contact adds to what is waiting
// rather than erasing it; "" is ai_npc's own voice and sorts first. Required rather than
// `opt`: it was optional for a day and three call sites forgot it, each filing a mod's line as
// ai_npc's own, so two mods writing about one contact landed on the same key and the first was
// erased. An omitted `opt` and a deliberate "" are the same three characters.
func AiNpcSeedContext(contactId: String, text: String, sourceId: String) -> Bool {
    if Equals(StrLen(contactId), 0) || Equals(StrLen(text), 0) {
        return false;
    }

    // A mod may seed this at run time without going through any config file, so the check
    // that facts.*.json gets at load happens here for everyone else -- see AiNpcSectionText.
    let safe = AiNpcSafeSectionText(text, sourceId);
    if Equals(StrLen(safe), 0) {
        return false;
    }

    if !AiNpcSetPendingContext(contactId, safe, sourceId) {
        return false;
    }

    AiNpcLog(s"Seeded context for '\(contactId)'.");
    return true;
}

/// Opening ///

// Opens the free-text chat on a contact, wherever the player is in the phone. The two steps
// are inseparable: selecting without opening leaves the phone in a state where the next
// RefreshInputHints reselects whatever the dialer is pointing at, and the chat then shows a
// different conversation than the one asked for.
//
// Idempotent, because opening builds a whole chat UI into the container: twice stacks two, and
// the widgets corrupt until the phone is closed. A caller wired to a button in someone else's
// screen cannot see the chat is already open, so the guard lives here.
//
// A code rather than a Bool: "already there" is a success a caller acts on differently from
// "just opened" -- a mod that scrolls to its own message has no business doing so when the
// player was already reading the thread.
//
// It goes through OpenChatFor, the same door as T, and inherits the same refusals: no usable
// phone tree, the phone put away, an unsupported contact, an unclaimable phone.
func AiNpcOpenChatOn(contactId: String) -> Int32 {
    if !AiNpcIsContactSupported(contactId) {
        AiNpcLog(s"Refused to open the chat on '\(contactId)': not a supported contact.");
        return AiNpcOpenNotDriven();
    }

    let system = GetAiNpcSystem();
    if !IsDefined(system) {
        return AiNpcOpenPhoneUnavailable();
    }

    // The PHONE's contact, not AiNpcCurrentContactId(): this whole function is about the phone,
    // and the general question would answer AGENT LINK's thread whenever the terminal is the
    // more recently painted surface -- reporting "already there" about a screen the caller was
    // not asking to open.
    if system.GetChatOpen() {
        if Equals(system.GetContactId(), contactId) {
            return AiNpcOpenAlreadyThere();    // opening again would build a second chat
        }

        // Open on someone else: swap the conversation rather than rebuild the UI, since the
        // widgets are the same and only their contents differ.
        system.SwitchChatTo(contactId);
        AiNpcLog(s"Switched the open chat to '\(system.GetContactId())'.");
        return AiNpcOpenOk();
    }

    let opened = system.OpenChatFor(contactId, "the public API");
    if opened {
        AiNpcLog(s"Opened the chat on '\(system.GetContactId())' (requested '\(contactId)').");
        return AiNpcOpenOk();
    }
    // Without the current contact: a refusal leaves the previous conversation selected, so
    // naming it read as "we opened river_ward when asked for anon_..." in gamelog and cost an
    // evening. The only contact this line may name is the one that was asked for.
    AiNpcLog(s"Refused to open the chat on '\(contactId)': the phone would not take it.");
    // Refused by the phone: in a menu, in combat, or the HUD is not up. The caller may retry,
    // which is why this is not the same answer as "not a supported contact".
    return AiNpcOpenPhoneUnavailable();
}

/// Opening from a message notification ///

// Not a fourth door: the same door as T, reached from the popup instead of from the phone.
// Separate from AiNpcOpenChatOn because it answers what that one cannot -- what to do when
// there is no contact list yet.
//
// False is the ordinary answer with the phone put away, and means "the note is armed, take the
// phone out": the caller acts on it rather than logging it.
func AiNpcRequestChatFromNotification(contactId: String) -> Bool {
    if !AiNpcIsContactSupported(contactId) {
        AiNpcLog(s"Notification for '\(contactId)' cannot be opened: not a supported contact.");
        return false;
    }

    let system = GetAiNpcSystem();
    if !IsDefined(system) {
        return false;
    }
    return system.RequestChatFromNotification(contactId);
}
