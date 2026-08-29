// A composed block: rubrics in a fixed order, each owned by a key.
//
// The block is a list of rubrics in a fixed order, each owned by a key. A provider or a JSON
// file contributes rubrics by key: a known key replaces that rubric in place, an unknown one
// is appended. Nothing can drop the block or reorder it.
//
// Three keys are the mod's own and refuse every contribution -- FORM, TIME and LENGTH. They
// are not editorial: they describe the surface the reply lands on. One message per turn, no
// "Name:" prefix, a length that fits a phone bubble, and time markers this mod writes and the
// model must only read. A contact that wins those breaks the chat UI for the player, not the
// characterisation.
//
// The rest is contributable, which is the point: a contact that is not a person needs YOU and
// SETTING in its own words, and may need rubrics the cast never imagined. No shipped sheet
// uses this; a provider another mod registers is what it is for.
//
// Pure. The texts come from callers, so the merge and the render are assertable without a
// session.

module AiNpc

// A rubric. `labelled` is false for the one rubric whose text carries its own labels: the
// language rule, which is two lines and states them itself.
public class AiNpcRule {
    public let key: String;
    public let text: String;
    public let labelled: Bool = true;
}

func AiNpcRuleOf(key: String, text: String) -> ref<AiNpcRule> {
    let rule = new AiNpcRule();
    rule.key = AiNpcRuleKey(key);
    rule.text = text;
    return rule;
}

// One spelling per rubric, decided here and nowhere else.
//
// Upper case is not cosmetic: the locked keys are compared by name, so "form" would be a
// second rubric contradicting FORM from the line above LENGTH rather than a refused
// contribution. StrUpper is ASCII-only, which is enough -- a key is a label the mod's own
// rubrics spell in ASCII, and a translated key would break the merge, not improve it.
func AiNpcRuleKey(raw: String) -> String {
    return StrUpper(AiNpcMemoryTrim(raw));
}

func AiNpcRawRuleOf(key: String, text: String) -> ref<AiNpcRule> {
    let rule = AiNpcRuleOf(key, text);
    rule.labelled = false;
    return rule;
}

// The keys no contribution may take, per block. Answered here rather than at each call site,
// so the prompt builder and the config validator cannot disagree about what is locked.
//
// The blocks are named by their tag, which is what an author reads in a prompt dump.
func AiNpcRuleIsLocked(block: String, key: String) -> Bool {
    let normalised = AiNpcRuleKey(key);
    if Equals(block, "system_rules") {
        return Equals(normalised, "FORM") || Equals(normalised, "TIME")
            || Equals(normalised, "LENGTH");
    }
    if Equals(block, "interactions") {
        // The one clause whose loss the player sees: a character promising to come and
        // getting nobody there reads as the mod being broken.
        return Equals(normalised, "PROMISES");
    }
    return false;
}

// What one contribution may spend, and what every contribution may spend together.
//
// Same shape as the <now> budgets and for the same reason: a block with no bound is a
// block one mod can fill. Smaller than <now>'s, because a rule is read on every message
// and sits inside the cacheable prefix, where length costs on every request rather than on
// the ones an event interrupts.
func AiNpcRuleBudget() -> Int32 {
    return 600;
}

func AiNpcRuleTotalBudget() -> Int32 {
    return 2000;
}

// Why a contribution was refused, or "" when it was taken. One answer for the merge and for
// the config report, so an author reads the same sentence in both places.
func AiNpcRuleRefusal(block: String, rule: ref<AiNpcRule>) -> String {
    if !IsDefined(rule) || Equals(StrLen(rule.key), 0) {
        return "a rule with no key";
    }
    if AiNpcRuleIsLocked(block, rule.key) {
        return s"one of the rubrics ai_npc keeps in <\(block)>: it describes the chat itself, not the character";
    }
    if Equals(StrLen(AiNpcMemoryTrim(rule.text)), 0) {
        return "empty, and an empty rubric would delete the mod's own rather than replace it";
    }
    if AiNpcTextLooksLikeMarkup(rule.text) {
        return "carrying markup: a contribution may not contain a tag";
    }
    if StrLen(rule.text) > AiNpcRuleBudget() {
        return s"longer than the \(AiNpcRuleBudget()) characters one rubric may spend";
    }
    return "";
}

func AiNpcRuleIndexOf(rules: array<ref<AiNpcRule>>, key: String) -> Int32 {
    let i = 0;
    let count = ArraySize(rules);
    while i < count {
        if Equals(rules[i].key, key) {
            return i;
        }
        i += 1;
    }
    return -1;
}

// One contribution against the block, in the style every other list here follows: a new
// array out rather than one edited in place. A locked key comes back unchanged, and the
// caller -- the only half that may log -- asks AiNpcRuleIsLocked why.
func AiNpcRulesWith(block: String, rules: array<ref<AiNpcRule>>,
                           rule: ref<AiNpcRule>) -> array<ref<AiNpcRule>> {
    if NotEquals(StrLen(AiNpcRuleRefusal(block, rule)), 0) {
        return rules;
    }

    let out = rules;
    let existing = AiNpcRuleIndexOf(out, rule.key);
    if existing >= 0 {
        // Replaced where it stands. A contribution that moved its rubric to the end would
        // silently gain the weight position gives, without saying so.
        out[existing] = rule;
        return out;
    }

    // LENGTH stays last whatever anyone contributes: it is the one dimension a sheet may not
    // win, and in a prompt the last statement of a conflict is the one a model keeps. A block
    // without it appends instead.
    let last = AiNpcRuleIndexOf(out, "LENGTH");
    if last < 0 {
        ArrayPush(out, rule);
        return out;
    }
    ArrayInsert(out, last, rule);
    return out;
}

func AiNpcRenderRules(block: String, rules: array<ref<AiNpcRule>>) -> String {
    let body = "";
    let i = 0;
    let count = ArraySize(rules);
    while i < count {
        let rule = rules[i];
        if NotEquals(StrLen(rule.text), 0) {
            if rule.labelled {
                body += rule.key + ": " + rule.text + "\n";
            } else {
                body += rule.text + "\n";
            }
        }
        i += 1;
    }

    if Equals(StrLen(body), 0) {
        return "";
    }
    return "<" + block + ">\n" + body + "</" + block + ">";
}

// A rubric declared by hand, replacing one of the same key rather than doubling it.
public func AiNpcRuleSet(rules: array<ref<AiNpcRule>>, key: String, text: String) -> array<ref<AiNpcRule>> {
    let out = rules;
    let existing = AiNpcRuleIndexOf(out, key);
    if existing >= 0 {
        out[existing] = AiNpcRuleOf(key, text);
        return out;
    }
    ArrayPush(out, AiNpcRuleOf(key, text));
    return out;
}
