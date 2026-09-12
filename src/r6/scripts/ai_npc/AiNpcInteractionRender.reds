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
//
// LE MEDIUM N'EST PLUS ICI. Cette phrase commencait par « You reach V only by text message »,
// et elle etait fausse pendant un appel : un personnage au telephone lisait qu'il envoyait des
// SMS. Le medium est affirme par <channel>, qui sait sur quelle surface le tour se tient. Ce
// qui reste vaut sur toutes.
func AiNpcReachConversation() -> String {
    return "The commands in <actions> are the only way you can act on the world. Use them when the context calls for it, exactly as written, only when it is necessary; skip actions otherwise.";
}

// The conversation whose commands were moved to a second call. It carries no vocabulary, so
// it asks for none: naming a block this prompt does not hold is what makes a model write the
// name itself, as prose, in the reply the player reads.
//
// VIDE, DONC PAS DE RUBRIQUE. Tout ce qu'elle disait etait le medium, parti dans <channel> ;
// il ne restait qu'un intitule sans phrase, et une rubrique qui n'affirme rien coute un nom
// que le modele doit lire. Rendre "" est la reponse, pas un manque : AiNpcRenderRules laisse
// tomber une rubrique sans texte, et c'est le seul endroit qui en decide.
func AiNpcReachDedicated() -> String {
    return "";
}

// The command call: the vocabulary and nothing else, answered in one line. NONE is named
// because AiNpcActionIsNone reads it back, and an empty answer is indistinguishable
// from a request that failed.
//
// IT NAMES WHAT TO READ AND WHAT TO AVOID, because this request has no other job. The other
// wording is a conduct rubric inside a conversation -- the model is writing a reply and a
// command is at most part of it -- while here the answer IS the decision, and a decision put
// as a condition to satisfy is read as satisfied by a model that was just handed a vocabulary
// to use. Measured on two bookings in one evening, both through this lane: a stranger's tag
// was emitted on his own offer before V had answered it, and another on a message whose prose
// was still asking a question.
//
// THE IMPERATIVE VERBS ARE THE INSTRUCTION, not a way of phrasing it. "Analyse" and "Think"
// are asked for as words: an order to deliberate is what recruits the reasoning the decision
// needs, and a paraphrase that states the same requirement without the verb drops exactly
// that. Both failure modes are named for the same reason, in the vocabulary
// docs/PLAN_ACTION_SELECTOR.md measures this lane with: a rubric aimed at one of them alone
// slides into the other.
func AiNpcReachCommands() -> String {
    return "Analyse the conversation to decide whether an action must be taken or not. Think about avoiding false positives and false negatives. Use the commands in <actions> ONLY if you decide one is strictly necessary. Otherwise answer NONE.";
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

// What a contact, the config or an extension adds to <interactions> is conduct for talking to
// V. The command call does not talk, so it renders the core wording alone.
func AiNpcInteractionSourceTakesContributions(source: String) -> Bool {
    return !Equals(source, "commands");
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

func AiNpcRenderInteractions(contactId: String, recipe: ref<AiNpcRecipe>,
                             ctx: ref<AiNpcContactContext>) -> String {
    if !AiNpcRecipeHas(recipe, "interactions") {
        return "";
    }

    let source = AiNpcRecipeSourceOf(recipe, "interactions");
    if Equals(StrLen(source), 0) {
        source = AiNpcInteractionDefaultSource();
    }

    let core = AiNpcCoreInteractionRules(source, recipe);
    if !AiNpcInteractionSourceTakesContributions(source) {
        return AiNpcRenderRules("interactions", core);
    }

    return AiNpcRenderRules("interactions",
        AiNpcComposedRules("interactions", contactId,
            core,
            AiNpcPromptOverridesFor(contactId).interactions,
            AiNpcGetPromptConfig().interactions,
            AiNpcExtensionInteractionRules(ctx)));
}
