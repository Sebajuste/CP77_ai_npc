// Where the player is inside the phone, and how they got there.
//
// The measured symptom this replaced: with a reply waiting, pressing D from the messages tab
// to the contacts tab opened the mod's chat by itself. The auto-open hung on a widget-spawn
// callback guarded by "am I on the contacts tab?", which is satisfied both when the player
// takes the phone out on contacts and when they switch tab to it -- a state cannot say where
// you came from. What was missing was a transition, not a condition.
//
// So this file names the states, names the edges between them, and is the only thing allowed
// to decide which edge just happened. A caller cannot write "on the contacts tab" and mean
// "just took the phone out": those are two values of two different types.
//
// Pure -- no widget, no system, no game instance -- so the self-tests cover it before any
// ScriptableSystem exists.
module AiNpc

// The screens this mod can distinguish. Not the game's PhoneScreenType, which knows nothing
// about the mod's chat -- a screen of its own from the player's point of view, since it covers
// the contact list and takes the input.
//
// Typing is a screen rather than a flag, because a flag beside a state is a second opinion
// about the same thing. "The chat is on screen" was once stored four times, which is sixteen
// combinations of which two are legal, and the fourteen illegal ones were all reachable. One
// variable makes "typing while the chat is closed" something nobody can write down.
public enum AiNpcPhoneScreen {
    Away = 0,
    Messages = 1,
    Contacts = 2,
    ModChat = 3,
    ModChatTyping = 4,
}

// Why a screen came up. Raised and TabSwitch end on the same screen and are not the same
// event, so no code branching on the destination alone can tell them apart. Rebuild is the
// common case -- the HUD redraws itself far more often than the player does anything -- so "a
// screen appeared" is by default not news.
public enum AiNpcPhoneEdge {
    None = 0,
    Raised = 1,
    TabSwitch = 2,
    Rebuild = 3,
}

public class AiNpcPhoneStateMachine {
    private let m_screen: AiNpcPhoneScreen = AiNpcPhoneScreen.Away;

    // Set by the tab key, consumed by the screen it produces. A latch rather than a boolean
    // about the present, because the two events arrive separately: SelectOtherTab() fires on
    // the keypress, the dialer reports its screen once it has finished spawning.
    private let m_tabSwitchPending: Bool = false;

    // The last contact row the dialer reported, verbatim -- not the hovered one.
    // RefreshInputHints is a list-refresh callback, and gamelog.3.log (2026-03-20) shows it
    // replayed over 22 contacts in two seconds when the contacts screen comes back. It is the
    // hovered row whenever the player has moved the selection, and the last populated one
    // before that.
    private let m_reportedRow: String = "";

    // The screen the chat was drawn over, and the one closing gives back. The chat covers
    // another screen, so "where does closing land?" has an answer only the open knows. Storing
    // it at the open lets the chat be opened from anywhere without the close guessing.
    private let m_returnScreen: AiNpcPhoneScreen = AiNpcPhoneScreen.Contacts;

    public func GetScreen() -> AiNpcPhoneScreen {
        return this.m_screen;
    }

    // Whether the contact list is the screen underneath -- it is up, or our chat is over it.
    //
    // The T key's precondition and nothing else's: T means "open the row I am pointing at", and
    // there are only rows to point at here. It was the chat's gate too until 2026-08-26, when
    // two routes to the same reply button on the same contact differed only by which tab the
    // phone had last reported. The surface's own question now lives in OpenChat.
    //
    // A field read rather than a walk of every ink layer, and true across the chat, so T stays
    // inert while it is up.
    public func IsOnContacts() -> Bool {
        return Equals(this.m_screen, AiNpcPhoneScreen.Contacts) || this.IsChatOpen();
    }

    // Derived, never stored: the accessor that replaced AiNpcSystem.chatOpen, so there is no
    // second field able to disagree with it.
    public func IsChatOpen() -> Bool {
        return Equals(this.m_screen, AiNpcPhoneScreen.ModChat)
            || Equals(this.m_screen, AiNpcPhoneScreen.ModChatTyping);
    }

    public func IsTyping() -> Bool {
        return Equals(this.m_screen, AiNpcPhoneScreen.ModChatTyping);
    }

    public func GetReportedRow() -> String {
        return this.m_reportedRow;
    }

    // Which tab they land on is not known yet and is not asked: the screen that follows says.
    public func OnTabSwitchRequested() -> Void {
        this.m_tabSwitchPending = true;
    }

    // A phone screen finished building; returns the edge that produced it. The order of the
    // tests is the specification:
    //
    //   1. our chat is on top -> whatever was redrawn underneath is not a navigation
    //   2. a tab switch is armed -> the player pressed Q or D. Before the Away test, because a
    //      keypress is something the player did and Away is only something this mod believed.
    //      The phone raised on the messages tab is the case that decides it: the contacts
    //      dialer reports nothing there, so the state is still Away when D arrives.
    //   3. we were Away -> the player took the phone out
    //   4. otherwise -> the HUD redrew itself
    public func OnScreenShown(screen: AiNpcPhoneScreen) -> AiNpcPhoneEdge {
        // The chat covers the contact list and the game keeps rebuilding the tree beneath it,
        // none of which is the player going anywhere. Swallowing them here stops a redraw
        // being read as a navigation and closing the chat.
        if this.IsChatOpen() {
            this.m_tabSwitchPending = false;
            return AiNpcPhoneEdge.Rebuild;
        }

        let edge: AiNpcPhoneEdge;
        if this.m_tabSwitchPending {
            edge = AiNpcPhoneEdge.TabSwitch;
        } else {
            if Equals(this.m_screen, AiNpcPhoneScreen.Away) {
                edge = AiNpcPhoneEdge.Raised;
            } else {
                edge = AiNpcPhoneEdge.Rebuild;
            }
        }

        this.m_tabSwitchPending = false;

        // The reported row belongs to the contact list, so it dies with it.
        if NotEquals(screen, AiNpcPhoneScreen.Contacts) {
            this.m_reportedRow = "";
        }

        this.m_screen = screen;
        return edge;
    }

    // Accepted unconditionally: gating it on the screen would make T's availability depend on
    // whether the dialer reports its rows before or after its screen, an ordering inside the
    // game's controller this mod cannot see. T is gated once, at the press.
    public func OnRowReported(contactId: String) -> Void {
        this.m_reportedRow = contactId;
    }

    // The game's own messenger took the screen.
    public func OnThreadOpened() -> Void {
        this.m_reportedRow = "";
        this.m_screen = AiNpcPhoneScreen.Messages;
    }

    // Anything but Messages is remembered as Contacts, Away included: the phone can be out on
    // the messages tab without this machine hearing a screen report, so Away means "I was not
    // told" rather than "the phone is gone". Giving that back on close would make the next
    // redraw read as the player taking the phone out again.
    public func OnChatOpened() -> Void {
        if Equals(this.m_screen, AiNpcPhoneScreen.Messages) {
            this.m_returnScreen = AiNpcPhoneScreen.Messages;
        } else {
            this.m_returnScreen = AiNpcPhoneScreen.Contacts;
        }
        this.m_screen = AiNpcPhoneScreen.ModChat;
    }

    // Gives back the screen the chat covered. Never Away: the phone is still out, and saying
    // otherwise would make the next redraw look like the player taking it out again.
    //
    // Closes from the typing screen too, which is the point of typing being a screen: nothing
    // has to remember to clear a flag on every close path.
    public func OnChatClosed() -> Void {
        if this.IsChatOpen() {
            this.m_screen = this.m_returnScreen;
        }
    }

    // Reachable only from the chat, in both directions, and enforced here rather than asked of
    // the caller: typing outside a chat has no input line to feed.
    public func OnTypingChanged(typing: Bool) -> Void {
        if !this.IsChatOpen() {
            return;
        }
        if typing {
            this.m_screen = AiNpcPhoneScreen.ModChatTyping;
        } else {
            this.m_screen = AiNpcPhoneScreen.ModChat;
        }
    }

    // Everything true about a screen stops being true here, the armed tab switch included: a
    // keypress that never produced a screen is stale, and carrying it over would turn the next
    // Raised into a TabSwitch.
    public func OnPhoneHidden() -> Void {
        this.m_screen = AiNpcPhoneScreen.Away;
        this.m_tabSwitchPending = false;
        this.m_reportedRow = "";
        // The screen a future chat would give back is a screen of THIS trip through the phone.
        this.m_returnScreen = AiNpcPhoneScreen.Contacts;
    }
}
