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

// Ce que la DLL recoit pour une replique, lu une seule fois sur le personnage.
class AiNpcVoiceChoice {
    // Le fichier de reference, dans r6\storages\AiNpc\voices\.
    public let file: String;
    // La voix de catalogue, ou "".
    public let fallback: String;
    public let rate: Float = 1.0;
}

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

// Sans clone declare, `<contactId>.wav`, qui est ce que la recette d'extraction produit. La
// vitesse est bornee ici et nulle part ailleurs : au-dela de quatre demi-tons une voix derivee
// ne ressemble plus a une personne.
func AiNpcVoiceChoiceFor(contactId: String) -> ref<AiNpcVoiceChoice> {
    let choice = new AiNpcVoiceChoice();
    if Equals(StrLen(contactId), 0) {
        return choice;
    }
    choice.file = contactId + ".wav";
    let voice = AiNpcVoiceOf(contactId);
    if IsDefined(voice) {
        if NotEquals(StrLen(voice.clone), 0) {
            choice.file = AiNpcDerivedVoiceFile(voice.clone, voice.shift);
            AiNpcAnnounceVoiceLines(voice);
        }
        choice.fallback = voice.fallback;
        choice.rate = ClampF(voice.rate, 0.8, 1.25);
    }
    return choice;
}

// `<clone>-x<shift>.wav`, the name the DLL reads the derivation back from. A clone at 1 keeps
// its own name, so a reference the player dropped in is still the one read.
func AiNpcDerivedVoiceFile(clone: String, shift: Float) -> String {
    let hundredths = Cast<Int32>(ClampF(shift, 0.85, 1.15) * 100.0 + 0.5);
    if hundredths == 100 {
        return clone;
    }
    let stem = AiNpcVoiceStem(clone);
    let fraction = hundredths % 100;
    let digits = fraction < 10 ? s"0\(fraction)" : s"\(fraction)";
    return s"\(stem)-x\(hundredths / 100).\(digits).wav";
}

// Les repliques qu'un personnage d'un autre mod donne a couper, poussees vers la DLL avant
// qu'elle en ait besoin. Rien a faire pour le casting livre : la recette nomme deja les siennes.
//
// A chaque replique, parce que ce fichier n'a pas de memoire et qu'un systeme entier pour en
// avoir une couterait plus que l'appel. La DLL ne retient que les changements.
func AiNpcAnnounceVoiceLines(voice: ref<AiNpcVoiceDef>) -> Void {
    let lines = voice.cloneLines;
    if ArraySize(lines) > 0 {
        AiNpcAudio.DeclareVoice(AiNpcVoiceStem(voice.clone), lines);
    }
}

// Le nom sous lequel la DLL cherche une voix : le fichier de reference sans son extension.
func AiNpcVoiceStem(clone: String) -> String {
    if StrEndsWith(clone, ".wav") {
        return StrLeft(clone, StrLen(clone) - 4);
    }
    return clone;
}
