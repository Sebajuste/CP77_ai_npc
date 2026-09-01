// One request, assembled and posted. The six steps every pass took for itself, written once.
//
// Resolve the slot, render the two messages, serialise, record, send. A pass differs by its
// builder and by nothing else, so a fifth pass is a builder rather than a sixth copy of this
// function.
//
// What stays with the lane is what a lane is: refusing on budget or credentials, the serial
// that addresses the answer, the watchdog, and delivering what comes back. This returns the
// slot and the record because both outlive the send -- the deadline is armed after it, and the
// cost is charged when the answer lands.

module AiNpc

// What a lane keeps from a request that left.
class AiNpcPassRequest {
    let slot: ref<AiNpcSlot>;
    let record: ref<AiNpcRequestRecord>;
}

// Null means nothing was sent: the transport refused it, or the pass had nothing to say. The
// caller reports it its own way -- from the player's side there is no difference between the
// two, and neither has cost anything.
func AiNpcPassSend(builder: ref<AiNpcPassBuilder>, provider: AiNpcProvider, contactId: String,
                   target: wref<IScriptable>, httpMethod: CName, requestId: Int32) -> ref<AiNpcPassRequest> {
    if !IsDefined(builder) || !builder.Ready() {
        return null;
    }

    let pass = builder.Pass();
    let slot = AiNpcGetSlotForPass(pass);
    // Bound to locals: the record measures each half, and a serialised body cannot be taken
    // apart again.
    let instruction = builder.Instruction();
    let ask = builder.Ask();
    let body = AiNpcLlmChatBody(provider, slot, instruction, ask);

    let record = AiNpcRequestRecord.Sent(pass, contactId, provider, slot,
        AiNpcRecipeNameOf(builder.Recipe()), instruction, ask);

    if !AiNpcSendChat(provider, body, requestId) {
        return null;
    }

    // Debug Mode's, not Enable Logs': the whole body, once per request. Enable Logs gets the
    // record line instead, safe to paste into a bug report.
    if AiNpcDebugEnabled() {
        AiNpcLog(s"== \(pass) POST \(AiNpcLlmChatUrl(provider)) ==");
        AiNpcLog(body);
    }

    let request = new AiNpcPassRequest();
    request.slot = slot;
    request.record = record;
    return request;
}
