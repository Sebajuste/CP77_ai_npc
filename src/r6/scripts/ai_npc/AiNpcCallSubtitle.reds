// Ce que le personnage dit, ecrit en bas de l'ecran pendant l'appel.
//
// On emprunte la voie du jeu plutot que de dessiner : le tableau noir UIGameData porte
// `ShowDialogLine` (un tableau de `scnDialogLineData`) et `HideDialogLine` (un tableau de
// `CRUID`), et c'est SubtitlesGameController qui peint -- avec la police, la place et le
// reglage d'affichage du joueur. Un mod qui redessine perd les trois.
//
// LA DUREE N'EFFACE RIEN TOUTE SEULE. Le champ `duration` decrit la ligne, il ne la retire pas :
// sans un `HideDialogLine` explicite, le sous-titre reste a l'ecran indefiniment -- y compris
// apres la fin de l'appel. D'ou le minuteur ci-dessous. Le montage est celui d'Audioware
// (Codeware.reds PropagateSubtitle + Callback.reds HideSubtitleCallback), qui est
// l'implementation de reference verifiee sur cette machine.
//
// TYPE : `Regular`, le sous-titre du bas. `scnDialogLineType.Holocall` existe aussi -- mesure au
// compilateur le 2026-09-03, contre le bundle vanilla, en meme temps que Radio, OverHead et
// Invisible ; Thought, Phone, GlobalTV et HolocallSmall, eux, n'existent pas. Holocall est le
// type que le jeu emploie pour ses propres appels, mais il peint dans le panneau d'appel
// vanilla, que cet appel-ci n'a pas. Regular est celui qu'un mod installe fait deja apparaitre.
//
// L'IDENTIFIANT est laisse a sa valeur par defaut : le vanilla ne sait pas construire un CRUID
// (`CreateCRUID` est un natif Codeware). C'est sans consequence tant qu'une seule ligne a nous
// est a l'ecran, ce que le remplacement ci-dessous garantit -- et c'est ce qui rend le numero de
// serie du minuteur indispensable.

module AiNpc

// Combien de temps une replique reste lisible.
//
// Estimee sur le texte, faute de mieux : la voie parlee ne rend pas la duree de ce qu'elle
// synthetise, et le sous-titre ne peut donc pas suivre la voix a la milliseconde. Quinze
// caracteres par seconde est le debit d'une phrase parlee tranquillement, et les deux secondes
// de tete couvrent le silence entre l'envoi et le premier son.
func AiNpcSubtitleSeconds(text: String) -> Float {
    let seconds = 2.0 + Cast<Float>(StrLen(text)) / 15.0;
    if seconds > 20.0 {
        return 20.0;
    }
    return seconds;
}

class AiNpcSubtitleHideCallback extends AiNpcSubtitleLaneCallback {
    public let serial: Int32;

    protected func Run(subtitles: ref<AiNpcCallSubtitles>) -> Void {
        subtitles.OnExpired(this.serial);
    }
}

// La ligne affichee, et une seule a la fois.
//
// Deliberement : deux repliques empilees seraient deux choses a lire en meme temps, et une
// reponse arrive ici phrase par phrase. La nouvelle remplace la precedente, ce qui garde l'etat
// trivial -- une ligne, un minuteur.
public class AiNpcCallSubtitles extends ScriptableSystem {

    private let m_line: scnDialogLineData;
    private let m_shown: Bool = false;

    // Un minuteur ne s'annule pas toujours a temps : arme sur la ligne d'avant, il peut echoir
    // une image apres que la suivante est apparue et l'effacer sans le savoir. Chaque minuteur
    // porte donc le numero de la ligne qui l'a arme, et un numero perime ne fait rien.
    private let m_serial: Int32 = 0;
    private let m_delay: DelayID;

    public static func Get() -> ref<AiNpcCallSubtitles> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
            .Get(NameOf<AiNpcCallSubtitles>()) as AiNpcCallSubtitles;
    }

    // Affiche une replique sous le nom du personnage. Sans effet sur une chaine vide.
    public func Show(speakerName: String, text: String) -> Void {
        if Equals(StrLen(text), 0) {
            return;
        }

        let board = GameInstance.GetBlackboardSystem(this.GetGameInstance())
            .Get(GetAllBlackboardDefs().UIGameData);
        if !IsDefined(board) {
            return;
        }

        this.Clear();
        this.m_serial += 1;

        let seconds = AiNpcSubtitleSeconds(text);

        let line: scnDialogLineData;
        line.text = text;
        // Le porteur de la ligne, pas celui qu'on lit : le personnage n'est pas dans le monde
        // pendant un appel, et un sous-titre du bas s'annonce par son nom, pas par son entite.
        line.speaker = GetPlayer(this.GetGameInstance());
        line.speakerName = speakerName;
        line.duration = seconds;
        line.isPersistent = false;
        line.type = scnDialogLineType.Regular;

        board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant([line]), true);
        this.m_line = line;
        this.m_shown = true;

        let callback = new AiNpcSubtitleHideCallback();
        callback.serial = this.m_serial;
        this.m_delay = GameInstance.GetDelaySystem(this.GetGameInstance())
            .DelayCallback(callback, seconds);
    }

    // Retire la ligne affichee, s'il y en a une, et desarme son minuteur. Idempotent : appelable
    // a la fin d'un appel sans rien savoir de l'etat.
    public func Clear() -> Void {
        if !this.m_shown {
            return;
        }
        GameInstance.GetDelaySystem(this.GetGameInstance()).CancelCallback(this.m_delay);
        this.m_delay = GetInvalidDelayID();
        this.Hide();
    }

    public func OnExpired(serial: Int32) -> Void {
        if NotEquals(serial, this.m_serial) {
            return;
        }
        this.m_delay = GetInvalidDelayID();
        this.Hide();
    }

    private func Hide() -> Void {
        if !this.m_shown {
            return;
        }
        this.m_shown = false;

        let board = GameInstance.GetBlackboardSystem(this.GetGameInstance())
            .Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine,
                ToVariant([this.m_line.id]), true);
        }
    }
}
