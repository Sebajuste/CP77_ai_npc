// What each character has already released, and how much is left in them.
//
// The cap is per CONTACT, not per session. One running total across everybody made Panam's
// generosity come out of Judy's allowance, and the refusal the model was handed -- "you have
// already sent V 5000 eddies in this conversation" -- named a conversation in which nothing
// had been sent. A character cannot be told a true sentence about a bound that is not hers.
//
// Held by AiNpcEconomySystem and reset by the one door that clears a thread, so the allowance
// and the conversation it belongs to are erased together. Nothing here decides WHEN that
// happens; see AiNpcConversationApi.
//
// No game API, no store, no logging, so the suite asserts the cumulation, the partial grant
// and the isolation of two contacts without a session -- none of which was assertable while
// the total lived in a system field.

module AiNpc

// One request against what this contact has left. Pure and parameterised, so the bound is
// assertable without a session -- as AiNpcClampAmount is for a single tag.
func AiNpcClampTransfer(requested: Int32, alreadyGiven: Int32, cap: Int32) -> Int32 {
    if requested <= 0 {
        return 0;
    }

    let remaining = cap - alreadyGiven;
    if remaining <= 0 {
        return 0;
    }
    if requested > remaining {
        return remaining;
    }
    return requested;
}

public class AiNpcTransferEntry {
    public let contactId: String;
    public let given: Int32;
}

public class AiNpcTransferLedger {
    private let m_entries: array<ref<AiNpcTransferEntry>>;

    // What this contact has released so far. A contact nobody has been paid by has spent
    // nothing, which is the same answer as an unknown contact and deliberately so.
    public func SpentOn(contactId: String) -> Int32 {
        let index = this.IndexOf(contactId);
        if index < 0 {
            return 0;
        }
        return this.m_entries[index].given;
    }

    // What may actually be released, recorded as released. Returns the granted amount, which
    // is not always the requested one: the caller has to be able to tell a character the real
    // figure, or its next message carries on as though the whole sum had gone.
    //
    // An empty contact id grants nothing rather than opening a shared slot: an unaddressed
    // transfer would spend a bound nobody owns.
    public func Grant(contactId: String, requested: Int32, cap: Int32) -> Int32 {
        if Equals(StrLen(contactId), 0) {
            return 0;
        }

        let granted = AiNpcClampTransfer(requested, this.SpentOn(contactId), cap);
        if granted <= 0 {
            return 0;
        }

        let index = this.IndexOf(contactId);
        if index < 0 {
            let entry = new AiNpcTransferEntry();
            entry.contactId = contactId;
            entry.given = granted;
            ArrayPush(this.m_entries, entry);
        } else {
            this.m_entries[index].given += granted;
        }
        return granted;
    }

    // Erases one contact's total and leaves everybody else's where it is. The entry is dropped
    // rather than zeroed: a contact that has spent nothing and one that was forgotten answer
    // the same thing, so keeping the row would only make the list grow with each reset.
    public func Reset(contactId: String) -> Void {
        let index = this.IndexOf(contactId);
        if index >= 0 {
            ArrayErase(this.m_entries, index);
        }
    }

    private func IndexOf(contactId: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_entries);
        while i < count {
            if Equals(this.m_entries[i].contactId, contactId) {
                return i;
            }
            i += 1;
        }
        return -1;
    }
}
