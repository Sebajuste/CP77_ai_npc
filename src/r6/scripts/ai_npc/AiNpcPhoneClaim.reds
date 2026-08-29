// Taking the phone away from the player, and giving it back.
//
// Drawing the mod's chat means borrowing two things that belong to the game's phone: its
// contact input (so arrow keys stop moving a list nobody can see) and its contact list (so
// our panel is not drawn on top of it). Both have to be given back, together, whatever ends
// the chat -- C, Escape, the hub menu, combat, the phone being put away, another mod.
//
// Kept as a rule instead, it is a defect nothing fails to compile over and nothing logs:
// deleting one of the two returns leaves the player on an invisible contact list over an
// input-dead phone. So the two calls happen here or nowhere -- Take and Release are the only
// entry points, and `m_held` makes both idempotent, so a double close, a close with the phone
// already gone, or a rebuild in the middle cannot desynchronise anything. tools\lint.ps1 rule
// 8e keeps this file the only owner.
//
// It deliberately does NOT know about the chat widget. Borrowing the phone and drawing on it
// are two steps and stay two steps; what this removes is the possibility of doing one of the
// two borrows.
module AiNpc

public class AiNpcPhoneClaim {
    private let m_held: Bool = false;

    public func IsHeld() -> Bool {
        return this.m_held;
    }

    // Borrow the phone. Answers whether the mod now holds it -- false means the tree was not
    // there, and the caller must not go on to draw a chat into it.
    //
    // Both halves are required. A claim with only one taken is the failure this class exists
    // to prevent, so a missing contact list refuses the whole claim rather than taking the
    // input half and hoping.
    public func Take(controller: wref<NewHudPhoneGameController>, view: ref<AiNpcPhoneChatRenderer>) -> Bool {
        if this.m_held {
            return true;
        }
        if !IsDefined(controller) || !IsDefined(view) || !view.HasContactList() {
            return false;
        }

        controller.DisableContactsInput();
        view.ToggleContactList(false);
        this.m_held = true;
        return true;
    }

    // Give the phone back. Silent and safe when nothing is held, because every close path in
    // the mod reaches here and none of them knows whether it is the one that closed anything.
    //
    // A claim held over a controller or a view that has since been rebuilt is DROPPED rather
    // than kept: the widgets it borrowed no longer exist, so there is nothing left to give
    // back, and holding on would make the next Take a no-op on a phone that is still
    // input-dead. That is the one case where the claim can be wrong, and it resolves toward
    // the player getting their phone back.
    public func Release(controller: wref<NewHudPhoneGameController>, view: ref<AiNpcPhoneChatRenderer>) -> Bool {
        if !this.m_held {
            return true;
        }

        this.m_held = false;

        if !IsDefined(controller) || !IsDefined(view) || !view.HasContactList() {
            AiNpcLog("Phone claim dropped: the controller or the contact list is gone. Nothing to give back.");
            return false;
        }

        controller.EnableContactsInput();
        view.ToggleContactList(true);
        return true;
    }
}
