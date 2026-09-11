// Le hub de dialogue du jeu, lu pour le tour de parole d'un holo.
//
// Le tableau noir n'est jamais réécrit : masquer les choix se fait à l'affichage, dans
// dialogWidgetGameController.UpdateDialogsData (AiNpcHooks.reds). La scène garde donc ses
// données intactes, et les rendre ne demande que de rejouer la valeur existante.

module AiNpc

func AiNpcDialogBoard() -> ref<IBlackboard> {
    return GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
}

func AiNpcDialogHubEvent(hubs: DialogChoiceHubs) -> AiNpcHoloTurnEvent {
    let list = hubs.choiceHubs;
    if ArraySize(list) == 0 {
        return AiNpcHoloTurnEvent.ChoiceGone;
    }
    if AiNpcDialogHubsTimed(list) {
        return AiNpcHoloTurnEvent.TimedChoiceShown;
    }
    return AiNpcHoloTurnEvent.ChoiceShown;
}

// Le minuteur peut porter sur le hub ou sur un choix : dialogUI.script lit les deux.
func AiNpcDialogHubsTimed(hubs: array<ListChoiceHubData>) -> Bool {
    let i = 0;
    while i < ArraySize(hubs) {
        let hub = hubs[i];
        if IsDefined(hub.timeProvider) {
            return true;
        }
        let choices = hub.choices;
        let j = 0;
        while j < ArraySize(choices) {
            let choice = choices[j];
            if IsDefined(choice.timeProvider) {
                return true;
            }
            j += 1;
        }
        i += 1;
    }
    return false;
}

// La même valeur, reposée avec notification : l'affichage relit le tour de parole.
func AiNpcDialogHubRepaint() -> Void {
    let board = AiNpcDialogBoard();
    if !IsDefined(board) {
        return;
    }
    let key = GetAllBlackboardDefs().UIInteractions.DialogChoiceHubs;
    board.SetVariant(key, board.GetVariant(key), true);
}
