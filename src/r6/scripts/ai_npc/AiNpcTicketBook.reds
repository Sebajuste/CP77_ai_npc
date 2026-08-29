// What became of a statement a mod made.
//
// CharacterKnows answers with a ticket rather than a Bool because the answer is not always
// known at the call: a permanent fact for a contact with no conversation yet is a normal thing
// to seed, and it settles when that contact next speaks. This is where those answers live
// until somebody asks.
//
// UNKNOWN IS NOT FAILED, and that is the whole reason for the ring. Resolved tickets cannot be
// kept forever, so the oldest fall out and answer Unknown -- which must stay distinguishable
// from Failed, or a mod reading "I no longer know" as "it did not work" announces to the
// player a failure that never happened.
//
// No game API and no publishing: the caller announces what this decides, which is what lets
// the suite assert the ring, the two emptinesses and the resolution of a pending ticket
// without a session.

module AiNpc

// How many resolved tickets stay answerable. Small on purpose: the window that matters is
// between the call and the caller's next turn, and anything older is being polled by a mod
// that should have registered a listener.
func AiNpcTicketRingSize() -> Int32 {
    return 32;
}

public class AiNpcTicketRecord {
    public let id: Int32;
    public let state: Int32;
    public let reason: String;
    public let contactId: String;
    public let modId: String;
}

public class AiNpcTicketBook {

    private let m_records: array<ref<AiNpcTicketRecord>>;

    // Ids start at 1, never 0: zero is the answer a call gives when it refused outright --
    // empty text, no contact, no session -- and it must not collide with a real ticket.
    private let m_next: Int32 = 1;

    public func Issue(modId: String, contactId: String, state: Int32, reason: String) -> Int32 {
        let record = new AiNpcTicketRecord();
        record.id = this.m_next;
        record.state = state;
        record.reason = reason;
        record.contactId = contactId;
        record.modId = modId;
        this.m_next += 1;

        ArrayPush(this.m_records, record);

        // Oldest out, as a ring rather than an unbounded log.
        while ArraySize(this.m_records) > AiNpcTicketRingSize() {
            ArrayErase(this.m_records, 0);
        }
        return record.id;
    }

    // False when the ticket is no longer answerable -- it fell out of the ring while it was
    // pending, which happens only to a mod that seeded far more than it read back. The caller
    // uses it to decide whether announcing the verdict would name a ticket nobody can look up.
    public func Resolve(ticket: Int32, state: Int32, reason: String) -> Bool {
        let index = this.IndexOf(ticket);
        if index < 0 {
            return false;
        }
        this.m_records[index].state = state;
        this.m_records[index].reason = reason;
        return true;
    }

    public func StateOf(ticket: Int32) -> Int32 {
        let index = this.IndexOf(ticket);
        if index < 0 {
            return AiNpcTicketUnknown();
        }
        return this.m_records[index].state;
    }

    // Empty for anything not failed. A reason on a successful ticket would read as a caveat.
    public func ReasonOf(ticket: Int32) -> String {
        let index = this.IndexOf(ticket);
        if index < 0 {
            return "";
        }
        return this.m_records[index].reason;
    }

    public func ContactOf(ticket: Int32) -> String {
        let index = this.IndexOf(ticket);
        if index < 0 {
            return "";
        }
        return this.m_records[index].contactId;
    }

    public func Count() -> Int32 {
        return ArraySize(this.m_records);
    }

    private func IndexOf(ticket: Int32) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_records);
        while i < count {
            if Equals(this.m_records[i].id, ticket) {
                return i;
            }
            i += 1;
        }
        return -1;
    }
}
