// The choices a contact's thread offers, read from its provider, and the one place a pick is
// handed back. Both written surfaces go through here, so a choice cannot mean one thing on the
// phone and another on the terminal.
//
// Each question has a pure half that takes the provider, and a thin one that fetches it: the
// start-up tests run before the registry exists.

module AiNpc

func AiNpcThreadChoiceLimit() -> Int32 {
    return 9;
}

func AiNpcThreadChoicesFor(contactId: String) -> array<ref<AiNpcThreadChoice>> {
    return AiNpcThreadChoicesOf(AiNpcProviderFor(contactId), contactId);
}

func AiNpcThreadChoicesOf(provider: ref<AiNpcContactProvider>, contactId: String) -> array<ref<AiNpcThreadChoice>> {
    let shown: array<ref<AiNpcThreadChoice>>;
    if !IsDefined(provider) {
        return shown;
    }
    let declared = provider.GetThreadChoices();
    let count = ArraySize(declared);
    let i = 0;
    while i < count {
        if !IsDefined(declared[i]) || Equals(StrLen(declared[i].id), 0) {
            AiNpcLog(s"'\(contactId)' declares a thread choice with no id at position \(i); not shown.");
        } else {
            if ArraySize(shown) < AiNpcThreadChoiceLimit() {
                ArrayPush(shown, declared[i]);
            } else {
                AiNpcLog(s"'\(contactId)' declares more than \(AiNpcThreadChoiceLimit()) thread choices; '\(declared[i].id)' is not shown.");
            }
        }
        i += 1;
    }
    return shown;
}

// True when a choice was handed to the provider.
func AiNpcThreadChoose(contactId: String, index: Int32) -> Bool {
    return AiNpcThreadChooseOn(AiNpcProviderFor(contactId), contactId, index);
}

func AiNpcThreadChooseOn(provider: ref<AiNpcContactProvider>, contactId: String, index: Int32) -> Bool {
    let choices = AiNpcThreadChoicesOf(provider, contactId);
    if index < 0 || index >= ArraySize(choices) {
        return false;
    }
    AiNpcLog(s"Thread choice '\(choices[index].id)' picked on '\(contactId)'.");
    provider.OnThreadChoice(choices[index].id);
    return true;
}

// The position of the choice a key picks, or -1 for a key that picks none.
func AiNpcThreadChoiceKeyIndex(key: String) -> Int32 {
    let keys = ["IK_1", "IK_2", "IK_3", "IK_4", "IK_5", "IK_6", "IK_7", "IK_8", "IK_9"];
    let count = ArraySize(keys);
    let i = 0;
    while i < count {
        if Equals(keys[i], key) {
            return i;
        }
        i += 1;
    }
    return -1;
}
