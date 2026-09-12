// Public extension point: how another mod gives one of its own contacts an AI voice, supplied
// at runtime. Registration is dynamic, so a provider can be registered the moment a contact
// becomes reachable and unregistered when it stops being; the phone picks the change up the
// next time its contact list is built.
//
// Two ways in, one registry: a JSON file in r6\storages\AiNpc\, which needs no compile-time
// dependency and is ignored when ai_npc is absent, or this class, for what JSON cannot
// express -- live game state, computed relationships, mod-specific actions.
//
// Every string a provider returns is expanded through AiNpcExpandTemplate, so {they} and
// {their} agree with V's gender.
//
// THE CLASS IS THE CONTRACT AND THE REGISTRY IS NOT. They shared a file until 2026-08-28,
// which put half the public surface outside api\ and made a 594-line file that both declared
// what a consumer subclasses and arbitrated between the results. AiNpcContactRegistry.reds
// holds the other half.

module AiNpc

public class AiNpcContactProvider extends IScriptable {

    // Must match the `contactId` the phone puts on its ContactData: that string is the only
    // thing tying a widget in the contact list to a conversation on disk, and it is the key
    // conversations.json is indexed by.
    public func GetContactId() -> String {
        return "";
    }

    public func GetDisplayName() -> String {
        return "";
    }

    // Whether the contact is reachable right now. A provider stays registered while this is
    // false and the contact drops out of the supported list, which is how a mod suspends AI
    // chat during one of its own scripted exchanges.
    public func IsAvailable() -> Bool {
        return true;
    }

    /// Prompt fragments ///
    // An empty string means "no opinion": ai_npc falls back to its built-in text for a vanilla
    // character, or omits the section for an external one. Hence no Has* companions.

    public func GetBio() -> String {
        return "";
    }

    public func GetRelationship() -> String {
        return "";
    }

    // Volatile state, rebuilt on every message and injected into <now>.
    public func GetLiveContext() -> String {
        return "";
    }

    // What this contact says about the quest V is tracking, keyed by AiNpcQuestKey. Empty for
    // most contacts and most quests.
    //
    // GetLiveContext answers about the contact's own state on every message; this answers
    // about V's, and only on a quest this contact has a line for.
    //
    // The ACCOUNT alone, in the second person. ai_npc writes the quest's title, the labels and
    // what V is doing right now around it -- see AiNpcQuestBlock -- so an answer that spelled
    // any of them itself would put them in the block twice.
    public func GetQuestContext(questKey: String) -> String {
        return "";
    }

    /// Intention ///

    // What this contact wants from V in general, when the current mission says nothing. Its
    // own question: GetBio says who somebody is and GetRelationship how they see V, and a
    // model given both and no intention invents a different one every message.
    //
    // Second person, one or two sentences, about what they want rather than what they know.
    // "You want V off this job before it kills {them}" is an intention; "You are worried about
    // V" is a mood and belongs in GetLiveContext.
    public func GetIntent() -> String {
        return "";
    }

    // Replaces the durable intention, keyed like GetQuestContext. Empty is no opinion and the
    // durable one stands: an intention is never blanked by a quest, only overridden.
    public func GetQuestIntent(questKey: String) -> String {
        return "";
    }

    /// Voice ///

    // Register, form of address, verbal tics, in one or two sentences. Additive: appended to
    // the rule block rather than replacing it, so the built-in constraints still apply.
    //
    // Stated in <relationship> instead, a form of address loses against a MANDATORY line every
    // time: a financier who "vouvoie V" answered with street slang because the French language
    // rule said characters use tu. Here it lands at the same weight as the rules it bends.
    //
    // About speech only. Facts belong in GetBio, mood in GetLiveContext.
    public func GetSpeechStyle() -> String {
        return "";
    }

    // The same, for a reply that is SAID rather than written. Empty keeps GetSpeechStyle, which
    // is right for a register that describes a person -- "blunt and quick, no hedging" holds on
    // any surface. Answer this one when yours describes TYPING: lowercase openings, missing
    // apostrophes, emoticons. Prescribing those to a mouth is the only thing the fallback gets
    // wrong.
    //
    // Not a rendering rule. That a voice speaks no emoticon is a fact about the surface and the
    // mod states it itself; that your character types them is a fact about them.
    public func GetSpokenStyle() -> String {
        return "";
    }

    // Which voice says this character's lines on a call. Null is no opinion: a character ai_npc
    // ships keeps its own; anybody else gets `<contactId>.wav` when the player has one, and the
    // system voice otherwise.
    public func GetVoice() -> ref<AiNpcVoiceDef> {
        return null;
    }

    // Whole sections replaced, for what GetSpeechStyle cannot bend. Null keeps every section
    // resolving from prompts.json or the built-in text.
    public func GetPromptOverrides() -> ref<AiNpcPromptOverrides> {
        return null;
    }

    /// Scripted replies ///

    // A hand-written answer to what V just sent. Three answers:
    //
    //   ""                    no opinion: the model answers.
    //   AiNpcSilentReply()    this contact says nothing at all to that message.
    //   anything else         that text is the reply.
    //
    // Taken per message, not per contact, so an automated correspondent can loop mechanically
    // and hand over to the model the moment the fiction says a person took the keyboard -- a
    // state a boolean on the provider could not express.
    //
    // A scripted reply takes the same path a generated one does, on a fixed beat. Called
    // before any prompt is built, so it costs no tokens, needs no key and cannot be talked
    // out of character.
    public func GetScriptedReply(playerText: String) -> String {
        return "";
    }

    /// Identity ///

    // What this character IS, as tags: "joytoy:client", "fixer". A command declared with
    // client.AddAction for one of these tags reaches this contact without either mod having
    // heard of the other -- which is what makes a contact minted at runtime reachable at all,
    // since it exists in no list anybody could have written.
    //
    // Tags only ever ADD. To take a command away from this character, suppress it; leaving a
    // tag out is never how reach is removed, because the tags ai_npc grants cannot be left out
    // and the ones you grant are yours to state.
    //
    // Read once per message alongside the assigned tags. "ainpc:" is ai_npc's own namespace
    // and a tag inside it is ignored with a line in the log.
    public func GetContactTags() -> array<String> {
        let empty: array<String>;
        return empty;
    }

    /// Policy ///

    // Whether this contact could know where V comes from.
    //
    // <target> states three things: the life path, the gender and whatever the player wrote
    // as an appearance. The last two are true of anyone who has ever seen V; the first is
    // biography, and "V is a streetkid (life path)" is a thing a client who found V on a
    // profile has no way to know -- and a gameplay word besides. Answer false and the clause
    // is left out for this contact; the rest of the block stands.
    //
    // A question rather than a text to override, so a contact that means "not this half"
    // does not have to restate the other two and lose the player's own appearance line.
    public func KnowsPlayerLifePath() -> Bool {
        return true;
    }

    public func IsRomanceCapable() -> Bool {
        return false;
    }

    // What the romance adds, and nothing the contact would say anyway: GetRelationship is
    // injected either way, so this says only what being together changes. Read by
    // AiNpcRomanceExtension, gated on IsRomanced, so no caller has to branch.
    public func GetRomance() -> String {
        return "";
    }

    // Whether V and this contact are together, as opposed to could be. On the base class
    // because a script provider that knew the answer had no way to say it otherwise:
    // AiNpcIsContactRomanced is the one resolver over both halves.
    public func IsRomanced() -> Bool {
        return false;
    }

    // Turning it off is characterisation rather than a limitation: an automated number does
    // not accumulate a relationship. A contact that says no gets no <memory> block and is
    // never compacted -- its window is trimmed instead. See docs\MEMORY.md.
    public func AllowsMemory() -> Bool {
        return true;
    }

    // What this contact knows about V before a message is exchanged. Seeded into the memory's
    // facts at the first compaction, then carried by the same machinery as everything else.
    // One line each: a fact is copied forward for the life of the playthrough.
    public func GetSeedFacts() -> array<String> {
        let empty: array<String>;
        return empty;
    }

    /// Phone presence ///

    // Whether this mod should put the contact into the phone's list itself. False by default:
    // almost every provider's contact is already supplied by its own mod's framework, and a
    // second one would show the contact twice. Opt in only for a contact nothing else
    // supplies.
    //
    // This is about the row existing. A contact supplied but never displayed is a different
    // problem, repaired for every provider in AiNpcPhoneContacts.
    public func WantsPhoneContact() -> Bool {
        return false;
    }

    // The avatar for an injected contact. Only consulted when WantsPhoneContact is true.
    public func GetPhoneAvatarId() -> TweakDBID {
        return t"PhoneAvatars.Avatar_Unknown";
    }

    /// The thread ///

    // What the player can do in this thread besides writing, in the order shown. ai_npc draws
    // them on every written surface and calls OnThreadChoice with the id of the one picked.
    // Asked each time the thread is shown, so a choice can come and go with the contact's
    // state. Nine at most: the phone binds them to the keys 1 to 9.
    public func GetThreadChoices() -> array<ref<AiNpcThreadChoice>> {
        let none: array<ref<AiNpcThreadChoice>>;
        return none;
    }

    // The player picked one of GetThreadChoices. A contact that is no longer available once
    // this returns has its thread closed.
    public func OnThreadChoice(choiceId: String) -> Void {}

    // A line has been written into this contact's thread and no surface painted it. Push the
    // notification yourself, or return false and let ai_npc push its own.
    //
    // ai_npc notifies through the vanilla phone, addressed by display name. That is right for
    // its own cast and wrong for a contact living in another phone framework, where a thread
    // is addressed by a hash and the notification has to be bound to it or it leads nowhere.
    // Such a framework usually needs its contact list refreshed too.
    //
    // The write is never delegated: the line is in the conversation store before this is
    // called. A probe that notified without writing produced a phone thread showing a message
    // the chat overlay had never seen. This hook moves who rings the bell, never who keeps
    // the record.
    //
    // Called only when nothing rendered the line, which makes it the ordinary path for a
    // character writing first. Return true only if you actually notified.
    public func Notify(text: String) -> Bool {
        return false;
    }
}
