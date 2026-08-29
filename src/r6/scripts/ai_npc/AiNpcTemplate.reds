// The placeholder substitution engine.
//
// PURE: no game API, no state, no config. Configured prompt text cannot concatenate
// AiNpcGetGenderedWord the way the built-in strings do, so it carries {they} / {their} /
// {partner} instead and they are substituted here.
//
// The half that READS the game to build the values lives in AiNpcPromptSections.reds. That
// split is not tidiness: it is what lets every substitution rule be asserted without a
// session, and it is guarded by tools/lint.ps1, which fails the build if a game dependency
// appears in this file.

module AiNpc

/// Templating ///

// The complete set of values a placeholder can expand to. Passed in rather than looked up,
// which is what keeps this file free of the game.
public class AiNpcTemplateVars {
    public let partner: String;   // boyfriend / girlfriend
    public let they: String;      // he / she
    public let them: String;      // him / her
    public let their: String;     // his / her
    public let gender: String;    // male / female
    public let npc: String;       // display name of the character being talked to
    public let time: String;      // in-game clock
    public let language: String;  // the active language instruction
    public let vgender: String;   // "V is a woman...", in the reply language

    // The language's default form of address -- "Les personnages se tutoient." and its
    // equivalents, empty in English.
    //
    // A per-character speechStyle REPLACES that default rather than adding to it, so that a
    // character can say otherwise: a style composed with its own contradiction ("characters
    // use tu. You address V formally.") is worse than either half. A style that wants to keep
    // the default says {register}; one that wants to overturn it leaves the placeholder out.
    public let register: String;
}

// Replaces every occurrence: StrReplace substitutes only the first, which silently leaves
// the second {they} of a sentence unexpanded. Scanning forward rather than restarting also
// means a replacement that contains its own pattern cannot loop forever.
func AiNpcReplaceAll(text: String, from: String, to: String) -> String {
    if Equals(StrLen(from), 0) {
        return text;
    }

    let result = "";
    let rest = text;
    let index = StrFindFirst(rest, from);
    while index >= 0 {
        result += StrLeft(rest, index) + to;
        rest = StrRight(rest, StrLen(rest) - (index + StrLen(from)));
        index = StrFindFirst(rest, from);
    }
    return result + rest;
}

func AiNpcCapitalize(text: String) -> String {
    if Equals(StrLen(text), 0) {
        return text;
    }
    return StrUpper(StrLeft(text, 1)) + StrRight(text, StrLen(text) - 1);
}

// An unknown placeholder is left verbatim rather than blanked: "{ther}" surviving into
// the prompt is visible in a log and in the reply, while a silent empty string would
// just make the sentence subtly wrong with nothing to trace it to.
func AiNpcExpandTemplateWith(text: String, vars: ref<AiNpcTemplateVars>) -> String {
    if !StrContains(text, "{") {
        return text;
    }

    let result = text;
    result = AiNpcReplaceAll(result, "{partner}", vars.partner);
    result = AiNpcReplaceAll(result, "{they}", vars.they);
    result = AiNpcReplaceAll(result, "{them}", vars.them);
    result = AiNpcReplaceAll(result, "{their}", vars.their);
    result = AiNpcReplaceAll(result, "{gender}", vars.gender);
    result = AiNpcReplaceAll(result, "{npc}", vars.npc);
    result = AiNpcReplaceAll(result, "{time}", vars.time);
    result = AiNpcReplaceAll(result, "{language}", vars.language);
    result = AiNpcReplaceAll(result, "{vgender}", vars.vgender);
    result = AiNpcReplaceAll(result, "{register}", vars.register);

    result = AiNpcReplaceAll(result, "{Partner}", AiNpcCapitalize(vars.partner));
    result = AiNpcReplaceAll(result, "{They}", AiNpcCapitalize(vars.they));
    result = AiNpcReplaceAll(result, "{Them}", AiNpcCapitalize(vars.them));
    result = AiNpcReplaceAll(result, "{Their}", AiNpcCapitalize(vars.their));

    return result;
}
