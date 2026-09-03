// <character>: who this character is, and how they talk.
//
// Three parts from three sources, and each one is somebody else's answer: the sheet says who,
// another installed mod may append to it, and the register comes from whichever of the three
// speech lanes answered. This file only decides which of them the recipe asked for and in what
// order they are written.
//
// THE REGISTER LIVES HERE, and it used to be the SPEECH rubric of <system_rules>. That block
// describes the chat -- write in the first person, no emoji, how long a message is -- and a
// character's register is not a property of the chat. Moving it makes "the character without
// how they talk" a part list on one block instead of an agreement between two. The rubric key
// is refused where it used to be taken, with a line that names this lane; see AiNpcRules.reds.
//
// The SPEECH label is kept. It is what the rule block wrote for years, it reads as a field
// rather than as a second paragraph of biography, and a model that has seen the one has seen
// the other.

module AiNpc

func AiNpcRenderCharacter(contactId: String, recipe: ref<AiNpcRecipe>, spoken: Bool) -> String {
    if !AiNpcRecipeHas(recipe, "character") {
        return "";
    }

    let body = "";
    if AiNpcRecipeWants(recipe, "character", "bio") {
        body = AiNpcGetCharacterBio(contactId);
    }
    if AiNpcRecipeWants(recipe, "character", "additions") {
        body = AiNpcJoinLines(body, AiNpcCharacterAdditionsText(contactId));
    }
    if AiNpcRecipeWants(recipe, "character", "speech") {
        body = AiNpcJoinLines(body, AiNpcCharacterSpeechLine(contactId, spoken));
    }

    return AiNpcSection("character", body);
}

// "" when the character states no register, so a recipe asking for the part does not produce a
// bare label. The style itself is resolved by AiNpcGetSpeechStyle, which is the only half that
// knows the three levels it comes from.
func AiNpcCharacterSpeechLine(contactId: String, spoken: Bool) -> String {
    let style = spoken ? AiNpcGetSpokenStyle(contactId) : AiNpcGetSpeechStyle(contactId);
    if Equals(StrLen(style), 0) {
        return "";
    }
    return AiNpcCharacterSpeechKey() + ": " + style;
}

// The label, written once. AiNpcRules.reds names it too -- to refuse it -- and the two must be
// the same word or the refusal would be about a rubric nobody writes.
func AiNpcCharacterSpeechKey() -> String {
    return "SPEECH";
}
