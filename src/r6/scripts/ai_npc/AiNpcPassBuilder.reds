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
