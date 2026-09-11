// Knowledge of one specific vanilla layout: the phone HUD the chat is drawn into.
//
// Separate from AiNpcWidgets.reds, which is the generic search by name. This file knows a
// SHAPE -- the phone mounts its screens in canvases called "contact_list_slot" and
// "sms_messenger_slot" -- and that shape changes when CDPR or another mod moves the phone
// around, while the generic search changes when inkWidget hierarchies do.
//
// None of this tree belongs to us, so the whole walk happens here and is all-or-nothing: a
// caller gets a fully resolved answer or an empty one, never a half-resolved state to be wrong
// about.

module AiNpc

// `found` is the only thing a caller should branch on: the chat is drawn as a sibling of the
// contact list and hidden by toggling it, so a tree with a parent and no list is nothing to do.
public class AiNpcPhoneTree {
    public let parent: wref<inkCanvas>;
    public let contactListSlot: wref<inkCanvas>;
    public let defaultChatUi: wref<inkCanvas>;
    public let found: Bool = false;
}

// Finds the panel the game mounts its phone in, by the names the game gives it:
// `contact_list_slot` -- the canvas the contact list is drawn into -- or `sms_messenger_slot`
// next to it. The chat is then drawn as a sibling of that canvas.
//
// By name, and only by name. There used to be an index walk behind this, counting down through
// the children of the HUD root; it never read the index it counted, so it re-ran this same scan
// ten times and logged nine lines naming a widget it had not looked at.
func AiNpcResolvePhoneTree() -> ref<AiNpcPhoneTree> {
    let tree = new AiNpcPhoneTree();

    let inkSystem = GameInstance.GetInkSystem();
    if !IsDefined(inkSystem) { return tree; }

    let layer = inkSystem.GetLayer(n"inkHUDLayer");
    if !IsDefined(layer) { return tree; }

    let virtualWindow = layer.GetVirtualWindow();
    if !IsDefined(virtualWindow) { return tree; }

    let root0: wref<inkCompoundWidget> = virtualWindow.GetWidget(0) as inkCompoundWidget;
    if !IsDefined(root0) {
        root0 = virtualWindow.GetWidgetByPathName(n"Root") as inkCompoundWidget;
    }
    if !IsDefined(root0) { return tree; }

    let count: Int32 = root0.GetNumChildren();
    let mid: wref<inkCompoundWidget>;
    let i: Int32 = 0;
    while i < count {
        let cand: wref<inkCompoundWidget> = root0.GetWidget(i) as inkCompoundWidget;
        if IsDefined(cand) {
            let p0: wref<inkCompoundWidget> = cand.GetWidget(0) as inkCompoundWidget;
            if IsDefined(p0) {
                let contactSlot: wref<inkWidget> = AiNpcFindWidget(p0, n"contact_list_slot");
                if !IsDefined(contactSlot) {
                    contactSlot = AiNpcFindWidget(p0, n"sms_messenger_slot");
                }
                if IsDefined(contactSlot) {
                    mid = cand;
                    break;
                }
            }
        }
        i += 1;
    }

    if IsDefined(mid) {
        tree.parent = mid.GetWidget(0) as inkCanvas;
        tree.contactListSlot = AiNpcFindWidget(tree.parent, n"contact_list_slot") as inkCanvas;
        tree.defaultChatUi = AiNpcFindWidget(tree.parent, n"sms_messenger_slot") as inkCanvas;
        tree.found = IsDefined(tree.contactListSlot);
        return tree;
    }

    // Nothing on the HUD layer holds a widget by either name. The phone works; ai_npc's chat
    // is what cannot be drawn.
    AiNpcLog("No 'contact_list_slot' or 'sms_messenger_slot' anywhere on the HUD layer: the chat cannot be drawn into the phone this session. Another mod replacing the phone UI, or a game patch that renamed them.");
    return tree;
}
