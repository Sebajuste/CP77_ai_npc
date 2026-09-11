// Where the mod attaches to the game's own phone. A wrapper here reports a fact and decides
// nothing: every call it makes is `GetAiNpcSystem().Report*(...)`, and tools\lint.ps1 enforces
// that the only member this file may call on the system is a Report*.
//
// These methods fire on the game's schedule, not the player's: OnAllElementsSpawned and
// RefreshInputHints say "widgets were built", never "the player wanted something", and no
// guard bolted on can make them say it. Measured 2026-08-22: the wrapper on
// OnAllElementsSpawned read `unread` and `IsOnContactsTab()` and concluded "open the chat",
// both true when the player merely pressed D to switch tab.
//
// So the decisions moved up to AiNpcSystem, which owns the state machine that can tell a tab
// switch from the phone being taken out, and the painting moved sideways to
// AiNpcPhoneWidgets. What is left is a translation layer: vanilla callback in, mod event out.
module AiNpc

@wrapMethod(PlayerPuppet)
protected cb func OnMakePlayerVisibleAfterSpawn(evt: ref<EndGracePeriodAfterSpawn>) -> Bool {
    wrappedMethod(evt);

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportPlayerSpawned();
    }
}

// m_screenType is the controller's own field, so the test lives on the controller: the com
// device blackboard says "the phone is open" for both tabs and cannot tell them apart.
@addMethod(NewHudPhoneGameController)
public final func AiNpcScreen() -> AiNpcPhoneScreen {
    if Equals(this.m_screenType, PhoneScreenType.Contacts) {
        return AiNpcPhoneScreen.Contacts;
    }
    return AiNpcPhoneScreen.Messages;
}

// The player pressed Q or D -- the event the mod never had, and the reason the D bug was
// unfixable by adding conditions. Reported before wrappedMethod, because the screen it
// produces may be built inside it and the latch has to be armed first.
//
// Verified name: NightlyNow calls this method on the same controller.
@wrapMethod(NewHudPhoneGameController)
private final func SelectOtherTab() -> Void {
    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportTabSwitch();
    }

    wrappedMethod();
}

// Fires when the phone comes up, on every tab switch to the contact list, and on plain
// redraws. Which of the three it was is the state machine's job: that this callback cannot
// tell them apart is why the state machine exists.
@wrapMethod(PhoneDialerLogicController)
protected cb func OnAllElementsSpawned() -> Bool {
    wrappedMethod();

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportPhoneScreen();
    }
}

// The phone HUD was rebuilt, so the mod's handles into it are stale. The signal the mod had
// evidence for and was not using: a removed "U - quick chat" wrapper on this method opened
// with a duplicate guard, which is proof it fires more than once per session.
//
// Cheap to be wrong about: rebuilding costs one allocation and one named scan of the HUD
// layer. Firing too often is invisible; firing too rarely is the bug this replaces.
@wrapMethod(PhoneDialerLogicController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportPhoneTreeRebuilt();
    }

    return result;
}

// Not the same thing as the phone going away, and telling those apart is the system's job.
// The catch-all: Escape, a menu taking over, the game closing the com device, and the other
// tab taking the screen all end up here.
//
// Opening the mod chat goes through DisableContactsInput(), not Hide(), so closing from here
// cannot fight the open path.
@wrapMethod(PhoneDialerLogicController)
public final func Hide() -> Void {
    wrappedMethod();

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportContactsScreenHidden();
    }
}

// C means "one screen up" everywhere in the phone, and on the mod's chat that screen is the
// contact list. The mod cannot swallow the key where it reads input -- the callback system
// observes, it never consumes -- so the press arrives twice.
//
// Measured 2026-08-23: PhoneSystem.ToggleContacts and PhoneSystem.OnUsePhone never fired,
// while PhoneDialerLogicController.Hide() did, so the close is script-side and does not go
// through the phone system. What is left is the phone controller's own action handler, the
// one place handed the action and a consumer.
@wrapMethod(NewHudPhoneGameController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    // Not calling wrappedMethod is the consumption. Reported first, because the answer decides
    // whether the game sees this press at all.
    let call = AiNpcCallSystem.Get();
    if IsDefined(call)
        && call.ReportPhoneAction(ListenerAction.GetName(action), ListenerAction.GetType(action)) {
        return true;
    }
    if IsDefined(GetAiNpcSystem())
        && GetAiNpcSystem().ReportPhoneAction(ListenerAction.GetName(action), ListenerAction.GetType(action)) {
        return true;
    }

    return wrappedMethod(action, consumer);
}

// A second net rather than the fix: the log proves the C press does not come through here, but
// a close that does reach it while the chat is up is one the mod would rather answer.
@wrapMethod(PhoneSystem)
private final func ToggleContacts(open: Bool) -> Void {
    if !open && IsDefined(GetAiNpcSystem()) && GetAiNpcSystem().ReportPhoneCloseRequested("ToggleContacts") {
        return;
    }

    wrappedMethod(open);
}

// Another menu took over -- Escape opening the hub, most often.
@wrapMethod(MenuHubLogicController)
public final func SetActive(isActive: Bool) -> Void {
    wrappedMethod(isActive);

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportMenuTookOver();
    }
}

// R on a call is the game's own Choice2, so the press arrives at the player rather than at the
// phone controller -- the phone is put away while a call is up.
//
// Reported before wrappedMethod for the same reason as the phone's handler: the answer decides
// whether the game sees the press at all.
@wrapMethod(PlayerPuppet)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    // Consumed, not just refused: returning true alone left Enter to commit the game's dialogue
    // choice. Night City Allies stops a native choice the same way.
    let call = AiNpcCallSystem.Get();
    if IsDefined(call)
        && call.ReportAction(ListenerAction.GetName(action), ListenerAction.GetType(action)) {
        ListenerActionConsumer.Consume(consumer);
        return true;
    }

    return wrappedMethod(action, consumer);
}

// Escape opens the pause menu from here, on the key going up, and this controller is where that
// is decided. A call with its line focused answers first: the key means "stop typing", and the
// menu must not also open.
//
// The action is consumed as well as refused, the way the vanilla branch does once it has spawned
// the menu: this controller is not the only listener registered on OpenPauseMenu.
@wrapMethod(gameuiInGameMenuGameController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    let call = AiNpcCallSystem.Get();
    if IsDefined(call)
        && call.ReportPauseAction(ListenerAction.GetName(action), ListenerAction.GetType(action)) {
        ListenerActionConsumer.Consume(consumer);
        return true;
    }

    return wrappedMethod(action, consumer);
}

@wrapMethod(PlayerPuppet)
protected cb func OnCombatStateChanged(newState: Int32) -> Bool {  // newState uses the values specified in enum PlayerCombatState
    let r: Bool = wrappedMethod(newState);

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportCombatState(newState);
    }

    return r;
}

// F on a contact row. The mod places the call only where the game has no scene for it.
@wrapMethod(NewHudPhoneGameController)
public final func CallContact() -> Void {
    let call = AiNpcCallSystem.Get();
    if IsDefined(call) && IsDefined(this.m_contactListLogicController) && this.m_PhoneSystem.IsCallingEnabled() {
        let row = this.m_contactListLogicController.GetSelectedContactData();
        if IsDefined(row)
            && call.ReportCallRequested(row.contactId, AiNpcVanillaCallable(this.m_journalMgr, row.hash)) {
            return;
        }
    }
    wrappedMethod();
}

// The messages key on a row: the mod's conversation, or one of its characters with none of the
// game's, opens the mod's chat.
@wrapMethod(NewHudPhoneGameController)
public final func ExecuteAction() -> Void {
    if IsDefined(this.m_contactListLogicController) && IsDefined(GetAiNpcSystem())
        && GetAiNpcSystem().ReportMessagesAction(this.m_contactListLogicController.GetSelectedContactData()) {
        return;
    }
    wrappedMethod();
}

// The mod's conversation has no preview in the game's messenger, which would show the
// contact's vanilla thread under its name.
@wrapMethod(NewHudPhoneGameController)
protected cb func OnContactSelectionChanged(evt: ref<ContactSelectionChangedEvent>) -> Bool {
    if IsDefined(evt.ContactData) && evt.ContactData.ainpcThread {
        return true;
    }
    return wrappedMethod(evt);
}

@wrapMethod(JournalManager)
public final func GetContactDataArray(includeUnknown: Bool, includeNonCallable: Bool) -> array<ref<IScriptable>> {
    let rows = wrappedMethod(includeUnknown, includeNonCallable);
    AiNpcGraftContactRows(rows);
    return rows;
}

// Called by the phone's messages screen alone (ShowSelectedContactMessages).
@wrapMethod(MessengerUtils)
public final static func GetMessageDataArrayForContact(journal: ref<JournalManager>, concactHash: Int32,
                                                       includeUnknown: Bool, skipEmpty: Bool,
                                                       opt activeDataSync: wref<MessengerContactSyncData>) -> array<ref<IScriptable>> {
    let rows = wrappedMethod(journal, concactHash, includeUnknown, skipEmpty, activeDataSync);
    let thread = AiNpcThreadRowFor(journal, concactHash);
    if IsDefined(thread) {
        ArrayPush(rows, thread);
    }
    return rows;
}

// Every change of the game's call information, the mod's own calls included.
@wrapMethod(NewHudPhoneGameController)
protected cb func OnPhoneCall(value: Variant) -> Bool {
    let result = wrappedMethod(value);
    let call = AiNpcCallSystem.Get();
    if IsDefined(call) {
        call.ReportPhoneCall(FromVariant<PhoneCallInformation>(value));
    }
    return result;
}

// The dialogue hub's display. While the model has the floor on a call, the choices are not
// drawn; the blackboard keeps them, so the scene waits on a choice it still has.
@wrapMethod(dialogWidgetGameController)
protected func UpdateDialogsData(const data: script_ref<DialogChoiceHubs>) -> Void {
    let call = AiNpcCallSystem.Get();
    if IsDefined(call) && call.ReportDialogHubs(Deref(data)) {
        let hidden: DialogChoiceHubs;
        wrappedMethod(hidden);
        return;
    }
    wrappedMethod(data);
}

// Every line the main subtitle controller shows. Measured 2026-09-11: a listener on
// UIGameData.ShowDialogLine heard nothing during a holocall -- the scene's lines reach the
// controllers through the native subtitle handler, and both routes end here. The overhead
// controller is left out: its lines are the street, not the call.
@wrapMethod(BaseSubtitlesGameController)
public final func ShowDialogLines(const linesToShow: script_ref<array<scnDialogLineData>>) -> Void {
    wrappedMethod(linesToShow);

    let call = AiNpcCallSystem.Get();
    if !IsDefined(call) || !IsDefined(this as SubtitlesGameController) {
        return;
    }
    let lines = Deref(linesToShow);
    let i = 0;
    while i < ArraySize(lines) {
        call.ReportDialogLine(lines[i]);
        i += 1;
    }
}

// The player opened one of the game's own message threads.
@wrapMethod(NewHudPhoneGameController)
public final func GotoSmsMessenger(contactData: wref<ContactData>) -> Void {
    wrappedMethod(contactData);

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportThreadOpened();
    }
}

// The sender's name is a parameter and must stay one: this runs when the chat is not open on
// the sender, so the selected contact is by definition not the one who wrote. The contact id
// is a parameter too, because it is what the popup's open key resolves to -- a popup carrying
// only the name is the one that opened the phone on nothing at all.
//
// An @addMethod rather than a hook: the one piece of vanilla surface this mod adds rather than
// observes. It reports nothing and decides nothing; it draws.
@addMethod(NewHudPhoneGameController)
public final func PushCustomSMSNotification(contactId: String, senderName: String, text: String) -> Void {
    let notificationData: gameuiGenericNotificationData;
    let userData: ref<PhoneMessageNotificationViewData> = new PhoneMessageNotificationViewData();
    let action = AiNpcNotificationOpenAction(contactId, this.m_PhoneSystem);
    userData.title = senderName;
    userData.SMSText = text;
    userData.animation = n"notification_phone_MSG";
    userData.soundEvent = n"PhoneSmsPopup";
    userData.soundAction = n"OnOpen";
    userData.action = action;
    notificationData.time = 6.70;
    notificationData.widgetLibraryItemName = n"notification_message";
    notificationData.notificationData = userData;
    this.AddNewNotificationData(notificationData);
}
