// Walking the game's widget tree.
//
// One function, and it earns its own file for the same reason the clock does: it is the only
// thing in the mod that knows how inkWidget hierarchies are searched, and it is used from
// two very different places -- building the chat window, and grafting a hint onto the vanilla
// phone. Neither owns it.

module AiNpc

//
// A STACK, NOT A RECURSION. Depth first, parent before its children, children left to right,
// first match wins. The order is held by pushing the children in reverse, so the leftmost is
// the next one popped; anything else would change which widget a name resolves to when a tree
// carries the name twice.
//
// Iterative because this is the deepest walk the mod performs, on a tree the mod does not own
// and cannot bound, driven from a HUD callback once per contact row every time the phone's
// list redraws.
//
// Searching nothing finds nothing, and that guard lives inside the loop rather than at each
// call site: every caller starts its walk from a widget it resolved POSITIONALLY out of a
// vanilla layout, so "not the hierarchy we expected" is a normal outcome.
public final func AiNpcFindWidget(widget: wref<inkWidget>, name: CName) -> wref<inkWidget> {
    let pending: array<wref<inkWidget>>;
    ArrayPush(pending, widget);

    while ArraySize(pending) > 0 {
        let current = ArrayPop(pending);
        if IsDefined(current) {
            if Equals(current.GetName(), name) {
                return current;
            }

            let compoundWidget = current as inkCompoundWidget;
            if IsDefined(compoundWidget) {
                let i = compoundWidget.GetNumChildren() - 1;
                while i >= 0 {
                    ArrayPush(pending, compoundWidget.GetWidgetByIndex(i));
                    i -= 1;
                }
            }
        }
    }
    return null;
}
