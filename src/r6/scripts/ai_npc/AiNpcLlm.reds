// What a chat-shaped request to the configured backend looks like. The mod makes two kinds of
// call that must not share state:
//
//   speaking  in character, to the player. Drives the typing indicator and the input field,
//             and reports its failures. Owned by AiNpcHttpSystem.
//   thinking  out of character, about the conversation. Invisible, and silent on failure.
//             Owned by AiNpcMemoryService.
//
// They share one answer -- which endpoint, which model, which headers, and is this backend
// usable -- and it has exactly one definition here, or the day a provider is added the two
// lanes start disagreeing about what is configured. Each keeps its own in-flight state and
// callbacks, which is what stops a background compaction greying out the player's input.
//
// Nothing here holds state or touches the game: building a request is a pure function of the
// settings, and sending it belongs to the lane that owns the answer.

module AiNpc

import RedData.Json.*

/// Wire shapes ///

public class AiNpcChatMessageDTO {
    public let role: String;
    public let content: String;
}

public class AiNpcOpenAIRequestDTO {
    public let model: String;
    public let messages: array<ref<AiNpcChatMessageDTO>>;
}

public class AiNpcProviderDTO {
    public let order: array<String>;
    public let allow_fallbacks: Bool;
}

public class AiNpcOpenRouterRequestDTO {
    public let model: String;
    public let messages: array<ref<AiNpcChatMessageDTO>>;

    public let provider: ref<AiNpcProviderDTO>;
}

/// Backend description ///

// Three questions about a backend, and they cut the four lanes three different ways. Kept apart
// because merging any two of them is how a lane ends up configured like its neighbour: the
// streaming lane runs in the plugin like a CLI lane, and is OpenRouter in every other respect.

// Whether ai_npc.dll runs it. Asked in exactly one place, AiNpcSendChat.
// Toutes les voies passent maintenant par ai_npc.dll. La fonction reste parce qu'elle nomme un
// fait -- « c'est le plugin qui parle au reseau » -- et qu'un jour ou une voie ne le ferait plus,
// c'est ici que ca se dirait plutot que dans un test disperse.
func AiNpcProviderIsNative(provider: AiNpcProvider) -> Bool {
    return true;
}

// Whether it is a coding-agent CLI. What hangs on this is the model namespace and the absence of
// a key -- not the transport.
func AiNpcProviderIsCli(provider: AiNpcProvider) -> Bool {
    return Equals(provider, AiNpcProvider.ClaudeCli) || Equals(provider, AiNpcProvider.CodexCli);
}

// Whether it is OpenRouter, by whichever pipe. Same endpoint, same key, same model namespace, so
// everything a player configures is shared and the menu shows one set of rows for both.
func AiNpcProviderIsOpenRouter(provider: AiNpcProvider) -> Bool {
    return Equals(provider, AiNpcProvider.OpenRouter);
}

// Where the request goes. The CLI lanes have no endpoint, and "" would be worse than useless:
// the url is what the failure log names, so a lane without one reports every failure as though
// it had never been addressed. A scheme nobody dials keeps those lines readable.
func AiNpcLlmChatUrl(provider: AiNpcProvider) -> String {
    switch provider {
        case AiNpcProvider.OpenRouter:
            return "https://openrouter.ai/api/v1/chat/completions";
            // Not the https:// url it dials: nothing in script sends this request, so a lane
            // reading this string must not be told to look for a TLS problem it cannot have.
            return "plugin://openrouter";
        case AiNpcProvider.ClaudeCli:
            return "cli://claude";
        case AiNpcProvider.CodexCli:
            return "cli://codex";
        default:
            return "";
    }
}

// What the request says it wants, once, for the body and for the log line that has to name
// the same thing.
//
// A CLI lane keeps its own: the slot format is OpenRouter's namespace -- `deepseek/...`
// against `sonnet` -- so a slot naming a model must not reach a `claude` process. Everything
// else about a slot applies to those lanes, because the plugin is handed the body an HTTP
// lane would have posted.
func AiNpcLlmSlotModel(provider: AiNpcProvider, slot: ref<AiNpcSlot>) -> String {
    let own = AiNpcLlmChatModel(provider);
    if AiNpcProviderIsCli(provider) {
        return own;
    }
    return AiNpcSlotModelOr(slot, own);
}

func AiNpcLlmChatModel(provider: AiNpcProvider) -> String {
    switch provider {
        case AiNpcProvider.OpenRouter:
            return AiNpcGetOpenRouterModel();
        case AiNpcProvider.ClaudeCli:
            return AiNpcGetClaudeCliModel();
        case AiNpcProvider.CodexCli:
            return AiNpcGetCodexCliModel();
        default:
            return "";
    }
}

// How long one leg of a request may stay silent -- a single exchange with the backend, not a
// whole generation.
//
// The numbers differ because the backends do: a cloud completion is already late at a minute
// and a half, while a CLI lane starts a process, an auth check and a session handshake before
// a token is generated. Both err generous: the point is to end an infinite wait, not to
// enforce a deadline.
//
// On a CLI lane this is the backstop, not the deadline: the plugin runs its own shorter clock
// and answers with a typed "timed out", and this only fires when the plugin never answers.
//
// A slot may say otherwise, and `timeoutSeconds` is reserved for exactly that: it is the one
// thing about a request that never goes on the wire, so it has no path out of the body.
func AiNpcLlmRequestTimeout(provider: AiNpcProvider, slot: ref<AiNpcSlot>) -> Float {
    if IsDefined(slot) && slot.timeoutSeconds > 0 {
        return Cast<Float>(slot.timeoutSeconds);
    }
    // Both plugin lanes get the backstop rather than the deadline: the plugin runs its own
    // shorter clock and answers with a typed failure, and this only fires when it never answers
    // at all.
    if AiNpcProviderIsNative(provider) {
        return 240.0;
    }
    return 90.0;
}

// "" when the backend is usable, otherwise the sentence explaining what is missing. One
// definition for both lanes, used for opposite purposes: the speaking lane turns it into a log
// line and a carrier message, the thinking lane treats a non-empty answer as "not now".
//
// The CLI lanes answer "" on purpose: whether the executable is there and the player signed in
// is knowable only by running it, in the scrubbed environment the request will use. Answering
// from a stale setting would declare a lane unusable that the player cannot then turn back on.
//
// The default branch names an unknown backend rather than returning "": a provider setting left
// over from an older build used to send a request to an empty url and fail with nothing to read.
func AiNpcLlmCredentialIssue(provider: AiNpcProvider) -> String {
    switch provider {
        case AiNpcProvider.OpenRouter:
            let key = AiNpcGetOpenRouterApiKey();
            if Equals(key, "0000000000") || StrLen(key) < 10 {
                return "no openRouterApiKey set in r6\\storages\\AiNpc\\settings.json";
            }
            return "";
        case AiNpcProvider.ClaudeCli:
            return "";
        case AiNpcProvider.CodexCli:
            return "";
        default:
            return "the selected provider no longer exists in this version - pick another one in Mod Settings";
    }
}

// Les en-tetes ne sont plus construits ici : ai_npc.dll ecrit les siens, dans
// OpenRouterStream.cpp, parce que c'est lui qui tient la connexion. Ce qui vivait ici servait
// RedHttpClient, qui n'est plus une dependance de ce mod.

/// Request bodies ///

func AiNpcLlmChatMessage(role: String, content: String) -> ref<AiNpcChatMessageDTO> {
    let message = new AiNpcChatMessageDTO();
    message.role = role;
    message.content = content;
    return message;
}

// The instruction and the ask, in the two roles the protocol names: "system" and "user" are
// the wire's words, and they are the only place those words are right. A JSON string rather
// than a DTO because the backends do not share a shape -- OpenRouter carries a routing
// preference nothing else accepts -- and that choice is what callers must not have to make
// twice.
//
// The plain shape is what the CLI lanes are handed too: the plugin receives the body an HTTP
// lane would have posted and answers in the same dialect, so the mod keeps one request builder
// and one response parser for every backend.
func AiNpcLlmChatBody(provider: AiNpcProvider, slot: ref<AiNpcSlot>,
                      instructionText: String, askText: String) -> String {
    if AiNpcProviderIsOpenRouter(provider) {
        let request = new AiNpcOpenRouterRequestDTO();
        request.model = AiNpcLlmSlotModel(provider, slot);
        ArrayPush(request.messages, AiNpcLlmChatMessage("system", instructionText));
        ArrayPush(request.messages, AiNpcLlmChatMessage("user", askText));

        let preferred = AiNpcGetOpenRouterProvider();
        if NotEquals(preferred, "Auto") && StrLen(preferred) > 0 {
            let routing = new AiNpcProviderDTO();
            ArrayPush(routing.order, preferred);
            routing.allow_fallbacks = true;
            request.provider = routing;
            AiNpcLog("OpenRouter: Routing preference set to " + preferred);
        }
        return AiNpcLlmWithSlot(ToJson(request), slot);
    }

    let request = new AiNpcOpenAIRequestDTO();
    request.model = AiNpcLlmSlotModel(provider, slot);
    ArrayPush(request.messages, AiNpcLlmChatMessage("system", instructionText));
    ArrayPush(request.messages, AiNpcLlmChatMessage("user", askText));
    return AiNpcLlmWithSlot(ToJson(request), slot);
}

// The slot's parameters, applied to both body shapes so the two cannot end up tunable one way
// and not the other. What the overlay does and why it copies rather than reads is
// AiNpcSlot.reds; this is only where it meets a serialised request.
func AiNpcLlmWithSlot(body: ref<JsonVariant>, slot: ref<AiNpcSlot>) -> String {
    let root = body as JsonObject;
    if !IsDefined(root) {
        return body.ToString();
    }
    AiNpcSlotOverlay(root, slot);
    return root.ToString();
}

/// Diagnosis ///

// Display name of a provider, matching the Mod Settings labels closely enough to be searched
// for by someone reading the log next to the menu. Also the word sent across to the plugin,
// which routes on it: a contract with Registry.cpp for the CLI lanes and with
// OpenRouterStream.cpp, not just a label.
func AiNpcProviderName(provider: AiNpcProvider) -> String {
    switch provider {
        case AiNpcProvider.OpenRouter:
            return "OpenRouter";
        case AiNpcProvider.ClaudeCli:
            return "ClaudeCli";
        case AiNpcProvider.CodexCli:
            return "CodexCli";
    }
    return "unknown";
}

// Turns a transport-level failure into something the player can act on. Status 0 is the only
// fact available: the request came back with no status, so it never got an answer from the
// socket, and which end refused it is invisible from redscript.
//
// So this states the fact and lists the causes rather than picking one. It used to answer
// "bridge unreachable - needs RedHttpClient 0.7.1+ AND -no-tls", phrased as a diagnosis, and
// on 2026-08-22 a status 0 whose real cause was a body that was not valid UTF-8 sent the
// debugging after a launch flag for a day.
//
// The url decides which list is shown, and reading the url rather than a global keeps this
// pure. The one that matters most: -no-tls does not permit http:// alongside https://, it
// turns TLS off, so a flag left over from the old local bridge breaks the only HTTP lane
// there now is.
func AiNpcDescribeTransportFailure(url: String, fallback: String) -> String {
    if StrBeginsWith(url, "https://") {
        return "no answer at all (status 0): the request never left the client. Could be: the provider or the network is unreachable; the game launched with -no-tls, which turns TLS off and refuses every https:// provider - it is no longer needed by any lane and should be removed; or a request the client would not send";
    }

    // A CLI lane never had a socket to fail on: what went wrong is whatever the plugin said,
    // and it said it in the fallback.
    return fallback;
}
