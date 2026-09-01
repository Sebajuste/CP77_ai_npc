// Every enum the mod declares, in one place.
//
// Together because their VALUES are a compatibility surface, and that is easy to forget when
// an enum sits at the bottom of the file that happens to use it. Mod Settings persists the
// integer, not the name, so inserting a member in the middle silently reassigns what a
// player already chose -- which is why Auto and External are numbered far away from the real
// members rather than appended. tools/lint.ps1 additionally checks that every member of an
// enum the settings menu exposes has a displayValue, since one without is simply blank in
// the menu.

module AiNpc

// Par quel medium une ligne a ete dite. La valeur part sur le disque, dans le journal, ce qui
// est exactement la raison d'etre de ce fichier : inserer un membre au milieu relirait les
// conversations deja ecrites sous un autre canal.
//
// Text vaut 0 et c'est toute la migration : chaque ligne deja stockee, chaque defaut, chaque
// renderer muet se relisent en Text, qui est ce qu'ils ont toujours ete.
//
// Call, pas Voice : l'axe est le medium et non le son. Une conversation en face a face serait
// parlee elle aussi, et il faut qu'il lui reste un nom.
enum AiNpcChannelId {
    Text = 0,
    Call = 1
}

enum AiNpcConversationType {
    Normal = 0,
    NSFW = 1,
    NSFW_Hard = 2
}

// Read from the character the player created, never from a setting: the game already
// knows the answer, and a menu that can disagree with the body is a menu that can be wrong.
enum AiNpcGender {
    Male = 0,
    Female = 1
}

// Four lanes, and two of them are OpenRouter: the same service, the same key, one reached
// through ai_npc.dll, which reads the reply as it is written and
// hands each finished sentence to the voice. Numbered contiguously and appended, never
// inserted: a hole would mean a persisted setting that reads as a provider nobody can select,
// and a member added in the middle silently reassigns what a player already chose.
// OpenRouter garde la valeur 0, et c'est la seule reponse correcte : Mod Settings persiste
// l'entier et non le nom, donc renumeroter relirait le choix d'un joueur comme un autre
// fournisseur. Ce qui a change sous ce nom, c'est le tuyau -- la voie passe par ai_npc.dll, qui
// lit la reponse pendant qu'elle s'ecrit.
//
// La valeur 3 a existe, le temps de mesurer la nouvelle voie contre l'ancienne. Elle n'existe
// plus, et AiNpcProviderSetting ramene un 3 persiste sur 0 : le meme service, la meme cle, le
// meme modele.
enum AiNpcProvider {
    OpenRouter = 0,
    ClaudeCli = 1,
    CodexCli = 2
}

// Where the choice of a command is made. Embedded is what the mod has always done and stays
// the default; Dedicated moves it to a request of its own -- see AiNpcActionService.
enum AiNpcActionMode {
    Embedded = 0,
    Dedicated = 1
}

enum AiNpcLanguage {
    English = 0,
    Spanish = 1,
    French = 2,
    German = 3,
    Italian = 4,
    Portuguese = 5,
    Russian = 6,
    Ukraine = 7
}
