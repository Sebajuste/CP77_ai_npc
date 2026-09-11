// Where a generated reply goes, and who gets asked first.
//
// A session registers itself and gets first refusal on the reply, answering whether it
// rendered it; with nothing registered the lane falls through to an SMS notification. A
// terminal cannot reuse AiNpcSystem.chatOpen instead: that flag also binds EVERY key to the
// phone chat (ListenKeys(true)), so "c" would close the conversation and "r" reset it while
// the player was typing.
//
// Sessions register, not surfaces: what varies between a phone and a terminal is the
// renderer a session drives. REDscript has no closures, so the callback is a virtual method
// on an object, and the registry holds a list of them ordered most-recent-first.
//
// This file must compile WITHOUT BrowserExtension installed, which is why the registry lives
// here rather than next to the site.

module AiNpc

//
// Ordering and first-refusal are the only decisions here, extracted as pure functions over a
// plain array so they are assertable with no system, no widgets and no game: the self-tests
// run from a ScriptableService at game start, where no system exists yet. They return a new
// array rather than mutating one in place.

// De-duplicated first: registering a session twice MOVES it to the most-recent end instead
// of leaving two entries that both answer.
func AiNpcSessionsWith(sessions: array<ref<AiNpcChatSession>>, session: ref<AiNpcChatSession>) -> array<ref<AiNpcChatSession>> {
    let result = sessions;
    if !IsDefined(session) {
        return result;
    }
    ArrayRemove(result, session);
    ArrayPush(result, session);
    return result;
}

// By identity, never unconditionally: two hosts overlap for an instant when BEF builds a new
// page's listener before the old one's teardown has run, and removing the wrong element
// there silences a surface that is on screen.
func AiNpcSessionsWithout(sessions: array<ref<AiNpcChatSession>>, session: ref<AiNpcChatSession>) -> array<ref<AiNpcChatSession>> {
    let result = sessions;
    if IsDefined(session) {
        ArrayRemove(result, session);
    }
    return result;
}

// The surface the player opened last is the one they are looking at.
func AiNpcSessionsMostRecentFirst(sessions: array<ref<AiNpcChatSession>>) -> array<ref<AiNpcChatSession>> {
    let ordered: array<ref<AiNpcChatSession>>;
    let i = ArraySize(sessions) - 1;
    while i >= 0 {
        ArrayPush(ordered, sessions[i]);
        i -= 1;
    }
    return ordered;
}

// The thread the player is looking at, or "" when none is.
//
// The first session showing something, not simply the first: a surface registers while it can
// paint, which the terminal does from its contact list too -- a page with no thread open. Only
// the shown id can tell "a surface exists" from "a conversation is up".
func AiNpcShownContactId(ordered: array<ref<AiNpcChatSession>>) -> String {
    let count = ArraySize(ordered);
    let i = 0;
    while i < count {
        let shown = ordered[i].GetShownContactId();
        if NotEquals(StrLen(shown), 0) {
            return shown;
        }
        i += 1;
    }
    return "";
}

// False means nobody rendered it, which is the caller's cue to notify instead.
func AiNpcDeliverReply(ordered: array<ref<AiNpcChatSession>>, contactId: String, text: String,
                       channel: AiNpcChannelId) -> Bool {
    let count = ArraySize(ordered);
    let i = 0;
    while i < count {
        if ordered[i].Deliver(contactId, text, channel) {
            return true;
        }
        i += 1;
    }
    return false;
}

// A ScriptableSystem rather than a global: it exists only inside a game session, which is
// exactly the lifetime of anything that could be registered in it.
public class AiNpcChatSessionRegistry extends ScriptableSystem {

    // Strong references, released by each host in its own teardown (OnUninitialize for a
    // browser page, HideModChat for the phone). A wref's null would be indistinguishable
    // from "never registered".
    //
    // Order IS the data structure: last element = the surface the player opened last.
    private let m_sessions: array<ref<AiNpcChatSession>>;

    public static func Get() -> ref<AiNpcChatSessionRegistry> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcChatSessionRegistry>()) as AiNpcChatSessionRegistry;
    }

    public func Register(session: ref<AiNpcChatSession>) -> Void {
        if !IsDefined(session) {
            return;
        }
        this.m_sessions = AiNpcSessionsWith(this.m_sessions, session);
        AiNpcLog(s"Chat session registered (\(ArraySize(this.m_sessions)) active).");
    }

    public func Unregister(session: ref<AiNpcChatSession>) -> Void {
        if IsDefined(session) {
            this.m_sessions = AiNpcSessionsWithout(this.m_sessions, session);
            AiNpcLog(s"Chat session unregistered (\(ArraySize(this.m_sessions)) active).");
        }
    }

    public func All() -> array<ref<AiNpcChatSession>> {
        return this.m_sessions;
    }

    public func Current() -> ref<AiNpcChatSession> {
        let count = ArraySize(this.m_sessions);
        if count < 1 {
            return null;
        }
        return this.m_sessions[count - 1];
    }
}

// Empty outside a game session: the registry is a system, so it does not exist before one
// starts, and no caller should have to know that. Reversed here rather than at each call
// site, where iterating the raw array would silently give the opposite order.
func AiNpcChatSessions() -> array<ref<AiNpcChatSession>> {
    let empty: array<ref<AiNpcChatSession>>;
    let registry = AiNpcChatSessionRegistry.Get();
    if !IsDefined(registry) {
        return empty;
    }
    return AiNpcSessionsMostRecentFirst(registry.All());
}

func AiNpcGetChatSession() -> ref<AiNpcChatSession> {
    let registry = AiNpcChatSessionRegistry.Get();
    if !IsDefined(registry) {
        return null;
    }
    return registry.Current();
}

//
// The three signals the HTTP lane emits, so that the lane never holds a surface, a widget or
// an opinion about what is on screen. AiNpcPublishReply is the only one that answers.

func AiNpcPublishReply(contactId: String, text: String, channel: AiNpcChannelId) -> Bool {
    return AiNpcDeliverReply(AiNpcChatSessions(), contactId, text, channel);
}

func AiNpcPublishTyping(contactId: String, value: Bool, channel: AiNpcChannelId) -> Void {
    let sessions = AiNpcChatSessions();
    let count = ArraySize(sessions);
    let i = 0;
    while i < count {
        sessions[i].SetTypingIndicator(contactId, value, channel);
        i += 1;
    }
}

// Broadcast, not first refusal: every surface that can send greys its own control, including
// the one the player is not looking at.
func AiNpcPublishGenerating(value: Bool) -> Void {
    let sessions = AiNpcChatSessions();
    let count = ArraySize(sessions);
    let i = 0;
    while i < count {
        sessions[i].SetBusy(value);
        i += 1;
    }
}

// The contact is a parameter for the same reason it is one everywhere below the send: a
// reply belongs to whoever was asked, a network round trip ago, not to whoever is on screen.
func AiNpcChatSessionShows(contactId: String) -> Bool {
    if Equals(StrLen(contactId), 0) {
        return false;
    }
    let sessions = AiNpcChatSessions();
    let count = ArraySize(sessions);
    let i = 0;
    while i < count {
        if Equals(sessions[i].GetShownContactId(), contactId) {
            return true;
        }
        i += 1;
    }
    return false;
}
