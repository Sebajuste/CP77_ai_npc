// One line per request: who it was for, how big it was, and what the provider says it cost.
//
// The lane already logged the entire request body and the entire response, so `usage` was
// already in the log -- buried in seventeen thousand characters of prompt, next to the
// player's own message. Nothing could be counted from it, and a log containing the whole
// conversation is not one a player can paste into a bug report. This writes a single line of
// metadata instead, and the dumps moved behind Debug Mode.
//
// It also re-measures, per provider and per model, the 3.81 characters per token that the
// whole section table in docs\PROMPT_BUDGET.md is derived from: both halves are on one line.
//
// Two rules. Both lanes always: the thinking lane compacts memory behind the player's back, on
// the same key and against the same cap, so a tally of only what the player typed would be
// wrong by however much the mod thinks. And absence is never zero: a provider that reports no
// usage block measured nothing, and printing 0 would make an unmeasured day read as free.
//
// The same numbers are charged to AiNpcUsageService, which decides whether the next request is
// sent. That is why Answered takes the whole response -- the day the charge belongs to is in
// the `Date` header -- and why the estimate the cap needs is marked rather than folded in.

module AiNpc

import RedData.Json.*

/// The three things that send ///

// Named rather than written as literals at the call sites, so a typo cannot create a fourth
// lane that no tally adds up.
func AiNpcLaneSpeaking() -> String {
    return "speaking";
}

// Its own lane because it is its own request with its own cost, and the only one of the three
// the player can turn off -- a decision worth having the numbers for.
func AiNpcLaneRepair() -> String {
    return "repair";
}

func AiNpcLaneThinking() -> String {
    return "thinking";
}

// The action selection, when the player has moved it out of the conversation. Its own lane
// because it is its own request with its own cost, once per reply -- which is exactly the
// number a player deciding between the two modes needs to see in the daily report.
func AiNpcLaneActions() -> String {
    return "actions";
}

// Une replique DITE, sur un appel holo. Sa propre voie parce que c'est son propre cout et
// surtout sa propre contrainte : ce qui est dit a voix haute ne s'ecrit pas, ne se relit pas et
// ne supporte pas la longueur qu'un fil de messages supporte. Un joueur qui compare son rapport
// du jour entre une soiree d'appels et une soiree de textos a besoin des deux totaux separes.
//
// Elle rend les MEMES messages que la voie ecrite : meme constructeur, meme recette par defaut.
// C'est la reliure de `passes` qui permet de les separer, pas ce nom.
func AiNpcLaneHolo() -> String {
    return "holo";
}

// The connection test, a lane rather than a silent request: it is a real send on the real key,
// and a day it spends is a day the player does not get back.
//
// The one send the daily cap never refuses: someone running it is finding out why nothing
// works, and answering "your budget is spent" to a diagnostic loses an evening. Counted,
// never blocked.
func AiNpcLaneTest() -> String {
    return "test";
}

/// The record ///

// What was known at send time, held until the answer comes back: the size of what was sent is
// gone by the time the callback runs, and the cost is not known until then.
//
// Not on AiNpcGeneration, which holds no logging: a generation is what a request is about, and
// it survives a repair this file has to count as a second send.
public class AiNpcRequestRecord {
    private let m_lane: String;
    private let m_contactId: String;
    private let m_provider: String;
    private let m_model: String;
    private let m_slot: String;
    private let m_recipe: String;
    private let m_systemChars: Int32;
    private let m_userChars: Int32;

    // Called on the line that posts, with the slot it goes out on and the two halves of the
    // body it is about to send.
    //
    // The slot is taken rather than the model, because the model is the slot's answer: a line
    // that read the dialogue model itself would name it whatever sent the request, and the one
    // failure this format exists to make payable -- a mistyped parameter coming back a 400 --
    // is only diagnosable if the line says which slot produced it.
    //
    // The recipe is named for the same reason and answers the other half: the slot says what
    // the request was sent with, the recipe says what was in it.
    public static func Sent(lane: String, contactId: String, provider: AiNpcProvider,
            slot: ref<AiNpcSlot>, recipeName: String, instructionText: String,
            askText: String) -> ref<AiNpcRequestRecord> {
        let self = new AiNpcRequestRecord();
        self.m_lane = lane;
        self.m_contactId = contactId;
        self.m_provider = AiNpcProviderName(provider);
        self.m_model = AiNpcLlmSlotModel(provider, slot);
        self.m_slot = AiNpcSlotNameOf(slot);
        self.m_recipe = recipeName;
        self.m_systemChars = StrLen(instructionText);
        self.m_userChars = StrLen(askText);
        return self;
    }

    // Before the first send of a session, and for a callback that fires with no record behind
    // it. A line that names nobody rather than a null every callback would have to check.
    public static func Idle() -> ref<AiNpcRequestRecord> {
        return AiNpcRequestRecord.Sent("", "", AiNpcProvider.OpenRouter, null, "", "", "");
    }

    // The one call the lanes make when a response lands, whatever the status. A failure is
    // logged too, and is the most valuable line of the lot: a 429 costs no tokens and is the
    // moment the daily cap was reached.
    //
    // The tally is charged from here because this is the only place "a request came back, and
    // this is what it cost" is a fact: the two halves sent are on this record and the usage
    // block is in the answer. Charging elsewhere would measure the request twice, in two places
    // that could disagree.
    //
    // The whole reply is taken because the day the charge belongs to travels beside the JSON:
    // the `Date` header on an HTTP lane, the machine clock on a CLI one.
    public func Answered(reply: ref<AiNpcReply>) -> Void {
        let root = IsDefined(reply) ? reply.Root() : null;
        let usage = AiNpcExtractUsage(root);
        let status = IsDefined(reply) ? reply.StatusCode() : 0;
        let line = this.Line(status, usage, AiNpcExtractFinishReason(root));

        let charge = AiNpcMeasureCharge(usage, this.m_systemChars + this.m_userChars);
        line += AiNpcTokenField("charged", charge.tokens);
        if charge.estimated {
            // Named, so the two numbers cannot be read as the same kind of fact: everything
            // else was measured by the provider, this one was not.
            line += " charged_from=chars";
        }

        let usageService = AiNpcUsageService.Get();
        if IsDefined(usageService) {
            usageService.Charge(this.m_lane, charge, IsDefined(reply) ? reply.Date() : "");
            line += AiNpcTokenField("day_total", usageService.DayTotal());
        }

        AiNpcLog(line);
    }

    // Apart from Answered and pure, so the format is asserted offline rather than by reading a
    // log after a session.
    public func Line(status: Int32, usage: ref<AiNpcUsage>, finishReason: String) -> String {
        // Two halves rather than a total: a single number says a request got bigger without
        // saying whether the memory block or the transcript did it.
        let line = s"request lane=\(this.m_lane) contact=\(this.m_contactId)"
            + s" provider=\(this.m_provider) model=\(this.m_model) slot=\(this.m_slot)"
            + s" recipe=\(this.m_recipe)"
            + s" chars_system=\(this.m_systemChars) chars_user=\(this.m_userChars)"
            + s" status=\(status)";

        if !IsDefined(usage) || !usage.known {
            return line + " usage=absent";
        }

        line += AiNpcTokenField("prompt_tokens", usage.promptTokens)
            + AiNpcTokenField("completion_tokens", usage.completionTokens)
            + AiNpcTokenField("total_tokens", usage.totalTokens)
            + AiNpcTokenField("cached_tokens", usage.cachedTokens)
            + AiNpcTokenField("reasoning_tokens", usage.reasoningTokens);

        if NotEquals(StrLen(finishReason), 0) {
            line += s" finish=\(finishReason)";
        }

        // Measured against the prompt tokens alone: those are what the characters sent turned
        // into, and mixing the completion in divides our characters by somebody else's.
        if usage.promptTokens > 0 {
            line += s" chars_per_token=\(AiNpcRatioLabel(this.m_systemChars + this.m_userChars, usage.promptTokens))";
        }
        return line;
    }
}

/// Formatting ///

// A token count, or nothing when the provider reported none. Absence leaves no key, so a
// reader never has to know what -1 means and a grep finds only lines carrying the number.
func AiNpcTokenField(key: String, value: Int32) -> String {
    if value == AiNpcTokensUnknown() {
        return "";
    }
    return s" \(key)=\(value)";
}

// To two decimals, without Float formatting, which spells the same ratio "3.808877" and makes
// two lines hard to compare at a glance.
func AiNpcRatioLabel(chars: Int32, tokens: Int32) -> String {
    if tokens <= 0 {
        return "";
    }
    let hundredths = (chars * 100 + tokens / 2) / tokens;   // rounded, not truncated
    let whole = hundredths / 100;
    let rest = hundredths - whole * 100;
    if rest < 10 {
        return s"\(whole).0\(rest)";
    }
    return s"\(whole).\(rest)";
}
