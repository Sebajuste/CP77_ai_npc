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
// THE HUB IS SHARED. Every source of interactions writes into the same value, so a call must
// clear what it added when it ends -- an option left behind is a prompt on screen with nothing
// to answer it.

module AiNpc

// Choice1 and Choice2 are the game's own dialogue-choice actions, declared in
// r6\config\inputUserMappings.xml (Choice1 through Choice4). Using them means the prompt shows
// the key the player has bound for dialogue, whatever that is.
func AiNpcCallWriteAction() -> CName {
    return n"Choice1";
}

func AiNpcCallHangUpAction() -> CName {
    return n"Choice2";
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

// Replaces whatever the hub was showing. A call takes the screen, so it takes the prompts with
// it; restoring what was there is the game's business when the hub is next rebuilt.
func AiNpcCallShowChoices(writeLabel: String, hangUpLabel: String) -> Void {
    let board = AiNpcCallInteractionBlackboard();
    if !IsDefined(board) {
        return;
    }

    let hub: InteractionChoiceHubData;
    hub.active = true;
    ArrayPush(hub.choices, AiNpcCallChoice(AiNpcCallWriteAction(), writeLabel));
    ArrayPush(hub.choices, AiNpcCallChoice(AiNpcCallHangUpAction(), hangUpLabel));

    let visuals: VisualizersInfo;
    visuals.activeVisId = hub.id;
    visuals.visIds = [hub.id];

    board.SetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub, ToVariant(hub), true);
    board.SetVariant(GetAllBlackboardDefs().UIInteractions.VisualizersInfo, ToVariant(visuals), true);
}

// An empty, inactive hub: the prompts go away. Called from every ending, including the ones
// nobody chose.
func AiNpcCallHideChoices() -> Void {
    let board = AiNpcCallInteractionBlackboard();
    if !IsDefined(board) {
        return;
    }

    let hub: InteractionChoiceHubData;
    hub.active = false;

    let visuals: VisualizersInfo;

    board.SetVariant(GetAllBlackboardDefs().UIInteractions.InteractionChoiceHub, ToVariant(hub), true);
    board.SetVariant(GetAllBlackboardDefs().UIInteractions.VisualizersInfo, ToVariant(visuals), true);
}
