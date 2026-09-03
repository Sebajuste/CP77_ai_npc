// <channel> : ce que le prompt affirme du MÉDIUM, et rien d'autre.
//
// Le médium était affirmé à deux endroits avant ce bloc, et les deux avaient tort pendant un
// appel : `<fiction>` disait « texting V on a phone », la rubrique `REACH` disait « You reach V
// only by text message ». Un personnage au téléphone lisait donc qu'il envoyait des SMS.
//
// POURQUOI UN BLOC À PART, ET POURQUOI ICI. Les deux affirmations vivaient au-dessus de `<now>`,
// et `<now>` décide où finit le préfixe cacheable. Les rendre dépendantes du canal aurait coupé
// ce préfixe en deux pour un joueur qui alterne SMS et appels. Sous `</now>`, ce bloc ne coûte
// rien qui n'était pas déjà dépensé.
//
// CE QU'IL PORTE ET CE QU'IL NE PORTE PAS. Des règles de RENDU : ce qu'une surface peut afficher
// ou prononcer. Pas une manière de parler -- celle-là appartient au personnage, et elle est dans
// `<character>`. Judy tape des émoticônes parce que c'est elle ; une bouche n'en prononce aucune
// parce que c'est une bouche. Les deux se disent sans se contredire, à deux endroits différents.
//
// Aucune contribution, comme `<explicitness>` : un canal répond à une question posée par la
// surface, et aucun personnage n'a voix au chapitre.

module AiNpc

// Le fait, puis ce que la surface accepte. Un texte par canal, écrit ici et nulle part ailleurs.
//
// SANS AUCUN EXEMPLE du côté parlé, et c'est mesuré : montrer le marqueur dans la rubrique TIME
// faisait recopier la chaîne dans 22 % des réponses, 7 sur 24 mot pour mot. Une règle qui
// montrerait « 22h devient vingt-deux heures » produirait « vingt-deux heures » dans des
// répliques sans horaire.
//
// Les exemples de smileys du côté écrit sont ceux que la rubrique FORM portait avant ce bloc :
// ils sont déplacés, pas réécrits.
// Un `switch` avec un retour final, et non une chaine de `if` : c'est la forme que
// `tools\prompt` sait recolter, comme pour la regle de langue et la forme d'adresse. Le canal
// ecrit est le retour par defaut, ce qui est aussi ce qu'un canal futur heriterait.
func AiNpcChannelPromptFor(channel: AiNpcChannelId) -> String {
    switch channel {
        case AiNpcChannelId.Call:
            return "You and V are on a call. Your reply is read out loud by a speech engine. Write every number, time and amount in words. Write names, acronyms and abbreviations out in full. No emoji, no typed smileys, no asterisks, no formatting of any kind.";
    }
    return "You and V are texting. Emoji and other pictographs cannot be displayed; typed smileys like :) ;) :/ xD are fine.";
}

// Le canal d'une passe. Une seule correspondance, ici, pour que le constructeur de prompt n'ait
// à connaître que sa propre passe.
func AiNpcChannelOfPass(pass: String) -> AiNpcChannelId {
    if Equals(pass, AiNpcLaneHolo()) {
        return AiNpcChannelId.Call;
    }
    return AiNpcChannelId.Text;
}
