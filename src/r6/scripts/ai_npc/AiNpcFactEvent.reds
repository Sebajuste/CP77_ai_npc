// How another mod's sentence enters the prompt.
//
// A pure table: text in, a line of <now> out. Nothing reads game state, so it is
// assertable without a session. The sentence itself comes from a quest fact watch --
// see AiNpcFactBridge.reds.
//
// NOTHING HERE MAY ASK FOR AN OUTPUT. A line in <now> lands after <actions> and last but
// for the closing token, so an instruction here competes with the one the prompt already
// gave, from a later and more specific position -- measured at 5/6 replies emitting their
// action command with no ambient event against 1/6 with an instruction-bearing one live.
// Context only. Output rules belong in <system_rules>, stated once for every message.

module AiNpc

// What a watched quest fact tells the character.
//
// The bracket is the whole of it, and it is not decoration. The text lands inside <now>,
// directly under the clock, in a prompt where every other line is either the character's own
// sheet or something V said -- a bare sentence there is read as V having said it. The frame
// is what makes it the world reporting instead, which is exactly the thing the model must
// not get wrong about a line that arrived from nobody.
//
// The sentence itself is passed through untouched. Another mod's author wrote it about their
// own content; rewording it here would be a translation layer with no one to check it.
func AiNpcFactEventContext(text: String) -> String {
    if Equals(StrLen(text), 0) {
        return "";
    }
    return "[WORLD EVENT: " + text + "]";
}
