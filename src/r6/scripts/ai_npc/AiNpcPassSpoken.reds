// La passe dite : la meme replique, sur un appel holo.
//
// ELLE REND EXACTEMENT LES MEMES DEUX MESSAGES que la passe ecrite, et c'est voulu -- c'est un
// personnage qui parle dans les deux cas, donc le meme vocabulaire de blocs s'applique. Ce
// qu'une passe distincte ouvre n'est pas un autre prompt, c'est une RELIURE :
//
//   - un autre slot, parce qu'une replique dite est plus courte et peut vivre sur un modele
//     moins cher que celle qu'on relit ;
//   - une autre recette, parce que ce qui est dit ne se relit pas : la regle de longueur et la
//     regle de forme sont les deux qu'on voudra changer en premier ;
//   - deux totaux separes dans le rapport du jour, entre une soiree d'appels et une soiree de
//     textos.
//
// Une classe plutot qu'une condition dans la passe ecrite, et le linter l'a exige avant qu'on
// y pense : une passe a un constructeur, un constructeur declare une passe. Une methode qui
// repond deux noms selon un champ est une passe qu'aucune regle ne peut plus compter.
//
// Non reliee, elle se comporte exactement comme la passe ecrite : le slot suit celui de
// `speaking`, et la recette est l'active. Une installation qui n'a rien configure ne s'apercoit
// de rien.

module AiNpc

class AiNpcPassSpoken extends AiNpcPassConversation {
    static func Spoken(contactId: String, pendingContext: String, intent: String, ask: String,
                       speaksFirst: Bool) -> ref<AiNpcPassSpoken> {
        let self = new AiNpcPassSpoken();
        self.contactId = contactId;
        self.pendingContext = pendingContext;
        self.intent = intent;
        self.ask = ask;
        self.speaksFirst = speaksFirst;
        return self;
    }

    func Pass() -> String {
        return AiNpcLaneHolo();
    }
}

// Le constructeur qui va avec le canal. Un seul endroit choisit, et c'est celui qui connait le
// canal -- rien en aval n'a besoin de le savoir.
func AiNpcPassBuilderFor(channel: AiNpcChannelId, contactId: String, pendingContext: String,
                         intent: String, ask: String, speaksFirst: Bool) -> ref<AiNpcPassConversation> {
    if Equals(channel, AiNpcChannelId.Call) {
        return AiNpcPassSpoken.Spoken(contactId, pendingContext, intent, ask, speaksFirst);
    }
    return AiNpcPassConversation.Of(contactId, pendingContext, intent, ask, speaksFirst);
}
