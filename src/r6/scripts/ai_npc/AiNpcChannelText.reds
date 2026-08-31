// Le canal écrit : le téléphone, le terminal, et la notification SMS quand personne ne peint.
//
// C'est le canal par défaut et celui de toutes les lignes déjà stockées, parce que `Text` vaut
// zéro. Ce fichier ne fait donc rien de neuf : il donne un nom à ce que le mod a toujours fait.

module AiNpc

class AiNpcChannelText extends AiNpcChannel {

    public func Id() -> AiNpcChannelId {
        return AiNpcChannelId.Text;
    }

    // Une seule décision, et c'est une question : quelqu'un a-t-il peint ceci ? Chaque surface
    // capable de rendre se la voit offrir, la plus récemment ouverte d'abord, et décide pour
    // elle-même. Que personne ne rende n'est pas une erreur -- c'est à ça que sert la
    // notification.
    public func Deliver(contactId: String, text: String) -> Void {
        if AiNpcPublishReply(contactId, text, this.Id()) {
            return;
        }

        // Le mod qui possède le correspondant a le premier refus, parce que la poussée
        // ci-dessous est celle du téléphone VANILLA et adresse un contact par son nom affiché.
        // Un contact qui vit dans un autre cadre téléphonique s'y adresse par empreinte, et une
        // notification vanilla pour lui ne mène nulle part quand le joueur la touche.
        let provider = AiNpcProviderFor(contactId);
        if IsDefined(provider) && provider.Notify(text) {
            return;
        }

        let phone = AiNpcFindPhoneController();
        if !IsDefined(phone) {
            AiNpcLog(s"No phone controller: '\(contactId)' had a line and nowhere to say it.");
            return;
        }
        phone.PushCustomSMSNotification(contactId, AiNpcGetCharacterName(contactId), text);
    }
}
