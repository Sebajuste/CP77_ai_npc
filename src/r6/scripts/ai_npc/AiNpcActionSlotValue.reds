// What a model actually wrote in a slot, once its decoration is taken off.
//
// A command block shows its slots as "{give_amount_eddies}", and a model that copies the shape
// along with the value writes "[ACTION:GIVE_EDDIES:{1000}]". Measured on OpenRouter across two
// prompt revisions and several models, so it is not a property of one wording: a language
// model's output is nearly right, and the last fraction has to be absorbed here rather than
// asked for again. Unabsorbed, the tag matches its head, fails its field, and the player sees
// a conversation that agreed on something the game never did.
//
// The set below is decoration and nothing else -- braces, brackets, angles, quotes, backticks,
// asterisks, blanks. No value any command takes can begin or end with one of them: a venue is
// a word, an hour and a price are digits. That is what makes stripping them safe in both
// directions, balanced or not -- a closing brace whose opening was eaten is still decoration.
//
// What this does NOT do is repair a value. "{mille}" cleans to "mille" and the consumer
// refuses it, which is the right answer: tolerance is for how a value was written, never for
// what it says.
//
// PURE: no game API, no state, no config.
module AiNpc

func AiNpcSlotDecoration() -> String {
    return "{}[]()<>*`\"' \t";
}

func AiNpcCleanSlotValue(written: String) -> String {
    let decoration = AiNpcSlotDecoration();
    let value = written;

    while StrLen(value) > 0 && StrContains(decoration, StrLeft(value, 1)) {
        value = StrRight(value, StrLen(value) - 1);
    }
    while StrLen(value) > 0 && StrContains(decoration, StrRight(value, 1)) {
        value = StrLeft(value, StrLen(value) - 1);
    }

    return value;
}
