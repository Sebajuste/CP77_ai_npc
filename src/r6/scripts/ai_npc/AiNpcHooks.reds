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

// Called on every refresh of the contact list, far more often than the player moves:
// gamelog.3.log (2026-03-20) records twenty-two rows in two seconds when the contacts screen
// comes back. Both lines below are idempotent and cheap, and neither writes anything the mod
// will mistake for an intent -- selecting the contact from here is how a refresh burst could
// decide what T would open.
@wrapMethod(PhoneDialerLogicController)
private final func RefreshInputHints(contactData: wref<ContactData>) -> Void {
    wrappedMethod(contactData);

    if contactData != null {
        GetAiNpcSystem().ReportContactRow(contactData.contactId);
        AiNpcDecorateContactRow(this.m_contactsList, contactData.contactId);
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

@wrapMethod(PlayerPuppet)
protected cb func OnCombatStateChanged(newState: Int32) -> Bool {  // newState uses the values specified in enum PlayerCombatState
    let r: Bool = wrappedMethod(newState);

    if IsDefined(GetAiNpcSystem()) {
        GetAiNpcSystem().ReportCombatState(newState);
    }

    return r;
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
