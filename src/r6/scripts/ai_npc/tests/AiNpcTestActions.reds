module AiNpc

// La voie d'action : inventaire des tags, analyse, transferts, faits, extensions.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

func AiNpcTestActionTagInventory(t: ref<AiNpcTestRunner>) -> Void {
    /// The lexicon: what counts as a tag at all ///

    let none = AiNpcFindActionTags("no tags here");
    t.EqInt("tags/none reported for plain text", ArraySize(none), 0);

    let two = AiNpcFindActionTags("[ACTION:A] then [ACTION:B:1]");
    t.EqInt("tags/every tag is reported", ArraySize(two), 2);

    let repeated = AiNpcFindActionTags("[ACTION:NOPE] x [ACTION:NOPE]");
    t.EqInt("tags/duplicates reported once", ArraySize(repeated), 1);

    // Unterminated is not a tag. The scanner runs to the first "]", so returning a head would
    // hand a caller a bracket no substitution can close.
    let unterminated = AiNpcFindActionTags("[ACTION:BROKEN");
    t.EqInt("tags/unterminated tag is not a tag", ArraySize(unterminated), 0);

    // A space inside would let one tag swallow the prose up to the next bracket.
    let spaced = AiNpcFindActionTags("[ACTION:GIVE_EDDIES:1 500]");
    t.EqInt("tags/a tag with a space is not a tag", ArraySize(spaced), 0);

    // Reading a repair back: the model was asked for a command alone and answers in all three
    // of these shapes.
    t.EqString("actions/first tag, alone",
        AiNpcFirstActionTag("[ACTION:TRICK:KABUKI_SF:2300:1000]"),
        "[ACTION:TRICK:KABUKI_SF:2300:1000]");
    t.EqString("actions/first tag, wrapped in prose",
        AiNpcFirstActionTag("Desole. [ACTION:TRICK:JIGJIG:2300:200] voila."),
        "[ACTION:TRICK:JIGJIG:2300:200]");
    t.EqString("actions/first tag wins",
        AiNpcFirstActionTag("[ACTION:GIVE_EDDIES:100] [ACTION:GIVE_EDDIES:1000]"),
        "[ACTION:GIVE_EDDIES:100]");
    t.EqString("actions/NONE carries no tag", AiNpcFirstActionTag("NONE"), "");
    t.EqString("actions/an unterminated tag is not a tag",
        AiNpcFirstActionTag("[ACTION:TRICK:KABUKI_SF"), "");

    /// Patterns: one declaration is both halves of a command ///

    let refusal = "";
    let slotted = AiNpcParseActionPattern("[ACTION:TRICK:{place}:{hour}:{price}]", refusal);
    t.Check("pattern/a slotted pattern parses", IsDefined(slotted));
    if IsDefined(slotted) {
        t.EqString("pattern/the verb names the command", slotted.verb, "TRICK");
        t.EqInt("pattern/the arity is the slot count", slotted.arity, 3);
        t.EqString("pattern/the head is the literal run before the first slot",
            slotted.head, "[ACTION:TRICK:");
    }

    let exact = AiNpcParseActionPattern("[ACTION:CALL_DELAMAIN]", refusal);
    t.Check("pattern/a slotless pattern parses", IsDefined(exact));
    if IsDefined(exact) {
        t.EqInt("pattern/a slotless pattern has no arity", exact.arity, 0);
        t.EqString("pattern/its head is the whole tag", exact.head, "[ACTION:CALL_DELAMAIN]");
    }

    // A literal after the verb is part of the head, so two commands may share a verb and
    // differ afterwards.
    let literal = AiNpcParseActionPattern("[ACTION:TRICK:NOTELL:{hour}]", refusal);
    t.Check("pattern/a literal segment parses", IsDefined(literal));
    if IsDefined(literal) {
        t.EqString("pattern/a literal after the verb joins the head",
            literal.head, "[ACTION:TRICK:NOTELL:");
    }

    // Each refusal is a declaration whose author could not have meant it, and each would
    // otherwise become a command advertised to a model and honoured by nobody.
    t.Check("pattern/a bare word is refused",
        !IsDefined(AiNpcParseActionPattern("TRICK", refusal)));
    t.Check("pattern/an unterminated pattern is refused",
        !IsDefined(AiNpcParseActionPattern("[ACTION:TRICK", refusal)));
    t.Check("pattern/a pattern with a space is refused",
        !IsDefined(AiNpcParseActionPattern("[ACTION:TWO WORDS]", refusal)));
    t.Check("pattern/a slot where the verb belongs is refused",
        !IsDefined(AiNpcParseActionPattern("[ACTION:{verb}:{x}]", refusal)));
    t.Check("pattern/an empty segment is refused",
        !IsDefined(AiNpcParseActionPattern("[ACTION:TRICK::{hour}]", refusal)));
    t.Check("pattern/a refusal says why", NotEquals(StrLen(refusal), 0));

    /// Matching: complete, fumbled, or not this command at all ///

    let good = AiNpcMatchActionPattern(slotted, "[ACTION:TRICK:JIGJIG:2300:200]");
    t.EqBool("match/a well-formed tag is complete", good.complete, true);
    t.EqInt("match/every slot is captured", ArraySize(good.params), 3);
    if Equals(ArraySize(good.params), 3) {
        t.EqString("match/slots are captured in order", good.params[0], "JIGJIG");
        t.EqString("match/the last slot is captured", good.params[2], "200");
    }

    // The distinction the whole dispatch turns on: the command EXISTS, the fields do not add
    // up. That is a fumble the repair pass can fix, not an unknown command.
    let short = AiNpcMatchActionPattern(slotted, "[ACTION:TRICK:JIGJIG:2300]");
    t.EqBool("match/a fumbled command still matches its head", short.headMatched, true);
    t.EqBool("match/a fumbled command is not complete", short.complete, false);

    // An empty field is a dropped field, never a value: a handler given "" would have to
    // invent what was meant.
    let hollow = AiNpcMatchActionPattern(slotted, "[ACTION:TRICK::2300:200]");
    t.EqBool("match/an empty field is not a value", hollow.complete, false);

    // The model copied the slot's braces along with the value. Observed on several models and
    // on two revisions of the command block, which is why the answer is here and not in the
    // wording: the value is right, its dress is not.
    let dressed = AiNpcMatchActionPattern(slotted, "[ACTION:TRICK:{JIGJIG}:<2300>:**200**]");
    t.EqBool("match/decorated fields still complete the command", dressed.complete, true);
    if Equals(ArraySize(dressed.params), 3) {
        t.EqString("match/braces are not part of the value", dressed.params[0], "JIGJIG");
        t.EqString("match/angles are not part of the value", dressed.params[1], "2300");
        t.EqString("match/asterisks are not part of the value", dressed.params[2], "200");
    }

    // Unbalanced is still decoration: no value any command takes starts or ends with one.
    let halfDressed = AiNpcMatchActionPattern(slotted, "[ACTION:TRICK:JIGJIG}:2300:\"200]");
    if Equals(ArraySize(halfDressed.params), 3) {
        t.EqString("match/a stray closing brace is stripped", halfDressed.params[0], "JIGJIG");
        t.EqString("match/a stray quote is stripped", halfDressed.params[2], "200");
    }

    // Tolerance is for how a value was written, never for what it says.
    t.EqString("match/cleaning does not repair a value",
        AiNpcCleanSlotValue("{mille}"), "mille");
    t.EqString("match/an inner brace is left alone",
        AiNpcCleanSlotValue("JIG{JIG"), "JIG{JIG");
    t.EqString("match/decoration alone is nothing", AiNpcCleanSlotValue("{}"), "");

    // A field holding only decoration is the dropped field it is.
    let empty = AiNpcMatchActionPattern(slotted, "[ACTION:TRICK:{}:2300:200]");
    t.EqBool("match/a field holding only decoration is not a value", empty.complete, false);

    // The boundary rule. Matching anywhere in the tag would let "[ACTION:TRICK:" claim
    // "[ACTION:UNDO_TRICK:".
    let other = AiNpcMatchActionPattern(slotted, "[ACTION:UNDO_TRICK:JIGJIG:2300:200]");
    t.EqBool("match/a head anchors at the start", other.headMatched, false);

    let literalTag = AiNpcMatchActionPattern(literal, "[ACTION:TRICK:TELL:2300]");
    t.EqBool("match/a literal segment must match too", literalTag.complete, false);

    /// Optional trailing fields ///

    // A model asked for five fields writes three when only three were agreed. That is a real
    // command in ai_npc_joytoys, not an imagined case, and the guarantee it must not cost is
    // the arity: `params` is always one entry per slot, and an absent optional is "".
    let optional = AiNpcParseActionPattern(
        "[ACTION:TRICK:{venue}:{hour}:{price}:{days?}:{protection?}]", refusal);
    t.Check("optional/a pattern with an optional tail parses", IsDefined(optional));
    if IsDefined(optional) {
        t.EqInt("optional/every slot counts toward the arity", optional.arity, 5);
        t.EqInt("optional/only the fixed ones are required", optional.required, 3);
    }

    let short3 = AiNpcMatchActionPattern(optional, "[ACTION:TRICK:JIGJIG:2300:200]");
    t.EqBool("optional/the required fields alone are complete", short3.complete, true);
    t.EqInt("optional/params is still one per slot", ArraySize(short3.params), 5);
    if Equals(ArraySize(short3.params), 5) {
        t.EqString("optional/an absent optional is empty", short3.params[3], "");
        t.EqString("optional/and so is the one after it", short3.params[4], "");
    }

    let full5 = AiNpcMatchActionPattern(optional, "[ACTION:TRICK:JIGJIG:2300:200:1:2]");
    t.EqBool("optional/a full tag is complete too", full5.complete, true);
    if Equals(ArraySize(full5.params), 5) {
        t.EqString("optional/a written optional is carried", full5.params[4], "2");
    }

    let tooFew = AiNpcMatchActionPattern(optional, "[ACTION:TRICK:JIGJIG:2300]");
    t.EqBool("optional/below the required count is still a fumble", tooFew.complete, false);
    t.EqBool("optional/and it still names a real command", tooFew.headMatched, true);

    let tooMany = AiNpcMatchActionPattern(optional, "[ACTION:TRICK:JIGJIG:2300:200:1:2:9]");
    t.EqBool("optional/past the last slot is a fumble", tooMany.complete, false);

    // A hole in the middle is unreadable both ways: the model cannot say which field it
    // skipped, and neither can the match.
    t.Check("optional/a required field after an optional one is refused",
        !IsDefined(AiNpcParseActionPattern("[ACTION:X:{a?}:{b}]", refusal)));

    /// Resolution: who reaches this contact, and who took it away ///

    let handler = new AiNpcActionHandler();
    let everyone = AiNpcActionClaimOf("taxi:CALL", "[ACTION:CALL]", AiNpcEveryContactTag(), handler);
    let clients = AiNpcActionClaimOf("joytoy:TRICK", "[ACTION:TRICK:{hour}]", "joytoy:client", handler);
    let claims = [everyone, clients];
    let noSuppressions: array<ref<AiNpcActionSuppression>>;

    let plainTags = [AiNpcEveryContactTag(), AiNpcContactTagFor("judy")];
    let plain = AiNpcResolveClaims(claims, plainTags, noSuppressions);
    t.EqInt("scope/a contact gets only the commands its tags carry", ArraySize(plain), 1);

    let clientTags = [AiNpcEveryContactTag(), AiNpcContactTagFor("anon_1"), "joytoy:client"];
    let both = AiNpcResolveClaims(claims, clientTags, noSuppressions);
    t.EqInt("scope/a tag adds a command without either mod knowing the other",
        ArraySize(both), 2);

    // The anonymous contact is the case that decided the design: minted at runtime, in no list
    // anybody could have written, reached because it was born carrying a tag.
    let stranger = AiNpcResolveClaims(claims,
        [AiNpcEveryContactTag(), AiNpcContactTagFor("anon_918273"), "joytoy:client"],
        noSuppressions);
    t.EqInt("scope/a contact minted at runtime is reachable", ArraySize(stranger), 2);

    let veto = new AiNpcActionSuppression();
    veto.modId = "joytoy";
    veto.head = "[ACTION:CALL]";
    veto.scopeTag = "joytoy:client";
    let suppressed = AiNpcResolveClaims(claims, clientTags, [veto]);
    t.EqInt("veto/a suppression removes a command from its bearers", ArraySize(suppressed), 1);
    if Equals(ArraySize(suppressed), 1) {
        t.EqString("veto/it removes the named one", suppressed[0].fullId, "joytoy:TRICK");
    }
    let untouched = AiNpcResolveClaims(claims, plainTags, [veto]);
    t.EqInt("veto/a suppression reaches only the tag it names", ArraySize(untouched), 1);

    // Attachment to one character beats a grant to everybody, for that character only.
    let mine = AiNpcActionClaimOf("mod:CALL", "[ACTION:CALL]", AiNpcContactTagFor("judy"), handler);
    let contested = AiNpcResolveClaims([everyone, mine], plainTags, noSuppressions);
    t.EqInt("arbitration/one command survives", ArraySize(contested), 1);
    if Equals(ArraySize(contested), 1) {
        t.EqString("arbitration/the more specific claim wins",
            contested[0].fullId, "mod:CALL");
    }
    // And the order it was declared in does not decide it.
    let reversed = AiNpcResolveClaims([mine, everyone], plainTags, noSuppressions);
    if Equals(ArraySize(reversed), 1) {
        t.EqString("arbitration/declaration order does not decide it",
            reversed[0].fullId, "mod:CALL");
    }

    /// Lookup: ownership survives the offer ///

    let table = new AiNpcActionTable();
    table.contactId = "anon_1";
    table.tags = clientTags;
    table.claims = both;

    let owned = table.Lookup("[ACTION:TRICK:2300]");
    t.EqBool("lookup/a live command is owned", owned.Owned(), true);
    t.EqBool("lookup/and complete", owned.Complete(), true);

    let fumbled = table.Lookup("[ACTION:TRICK:2300:200]");
    t.EqBool("lookup/a fumbled command is still owned", fumbled.Owned(), true);
    t.EqBool("lookup/but not complete", fumbled.Complete(), false);

    let invented = table.Lookup("[ACTION:NOBODY]");
    t.EqBool("lookup/an invented command is owned by nobody", invented.Owned(), false);

    /// The transfer, which is now a command like any other ///

    t.EqString("transfer/the built-in declares one pattern",
        AiNpcTransferPattern(), "[ACTION:GIVE_EDDIES:{give_amount_eddies}]");
    t.EqString("transfer/its head is what an opt-out names",
        AiNpcTransferHead(), "[ACTION:GIVE_EDDIES:");

    let transferPattern = AiNpcParseActionPattern(AiNpcTransferPattern(), refusal);
    let paid = AiNpcMatchActionPattern(transferPattern, "[ACTION:GIVE_EDDIES:750]");
    t.EqBool("transfer/an amount is a field like any other", paid.complete, true);
    if Equals(ArraySize(paid.params), 1) {
        t.EqInt("transfer/the amount is read from the field",
            AiNpcTransferAmount(paid.params[0]), 750);
    }

    t.EqInt("transfer/a junk amount is worth nothing", AiNpcTransferAmount("a lot"), 0);
    t.EqInt("transfer/a page of zeroes cannot wrap an Int32",
        AiNpcTransferAmount("00000000000000009000"), 0);
    t.EqInt("transfer/one tag is clamped to the ceiling",
        AiNpcTransferAmount("999999"), AiNpcTransferCap());
    t.EqInt("transfer/the conversation is clamped too",
        AiNpcClampTransfer(4000, 4500, AiNpcTransferCap()), 500);
    t.EqInt("transfer/a spent conversation pays nothing",
        AiNpcClampTransfer(1000, AiNpcTransferCap(), AiNpcTransferCap()), 0);

    /// Tags: granted, never given ///

    t.EqBool("tags/ainpc: is reserved", AiNpcTagIsReserved("ainpc:contact"), true);
    t.EqBool("tags/contact: is reserved too", AiNpcTagIsReserved("contact:judy"), true);
    t.EqBool("tags/a mod's own tag is not", AiNpcTagIsReserved("joytoy:client"), false);
    t.EqBool("tags/a tag with a space is not a tag", AiNpcTagIsWellFormed("joytoy client"), false);
    t.EqString("tags/a contact tag is derived from the id",
        AiNpcContactTagFor("anon_1"), "contact:anon_1");

    // A section with nothing in it does not appear at all -- a function rather than a rule per
    // tag, so it cannot be true of one and quietly false of the next.
    t.EqString("prompt/an empty section is omitted", AiNpcSection("quest", ""), "");
    t.EqString("prompt/a section with content is wrapped",
        AiNpcSection("quest", "x"), "<quest>x</quest>");
}

/// Config helpers ///

func AiNpcTestActionParsing(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("collapse/runs", AiNpcCollapseSpaces("a    b"), "a b");
    t.EqString("collapse/noop", AiNpcCollapseSpaces("a b"), "a b");

    // Cutting a command out of the middle of a sentence has to leave one gap, not two: the
    // words either side kept their separators.
    let midSentence = AiNpcStripActionTags("here [ACTION:GIVE_EDDIES:40] you go",
        ["[ACTION:GIVE_EDDIES:40]"]);
    t.EqString("strip/a tag anywhere leaves one space", midSentence, "here you go");

    let leading = AiNpcStripActionTags("[ACTION:GIVE_EDDIES:750] here, take this",
        ["[ACTION:GIVE_EDDIES:750]"]);
    t.EqString("strip/a leading tag leaves no blank", leading, "here, take this");

    let repeated = AiNpcStripActionTags("[ACTION:X][ACTION:X] all yours", ["[ACTION:X]"]);
    t.EqString("strip/every occurrence goes", repeated, "all yours");

    // An unterminated tag is not one: it stays where it was written rather than swallowing the
    // rest of the message on its way out.
    let open = AiNpcFindActionTags("here [ACTION:GIVE_EDDIES:500 and the rest");
    t.EqInt("strip/an unterminated tag is not found", ArraySize(open), 0);

    /// Reading an amount out of a field ///

    t.EqInt("amount/a plain number", AiNpcTransferAmount("750"), 750);
    t.EqInt("amount/junk pays nothing", AiNpcTransferAmount("alot"), 0);
    t.EqInt("amount/a negative pays nothing", AiNpcTransferAmount("-500"), 0);

    // Nine digits is where StringToInt stops fitting in an Int32. Past it the amount is
    // refused outright rather than wrapping into a negative transfer.
    t.EqInt("amount/an unreadable number pays nothing",
        AiNpcTransferAmount("99999999999"), 0);

    // One tag against the ceiling, which is not the conversation cap: a model writing a page
    // of digits is a typo, and it must not read as a decision to give everything at once.
    t.EqInt("amount/one tag is clamped to the cap",
        AiNpcTransferAmount("999999"), AiNpcTransferCap());

    t.EqBool("actions/digits", AiNpcIsDigits("1500"), true);
    t.EqBool("actions/not digits", AiNpcIsDigits("1 500"), false);
    t.EqBool("actions/empty is not digits", AiNpcIsDigits(""), false);

    t.EqInt("amount/under the cap", AiNpcClampAmount(750, 5000), 750);
    t.EqInt("amount/at the cap", AiNpcClampAmount(5000, 5000), 5000);
    t.EqInt("amount/over the cap", AiNpcClampAmount(50000, 5000), 5000);
    t.EqInt("amount/zero", AiNpcClampAmount(0, 5000), 0);
    t.EqInt("amount/negative", AiNpcClampAmount(-1, 5000), 0);
}

func AiNpcTestTransferClamp(t: ref<AiNpcTestRunner>) -> Void {
    t.EqInt("clamp/under cap", AiNpcClampTransfer(100, 0, 5000), 100);
    t.EqInt("clamp/exactly cap", AiNpcClampTransfer(5000, 0, 5000), 5000);
    t.EqInt("clamp/partial remainder", AiNpcClampTransfer(1000, 4500, 5000), 500);
    t.EqInt("clamp/cap reached", AiNpcClampTransfer(1000, 5000, 5000), 0);
    t.EqInt("clamp/over cap already", AiNpcClampTransfer(1000, 9000, 5000), 0);
    t.EqInt("clamp/zero request", AiNpcClampTransfer(0, 0, 5000), 0);
    t.EqInt("clamp/negative request", AiNpcClampTransfer(-500, 0, 5000), 0);

    // Regression: the exploit was an unbounded loop of maximum transfers.
    t.EqInt("clamp/regression: farming is bounded",
        AiNpcClampTransfer(15000, 0, AiNpcTransferCap()), AiNpcTransferCap());
}

// The running total, which nothing could assert while it was one Int32 on a system.

// The running total, which nothing could assert while it was one Int32 on a system.
func AiNpcTestTransferLedger(t: ref<AiNpcTestRunner>) -> Void {
    let ledger = new AiNpcTransferLedger();

    t.EqInt("ledger/nobody has spent anything", ledger.SpentOn("panam"), 0);
    t.EqInt("ledger/first grant", ledger.Grant("panam", 2000, 5000), 2000);
    t.EqInt("ledger/recorded", ledger.SpentOn("panam"), 2000);
    t.EqInt("ledger/second grant accumulates", ledger.Grant("panam", 1000, 5000), 1000);
    t.EqInt("ledger/partial remainder", ledger.Grant("panam", 5000, 5000), 2000);
    t.EqInt("ledger/cap reached", ledger.Grant("panam", 100, 5000), 0);
    t.EqInt("ledger/total is the cap", ledger.SpentOn("panam"), 5000);

    // The defect this file exists for: one global counter made Panam's generosity come out of
    // Judy's allowance, and the refusal handed to the model named a conversation in which
    // nothing had been sent.
    t.EqInt("ledger/another contact is untouched", ledger.SpentOn("judy"), 0);
    t.EqInt("ledger/another contact has its own cap", ledger.Grant("judy", 5000, 5000), 5000);
    t.EqInt("ledger/the first is still spent", ledger.SpentOn("panam"), 5000);

    // The other half of the same defect: erasing one thread refilled everybody.
    ledger.Reset("panam");
    t.EqInt("ledger/reset refills the contact", ledger.SpentOn("panam"), 0);
    t.EqInt("ledger/reset leaves the others", ledger.SpentOn("judy"), 5000);
    t.EqInt("ledger/refilled contact may give again", ledger.Grant("panam", 5000, 5000), 5000);

    // An unaddressed transfer would spend a bound nobody owns.
    t.EqInt("ledger/no contact grants nothing", ledger.Grant("", 1000, 5000), 0);
}

/// Transport diagnostics ///

// Guards the sentence a player reads when a request never reaches the network.
//
// These were unreachable by any test until AiNpcDescribeTransportFailure stopped reading
// GetAiNpcSystem(), which is the reason the https branch was missing for as long as it
// was: the only way to exercise it was to break a live session on purpose.
/// Quest-fact bridge ///

func AiNpcTestFactBridge(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("facts/a flag going up fires", AiNpcFactCrossed(0, 1, 1));
    t.Check("facts/writing it again does not", !AiNpcFactCrossed(1, 2, 1));
    t.Check("facts/an unset flag does not", !AiNpcFactCrossed(0, 0, 1));

    // The baseline rule. A quest finished three saves ago reads as done the moment the
    // session opens, and a character bringing it up as fresh news is the failure this
    // prevents -- so the first value seen is a starting point, never a trigger.
    t.Check("facts/already done before the session started", !AiNpcFactCrossed(5, 5, 1));
    t.Check("facts/still not news when it is written again", !AiNpcFactCrossed(5, 6, 1));

    // A counter fires on the entry it names and stays quiet above it, which is what makes
    // "after the third one" expressible without the declaring mod adding a flag for it.
    t.Check("facts/a counter fires on its number", AiNpcFactCrossed(2, 3, 3));
    t.Check("facts/and not on the one after", !AiNpcFactCrossed(3, 4, 3));
    t.Check("facts/nor on the way up to it", !AiNpcFactCrossed(1, 2, 3));

    // A mod that clears its fact and raises it again is signalling twice, and means to.
    t.Check("facts/cleared and raised again is news again", AiNpcFactCrossed(0, 1, 1));

    // The frame is what stops a third party's sentence from reading as something V said,
    // since it lands in <now> among lines that are.
    t.EqString("facts/an event is framed as the world reporting",
        AiNpcFactEventContext("Panam heard about the convoy."), "[WORLD EVENT: Panam heard about the convoy.]");
    t.EqString("facts/nothing said, nothing added", AiNpcFactEventContext(""), "");
}

/// Weather ///

func AiNpcTestExtensionOrder(t: ref<AiNpcTestRunner>) -> Void {
    let empty: array<String>;
    t.EqInt("order/an empty list takes the first entry at 0", AiNpcIdInsertionPoint(empty, "a:x"), 0);
    t.EqInt("order/and knows it holds nothing", AiNpcIdIndexOf(empty, "a:x"), -1);

    let ids: array<String>;
    ArrayPush(ids, "b:x");
    ArrayPush(ids, "d:x");
    t.EqInt("order/before everything", AiNpcIdInsertionPoint(ids, "a:x"), 0);
    t.EqInt("order/between", AiNpcIdInsertionPoint(ids, "c:x"), 1);
    t.EqInt("order/after everything", AiNpcIdInsertionPoint(ids, "e:x"), 2);

    // THE TRAP, asserted rather than described. A mnemonic id is exactly the kind whose
    // alphabetical order is not its author's, and both defects this layer produced on the day
    // it was written were somebody laying out a case by the story instead of by the string.
    let greek: array<String>;
    ArrayPush(greek, "delta");
    ArrayPush(greek, "epsilon");
    t.EqInt("order/gamma sorts AFTER delta and epsilon, not before them",
        AiNpcIdInsertionPoint(greek, "gamma"), 2);
    t.EqInt("order/and alpha before both", AiNpcIdInsertionPoint(greek, "alpha"), 0);

    // Case-sensitive: an id is a key, not a label. Folding case would order two different mods
    // as one.
    let mods: array<String>;
    ArrayPush(mods, "RogueGigs:offers");
    t.EqInt("order/case is part of the key", AiNpcIdIndexOf(mods, "roguegigs:offers"), -1);

    // The two questions are different, and confusing them either duplicates an entry or
    // overwrites its neighbour.
    let held: array<String>;
    ArrayPush(held, "a:x");
    ArrayPush(held, "b:x");
    t.EqInt("order/an id already held is found where it is", AiNpcIdIndexOf(held, "b:x"), 1);
    t.EqInt("order/and would be inserted at the same place", AiNpcIdInsertionPoint(held, "b:x"), 1);
}

func AiNpcTestExtensionCoverage(t: ref<AiNpcTestRunner>) -> Void {
    // An empty list means EVERY drivable contact. It is the shape a mod uses to add one line
    // to the whole cast, and reading it as "nobody" would make such a mod silently do nothing.
    let all = new AiNpcExtensionEntry();
    t.EqBool("coverage/no list means every contact", all.Covers("panam"), true);
    t.EqBool("coverage/including one nobody has heard of", all.Covers("some_other_mod_01"), true);

    let named = new AiNpcExtensionEntry();
    ArrayPush(named.contactIds, "rogue");
    ArrayPush(named.contactIds, "judy");
    t.EqBool("coverage/a named contact is covered", named.Covers("rogue"), true);
    t.EqBool("coverage/one that is not, is not", named.Covers("panam"), false);

    // Listeners answer the same question the same way, and the two classes are separate
    // declarations -- so the rule is asserted on both rather than assumed to have been copied.
    let watcher = new AiNpcListenerEntry();
    t.EqBool("coverage/a listener with no list hears everything", watcher.Covers("panam"), true);
    ArrayPush(watcher.contactIds, "judy");
    t.EqBool("coverage/and one with a list hears only it", watcher.Covers("panam"), false);
}

// The forbidden states, and the point is that most of them can no longer be written down.
//
// "The chat is on screen" used to live on four objects at once. These assertions pin the two
// that are now DERIVED -- chat-open and typing -- to the single screen they are derived from,
// so a future field claiming to know better would have to disagree with them here first.
