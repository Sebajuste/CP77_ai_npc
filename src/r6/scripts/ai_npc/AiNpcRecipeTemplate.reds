// The recipes template, which is also the mod's own default.
//
// ONE COPY, and this is it. The text below is written to recipes.example.json every launch as
// documentation, AND parsed by AiNpcRecipeParse to produce the recipe the mod renders with
// when no recipes.json is on disk. A template that documented a default kept somewhere else
// would be free to disagree with it; this one cannot, and the parser is exercised on every
// launch by the mod's own file rather than only by a player's.
//
// It is a difference from nothing: every key states what the built-in schema already says, so
// what a reader sees is the whole vocabulary rather than the subset somebody chose to write
// out. A player copies it to recipes.json and deletes the lines they do not want to change.
//
// ASCII only, and the encoding rule of this repo applies with force: this string becomes a
// file on the player's disk.

module AiNpc

func AiNpcRecipeTemplateFile() -> String {
    return "recipes.example.json";
}

func AiNpcRecipeFile() -> String {
    return "recipes.json";
}

func AiNpcRecipeTemplate() -> String {
    return "{\n" +
        "    \"_doc\": \"What the system prompt renders, block by block. Copy this file to recipes.json to use it; this one is rewritten every launch and never read. Keys starting with _ are comments.\",\n" +
        "    \"_order\": \"The ORDER of the blocks is not in this file. The mod renders them in one fixed sequence, ranked by how often each one changes, because an OpenAI-compatible backend stops discounting a repeated prompt at the first thing that moves. This file says WHAT is rendered, never WHERE.\",\n" +
        "    \"_absent\": \"A key you leave out keeps the mod's own answer -- it does NOT remove the block. That is what lets a block added by a later version reach a file written today. Removing a block is explicit: false, \\\"none\\\", or an empty list.\",\n" +
        "    \"_values\": \"Four shapes: \\\"full\\\" (every part), a list of parts, false or \\\"none\\\" (not rendered), or an object with \\\"parts\\\"/\\\"level\\\" and the block's own options.\",\n" +
        "    \"version\": 1,\n" +
        "    \"_active\": \"Which recipe below the mod renders with.\",\n" +
        "    \"active\": \"default\",\n" +
        "    \"recipes\": {\n" +
        "        \"_default\": \"The mod's own, written out in full. Every value here is what you get by omitting the key.\",\n" +
        "        \"default\": {\n" +
        "            \"_system\": \"<system>: the fiction, and the rules that describe the chat itself. Cannot be removed -- FORM, TIME and LENGTH live here.\",\n" +
        "            \"system\": \"full\",\n" +
        "            \"_explicitness\": \"<explicitness>: what YOU allowed in the Mod Settings menu, stated once at the top and restated last. Cannot be removed: it answers a question that was put to you, not to a character and not to this file.\",\n" +
        "            \"explicitness\": \"full\",\n" +
        "            \"_character\": \"<character>: who this character is. bio is the description, speech is how they talk, additions is what another installed mod appended. [\\\"bio\\\"] alone is the character without a register.\",\n" +
        "            \"character\": [\"bio\", \"speech\", \"additions\"],\n" +
        "            \"_target\": \"<target>: who the character is writing TO. source names them; \\\"player\\\" is V, and it is the only source this version implements.\",\n" +
        "            \"target\": { \"level\": \"full\", \"source\": \"player\" },\n" +
        "            \"_relationship\": \"<relationship>: how this character sees V.\",\n" +
        "            \"relationship\": \"full\",\n" +
        "            \"_world\": \"Three tags, one key: <interactions> what they can do to reach V, <world_background> Night City, <mechanics> how the world works.\",\n" +
        "            \"world\": [\"interactions\", \"background\", \"mechanics\"],\n" +
        "            \"_commands\": \"<commands>: the commands this character may write. false removes the block AND the pass that repairs a malformed one -- with no vocabulary in the prompt, a bracket in a reply is prose.\",\n" +
        "            \"commands\": true,\n" +
        "            \"_memory\": \"<memory>: what they remember of earlier conversations. [\\\"facts\\\"] keeps the consolidated facts and drops the story, the open loops and the agreements.\",\n" +
        "            \"memory\": [\"chronicle\", \"facts\", \"open\", \"agreed\", \"tone\"],\n" +
        "            \"_intent\": \"<intent>: what they want of V. own is theirs, extensions is what other installed mods want of V through them.\",\n" +
        "            \"intent\": [\"own\", \"extensions\"],\n" +
        "            \"_quest\": \"<quest>: the quest you are tracking. name is its title, context what this character says about it, objective what you are doing right now.\",\n" +
        "            \"quest\": [\"name\", \"context\", \"objective\"],\n" +
        "            \"_now\": \"<now>: the only block that changes every message. clock is the time, weather the sky, pending what another mod seeded, live the character's own current state.\",\n" +
        "            \"now\": [\"clock\", \"weather\", \"pending\", \"live\"]\n" +
        "        },\n" +
        "        \"_compact\": \"An example of the shape you actually write: only what differs. Set active to \\\"compact\\\" to render this one.\",\n" +
        "        \"compact\": {\n" +
        "            \"character\": [\"bio\"],\n" +
        "            \"memory\": [\"facts\"],\n" +
        "            \"quest\": [\"name\", \"context\"],\n" +
        "            \"commands\": false\n" +
        "        }\n" +
        "    }\n" +
        "}\n";
}
