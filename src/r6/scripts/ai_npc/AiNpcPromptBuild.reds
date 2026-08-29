// Which blocks, in which order, with what between them. The pair to AiNpcPromptSections.reds,
// which decides how each section is chosen.
//
// Free functions rather than methods: given a contact id and the pending context, the same
// prompt comes out, and it can be built from a diagnostic or a test with no request in
// flight.
//
// Nothing here consumes anything. The pending context is passed in, already taken by the
// caller on the line that sends: a builder that took it itself would mean looking at a prompt
// spends a mod's seeded context.

module AiNpc

/// What the prompt is built from ///

// The conversation is read through AiNpcConversationApi: building a prompt is a reader like
// any other and gets no shortcut.

// What the transcript sends verbatim. With memory on that is the whole stored list, because
// the stored list is exactly the part not absorbed yet -- eviction happens at compaction
// time -- so sending less would drop messages nothing remembers. It settles to six turns
// after each compaction and grows back to sixteen before the next.
//
// With memory off the window is what the mod sent before memory existed. The store keeps the
// same messages either way.
func AiNpcPromptWindow(contactId: String) -> array<ref<AiNpcMessage>> {
    let history = AiNpcStoredMessages(contactId);
    if AiNpcMemoryEnabled() {
        return history;
    }
    return AiNpcHistoryTrim(history, AiNpcMemoryLegacyMaxTurns());
}

// Three ways it comes back empty, none of them an error: the setting is off, the provider
// says this contact does not remember, or no compaction has succeeded yet -- the normal state
// of every conversation for its first sixteen turns.
func AiNpcRenderMemoryBlock(contactId: String) -> String {
    if !AiNpcMemoryEnabled() {
        return "";
    }

    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) && !provider.AllowsMemory() {
        return "";
    }

    return AiNpcMemoryRenderAt(AiNpcStoredMemory(contactId), AiNpcGetCurrentGameTimeSeconds());
}

/// The system prompt ///

// One tagged section, or nothing when it has nothing to say. The single place that rule
// lives, so it cannot be true of one tag and false of the next.
//
// An empty tag is not harmless: `<quest></quest>` is a heading with a blank under it, and
// a model reading a blank field is invited to fill it in. That is how a character acquires a
// quest nobody gave it.
func AiNpcSection(tag: String, body: String) -> String {
    if Equals(StrLen(body), 0) {
        return "";
    }
    return "<" + tag + ">" + body + "</" + tag + ">";
}

// Keyed by the contact id it was handed. Nothing reads the current selection, so the prompt
// describes the character the request is for even if the player is looking at somebody else.
//
// Blocks are assembled in order of increasing volatility: everything invariant first --
// rules, character, V, relationship, world -- then the memory, rewritten once every ten
// turns, then the quest state, the seeded context and the clock, which change every message.
//
// OpenAI-compatible backends discount a repeated prefix from around a thousand tokens, and
// the identical prefix ends at the first thing that moves, so one volatile line high up makes
// the discount unreachable for the whole prompt. This ordering keeps ~1400 tokens of corpus
// above that point; a new block goes where its volatility says.
//
// The closing <explicitness> stays last despite being invariant: it is a recency device, one line, and
// everything after the cacheable prefix is uncached anyway.
func AiNpcBuildSystemPrompt(contactId: String, pendingContext: String,
                                   opt intentOverride: String) -> String {
    let prompt = "";

    let systemRules = AiNpcGetSystemRules(contactId);

    let provider = AiNpcProviderFor(contactId);

    // Built once and handed to every extension question below, so a dozen contributions do
    // not mean a dozen quest-fact reads.
    let ctx = AiNpcBuildContactContext(contactId);

    // A statement that had nowhere to land settles here: the first moment the conversation is
    // certainly present. Retrying at a point the code already reaches beats a notification
    // path that has to stay correct forever.
    let clients = AiNpcGetClientRegistry();
    if IsDefined(clients) {
        clients.Flush(contactId);
    }

    /// Invariant ///
    // Everything from here down goes through AiNpcSection, so a section with nothing to say
    // does not appear at all.


    prompt += "<|start_header_id|> system: <|end_header_id|>";
    prompt += "<system>";
    // The one sentence nobody may drop, which is why it is here and not in <system_rules>:
    // the rubrics there are contributable by key, and a character another mod registers
    // carries whatever that mod wrote and nothing else.
    //
    // It names the fiction, the two parties, and the assistant register with the three
    // tells that give it away -- therapist tone, disclaimers, meta-text. Those are here
    // rather than in <system_rules> for the same reason as the rest of this line: the rules
    // are replaceable and this claim may not be. What stays in NEVER is the sycophancy,
    // which is a way of talking rather than a way of breaking the fiction.
    //
    // Naming the parties is the half a thin third-party bio leaves out. "In the video game",
    // which this replaced, placed the conversation inside a piece of software -- an
    // invitation to exactly the meta-text forbidden on the same line.
    //
    // Identical for every contact and every save, so it lengthens the shared prefix instead of
    // breaking it -- the one addition here that costs nothing under prefix caching.
    prompt += "<fiction>This is fiction. You are a character from Cyberpunk 2077, not an assistant, texting V on a phone. No therapist or customer-service tone, no disclaimers, no meta-text.</fiction>";
    prompt += systemRules;
    prompt += "</system>";
    prompt += AiNpcGetConversationTypePrompt(contactId);
    // The bio, plus whatever another mod added. AiNpcWorldBackgroundWith is the joiner the
    // world background uses: one newline, the addition after the original.
    prompt += AiNpcSection("character",
        AiNpcWorldBackgroundWith(AiNpcGetCharacterBio(contactId),
                                 AiNpcCharacterAdditionsText(contactId)));
    // Omitted whole rather than emitted empty: a contact that has never met V says nothing
    // about V, and an empty <player></player> reads as a person with no attributes.
    let playerSection = AiNpcGetPlayerSection(contactId);
    if NotEquals(StrLen(playerSection), 0) {
        prompt += "<player>" + playerSection + "</player>";
    }
    prompt += AiNpcSection("relationship", AiNpcGetRelationship(contactId));
    // Rendered with its own tag, like <system_rules>: a composed block knows whether it has
    // anything to say, and AiNpcSection would wrap it a second time.
    prompt += AiNpcGetWorldInteractions(contactId);
    prompt += AiNpcSection("world_background", AiNpcGetWorldBackground(contactId));

    // Two blocks, and they answer different questions. <mechanics> is prose about how the world
    // works, which most characters have nothing to say about. <commands> is the vocabulary,
    // rendered from the very table the reply will be dispatched against -- so what the model is
    // told it may do and what this mod will honour are one object rather than two computations
    // that have to be kept in agreement.
    prompt += AiNpcSection("mechanics", AiNpcGetWorldMechanics(contactId));

    prompt += AiNpcRenderActionBlock(ctx, AiNpcBuildActionTable(contactId));
    // No <language> section: the language rule and the per-contact register are stated in
    // <system_rules> only. A second copy 8000 characters down does not read as emphasis, it
    // reads as a new instruction, and a prompt that says one thing twice teaches a model it
    // has layers to arbitrate between. A provider overriding languagePrompt is unaffected --
    // AiNpcGetGuidelines calls the same getter.

    /// Volatile ///

    // Rewritten roughly once every ten turns, so it sits below the corpus and above the
    // per-message blocks. Absent until a first compaction has succeeded.
    let memoryBlock = AiNpcRenderMemoryBlock(contactId);
    if NotEquals(StrLen(memoryBlock), 0) {
        prompt += "<memory>" + memoryBlock + "</memory>";
    }

    // The two sections the tracked quest decides, and one journal walk for both. By contact
    // id, never by display name: the name is overridable, so keying the quest table on it made
    // renaming a contact delete its quest context silently.
    //
    // No built-in test: GetQuestContext is on the base provider class and answerable by
    // anyone, so gating on "is this one of ours" made a public method dead for every caller
    // outside this mod. A contact with nothing to say answers "" and contributes no section.
    let questKey = AiNpcContactQuestKey(contactId);

    // Durable, or whatever the tracked quest replaced it with. Above <quest> because it is
    // the frame the mission is read through.
    // The contact's own, then what every extension wants of V through them: appended, never
    // replacing, and in the registry's id order -- see AiNpcExtensionIntent.
    let intent = AiNpcExpandTemplateFor(contactId,
        AiNpcIntentOf(contactId, questKey, intentOverride));
    prompt += AiNpcSection("intent", AiNpcJoinLines(intent, AiNpcExtensionIntent(ctx)));
    prompt += AiNpcSection("quest", AiNpcQuestContext(contactId, questKey));
    prompt += "<now>";
    // The clock, and not in <system>: the most volatile thing in the prompt, so its position
    // decides where the cacheable prefix ends.
    prompt += "It is " + AiNpcGetCurrentTime() + ".\n";
    // State, not news: the sky is the same for both ends of the conversation, so a character
    // reads it without being told where V is.
    prompt += AiNpcWeatherLine();
    prompt += pendingContext;
    if IsDefined(provider) {
        // Terminated here rather than by whoever wrote it: every other contributor to <now>
        // ends its own line, but this is a sheet field, and the alternative is asking every
        // character file to remember a trailing newline. The one that forgets runs into the
        // romance rubric on the same line.
        let live = AiNpcExpandTemplateFor(contactId,
            AiNpcSafeSectionText(provider.GetLiveContext(), contactId));
        if NotEquals(StrLen(live), 0) {
            prompt += live + "\n";
        }
    }
    prompt += AiNpcExtensionLiveContext(ctx);
    prompt += "</now>";

    // Last block before the end token: whatever states the register last is what the model is
    // still holding when it starts writing.
    let closingRule = AiNpcGetToneReminder(contactId);
    if NotEquals(StrLen(closingRule), 0) {
        prompt += "<explicitness>" + closingRule + "</explicitness>";
    }
    prompt += "<|eot_id|>";

    return prompt;
}

/// The transcript ///

// Transcript plus V's turn, for chat APIs where the system prompt is a separate message. The
// clock is read here and handed to the pure renderer: the trailing gap marker measures the
// silence up to the line V is sending now, so it lands between the last stored message and
// the "V: " below.
func AiNpcBuildTranscript(contactId: String, playerInput: String) -> String {
    return AiNpcTranscriptEndingOn(contactId, "V: " + playerInput);
}

// The same transcript, ending on a reason instead of on a line of V's -- the whole of what
// CharacterWantsToSay needs from the prompt.
//
// The reason goes here and not in <now>. Measured 2026-08-23 against a captured prompt
// (ai_npc_lab\unprompted), on a reason the transcript cannot imply -- V's birthday. Seeded into
// <now>, it was the subject of the message 0 times out of 8, an afterthought 4 times and
// dropped 4 times; in the position V's line occupied, the subject 8 times out of 8. <now>
// holds statements about the world, so a reason among them becomes one more thing she happens
// to know, and it sits thousands of tokens above where the turn is handed over.
//
// Do not also seed it into <now> for emphasis: one subject, one block, one position.
//
// A silence validates nothing, so it cannot be tested there: on "no message for three days",
// cutting V's line and adding nothing already produces a good message, because the trailing
// gap marker carries it.
//
// The reason is arbitrary text from a third-party mod, flattened through AiNpcTranscriptLine
// like every stored message, so a newline in it cannot open a line of its own and forge
// "V: ..." into the transcript. That is the only injection this prompt is open to.
//
// The parentheses and the dedicated line are the gap markers' convention, which is already
// how this transcript says something nobody speaks and is defined never to touch the
// "V: " / "<name>: " grammar the stop sequences rely on.
func AiNpcBuildUnpromptedTranscript(contactId: String, reason: String) -> String {
    return AiNpcTranscriptEndingOn(contactId, AiNpcTranscriptReasonLine(reason));
}

// Its own function because it is the whole of the injection guard, and a guard applied at a
// call site is one somebody adds a second call site without.
func AiNpcTranscriptReasonLine(reason: String) -> String {
    return "(" + AiNpcTranscriptLine(reason) + ")";
}

// The last line, then the turn handed over mid-sentence. The single place these tokens are
// written: the model is asked to continue "<name>: ", so a byte differing between the two
// endings changes what is asked on one path and not the other, and nothing downstream would
// report it.
func AiNpcTranscriptHandover(npcName: String, lastLine: String) -> String {
    return lastLine + " <|eot_id|><|start_header_id|>character<|end_header_id|>\n\n" + npcName + ": ";
}

// One function for both, so the only difference between answering V and writing first is the
// line handed in.
func AiNpcTranscriptEndingOn(contactId: String, lastLine: String) -> String {
    let npcName = AiNpcGetCharacterName(contactId);
    let history = AiNpcHistoryTranscriptAt(AiNpcPromptWindow(contactId), npcName, AiNpcGetCurrentGameTimeSeconds());

    return history + AiNpcTranscriptHandover(npcName, lastLine);
}
