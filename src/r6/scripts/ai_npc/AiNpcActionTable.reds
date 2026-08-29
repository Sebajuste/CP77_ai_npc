// The commands one contact actually has, resolved once and read by both halves.
//
// THIS IS THE POINT OF THE WHOLE LANE. The prompt renders this table; the dispatcher indexes
// it. What the model is told and what the mod honours are therefore the same object, not two
// computations that have to be kept in agreement -- and every defect this refactor was written
// for was a disagreement between two such computations.
//
// Built per contact, per turn. Once when the prompt is assembled, once when the reply comes
// back, because between the two there is a network round trip and the world moves inside it.
// The two builds are the SAME function, which is what keeps the answers comparable.
module AiNpc

/// Looking a tag up ///

public class AiNpcActionLookup {
    public let claim: ref<AiNpcActionClaim>;
    public let match: ref<AiNpcPatternMatch>;

    public func Owned() -> Bool {
        return IsDefined(this.claim);
    }

    public func Complete() -> Bool {
        return IsDefined(this.match) && this.match.complete;
    }
}

/// The table ///

public class AiNpcActionTable {
    public let contactId: String;
    public let tags: array<String>;

    // The OWNERSHIP set: every claim this contact is covered by, whether or not its handler is
    // offering it this turn. Ownership and offering are different questions and this is the
    // one that decides whether a bracket is recognised.
    public let claims: array<ref<AiNpcActionClaim>>;

    // Which claim owns a tag, and whether the tag is complete enough to run.
    //
    // A complete match wins over a bare head match: two patterns can share a prefix --
    // "[ACTION:MEET:" and "[ACTION:MEET:NOTELL:" -- and the one that actually parses the tag is
    // the one that meant it.
    public func Lookup(tag: String) -> ref<AiNpcActionLookup> {
        let lookup = new AiNpcActionLookup();

        let i = 0;
        let count = ArraySize(this.claims);
        while i < count {
            let claim = this.claims[i];
            let match = AiNpcMatchActionPattern(claim.pattern, tag);
            if match.complete {
                lookup.claim = claim;
                lookup.match = match;
                return lookup;
            }
            if match.headMatched && !IsDefined(lookup.claim) {
                lookup.claim = claim;
                lookup.match = match;
            }
            i += 1;
        }
        return lookup;
    }
}

/// Building it ///

// Three passes, and each one exists because leaving it out was a defect somewhere:
//
//   scope         a claim reaches a contact only through a tag the contact carries
//   suppression   the character's declarer may take a command away, and nobody gives it back
//   arbitration   two claims on one command head resolve to one, deterministically
//
// Pure, and separate from the lookup below for exactly that reason: this is the rule the whole
// lane turns on, and a rule that needs a running game to check is one that gets checked once.
// The claims arrive already sorted by full id, so "the first survivor" is a stable answer
// across launches where registration order is not.
func AiNpcResolveClaims(claims: array<ref<AiNpcActionClaim>>, tags: array<String>,
                               suppressions: array<ref<AiNpcActionSuppression>>) -> array<ref<AiNpcActionClaim>> {
    let surviving: array<ref<AiNpcActionClaim>>;
    let heads: array<String>;

    let i = 0;
    let count = ArraySize(claims);
    while i < count {
        let claim = claims[i];
        // Bound to a local before ArrayContains: the intrinsics take their operand by
        // reference and a call result has no stable slot, so passing the call directly
        // answers false every time.
        let scope = claim.scopeTag;
        if ArrayContains(tags, scope)
                && !AiNpcActionIsSuppressed(suppressions, tags, claim.pattern.head) {
            let head = claim.pattern.head;
            let taken = AiNpcIndexOfString(heads, head);
            if taken < 0 {
                ArrayPush(heads, head);
                ArrayPush(surviving, claim);
            } else {
                // Same command, two claimants, and the contact carries both tags. Attachment
                // to this character beats a grant to a category; otherwise the lower id wins,
                // which the ordering has already decided.
                if claim.IsDirect() && !surviving[taken].IsDirect() {
                    surviving[taken] = claim;
                }
            }
        }
        i += 1;
    }

    return surviving;
}

// One suppression covering this contact is enough, and no claim can put the command back.
func AiNpcActionIsSuppressed(suppressions: array<ref<AiNpcActionSuppression>>,
                                    tags: array<String>, head: String) -> Bool {
    let i = 0;
    let count = ArraySize(suppressions);
    while i < count {
        let scope = suppressions[i].scopeTag;
        if Equals(suppressions[i].head, head) && ArrayContains(tags, scope) {
            return true;
        }
        i += 1;
    }
    return false;
}

// The same resolution, for a contact of a running session.
func AiNpcBuildActionTable(contactId: String) -> ref<AiNpcActionTable> {
    let table = new AiNpcActionTable();
    table.contactId = contactId;

    if Equals(StrLen(contactId), 0) {
        return table;
    }
    table.tags = AiNpcContactTags(contactId);

    let registry = AiNpcGetActionRegistry();
    if !IsDefined(registry) {
        return table;
    }

    table.claims = AiNpcResolveClaims(registry.Claims(), table.tags, registry.Suppressions());
    return table;
}

/// Writing one by hand ///

// For a test, and for nothing else: every other caller builds a table from the registry. It is
// public because the alternative -- asserting the arbitration through a live registry -- is a
// test that needs a game launch to run, which is a test that runs once.
func AiNpcActionClaimOf(fullId: String, pattern: String, scopeTag: String,
                               handler: ref<AiNpcActionHandler>) -> ref<AiNpcActionClaim> {
    let refusal = "";
    let parsed = AiNpcParseActionPattern(pattern, refusal);
    if !IsDefined(parsed) {
        return null;
    }

    let claim = new AiNpcActionClaim();
    claim.fullId = fullId;
    claim.modId = fullId;
    claim.pattern = parsed;
    claim.prompt = "test";
    claim.handler = handler;
    claim.scopeTag = scopeTag;
    return claim;
}
