// What a prompt renders, block by block. The model only -- no file, no JSON, no session --
// so a renderer can be asserted against a recipe built in three lines.
//
// A recipe answers two questions and nothing else: is this block rendered, and which of its
// parts. It does NOT carry the order: AiNpcPromptBuild walks its own canonical sequence and
// asks about each block in turn. Order is ranked by volatility, and the prefix discount an
// OpenAI-compatible backend gives stops at the first thing that moves -- a recipe that could
// reorder would be one that silently makes every request cost full price.
//
// Null reads as "render everything". That is the same convention the rest of the config
// follows: an absent opinion is not an opinion to render less.

module AiNpc

class AiNpcRecipeBlock {
    let key: String;
    // Which parts, in the block's own order. A present block with no part is not a block:
    // an empty list is how a recipe says "drop it".
    let parts: array<String>;
    // The block's own option, for the one block that has one. See AiNpcTargetRender.
    let source: String;
}

class AiNpcRecipe {
    let name: String;
    let blocks: array<ref<AiNpcRecipeBlock>>;
}

/// What a renderer asks ///

// Whether this block is rendered at all. A key the recipe never mentions is rendered: a
// block added to the mod after a player wrote their file reaches them, rather than
// disappearing from a recipe that has never heard of it.
func AiNpcRecipeHas(recipe: ref<AiNpcRecipe>, blockKey: String) -> Bool {
    let block = AiNpcRecipeBlockNamed(recipe, blockKey);
    if !IsDefined(block) {
        return true;
    }
    return ArraySize(block.parts) > 0;
}

// Whether this block renders that part. The part name is checked against the schema by
// tools\lint.ps1, which is the only thing between a typo here and a section that vanishes
// without a word.
func AiNpcRecipeWants(recipe: ref<AiNpcRecipe>, blockKey: String, part: String) -> Bool {
    let block = AiNpcRecipeBlockNamed(recipe, blockKey);
    if !IsDefined(block) {
        return true;
    }
    return ArrayContains(block.parts, part);
}

// The block's option, or "" when the recipe says nothing. A renderer decides what an empty
// answer means, because only it knows its own default.
func AiNpcRecipeSourceOf(recipe: ref<AiNpcRecipe>, blockKey: String) -> String {
    let block = AiNpcRecipeBlockNamed(recipe, blockKey);
    if !IsDefined(block) {
        return "";
    }
    return block.source;
}

func AiNpcRecipeBlockNamed(recipe: ref<AiNpcRecipe>, blockKey: String) -> ref<AiNpcRecipeBlock> {
    if !IsDefined(recipe) {
        return null;
    }
    let i = 0;
    let count = ArraySize(recipe.blocks);
    while i < count {
        if Equals(recipe.blocks[i].key, blockKey) {
            return recipe.blocks[i];
        }
        i += 1;
    }
    return null;
}

/// Building one ///

// A block set on a copy, never edited in place: a recipe is handed around a prompt build and
// a shared one edited underneath is a prompt that differs from the one that was logged.
func AiNpcRecipeWith(recipe: ref<AiNpcRecipe>, block: ref<AiNpcRecipeBlock>) -> ref<AiNpcRecipe> {
    let out = new AiNpcRecipe();
    out.name = recipe.name;

    let replaced = false;
    let i = 0;
    let count = ArraySize(recipe.blocks);
    while i < count {
        if Equals(recipe.blocks[i].key, block.key) {
            ArrayPush(out.blocks, block);
            replaced = true;
        } else {
            ArrayPush(out.blocks, recipe.blocks[i]);
        }
        i += 1;
    }
    if !replaced {
        ArrayPush(out.blocks, block);
    }
    return out;
}

func AiNpcRecipeBlockOf(key: String, parts: array<String>) -> ref<AiNpcRecipeBlock> {
    let block = new AiNpcRecipeBlock();
    block.key = key;
    block.parts = parts;
    return block;
}
