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

    // The voice-over lines to cut the reference from, by file name and nothing else:
    // "fingers_q105_f_13a374d16c4e6008.wem". For a vanilla character the mod owns and ai_npc
    // does not: ai_npc ships no recipe for them, so the mod brings the list and the mod's own
    // repository is where it is documented.
    //
    // Naming them one by one is not a shape choice: an archive holds no path, only the hash of
    // one, so "every line of this character" is a question nobody can ask at runtime.
    // `tools\voice-extract` answers it offline and prints the list. The names carry no folder
    // because they are the same in every language -- the player's voice-over locale decides
    // which one is read, and a character the player's dub does not have falls back to the
    // catalogue voice.
    //
    // Empty for the shipped cast, whose lines the recipe already names.
    public let cloneLines: array<String>;

    // A PocketTTS catalogue voice, by name: "eve", "jean", "mary"... Empty leaves this character
    // on the system voice when no clone is possible.
    public let fallback: String;

    // How fast the catalogue voice is played back. Pitch and pace move together: 1.06 is one
    // semitone higher and six percent quicker, which is how one catalogue voice becomes a
    // second character. Held between 0.8 and 1.25. A clone ignores it -- a cloned voice is
    // derived in the recipe -- and so does the Windows voice.
    public let rate: Float = 1.0;

    // How fast the clone's reference is re-read, which is the same derivation for the cloned
    // tier: 1.04 makes another person of the same civilian. Held between 0.85 and 1.15. The
    // reference is written once per value, as `<clone>-x1.04.wav`.
    public let shift: Float = 1.0;
}
