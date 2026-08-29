// A text field for a computer terminal, assembled from raw key events.
//
// Not Codeware: HubTextInput, which the phone chat uses, delivers no keystroke in a browser
// page -- measured on both focus routes -- and instantiating the vanilla inkTextInput from
// script and reparenting it crashes the game. What works is the mechanism underneath: an
// interactive, focusable widget listening for n"OnInputKey" and assembling the string itself.
//
// Three things that are easy to get wrong:
//
// 1. OnInputKey fires once per input action, not per keystroke: only IACT_Press is a
//    character, and acting on the others turns one tap into "aaaaaaa". A held key, which the
//    engine repeats for nobody, is AiNpcKeyRepeat's -- this file only feeds it presses and
//    releases.
//
// 2. A page never redraws itself, so the label is updated in place. Rebuilding on a keystroke
//    would also drop the focus, making the second character impossible to type.
//
// 3. There is no IK_NumPad_Enter in the enum, only IK_Enter.
//
// The field outlives the page it is drawn on: the text lives in m_text rather than in a
// widget, so its owner calls Build() again on every page and nothing typed is lost. It is its
// own IScriptable because it is the callback target for its own keys.
//
// The keyboard does not outlive it: the text is the player's, the capture belongs to what is
// on screen. This class is a claimant so the routes out of a page can hand the keyboard back
// without holding this object.

module AiNpc

public class AiNpcTerminalField extends AiNpcKeyboardClaimant {

    private let m_box: ref<inkCanvas>;
    private let m_fill: ref<inkRectangle>;
    private let m_label: ref<inkText>;

    private let m_text: String;

    // The clock that replays a held key. Owned rather than inherited: a keyboard's repeat is
    // not a property of a rectangle with text in it.
    private let m_repeat: ref<AiNpcKeyRepeat>;

    private let m_placeholder: String;
    private let m_focused: Bool;
    private let m_disabled: Bool;

    // Set on Enter, read and cleared by the owner: the field cannot know what submitting
    // means, so it only records that it happened.
    private let m_submitted: Bool;

    public final func Setup(placeholder: String) -> Void {
        this.m_placeholder = placeholder;
        this.m_repeat = new AiNpcKeyRepeat();
        this.m_repeat.Bind(this);
    }

    // What leaves the field is well-formed whatever happened while it was typed. The editing
    // above cannot produce a stray byte, so this covers what the key events deliver -- the one
    // input this class does not control. Once per send, never while typing.
    public final func GetText() -> String {
        return AiNpcUtf8Clean(this.m_text);
    }

    public final func Clear() -> Void {
        this.m_text = "";
        this.m_submitted = false;
        this.Refresh();
    }

    public final func TakeSubmitted() -> Bool {
        let was: Bool = this.m_submitted;
        this.m_submitted = false;
        return was;
    }

    public final func IsFocused() -> Bool {
        return this.m_focused;
    }

    // Greyed out while a reply is in flight. The keys are still delivered: refusing them here
    // rather than unregistering the callback keeps the widget's state and the field's from
    // diverging.
    public final func SetDisabled(value: Bool) -> Void {
        this.m_disabled = value;
        if value {
            // The keyboard goes back too, not just the highlight: a disabled field that kept
            // the capture refuses the keys and stops the player moving.
            this.ReleaseKeyboard();
        }
        this.Refresh();
    }

    public final func GetRootWidget() -> ref<inkCanvas> {
        return this.m_box;
    }


    // In flow layout the caller has already anchored the parent, so only the height is ours to
    // state; in absolute layout the caller passes x / y / w and we place ourselves.
    public final func Build(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float,
                            colour: Color) -> Void {
        let box = new inkCanvas();
        box.SetName(n"ainpc_field");
        box.SetHAlign(inkEHorizontalAlign.Left);
        box.SetVAlign(inkEVerticalAlign.Top);
        box.SetAnchorPoint(new Vector2(0.0, 0.0));
        box.SetSize(new Vector2(w, AiNpcTerminalStyle.FieldHeight()));
        box.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        // Both are required: interactive gets the mouse, focus support gets the keyboard.
        box.SetInteractive(true);
        box.SetSupportFocus(true);
        box.Reparent(parent);

        let fill = new inkRectangle();
        fill.SetName(n"fill");
        fill.SetTintColor(colour);
        fill.SetAnchor(inkEAnchor.Fill);
        fill.SetSize(new Vector2(w, AiNpcTerminalStyle.FieldHeight()));
        fill.Reparent(box);
        this.m_fill = fill;

        let label = new inkText();
        label.SetName(n"value");
        label.SetFontFamily(AiNpcTerminalStyle.FontFamily());
        label.SetFontStyle(AiNpcTerminalStyle.FontStyleBody());
        label.SetFontSize(AiNpcTerminalStyle.FsBody());
        label.SetLetterCase(textLetterCase.OriginalCase);
        label.SetTintColor(colour);
        label.SetHAlign(inkEHorizontalAlign.Left);
        label.SetVAlign(inkEVerticalAlign.Top);
        label.SetAnchorPoint(new Vector2(0.0, 0.0));
        label.SetMargin(new inkMargin(AiNpcTerminalStyle.FieldTextInset(),
                                      AiNpcTerminalStyle.FieldTextInset() * 0.6, 0.0, 0.0));
        label.SetFitToContent(true);
        label.SetInteractive(false);
        label.Reparent(box);
        this.m_label = label;

        // The callbacks target the field, not the page: the field turns a key into a character
        // and survives the page being rebuilt.
        box.RegisterToCallback(n"OnInputKey", this, n"OnAiNpcFieldKey");
        box.RegisterToCallback(n"OnRelease", this, n"OnAiNpcFieldClick");

        this.m_box = box;
        this.m_repeat.Start(box);
        this.Refresh();
    }

    // Called on a click, and by the page for the field the player should start in. Announced to
    // the capture registry in the same breath, because a capture nobody knows about is one
    // nobody can end.
    public final func Focus() -> Void {
        if !IsDefined(this.m_box) || this.m_disabled {
            return;
        }
        // The claim comes first: it makes a previous holder let go, and letting go clears the
        // ink focus. Announced afterwards, the other field's release would land on the focus
        // this one had just taken.
        AiNpcClaimKeyboard(this);
        let inkSystem = GameInstance.GetInkSystem();
        if IsDefined(inkSystem) {
            inkSystem.SetFocus(this.m_box);
        }
        this.m_focused = true;
        this.Refresh();
    }

    // The only way this field lets go, whoever says it and for whatever reason: the registry
    // retiring a page, Escape, a click elsewhere, a reply in flight.
    //
    // Safe to call from the registry, which clears the holder before asking it to let go: the
    // release then finds nothing to remove, because it removes by identity. Idempotent,
    // because the routes out of a page overlap and a release that works once would depend on
    // which ran first.
    public func ReleaseKeyboard() -> Void {
        // Before the focus check: a key can be down while the capture ends for an unrelated
        // reason, and a repeat left armed would keep eating the line.
        this.m_repeat.Forget();
        if !this.m_focused {
            return;
        }
        this.m_focused = false;
        AiNpcClearInkFocus();
        AiNpcReleaseKeyboard(this);
        this.Refresh();
    }


    // Updates the widgets in place, never rebuilds.
    private func Refresh() -> Void {
        if IsDefined(this.m_fill) {
            if this.m_focused {
                this.m_fill.SetOpacity(AiNpcTerminalStyle.FieldFocusOpacity());
            } else {
                this.m_fill.SetOpacity(AiNpcTerminalStyle.FieldFillOpacity());
            }
        }
        if !IsDefined(this.m_label) {
            return;
        }

        if this.m_disabled {
            this.m_label.SetText(this.m_placeholder);
            this.m_label.SetOpacity(0.25);
            return;
        }

        if Equals(StrLen(this.m_text), 0) && !this.m_focused {
            this.m_label.SetText(this.m_placeholder);
            this.m_label.SetOpacity(0.45);
            return;
        }

        this.m_label.SetOpacity(1.0);
        if this.m_focused {
            this.m_label.SetText(this.Visible() + "_");
        } else {
            this.m_label.SetText(this.Visible());
        }
    }

    // What fits in the box. Nothing measures text here, so a long value is shown by its tail:
    // the player is typing at the end, and watching the beginning while the caret is off screen
    // is worse than truncating.
    private func Visible() -> String {
        let budget: Int32 = AiNpcTerminalStyle.FieldVisibleChars();
        if AiNpcUtf8Len(this.m_text) <= budget {
            return this.m_text;
        }
        // In characters: cutting the tail on a byte boundary would draw half an accent.
        return "..." + AiNpcUtf8Right(this.m_text, budget - 3);
    }


    protected cb func OnAiNpcFieldKey(evt: ref<inkKeyInputEvent>) -> Bool {
        AiNpcKeyTraceWidget(evt);

        // A release is the end of a keystroke, so only the clock has anything to do with it.
        if Equals(evt.GetAction(), EInputAction.IACT_Release) {
            this.m_repeat.Release(evt);
            return true;
        }
        // Press only, for everything else.
        if NotEquals(evt.GetAction(), EInputAction.IACT_Press) {
            return true;
        }
        if this.m_disabled {
            return true;
        }

        this.m_repeat.Press(evt);
        this.ApplyKey(evt);
        return true;
    }

    // One keystroke, from the engine or from the clock replaying a held key, which is why it is
    // the claimant's method. Everything the field does with a key is here, so a repeated key
    // cannot drift from a pressed one.
    public func ApplyKey(evt: ref<inkKeyInputEvent>) -> Void {
        if Equals(evt.GetKey(), EInputKey.IK_Enter) {
            // The text is not cleared here: the page reads it from its own handler and clears
            // the field once the message has been sent, so a refused send does not eat what
            // was typed.
            this.m_submitted = true;
            return;
        }

        // The way out every other text field in the game has: Escape gives the keyboard back
        // and leaves the page where it was. The typed text is kept -- Escape is "stop typing",
        // not "throw it away".
        if Equals(evt.GetKey(), EInputKey.IK_Escape) {
            this.ReleaseKeyboard();
            return;
        }

        if Equals(evt.GetKey(), EInputKey.IK_Backspace) {
            // One character, not one byte: as StrLeft(text, StrLen(text) - 1) this removed half
            // an accent and left the lead byte inside the message.
            if AiNpcUtf8Len(this.m_text) > 0 {
                this.m_text = AiNpcUtf8DropLast(this.m_text);
                this.Refresh();
            }
            return;
        }

        if evt.IsCharacter() && !evt.IsControlDown() && !evt.IsAltDown() {
            // The cap counts characters too: in bytes, a message in French is refused sooner
            // than the same message in English.
            if AiNpcUtf8Len(this.m_text) < AiNpcTerminalStyle.FieldMaxLength() {
                this.m_text += evt.GetCharacter();
                this.Refresh();
            }
        }
    }

    // Filtered like every other pointer callback here: OnRelease is delivered for any pointer
    // action, the wheel included, and unguarded, scrolling over the field stole the focus.
    protected cb func OnAiNpcFieldClick(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        // Consumed, so the page's backdrop handler does not read this click as "clicked
        // somewhere that is not the field" and blur what was just focused.
        evt.Consume();
        this.Focus();
        return true;
    }
}
