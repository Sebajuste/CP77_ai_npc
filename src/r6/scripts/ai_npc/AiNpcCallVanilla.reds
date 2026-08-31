// THE ONE PLACE A VANILLA CALL IS PLACED. Everything the game knows about calls is asked for
// here, and nothing else in the mod names a quest type.
//
// The call a player expects is the game's own, and it is not ours to rebuild: the phone folds
// away, the contact's portrait comes up, the ringtone plays. `questTriggerCallRequest` asks for
// exactly that.
//
// IT IS AN AUDIO CALL, AND THAT IS A MEASUREMENT RATHER THAN A PREFERENCE. `callMode = Video`
// opens the real holo window -- and it stays empty. Measured 2026-08-31 across every reachable
// entry point: `StartHolocall`, `StartAudiocall` and `RefreshView` on the live
// `HudPhoneAvatarController`, and `HolocallStartEvent` queued on the player. Nothing draws a
// character. In vanilla the quest's scene puts an actor in that frame, and a call placed from
// script has no scene behind it.
//
// So the surface is the portrait and an open voice channel. It is the lesser ambition and the
// better result: no uncanny empty window, and the player keeps the world on screen while the
// character talks. Going back to Video is one enum away if a way to populate the frame is ever
// found.
//
// Verified against the vanilla bundle on 2026-08-31, one candidate per probe function, because
// the compiler reports at most ONE error per function and a batched probe validates nothing
// after its first failure. What resolves: `addressee`, `callPhase` (StartCall, EndCall),
// `callMode` (Audio, Video), `visuals` (Default, Somi), `showAvatar`, `isRejectable`,
// `isPlayerTriggered`, and `PhoneSystem.QueueRequest`.
//
// What does NOT exist, and shapes the code below: there is no phase `None`, and **the request
// carries no ringtone flag** -- the sound is the caller's, played by its own Wwise event.
//
// THE RING IS PLAYED LATE, AND THAT IS THE WHOLE OF WHAT WAS WRONG WITH IT TWICE.
//
// Measured 2026-08-31, in three launches. Played immediately after QueueRequest, the tone lasts
// under a second and stops; re-played every two seconds it is cut short each time; played once,
// nothing is heard at all. The common cause is the order: `QueueRequest` is handled by
// PhoneSystem on a LATER tick, and handling a call is where the game emits its own call audio,
// including the stops. Our tone is started before that and killed by it.
//
// So the ring is armed on a short delay -- after the request has been digested -- and the delay
// is a named number rather than a magic one, because it is a guess about another system's tick
// and the next launch is what settles it.
//
// What no compiler can say is whether a Video call with no scene behind it has anything to
// show: the character is drawn into a render texture, and a mod on this machine (VendorsXL)
// pairs holocalls with workspots. That is the measurement this file exists to make.
//
// All-or-nothing, like every other foreign surface this mod reaches: a caller gets true or
// false, never a half-placed call.

module AiNpc

// The game names a correspondent by CName and the mod names it by String. They are assumed to
// be the same word until a launch says otherwise; an addressee the game does not know is
// expected to cost the portrait, not the call.
func AiNpcCallAddressee(contactId: String) -> CName {
    return StringToName(contactId);
}

func AiNpcVanillaPhone() -> ref<PhoneSystem> {
    return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"PhoneSystem") as PhoneSystem;
}

// Ring. `video` is the difference between the two sequences: false is the portrait and the
// ringtone, true is the character.
//
// isRejectable is false on purpose. The vanilla call UI can answer and decline on its own, and
// a player using it would move the game's state while AiNpcCallSystem still believed the phone
// was ringing. One machine drives; this only draws.
func AiNpcVanillaCallStart(contactId: String) -> Bool {
    let phone = AiNpcVanillaPhone();
    if !IsDefined(phone) {
        AiNpcLog("No PhoneSystem: a call cannot be shown.");
        return false;
    }

    let request = new questTriggerCallRequest();
    request.addressee = AiNpcCallAddressee(contactId);
    request.callPhase = questPhoneCallPhase.StartCall;
    request.callMode = questPhoneCallMode.Audio;
    request.visuals = questPhoneCallVisuals.Default;
    request.showAvatar = true;
    request.isPlayerTriggered = true;
    request.isRejectable = false;

    phone.QueueRequest(request);
    AiNpcLog(s"Vanilla call requested for '\(contactId)'.");
    return true;
}

func AiNpcVanillaCallEnd(contactId: String) -> Bool {
    let phone = AiNpcVanillaPhone();
    if !IsDefined(phone) {
        return false;
    }

    let request = new questTriggerCallRequest();
    request.addressee = AiNpcCallAddressee(contactId);
    request.callPhase = questPhoneCallPhase.EndCall;
    request.visuals = questPhoneCallVisuals.Default;
    request.isPlayerTriggered = true;

    phone.QueueRequest(request);
    AiNpcLog(s"Vanilla call ended for '\(contactId)'.");
    return true;
}

// The outgoing tone. The mod places the call, so this is the tone rather than the incoming
// ringtone, which is the event for a call the player RECEIVES.
func AiNpcVanillaRingStart() -> Void {
    AiNpcLog("Ring: playing ui_phone_initiation_call.");
    GameInstance.GetAudioSystem(GetGameInstance()).Play(n"ui_phone_initiation_call");
}

// How long to wait after the call request before ringing. See the head of this file.
func AiNpcVanillaRingDelay() -> Float {
    return 0.6;
}

func AiNpcVanillaRingStop() -> Void {
    GameInstance.GetAudioSystem(GetGameInstance()).Play(n"ui_phone_initiation_call_stop");
}

// What the journal knows about this save's contacts, written to the log.
//
// The holo shows an empty frame for a contact the game cannot resolve, and the mod addresses a
// call by its OWN id ("judy"), which the journal has never heard of. This is how the real names
// are found rather than guessed: the same array the phone's contact list is built from, printed
// with everything that identifies a row.
//
// includeUnknown and includeNonCallable are both true: a contact the game will not let the
// player call is exactly the kind this needs to see.
// What the game holds for a character record, for the contacts the journal knows.
//
// The holo frame comes up empty, and the contact is NOT the reason -- the dump above proved
// 'judy' is the journal's own id, callable, with its avatar. What draws the character into the
// frame is the remaining question, and `holocallInitializerPath` on a Character record is the
// only field in the game named for it. This says whether the characters we call have one.
func AiNpcDumpCharacterRecords(ids: array<String>) -> Void {
    let i = 0;
    while i < ArraySize(ids) {
        let id = ids[i];
        let record = TweakDBInterface.GetCharacterRecord(TDBID.Create("Character." + id));
        if IsDefined(record) {
            FTLog(s"[ai_npc] Character.\(id): holocallInitializerPath='\(record.HolocallInitializerPath())'");
        } else {
            FTLog(s"[ai_npc] Character.\(id): no such record.");
        }
        i += 1;
    }
}

func AiNpcDumpJournalContacts() -> Int32 {
    let journal = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
        return -1;
    }

    let rows = journal.GetContactDataArray(true, true);
    let count = ArraySize(rows);
    let i = 0;
    while i < count {
        let data = rows[i] as ContactData;
        if IsDefined(data) {
            FTLog(s"[ai_npc] contact \(i): id='\(data.id)' contactId='\(data.contactId)' name='\(data.localizedName)' callable=\(data.isCallable) avatar=\(TDBID.ToStringDEBUG(data.avatarID))");
        }
        i += 1;
    }
    FTLog(s"[ai_npc] \(count) contact row(s) in the journal.");

    // The same ids, asked of the character table. Built from the rows rather than typed, so it
    // covers whatever this save actually has.
    let ids: array<String>;
    i = 0;
    while i < count {
        let data = rows[i] as ContactData;
        if IsDefined(data) && NotEquals(StrLen(data.id), 0) {
            ArrayPush(ids, data.id);
        }
        i += 1;
    }
    AiNpcDumpCharacterRecords(ids);
    return count;
}
