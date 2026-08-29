// A probe for ONE question: does a widget that listens for n"OnInputKey" receive keys inside
// inkHUDLayer?
//
// ANSWERED, YES, on the forced-focus route, with evt.GetCharacter() delivering characters --
// so the phone chat can drop Codeware's HubTextInput and both surfaces end up with the one
// input implementation AiNpcTerminalField already carries. The file is kept as the evidence
// behind that answer: nothing depends on it, and deleting it reverts the mod exactly.
//
// The caveat, so a positive result is not over-read: it attaches at
// PhoneDialerLogicController.GetRootWidget(), while the chat lives in ainpc_chat_slot, a
// sibling subtree under contact_list_slot's parent. Keys arriving here make it very likely
// they arrive there too, but that is not measured.
//
// With the probe on: open the phone, a magenta box appears at the top left, type.
//   * characters appear   -> yes, on the forced-focus route
//   * nothing appears     -> click the box first, then type: that is the second focus route
//   * still nothing       -> no
//
// Every event is logged whether or not it produces a character, because "an event arrived but
// was not a character" and "no event arrived" are different answers.

module AiNpc

// The off switch. False disables the probe without deleting the file; deleting the file is
// the full revert.
//
// Off because the probe takes the keyboard focus and breaks phone navigation, which is its
// own doing rather than the mechanism's: OnAiNpcProbeKey returns true on every branch, and
// true means "handled, stop propagating".
func AiNpcProbeEnabled() -> Bool {
    return false;
}

public class AiNpcHudKeyProbe extends IScriptable {

    private let m_box: ref<inkCanvas>;
    private let m_label: ref<inkText>;
    private let m_text: String;
    private let m_events: Int32 = 0;
    private let m_characters: Int32 = 0;

    public final func Build(parent: ref<inkCompoundWidget>) -> Void {
        let box = new inkCanvas();
        box.SetName(n"ainpc_hud_key_probe");
        box.SetAnchor(inkEAnchor.TopLeft);
        box.SetAnchorPoint(new Vector2(0.0, 0.0));
        box.SetMargin(new inkMargin(200.0, 200.0, 0.0, 0.0));
        box.SetSize(new Vector2(1200.0, 90.0));
        // Both are required and neither is enough alone: interactive gets the mouse,
        // focus support gets the keyboard. Copied from AiNpcTerminalField.Build, which is
        // the version that works.
        box.SetInteractive(true);
        box.SetSupportFocus(true);
        box.Reparent(parent);

        let fill = new inkRectangle();
        fill.SetName(n"fill");
        fill.SetTintColor(new Color(Cast(255u), Cast(0u), Cast(180u), Cast(255u)));
        fill.SetOpacity(0.35);
        fill.SetAnchor(inkEAnchor.Fill);
        fill.SetSize(new Vector2(1200.0, 90.0));
        fill.SetInteractive(false);
        fill.Reparent(box);

        let label = new inkText();
        label.SetName(n"value");
        label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        label.SetFontStyle(n"Medium");
        label.SetFontSize(40);
        label.SetLetterCase(textLetterCase.OriginalCase);
        label.SetTintColor(new Color(Cast(255u), Cast(255u), Cast(255u), Cast(255u)));
        label.SetHAlign(inkEHorizontalAlign.Left);
        label.SetVAlign(inkEVerticalAlign.Top);
        label.SetAnchorPoint(new Vector2(0.0, 0.0));
        label.SetMargin(new inkMargin(20.0, 20.0, 0.0, 0.0));
        label.SetFitToContent(true);
        label.SetInteractive(false);
        label.Reparent(box);
        this.m_label = label;

        // The callbacks target this object, not the controller: it has to still be alive
        // when a key arrives, which is why the controller holds it in a field.
        box.RegisterToCallback(n"OnInputKey", this, n"OnAiNpcProbeKey");
        box.RegisterToCallback(n"OnRelease", this, n"OnAiNpcProbeClick");

        this.m_box = box;
        this.Refresh();

        // Focus route 2: forced. Route 1 is the click, handled below. Both are tried because
        // HubTextInput failed on BOTH inside a page, and a probe testing only one of them
        // cannot tell the two answers apart.
        let inkSystem = GameInstance.GetInkSystem();
        if IsDefined(inkSystem) {
            inkSystem.SetFocus(box);
            AiNpcLog("[probe] built on the dialer root, focus forced via inkSystem.SetFocus.");
        } else {
            AiNpcLog("[probe] built, but GetInkSystem() is null -- focus not forced.");
        }
    }

    private func Refresh() -> Void {
        if IsDefined(this.m_label) {
            this.m_label.SetText(s"PROBE  events:\(this.m_events)  chars:\(this.m_characters)  [\(this.m_text)]");
        }
    }

    // Everything is logged, including the events that produce nothing. "An event arrived
    // but was not a character" and "no event arrived at all" are different answers.
    protected cb func OnAiNpcProbeKey(evt: ref<inkKeyInputEvent>) -> Bool {
        this.m_events += 1;
        let action = s"\(evt.GetAction())";
        let key = s"\(evt.GetKey())";
        AiNpcLog(s"[probe] OnInputKey: action=\(action) key=\(key) isCharacter=\(evt.IsCharacter())");

        if NotEquals(evt.GetAction(), EInputAction.IACT_Press) {
            this.Refresh();
            return true;
        }

        if Equals(evt.GetKey(), EInputKey.IK_Backspace) {
            // Characters, not bytes -- see AiNpcUtf8. A probe exists to be believed: one
            // that mangles an accent would report the keyboard as broken when it is not.
            if AiNpcUtf8Len(this.m_text) > 0 {
                this.m_text = AiNpcUtf8DropLast(this.m_text);
            }
            this.Refresh();
            return true;
        }

        if evt.IsCharacter() && !evt.IsControlDown() && !evt.IsAltDown() {
            this.m_characters += 1;
            this.m_text += evt.GetCharacter();
            this.Refresh();
            return true;
        }

        this.Refresh();
        return true;
    }

    // Focus route 1: the click. Filtered against OnRelease the same way the terminal field
    // filters it -- OnRelease is delivered for the release of ANY pointer action, the mouse
    // wheel included.
    protected cb func OnAiNpcProbeClick(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        let inkSystem = GameInstance.GetInkSystem();
        if IsDefined(inkSystem) && IsDefined(this.m_box) {
            inkSystem.SetFocus(this.m_box);
            AiNpcLog("[probe] clicked: focus requested on the click route.");
        }
        return true;
    }
}

// Held by the controller so it outlives Build() and is still there when a key arrives.
@addField(PhoneDialerLogicController)
private let m_aiNpcKeyProbe: ref<AiNpcHudKeyProbe>;

// A second wrapper on a method AiNpcHooks.reds already wraps. Wrappers chain, and keeping
// the probe in its own file is what makes deleting it a complete revert.
@wrapMethod(PhoneDialerLogicController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();

    if !AiNpcProbeEnabled() {
        return result;
    }

    let root = this.GetRootWidget() as inkCompoundWidget;
    if !IsDefined(root) {
        AiNpcLog("[probe] no root widget on the dialer -- nothing built.");
        return result;
    }

    // Same duplicate guard as the "U" hint, and for the same reason: this method fires more
    // than once per session.
    if IsDefined(AiNpcFindWidget(root, n"ainpc_hud_key_probe")) {
        return result;
    }

    this.m_aiNpcKeyProbe = new AiNpcHudKeyProbe();
    this.m_aiNpcKeyProbe.Build(root);

    return result;
}
