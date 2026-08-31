# Plan: the prompt recipe

The assembly of the system prompt becomes data. One file says, per block, what to render;
the code keeps the order.

## The problem

`AiNpcBuildSystemPrompt` decides three things at once: which blocks exist, in which order,
and how much of each one is rendered. The first two are the mod's business. The third is not,
and today nobody can ask for less: the bio is whatever the sheet wrote, the memory is every
section it holds, the command block is every command that can fire. A conversation that wants
a cheaper prompt has no way to say so.

## What a recipe is

A named set of answers to one question per block: **what do you render?**

```json
{
  "active": "default",
  "recipes": {
    "compact": {
      "character": ["bio"],
      "memory": ["facts"],
      "commands": false
    }
  }
}
```

Four value forms, and a block key accepts whichever ones its schema entry allows:

| form | meaning |
|---|---|
| `"full"` | every part of the block |
| `["a", "b"]` | those parts, in the block's own order |
| `"none"` / `false` / `[]` | the block is not rendered |
| `{ "level": ..., "source": ... }` | a part list plus the block's own options |

**An absent key is not an absent block.** It means "the built-in answer", so a block added to
the mod later reaches every recipe a player has already written. Removing a block is explicit.

## What it may not do

**The order is not in the file.** `AiNpcBuildSystemPrompt` walks its own canonical sequence and
asks the recipe about each block in turn. The sequence is ordered by volatility — invariant
corpus first, then memory, then what changes every message — because the prefix discount an
OpenAI-compatible backend gives stops at the first thing that moves. A recipe that could
reorder would be a recipe that can silently make every request cost full price.

**Two blocks are required.** `system` and `explicitness` accept `"full"` and nothing else,
and the schema refuses the rest by name.

- `<system>` carries the `<fiction>` sentence and the locked FORM / TIME / LENGTH rubrics.
- `<explicitness>` states what the *player* consented to in Mod Settings. It already has no
  contribution lane of any kind, for the same reason: it answers a question that was put to
  the player, not to a mod and not to a recipe.

The rest of a block's invariants are inside its renderer, not in the schema: the memory block's
header is emitted whenever any memory part is, because a memory block without it reads as more
instructions and the model answers them.

## The blocks

Canonical order, which is also the order of the rendered prompt.

| key | tag | parts | droppable |
|---|---|---|---|
| `system` | `<system>` | — | no |
| `explicitness` | `<explicitness>` (twice) | — | no |
| `character` | `<character>` | `bio`, `speech`, `additions` | yes |
| `target` | `<target>` | — (option: `source`) | yes |
| `relationship` | `<relationship>` | — | yes |
| `interactions` | `<interactions>` | `reach`, `real`, `promises`, plus a source | yes |
| `world` | `<world_background>` | `background` | yes |
| `actions` | `<actions>` | — | yes |
| `memory` | `<memory>` | `chronicle`, `facts`, `open`, `agreed`, `tone` | yes |
| `intent` | `<intent>` | `own`, `extensions` | yes |
| `quest` | `<quest>` | `name`, `context`, `objective` | yes |
| `now` | `<now>` | `clock`, `weather`, `pending`, `live` | yes |

`explicitness` appears twice in the prompt on purpose and has done since before this plan: the
permission near the top, the one prohibition that has to survive the transcript restated last.
One key governs both.

## The three changes to the prompt itself

**1. The speech style moves into `<character>`.** It is rendered today as the SPEECH rubric of
`<system_rules>`, which put a character's register in the block that describes the chat. Moving
it makes `["bio"]` mean exactly "the character, without how they talk" — one part list on one
block instead of two keys to keep in agreement.

Its three sources are unchanged: `GetSpeechStyle()`, the `speechStyle` override field,
`prompts.json`. What changes is the destination — and that SPEECH joins the locked keys of
`<system_rules>`, with a refusal that names the new lane. A contribution that vanished in
silence would be the worst of the three outcomes.

**2. `<player>` becomes `<target>`.** The block answers "who are you writing to", and the
answer is V today. `source` is the recipe option that names it, `"player"` is the only value
this pass implements, and an unknown source is a named error rather than an empty block.

This is a seam, not a feature: a target that is not V also needs the transcript's `"V: "`
grammar and the gendered template variables, which resolve against the player. Both stay as
they are.

**3. The command block and the repair pass are one decision.** `commands: false` removes
`<commands>` from the prompt, and `AiNpcActionVocabularyFor` — what the repair pass reads —
answers the same recipe. It already treats an empty vocabulary as "a bracket in this reply is
prose", so the short-circuit needs no branch of its own.

Dispatch is not affected. A command reproduced from earlier in the transcript is still one the
mod claimed, and `IsOffered` remains the authority on whether it may fire.

## Where it lives

```
recipes.json           read if present, in the storage root beside prompts.json
recipes.example.json   written every launch, never read: the live schema doc
```

The built-in default is **not** a second copy in code. It is the template text, parsed at load
by the same parser a player's file goes through, which is what makes the template incapable of
drifting from the default and exercises the parser on every launch.

## Steps

1. `docs/PLAN_PROMPT_RECIPE.md` — this file.
2. `AiNpcRecipe.reds` — the model, and the two questions a renderer asks it.
3. `AiNpcRecipeSchema.reds` — the block and part vocabulary, in one table.
4. `AiNpcRecipeTemplate.reds` — the template text, which is also the default.
5. `AiNpcRecipeParse.reds` — JSON to recipe, every refusal named.
6. `AiNpcConfig.reds` — load `recipes.json`, write the example, report.
7. `AiNpcCharacterRender.reds` — `<character>` from its parts.
8. `AiNpcTargetRender.reds` — `<target>`, by source.
9. `AiNpcMemory.reds` — `AiNpcMemoryRenderParts`.
10. `AiNpcPromptSections.reds` / `AiNpcRules.reds` — SPEECH leaves the rule block and is locked.
11. `AiNpcActionPrompt.reds` — the vocabulary answers the recipe.
12. `AiNpcPromptBuild.reds` — the walk.
13. `tests/AiNpcTestRecipe.reds` — the parser, the schema, the renderers, the default.
14. `tools/prompt` — the offline builder, reconnected onto the new assembly.
15. `tools/lint.ps1` — one vocabulary: schema, renderers and template.
16. `README.md`, `docs/ARCHITECTURE.md` — the file map and the doc index.

## What this does not change

No prompt text is rewritten. The default recipe renders every block at every part, so the
information in the prompt is what it was — the `<character>` block gains the speech style the
rule block loses, and `<player>` is spelled `<target>`.
