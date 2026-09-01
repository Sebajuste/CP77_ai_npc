// How a CLI answer finds its way back to the lane that asked for it.
//
// Ce fichier a existe parce qu'un second transport, RedHttpClient, portait lui-meme un objet
// cible et une methode. Il n'y en a plus qu'un, et c'est celui-ci.
// method name in its callback, so the answer lands on the object that sent the request. The
// plugin has no such channel by design -- carrying one would mean registering a second
// native class, and AiNpcCliNative explains what each of those costs.
//
// So the routing is carried in the request id itself, and the id is composed rather than
// allocated: the lane it belongs to is a digit in it. Nothing has to be remembered between
// the send and the answer, which means nothing can leak when a request never comes back --
// and there is no registry to fall out of step with the lanes.
//
//   requestId = laneCode * 1000000 + serial
//
// The serial is the lane's own counter, and it is what makes a LATE answer harmless. A
// request that timed out is not cancelled -- the process is still running, and the plugin
// will still deliver when it finishes. By then the lane has moved on, its counter has
// advanced, and the stale answer is dropped instead of being written into a conversation
// that has had three messages since.

module AiNpc

/// The lanes ///

// Three, because that is how many places send a request, not how many providers exist. The
// repair is its own lane rather than a flag on the speaking one: it is a SECOND request
// inside one turn, and its answer re-enters at a different point.
func AiNpcCliLaneChat() -> Int32 {
    return 1;
}

func AiNpcCliLaneRepair() -> Int32 {
    return 2;
}

func AiNpcCliLaneMemory() -> Int32 {
    return 3;
}

// The setup window's connection test. A lane like any other, because it is one: it builds its
// body and reads its answer with the same functions the other three use, which is what makes
// a green test mean something.
func AiNpcCliLaneTest() -> Int32 {
    return 4;
}

// The action selection. A fifth code and no C++ change: the plugin composes nothing, it echoes
// back the id it was handed, so a lane added here is a lane the plugin already routes.
func AiNpcCliLaneActions() -> Int32 {
    return 5;
}

/// Composing and taking apart ///

func AiNpcCliRequestSpan() -> Int32 {
    return 1000000;
}

// The serial wraps rather than growing without bound. A million requests into one session is
// not reachable, and a wrapped serial only ever collides with an answer a million requests
// old -- which cannot still be in flight.
func AiNpcCliRequestId(laneCode: Int32, serial: Int32) -> Int32 {
    return laneCode * AiNpcCliRequestSpan() + (serial % AiNpcCliRequestSpan());
}

func AiNpcCliLaneOf(requestId: Int32) -> Int32 {
    return requestId / AiNpcCliRequestSpan();
}

func AiNpcCliSerialOf(requestId: Int32) -> Int32 {
    return requestId % AiNpcCliRequestSpan();
}

/// The door the plugin knocks on ///

// Called BY THE PLUGIN, from the game thread, once per request it was given.
//
// This is the only entry point ai_npc.dll has into script, and it is a plain redscript
// function rather than a native callback type for the reason AiNpcCliNative gives. Its
// signature is therefore a contract with C++: changing it means changing ScriptApi.cpp in
// the same commit, and the failure mode if they disagree is silence -- the answer simply
// never arrives, and the lane's watchdog reports it as a provider that never replied.
//
// `body` is OpenAI-shaped JSON in both directions of the outcome. A typed failure arrives as
// {"error":{"message":"..."}} with a non-200 status, which is the shape AiNpcExtractApiError
// already reads -- so a CLI that is not signed in reaches the player through the same lines
// of script as an OpenRouter 401, down to the sentence in the bubble. That is the whole
// reason the plugin speaks this dialect instead of one of its own.
public func AiNpcCliDeliver(requestId: Int32, status: Int32, body: String, date: String) -> Void {
    let reply = AiNpcReply.FromCli(status, body, date);
    let lane = AiNpcCliLaneOf(requestId);
    let serial = AiNpcCliSerialOf(requestId);

    if Equals(lane, AiNpcCliLaneMemory()) {
        let memory = GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcMemoryService>()) as AiNpcMemoryService;
        if IsDefined(memory) {
            memory.OnCliMemoryReply(serial, reply);
        }
        return;
    }

    if Equals(lane, AiNpcCliLaneActions()) {
        let actions = GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcActionService>()) as AiNpcActionService;
        if IsDefined(actions) {
            actions.OnCliActionReply(serial, reply);
        }
        return;
    }

    if Equals(lane, AiNpcCliLaneTest()) {
        let setup = GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcSetupSystem>()) as AiNpcSetupSystem;
        if IsDefined(setup) {
            setup.OnCliTestReply(serial, reply);
        }
        return;
    }

    let speaking = GameInstance.GetScriptableSystemsContainer(GetGameInstance())
        .Get(NameOf<AiNpcHttpSystem>()) as AiNpcHttpSystem;
    if !IsDefined(speaking) {
        // The session went away while the process was running. Nothing to report and nobody
        // to report it to; the lane it belonged to no longer exists.
        return;
    }

    if Equals(lane, AiNpcCliLaneRepair()) {
        speaking.OnCliRepairReply(serial, reply);
        return;
    }
    if Equals(lane, AiNpcCliLaneChat()) {
        speaking.OnCliChatReply(serial, reply);
        return;
    }

    // An id the plugin invented, or one this build no longer knows. Logged rather than
    // dropped: it means C++ and script have drifted apart, which is exactly the thing the
    // contract note above is trying to prevent.
    AiNpcLog(s"A CLI answer arrived for lane \(lane), which does not exist. Request \(requestId).");
}
