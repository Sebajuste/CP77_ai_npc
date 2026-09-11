module AiNpc

import Codeware.*
import Codeware.UI.*
import RedFileSystem.*
import RedData.Json.*

public class AiNpcSystem extends ScriptableService {
    private let initialized: Bool = false;
    private let callbackSystem: wref<CallbackSystem>;
    private let npcSelected: Bool = false;
    private let defaultPhoneController: wref<NewHudPhoneGameController>;

    // The painter. Holds every widget handle this mod takes and is the only way to reach one,
    // so a widget cannot be dereferenced without going through something whose existence
    // means the tree was found. See AiNpcPhoneRenderer.reds.
    private let m_phoneView: ref<AiNpcPhoneChatRenderer>;

    // The conversation, which outlives the renderer above: a renderer holds wrefs into a tree
    // the game replaces, a session holds a contact id and two flags. The renderer is rebuilt
    // with the phone HUD, the session is not.
    private let m_phoneSession: ref<AiNpcChatSession>;
    private let player: wref<PlayerPuppet>;

    // Where the player is in the phone, and how they got there. See AiNpcPhoneState.reds.
    private let m_phoneState: ref<AiNpcPhoneStateMachine>;

    // A back press the mod has already answered, waiting for the game's half of it. One press
    // of C reaches the mod twice, from two lanes with no order between them: raw input
    // (OnKeyInput) and the phone controller's action handler (ReportPhoneAction). Whichever
    // arrives first closes the chat; this tells the second one the press is spent.
    //
    // Cleared on the release of that press, when the contacts screen goes away, and at every
    // initialisation. Worst case if it sticks: one press of C on the contact list is eaten --
    // preferred over a phone that cannot be put away at all.
    private let m_backKeyPending: Bool = false;

    public let vanillaPhoneController: wref<PhoneDialerLogicController>;

    // Built on first use, not in InitializeSystem: the phone hooks can fire before the player
    // has finished spawning, and a report arriving before the machine exists would be dropped.
    private func PhoneState() -> ref<AiNpcPhoneStateMachine> {
        if !IsDefined(this.m_phoneState) {
            this.m_phoneState = new AiNpcPhoneStateMachine();
        }
        return this.m_phoneState;
    }

    // What the mod has borrowed from the vanilla phone, and the only thing allowed to give it
    // back. The machine says which screen, the claim says what is on loan.
    private let m_phoneClaim: ref<AiNpcPhoneClaim>;

    private func PhoneClaim() -> ref<AiNpcPhoneClaim> {
        if !IsDefined(this.m_phoneClaim) {
            this.m_phoneClaim = new AiNpcPhoneClaim();
        }
        return this.m_phoneClaim;
    }

    // A conversation asked for from an SMS notification, waiting for the contact list that can
    // show it -- the only state in the mod describing a screen that does not exist yet.
    private let m_openIntent: ref<AiNpcPhoneOpenIntent>;

    private func OpenIntent() -> ref<AiNpcPhoneOpenIntent> {
        if !IsDefined(this.m_openIntent) {
            this.m_openIntent = new AiNpcPhoneOpenIntent();
        }
        return this.m_openIntent;
    }
    
    // The conversation the phone has open, kept in the session and nowhere else.
    //
    // It used to be a field here as well, written through a SetContact this class then
    // disagreed with itself about: SendTyped read the session, ResetConversation and
    // UndoMessage read the field, and Close() empties one of the two. Nothing in the language
    // decides which of two copies a new call site takes.
    //
    // Empty outside a chat, which is a different answer from AiNpcCurrentContactId(): this one
    // is about the phone, and the seed API needs that distinction to tell "already there" from
    // "the terminal is showing something else".
    public func GetContactId() -> String {
        if !IsDefined(this.m_phoneSession) {
            return "";
        }
        return this.m_phoneSession.GetShownContactId();
    }

    private cb func OnReload() {
        AiNpcLog("Reloading ai_npc...");
        this.initialized = false;
        this.InitializeSystem();
    }

    // Input callbacks, the phone controller and a fresh renderer, none of which survive a
    // player spawn. Runs on every spawn, which includes every save load.
    private func InitializeSystem() {
        this.player = GetPlayer(GetGameInstance());
        this.npcSelected = false;
        this.m_backKeyPending = false;
        // The phone is not out at a spawn, including a save loaded with the chat on screen.
        // Left alone, the machine would still say ModChat and swallow the next screen report
        // as a redraw under a chat that no longer exists.
        this.PhoneState().OnPhoneHidden();
        this.callbackSystem = GameInstance.GetCallbackSystem();
        this.ListenKeys(false);
        this.callbackSystem.UnregisterCallback(n"Input/Axis", this, n"OnAxisInput");
        // Rebuilt from scratch every initialisation: a view carries handles into a widget tree
        // that no longer exists once the phone is rebuilt.
        //
        // Any previous one is unregistered first. Loading a save with the chat open never
        // reaches HideModChat, so nothing else would take that view out of the registry: it
        // would keep claiming its contact and answer the next reply with `true` on dead
        // widgets -- no bubble drawn, notification suppressed, reply lost. Registration means
        // "I can paint right now", so anything that invalidates the widgets has to end it.
        let registry = AiNpcChatSessionRegistry.Get();
        if IsDefined(registry) && IsDefined(this.m_phoneSession) {
            registry.Unregister(this.m_phoneSession);
        }
        // Made once per game session and kept. Everything that can go stale is on the other
        // side of BindSession.
        if !IsDefined(this.m_phoneSession) {
            this.m_phoneSession = new AiNpcChatSession();
        }
        this.RebuildPhoneView();
        this.InitializeDefaultPhoneController();
        this.initialized = true;
        GetAiNpcHttpSystem().ToggleIsGenerating(false);
        // Logged because the detection is silent by design: if the pronouns come out wrong,
        // this is the line that says what the game answered about V's body.
        AiNpcLog(s"Player gender: \(AiNpcResolveGender())");
        // Same reasoning for the language: the mapping is silent, so the log is what says
        // which locale the game answered and what the mod made of it -- an unmapped locale
        // reads as English, and that is indistinguishable from a failure without this line.
        AiNpcLog(s"Reply language: \(AiNpcResolveLanguage()) (game: \(AiNpcGameTextLanguage()))");
        // Same reason again: four settings that default to silence are impossible to tell
        // apart from a setting that failed to load, and this is the line that says which.
        AiNpcLog(s"Player description: \(AiNpcPlayerDescription())");
        // The budget in force, not the field: they differ whenever a stale value falls outside
        // the slider's range, and the character is given the one in force.
        AiNpcLog(s"Memory: \(AiNpcMemoryEnabled()) (budget: \(AiNpcMemoryFactBudget()) facts)");
        // Only when the two disagree: a player who wrote memoryEnabled:false in settings.json
        // and sees memory running is owed the reason, which is that the switch moved.
        if AiNpcLegacyMemoryDisabled() && AiNpcMemoryEnabled() {
            AiNpcLog("settings.json still says memoryEnabled:false -- that key is no longer read. " +
                     "Memory is now Mod Settings -> AI NPC -> Memory. Delete the key to silence this.");
        }
        // A character writing first looks like a bug from the player's side, so a report
        // saying "she texted me out of nowhere" needs this line to say whether it was on.
        AiNpcLog(s"Characters may write first: \(AiNpcUnpromptedEnabled())");
        AiNpcLog("ai_npc initialized");
    }


    // Asked of the game's blackboard rather than of a flag of ours: the game can put the
    // phone away without telling this mod.
    private func IsVanillaPhoneActive() -> Bool {
        let blackboardSystem = GameInstance.GetBlackboardSystem(GetGameInstance());
        let blackboard = blackboardSystem.Get(GetAllBlackboardDefs().UI_ComDevice);
        return blackboard.GetBool(GetAllBlackboardDefs().UI_ComDevice.ContactsActive);
    }

    // The keyboard, in one place: listened to only while the chat is on screen, which is the
    // only time there is a text field to feed. Everything else opens through the phone's own
    // keys.
    private func ListenKeys(listening: Bool) -> Void {
        if !IsDefined(this.callbackSystem) {
            return;
        }
        this.callbackSystem.UnregisterCallback(n"Input/Key", this, n"OnKeyInput");
        if listening {
            this.callbackSystem.RegisterCallback(n"Input/Key", this, n"OnKeyInput", true);
        }
    }

    // Keys are dispatched on the screen, never reconstructed from flags: the handler asks the
    // screen once and routes, so a key belonging to one screen cannot fire on another.
    private cb func OnKeyInput(event: ref<KeyInputEvent>) {
        AiNpcKeyTraceEngine(event);

        if NotEquals(s"\(event.GetAction())", "IACT_Press") {
            return;
        }

        let key = s"\(event.GetKey())";

        // Escape always opens the hub menu -- the mod cannot swallow it -- so the chat comes
        // down on the press itself. MenuHubLogicController.SetActive does not fire from the
        // phone, and relying on it leaves the chat on screen and unclosable. Outside the
        // dispatch because it means the same on every screen, and CloseChat is a no-op where
        // there is nothing to close.
        if Equals(key, "IK_Escape") {
            this.CloseChat();
            return;
        }

        switch this.PhoneState().GetScreen() {
            case AiNpcPhoneScreen.ModChatTyping:
                this.OnTypingKey(key);
                break;
            case AiNpcPhoneScreen.ModChat:
                this.OnChatKey(key);
                break;
            default:
                break;
        }
    }

    // The keyboard belongs to the input line.
    private func OnTypingKey(key: String) -> Void {
        if Equals(key, "IK_Enter") {
            let typed = this.m_phoneView.GetInputText();
            this.PhoneState().OnTypingChanged(false);
            this.m_phoneView.SetTyping(false);
            this.SendTyped(typed);
            return;
        }
        this.PlaySound(n"ui_menu_mouse_click");
    }

    // The chat is up and the player is reading it.
    private func OnChatKey(key: String) -> Void {
        // C is back, not close: one screen up, onto the contact list. This lane and the action
        // handler both answer the same press, and both write the note before closing so the
        // other recognises it as spent.
        if Equals(key, "IK_C") {
            this.m_backKeyPending = true;
            this.CloseChat();
            return;
        }
        if Equals(key, "IK_R") {
            this.ResetConversation(true);
            return;
        }
        // Z exists only with Debug Mode on, and the hint strip is drawn from the same answer,
        // so out of debug there is no key and no glyph promising one.
        if Equals(key, "IK_Z") && AiNpcUndoAvailable() {
            this.UndoMessage();
            return;
        }
        if Equals(key, "IK_LeftMouse") {
            // The one refusal that is not about the screen: a reply is in flight. A fact about
            // the request lane, not about where the player is.
            if GetAiNpcHttpSystem().GetIsGenerating() {
                return;
            }
            this.PhoneState().OnTypingChanged(true);
            this.m_phoneView.BeginInput();
        }
    }

    // Handle scrolling messages
    private cb func OnAxisInput(event: ref<AxisInputEvent>) {
        if Equals(s"\(event.GetKey())", "IK_MouseZ") {
            if Equals(event.GetValue(), 1.0) {
                this.m_phoneView.Scroll(1.0);
            } else if Equals(event.GetValue(), -1.0) {
                this.m_phoneView.Scroll(-1.0);
            }
        }
    }

    // The player's half of a turn. Echoing V's line, ending the typing state and scrolling
    // down are the session's; what is left here is the lane call, because the session may not
    // reach for a system (see the head of AiNpcChatSession).
    //
    // Sending from inside the widget builder instead welds "draw V's bubble" to "ask the
    // model", and replaying a history would then re-send the whole thread.
    private func SendTyped(message: String) {
        let session = this.m_phoneSession;
        if !IsDefined(session) {
            return;
        }

        // La sequence -- lire le contact, echo, appeler la voie, classer -- appartient au
        // canal, qui l'ecrit une fois pour toutes les surfaces. Le telephone dit seulement par
        // quel medium il parle.
        AiNpcChannelOf(AiNpcChannelId.Text).Send(session, message);
    }

    private func ResetConversation(playSound: Bool) {
        AiNpcResetConversation(this.GetContactId());
        this.m_phoneView.ClearMessages();
        if playSound {
            this.PlaySound(n"ui_menu_map_pin_off");
        }
    }

    // The widget list is rebuilt from the history rather than popping a fixed number of
    // widgets: one long reply renders as two bubbles.
    private func UndoMessage() {
        let contactId = this.GetContactId();
        // Bound to locals: ArraySize on a call result reads the wrong stack slot, so the
        // comparison below never detected the removal.
        let historyBefore = AiNpcStoredMessages(contactId);
        let before = ArraySize(historyBefore);
        AiNpcUndoMessage(contactId);

        let historyAfter = AiNpcStoredMessages(contactId);
        if ArraySize(historyAfter) < before {
            this.m_phoneView.RefreshConversation();
            this.PlaySound(n"ui_menu_map_pin_off");
        }
    }

    public func ToggleNpcSelected(value: Bool) {
        if !this.initialized {
            this.InitializeSystem();
        } 

        // Bookkeeping only: deciding bindings here would put a hover-driven flag in charge of
        // whether the opening key exists. Bindings follow the chat's lifetime instead.
        this.npcSelected = value;
    }
    

    // The screen changes -- the machine refuses outright when no chat is up -- and the view is
    // told so it can redraw its input line. Pushed into the view, never pulled: a view asking
    // the system what it should look like is the ambient read this split exists to remove.
    public func ToggleIsTyping(value: Bool) {
        this.PhoneState().OnTypingChanged(value);
        if IsDefined(this.m_phoneView) {
            this.m_phoneView.SetTyping(this.PhoneState().IsTyping());
        }
    }

    /// What the phone reported ///
    //
    // Every hook in AiNpcHooks.reds lands in exactly one of these. A hook fires on the game's
    // schedule and knows only that widgets moved, so it cannot tell "the player did something"
    // from "the HUD redrew". This side owns the state machine that can, and acts.

    // Includes every save load.
    public func ReportPlayerSpawned() -> Void {
        if GameInstance.GetSystemRequestsHandler().IsPreGame() {
            return;
        }
        this.InitializeSystem();
    }

    // Which tab they land on is the business of the screen report that follows.
    public func ReportTabSwitch() -> Void {
        this.PhoneState().OnTabSwitchRequested();
    }

    // The tab is read here from the controller rather than passed by the hook, which fires on
    // the dialer. Read at the moment the screen changes, "which tab is up" becomes a field.
    //
    // An unresolvable controller answers Contacts, the permissive direction: an unknown tab
    // must not leave T dead with nothing in the log.
    public func ReportPhoneScreen() -> Void {
        if !IsDefined(this.defaultPhoneController) {
            this.InitializeDefaultPhoneController();
        }

        let screen = AiNpcPhoneScreen.Contacts;
        if IsDefined(this.defaultPhoneController) {
            screen = this.defaultPhoneController.AiNpcScreen();
        }

        let edge = this.PhoneState().OnScreenShown(screen);

        // Rebuild is the common case -- the HUD redraws constantly -- and logging it would
        // bury the two lines worth reading.
        if NotEquals(edge, AiNpcPhoneEdge.Rebuild) {
            AiNpcLog(s"Phone screen: \(screen) (\(edge)).");
        }

        // The phone the notification key was waiting for: a screen finished building, so the
        // phone is out, which is all the chat needs on any tab.
        //
        // The one place where a screen event leads to an open. Unlike the auto-open that was
        // removed, the intention is not inferred from the event -- it was recorded when the
        // player pressed the key, and the event only says "now".
        if this.OpenIntent().IsArmed() {
            this.OpenChat(this.OpenIntent().Take(), "a message notification");
        }
    }

    // The phone's messages key on a row. True when the mod's chat opens instead of the game's
    // messenger: the mod's own conversation, or a character with none of the game's.
    public func ReportMessagesAction(row: wref<ContactData>) -> Bool {
        if !AiNpcOpensModChat(row) {
            return false;
        }
        this.OpenChat(row.contactId, "the phone's messages");
        return true;
    }

    // The phone HUD was rebuilt underneath us, so every widget handle the mod holds is stale.
    public func ReportPhoneTreeRebuilt() -> Void {
        this.RebuildPhoneView();
    }

    // The contacts screen going away is not the phone going away, and the dialer's Hide()
    // fires for both. The com device blackboard is the one thing that knows which it was: read
    // wrong in the "still out" direction, the next redraw reads as the player raising the
    // phone again.
    public func ReportContactsScreenHidden() -> Void {
        // A pending back note was never acted on: the close it was meant to refuse took
        // another route. Dropped here rather than left to expire, since it would otherwise eat
        // the player's next C on the contact list.
        this.m_backKeyPending = false;

        this.CloseChat();

        if this.IsVanillaPhoneActive() {
            this.PhoneState().OnScreenShown(AiNpcPhoneScreen.Messages);
        } else {
            // The line that separates "changed tab" from "the phone left" in the log.
            AiNpcLog("Contacts screen hidden and the phone is no longer active: the phone went away.");
            this.PhoneState().OnPhoneHidden();

            // A notification the player asked to open, on a phone that is now away, was
            // answered by something else. Kept, it would open a chat by itself the next time
            // the phone comes out.
            this.OpenIntent().Drop();
        }
    }

    // The game is about to put the phone away. Answers whether it should not.
    //
    // The screen is asked as well as the note, because the two lanes carry no order between
    // them: refusing on m_backKeyPending alone assumes the mod reads the press before the game
    // acts on it, and that did not hold in play. If the mod's chat is what the player is
    // looking at, C means back either way.
    //
    // The cost: a close the mod did not cause -- combat, a quest, the phone being disabled --
    // is also refused while the chat is up. It costs one press, since the chat comes down here.
    public func ReportPhoneCloseRequested(source: String) -> Bool {
        // Read, not consumed: the action lane ends the note, on the release of that press.
        let mine = this.m_backKeyPending || this.PhoneState().IsChatOpen();

        // Logged on both answers: a press that closes the phone with no line here took a path
        // nothing hooks.
        if mine {
            AiNpcLog(s"Phone close from \(source) refused: C on the chat is a back, not a close.");
            this.CloseChat();
        } else {
            AiNpcLog(s"Phone close from \(source): not ours, passed through.");
        }
        return mine;
    }

    // Where C stops being a close and becomes a back: the handler that receives the action and
    // a consumer, which is where the game decides the same question for its own screens.
    public func ReportPhoneAction(action: CName, kind: gameinputActionType) -> Bool {
        // Every action is logged while the chat is up: the name C carries here is not readable
        // offline, so the log is what names it.
        if this.PhoneState().IsChatOpen() {
            AiNpcLog(s"Phone action while the chat is open: \(action) (\(kind)).");
        }

        if !this.IsPhoneBackAction(action) {
            return false;
        }

        // Swallowed whole: the game never sees it, and the phone stays out on the contact list.
        if this.PhoneState().IsChatOpen() {
            if Equals(kind, gameinputActionType.BUTTON_PRESSED) {
                AiNpcLog(s"'\(action)' taken as back: closing the chat, keeping the phone out.");
                this.m_backKeyPending = true;
                this.CloseChat();
            }
            return true;
        }

        // Already closed by the other lane reading this same press. The release clears the note.
        if this.m_backKeyPending {
            if NotEquals(kind, gameinputActionType.BUTTON_PRESSED) {
                this.m_backKeyPending = false;
            }
            return true;
        }

        return false;
    }

    // A list, because the name C carries is not knowable offline. Each one is refused only
    // while the mod's own chat is the screen being left.
    private func IsPhoneBackAction(action: CName) -> Bool {
        return Equals(action, n"UI_Cancel")
            || Equals(action, n"cancel")
            || Equals(action, n"back")
            || Equals(action, n"UI_Exit")
            || Equals(action, n"OpenPhone")
            || Equals(action, n"TogglePhone")
            || Equals(action, n"HidePhone");
    }

    public func ReportThreadOpened() -> Void {
        this.PhoneState().OnThreadOpened();
    }

    // Another menu took over -- usually Escape opening the hub. This must restore the phone,
    // not just hide the chat widget: hiding alone leaves it on screen and unclosable.
    public func ReportMenuTookOver() -> Void {
        this.CloseChat();
    }

    // Entering combat with the chat open used to leave the phone input-disabled behind it.
    public func ReportCombatState(newState: Int32) -> Void {
        if Equals(newState, 1) {
            this.CloseChat();
        }
    }

    /// The chat's one door ///
    //
    // Opening the chat is three things -- borrow the phone, draw the panel, take the keyboard
    // -- and closing it is the same three undone. One door each, both private, with the
    // reasons to refuse in the door rather than in its callers: AiNpcSeed's public API goes
    // through the same door as the phone, so an external caller cannot reach a state the
    // player could not.

    // Answers whether the chat is now on screen. Every branch before the transition is a
    // reason not to open and none of them writes state: a refusal that wrote state would leave
    // the mod believing in a chat that was never drawn, and only a reload would clear it.
    private func OpenChat(contactId: String, reason: String) -> Bool {
        if this.PhoneUnavailable() {
            AiNpcLog(s"\(reason) blocked: there is no usable phone tree.");
            return false;
        }
        if this.PhoneState().IsChatOpen() {
            return true;
        }

        // The only gate: is there a phone to draw on? Drawing the chat needs a phone that is
        // out and a tree that can be borrowed, nothing more -- EnterChat hides the game's
        // messenger slot and LeaveChat restores it, so covering a vanilla thread is supported.
        //
        // Asked of the com device blackboard, not of this mod's state: the machine can read
        // Away while the phone is out on the messages tab, where the contacts dialer never
        // builds and nothing reports a screen.
        if !this.IsVanillaPhoneActive() {
            AiNpcLog(s"\(reason) blocked: the phone is not out.");
            return false;
        }
        if Equals(StrLen(contactId), 0) {
            AiNpcLog(s"\(reason): no contact reported by the phone, nothing to open.");
            return false;
        }
        if !AiNpcIsContactSupported(contactId) {
            AiNpcLog(s"\(reason) blocked: contact '\(contactId)' is not supported.");
            return false;
        }

        // The borrow comes first and its failure is a refusal: a chat drawn without the phone's
        // contact input disabled leaves the arrow keys moving a list nobody can see.
        if !this.PhoneClaim().Take(this.defaultPhoneController, this.m_phoneView) {
            this.InitializeDefaultPhoneController();
            if !this.PhoneClaim().Take(this.defaultPhoneController, this.m_phoneView) {
                AiNpcLog(s"\(reason) blocked: the phone could not be claimed (controller or contact list missing).");
                return false;
            }
        }

        AiNpcLog(s"Chat opened by: \(reason), on '\(contactId)'.");
        this.ToggleNpcSelected(true);
        this.ShowModChat(contactId);
        return true;
    }

    // The way out, and total by construction. The claim owns the other two undos and is
    // idempotent, so every close path -- C, Escape, the hub menu, combat, the phone being put
    // away -- can call this without knowing whether it is the one that closed anything.
    private func CloseChat() -> Void {
        if !this.PhoneState().IsChatOpen() && !this.PhoneClaim().IsHeld() {
            return;
        }

        this.PhoneClaim().Release(this.defaultPhoneController, this.m_phoneView);
        this.HideModChat();
        this.ToggleNpcSelected(false);
    }

    // Draw the panel and take the keyboard. Reachable only from OpenChat, which makes "drawn
    // without the phone borrowed" unwritable.
    private func ShowModChat(contactId: String) {
        this.PhoneState().OnChatOpened();

        // Before the widgets, because they are painted from the session: the door is what puts
        // the thread there, and announcing it is the same act.
        AiNpcOpenConversation(this.m_phoneSession, contactId);

        this.m_phoneView.EnterChat();
        // Registered only once the widgets exist: until this runs, nothing can ask this
        // surface to paint.
        let registry = AiNpcChatSessionRegistry.Get();
        if IsDefined(registry) {
            registry.Register(this.m_phoneSession);
        }
        this.PlaySound(n"ui_menu_map_pin_created");
        // Typing needs every key, and the wheel belongs to the message list. Both are given
        // back in HideModChat, whatever closes the chat.
        this.ListenKeys(true);
        this.callbackSystem.UnregisterCallback(n"Input/Axis", this, n"OnAxisInput");
        this.callbackSystem.RegisterCallback(n"Input/Axis", this, n"OnAxisInput", true);
    }

    // Take the panel away and give the keyboard back. Reachable only from CloseChat.
    private func HideModChat() {
        // Unregistered before anything is torn down: a reply landing in between would be
        // handed to a view whose widgets are half gone. Order is the guarantee, not a null
        // check.
        let registry = AiNpcChatSessionRegistry.Get();
        if IsDefined(registry) {
            registry.Unregister(this.m_phoneSession);
        }
        if IsDefined(this.m_phoneView) {
            this.m_phoneView.LeaveChat();
        }

        this.PhoneState().OnChatClosed();

        // The "was it open" guard the announcement used to need is the door's now, and it
        // guards on the thread rather than on the screen: a close with nothing shown announces
        // nothing, whatever the state machine believed.
        AiNpcCloseConversation(this.m_phoneSession);

        // The single point where the input goes back to its resting shape: every close path
        // reaches here through CloseChat, so none can leave the all-keys binding on. Typing
        // was a screen, and the screen just changed.
        this.ListenKeys(false);
        this.callbackSystem.UnregisterCallback(n"Input/Axis", this, n"OnAxisInput");
    }

    // The public door, for the API in AiNpcSeed.reds. Same door as the phone, same refusals.
    public func OpenChatFor(contactId: String, reason: String) -> Bool {
        return this.OpenChat(contactId, reason);
    }

    // The two writes are one operation: selecting without repainting leaves the chat showing a
    // thread that is no longer selected, and the next reply lands in the wrong conversation.
    // Only reachable with a chat already open; opening is OpenChat's job.
    //
    // Through the door like every other opening, which is what makes a switch a pair of events
    // instead of the silence it was: the old thread closes, the new one opens, and the memory
    // service gets the second one.
    public func SwitchChatTo(contactId: String) -> Void {
        if !AiNpcOpenConversation(this.m_phoneSession, contactId) {
            return;
        }
        let view = this.GetPhoneView();
        if IsDefined(view) {
            view.ShowContact();
        }
    }

    // Answers whether the conversation is now on screen. Three cases:
    //
    //   the chat is up     on somebody else -- a notification is only pushed when no surface
    //                      painted the reply. Swap, do not reopen.
    //   the phone is out   open now, and answer true so the caller does not move the phone.
    //   the phone is away  leave the note, answer false; the caller raises the phone and
    //                      ReportPhoneScreen finds the note on the way up.
    //
    // The middle case is asked by calling the door, never by re-deriving its conditions here.
    public func RequestChatFromNotification(contactId: String) -> Bool {
        if this.PhoneState().IsChatOpen() {
            if Equals(this.GetContactId(), contactId) {
                return true;
            }
            this.SwitchChatTo(contactId);
            AiNpcLog(s"A message notification switched the open chat to '\(contactId)'.");
            return true;
        }

        if this.OpenChat(contactId, "a message notification") {
            return true;
        }

        this.OpenIntent().Arm(contactId);
        AiNpcLog(s"A message notification asked for '\(contactId)'; waiting for a contact list.");
        return false;
    }

    // For the paths outside this file that end a chat.
    public func ForceCloseChat() -> Void {
        this.CloseChat();
    }


    // A fresh renderer against the tree as it is now. Called at spawn and on every rebuild of
    // the phone HUD: resolving once per session leaves wrefs pointing at widgets that stopped
    // existing when the HUD was rebuilt.
    //
    // The previous renderer is dropped. The conversation, the typing flag and the busy flag
    // are all on the session, which is handed to the new one unchanged.
    public func RebuildPhoneView() {
        if !IsDefined(this.m_phoneSession) {
            return;
        }
        this.m_phoneView = new AiNpcPhoneChatRenderer();
        this.m_phoneView.BindSession(this.m_phoneSession);
        this.m_phoneSession.Attach(this.m_phoneView);
        this.m_phoneView.Resolve(this.player);
        if IsDefined(this.defaultPhoneController) {
            this.m_phoneView.SetPhoneController(this.defaultPhoneController);
        }

        // A rebuild with the chat on screen has to put it back, or the player is left looking
        // at the widgets of a tree that has been replaced -- visible, and dead.
        //
        // Only the widget half: the registry entry, the key bindings and the sound belong to
        // opening a chat, and the chat never closed.
        if this.PhoneState().IsChatOpen() && !this.m_phoneView.IsDisabled() {
            AiNpcLog("Phone HUD rebuilt with the chat open: drawing it again on the live tree.");
            this.m_phoneView.EnterChat();
        }
    }

    // Re-run on every spawn: the controller is destroyed with the HUD, so this handle is only
    // valid while this system keeps refreshing it. The search lives in AiNpcNotification.
    private func InitializeDefaultPhoneController() {
        this.defaultPhoneController = AiNpcFindPhoneController();
        if !IsDefined(this.defaultPhoneController) {
            return;
        }
        if IsDefined(this.m_phoneView) {
            this.m_phoneView.SetPhoneController(this.defaultPhoneController);
        }
        AiNpcLog("Phone controller found.");
    }



    private func PlaySound(sound: CName) {
        GameObject.PlaySoundEvent(this.player, sound);
    }



    // The one thing the model needs to know about widgets, and a Bool rather than a handle.
    private func PhoneUnavailable() -> Bool {
        return !IsDefined(this.m_phoneView) || this.m_phoneView.IsDisabled();
    }

    private func HasContactList() -> Bool {
        return IsDefined(this.m_phoneView) && this.m_phoneView.HasContactList();
    }

    // For the callers outside this file that legitimately paint: the seed API refreshing an
    // open thread, and nothing else.
    public func GetPhoneView() -> ref<AiNpcPhoneChatRenderer> {
        return this.m_phoneView;
    }

    public func GetChatOpen() -> Bool {
        return this.PhoneState().IsChatOpen();
    }





}


