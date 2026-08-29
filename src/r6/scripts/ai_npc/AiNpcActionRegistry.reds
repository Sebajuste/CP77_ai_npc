// Every command any mod has declared, and every one anybody has taken away.
//
// One registry for all of them -- the built-in eddie transfer included, registered through the
// public door like everybody else. That is not politeness, it is the only way the two halves
// of a command stay in step: whatever is in here is what the model is told AND what the
// dispatcher honours, because both read this list. The four defects recorded in
// docs/PLAN_ACTION_LANE.md were all divergences between two lists that were supposed to say
// the same thing.
//
// Sorted by full id ("<modId>:<verb>"), never by registration order: ScriptableSystem attach
// order is not guaranteed and differs between two loads of the same save, so ordering on it
// would make a character's prompt change from one launch to the next. Sorted on insert,
// because registrations happen once at attach and queries happen on every message.
module AiNpc

/// What is registered ///

public class AiNpcActionClaim {
    public let fullId: String;
    public let modId: String;
    public let pattern: ref<AiNpcActionPattern>;
    public let prompt: String;

    // What the pattern's slots mean. Rendered once for the whole block, not once per command:
    // see AiNpcRenderActionBlock.
    public let parameters: array<ref<AiNpcActionParam>>;
    public let handler: ref<AiNpcActionHandler>;

    // Who may use the command. One tag, never a list: a mod that means two audiences means two
    // commands or one tag that covers both, and both of those are things a reader can see.
    public let scopeTag: String;

    // A claim attached to one character outranks one granted to a category, for that character.
    // Deterministic, and it is the useful direction: "this one sends money differently" is a
    // registration rather than a negotiation.
    public func IsDirect() -> Bool {
        return StrBeginsWith(this.scopeTag, "contact:");
    }
}

// Removing a command from a character, scoped exactly like a claim so there is one matcher and
// not two.
//
// One-way. Nobody can grant back what another mod removed -- that is the existing merge
// doctrine of AiNpcCharacterExtension, where permissions merge by veto, applied to a case it
// already covered: a global command is a permission granted to a character, so the character's
// declarer keeps the last word on it.
public class AiNpcActionSuppression {
    public let modId: String;
    public let head: String;
    public let scopeTag: String;
}

/// The registry ///

public class AiNpcActionRegistry extends ScriptableSystem {

    private let m_claims: array<ref<AiNpcActionClaim>>;
    private let m_suppressions: array<ref<AiNpcActionSuppression>>;

    public static func Get(game: GameInstance) -> ref<AiNpcActionRegistry> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcActionRegistry>()) as AiNpcActionRegistry;
    }

    /// Registration ///

    // Idempotent by full id: re-declaring the same verb replaces it, so a mod calls this
    // unconditionally on every attach. Every refusal is a declaration its author could not have
    // meant, and each one would otherwise become a command advertised to a model and honoured
    // by nobody -- so they are refused loudly here, in front of the author, rather than
    // reaching the player as a bracket mid-sentence.
    public func RegisterAction(modId: String, patternRaw: String, prompt: String,
                               handler: ref<AiNpcActionHandler>, scopeTag: String,
                               opt parameters: array<ref<AiNpcActionParam>>) -> Bool {
        if Equals(StrLen(modId), 0) {
            return false;
        }
        if !IsDefined(handler) {
            FTLogError(s"[ai_npc]: action \(patternRaw) from '\(modId)' refused: no handler.");
            return false;
        }
        if Equals(StrLen(prompt), 0) {
            FTLogError(s"[ai_npc]: action \(patternRaw) from '\(modId)' refused: no prompt. A command with no trigger is one the model emits at random or never.");
            return false;
        }

        // The scope is required and there is no default. An omission must NARROW reach, never
        // widen it: a permissive default is discovered by the player, in play, on the day the
        // model happens to emit the tag, while a refused registration is discovered by the
        // author immediately. "Everyone" is spelled AiNpcEveryContactTag() and nobody writes
        // that by accident.
        if Equals(StrLen(scopeTag), 0) {
            FTLogError(s"[ai_npc]: action \(patternRaw) from '\(modId)' refused: no scope tag. Name the tag whose bearers may use it -- \"\(AiNpcEveryContactTag())\" for every contact.");
            return false;
        }
        if !AiNpcTagIsWellFormed(scopeTag) {
            FTLogError(s"[ai_npc]: action \(patternRaw) from '\(modId)' refused: \"\(scopeTag)\" is not a tag.");
            return false;
        }
        let refusal = "";
        let pattern = AiNpcParseActionPattern(patternRaw, refusal);
        if !IsDefined(pattern) {
            FTLogError(s"[ai_npc]: action \(patternRaw) from '\(modId)' refused: \(refusal).");
            return false;
        }

        let paramRefusal = AiNpcActionParamsRefusal(pattern, parameters);
        if NotEquals(StrLen(paramRefusal), 0) {
            FTLogError(s"[ai_npc]: action \(patternRaw) from '\(modId)' refused: \(paramRefusal).");
            return false;
        }

        let claim = new AiNpcActionClaim();
        claim.modId = modId;
        claim.pattern = pattern;
        claim.fullId = modId + ":" + pattern.verb;
        claim.prompt = prompt;
        claim.parameters = parameters;
        claim.handler = handler;
        claim.scopeTag = scopeTag;

        let existingIds = this.ClaimIds();
        let existing = AiNpcIdIndexOf(existingIds, claim.fullId);
        if existing >= 0 {
            this.m_claims[existing] = claim;
            return true;
        }

        ArrayInsert(this.m_claims, AiNpcIdInsertionPoint(existingIds, claim.fullId), claim);
        AiNpcLog(s"Registered action \(pattern.raw) as '\(claim.fullId)' for \(scopeTag).");
        this.ReportHeadCollisions(claim);
        return true;
    }

    public func UnregisterAction(modId: String, verb: String) -> Bool {
        let ids = this.ClaimIds();
        let index = AiNpcIdIndexOf(ids, modId + ":" + verb);
        if index < 0 {
            return false;
        }
        ArrayErase(this.m_claims, index);
        return true;
    }

    // Everything one declarer registered, claims and suppressions alike. Walked backwards so
    // erasing does not move entries the loop has not reached yet.
    //
    // What a re-read of a character sheet needs: registering again replaces command for
    // command, so a sheet that has DROPPED one would otherwise keep it alive from the previous
    // read -- a command the file no longer declares, still advertised and still firing.
    public func UnregisterAllFor(modId: String) -> Void {
        let i = ArraySize(this.m_claims) - 1;
        while i >= 0 {
            if Equals(this.m_claims[i].modId, modId) {
                ArrayErase(this.m_claims, i);
            }
            i -= 1;
        }

        let j = ArraySize(this.m_suppressions) - 1;
        while j >= 0 {
            if Equals(this.m_suppressions[j].modId, modId) {
                ArrayErase(this.m_suppressions, j);
            }
            j -= 1;
        }
    }

    /// Suppression ///

    public func SuppressAction(modId: String, head: String, scopeTag: String) -> Bool {
        if Equals(StrLen(modId), 0) || Equals(StrLen(head), 0) {
            return false;
        }
        if Equals(StrLen(scopeTag), 0) || !AiNpcTagIsWellFormed(scopeTag) {
            FTLogError(s"[ai_npc]: '\(modId)' cannot suppress \(head): no scope tag.");
            return false;
        }

        let i = 0;
        let count = ArraySize(this.m_suppressions);
        while i < count {
            let existing = this.m_suppressions[i];
            if Equals(existing.modId, modId) && Equals(existing.head, head)
                    && Equals(existing.scopeTag, scopeTag) {
                return true;
            }
            i += 1;
        }

        let entry = new AiNpcActionSuppression();
        entry.modId = modId;
        entry.head = head;
        entry.scopeTag = scopeTag;
        ArrayPush(this.m_suppressions, entry);
        AiNpcLog(s"'\(modId)' suppressed \(head) for \(scopeTag).");
        return true;
    }

    // A mod lifts only its own. Another mod's identical suppression stands -- that is what
    // one-way means, and it is why a mod that has taken responsibility for a character's
    // economy cannot be overridden by whoever registers afterwards.
    public func UnsuppressAction(modId: String, head: String, scopeTag: String) -> Bool {
        let i = 0;
        while i < ArraySize(this.m_suppressions) {
            let existing = this.m_suppressions[i];
            if Equals(existing.modId, modId) && Equals(existing.head, head)
                    && Equals(existing.scopeTag, scopeTag) {
                ArrayErase(this.m_suppressions, i);
                return true;
            }
            i += 1;
        }
        return false;
    }

    /// Reading ///

    public func Claims() -> array<ref<AiNpcActionClaim>> {
        return this.m_claims;
    }

    public func Suppressions() -> array<ref<AiNpcActionSuppression>> {
        return this.m_suppressions;
    }

    private func ClaimIds() -> array<String> {
        let ids: array<String>;
        let i = 0;
        let count = ArraySize(this.m_claims);
        while i < count {
            ArrayPush(ids, this.m_claims[i].fullId);
            i += 1;
        }
        return ids;
    }

    /// Diagnostics ///

    // Two mods claiming one command head is the single collision this design cannot make
    // unsayable, so it is reported the moment it becomes true rather than noticed later as a
    // command that sometimes does the wrong thing. Reported, not refused: the second claimant
    // is usually right about everything else it contributes, and a contact carrying only one
    // of the two scopes never sees the conflict at all.
    private func ReportHeadCollisions(claim: ref<AiNpcActionClaim>) -> Void {
        let i = 0;
        let count = ArraySize(this.m_claims);
        while i < count {
            let other = this.m_claims[i];
            if NotEquals(other.fullId, claim.fullId)
                    && Equals(other.pattern.head, claim.pattern.head) {
                FTLogError(s"[ai_npc]: command \(claim.pattern.head) is claimed by both '\(claim.fullId)' (for \(claim.scopeTag)) and '\(other.fullId)' (for \(other.scopeTag)). A contact carrying both tags gets the more specific claim, then the lower id.");
            }
            i += 1;
        }
    }
}

// Whether any registered command would recognise this tag, ignoring scope.
//
// For the load report, which reads a character file before knowing which contacts exist and
// cannot ask a table. It answers the one question worth asking there -- "does this command
// exist at all" -- and deliberately not "may this character use it", which is a question about
// tags that only has an answer at message time.
func AiNpcActionHeadIsClaimed(tag: String) -> Bool {
    let registry = AiNpcGetActionRegistry();
    if !IsDefined(registry) {
        return false;
    }

    let claims = registry.Claims();
    let i = 0;
    let count = ArraySize(claims);
    while i < count {
        if AiNpcMatchActionPattern(claims[i].pattern, tag).headMatched {
            return true;
        }
        i += 1;
    }
    return false;
}

public func AiNpcGetActionRegistry() -> ref<AiNpcActionRegistry> {
    return AiNpcActionRegistry.Get(GetGameInstance());
}

// The mod id ai_npc registers its own commands under. Stated once: it is the id that may
// target the reserved namespace, and a second spelling of it is a privilege granted by
// accident.
func AiNpcOwnModId() -> String {
    return "ai_npc";
}
