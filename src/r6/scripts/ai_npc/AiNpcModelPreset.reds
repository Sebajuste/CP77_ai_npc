// The three starting points: light, normal, premium.
//
// A preset is a block of JSON written into settings.json, in clear, and then owned by the
// player -- not a mode the mod runs in. Nothing re-applies one on its own, and editing a model
// under it is the expected thing to do. `modelPreset` records which one produced the block, the
// way installPreset records the installer's answer: a stamp, not an instruction.
//
// ONE MODEL EACH, and the passes nobody has measured stay on it. That is not a simplification
// -- see docs\PLAN_PRESETS.md: the numbers behind each model below are the speaking pass's,
// from docs\MODEL_BENCH.md, and there is no measurement at all for the compaction or the
// repair. A slot filled by guesswork would be worse than an absent one, because it would be
// invisible.
//
// What every preset DOES carry is a budget for its technical calls, and that is not the same
// kind of decision: which model answers is a judgement a bench makes, how much a call that
// nobody reads may spend is a bound. See "The output budget" below.

module AiNpc

import RedData.Json.*

class AiNpcModelPreset {
    let name: String;
    let model: String;
    // One line for the CET window, opening on the name: the overlay reads its buttons out of
    // this text rather than holding a second list. Same contract as DescribeProviders.
    let summary: String;
}

func AiNpcModelPresetKey() -> String {
    return "modelPreset";
}

func AiNpcModelPresets() -> array<ref<AiNpcModelPreset>> {
    let presets: array<ref<AiNpcModelPreset>>;

    ArrayPush(presets, AiNpcModelPresetOf("light", "google/gemma-4-31b-it:free",
        "free. One model for every pass, on purpose: the free tier is a shared pool, and spreading the work over several free models multiplies the walls rather than the throughput. Measured 0 mechanical defects over 34 replies and the action command 3/3 on the fixture -- and 46 requests out of 54 answered HTTP 429 on the evening it was measured. A way to try the mod, not a way to play an evening."));

    ArrayPush(presets, AiNpcModelPresetOf("normal", "qwen/qwen3-235b-a22b-2507",
        "about 1 $/month at two hours a day, and the cheapest that does the job: the appointment commands 18 times out of 20 on real recorded conversations, no mechanical defect over 54 replies, 2.7 s. What it does not do is hold the Normal explicitness tier -- 23 explicit replies out of 24 -- which is a prompt problem before it is a model one, and no preset fixes it."));

    ArrayPush(presets, AiNpcModelPresetOf("premium", "meta-llama/llama-4-maverick",
        "about 2.57 $/month, the best measured whatever it costs: 20 out of 20 on the same conversations, one control-token leak in 54 replies, 2.0 s, and the strictest tier adherence of anything measured. If a provider outage makes it unavailable, deepseek/deepseek-chat-v3-0324 matches it for 25 % more."));

    return presets;
}

func AiNpcModelPresetOf(name: String, model: String, summary: String) -> ref<AiNpcModelPreset> {
    let preset = new AiNpcModelPreset();
    preset.name = name;
    preset.model = model;
    preset.summary = summary;
    return preset;
}

func AiNpcModelPresetNamed(name: String) -> ref<AiNpcModelPreset> {
    let presets = AiNpcModelPresets();
    let i = 0;
    let count = ArraySize(presets);
    while i < count {
        if Equals(presets[i].name, name) {
            return presets[i];
        }
        i += 1;
    }
    return null;
}

func AiNpcModelPresetNames() -> array<String> {
    let names: array<String>;
    let presets = AiNpcModelPresets();
    let i = 0;
    let count = ArraySize(presets);
    while i < count {
        ArrayPush(names, presets[i].name);
        i += 1;
    }
    return names;
}

/// The output budget ///

// A CEILING, not an economy. The distinction is the whole of this section: a cap sized to save
// money cuts the last thing in a message, and the last thing in a message is the
// [ACTION:...] command -- a reply that reads perfectly and creates no appointment, which is the
// worst failure this mod can have. A cap sized above everything ever measured costs nothing and
// bounds a model that runs away.
//
// 4096, against 1976 -- the longest completion measured over 31 runs on two providers, every
// one of which finished on "stop". Twice that, and it has to be: reasoning tokens are billed
// against this same number, and the heaviest model measured spends 1250 of them on a draft
// nobody reads before writing a word of the answer (docs\MODEL_BENCH.md). A round number
// rather than a tight one, because the point of this ceiling is to bound a runaway, and
// anything close to the measurements would be an economy in disguise.
func AiNpcSlotDialogueMaxTokens() -> Int32 {
    return 4096;
}

// A technical call asks for one line and gets one line: the repair, and the action selection.
// They are the only passes whose output has a known shape, so the only ones that can carry a
// tight ceiling, and the only ones where being cut off costs nothing -- a repair that fails
// delivers the reply as it was written, and a selection that fails fires nothing.
//
// 500 for a line of about twenty tokens, AND THE DRAFT SWITCHED OFF ON THE SAME SLOT. The two
// go together and the second is what makes the first comfortable: measured, a selector with
// its reasoning off answers in three tokens, so 500 is fifteen times the room it needs. With
// the draft left on, the same 500 is not a bound but a guillotine -- see
// AiNpcSlotDisableReasoning for the numbers and for the one provider that refuses it.
func AiNpcSlotMechanicName() -> String {
    return "mechanic";
}

func AiNpcSlotMechanicMaxTokens() -> Int32 {
    return 500;
}

/// What it writes ///

// One MODEL, on the dialogue slot, and every pass on it. The second slot carries no model at
// all -- it inherits the first -- and exists for its ceiling alone: the numbers a bench has not
// spoken about are models, not budgets.
func AiNpcModelPresetSlots(preset: ref<AiNpcModelPreset>) -> ref<JsonObject> {
    let dialogue = new JsonObject();
    dialogue.SetKeyString("model", preset.model);
    AiNpcSlotSetMaxTokens(dialogue, AiNpcSlotDialogueMaxTokens());

    let mechanic = new JsonObject();
    AiNpcSlotSetMaxTokens(mechanic, AiNpcSlotMechanicMaxTokens());
    AiNpcSlotDisableReasoning(mechanic);

    let slots = new JsonObject();
    slots.SetKey(AiNpcSlotDefaultName(), dialogue);
    slots.SetKey(AiNpcSlotMechanicName(), mechanic);
    return slots;
}

// Every pass, each naming its slot and its own recipe -- so the file says which model and which
// prompt every kind of work uses instead of leaving all but one implicit.
//
// The recipe name is written ONLY when the loaded book declares it. A player who keeps their own
// recipes.json replaces the shipped book whole, and a preset naming a recipe they do not have
// would write a binding that points at nothing.
func AiNpcModelPresetPasses(book: ref<AiNpcRecipeBook>) -> ref<JsonObject> {
    let passes = new JsonObject();
    let names = AiNpcPassNames();
    let i = 0;
    let count = ArraySize(names);
    while i < count {
        let entry = new JsonObject();
        entry.SetKeyString("slot", AiNpcModelPresetSlotFor(names[i]));

        let recipe = AiNpcPassRecipeName(names[i]);
        if AiNpcRecipeBookHas(book, recipe) {
            entry.SetKeyString("recipe", recipe);
        }
        passes.SetKey(names[i], entry);
        i += 1;
    }
    return passes;
}

// Which slot each pass is sent on. Only the two technical calls move, and only for their
// ceiling: the model is the same one everywhere, because no bench has said anything about a
// second.
func AiNpcModelPresetSlotFor(pass: String) -> String {
    if Equals(pass, AiNpcLaneRepair()) || Equals(pass, AiNpcLaneActions()) {
        return AiNpcSlotMechanicName();
    }
    return AiNpcSlotDefaultName();
}

// The whole edit, as one object, so applying a preset is one write to settings.json rather than
// three that could half-happen.
func AiNpcModelPresetPatch(preset: ref<AiNpcModelPreset>, book: ref<AiNpcRecipeBook>) -> ref<JsonObject> {
    let patch = new JsonObject();
    patch.SetKeyString(AiNpcModelPresetKey(), preset.name);
    patch.SetKey("slots", AiNpcModelPresetSlots(preset));
    patch.SetKey("passes", AiNpcModelPresetPasses(book));
    return patch;
}

/// Where a model typed by hand goes ///

// The dialogue slot when there is one, the legacy setting otherwise -- the same order the
// resolution reads them in. Without this the Model box in the CET window would write a key that
// a slot then shadows, and report success over a model nobody sends.
func AiNpcModelPresetWritesToSlot() -> Bool {
    let slots = AiNpcGetSettingObject("slots");
    let dialogue = AiNpcSlotObjectAt(slots, AiNpcSlotDefaultName());
    return IsDefined(dialogue) && dialogue.HasKey("model");
}

func AiNpcModelPresetSetModel(storage: ref<AiNpcStorageService>, model: String) -> Bool {
    if !IsDefined(storage) {
        return false;
    }
    if !AiNpcModelPresetWritesToSlot() {
        return storage.SetSetting("openRouterModel", model);
    }

    let slots = AiNpcGetSettingObject("slots");
    let dialogue = AiNpcSlotObjectAt(slots, AiNpcSlotDefaultName());
    dialogue.SetKeyString("model", model);

    let patch = new JsonObject();
    patch.SetKey("slots", slots);
    return storage.SetSettings(patch);
}
