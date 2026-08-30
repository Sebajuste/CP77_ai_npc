// The vocabulary a recipe may use: which blocks exist, which parts each one has, and which
// of them may not be dropped. One table, read by three halves that would otherwise drift --
// the parser refusing an unknown word, the renderers asking for a part, and the example file
// that documents the whole thing.
//
// The order of this table IS the order of the prompt, and AiNpcBuildSystemPromptWith walks the
// same sequence by hand. Nothing compares the two orders -- a block moved here and not there
// costs a reader their bearings, not a player their prompt, and the order that runs is the
// builder's. What tools\lint.ps1 does check is the vocabulary: every block and part a renderer
// asks for is declared below, every droppable block is asked about by somebody, and the shipped
// template names them all.
//
// Two blocks are required, and the schema is where that is stated rather than in a branch of
// the parser:
//
//   <system>        carries the <fiction> sentence and the locked FORM / TIME / LENGTH rubrics
//   <explicitness>  states what the PLAYER consented to in Mod Settings
//
// The second is the one worth spelling out. It already refuses every contribution lane -- no
// contact override, no prompts.json level, no extension -- because it answers a question that
// was put to the player. A recipe is not a better position from which to answer it.

module AiNpc

class AiNpcRecipeBlockSchema {
    let key: String;
    let parts: array<String>;
    // Whether a recipe may drop it. A required block accepts "full" and refuses everything
    // else by name.
    let required: Bool;
    // Whether the block takes a "source". One block does; a second one would be a reason to
    // generalise this, not a reason to have generalised it already.
    let sourced: Bool;
}

// Every block, in prompt order.
func AiNpcRecipeSchema() -> array<ref<AiNpcRecipeBlockSchema>> {
    let schema: array<ref<AiNpcRecipeBlockSchema>>;

    ArrayPush(schema, AiNpcRecipeRequired("system"));
    ArrayPush(schema, AiNpcRecipeRequired("explicitness"));
    // `additions` is what another mod appended to the bio -- see AiNpcCharacterAdditionsText.
    // `speech` moved here from the SPEECH rubric of <system_rules> so that "the character,
    // without how they talk" is one part list rather than two keys held in agreement.
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("character", ["bio", "speech", "additions"]));
    ArrayPush(schema, AiNpcRecipeSourced("target"));
    ArrayPush(schema, AiNpcRecipeWhole("relationship"));
    // Three tags, one key. They answer one question between them -- what the world is and what
    // may be done in it -- and a player trimming the prompt trims them together.
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("world", ["interactions", "background", "mechanics"]));
    ArrayPush(schema, AiNpcRecipeWhole("commands"));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("memory", ["chronicle", "facts", "open", "agreed", "tone"]));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("intent", ["own", "extensions"]));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("quest", ["name", "context", "objective"]));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("now", ["clock", "weather", "pending", "live"]));

    return schema;
}

// A block with nothing to divide is still a block with a part, and the part is named rather
// than left implicit: "full" then means the same thing everywhere -- every part in the
// schema -- instead of meaning "true" here and "the list" next door.
func AiNpcRecipePartAll() -> String {
    return "all";
}

func AiNpcRecipeBlockSchemaOf(key: String, parts: array<String>) -> ref<AiNpcRecipeBlockSchema> {
    let entry = new AiNpcRecipeBlockSchema();
    entry.key = key;
    entry.parts = parts;
    return entry;
}

// A block with nothing to divide: one part, named by the schema rather than by the file, so
// "full" and a bare `true` mean the same thing here as everywhere else.
func AiNpcRecipeWhole(key: String) -> ref<AiNpcRecipeBlockSchema> {
    return AiNpcRecipeBlockSchemaOf(key, [AiNpcRecipePartAll()]);
}

func AiNpcRecipeRequired(key: String) -> ref<AiNpcRecipeBlockSchema> {
    let entry = AiNpcRecipeWhole(key);
    entry.required = true;
    return entry;
}

func AiNpcRecipeSourced(key: String) -> ref<AiNpcRecipeBlockSchema> {
    let entry = AiNpcRecipeWhole(key);
    entry.sourced = true;
    return entry;
}

func AiNpcRecipeSchemaOf(key: String) -> ref<AiNpcRecipeBlockSchema> {
    let schema = AiNpcRecipeSchema();
    let i = 0;
    let count = ArraySize(schema);
    while i < count {
        if Equals(schema[i].key, key) {
            return schema[i];
        }
        i += 1;
    }
    return null;
}

// Every block at every part: the recipe a file is a difference from, and the one the mod
// renders when nothing on disk says otherwise. Derived from the table rather than written
// out, so a block added above is rendered by default without a second edit.
func AiNpcRecipeFull() -> ref<AiNpcRecipe> {
    let recipe = new AiNpcRecipe();
    recipe.name = "full";

    let schema = AiNpcRecipeSchema();
    let i = 0;
    let count = ArraySize(schema);
    while i < count {
        ArrayPush(recipe.blocks, AiNpcRecipeBlockOf(schema[i].key, schema[i].parts));
        i += 1;
    }
    return recipe;
}

// The names a file may use, for the parser's "unknown key" line. The list is the schema's, so
// the message can never advertise a block the renderers do not know.
func AiNpcRecipeBlockNames() -> array<String> {
    let names: array<String>;
    let schema = AiNpcRecipeSchema();
    let i = 0;
    let count = ArraySize(schema);
    while i < count {
        ArrayPush(names, schema[i].key);
        i += 1;
    }
    return names;
}

func AiNpcRecipeJoinNames(names: array<String>) -> String {
    let out = "";
    let i = 0;
    let count = ArraySize(names);
    while i < count {
        if i > 0 {
            out += ", ";
        }
        out += names[i];
        i += 1;
    }
    return out;
}
