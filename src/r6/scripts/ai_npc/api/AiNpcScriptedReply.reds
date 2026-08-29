// The sentinels and the timing constant a scripted reply is defined in terms of.
//
// They belong to the contract a third-party mod implements, not to the stored-message model
// and not to the registry: a provider answering GetScriptedReply has to be able to say
// "nothing at all", and that answer needs a spelling both sides agree on.

module AiNpc

// "This contact answers nothing at all to that message". A third answer, because "" means the
// opposite -- no opinion, let the model write. Silence is a decision, and for an automated
// correspondent questioned twice it is the decision; a generated apology would undo it.
//
// A sentinel string rather than a Bool out-parameter: redscript has no option type, so every
// answer travels through the same return value. Deliberately unspeakable, so it can never
// collide with a real reply.
public func AiNpcSilentReply() -> String {
    return "<<ai_npc:silence>>";
}

public func AiNpcIsSilentReply(text: String) -> Bool {
    return Equals(text, AiNpcSilentReply());
}

// Fixed and short: the regularity is the feature, not a detail to smooth over.
public func AiNpcScriptedReplyDelay() -> Float {
    return 1.6;
}
