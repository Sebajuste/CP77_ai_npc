// Le canal : par quel medium une conversation se tient, et qui possède un tour.
//
// DEUX CHOSES QU'IL NE FAUT PAS CONFONDRE. `AiNpcChannelId` est la valeur qui se stocke et se
// compare -- un entier dans le journal, un test d'égalité dans un prédicat. `AiNpcChannel` est
// l'objet qui possède un tour. L'identité part sur le disque ; le comportement se résout à
// partir d'elle. Une classe n'entre pas dans une sauvegarde, et un entier ne possède pas un
// pipeline.
//
// CE QU'IL N'EST PAS.
//
// Pas la porte. `AiNpcChatDoor` est le seul endroit où une conversation s'ouvre et se ferme ; le
// canal est le seul endroit où un tour se dit et se répond. Des verbes différents, des durées de
// vie différentes, et les fusionner mettrait le déclencheur unique du service de mémoire dans
// l'envoi.
//
// Pas une session, et il ne doit jamais s'enregistrer comme telle. `AiNpcChatRegistry` est un
// premier-servi : ce qui répond vrai prend la réponse et les autres ne la voient jamais.
//
// Pas une passe. Une passe est un genre de TRAVAIL -- parler, réparer, compacter -- avec son
// constructeur et sa recette, assemblée par la colonne unique d'`AiNpcPassSend`. Un canal est un
// genre de CONVERSATION. Deux axes, aucun croisement : le canal ne construit aucune requête.
//
// Pas pur, et c'est un rôle plutôt qu'un manquement. `Send` et `Deliver` atteignent des
// systèmes, donc ne s'assertent pas au démarrage -- c'est l'« adaptateur mince qui va chercher »
// de la règle 3b. Ce qui se teste, ce sont les réponses qui ne touchent rien : `Id`, `Clean`,
// `ShowsInThread`.

module AiNpc

abstract class AiNpcChannel extends IScriptable {

    // Ce qui part sur le disque, et ce à quoi une surface est comparée.
    public func Id() -> AiNpcChannelId {
        return AiNpcChannelId.Text;
    }

    // Le même canal, sous le nom que le dehors lit. Une chaîne et non l'entier : l'ensemble est
    // ouvert, donc un consommateur qui compare doit pouvoir recevoir un nom qu'il ne connaît
    // pas plutôt qu'un numéro qu'il croit épuiser. `AiNpcChannelNames` épelle ceux qui existent.
    //
    // "text" et non "sms" : le terminal est écrit lui aussi, et il n'envoie aucun message.
    public func Name() -> String {
        return AiNpcTextChannel();
    }

    // Une bouche dira ceci, donc pas d'emoji, pas de didascalie, les nombres en toutes lettres.
    //
    // C'EST LA PROPRIÉTÉ SUR LAQUELLE ON BRANCHE, et non l'identité : une conversation en face à
    // face est parlée comme un appel l'est, et un test contre l'appel la traiterait comme un SMS.
    public func IsSpoken() -> Bool {
        return false;
    }

    // La moitié du tour qui appartient au joueur, dans le seul ordre juste. La session écho la
    // ligne, arrête l'état de frappe et suit la conversation ; l'appel à la voie et le dépôt
    // sont à moi.
    //
    // L'ORDRE EST UN PIÈGE ET C'EST POURQUOI IL EST ÉCRIT ICI UNE FOIS : déposer avant
    // d'envoyer envoie la ligne deux fois, parce que la voie lit le transcript dans le store et
    // reçoit la ligne de V séparément.
    public func Send(session: ref<AiNpcChatSession>, text: String) -> Void {
        if !IsDefined(session) {
            return;
        }

        // Lu une fois et passé plus bas : la requête et la ligne de V sont un même échange et ne
        // doivent pas pouvoir atterrir dans deux fils différents.
        let contactId = session.GetShownContactId();
        if !session.AcceptTyped(text) {
            return;
        }
        this.SendFrom(contactId, text);
    }

    // Le même échange, pour une surface qui n'a pas de session de chat.
    //
    // UN APPEL N'EN A PAS : la session appartient au fil écrit, elle porte le contact affiché et
    // l'écho dans la bulle. Un appel connaît son contact tout seul et n'a rien à peindre. Ce qui
    // reste -- appeler la voie, classer la ligne de V -- est la même séquence, et elle est ici
    // pour qu'il n'y en ait qu'une : deux copies dériveraient, et la première dérive serait un
    // tour envoyé au modèle sans être classé.
    public func SendFrom(contactId: String, text: String) -> Void {
        if Equals(StrLen(contactId), 0) || Equals(StrLen(text), 0) {
            return;
        }
        let lane = GetAiNpcHttpSystem();
        if !IsDefined(lane) {
            return;
        }
        lane.TriggerPostRequest(contactId, text, this.Id());
        AiNpcAppendMessage(contactId, text, true, "", false, this.Id());
    }

    // L'issue d'un tour, à qui peut la montrer sur moi -- et ma propre réponse quand personne ne
    // le peut. Appelée quand le tour CONCLUT, ce qui peut être plusieurs requêtes après `Send`.
    public func Deliver(contactId: String, text: String) -> Void {}

    // Passée sur ce qui sera dit ou classé, jamais après. Pure : deux consommateurs l'appellent
    // -- la réplique complète et la phrase que le streaming livre à la voix -- et n'en nettoyer
    // qu'un prononcerait ce que l'autre a nettoyé. `language` est celle dans laquelle la réplique
    // est écrite.
    public func Clean(text: String, language: AiNpcLanguage) -> String {
        return text;
    }

    // Le fil écrit peint-il mes lignes.
    public func ShowsInThread() -> Bool {
        return true;
    }
}

// Le canal d'une valeur. Sans état, donc résoudre c'est allouer -- et un canal inconnu rend le
// canal écrit, parce qu'un entier venu d'un journal plus récent que le mod ne doit pas faire
// disparaître une conversation.
func AiNpcChannelOf(id: AiNpcChannelId) -> ref<AiNpcChannel> {
    if Equals(id, AiNpcChannelId.Call) {
        return new AiNpcChannelHolo();
    }
    return new AiNpcChannelText();
}

// Un entier lu sur le disque. Hors table = Text, pour la même raison.
func AiNpcChannelFromInt(value: Int32) -> AiNpcChannelId {
    if Equals(value, EnumInt(AiNpcChannelId.Call)) {
        return AiNpcChannelId.Call;
    }
    return AiNpcChannelId.Text;
}
