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

// The HUD's own coordinates, whatever the screen really is: 3840 x 2160 virtual units, which
// the engine scales. Every mod that hangs a widget on this layer states the same pair.
func AiNpcHoloInputScreenWidth() -> Float {
    return 3840.0;
}

func AiNpcHoloInputScreenHeight() -> Float {
    return 2160.0;
}

func AiNpcHoloInputWidth() -> Float {
    return 2200.0;
}

// Enough for a spoken sentence without the line becoming a message box: past three lines the
// player is writing prose, and a call is not a chat.
func AiNpcHoloInputLines() -> Int32 {
    return 3;
}

// How far the bottom of the line sits above the bottom of the screen.
func AiNpcHoloInputBottomGap() -> Float {
    return 260.0;
}

// Along the bottom edge, centred. Beside the call widgets it was drawn BEHIND the holo panel:
// the panel is larger than the `incomming_call_slot` margins suggest, and the only part of the
// screen it leaves free is the strip the game keeps for subtitles.
func AiNpcHoloInputTop() -> Float {
    return AiNpcHoloInputScreenHeight() - AiNpcHoloInputBottomGap()
           - AiNpcTerminalStyle.FieldHeightFor(AiNpcHoloInputLines());
}

func AiNpcHoloInputLeft() -> Float {
    return (AiNpcHoloInputScreenWidth() - AiNpcHoloInputWidth()) * 0.5;
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

    private let m_field: ref<AiNpcHoloField>;

    // Escape reaches this line twice: once as a key, which the field answers by giving the
    // keyboard back, and once as the pause action, which the game answers by opening its menu.
    // Only the first is what the player meant. It is noted here because by the time the action
    // arrives the line no longer holds the keyboard, so asking whether it does would let the
    // menu through -- which is exactly what happened.
    private let m_escaped: Bool;

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

        this.m_field = new AiNpcHoloField();
        this.m_field.Setup(AiNpcHoloInputPlaceholder(), AiNpcHoloInputLines());
        // La couleur du texte en cours de frappe, la meme sur les trois surfaces. L'accent
        // corail est reserve a ce qui demande une lecture -- une ligne dans laquelle on tape
        // n'est pas une alerte.
        this.m_field.Build(host, AiNpcHoloInputLeft(), AiNpcHoloInputTop(), AiNpcHoloInputWidth(),
            AiNpcStyle.Typed());

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
        this.m_escaped = false;
    }

    // Enter and Escape, and nothing else. THE FIELD APPLIES THE KEY ITSELF, from its own
    // OnInputKey handler and through AiNpcKeyRepeat -- applying it a second time here typed
    // every character twice or more, which reads as "SSSallluutttt" and not as a repeat bug.
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

        if Equals(evt.GetKey(), EInputKey.IK_Escape) {
            this.m_escaped = true;
            return true;
        }

        if !this.m_field.TakeSubmitted() {
            return true;
        }

        // EVERY validation ends the typing, empty line included. What is typed here is one
        // spoken sentence, not a thread: the player says it and goes back to walking, and a
        // line that kept the keyboard after Enter left them unable to move. What to do with an
        // empty line is the call's, and it says nothing.
        // The line is reported before the keyboard is given back: the call has to hear it while
        // the player is still typing, or the release reads as a line given up.
        let text = this.m_field.GetText();
        this.m_field.Clear();

        let call = AiNpcCallSystem.Get();
        if IsDefined(call) {
            call.ReportSpoken(text);
        }
        this.m_field.ReleaseKeyboard();
        return true;
    }

    // Read and cleared: the note exists to answer one pause action, the one that follows the
    // key that set it.
    public final func TakeEscaped() -> Bool {
        let was: Bool = this.m_escaped;
        this.m_escaped = false;
        return was;
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
