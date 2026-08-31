// One generation, from the moment it is addressed to the moment its reply is on screen.
//
// Not "turn": a turn is one message from V plus one reply, which is what the history window,
// the memory budget and NotifyTurnComplete count in, and taking a turn in the sense of whose
// turn it is to speak is the floor. Not "request" either, since a repair is a second request
// inside one of these.
//
// The invariant it enforces: a request is addressed once, at send time, and nothing downstream
// re-asks who is selected. Delivery happens seconds of DelayCallback plus latency later, so
// reading the current selection down there files Panam's answer in Judy's thread. That used to
// be three loose fields and a comment; here the contact is set by a constructor and there is
// no method to set it again.
//
// A generation also says who asked and what they asked: the line typed, or a mod's reason and
// a ticket to report back on. The nature is fixed by the constructor rather than a flag passed
// down -- an unprompted generation is one with no player line, and SpeaksFirst() reads that
// rather than storing it.
//
// The repair budget lives here because it is generation-scoped: one repair per thing V said.
// As a field on the lane it needed an explicit Refill() at the top of every send, and
// forgetting it means a model writing the same broken command keeps buying requests. The
// ticket sits beside it and not on the request record, which a repair replaces.
//
// No game API, no store, no settings, no logging: who sends a request and who paints the
// answer are the lane's, which is what lets the suite assert the addressing rule offline.

module AiNpc

public class AiNpcGeneration {
    // Who this generation is for. Written once, by a constructor.
    private let m_contactId: String;

    // Par quel medium. Capture ici et pour la meme raison que le contact : la livraison arrive
    // un DelayCallback et un aller-retour plus tard, et un joueur qui a raccroche entre-temps
    // verrait sinon une ligne parlee peinte dans le fil SMS.
    private let m_channel: AiNpcChannelId;

    // "" is the player, the only author with no mod id, so the empty string is a real answer
    // here rather than a missing one.
    private let m_askedBy: String;

    // The line V typed, or the reason a mod gave. Shown to the player in neither case: the
    // first is already in the thread, the second is written for the model.
    private let m_ask: String;

    // 0 when nobody is waiting: the player's own message reports to the screen, and
    // AiNpcTicketBook never issues 0.
    private let m_ticket: Int32;

    // Derived at construction from whether anybody handed her a line to answer, so it cannot
    // disagree with the rest of the object.
    private let m_speaksFirst: Bool;

    // What the character is after while writing this one message, when the mod that asked said.
    // Empty means what she always wants.
    //
    // On the generation and not the character: an intent on the character would have to merge
    // with another mod's, and two intents do not merge. A request has nobody to merge with.
    private let m_intent: String;

    // Recorded at send time for the same reason the contact is: by the time a failure is
    // described, the provider setting that chose the url may no longer say the same thing. It
    // is also the only thing that distinguishes the two ways a status-0 failure happens.
    private let m_url: String;

    private let m_repair: ref<AiNpcRepair>;

    // V wrote something and the character is answering it.
    public static func ForPlayer(contactId: String, playerLine: String,
                                opt channel: AiNpcChannelId) -> ref<AiNpcGeneration> {
        let self = AiNpcGeneration.Addressed(contactId);
        self.m_ask = playerLine;
        self.m_channel = channel;
        return self;
    }

    // A mod stated a reason and the character is writing first.
    public static func ForMod(contactId: String, modId: String, reason: String, ticket: Int32,
                              opt intent: String) -> ref<AiNpcGeneration> {
        let self = AiNpcGeneration.Addressed(contactId);
        self.m_askedBy = modId;
        self.m_ask = reason;
        self.m_ticket = ticket;
        self.m_speaksFirst = true;
        self.m_intent = intent;
        return self;
    }

    // Before the first generation of a session and after the last: one that exists but names
    // nobody, rather than a null the whole lane would have to check.
    public static func Idle() -> ref<AiNpcGeneration> {
        return AiNpcGeneration.Addressed("");
    }

    // The one place a generation is addressed. Private, so every public constructor goes
    // through it and no future one can forget the repair budget.
    private static func Addressed(contactId: String) -> ref<AiNpcGeneration> {
        let self = new AiNpcGeneration();
        self.m_contactId = contactId;
        self.m_repair = new AiNpcRepair();
        return self;
    }

    public func Contact() -> String {
        return this.m_contactId;
    }

    public func Channel() -> AiNpcChannelId {
        return this.m_channel;
    }

    // "" is the player. Anything else is the mod that asked.
    public func AskedBy() -> String {
        return this.m_askedBy;
    }

    public func Ask() -> String {
        return this.m_ask;
    }

    // "" when the caller stated none, so the prompt builder reads one field and needs no second
    // question about who asked.
    public func Intent() -> String {
        return this.m_intent;
    }

    public func Ticket() -> Int32 {
        return this.m_ticket;
    }

    // Read by three things downstream: which ending the transcript gets, whether the
    // scripted-reply path is consulted, and whether a failure may speak to the player. Nobody
    // is waiting on a screen for a message they never sent, so a carrier line there would
    // arrive out of nowhere and be filed into the thread.
    public func SpeaksFirst() -> Bool {
        return this.m_speaksFirst;
    }

    public func Url() -> String {
        return this.m_url;
    }

    public func Repair() -> ref<AiNpcRepair> {
        return this.m_repair;
    }

    // Called by both sends, the reply and the repair, because either can be the request a
    // failure ends up describing.
    public func SendingTo(url: String) -> Void {
        this.m_url = url;
    }
}
