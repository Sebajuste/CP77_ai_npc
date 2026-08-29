// What a character has not been told yet.
//
// A line of context is pushed for a contact -- the weather turned, the police heat rose, a
// quest fact flipped, a mod seeded something -- and waits there until that contact's next
// generation picks it up.
//
// The key is (contactId, sourceId). A single slot handed unconsumed context to whoever was
// opened next; keying on the contact alone let two mods seeding for one contact erase each
// other silently, both callers told true. The merge rule differs along the two axes:
//
//     same contact, same source   REPLACE. One author restating its own state.
//     same contact, two sources   CONCATENATE, in ascending source order.
//
// By source id rather than by arrival: arrival order is attachment order, which differs
// between two loads of the same save, and a prompt that reorders itself between launches is
// a bug nobody reproduces.
//
// No game API, no store, no logging, so the suite can assert every rule above -- the budget
// included -- without a session. That is also why Take has a reporting form: the model
// decides WHAT was dropped and the caller says so.

module AiNpc

/// The budget for <now> ///

// Shared with the extension contributions in AiNpcExtensionRegistry: they land in the same
// block and compete for the same attention. Here rather than there so a suite can read them
// without a session.
//
// The failure being bounded: N mods each adding a paragraph outweighs the message V actually
// wrote, and a model reads the commentary as the more important half because there is more
// of it.
func AiNpcNowLineBudget() -> Int32 {
    return 400;
}

func AiNpcNowTotalBudget() -> Int32 {
    return 1200;
}

/// Entries ///

public class AiNpcPendingEntry {
    public let contactId: String;

    // Which mod stated it. "" is ai_npc itself and sorts first: the mod's own voice reads
    // better before third-party commentary than buried in it.
    public let sourceId: String;

    public let text: String;
}

// Two fields rather than a String return: the caller has to be able to say which source was
// dropped, and this file is not allowed to log.
public class AiNpcPendingTake {
    public let text: String;
    public let droppedIds: array<String>;
    public let clampedIds: array<String>;
}

public class AiNpcPendingContext {
    private let m_entries: array<ref<AiNpcPendingEntry>>;

    // An empty contact id is refused rather than stored: context that names no contact is the
    // shared slot this type exists to remove. sourceId is `opt` so the callers that speak for
    // ai_npc itself do not have to name it.
    public func Set(contactId: String, text: String, opt sourceId: String) -> Bool {
        if Equals(StrLen(contactId), 0) {
            return false;
        }

        let index = this.IndexOf(contactId, sourceId);
        if index >= 0 {
            this.m_entries[index].text = text;
            return true;
        }

        let entry = new AiNpcPendingEntry();
        entry.contactId = contactId;
        entry.sourceId = sourceId;
        entry.text = text;
        ArrayInsert(this.m_entries, this.InsertionPoint(contactId, sourceId), entry);
        return true;
    }

    // Consumes everything waiting for one contact; another contact's context is left where it
    // is. Clamped per source, then by a running total, both reported rather than applied
    // silently.
    //
    // THE PER-SOURCE CLAMP FIRES FIRST, and the order is not interchangeable: measuring the
    // total against raw text would let one five-thousand-character line consume the whole
    // budget before anything trimmed it, leaving the per-source cap decorative.
    //
    // A DROPPED LINE DOES NOT COUNT TOWARDS THE TOTAL, so the fill is greedy: a long line that
    // did not fit leaves its room to shorter ones after it. Both rules are arbitrary at the
    // margin; this one delivers more, and every drop names its source in the log.
    public func TakeReport(contactId: String) -> ref<AiNpcPendingTake> {
        let taken = new AiNpcPendingTake();
        let spent = 0;

        let i = 0;
        while i < ArraySize(this.m_entries) {
            if Equals(this.m_entries[i].contactId, contactId) {
                let entry = this.m_entries[i];
                ArrayErase(this.m_entries, i);

                if NotEquals(StrLen(entry.text), 0) {
                    let line = entry.text;
                    if StrLen(line) > AiNpcNowLineBudget() {
                        line = AiNpcMemoryClampTo(line, AiNpcNowLineBudget());
                        ArrayPush(taken.clampedIds, entry.sourceId);
                    }

                    if spent + StrLen(line) > AiNpcNowTotalBudget() {
                        ArrayPush(taken.droppedIds, entry.sourceId);
                    } else {
                        spent += StrLen(line);
                        taken.text += line + "\n";
                    }
                }
            } else {
                // Only advanced when nothing was erased: erasing shifts the tail down, so
                // stepping past it here would skip the entry that took its place.
                i += 1;
            }
        }
        return taken;
    }

    // The same, for a caller with nothing to report.
    public func Take(contactId: String) -> String {
        return this.TakeReport(contactId).text;
    }

    // What one source may still add for a contact before the clamp bites. No bookkeeping is
    // needed, because the cap is per line rather than cumulative.
    public func BudgetLeft(contactId: String, sourceId: String) -> Int32 {
        let index = this.IndexOf(contactId, sourceId);
        if index < 0 {
            return AiNpcNowLineBudget();
        }

        let left = AiNpcNowLineBudget() - StrLen(this.m_entries[index].text);
        if left < 0 {
            return 0;
        }
        return left;
    }

    public func Count() -> Int32 {
        return ArraySize(this.m_entries);
    }

    public func CountFor(contactId: String) -> Int32 {
        let total = 0;
        let i = 0;
        let count = ArraySize(this.m_entries);
        while i < count {
            if Equals(this.m_entries[i].contactId, contactId) {
                total += 1;
            }
            i += 1;
        }
        return total;
    }

    // Everything one source is holding, across every contact. What a mod withdrawing from the
    // session calls, and the reason a source id is stored rather than only compared.
    public func ForgetSource(sourceId: String) -> Int32 {
        let removed = 0;
        let i = ArraySize(this.m_entries) - 1;
        while i >= 0 {
            if Equals(this.m_entries[i].sourceId, sourceId) {
                ArrayErase(this.m_entries, i);
                removed += 1;
            }
            i -= 1;
        }
        return removed;
    }

    /// Ordering ///

    // Sorted on insert rather than at read: seeding happens a few times per message, reading
    // once per generation. Contact first so one contact's entries are contiguous, then source.
    private func InsertionPoint(contactId: String, sourceId: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_entries);
        while i < count {
            let byContact = StrCmp(this.m_entries[i].contactId, contactId);
            if byContact > 0 {
                return i;
            }
            if Equals(byContact, 0) && StrCmp(this.m_entries[i].sourceId, sourceId) > 0 {
                return i;
            }
            i += 1;
        }
        return count;
    }

    private func IndexOf(contactId: String, sourceId: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_entries);
        while i < count {
            if Equals(this.m_entries[i].contactId, contactId)
                && Equals(this.m_entries[i].sourceId, sourceId) {
                return i;
            }
            i += 1;
        }
        return -1;
    }
}
