// One question, asked by everything that has to be dated: is this quest fact posed.
//
// The answer belongs to the save, and the code that selects on it must stay testable without
// one -- so the read is behind an object rather than called directly. The game answers through
// the quests system; a test answers from a list, and the same selection runs in both.
module AiNpc

func AiNpcFactIsSet(factName: String) -> Bool {
    if Equals(StrLen(factName), 0) {
        return false;
    }

    let fact = StringToName(factName);
    if !IsNameValid(fact) {
        return false;
    }

    let questsSystem = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(questsSystem) {
        return false;
    }
    return questsSystem.GetFact(fact) > 0;
}

abstract class AiNpcFactGate extends IScriptable {
    public func IsSet(fact: String) -> Bool {
        return false;
    }
}

class AiNpcSaveFactGate extends AiNpcFactGate {
    public func IsSet(fact: String) -> Bool {
        return AiNpcFactIsSet(fact);
    }
}

func AiNpcSaveFacts() -> ref<AiNpcFactGate> {
    return new AiNpcSaveFactGate();
}
