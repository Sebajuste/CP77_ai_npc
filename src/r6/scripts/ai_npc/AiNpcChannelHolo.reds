// Le canal parlé : l'appel.
//
// Ce qui s'y dit ne doit pas apparaître comme un message écrit, et la mémoire reste partagée.
// Les deux exigences tirent en sens inverse, et ce fichier ne tranche que la première : la
// seconde est tenue par l'absence de découpage dans le store.

module AiNpc

class AiNpcChannelHolo extends AiNpcChannel {

    public func Id() -> AiNpcChannelId {
        return AiNpcChannelId.Call;
    }

    public func Name() -> String {
        return AiNpcHoloChannel();
    }

    public func IsSpoken() -> Bool {
        return true;
    }

    // Le fil écrit ne peint pas ce qui a été dit de vive voix. Une ligne d'appel y apparaîtra,
    // sans son contenu, et elle sera DÉRIVÉE de la suite des lignes parlées plutôt que stockée.
    public func ShowsInThread() -> Bool {
        return false;
    }

    // Personne ne l'a peinte ? Alors rien n'est poussé. La ligne est déjà classée, donc la
    // mémoire la garde.
    //
    // C'EST LA MOITIÉ QUI SERAIT UN DÉFAUT VISIBLE SI ON L'OUBLIAIT : un SMS de ce qu'un
    // personnage a dit à voix haute au téléphone. Un appel manqué est une notification d'un
    // autre genre et appartient au système d'appel, pas ici -- il peut attendre, précisément
    // parce que ce silence-ci est muet et non faux.
    public func Deliver(contactId: String, text: String) -> Void {
        if AiNpcPublishReply(contactId, text, this.Id()) {
            return;
        }
        AiNpcLog(s"'\(contactId)' a parlé et l'appel n'est plus là. La ligne est classée, rien n'est poussé.");
    }

    // Ce qu'un modèle écrit et qu'une voix ne peut pas dire.
    //
    // Les didascalies sont le défaut de qualité le plus rapporté par les joueurs de Mantella :
    // une narration entre astérisques ou entre crochets, lue à voix haute. Le prompt le demande
    // déjà ; une demande n'est pas une garantie, et c'est ici qu'est la garantie.
    //
    // Les emoji ne sont PAS retirés ici, et c'est délibéré : la règle FORM du prompt les interdit
    // déjà pour toutes les surfaces, faute de pouvoir les afficher. Écrire un second filtre
    // approximatif contre eux coûterait plus qu'il ne rapporte.
    public func Clean(text: String) -> String {
        return AiNpcStripNarration(text);
    }
}

// Retire ce qui est encadré par des astérisques ou des crochets, et referme l'espace laissé.
//
// Une seule passe, sans récursion : on recopie ce qui est hors d'un encadrement, et un
// encadrement jamais refermé est recopié tel quel -- une astérisque isolée dans une phrase est
// de la ponctuation, pas une didascalie ouverte.
func AiNpcStripNarration(text: String) -> String {
    let out = "";
    let pending = "";
    let opener = "";

    let i = 0;
    let count = StrLen(text);
    while i < count {
        let c = StrMid(text, i, 1);

        if Equals(StrLen(opener), 0) {
            if Equals(c, "*") || Equals(c, "[") {
                opener = c;
                pending = c;
            } else {
                out += c;
            }
        } else {
            pending += c;
            let closes = Equals(opener, "*") && Equals(c, "*");
            if Equals(opener, "[") && Equals(c, "]") {
                closes = true;
            }
            if closes {
                opener = "";
                pending = "";
            }
        }
        i += 1;
    }

    // Un encadrement ouvert et jamais refermé : le texte est rendu, pas mangé.
    out += pending;
    return AiNpcTrimTrailingSpaces(AiNpcCollapseSpaces(out));
}


// Une didascalie en fin de phrase laisse l'espace qui la precedait. AiNpcCollapseSpaces, elle,
// est celle d'AiNpcText : refermer le trou laisse par un morceau coupe au milieu d'une phrase
// est exactement le meme besoin que pour une commande, et deux copies seraient deux fonctions
// a garder d'accord.
func AiNpcTrimTrailingSpaces(text: String) -> String {
    let end = StrLen(text);
    while end > 0 && Equals(StrMid(text, end - 1, 1), " ") {
        end -= 1;
    }
    return StrLeft(text, end);
}
