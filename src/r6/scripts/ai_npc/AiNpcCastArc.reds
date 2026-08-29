// The shipped cast's own story beats, turned into fact watches.
//
// A sheet declares what its character lives through as `arc`, one AiNpcArcBeat per moment:
// the quest fact that says it happened, and the sentence they carry afterwards. This file is
// the only thing that knows how such a beat becomes a watch the fact bridge can register.
//
// WHY THE MEMORY AND NOT A VARIANT. A variant replaces a field, so the first one that matches
// wins and only the latest moment speaks -- and a character who reached the parade would stop
// knowing about the roof. An arc accumulates: after the fourth beat the first three are still
// true. The memory block is the only channel in the prompt that accumulates AND outranks the
// sheet, which is what a thing that has happened needs against a bio written before it.
//
// WHY NOT facts.*.json. That file is the door for mods that have never heard of ai_npc, and
// it is rewritten at runtime under r6\storages\. Content the mod ships belongs in src\, and
// content about a character belongs in that character's sheet.
module AiNpc

// Every shipped beat, as watches the bridge can register. Built once, at player attach.
func AiNpcArcWatches() -> array<ref<AiNpcFactWatch>> {
    let watches: array<ref<AiNpcFactWatch>>;
    let cast = AiNpcBuiltinCast();

    let c = 0;
    while c < ArraySize(cast) {
        let sheet = cast[c];
        if sheet.enabled {
            let b = 0;
            while b < ArraySize(sheet.arc) {
                ArrayPush(watches, AiNpcArcWatchFor(sheet.contactId, sheet.arc[b]));
                b += 1;
            }
        }
        c += 1;
    }
    return watches;
}

// One beat, as a watch. The contact list is the one character: a beat is something that
// happened to them, and telling somebody else about it is what facts.*.json is for.
func AiNpcArcWatchFor(contactId: String, beat: ref<AiNpcArcBeat>) -> ref<AiNpcFactWatch> {
    let watch = new AiNpcFactWatch();
    watch.fact = beat.fact;
    watch.atLeast = beat.atLeast;
    watch.event = beat.text;
    watch.remembered = true;
    watch.unlessFact = beat.unlessFact;
    ArrayPush(watch.contacts, contactId);

    // No ackFact: nothing outside is waiting to hear that our own character took the news.
    watch.source = "ai_npc";
    return watch;
}
