// The two messages of one pass, and the only door onto its recipe.
//
// A builder knows one thing about itself: which pass it is. Everything else follows from that
// name -- the slot AiNpcPassSend resolves, and the recipe Recipe() reads -- so a builder cannot
// render one pass against another pass's configuration.
//
// No side effect below this line. What a request costs the world -- a pending context consumed,
// a budget spent -- is the lane's, taken before the builder is constructed.

module AiNpc

class AiNpcPassBuilder extends IScriptable {
    func Pass() -> String {
        return "";
    }

    // The recipe bound to this pass, or the active one. The single call site of
    // AiNpcPassRecipe, which tools\lint.ps1 holds to one.
    func Recipe() -> ref<AiNpcRecipe> {
        return AiNpcPassRecipe(this.Pass());
    }

    func Instruction() -> String {
        return "";
    }

    func Ask() -> String {
        return "";
    }

    // Whether this pass has anything to send. False costs the request and nothing else: the
    // lane asks before it spends, and AiNpcPassSend asks again before it posts.
    func Ready() -> Bool {
        return true;
    }
}

// Whether the conversation prompt carries the command vocabulary, which is the whole of what
// "Embedded" and "Dedicated" name. THE RECIPE ANSWERS IT, not the menu: the Command Handling
// setting picks which conversation recipe the speaking pass is bound to (AiNpcPassRecipeName),
// and a recipes.json written by hand reaches the same answer without touching the menu.
//
// Here rather than beside its two readers, because the recipe has one door -- see the spine
// rule in tools\lint.ps1. Both readers live in the speaking lane, which is the pass this asks
// about.
func AiNpcSpeakingCarriesActions() -> Bool {
    return AiNpcRecipeHas(AiNpcPassRecipe(AiNpcLaneSpeaking()), "actions");
}
