// Running the commands a reply carries, and cleaning the reply of them.
//
// Everything here operates on text a language model wrote, so the ordering rule is the one
// that matters: WHAT IS OWNED IS DECIDED BEFORE WHAT IS OFFERED. A claim that has stopped
// offering its command still owns its tag, because between the prompt that advertised it and
// the reply that used it there was a network round trip, and the world moves inside it -- the
// player edits a config file, the last slot fills. The command was legitimately announced and
// legitimately emitted; refusing it is right, and leaving its bracket in the player's chat is
// not. That case reproduces only at the right quarter second, so it is designed for rather
// than tested for.
//
// Three outcomes for a bracket, and the third is the one that looks wrong until you know why:
//
//   owned, complete     handed to the handler, and stripped whatever the handler answers
//   owned, wrong arity  a real command fumbled -- offered to the repair pass, then stripped
//   owned by nobody     LEFT IN THE TEXT
//
// The last is deliberate. An unclaimed tag is a configuration error the load report already
// names, and stripping it here would hide that report -- the mod would look like it worked
// while a command nobody implements was quietly swallowed on every message.
module AiNpc

/// What came of a reply ///

public class AiNpcActionOutcome {
    public let text: String;

    // Still in the text, both of them, and for different reasons: `fumbled` names a command
    // that exists, so it must never reach the player; `unknown` names one nobody declared, so
    // it must.
    public let fumbled: array<String>;
    public let unknown: array<String>;

    // What the repair pass may ask the model to rewrite. Fumbled first: a command that exists
    // and was mis-typed is far likelier to be repairable than one that was invented whole.
    public func RepairCandidates() -> array<String> {
        let candidates = this.fumbled;
        let i = 0;
        let count = ArraySize(this.unknown);
        while i < count {
            ArrayPush(candidates, this.unknown[i]);
            i += 1;
        }
        return candidates;
    }
}

/// Applying ///

// contactId is the one captured at send time, never the selection now: this runs after a round
// trip, and the player may have opened somebody else.
func AiNpcApplyActions(contactId: String, text: String,
                       opt channel: AiNpcChannelId) -> ref<AiNpcActionOutcome> {
    let outcome = new AiNpcActionOutcome();
    outcome.text = text;

    let tags = AiNpcFindActionTags(text);
    let count = ArraySize(tags);
    if Equals(count, 0) {
        return outcome;
    }

    let ctx = AiNpcBuildContactContext(contactId, "", channel);
    let table = AiNpcBuildActionTable(contactId);
    ctx.tags = table.tags;      // as the renderer does, so a handler reads the same context here

    let i = 0;
    while i < count {
        let tag = tags[i];
        let lookup = table.Lookup(tag);

        if !lookup.Owned() {
            ArrayPush(outcome.unknown, tag);
        } else {
            if lookup.Complete() {
                AiNpcRunActionClaim(ctx, lookup.claim, tag, lookup.match.params);
                outcome.text = AiNpcReplaceAll(outcome.text, tag, "");
            } else {
                AiNpcLog(s"Command \(tag) is \(lookup.claim.pattern.raw) with the wrong number of fields; offering it for repair.");
                ArrayPush(outcome.fumbled, tag);
            }
        }
        i += 1;
    }

    outcome.text = AiNpcTidyAfterRemoval(outcome.text);
    return outcome;
}

// What a removed command leaves behind, on all three axes and in one place, so the two sites
// that cut a tag out cannot end up tidying differently.
//
// The order is the argument: blank lines are collapsed only once the space a tag left on its
// own line is gone, and the ends are trimmed last because collapsing is what puts the final
// newline within reach of the trim.
func AiNpcTidyAfterRemoval(text: String) -> String {
    return AiNpcTrimBlanks(AiNpcCollapseBlankLines(AiNpcCollapseSpaces(text)));
}

// One command, run and accounted for.
//
// A handler that answers nothing has not refused, it has failed to answer: the claim owns the
// tag, so there is nobody else to offer it to. Treated as a silent refusal and logged against
// the claim, because the alternative is a command that appears to work.
func AiNpcRunActionClaim(ctx: ref<AiNpcContactContext>, claim: ref<AiNpcActionClaim>,
                         tag: String, params: array<String>) -> Void {
    let result = claim.handler.OnAction(ctx, params);
    if !IsDefined(result) {
        AiNpcLog(s"Command \(tag) returned nothing from '\(claim.fullId)'; treated as refused.");
        AiNpcPublishAction(ctx.contactId, tag, claim.fullId, false, "");
        return;
    }

    if !result.applied {
        AiNpcLog(s"Command \(tag) refused by '\(claim.fullId)': \(result.note)");
    }
    AiNpcPublishAction(ctx.contactId, tag, claim.fullId, result.applied, result.note);

    // Seeded here, where the author is known. The result carries no author, so seeding it from
    // the caller filed every note under ai_npc's own id -- and two claims speaking in one reply
    // wrote to the same key, where the first note was erased by the second.
    if NotEquals(StrLen(result.note), 0) {
        AiNpcSeedContext(ctx.contactId, result.note, claim.fullId);
    }
}

/// Cleaning up after a repair that could not run ///

// A command that EXISTS never reaches the player. When the repair pass is unavailable -- the
// day's budget is spent, the credentials have stopped working, the player turned it off -- the
// fumbled bracket is removed rather than shown: the player would read an unclosable command
// mid-sentence while the prose around it says the thing happened.
func AiNpcStripActionTags(text: String, tags: array<String>) -> String {
    let result = text;
    let i = 0;
    let count = ArraySize(tags);
    while i < count {
        result = AiNpcReplaceAll(result, tags[i], "");
        i += 1;
    }
    return AiNpcTidyAfterRemoval(result);
}
