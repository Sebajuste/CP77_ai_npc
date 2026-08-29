module AiNpc

// What a mod writes to give a character something to DO.
//
// One required method. That is deliberate and it is the lesson of the interface this replaces:
// REDscript has no function values, so a callback has to be an object, and a WIDE object is
// overridden method by method -- a consumer that gets one name or one signature wrong keeps
// compiling, silently overrides nothing, and ships a feature that never runs. ai_npc_joytoys
// lost its whole rendezvous vocabulary that way, for as long as the feature existed, because
// the two lanes that did this job had spelled one method differently.
//
// A command is declared in one call:
//
//     client.AddAction("[ACTION:CALL_DELAMAIN]",
//                      "You call a Delamain for V when they need one and you are placed to do it.",
//                      new DelamainHandler(), AiNpcEveryContactTag());
//
// The pattern is both halves at once: the model reads it, and the dispatcher matches against
// it. Announcing a command nobody implements, and implementing one nobody announced, are not
// mistakes that can be made from here.

/// What a slot of the pattern means ///

// What one slot of a pattern means, written once and read by every command that uses it.
//
// The name is the slot as the pattern shows it -- "{venue}" -- so the model reads the same
// token in the tag and in the definition, with nothing to match up.
public class AiNpcActionParam {
    public let name: String;
    public let text: String;
}

// Nothing inside ai_npc calls this; ai_npc_joytoys does, twice per registration.
public func AiNpcParam(name: String, text: String) -> ref<AiNpcActionParam> {
    let param = new AiNpcActionParam();
    param.name = name;
    param.text = text;
    return param;
}

/// What applying an action did ///

// The note is the reason this is not a Bool. A refused action is otherwise invisible: the tag
// is stripped so the vocabulary does not leak into the bubble, and the model has already
// written a message assuming it worked. The note is handed to the character as something it
// knows for its next reply, so the refusal comes back in that character's own voice instead of
// as a banner -- which is this project's standing rule about who announces a change of state.
//
// Keep the note a plain sentence addressed to the character. It reaches the model untouched.
public class AiNpcActionResult extends IScriptable {
    public let applied: Bool;
    public let note: String;
}

// The command was carried out. Pass a note when the character should mention something about
// it -- a clamped amount, a substituted choice -- and nothing when it simply worked.
public func AiNpcActionDone(opt note: String) -> ref<AiNpcActionResult> {
    let result = new AiNpcActionResult();
    result.applied = true;
    result.note = note;
    return result;
}

// The command could not be carried out. Say something whenever the character could know it:
// without a note the next reply carries on as though the command had worked.
//
// The note is left empty for a refusal whose reason is outside the fiction -- a permission a
// config file withdrew between the prompt and the reply, a precondition about the installation
// rather than the world. The character has no way of knowing that, and a note would only make
// it invent an explanation. The log keeps the record.
public func AiNpcActionRefused(opt note: String) -> ref<AiNpcActionResult> {
    let result = new AiNpcActionResult();
    result.applied = false;
    result.note = note;
    return result;
}

/// The handler ///

public class AiNpcActionHandler extends IScriptable {

    // Required. `params` are the slot values in pattern order, already split and counted:
    // "[ACTION:TRICK:{place}:{hour}:{price}]" hands you three non-empty strings, always.
    //
    // The arity is all the dispatcher bought you. EVERY FIELD WAS WRITTEN BY A LANGUAGE MODEL,
    // so validate the meaning here: clamp a number, snap a name to a known one. Prefer that to
    // refusing, because a refusal costs the whole command and the model has already promised
    // it in the sentence around the tag.
    //
    // Re-check your own preconditions too. The prompt that advertised this command was built
    // before V wrote, the offer may be gone, and a model can be argued into emitting a tag it
    // was never shown.
    //
    // MUST BE IDEMPOTENT: the model repeats tags, and a resend after a network error replays
    // the whole reply.
    public func OnAction(ctx: ref<AiNpcContactContext>, params: array<String>) -> ref<AiNpcActionResult> {
        return null;
    }

    // Whether the command is offered to this contact right now. Answer false and it is not
    // written into the prompt at all, which is the cheapest refusal there is: a command a model
    // is told about but will be refused is one it argues for instead of talking.
    //
    // This is where STATE goes -- "the diary is full", "V is not romanced", "Delamain is not
    // unlocked in this save". What the character IS goes in a tag instead; the line is declared
    // against computed, and mixing them produces two state machines answering one question at
    // different rates.
    //
    // Cost matters here: a command's fragment enters the prompt of every contact it covers, on
    // every message. Answering false removes the tokens as well as the mistake.
    //
    // NOT A GUARD ON THE EFFECT. A claim that stops offering its command still owns the tag:
    // between the prompt and the reply there is a round trip, the offer can vanish inside it,
    // and the tag must still be recognised and stripped rather than left in the player's chat.
    // OnAction is where that case is refused.
    public func IsOffered(ctx: ref<AiNpcContactContext>) -> Bool {
        return true;
    }

    // The sentence that teaches the model when to emit the command. `declared` is the string
    // passed to AddAction, and returning it is the default -- override only when the text has
    // to be computed, as a table of tonight's free slots has to be.
    //
    // Keep it short. Two lines, not a paragraph: this is paid for in every prompt of every
    // covered contact.
    public func GetPrompt(ctx: ref<AiNpcContactContext>, declared: String) -> String {
        return declared;
    }

    // What the pattern's slots mean, for this contact. `declared` is what AddAction was given,
    // and returning it is the default -- override only when a definition has to be computed,
    // as a list of the venues this save has unlocked has to be.
    //
    // THE SECOND METHOD OF THIS SHAPE, and the file's own warning about wide interfaces applies
    // to it: get the name wrong and you override nothing, silently. It is here rather than
    // folded into GetPrompt because a definition is shared -- two commands of one mod cite the
    // same slot -- and a sentence cannot be shared. Splitting a slot's meaning between the
    // sentence and the parameter would put its two halves a kilobyte apart, which is the
    // arrangement this replaced.
    public func GetParameters(ctx: ref<AiNpcContactContext>,
                              declared: array<ref<AiNpcActionParam>>)
                              -> array<ref<AiNpcActionParam>> {
        return declared;
    }
}
