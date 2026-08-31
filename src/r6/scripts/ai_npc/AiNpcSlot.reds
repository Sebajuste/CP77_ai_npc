// A slot: the model and the request parameters one kind of work is sent with.
//
// THE KEYS ARE THE PROTOCOL'S, AND THE MOD DOES NOT READ THEM. `max_tokens`, `temperature`,
// `top_p`, whatever a provider ships next -- the file writes request JSON, and the overlay
// copies it onto the body the mod built. That is what lets a parameter added by a provider
// tomorrow work tomorrow, with no accessor, no setting and no release. The price is that a
// mistyped key is not refused here: it goes out and comes back a 400, which is why the
// request log names the slot that produced it.
//
// Two keys are held out of the copy, for two different reasons:
//
//   timeoutSeconds  ours, never sent. camelCase carries the boundary -- snake_case goes on
//                   the wire, camelCase stays here -- so a reader can see it without a list.
//   model           the provider owns it on the CLI lanes: a slot naming an OpenRouter model
//                   must not reach a `claude` process. Resolved once, in AiNpcLlmSlotModel.
//
// Pure over a JsonObject: no storage, no session. AiNpcGetSlot in AiNpcSettings.reds is the
// one impure half, and it is one read.

module AiNpc

import RedData.Json.*

class AiNpcSlot {
    let name: String;
    let model: String;
    // 0 means the provider's own budget, which is what AiNpcLlmRequestTimeout answers.
    let timeoutSeconds: Int32;
    let params: ref<JsonObject>;
}

// The slot every other one is resolved against, and the one an unnamed pass uses.
func AiNpcSlotDefaultName() -> String {
    return "dialogue";
}

// The whole reserved list, and tools\lint.ps1 fails the day a second file writes this word.
// A second reserved key is a decision, not a convenience.
func AiNpcSlotTimeoutKey() -> String {
    return "timeoutSeconds";
}

/// Resolution ///

// Key by key, with `dialogue` as the base: "the slot is empty" and "the slot says nothing
// about this parameter" become one case. An unknown name resolves to the base rather than to
// nothing, so a file written for a later version -- which may name a slot this one has never
// heard of -- still sends what it always sent.
//
// THE MORE SPECIFIC WINS: named slot, then the dialogue slot, then the settings that predate
// the format. A file with no `slots` block behaves exactly as it always has -- the aliases are
// then the only thing there is -- and a file that has one is edited where it can be read.
//
// A preset writes slots.dialogue.model, so the aliases have to lose: an openRouterModel left in
// the file from before would otherwise shadow it, and the preset would appear to do nothing.
func AiNpcSlotFrom(slots: ref<JsonObject>, name: String, aliases: ref<JsonObject>) -> ref<AiNpcSlot> {
    let slot = new AiNpcSlot();
    slot.name = name;
    slot.params = new JsonObject();

    AiNpcSlotAbsorb(slot, aliases);
    AiNpcSlotAbsorb(slot, AiNpcSlotObjectAt(slots, AiNpcSlotDefaultName()));
    if NotEquals(name, AiNpcSlotDefaultName()) {
        AiNpcSlotAbsorb(slot, AiNpcSlotObjectAt(slots, name));
    }
    return slot;
}

func AiNpcSlotObjectAt(owner: ref<JsonObject>, key: String) -> ref<JsonObject> {
    if !IsDefined(owner) || !owner.HasKey(key) {
        return null;
    }
    let value = owner.GetKey(key);
    if !IsDefined(value) || !value.IsObject() {
        return null;
    }
    return value as JsonObject;
}

func AiNpcSlotAbsorb(slot: ref<AiNpcSlot>, source: ref<JsonObject>) -> Void {
    if !IsDefined(source) {
        return;
    }
    let keys = source.GetKeys();
    let i = 0;
    let count = ArraySize(keys);
    while i < count {
        let key = keys[i];
        if !StrBeginsWith(key, "_") {
            if Equals(key, "model") {
                slot.model = AiNpcJsonString(source, key);
            } else {
                if Equals(key, AiNpcSlotTimeoutKey()) {
                    slot.timeoutSeconds = AiNpcJsonInt(source, key, slot.timeoutSeconds);
                } else {
                    slot.params.SetKey(key, source.GetKey(key));
                }
            }
        }
        i += 1;
    }
}

// The two settings that predate the slots, translated to their wire names. THE ONLY PLACE a
// wire parameter is written out in redscript: everywhere else the overlay copies what the
// file said.
//
// Absence is the file's, not the accessor's. `maxTokens` reads 0 and `reasoningEffort` reads
// "" when nobody wrote them, and both mean "send no key" -- the same thing they meant before
// slots existed. `model` is passed in already resolved, and empty when the file says nothing:
// its accessor has a built-in default, which is the provider's answer rather than a written
// opinion, and a slot resolving to it would read as one.
func AiNpcSlotAliases(model: String, maxTokens: Int32, reasoningEffort: String) -> ref<JsonObject> {
    let aliases = new JsonObject();
    if NotEquals(StrLen(model), 0) {
        aliases.SetKeyString("model", model);
    }
    if maxTokens > 0 {
        aliases.SetKeyInt64("max_tokens", Cast<Int64>(maxTokens));
    }
    if NotEquals(StrLen(reasoningEffort), 0) {
        aliases.SetKeyString("reasoning_effort", reasoningEffort);
    }
    return aliases;
}

// The one parameter the mod writes rather than copies: a preset ships an output ceiling, and
// the ceiling is a bound on a runaway, not a choice about a model. Written HERE because this
// file is where a wire name is allowed to appear -- everywhere else the overlay copies what the
// file said, and tools\lint.ps1 fails the day a second file spells one.
func AiNpcSlotSetMaxTokens(slot: ref<JsonObject>, maxTokens: Int32) -> Void {
    if !IsDefined(slot) || maxTokens <= 0 {
        return;
    }
    slot.SetKeyInt64("max_tokens", Cast<Int64>(maxTokens));
}

// The second parameter a preset writes, and the same rule about where it may be spelled.
//
// A TECHNICAL CALL HAS NOTHING TO DELIBERATE. The repair rewrites one bracket; the selection
// reads a decision already taken in prose and transcribes it. Neither is a judgement a draft
// improves, and both are paid for on every message.
//
// Measured 2026-08-31 in ai_npc_lab\action-bench, nvidia/nemotron-3-super-120b:free, 50 items
// of the action selection. With reasoning left on, at the 500-token ceiling below: median
// output 500 -- the ceiling exactly -- of which 386 was a draft nobody reads, 6 answers in 19
// cut off, 6.6 s each. With reasoning off: median output THREE tokens, longest 32, not one
// truncation in 34 answers, 1.4 s, and no false positive on 22 negatives. The ceiling stops
// being a constraint the moment the draft stops being paid for.
//
// "effort": "low" is not this setting. On the same model it moved 386 reasoning tokens to 370
// -- it is a hint, and a hint is not a bound.
//
// THE ONE THING IT COSTS: a provider may refuse it. liquid/lfm-2.5-2.6b:free answers HTTP 400,
// "Reasoning is mandatory for this endpoint and cannot be disabled." The refusal is named in
// the log by whoever sent the request, and a player on such a model deletes the key. That is
// the price of a slot format that copies rather than validates, and it is paid in the open.
func AiNpcSlotDisableReasoning(slot: ref<JsonObject>) -> Void {
    if !IsDefined(slot) {
        return;
    }
    let reasoning = new JsonObject();
    reasoning.SetKeyBool("enabled", false);
    slot.SetKey("reasoning", reasoning);
}

/// The overlay ///

// Applied to the serialised body rather than to a DTO, because a DTO field is always emitted:
// `"max_tokens": 0` is not unset, it is a value, and it is rejected with a 400. A key that
// must sometimes not exist cannot be a field on a class whose serialiser writes every field.
func AiNpcSlotOverlay(root: ref<JsonObject>, slot: ref<AiNpcSlot>) -> Void {
    if !IsDefined(root) || !IsDefined(slot) || !IsDefined(slot.params) {
        return;
    }
    let keys = slot.params.GetKeys();
    let i = 0;
    let count = ArraySize(keys);
    while i < count {
        root.SetKey(keys[i], slot.params.GetKey(keys[i]));
        i += 1;
    }
}

func AiNpcSlotModelOr(slot: ref<AiNpcSlot>, fallback: String) -> String {
    if IsDefined(slot) && NotEquals(StrLen(slot.model), 0) {
        return slot.model;
    }
    return fallback;
}

func AiNpcSlotNameOf(slot: ref<AiNpcSlot>) -> String {
    if !IsDefined(slot) {
        return AiNpcSlotDefaultName();
    }
    return slot.name;
}

/// Reporting ///

// The one thing about a slot the mod can check: that it is an object. A parameter inside it
// is the provider's business, and a slot written as a string is a file that will send nothing
// it meant to.
func AiNpcSlotReportShapes(slots: ref<JsonObject>, fileName: String,
                           out issues: array<ref<AiNpcConfigIssue>>) -> Void {
    if !IsDefined(slots) {
        return;
    }
    let keys = slots.GetKeys();
    let i = 0;
    let count = ArraySize(keys);
    while i < count {
        if !StrBeginsWith(keys[i], "_") && !IsDefined(AiNpcSlotObjectAt(slots, keys[i])) {
            ArrayPush(issues, AiNpcConfigIssueOf("error", fileName,
                s"slots.\(keys[i]) is not an object; it is ignored."));
        }
        i += 1;
    }
}

func AiNpcSlotDeclared(slots: ref<JsonObject>, name: String) -> Bool {
    return IsDefined(AiNpcSlotObjectAt(slots, name));
}
