// Where the waiting context lives, and the only thing that outlives a session's worth of it.
//
// It used to live on AiNpcHttpSystem, and the shape of that mistake is worth keeping: what a
// mod has told a character is not a fact about a request in flight. Hosting it there made
// three callers with no business in the speaking lane reach for GetAiNpcHttpSystem() -- seeding
// a line, forgetting a withdrawn mod's lines, reading a budget -- and an ambient reach for a
// system that holds a generation is how a lane came to paint a widget. The store moved; the
// lane kept the one call that is genuinely its own, at the moment it builds a prompt.
//
// A ScriptableSystem, which is the lifetime this state already had and must keep: a line
// waiting for a character is waiting inside one playthrough, and a service would carry it
// across a save load into a session where the quest that seeded it never happened.
//
// The model is pure and lives in AiNpcPendingContext.reds. This file is the host and the
// voice: the model decides what was clamped and dropped, and cannot say so.

module AiNpc

public class AiNpcPendingContextSystem extends ScriptableSystem {

    private let m_pending: ref<AiNpcPendingContext>;

    private func OnAttach() -> Void {
        this.m_pending = new AiNpcPendingContext();
    }

    public static func Get() -> ref<AiNpcPendingContextSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcPendingContextSystem>()) as AiNpcPendingContextSystem;
    }

    public func Set(contactId: String, text: String, sourceId: String) -> Bool {
        return this.m_pending.Set(contactId, text, sourceId);
    }

    public func BudgetLeft(contactId: String, sourceId: String) -> Int32 {
        return this.m_pending.BudgetLeft(contactId, sourceId);
    }

    public func ForgetSource(sourceId: String) -> Int32 {
        return this.m_pending.ForgetSource(sourceId);
    }

    public func TakeReport(contactId: String) -> ref<AiNpcPendingTake> {
        return this.m_pending.TakeReport(contactId);
    }
}

/// The named questions ///

// The single write point. sourceId is required, not `opt`: it stops a second mod seeding for
// the same contact from erasing the first, and as an `opt` it was omitted at three sites in one
// day, because ai_npc's own voice ("") and a forgotten argument looked identical.
func AiNpcSetPendingContext(contactId: String, text: String, sourceId: String) -> Bool {
    let system = AiNpcPendingContextSystem.Get();
    if !IsDefined(system) {
        return false;
    }
    if !system.Set(contactId, text, sourceId) {
        AiNpcLog("Refused pending context with no contact id.");
        return false;
    }
    return true;
}

// How much this source may still add before the clamp bites, in characters. Zero outside a
// session, which is the honest answer: there is nothing to add to.
public func AiNpcPendingContextBudgetLeft(contactId: String, sourceId: String) -> Int32 {
    let system = AiNpcPendingContextSystem.Get();
    if !IsDefined(system) {
        return 0;
    }
    return system.BudgetLeft(contactId, sourceId);
}

// Everything one mod left waiting, for every contact. Answers how many lines were dropped, so
// a withdrawal that silently removed nothing is distinguishable from one that removed six.
func AiNpcForgetPendingContextFrom(sourceId: String) -> Int32 {
    let system = AiNpcPendingContextSystem.Get();
    if !IsDefined(system) {
        return 0;
    }
    return system.ForgetSource(sourceId);
}

// Consumes one contact's waiting context and reports what the budget cost. The model that owns
// the merge rules is pure and may not log, so it decides what was clamped and this says so: a
// budget that bites silently is indistinguishable from a mod that does not work.
func AiNpcTakePendingContext(contactId: String) -> String {
    let system = AiNpcPendingContextSystem.Get();
    if !IsDefined(system) {
        return "";
    }

    let taken = system.TakeReport(contactId);
    let i = 0;
    while i < ArraySize(taken.clampedIds) {
        AiNpcLog(s"Context from '\(taken.clampedIds[i])' clamped to \(AiNpcNowLineBudget()) chars for '\(contactId)'.");
        i += 1;
    }

    let j = 0;
    while j < ArraySize(taken.droppedIds) {
        AiNpcLog(s"Context from '\(taken.droppedIds[j])' dropped for '\(contactId)': the shared <now> budget is spent.");
        j += 1;
    }
    return taken.text;
}
