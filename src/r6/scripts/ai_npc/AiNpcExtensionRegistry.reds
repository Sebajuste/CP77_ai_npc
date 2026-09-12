// Where several mods' contributions to one character are held and merged. Declarations are
// AiNpcContactRegistry's, one provider per contact; this is the other half -- N contributions,
// no claim to win, and a merge rule per method written into AiNpcCharacterExtension.
//
// Sorted by full id ("<modId>:<subject>"), never by registration order: attachment order of
// ScriptableSystems is not guaranteed, so it differs between two loads of the same save, and
// ordering on it would make Rogue's prompt change from one launch to the next. Sorted on
// insert, because registrations happen once at attach and queries on every message.
//
// The trap: the key is the id, and a mnemonic id's alphabetical order is not the order its
// author has in mind -- "johnny_leisure" runs before "rogue_gigs" however the scene reads.
// Order a test or a worked example by the string, not by the story: it compiles clean either
// way and diverges only at a game launch.
//
// Listeners live here too and are the easy half: nothing they return is read, so they need no
// order, budget or arbitration. They share the registration lifetime and nothing else.
//
// Commands are NOT here. What a character can do is declared with client.AddAction and lives
// in AiNpcActionRegistry, scoped by a tag rather than by this class's contact list -- which is
// what lets a command reach a contact minted at runtime, and what keeps the announcement and
// the dispatch reading one list instead of two.

module AiNpc

/// Entries ///

// A registered contribution, plus the id it is sorted by and the contacts it covers. The
// contact list is read once at registration and cached, which is a contract: it keeps a
// message from making a virtual call into every installed extension just to find out it was
// not addressed. To change the list, register again.
public class AiNpcExtensionEntry {
    public let fullId: String;
    public let modId: String;
    public let subject: String;
    public let contactIds: array<String>;
    public let ext: ref<AiNpcCharacterExtension>;

    // An empty list means every drivable contact, which is the whole point of allowing it.
    public func Covers(contactId: String) -> Bool {
        if Equals(ArraySize(this.contactIds), 0) {
            return true;
        }
        return ArrayContains(this.contactIds, contactId);
    }
}

public class AiNpcListenerEntry {
    public let fullId: String;
    public let modId: String;
    public let subject: String;
    public let contactIds: array<String>;
    public let listener: ref<AiNpcConversationListener>;

    public func Covers(contactId: String) -> Bool {
        if Equals(ArraySize(this.contactIds), 0) {
            return true;
        }
        return ArrayContains(this.contactIds, contactId);
    }
}

/// The registry ///

// A ScriptableSystem for the same reason AiNpcContactRegistry is one: the lifetime is the
// game session. Registrations must not leak across a save load, and a mod re-registers on
// every attach.
public class AiNpcExtensionRegistry extends ScriptableSystem {

    private let m_extensions: array<ref<AiNpcExtensionEntry>>;
    private let m_listeners: array<ref<AiNpcListenerEntry>>;

    public static func Get(game: GameInstance) -> ref<AiNpcExtensionRegistry> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcExtensionRegistry>()) as AiNpcExtensionRegistry;
    }

    /// Registration ///

    // Idempotent by full id: re-registering the same subject replaces its entry, so a mod can
    // call this unconditionally on every attach. It never refuses for conflict, because there
    // is none to have; the only false is a malformed contribution.
    public func RegisterExtension(modId: String, ext: ref<AiNpcCharacterExtension>) -> Bool {
        if !IsDefined(ext) || Equals(StrLen(modId), 0) {
            return false;
        }

        let subject = ext.GetSubject();
        if Equals(StrLen(subject), 0) {
            FTLogError(s"[ai_npc]: extension from '\(modId)' refused: no subject.");
            return false;
        }

        let entry = new AiNpcExtensionEntry();
        entry.modId = modId;
        entry.subject = subject;
        entry.fullId = modId + ":" + subject;
        entry.contactIds = ext.GetContactIds();
        entry.ext = ext;

        let existingIds = this.ExtensionIds();
        let existing = AiNpcIdIndexOf(existingIds, entry.fullId);
        if existing >= 0 {
            this.m_extensions[existing] = entry;
            return true;
        }

        ArrayInsert(this.m_extensions, AiNpcIdInsertionPoint(existingIds, entry.fullId), entry);
        AiNpcLog(s"Registered extension '\(entry.fullId)'.");
        return true;
    }

    public func UnregisterExtension(modId: String, subject: String) -> Bool {
        let ids = this.ExtensionIds();
        let index = AiNpcIdIndexOf(ids, modId + ":" + subject);
        if index < 0 {
            return false;
        }
        ArrayErase(this.m_extensions, index);
        return true;
    }

    public func RegisterListener(modId: String, listener: ref<AiNpcConversationListener>) -> Bool {
        if !IsDefined(listener) || Equals(StrLen(modId), 0) {
            return false;
        }

        let subject = listener.GetSubject();
        if Equals(StrLen(subject), 0) {
            FTLogError(s"[ai_npc]: listener from '\(modId)' refused: no subject.");
            return false;
        }

        let entry = new AiNpcListenerEntry();
        entry.modId = modId;
        entry.subject = subject;
        entry.fullId = modId + ":" + subject;
        entry.contactIds = listener.GetContactIds();
        entry.listener = listener;

        let existingIds = this.ListenerIds();
        let existing = AiNpcIdIndexOf(existingIds, entry.fullId);
        if existing >= 0 {
            this.m_listeners[existing] = entry;
            return true;
        }

        ArrayInsert(this.m_listeners, AiNpcIdInsertionPoint(existingIds, entry.fullId), entry);
        AiNpcLog(s"Registered listener '\(entry.fullId)'.");
        return true;
    }

    public func UnregisterListener(modId: String, subject: String) -> Bool {
        let ids = this.ListenerIds();
        let index = AiNpcIdIndexOf(ids, modId + ":" + subject);
        if index < 0 {
            return false;
        }
        ArrayErase(this.m_listeners, index);
        return true;
    }

    // Walked backwards so erasing does not move entries the loop has not reached yet.
    public func UnregisterAllFor(modId: String) -> Void {
        let i = ArraySize(this.m_extensions) - 1;
        while i >= 0 {
            if Equals(this.m_extensions[i].modId, modId) {
                ArrayErase(this.m_extensions, i);
            }
            i -= 1;
        }

        let j = ArraySize(this.m_listeners) - 1;
        while j >= 0 {
            if Equals(this.m_listeners[j].modId, modId) {
                ArrayErase(this.m_listeners, j);
            }
            j -= 1;
        }
    }

    /// Reads ///

    public func Extensions() -> array<ref<AiNpcExtensionEntry>> {
        return this.m_extensions;
    }

    public func Listeners() -> array<ref<AiNpcListenerEntry>> {
        return this.m_listeners;
    }

    public func CountExtensions() -> Int32 {
        return ArraySize(this.m_extensions);
    }

    /// Ordering ///

    // Both lists are kept ascending by full id; the arithmetic is in AiNpcExtensionRules, where
    // a suite can reach it. The ids are gathered into a local first, because the array
    // intrinsics take their operand by reference and a call result has no stable slot.

    private func ExtensionIds() -> array<String> {
        let ids: array<String>;
        let i = 0;
        let count = ArraySize(this.m_extensions);
        while i < count {
            ArrayPush(ids, this.m_extensions[i].fullId);
            i += 1;
        }
        return ids;
    }

    private func ListenerIds() -> array<String> {
        let ids: array<String>;
        let i = 0;
        let count = ArraySize(this.m_listeners);
        while i < count {
            ArrayPush(ids, this.m_listeners[i].fullId);
            i += 1;
        }
        return ids;
    }

}

/// Access ///

public func AiNpcGetExtensionRegistry() -> ref<AiNpcExtensionRegistry> {
    return AiNpcExtensionRegistry.Get(GetGameInstance());
}

/// The context every extension method is handed ///

// Built once per question asked of the extensions, not per extension: a dozen contributions on
// one contact must not mean a dozen quest-fact reads.
func AiNpcBuildContactContext(contactId: String, playerText: String,
                              channel: AiNpcChannelId) -> ref<AiNpcContactContext> {
    let medium = AiNpcChannelOf(channel);
    let ctx = new AiNpcContactContext();
    ctx.channel = medium.Name();
    ctx.spoken = medium.IsSpoken();
    ctx.showsInThread = medium.ShowsInThread();
    ctx.contactId = contactId;
    ctx.displayName = AiNpcGetCharacterName(contactId);
    ctx.language = AiNpcChosenLanguage();
    ctx.speaksOfPlayerAsMale = AiNpcSpeaksOfPlayerAsMale();
    ctx.isBuiltIn = AiNpcIsBuiltinContactId(contactId);
    ctx.isRomanced = AiNpcIsContactRomanced(contactId);
    ctx.playerText = playerText;
    return ctx;
}

// Built-in characters answer from the save's romance facts, everyone else from whoever
// declared them.
public func AiNpcIsContactRomanced(contactId: String) -> Bool {
    let provider = AiNpcProviderFor(contactId);
    return IsDefined(provider) && provider.IsRomanced();
}

/// The merges ///

// Every extension's addition to <intent>, in id order, budgeted like <now>.
//
// One line each, joined by a newline, because an intention is read as a paragraph and two
// mods' sentences run together would read as one claim.
func AiNpcExtensionIntent(ctx: ref<AiNpcContactContext>) -> String {
    let merged = "";
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) || !IsDefined(ctx) {
        return merged;
    }

    let spent = 0;
    let entries = registry.Extensions();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(ctx.contactId) {
            let line = AiNpcSafeSectionText(entries[i].ext.GetIntentAddition(ctx), entries[i].fullId);
            if NotEquals(StrLen(line), 0) {
                if StrLen(line) > AiNpcNowLineBudget() {
                    AiNpcLog(s"Extension '\(entries[i].fullId)' intent clamped to \(AiNpcNowLineBudget()) chars.");
                    line = AiNpcMemoryClampTo(line, AiNpcNowLineBudget());
                }

                if spent + StrLen(line) > AiNpcNowTotalBudget() {
                    AiNpcLog(s"Extension '\(entries[i].fullId)' intent dropped: the shared <intent> budget is spent.");
                } else {
                    spent += StrLen(line);
                    merged += AiNpcExpandTemplateFor(ctx.contactId, line) + "
";
                }
            }
        }
        i += 1;
    }
    return merged;
}

// Every extension's rubrics of <system_rules>, in id order.
//
// Collecting only: the locks and the budget live in AiNpcRules.reds and are applied once, by
// the composer, so an extension's contribution is refused for exactly the same reasons a
// sheet's is.
func AiNpcExtensionRules(ctx: ref<AiNpcContactContext>) -> array<ref<AiNpcRule>> {
    return AiNpcExtensionRulesOf("system_rules", ctx);
}

// The same, for <interactions>.
func AiNpcExtensionInteractionRules(ctx: ref<AiNpcContactContext>) -> array<ref<AiNpcRule>> {
    return AiNpcExtensionRulesOf("interactions", ctx);
}

func AiNpcExtensionRulesOf(block: String, ctx: ref<AiNpcContactContext>) -> array<ref<AiNpcRule>> {
    let taken: array<ref<AiNpcRule>>;
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) || !IsDefined(ctx) {
        return taken;
    }

    let entries = registry.Extensions();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(ctx.contactId) {
            let rules = entries[i].ext.GetRuleContributions(block, ctx);
            let j = 0;
            let ruleCount = ArraySize(rules);
            while j < ruleCount {
                if IsDefined(rules[j]) && AiNpcRuleIndexOf(taken, rules[j].key) < 0 {
                    ArrayPush(taken, AiNpcRuleOf(rules[j].key,
                        AiNpcExpandTemplateFor(ctx.contactId, rules[j].text)));
                }
                j += 1;
            }
        }
        i += 1;
    }
    return taken;
}

// Every extension's line, in id order, clamped twice: the per-extension clamp keeps one
// talkative mod from spending the whole budget, the running total keeps twenty quiet ones from
// doing it together. Both drops are logged.
//
// Clamped with AiNpcMemoryClampTo rather than a truncation of its own: it already cuts on a
// boundary instead of mid-word, and two ways to shorten a string is one too many.
func AiNpcExtensionLiveContext(ctx: ref<AiNpcContactContext>) -> String {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return "";
    }

    let merged = "";
    let spent = 0;
    let entries = registry.Extensions();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(ctx.contactId) {
            let line = AiNpcSafeSectionText(entries[i].ext.GetLiveContextAddition(ctx), entries[i].fullId);
            if NotEquals(StrLen(line), 0) {
                if StrLen(line) > AiNpcNowLineBudget() {
                    AiNpcLog(s"Extension '\(entries[i].fullId)' context clamped to \(AiNpcNowLineBudget()) chars.");
                    line = AiNpcMemoryClampTo(line, AiNpcNowLineBudget());
                }

                if spent + StrLen(line) > AiNpcNowTotalBudget() {
                    AiNpcLog(s"Extension '\(entries[i].fullId)' context dropped: the shared <now> budget is spent.");
                } else {
                    spent += StrLen(line);
                    merged += AiNpcExpandTemplateFor(ctx.contactId, line) + "\n";
                }
            }
        }
        i += 1;
    }
    return merged;
}

/// Broadcasts ///
// One shape for all of them: build the event, walk the listeners that cover the contact, hand
// it over, ignore whatever they do. No ordering guarantee and no return value to collect,
// which is why observers cost nothing to add.

func AiNpcPublishMessage(contactId: String, text: String, fromPlayer: Bool, sourceId: String,
                         systemNotice: Bool, channel: AiNpcChannelId) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let medium = AiNpcChannelOf(channel);
    let ev = new AiNpcMessageEvent();
    ev.contactId = contactId;
    ev.text = text;
    ev.fromPlayer = fromPlayer;
    ev.sourceId = sourceId;
    ev.systemNotice = systemNotice;
    ev.channel = medium.Name();
    ev.spoken = medium.IsSpoken();
    ev.showsInThread = medium.ShowsInThread();

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnMessage(ev);
        }
        i += 1;
    }
}

func AiNpcPublishReplyFailed(contactId: String, reason: String) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ev = new AiNpcReplyFailedEvent();
    ev.contactId = contactId;
    ev.reason = reason;

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnReplyFailed(ev);
        }
        i += 1;
    }
}

func AiNpcPublishAction(contactId: String, tag: String, sourceId: String, applied: Bool, note: String) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ev = new AiNpcActionEvent();
    ev.contactId = contactId;
    ev.tag = tag;
    ev.sourceId = sourceId;
    ev.applied = applied;
    ev.note = note;

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnActionApplied(ev);
        }
        i += 1;
    }
}

func AiNpcPublishConversationOpened(contactId: String) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ev = new AiNpcThreadEvent();
    ev.contactId = contactId;

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnConversationOpened(ev);
        }
        i += 1;
    }
}

func AiNpcPublishConversationClosed(contactId: String) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ev = new AiNpcThreadEvent();
    ev.contactId = contactId;

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnConversationClosed(ev);
        }
        i += 1;
    }
}

func AiNpcPublishFactRecorded(contactId: String, ticket: Int32, state: Int32, reason: String) -> Void {
    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return;
    }

    let ev = new AiNpcTicketEvent();
    ev.contactId = contactId;
    ev.ticket = ticket;
    ev.state = state;
    ev.reason = reason;

    let entries = registry.Listeners();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            entries[i].listener.OnTicketSettled(ev);
        }
        i += 1;
    }
}
