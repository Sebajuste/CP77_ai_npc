// Ordering the contact list.
//
// Pure: no game API, no store, no widget. The page reads the two facts a contact is sorted by
// -- its display name and when it last said something -- and hands them here as parallel
// arrays, which is what makes the ordering testable without a session.
//
// "Recent" falls back to alphabetical rather than to nothing. A message carries the in-game
// time it was written (AiNpcMessage.gameTimeSeconds), and 0 means "no answer" -- an untimed
// message, or a contact with no conversation at all. Sorting those by time would order them
// by whatever the id list happened to hold, which reads as random and changes between
// sessions. So an unknown time sorts LAST and ties are broken alphabetically: on a fresh save
// both orders agree, and they separate as the player actually talks to people.

module AiNpc

public enum AiNpcTerminalOrder {
    Recent = 0,
    Alphabetical = 1
}

// The next mode, for a header that toggles rather than opens a menu. Two modes, so it is a
// toggle; written as a switch so a third mode is a line rather than a rethink.
func AiNpcTerminalNextOrder(order: AiNpcTerminalOrder) -> AiNpcTerminalOrder {
    switch order {
        case AiNpcTerminalOrder.Recent:
            return AiNpcTerminalOrder.Alphabetical;
        default:
            return AiNpcTerminalOrder.Recent;
    }
}

// True when `a` belongs before `b`.
//
// Case-insensitive on the name: the cast is stored with whatever capitalisation its
// character sheet uses, and a player reading a list does not expect "Judy" to sort before
// "jackie" because of an upper-case J.
func AiNpcTerminalOrderBefore(nameA: String, timeA: Int32,
                                     nameB: String, timeB: Int32,
                                     order: AiNpcTerminalOrder) -> Bool {
    if Equals(order, AiNpcTerminalOrder.Alphabetical) {
        return StrCmp(StrLower(nameA), StrLower(nameB)) < 0;
    }

    // Recent, newest first. An unknown time is not "very old" -- it is not a time at all --
    // so it goes to the end of the list rather than to the top of the oldest.
    let hasA: Bool = timeA > 0;
    let hasB: Bool = timeB > 0;
    if NotEquals(hasA, hasB) {
        return hasA;
    }
    if hasA && NotEquals(timeA, timeB) {
        return timeA > timeB;
    }
    return StrCmp(StrLower(nameA), StrLower(nameB)) < 0;
}

// The ids, ordered. `names` and `times` are read at the same index as `ids`.
//
// Insertion sort, because the list is a dozen entries and because it is STABLE: two
// contacts the comparison cannot separate keep the order the caller gave them, so the page
// does not reshuffle itself between two builds that read the same data.
//
// Mismatched array lengths return the input untouched rather than indexing past the end:
// the caller builds all three in one pass, so a mismatch is a bug in the CALLER, and a
// silently reordered list would hide it.
func AiNpcTerminalOrderIds(ids: array<String>, names: array<String>,
                                  times: array<Int32>,
                                  order: AiNpcTerminalOrder) -> array<String> {
    let count = ArraySize(ids);
    if NotEquals(ArraySize(names), count) || NotEquals(ArraySize(times), count) {
        return ids;
    }

    let sortedIds: array<String>;
    let sortedNames: array<String>;
    let sortedTimes: array<Int32>;

    let i: Int32 = 0;
    while i < count {
        // Where this entry belongs among the ones already placed.
        let at: Int32 = ArraySize(sortedIds);
        let j: Int32 = 0;
        let placed: Bool = false;
        while j < ArraySize(sortedIds) && !placed {
            if AiNpcTerminalOrderBefore(names[i], times[i], sortedNames[j], sortedTimes[j],
                                        order) {
                at = j;
                placed = true;
            }
            j += 1;
        }

        ArrayInsert(sortedIds, at, ids[i]);
        ArrayInsert(sortedNames, at, names[i]);
        ArrayInsert(sortedTimes, at, times[i]);
        i += 1;
    }

    return sortedIds;
}
