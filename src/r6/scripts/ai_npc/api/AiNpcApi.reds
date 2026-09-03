module AiNpc

import RedFileSystem.*

// The contract. Everything another mod is allowed to call lives in this folder, and nothing
// else in ai_npc is part of the deal.
//
// A facade rather than "the public functions": in a module, declarations are shared between
// files without `public`, so `public` means exported. Measured 2026-08-22 -- 66 files, 351
// `public func`, 63 `public class`, of which one integrating mod used about twenty-five. 351
// exports is an accident, and the next integrator calls AiNpcClipText because it was
// reachable.
//
// Cut on 2026-08-28, from 712 top-level exports outside this folder to 174. Two causes, and
// the second was the bigger one: 264 declarations were exported for no reader at all, and 284
// only because the self-tests lived in a separate module and cross-module access needs
// `public` -- so a file deleted before release was deciding this mod's public ABI. The tests
// moved into `module AiNpc` and an empty AiNpcTestSuite.reds took over the ModuleExists seam.
// What is left public outside this folder is what api\ delegates to, plus the handful of names
// the plugin and the CET window reach by qualified name. tools\lint.ps1 ratchets the number.
//
// One rule decides which side a call is on:
//
//     free function -- here      reading, or anything with no author
//     method on AiNpcClient      writing
//
// The write forms used to be free functions here. They are gone, not deprecated: an anonymous
// write cannot be budgeted per mod, told apart in a listener, or refused when it would land
// in the middle of somebody's scene. AiNpcOpenClient("your_mod_id") is the whole migration.
//
// AiNpcFindCharacter is gone because its only documented use was the decorator dance --
// unregister somebody else's provider, wrap it, put it back -- which existed because a
// contact had one slot. Contributions no longer collide.
//
// Three shapes, and the shape says what the name answers:
//
//   subject + tense   a statement about the world   client.CharacterKnows, client.PlayerWrote
//   verb first        an order to ai_npc            client.OpenConversation, AiNpcOpenClient
//   question          the character answering       IsAvailable(), GetLiveContext()
//
// Inside the first shape the tense carries the how: past means it already happened and you
// are recording it, nothing is sent; present means a state you are setting, held until the
// bound you give. A name like ThreadSay promises both, and this mod paid for that once -- the
// anonymous-contact probe notified without writing to the store.
//
// No logic here at all: every function delegates in one line. A consumer taking ai_npc
// optionally mirrors this behind @if(ModuleExists("AiNpc")) and writes the degraded half
// itself, so anything computed here is something that mirror has to reimplement identically.
//
// Additive only once it ships. @if tests ModuleExists and nothing else, so a mod built for
// API 2 next to API 1 raises UNRESOLVED_FN -- which fails the compilation of the whole game,
// not of the offending mod. Add functions, never remove one, never change a signature, take
// new parameters as `opt`. Nothing is published yet, so breaking is still free.

/// Version ///

// Bumped when behaviour changes at an unchanged signature -- the only thing a runtime check
// can cover, since a missing function is a compile error that never reaches this.
//
// Still 1 through the extension rework and through CharacterWantsToSay becoming real. A
// version is for a consumer holding an older ai_npc against a newer contract, and nothing has
// shipped, so the number would move with no installation able to tell the difference and
// arrive at 1.0 already spent. It moves on the first release.
public func AiNpcApiVersion() -> Int32 {
    return 1;
}

/// Readiness ///

// All three registries, not one: a session where contacts resolve but no extension can
// register is not one an integrator can work in.
//
// False is normal, not a failure: script load order is not guaranteed, so try again at the
// next attach rather than latching "ai_npc is missing".
public func AiNpcIsReady() -> Bool {
    return IsDefined(AiNpcGetContactRegistry())
        && IsDefined(AiNpcGetExtensionRegistry())
        && IsDefined(AiNpcGetClientRegistry());
}

/// How long a statement holds ///

// Functions rather than an enum: a public enum forces a guarded declaration in a consumer
// that takes ai_npc optionally, where a function forces only a guarded wrapper. Int32 crosses
// the boundary, the vocabulary does not.
//
// NextReply is 0, the value an `opt` parameter defaults to, because it is the safe direction:
// a wrong permanent fact cannot be taken back, a wrong transient one is gone after one
// generation.
public func AiNpcUntilNextReply() -> Int32 {
    return 0;
}

public func AiNpcUntilForever() -> Int32 {
    return 1;
}

/// Questions about the cast ///

// Two lists, and not the same question, which is why no short `AiNpcListCharacters` is
// offered: whichever it returned, half the callers would have meant the other.
//
//   built-in    ai_npc's own cast, always the same eleven.
//   drivable    everything ai_npc can hold a conversation for right now: the built-ins plus
//               every registered provider whose IsAvailable() is true.
public func AiNpcListBuiltInCharacters() -> array<String> {
    return AiNpcGetAllContactIds();
}

public func AiNpcListDrivableCharacters() -> array<String> {
    return AiNpcGetActiveContactIds();
}

// Whether ai_npc can hold a conversation for this contact id at this moment.
public func AiNpcDrivesCharacter(contactId: String) -> Bool {
    return AiNpcIsContactSupported(contactId);
}

// The provider behind the chat the player currently has open, or null when none is.
public func AiNpcCharacterInOpenChat() -> ref<AiNpcContactProvider> {
    return AiNpcCurrentProvider();
}

/// Questions about a thread ///

// The whole stored thread, oldest first, both speakers, each message carrying who wrote it,
// its text and the in-game time. A snapshot, not a view: appending to it changes nothing.
//
// An empty array is the normal answer outside a session, for a contact nobody has texted, and
// for one ai_npc does not drive; AiNpcDrivesCharacter separates them.
//
// The expensive call in this file -- the full history, not a window. For "has this
// conversation started", use AiNpcPlayerHasWritten.
// Who V is on a holo call with, or "" when there is none. A call that has ended keeps naming
// its contact until the next one is placed, so a caller reading just after it ended still knows
// who it was about.
public func AiNpcCharacterOnCall() -> String {
    let calls = AiNpcCallSystem.Get();
    if !IsDefined(calls) {
        return "";
    }
    return calls.ContactId();
}

public func AiNpcReadConversation(contactId: String) -> array<ref<AiNpcMessage>> {
    return AiNpcStoredMessages(contactId);
}

// The predicate a life cycle hangs on: a contact V has answered has a history, which is what
// a bridge cannot rebuild. Cheap enough to poll; see AiNpcPlayerWroteIn.
public func AiNpcPlayerHasWritten(contactId: String) -> Bool {
    return AiNpcPlayerWroteIn(contactId);
}

// Who holds the exclusive turn, or "" when it is free. A held thread answers from its
// holder's script, takes no generated reply, and accepts no write from anybody else.
public func AiNpcFloorHeldBy(contactId: String) -> String {
    return AiNpcFloorHolder(contactId);
}

/// Diagnostics ///

// Everything acting on one contact, as text: who declared it, which extensions contribute and
// how many tags each claims, which listeners watch, who holds the floor. With N contributors
// on one character, "my action does not fire" has to be one line to read, and nothing else in
// the API can answer it.
//
// Not in config-report.json, where a reader would look first: that report is produced when
// the configuration loads and extensions register later, so the section would always be empty.
public func AiNpcExplainCharacter(contactId: String) -> String {
    return AiNpcExplainContact(contactId);
}

/// Questions to ai_npc ///

// The shared r6\storages\AiNpc\ folder, already open. Never call
// FileSystem.GetStorage("AiNpc") yourself: RedFileSystem allows one claimant per storage name
// and revokes it permanently for the session on a second, and the mod that loses is ai_npc --
// no journal, every conversation empty, every request [NO SIGNAL: HTTP 0]. The only trace is
// red4ext\logs\redfilesystem-*.log.
//
// Name your files with client.FileName so they cannot collide with ai_npc's own, which the
// config loader globs by pattern.
public func AiNpcSharedStorage() -> ref<FileSystemStorage> {
    return AiNpcModStorage();
}

// The language the conversation is in, as the two-letter code a file name uses. ai_npc's own
// resolution, which folds the player's override -- not the game's UI language. A stranger
// whose SMS arrives in English inside a French conversation is what this prevents.
public func AiNpcChosenLanguage() -> String {
    switch AiNpcResolveLanguage() {
        case AiNpcLanguage.French: return "fr";
        case AiNpcLanguage.Spanish: return "es";
        case AiNpcLanguage.German: return "de";
        case AiNpcLanguage.Italian: return "it";
        case AiNpcLanguage.Portuguese: return "pt";
        case AiNpcLanguage.Russian: return "ru";
        case AiNpcLanguage.Ukraine: return "uk";
        default: return "en";
    }
}

// Whether your text should speak of V in the masculine. Folds the player's Auto/Male/Female
// override, so it is not the same question as reading the puppet's gender.
public func AiNpcSpeaksOfPlayerAsMale() -> Bool {
    return Equals(AiNpcResolveGender(), AiNpcGender.Male);
}

// "normal", "nsfw" or "nsfw_hard": the player's answer, asked once by the menu. A second mod
// asking again with its own switch is how a player consents twice and is contradicted by
// whichever they forgot.
//
// A code and not the enum, because a consumer takes ai_npc optionally and cannot name a type
// of ours outside its @if block. Prefer AiNpcAllowsExplicitContent unless you really have
// three texts: comparing this code by hand breaks when a tier is added.
//
// ai_npc does not gate its own authored text on the tier -- the setting constrains what the
// model is asked for, and a hand-written line ships as written. Using this to hide your own
// written content is a rule of yours, not one you inherit.
public func AiNpcChosenTone() -> String {
    return AiNpcToneCodeFor(AiNpcToneTier());
}

// The setting behind AiNpcTicketRefused, asked before you arm a trigger rather than after you
// have built a reason for one.
//
// A question about the gesture -- being written to out of nowhere -- not about who writes the
// text, so it is also the answer for your own authored SMS. ai_npc cannot gate that one:
// CharacterWrote sends nothing and the notification is on your side.
public func AiNpcMayWriteFirst() -> Bool {
    return AiNpcUnpromptedEnabled();
}

// True at both NSFW tiers. The stable form of the question above: a tier added later cannot
// flip this to yes, because the answer is enumerated rather than derived from "not Normal".
public func AiNpcAllowsExplicitContent() -> Bool {
    return AiNpcToneAllowsExplicitFor(AiNpcToneTier());
}

// Whether V and this contact are together, per the save for a built-in and per whoever
// declared it for anyone else.
public func AiNpcCharacterIsRomanced(contactId: String) -> Bool {
    return AiNpcIsContactRomanced(contactId);
}

// Expands {they}, {them}, {their}, {partner} and {gender}, so a line your mod wrote agrees
// with V's gender as a character definition would.
public func AiNpcExpand(text: String) -> String {
    return AiNpcExpandTemplate(text);
}

// The same, plus the per-contact set ({npc}, {language}...).
public func AiNpcExpandFor(contactId: String, text: String) -> String {
    return AiNpcExpandTemplateFor(contactId, text);
}

// Exposed because a phone framework indexes contacts by hash and a bridge has to get back to
// the id. Never reimplement it: a divergent copy compiles, logs nothing, and reads in game as
// a thread whose chat opens on nothing.
public func AiNpcContactKey(contactId: String) -> Int32 {
    return AiNpcContactHash(contactId);
}

// "Send nothing at all", as opposed to "", which means "hand this message to the model". Two
// emptinesses, and this is the one that cannot be guessed.
public func AiNpcSilentAnswer() -> String {
    return AiNpcSilentReply();
}
