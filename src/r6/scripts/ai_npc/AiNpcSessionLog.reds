module AiNpc

import RedFileSystem.*
import RedData.Json.*

// Which playthrough sits on which journal branch -- the one fact the savegame keeps to itself.
//
// The branch pointer is a persistent field of AiNpcConversationStore, so it lives inside
// sav.dat and no offline tool can read it. Everything else about a save is in plain sight
// (metadata.9.json), which leaves a tool guessing which save wrote which branch. This file
// removes the guess: every resolution and every fork records its pointer here, keyed by the
// engine's playthrough time -- the same value the save metadata carries as "playthroughTime".
//
// Written for ai_npc_lab\journal\journal_viewer.py and never read back by the mod. Losing it costs a
// diagnostic, never a conversation.
//
// Files in <game>\r6\storages\AiNpc\ :
//   journal.sessions.json   [{b, n, pt, lp}, ...], oldest first

func AiNpcSessionLogRecord(storage: ref<FileSystemStorage>, branchId: Int32, seq: Int32) -> Void {
    if !IsDefined(storage) || branchId <= 0 {
        return;
    }

    let root = ParseJson("{}") as JsonObject;
    let sessions = ParseJson("[]") as JsonArray;

    let kept = AiNpcSessionLogKeep(storage, branchId);
    let i = 0;
    while i < ArraySize(kept) {
        sessions.AddItem(kept[i]);
        i += 1;
    }
    sessions.AddItem(AiNpcSessionLogEntry(branchId, seq));

    root.SetKey("sessions", sessions);
    storage.GetFile(AiNpcSessionLogFile()).WriteJson(root, "    ");
}

func AiNpcSessionLogFile() -> String {
    return "journal.sessions.json";
}

// The playthrough is identified by its branch, so a session that appends to one it already
// recorded replaces that entry instead of adding a second. A run that forks often would
// otherwise push every older playthrough out of the file within an evening.
func AiNpcSessionLogKeep(storage: ref<FileSystemStorage>, branchId: Int32) -> array<ref<JsonObject>> {
    let kept: array<ref<JsonObject>>;

    let raw = storage.GetFile(AiNpcSessionLogFile()).ReadAsJson();
    if IsDefined(raw) && !raw.IsUndefined() && raw.IsObject() {
        let existing = (raw as JsonObject).GetKey("sessions") as JsonArray;
        if IsDefined(existing) {
            let i: Uint32 = 0u;
            while i < existing.GetSize() {
                let entry = existing.GetItem(i) as JsonObject;
                if IsDefined(entry) && NotEquals(Cast<Int32>(entry.GetKeyInt64("b")), branchId) {
                    ArrayPush(kept, entry);
                }
                i += 1u;
            }
        }
    }

    while ArraySize(kept) >= AiNpcSessionLogMaxEntries() {
        ArrayErase(kept, 0);
    }
    return kept;
}

func AiNpcSessionLogMaxEntries() -> Int32 {
    return 40;
}

func AiNpcSessionLogEntry(branchId: Int32, seq: Int32) -> ref<JsonObject> {
    let entry = ParseJson("{}") as JsonObject;
    entry.SetKeyInt64("b", Cast<Int64>(branchId));
    entry.SetKeyInt64("n", Cast<Int64>(seq));
    entry.SetKeyInt64("pt", Cast<Int64>(AiNpcPlaythroughSeconds()));
    entry.SetKeyString("lp", AiNpcResolveLifePath());
    return entry;
}

// Seconds of playthrough, the engine's own count -- it survives save and load, where
// GetSimTime restarts. The same number the save metadata writes.
func AiNpcPlaythroughSeconds() -> Float {
    return EngineTime.ToFloat(GameInstance.GetPlaythroughTime(GetGameInstance()));
}
