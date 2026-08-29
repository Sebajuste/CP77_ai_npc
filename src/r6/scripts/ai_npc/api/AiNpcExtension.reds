module AiNpc

// Public extension point: what another mod adds to a character it does not own.
//
// A provider declares a character -- who this person is, one per contactId, first claim wins,
// because two mods cannot both be right about who Rogue is. But two mods can both be right
// about what she can do: a gig mod that has her offer work and a Johnny mod that has her
// suggest a drink only looked like a conflict because both went through the single provider
// slot, and the second lost its whole contribution with nothing to show the player.
//
// A method may join this class only if the rule for merging two answers is written in its
// contract. That is why the class is short: GetBio is absent because two bios concatenated
// describe nobody, GetSpeechStyle because "relaxed, first names" and "formal, keeps V at
// arm's length" do not average. The only honest design is to make the collision unsayable
// rather than arbitrate it.
//
// What is left merges three ways, and three is all there is:
//
//     concatenation   text fragments                 everyone contributes
//     veto            permissions                    anyone may remove a permission,
//                                                    nobody may grant one
//     exclusive turn  writing the reply              one holder, see the floor on AiNpcClient
//
// COMMANDS ARE NOT HERE ANY MORE. What a character can DO is declared with client.AddAction,
// which is one call rather than four methods to override, and is scoped by a tag rather than a
// contact list. The move is not tidying: this class used to carry a command lane that the
// provider class carried under different method names, and the two drifted -- one veto was
// read by nobody, and one consumer's fragment method never overrode anything and silently
// advertised no commands for as long as it existed. See docs/PLAN_ACTION_LANE.md.
//
// What to use instead of what is missing:
//
//     GetBio, GetRelationship, GetSpeechStyle   declare the contact, or characters.json --
//                           and a mood belongs in GetLiveContext anyway
//     GetSeedFacts          client.CharacterKnows(id, text, AiNpcUntilForever()), which works
//                           at any moment rather than only before the first message
//     IsAvailable           two questions, and conflating them was the old bug: "unreachable
//                           in the fiction" stays on the provider, "busy with my scripted
//                           exchange" is client.TakeFloor
//     GetActionTags,        client.AddAction, and AiNpcActionHandler for the effect
//     TryApplyAction
//     AllowsGenericTransfer client.SuppressAction(AiNpcTransferHead(), tag), which removes any
//                           command rather than one named in the method
//     GetScriptedReply      here, but consulted only while you hold the floor

public class AiNpcCharacterExtension extends IScriptable {

    // The half of the identity this extension chooses; the client supplies the other, and the
    // full id is "<modId>:<subject>". Split so the mod name is stated once, where the client
    // is opened: a subject typed twice is two extensions, a mod name typed wrong once is a
    // contribution nobody can find or retract.
    //
    // The id orders your contribution and the order is not yours to choose. Contributions
    // merge in ascending id, which is stable across launches where registration order is not,
    // but it is alphabetical rather than meaningful. Never write a contribution whose sense
    // depends on running before or after somebody else's: that is a disagreement about a
    // character, not an addition to one, and the merge rules cannot express it.
    public func GetSubject() -> String {
        return "";
    }

    // An empty array means every drivable contact: a mod adding one line of weather, or a rule
    // about how everyone treats V after a public event, has no list to write. It is also where
    // the budget below matters most.
    public func GetContactIds() -> array<String> {
        let empty: array<String>;
        return empty;
    }

    /// Concatenated ///

    // What this mod wants of V through that character, appended to <intent> after whatever
    // the contact wants of its own.
    //
    // Appended, never replacing: the contact's own intention is who they are, and a mod that
    // adds a job to somebody's week does not get to overwrite it. Budgeted like <now> -- 400
    // characters a line, 1200 across every extension -- and refused whole rather than clamped
    // when it carries a tag.
    public func GetIntentAddition(ctx: ref<AiNpcContactContext>) -> String {
        return "";
    }

    // Rubrics of a composed block, contributed by key. `block` is the tag: "system_rules" or
    // "interactions" -- answer "" for the ones you have nothing to say about.
    //
    // A known key -- YOU, NEVER, SETTING, SPEECH -- replaces that rubric where it stands; any
    // other key adds one of yours, after the mod's and before LENGTH. FORM, TIME and LENGTH
    // refuse both: they describe the chat itself, not the character.
    //
    // Last of the three sources, after the contact's own and prompts.json, and a key already
    // claimed by either is left alone -- your extension applies to contacts it did not
    // declare, and a character's own words about itself outrank a passing mod's.
    //
    // Budgeted like <now>: 600 characters per rubric, 2000 across every contribution, and
    // every refusal is logged with its reason.
    public func GetRuleContributions(block: String, ctx: ref<AiNpcContactContext>) -> array<ref<AiNpcRule>> {
        let none: array<ref<AiNpcRule>>;
        return none;
    }

    // Volatile state, rebuilt for every message and joined into <now> in ascending full-id
    // order. Budgeted: past the per-extension cap the tail is dropped and the drop is logged,
    // because N mods each adding a paragraph is how the message V wrote ends up outweighed by
    // commentary about it.
    //
    // Return "" when there is nothing to say: an extension that always has something spends a
    // shared budget on nothing.
    public func GetLiveContextAddition(ctx: ref<AiNpcContactContext>) -> String {
        return "";
    }

    /// Exclusive turn ///

    // A hand-written answer instead of a generated one. Consulted only while this extension
    // holds the floor on ctx.contactId, so it needs no guard against answering during
    // somebody else's scene. Three answers:
    //
    //     ""                    no opinion -- end the scene and hand the keyboard back
    //     AiNpcSilentAnswer()   this contact says nothing at all to that message
    //     anything else         that text is the reply
    //
    // It takes the same path a generated reply does and differs twice: it costs no tokens and
    // no network, and it lands on a fixed short beat. That regularity is the feature.
    public func GetScriptedReply(ctx: ref<AiNpcContactContext>) -> String {
        return "";
    }

    // Called on every extension registered for the contact, in full-id order, so a mod whose
    // TakeFloor was refused has a defined moment to try again rather than polling. Whoever
    // takes it first inside this callback wins, on every machine and every replay.
    public func OnFloorAvailable(ctx: ref<AiNpcContactContext>) -> Void {
    }
}
