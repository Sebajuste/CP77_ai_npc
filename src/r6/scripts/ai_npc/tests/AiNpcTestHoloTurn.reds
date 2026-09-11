// Le tour de parole d'un holo du jeu : jamais deux voix à la fois, et aucun choix du jeu
// validé pendant que le joueur écrit.

module AiNpc

func AiNpcTestHoloTurn(t: ref<AiNpcTestRunner>) -> Void {
    let scene = AiNpcHoloTurn.Scene;
    t.Check("turn/nothing is said over the scene", !AiNpcHoloTurnTakesReply(scene));
    t.Check("turn/opening the line over the scene is refused",
        Equals(AiNpcHoloTurnAfter(scene, AiNpcHoloTurnEvent.PlayerTyping), scene));

    let choice = AiNpcHoloTurnAfter(scene, AiNpcHoloTurnEvent.ChoiceShown);
    t.Check("turn/a choice on screen offers the reply", AiNpcHoloTurnTakesReply(choice));
    t.Check("turn/and leaves the game's choices visible", !AiNpcHoloTurnHidesChoices(choice));
    t.Check("turn/a line needs the line open",
        Equals(AiNpcHoloTurnAfter(choice, AiNpcHoloTurnEvent.PlayerSpoke), choice));

    let timed = AiNpcHoloTurnAfter(scene, AiNpcHoloTurnEvent.TimedChoiceShown);
    t.Check("turn/a timed choice keeps the reply closed", !AiNpcHoloTurnTakesReply(timed));

    let typing = AiNpcHoloTurnAfter(choice, AiNpcHoloTurnEvent.PlayerTyping);
    t.Check("turn/typing hides the game's choices", AiNpcHoloTurnHidesChoices(typing));
    t.Check("turn/and accepts the line", AiNpcHoloTurnAcceptsLine(typing));
    t.Check("turn/a rewritten hub stays hidden while typing",
        Equals(AiNpcHoloTurnAfter(typing, AiNpcHoloTurnEvent.ChoiceShown), typing));
    t.Check("turn/giving up the line gives the choice back",
        Equals(AiNpcHoloTurnAfter(typing, AiNpcHoloTurnEvent.TypingDropped), AiNpcHoloTurn.Choice));

    let model = AiNpcHoloTurnAfter(typing, AiNpcHoloTurnEvent.PlayerSpoke);
    t.Check("turn/a line said hands the floor to the model", Equals(model, AiNpcHoloTurn.Model));
    t.Check("turn/the choices stay hidden while it answers", AiNpcHoloTurnHidesChoices(model));
    t.Check("turn/the line closing after it was said moves nothing",
        Equals(AiNpcHoloTurnAfter(model, AiNpcHoloTurnEvent.TypingDropped), model));
    t.Check("turn/a rewritten hub stays hidden while it answers",
        Equals(AiNpcHoloTurnAfter(model, AiNpcHoloTurnEvent.ChoiceShown), model));
    t.Check("turn/the reply over gives the choice back",
        Equals(AiNpcHoloTurnAfter(model, AiNpcHoloTurnEvent.ModelDone), AiNpcHoloTurn.Choice));

    t.Check("turn/a vanilla answer hands the line to the scene",
        Equals(AiNpcHoloTurnAfter(choice, AiNpcHoloTurnEvent.ChoiceGone), scene));
    t.Check("turn/a stale reply end moves nothing",
        Equals(AiNpcHoloTurnAfter(scene, AiNpcHoloTurnEvent.ModelDone), scene));
}
