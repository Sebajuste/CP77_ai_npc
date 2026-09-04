// One stored line of a conversation, and who wrote it.
//
// In api\ because AiNpcReadConversation hands an array of these back: a consumer reads it, so
// the record is part of the contract even though nothing outside builds one. The operations
// over it -- append, trim, undo, transcript -- are the pure model in AiNpcHistory.reds, which
// is where they stay.
//
// Le canal est la seule chose ici qui se demande plutot que se lire : la valeur stockee est
// numerotee pour le disque, et ce qu'un consommateur en obtient est un nom et deux predicats.
// Un enregistrement DERIVE -- il ne recopie pas trois champs qui pourraient diverger de
// l'entier qu'ils decrivent, et une ligne relue d'un journal ancien repond comme les autres.

module AiNpc

public class AiNpcMessage {
    public let fromPlayer: Bool;
    public let text: String;

    // Par quel medium elle a ete dite. LA VALEUR DE DISQUE, ET RIEN D'AUTRE : elle est numerotee,
    // Text vaut zero, et c'est ce qui fait qu'une ligne ecrite avant ce champ se relit comme ce
    // qu'elle etait. Un consommateur lit `Channel()` et les deux predicats sous elle, jamais ceci
    // -- un entier compare a une constante avale en silence le canal qui n'existe pas encore.
    let channel: AiNpcChannelId;

    // Le canal sous son nom public : "text", "holo", ou celui d'un canal que ce mod ne connait
    // pas encore. Compare-le pour un canal que tu connais.
    public func Channel() -> String {
        return AiNpcChannelOf(this.channel).Name();
    }

    // Ce sur quoi on branche quand on ne connait pas le canal, et il en arrivera. Une ligne
    // parlee n'est pas forcement un appel : une conversation en face a face l'est aussi.
    public func IsSpoken() -> Bool {
        return AiNpcChannelOf(this.channel).IsSpoken();
    }

    // Le fil ecrit peint-il cette ligne. Faux pour ce qui a ete dit de vive voix, dont le fil ne
    // garde qu'une trace.
    public func ShowsInThread() -> Bool {
        return AiNpcChannelOf(this.channel).ShowsInThread();
    }

    // Absolute in-game seconds. 0 means unknown -- what every message written before this
    // field reads back as -- and must be treated as "no answer", never as midnight of day
    // zero. Absolute rather than the "3:45pm" the prompt shows: a formatted clock cannot be
    // subtracted, so it says when a message was sent but never how long ago.
    public let gameTimeSeconds: Int32;
}
