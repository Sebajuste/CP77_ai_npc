// The two options a call offers, drawn by the game's own choice hub.
//
// It is the widget the player already knows -- the stacked "blueline" prompts of an
// interaction -- so a call offering "answer / hang up" reads like every other choice in the
// game rather than like a mod's window. Nothing is drawn here: the hub is a blackboard value,
// and the game paints whatever is in it.
//
// The pattern is not invented. It is the one NightlyNow and Street Vendors run on this machine:
// build an InteractionChoiceHubData, push it and its VisualizersInfo into the UIInteractions
// blackboard, and listen for the input action of the choice that was pressed.
//
// THE HUB IS SHARED, ET LE JEU LE REECRIT. Chaque source d'interaction ecrit dans la meme
// valeur, et le systeme d'interaction du jeu la reconstruit des que le contexte du joueur
// change : s'approcher d'une porte, s'en eloigner, un vehicule, un combat. Deux consequences,
// et les deux ont mordu.
//
// ON FUSIONNE, ON N'ECRASE PAS. Un hub remplace efface l'interaction que le joueur avait sous
// les yeux ; on ajoute nos deux lignes a ce qui est la et on ne retire que les notres.
//
// ON REAFFIRME. Ecrire une fois au decrochage ne tient pas : la premiere reconstruction du jeu
// emporte nos deux boutons, et le joueur se retrouve en appel sans rien pour repondre ni
// raccrocher -- observe en jeu le 2026-09-03. C'est la nature du support, pas un accident : le
// meme mecanisme fait tourner NightlyNow, qui reajoute ses interactions a intervalle regulier.
// Le controle est dans AiNpcCallSystem, qui a deja l'horloge et le numero de serie.

module AiNpc

// Actions nommées de r6\config\inputUserMappings.xml : l'invite montre la touche que le joueur
// a liée. Choice2 (R) et non Choice1 (F), qui sélectionne les choix de dialogue du jeu.
// PhoneReject est le maintien de T, le raccrocher du jeu ; il arrive au contrôleur du
// téléphone, pas au joueur.
func AiNpcCallReplyAction() -> CName {
    return n"Choice2";
}

func AiNpcCallHangUpAction() -> CName {
    return n"PhoneReject";
}

// La meme touche T porte une seconde action : PhoneInteract, dont le maintien sort le
// telephone (NewHudPhoneGameController.OnAction, branche BUTTON_HOLD_COMPLETE). Un seul
// maintien declenche les deux, et le jeu ne se marche jamais dessus parce que ses deux
// branches s'excluent sur callPhase == IncomingCall -- ce qu'un appel du mod n'est pas.
func AiNpcPhoneOpenAction() -> CName {
    return n"PhoneInteract";
}

// Les actions de choix du jeu. F et Entrée valident (Choice1, ChoiceApply -- DialogConfirm lie
// les deux touches), R et les autres prennent un choix secondaire. Une lettre tapée dans la
// ligne de saisie les déclenche aussi.
func AiNpcIsChoiceAction(name: CName) -> Bool {
    return Equals(name, n"Choice1") || Equals(name, n"Choice2") || Equals(name, n"Choice3")
        || Equals(name, n"Choice4") || Equals(name, n"ChoiceApply");
}

func AiNpcCallInteractionBlackboard() -> ref<IBlackboard> {
    return GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
}

func AiNpcCallChoice(action: CName, label: String) -> InteractionChoiceData {
    let choice: InteractionChoiceData;
    choice.localizedName = label;
    choice.inputAction = action;

    let kind: ChoiceTypeWrapper;
    ChoiceTypeWrapper.SetType(kind, gameinteractionsChoiceType.Blueline);
    choice.type = kind;
    return choice;
}

// Ce que le hub montre pour nous, s'il le montre encore. Le reste appartient a qui l'a mis.
func AiNpcCallChoicesShown() -> Bool {
    let board = AiNpcCallInteractionBlackboard();
    if !IsDefined(board) {
        return false;
    }
    let hub: InteractionChoiceHubData = FromVariant(
        board.GetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub));
    if !hub.active {
        return false;
    }

    let i = 0;
    let count = ArraySize(hub.choices);
    while i < count {
        if AiNpcCallOwnsChoice(hub.choices[i]) {
            return true;
        }
        i += 1;
    }
    return false;
}

func AiNpcCallOwnsChoice(choice: InteractionChoiceData) -> Bool {
    return Equals(choice.inputAction, AiNpcCallReplyAction())
        || Equals(choice.inputAction, AiNpcCallHangUpAction());
}

// Ce qui reste du hub une fois nos lignes retirees. Rendu plutot que modifie sur place :
// l'affichage et l'effacement en ont tous les deux besoin, et pour la meme raison.
func AiNpcCallWithoutOurs(choices: array<InteractionChoiceData>) -> array<InteractionChoiceData> {
    let kept: array<InteractionChoiceData>;
    let i = 0;
    let count = ArraySize(choices);
    while i < count {
        if !AiNpcCallOwnsChoice(choices[i]) {
            ArrayPush(kept, choices[i]);
        }
        i += 1;
    }
    return kept;
}

// Pose nos deux lignes dans le hub, en gardant celles des autres. Idempotent : appelee a
// chaque reaffirmation, elle remplace les notres au lieu de les empiler.
func AiNpcCallShowChoices(replyLabel: String, hangUpLabel: String) -> Void {
    let board = AiNpcCallInteractionBlackboard();
    if !IsDefined(board) {
        return;
    }

    let hub: InteractionChoiceHubData = FromVariant(
        board.GetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub));
    let others = AiNpcCallWithoutOurs(hub.choices);

    hub.choices = others;
    hub.active = true;
    ArrayPush(hub.choices, AiNpcCallChoice(AiNpcCallReplyAction(), replyLabel));
    ArrayPush(hub.choices, AiNpcCallChoice(AiNpcCallHangUpAction(), hangUpLabel));

    let visuals: VisualizersInfo;
    visuals.activeVisId = hub.id;
    visuals.visIds = [hub.id];

    board.SetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub, ToVariant(hub), true);
    board.SetVariant(GetAllBlackboardDefs().UIInteractions.VisualizersInfo, ToVariant(visuals), true);
}

// Retire nos deux lignes et laisse le reste. Appelee depuis chaque fin d'appel, y compris
// celles que personne n'a choisies.
//
// Le hub ne se desactive que s'il ne restait que nous : le desactiver alors qu'une porte est
// sous les yeux du joueur ferait disparaitre SON invite, et le jeu ne la redessinerait qu'au
// prochain changement de contexte.
func AiNpcCallHideChoices() -> Void {
    let board = AiNpcCallInteractionBlackboard();
    if !IsDefined(board) {
        return;
    }

    let hub: InteractionChoiceHubData = FromVariant(
        board.GetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub));
    let others = AiNpcCallWithoutOurs(hub.choices);

    hub.choices = others;
    hub.active = ArraySize(others) > 0;

    let visuals: VisualizersInfo;
    if hub.active {
        visuals.activeVisId = hub.id;
        visuals.visIds = [hub.id];
    }

    board.SetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub, ToVariant(hub), true);
    board.SetVariant(GetAllBlackboardDefs().UIInteractions.VisualizersInfo, ToVariant(visuals), true);
}
