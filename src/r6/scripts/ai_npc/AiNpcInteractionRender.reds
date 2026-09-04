// <interactions>: what a character may do to reach V, and what it writes when there is
// nothing to do.
//
// ONE BLOCK, THREE WORDINGS, and the recipe picks. The conduct rubric is the only text in the
// prompt whose right words depend on which request is being built: a conversation that carries
// the command vocabulary, a conversation whose commands were moved to a second call, and that
// second call itself, which answers in one line and needs a word for "nothing happened".
// Nothing here asks a setting which of the three it is -- see AiNpcInteractionSources.
//
// REACH is the rubric that asks for an output, so it is the one that has to name the block it
// points at and the answer it wants when no command applies. REAL and PROMISES describe what
// is true, not what to write, which is why a command call renders neither.
module AiNpc

// The sources a recipe may name. Read by the parser, so an unknown source is refused when the
// file is read rather than discovered as a missing rubric mid-conversation.
func AiNpcInteractionSources() -> array<String> {
    return ["conversation", "dedicated", "commands"];
}

func AiNpcInteractionDefaultSource() -> String {
    return "conversation";
}

/// The three wordings ///

// The conversation that carries <actions>: the vocabulary is in the same prompt, and the
// character writes a command inside its reply or writes none.
func AiNpcReachConversation() -> String {
    return "You reach V only by text message, and the commands in <actions> are the only way you can act on the world. Use them when the context calls for it, exactly as written, only when it is necessary; skip actions otherwise.";
}

// The conversation whose commands were moved to a second call. It carries no vocabulary, so
// it asks for none: naming a block this prompt does not hold is what makes a model write the
// name itself, as prose, in the reply the player reads.
func AiNpcReachDedicated() -> String {
    return "You reach V only by text message.";
}

// The command call: the vocabulary and nothing else, answered in one line. NONE is named
// because AiNpcActionSelectorRefusal reads it back, and an empty answer is indistinguishable
// from a request that failed.
func AiNpcReachCommands() -> String {
    return "Determine if an action is required; use commands in <actions> if you decide it is necessary. Otherwise answer NONE.";
}

func AiNpcReachRule(source: String) -> String {
    if Equals(source, "dedicated") {
        return AiNpcReachDedicated();
    }
    if Equals(source, "commands") {
        return AiNpcReachCommands();
    }
    return AiNpcReachConversation();
}

/// The block ///

// PROMISES is locked -- see AiNpcRuleIsLocked. It is the one clause whose loss the player
// sees: a character promising to come and getting nobody there reads as the mod being broken
// rather than as a character changing its mind.
func AiNpcCoreInteractionRules(source: String, recipe: ref<AiNpcRecipe>) -> array<ref<AiNpcRule>> {
    let rules: array<ref<AiNpcRule>>;

    if AiNpcRecipeWants(recipe, "interactions", "reach") {
        ArrayPush(rules, AiNpcRuleOf("REACH", AiNpcReachRule(source)));
    }
    // The test is "did it happen?", never "is it an act?". A blanket ban on acts forbids
    // exactly what the commands do -- a transfer moves real eddies -- from a rubric read
    // before the commands are announced, which a model resolves by committing to nothing.
    if AiNpcRecipeWants(recipe, "interactions", "real") {
        ArrayPush(rules, AiNpcRuleOf("REAL", "What a command did is real, and so is what your memory says you agreed to."));
    }
    if AiNpcRecipeWants(recipe, "interactions", "promises") {
        ArrayPush(rules, AiNpcRuleOf("PROMISES", "Everything else you never did: do not announce it, do not promise it."));
    }

    return rules;
}

func AiNpcRenderInteractions(contactId: String, recipe: ref<AiNpcRecipe>) -> String {
    if !AiNpcRecipeHas(recipe, "interactions") {
        return "";
    }

    let source = AiNpcRecipeSourceOf(recipe, "interactions");
    if Equals(StrLen(source), 0) {
        source = AiNpcInteractionDefaultSource();
    }

    return AiNpcRenderRules("interactions",
        AiNpcComposedRules("interactions", contactId,
            AiNpcCoreInteractionRules(source, recipe),
            AiNpcPromptOverridesFor(contactId).interactions,
            AiNpcGetPromptConfig().interactions,
            AiNpcExtensionInteractionRules(AiNpcBuildContactContext(contactId))));
}
