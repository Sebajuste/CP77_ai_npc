module AiNpc

import RedData.Json.*

// Getting the reply out of a provider's answer, whatever shape it turns out to be in.
//
// Everything here reads through AiNpcJson, so an error object, a proxy's HTML page or a
// truncated payload degrades into "no text" rather than taking the callback down. What THIS
// file adds is where each provider puts the words, and the ways a reply can arrive that are
// not failures at all: a reasoning model answering in the wrong field, or with its own notes.

/// Provider-specific extraction ///

// What is left of a reply once the model's own deliberation is taken out of it.
//
// A reasoning model is under no obligation to keep its thinking out of the field the answer
// is read from, and two shapes are in circulation. Both arrive as a perfectly well-formed
// 200, so nothing else in this file sees anything wrong with them:
//
//   "<think>she's asking about the heist, keep it short</think>Yeah. Garage, an hour."
//   ""            -- with the whole turn in message.reasoning instead
//
// Untreated, the first puts the character's private notes in the chat bubble in the third
// person, and the second reads as "the character had nothing to say" and costs the player a
// message they paid for.
//
// One rule covers both: the reply is what lies OUTSIDE the think spans, and a span that was
// never closed runs to the end of the text -- which is a generation cut short by a token
// limit, where the notes are all that came back and the honest answer is nothing. Blanks left
// behind by a removed span go with it, so a content field that was only thinking reads as
// empty and falls through to the reasoning field below.
//
// Only `<think>` is recognised: a tag nobody emits is a branch nobody tests.
func AiNpcStripThinking(text: String) -> String {
    let opening = "<think>";
    let closing = "</think>";

    let kept = "";
    let rest = text;
    let start = StrFindFirst(rest, opening);
    while start >= 0 {
        kept += StrLeft(rest, start);
        rest = StrRight(rest, StrLen(rest) - (start + StrLen(opening)));

        let end = StrFindFirst(rest, closing);
        if end < 0 {
            return AiNpcTrimBothEnds(kept);
        }
        rest = StrRight(rest, StrLen(rest) - (end + StrLen(closing)));
        start = StrFindFirst(rest, opening);
    }
    return AiNpcTrimBothEnds(kept + rest);
}

// OpenAI and OpenRouter: choices[0].message.content
func AiNpcExtractChatText(root: ref<JsonObject>) -> String {
    let choices = AiNpcJsonArrayAt(root, "choices");
    let firstChoice = AiNpcJsonItemObject(choices, 0u);
    let message = AiNpcJsonObjectAt(firstChoice, "message");

    let content = AiNpcStripThinking(AiNpcJsonString(message, "content"));
    if NotEquals(StrLen(content), 0) {
        return content;
    }

    // Some routes put the turn in a separate field -- DeepSeek calls it reasoning_content,
    // OpenRouter normalises it to reasoning. Read only when content came back empty, so the
    // ordinary field always wins where both are present.
    let elsewhere = AiNpcJsonString(message, "reasoning_content");
    if Equals(StrLen(elsewhere), 0) {
        elsewhere = AiNpcJsonString(message, "reasoning");
    }
    return AiNpcStripThinking(elsewhere);
}

// Failures arrive in several shapes depending on the provider and on whether the
// request even reached it. Return whichever is present, or "" when none is.
func AiNpcExtractApiError(root: ref<JsonObject>) -> String {
    if !IsDefined(root) {
        return "";
    }

    // OpenAI / OpenRouter: { "error": { "message": "..." } }
    let errorObject = AiNpcJsonObjectAt(root, "error");
    if IsDefined(errorObject) {
        let nested = AiNpcJsonString(errorObject, "message");
        if NotEquals(StrLen(nested), 0) {
            // "Provider returned error" ne dit rien : OpenRouter enveloppe la reponse du
            // fournisseur, et ce que celui-ci reproche est dans metadata.raw. Sans cette
            // ligne, un refus pour cause de plafond de jetons et une panne de reseau se lisent
            // pareil dans le journal -- ce qui a coute une soiree le 2026-09-02.
            let metadata = AiNpcJsonObjectAt(errorObject, "metadata");
            if IsDefined(metadata) {
                let raw = AiNpcJsonString(metadata, "raw");
                if NotEquals(StrLen(raw), 0) {
                    return nested + " -- " + raw;
                }
            }
            return nested;
        }
    }

    // Several proxies answer this shape: { "message": "..." }
    let direct = AiNpcJsonString(root, "message");
    if NotEquals(StrLen(direct), 0) {
        return direct;
    }

    // { "error": "..." }
    return AiNpcJsonString(root, "error");
}

/// What the request cost ///

// The sentinel for "the provider did not say". Named rather than written as -1, because the
// whole point is that it is not a token count -- see AiNpcJsonInt.
func AiNpcTokensUnknown() -> Int32 {
    return -1;
}

// What a provider reported about the request it just answered.
//
// `known` is the measurement, not a convenience flag: usage is OPTIONAL on the wire, and a
// proxy that strips the block or a route that never fills it in answers without it. A record
// printing zeroes for those would say the day was free.
public class AiNpcUsage {
    public let known: Bool = false;
    public let promptTokens: Int32;
    public let completionTokens: Int32;
    public let totalTokens: Int32;

    // Both optional inside an optional block, so both carry the sentinel rather than 0:
    // "no cache discount" and "the provider does not report caching" are different facts,
    // and only the first one is worth changing a setting over.
    public let cachedTokens: Int32;
    public let reasoningTokens: Int32;
}

func AiNpcExtractUsage(root: ref<JsonObject>) -> ref<AiNpcUsage> {
    let usage = new AiNpcUsage();
    usage.promptTokens = AiNpcTokensUnknown();
    usage.completionTokens = AiNpcTokensUnknown();
    usage.totalTokens = AiNpcTokensUnknown();
    usage.cachedTokens = AiNpcTokensUnknown();
    usage.reasoningTokens = AiNpcTokensUnknown();

    let block = AiNpcJsonObjectAt(root, "usage");
    if !IsDefined(block) {
        return usage;
    }

    usage.promptTokens = AiNpcJsonInt(block, "prompt_tokens", AiNpcTokensUnknown());
    usage.completionTokens = AiNpcJsonInt(block, "completion_tokens", AiNpcTokensUnknown());
    usage.totalTokens = AiNpcJsonInt(block, "total_tokens", AiNpcTokensUnknown());
    usage.cachedTokens = AiNpcJsonInt(AiNpcJsonObjectAt(block, "prompt_tokens_details"),
        "cached_tokens", AiNpcTokensUnknown());
    usage.reasoningTokens = AiNpcJsonInt(AiNpcJsonObjectAt(block, "completion_tokens_details"),
        "reasoning_tokens", AiNpcTokensUnknown());

    // A block that is present but says nothing about the prompt is not a measurement. The
    // shape occurs: some proxies emit `"usage": {}` to satisfy clients that require the key.
    usage.known = usage.promptTokens != AiNpcTokensUnknown()
        || usage.completionTokens != AiNpcTokensUnknown()
        || usage.totalTokens != AiNpcTokensUnknown();
    return usage;
}

// Why the model stopped writing -- "stop", "length", "content_filter"...
//
// Read because a reply cut short by max_tokens looks exactly like a model that ignored its
// instructions: the command a turn was supposed to emit is the LAST thing in the text, so a
// truncation deletes precisely the evidence. See PROMPT_BUDGET.md.
func AiNpcExtractFinishReason(root: ref<JsonObject>) -> String {
    let choices = AiNpcJsonArrayAt(root, "choices");
    return AiNpcJsonString(AiNpcJsonItemObject(choices, 0u), "finish_reason");
}

// Whether the model was cut off by the output budget rather than finishing.
//
// The one answer a cap makes possible and nothing else does, so every lane that can be capped
// asks it: a truncated reply is not a bad reply, it is half a reply, and the half that is
// missing is the end -- where the command sits, and where a continuity note keeps its last
// section. Named here because "length" is the wire's word and no lane should have to know it.
func AiNpcReplyWasTruncated(root: ref<JsonObject>) -> Bool {
    return Equals(AiNpcExtractFinishReason(root), "length");
}
