// The shipped cast: which characters exist, in what order, and how a sheet is copied.
//
// One line per character, and one file per character next to it in cast\. Everything about
// somebody -- name, bio, relationship, romance fact, quest context, rule block -- is in
// their own sheet, so adding a character is adding a file and a line here, and modifying
// one is opening one file.
//
// A sheet cannot be half-written -- it is one object -- and an id nobody ships resolves to
// nothing at all rather than falling through to somebody else.
//
// The cast is built ONCE per session, by the contact registry, which then holds a provider
// per sheet. Nothing here is called per message: a sheet allocates a dozen long strings and
// AiNpcGetAllContactIds is read on every message, which is why the id list below is written
// out rather than derived from the sheets -- with a self-test asserting the two agree.
module AiNpc

/// The cast ///

func AiNpcBuiltinCast() -> array<ref<AiNpcCharacterDef>> {
    return [
        AiNpcSheetPanam(),
        AiNpcSheetJudy(),
        AiNpcSheetRiver(),
        AiNpcSheetKerry(),
        AiNpcSheetSongbird(),
        AiNpcSheetRogue(),
        AiNpcSheetViktor(),
        AiNpcSheetTakemura(),
        AiNpcSheetJackie(),
        AiNpcSheetJackieArchive(),
        AiNpcSheetJesse()
    ];
}

// The sheet a shipped character is defined by, or null. Every field of the answer may be
// read, none of it may be kept: the config loader takes a copy and writes overrides onto
// it, and a caller that held the original instead would see one player's edits applied to
// the built-in text of everybody's game.
func AiNpcBuiltinSheet(contactId: String) -> ref<AiNpcCharacterDef> {
    let cast = AiNpcBuiltinCast();
    let i = 0;
    let count = ArraySize(cast);
    while i < count {
        if Equals(cast[i].contactId, contactId) {
            return cast[i];
        }
        i += 1;
    }
    return null;
}

/// Copying ///

// A copy of a sheet, deep enough to be written on.
//
// This is what makes "config overrides the built-in text, field by field" a fact rather
// than a convention: the loader starts from this and assigns only the keys the file
// actually carries, so an absent key means "keep what you had" without any code saying so.
//
// The arrays are copied; their elements are not. A variant and a quest entry are read-only
// once built -- nothing in the mod mutates one -- and copying the array is what keeps a
// file that declares its own variants from appending to the built-in ones.
func AiNpcCopySheet(source: ref<AiNpcCharacterDef>) -> ref<AiNpcCharacterDef> {
    let copy = new AiNpcCharacterDef();
    if !IsDefined(source) {
        return copy;
    }

    copy.contactId = source.contactId;
    copy.displayName = source.displayName;
    copy.bio = source.bio;
    copy.relationship = source.relationship;
    copy.romance = source.romance;
    copy.liveContext = source.liveContext;
    copy.speechStyle = source.speechStyle;
    copy.spokenStyle = source.spokenStyle;
    copy.romanceable = source.romanceable;
    copy.romanced = source.romanced;
    copy.romanceFact = source.romanceFact;
    copy.allowsMemory = source.allowsMemory;
    copy.enabled = source.enabled;
    copy.source = source.source;
    copy.prompts = source.prompts;
    // Partage plutot que copie, comme `prompts` juste au-dessus : personne ne mute une
    // definition de voix apres coup, et le lecteur JSON en construit une neuve.
    copy.voice = source.voice;
    copy.intent = source.intent;

    let i = 0;
    let facts = ArraySize(source.seedFacts);
    while i < facts {
        ArrayPush(copy.seedFacts, source.seedFacts[i]);
        i += 1;
    }

    i = 0;
    let variants = ArraySize(source.variants);
    while i < variants {
        ArrayPush(copy.variants, source.variants[i]);
        i += 1;
    }

    i = 0;
    let quests = ArraySize(source.questContexts);
    while i < quests {
        ArrayPush(copy.questContexts, source.questContexts[i]);
        i += 1;
    }

    i = 0;
    let intents = ArraySize(source.questIntents);
    while i < intents {
        ArrayPush(copy.questIntents, source.questIntents[i]);
        i += 1;
    }

    i = 0;
    let actions = ArraySize(source.actions);
    while i < actions {
        ArrayPush(copy.actions, source.actions[i]);
        i += 1;
    }

    i = 0;
    let refused = ArraySize(source.suppressActions);
    while i < refused {
        ArrayPush(copy.suppressActions, source.suppressActions[i]);
        i += 1;
    }

    i = 0;
    let tags = ArraySize(source.tags);
    while i < tags {
        ArrayPush(copy.tags, source.tags[i]);
        i += 1;
    }

    i = 0;
    let lines = ArraySize(source.scriptedReply);
    while i < lines {
        ArrayPush(copy.scriptedReply, source.scriptedReply[i]);
        i += 1;
    }

    return copy;
}
