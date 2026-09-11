// Qui passe l'appel quand le joueur appuie sur F devant un contact. Pur.

module AiNpc

enum AiNpcCallRoute {
    Vanilla = 0,
    Ours = 1,
}

// Le jeu garde tout appel pour lequel il a une scène ; la barre de chat s'y greffe ensuite.
// Le mod n'appelle lui-même que ses personnages que le jeu ne sait pas appeler.
func AiNpcCallRouteFor(managed: Bool, vanillaCallable: Bool) -> AiNpcCallRoute {
    if managed && !vanillaCallable {
        return AiNpcCallRoute.Ours;
    }
    return AiNpcCallRoute.Vanilla;
}
