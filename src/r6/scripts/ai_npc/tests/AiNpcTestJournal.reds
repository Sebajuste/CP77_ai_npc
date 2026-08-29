module AiNpc

// Le journal de conversation : operations, rejeu, branches, pointeur de sauvegarde.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

// Renders a replayed state as "judy=V:a|N:b ; panam=V:x", in first-appearance order.
func AiNpcTestRenderState(conversations: array<ref<AiNpcConversation>>) -> String {
    let result = "";
    let i = 0;
    while i < ArraySize(conversations) {
        if i > 0 {
            result += " ; ";
        }
        result += conversations[i].contactId + "=" + AiNpcTestRender(conversations[i].messages);
        i += 1;
    }
    return result;
}

// A journal as it comes back off disk: serialized to lines, then parsed again. Every
// replay assertion below goes through this, so the tests exercise the file format rather
// than the in-memory objects the writer happened to build.

// A journal as it comes back off disk: serialized to lines, then parsed again. Every
// replay assertion below goes through this, so the tests exercise the file format rather
// than the in-memory objects the writer happened to build.
func AiNpcTestRoundTripOps(ops: array<ref<AiNpcJournalOp>>) -> array<ref<AiNpcJournalOp>> {
    let lines: array<String>;
    ArrayPush(lines, AiNpcJournalHeaderLine(3l, "b1", ""));

    let i = 0;
    while i < ArraySize(ops) {
        ArrayPush(lines, AiNpcJournalOpToLine(ops[i]));
        i += 1;
    }
    return AiNpcJournalParseLines(lines);
}

// The import setting is the one place a pointer is typed by a human, so the parser has to
// take what a log line offers ("b14:467") and refuse the rest without inventing a branch.

// The import setting is the one place a pointer is typed by a human, so the parser has to
// take what a log line offers ("b14:467") and refuse the rest without inventing a branch.
func AiNpcTestJournalPointer(t: ref<AiNpcTestRunner>) -> Void {
    let full = AiNpcParseJournalPointer("b14:467");
    t.EqBool("pointer/full is valid", full.valid, true);
    t.EqInt("pointer/full branch", full.branchId, 14);
    t.EqInt("pointer/full seq", full.seq, 467);

    // No sequence number means "as far as that branch goes", which the store resolves to
    // the head -- zero here, never a guess.
    let branchOnly = AiNpcParseJournalPointer("b14");
    t.EqBool("pointer/branch only is valid", branchOnly.valid, true);
    t.EqInt("pointer/branch only branch", branchOnly.branchId, 14);
    t.EqInt("pointer/branch only seq", branchOnly.seq, 0);

    let bare = AiNpcParseJournalPointer("14:467");
    t.EqBool("pointer/bare number is valid", bare.valid, true);
    t.EqInt("pointer/bare number branch", bare.branchId, 14);

    let spaced = AiNpcParseJournalPointer("  B14:467");
    t.EqBool("pointer/leading blanks and capital B", spaced.valid, true);
    t.EqInt("pointer/leading blanks branch", spaced.branchId, 14);

    t.EqBool("pointer/empty is invalid", AiNpcParseJournalPointer("").valid, false);
    t.EqBool("pointer/prefix alone is invalid", AiNpcParseJournalPointer("b").valid, false);
    t.EqBool("pointer/words are invalid", AiNpcParseJournalPointer("latest").valid, false);
    t.EqBool("pointer/branch zero is invalid", AiNpcParseJournalPointer("b0:5").valid, false);
    t.EqBool("pointer/three parts are invalid", AiNpcParseJournalPointer("b1:2:3").valid, false);
}

// The listing path: a branch's head is read from its tail rather than from a full parse,
// and a quoted message is flattened and clipped so a table cannot be pushed apart by one
// long reply.

// The listing path: a branch's head is read from its tail rather than from a full parse,
// and a quoted message is flattened and clipped so a table cannot be pushed apart by one
// long reply.
func AiNpcTestJournalListing(t: ref<AiNpcTestRunner>) -> Void {
    let lines: array<String>;
    ArrayPush(lines, AiNpcJournalHeaderLine(3, "b7", "b3:4"));
    ArrayPush(lines, AiNpcJournalOpToLine(AiNpcJournalOpAppend(11, "judy", "hey", true)));
    ArrayPush(lines, AiNpcJournalOpToLine(AiNpcJournalOpAppend(12, "judy", "hey yourself", false)));
    t.EqInt("listing/head is the tail operation", AiNpcJournalTailSeq(lines), 12);

    // A crash mid-write leaves a truncated last line; the head is the last COMPLETE one.
    ArrayPush(lines, "{\"n\":13,\"c\":\"jud");
    ArrayPush(lines, "");
    t.EqInt("listing/truncated tail is skipped", AiNpcJournalTailSeq(lines), 12);

    let headerOnly: array<String>;
    ArrayPush(headerOnly, AiNpcJournalHeaderLine(3, "b8", ""));
    t.EqInt("listing/header alone has no head", AiNpcJournalTailSeq(headerOnly), 0);

    t.EqString("listing/short text is untouched", AiNpcClipText("hey", 90), "hey");
    t.EqString("listing/newlines are flattened", AiNpcClipText("a
b", 90), "a b");
    t.EqString("listing/long text is clipped", AiNpcClipText("abcdef", 3), "abc...");
}

func AiNpcTestJournal(t: ref<AiNpcTestRunner>) -> Void {
    let ops: array<ref<AiNpcJournalOp>>;
    ArrayPush(ops, AiNpcJournalOpAppend(1, "judy", "hey", true));
    ArrayPush(ops, AiNpcJournalOpAppend(2, "judy", "hey yourself", false));
    ArrayPush(ops, AiNpcJournalOpAppend(3, "panam", "you up?", true));
    ArrayPush(ops, AiNpcJournalOpAppend(4, "judy", "still there?", true));

    let parsed = AiNpcTestRoundTripOps(ops);
    t.EqInt("journal/header line is not an operation", ArraySize(parsed), 4);
    t.EqInt("journal/head seq", AiNpcJournalHeadSeq(parsed), 4);

    // The whole point of the pointer: the same file replays to different states.
    t.EqString("journal/replay at head",
        AiNpcTestRenderState(AiNpcJournalReplay(parsed, 4, 20)),
        "judy=V:hey|N:hey yourself|V:still there? ; panam=V:you up?");
    t.EqString("journal/replay in the past",
        AiNpcTestRenderState(AiNpcJournalReplay(parsed, 2, 20)),
        "judy=V:hey|N:hey yourself");
    t.EqString("journal/replay before anything", AiNpcTestRenderState(AiNpcJournalReplay(parsed, 0, 20)), "");

    // A save pointing past the head (a branch that lost its tail) sees what is there,
    // never somebody else's messages.
    t.EqString("journal/replay past the head",
        AiNpcTestRenderState(AiNpcJournalReplay(parsed, 99, 20)),
        "judy=V:hey|N:hey yourself|V:still there? ; panam=V:you up?");

    // Undo and clear replay as operations, not as rewritten history.
    let edits: array<ref<AiNpcJournalOp>>;
    ArrayPush(edits, AiNpcJournalOpAppend(1, "judy", "hey", true));
    ArrayPush(edits, AiNpcJournalOpAppend(2, "judy", "yo", false));
    ArrayPush(edits, AiNpcJournalOpAppend(3, "judy", "again", true));
    ArrayPush(edits, AiNpcJournalOpUndo(4, "judy"));
    ArrayPush(edits, AiNpcJournalOpClear(5, "judy"));

    let replayedEdits = AiNpcTestRoundTripOps(edits);
    t.EqString("journal/undo replays", AiNpcTestRenderState(AiNpcJournalReplay(replayedEdits, 4, 20)), "judy=V:hey|N:yo");
    t.EqString("journal/clear replays", AiNpcTestRenderState(AiNpcJournalReplay(replayedEdits, 5, 20)), "judy=");

    // Replay applies the same trim the live path does, so a long branch cannot restore a
    // window wider than the one the game would have kept.
    let many: array<ref<AiNpcJournalOp>>;
    let n = 1;
    while n <= 10 {
        ArrayPush(many, AiNpcJournalOpAppend(n, "judy", s"m\(n)", (n % 2) == 1));
        n += 1;
    }
    let trimmed = AiNpcJournalReplay(AiNpcTestRoundTripOps(many), 10, 2);
    t.EqInt("journal/replay honours the trim window", ArraySize(trimmed[0].messages), 4);

    // Fork: the snapshot must reproduce the state it was taken from, and must not carry
    // contacts that have nothing to say.
    let state = AiNpcJournalReplay(parsed, 4, 20);
    let silent = new AiNpcConversation();
    silent.contactId = "river";
    ArrayPush(state, silent);

    let snapshot = AiNpcJournalSnapshotOps(state);
    t.EqInt("journal/snapshot skips empty conversations", ArraySize(snapshot), 2);
    t.EqInt("journal/snapshot numbers from one", snapshot[0].seq, 1);
    t.EqString("journal/fork reproduces the forked state",
        AiNpcTestRenderState(AiNpcJournalReplay(AiNpcTestRoundTripOps(snapshot), 2, 20)),
        AiNpcTestRenderState(AiNpcJournalReplay(parsed, 4, 20)));

    // The reload-into-the-past sequence, end to end: a save sits at seq 2 of a branch whose
    // head is 4, the player sends a message, the store forks. The new branch must replay to
    // "the state at seq 2, plus the new message" -- no messages from the abandoned tail,
    // and no message counted twice.
    //
    // Regression: the fork used to snapshot after applying the operation, which put the new
    // message in the snapshot *and* in the entry after it.
    let rewound = AiNpcJournalReplay(parsed, 2, 20);
    let forkOps = AiNpcJournalSnapshotOps(rewound);
    let resumed = AiNpcJournalOpAppend(ArraySize(forkOps) + 1, "judy", "wait, again", true);
    ArrayPush(forkOps, resumed);

    t.EqString("journal/fork resumes from the pointer, not the head",
        AiNpcTestRenderState(AiNpcJournalReplay(AiNpcTestRoundTripOps(forkOps), resumed.seq, 20)),
        "judy=V:hey|N:hey yourself|V:wait, again");

    // JSONL invariant: one operation is exactly one line. A newline inside a message is
    // escaped by the JSON writer -- if it ever were not, every message after it would be
    // lost on the next load, silently.
    let hostile = AiNpcJournalOpAppend(1, "judy", "two\nlines \"quoted\" and a | pipe", true);
    let line = AiNpcJournalOpToLine(hostile);
    let lineParts = StrSplit(line, "\n");
    t.EqInt("journal/one operation is one line", ArraySize(lineParts), 1);

    let hostileOps: array<ref<AiNpcJournalOp>>;
    ArrayPush(hostileOps, hostile);
    let hostileState = AiNpcJournalReplay(AiNpcTestRoundTripOps(hostileOps), 1, 20);
    t.EqString("journal/hostile text survives the file format",
        hostileState[0].messages[0].text,
        "two\nlines \"quoted\" and a | pipe");

    // Damage is confined to the lines that carry it: a truncated tail costs the last
    // message, not the conversation.
    let damaged: array<String>;
    ArrayPush(damaged, AiNpcJournalHeaderLine(3l, "b1", "b0:12"));
    ArrayPush(damaged, AiNpcJournalOpToLine(AiNpcJournalOpAppend(1, "judy", "hey", true)));
    ArrayPush(damaged, "");
    ArrayPush(damaged, "{\"n\":2,\"c\":\"judy\",\"o\":\"a\",\"p\":fal");
    ArrayPush(damaged, "not json at all");
    ArrayPush(damaged, AiNpcJournalOpToLine(AiNpcJournalOpAppend(3, "judy", "still here", false)));

    let survivors = AiNpcJournalParseLines(damaged);
    t.EqInt("journal/skips blank and corrupt lines", ArraySize(survivors), 2);
    t.EqString("journal/a corrupt line does not lose the rest",
        AiNpcTestRenderState(AiNpcJournalReplay(survivors, 3, 20)),
        "judy=V:hey|N:still here");

    // Pointers are for logs and for the parent field of a fork; the savegame stores the
    // branch and the sequence number separately, so this is never parsed back.
    t.EqString("journal/pointer format", AiNpcJournalPointer("b3", 147), "b3:147");
    t.EqString("journal/no branch means no pointer", AiNpcJournalPointer("", 0), "");
    t.EqString("journal/branch file name", AiNpcBranchFileName(AiNpcBranchId(7)), "journal.b7.jsonl");
}

/// Response extraction ///
