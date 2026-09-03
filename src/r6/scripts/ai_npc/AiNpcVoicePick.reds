// Quelle voix dit les repliques d'un personnage, lu dans sa fiche.
//
// Deux paliers, et ils ne se remplacent pas : le clone est la voix du jeu, taillee dans les
// archives du joueur ; le repli est une voix de catalogue libre, qui ne lui ressemble pas mais
// qui distingue onze personnages la ou Windows n'en distingue aucun.
//
// Le choix ENTRE les deux appartient a la DLL, parce qu'il depend de ce qui est sur le disque
// et que le disque change sans que le jeu redemarre -- un pack installe en cours de partie doit
// s'entendre. Ce fichier ne fait que lire ce que la fiche declare.

module AiNpc

// La fiche vivante d'un contact, surcharges de fichier comprises, ou la fiche livree quand le
// registre n'existe pas encore. Un appel tres tot -- au chargement, avant le joueur -- doit
// repondre quelque chose de juste plutot que rien.
func AiNpcVoiceSheetFor(contactId: String) -> ref<AiNpcCharacterDef> {
    let registry = AiNpcGetContactRegistry();
    if IsDefined(registry) {
        let provider = registry.Find(contactId) as AiNpcDefContactProvider;
        if IsDefined(provider) {
            return provider.GetDefinition();
        }
    }
    return AiNpcBuiltinSheet(contactId);
}

// Le fichier de reference, dans r6\storages\AiNpc\voices\.
//
// Par defaut `<contactId>.wav`, qui est ce que la recette d'extraction produit -- une fiche n'a
// donc rien a dire dans le cas ordinaire. Le nommer sert a partager une reference entre deux
// contacts, ou a en designer une que le joueur a deposee sous un autre nom.
func AiNpcVoiceFileFor(contactId: String) -> String {
    if Equals(StrLen(contactId), 0) {
        return "";
    }
    let def = AiNpcVoiceSheetFor(contactId);
    if IsDefined(def) && IsDefined(def.voice) && NotEquals(StrLen(def.voice.clone), 0) {
        return def.voice.clone;
    }
    return contactId + ".wav";
}

// La voix de catalogue de ce personnage, ou "" s'il n'en declare aucune.
//
// Vide n'est pas une erreur : un contact ajoute par un tiers n'a aucune raison de connaitre le
// catalogue de PocketTTS, et la voix du systeme reste derriere.
func AiNpcVoiceFallbackFor(contactId: String) -> String {
    if Equals(StrLen(contactId), 0) {
        return "";
    }
    let def = AiNpcVoiceSheetFor(contactId);
    if IsDefined(def) && IsDefined(def.voice) {
        return def.voice.fallback;
    }
    return "";
}
