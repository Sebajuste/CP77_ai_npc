// The call, as a machine. What state it is in, what moves it, and the one moment that opens a
// conversation.
//
// The decisions are not here -- they are in AiNpcCallState.reds, pure, so the suite can run
// them before any system exists. What is here is the reaching: the timers, the contact it is
// addressed to, and the single crossing of AiNpcChatDoor.
//
// A ScriptableSystem rather than a service: a call belongs to a playthrough, and nothing about
// it may outlive one. Nothing is persistent, so a save taken mid-call reloads Idle.
//
// It draws nothing. A surface for the call is step 4 of docs/PLAN_HOLO_LANE.md, and the point
// of arriving at it in this order is that the door discipline below is proven before a widget
// can hide it.

module AiNpc

// How long the ringing lasts on each side. Named rather than inline: they are the two numbers
// a play session will want to argue about, and finding them should not need reading the
// machine.
func AiNpcCallDialSeconds() -> Float {
    return 1.5;
}

// Long enough for a person to answer. The first value tried was 8 seconds, and a hand driving
// four buttons in a debug window missed it on the first attempt -- which is roughly what a
// player reaching for a ringing phone does.
//
// It is the BACKSTOP now, not the schedule: a call is answered when the voice is ready, and
// this is what happens when it never is.
func AiNpcCallRingSeconds() -> Float {
    return 20.0;
}

// Combien de fois par seconde on demande a la voix ou elle en est.
//
// Assez souvent pour que le decroche suive la fin du chargement plutot que de l'arrondir, assez
// rarement pour qu'une sonnerie de vingt secondes coute quarante questions et non deux mille.
// La reponse est un mot lu sous un verrou deja pris ; elle ne coute rien.
func AiNpcCallPickUpPollSeconds() -> Float {
    return 0.5;
}

// A quelle cadence on verifie que nos deux invites sont toujours a l'ecran.
//
// Le jeu reconstruit le hub d'interaction a chaque changement de contexte du joueur, et emporte
// ce qu'il n'a pas mis. Une demi-seconde est la plus longue absence qu'on accepte de laisser
// voir ; la verification est une lecture de tableau noir et ne coute rien.
func AiNpcCallChoicesPollSeconds() -> Float {
    return 0.5;
}

// Depuis quand ce contact est en ligne, zero s'il ne l'est pas.
//
// Pose ici plutot que sur la classe parce que les lecteurs sont des surfaces : un fil ecrit
// demande cela du contact qu'il affiche, et la reponse doit etre zero pour tous les autres --
// un appel avec Judy ne suspend pas la trace d'un appel termine avec Panam.
func AiNpcLiveCallSince(contactId: String) -> Int32 {
    let call = AiNpcCallSystem.Get();
    if !IsDefined(call) || NotEquals(call.State(), AiNpcCallState.Connected) {
        return 0;
    }
    if NotEquals(call.ContactId(), contactId) {
        return 0;
    }
    return call.ConnectedAt();
}

// Les deux invites d'un appel du mod. Les mots appartiennent à cette voie, le hub est un
// mécanisme.
func AiNpcCallShowOurChoices() -> Void {
    let language = AiNpcResolveLanguage();
    AiNpcCallShowChoices(AiNpcCallReplyLabel(language), AiNpcCallHangUpLabel(language));
}

// À quelle cadence on demande si la réponse du modèle est finie, requête et voix comprises.
func AiNpcCallTurnPollSeconds() -> Float {
    return 0.5;
}


public class AiNpcCallSystem extends ScriptableSystem {

    private let m_state: AiNpcCallState = AiNpcCallState.Idle;
    private let m_contactId: String = "";

    // Every timer carries the serial it was armed under, and a timer whose serial has moved on
    // does nothing. A DelaySystem timer cannot be cancelled, so hanging up and calling again
    // inside the ring window would otherwise let the FIRST call's timeout end the second one.
    private let m_serial: Int32 = 0;

    // L'instant ou l'on a decroche, en secondes de jeu absolues.
    //
    // LA BORNE DE L'ECHANGE EN COURS. Le prompt d'un appel ne porte que ce qui s'est dit depuis
    // ici : l'appel d'avant appartient a la memoire, pas a celui-ci. Rien n'est persistant dans
    // cette classe, donc une sauvegarde reprise hors appel n'a pas de borne a relire -- et n'en
    // a pas besoin, puisqu'il n'y a pas d'appel en cours.
    private let m_connectedAt: Int32 = 0;

    // The one line V speaks into. Built on demand and dropped with the call: it holds widgets,
    // so it cannot outlive the HUD that hosts them.
    private let m_input: ref<AiNpcHoloInput>;

    private let m_origin: AiNpcCallOrigin = AiNpcCallOrigin.Ours;

    // Le tour de parole d'un appel du jeu. Sans objet sur un appel du mod.
    private let m_turn: AiNpcHoloTurn = AiNpcHoloTurn.Scene;
    private let m_replyHint: ref<AiNpcHoloReplyHint>;

    public static func Get() -> ref<AiNpcCallSystem> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcCallSystem>()) as AiNpcCallSystem;
    }

    public func State() -> AiNpcCallState {
        return this.m_state;
    }

    public func ContactId() -> String {
        return this.m_contactId;
    }

    // What the window shows: the state, and who it is with.
    public func Describe() -> String {
        if Equals(StrLen(this.m_contactId), 0) {
            return AiNpcCallStateLabel(this.m_state);
        }
        return s"\(AiNpcCallStateLabel(this.m_state)) -- \(this.m_contactId)";
    }

    /// The player's verbs ///

    // Place a call. Answers what happened, so a caller shows one sentence rather than deciding
    // what a refusal means.
    public func Dial(contactId: String) -> String {
        if Equals(StrLen(contactId), 0) {
            return "Refused: a call needs a contact.";
        }
        // The previous call's ending is cleared here and nowhere else: it stays on screen until
        // it is in the way, which is the only moment it stops being worth reading.
        if AiNpcCallIsOver(this.m_state) {
            this.Enter(AiNpcCallState.Idle);
        }
        if !AiNpcCallMayGo(this.m_state, AiNpcCallState.Dialing) {
            return s"Refused: already \(AiNpcCallStateLabel(this.m_state)).";
        }
        if !AiNpcIsContactSupported(contactId) {
            return s"Refused: '\(contactId)' is not a contact this mod can talk to.";
        }

        this.m_contactId = contactId;
        this.m_origin = AiNpcCallOrigin.Ours;
        this.Enter(AiNpcCallState.Dialing);
        AiNpcArmTimeout(AiNpcCallTickCallback.Create(this.m_serial, AiNpcCallState.Ringing),
            AiNpcCallDialSeconds());
        return s"Dialing \(contactId)...";
    }

    // The character picks up. In this step it is the player who decides, from the window; a
    // character deciding for itself is a later question and does not change the transition.
    public func PickUp() -> String {
        return this.Move(AiNpcCallState.Connected);
    }

    // Never got through.
    public func Decline() -> String {
        return this.Move(AiNpcCallState.Refused);
    }

    // Over, whether it was answered or not.
    public func HangUp() -> String {
        return this.Move(AiNpcCallState.Ended);
    }

    /// The machine ///

    // The one door every transition goes through, so the table in AiNpcCallState is the only
    // thing that decides, and every entry into a state does its work exactly once.
    private func Move(to: AiNpcCallState) -> String {
        if !AiNpcCallMayGo(this.m_state, to) {
            return s"Refused: \(AiNpcCallStateLabel(this.m_state)) does not go to \(AiNpcCallStateLabel(to)).";
        }
        this.Enter(to);
        return this.Describe();
    }

    private func Enter(to: AiNpcCallState) -> Void {
        let from = this.m_state;
        let contactId = this.m_contactId;

        // Bumped on EVERY entry, so any timer armed under the old state is already stale.
        this.m_serial += 1;
        this.m_state = to;
        AiNpcLog(s"Call: \(AiNpcCallStateLabel(from)) -> \(AiNpcCallStateLabel(to)) ('\(contactId)').");

        // The call the player sees is the game's own, asked for once. Picking up does not ask
        // again: the vanilla call is already up, and answering only stops the ring and offers
        // the two choices. Nothing is drawn here.
        if Equals(to, AiNpcCallState.Ringing) {
            // LA SONNERIE EST LE CHARGEMENT, et c'est tout l'interet de la placer ici.
            //
            // Preparer une voix coute environ sept secondes -- charger le modele, tailler la
            // reference dans les archives du joueur, la cloner -- et rien de cela ne depend de
            // ce qui sera dit. Faire sonner pendant est la seule facon de ne pas faire attendre
            // apres : le joueur entend un telephone, pas une barre de progression.
            AiNpcAudio.Warm(contactId, AiNpcVoiceFileFor(contactId),
                AiNpcVoiceFallbackFor(contactId), AiNpcVoiceOverLocale());
            AiNpcVanillaCallStart(contactId);
            AiNpcArmTimeout(AiNpcCallRingCallback.Create(this.m_serial), AiNpcVanillaRingDelay());
            AiNpcArmTimeout(AiNpcCallPickUpCallback.Create(this.m_serial),
                AiNpcCallPickUpPollSeconds());
            AiNpcArmTimeout(AiNpcCallTickCallback.Create(this.m_serial, AiNpcCallState.Missed),
                AiNpcCallRingSeconds());
        }

        if Equals(to, AiNpcCallState.Connected) {
            this.m_connectedAt = AiNpcGetCurrentGameTimeSeconds();
            // Un appel du jeu a sa scène et ses choix ; seul le nôtre sonne et offre les siens.
            if Equals(this.m_origin, AiNpcCallOrigin.Ours) {
                AiNpcVanillaRingStop();
                // Le declic que le jeu joue quand un appel est accepte. Sans lui la tonalite
                // s'arrete et rien ne dit que quelqu'un a decroche -- ce que le joueur lit comme
                // un appel qui a rate, pas comme un appel qui commence.
                AiNpcVanillaCallAnswered();
                AiNpcCallShowOurChoices();
                AiNpcArmTimeout(AiNpcCallChoicesCallback.Create(this.m_serial),
                    AiNpcCallChoicesPollSeconds());
            }

            // Lu autant qu'entendu. Le sous-titre suit la file de parole et non les envois :
            // il n'a besoin que du nom, et prend le texte a la source a chaque tour.
            let subtitles = AiNpcCallSubtitles.Get();
            if IsDefined(subtitles) {
                subtitles.Follow(AiNpcGetCharacterName(contactId));
            }
        }

        // Un appel termine ne parle plus. Ici plutot que sur le seul raccroche du joueur : un
        // appel manque, une coupure et un raccroche laissent la meme voix en train de dire une
        // phrase a une ligne fermee.
        if AiNpcCallIsOver(to) {
            AiNpcAudio.Silence();
            let ending = AiNpcCallSubtitles.Get();
            if IsDefined(ending) {
                ending.Release();
            }
            this.HideInput();
            this.EndTurn();
        }

        // Every ending of OUR call closes the game's call, including the ones nobody answered --
        // a portrait left ringing after a missed call is the failure this line exists to
        // prevent. A call of the game's is closed by its scene.
        if AiNpcCallIsOver(to) && Equals(this.m_origin, AiNpcCallOrigin.Ours) {
            AiNpcVanillaRingStop();
            AiNpcCallHideChoices();
            AiNpcVanillaCallEnd(contactId);
        }

        // THE CROSSING. Asked of the pure function and not re-derived here, because "a call
        // that was never picked up opens no conversation" is the whole subject of this step.
        if AiNpcCallConnects(from, to) {
            this.OpenConversation(contactId);
        }

        // An ending is NOT collapsed here. It stays, with the contact it was about, so the
        // window says "missed -- judy" rather than an idle nobody can explain. Dial clears it.
        if Equals(to, AiNpcCallState.Idle) {
            this.m_contactId = "";
        }
    }

    // AN ANSWERED CALL DOES NOT OPEN THE WRITTEN THREAD, and the temptation to make it do so
    // is why this is a named function with a comment rather than one line.
    //
    // A call is spoken. docs/PLAN_HOLO_CHANNEL.md is the whole argument: what is said on a call
    // must not appear as a written message, while the memory stays shared. Opening the SMS
    // thread here would be the exact defect that document exists to prevent -- and it would
    // look like it worked, which is worse.
    //
    // Crossing AiNpcChatDoor needs a session, and the session a call opens is the holo's. It
    // does not exist yet: the channel is step 0 and the surface is step 4. So this step proves
    // the machine and the timers, and the crossing is deliberately absent rather than faked
    // through the phone.
    private func OpenConversation(contactId: String) -> Void {
        AiNpcLog(s"Call connected to '\(contactId)'. No written conversation is opened: a call is spoken.");
    }

    // A game action, offered by the player's action hook. True means the call took it: the hook
    // consumes it, and the game never acts on it.
    public func ReportAction(name: CName, kind: gameinputActionType) -> Bool {
        if AiNpcIsChoiceAction(name) && this.KeepsChoiceInput() {
            return true;
        }
        if !Equals(name, AiNpcCallReplyAction()) || !this.OffersReply() {
            return false;
        }
        if Equals(kind, gameinputActionType.BUTTON_RELEASED) {
            this.ShowInput();
        }
        return true;
    }

    // Measured in game: Enter in the line committed the game's dialogue choice. While the line
    // holds the keyboard every choice action is a keystroke, and while the game's choices are
    // hidden there is nothing on screen for the player to commit.
    private func KeepsChoiceInput() -> Bool {
        if IsDefined(this.m_input) && this.m_input.HasKeyboard() {
            return true;
        }
        return Equals(this.m_origin, AiNpcCallOrigin.Game)
            && Equals(this.m_state, AiNpcCallState.Connected)
            && AiNpcHoloTurnHidesChoices(this.m_turn);
    }

    // R means something else at every other moment. On a call of the game's it opens the line
    // only before a choice that waits: the rest of the time the scene has the floor.
    private func OffersReply() -> Bool {
        if NotEquals(this.m_state, AiNpcCallState.Connected) {
            return false;
        }
        return Equals(this.m_origin, AiNpcCallOrigin.Ours) || AiNpcHoloTurnTakesReply(this.m_turn);
    }

    // The line gave the keyboard back. With no line said, the choice is the player's again.
    public func ReportTypingEnded() -> Void {
        if Equals(this.m_origin, AiNpcCallOrigin.Game) && Equals(this.m_state, AiNpcCallState.Connected) {
            this.ApplyTurn(AiNpcHoloTurnEvent.TypingDropped);
        }
    }

    // Hold T, offered by the phone controller's action hook. Only on a call the mod placed: a
    // call of the game's is hung up by its scene.
    public func ReportPhoneAction(name: CName, kind: gameinputActionType) -> Bool {
        if !Equals(name, AiNpcCallHangUpAction())
                || NotEquals(kind, gameinputActionType.BUTTON_HOLD_COMPLETE)
                || !AiNpcCallIsLive(this.m_state)
                || NotEquals(this.m_origin, AiNpcCallOrigin.Ours) {
            return false;
        }
        this.HangUp();
        return true;
    }

    // F on a contact row. True when the mod places the call itself.
    public func ReportCallRequested(contactId: String, vanillaCallable: Bool) -> Bool {
        let route = AiNpcCallRouteFor(AiNpcIsContactSupported(contactId), vanillaCallable);
        if NotEquals(route, AiNpcCallRoute.Ours) {
            return false;
        }
        AiNpcLog(s"F on '\(contactId)': \(this.Dial(contactId))");
        return true;
    }

    /// A call of the game's ///

    // The game's call information changed. A call the game placed to one of the mod's
    // characters is joined once picked up, and left when its scene hangs up.
    public func ReportPhoneCall(info: PhoneCallInformation) -> Void {
        let contactId = NameToString(info.contactName);
        switch info.callPhase {
            case questPhoneCallPhase.StartCall:
                this.Join(contactId);
                break;
            case questPhoneCallPhase.EndCall:
            case questPhoneCallPhase.Undefined:
                this.Leave(contactId);
                break;
            default:
                break;
        }
    }

    // The game's dialogue hub changed. True when its choices must not be shown.
    public func ReportDialogHubs(hubs: DialogChoiceHubs) -> Bool {
        if NotEquals(this.m_origin, AiNpcCallOrigin.Game)
                || NotEquals(this.m_state, AiNpcCallState.Connected) {
            return false;
        }
        this.ApplyTurn(AiNpcDialogHubEvent(hubs));
        return AiNpcHoloTurnHidesChoices(this.m_turn);
    }

    private func Join(contactId: String) -> Void {
        if !AiNpcCallMayJoin(this.m_state) || !AiNpcIsContactSupported(contactId) {
            return;
        }
        if AiNpcCallIsOver(this.m_state) {
            this.Enter(AiNpcCallState.Idle);
        }
        this.m_contactId = contactId;
        this.m_origin = AiNpcCallOrigin.Game;
        this.m_turn = AiNpcHoloTurn.Scene;
        AiNpcAudio.Warm(contactId, AiNpcVoiceFileFor(contactId),
            AiNpcVoiceFallbackFor(contactId), AiNpcVoiceOverLocale());
        this.Enter(AiNpcCallState.Connected);
    }

    // The scene hung up: the call is over, with no handover.
    private func Leave(contactId: String) -> Void {
        if NotEquals(this.m_origin, AiNpcCallOrigin.Game)
                || NotEquals(this.m_state, AiNpcCallState.Connected)
                || NotEquals(this.m_contactId, contactId) {
            return;
        }
        this.Move(AiNpcCallState.Ended);
    }

    private func ApplyTurn(event: AiNpcHoloTurnEvent) -> Void {
        let before = this.m_turn;
        let after = AiNpcHoloTurnAfter(before, event);
        if Equals(before, after) {
            return;
        }
        this.m_turn = after;
        AiNpcLog(s"Holo turn: \(before) -> \(after) ('\(this.m_contactId)').");
        this.ReplyHint().Show(AiNpcHoloTurnTakesReply(after));
        if NotEquals(AiNpcHoloTurnHidesChoices(before), AiNpcHoloTurnHidesChoices(after)) {
            AiNpcDialogHubRepaint();
        }
        if Equals(after, AiNpcHoloTurn.Model) {
            AiNpcArmTimeout(AiNpcCallTurnCallback.Create(this.m_serial), AiNpcCallTurnPollSeconds());
        }
    }

    // Whatever ends the call gives the game back its choices.
    private func EndTurn() -> Void {
        let masked = AiNpcHoloTurnHidesChoices(this.m_turn);
        this.m_turn = AiNpcHoloTurn.Scene;
        this.ReplyHint().Hide();
        if masked {
            AiNpcDialogHubRepaint();
        }
    }

    // A line the game shows on a call of its own: filed in the call's transcript as an ordinary
    // line, and logged with the turn it landed in -- how often the scene's waiting lines fall
    // while the player types or the model answers is still being measured.
    public func ReportDialogLine(line: scnDialogLineData) -> Void {
        if NotEquals(this.m_origin, AiNpcCallOrigin.Game)
                || NotEquals(this.m_state, AiNpcCallState.Connected) {
            return;
        }
        let subtitles = AiNpcCallSubtitles.Get();
        if IsDefined(subtitles) && subtitles.IsShowing(line.text) {
            return;
        }
        let overUs = AiNpcHoloTurnHidesChoices(this.m_turn);
        let filed = AiNpcFileSceneLine(this.m_contactId, line);
        AiNpcLog(s"Holo line during \(this.m_turn)\(overUs ? " (over our turn)" : ""): \(line.speakerName): '\(line.text)' [\(line.type), \(line.duration)s], \(filed ? "filed" : "not filed: empty or already in the thread").");
    }

    private func ReplyHint() -> ref<AiNpcHoloReplyHint> {
        if !IsDefined(this.m_replyHint) {
            this.m_replyHint = new AiNpcHoloReplyHint();
        }
        return this.m_replyHint;
    }

    // The model's turn ends when neither the request nor the voice has anything left.
    public func OnTurnTick(serial: Int32) -> Void {
        if NotEquals(serial, this.m_serial) || !Equals(this.m_turn, AiNpcHoloTurn.Model) {
            return;
        }
        if AiNpcIsGenerating() || NotEquals(StrLen(AiNpcAudio.Speaking()), 0) {
            AiNpcArmTimeout(AiNpcCallTurnCallback.Create(this.m_serial), AiNpcCallTurnPollSeconds());
            return;
        }
        this.ApplyTurn(AiNpcHoloTurnEvent.ModelDone);
    }

    // Escape, offered by the pause menu's own controller. True means the call took it and the
    // menu must not open.
    //
    // NOT ASKED OF THE PLAYER, and that is the whole of the defect this replaces: the player
    // object is an input listener for six gameplay actions, and OpenPauseMenu is not one of
    // them, so a branch reading it from PlayerPuppet.OnAction never ran once. The name it
    // compared -- OpenPauseMenu_Button -- is the key mapping's, not the action's, so it could
    // not have matched either.
    //
    // The release is the only half that matters: gameuiInGameMenuGameController spawns the menu
    // on BUTTON_RELEASED.
    public func ReportPauseAction(name: CName, kind: gameinputActionType) -> Bool {
        if !Equals(name, n"OpenPauseMenu")
                || NotEquals(kind, gameinputActionType.BUTTON_RELEASED)
                || !IsDefined(this.m_input) {
            return false;
        }

        // The line has already let go, because the key reached it as a key first.
        if this.m_input.TakeEscaped() {
            return true;
        }

        // It did not, so the field never saw the key -- it is still holding the keyboard, and
        // this is where it gives it back.
        if this.m_input.HasKeyboard() {
            this.m_input.DropFocus();
            return true;
        }

        return false;
    }

    // One line, over the call. Not a chat: the reply comes back on the call, and nothing that
    // is said here belongs in a written thread.
    private func ShowInput() -> Void {
        if !IsDefined(this.m_input) {
            this.m_input = new AiNpcHoloInput();
        }
        if !this.m_input.Show() {
            AiNpcLog("Call: no input line could be shown.");
            return;
        }
        if Equals(this.m_origin, AiNpcCallOrigin.Game) {
            this.ApplyTurn(AiNpcHoloTurnEvent.PlayerTyping);
        }
    }

    private func HideInput() -> Void {
        if IsDefined(this.m_input) {
            this.m_input.Hide();
        }
    }

    // Depuis quand l'echange en cours dure. Zero hors appel, ce qui ne laisse rien passer :
    // aucun prompt d'appel n'est construit sans appel.
    public func ConnectedAt() -> Int32 {
        return this.m_connectedAt;
    }

    // Ce que V a dit, depuis la ligne.
    //
    // ELLE PART AU MODELE, et c'est ce qui manquait : jusqu'ici cette fonction ne faisait que
    // synthetiser la ligne de V et la jouer -- ce qui eprouvait la voie parlee et n'ouvrait
    // aucune conversation. Un joueur voyait donc son propre texte relu, sans reponse et sans
    // rien de classe.
    //
    // La sequence appartient au canal, qui l'ecrit une fois pour toutes les surfaces : appeler
    // la voie, classer la ligne. Un appel n'a pas de session de chat -- elle porte le contact
    // affiche et l'echo dans la bulle, dont un appel n'a ni l'un ni l'autre -- donc il passe par
    // SendFrom, qui est la meme sequence sans la moitie qui peint.
    //
    // LA LIGNE DE V N'EST PLUS DITE. Elle l'etait pour eprouver le moteur avant qu'un modele
    // reponde, avec la voix de son interlocuteur faute de v.wav. Maintenant qu'une reponse
    // arrive, la dire serait nuisible et pas seulement etrange : la voie audio ne tient qu'une
    // voix a la fois, donc la premiere phrase de la reponse couperait la ligne de V au milieu.
    public func ReportSpoken(text: String) -> Void {
        if Equals(StrLen(text), 0) {
            return;
        }
        if NotEquals(this.m_state, AiNpcCallState.Connected) {
            return;
        }
        if Equals(this.m_origin, AiNpcCallOrigin.Game) {
            if !AiNpcHoloTurnAcceptsLine(this.m_turn) {
                AiNpcLog("Call: V's line is refused, the scene has the floor.");
                return;
            }
            this.ApplyTurn(AiNpcHoloTurnEvent.PlayerSpoke);
        }
        AiNpcLog(s"Call: V said '\(text)' to '\(this.m_contactId)'.");
        AiNpcAudio.Prime(AiNpcVoiceFileFor(this.m_contactId), AiNpcVoiceFallbackFor(this.m_contactId),
            AiNpcVoiceRateFor(this.m_contactId));
        AiNpcChannelOf(AiNpcChannelId.Call).SendFrom(this.m_contactId, text);
    }

    // One sentence of a reply, from AiNpcStreamDeliver -- the voice's only source, whatever lane
    // produced the reply.
    //
    // Spoken only on a connected call, and that is the whole of the policy: the written surfaces
    // are read, not heard, and a phone that started talking out loud while the player was texting
    // would be a bug with no way to turn it off.
    public func SpeakStreamed(text: String) -> Void {
        if NotEquals(this.m_state, AiNpcCallState.Connected) {
            return;
        }
        // Nettoyee par le canal avant d'etre dite, comme la replique complete l'est avant d'etre
        // classee. Les deux chemins passent par la meme fonction pure : n'en nettoyer qu'un
        // prononcerait la didascalie que l'autre a retiree.
        let spoken = AiNpcChannelOf(AiNpcChannelId.Call).Clean(text, AiNpcResolveLanguage());
        if Equals(StrLen(spoken), 0) {
            return;
        }
        AiNpcLog(s"Call: '\(this.m_contactId)' says '\(spoken)'. \(AiNpcAudio.Speak(spoken, this.m_contactId, AiNpcVoiceFileFor(this.m_contactId),
                 AiNpcVoiceFallbackFor(this.m_contactId), AiNpcVoiceOverLocale(), AiNpcVoiceRateFor(this.m_contactId)))");
    }

    // Le personnage decroche quand sa voix est prete, et pas avant.
    //
    // C'est ce qui remplace un delai fixe, et ce n'est pas cosmetique : un delai trop court fait
    // decrocher un personnage qui parlera ensuite avec la voix de Windows, un delai trop long
    // fait sonner dans le vide une machine qui etait prete depuis longtemps. L'evenement est le
    // bon signal parce que c'est exactement la chose qu'on attend.
    //
    // Trois reponses, trois conduites :
    //
    //   ready        on decroche
    //   unavailable  on decroche AUSSI, tout de suite -- il n'y a rien a attendre, et une
    //                installation sans pack ne doit pas sonner vingt secondes pour rien
    //   pending      on redemande
    //
    // "unknown" est traite comme "unavailable" : personne n'a demande cette voix, donc personne
    // ne la prepare, donc attendre serait attendre une chose qui n'arrivera pas.
    public func OnPickUpTick(serial: Int32) -> Void {
        if NotEquals(serial, this.m_serial) || NotEquals(this.m_state, AiNpcCallState.Ringing) {
            return;
        }
        if Equals(AiNpcAudio.VoiceState(this.m_contactId), "pending") {
            AiNpcArmTimeout(AiNpcCallPickUpCallback.Create(this.m_serial),
                AiNpcCallPickUpPollSeconds());
            return;
        }
        this.Move(AiNpcCallState.Connected);
    }

    // Nos invites, remises si le jeu les a emportees.
    //
    // La verification precede la reecriture : reecrire a chaque demi-seconde marcherait aussi,
    // et ecraserait a chaque fois l'interaction que le joueur vient d'obtenir en s'approchant
    // de quelque chose. On ne reprend la parole que quand on l'a perdue.
    public func OnChoicesTick(serial: Int32) -> Void {
        if NotEquals(serial, this.m_serial) || NotEquals(this.m_state, AiNpcCallState.Connected) {
            return;
        }
        if !AiNpcCallChoicesShown() {
            AiNpcCallShowOurChoices();
        }
        AiNpcArmTimeout(AiNpcCallChoicesCallback.Create(this.m_serial),
            AiNpcCallChoicesPollSeconds());
    }

    // The ring, armed late on purpose -- see the head of AiNpcCallVanilla.reds.
    public func OnRingTick(serial: Int32) -> Void {
        if NotEquals(serial, this.m_serial) || NotEquals(this.m_state, AiNpcCallState.Ringing) {
            return;
        }
        AiNpcVanillaRingStart();
    }

    // A timer that was armed under a serial this system has moved past. Doing nothing is the
    // whole of the correct behaviour.
    public func OnCallTick(serial: Int32, to: AiNpcCallState) -> Void {
        if NotEquals(serial, this.m_serial) {
            return;
        }
        this.Move(to);
    }
}

// The ring and the pickup window, each carrying the state it was armed to reach. One class for
// both, because what differs between them is data rather than behaviour.
class AiNpcCallRingCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnRingTick(this.serial);
    }

    public static func Create(serial: Int32) -> ref<AiNpcCallRingCallback> {
        let self = new AiNpcCallRingCallback();
        self.serial = serial;
        return self;
    }
}

class AiNpcCallPickUpCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnPickUpTick(this.serial);
    }

    public static func Create(serial: Int32) -> ref<AiNpcCallPickUpCallback> {
        let self = new AiNpcCallPickUpCallback();
        self.serial = serial;
        return self;
    }
}

class AiNpcCallChoicesCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnChoicesTick(this.serial);
    }

    public static func Create(serial: Int32) -> ref<AiNpcCallChoicesCallback> {
        let self = new AiNpcCallChoicesCallback();
        self.serial = serial;
        return self;
    }
}

class AiNpcCallTurnCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnTurnTick(this.serial);
    }

    public static func Create(serial: Int32) -> ref<AiNpcCallTurnCallback> {
        let self = new AiNpcCallTurnCallback();
        self.serial = serial;
        return self;
    }
}

class AiNpcCallTickCallback extends AiNpcCallLaneCallback {
    public let serial: Int32;
    public let to: AiNpcCallState;

    protected func Run(call: ref<AiNpcCallSystem>) -> Void {
        call.OnCallTick(this.serial, this.to);
    }

    public static func Create(serial: Int32, to: AiNpcCallState) -> ref<AiNpcCallTickCallback> {
        let self = new AiNpcCallTickCallback();
        self.serial = serial;
        self.to = to;
        return self;
    }
}
