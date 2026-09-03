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
// Three blocks are required, and the schema is where that is stated rather than in a branch of
// the parser:
//
//   <system>        carries the <fiction> sentence and the locked FORM / TIME / LENGTH rubrics
//   <explicitness>  states what the PLAYER consented to in Mod Settings
//   <channel>       states which surface the reply lands on, and what that surface accepts
//
// The third is the newest and the least obvious. A recipe that dropped <channel> would leave a
// character believing it is texting during a call -- and the rules it carries are not editorial
// either: a numeral glued to its unit derails the speech engine, measured, and no prompt above
// it says so. It is dropped for the same reason <system> is: what it carries is not a
// character's to trim.
//
// The second is the one worth spelling out. It already refuses every contribution lane -- no
// contact override, no prompts.json level, no extension -- because it answers a question that
// was put to the player. A recipe is not a better position from which to answer it.
//
// Both are required OF A CONVERSATION RECIPE, which is what a recipe is until it says
// otherwise. The two blocks at the end of the table -- <instruction> and <ask> -- name the
// builders of the two messages a request is made of, and a recipe whose instruction comes
// from another pass carries neither a <system> block nor an explicitness tier to state. It
// may then drop them. AiNpcRecipeParse reads that source before the loop below, for that
// reason and no other.

module AiNpc

class AiNpcRecipeBlockSchema {
    let key: String;
    let parts: array<String>;
    // Whether a recipe may drop it. A required block accepts "full" and refuses everything
    // else by name -- unless the recipe has said it describes another pass's message, which
    // is the whole of the exemption. See AiNpcRecipeDescribesConversation.
    let required: Bool;
    // The sources this block may name, or empty when it takes none. Per block, because the
    // two message blocks and <target> answer different questions and share no vocabulary.
    let sources: array<String>;
}

func AiNpcRecipeIsSourced(entry: ref<AiNpcRecipeBlockSchema>) -> Bool {
    if !IsDefined(entry) {
        return false;
    }
    return ArraySize(entry.sources) > 0;
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
    ArrayPush(schema, AiNpcRecipeSourced("target", AiNpcTargetSources()));
    ArrayPush(schema, AiNpcRecipeWhole("relationship"));
    // Three tags, one key. They answer one question between them -- what the world is and what
    // may be done in it -- and a player trimming the prompt trims them together.
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("world", ["interactions", "background", "mechanics"]));
    ArrayPush(schema, AiNpcRecipeWhole("commands"));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("memory", ["chronicle", "facts", "open", "agreed", "tone"]));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("intent", ["own", "extensions"]));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("quest", ["name", "context", "objective"]));
    ArrayPush(schema, AiNpcRecipeBlockSchemaOf("now", ["clock", "weather", "pending", "live"]));
    ArrayPush(schema, AiNpcRecipeRequired("channel"));

    // Last, and outside the order above, because they render nothing: a request is two
    // messages, and these two say which builder writes each half. The eleven blocks above are
    // the instruction's own, and only while its source is "conversation".
    ArrayPush(schema, AiNpcRecipeMessage("instruction", AiNpcPassInstructionSources()));
    ArrayPush(schema, AiNpcRecipeMessage("ask", AiNpcPassAskSources()));

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

func AiNpcRecipeSourced(key: String, sources: array<String>) -> ref<AiNpcRecipeBlockSchema> {
    let entry = AiNpcRecipeWhole(key);
    entry.sources = sources;
    return entry;
}

// A message: sourced, and not removable. A request has two halves whatever a file says, so
// there is nothing for "none" to mean here.
func AiNpcRecipeMessage(key: String, sources: array<String>) -> ref<AiNpcRecipeBlockSchema> {
    let entry = AiNpcRecipeSourced(key, sources);
    entry.required = true;
    return entry;
}

// The two blocks that describe a message rather than a piece of one. They are required in
// every recipe, whatever pass it is for, because a request always has two halves.
func AiNpcRecipeBlockIsMessage(entry: ref<AiNpcRecipeBlockSchema>) -> Bool {
    if !IsDefined(entry) {
        return false;
    }
    return Equals(entry.key, "instruction") || Equals(entry.key, "ask");
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

// La recette d'une replique dite a voix haute, sans fichier.
//
// Elle ne retire qu'une chose a la recette integrale : les commandes. Une reponse parlee ne
// porte pas de tag entre crochets -- personne ne prononce ca -- et laisser le bloc ferait aussi
// tourner la passe de reparation qui va le chercher derriere chaque replique.
//
// INTEGREE PLUTOT QUE DANS L'EXEMPLE. `recipes.example.json` la decrit depuis le debut, mais un
// exemple n'est pas charge : sans `recipes.json`, le livre est vide et chaque passe retombait
// sur la recette integrale. Une recette livree, correcte, et jamais montee -- mesure en jeu le
// 2026-09-02. Ce que le fichier apporte reste le reglage ; ce qui est ici est le defaut.
func AiNpcRecipeSpoken() -> ref<AiNpcRecipe> {
    let recipe = new AiNpcRecipe();
    recipe.name = "spoken";

    let schema = AiNpcRecipeSchema();
    let i = 0;
    let count = ArraySize(schema);
    while i < count {
        if NotEquals(schema[i].key, "commands") {
            ArrayPush(recipe.blocks, AiNpcRecipeBlockOf(schema[i].key, schema[i].parts));
        }
        i += 1;
    }
    return recipe;
}

// Les recettes que le mod porte lui-meme, par nom. Null pour tout le reste : un nom inconnu ici
// est un nom que seul un fichier peut fournir.
func AiNpcRecipeBuiltInNamed(name: String) -> ref<AiNpcRecipe> {
    if Equals(name, "spoken") {
        return AiNpcRecipeSpoken();
    }
    return null;
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
