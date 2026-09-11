// Quelle voix dit les repliques d'un personnage, lue sur son provider.
//
// Deux paliers, et ils ne se remplacent pas : le clone est la voix du jeu, taillee dans les
// archives du joueur ; le repli est une voix de catalogue libre, qui ne lui ressemble pas mais
// qui distingue onze personnages la ou Windows n'en distingue aucun.
//
// Le choix ENTRE les deux appartient a la DLL, parce qu'il depend de ce qui est sur le disque
// et que le disque change sans que le jeu redemarre -- un pack installe en cours de partie doit
// s'entendre. Ce fichier ne fait que lire ce que le personnage declare.

module AiNpc

// La voix que le provider declare, quel qu'il soit -- fiche ou script d'un autre mod. Null est
// « sans avis » : la fiche livree repond alors, et c'est aussi elle qui repond quand le registre
// n'existe pas encore, pour qu'un appel tres tot dise quelque chose de juste plutot que rien.
func AiNpcVoiceOf(contactId: String) -> ref<AiNpcVoiceDef> {
    let registry = AiNpcGetContactRegistry();
    if IsDefined(registry) {
        let provider = registry.Find(contactId);
        if IsDefined(provider) {
            let declared = provider.GetVoice();
            if IsDefined(declared) {
                return declared;
            }
        }
    }
    let sheet = AiNpcBuiltinSheet(contactId);
    if IsDefined(sheet) {
        return sheet.voice;
    }
    return null;
}

// Le fichier de reference, dans r6\storages\AiNpc\voices\. Par defaut `<contactId>.wav`, qui
// est ce que la recette d'extraction produit.
func AiNpcVoiceFileFor(contactId: String) -> String {
    if Equals(StrLen(contactId), 0) {
        return "";
    }
    let voice = AiNpcVoiceOf(contactId);
    if IsDefined(voice) && NotEquals(StrLen(voice.clone), 0) {
        return voice.clone;
    }
    return contactId + ".wav";
}

// La vitesse de lecture, bornee ici et nulle part ailleurs : au-dela de quatre demi-tons une
// voix derivee ne ressemble plus a une personne.
func AiNpcVoiceRateFor(contactId: String) -> Float {
    let voice = AiNpcVoiceOf(contactId);
    if !IsDefined(voice) {
        return 1.0;
    }
    return ClampF(voice.rate, 0.8, 1.25);
}

// La voix de catalogue de ce personnage, ou "" s'il n'en declare aucune.
func AiNpcVoiceFallbackFor(contactId: String) -> String {
    if Equals(StrLen(contactId), 0) {
        return "";
    }
    let voice = AiNpcVoiceOf(contactId);
    if IsDefined(voice) {
        return voice.fallback;
    }
    return "";
}
