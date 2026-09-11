// Les répliques d'un appel du jeu, classées dans la transcription de l'appel comme des répliques
// ordinaires. Le modèle ne sait pas qu'elles viennent de la scène : pour lui, c'est ce qui s'est
// dit. Elles restent dans l'historique, donc dans la mémoire du personnage.
//
// Une réplique déjà présente dans l'historique du contact n'est pas classée une seconde fois :
// un appel répétable rejoue les mêmes lignes, et V peut choisir deux fois la même réponse.

module AiNpc

// Le texte que le joueur lit, composé comme le fait le contrôleur de sous-titres du jeu : la
// traduction pour une réplique Kiroshi, le mot étranger tel qu'il est dit pour une réplique en
// langue maternelle. Pur.
func AiNpcSceneLineText(kiroshi: Bool, motherTongue: Bool, raw: String, pre: String,
                        foreign: String, translation: String, post: String) -> String {
    if kiroshi && NotEquals(StrLen(translation), 0) {
        return AiNpcSceneLineJoin(pre, translation, post);
    }
    if motherTongue {
        return AiNpcSceneLineJoin(pre, foreign, post);
    }
    return raw;
}

func AiNpcSceneLineJoin(pre: String, middle: String, post: String) -> String {
    let parts = [pre, middle, post];
    let joined = "";
    let i = 0;
    while i < ArraySize(parts) {
        let part = parts[i];
        if NotEquals(StrLen(part), 0) {
            if NotEquals(StrLen(joined), 0) {
                joined += " ";
            }
            joined += part;
        }
        i += 1;
    }
    return AiNpcReplaceAll(joined, "  ", " ");
}

// Pur.
func AiNpcSceneLineIsNew(messages: array<ref<AiNpcMessage>>, text: String, fromPlayer: Bool) -> Bool {
    let i = 0;
    while i < ArraySize(messages) {
        let message = messages[i];
        if Equals(message.text, text) && Equals(message.fromPlayer, fromPlayer) {
            return false;
        }
        i += 1;
    }
    return true;
}

func AiNpcSceneLineShown(line: scnDialogLineData) -> String {
    let kiroshi = scnDialogLineData.HasKiroshiTag(line);
    let motherTongue = scnDialogLineData.HasMothertongueTag(line);
    if !kiroshi && !motherTongue {
        return line.text;
    }
    let shown = scnDialogLineData.GetDisplayText(line);
    return AiNpcSceneLineText(kiroshi, motherTongue, line.text, shown.preTranslatedText,
        shown.text, shown.translation, shown.postTranslatedText);
}

// Vrai quand la réplique a été classée.
func AiNpcFileSceneLine(contactId: String, line: scnDialogLineData) -> Bool {
    let text = AiNpcSceneLineShown(line);
    if Equals(StrLen(text), 0) {
        return false;
    }
    let fromPlayer = IsDefined(line.speaker) && line.speaker.IsPlayer();
    let messages = AiNpcStoredMessages(contactId);
    if !AiNpcSceneLineIsNew(messages, text, fromPlayer) {
        return false;
    }
    return AiNpcAppendMessage(contactId, text, fromPlayer, "", false, AiNpcChannelId.Call);
}
