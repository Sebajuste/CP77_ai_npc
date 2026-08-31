// UNE SONDE, PAS UNE FONCTIONNALITÉ. À supprimer quand elle aura répondu.
//
// Question unique : le holo s'ouvre sur un cadre vide, et rien dans les données ne dit qui
// devrait y être dessiné -- `holocallInitializerPath` est NULL même pour Songbird, qui a des
// holocalls en jeu. C'est donc la scène de quête qui y met un acteur en vanilla, et ce fichier
// mesure ce qu'un mod peut faire à la place.
//
// Quatre hypothèses, quatre boutons, un seul lancement. Chacune rend une phrase : ce que la
// sonde a trouvé, pas ce qu'elle espérait.
//
// Vérifié au compilateur le 2026-08-31 : `HudPhoneAvatarController` existe, et
// `StartHolocall`, `StartAudiocall`, `ShowIncomingContact`, `RefreshView` et `SetStatusText`
// sont appelables ; `EHudAvatarMode` n'a que `Holocall` et `Audiocall` ; `HolocallStartEvent`
// se construit. Ce qu'aucun compilateur ne dit, c'est si l'un d'eux remplit le cadre.

module AiNpc

// LA SEULE MARCHE DE L'ARBRE DU TÉLÉPHONE, et elle est itérative : une file et pas un appel
// récursif, comme l'exige la règle 3 de CLAUDE.md.
//
// Rend le premier contrôleur d'avatar trouvé, ou rien. Un arbre de widgets n'a pas de cycle,
// donc la file suffit : ce qui compte est de ne pas descendre en pile.
func AiNpcHoloFindAvatar(out description: String) -> ref<HudPhoneAvatarController> {
    let host = AiNpcHoloInputHost();
    if !IsDefined(host) {
        description = "aucun contrôleur de téléphone dans le HUD";
        return null;
    }

    let found: ref<HudPhoneAvatarController>;
    let seen: Int32 = 0;
    let named: String = "";

    let queue: array<ref<inkWidget>>;
    ArrayPush(queue, host);

    let at: Int32 = 0;
    while at < ArraySize(queue) {
        let widget = queue[at];
        at += 1;
        seen += 1;

        let controller = widget.GetController() as HudPhoneAvatarController;
        if IsDefined(controller) && !IsDefined(found) {
            found = controller;
            named = NameToString(widget.GetName());
        }

        let compound = widget as inkCompoundWidget;
        if IsDefined(compound) {
            let count = compound.GetNumChildren();
            let i: Int32 = 0;
            while i < count {
                let child = compound.GetWidgetByIndex(i);
                if IsDefined(child) {
                    ArrayPush(queue, child);
                }
                i += 1;
            }
        }
    }

    if IsDefined(found) {
        description = s"contrôleur d'avatar trouvé sur '\(named)', après \(seen) widget(s)";
    } else {
        description = s"aucun contrôleur d'avatar dans \(seen) widget(s)";
    }
    return found;
}

// Ce que l'arbre contient, à plat. La première chose à lire : si le contrôleur d'avatar n'est
// pas là, les trois autres hypothèses n'ont rien à quoi parler.
func AiNpcHoloProbeTree() -> String {
    let description: String;
    AiNpcHoloFindAvatar(description);
    AiNpcLog(s"Sonde holo -- arbre : \(description)");
    return description;
}

// Hypothèse 1 : demander au contrôleur de démarrer un holocall.
//
// `id` est un TweakDBID et on ne sait pas lequel il attend -- l'enregistrement de contact ou
// celui d'avatar. D'où un champ de saisie plutôt que deux boutons : `PhoneAvatars.Avatar_Judy`
// et `Contacts.judy` se testent à la main, et le log dit lequel a fait quelque chose.
func AiNpcHoloProbeStart(id: String, mode: String) -> String {
    let description: String;
    let avatar = AiNpcHoloFindAvatar(description);
    if !IsDefined(avatar) {
        return description;
    }

    let record = TDBID.Create(id);
    let name = "Judy";
    if Equals(mode, "audio") {
        avatar.StartAudiocall(record, name, false);
    } else {
        avatar.StartHolocall(record, name);
    }

    let answer = s"\(mode) demandé avec '\(id)'. \(description)";
    AiNpcLog(s"Sonde holo -- \(answer)");
    return answer;
}

// Hypothèse 2 : forcer le mode d'affichage plutôt que de démarrer un appel.
func AiNpcHoloProbeRefresh(id: String) -> String {
    let description: String;
    let avatar = AiNpcHoloFindAvatar(description);
    if !IsDefined(avatar) {
        return description;
    }

    avatar.RefreshView(TDBID.Create(id), "Judy", EHudAvatarMode.Holocall);
    let answer = s"RefreshView(Holocall) avec '\(id)'. \(description)";
    AiNpcLog(s"Sonde holo -- \(answer)");
    return answer;
}

// Hypothèse 3 : l'événement que le jeu se lance à lui-même. S'il porte sa propre logique de
// mise en scène, il n'a besoin d'aucun contrôleur.
func AiNpcHoloProbeEvent() -> String {
    let player = GetPlayer(GetGameInstance());
    if !IsDefined(player) {
        return "pas de joueur";
    }
    player.QueueEvent(new HolocallStartEvent());
    AiNpcLog("Sonde holo -- HolocallStartEvent envoyé au joueur.");
    return "HolocallStartEvent envoyé au joueur";
}

// Hypothèse 4 : le contrôleur répond-il à quoi que ce soit ? Écrire un texte de statut est
// l'appel le plus inoffensif qu'il expose ; s'il ne s'affiche pas, celui qu'on a trouvé n'est
// pas celui qui dessine.
func AiNpcHoloProbeStatus(text: String) -> String {
    let description: String;
    let avatar = AiNpcHoloFindAvatar(description);
    if !IsDefined(avatar) {
        return description;
    }

    avatar.SetStatusText(text);
    let answer = s"statut '\(text)' écrit. \(description)";
    AiNpcLog(s"Sonde holo -- \(answer)");
    return answer;
}
