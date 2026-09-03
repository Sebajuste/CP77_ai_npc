// The chat, with no surface attached: what is shown, what happens next, and nothing drawn.
//
// Five policies the phone and the terminal must not be free to answer differently:
//
//   1. splitting a reply too long for one bubble;
//   2. turning a stored history into the messages a surface should show;
//   3. deciding whether a reply is addressed to what this surface is showing;
//   4. the resting / typing / generating states;
//   5. the send sequence.
//
// Everything takes its data as a parameter. The test suite runs from AiNpcStorageService at
// game start, BEFORE any ScriptableSystem exists, and AiNpcConversationStore is one: a policy
// that reached for AiNpcConversationStore.Get() or GetAiNpcHttpSystem() would be
// unassertable. No Get...() below this line, ever.

module AiNpc

//
// Free functions over plain data: what the assertions reach. The class underneath is the part
// that needs a renderer to observe.

// One piece when the message fits, two when it does not -- never more: a reply long enough to
// need three is a provider problem rather than a layout one.
//
// A budget of zero or less means "no limit", so a surface that wraps natively can say so
// rather than pretending to a number.
func AiNpcSplitForBudget(text: String, budget: Int32) -> array<String> {
    let pieces: array<String>;
    if budget <= 0 || StrLen(text) <= budget {
        ArrayPush(pieces, text);
        return pieces;
    }
    ArrayPush(pieces, StrLeft(text, budget));
    ArrayPush(pieces, StrRight(text, StrLen(text) - budget));
    return pieces;
}

// Where a surface should start reading a thread, given how many messages it can show.
// A limit of zero or less means all of them. Never negative, so the caller can loop from
// the answer without a second guard.
func AiNpcHistoryWindowStart(count: Int32, limit: Int32) -> Int32 {
    if limit <= 0 {
        return 0;
    }
    let start: Int32 = count - limit;
    if start < 0 {
        return 0;
    }
    return start;
}

// The system-event marker is bookkeeping the prompt builder writes into the history as if the
// player had spoken. Filtered on the player's side only: it is never authored by a character.
func AiNpcIsDisplayableMessage(message: ref<AiNpcMessage>, surface: AiNpcChannelId) -> Bool {
    if !IsDefined(message) {
        return false;
    }
    // Une surface ne peint que son propre canal. C'est ici que ce qui a ete dit de vive voix
    // reste hors du fil ecrit, et le filtre est au bout de la lecture -- le store, lui, garde
    // une seule chronologie.
    if NotEquals(message.channel, surface) {
        return false;
    }
    if message.fromPlayer && Equals(message.text, AiNpcSystemEventMarker()) {
        return false;
    }
    return true;
}

// Refusing is not a failure: it is what sends the reply on to the SMS notification, where a
// reply for somebody else belongs. A surface showing nothing accepts nothing.
// Le canal de la reponse compte autant que le contact : la session du telephone est encore
// enregistree quand un appel se termine, et une reponse parlee en retard atterrirait dans le
// fil SMS avec ce test pour seul obstacle.
func AiNpcSessionAccepts(shownContactId: String, targetContactId: String,
                         surface: AiNpcChannelId, reply: AiNpcChannelId) -> Bool {
    if Equals(StrLen(shownContactId), 0) {
        return false;
    }
    if NotEquals(surface, reply) {
        return false;
    }
    return Equals(shownContactId, targetContactId);
}

public class AiNpcChatSession extends IScriptable {

    // The surface, or nothing. Nothing is an ordinary state: it is what a chat that is not on
    // screen looks like, and why replies fall through to the SMS notification.
    private let m_renderer: ref<AiNpcChatRenderer>;

    private let m_shownContactId: String = "";
    private let m_typing: Bool = false;
    private let m_busy: Bool = false;

    public final func Attach(renderer: ref<AiNpcChatRenderer>) -> Void {
        this.m_renderer = renderer;
    }

    public final func Detach() -> Void {
        this.m_renderer = null;
    }

    // Attached AND still standing. A renderer whose widgets went away answers false to
    // Alive(), and every path below treats that exactly like no renderer at all.
    public final func HasRenderer() -> Bool {
        return IsDefined(this.m_renderer) && this.m_renderer.Alive();
    }

    public final func GetRenderer() -> ref<AiNpcChatRenderer> {
        return this.m_renderer;
    }

    public final func GetShownContactId() -> String {
        return this.m_shownContactId;
    }

    public final func Show(contactId: String) -> Void {
        this.m_shownContactId = contactId;
    }

    public final func Close() -> Void {
        this.m_shownContactId = "";
        this.m_typing = false;
        this.m_busy = false;
    }

    public final func IsTyping() -> Bool {
        return this.m_typing;
    }

    public final func IsBusy() -> Bool {
        return this.m_busy;
    }

    // The history is handed in, never fetched. `messages` is the whole thread; the window and
    // the filtering are decided here, the budget by the renderer.
    public final func Fill(messages: array<ref<AiNpcMessage>>) -> Void {
        if !this.HasRenderer() {
            return;
        }
        let renderer = this.m_renderer;
        renderer.Clear();

        // Un fil ecrit garde la trace des appels ; une surface parlee n'a rien a resumer,
        // puisqu'elle ne montre que l'echange qu'on est en train d'avoir.
        let shown = messages;
        if AiNpcChannelOf(renderer.Channel()).ShowsInThread() {
            let settled = AiNpcHistoryWithoutLiveCall(messages,
                AiNpcLiveCallSince(this.GetShownContactId()));
            shown = AiNpcHistoryForThread(settled);
        }

        let count: Int32 = ArraySize(shown);
        let i: Int32 = AiNpcHistoryWindowStart(count, renderer.HistoryLimit());
        while i < count {
            if AiNpcIsDisplayableMessage(shown[i], renderer.Channel()) {
                this.Paint(shown[i].text, shown[i].fromPlayer, false);
            }
            i += 1;
        }

        renderer.ScrollToBottom();
        this.SyncInputMode();
    }

    // Only what a character says is split: a player's message came from a field with its own
    // limit, so splitting it would be the mod cutting up its own input.
    private final func Paint(text: String, fromPlayer: Bool, animate: Bool) -> Void {
        let renderer = this.m_renderer;
        if fromPlayer {
            renderer.AppendMessage(text, true, animate);
            return;
        }
        let pieces = AiNpcSplitForBudget(text, renderer.SplitBudget());
        let i: Int32 = 0;
        while i < ArraySize(pieces) {
            renderer.AppendMessage(pieces[i], false, animate);
            i += 1;
        }
    }

    // True when this surface rendered the reply; the false is what carries the reply on to the
    // SMS notification.
    //
    // Whether the view follows the conversation is decided BEFORE the message lands: a player
    // who had scrolled up to read something older is not dragged back down.
    public final func Deliver(contactId: String, text: String, channel: AiNpcChannelId) -> Bool {
        if !this.HasRenderer() {
            return false;
        }
        if !AiNpcSessionAccepts(this.m_shownContactId, contactId, this.m_renderer.Channel(), channel) {
            return false;
        }
        let follow: Bool = this.m_renderer.IsAtBottom();
        this.Paint(text, false, true);
        if follow {
            this.m_renderer.ScrollToBottom();
        }
        this.SyncInputMode();
        return true;
    }

    // The dots are the one signal that also means "stop": a false must be obeyed whoever it
    // was addressed to, because the generation it belonged to has ended either way.
    public final func SetTypingIndicator(contactId: String, value: Bool,
                                        channel: AiNpcChannelId) -> Void {
        if !this.HasRenderer() {
            return;
        }
        if AiNpcSessionAccepts(this.m_shownContactId, contactId, this.m_renderer.Channel(), channel)
                || !value {
            this.m_renderer.SetTypingIndicator(value);
        }
    }

    public final func SetBusy(value: Bool) -> Void {
        this.m_busy = value;
        if this.HasRenderer() {
            this.m_renderer.SetBusy(value);
        }
        this.SyncInputMode();
    }

    public final func BeginTyping() -> Void {
        this.m_typing = true;
        this.SyncInputMode();
    }

    public final func EndTyping() -> Void {
        this.m_typing = false;
        this.SyncInputMode();
    }

    // The one place the three states are decided, so no surface has to work them out again.
    // Busy wins over typing: a generation in flight refuses input whatever the player was
    // doing when it started.
    public final func SyncInputMode() -> Void {
        if !this.HasRenderer() {
            return;
        }
        if this.m_busy {
            this.m_renderer.SetInputMode(AiNpcInputMode.Disabled);
        } else if this.m_typing {
            this.m_renderer.SetInputMode(AiNpcInputMode.Typing);
        } else {
            this.m_renderer.SetInputMode(AiNpcInputMode.Resting);
        }
    }

    // The player's half of a turn, and the only part of the send sequence that belongs to the
    // chat: echo the message, stop typing, follow the conversation down.
    //
    // It does NOT talk to the HTTP lane -- that needs a system, which nothing here may reach
    // for. It returns whether the message was worth sending, so the caller decides without
    // re-deciding what "worth sending" means.
    public final func AcceptTyped(text: String) -> Bool {
        if Equals(StrLen(text), 0) {
            this.EndTyping();
            return false;
        }
        if this.m_busy {
            return false;
        }
        if this.HasRenderer() {
            this.Paint(text, true, true);
            this.m_renderer.ScrollToBottom();
        }
        this.EndTyping();
        return true;
    }
}
