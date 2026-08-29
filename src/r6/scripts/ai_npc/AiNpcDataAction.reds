// What a character sheet may DO, and the only effect a sheet is allowed to have.
//
// DATA CARRIES THE TEXT, NEVER THE PREDICATE: a JSON file may say what a character thinks,
// never ask the game a question this mod did not agree to answer. An action is the same rule
// pointed the other way -- data may say what a character announces, never decide what the
// game does about it. So there is one effect, it is named here, and widening the list is a
// decision taken in this file rather than something a file under r6\storages\ can do to
// itself.
//
// The effect is a quest fact, the one channel every side already speaks: AiNpcFactBridge.reds
// turns another mod's fact into something a character reacts to, and this is the return path.
//
// A tag is a request FROM A LANGUAGE MODEL, and a model can be argued into emitting anything.
// A file that could name any fact would let a player who talks a character into one bracket
// write `q101_started`. So a sheet may only write inside `ainpc_`, checked at load AND at
// apply. Wanting to move real quest state means wanting to run code when it moves, which is a
// script provider -- and a script provider has always been able to do anything.
//
// Nothing announces the change from here: the tag rides inside the character's own message,
// and the sentence around it IS the announcement, in that character's voice.
//
// A sheet declares its commands on the same lane a mod does, scoped to the one character that
// declared them. There is no second dispatcher for data.
module AiNpc

/// The declaration ///

// One command a character may emit, and the fact it sets when it does.
//
// `prompt` is the sentence that teaches the model WHEN to emit it, and it is not optional in
// practice: a tag announced with no trigger is a command the model fires at random or never.
public class AiNpcActionDef {
    public let tag: String;
    public let prompt: String;
    public let fact: String;

    // What the slots of `tag` mean. Rendered once under the commands rather than inside each
    // one: two commands of the same mod share a slot, and a sentence that re-teaches it puts a
    // kilobyte between the instruction and the tag it is about.
    public let parameters: array<ref<AiNpcActionParam>>;

    // What the fact is set to. One is what a flag means; a sheet that wants a counter value
    // assigns its own after the constructor.
    public let value: Int32 = 1;
}

// Free constructor, as AiNpcQuest has: a sheet in cast\ is read as data, and every line of
// ceremony there is a line of noise.
func AiNpcAction(tag: String, prompt: String, fact: String,
                        opt parameters: array<ref<AiNpcActionParam>>) -> ref<AiNpcActionDef> {
    let action = new AiNpcActionDef();
    action.tag = tag;
    action.prompt = prompt;
    action.fact = fact;
    action.value = 1;
    action.parameters = parameters;
    return action;
}

/// The rule a declaration has to satisfy ///

// The namespace a sheet may write in. Stated once, read by the loader and by the apply.
func AiNpcActionFactNamespace() -> String {
    return "ainpc_";
}

// The whole of what stops a bracket from reaching vanilla quest state.
func AiNpcActionFactIsWritable(fact: String) -> Bool {
    return StrBeginsWith(fact, AiNpcActionFactNamespace())
        && StrLen(fact) > StrLen(AiNpcActionFactNamespace())
        && !StrContains(fact, " ");
}

// The tags a sheet declares, for the loader's duplicate check.
func AiNpcActionsTags(actions: array<ref<AiNpcActionDef>>) -> array<String> {
    let tags: array<String>;
    let i = 0;
    let count = ArraySize(actions);
    while i < count {
        ArrayPush(tags, actions[i].tag);
        i += 1;
    }
    return tags;
}

/// Applying ///

// Sets the fact, or refuses.
//
// The namespace is checked HERE and not only at load, because this is the line that writes:
// the loader rejects a bad declaration where a player can still fix it, and this makes the
// rule true of a sheet compiled into the mod as well.
//
// Idempotent by construction, which matters: a model repeats itself, and a resend after a
// network error replays the whole reply.
func AiNpcApplyDataAction(action: ref<AiNpcActionDef>) -> Bool {
    if !IsDefined(action) || !AiNpcActionFactIsWritable(action.fact) {
        return false;
    }

    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }

    quests.SetFact(StringToName(action.fact), action.value);
    AiNpcLog(s"Action \(action.tag) applied: \(action.fact) = \(action.value).");
    return true;
}

// One declaration, on the lane every command uses.
//
// It re-checks nothing about the world and has nothing to re-check: the only effect a
// declaration can have is writing a fact inside `ainpc_`, which is idempotent and true
// whatever the game state. A precondition is a predicate, data does not carry predicates, and
// a sheet that needs one needs a script provider.
public class AiNpcDataActionHandler extends AiNpcActionHandler {
    private let m_action: ref<AiNpcActionDef>;

    public static func Create(action: ref<AiNpcActionDef>) -> ref<AiNpcDataActionHandler> {
        let handler = new AiNpcDataActionHandler();
        handler.m_action = action;
        return handler;
    }

    public func OnAction(ctx: ref<AiNpcContactContext>, params: array<String>) -> ref<AiNpcActionResult> {
        if AiNpcApplyDataAction(this.m_action) {
            return AiNpcActionDone();
        }
        return AiNpcActionRefused();
    }
}

/// Registration ///

// Who a sheet's commands are registered as. The contact is part of the id because the
// declaring author is the SHEET, not the mod: two characters declaring [ACTION:BOOK] are two
// commands, and an id of "ai_npc:BOOK" would have made the second replace the first.
func AiNpcSheetModId(contactId: String) -> String {
    return "cast:" + contactId;
}

// Every command a sheet declares, plus every command it refuses.
//
// Scoped to this character alone. A sheet cannot grant a command to anybody else -- that is a
// statement about somebody else's character, and data does not get to make one.
func AiNpcRegisterSheetActions(def: ref<AiNpcCharacterDef>) -> Void {
    let registry = AiNpcGetActionRegistry();
    if !IsDefined(registry) || !IsDefined(def) {
        return;
    }

    let modId = AiNpcSheetModId(def.contactId);
    // Cleared first, because a character file is applied OVER a shipped sheet: a command the
    // file dropped would otherwise survive from the sheet that was replaced, advertised and
    // firing while the file that is supposed to define this character says nothing about it.
    registry.UnregisterAllFor(modId);
    let scope = AiNpcContactTagFor(def.contactId);

    let actions = def.actions;
    let i = 0;
    let count = ArraySize(actions);
    while i < count {
        registry.RegisterAction(modId, actions[i].tag, actions[i].prompt,
                                AiNpcDataActionHandler.Create(actions[i]), scope,
                                actions[i].parameters);
        i += 1;
    }

    // The declarative half of the veto, and the reason it exists: a character declared by a
    // JSON file has no code, and that is the commonest way a third party adds a character.
    // Without this, most of the world's characters could not refuse a command granted to
    // everyone -- and a refusal nobody can express is a permission.
    let refused = def.suppressActions;
    let j = 0;
    let refusedCount = ArraySize(refused);
    while j < refusedCount {
        registry.SuppressAction(modId, refused[j], scope);
        j += 1;
    }
}
