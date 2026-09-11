// Qui passe l'appel sur F, et quand le mod rejoint un appel du jeu.

module AiNpc

func AiNpcTestCallRoute(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("route/the game keeps a call it has a scene for",
        Equals(AiNpcCallRouteFor(true, true), AiNpcCallRoute.Vanilla));
    t.Check("route/the mod calls where the game has no scene",
        Equals(AiNpcCallRouteFor(true, false), AiNpcCallRoute.Ours));
    t.Check("route/a contact the mod does not manage stays vanilla",
        Equals(AiNpcCallRouteFor(false, true), AiNpcCallRoute.Vanilla));
    t.Check("route/even when the game cannot call it",
        Equals(AiNpcCallRouteFor(false, false), AiNpcCallRoute.Vanilla));

    t.Check("join/a game call is joined from idle", AiNpcCallMayJoin(AiNpcCallState.Idle));
    t.Check("join/or once the last call is over", AiNpcCallMayJoin(AiNpcCallState.Ended));
    t.Check("join/never over a call of ours", !AiNpcCallMayJoin(AiNpcCallState.Ringing));
    t.Check("join/nor over a live one", !AiNpcCallMayJoin(AiNpcCallState.Connected));
}
