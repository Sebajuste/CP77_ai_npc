// What a call can be, and what it may become. Pure, and that is the whole point of the file.
//
// A call has moments no widget can report -- dialing, ringing, picked up, refused, hung up --
// and building the widget is one of them. So the lifecycle cannot live in a renderer: the
// renderer would have to exist before it exists. It lives in AiNpcCallSystem, and the part
// that decides anything lives here, in free functions over plain data, so
// tests\AiNpcTestCallState.reds can run them at AiNpcStorageService attach, before any
// ScriptableSystem exists. No Get...() below this line, ever -- same constraint as
// AiNpcChatSession, same reason.
//
// Not persistent, and not by omission: a call is a moment. A save taken mid-call reloads Idle,
// and the mod already has a lane for what must wait for a moment to come back.

module AiNpc

enum AiNpcCallState {
    Idle = 0,
    Dialing = 1,
    Ringing = 2,
    Connected = 3,
    // The three ways it stops, kept apart because they are not the same event to anyone
    // watching: Refused never reached the other end, Missed reached it and nobody answered,
    // Ended was a call that happened.
    Refused = 4,
    Missed = 5,
    Ended = 6,
}

// The legal transitions, written once as a table rather than as guards spread over the system.
//
// A state never goes to itself: re-entering Ringing is not a transition, and a machine that
// allowed it would re-arm a timer on every tick.
func AiNpcCallMayGo(from: AiNpcCallState, to: AiNpcCallState) -> Bool {
    if Equals(from, to) {
        return false;
    }
    switch from {
        case AiNpcCallState.Idle:
            return Equals(to, AiNpcCallState.Dialing);
        case AiNpcCallState.Dialing:
            // Ended is the player hanging up before it ever rang.
            return Equals(to, AiNpcCallState.Ringing)
                || Equals(to, AiNpcCallState.Refused)
                || Equals(to, AiNpcCallState.Ended);
        case AiNpcCallState.Ringing:
            return Equals(to, AiNpcCallState.Connected)
                || Equals(to, AiNpcCallState.Missed)
                || Equals(to, AiNpcCallState.Ended);
        case AiNpcCallState.Connected:
            return Equals(to, AiNpcCallState.Ended);
        default:
            // The three endings settle back to Idle and nowhere else.
            return Equals(to, AiNpcCallState.Idle);
    }
}

// A call that is over but has not been cleared yet. The three endings are kept apart from
// Idle because a call that ended IS a thing that happened: collapsing them the moment they are
// reached leaves nothing on screen to read, and "why did Pick up refuse?" has no answer.
//
// Cleared lazily, when the next call is placed, which is this project's convention for
// anything that expires -- an expiry driven by a timer does not survive a save.
func AiNpcCallIsOver(state: AiNpcCallState) -> Bool {
    return Equals(state, AiNpcCallState.Refused)
        || Equals(state, AiNpcCallState.Missed)
        || Equals(state, AiNpcCallState.Ended);
}

// Whether something is going on that the player would call "a call".
func AiNpcCallIsLive(state: AiNpcCallState) -> Bool {
    return Equals(state, AiNpcCallState.Dialing)
        || Equals(state, AiNpcCallState.Ringing)
        || Equals(state, AiNpcCallState.Connected);
}

// THE ONE TRANSITION THAT CROSSES AiNpcChatDoor, and the reason it is a function rather than
// an `Equals(to, Connected)` at the call site: a call that is never picked up must open no
// conversation, publish no ConversationOpened and never reach the memory service. Stated here,
// it is asserted here.
func AiNpcCallConnects(from: AiNpcCallState, to: AiNpcCallState) -> Bool {
    return Equals(to, AiNpcCallState.Connected) && AiNpcCallMayGo(from, to);
}

// Qui a placé l'appel. Le jeu place les siens avec leur scène ; le mod n'y greffe que la parole.
enum AiNpcCallOrigin {
    Ours = 0,
    Game = 1,
}

// Un appel du jeu se rejoint déjà décroché : il ne sonne pas, et ne passe donc pas par la table.
func AiNpcCallMayJoin(state: AiNpcCallState) -> Bool {
    return Equals(state, AiNpcCallState.Idle) || AiNpcCallIsOver(state);
}

// What the state is called, for anything that shows it. Here rather than in the window,
// because a window that spelled the states itself would drift from the table above.
func AiNpcCallStateLabel(state: AiNpcCallState) -> String {
    switch state {
        case AiNpcCallState.Dialing: return "dialing";
        case AiNpcCallState.Ringing: return "ringing";
        case AiNpcCallState.Connected: return "connected";
        case AiNpcCallState.Refused: return "refused";
        case AiNpcCallState.Missed: return "missed";
        case AiNpcCallState.Ended: return "ended";
        default: return "idle";
    }
}
