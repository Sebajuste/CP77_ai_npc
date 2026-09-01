// The send, and the only place that knows there is more than one way to send.
//
// Both lanes call this and neither tests the provider: AiNpcHttp.reds and
// AiNpcMemoryService.reds must not name a native type, because the file that names one can
// stop the game booting when the plugin is absent (AiNpcCliNative says why). `AiNpcCli` is
// mentioned in exactly one place, so that blast radius is one file instead of three.
//
// What the plugin runs is not only the CLI lanes any more: the streaming OpenRouter lane goes
// through the same Send, because what it needs from script is the same body and the same request
// id. Which is why the question asked here is "does the plugin run it", not "is it a CLI".
//
// The switch is at home beside the ones AiNpcLlm.reds carries -- url, model, headers,
// timeout, credentials -- so adding a provider means touching those five answers and this one.
//
// Nothing here holds state. Which lane is waiting for the answer is carried by the callback
// on the HTTP side and by the request id on the CLI side -- see AiNpcCliRequest.

module AiNpc


// Sends one chat-shaped request and returns whether it left.
//
// `target` and `httpMethod` address the answer on the HTTP transport; `requestId` addresses
// it on the CLI transport. Both are passed always, because which one is used is precisely
// what the caller must not have to know.
//
// False means nothing was sent and nothing will be delivered. The caller reports it the same
// way it reports any other failure -- there is no separate ending for "the transport refused
// it", because from the player's side there is no difference.
func AiNpcSendChat(provider: AiNpcProvider, body: String, requestId: Int32) -> Bool {
    // The provider is named rather than numbered on the way across: the plugin has its own
    // registry keyed by that name, and a number would make the two halves agree by coincidence
    // of ordering rather than by saying the same word.
    return AiNpcCli.Send(AiNpcProviderName(provider), body, requestId);
}
