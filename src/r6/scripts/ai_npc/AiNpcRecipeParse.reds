// A recipes file read into recipes, and every refusal named.
//
// Pure over a JsonObject: no storage, no service, no session. That is what lets the template
// the mod ships be parsed by exactly this code on every launch, and what lets the whole
// vocabulary be asserted without a game.
//
// NOTHING IS EVER DROPPED IN SILENCE. A misspelled block, an unknown part, a value shape the
// schema does not allow -- each one is reported with the word that was read and the words
// that were allowed. A recipe is written by hand in a text editor, so a typo is not an edge
// case, it is the likeliest thing that will ever happen to this file; and a block that
// quietly stopped being rendered looks exactly like a model that got worse.
//
// A refusal costs the key, never the file. What could not be read keeps the built-in answer.

module AiNpc

import RedData.Json.*

class AiNpcRecipeBook {
    let active: String;
    let recipes: array<ref<AiNpcRecipe>>;
}

// The recipe the mod renders with, or every block at every part when the file names one that
// is not there. Falling back rather than failing: a mistyped "active" should cost the
// selection, not the conversation.
func AiNpcRecipeBookActive(book: ref<AiNpcRecipeBook>) -> ref<AiNpcRecipe> {
    if !IsDefined(book) {
        return AiNpcRecipeFull();
    }
    let i = 0;
    let count = ArraySize(book.recipes);
    while i < count {
        if Equals(book.recipes[i].name, book.active) {
            return book.recipes[i];
        }
        i += 1;
    }
    return AiNpcRecipeFull();
}

/// The file ///

func AiNpcRecipeBookFromJson(root: ref<JsonObject>, fileName: String,
                             out issues: array<ref<AiNpcConfigIssue>>) -> ref<AiNpcRecipeBook> {
    let book = new AiNpcRecipeBook();
    book.active = "default";

    if !IsDefined(root) {
        return book;
    }

    AiNpcRecipeReportUnknown(root, ["version", "active", "recipes"], fileName, "", issues);

    let active = AiNpcJsonString(root, "active");
    if NotEquals(StrLen(active), 0) {
        book.active = active;
    }

    let recipes = AiNpcJsonObjectAt(root, "recipes");
    if !IsDefined(recipes) {
        ArrayPush(issues, AiNpcConfigIssueOf("error", fileName,
            "missing or non-object \"recipes\"; the built-in recipe is used."));
        return book;
    }

    let names = recipes.GetKeys();
    let i = 0;
    let count = ArraySize(names);
    while i < count {
        let name = names[i];
        if !StrBeginsWith(name, "_") {
            let body = AiNpcJsonObjectAt(recipes, name);
            if IsDefined(body) {
                ArrayPush(book.recipes, AiNpcRecipeFromJson(body, name, fileName, issues));
            } else {
                ArrayPush(issues, AiNpcConfigIssueOf("error", fileName,
                    s"recipes.\(name) is not an object; it is ignored."));
            }
        }
        i += 1;
    }

    // Named here rather than left to show up as a prompt that ignores the file: "active"
    // pointing at nothing is the one mistake whose symptom is indistinguishable from the file
    // not being read at all.
    if !AiNpcRecipeBookHas(book, book.active) {
        ArrayPush(issues, AiNpcConfigIssueOf("error", fileName,
            s"active names \"\(book.active)\", which no recipe in this file declares; the built-in recipe is used."));
    }

    return book;
}

func AiNpcRecipeBookHas(book: ref<AiNpcRecipeBook>, name: String) -> Bool {
    let i = 0;
    let count = ArraySize(book.recipes);
    while i < count {
        if Equals(book.recipes[i].name, name) {
            return true;
        }
        i += 1;
    }
    return false;
}

func AiNpcRecipeBookNamed(book: ref<AiNpcRecipeBook>, name: String) -> ref<AiNpcRecipe> {
    if !IsDefined(book) {
        return null;
    }
    let i = 0;
    let count = ArraySize(book.recipes);
    while i < count {
        if Equals(book.recipes[i].name, name) {
            return book.recipes[i];
        }
        i += 1;
    }
    return null;
}

/// One recipe ///

// Every recipe is a DIFFERENCE from the full render, never a declaration of it. A key the
// file leaves out keeps the built-in answer, so a block added to the mod later reaches a file
// written before it existed. Removing a block stays something a player writes on purpose.
func AiNpcRecipeFromJson(body: ref<JsonObject>, name: String, fileName: String,
                         out issues: array<ref<AiNpcConfigIssue>>) -> ref<AiNpcRecipe> {
    let recipe = AiNpcRecipeFull();
    recipe.name = name;

    AiNpcRecipeReportUnknown(body, AiNpcRecipeBlockNames(), fileName, s"\(name).", issues);

    // Read before the loop, and this is the only thing that needs it: <system> and
    // <explicitness> are required of a recipe that describes the conversation, and a recipe
    // written for another pass carries neither.
    let conversation = AiNpcRecipeDescribesConversation(body);

    let schema = AiNpcRecipeSchema();
    let i = 0;
    let count = ArraySize(schema);
    while i < count {
        let entry = schema[i];
        if body.HasKey(entry.key) {
            recipe = AiNpcRecipeWith(recipe,
                AiNpcRecipeBlockFromJson(body, entry, conversation,
                    s"\(fileName): \(name).\(entry.key)", issues));
        }
        i += 1;
    }
    return recipe;
}

// A recipe is a conversation recipe until it says otherwise: silence is not a declaration,
// and a file that has never heard of the instruction block is every file written before this
// version. Only an instruction source naming another pass's builder exempts it.
func AiNpcRecipeDescribesConversation(body: ref<JsonObject>) -> Bool {
    if !IsDefined(body) {
        return true;
    }
    let declared = AiNpcJsonString(AiNpcJsonObjectAt(body, "instruction"), "source");
    if Equals(StrLen(declared), 0) {
        return true;
    }
    return Equals(declared, AiNpcPassInstructionSource(AiNpcLaneSpeaking()));
}

// One block's value, in whichever of the five shapes it was written: an object, a list of
// parts, a level, a boolean, or null.
func AiNpcRecipeBlockFromJson(body: ref<JsonObject>, entry: ref<AiNpcRecipeBlockSchema>,
                              conversation: Bool, where: String,
                              out issues: array<ref<AiNpcConfigIssue>>) -> ref<AiNpcRecipeBlock> {
    let value = body.GetKey(entry.key);

    if IsDefined(value) && value.IsObject() {
        return AiNpcRecipeBlockFromObject(value as JsonObject, entry, conversation, where, issues);
    }
    if IsDefined(value) && value.IsArray() {
        return AiNpcRecipeBlockOfParts(entry,
            AiNpcRecipePartsFromArray(value as JsonArray, entry, conversation, where, issues));
    }
    if IsDefined(value) && value.IsString() {
        return AiNpcRecipeBlockOfParts(entry,
            AiNpcRecipePartsFromLevel(value.GetString(), entry, conversation, where, issues));
    }

    if IsDefined(value) && value.IsBool() {
        if value.GetBool() {
            return AiNpcRecipeBlockOfParts(entry, entry.parts);
        }
        return AiNpcRecipeBlockOfParts(entry, AiNpcRecipeDropped(entry, conversation, where, issues));
    }

    // A number is nobody's way of saying anything about a block, so it is named rather than
    // read as one of the shapes it resembles. Written out because the alternative is a `1`
    // that reads as `true` on one line and a `0` that deletes a block on the next.
    if IsDefined(value) && (value.IsInt64() || value.IsUint64() || value.IsDouble()) {
        ArrayPush(issues, AiNpcConfigIssueOf("error", where,
            "a number says nothing about a block. Write \"full\", \"none\", null, or the list of parts. The block keeps every part."));
        return AiNpcRecipeBlockOfParts(entry, entry.parts);
    }

    // null, and it removes the block -- the fourth spelling of "none", after false and the
    // empty list.
    //
    // It is NOT the same as leaving the key out, and the difference is the whole reason this
    // branch is written rather than inherited. An absent key keeps the mod's answer, so a
    // block added by a later version reaches a file written today; a key written as null is
    // somebody saying "not this one", out loud, in a file they edited on purpose.
    return AiNpcRecipeBlockOfParts(entry, AiNpcRecipeDropped(entry, conversation, where, issues));
}

func AiNpcRecipeBlockFromObject(obj: ref<JsonObject>, entry: ref<AiNpcRecipeBlockSchema>,
                                conversation: Bool, where: String,
                                out issues: array<ref<AiNpcConfigIssue>>) -> ref<AiNpcRecipeBlock> {
    AiNpcRecipeReportUnknown(obj, ["level", "parts", "source"], where, "", issues);

    let parts = entry.parts;
    if obj.HasKey("parts") {
        parts = AiNpcRecipePartsFromArray(AiNpcJsonArrayAt(obj, "parts"), entry, conversation, where, issues);
    } else {
        if obj.HasKey("level") {
            parts = AiNpcRecipePartsFromLevel(AiNpcJsonString(obj, "level"), entry, conversation, where, issues);
        }
    }

    let block = AiNpcRecipeBlockOfParts(entry, parts);
    let source = AiNpcJsonString(obj, "source");
    if NotEquals(StrLen(source), 0) {
        if !AiNpcRecipeIsSourced(entry) {
            ArrayPush(issues, AiNpcConfigIssueOf("warning", where,
                s"\"source\" means nothing to this block; it is ignored."));
        } else {
            let known = entry.sources;
            if !ArrayContains(known, source) {
                ArrayPush(issues, AiNpcConfigIssueOf("error", where,
                    s"source \"\(source)\" is not one of: \(AiNpcRecipeJoinNames(known)). The block keeps its built-in source."));
            } else {
                block.source = source;
            }
        }
    }
    return block;
}

/// Parts ///

// "full" and "none" are the two words, and anything else is named back. A level is where a
// player types a word of their own -- "short", "brief" -- and a silent fallback there would
// be the whole feature failing quietly.
func AiNpcRecipePartsFromLevel(level: String, entry: ref<AiNpcRecipeBlockSchema>,
                               conversation: Bool, where: String,
                               out issues: array<ref<AiNpcConfigIssue>>) -> array<String> {
    if Equals(level, "full") {
        return entry.parts;
    }
    if Equals(level, "none") {
        return AiNpcRecipeDropped(entry, conversation, where, issues);
    }

    ArrayPush(issues, AiNpcConfigIssueOf("error", where,
        s"\"\(level)\" is not a level. Write \"full\", \"none\", null, or the list of parts: \(AiNpcRecipeJoinNames(entry.parts)). The block keeps every part."));
    return entry.parts;
}

// The requested parts, in the SCHEMA's order rather than the file's. The order of a block's
// parts is the mod's -- <memory> reads oldest and blurriest first, and a file listing them
// backwards must not reverse the block.
func AiNpcRecipePartsFromArray(items: ref<JsonArray>, entry: ref<AiNpcRecipeBlockSchema>,
                               conversation: Bool, where: String,
                               out issues: array<ref<AiNpcConfigIssue>>) -> array<String> {
    let requested: array<String>;
    if IsDefined(items) {
        let i: Uint32 = 0u;
        while i < items.GetSize() {
            let item = items.GetItem(i);
            if IsDefined(item) && item.IsString() {
                let part = item.GetString();
                if ArrayContains(entry.parts, part) {
                    ArrayPush(requested, part);
                } else {
                    ArrayPush(issues, AiNpcConfigIssueOf("warning", where,
                        s"\"\(part)\" is not a part of this block. Known parts: \(AiNpcRecipeJoinNames(entry.parts))."));
                }
            }
            i += 1u;
        }
    }

    let ordered: array<String>;
    let j = 0;
    let count = ArraySize(entry.parts);
    while j < count {
        if ArrayContains(requested, entry.parts[j]) {
            ArrayPush(ordered, entry.parts[j]);
        }
        j += 1;
    }

    if ArraySize(ordered) == 0 {
        return AiNpcRecipeDropped(entry, conversation, where, issues);
    }
    return ordered;
}

// Dropping a block, or being told why it cannot be dropped. The schema answers, so the two
// required blocks are stated once in the table instead of as a branch here and a sentence in
// the documentation.
func AiNpcRecipeDropped(entry: ref<AiNpcRecipeBlockSchema>, conversation: Bool, where: String,
                        out issues: array<ref<AiNpcConfigIssue>>) -> array<String> {
    if entry.required && AiNpcRecipeBlockIsMessage(entry) {
        ArrayPush(issues, AiNpcConfigIssueOf("error", where,
            "this block cannot be removed: a request is two messages, and this one names one of them. It keeps its source."));
        return entry.parts;
    }
    if entry.required && conversation {
        ArrayPush(issues, AiNpcConfigIssueOf("error", where,
            "this block cannot be removed: it carries what the mod and the player decided, not what a character says. It keeps every part."));
        return entry.parts;
    }
    let empty: array<String>;
    return empty;
}

func AiNpcRecipeBlockOfParts(entry: ref<AiNpcRecipeBlockSchema>, parts: array<String>) -> ref<AiNpcRecipeBlock> {
    return AiNpcRecipeBlockOf(entry.key, parts);
}

/// Reporting ///

// Same convention as every other file the mod reads: a leading underscore is a comment,
// because JSON has none and the shipped template annotates itself with them.
func AiNpcRecipeReportUnknown(owner: ref<JsonObject>, allowed: array<String>, where: String,
                              prefix: String, out issues: array<ref<AiNpcConfigIssue>>) -> Void {
    if !IsDefined(owner) {
        return;
    }
    let keys = owner.GetKeys();
    let i = 0;
    let count = ArraySize(keys);
    while i < count {
        if !StrBeginsWith(keys[i], "_") && !ArrayContains(allowed, keys[i]) {
            ArrayPush(issues, AiNpcConfigIssueOf("warning", where,
                s"unknown key \"\(prefix)\(keys[i])\" is ignored. Known: \(AiNpcRecipeJoinNames(allowed))."));
        }
        i += 1;
    }
}
