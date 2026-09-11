// Qui a la parole pendant un holo du jeu où la barre de chat est greffée. Pur.
//
// Le conflit de voix est impossible par construction : le modèle ne parle que devant un choix
// qui attend, et les choix du jeu restent masqués tant que le joueur écrit ou que le modèle
// répond. Rien ici n'écoute l'audio du jeu : « la scène a fini sa réplique » se lit au choix
// suivant qui s'affiche.

module AiNpc

enum AiNpcHoloTurn {
    Scene = 0,
    Choice = 1,
    TimedChoice = 2,
    Model = 3,
    Typing = 4,
}

enum AiNpcHoloTurnEvent {
    ChoiceShown = 0,
    TimedChoiceShown = 1,
    ChoiceGone = 2,
    PlayerSpoke = 3,
    ModelDone = 4,
    PlayerTyping = 5,
    TypingDropped = 6,
}

func AiNpcHoloTurnAfter(turn: AiNpcHoloTurn, event: AiNpcHoloTurnEvent) -> AiNpcHoloTurn {
    switch event {
        case AiNpcHoloTurnEvent.ChoiceShown:
            // Le jeu réécrit le hub pendant que le joueur écrit ou que le modèle répond : il
            // reste masqué.
            if AiNpcHoloTurnHidesChoices(turn) {
                return turn;
            }
            return AiNpcHoloTurn.Choice;
        case AiNpcHoloTurnEvent.TimedChoiceShown:
            if AiNpcHoloTurnHidesChoices(turn) {
                return turn;
            }
            return AiNpcHoloTurn.TimedChoice;
        case AiNpcHoloTurnEvent.ChoiceGone:
            return AiNpcHoloTurn.Scene;
        case AiNpcHoloTurnEvent.PlayerTyping:
            if Equals(turn, AiNpcHoloTurn.Choice) {
                return AiNpcHoloTurn.Typing;
            }
            return turn;
        case AiNpcHoloTurnEvent.PlayerSpoke:
            if Equals(turn, AiNpcHoloTurn.Typing) {
                return AiNpcHoloTurn.Model;
            }
            return turn;
        case AiNpcHoloTurnEvent.TypingDropped:
            if Equals(turn, AiNpcHoloTurn.Typing) {
                return AiNpcHoloTurn.Choice;
            }
            return turn;
        case AiNpcHoloTurnEvent.ModelDone:
            if Equals(turn, AiNpcHoloTurn.Model) {
                return AiNpcHoloTurn.Choice;
            }
            return turn;
    }
    return turn;
}

// R ouvre la ligne. Un choix minuté est exclu : masquer les choix n'arrête pas son minuteur.
func AiNpcHoloTurnTakesReply(turn: AiNpcHoloTurn) -> Bool {
    return Equals(turn, AiNpcHoloTurn.Choice);
}

func AiNpcHoloTurnAcceptsLine(turn: AiNpcHoloTurn) -> Bool {
    return Equals(turn, AiNpcHoloTurn.Typing);
}

func AiNpcHoloTurnHidesChoices(turn: AiNpcHoloTurn) -> Bool {
    return Equals(turn, AiNpcHoloTurn.Typing) || Equals(turn, AiNpcHoloTurn.Model);
}
