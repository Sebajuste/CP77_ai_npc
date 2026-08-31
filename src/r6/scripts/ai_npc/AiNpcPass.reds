// A pass: one kind of request, with the slot it is sent on and the recipe it is described by.
//
// A pass is a lane of AiNpcRequestLog.reds, by name -- nothing is invented and nothing is
// renamed, so the daily usage report already totals per pass.
//
// WHAT A PASS DECIDES AND WHAT A RECIPE DECIDES ARE NOT THE SAME THING. A pass names the two
// builders: the instruction it sends and the ask it ends on. A recipe describes the
// conversation instruction, block by block, and nothing else -- bound to `thinking`, a recipe
// saying `character: ["bio"]` would render nothing at all. So the sources below are the
// pass's, and a recipe that declares one is not choosing a builder: it is saying which pass it
// was written for, so that binding it to another is refused here rather than discovered as a
// prompt nobody recognises.
//
// Pure over a JsonObject and a recipe book: the whole table is assertable without a session.

module AiNpc

import RedData.Json.*

/// The vocabulary ///

// Every pass this version implements. A name outside this list is reported and ignored, which
// is what lets a table be written ahead of the code.
//
// `actions` is bound like the other four and sends nothing until the player asks for it: it is
// the one pass a setting can switch off entirely (Mod Settings > Command Handling).
func AiNpcPassNames() -> array<String> {
    return [AiNpcLaneSpeaking(), AiNpcLaneThinking(), AiNpcLaneRepair(), AiNpcLaneTest(),
        AiNpcLaneActions()];
}

// The builder of the first message, named after the lane that already writes it.
//
// `conversation` is one source and not two, although the speaking lane has two askmakers:
// AiNpcBuildTranscript and AiNpcBuildUnpromptedTranscript are chosen by SpeaksFirst() at the
// moment of sending, and a file that could name one of them would be a file that switches off
// the character writing first.
func AiNpcPassInstructionSource(pass: String) -> String {
    if Equals(pass, AiNpcLaneSpeaking()) {
        return "conversation";
    }
    if Equals(pass, AiNpcLaneThinking()) {
        return "memory";
    }
    if Equals(pass, AiNpcLaneRepair()) {
        return "commands";
    }
    if Equals(pass, AiNpcLaneTest()) {
        return "test";
    }
    // The same table the repair is sent, and for the same reason: it is the whole of what the
    // mod will honour, so what a model is shown and what may fire are one object.
    if Equals(pass, AiNpcLaneActions()) {
        return "commands";
    }
    return "";
}

func AiNpcPassAskSource(pass: String) -> String {
    if Equals(pass, AiNpcLaneSpeaking()) {
        return "conversation";
    }
    if Equals(pass, AiNpcLaneThinking()) {
        return "memory";
    }
    if Equals(pass, AiNpcLaneRepair()) {
        return "repair";
    }
    if Equals(pass, AiNpcLaneTest()) {
        return "test";
    }
    // The thread plus the reply just written, ending on a question rather than on the handover:
    // this pass reads what was written instead of continuing it.
    if Equals(pass, AiNpcLaneActions()) {
        return "selector";
    }
    return "";
}

// What a recipe may name, which is what the passes render. Derived rather than written out:
// a fifth pass brings its own sources with it, and the schema learns them without an edit.
func AiNpcPassInstructionSources() -> array<String> {
    let sources: array<String>;
    let names = AiNpcPassNames();
    let i = 0;
    let count = ArraySize(names);
    while i < count {
        let source = AiNpcPassInstructionSource(names[i]);
        if NotEquals(StrLen(source), 0) && !ArrayContains(sources, source) {
            ArrayPush(sources, source);
        }
        i += 1;
    }
    return sources;
}

func AiNpcPassAskSources() -> array<String> {
    let sources: array<String>;
    let names = AiNpcPassNames();
    let i = 0;
    let count = ArraySize(names);
    while i < count {
        let source = AiNpcPassAskSource(names[i]);
        if NotEquals(StrLen(source), 0) && !ArrayContains(sources, source) {
            ArrayPush(sources, source);
        }
        i += 1;
    }
    return sources;
}

// The recipe the shipped template writes for each pass, and the name a preset binds. Checked
// against the template by tools\lint.ps1: a name that no recipe declares is a binding that
// points at nothing.
func AiNpcPassRecipeName(pass: String) -> String {
    if Equals(pass, AiNpcLaneSpeaking()) {
        return "default";
    }
    if Equals(pass, AiNpcLaneThinking()) {
        return "compaction";
    }
    if Equals(pass, AiNpcLaneRepair()) {
        return "repair";
    }
    if Equals(pass, AiNpcLaneTest()) {
        return "test";
    }
    if Equals(pass, AiNpcLaneActions()) {
        return "actions";
    }
    return "";
}

/// The table ///

// An empty slot name means the dialogue slot, an empty recipe name means the active recipe.
// Both are what an absent `passes` block gives every pass, which is today's behaviour.
class AiNpcPassBinding {
    let name: String;
    let slotName: String;
    let recipeName: String;
}

// Both names empty: "nothing was written" is not the same answer as "the dialogue slot", and
// the test pass is what needs the difference. See AiNpcPassSlotNameIn.
func AiNpcPassBindingOf(name: String) -> ref<AiNpcPassBinding> {
    let binding = new AiNpcPassBinding();
    binding.name = name;
    return binding;
}

// The slot a pass is sent on. The test pass follows the SPEAKING pass when it says nothing of
// its own: a connection test run against another slot declares the installation healthy on a
// model the player never sees, which is the one thing a diagnostic must not do.
func AiNpcPassSlotNameIn(bindings: array<ref<AiNpcPassBinding>>, pass: String) -> String {
    let named = AiNpcPassBindingNamed(bindings, pass).slotName;
    if NotEquals(StrLen(named), 0) {
        return named;
    }
    if Equals(pass, AiNpcLaneTest()) {
        let speaking = AiNpcPassBindingNamed(bindings, AiNpcLaneSpeaking()).slotName;
        if NotEquals(StrLen(speaking), 0) {
            return speaking;
        }
    }
    return AiNpcSlotDefaultName();
}

func AiNpcPassBindingNamed(bindings: array<ref<AiNpcPassBinding>>, name: String) -> ref<AiNpcPassBinding> {
    let i = 0;
    let count = ArraySize(bindings);
    while i < count {
        if Equals(bindings[i].name, name) {
            return bindings[i];
        }
        i += 1;
    }
    return AiNpcPassBindingOf(name);
}

// Both keys cross a file boundary: a slot into `slots`, a recipe into recipes.json. Pointing
// at nothing is named on the spot -- the symptom otherwise is a request that goes out on the
// wrong model, which nothing downstream can distinguish from the file not being read.
func AiNpcPassTableFromJson(passes: ref<JsonObject>, fileName: String, slots: ref<JsonObject>,
                            book: ref<AiNpcRecipeBook>,
                            out issues: array<ref<AiNpcConfigIssue>>) -> array<ref<AiNpcPassBinding>> {
    let bindings: array<ref<AiNpcPassBinding>>;
    if !IsDefined(passes) {
        return bindings;
    }

    let known = AiNpcPassNames();
    let keys = passes.GetKeys();
    let i = 0;
    let count = ArraySize(keys);
    while i < count {
        let name = keys[i];
        if !StrBeginsWith(name, "_") {
            if !ArrayContains(known, name) {
                ArrayPush(issues, AiNpcConfigIssueOf("warning", fileName,
                    s"passes.\(name) is not a pass this version makes; it is ignored. Known: \(AiNpcRecipeJoinNames(known))."));
            } else {
                let body = AiNpcJsonObjectAt(passes, name);
                if !IsDefined(body) {
                    ArrayPush(issues, AiNpcConfigIssueOf("error", fileName,
                        s"passes.\(name) is not an object; it is ignored."));
                } else {
                    ArrayPush(bindings, AiNpcPassBindingFromJson(body, name, fileName, slots, book, issues));
                }
            }
        }
        i += 1;
    }
    return bindings;
}

func AiNpcPassBindingFromJson(body: ref<JsonObject>, name: String, fileName: String,
                              slots: ref<JsonObject>, book: ref<AiNpcRecipeBook>,
                              out issues: array<ref<AiNpcConfigIssue>>) -> ref<AiNpcPassBinding> {
    let binding = AiNpcPassBindingOf(name);
    let where = s"\(fileName): passes.\(name)";
    AiNpcRecipeReportUnknown(body, ["slot", "recipe"], where, "", issues);

    let slotName = AiNpcJsonString(body, "slot");
    if NotEquals(StrLen(slotName), 0) {
        if AiNpcSlotDeclared(slots, slotName) || Equals(slotName, AiNpcSlotDefaultName()) {
            binding.slotName = slotName;
        } else {
            ArrayPush(issues, AiNpcConfigIssueOf("error", where,
                s"slot \"\(slotName)\" is not declared in \"slots\"; the \(AiNpcSlotDefaultName()) slot is used."));
        }
    }

    let recipeName = AiNpcJsonString(body, "recipe");
    if NotEquals(StrLen(recipeName), 0) {
        if AiNpcRecipeBookHas(book, recipeName) {
            binding.recipeName = recipeName;
            AiNpcPassReportSources(name, AiNpcRecipeBookNamed(book, recipeName), where, issues);
        } else {
            ArrayPush(issues, AiNpcConfigIssueOf("error", where,
                s"recipe \"\(recipeName)\" is declared by no recipe in \(AiNpcRecipeFile()); the active recipe is used."));
        }
    }
    return binding;
}

// A recipe says which pass it was written for; this is where the two are put side by side.
// Reported and then ignored: the pass keeps its own builder, because a recipe cannot make one
// lane render another lane's message.
func AiNpcPassReportSources(pass: String, recipe: ref<AiNpcRecipe>, where: String,
                            out issues: array<ref<AiNpcConfigIssue>>) -> Void {
    AiNpcPassReportOneSource(AiNpcRecipeSourceOf(recipe, "instruction"),
        AiNpcPassInstructionSource(pass), pass, "instruction", where, issues);
    AiNpcPassReportOneSource(AiNpcRecipeSourceOf(recipe, "ask"),
        AiNpcPassAskSource(pass), pass, "ask", where, issues);
}

func AiNpcPassReportOneSource(declared: String, rendered: String, pass: String, block: String,
                              where: String, out issues: array<ref<AiNpcConfigIssue>>) -> Void {
    if Equals(StrLen(declared), 0) || Equals(declared, rendered) {
        return;
    }
    ArrayPush(issues, AiNpcConfigIssueOf("error", where,
        s"this recipe declares \(block) source \"\(declared)\", and the \(pass) pass renders \"\(rendered)\". The pass keeps its own."));
}
