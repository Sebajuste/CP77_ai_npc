module AiNpc

import RedData.Json.*

// How a conversation history is tied to a savegame.
//
// A history has to belong to a playthrough and to a moment in it. Stored flat, keyed by
// contact id alone, it belongs to nobody: reloading an earlier save leaves the chat at its
// latest state, and a new game inherits the previous playthrough's whole history.
//
// Putting it all in the savegame would fix both and put every schema change in front of the
// save format, and take the file away from the player, whose copy is the first thing a bug
// report asks for. So the bulk stays on disk and the savegame carries a pointer into it:
//
//   * on disk, an append-only log of operations, one file per branch, one JSON object per line;
//   * in the savegame, two persistent fields: the branch id and a sequence number.
//
// Reading is a replay of every operation with seq <= the saved number, through the same pure
// functions the live path uses, so it reproduces the state bit for bit.
//
// The savegame's pointer needs no save hook -- and there is no reliable one. A persistent
// field is serialised with whatever value it holds at the moment the game saves, so the
// pointer is simply kept current on every write and any save picks up the right one.
//
// Branching is the part that has to be right. Save at seq 100, play to 150, reload: the
// numbers 101..150 are already spent on a timeline this save is not on, and reusing them
// would let a later reload replay another timeline's messages. So a write from a pointer
// that is not at the head of its branch *forks*: a new branch file opens with a snapshot
// of the replayed state, and the two timelines never share a number again. Branch ids are
// allocated from a counter that is never decremented, so a purged branch's id is never
// handed out a second time -- a pointer into a deleted branch resolves to nothing, never
// to somebody else's conversation.
//
// Everything in this file is pure: no game API, no file access, no global state. The IO
// and the lifecycle live in AiNpcConversationStore.reds; the replay is tested directly
// (see tests\AiNpcTestJournal.reds).

public class AiNpcConversation {
    public let contactId: String;

    // Everything that has fallen out of the window and is no longer sent verbatim.
    // AiNpcMemory.reds holds the invariant: `messages` is always a suffix, nothing is in both.
    public let memory: ref<AiNpcMemory>;

    public let messages: array<ref<AiNpcMessage>>;
}

/// Operations ///

// Short on purpose: written once per message for the life of a playthrough.
func AiNpcJournalKindAppend() -> String { return "a"; }
func AiNpcJournalKindUndo() -> String { return "u"; }
func AiNpcJournalKindClear() -> String { return "x"; }
func AiNpcJournalKindSnapshot() -> String { return "s"; }

public class AiNpcJournalOp {
    public let seq: Int32;
    public let contactId: String;
    public let kind: String;

    // Append only.
    public let fromPlayer: Bool;
    public let text: String;
    // Absolute in-game seconds; AiNpcTimeUnknown() when the caller had no clock to read.
    public let gameTimeSeconds: Int32;
    // Append only. Text is the zero, so a line written before this field existed reads back as
    // what it was.
    public let channel: AiNpcChannelId;

    // Snapshot only: the whole message list for this contact, replacing what the replay had
    // built. It is what makes a fork cheap to open and cheap to read.
    public let snapshot: array<ref<AiNpcMessage>>;

    // Snapshot only: the memory that goes with that message list. A compaction is a snapshot,
    // which is why memory needed no operation of its own, and it has to travel here for Fork,
    // which would otherwise drop the memory of every contact it snapshots.
    //
    // The pairing is the point: evicting the messages and writing the memory that absorbed them
    // are one line, so no reload can land between the two.
    public let memory: ref<AiNpcMemory>;
}

func AiNpcJournalOpAppend(seq: Int32, contactId: String, text: String, fromPlayer: Bool) -> ref<AiNpcJournalOp> {
    return AiNpcJournalOpAppendAt(seq, contactId, text, fromPlayer, AiNpcTimeUnknown());
}

func AiNpcJournalOpAppendAt(seq: Int32, contactId: String, text: String, fromPlayer: Bool,
                            gameTimeSeconds: Int32, opt channel: AiNpcChannelId) -> ref<AiNpcJournalOp> {
    let op = new AiNpcJournalOp();
    op.seq = seq;
    op.contactId = contactId;
    op.kind = AiNpcJournalKindAppend();
    op.text = text;
    op.fromPlayer = fromPlayer;
    op.gameTimeSeconds = gameTimeSeconds;
    op.channel = channel;
    return op;
}

func AiNpcJournalOpUndo(seq: Int32, contactId: String) -> ref<AiNpcJournalOp> {
    let op = new AiNpcJournalOp();
    op.seq = seq;
    op.contactId = contactId;
    op.kind = AiNpcJournalKindUndo();
    return op;
}

func AiNpcJournalOpClear(seq: Int32, contactId: String) -> ref<AiNpcJournalOp> {
    let op = new AiNpcJournalOp();
    op.seq = seq;
    op.contactId = contactId;
    op.kind = AiNpcJournalKindClear();
    return op;
}

func AiNpcJournalOpSnapshot(seq: Int32, contactId: String, messages: array<ref<AiNpcMessage>>) -> ref<AiNpcJournalOp> {
    return AiNpcJournalOpSnapshotWith(seq, contactId, messages, AiNpcMemoryNew());
}

func AiNpcJournalOpSnapshotWith(seq: Int32, contactId: String, messages: array<ref<AiNpcMessage>>,
        memory: ref<AiNpcMemory>) -> ref<AiNpcJournalOp> {
    let op = new AiNpcJournalOp();
    op.seq = seq;
    op.contactId = contactId;
    op.kind = AiNpcJournalKindSnapshot();
    op.snapshot = AiNpcHistoryCopy(messages);
    op.memory = AiNpcMemoryCopy(memory);
    return op;
}

/// Serialization ///

func AiNpcJournalOpToJson(op: ref<AiNpcJournalOp>) -> ref<JsonObject> {
    let entry = ParseJson("{}") as JsonObject;
    entry.SetKeyInt64("n", Cast<Int64>(op.seq));
    entry.SetKeyString("c", op.contactId);
    entry.SetKeyString("o", op.kind);

    if Equals(op.kind, AiNpcJournalKindAppend()) {
        entry.SetKeyBool("p", op.fromPlayer);
        entry.SetKeyString("t", op.text);
        // Omitted when unknown rather than written as 0, so a reader cannot mistake the
        // sentinel for a real time and the line looks like one written before the field.
        if NotEquals(op.gameTimeSeconds, AiNpcTimeUnknown()) {
            entry.SetKeyInt64("g", Cast<Int64>(op.gameTimeSeconds));
        }
        // "ch" et pas "c" : "c" est deja le contact, deux lignes plus haut. Meme cle dans les
        // deux serialisations, celle-ci et celle des instantanes, pour qu'un lecteur n'ait
        // qu'un nom a retenir.
        //
        // Omise quand la ligne est ecrite, comme "g" l'est quand l'heure est inconnue : un
        // journal sans ligne parlee est byte pour byte celui d'avant ce champ.
        if NotEquals(op.channel, AiNpcChannelId.Text) {
            entry.SetKeyInt64("ch", Cast<Int64>(EnumInt(op.channel)));
        }
    }
    if Equals(op.kind, AiNpcJournalKindSnapshot()) {
        entry.SetKey("m", AiNpcMessagesToJson(op.snapshot));
        // Omitted when there is nothing remembered, so a line for a conversation with no memory
        // is byte-identical to one written before the field existed.
        if !AiNpcMemoryIsEmpty(op.memory) {
            entry.SetKey("mm", AiNpcMemoryToJson(op.memory));
        }
    }
    return entry;
}

// Null for anything that is not an operation: the header line, a blank line, or one truncated
// by a crash mid-write. A journal is append-only, so damage is confined to the tail.
func AiNpcJournalOpFromJson(json: ref<JsonObject>) -> ref<AiNpcJournalOp> {
    if !IsDefined(json) || !json.HasKey("n") || !json.HasKey("o") {
        return null;
    }

    let op = new AiNpcJournalOp();
    op.seq = Cast<Int32>(json.GetKeyInt64("n"));
    op.contactId = json.GetKeyString("c");
    op.kind = json.GetKeyString("o");
    op.fromPlayer = json.GetKeyBool("p");
    op.text = json.GetKeyString("t");
    op.gameTimeSeconds = AiNpcTimeUnknown();
    if json.HasKey("g") {
        op.gameTimeSeconds = Cast<Int32>(json.GetKeyInt64("g"));
    }
    // Absente = Text, ce qui est le cas de toute ligne ecrite avant ce champ.
    op.channel = AiNpcChannelFromInt(Cast<Int32>(json.GetKeyInt64("ch")));

    if Equals(op.kind, AiNpcJournalKindSnapshot()) {
        op.snapshot = AiNpcMessagesFromJson(json.GetKey("m") as JsonArray);
        op.memory = AiNpcMemoryFromJson(AiNpcJsonObjectAt(json, "mm"));
    }
    return op;
}

// One operation, one line. ToString() with no indent is single-line and the JSON writer escapes
// a newline inside a message, so a message can never break the line structure.
func AiNpcJournalOpToLine(op: ref<AiNpcJournalOp>) -> String {
    return AiNpcJournalOpToJson(op).ToString();
}

func AiNpcJournalParseLines(lines: array<String>) -> array<ref<AiNpcJournalOp>> {
    let result: array<ref<AiNpcJournalOp>>;
    let i = 0;
    while i < ArraySize(lines) {
        if NotEquals(StrLen(lines[i]), 0) {
            let parsed = ParseJson(lines[i]);
            if IsDefined(parsed) && !parsed.IsUndefined() && parsed.IsObject() {
                let op = AiNpcJournalOpFromJson(parsed as JsonObject);
                if IsDefined(op) {
                    ArrayPush(result, op);
                }
            }
        }
        i += 1;
    }
    return result;
}

// First line of every branch file. It carries no operation, so the parser skips it: it exists
// so a file found on disk can be traced back to what it forked from.
func AiNpcJournalHeaderLine(version: Int64, branch: String, parent: String) -> String {
    let header = ParseJson("{}") as JsonObject;
    header.SetKeyInt64("h", version);
    header.SetKeyString("b", branch);
    header.SetKeyString("from", parent);
    return header.ToString();
}

/// Branch naming ///

func AiNpcBranchId(index: Int32) -> String {
    return s"b\(index)";
}

func AiNpcBranchFileName(branch: String) -> String {
    return "journal." + branch + ".jsonl";
}

// "b3:147", for logs and for the parent field of a fork. A savegame never parses one back: it
// stores the two numbers separately so restoring a pointer needs no string parsing.
func AiNpcJournalPointer(branch: String, seq: Int32) -> String {
    if Equals(StrLen(branch), 0) {
        return "";
    }
    return s"\(branch):\(seq)";
}

public class AiNpcJournalPointerParts {
    public let valid: Bool;
    public let branchId: Int32;
    public let seq: Int32;      // 0 = "as far as that branch goes"
}

// Reads a pointer back into its two numbers. The one place a human writes one is the
// importConversationsFrom setting, copied from a log line that already reads "b14:467", so this
// parses exactly that and refuses the rest. A branch id of zero is not a branch, so anything
// that does not yield a positive id is invalid -- which covers every typo at once.
func AiNpcParseJournalPointer(text: String) -> ref<AiNpcJournalPointerParts> {
    let parts = new AiNpcJournalPointerParts();

    let rest = AiNpcTrimLeadingBlanks(text);
    if StrBeginsWith(rest, "b") || StrBeginsWith(rest, "B") {
        rest = StrRight(rest, StrLen(rest) - 1);
    }
    if Equals(StrLen(rest), 0) {
        return parts;
    }

    let pieces = StrSplit(rest, ":");
    if ArraySize(pieces) < 1 || ArraySize(pieces) > 2 {
        return parts;
    }

    parts.branchId = StringToInt(pieces[0]);
    if ArraySize(pieces) == 2 {
        parts.seq = StringToInt(pieces[1]);
    }
    parts.valid = parts.branchId > 0 && parts.seq >= 0;
    return parts;
}

/// Replay ///

func AiNpcConversationIndex(conversations: array<ref<AiNpcConversation>>, contactId: String) -> Int32 {
    let i = 0;
    while i < ArraySize(conversations) {
        if Equals(conversations[i].contactId, contactId) {
            return i;
        }
        i += 1;
    }
    return -1;
}

// The highest sequence number the file holds. A pointer below it means the savegame sits in the
// past of its own branch, which forces a fork on the next write.
func AiNpcJournalHeadSeq(ops: array<ref<AiNpcJournalOp>>) -> Int32 {
    let head = 0;
    let i = 0;
    while i < ArraySize(ops) {
        if ops[i].seq > head {
            head = ops[i].seq;
        }
        i += 1;
    }
    return head;
}

// The head of a branch without reading the branch: a branch file is append-only, so its last
// operation carries the highest number. AiNpcJournalHeadSeq scans every operation, which for
// fifteen branches is several thousand JSON parses before a listing can draw its first row.
//
// Scans backwards past blank and truncated lines, and answers 0 for a fresh fork that has only
// its header.
func AiNpcJournalTailSeq(lines: array<String>) -> Int32 {
    let i = ArraySize(lines) - 1;
    while i >= 0 {
        if NotEquals(StrLen(lines[i]), 0) {
            let parsed = ParseJson(lines[i]);
            if IsDefined(parsed) && !parsed.IsUndefined() && parsed.IsObject() {
                let op = AiNpcJournalOpFromJson(parsed as JsonObject);
                if IsDefined(op) {
                    return op.seq;
                }
            }
        }
        i -= 1;
    }
    return 0;
}

// The only place an operation is interpreted: the live path calls it to mutate the session's
// conversations and the replay calls it for every entry of a file, so "what the game did" and
// "what a reload rebuilds" are one function called twice rather than two to keep in agreement.
func AiNpcJournalApply(conversations: array<ref<AiNpcConversation>>, op: ref<AiNpcJournalOp>, maxTurns: Int32) -> array<ref<AiNpcConversation>> {
    let result = conversations;
    if !IsDefined(op) || Equals(StrLen(op.contactId), 0) {
        return result;
    }

    let index = AiNpcConversationIndex(result, op.contactId);
    if index < 0 {
        let fresh = new AiNpcConversation();
        fresh.contactId = op.contactId;
        fresh.memory = AiNpcMemoryNew();
        ArrayPush(result, fresh);
        index = ArraySize(result) - 1;
    }

    let conversation = result[index];
    if Equals(op.kind, AiNpcJournalKindAppend()) {
        conversation.messages = AiNpcHistoryTrim(
            AiNpcHistoryAppendAt(conversation.messages, op.text, op.fromPlayer, op.gameTimeSeconds,
                op.channel),
            maxTurns);
    } else {
        if Equals(op.kind, AiNpcJournalKindUndo()) {
            conversation.messages = AiNpcHistoryUndo(conversation.messages);
        } else {
            if Equals(op.kind, AiNpcJournalKindClear()) {
                ArrayClear(conversation.messages);
                // Clear means "this conversation never happened", and a surviving memory would
                // be the one thing still able to contradict that.
                conversation.memory = AiNpcMemoryNew();
            } else {
                if Equals(op.kind, AiNpcJournalKindSnapshot()) {
                    conversation.messages = AiNpcHistoryCopy(op.snapshot);
                    conversation.memory = AiNpcMemoryCopy(op.memory);
                }
            }
        }
    }

    return result;
}

// Applied in file order rather than sorted by sequence number: the file is append-only so the
// two agree, and trusting file order means a duplicated number degrades one entry instead of
// reordering a whole conversation.
func AiNpcJournalReplay(ops: array<ref<AiNpcJournalOp>>, upTo: Int32, maxTurns: Int32) -> array<ref<AiNpcConversation>> {
    let result: array<ref<AiNpcConversation>>;

    let i = 0;
    while i < ArraySize(ops) {
        if ops[i].seq <= upTo {
            result = AiNpcJournalApply(result, ops[i], maxTurns);
        }
        i += 1;
    }

    return result;
}

// One snapshot per contact that still has messages. Empty histories are skipped: an absent
// conversation and an empty one are the same thing to every reader.
func AiNpcJournalSnapshotOps(conversations: array<ref<AiNpcConversation>>) -> array<ref<AiNpcJournalOp>> {
    let result: array<ref<AiNpcJournalOp>>;
    let seq = 0;
    let i = 0;
    while i < ArraySize(conversations) {
        // A conversation with nothing but a memory is still worth snapshotting: the window can
        // be emptied by an undo while everything remembered still stands.
        if ArraySize(conversations[i].messages) > 0 || !AiNpcMemoryIsEmpty(conversations[i].memory) {
            seq += 1;
            ArrayPush(result, AiNpcJournalOpSnapshotWith(seq, conversations[i].contactId,
                conversations[i].messages, conversations[i].memory));
        }
        i += 1;
    }
    return result;
}

/// Message serialization ///
// Split out as free functions so a round-trip can be asserted without touching the disk.

func AiNpcMessagesToJson(messages: array<ref<AiNpcMessage>>) -> ref<JsonArray> {
    let result = ParseJson("[]") as JsonArray;
    let i = 0;
    while i < ArraySize(messages) {
        let entry = ParseJson("{}") as JsonObject;
        entry.SetKeyBool("p", messages[i].fromPlayer);
        entry.SetKeyString("t", messages[i].text);
        if AiNpcMessageHasTime(messages[i]) {
            entry.SetKeyInt64("g", Cast<Int64>(messages[i].gameTimeSeconds));
        }
        if NotEquals(messages[i].channel, AiNpcChannelId.Text) {
            entry.SetKeyInt64("ch", Cast<Int64>(EnumInt(messages[i].channel)));
        }
        result.AddItem(entry);
        i += 1;
    }
    return result;
}

func AiNpcMessagesFromJson(json: ref<JsonArray>) -> array<ref<AiNpcMessage>> {
    let result: array<ref<AiNpcMessage>>;
    if !IsDefined(json) {
        return result;
    }

    let i: Uint32 = 0u;
    while i < json.GetSize() {
        let entry = json.GetItem(i) as JsonObject;
        if IsDefined(entry) {
            // A missing "g" is normal for a snapshot written before the field existed, and
            // reads back as unknown rather than as time zero.
            let stamp = AiNpcTimeUnknown();
            if entry.HasKey("g") {
                stamp = Cast<Int32>(entry.GetKeyInt64("g"));
            }
            ArrayPush(result, AiNpcMessageNewAt(entry.GetKeyString("t"), entry.GetKeyBool("p"), stamp,
                AiNpcChannelFromInt(Cast<Int32>(entry.GetKeyInt64("ch")))));
        }
        i += 1u;
    }
    return result;
}
