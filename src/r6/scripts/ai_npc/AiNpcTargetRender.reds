// <target>: who the character is writing to.
//
// It was <player>, and the rename is the whole of what this file adds. The block answers "who
// is on the other end", the answer is V in every conversation this version can hold, and the
// recipe names it with a source rather than the mod assuming it. A conversation between two
// characters is then a source this file grows, not a block somebody has to invent.
//
// What that day still needs, and what is deliberately NOT pretended here: the transcript
// writes "V: " for the other end and the stop sequences rely on it, and the gendered template
// variables resolve against the player. Both stay as they are. A source that named an NPC
// today would produce a prompt describing one person and a transcript quoting another.
//
// Omitted whole rather than emitted empty, which is the rule every section follows: a contact
// that has never met V says nothing about V, and <target></target> reads as a person with no
// attributes -- an invitation to invent some.

module AiNpc

// The sources a recipe may name. Read by the parser, so an unknown source is refused when the
// file is read rather than discovered as a missing block ten minutes into a conversation.
func AiNpcTargetSources() -> array<String> {
    return ["player"];
}

func AiNpcTargetDefaultSource() -> String {
    return "player";
}

func AiNpcRenderTarget(contactId: String, recipe: ref<AiNpcRecipe>) -> String {
    if !AiNpcRecipeHas(recipe, "target") {
        return "";
    }

    let source = AiNpcRecipeSourceOf(recipe, "target");
    if Equals(StrLen(source), 0) {
        source = AiNpcTargetDefaultSource();
    }
    // One source, so one branch. The parser has already refused anything else by name, and a
    // fallback here would be a second place deciding what an unknown word means.
    if Equals(source, "player") {
        return AiNpcSection("target", AiNpcGetPlayerSection(contactId));
    }
    return "";
}
