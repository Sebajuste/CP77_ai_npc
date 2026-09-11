// Which voice says a character's lines, by tier.
//
// Two entries because there are two tiers and neither replaces the other: the clone is the
// game's own voice, cut from the player's archives; the catalogue voice is a free one that does
// not sound like the character. A player with the cloning pack hears the first, everybody else
// the second, and nobody hears the Windows synthesiser unless neither is available.
//
// A fact about the character, not a setting: it lives on the sheet, or on the provider.

module AiNpc

public class AiNpcVoiceDef {
    // The reference file in r6\storages\AiNpc\voices\. Empty means `<contactId>.wav`. The mod
    // makes a reference itself when its recipe knows the name: the shipped cast, and voices cut
    // from anonymous civilians for characters the game never voiced, such as
    // "civ_mid_f_21_enus_25.wav". Any other name is a file the player dropped there.
    public let clone: String;

    // A PocketTTS catalogue voice, by name: "eve", "jean", "mary"... Empty leaves this character
    // on the system voice when no clone is possible.
    public let fallback: String;

    // How fast the catalogue voice is played back. Pitch and pace move together: 1.06 is one
    // semitone higher and six percent quicker, which is how one catalogue voice becomes a
    // second character. Held between 0.8 and 1.25. A clone ignores it -- a cloned voice is
    // derived in the recipe -- and so does the Windows voice.
    public let rate: Float = 1.0;
}
