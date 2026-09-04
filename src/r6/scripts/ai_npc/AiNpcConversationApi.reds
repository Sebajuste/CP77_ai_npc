// Reading and writing a conversation from outside a game session's guarantees.
//
// AiNpcConversationStore owns the history: one ordered, per-contact message list, trimmed,
// journalled and tied to the savegame.
//
// THE BOUNDARY IS A LAYER, NOT A DOOR, and stating it as a door was how it drifted. The store
// layer is the store itself, AiNpcMemoryService and AiNpcJournalApi; inside it the store is
// held directly, because a compaction reads the messages, reads the memory and writes both
// under one consistency check -- one operation that three facade calls would take apart. The
// CET debug window is the fourth case and cannot be helped: a scripted global in a module is
// not a Lua global, so from the console the only way in is the store's own qualified name.
//
// EVERYTHING ABOVE THAT LAYER COMES THROUGH HERE. tools\lint.ps1 enforces the list, because
// the two callers that had drifted -- the client's ForgetConversation and the public
// PlayerHasWritten -- were both one line that looked local and correct.
//
// What it buys above that layer is the guard that opens every one of these functions. The
// store is a ScriptableSystem, so it exists only inside a session, and a contact id can be
// empty on any path that starts from a widget; every caller of a raw store handle would have
// to remember both, and one of them eventually would not. Here the answer to "no session, no
// store, no contact" is written once -- empty history, empty memory, dropped write -- and
// nothing crashes for having asked outside a session.
//
// Free functions and not a service: as methods on the speaking lane these made six files
// reach for GetAiNpcHttpSystem() to ask a question that has nothing to do with a request in
// flight. Nothing here starts, stops or observes a generation.
//
// Every function takes its contact as a parameter and none of them has a default: there is
// no way to write to "the current conversation", so no call site can be wrong about which
// one it meant without saying so out loud.

module AiNpc

/// Reading ///

public func AiNpcStoredMessages(contactId: String) -> array<ref<AiNpcMessage>> {
    let store = AiNpcConversationStore.Get();
    if !IsDefined(store) || Equals(StrLen(contactId), 0) {
        let empty: array<ref<AiNpcMessage>>;
        return empty;
    }
    return store.GetMessages(contactId);
}

// Whether V has ever written to this contact. Answered by the store rather than by scanning a
// copy of the thread, because this one is POLLED -- the anonymous contacts next door ask it per
// contact per minute, and AiNpcStoredMessages would copy a whole history to look at one flag.
public func AiNpcPlayerWroteIn(contactId: String) -> Bool {
    let store = AiNpcConversationStore.Get();
    if !IsDefined(store) || Equals(StrLen(contactId), 0) {
        return false;
    }
    return store.PlayerHasWritten(contactId);
}

// Never null: a contact nobody has talked to has an empty memory, not a missing one.
func AiNpcStoredMemory(contactId: String) -> ref<AiNpcMemory> {
    let store = AiNpcConversationStore.Get();
    if !IsDefined(store) || Equals(StrLen(contactId), 0) {
        return AiNpcMemoryNew();
    }
    return store.GetMemory(contactId);
}

/// Writing ///

// A message with no contact is refused rather than filed under a guess: the store is keyed by
// contact, so the only place an unaddressed line could go is somebody else's thread. Returns
// whether the line was filed, so a caller seeding on behalf of a mod can say no.
//
// THE ONE PLACE A MESSAGE ENTERS A THREAD, and therefore the one place it is announced to
// listeners: every author reaches here -- V typing, a generated reply, a line seeded by a mod
// -- so an observer sees the conversation rather than the fraction of it that came through
// the API it was watching. Announced here and not in AiNpcConversationStore.Append, which a
// journal replay also drives: publishing there would replay the whole history as fresh events
// on every save load.
//
// systemNotice marks a line THE MOD wrote as itself -- the operator notice standing in for a
// reply that never arrived. It is stored and announced like any other, so that the history
// keeps the gap where a request failed; what the flag buys is that a listener reacting to
// what a CHARACTER said does not react to the phone company.
//
// sourceId names the mod on whose behalf the line is filed, "" for ai_npc itself. It travels
// to the LISTENERS and stops there: a listener needs it to tell its own writes from everyone
// else's, which is what stops a mod that answers messages from answering itself, and what was
// said stays said whether or not that mod is still installed.
func AiNpcAppendMessage(contactId: String, message: String, fromPlayer: Bool, opt sourceId: String,
                        opt systemNotice: Bool, opt channel: AiNpcChannelId) -> Bool {
    if Equals(StrLen(contactId), 0) {
        AiNpcLog("Dropped a message with no contact id rather than filing it under a guess.");
        return false;
    }

    let store = AiNpcConversationStore.Get();
    if !IsDefined(store) {
        return false;
    }

    // The one door every line goes through -- both surfaces, generated replies, and any mod
    // using the public API -- which makes it the place to stop a malformed byte from being
    // written down. It has to be stopped HERE and not at the send: the history is re-read
    // into every later request, so one bad byte filed once silences the contact for good.
    // See AiNpcUtf8 for how it is produced and why nothing downstream can see it coming.
    let filed = AiNpcUtf8Clean(message);
    if NotEquals(StrLen(filed), StrLen(message)) {
        AiNpcLog(s"Repaired a malformed character in a message for '\(contactId)' before filing it.");
    }

    store.Append(contactId, filed, fromPlayer, channel);
    AiNpcPublishMessage(contactId, filed, fromPlayer, sourceId, systemNotice, channel);
    return true;
}

// THE ONE PLACE A THREAD IS ERASED, which is what makes "the allowance goes with the
// conversation" a fact rather than something two call sites have to remember. The cap exists
// to stop one character from minting eddies; a conversation that no longer exists has spent
// nothing, and only that character's total is refilled.
//
// An empty contact clears nothing AND refills nothing: the pair has to move together, or the
// door that guards one guards half of what it was asked to.
//
// Answers whether a thread was really erased, so a mod told "done" outside a session is not
// told it about a store that was not there. The allowance is refilled either way -- a total
// with no store behind it is the one thing that could survive this call.
func AiNpcResetConversation(contactId: String) -> Bool {
    if Equals(StrLen(contactId), 0) {
        return false;
    }

    let economy = AiNpcEconomySystem.Get();
    if IsDefined(economy) {
        economy.ResetTransferAllowance(contactId);
    }

    let store = AiNpcConversationStore.Get();
    if !IsDefined(store) {
        return false;
    }
    store.Clear(contactId);
    return true;
}

// Drops the last exchange -- V's line and the answer to it.
func AiNpcUndoMessage(contactId: String) -> Void {
    let store = AiNpcConversationStore.Get();
    if IsDefined(store) && NotEquals(StrLen(contactId), 0) {
        store.Undo(contactId);
    }
}
