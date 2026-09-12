// Where the sentences of a reply go: to the voice, and nowhere else. It is the voice's only
// source, whatever the lane. The streaming lane delivers them while the model is still writing,
// hiding the synthesis inside a delay the player is already paying; a lane that answers in one
// block delivers them, cut the same way, when it has answered.
//
// IT CHANGES NOTHING ELSE. The reply itself still arrives once, whole, at AiNpcCliDeliver, and
// everything downstream of it -- the commands, the repair pass, the memory service, the thread,
// the surfaces -- keeps working on a whole text. Nothing here writes anything down. A build where
// this file did not exist would lose the voice and keep the mod.
//
// It is a plain redscript global, like AiNpcCliDeliver and for the same reason: a declared
// native class the plugin failed to register stops the GAME from starting, and the head of
// AiNpcCliNative.reds counts what each one costs.

module AiNpc

// Called BY THE PLUGIN, from the game thread, several times for one request.
//
// The signature is a contract with ScriptApi.cpp, and if the two disagree nothing arrives -- the
// reply still does, so the symptom is a lane that works and never speaks.
//
// `isFinal` is the end of the stream, and that call may carry no text at all: a reply that ended
// exactly on a sentence already delivered still has to say there is no more coming, or the last
// thing the voice heard is indistinguishable from a pause.
public func AiNpcStreamDeliver(requestId: Int32, text: String, isFinal: Bool) -> Void {
    // Only the speaking lane has a voice. The repair, the memory compaction and the connection
    // test are out-of-character requests nobody listens to, and a character reading a memory
    // summary out loud is the one thing this lane must never do.
    if NotEquals(AiNpcCliLaneOf(requestId), AiNpcCliLaneChat()) {
        return;
    }

    // The evidence this lane is judged on, and the only place script can show it: a run whose
    // sentences are logged before the reply lands is a run where the voice had a head start, and
    // one where they all arrive after it is a model that streams too coarsely for any of this to
    // buy anything. The plugin logs the milliseconds; this logs the order.
    if isFinal {
        AiNpcLog(s"Stream: request \(requestId) has no more to say.");
        return;
    }

    AiNpcLog(s"Stream: request \(requestId) delivered '\(text)'.");

    let lane = GetAiNpcHttpSystem();
    let generation = IsDefined(lane) ? lane.GenerationOf(AiNpcCliSerialOf(requestId)) : null;
    if !IsDefined(generation) {
        AiNpcLog(s"Stream: request \(requestId) is no longer the generation in flight; not spoken.");
        return;
    }

    let call = AiNpcCallSystem.Get();
    if IsDefined(call) {
        call.SpeakStreamed(generation.Contact(), generation.Channel(), text);
    }
}
