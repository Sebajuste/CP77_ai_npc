// One line to speak into, over a call. Not a chat: no thread, no bubbles, no history -- a call
// is spoken, and what is said on it has no business appearing as written messages.
//
// The field is the terminal's, `AiNpcTerminalField`, which is the mod's own widget rather than
// Codeware's. That was already the plan's choice for the holo, and it holds here for a second
// reason: the eventual speech-to-text lane replaces a field this mod wrote itself.
//
// WHERE IT HANGS. The call takes the phone off the screen, but the phone's HUD controller stays
// alive -- it is what hosts the game's own `incomming_call_slot` and `holoaudio_call_slot`. So
// its root is the parent that exists for exactly as long as a call does.
//
// The traversal of that foreign tree is one function, validated as a whole, per rule 2 of
// docs/VIEW_ARCHITECTURE.md: a caller gets a parent or nothing, never a half-walked tree.

module AiNpc

// What the empty line says. Its own function rather than a literal at the call site: the words
// a player reads belong beside the other labels of this lane, not inside a widget builder.
func AiNpcHoloInputPlaceholder() -> String {
    return "Say something...";
}

func AiNpcHoloInputWidth() -> Float {
    return 900.0;
}

// Placed under the call widgets rather than beside them: the game's own margins for
// `incomming_call_slot` put the call around 300 from the top, and a field over it would cover
// the face the player is talking to.
func AiNpcHoloInputTop() -> Float {
    return 620.0;
}

func AiNpcHoloInputLeft() -> Float {
    return 80.0;
}

// The one walk of the phone HUD's tree. Nothing else in this file reaches for a widget.
func AiNpcHoloInputHost() -> ref<inkCompoundWidget> {
    let phone = AiNpcFindPhoneController();
    if !IsDefined(phone) {
        return null;
    }
    return phone.GetRootCompoundWidget();
}

// Built when a call asks for it and dropped when the call ends. It holds widgets and no state:
// what was typed lives in the field, and whether a call is up lives in AiNpcCallSystem.
class AiNpcHoloInput extends IScriptable {

    private let m_field: ref<AiNpcTerminalField>;

    public final func IsUp() -> Bool {
        return IsDefined(this.m_field);
    }

    // False when there is nowhere to draw, which is an ordinary answer: the HUD is rebuilt on
    // more occasions than a call can know about.
    public final func Show() -> Bool {
        if IsDefined(this.m_field) {
            this.m_field.Focus();
            return true;
        }

        let host = AiNpcHoloInputHost();
        if !IsDefined(host) {
            AiNpcLog("No phone HUD host: the call has nowhere to put its input line.");
            return false;
        }

        this.m_field = new AiNpcTerminalField();
        this.m_field.Setup(AiNpcHoloInputPlaceholder());
        this.m_field.Build(host, AiNpcHoloInputLeft(), AiNpcHoloInputTop(), AiNpcHoloInputWidth(),
            AiNpcStyle.Accent());

        let box = this.m_field.GetRootWidget();
        if IsDefined(box) {
            box.RegisterToCallback(n"OnInputKey", this, n"OnAiNpcHoloFieldKey");
        }
        this.m_field.Focus();
        return true;
    }

    // The keyboard first, then the widgets: a field torn off the tree while it still holds the
    // keyboard leaves the player unable to move.
    public final func Hide() -> Void {
        if !IsDefined(this.m_field) {
            return;
        }

        this.m_field.ReleaseKeyboard();
        let box = this.m_field.GetRootWidget();
        if IsDefined(box) {
            box.UnregisterFromCallback(n"OnInputKey", this, n"OnAiNpcHoloFieldKey");
        }

        // By name, off the host we built into: an inkWidget cannot detach itself, and the host
        // is resolved again rather than held, because the HUD may have been rebuilt under us.
        let host = AiNpcHoloInputHost();
        if IsDefined(host) {
            host.RemoveChildByName(n"ainpc_field");
        }
        this.m_field = null;
    }

    // Enter, and nothing else. THE FIELD APPLIES THE KEY ITSELF, from its own OnInputKey
    // handler and through AiNpcKeyRepeat -- applying it a second time here typed every
    // character twice or more, which reads as "SSSallluutttt" and not as a repeat bug.
    //
    // Same shape as the terminal's handler next door, for the same reason: this decides what
    // Enter meant, the field decides what a key is.
    protected cb func OnAiNpcHoloFieldKey(evt: ref<inkKeyInputEvent>) -> Bool {
        if NotEquals(evt.GetAction(), EInputAction.IACT_Press) {
            return true;
        }
        if !IsDefined(this.m_field) {
            return false;
        }
        if !this.m_field.TakeSubmitted() {
            return true;
        }

        let text = this.m_field.GetText();
        this.m_field.Clear();

        let call = AiNpcCallSystem.Get();
        if IsDefined(call) {
            call.ReportSpoken(text);
        }
        return true;
    }

    // Whether the line still holds the keyboard. Asked by the call before it decides to eat the
    // pause key: a line the player has already left must not swallow Escape.
    public final func HasKeyboard() -> Bool {
        return IsDefined(this.m_field) && this.m_field.IsFocused();
    }

    public final func DropFocus() -> Void {
        if IsDefined(this.m_field) {
            this.m_field.ReleaseKeyboard();
        }
    }
}
