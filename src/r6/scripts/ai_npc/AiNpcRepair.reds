// The one second chance a reply gets, and what decides whether to spend it.
//
// A model writes "[ACTION:KABUKI_SF:2200:1000:1]" -- a command with the verb dropped. Nothing
// claims it, so nothing strips it, and the player reads the bracket while the sentence around
// it says the meeting is on. This asks the model, once, to write that command again.
//
// It ASKS rather than guessing: an unclaimed tag is either a dropped verb or a command
// belonging to a mod that is not installed, and nothing can tell those apart. The verb IS the
// routing key, so reconstructing it from the shape of the payload would let one contact's
// provider quietly answer for a command addressed to somebody else.
//
// Everything that can be wrong about a repair is a decision -- whether one is owed, whether
// the budget is spent, whether there is a vocabulary to correct against, what the corrected
// reply reads like -- and all four are here, over plain strings, with the conditions handed in
// as arguments. What is left in the lane is a POST and a callback.
//
// THE BUDGET IS ONE: a Bool rather than a counter. The repaired reply re-enters the ordinary
// delivery path, so without a latch a model that keeps writing the same broken command would
// keep buying requests until the player closed the game. It is never refilled -- a repair
// lives exactly as long as the turn that made it.

module AiNpc

public class AiNpcRepair {
    private let m_spent: Bool = false;

    // The reply as it stood when the repair was claimed, and the bracket in it to replace.
    private let m_text: String;
    private let m_tag: String;

    // Decides whether this reply is worth a second request, and arms one if it is. Returns
    // the tag to correct, or "" when the reply should be delivered as written.
    //
    // `vocabulary` is the contact's command block, rendered from the same table the reply was
    // dispatched against. Empty means this contact was never given a command, so a bracket in
    // its reply is prose -- and asking a model to fix prose against an empty rulebook is how a
    // good reply gets replaced by a worse one.
    //
    // `candidates` is what the dispatcher could not run, fumbled commands first. Handed in
    // rather than rescanned here: whether a bracket names a real command is a question about
    // the claim table, and a second answer computed in this file is a second answer to drift.
    //
    // `credentialsUsable` is false when the key has stopped working. A repair is then worse
    // than the broken tag: the second request would fail too, and the player would have
    // waited twice for the same message.
    //
    // `budgetLeft` is false when the day's token ceiling has been met. A repair is the one
    // request the player already agreed to pay for twice, so it is also the first one a
    // spent day must refuse -- and refusing it costs nothing they can see: the reply exists
    // and reads correctly, the defect is one bracket in it.
    public func Claim(text: String, candidates: array<String>, vocabulary: String, enabled: Bool,
            credentialsUsable: Bool, budgetLeft: Bool) -> String {
        if this.m_spent || !enabled || !credentialsUsable || !budgetLeft
                || Equals(StrLen(vocabulary), 0) || Equals(ArraySize(candidates), 0) {
            return "";
        }

        this.m_spent = true;
        this.m_text = text;
        this.m_tag = candidates[0];
        return this.m_tag;
    }

    // The corrected reply. `corrected` is whatever came back, and "" is a legitimate answer:
    // a model handed the vocabulary and told to write NONE did not find its command there.
    // The bracket goes either way, because an unreadable command in the bubble is the whole
    // defect this path removes.
    //
    // Only the bracket is replaced. The prose the player is about to read cannot change under
    // them, which is why the request below asks for the command alone.
    // The third site that cuts a tag out of a reply, and the correction can be empty -- which
    // is this path's ordinary answer, not its edge case. Same tidy as the other two.
    public func Merge(corrected: String) -> String {
        return AiNpcTidyAfterRemoval(AiNpcReplaceAll(this.m_text, this.m_tag, corrected));
    }

    public func HeldTag() -> String {
        return this.m_tag;
    }
}

// The second request's whole prompt, next to the vocabulary it will be sent with.
//
// The smallest thing this mod ever sends: the command list and the broken tag, no persona, no
// memory, no transcript -- about a thousand tokens against the five thousand a real turn
// costs. On Groq's free tier, 8000 tokens a minute, a repair that resent the conversation
// would push the wait between two player messages past a minute; this one is nearly free.
func AiNpcRepairAsk(tag: String) -> String {
    return s"You wrote this command in your last message:\n\(tag)\n\n"
        + "It is not one of the commands above, so nothing happened. Write the correct command "
        + "for what you have just agreed, alone, on one line, with no other text.";
}
