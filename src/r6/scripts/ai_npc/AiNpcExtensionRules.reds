// The arithmetic the extension layer rests on, with nothing underneath it.
//
// Two rules, both with a failure that is invisible in game:
//
//   * WHERE AN ID BELONGS. Contributions merge in ascending id so the prompt is identical
//     between two loads of one save. Get that wrong and the prompt reorders itself between
//     launches, which is the class of bug nobody reproduces.
//
//   * WHEN A LEASE IS OVER. The floor expires on read rather than on a timer, because a timer
//     does not survive a save load. Getting the comparison backwards holds a character for
//     the rest of the playthrough on behalf of a mod that stopped.
//
// No game API, no registry, no clock: every input is a parameter, which is what lets the
// suite assert both without a session.

module AiNpc

/// Order ///

// Where `id` belongs in a list already sorted ascending. Returns ArraySize(ids) for an id
// that sorts after everything, which is the append case.
//
// StrCmp, and CASE-SENSITIVE on purpose: an id is a key, not a label. Folding case would order
// "RogueGigs" and "roguegigs" as equal while leaving them two different mods.
//
// The trap this exists to make testable: the key is the STRING. "gamma" sorts after "delta",
// and "johnny_leisure" merges before "rogue_gigs" whatever the scene between them reads like.
// A mnemonic id is exactly the kind whose alphabetical order is not its author's.
func AiNpcIdInsertionPoint(ids: array<String>, id: String) -> Int32 {
    let i = 0;
    let count = ArraySize(ids);
    while i < count {
        if StrCmp(ids[i], id) > 0 {
            return i;
        }
        i += 1;
    }
    return count;
}

// Where `id` already is, or -1. Separate from the insertion point because the two answers are
// different questions: one asks where it goes, the other whether it is already there, and a
// registration that confuses them either duplicates an entry or overwrites its neighbour.
func AiNpcIdIndexOf(ids: array<String>, id: String) -> Int32 {
    return AiNpcIndexOfString(ids, id);
}

/// The floor's lease ///

// How long a claim lasts when the caller does not say, in seconds of engine time.
//
// Generous, because this is a backstop against a mod that stopped rather than a scene timer: a
// scene that ends releases the floor itself, and an expiry is reported as the anomaly it is.
func AiNpcFloorDefaultLease() -> Float {
    return 300.0;
}

// When a claim taken now runs out. A maxSeconds of zero -- the value an `opt` defaults to --
// means "use the default", which is why it is not a valid lease length of its own.
func AiNpcLeaseEndsAt(now: Float, maxSeconds: Float) -> Float {
    if maxSeconds > 0.0 {
        return now + maxSeconds;
    }
    return now + AiNpcFloorDefaultLease();
}

// STRICT: a lease is over the moment its end is reached, not after it. The boundary matters
// because the alternative reading -- still held at exactly expiresAt -- keeps a stopped mod's
// hold alive on any clock that lands on the instant, and there is no reason to prefer the
// answer that holds a character longer.
func AiNpcLeaseHasExpired(expiresAt: Float, now: Float) -> Bool {
    return now >= expiresAt;
}
