// The phone chat, as a surface that paints.
//
// The model must not hold widgets: AiNpcSystem lives for the whole process while the phone
// tree is built and destroyed by the game, so a handle kept there is one every use site has
// to re-ask "is this still alive?" about. The answer is not a null check per site but one
// question asked once, at registration:
//
//     existence     this object knows where the phone tree is. Created when the walk in
//                   ResolveWidgets succeeds, dropped when it is redone.
//     registration  this object can paint a reply right now. Registered in ShowModChat once
//                   BuildChatUi has returned, unregistered in HideModChat before teardown.
//
// Separate because the tree is built in two stages, and a single lifetime would break
// ToggleContactList, which runs before the chat is on screen. Registration order is not
// arbitrary -- unregister before tearing down, register after building -- or a reply is
// handed to a renderer whose widgets are half gone.
//
// The model stays on AiNpcSystem: which contact is selected, whether the chat is open,
// typing, key bindings, Mod Settings and the vanilla phone controller. This file paints and
// knows nothing about why it was asked to.
//
// BuildChatUi is left whole: the ink tree it assembles is order-dependent, and every
// candidate seam through it splits a widget from the property that positions it.

module AiNpc

import Codeware.*
import Codeware.UI.*

// Sound belongs to the player object, not the widget tree, and both the model and the view
// need it. A free function, so the view holds no second opinion about how a sound is played.
func AiNpcPhonePlaySound(player: wref<PlayerPuppet>, sound: CName) -> Void {
    if IsDefined(player) {
        GameObject.PlaySoundEvent(player, sound);
    }
}

public class AiNpcPhoneChatRenderer extends AiNpcChatRenderer {

    // Handles to widgets this mod does not own the lifetime of, which is why they live behind
    // an object whose own lifetime is tied to theirs.
    private let parent: wref<inkCanvas>;
    private let contactListSlot: wref<inkCanvas>;
    private let chatContainer: wref<inkCanvas>;
    private let defaultChatUi: wref<inkCanvas>;
    private let messageParent: wref<inkVerticalPanel>;
    private let typedMessageText: wref<inkText>;
    private let typedMessageWrapper: wref<inkHorizontalPanel>;
    private let chatInputHint: wref<inkImage>;
    private let messengerSlotRoot: wref<inkCanvas>;
    private let chatScrollController: wref<inkScrollController>;
    private let typingIndicator: wref<inkFlex>;
    private let hintStrip: wref<inkHorizontalPanel>;

    // Pushed in by the model, never read back out of it: a view reaching for GetAiNpcSystem()
    // to ask who is selected would be the same disease in a new file.
    private let m_player: wref<PlayerPuppet>;
    private let m_phoneController: wref<NewHudPhoneGameController>;
    // What is shown and whether the player is typing are the session's: a renderer keeping its
    // own copy is how the phone and the terminal drifted apart.
    private let m_session: ref<AiNpcChatSession>;
    private let m_disabled: Bool = false;

    // -- Resolution -------------------------------------------------------------

    // True when the phone tree was found. Called on every rebuild of the phone HUD, not once
    // per session: the handles below are wrefs into a tree the game replaces, and a renderer
    // that resolved once would paint into widgets nobody is looking at.
    public func Resolve(player: wref<PlayerPuppet>) -> Bool {
        this.m_player = player;

        let tree = AiNpcResolvePhoneTree();
        this.parent = tree.parent;
        this.contactListSlot = tree.contactListSlot;
        this.defaultChatUi = tree.defaultChatUi;
        this.m_disabled = !tree.found;

        if !this.m_disabled {
            this.SetupChatContainer();
        }
        return !this.m_disabled;
    }

    // Handed in, never made here: a renderer that created its own would lose the conversation
    // every time the HUD was rebuilt.
    public func BindSession(session: ref<AiNpcChatSession>) -> Void {
        this.m_session = session;
    }

    public func GetSession() -> ref<AiNpcChatSession> {
        return this.m_session;
    }

    public func IsDisabled() -> Bool {
        return this.m_disabled;
    }

    public func HasContactList() -> Bool {
        return IsDefined(this.contactListSlot);
    }

    public func SetPhoneController(controller: wref<NewHudPhoneGameController>) -> Void {
        this.m_phoneController = controller;
    }

    // EnterChat and LeaveChat are the widget halves of ShowModChat and HideModChat. The model
    // keeps the state transitions; what is here only touches a widget.
    //
    // No contact parameter, on all three: the session already holds the thread -- the model
    // put it there through AiNpcChatDoor before calling any of these -- and taking it a second
    // time is how a repaint could disagree with what is open. Which is why RebuildPhoneView
    // can call EnterChat with nothing to hand it.

    public func EnterChat() -> Void {
        this.parent.ReorderChild(this.chatContainer, 12);
        this.parent.ReorderChild(this.defaultChatUi, 14);
        // Reordering is not hiding. sms_messenger_slot holds the game's own conversation view,
        // and opening our chat only moved it in the draw order, so a thread opened from the
        // messages tab stayed on screen underneath -- two conversation windows at once.
        // Hidden here and restored in LeaveChat, which every close path goes through.
        if IsDefined(this.defaultChatUi) {
            this.defaultChatUi.SetVisible(false);
        }
        this.BuildChatUi();
        if IsDefined(this.chatScrollController) {
            this.chatScrollController.SetScrollPosition(1.0);
        }
    }

    public func LeaveChat() -> Void {
        this.parent.ReorderChild(this.defaultChatUi, 12);
        this.parent.ReorderChild(this.chatContainer, 14);
        // Given back unconditionally, even if we did not hide it: an invisible vanilla
        // messenger is a state only this mod can produce, and leaving it so costs the player
        // the game's own conversations.
        if IsDefined(this.defaultChatUi) {
            this.defaultChatUi.SetVisible(true);
        }
        this.chatContainer.RemoveAllChildren();
    }

    // The player switched contact without closing: same widgets, different contents.
    public func ShowContact() -> Void {
        this.RefreshConversation();
        this.ShowThreadChoices();
    }

    // The choices of the thread on screen, asked of its contact each time it is shown.
    public func ShowThreadChoices() -> Void {
        if IsDefined(this.hintStrip) {
            AiNpcPhoneShowChoices(this.hintStrip, AiNpcThreadChoicesFor(this.m_session.GetShownContactId()));
        }
    }

    // -- Input, driven by the model's key handling ------------------------------

    public func SetTyping(value: Bool) -> Void {
        if value {
            this.m_session.BeginTyping();
        } else {
            this.m_session.EndTyping();
        }
    }

    // The resting label goes away and the real input widget takes the focus.
    public func BeginInput() -> Void {
        this.m_session.BeginTyping();
        this.typedMessageText.SetText(AiNpcStartTypingLabel(AiNpcResolveLanguage()));
        this.typedMessageText.SetVisible(false);
        this.chatInputHint.SetTexturePart(n"kb_enter");
        this.BuildInput();
    }

    public func ClearMessages() -> Void {
        if IsDefined(this.messageParent) {
            this.messageParent.RemoveAllChildren();
        }
    }

    public func Scroll(direction: Float) -> Void {
        if IsDefined(this.chatScrollController) {
            this.chatScrollController.Scroll(direction, true);
        }
    }

    // The four signals the HTTP lane publishes. Reachable only while registered, which is only
    // while the widgets exist -- that is the whole guarantee, and why none re-checks a handle.

    public func GetShownContactId() -> String {
        return this.m_session.GetShownContactId();
    }

    // Refuses anything addressed to a conversation this chat is not showing, as the terminal
    // does. Refusing is not a failure: it sends the reply on to the SMS notification.
    //
    // The thousand-character split lives here because it is a fact about this surface -- the
    // terminal wraps differently.


    // The dots are the one signal that also means "stop": a false is obeyed whoever it was
    // addressed to, because the generation it belonged to has ended either way.

    public func Clear() -> Void {
        this.ClearMessages();
    }

    public func AppendMessage(text: String, fromPlayer: Bool, animate: Bool) -> Void {
        this.BuildMessage(text, fromPlayer, animate);
    }

    public func SetTypingIndicator(value: Bool) -> Void {
        this.ToggleTypingIndicator(value);
    }

    public func ScrollToBottom() -> Void {
        if IsDefined(this.chatScrollController) {
            this.chatScrollController.SetScrollPosition(1.0);
        }
    }

    // Same threshold the terminal uses: a player reading back through a conversation must not
    // be yanked to the end by an arriving reply.
    public func IsAtBottom() -> Bool {
        if !IsDefined(this.chatScrollController) {
            return true;
        }
        return this.chatScrollController.position > 0.95;
    }

    // Two inkTexts, because a single one long enough overflows the bubble. The number belongs
    // to this surface, which is why the renderer is asked for it.
    public func SplitBudget() -> Int32 {
        return 1000;
    }

    // The phone scrolls, so it shows the whole thread.
    public func HistoryLimit() -> Int32 {
        return 0;
    }

    public func Alive() -> Bool {
        return !this.m_disabled && IsDefined(this.messageParent);
    }

    // The removal is unconditional and must stay so: Resolve runs on every rebuild of the phone
    // HUD, so a stale ainpc_chat_slot that survives even sometimes means a second one parented
    // beside it, and then a third.
    private func SetupChatContainer() {
        this.parent.RemoveChildByName(n"ainpc_chat_slot");

        let modMessengerSlot = new inkCanvas();
        modMessengerSlot.Reparent(this.parent);
        modMessengerSlot.SetMargin(new inkMargin(80.0, 480.0, 0.0, 0.0));
        modMessengerSlot.SetChildOrder(inkEChildOrder.Backward);
        modMessengerSlot.SetName(n"ainpc_chat_slot");

        this.chatContainer = modMessengerSlot;
    }

    // Walks three levels into the game's contact list, on every open and close. Every level is
    // checked, and the first ones matter most: checking only the last checks the step that
    // cannot fail on its own, from a line the walk never reaches if an earlier level was null.
    public func ToggleContactList(value: Bool) {
        AiNpcLog(s"Toggling contact list: \(value)");
        if !IsDefined(this.contactListSlot) {
            AiNpcLog("Contact list not found.");
            return;
        }
        let contactListRoot = this.contactListSlot.GetWidget(0) as inkCanvas;
        if !IsDefined(contactListRoot) {
            AiNpcLog("Contact list not found.");
            return;
        }
        let contactListContainer = contactListRoot.GetWidget(0) as inkCanvas;
        if !IsDefined(contactListContainer) {
            AiNpcLog("Contact list not found.");
            return;
        }
        let contactCentralContainer = contactListContainer.GetWidget(1) as inkVerticalPanel;
        if !IsDefined(contactCentralContainer) {
            AiNpcLog("Contact list not found.");
            return;
        }
        if value {
            AiNpcLog("Setting contact list to visible.");
            contactCentralContainer.SetVisible(true);
        } else {
            AiNpcLog("Setting contact list to invisible.");
            contactCentralContainer.SetVisible(false);
        }
    }

    // The player's text field, or null when there is none on screen. "Index 1" is not a
    // location but a question -- is the player typing right now? The HubTextInput is created
    // when they click to type and removed the moment they stop, so for most of a chat's life
    // there is nothing at that index, and asking positionally derefs null on the ordinary path.
    //
    // The input line is painted from a mode it is handed, never one it asks for: a renderer
    // that read the lane and its own typing flag would be deciding the state as well as
    // drawing it, and the other surface would decide the same thing separately.
    public func SetInputMode(mode: AiNpcInputMode) -> Void {
        // The strip follows the mode, because every key it names belongs to the reading
        // screen: while a field has the keyboard, the mod answers Enter and nothing else.
        // Left up, it promised four keys and a thread choice pressed there died in silence.
        if IsDefined(this.hintStrip) {
            this.hintStrip.SetVisible(NotEquals(mode, AiNpcInputMode.Typing));
        }
        if !IsDefined(this.typedMessageText) || !IsDefined(this.chatInputHint) {
            return;
        }
        if Equals(mode, AiNpcInputMode.Typing) {
            this.typedMessageText.SetOpacity(1);
            this.chatInputHint.SetOpacity(1);
            return;
        }

        // Resting and Disabled draw the same line at two opacities: the resting label with its
        // click hint, greyed out when the lane will refuse anyway.
        let opacity: Float = 1.0;
        if Equals(mode, AiNpcInputMode.Disabled) {
            opacity = 0.2;
        }
        AiNpcPhoneRemoveInput(this.typedMessageWrapper);
        this.typedMessageText.SetVisible(true);
        this.typedMessageText.SetText(AiNpcSendMessageLabel(AiNpcResolveLanguage()));
        this.typedMessageText.SetOpacity(opacity);
        this.chatInputHint.SetTexturePart(n"mouse_left");
        this.chatInputHint.SetOpacity(opacity);
    }

    private func BuildInput() {
        AiNpcPhoneBeginInput(this.typedMessageWrapper);
    }

    // What the player typed, or "" when there is no field on screen.
    public func GetInputText() -> String {
        return AiNpcPhoneGetInputText(this.typedMessageWrapper);
    }

    public func ToggleTypingIndicator(value: Bool) {
        if value {
            this.typingIndicator.SetVisible(!this.typingIndicator.IsVisible());
            if this.typingIndicator.IsVisible() {
                AiNpcPhonePlaySound(this.m_player, n"ui_messenger_typing");
            }
        } else {
            this.typingIndicator.SetVisible(false);
        }
    }

    // No scrolling here: whether the view follows a new message down is the session's decision,
    // taken before the message is painted.
    public func BuildMessage(text: String, fromPlayer: Bool, useAnim: Bool) {
        AiNpcPhoneBuildMessage(this.messageParent, this.m_player, text, fromPlayer, useAnim);
    }

    // Public because a conversation can change from outside the chat: another mod may append
    // while the player is looking at the thread, and without this the new message would appear
    // only after a close and reopen, which reads as a lost message.
    public func RefreshConversation() {
        this.FillFromStore();
    }

    // Fetching is this side's business -- a renderer may reach for a system, a session may not.
    // The window, the system marker and the split are the session's, so both surfaces get the
    // same answer to all three.
    private func FillFromStore() {
        if !IsDefined(this.messageParent) {
            return;
        }
        this.m_session.Fill(AiNpcStoredMessages(this.m_session.GetShownContactId()));
    }

    // Assembles the panel out of the six builders that draw it -- a frame, a header, a
    // scrolling list, a typing indicator, an input line, the key hints -- and keeps the
    // handles anything touches again.
    private func BuildChatUi() {
        AiNpcLog("Building chat UI...");

        let chrome = AiNpcPhoneBuildChrome(this.chatContainer,
                                           AiNpcGetCharacterName(this.m_session.GetShownContactId()));

        this.messengerSlotRoot = chrome.root;
        this.messageParent = chrome.messages;
        this.typingIndicator = chrome.typing;
        this.chatScrollController = chrome.scroll;
        this.typedMessageWrapper = chrome.input.wrapper;
        this.typedMessageText = chrome.input.label;
        this.chatInputHint = chrome.input.hint;
        this.hintStrip = chrome.hints;

        this.FillFromStore();
        this.ShowThreadChoices();

        chrome.root.PlayAnimation(AiNpcPhoneEntranceAnim());
    }
}
