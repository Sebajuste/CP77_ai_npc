// What a chat surface must be able to do, and nothing about how it does it.
//
// The seam is under the BEHAVIOUR, not under the surface. Splitting an over-long reply,
// filling a conversation out of the store, deciding whether a reply is ours to render, the
// resting/typing/generating states and the send sequence are decided once, in
// AiNpcChatSession. Put the seam above them and each surface owns its own copy, which is how
// the phone and the terminal came to disagree about whether a new message pins the view to
// the bottom.
//
// What is left is the questions only a surface can answer, and the verb list is deliberately
// NOT a lowest common denominator: a renderer answers each of them for ITSELF. SplitBudget is
// the pattern -- the session asks how long a message may be before it is split, and neither
// answer reaches the other surface. The same goes for HistoryLimit (the terminal shows the
// last 40 because a page is built in one pass, the phone shows all of them) and for
// IsAtBottom, where one surface asks an inkScrollController and the other does arithmetic on
// a cursor.
//
// A RENDERER MUST NOT HOLD STATE. It holds widgets. Anything it remembers between calls is
// state the session should have been holding, and it is what makes a renderer impossible to
// throw away when the HUD is rebuilt under it: a renderer is built when its widgets exist and
// dropped when they do not.

module AiNpc

// What the input row is showing. The session decides which one applies; the renderer decides
// what each one looks like.
public enum AiNpcInputMode {
    // Nothing is being typed: the resting label and its click hint.
    Resting = 0,
    // The player is typing: the field has the keyboard.
    Typing = 1,
    // A generation is in flight, so the field is refused rather than merely empty.
    Disabled = 2,
}

public abstract class AiNpcChatRenderer extends IScriptable {

    // Take every message off the surface. Called before a refill, never on its own.
    public func Clear() -> Void {}

    // One message. `animate` is false while filling a conversation that already happened
    // and true for a message arriving now -- a replayed history that animates reads as
    // twenty replies landing at once.
    public func AppendMessage(text: String, fromPlayer: Bool, animate: Bool) -> Void {}

    // The dots.
    public func SetTypingIndicator(value: Bool) -> Void {}

    // A generation is in flight. Distinct from the typing indicator: one is the character
    // appearing to write, the other is this surface refusing to take more input.
    public func SetBusy(value: Bool) -> Void {}

    public func SetInputMode(mode: AiNpcInputMode) -> Void {}

    public func ScrollToBottom() -> Void {}

    // Asked BEFORE appending, so "the player was reading the bottom" can be told apart from
    // "the player had scrolled up to read something older". The default is true because a
    // surface that cannot answer should keep following the conversation rather than freeze.
    public func IsAtBottom() -> Bool {
        return true;
    }

    // How long a message may be before it is split across two bubbles. Both surfaces answer
    // 1000 today; they are not required to, and that is the point.
    public func SplitBudget() -> Int32 {
        return 1000;
    }

    // How many messages of a thread to show, counting from the most recent. 0 means all of
    // them, which is what a surface that scrolls should answer.
    public func HistoryLimit() -> Int32 {
        return 0;
    }

    // Which channel this surface paints. The default is Text, so the phone and the terminal
    // need no edit: they paint what they have always painted.
    //
    // Beside SplitBudget and HistoryLimit, and for the same reason -- a renderer answers each of
    // these for ITSELF, and the holo's answer reaches neither of the other two.
    public func Channel() -> AiNpcChannelId {
        return AiNpcChannelId.Text;
    }

    // False once the widgets are gone. Dropping a dead renderer is better than asking it,
    // so this covers only the window between the tree going away and the session noticing.
    public func Alive() -> Bool {
        return true;
    }
}
