module AiNpc

// Les deux surfaces de conversation, et le clavier qu'elles se disputent.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

// The eight tables the chat window shows: a language added to the enum with no case falls to
// the English default and nothing says so.
//
// Structural, like AiNpcTestCarrierMessage: what is asserted is that every language answers
// with something, not what it says.
func AiNpcTestUiLabels(t: ref<AiNpcTestRunner>) -> Void {
    let languages = [AiNpcLanguage.English, AiNpcLanguage.Spanish, AiNpcLanguage.French,
        AiNpcLanguage.German, AiNpcLanguage.Italian, AiNpcLanguage.Portuguese,
        AiNpcLanguage.Russian, AiNpcLanguage.Ukraine];
    let names = AiNpcLanguageNames();

    let i = 0;
    while i < ArraySize(languages) {
        let lang = languages[i];
        let name = names[i];
        t.Check(s"labels/\(name) is typing", NotEquals(StrLen(AiNpcIsTypingLabel(lang)), 0));
        t.Check(s"labels/\(name) messages header", NotEquals(StrLen(AiNpcMessagesHeaderLabel(lang)), 0));
        t.Check(s"labels/\(name) send message", NotEquals(StrLen(AiNpcSendMessageLabel(lang)), 0));
        t.Check(s"labels/\(name) start typing", NotEquals(StrLen(AiNpcStartTypingLabel(lang)), 0));
        t.Check(s"labels/\(name) back", NotEquals(StrLen(AiNpcBackLabel(lang)), 0));
        t.Check(s"labels/\(name) reset", NotEquals(StrLen(AiNpcResetLabel(lang)), 0));
        t.Check(s"labels/\(name) undo", NotEquals(StrLen(AiNpcUndoLabel(lang)), 0));
        i += 1;
    }

    // The typing indicator is appended to a name, so it has to carry its own leading space.
    t.Check("labels/is-typing keeps its leading space",
        StrBeginsWith(AiNpcIsTypingLabel(AiNpcLanguage.English), " "));

    // The language rule, same shape. Each language carries its own code and its own text: a
    // case falling through to English is the silent failure here, and it reads as a character
    // answering a French player in English with nothing in the log.
    let j = 0;
    while j < ArraySize(languages) {
        let lang = languages[j];
        let name = names[j];
        let rule = AiNpcBuiltinLanguageRule(lang);
        t.Check(s"language rule/\(name) says something", StrLen(rule) > 40);
        t.Check(s"language rule/\(name) bans the transcript grammar", StrContains(rule, ":"));
        if NotEquals(name, "English") {
            t.Check(s"language rule/\(name) is not the English one",
                NotEquals(rule, AiNpcBuiltinLanguageRule(AiNpcLanguage.English)));
        }
        j += 1;
    }
}

/// Ordering the terminal's contact list ///

// The two orders the site's header offers, and the case that made "recent" need a rule of
// its own: a time of 0 is not a time. Every message written before AiNpcMessage carried one
// reads back as 0, and so does a contact nobody has ever texted -- sorting those by number
// would order them by whatever AiNpcGetActiveContactIds happened to return.

// The two orders the site's header offers, and the case that made "recent" need a rule of
// its own: a time of 0 is not a time. Every message written before AiNpcMessage carried one
// reads back as 0, and so does a contact nobody has ever texted -- sorting those by number
// would order them by whatever AiNpcGetActiveContactIds happened to return.
func AiNpcTestTerminalOrder(t: ref<AiNpcTestRunner>) -> Void {
    let ids = ["c", "a", "b"];
    let names = ["Zeta", "Judy", "jackie"];
    let times = [0, 300, 100];

    // Alphabetical ignores case: "jackie" before "Judy" is what a player reading the list
    // expects, and comparing raw strings would put every capital first.
    let byName = AiNpcTerminalOrderIds(ids, names, times, AiNpcTerminalOrder.Alphabetical);
    t.EqString("order/alpha first", byName[0], "b");
    t.EqString("order/alpha second", byName[1], "a");
    t.EqString("order/alpha last", byName[2], "c");

    let byTime = AiNpcTerminalOrderIds(ids, names, times, AiNpcTerminalOrder.Recent);
    t.EqString("order/recent newest", byTime[0], "a");
    t.EqString("order/recent older", byTime[1], "b");
    t.EqString("order/recent unknown last", byTime[2], "c");

    let cold = [0, 0, 0];
    let byTimeCold = AiNpcTerminalOrderIds(ids, names, cold, AiNpcTerminalOrder.Recent);
    let byNameCold = AiNpcTerminalOrderIds(ids, names, cold, AiNpcTerminalOrder.Alphabetical);
    t.EqString("order/cold start matches alpha 0", byTimeCold[0], byNameCold[0]);
    t.EqString("order/cold start matches alpha 1", byTimeCold[1], byNameCold[1]);
    t.EqString("order/cold start matches alpha 2", byTimeCold[2], byNameCold[2]);

    // Two contacts the comparison cannot separate keep the order they were given, so the
    // page does not reshuffle itself between two builds that read the same data.
    let sameIds = ["first", "second"];
    let sameNames = ["Nomad", "Nomad"];
    let sameTimes = [50, 50];
    let stable = AiNpcTerminalOrderIds(sameIds, sameNames, sameTimes,
                                       AiNpcTerminalOrder.Recent);
    t.EqString("order/stable keeps input order", stable[0], "first");

    // Mismatched lengths are a bug in the CALLER: the list comes back untouched rather than
    // indexed past its end.
    let shortNames = ["Judy"];
    let mismatched = AiNpcTerminalOrderIds(ids, shortNames, times,
                                           AiNpcTerminalOrder.Alphabetical);
    t.EqInt("order/mismatched arrays are refused", ArraySize(mismatched), 3);
    t.EqString("order/mismatched keeps input", mismatched[0], "c");

    t.Check("order/next from recent",
        Equals(AiNpcTerminalNextOrder(AiNpcTerminalOrder.Recent),
               AiNpcTerminalOrder.Alphabetical));
    t.Check("order/next from alpha",
        Equals(AiNpcTerminalNextOrder(AiNpcTerminalOrder.Alphabetical),
               AiNpcTerminalOrder.Recent));
}

// A held key repeats, but not straight away. The bug this pins is the version where nothing
// repeated at all: holding backspace deleted one character and then sat there, because the
// field refused everything that was not a fresh press and the engine sends no repeat action.

// A held key repeats, but not straight away. The bug this pins is the version where nothing
// repeated at all: holding backspace deleted one character and then sat there, because the
// field refused everything that was not a fresh press and the engine sends no repeat action.
func AiNpcTestKeyRepeat(t: ref<AiNpcTestRunner>) -> Void {
    let delay: Int32 = AiNpcKeyRepeatDelayTicks();
    let every: Int32 = AiNpcKeyRepeatEveryTicks();

    t.EqBool("repeat/nothing on the first tick", AiNpcRepeatFires(1, false, delay, every), false);
    t.EqBool("repeat/nothing just before the delay",
        AiNpcRepeatFires(delay - 1, false, delay, every), false);
    t.EqBool("repeat/the first repeat waits for the delay",
        AiNpcRepeatFires(delay, false, delay, every), true);

    // And once it has started, it is fast: the counter is reset by the caller, so this is
    // "two ticks after the last repeat", not "two ticks after the press".
    t.EqBool("repeat/once started, one tick is not enough",
        AiNpcRepeatFires(every - 1, true, delay, every), false);
    t.EqBool("repeat/once started, it fires every couple of ticks",
        AiNpcRepeatFires(every, true, delay, every), true);

    // The interval is the short one and the delay the long one. Asserted rather than assumed
    // because the two numbers are edited by hand, and swapped they would make every tap
    // repeat and every hold crawl.
    t.EqBool("repeat/the delay is longer than the interval", delay > every, true);

    // A tick lost to a busy frame must not strand a held key: the test is >=, not ==.
    t.EqBool("repeat/a skipped tick still fires", AiNpcRepeatFires(delay + 5, false, delay, every), true);
    t.EqBool("repeat/a skipped tick still fires while repeating",
        AiNpcRepeatFires(every + 5, true, delay, every), true);
}

// A keyboard owner that owns no keyboard: the policy below is about identity and nothing
// else, and asserting it on a real text field would drag a widget tree into a test that has
// no opinion about widgets.

// A keyboard owner that owns no keyboard: the policy below is about identity and nothing
// else, and asserting it on a real text field would drag a widget tree into a test that has
// no opinion about widgets.
class AiNpcTestClaimant extends AiNpcKeyboardClaimant {
}

// Who holds the keyboard, and the one rule that is not obvious: a release names WHO is
// releasing. The bug behind the file is the opposite mistake -- nothing released at all, and
// the player left a computer unable to move because a text field nobody could see was still
// eating every key.

// Who holds the keyboard, and the one rule that is not obvious: a release names WHO is
// releasing. The bug behind the file is the opposite mistake -- nothing released at all, and
// the player left a computer unable to move because a text field nobody could see was still
// eating every key.
func AiNpcTestKeyboardCapture(t: ref<AiNpcTestRunner>) -> Void {
    let first = new AiNpcTestClaimant();
    let second = new AiNpcTestClaimant();
    let nobody: ref<AiNpcKeyboardClaimant>;

    t.Check("capture/a claim is recorded",
        Equals(AiNpcKeyboardAfterClaim(nobody, first), first));
    t.Check("capture/a second claim wins",
        Equals(AiNpcKeyboardAfterClaim(first, second), second));
    // Claiming nothing is not a way to release: it would strand the holder, which is the
    // shape of the original bug.
    t.Check("capture/claiming nothing changes nothing",
        Equals(AiNpcKeyboardAfterClaim(first, nobody), first));

    t.Check("capture/the holder releases itself",
        Equals(AiNpcKeyboardAfterRelease(first, first), nobody));
    // The one that matters: two pages overlap while the next is built and the previous torn
    // down, so a late teardown must not take the new page's keyboard away.
    t.Check("capture/a stranger cannot release the holder",
        Equals(AiNpcKeyboardAfterRelease(second, first), second));
    t.Check("capture/releasing nothing changes nothing",
        Equals(AiNpcKeyboardAfterRelease(first, nobody), first));
    t.Check("capture/releasing an empty holder stays empty",
        Equals(AiNpcKeyboardAfterRelease(nobody, first), nobody));
}

// The wrapper the terminal bubbles are sized from. Its line COUNT is what a bubble's height
// is computed from, so a wrap that silently loses or invents a line is a bubble that
// overlaps the next one.

// The wrapper the terminal bubbles are sized from. Its line COUNT is what a bubble's height
// is computed from, so a wrap that silently loses or invents a line is a bubble that
// overlaps the next one.
func AiNpcTestTerminalWrap(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("wrap/short text is untouched",
        AiNpcTerminalWrapText("hey", 20), "hey");
    t.EqInt("wrap/short text is one line",
        AiNpcTerminalCountLines(AiNpcTerminalWrapText("hey", 20)), 1);

    // Eight, not seven: below AiNpcTerminalMinWrapBudget the function returns the text
    // untouched, so a smaller budget asks for a wrap it has just forbidden.
    t.EqString("wrap/breaks on a space",
        AiNpcTerminalWrapText("one two three", 8), "one two\nthree");

    t.EqString("wrap/a budget below the floor is left alone",
        AiNpcTerminalWrapText("one two three", AiNpcTerminalMinWrapBudget() - 1),
        "one two three");

    t.EqInt("wrap/keeps paragraphs",
        AiNpcTerminalCountLines(AiNpcTerminalWrapText("one\ntwo", 40)), 2);

    // A word longer than the budget is not cut: it overflows its line rather than being
    // silently mangled, and the height still counts that line.
    t.EqInt("wrap/oversized word stays one line",
        AiNpcTerminalCountLines(AiNpcTerminalWrapText("supercalifragilistic", 8)), 1);

    t.EqString("wrap/refuses a nonsense budget",
        AiNpcTerminalWrapText("one two", 2), "one two");

    t.EqString("wrap/preview flattens newlines",
        AiNpcTerminalPreview("one\ntwo", 40), "one two");
    t.EqInt("wrap/preview truncates to budget",
        StrLen(AiNpcTerminalPreview("aaaaaaaaaaaaaaaaaaaa", 10)), 10);
}

/// The section resolution chain ///

// The resolution policy, and the two normalisations that let one copy of it serve every
// section.

// Renders an edge as one letter, so a whole navigation reads as a string in the assertion:
// R raised, T tab switch, B rebuild.
func AiNpcTestEdge(edge: AiNpcPhoneEdge) -> String {
    if Equals(edge, AiNpcPhoneEdge.Raised) { return "R"; }
    if Equals(edge, AiNpcPhoneEdge.TabSwitch) { return "T"; }
    if Equals(edge, AiNpcPhoneEdge.Rebuild) { return "B"; }
    return ".";
}

/// AiNpcPhoneOpenIntent ///

func AiNpcTestPhoneOpenIntent(t: ref<AiNpcTestRunner>) -> Void {
    let i = new AiNpcPhoneOpenIntent();
    t.EqBool("intent/nothing asked for", i.IsArmed(), false);
    t.EqString("intent/taking nothing gives nothing", i.Take(), "");

    i.Arm("panam");
    t.EqBool("intent/armed", i.IsArmed(), true);
    t.EqString("intent/answers the contact", i.Take(), "panam");

    // Single shot, and this is the assertion that keeps it one: a contact list arriving twice
    // -- which it does, the phone redraws constantly -- must not reopen a chat the player has
    // just backed out of.
    t.EqBool("intent/taken once", i.IsArmed(), false);
    t.EqString("intent/taken twice gives nothing", i.Take(), "");

    // Two presses before either screen arrives: the second is the one the player meant.
    i.Arm("judy");
    i.Arm("river_ward");
    t.EqString("intent/the last press wins", i.Take(), "river_ward");

    i.Arm("judy");
    i.Drop();
    t.EqBool("intent/dropped with the phone", i.IsArmed(), false);
}

func AiNpcTestPhoneState(t: ref<AiNpcTestRunner>) -> Void {
    // Regression, and THE one: with a reply waiting, pressing D from the messages tab to the
    // contacts tab opened the mod's chat by itself. "Am I on the contacts tab?" is true of
    // both arrivals -- nothing that branches on the destination can tell them apart, only the
    // edge can.
    let m = new AiNpcPhoneStateMachine();
    m.OnScreenShown(AiNpcPhoneScreen.Contacts);          // phone out, on contacts
    t.EqString("phone/raised on contacts",
        AiNpcTestEdge(m.OnScreenShown(AiNpcPhoneScreen.Contacts)), "B");

    let m2 = new AiNpcPhoneStateMachine();
    t.EqString("phone/taking the phone out is Raised",
        AiNpcTestEdge(m2.OnScreenShown(AiNpcPhoneScreen.Contacts)), "R");
    m2.OnTabSwitchRequested();
    m2.OnScreenShown(AiNpcPhoneScreen.Messages);
    m2.OnTabSwitchRequested();
    t.EqString("phone/switching back to contacts is not Raised",
        AiNpcTestEdge(m2.OnScreenShown(AiNpcPhoneScreen.Contacts)), "T");

    // The messages tab does not build the contacts dialer, so nothing is reported while the
    // player sits there: the machine still believes it is Away when D arrives. Testing Away
    // before the latch would call that a Raised -- the same bug, one layer down. This is why
    // OnScreenShown checks the latch first.
    let m3 = new AiNpcPhoneStateMachine();
    m3.OnTabSwitchRequested();
    t.EqString("phone/a tab switch beats a stale Away",
        AiNpcTestEdge(m3.OnScreenShown(AiNpcPhoneScreen.Contacts)), "T");

    // Putting the phone away disarms the latch. A keypress that never produced a screen must
    // not survive into the next time the phone comes out.
    let m4 = new AiNpcPhoneStateMachine();
    m4.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m4.OnTabSwitchRequested();
    m4.OnPhoneHidden();
    t.EqString("phone/putting it away disarms the tab latch",
        AiNpcTestEdge(m4.OnScreenShown(AiNpcPhoneScreen.Contacts)), "R");

    // Regression: the phone HUD is rebuilt under an open chat (the scanner case). The chat did
    // not close, so the redraw underneath it is not navigation and must not move the state.
    let m5 = new AiNpcPhoneStateMachine();
    m5.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m5.OnChatOpened();
    t.EqString("phone/a redraw under the chat is not navigation",
        AiNpcTestEdge(m5.OnScreenShown(AiNpcPhoneScreen.Contacts)), "B");
    t.EqBool("phone/the chat survives a redraw",
        Equals(m5.GetScreen(), AiNpcPhoneScreen.ModChat), true);
    m5.OnChatClosed();
    t.EqBool("phone/closing the chat lands on the contact list",
        Equals(m5.GetScreen(), AiNpcPhoneScreen.Contacts), true);

    // The chat covers a screen and gives it back. Regression: closing always landed on
    // Contacts, which was only right while opening was refused anywhere else -- now that the
    // chat opens over a vanilla thread it would leave the mod believing in a contact list the
    // player is not looking at.
    let m8 = new AiNpcPhoneStateMachine();
    m8.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m8.OnThreadOpened();
    m8.OnChatOpened();
    t.EqBool("phone/the chat opens over a vanilla thread",
        Equals(m8.GetScreen(), AiNpcPhoneScreen.ModChat), true);
    m8.OnChatClosed();
    t.EqBool("phone/and closing gives the thread back",
        Equals(m8.GetScreen(), AiNpcPhoneScreen.Messages), true);

    // Opened with nothing reported -- the phone out on the messages tab builds no contacts
    // dialer, so the machine still reads Away. Away is "I was not told", not "the phone is
    // gone", and giving it back would make the next redraw read as a Raised.
    let m9 = new AiNpcPhoneStateMachine();
    m9.OnChatOpened();
    m9.OnChatClosed();
    t.EqBool("phone/a chat opened from an unreported screen lands on the contact list",
        Equals(m9.GetScreen(), AiNpcPhoneScreen.Contacts), true);

    // The return screen belongs to one trip through the phone. Putting it away forgets it,
    // for the same reason the tab latch is disarmed there.
    let m10 = new AiNpcPhoneStateMachine();
    m10.OnScreenShown(AiNpcPhoneScreen.Messages);
    m10.OnChatOpened();
    m10.OnPhoneHidden();
    m10.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m10.OnChatOpened();
    m10.OnChatClosed();
    t.EqBool("phone/putting it away forgets the screen to return to",
        Equals(m10.GetScreen(), AiNpcPhoneScreen.Contacts), true);

    // T is refused everywhere but the contact list, and that is now a property of the state
    // rather than of two hooks blanking a field.
    let m6 = new AiNpcPhoneStateMachine();
    t.EqBool("phone/T is dead with the phone away", m6.IsOnContacts(), false);
    m6.OnScreenShown(AiNpcPhoneScreen.Contacts);
    t.EqBool("phone/T is live on the contact list", m6.IsOnContacts(), true);
    m6.OnScreenShown(AiNpcPhoneScreen.Messages);
    t.EqBool("phone/T is dead on the messages tab", m6.IsOnContacts(), false);

    // Regression: the T target used to be a field that only two unrelated hooks ever cleared,
    // so a row reported on the contact list stayed live over the game's own messenger and T
    // opened the mod's chat on top of it. Leaving the contact list now takes it.
    let m7 = new AiNpcPhoneStateMachine();
    m7.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m7.OnRowReported("panam");
    t.EqString("phone/the reported row is the T target", m7.GetReportedRow(), "panam");
    m7.OnThreadOpened();
    t.EqString("phone/opening a vanilla thread drops the T target", m7.GetReportedRow(), "");
    m7.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m7.OnRowReported("judy");
    m7.OnScreenShown(AiNpcPhoneScreen.Messages);
    t.EqString("phone/leaving the contact list drops the T target", m7.GetReportedRow(), "");
}

/// Pending context: one waiting line per contact ///

// The bug this type exists to remove: a single shared slot handed one character's context to
// whoever was opened next. Both halves of that are asserted here -- what a contact gets, and
// what it must NOT get.

// The bug this type exists to remove: a single shared slot handed one character's context to
// whoever was opened next. Both halves of that are asserted here -- what a contact gets, and
// what it must NOT get.
func AiNpcTestPendingContext(t: ref<AiNpcTestRunner>) -> Void {
    let p = new AiNpcPendingContext();

    t.EqString("pending/nothing waiting reads empty", p.Take("panam"), "");

    // Every consumed line ends in a newline: the block goes into the prompt as lines, and one
    // author's sentence must not run into the next one's.
    p.Set("panam", "it started raining");
    t.EqString("pending/what was set is what is taken", p.Take("panam"), "it started raining
");
    t.EqString("pending/taking consumes it", p.Take("panam"), "");

    // The first regression: Judy's context must survive Panam's turn untouched.
    let q = new AiNpcPendingContext();
    q.Set("panam", "for panam");
    q.Set("judy", "for judy");
    t.EqString("pending/a turn takes only its own", q.Take("panam"), "for panam
");
    t.EqInt("pending/the other entry is still waiting", q.Count(), 1);
    t.EqString("pending/and it is intact", q.Take("judy"), "for judy
");

    // Same contact, same source: the older description is simply wrong.
    let r = new AiNpcPendingContext();
    r.Set("panam", "the police are looking for you");
    r.Set("panam", "the police lost interest");
    t.EqInt("pending/one source restating itself replaces", r.Count(), 1);
    t.EqString("pending/and the later description wins",
        r.Take("panam"), "the police lost interest
");

    // An unaddressed line is exactly the shared slot this replaced.
    let u = new AiNpcPendingContext();
    t.EqBool("pending/context with no contact is refused", u.Set("", "nobody"), false);
    t.EqInt("pending/and nothing was stored", u.Count(), 0);

    //
    // The bug the extension API exists to remove: the second Set used to erase the first and
    // both callers were told true.
    let m = new AiNpcPendingContext();
    m.Set("panam", "a gig came in", "gigs");
    m.Set("panam", "she is thinking about Johnny", "johnny");
    t.EqInt("pending/two sources both survive", m.CountFor("panam"), 2);
    t.EqString("pending/two authors concatenate in source order",
        m.Take("panam"), "a gig came in
she is thinking about Johnny
");

    // ai_npc's own voice is source "", which sorts first: the mod's own line reads better
    // before third-party commentary than buried in it.
    let o = new AiNpcPendingContext();
    o.Set("panam", "from a mod", "zzz");
    o.Set("panam", "the weather turned");
    t.EqString("pending/the mod's own voice reads first",
        o.Take("panam"), "the weather turned
from a mod
");

    let d = new AiNpcPendingContext();
    d.Set("panam", "first from A", "a");
    d.Set("panam", "from B", "b");
    d.Set("panam", "second from A", "a");
    t.EqInt("pending/restating one source leaves the other alone", d.CountFor("panam"), 2);
    t.EqString("pending/and only that source's line changed",
        d.Take("panam"), "second from A
from B
");

    //
    // Asserted here because it is the rule most likely to be got wrong and least likely to be
    // noticed in game: a clamped line still reads like a sentence.
    let b = new AiNpcPendingContext();
    t.EqInt("pending/an unused source has the whole line budget",
        b.BudgetLeft("panam", "gigs"), AiNpcNowLineBudget());
    b.Set("panam", "short", "gigs");
    t.EqInt("pending/what is spent comes off the budget",
        b.BudgetLeft("panam", "gigs"), AiNpcNowLineBudget() - 5);
    t.EqInt("pending/the budget is per source",
        b.BudgetLeft("panam", "johnny"), AiNpcNowLineBudget());

    // A source withdrawing from the session takes its lines with it, on every contact.
    let f = new AiNpcPendingContext();
    f.Set("panam", "gig line", "gigs");
    f.Set("judy", "gig line", "gigs");
    f.Set("panam", "kept", "johnny");
    t.EqInt("pending/a withdrawing source drops every line it held", f.ForgetSource("gigs"), 2);
    t.EqInt("pending/and nobody else's", f.Count(), 1);
    t.EqString("pending/what is left belongs to the other source",
        f.Take("panam"), "kept
");

    //
    // The per-source clamp fires BEFORE the total, and the two are not interchangeable.
    // Measured against raw text, these two lines are 1800 characters against a 1200 budget
    // and the second would be dropped; clamped first they are 400 each and both fit. The
    // discriminating case, rather than a restatement of the cap.
    let c = new AiNpcPendingContext();
    c.Set("panam", AiNpcTestFill(900), "alpha");
    c.Set("panam", AiNpcTestFill(900), "beta");
    let clamped = c.TakeReport("panam");
    t.EqInt("pending/an oversized line is clamped, not dropped",
        ArraySize(clamped.droppedIds), 0);
    t.EqInt("pending/both sources were clamped", ArraySize(clamped.clampedIds), 2);
    t.EqInt("pending/and the total counts the clamped length, not the raw one",
        StrLen(clamped.text), (AiNpcNowLineBudget() + 1) * 2);

    //
    // A line that does not fit leaves its room to shorter ones after it, rather than closing
    // the block at the first overflow. Stopping at the first overflow would make a late
    // contributor's presence depend on how verbose an unrelated mod earlier in the alphabet
    // happened to be.
    //
    // The source ids are numbered rather than named because the merge order is ALPHABETICAL,
    // not insertion order: with names, "gamma" sorts after "epsilon" and the case being set up
    // here is not the case that runs. 400 + 400 + 300 leaves 100 of the 1200; s4 asks for 400
    // and is dropped; s5 asks for 100 and still gets in.
    let g = new AiNpcPendingContext();
    g.Set("panam", AiNpcTestFill(400), "s1");
    g.Set("panam", AiNpcTestFill(400), "s2");
    g.Set("panam", AiNpcTestFill(300), "s3");
    g.Set("panam", AiNpcTestFill(400), "s4");
    g.Set("panam", AiNpcTestFill(100), "s5");
    let greedy = g.TakeReport("panam");
    t.EqInt("pending/exactly one line did not fit", ArraySize(greedy.droppedIds), 1);
    t.EqString("pending/and it is the one that overflowed", greedy.droppedIds[0], "s4");
    // 400 + 400 + 300 + 100, each with its newline. s5 is in it; s4 is not.
    t.EqInt("pending/a dropped line does not spend budget", StrLen(greedy.text), 1204);
}

// A string of exactly `count` characters, with no spaces in it.
//
// No spaces on purpose: AiNpcMemoryClampTo backs up to a word boundary unless that would cost
// more than a quarter of the line, so a run of one character is the only filler whose clamped
// length is arithmetic rather than a property of where the spaces fell.

func AiNpcTestFloorLease(t: ref<AiNpcTestRunner>) -> Void {
    // Zero is not a lease length, it is the value an `opt` defaults to. Reading it as "expires
    // immediately" would hand every scene back on the first message.
    t.EqBool("lease/no length asked means the default",
        Equals(AiNpcLeaseEndsAt(1000.0, 0.0), 1000.0 + AiNpcFloorDefaultLease()), true);
    t.EqBool("lease/a length asked is honoured",
        Equals(AiNpcLeaseEndsAt(1000.0, 30.0), 1030.0), true);

    t.EqBool("lease/still held before the end", AiNpcLeaseHasExpired(1030.0, 1029.9), false);

    // STRICT at the boundary. The other reading keeps a stopped mod's hold alive on any clock
    // that lands on the instant, and nothing prefers the answer that holds a character longer.
    t.EqBool("lease/over exactly at the end", AiNpcLeaseHasExpired(1030.0, 1030.0), true);
    t.EqBool("lease/and after it", AiNpcLeaseHasExpired(1030.0, 1030.1), true);
}

func AiNpcTestTicketBook(t: ref<AiNpcTestRunner>) -> Void {
    let book = new AiNpcTicketBook();

    // Ids never start at 0: zero is what a call returns when it refused outright, and a real
    // ticket colliding with it would make "nothing happened" unreadable.
    let done = book.Issue("gigs", "rogue", AiNpcTicketDone(), "");
    t.EqBool("ticket/ids start above the refusal value", done > 0, true);
    t.EqInt("ticket/a resolved ticket answers at once", book.StateOf(done), AiNpcTicketDone());
    t.EqString("ticket/and a success carries no reason", book.ReasonOf(done), "");

    let failed = book.Issue("gigs", "rogue", AiNpcTicketFailed(), "memory is turned off in the settings");
    t.EqInt("ticket/a failure says so", book.StateOf(failed), AiNpcTicketFailed());
    t.EqString("ticket/and says why", book.ReasonOf(failed), "memory is turned off in the settings");

    // UNKNOWN IS NOT FAILED. A ticket nobody issued is one this book has no opinion about, and
    // a mod reading that as a failure announces to the player something that never happened.
    t.EqInt("ticket/an id never issued is unknown, not failed", book.StateOf(9999), AiNpcTicketUnknown());
    t.EqString("ticket/and unknown explains nothing", book.ReasonOf(9999), "");

    // Pending settles later: that is the whole reason CharacterKnows answers with a ticket
    // instead of a Bool it would have to guess.
    let pending = book.Issue("gigs", "judy", AiNpcTicketPending(), "");
    t.EqInt("ticket/pending is its own answer", book.StateOf(pending), AiNpcTicketPending());
    t.EqString("ticket/the book remembers who it was for", book.ContactOf(pending), "judy");
    t.EqBool("ticket/resolving one it knows succeeds", book.Resolve(pending, AiNpcTicketDone(), ""), true);
    t.EqInt("ticket/and the verdict is visible", book.StateOf(pending), AiNpcTicketDone());
    t.EqBool("ticket/resolving one it does not know fails",
        book.Resolve(9999, AiNpcTicketDone(), ""), false);

    // The ring. A talkative mod must not leave a session's worth of records behind, and what
    // falls out has to become Unknown rather than anything that reads as a verdict.
    let ring = new AiNpcTicketBook();
    let first = ring.Issue("gigs", "rogue", AiNpcTicketDone(), "");
    let i = 0;
    while i < AiNpcTicketRingSize() {
        ring.Issue("gigs", "rogue", AiNpcTicketDone(), "");
        i += 1;
    }
    t.EqInt("ticket/the ring never grows past its size", ring.Count(), AiNpcTicketRingSize());
    t.EqInt("ticket/and the oldest fell out as unknown", ring.StateOf(first), AiNpcTicketUnknown());
}

// The queue of unprompted messages: the cap, the replacement, the debounce and the two
// boundaries. All four are invisible to a compile and all four read in game as a message that
// did not arrive, which is the least debuggable symptom this mod has.

// The queue of unprompted messages: the cap, the replacement, the debounce and the two
// boundaries. All four are invisible to a compile and all four read in game as a message that
// did not arrive, which is the least debuggable symptom this mod has.
func AiNpcTestSpeechQueue(t: ref<AiNpcTestRunner>) -> Void {
    let q = new AiNpcSpeechQueue();

    // A contact that has never written first is never held back: the debounce is a ceiling on
    // repetition, not a delay on the first one.
    t.EqBool("speech/the first unprompted message is never held", q.MaySpeakAt("panam", 0.0), true);

    t.EqInt("speech/a reason with a window is admitted",
        q.Admit("gigs", "panam", "she is worried", "", 1, 100.0), AiNpcSpeechAdmitted());
    t.EqInt("speech/and it is waiting", q.Count(), 1);

    // ONE ENTRY PER (MOD, CONTACT). A mod whose trigger fires twice must not thereby own two
    // slots of a queue eight deep -- that is the abuse the cap alone does not cover.
    t.EqInt("speech/restating replaces rather than stacks",
        q.Admit("gigs", "panam", "she is worried, still", "", 2, 120.0), AiNpcSpeechAdmitted());
    t.EqInt("speech/so one mod holds one slot per contact", q.Count(), 1);
    t.EqString("speech/and the newer wording is the one waiting", q.At(0).reason, "she is worried, still");
    t.EqInt("speech/on the newer ticket", q.At(0).ticket, 2);

    // Another mod on the same contact is a second entry: the replacement rule is per author,
    // exactly as a transient context line is.
    t.EqInt("speech/another mod is another entry",
        q.Admit("joytoys", "panam", "the client is asking after her", "", 3, 120.0), AiNpcSpeechAdmitted());
    t.EqInt("speech/two now", q.Count(), 2);

    // The cap, and it is refused OUTRIGHT rather than held: an entry admitted only when
    // somebody else's is spent is a wait with no bound anyone could state.
    let i = 0;
    while i < AiNpcSpeechQueueSize() {
        q.Admit(s"filler\(i)", "judy", "something", "", 100 + i, 120.0);
        i += 1;
    }
    t.EqInt("speech/the queue never grows past its size", q.Count(), AiNpcSpeechQueueSize());
    t.EqInt("speech/and a full queue refuses at once",
        q.Admit("late", "kerry", "too late", "", 999, 120.0), AiNpcSpeechQueueIsFull());

    let d = new AiNpcSpeechQueue();
    d.MarkSpoken("panam", 1000.0);
    t.EqBool("speech/she may not write again straight away", d.MaySpeakAt("panam", 1030.0), false);
    t.EqBool("speech/and may exactly when the debounce lifts",
        d.MaySpeakAt("panam", 1000.0 + AiNpcSpeechDebounce()), true);
    t.EqBool("speech/a different contact is unaffected", d.MaySpeakAt("judy", 1030.0), true);

    // A window that ends before the debounce lifts is doomed on arrival. Refusing it here is
    // the difference between a mod being told now and a mod being told after a wait that could
    // never have worked.
    t.EqInt("speech/a window shorter than the debounce is refused at the call",
        d.Admit("gigs", "panam", "now-ish", "", 4, 1030.0), AiNpcSpeechWindowTooShort());
    t.EqInt("speech/one that outlasts it is admitted",
        d.Admit("gigs", "panam", "in a while", "", 5, 1100.0), AiNpcSpeechAdmitted());

    // Expiry is read, never scheduled -- and STRICT at the boundary, like the floor lease: a
    // window is over the moment it is reached, and nothing prefers the answer that delivers a
    // reason that has just stopped being true.
    let alive = d.TakeExpired(1099.9);
    t.EqInt("speech/nothing expires before its instant", ArraySize(alive), 0);
    let dead = d.TakeExpired(1100.0);
    t.EqInt("speech/and it expires exactly at it", ArraySize(dead), 1);
    t.EqInt("speech/handed back with its ticket, so it can be answered", dead[0].ticket, 5);
    t.EqInt("speech/and it is out of the queue", d.Count(), 0);

    let c = new AiNpcSpeechQueue();
    c.Admit("gigs", "rogue", "she has news", "", 7, 100.0);
    t.EqBool("speech/somebody else may not cancel it", IsDefined(c.TakeOwned("joytoys", 7)), false);
    t.EqBool("speech/its author may", IsDefined(c.TakeOwned("gigs", 7)), true);
    t.EqBool("speech/cancelling twice answers no", IsDefined(c.TakeOwned("gigs", 7)), false);

    let w = new AiNpcSpeechQueue();
    t.EqBool("speech/an empty queue has nothing to wake for", w.NextWakeAt(0.0) <= 0.0, true);
    w.Admit("gigs", "panam", "later", "", 8, 500.0);
    w.Admit("gigs", "judy", "sooner", "", 9, 300.0);
    t.EqBool("speech/the earliest window decides the wake-up", w.NextWakeAt(0.0) == 300.0, true);
}

// The forbidden states, and the point is that most of them can no longer be written down.
//
// "The chat is on screen" used to live on four objects at once. These assertions pin the two
// that are now DERIVED -- chat-open and typing -- to the single screen they are derived from,
// so a future field claiming to know better would have to disagree with them here first.
func AiNpcTestPhoneForbidden(t: ref<AiNpcTestRunner>) -> Void {
    // Typing is reachable only from a chat. Regression: isTyping was a Bool that any caller
    // could set, and two key branches set it directly, bypassing the mirror into the view.
    let m = new AiNpcPhoneStateMachine();
    m.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m.OnTypingChanged(true);
    t.EqBool("forbidden/typing without a chat is refused", m.IsTyping(), false);
    t.EqBool("forbidden/and leaves the screen alone",
        Equals(m.GetScreen(), AiNpcPhoneScreen.Contacts), true);

    m.OnChatOpened();
    m.OnTypingChanged(true);
    t.EqBool("phone/typing is reachable from the chat", m.IsTyping(), true);
    // The one that was four fields: typing IS a chat, so these cannot come apart.
    t.EqBool("forbidden/typing implies the chat is open", m.IsChatOpen(), true);
    t.EqBool("phone/and the chat still counts as the contact list", m.IsOnContacts(), true);

    // Closing from the typing screen closes both, in one transition. Regression: every close
    // path had to remember to clear isTyping as well, and skipping it stranded the player with
    // the keyboard captured.
    m.OnChatClosed();
    t.EqBool("forbidden/closing from typing clears typing", m.IsTyping(), false);
    t.EqBool("phone/closing from typing closes the chat", m.IsChatOpen(), false);
    t.EqBool("phone/and lands on the contact list",
        Equals(m.GetScreen(), AiNpcPhoneScreen.Contacts), true);

    let m2 = new AiNpcPhoneStateMachine();
    m2.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m2.OnChatOpened();
    m2.OnTypingChanged(true);
    m2.OnPhoneHidden();
    t.EqBool("forbidden/no chat survives the phone going away", m2.IsChatOpen(), false);
    t.EqBool("forbidden/no typing survives it either", m2.IsTyping(), false);
    t.EqString("phone/and the T target goes with it", m2.GetReportedRow(), "");

    // A redraw underneath the chat is swallowed while typing too -- the screen must not fall
    // back to ModChat and drop the keyboard mid-sentence.
    let m3 = new AiNpcPhoneStateMachine();
    m3.OnScreenShown(AiNpcPhoneScreen.Contacts);
    m3.OnChatOpened();
    m3.OnTypingChanged(true);
    m3.OnScreenShown(AiNpcPhoneScreen.Contacts);
    t.EqBool("forbidden/a redraw does not drop the keyboard", m3.IsTyping(), true);
}

/// The daily token cap ///

// Everything asserted here is a RULE rather than a wire, which is why AiNpcUsageLedger.reds
// is a separate file from the service that reaches for the disk. The rules are also the part
// that can be wrong in a way nobody notices for a day: a boundary read off the wrong string
// silently purges a real total, and a charge that rounds to zero is a ceiling with a hole in
// it. None of it needs a session.
