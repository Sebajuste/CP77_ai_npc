module AiNpc

import RedFileSystem.*
import RedData.Json.*
import Codeware.*

// Conversation storage, tied to the savegame: files, session lifecycle, and the two
// persistent fields that ride along in the save. The model and the replay are in
// AiNpcJournal.reds.
//
// Files in <game>\r6\storages\AiNpc\ :
//   journal.index.json    - branch registry and the never-reused branch counter
//   journal.b<N>.jsonl    - one append-only branch, one JSON operation per line
//   conversations.v2.json - backup of the pre-journal file, kept after migration
//
// A ScriptableSystem rather than a ScriptableService: its state is per-playthrough and must
// not leak across a save load, and a service lives for the whole process.
//
// One source of truth for the live state, m_conversations, and nothing else may cache a
// copy. Every mutation goes to disk through RecordOp, which updates the list too.
public class AiNpcConversationStore extends ScriptableSystem {

    private const let INDEX_FILE: String = "journal.index.json";
    private const let LEGACY_FILE: String = "conversations.json";
    private const let LEGACY_BACKUP: String = "conversations.legacy.json";
    private const let MIGRATED_BACKUP: String = "conversations.v2.json";
    private const let SCHEMA_VERSION: Int64 = 3;
    // The backstop, not the prompt window: the point past which messages are destroyed
    // because no compaction came to absorb them. Not conditional on the memory setting, so
    // toggling that can never lose a message.

    // Bounds the replay at session start. Reaching it forks, snapshotting the already-trimmed
    // live state into a fresh file and leaving the long one behind.
    private const let MAX_BRANCH_ENTRIES: Int32 = 2000;

    // Ids are never reused, so purging one can cost an old savegame its history but never
    // hand it somebody else's. The seed branch is exempt.
    private const let MAX_BRANCHES: Int32 = 24;

    /// Savegame state ///
    // The whole footprint of this system in a save: which branch, and how far along. Kept
    // current on every write, because the game never says when it is about to save.
    //
    // Two Int32s rather than a "b3:147" string: the compiler refuses a persistent String
    // (INVALID_PERSISTENT), and integers need no parsing, so a restore cannot fail on a
    // malformed one.
    //
    // A contract with every savegame written from here on: their types must not change, and
    // a new fact about the pointer goes in a new field.
    private persistent let m_branchId: Int32;   // 0 = this playthrough has written nothing yet
    private persistent let m_seq: Int32;

    // What this savegame has already imported; zero means never. Without it, a key left in
    // settings.json would re-import on every load, so an hour of new conversation would
    // vanish the next time the save was opened.
    private persistent let m_importedBranch: Int32;
    private persistent let m_importedSeq: Int32;

    /// Session state ///

    private let m_conversations: array<ref<AiNpcConversation>>;
    private let m_head: Int32 = 0;
    private let m_resolved: Bool = false;
    private let m_callbackSystem: wref<CallbackSystem>;

    // Forces the first write to fork. Only the seed branch is read-only, and it has to be:
    // every pre-journal save adopts it, so one that appended directly would hand its messages
    // to all the others.
    private let m_readOnlyBranch: Bool = false;

    // Set by OnRestored, the only signal that reports it reliably. It tells a legitimate
    // orphan branch -- a new playthrough -- from one that means history has just been lost.
    private let m_restoredSession: Bool = false;

    public static func Get() -> ref<AiNpcConversationStore> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(NameOf<AiNpcConversationStore>()) as AiNpcConversationStore;
    }

    /// Lifecycle ///

    private func OnAttach() -> Void {
        this.m_callbackSystem = GameInstance.GetCallbackSystem();
        this.m_callbackSystem.RegisterCallback(n"Session/Ready", this, n"OnStoreSessionReady");
    }

    private func OnDetach() -> Void {
        if IsDefined(this.m_callbackSystem) {
            this.m_callbackSystem.UnregisterCallback(n"Session/Ready", this, n"OnStoreSessionReady");
        }
        this.m_callbackSystem = null;
    }

    // What resolution is driven by. OnRestored fires only for a session loaded from a save,
    // and only once the persistent fields are restored -- the pair of facts Resolve needs,
    // and it cannot be missed the way a callback subscription can.
    //
    // Session/Ready was never delivered here: the system subscribes from OnAttach, which runs
    // after the event is broadcast. Resolution then fell through to EnsureResolved with
    // restoredFromSave = false, and whether a loaded save kept its history came down to
    // whether the first write landed before or after the persistent restore. The symptom was
    // an intermittent reset on reload; the trace is a branch with an empty parent.
    private func OnRestored(saveVersion: Int32, gameVersion: Int32) -> Void {
        this.m_restoredSession = true;
        this.Resolve(true);
    }

    // A backstop that still carries the new-game case: OnRestored does not fire for a
    // playthrough that was never saved.
    private cb func OnStoreSessionReady(event: ref<GameSessionEvent>) -> Bool {
        if event.IsPreGame() {
            return false;
        }
        this.Resolve(event.IsRestored());
        return false;
    }

    /// Public API ///

    // Reads do not resolve: before Session/Ready there is no way to tell a loaded save from a
    // new game, so resolving would settle it wrongly and for good. An early read gets an empty
    // history and the next one gets the real one. Only writes force the issue.
    public func GetMessages(contactId: String) -> array<ref<AiNpcMessage>> {
        let index = AiNpcConversationIndex(this.m_conversations, contactId);
        if index < 0 {
            let empty: array<ref<AiNpcMessage>>;
            return empty;
        }
        return this.m_conversations[index].messages;
    }

    // A predicate rather than a read: redscript arrays are values, so GetMessages copies every
    // message slot, and answering a yes/no that way costs a conversation copy. Asked once per
    // anonymous contact per minute by the mod next door.
    //
    // The conversation is bound before its messages are indexed: it is a reference, so binding
    // it is free, while binding `.messages` would copy the array this exists to avoid.
    public func PlayerHasWritten(contactId: String) -> Bool {
        let index = AiNpcConversationIndex(this.m_conversations, contactId);
        if index < 0 {
            return false;
        }

        let conversation = this.m_conversations[index];
        let i = 0;
        let count = ArraySize(conversation.messages);
        while i < count {
            if conversation.messages[i].fromPlayer {
                return true;
            }
            i += 1;
        }
        return false;
    }

    // Never null: a contact nobody has talked to has an empty memory, not a missing one, so
    // callers render, clamp and merge without a defined-check.
    public func GetMemory(contactId: String) -> ref<AiNpcMemory> {
        let index = AiNpcConversationIndex(this.m_conversations, contactId);
        if index < 0 {
            return AiNpcMemoryNew();
        }
        return this.m_conversations[index].memory;
    }

    // Replaces the whole state: the memory that just absorbed a batch, and the messages that
    // survive it. One operation, because writing the memory and evicting the messages
    // separately leaves a window in which the batch is remembered twice or lost. A snapshot
    // cannot be half-applied.
    //
    // The caller decides what is kept; this is the write, not the policy.
    public func Compact(contactId: String, memory: ref<AiNpcMemory>, kept: array<ref<AiNpcMessage>>) -> Void {
        this.EnsureResolved();
        if AiNpcConversationIndex(this.m_conversations, contactId) < 0 {
            return;
        }
        this.RecordOp(AiNpcJournalOpSnapshotWith(0, contactId, kept, AiNpcMemoryClamp(memory)));
    }

    // One fact into a contact's memory, from outside a compaction: the door for something
    // another mod's systems observed and the conversation has no way of hearing. Compaction
    // only reads the transcript, where a scene was never written.
    //
    // A snapshot, like Compact: the journal is what survives a reload, so a memory written
    // straight into the field is silently erased by the next replay. The memory moves, the
    // transcript does not.
    //
    // Appended last, because eviction takes the oldest non-founding fact and what the game
    // just observed should be the last thing forgotten. Not counted as founding: that prefix
    // is identity, and an episode is not identity however important.
    //
    // False when there is no conversation to attach it to -- a real answer, and the caller is
    // expected to fall back on a channel of its own. Verified by read-back, because
    // AiNpcMemoryClamp may drop the entry as blank, over-long or already held.
    //
    // Idempotent on exact text. Two wordings of one event are two facts, so callers must build
    // the sentence the same way every time.
    public func RecordFact(contactId: String, text: String, nowSeconds: Int32) -> Bool {
        this.EnsureResolved();
        if AiNpcConversationIndex(this.m_conversations, contactId) < 0 {
            return false;
        }

        let memory = AiNpcMemoryCopy(this.GetMemory(contactId));
        ArrayPush(memory.facts, text);

        // The block renders "the most recent of it was <elapsed>", and a fact recorded a
        // minute ago is the most recent thing in it. Left alone, the character speaks of last
        // night as though it were last week.
        if NotEquals(nowSeconds, AiNpcTimeUnknown()) && nowSeconds > memory.coveredUpTo {
            memory.coveredUpTo = nowSeconds;
        }

        this.RecordOp(AiNpcJournalOpSnapshotWith(0, contactId, this.GetMessages(contactId),
            AiNpcMemoryClamp(memory)));

        // Bound to a local before the intrinsic touches it: ArrayContains takes its operand by
        // reference and a return value has no stable slot, so inlined it answers false every
        // time -- and every caller would fall back as though memory were switched off.
        let facts = this.GetMemory(contactId).facts;
        return ArrayContains(facts, AiNpcMemoryClampEntry(text));
    }

    public func Append(contactId: String, text: String, fromPlayer: Bool,
                       opt channel: AiNpcChannelId) -> Void {
        this.EnsureResolved();
        // The clock is read at the one impure edge and travels with the operation, so the
        // replay stamps the message with the time it was written, not the time the save was
        // loaded. AiNpcJournalApply stays pure.
        this.RecordOp(AiNpcJournalOpAppendAt(0, contactId, AiNpcTrimLeadingBlanks(text), fromPlayer,
            AiNpcGetCurrentGameTimeSeconds(), channel));
    }

    // Undo and Clear check the conversation exists first, so a stray call on a contact nobody
    // has talked to costs nothing rather than a no-op entry in the journal.
    public func Undo(contactId: String) -> Void {
        this.EnsureResolved();
        if AiNpcConversationIndex(this.m_conversations, contactId) < 0 {
            return;
        }
        this.RecordOp(AiNpcJournalOpUndo(0, contactId));
    }

    public func Clear(contactId: String) -> Void {
        this.EnsureResolved();
        if AiNpcConversationIndex(this.m_conversations, contactId) < 0 {
            return;
        }
        this.RecordOp(AiNpcJournalOpClear(0, contactId));
    }

    public func HasPendingReply(contactId: String) -> Bool {
        return AiNpcHistoryHasPendingReply(this.GetMessages(contactId));
    }

    // For logs and diagnostics: "b3:147", or "" before the first message of a playthrough.
    public func GetPointer() -> String {
        return AiNpcJournalPointer(this.BranchName(), this.m_seq);
    }

    private func BranchName() -> String {
        if this.m_branchId <= 0 {
            return "";
        }
        return AiNpcBranchId(this.m_branchId);
    }

    /// Resolution ///

    // The last resort: a write that arrived before either lifecycle signal. It passes
    // restoredFromSave = false, which is safe for the pointer and not for adopting the
    // pre-journal history -- nothing here can tell a loaded save from a new game, and guessing
    // wrong hands a new playthrough the previous one's memories.
    //
    // OnRestored resolves a loaded save before any gameplay write reaches the store, so this
    // line in a loaded save means that ordering has broken.
    private func EnsureResolved() -> Void {
        if !this.m_resolved {
            AiNpcLog("Conversation store resolved by a write, ahead of OnRestored and Session/Ready; skipping pre-journal migration.");
            this.Resolve(false);
        }
    }

    private func Resolve(restoredFromSave: Bool) -> Void {
        if this.m_resolved {
            return;
        }

        // settings.json is read once, when the storage service starts, so a key added while
        // the game runs would wait for a relaunch -- and the import setting is added, used and
        // deleted in one sitting. Once per session or load costs a file read nobody notices.
        this.ReloadSettings();

        // A pointer that cannot be read yet is not a pointer that does not exist, and the
        // branch-missing path below zeroes m_branchId, the only reference this savegame has to
        // its history. Deferring costs one retry; latching would throw the history away
        // because the storage service opened a moment later.
        //
        // A pending import defers from the other direction: resolving without the storage
        // would settle this session on its own history and spend the import on nothing.
        if !IsDefined(AiNpcModStorage()) && (this.m_branchId > 0 || this.ImportPending()) {
            return;
        }

        this.m_resolved = true;
        ArrayClear(this.m_conversations);
        this.m_head = 0;

        this.MigrateLegacyFile();

        // Ahead of everything below: an import replaces whatever pointer this save carries.
        if this.ApplyImport() {
            return;
        }

        if this.m_branchId <= 0 {
            if restoredFromSave {
                this.AdoptSeedBranch();
            } else {
                AiNpcLog("New playthrough: conversation history starts empty.");
            }
            return;
        }

        let storage = AiNpcModStorage();
        let fileName = AiNpcBranchFileName(this.BranchName());
        if NotEquals(storage.Exists(fileName), FileSystemStatus.True) {
            // Purged, or the folder was cleaned out. Start empty rather than fall back to
            // whatever else is on disk: branch ids are never reused, so no other file could
            // legitimately hold this save's history. Only reached with the storage open, since
            // zeroing the pointer is not recoverable.
            AiNpcLog(s"Journal branch '\(this.BranchName())' is missing; this playthrough starts from an empty history.");
            this.m_branchId = 0;
            this.m_seq = 0;
            return;
        }

        let ops = AiNpcJournalParseLines(storage.GetFile(fileName).ReadAsLines());
        this.m_head = AiNpcJournalHeadSeq(ops);
        this.m_conversations = AiNpcJournalReplay(ops, this.m_seq, AiNpcMemoryHardMaxTurns());

        AiNpcLog(s"Restored \(ArraySize(this.m_conversations)) conversation(s) at \(this.GetPointer()) (branch head \(this.m_head)).");
        AiNpcSessionLogRecord(storage, this.m_branchId, this.m_seq);
    }

    // A savegame predating the journal has no pointer, so it is offered the history the
    // single-file format left behind. They all adopt the same seed branch and fork apart on
    // their first write, which comes from a pointer no longer at the head. A new game is never
    // offered it.
    private func AdoptSeedBranch() -> Void {
        let index = this.ReadIndex();
        let seed = Cast<Int32>(index.GetKeyInt64("seed"));
        if seed <= 0 {
            return;
        }

        let storage = AiNpcModStorage();
        let fileName = AiNpcBranchFileName(AiNpcBranchId(seed));
        if !IsDefined(storage) || NotEquals(storage.Exists(fileName), FileSystemStatus.True) {
            return;
        }

        let ops = AiNpcJournalParseLines(storage.GetFile(fileName).ReadAsLines());
        this.m_branchId = seed;
        this.m_head = AiNpcJournalHeadSeq(ops);
        this.m_seq = this.m_head;
        this.m_conversations = AiNpcJournalReplay(ops, this.m_seq, AiNpcMemoryHardMaxTurns());
        this.m_readOnlyBranch = true;

        AiNpcLog(s"Save predates the journal: adopted the pre-upgrade history at \(this.GetPointer()); it will fork on the first message.");
    }

    /// Import ///

    // Cheap enough for the deferral guard: it reads a setting and touches no file. A request
    // this savegame has already served is not pending.
    private func ImportPending() -> Bool {
        let request = AiNpcParseJournalPointer(AiNpcImportPointerSetting());
        return request.valid && !this.ImportAlreadyApplied(request);
    }

    // A request with no sequence number means "as far as that branch goes", which cannot be
    // compared against a recorded number, so the branch alone settles it: asking twice for the
    // head of b14 is one import.
    private func ImportAlreadyApplied(request: ref<AiNpcJournalPointerParts>) -> Bool {
        if this.m_importedBranch != request.branchId {
            return false;
        }
        return request.seq <= 0 || this.m_importedSeq == request.seq;
    }

    // The repair hatch: "importConversationsFrom": "b14:467" in settings.json. The pointer
    // lives inside the savegame, so when a later save is lost and play resumes from an earlier
    // one, no file rewrite outside the game can aim it at the history it lost.
    //
    // It replays the requested pointer and immediately forks, which is the whole safety of it:
    // two savegames sharing a branch is the bug this journal prevents, and the read-only flag
    // that holds a shared branch at arm's length is session state that would be gone by the
    // next load. The source file is never written to, so the import can be repeated or aimed
    // elsewhere, and journal.index.json records where the new branch came from.
    //
    // False means carry on as usual: an absent key, a malformed one, a branch that is gone, or
    // a request this save already served.
    private func ApplyImport() -> Bool {
        let raw = AiNpcImportPointerSetting();
        if Equals(StrLen(raw), 0) {
            return false;
        }

        let request = AiNpcParseJournalPointer(raw);
        if !request.valid {
            FTLogError(s"[ai_npc]: importConversationsFrom = '\(raw)' is not a journal pointer; expected something like \"b14:467\". Ignored.");
            return false;
        }
        if this.ImportAlreadyApplied(request) {
            return false;
        }

        // FTLog, not AiNpcLog: a one-shot repair the player asked for by hand must not be
        // invisible because the in-game logging toggle is off.
        let report: String;
        if this.ImportPointer(request, report) {
            FTLog(s"[ai_npc]: \(report)");
            FTLog(s"[ai_npc]: this savegame will not import again -- remove \"importConversationsFrom\" from settings.json now, or every OTHER save you load will import it too.");
            return true;
        }

        FTLogError(s"[ai_npc]: \(report)");
        return false;
    }

    // The import itself, with no opinion about who asked: the settings key at load time, or
    // AiNpcJournalImport from the console. Everything refusable is refused before the first
    // write, so a mistyped pointer costs a message rather than this playthrough's pointer.
    private func ImportPointer(request: ref<AiNpcJournalPointerParts>, out report: String) -> Bool {
        let storage = AiNpcModStorage();
        let branch = AiNpcBranchId(request.branchId);
        let fileName = AiNpcBranchFileName(branch);
        if !IsDefined(storage) || NotEquals(storage.Exists(fileName), FileSystemStatus.True) {
            report = s"\(branch) is not on disk. Nothing imported.";
            return false;
        }

        let ops = AiNpcJournalParseLines(storage.GetFile(fileName).ReadAsLines());
        let seq = request.seq;
        if seq <= 0 {
            seq = AiNpcJournalHeadSeq(ops);
        }

        let imported = AiNpcJournalReplay(ops, seq, AiNpcMemoryHardMaxTurns());
        if Equals(ArraySize(imported), 0) {
            report = s"\(AiNpcJournalPointer(branch, seq)) replays to an empty history. Nothing imported.";
            return false;
        }

        // Fork snapshots what m_conversations holds and names the current pointer as parent, so
        // both are set first.
        this.m_conversations = imported;
        this.m_branchId = request.branchId;
        this.m_seq = seq;
        this.m_head = seq;
        this.Fork();

        this.m_importedBranch = request.branchId;
        this.m_importedSeq = seq;

        report = s"imported \(ArraySize(imported)) conversation(s) from \(AiNpcJournalPointer(branch, seq)) into \(this.GetPointer()).";
        return true;
    }

    /// Debug surface ///
    // Called from the console and from other mods through AiNpcJournalApi.reds. Everything
    // answers with a String: the caller is a person reading a console, and a String is the one
    // return type that survives CET's RTTI bridge unchanged.

    // Mid-session import, the console's counterpart to the settings key. It refuses while the
    // phone is open: the chat UI holds what it drew, so replacing the history underneath would
    // leave the player looking at messages that no longer exist.
    public func ImportFromPointer(pointer: String) -> String {
        let request = AiNpcParseJournalPointer(pointer);
        if !request.valid {
            return s"'\(pointer)' is not a journal pointer; expected something like \"b14:467\".";
        }

        if AiNpcChatIsOnScreen() {
            return "Close the phone first: importing while a conversation is on screen would leave the UI showing messages that no longer exist.";
        }

        this.EnsureResolved();

        let report: String;
        if this.ImportPointer(request, report) {
            FTLog(s"[ai_npc]: \(report)");
            return report;
        }
        return report;
    }

    // What this session is: the pointer it restored, and what that replayed to.
    public func DescribeState() -> String {
        let pointer = this.GetPointer();
        if Equals(StrLen(pointer), 0) {
            pointer = "(nothing written yet)";
        }

        let result = s"ai_npc \(AiNpcVersion()) -- pointer \(pointer), branch head \(this.m_head), \(ArraySize(this.m_conversations)) conversation(s)";
        let i = 0;
        while i < ArraySize(this.m_conversations) {
            let conversation = this.m_conversations[i];
            result += s"\n  \(conversation.contactId): \(ArraySize(conversation.messages)) message(s)";
            if !AiNpcMemoryIsEmpty(conversation.memory) {
                result += s", \(ArraySize(conversation.memory.facts)) remembered fact(s)";
            }
            i += 1;
        }
        return result;
    }

    // Every branch the index knows about, one tab-separated row each:
    //
    //   id \t parent \t head \t lines \t present \t current
    //
    // Reads only what a row shows -- the file's length and its last operation. Replaying every
    // branch to report a conversation count cost several thousand JSON parses before anything
    // could be drawn. What costs a replay is in DescribeBranchDetail, for one branch at a time.
    //
    // Tab-separated because the caller is Lua and the parse is one split. An empty result means
    // nothing to list, never an error.
    public func JournalBranchRows() -> String {
        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            return "";
        }

        let index = this.ReadIndex();
        let branches = index.GetKey("branches") as JsonArray;
        if !IsDefined(branches) {
            return "";
        }

        let result = "";
        let i: Uint32 = 0u;
        while i < branches.GetSize() {
            let entry = branches.GetItem(i) as JsonObject;
            if IsDefined(entry) {
                let id = Cast<Int32>(entry.GetKeyInt64("id"));
                let fileName = AiNpcBranchFileName(AiNpcBranchId(id));
                let present = Equals(storage.Exists(fileName), FileSystemStatus.True);

                let head = 0;
                let lines = 0;
                if present {
                    let content = storage.GetFile(fileName).ReadAsLines();
                    lines = ArraySize(content);
                    head = AiNpcJournalTailSeq(content);
                }

                let parent = entry.GetKeyString("parent");
                if Equals(StrLen(parent), 0) {
                    parent = "-";
                }

                // "1"/"0" rather than the Bools: how redscript renders a Bool into a string is
                // not something this format should depend on, and the reader is a Lua split.
                let presentCell = "0";
                if present {
                    presentCell = "1";
                }
                let currentCell = "0";
                if id == this.m_branchId {
                    currentCell = "1";
                }

                result += s"\(id)\t\(parent)\t\(head)\t\(lines)\t\(presentCell)\t\(currentCell)\n";
            }
            i += 1u;
        }
        return result;
    }

    // One branch, replayed and described: enough to recognise the playthrough by reading rather
    // than by counting. `pointer` may name a sequence number ("b14:96") to describe the branch
    // as it stood at that moment, which is how a point to come back to is found.
    public func DescribeBranchDetail(pointer: String) -> String {
        let request = AiNpcParseJournalPointer(pointer);
        if !request.valid {
            return s"'\(pointer)' is not a journal pointer.";
        }

        let storage = AiNpcModStorage();
        let branch = AiNpcBranchId(request.branchId);
        let fileName = AiNpcBranchFileName(branch);
        if !IsDefined(storage) || NotEquals(storage.Exists(fileName), FileSystemStatus.True) {
            return s"\(branch) is not on disk.";
        }

        let ops = AiNpcJournalParseLines(storage.GetFile(fileName).ReadAsLines());
        let seq = request.seq;
        if seq <= 0 {
            seq = AiNpcJournalHeadSeq(ops);
        }

        let state = AiNpcJournalReplay(ops, seq, AiNpcMemoryHardMaxTurns());
        let total = 0;
        let i = 0;
        while i < ArraySize(state) {
            total += ArraySize(state[i].messages);
            i += 1;
        }

        let result = s"\(AiNpcJournalPointer(branch, seq)) -- \(ArraySize(state)) conversation(s), \(total) message(s)";
        i = 0;
        while i < ArraySize(state) {
            let conversation = state[i];
            result += s"\n  \(conversation.contactId): \(ArraySize(conversation.messages)) message(s)";
            if !AiNpcMemoryIsEmpty(conversation.memory) {
                result += s", \(ArraySize(conversation.memory.facts)) fact(s)";
            }
            // The last thing said identifies a playthrough at a glance, so it is the one
            // message the listing quotes.
            let size = ArraySize(conversation.messages);
            if size > 0 {
                result += s"\n      \(AiNpcClipText(conversation.messages[size - 1].text, 90))";
            }
            i += 1;
        }
        return result;
    }

    // For the console, where a person wants the whole picture in one call.
    public func DescribeBranches() -> String {
        let rows = this.JournalBranchRows();
        if Equals(StrLen(rows), 0) {
            return "No branch to list (storage closed, or nothing registered yet).";
        }

        let result = "";
        let lines = StrSplit(rows, "\n");
        let i = 0;
        while i < ArraySize(lines) {
            if NotEquals(StrLen(lines[i]), 0) {
                let cell = StrSplit(lines[i], "\t");
                if ArraySize(cell) >= 6 {
                    let here = "";
                    if Equals(cell[5], "1") {
                        here = "   <- this savegame";
                    }
                    let state = "";
                    if Equals(cell[4], "0") {
                        state = " (purged)";
                    }
                    result += s"b\(cell[0]): from \(cell[1]), head \(cell[2]), \(cell[3]) line(s)\(state)\(here)\n";
                }
            }
            i += 1;
        }
        return result;
    }

    /// Writing ///

    // The single write path: fork if needed, apply, persist, advance the pointer.
    //
    // The fork snapshots the live state, so it happens before the operation is applied:
    // afterwards, the new message would be in the snapshot and in the operation that follows
    // it, and a replay would show it twice.
    //
    // Applied to memory before the write, not after a successful one: a failed write must not
    // leave the conversation on screen out of step with the one the player is having. It costs
    // the message on the next reload, and the log says so.
    private func RecordOp(op: ref<AiNpcJournalOp>) -> Void {
        if this.NeedsFork() {
            this.Fork();
        }

        this.m_conversations = AiNpcJournalApply(this.m_conversations, op, AiNpcMemoryHardMaxTurns());

        if this.m_branchId <= 0 {
            return;     // no storage: the session works, nothing survives it
        }

        op.seq = this.m_head + 1;
        if this.AppendLine(this.BranchName(), AiNpcJournalOpToLine(op)) {
            this.m_head = op.seq;
            this.m_seq = op.seq;
        } else {
            AiNpcLog(s"Could not write to journal branch \(this.BranchName()); this message will not survive a reload.");
        }
    }

    private func NeedsFork() -> Bool {
        return this.m_branchId <= 0                      // first message of a playthrough
            || this.m_readOnlyBranch                     // shared branch: never extend it
            || NotEquals(this.m_seq, this.m_head)        // reloaded into the past of this branch
            || this.m_head >= this.MAX_BRANCH_ENTRIES;   // long enough to be worth snapshotting
    }

    // Opens a new branch seeded with a snapshot of the live state and points this playthrough
    // at it. Every branch it writes from here on is its own.
    private func Fork() -> Void {
        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            return;
        }

        let parent = this.GetPointer();
        let index = this.ReadIndex();
        let next = Cast<Int32>(index.GetKeyInt64("nextBranch"));
        if next < 1 {
            next = 1;
        }

        let branch = AiNpcBranchId(next);
        let fileName = AiNpcBranchFileName(branch);

        // The counter is written before the file it names, so a crash between the two burns an
        // id rather than handing it out twice.
        index.SetKeyInt64("nextBranch", Cast<Int64>(next + 1));
        this.RegisterBranch(index, next, parent);
        this.WriteIndex(index);

        storage.GetFile(fileName).WriteText(
            AiNpcJournalHeaderLine(this.SCHEMA_VERSION, branch, parent) + "\n",
            FileSystemWriteMode.Truncate);

        let snapshot = AiNpcJournalSnapshotOps(this.m_conversations);
        let i = 0;
        while i < ArraySize(snapshot) {
            this.AppendLine(branch, AiNpcJournalOpToLine(snapshot[i]));
            i += 1;
        }

        this.m_branchId = next;
        this.m_head = ArraySize(snapshot);
        this.m_seq = this.m_head;
        this.m_readOnlyBranch = false;   // this branch belongs to this playthrough alone

        AiNpcSessionLogRecord(storage, this.m_branchId, this.m_seq);

        if Equals(StrLen(parent), 0) {
            // A branch with no parent means the live state was empty when it opened: correct
            // in a new playthrough, and in a loaded save the signature of history lost on the
            // way in. This is the only moment it is still visible -- afterwards the session
            // looks healthy and simply has no past. Through FTLogError, so it does not need
            // the logging toggle.
            if this.m_restoredSession {
                FTLogError(s"[ai_npc]: opened journal branch \(branch) with no parent in a LOADED save: the previous history was not restored. Please report this with journal.index.json.");
            } else {
                AiNpcLog(s"Opened journal branch \(branch).");
            }
        } else {
            AiNpcLog(s"Forked journal branch \(branch) from \(parent).");
        }

        this.PurgeOldBranches();
    }

    private func AppendLine(branch: String, line: String) -> Bool {
        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            return false;
        }
        return storage.GetFile(AiNpcBranchFileName(branch)).WriteText(line + "\n", FileSystemWriteMode.Append);
    }

    /// Branch index ///

    // Always an object, empty when the file is absent or unreadable. An unreadable index costs
    // branch history, not correctness: nextBranch restarts, which is why RegisterBranch lifts
    // it above every id it can still see on disk.
    private func ReadIndex() -> ref<JsonObject> {
        let storage = AiNpcModStorage();
        if IsDefined(storage) && Equals(storage.Exists(this.INDEX_FILE), FileSystemStatus.True) {
            let raw = storage.GetFile(this.INDEX_FILE).ReadAsJson();
            if IsDefined(raw) && !raw.IsUndefined() && raw.IsObject() {
                return raw as JsonObject;
            }
        }

        let fresh = ParseJson("{}") as JsonObject;
        fresh.SetKeyInt64("version", this.SCHEMA_VERSION);
        fresh.SetKeyInt64("nextBranch", 1l);
        fresh.SetKeyInt64("seed", 0l);
        fresh.SetKey("branches", ParseJson("[]"));
        return fresh;
    }

    private func WriteIndex(index: ref<JsonObject>) -> Void {
        let storage = AiNpcModStorage();
        if IsDefined(storage) {
            index.SetKeyInt64("version", this.SCHEMA_VERSION);
            storage.GetFile(this.INDEX_FILE).WriteJson(index, "    ");
        }
    }

    private func RegisterBranch(index: ref<JsonObject>, branchId: Int32, parent: String) -> Void {
        let branches = index.GetKey("branches") as JsonArray;
        if !IsDefined(branches) {
            branches = ParseJson("[]") as JsonArray;
            index.SetKey("branches", branches);
        }

        let entry = ParseJson("{}") as JsonObject;
        entry.SetKeyInt64("id", Cast<Int64>(branchId));
        entry.SetKeyString("parent", parent);
        branches.AddItem(entry);
    }

    // Keeps the newest MAX_BRANCHES plus the seed. Order is creation order, which is the order
    // the array holds: the journal has no clock, and the game gives scripts no wall time worth
    // persisting.
    private func PurgeOldBranches() -> Void {
        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            return;
        }

        let index = this.ReadIndex();
        let branches = index.GetKey("branches") as JsonArray;
        if !IsDefined(branches) {
            return;
        }

        let seed = Cast<Int32>(index.GetKeyInt64("seed"));
        let total = Cast<Int32>(branches.GetSize());
        if total <= this.MAX_BRANCHES {
            return;
        }

        let kept = ParseJson("[]") as JsonArray;
        let removed = 0;
        let i: Uint32 = 0u;
        while i < branches.GetSize() {
            let entry = branches.GetItem(i) as JsonObject;
            if IsDefined(entry) {
                let id = Cast<Int32>(entry.GetKeyInt64("id"));
                let isOldest = Cast<Int32>(i) < (total - this.MAX_BRANCHES);
                if isOldest && NotEquals(id, seed) && NotEquals(id, this.m_branchId) {
                    storage.DeleteFile(AiNpcBranchFileName(AiNpcBranchId(id)));
                    removed += 1;
                } else {
                    kept.AddItem(entry);
                }
            }
            i += 1u;
        }

        if removed > 0 {
            index.SetKey("branches", kept);
            this.WriteIndex(index);
            AiNpcLog(s"Purged \(removed) old journal branch(es); saves pointing at them will load an empty history.");
        }
    }

    /// Migration ///

    // Converts the pre-journal conversations.json into the seed branch, once. Both older
    // formats are read: schema v2, a JSON array per contact, and the original "|"-joined
    // strings.
    private func MigrateLegacyFile() -> Void {
        let storage = AiNpcModStorage();
        if !IsDefined(storage) || NotEquals(storage.Exists(this.LEGACY_FILE), FileSystemStatus.True) {
            return;
        }

        let raw = storage.GetFile(this.LEGACY_FILE).ReadAsJson();
        if !IsDefined(raw) || raw.IsUndefined() || !raw.IsObject() {
            AiNpcLog(s"\(this.LEGACY_FILE) is unreadable; leaving it alone and starting from an empty journal.");
            return;
        }

        let root = raw as JsonObject;
        let conversations: array<ref<AiNpcConversation>>;
        if root.HasKey("version") {
            conversations = this.ReadV2(root);
        } else {
            conversations = this.ReadV1(root);
            storage.GetFile(this.LEGACY_BACKUP).WriteJson(root, "    ");
        }

        let index = this.ReadIndex();
        let next = Cast<Int32>(index.GetKeyInt64("nextBranch"));
        if next < 1 {
            next = 1;
        }
        let seed = AiNpcBranchId(next);

        index.SetKeyInt64("nextBranch", Cast<Int64>(next + 1));
        index.SetKeyInt64("seed", Cast<Int64>(next));
        this.RegisterBranch(index, next, "");
        this.WriteIndex(index);

        storage.GetFile(AiNpcBranchFileName(seed)).WriteText(
            AiNpcJournalHeaderLine(this.SCHEMA_VERSION, seed, "") + "\n",
            FileSystemWriteMode.Truncate);

        let snapshot = AiNpcJournalSnapshotOps(conversations);
        let i = 0;
        while i < ArraySize(snapshot) {
            this.AppendLine(seed, AiNpcJournalOpToLine(snapshot[i]));
            i += 1;
        }

        // Backed up rather than left in place: leaving it would migrate again every session,
        // opening another seed branch each time.
        storage.GetFile(this.MIGRATED_BACKUP).WriteJson(root, "    ");
        storage.DeleteFile(this.LEGACY_FILE);

        AiNpcLog(s"Migrated \(ArraySize(snapshot)) conversation(s) from \(this.LEGACY_FILE) into seed branch \(seed) (backup: \(this.MIGRATED_BACKUP)).");
    }

    private func ReadV2(root: ref<JsonObject>) -> array<ref<AiNpcConversation>> {
        let result: array<ref<AiNpcConversation>>;
        let conversations = root.GetKey("conversations") as JsonObject;
        if !IsDefined(conversations) {
            return result;
        }

        let contactIds = conversations.GetKeys();
        let i = 0;
        while i < ArraySize(contactIds) {
            let entry = conversations.GetKey(contactIds[i]) as JsonArray;
            if IsDefined(entry) {
                let conversation = new AiNpcConversation();
                conversation.contactId = contactIds[i];
                conversation.memory = AiNpcMemoryNew();
                conversation.messages = AiNpcHistoryTrim(AiNpcMessagesFromJson(entry), AiNpcMemoryHardMaxTurns());
                ArrayPush(result, conversation);
            }
            i += 1;
        }
        return result;
    }

    // The original { "judy": { "vMessages": "a|b|", "npcResponses": "x|y|" } } layout.
    private func ReadV1(root: ref<JsonObject>) -> array<ref<AiNpcConversation>> {
        let result: array<ref<AiNpcConversation>>;
        let contactIds = root.GetKeys();
        let i = 0;
        while i < ArraySize(contactIds) {
            let entry = root.GetKey(contactIds[i]) as JsonObject;
            if IsDefined(entry) {
                let conversation = new AiNpcConversation();
                conversation.contactId = contactIds[i];
                conversation.memory = AiNpcMemoryNew();
                conversation.messages = AiNpcHistoryTrim(
                    AiNpcHistoryFromLegacy(entry.GetKeyString("vMessages"), entry.GetKeyString("npcResponses")),
                    AiNpcMemoryHardMaxTurns());
                ArrayPush(result, conversation);
            }
            i += 1;
        }
        return result;
    }

    /// Helpers ///

    private func ReloadSettings() -> Void {
        let service = AiNpcStorageService.GetPersistentStorageSystem();
        if IsDefined(service) {
            service.ReloadSettings();
        }
    }

}
