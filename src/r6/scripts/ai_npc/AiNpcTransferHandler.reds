// Sending eddies to V: ai_npc's own command, declared through ai_npc's own public door.
//
// Nothing here is privileged. It opens a client under ai_npc's own id and calls AddAction like
// any mod's command, is scoped by an ordinary tag, is announced from its pattern, and is
// dispatched by the same table. That is the point: the first consumer of an API being the mod
// that ships it is what keeps the API honest, and the half of this mod that skipped its own
// door is where four silent defects grew -- a veto called from nowhere, a clamp that told
// nobody, a vocabulary two lanes spelled differently. See docs/PLAN_ACTION_LANE.md.
//
// The client and not the registry. Going straight to AiNpcGetActionRegistry() worked, and that
// is exactly why it survived a rewrite whose whole subject was this file's privileges: ai_npc
// was the one contributor that never claimed its own mod id, so the mod shipping the API was
// missing from the diagnostic the API offers for reading who granted what.
//
// Two bounds, and they answer different questions. This file clamps ONE tag, because a model
// writing 999999 has made a typo rather than a decision. AiNpcTransferLedger clamps what one
// CONTACT may release across a thread, because a player can talk a character into emitting the
// tag every message.
module AiNpc

/// The bounds ///

// The most one tag may carry, and the most one contact may release. Stated here and in the
// prompt text below, because the model is told the ceiling it will be held to -- a character
// promising 20000 and delivering 5000 is the broken promise the prompt's own PROMISES rule
// exists to prevent.
func AiNpcTransferCap() -> Int32 {
    return 5000;
}

// One tag against the ceiling. Pure and parameterised, so the bound is assertable without a
// session -- as AiNpcClampTransfer is for the running total.
func AiNpcClampAmount(amount: Int32, cap: Int32) -> Int32 {
    if amount <= 0 {
        return 0;
    }
    if amount > cap {
        return cap;
    }
    return amount;
}

// What one field is worth: its own digits, clamped.
//
// Digits only, and at most nine of them. "1 500", "1.5k" and "5000eddies" all read as no amount
// rather than as a number this code guessed at, and nine digits is where an Int32 stops holding
// what StringToInt was handed -- a model writing a page of zeroes must not wrap into a negative
// transfer.
func AiNpcTransferAmount(payload: String) -> Int32 {
    let length = StrLen(payload);
    if length <= 0 || length > 9 || !AiNpcIsDigits(payload) {
        return 0;
    }
    return AiNpcClampAmount(StringToInt(payload), AiNpcTransferCap());
}

/// The declaration ///

func AiNpcTransferPattern() -> String {
    // NAMED FOR THE COMMAND, not for what it holds. The block is one flat list of parameters:
    // "{amount}" is what a joytoy's price would be called too, and a model reading one list
    // with one name defined twice cannot tell which command it belongs to. The registry keeps
    // the two mods apart; the prompt does not.
    return "[ACTION:GIVE_EDDIES:{give_amount_eddies}]";
}

// What the command does and when, and nothing about its field: the field is a parameter now,
// and repeating its grammar here is the arrangement the parameters replaced.
func AiNpcTransferPrompt() -> String {
    return "Send eddies to V's account, when V asks for money. One tag per message.";
}

// Three landmarks rather than three tiers: the amount is the character's to choose, and the
// examples are there to give the scale a sense of what money means here.
func AiNpcTransferAmountParam() -> String {
    return "plain digits, never above " + IntToString(AiNpcTransferCap())
        + ". Pick the number yourself: 100 is a drink or spare change, 1000 buys ammo and gear "
        + "for a job, 5000 covers a debt or an emergency and stays rare.";
}

/// The effect ///

public class AiNpcTransferHandler extends AiNpcActionHandler {

    public func OnAction(ctx: ref<AiNpcContactContext>, params: array<String>) -> ref<AiNpcActionResult> {
        // The arity is guaranteed by the pattern; the MEANING never is. Every field inside a
        // tag was written by a language model.
        let requested = AiNpcTransferAmount(params[0]);
        if requested <= 0 {
            return AiNpcActionRefused("The transfer did not go through: the amount you wrote was not a plain number, so nothing was sent.");
        }

        let economy = AiNpcEconomySystem.Get();
        if !IsDefined(economy) {
            return AiNpcActionRefused();
        }

        // Idempotence is the ledger's, not this method's: a resend after a network error
        // replays the whole reply, and this contact's running total is what stops the replay
        // from paying twice over.
        let granted = economy.TransferMoneyToPlayer(ctx.contactId, requested);

        if granted <= 0 {
            return AiNpcActionRefused(s"The transfer did not go through: you have already sent V \(AiNpcTransferCap()) eddies, which is all your account will release. Say so rather than promising more.");
        }
        if granted < requested {
            return AiNpcActionDone(s"Only \(granted) eddies actually reached V, not the \(requested) you meant to send: that is what was left of what your account will release. Mention the real figure.");
        }
        return AiNpcActionDone();
    }
}

// Registered by ai_npc itself, for every drivable contact.
//
// AiNpcEveryContactTag() is written out because "everyone" is a decision, not a default. A
// contact whose own mod already moves money suppresses this command rather than opting out of
// a flag named after it, which is why AllowsGenericTransfer no longer exists.
func AiNpcRegisterTransferAction() -> Bool {
    return AiNpcOpenClient(AiNpcOwnModId())
        .AddAction(AiNpcTransferPattern(), AiNpcTransferPrompt(),
                   new AiNpcTransferHandler(), AiNpcEveryContactTag(),
                   [AiNpcParam("{give_amount_eddies}", AiNpcTransferAmountParam())]);
}

// The head every opt-out names, and the one name in docs\API.md that is NOT declared under
// api\. It stays here, beside the pattern that declares the command and the parser that
// recognises it: one literal, so a mod suppressing the transfer and the dispatcher matching it
// cannot drift apart. Moving it into api\AiNpcActionHandler.reds -- the contract EVERY handler
// implements -- would put the built-in command's name in the one file that must not know it,
// which is the privilege docs/PLAN_ACTION_LANE.md removed and tools\lint.ps1 rule 9 catches.
public func AiNpcTransferHead() -> String {
    return "[ACTION:GIVE_EDDIES:";
}

// Registered at attach, the way the romance rubric is: this mod's own contributions go through
// the public door, and a bootstrap that fails is a line in the log rather than a command that
// silently does not exist.
public class AiNpcTransferBootstrap extends ScriptableSystem {

    private func OnAttach() -> Void {
        if !AiNpcRegisterTransferAction() {
            FTLogError("[ai_npc]: the eddie transfer could not register: no action registry.");
        }
    }
}
