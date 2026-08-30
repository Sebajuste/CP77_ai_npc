// One whole section of the system prompt, replaced. The field names are exactly the keys of
// prompts.json, so the global file and a per-contact override speak one vocabulary.
//
// An empty field means "no opinion", not "blank section", which is what makes this safe to
// return half-filled: the sections left alone keep resolving down the chain
// contact override -> prompts.json -> built-in text.
//
// Replacing is the escape hatch. To bend how one character speaks, use GetSpeechStyle, which
// composes with the built-in rules instead of dropping them.
//
// In api\ because a consumer builds one and hands it back from GetPromptOverrides: it is a
// type in the contract, and a contract that lives in two folders is one nobody can read in
// one place. It shared a file with the registry that arbitrates providers until 2026-08-28.

module AiNpc

public class AiNpcPromptOverrides {
    // <system_rules>, by rubric. A known key replaces that rubric where it stands, an unknown
    // one is appended before LENGTH, and FORM / TIME / LENGTH refuse both -- see
    // AiNpcRules.reds. Use SetRule rather than pushing here.
    public let rules: array<ref<AiNpcRule>>;

    public func SetRule(key: String, text: String) -> Void {
        this.rules = AiNpcRuleSet(this.rules, key, text);
    }

    // The same, for <interactions>. Two methods rather than one with a block argument: a
    // typo in a block name would compile and go nowhere, where a method name does not.
    public func SetInteraction(key: String, text: String) -> Void {
        this.interactions = AiNpcRuleSet(this.interactions, key, text);
    }
    // <interactions>, by rubric: REACH and REAL are contributable, PROMISES is the mod's.
    public let interactions: array<ref<AiNpcRule>>;
    public let worldBackground: String;    // <world_background> -- the world, NOT V
    public let playerDescription: String;  // <target> -- who V is, to this contact only
    public let worldMechanics: String;     // <mechanics>
    // NO TONE LANE. <explicitness> states what the PLAYER consented to in Mod Settings, and
    // a contact rewriting it would answer a question that was never put to it. A character
    // who does not swear says so in its SPEECH rubric, which is where a register lives.
    public let language: String;           // <language> -- replaces the active language rule

    // The three below have no prompts.json counterpart, because a global default for them
    // makes no sense: they exist for the contact that is not a person.

    // Rendered in <character> as SPEECH, same slot as GetSpeechStyle, which wins where a
    // provider implements it. Here so a built-in contact can still state a register.
    public let speechStyle: String;
}
