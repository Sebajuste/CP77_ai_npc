module AiNpc

// Les politiques de session : qui parle, laquelle est affichee, laquelle se ferme.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

// A renderer that draws nothing and records everything.
//
// It answers the two questions whose answer changes the session's behaviour -- SplitBudget
// and IsAtBottom -- as instructed, because a mock that always said "yes, at the bottom"
// would make the follow-the-conversation assertions pass without ever exercising the branch
// that leaves a reader alone.
class AiNpcMockRenderer extends AiNpcChatRenderer {
    public let budget: Int32 = 0;
    public let limit: Int32 = 0;
    public let atBottom: Bool = true;
    public let alive: Bool = true;

    // "P:hi" / "N:yo", in the order they were painted.
    public let lines: array<String>;
    public let clears: Int32 = 0;
    public let scrolls: Int32 = 0;
    public let animated: Int32 = 0;
    public let typingOn: Int32 = 0;
    public let typingOff: Int32 = 0;
    public let lastMode: String = "";

    public func Clear() -> Void {
        this.clears += 1;
        ArrayClear(this.lines);
    }

    public func AppendMessage(text: String, fromPlayer: Bool, animate: Bool) -> Void {
        if animate {
            this.animated += 1;
        }
        if fromPlayer {
            ArrayPush(this.lines, "P:" + text);
        } else {
            ArrayPush(this.lines, "N:" + text);
        }
    }

    public func SetTypingIndicator(value: Bool) -> Void {
        if value {
            this.typingOn += 1;
        } else {
            this.typingOff += 1;
        }
    }

    public func SetInputMode(mode: AiNpcInputMode) -> Void {
        this.lastMode = s"\(mode)";
    }

    public func ScrollToBottom() -> Void {
        this.scrolls += 1;
    }

    public func IsAtBottom() -> Bool {
        return this.atBottom;
    }

    public func SplitBudget() -> Int32 {
        return this.budget;
    }

    public func HistoryLimit() -> Int32 {
        return this.limit;
    }

    public func Alive() -> Bool {
        return this.alive;
    }
}

func AiNpcTestSessionPolicy(t: ref<AiNpcTestRunner>) -> Void {

    let one = AiNpcSplitForBudget("hello", 10);
    t.EqInt("session/short text is one piece", ArraySize(one), 1);

    let two = AiNpcSplitForBudget("abcdefghij", 4);
    t.EqInt("session/long text is two pieces", ArraySize(two), 2);
    t.EqString("session/first piece is the budget", two[0], "abcd");
    t.EqString("session/second piece is the rest", two[1], "efghij");

    let none = AiNpcSplitForBudget("abcdefghij", 0);
    t.EqInt("session/a budget of zero means no split", ArraySize(none), 1);

    t.EqInt("session/window with no limit starts at zero", AiNpcHistoryWindowStart(50, 0), 0);
    t.EqInt("session/window keeps the last N", AiNpcHistoryWindowStart(50, 40), 10);
    t.EqInt("session/window never starts before the start", AiNpcHistoryWindowStart(5, 40), 0);

    t.EqBool("session/a reply for the shown contact is accepted",
             AiNpcSessionAccepts("panam", "panam", AiNpcChannelId.Text, AiNpcChannelId.Text), true);
    t.EqBool("session/a reply for someone else is refused",
             AiNpcSessionAccepts("panam", "judy", AiNpcChannelId.Text, AiNpcChannelId.Text), false);
    t.EqBool("session/a surface showing nothing accepts nothing",
             AiNpcSessionAccepts("", "panam", AiNpcChannelId.Text, AiNpcChannelId.Text), false);

    let session = new AiNpcChatSession();
    let mock = new AiNpcMockRenderer();
    mock.budget = 4;
    session.Attach(mock);
    session.Show("panam");

    t.EqBool("session/delivery to another contact is refused",
             session.Deliver("judy", "hey", AiNpcChannelId.Text), false);
    t.EqInt("session/a refused delivery paints nothing", ArraySize(mock.lines), 0);

    t.EqBool("session/delivery to the shown contact is accepted",
             session.Deliver("panam", "abcdefghij", AiNpcChannelId.Text), true);
    t.EqInt("session/a long reply is split at the renderer budget", ArraySize(mock.lines), 2);
    t.EqString("session/the split keeps the order", mock.lines[0], "N:abcd");
    t.EqInt("session/a live reply animates", mock.animated, 2);

    let before: Int32 = mock.scrolls;
    mock.atBottom = false;
    session.Deliver("panam", "hi", AiNpcChannelId.Text);
    t.EqInt("session/a reader scrolled up is left alone", mock.scrolls, before);
    mock.atBottom = true;
    session.Deliver("panam", "hi", AiNpcChannelId.Text);
    t.EqInt("session/a reader at the bottom follows", mock.scrolls, before + 1);

    let fill = new AiNpcChatSession();
    let fillMock = new AiNpcMockRenderer();
    fill.Attach(fillMock);
    fill.Show("panam");
    fill.Fill(AiNpcTestHistory(["V:hi", "N:yo", "V:" + AiNpcSystemEventMarker()]));
    t.EqInt("session/filling clears first", fillMock.clears, 1);
    t.EqInt("session/the system marker is not shown", ArraySize(fillMock.lines), 2);
    t.EqString("session/the player is painted as the player", fillMock.lines[0], "P:hi");
    t.EqInt("session/a replayed history does not animate", fillMock.animated, 0);

    let modes = new AiNpcChatSession();
    let modeMock = new AiNpcMockRenderer();
    modes.Attach(modeMock);
    modes.Show("panam");

    modes.EndTyping();
    t.EqString("session/not typing is resting", modeMock.lastMode, "Resting");
    modes.BeginTyping();
    t.EqString("session/typing is typing", modeMock.lastMode, "Typing");
    modes.SetBusy(true);
    t.EqString("session/a generation wins over typing", modeMock.lastMode, "Disabled");
    modes.SetBusy(false);
    t.EqString("session/the state comes back when it ends", modeMock.lastMode, "Typing");

    modes.SetTypingIndicator("judy", true, AiNpcChannelId.Text);
    t.EqInt("session/dots for another contact are ignored", modeMock.typingOn, 0);
    modes.SetTypingIndicator("panam", true, AiNpcChannelId.Text);
    t.EqInt("session/dots for the shown contact are shown", modeMock.typingOn, 1);
    modes.SetTypingIndicator("judy", false, AiNpcChannelId.Text);
    t.EqInt("session/dots off is obeyed whoever it is for", modeMock.typingOff, 1);

    let send = new AiNpcChatSession();
    let sendMock = new AiNpcMockRenderer();
    send.Attach(sendMock);
    send.Show("panam");
    send.BeginTyping();

    t.EqBool("session/an empty message is not worth sending", send.AcceptTyped(""), false);
    t.EqInt("session/an empty message paints nothing", ArraySize(sendMock.lines), 0);
    t.EqBool("session/typing ends on an empty send", send.IsTyping(), false);

    send.BeginTyping();
    t.EqBool("session/a real message is worth sending", send.AcceptTyped("hey"), true);
    t.EqString("session/the player message is echoed", sendMock.lines[0], "P:hey");
    t.EqBool("session/typing ends on a send", send.IsTyping(), false);

    let orphan = new AiNpcChatSession();
    orphan.Show("panam");
    t.EqBool("session/no renderer refuses delivery", orphan.Deliver("panam", "hey", AiNpcChannelId.Text), false);
    orphan.Fill(AiNpcTestHistory(["V:hi"]));
    t.EqBool("session/no renderer survives a fill", orphan.HasRenderer(), false);

    let dead = new AiNpcChatSession();
    let deadMock = new AiNpcMockRenderer();
    dead.Attach(deadMock);
    dead.Show("panam");
    deadMock.alive = false;
    t.EqBool("session/a dead renderer is no renderer", dead.HasRenderer(), false);
    t.EqBool("session/a dead renderer refuses delivery", dead.Deliver("panam", "hey", AiNpcChannelId.Text), false);
    t.EqInt("session/a dead renderer is never painted into", ArraySize(deadMock.lines), 0);
}

/// Chat session delivery ///

// A session whose renderer records what it was told, wired to accept or refuse.
//
// The whole point of the session split is that a surface can refuse a reply, so the double
// has to be able to refuse: a stub that always rendered would make every assertion below
// pass without exercising the fall-through, which is the branch the SMS notification
// depends on. A session refuses by showing a different conversation, which is exactly how
// it refuses in the game.

// A session whose renderer records what it was told, wired to accept or refuse.
//
// The whole point of the session split is that a surface can refuse a reply, so the double
// has to be able to refuse: a stub that always rendered would make every assertion below
// pass without exercising the fall-through, which is the branch the SMS notification
// depends on. A session refuses by showing a different conversation, which is exactly how
// it refuses in the game.
func AiNpcFakeSession(shown: String) -> ref<AiNpcChatSession> {
    let session = new AiNpcChatSession();
    session.Attach(new AiNpcMockRenderer());
    session.Show(shown);
    return session;
}

func AiNpcTestSessionRegistryPolicy(t: ref<AiNpcTestRunner>) -> Void {
    let phone = AiNpcFakeSession("panam");
    let terminal = AiNpcFakeSession("panam");

    let sessions: array<ref<AiNpcChatSession>>;
    sessions = AiNpcSessionsWith(sessions, phone);
    sessions = AiNpcSessionsWith(sessions, terminal);
    t.EqInt("sessions/two registrations are two sessions", ArraySize(sessions), 2);

    let ordered = AiNpcSessionsMostRecentFirst(sessions);
    t.Check("sessions/most recent is delivered first", Equals(ordered[0], terminal));
    t.Check("sessions/older session comes second", Equals(ordered[1], phone));

    // BEF rebuilds a page's listener on every navigation, so this is the case that happens
    // for real.
    let again = AiNpcSessionsWith(sessions, phone);
    let againOrdered = AiNpcSessionsMostRecentFirst(again);
    t.EqInt("sessions/re-registering does not duplicate", ArraySize(again), 2);
    t.Check("sessions/re-registering moves to the front", Equals(againOrdered[0], phone));

    let pruned = AiNpcSessionsWithout(sessions, phone);
    t.EqInt("sessions/unregistering removes exactly one", ArraySize(pruned), 1);
    t.Check("sessions/unregistering the older keeps the newer", Equals(pruned[0], terminal));

    let unknown = AiNpcSessionsWithout(sessions, AiNpcFakeSession("never registered"));
    t.EqInt("sessions/unregistering a stranger changes nothing", ArraySize(unknown), 2);

    let front = AiNpcFakeSession("panam");
    let behind = AiNpcFakeSession("panam");
    let both: array<ref<AiNpcChatSession>>;
    both = AiNpcSessionsWith(both, behind);
    both = AiNpcSessionsWith(both, front);
    let bothOrdered = AiNpcSessionsMostRecentFirst(both);
    t.Check("sessions/first refusal renders",
        AiNpcDeliverReply(bothOrdered, "panam", "hi", AiNpcChannelId.Text));
    t.EqInt("sessions/the front session painted",
            ArraySize((front.GetRenderer() as AiNpcMockRenderer).lines), 1);
    t.EqInt("sessions/the session behind was not asked",
            ArraySize((behind.GetRenderer() as AiNpcMockRenderer).lines), 0);

    // The phone showing another conversation: the branch that keeps a reply out of the wrong
    // thread.
    let refuses = AiNpcFakeSession("panam");
    let accepts = AiNpcFakeSession("judy");
    let chain: array<ref<AiNpcChatSession>>;
    chain = AiNpcSessionsWith(chain, accepts);
    chain = AiNpcSessionsWith(chain, refuses);
    let chainOrdered = AiNpcSessionsMostRecentFirst(chain);
    t.Check("sessions/a refusal falls through", AiNpcDeliverReply(chainOrdered, "judy", "hi", AiNpcChannelId.Text));
    t.EqInt("sessions/the refusing session painted nothing",
            ArraySize((refuses.GetRenderer() as AiNpcMockRenderer).lines), 0);
    t.EqInt("sessions/the next session rendered it",
            ArraySize((accepts.GetRenderer() as AiNpcMockRenderer).lines), 1);

    let allRefuse: array<ref<AiNpcChatSession>>;
    allRefuse = AiNpcSessionsWith(allRefuse, AiNpcFakeSession("judy"));
    allRefuse = AiNpcSessionsWith(allRefuse, AiNpcFakeSession("panam"));
    let allRefuseOrdered = AiNpcSessionsMostRecentFirst(allRefuse);
    t.EqBool("sessions/nobody rendering means nobody rendered",
        AiNpcDeliverReply(allRefuseOrdered, "river", "hi", AiNpcChannelId.Text), false);

    let none: array<ref<AiNpcChatSession>>;
    t.EqBool("sessions/no session means no render", AiNpcDeliverReply(none, "panam", "hi", AiNpcChannelId.Text), false);
    let noneOrdered = AiNpcSessionsMostRecentFirst(none);
    t.EqInt("sessions/ordering an empty list is empty", ArraySize(noneOrdered), 0);
}

/// UI labels ///

// The eight tables the chat window shows: a language added to the enum with no case falls to
// the English default and nothing says so.
//
// Structural, like AiNpcTestCarrierMessage: what is asserted is that every language answers
// with something, not what it says.
