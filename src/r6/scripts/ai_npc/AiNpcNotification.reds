// Getting a line in front of the player when nothing is painting it.
//
// The speaking lane offers every registered surface the reply first (AiNpcPublishReply); the
// ordinary answer is that none of them took it, because the ordinary state is a closed phone.
// What happens then is here, and deliberately NOT in the lane: pushing an SMS means holding a
// game controller, and a lane that held one would dereference null every time a reply lands
// with the chat closed -- the common case, not the rare one.
//
// The controller search is written once here; each caller keeps its own handle for its own
// lifetime.

module AiNpc

// Finds the phone controller by CLASS NAME, because the game exposes no accessor for it.
//
// The HUD layer first, which is where it lives. The sweep over the remaining layers is a
// fallback: losing an SMS is a worse failure than one extra loop over a dozen controllers.
//
// Never cached here. The controller is destroyed with the HUD, so a handle is only valid for
// as long as its holder can promise to refresh it, and this function makes no such promise.
func AiNpcFindPhoneController() -> wref<NewHudPhoneGameController> {
    let inkSystem = GameInstance.GetInkSystem();
    let found: wref<NewHudPhoneGameController>;

    let hud = inkSystem.GetLayer(n"inkHUDLayer");
    if IsDefined(hud) {
        for controller in hud.GetGameControllers() {
            if Equals(s"\(controller.GetClassName())", "NewHudPhoneGameController") {
                found = controller as NewHudPhoneGameController;
            }
        }
    }
    if IsDefined(found) {
        return found;
    }

    for layer in inkSystem.GetLayers() {
        for controller in layer.GetGameControllers() {
            if Equals(s"\(controller.GetClassName())", "NewHudPhoneGameController") {
                found = controller as NewHudPhoneGameController;
            }
        }
    }
    return found;
}

// One line, to whoever can show it.
//
// The single delivery decision, and it is one question: did anybody paint this? Every surface
// that can render is offered it, most recently opened first, and each decides for itself
// whether the message belongs on it. Nobody rendering is not an error and never was -- it is
// what an SMS notification is for.
//
// The contact is a parameter for the same reason it is one everywhere below the send, and
// here it is at its sharpest: this is the path taken when the chat is NOT open on the sender.
// Title the notification from the current selection instead and a reply from Panam, arriving
// while the player is reading Judy's thread, is announced as Judy's.
func AiNpcDeliverOrNotify(contactId: String, text: String) -> Void {
    if AiNpcPublishReply(contactId, text) {
        return;
    }

    // The mod that owns the correspondent gets first refusal on the notification, because the
    // push below is the VANILLA phone's and addresses a contact by display name. A contact
    // that lives in another mod's phone framework is addressed there by hash, and a vanilla
    // notification for it leads nowhere when the player taps it. See
    // AiNpcContactProvider.Notify -- and note the write already happened, above and always.
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) && provider.Notify(text) {
        return;
    }

    let phone = AiNpcFindPhoneController();
    if !IsDefined(phone) {
        AiNpcLog(s"No phone controller: '\(contactId)' had a line and nowhere to say it.");
        return;
    }
    phone.PushCustomSMSNotification(contactId, AiNpcGetCharacterName(contactId), text);
}
