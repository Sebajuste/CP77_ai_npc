// Le nom des canaux, épelé pour qui les compare.
//
// UN ENSEMBLE OUVERT, ET C'EST TOUTE LA RAISON DE LA FORME. Les autres vocabulaires de cette
// API sont des `Int32` à plages disjointes -- tickets 0-3, ouverture 10-14, écriture 20-24 --
// parce qu'un entier comparé à la mauvaise constante correspond en silence. Un canal ne peut pas
// entrer dans ce schéma : il en arrivera d'autres, chacun voudrait sa plage réservée, et surtout
// un consommateur qui écrit `if appel { ... } else { /* écrit */ }` avalerait le canal suivant
// dans son `else`, sans erreur et sans log. Une chaîne traverse le `@if` aussi bien qu'un entier
// et ne se laisse pas épuiser : un nom inconnu reste un nom inconnu.
//
// Nommees `AiNpc<Canal>Channel` et non `AiNpcChannel<Canal>` : les secondes sont les classes
// internes qui portent le comportement, et le module ne tient qu'un nom.
//
// La forme est celle des tags, pour la même raison qu'eux : ce qui est ouvert se nomme, et
// l'API épelle les noms pour que personne ne les tape à la main.
//
// COMPARE L'IDENTITÉ POUR UN CANAL QUE TU CONNAIS ; BRANCHE SUR LES PROPRIÉTÉS POUR LES AUTRES.
// `spoken` et `showsInThread` accompagnent le nom partout où il est rendu, et ce sont eux qui
// répondent à "comment rendre ceci" -- un canal ajouté demain les porte, et un mod déjà publié
// continue d'avoir raison sans être recompilé.

module AiNpc

// Le téléphone, le terminal, et tout ce qui se lit. Le canal par défaut.
//
// "text" et non "sms" : le transport n'est pas l'axe, le terminal est écrit lui aussi.
public func AiNpcTextChannel() -> String {
    return "text";
}

// L'appel holo : ce qui s'y dit est prononcé et n'apparaît pas dans le fil écrit.
public func AiNpcHoloChannel() -> String {
    return "holo";
}
