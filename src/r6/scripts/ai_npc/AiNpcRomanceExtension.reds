// ai_npc's own romance rubric, contributed through ai_npc's own extension API.
//
// The romance is not a different character: it is something TRUE ABOUT ONE, alongside
// everything else that is true about them, and the mod already has a name for that shape.
// So <relationship> is the psychology, injected either way, and this adds the one thing the
// psychology cannot state on its own. A second whole paragraph replacing the first would
// restate the bio, the tone, the trust and the teasing with a few words different, and
// forgetting to edit the copy would only show in the playthroughs that had the romance.
//
// It goes through the PUBLIC door -- AiNpcOpenClient(...).RegisterExtension, gated on
// ctx.isRomanced, budgeted like everybody else. Nothing here is privileged: the first consumer
// of an API being the mod that ships it is what keeps the API honest.
//
// The client and not the registry, which is the difference this sentence used to claim and the
// code did not make. Opening a client CLAIMS the mod id, so ai_npc appears beside every other
// contributor in AiNpcExplainCharacter -- and the one contributor missing from the diagnostic
// was the mod that ships it.
//
// IT ANSWERS IN BOTH POLARITIES, AND IT HAS TO. Whether V and this character are together is
// a statement about the state of the save, not psychology, so it belongs here rather than in
// `relationship` -- where additive injection would leave a prompt telling a character to
// refuse V and to flirt with {them} in the same breath.
//
// One sentence for all four rather than a field per sheet, because it is a RULE. A character
// who refuses differently says so in its own `relationship`, which is where Songbird's sits:
// she is not romanceable, so nothing here ever speaks for her.

module AiNpc

// What a romanceable character is told while the save says the romance has not happened.
//
// Three clauses, and each one is there because leaving it out was wrong:
//
//   the state      "You and V are not together" -- what the save actually says. Not "V is a
//                  friend and nothing more", which is a claim about the relationship made in
//                  the rules lane, where it overrode the four <relationship> texts that had
//                  just said otherwise and called a cop met on a case V's friend. And not
//                  "nothing ever will be" either: the save says it HAS NOT HAPPENED, and a
//                  playthrough that romances the character later would read a prompt that had
//                  already closed the door.
//   the refusal    the advance is not taken up. The only part that is genuinely a rule.
//   the manner     given back to the character. "Reject outright" asked all four to refuse the
//                  same flat way, which is the one thing their sheets already know how to do
//                  differently -- Panam sends V packing, Judy deflects, Kerry makes a joke of
//                  it. A rule that legislates the manner spends four sheets to say one thing.
//
// The last clause exists because the cheapest way to obey the other two is to ignore the
// message, and a character who acts as though V had said nothing reads as a model that missed
// it rather than as somebody saying no.
//
// Free function so the suite can assert the exact wording without a session: the failure this
// guards against is the sentence quietly going missing, and a missing instruction reads in
// game as a model being agreeable rather than as a bug.
func AiNpcRomanceRefusalLine() -> String {
    return "You and V are not together. An advance from V is not taken up: turn it down in your own words, and never answer as though it had not been made.";
}

public class AiNpcRomanceExtension extends AiNpcCharacterExtension {

    public func GetSubject() -> String {
        return "romance";
    }

    // Every drivable contact, and no list to keep in step with the cast. A contact with
    // nothing to say about romance answers "" below, which is cheaper than maintaining four
    // ids here and getting them wrong the day a fifth character ships.
    public func GetContactIds() -> array<String> {
        let empty: array<String>;
        return empty;
    }

    // WHAT IS SAID WHERE, and the split is the point of this file.
    //
    // Being romanced is a FACT about the two of them: it belongs in <now>, among the things
    // that are true at this moment. Refusing advances is a RULE about how to answer: it
    // belongs in <system_rules>, as a rubric, where every other rule the model must follow
    // lives. It sat in <now> until 2026-08-27 for want of a rubric lane, which is the same
    // reason everything else that did not belong there sat there.
    public func GetRuleContributions(block: String, ctx: ref<AiNpcContactContext>) -> array<ref<AiNpcRule>> {
        let rules: array<ref<AiNpcRule>>;
        if NotEquals(block, "system_rules") || !IsDefined(ctx) || ctx.isRomanced {
            return rules;
        }

        // Said only where it could be false. A character the base game never lets V romance
        // has no state to correct, and telling it to refuse advances nobody has made is the
        // same waste as advertising a command that cannot fire.
        let provider = AiNpcProviderFor(ctx.contactId);
        if IsDefined(provider) && provider.IsRomanceCapable() {
            ArrayPush(rules, AiNpcRuleOf("ROMANCE", AiNpcRomanceRefusalLine()));
        }
        return rules;
    }

    // Three answers, and the third is the common one.
    //
    // ctx.isRomanced is ai_npc's own resolution -- the save's quest fact for a shipped
    // character, the sheet's `romanced` for a contact somebody else declared -- so this file
    // never reads a fact and never has a second copy of the answer to keep in step.
    public func GetLiveContextAddition(ctx: ref<AiNpcContactContext>) -> String {
        if !IsDefined(ctx) {
            return "";
        }

        let provider = AiNpcProviderFor(ctx.contactId);
        if !IsDefined(provider) {
            return "";
        }

        if ctx.isRomanced {
            return AiNpcSafeSectionText(provider.GetRomance(), ctx.contactId);
        }

        // The refusal is a rule, and it is stated as one -- see GetRules above.
        return "";
    }
}

// Registration, at the one moment a session certainly exists.
//
// A system of its own rather than a line in AiNpcExtensionRegistry.OnAttach: the registry
// arbitrates contributions and must not know any of them by name, or the first built-in
// extension becomes a precedent for the second. Idempotent by full id, so re-attaching after
// a save load replaces the entry instead of adding a second.
public class AiNpcRomanceExtensionBootstrap extends ScriptableSystem {

    private func OnAttach() -> Void {
        if !AiNpcOpenClient(AiNpcOwnModId()).RegisterExtension(new AiNpcRomanceExtension()) {
            FTLogError("[ai_npc]: the romance rubric could not register: no extension registry.");
        }
    }
}
