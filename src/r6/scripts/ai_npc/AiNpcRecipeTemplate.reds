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
        "    \"_absent\": \"A key you leave out keeps the mod's own answer -- it does NOT remove the block. That is what lets a block added by a later version reach a file written today. Removing a block is explicit, and null is one of the ways to say it: null, false, \\\"none\\\", or an empty list all remove it.\",\n" +
        "    \"_messages\": \"A request is two messages, and the last two keys of a recipe name who writes each one: instruction is everything above, ask is the turn handed to the character. A recipe that names neither is a conversation recipe, and every pass keeps its own builder -- which is what the mod does out of the box. You only write them to say which pass a recipe was written for, so that binding it to another one in settings.json is refused instead of silently rendering nothing.\",\n" +
        "    \"_values\": \"Five shapes: \\\"full\\\" (every part), a list of parts, null or false or \\\"none\\\" (not rendered), an object with \\\"parts\\\"/\\\"level\\\" and the block's own options, and nothing at all -- an absent key keeps the mod's answer.\",\n" +
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
        "            \"_interactions\": \"<interactions>: how this character may act. reach is the conduct rubric -- what to write when a command applies and what to write when none does -- and source is which wording it takes: conversation carries <actions>, dedicated is the same chat with the commands moved to their own request, commands is that request. real and promises state what is true rather than what to write.\",\n" +
        "            \"interactions\": { \"parts\": [\"reach\", \"real\", \"promises\"], \"source\": \"conversation\" },\n" +
        "            \"_world\": \"<world_background>: Night City, and how a local reacts to it.\",\n" +
        "            \"world\": [\"background\"],\n" +
        "            \"_actions\": \"<actions>: the commands this character may write. false removes the block AND the pass that repairs a malformed one -- with no vocabulary in the prompt, a bracket in a reply is prose.\",\n" +
        "            \"actions\": true,\n" +
        "            \"_memory\": \"<memory>: what they remember of earlier conversations. [\\\"facts\\\"] keeps the consolidated facts and drops the story, the open loops and the agreements.\",\n" +
        "            \"memory\": [\"chronicle\", \"facts\", \"open\", \"agreed\", \"tone\"],\n" +
        "            \"_intent\": \"<intent>: what they want of V. own is theirs, extensions is what other installed mods want of V through them.\",\n" +
        "            \"intent\": [\"own\", \"extensions\"],\n" +
        "            \"_quest\": \"<quest>: the quest you are tracking. name is its title, context what this character says about it, objective what you are doing right now.\",\n" +
        "            \"quest\": [\"name\", \"context\", \"objective\"],\n" +
        "            \"_now\": \"<now>: the only block that changes every message. clock is the time, weather the sky, pending what another mod seeded, live the character's own current state.\",\n" +
        "            \"now\": [\"clock\", \"weather\", \"pending\", \"live\"],\n" +
        "            \"_instruction\": \"The first message: every block above. source is the pass that builds it -- conversation, memory, commands or test. Cannot be removed.\",\n" +
        "            \"instruction\": { \"source\": \"conversation\" },\n" +
        "            \"_ask\": \"The second message: the transcript, ending on the turn handed to the character. source is conversation, memory, repair or test. Cannot be removed.\",\n" +
        "            \"ask\": { \"source\": \"conversation\" }\n" +
        "        },\n" +
        "        \"_compact\": \"An example of the shape you actually write: only what differs. Set active to \\\"compact\\\" to render this one.\",\n" +
        "        \"compact\": {\n" +
        "            \"character\": [\"bio\"],\n" +
        "            \"memory\": [\"facts\"],\n" +
        "            \"quest\": [\"name\", \"context\"],\n" +
        "            \"actions\": false\n" +
        "        },\n" +
        "        \"_dedicated\": \"The conversation recipe Mod Settings > Command Handling binds when you pick Dedicated. It differs from default by two lines: no <actions> block, and a REACH rubric that does not point at one. The commands are chosen afterwards, by the actions recipe below.\",\n" +
        "        \"dedicated\": {\n" +
        "            \"interactions\": { \"parts\": [\"reach\", \"real\", \"promises\"], \"source\": \"dedicated\" },\n" +
        "            \"actions\": false\n" +
        "        },\n" +
        "        \"_perpass\": \"The mod ships one recipe per pass, and a preset binds them by name in settings.json. The three below remove nothing: their pass builds both its messages itself, and the recipe only says which pass it belongs to.\",\n" +
        "        \"_compaction\": \"A recipe for another pass. It removes nothing: the compaction builds both its messages itself, and this only says which pass it belongs to. Bind it with \\\"passes\\\": { \\\"thinking\\\": { \\\"recipe\\\": \\\"compaction\\\" } } in settings.json.\",\n" +
        "        \"compaction\": {\n" +
        "            \"instruction\": { \"source\": \"memory\" },\n" +
        "            \"ask\": { \"source\": \"memory\" }\n" +
        "        },\n" +
        "        \"_repair\": \"The second request the mod makes when a character writes a command with a wrong bracket: the command list, and the broken tag. Bound by passes.repair.\",\n" +
        "        \"repair\": {\n" +
        "            \"interactions\": { \"parts\": [\"reach\"], \"source\": \"commands\" },\n" +
        "            \"instruction\": { \"source\": \"actions\" },\n" +
        "            \"ask\": { \"source\": \"repair\" }\n" +
        "        },\n" +
        "        \"_actions\": \"The action selection, when Mod Settings > Command Handling is set to Dedicated: the command list, the last few messages and the reply that was just written. It carries no bio, no world and no tier -- none of them decides whether money changed hands. Bound by passes.actions.\",\n" +
        "        \"actions\": {\n" +
        "            \"interactions\": { \"parts\": [\"reach\"], \"source\": \"commands\" },\n" +
        "            \"instruction\": { \"source\": \"actions\" },\n" +
        "            \"ask\": { \"source\": \"selector\" }\n" +
        "        },\n" +
        "        \"_test\": \"The connection check: two sentences, sent on the slot the reply is written on. Bound by passes.test.\",\n" +
        "        \"test\": {\n" +
        "            \"instruction\": { \"source\": \"test\" },\n" +
        "            \"ask\": { \"source\": \"test\" }\n" +
        "        }\n" +
        "    }\n" +
        "}\n";
}
