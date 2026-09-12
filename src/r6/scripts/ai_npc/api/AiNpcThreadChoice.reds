// Something the player can do in a contact's thread besides writing to them.
//
// Declared by the mod that owns the contact (AiNpcContactProvider.GetThreadChoices) and handed
// back to it (OnThreadChoice). ai_npc shows the label and reports the pick; what a choice does
// -- block a number, report a scam -- belongs to the owning mod, never to ai_npc.

module AiNpc

public class AiNpcThreadChoice {
    // What OnThreadChoice receives. Stable across sessions.
    public let id: String;
    // What the player reads, already in their language.
    public let label: String;
}

public func AiNpcThreadChoiceOf(id: String, label: String) -> ref<AiNpcThreadChoice> {
    let choice = new AiNpcThreadChoice();
    choice.id = id;
    choice.label = label;
    return choice;
}
