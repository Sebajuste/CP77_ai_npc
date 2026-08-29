// How the two tags every ai_npc contact carries are spelled.
//
// In api\ because a mod scopes its own command with them -- AddAction(..., AiNpcEveryContactTag())
// reaches an anonymous escort minted at runtime by a mod it has never seen. Two literals, and
// they are contract: a mod that wrote "ainpc:contact" by hand would keep working right up to
// the day the spelling changed, and would then reach nobody, silently.
//
// Who CARRIES a tag, and who may say so, is AiNpcContactTags.reds. Nothing here grants
// anything.

module AiNpc

// Every drivable contact carries it. This is how "everyone" is spelled: an ordinary tag, so
// the matcher has one code path and no wildcard, and so a global grant is a thing the load
// report can name and the player can read.
public func AiNpcEveryContactTag() -> String {
    return "ainpc:contact";
}

// One per contact. This is how "attached to this character" is spelled, and it is what makes
// a runtime-minted contact reachable with no list to keep.
public func AiNpcContactTagFor(contactId: String) -> String {
    return "contact:" + contactId;
}
