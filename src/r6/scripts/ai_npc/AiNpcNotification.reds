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

// Ce qui livrait une ligne vit maintenant dans AiNpcChannelText : la question n'est plus « qui
// peint ceci » mais « que fait CE canal quand personne ne peint », et la reponse differe --
// l'ecrit pousse une notification, le parle ne pousse rien.
//
// Ce qui reste ici est la recherche du controleur, ecrite une fois, parce qu'elle appartient au
// telephone et a personne d'autre.
