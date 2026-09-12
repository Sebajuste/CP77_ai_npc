// The command block the model reads, rendered from the table the dispatcher will index.
//
// Every line here is a pattern verbatim. Not a paraphrase of one, not a second string kept in
// step with one -- the same object. A command cannot be advertised without being claimed, and
// a claim cannot exist without a line, because there is one list and this walks it.
//
// Unbudgeted, unlike <now>, and for a reason worth keeping written down: a line here defines a
// command that WILL be honoured, so dropping it to save characters would leave the dispatcher
// accepting a vocabulary the model was never taught. A mod padding this block shows up in the
// prompt dump; a dropped command shows up as a feature that silently does nothing.
//
// The restraint lives on the other side instead: IsOffered removes a command from the prompt
// when it cannot fire, which costs nothing to a mod that means what it declared and everything
// to one that does not.
module AiNpc

func AiNpcActionBlockOpen() -> String {
    return "<actions>";
}

// The block, or "" when this contact has no command it can use right now -- absent rather than
// a heading with nothing under it, as every section here is.
//
// IsOffered is asked HERE and nowhere else on the prompt side. A claim that answers false is
// not written, and that is the cheapest refusal there is: a model told about a command it will
// be refused argues for it instead of talking.
func AiNpcRenderActionBlock(ctx: ref<AiNpcContactContext>, table: ref<AiNpcActionTable>) -> String {
    if !IsDefined(ctx) || !IsDefined(table) {
        return "";
    }

    // The contact's tags are resolved with the table, so the handlers below are handed them
    // rather than each resolving the same three lists again.
    ctx.tags = table.tags;

    let lines = "";
    let names: array<String>;
    let owners: array<String>;
    let definitions = "";
    let i = 0;
    let count = ArraySize(table.claims);
    while i < count {
        let claim = table.claims[i];
        if claim.handler.IsOffered(ctx) {
            let prompt = AiNpcSafeSectionText(claim.handler.GetPrompt(ctx, claim.prompt), claim.fullId);
            if NotEquals(StrLen(prompt), 0) {
                lines += AiNpcActionPatternLine(claim.pattern,
                    AiNpcExpandTemplateFor(table.contactId, prompt)) + "\n";
                definitions += AiNpcCollectActionParams(
                    claim, claim.handler.GetParameters(ctx, claim.parameters),
                    table.contactId, names, owners);
            }
        }
        i += 1;
    }

    return AiNpcActionBlockAround(lines, definitions);
}

// The definitions this claim adds to the block, and the two lists that keep the whole block
// honest: which names are already spoken for, and by whom.
//
// FIRST DEFINITION WINS, and a second one from ANOTHER mod is refused rather than overwritten.
// The rendered block is one flat list -- the model sees a single "{amount}" -- so two mods
// meaning different things by one name cannot both be served, whoever owns the claim. The same
// mod defining it twice is not a conflict: its second command simply uses what the first
// declared, which is the point of moving definitions out of the sentences.
//
// Silence is not an option here for the same reason it is not one at registration: the losing
// mod's command still cites the slot, so the model would read a name explained by somebody
// else's text.
func AiNpcCollectActionParams(claim: ref<AiNpcActionClaim>,
                                     parameters: array<ref<AiNpcActionParam>>,
                                     contactId: String,
                                     out names: array<String>, out owners: array<String>) -> String {
    let out = "";
    let i = 0;
    while i < ArraySize(parameters) {
        let param = parameters[i];
        let at = AiNpcIdIndexOf(names, param.name);
        if at < 0 {
            ArrayPush(names, param.name);
            ArrayPush(owners, claim.modId);
            out += param.name + ": " + AiNpcExpandTemplateFor(contactId, param.text) + "\n";
        } else {
            if NotEquals(owners[at], claim.modId) {
                FTLogError(s"[ai_npc]: \(claim.fullId) redefines \(param.name), already defined by '\(owners[at])'. The block is one list: rename the slot.");
            }
        }
        i += 1;
    }
    return out;
}

// The framing, apart from the walk that fills it. Separated so the text has one home: the
// offline builder in tools\\prompt reads this function to reproduce the block without the game,
// and a header spelled inside a loop is a header it would have to re-type.
//
// One placement rule for every command, stated once. Two of them -- one here and one in a
// neighbouring block -- taught the model there were two conventions to arbitrate between,
// which is how a bracket ends up half-written.
//
// IT DESCRIBES, IT DOES NOT ORDER. "Write a command" was an imperative carrying no condition,
// and it was the last thing read before the vocabulary -- so it won against every rubric above
// it that asked for a decision first, including one that said ONLY if strictly necessary and
// named NONE. Measured on the action pass: a stranger who had named a price and nothing else
// got a meeting booked at a venue and an hour the conversation had never mentioned. A sentence
// that states where a command goes cannot be obeyed by writing one.
//
// AND NOTHING IS A LISTED CHOICE, not a word in a rubric. The vocabulary is where a model looks
// for what it may answer, so "do nothing" stated anywhere else is an instruction competing with
// a list, and the list wins. It is not a claim and never becomes one: nobody implements it,
// AiNpcActionIsNone reads it back on both lanes, and a tag meaning "I wrote no command" has
// nothing to dispatch to.
func AiNpcActionBlockAround(lines: String, opt definitions: String) -> String {
    if Equals(StrLen(lines), 0) {
        return "";
    }
    // ONE EXPRESSION, deliberately. tools\\prompt\\sectionreader.py harvests this function's
    // final return to reproduce the frame offline; accumulating into a local left it holding a
    // reference it cannot resolve, and the offline block silently lost its header. `definitions`
    // is "" when no command declared a parameter, so it concatenates either way.
    return AiNpcActionBlockOpen()
        + "A command is written on the last line of your message, exactly as shown, with its "
        + "slots filled from the parameters below.\n"
        + lines
        + "[ACTION:" + AiNpcActionSelectorNone() + "]: DOING NOTHING, and the right answer "
        + "whenever the conversation has not reached what a command above describes.\n"
        + definitions
        + "</actions>";
}

// What the repair pass is handed: the vocabulary alone, with no persona and no transcript.
// Empty means this contact was never given a command, and a bracket in its reply is therefore
// prose -- asking a model to fix prose against an empty rulebook is how a good reply gets
// replaced by a worse one.
//
// The recipe is handed in rather than read: this is the same block <actions> renders in the
// prompt, so it has to be the same recipe. Reading one here made the two answers divergeable.
func AiNpcActionVocabularyFor(contactId: String, recipe: ref<AiNpcRecipe>,
                              ctx: ref<AiNpcContactContext>) -> String {
    if !AiNpcRecipeHas(recipe, "actions") {
        return "";
    }
    return AiNpcRenderActionBlock(ctx, AiNpcBuildActionTable(contactId));
}
