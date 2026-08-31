// The call, as a machine. What state it is in, what moves it, and the one moment that opens a
// conversation.
//
// The decisions are not here -- they are in AiNpcCallState.reds, pure, so the suite can run
// them before any system exists. What is here is the reaching: the timers, the contact it is
// addressed to, and the single crossing of AiNpcChatDoor.
//
// A ScriptableSystem rather than a service: a call belongs to a playthrough, and nothing about
// it may outlive one. Nothing is persistent, so a save taken mid-call reloads Idle.
//
// It draws nothing. A surface for the call is step 4 of docs/PLAN_HOLO_LANE.md, and the point
// of arriving at it in this order is that the door discipline below is proven before a widget
// can hide it.

module AiNpc

// How long the ringing lasts on each side. Named rather than inline: they are the two numbers
// a play session will want to argue about, and finding them should not need reading the
// machine.
func AiNpcCallDialSeconds() -> Float {
    return 1.5;
}

// Long enough for a person to answer. The first value tried was 8 seconds, and a hand driving
// four buttons in a debug window missed it on the first attempt -- which is roughly what a
// player reaching for a ringing phone does.
func AiNpcCallRingSeconds() -> Float {
    return 20.0;
}

// What the two prompts say. Here rather than in the choice file, because the words belong to
// this lane and the hub is a mechanism.
func AiNpcCallWriteLabel() -> String {
    return "Say something";
}

func AiNpcCallHangUpLabel() -> String {
    return "Hang up";
}


public class AiNpcCallSystem extends ScriptableSystem {

    private let m_state: AiNpcCallState = AiNpcCallState.Idle;
    private let m_contactId: String = "";

    // Every timer carries the serial it was armed under, and a timer whose serial has moved on
    // does nothing. A DelaySystem timer cannot be cancelled, so hanging up and calling again
    // inside the ring window would otherwise let the FIRST call's timeout end the second one.
    private let m_serial: Int32 = 0;

    // The one line V speaks into. Built on demand and dropped with the call: it holds widgets,
    // so it cannot outlive the HUD that hosts them.
    private let m_input: ref<AiNpcHoloInput>;

    public static func Get() -> ref<AiNpcCallSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcCallSystem>()) as AiNpcCallSystem;
    }

    public func State() -> AiNpcCallState {
        return this.m_state;
    }

    public func ContactId() -> String {
        return this.m_contactId;
    }

    // What the window shows: the state, and who it is with.
    public func Describe() -> String {
        if Equals(StrLen(this.m_contactId), 0) {
            return AiNpcCallStateLabel(this.m_state);
        }
        return s"\(AiNpcCallStateLabel(this.m_state)) -- \(this.m_contactId)";
    }

    /// The player's verbs ///

    // Place a call. Answers what happened, so a caller shows one sentence rather than deciding
    // what a refusal means.
    public func Dial(contactId: String) -> String {
        if Equals(StrLen(contactId), 0) {
            return "Refused: a call needs a contact.";
        }
        // The previous call's ending is cleared here and nowhere else: it stays on screen until
        // it is in the way, which is the only moment it stops being worth reading.
        if AiNpcCallIsOver(this.m_state) {
            this.Enter(AiNpcCallState.Idle);
        }
        if !AiNpcCallMayGo(this.m_state, AiNpcCallState.Dialing) {
            return s"Refused: already \(AiNpcCallStateLabel(this.m_state)).";
        }
        if !AiNpcIsContactSupported(contactId) {
            return s"Refused: '\(contactId)' is not a contact this mod can talk to.";
        }

        this.m_contactId = contactId;
        this.Enter(AiNpcCallState.Dialing);
        AiNpcArmTimeout(AiNpcCallTickCallback.Create(this.m_serial, AiNpcCallState.Ringing),
            AiNpcCallDialSeconds());
        return s"Dialing \(contactId)...";
    }

    // The character picks up. In this step it is the player who decides, from the window; a
    // character deciding for itself is a later question and does not change the transition.
    public func PickUp() -> String {
        return this.Move(AiNpcCallState.Connected);
    }

    // Never got through.
    public func Decline() -> String {
        return this.Move(AiNpcCallState.Refused);
    }

    // Over, whether it was answered or not.
    public func HangUp() -> String {
        return this.Move(AiNpcCallState.Ended);
    }

    /// The machine ///

    // The one door every transition goes through, so the table in AiNpcCallState is the only
    // thing that decides, and every entry into a state does its work exactly once.
    private func Move(to: AiNpcCallState) -> String {
        if !AiNpcCallMayGo(this.m_state, to) {
            return s"Refused: \(AiNpcCallStateLabel(this.m_state)) does not go to \(AiNpcCallStateLabel(to)).";
        }
        this.Enter(to);
        return this.Describe();
    }

    private func Enter(to: AiNpcCallState) -> Void {
        let from = this.m_state;
        let contactId = this.m_contactId;

        // Bumped on EVERY entry, so any timer armed under the old state is already stale.
        this.m_serial += 1;
        this.m_state = to;
        AiNpcLog(s"Call: \(AiNpcCallStateLabel(from)) -> \(AiNpcCallStateLabel(to)) ('\(contactId)').");

        // The call the player sees is the game's own, asked for once. Picking up does not ask
        // again: the vanilla call is already up, and answering only stops the ring and offers
        // the two choices. Nothing is drawn here.
        if Equals(to, AiNpcCallState.Ringing) {
            AiNpcVanillaCallStart(contactId);
            AiNpcArmTimeout(AiNpcCallRingCallback.Create(this.m_serial), AiNpcVanillaRingDelay());
            AiNpcArmTimeout(AiNpcCallTickCallback.Create(this.m_serial, AiNpcCallState.Missed),
                AiNpcCallRingSeconds());
        }

        if Equals(to, AiNpcCallState.Connected) {
            AiNpcVanillaRingStop();
            AiNpcCallShowChoices(AiNpcCallWriteLabel(), AiNpcCallHangUpLabel());
        }

        // Every ending closes the game's call, including the ones nobody answered -- a portrait
        // left ringing after a missed call is the failure this line exists to prevent.
        if AiNpcCallIsOver(to) {
            AiNpcVanillaRingStop();
            AiNpcCallHideChoices();
            this.HideInput();
            AiNpcVanillaCallEnd(contactId);
        }

        // THE CROSSING. Asked of the pure function and not re-derived here, because "a call
        // that was never picked up opens no conversation" is the whole subject of this step.
        if AiNpcCallConnects(from, to) {
            this.OpenConversation(contactId);
        }

        // An ending is NOT collapsed here. It stays, with the contact it was about, so the
        // window says "missed -- judy" rather than an idle nobody can explain. Dial clears it.
        if Equals(to, AiNpcCallState.Idle) {
            this.m_contactId = "";
        }
    }

    // AN ANSWERED CALL DOES NOT OPEN THE WRITTEN THREAD, and the temptation to make it do so
    // is why this is a named function with a comment rather than one line.
    //
    // A call is spoken. docs/PLAN_HOLO_CHANNEL.md is the whole argument: what is said on a call
    // must not appear as a written message, while the memory stays shared. Opening the SMS
    // thread here would be the exact defect that document exists to prevent -- and it would
    // look like it worked, which is worse.
    //
    // Crossing AiNpcChatDoor needs a session, and the session a call opens is the holo's. It
    // does not exist yet: the channel is step 0 and the surface is step 4. So this step proves
    // the machine and the timers, and the crossing is deliberately absent rather than faked
    // through the phone.
    private func OpenConversation(contactId: String) -> Void {
        AiNpcLog(s"Call connected to '\(contactId)'. No written conversation is opened: a call is spoken.");
    }

    // A key, offered by the hook and answered here. True means the call took it, which is what
    // stops the game from also acting on it.
    //
    // Scoped to a live call in every branch: these keys mean something else at every other
    // moment, and a call that answered them from Idle would eat a dialogue choice in a quest.
    public func ReportAction(name: CName, kind: gameinputActionType) -> Bool {
        // Escape, while the line has the keyboard. It is the way out of every other text field
        // in the game, and on the HUD it also opens the pause menu -- so the whole action is
        // eaten, press and release together. Half an action consumed is a menu that opens on
        // the key going up.
        if Equals(name, n"OpenPauseMenu_Button") && IsDefined(this.m_input) && this.m_input.HasKeyboard() {
            if Equals(kind, gameinputActionType.BUTTON_PRESSED) {
                this.m_input.DropFocus();
            }
            return true;
        }

        if NotEquals(kind, gameinputActionType.BUTTON_RELEASED)
                || NotEquals(this.m_state, AiNpcCallState.Connected) {
            return false;
        }

        if Equals(name, AiNpcCallHangUpAction()) {
            this.HangUp();
            return true;
        }

        if Equals(name, AiNpcCallWriteAction()) {
            this.ShowInput();
            return true;
        }

        return false;
    }

    // One line, over the call. Not a chat: the reply comes back on the call, and nothing that
    // is said here belongs in a written thread.
    private func ShowInput() -> Void {
        if !IsDefined(this.m_input) {
            this.m_input = new AiNpcHoloInput();
        }
        if !this.m_input.Show() {
            AiNpcLog("Call: no input line could be shown.");
        }
    }

    private func HideInput() -> Void {
        if IsDefined(this.m_input) {
            this.m_input.Hide();
        }
    }

    // What V said, from the line.
    //
    // Nobody answers it yet -- generating a reply is the speaking lane's, and the channel that
    // keeps a spoken turn out of the written thread is not built. What happens instead is the
    // rest of the lane, end to end: the words are synthesised and played, so the path from a
    // typed line to a sound in the room is measured before anything is asked of a model.
    public func ReportSpoken(text: String) -> Void {
        if Equals(StrLen(text), 0) {
            return;
        }
        AiNpcLog(s"Call: V said '\(text)' to '\(this.m_contactId)'. \(AiNpcAudio.Speak(text))");
    }

    // The ring, armed late on purpose -- see the head of AiNpcCallVanilla.reds.
    public func OnRingTick(serial: Int32) -> Void {
        if NotEquals(serial, this.m_serial) || NotEquals(this.m_state, AiNpcCallState.Ringing) {
            return;
        }
        AiNpcVanillaRingStart();
    }

    // A timer that was armed under a serial this system has moved past. Doing nothing is the
    // whole of the correct behaviour.
    public func OnCallTick(serial: Int32, to: AiNpcCallState) -> Void {
        if NotEquals(serial, this.m_serial) {
            return;
        }
        this.Move(to);
    }
}

// The ring and the pickup window, each carrying the state it was armed to reach. One class for
// both, because what differs between them is data rather than behaviour.
class AiNpcCallRingCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnRingTick(this.serial);
    }

    public static func Create(serial: Int32) -> ref<AiNpcCallRingCallback> {
        let self = new AiNpcCallRingCallback();
        self.serial = serial;
        return self;
    }
}

class AiNpcCallTickCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;
    public let to: AiNpcCallState;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnCallTick(this.serial, this.to);
    }

    public static func Create(serial: Int32, to: AiNpcCallState) -> ref<AiNpcCallTickCallback> {
        let self = new AiNpcCallTickCallback();
        self.serial = serial;
        self.to = to;
        return self;
    }
}
