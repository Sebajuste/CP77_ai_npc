// Knowledge of one specific vanilla layout: the phone's contact list.
//
// Separate from AiNpcWidgets.reds, which is the generic search by name. This file knows a
// SHAPE -- a contact row holds a label called "contactLabel", the badges live in a
// "hints_holder", the holder hangs off a "horiz_holder" -- and that shape changes when CDPR
// or another mod moves the phone around, while the generic search changes when inkWidget
// hierarchies do.
//
// Reaching one of these widgets is six steps, every one of which can fail because none of
// this tree belongs to us, and a forgotten check dereferences null inside a HUD callback. So
// the whole walk happens here and is all-or-nothing: a caller gets a fully resolved answer or
// an empty one, never a half-resolved state to be wrong about.

module AiNpc

// labelMatched is separate from hintsHolder: "no row is labelled that" and "the row is there
// but its shape is not the one we know" are different failures, and only the first is worth
// telling the player's log about. The second is another mod having rearranged the phone.
public class AiNpcContactRow {
    public let entry: wref<inkCompoundWidget>;
    public let hintsHolder: wref<inkHorizontalPanel>;
    public let existingHint: wref<inkHorizontalPanel>;
    public let labelMatched: Bool = false;
}

// The row whose label reads `expectedLabel`, fully resolved or not at all.
//
// hintsHolder is null unless EVERY step of the walk resolved and the holder sits where it is
// expected to. It never null-checks a caller into safety: dereferencing it anyway fails here
// rather than one frame later somewhere else.
func AiNpcResolveContactRow(listRef: inkWidgetRef, expectedLabel: String) -> ref<AiNpcContactRow> {
    let row = new AiNpcContactRow();
    let list = inkWidgetRef.Get(listRef) as inkCompoundWidget;
    if !IsDefined(list) {
        return row;
    }

    let count = list.GetNumChildren();
    let i = 0;
    while i < count {
        let entry = list.GetWidgetByIndex(i) as inkCompoundWidget;
        if IsDefined(entry) {
            let label = AiNpcFindWidget(entry, n"contactLabel") as inkText;
            if IsDefined(label) && Equals(label.GetText(), expectedLabel) {
                row.entry = entry;
                row.labelMatched = true;

                let holder = AiNpcFindWidget(entry, n"hints_holder") as inkHorizontalPanel;
                // The shape assertion. A hints_holder whose parent is not horiz_holder is
                // not the holder this mod knows how to graft onto -- and parentWidget is
                // checked before its name is read, because a widget can have neither.
                if IsDefined(holder) && IsDefined(holder.parentWidget)
                    && Equals(s"\(holder.parentWidget.GetName())", "horiz_holder") {
                    row.hintsHolder = holder;
                    row.existingHint = AiNpcFindWidget(holder, n"ainpc_contact_hint") as inkHorizontalPanel;
                }
                return row;
            }
        }
        i += 1;
    }

    return row;
}

//
// The same rule, applied to the panel the chat is drawn into. It lives here rather than on
// the renderer so a renderer can be thrown away and rebuilt without taking the walk with it.
//
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
    // is what cannot be drawn, and the player sees a phone with no badge and no answer to T.
    AiNpcLog("No 'contact_list_slot' or 'sms_messenger_slot' anywhere on the HUD layer: the chat cannot be drawn into the phone this session. Another mod replacing the phone UI, or a game patch that renamed them.");
    return tree;
}

//
// Painting, and painting on a foreign tree, so it belongs on this side of the wall with the
// walk it depends on. What stays in AiNpcHooks.reds is one line reporting a row and one
// asking for it to be decorated.
//
// Everything here is idempotent and cheap to call often, because it IS called often: once per
// row per refresh of the contact list, in bursts of twenty-odd rows.
func AiNpcDecorateContactRow(listRef: inkWidgetRef, contactId: String) -> Void {
    // Nothing is offered while a reply is in flight: the badge would promise a chat that the
    // send path refuses.
    if GetAiNpcHttpSystem().GetIsGenerating() {
        return;
    }
    // Resolved ONCE and asked both questions: a lookup by id is a linear scan of the registry
    // comparing GetContactId() on every provider it walks past, and this runs once per row
    // every time the list redraws. See AiNpcIsContactReachable in AiNpcContacts.reds.
    let provider = AiNpcProviderFor(contactId);
    if !AiNpcIsContactReachable(contactId, provider) {
        return;
    }

    // The badge is attached by matching the row's displayed label against the character's
    // display name, the one part of this path that can fail silently: the contact answers to
    // T but shows no badge, which reads as "not supported". A provider whose GetDisplayName
    // disagrees with the localizedName its mod put on the ContactData is that case.
    let expectedLabel = AiNpcNameOfProvider(provider);
    let row = AiNpcResolveContactRow(listRef, expectedLabel);

    if !row.labelMatched {
        if AiNpcLogging() {
            AiNpcLog(s"No contact row labelled '\(expectedLabel)' for '\(contactId)'; the chat still opens on T, but the row shows no badge. A provider's GetDisplayName must equal the localizedName on its ContactData.");
        }
        return;
    }

    if !IsDefined(row.hintsHolder) || IsDefined(row.existingHint) {
        return;
    }

    // Built through the same helpers the chat's own hint strip uses (AiNpcInk.reds,
    // AiNpcPhoneHints.reds), so the two atlases are named once each in AiNpcPhoneStyle. A
    // mistyped resource path does not fail -- the widget simply draws nothing.
    let hintMod = AiNpcInkHorizontal(row.hintsHolder, n"ainpc_contact_hint");
    hintMod.SetVisible(true);
    hintMod.SetAnchor(inkEAnchor.TopRight);
    hintMod.SetVAlign(inkEVerticalAlign.Center);
    hintMod.SetHAlign(inkEHorizontalAlign.Right);

    // NOT AiNpcInkBindTint: that helper pairs BindProperty with a SetStyle of the mod's own
    // style resource, which the chat panel needs because its tree has no vanilla ancestor to
    // inherit one from. This badge hangs off a vanilla contact row and resolves
    // ContactListItem.* against it, so a SetStyle here would repoint the lookup and recolour
    // the badge.
    let keyWidget = AiNpcInkImage(hintMod, n"hint_icon", AiNpcPhoneStyle.AtlasKeyboard(),
                                  n"kb_t", AiNpcStyle.Character());
    keyWidget.SetSize(new Vector2(64.0, 64.0));
    keyWidget.SetAnchor(inkEAnchor.Centered);
    keyWidget.SetVisible(true);
    keyWidget.SetVAlign(inkEVerticalAlign.Center);
    keyWidget.SetHAlign(inkEHorizontalAlign.Center);
    // Bound, then set: the order is what renders today, and the last write is the one that
    // shows when the binding does not resolve.
    keyWidget.BindProperty(n"tintColor", n"ContactListItem.fontColor");
    keyWidget.SetTintColor(AiNpcStyle.Character());

    let iconWidget = AiNpcInkImage(hintMod, n"hint_fluff", AiNpcPhoneStyle.AtlasCommonIcons(),
                                   n"ico_envelelope_reply1", AiNpcStyle.Character());
    iconWidget.SetSize(new Vector2(48.0, 48.0));
    iconWidget.SetAnchor(inkEAnchor.TopLeft);
    iconWidget.SetVAlign(inkEVerticalAlign.Center);
    iconWidget.SetHAlign(inkEHorizontalAlign.Center);
    iconWidget.SetMargin(new inkMargin(7.0, 9.0, 8.0, 0.0));
    iconWidget.SetFitToContent(true);
    iconWidget.BindProperty(n"tintColor", n"MainColors.Blue");
    iconWidget.BindProperty(n"opacity", n"MenuLabel.MainOpacity");
    iconWidget.SetVisible(true);

    row.hintsHolder.ReorderChild(hintMod, 0);
}
