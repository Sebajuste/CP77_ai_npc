// Ce que le personnage dit, ecrit en bas de l'ecran pendant qu'on l'entend.
//
// On emprunte la voie du jeu plutot que de dessiner : le tableau noir UIGameData porte
// `ShowDialogLine` (un tableau de `scnDialogLineData`) et `HideDialogLine` (un tableau de
// `CRUID`), et c'est SubtitlesGameController qui peint -- avec la police, la place et le
// reglage d'affichage du joueur. Un mod qui redessine perd les trois.
//
// LE SOUS-TITRE EST UNE VUE DE LA FILE DE PAROLE, ET C'EST TOUTE L'ARCHITECTURE. Une reponse
// arrive phrase par phrase ; la file les joue dans l'ordre, donc au moment ou la troisieme est
// envoyee, c'est la premiere qu'on entend. Afficher ce qu'on vient d'envoyer affiche la
// mauvaise -- on ne voyait que la derniere phrase pendant que la premiere se jouait. Estimer une
// duree ne rattrape rien : l'erreur s'ajoute a chaque phrase.
//
// Donc rien n'est estime et rien n'est chronometre ici. `AiNpcAudio.Speaking()` rend le texte du
// morceau que le peripherique n'a pas encore joue -- ce qui sort du haut-parleur, par
// construction -- et cet ecran affiche ca. Quand la file se tait, la ligne s'en va.
//
// LA DUREE N'EFFACE RIEN TOUTE SEULE. Le champ `duration` decrit la ligne, il ne la retire pas :
// sans un `HideDialogLine` explicite, le sous-titre reste a l'ecran indefiniment. Il est donne
// large et c'est la file qui decide, pas lui.
//
// TYPE : `Regular`, le sous-titre du bas. `scnDialogLineType.Holocall` existe aussi -- mesure au
// compilateur le 2026-09-03, contre le bundle vanilla, en meme temps que Radio, OverHead et
// Invisible ; Thought, Phone, GlobalTV et HolocallSmall, eux, n'existent pas. Holocall est le
// type que le jeu emploie pour ses propres appels, mais il peint dans le panneau d'appel
// vanilla, que cet appel-ci n'a pas. Regular est celui qu'un mod installe fait deja apparaitre.
//
// L'IDENTIFIANT est laisse a sa valeur par defaut : le vanilla ne sait pas construire un CRUID
// (`CreateCRUID` est un natif Codeware). Toutes nos lignes portent donc LE MEME, et c'est ce qui
// oblige a retirer la precedente avant de poser la suivante : posee par-dessus, le controleur la
// lit comme la ligne deja affichee et garde la premiere. Mesure en jeu le 2026-09-03 -- seul le
// texte initial restait, alors que la file annoncait bien la suite. NCSH_Speech.reds fait le
// meme retrait, pour la meme raison, et c'est de la que vient le patron.

module AiNpc

// A quelle cadence on demande a la file ce qu'elle joue.
//
// C'est le retard maximum entre le premier mot d'une phrase et son apparition. Un dixieme de
// seconde ne se voit pas ; la question est la lecture d'un entier sous un verrou deja pris.
func AiNpcSubtitleFollowSeconds() -> Float {
    return 0.1;
}

// Combien de temps le jeu garde la ligne si personne ne la retire.
//
// Un filet, pas une horloge : la file retire la ligne des qu'elle passe a la suivante. Ce
// nombre ne sert que si la voie parlee meurt en cours de replique.
func AiNpcSubtitleMaxSeconds() -> Float {
    return 30.0;
}

class AiNpcSubtitleFollowCallback extends AiNpcSubtitleLaneCallback {
    protected func Run(subtitles: ref<AiNpcCallSubtitles>) -> Void {
        subtitles.OnFollowTick();
    }
}

// La ligne affichee, et une seule a la fois.
//
// Deliberement : deux repliques empilees seraient deux choses a lire en meme temps, et une
// reponse arrive ici phrase par phrase. La nouvelle remplace la precedente, ce qui garde l'etat
// trivial -- une ligne, et le texte qu'elle porte.
public class AiNpcCallSubtitles extends ScriptableSystem {

    private let m_line: scnDialogLineData;
    private let m_speakerName: String = "";
    private let m_shown: String = "";
    private let m_following: Bool = false;

    public static func Get() -> ref<AiNpcCallSubtitles> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcCallSubtitles>()) as AiNpcCallSubtitles;
    }

    // Commence a suivre la parole, sous ce nom. Appelee au decrochage : le nom ne change pas
    // pendant un appel, et le texte, lui, vient de la file a chaque tour.
    public func Follow(speakerName: String) -> Void {
        this.m_speakerName = speakerName;
        if this.m_following {
            return;
        }
        this.m_following = true;
        this.Arm();
    }

    public func IsShowing(text: String) -> Bool {
        return NotEquals(StrLen(text), 0) && Equals(this.m_shown, text);
    }

    // Arrete de suivre et retire ce qui restait. Idempotent.
    public func Release() -> Void {
        this.m_following = false;
        this.m_speakerName = "";
        this.Hide();
    }

    public func OnFollowTick() -> Void {
        if !this.m_following {
            return;
        }

        let saying = AiNpcAudio.Speaking();
        if NotEquals(saying, this.m_shown) {
            AiNpcLog(s"Subtitle: the speaker moved to '\(saying)'.");
            if Equals(StrLen(saying), 0) {
                this.Hide();
            } else {
                this.Paint(saying);
            }
        }
        this.Arm();
    }

    private func Arm() -> Void {
        AiNpcArmTimeout(new AiNpcSubtitleFollowCallback(), AiNpcSubtitleFollowSeconds());
    }

    private func Paint(text: String) -> Void {
        let board = GameInstance.GetBlackboardSystem(this.GetGameInstance())
            .Get(GetAllBlackboardDefs().UIGameData);
        if !IsDefined(board) {
            return;
        }

        // La precedente s'en va avant que la suivante arrive : elles partagent un identifiant.
        this.Hide();

        let line: scnDialogLineData;
        line.text = text;
        // Le porteur de la ligne, pas celui qu'on lit : le personnage n'est pas dans le monde
        // pendant un appel, et un sous-titre du bas s'annonce par son nom, pas par son entite.
        line.speaker = GetPlayer(this.GetGameInstance());
        line.speakerName = this.m_speakerName;
        line.duration = AiNpcSubtitleMaxSeconds();
        line.isPersistent = false;
        line.type = scnDialogLineType.Regular;

        board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant([line]), true);
        this.m_line = line;
        this.m_shown = text;
    }

    private func Hide() -> Void {
        if Equals(StrLen(this.m_shown), 0) {
            return;
        }
        this.m_shown = "";

        let board = GameInstance.GetBlackboardSystem(this.GetGameInstance())
            .Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine,
                ToVariant([this.m_line.id]), true);
        }
    }
}
