module AiNpc

// The journal's public surface: four functions, all String in and String out.
//
// The answer is always a String that is already a sentence, failures included -- they say
// what was refused and why rather than returning a bare false the caller has to interpret.
//
// CET does not reach these. A scripted global in a module is not exposed as a Lua global --
// `AiNpcJournalStatus()` in the console is a nil value -- so from Lua the way in is the store
// itself, by its module-qualified name:
//
//   local store = Game.GetScriptableSystemsContainer():Get("AiNpc.AiNpcConversationStore")
//   print(store:DescribeBranches())
//   print(store:ImportFromPointer("b14:467"))
//
// That is what the ai_npc_debug CET window wraps. These functions exist for the other caller:
// a mod, in redscript, with ai_npc optional:
//
//   @if(ModuleExists("AiNpc"))
//   public func MyModImportHistory(pointer: String) -> String {
//       return AiNpc.AiNpcJournalImport(pointer);
//   }
//
// Every one of them is safe to call at any moment: with no session loaded the store does not
// exist, and each says so instead of failing.

// The store, or null before a session exists. Not exported: a caller holding the store
// itself is a caller that can reach past this surface into the store's private business.
func AiNpcJournalStore() -> ref<AiNpcConversationStore> {
    return AiNpcConversationStore.Get();
}

func AiNpcJournalNoSession() -> String {
    return "No session: load a savegame first (the conversation store is per-playthrough).";
}

// What this session restored, and what each contact holds. The first thing to read when a
// character seems to have forgotten a conversation.
public func AiNpcJournalStatus() -> String {
    let store = AiNpcJournalStore();
    if !IsDefined(store) {
        return AiNpcJournalNoSession();
    }
    return store.DescribeState();
}

// Every branch on disk, replayed to its head. This is where an import pointer comes from:
// the branch whose conversation count matches the playthrough you lost.
public func AiNpcJournalBranches() -> String {
    let store = AiNpcJournalStore();
    if !IsDefined(store) {
        return AiNpcJournalNoSession();
    }
    return store.DescribeBranches();
}

// One branch, replayed and described: per-contact counts and the last thing said in each.
// The pointer may carry a sequence number ("b14:96") to describe that branch as it stood at
// that moment. This is the expensive call, and the reason the branch list is not: it happens
// to one branch, when somebody points at it.
public func AiNpcJournalDetail(pointer: String) -> String {
    let store = AiNpcJournalStore();
    if !IsDefined(store) {
        return AiNpcJournalNoSession();
    }
    return store.DescribeBranchDetail(pointer);
}

// The pointer this savegame is on, as "b14:467" -- or "" before its first message.
public func AiNpcJournalPointerNow() -> String {
    let store = AiNpcJournalStore();
    if !IsDefined(store) {
        return "";
    }
    return store.GetPointer();
}

// Adopts the history at `pointer` ("b14:467", or "b14" for as far as that branch goes) and
// forks into a branch of this savegame's own. The source file is never written to, so a
// mistaken import is undone by importing something else, or by loading an older save.
//
// The same repair is available without the console as the importConversationsFrom setting;
// this is the version for when you would rather see the branch list first.
public func AiNpcJournalImport(pointer: String) -> String {
    let store = AiNpcJournalStore();
    if !IsDefined(store) {
        return AiNpcJournalNoSession();
    }
    return store.ImportFromPointer(pointer);
}
