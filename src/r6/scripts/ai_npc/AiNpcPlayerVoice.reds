// La voix de V, qui dit pendant un holo la replique que le joueur a tapee.
//
// Le timbre suit AiNpcResolveGender(), comme les accords du prompt : la voix et le texte ne
// peuvent pas se contredire.

module AiNpc

// Le nom sous lequel la DLL range la preparation de cette voix et la cite dans son journal.
func AiNpcPlayerVoiceKey() -> String {
    return "V";
}

// La reference que la recette taille dans les archives du joueur, comme pour les personnages.
func AiNpcPlayerVoiceFile() -> String {
    return Equals(AiNpcResolveGender(), AiNpcGender.Female) ? "v_female.wav" : "v_male.wav";
}

// La voix de catalogue quand aucun clone n'est possible. Aucune fiche ne l'emploie.
func AiNpcPlayerVoiceFallback() -> String {
    return Equals(AiNpcResolveGender(), AiNpcGender.Female) ? "jane" : "charles";
}
