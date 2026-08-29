module AiNpc

// Everything a mod is told about the contact it is being asked about.
//
// Shared by both public lanes -- an extension contributing to a character, and an action
// handler running a command on one -- because both are answering questions about the same
// person at the same moment. Built once per question asked, not once per consumer: a dozen
// contributions on one contact must not mean a dozen quest-fact reads.
//
// ONE PARAMETER RATHER THAN A GROWING ARGUMENT LIST, and that is what lets this grow at all.
// `opt` covers a free function; for a virtual method it does not -- a consumer's override
// keeps the old signature, quietly stops overriding, and ai_npc calls its own default. That
// compiles, logs nothing, and reads in game as a feature that was never wired. A field added
// to a class the consumer never constructs has none of those effects.
public class AiNpcContactContext extends IScriptable {
    public let contactId: String;
    public let displayName: String;

    // ai_npc's own resolution, folding the player's override -- not the game's UI language.
    // Two-letter code, as AiNpcChosenLanguage returns it.
    public let language: String;
    public let speaksOfPlayerAsMale: Bool;

    public let isRomanced: Bool;

    // Worth branching on: a built-in has bio, relationship and quest context of its own that
    // a contribution must not restate.
    public let isBuiltIn: Bool;

    // Set for GetScriptedReply and empty everywhere else: the other methods run while a prompt
    // is being built, on its own schedule rather than in answer to a message.
    public let playerText: String;

    // What this contact IS: "ainpc:contact", "contact:judy", "joytoy:client". Populated on the
    // action lane, where it is resolved anyway, and empty elsewhere.
    //
    // Read it rather than deciding from contactId. A mod that keys behaviour on an id list has
    // to keep that list in step with every character every other mod adds; a tag was put there
    // by whoever knew.
    public let tags: array<String>;

    public func HasTag(tag: String) -> Bool {
        let mine = this.tags;
        return ArrayContains(mine, tag);
    }
}
