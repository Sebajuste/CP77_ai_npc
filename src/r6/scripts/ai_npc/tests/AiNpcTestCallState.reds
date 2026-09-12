// La table des transitions d'un appel, verifiee la ou aucun systeme n'existe.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.
//
// The whole reason AiNpcCallState.reds is pure: these run from AiNpcStorageService's attach, at
// game start, before any ScriptableSystem is alive. A machine that decided inside the system
// could only ever be checked by placing a call in game.

module AiNpc

func AiNpcTestCallTransitions(t: ref<AiNpcTestRunner>) -> Void {

    t.Check("a call starts by dialing",
        AiNpcCallMayGo(AiNpcCallState.Idle, AiNpcCallState.Dialing));
    t.Check("nothing else starts a call",
        !AiNpcCallMayGo(AiNpcCallState.Idle, AiNpcCallState.Connected));
    t.Check("a state does not go to itself",
        !AiNpcCallMayGo(AiNpcCallState.Ringing, AiNpcCallState.Ringing));

    t.Check("dialing reaches ringing",
        AiNpcCallMayGo(AiNpcCallState.Dialing, AiNpcCallState.Ringing));
    t.Check("dialing can be refused",
        AiNpcCallMayGo(AiNpcCallState.Dialing, AiNpcCallState.Refused));
    t.Check("dialing can be hung up",
        AiNpcCallMayGo(AiNpcCallState.Dialing, AiNpcCallState.Ended));
    t.Check("dialing never connects on its own",
        !AiNpcCallMayGo(AiNpcCallState.Dialing, AiNpcCallState.Connected));

    t.Check("ringing is picked up",
        AiNpcCallMayGo(AiNpcCallState.Ringing, AiNpcCallState.Connected));
    t.Check("ringing runs out",
        AiNpcCallMayGo(AiNpcCallState.Ringing, AiNpcCallState.Missed));
    t.Check("ringing can be hung up",
        AiNpcCallMayGo(AiNpcCallState.Ringing, AiNpcCallState.Ended));

    t.Check("a connected call only ends",
        AiNpcCallMayGo(AiNpcCallState.Connected, AiNpcCallState.Ended));
    t.Check("a connected call does not ring again",
        !AiNpcCallMayGo(AiNpcCallState.Connected, AiNpcCallState.Ringing));

    t.Check("an ending settles to idle",
        AiNpcCallMayGo(AiNpcCallState.Ended, AiNpcCallState.Idle));
    t.Check("a missed call settles to idle",
        AiNpcCallMayGo(AiNpcCallState.Missed, AiNpcCallState.Idle));
    t.Check("an ending goes nowhere else",
        !AiNpcCallMayGo(AiNpcCallState.Ended, AiNpcCallState.Dialing));
}

func AiNpcTestCallHearsOnlyItsOwn(t: ref<AiNpcTestRunner>) -> Void {
    let live = AiNpcCallState.Connected;

    t.Check("hears/its own spoken reply",
        AiNpcCallHears(live, "victor_vector", "victor_vector", AiNpcChannelId.Call));
    t.Check("hears/not another contact's text",
        !AiNpcCallHears(live, "victor_vector", "anon_1298803501", AiNpcChannelId.Text));
    t.Check("hears/not its own contact's text",
        !AiNpcCallHears(live, "victor_vector", "victor_vector", AiNpcChannelId.Text));
    t.Check("hears/not another contact on the call channel",
        !AiNpcCallHears(live, "victor_vector", "judy", AiNpcChannelId.Call));
    t.Check("hears/nothing once it has ended",
        !AiNpcCallHears(AiNpcCallState.Ended, "victor_vector", "victor_vector", AiNpcChannelId.Call));
    t.Check("hears/nothing for nobody",
        !AiNpcCallHears(live, "", "", AiNpcChannelId.Call));
}

// The rule this whole step exists to prove, and the one a widget could hide later: a call that
// was not answered opens no conversation.
func AiNpcTestCallOpensOnce(t: ref<AiNpcTestRunner>) -> Void {

    t.Check("being picked up opens it",
        AiNpcCallConnects(AiNpcCallState.Ringing, AiNpcCallState.Connected));

    t.Check("ringing out does not",
        !AiNpcCallConnects(AiNpcCallState.Ringing, AiNpcCallState.Missed));
    t.Check("being refused does not",
        !AiNpcCallConnects(AiNpcCallState.Dialing, AiNpcCallState.Refused));
    t.Check("hanging up while it rings does not",
        !AiNpcCallConnects(AiNpcCallState.Ringing, AiNpcCallState.Ended));
    t.Check("dialing does not",
        !AiNpcCallConnects(AiNpcCallState.Idle, AiNpcCallState.Dialing));

    // The transition has to be legal AND land on Connected: a stale timer firing into Idle
    // must not open a thread, and that is exactly what the serial guard defends against.
    t.Check("an illegal jump to connected does not open one either",
        !AiNpcCallConnects(AiNpcCallState.Idle, AiNpcCallState.Connected));

    t.Check("a missed call is over", AiNpcCallIsOver(AiNpcCallState.Missed));
    t.Check("a refused call is over", AiNpcCallIsOver(AiNpcCallState.Refused));
    t.Check("an ended call is over", AiNpcCallIsOver(AiNpcCallState.Ended));
    t.Check("idle is not an ending", !AiNpcCallIsOver(AiNpcCallState.Idle));
    t.Check("ringing is not an ending", !AiNpcCallIsOver(AiNpcCallState.Ringing));

    t.Check("dialing is live", AiNpcCallIsLive(AiNpcCallState.Dialing));
    t.Check("a missed call is not", !AiNpcCallIsLive(AiNpcCallState.Missed));
    t.Check("idle is not", !AiNpcCallIsLive(AiNpcCallState.Idle));
}
