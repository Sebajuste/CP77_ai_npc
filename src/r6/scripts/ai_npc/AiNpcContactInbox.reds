// Ce que la touche des messages ouvre sur une ligne de contact.
//
// Le jeu n'a que deux notions et elles suffisent : un contact possède des conversations, une
// conversation s'ouvre. La nôtre en est une. Ce fichier répond à une seule question -- laquelle
// des trois situations -- et rien d'autre : il n'ouvre rien et ne dessine rien.
//
// LA SITUATION PARTAGÉE EST CELLE QUE LE JEU NE CONNAÎT PAS. Un contact livré par un autre mod
// (Phone Extension, NightlyNow) n'a aucune entrée dans le journal : le jeu ne lui dessine pas de
// liste de conversations, et l'autre mod répond à sa place sans transmettre l'appel plus loin.
// Y greffer la nôtre est donc impossible -- il n'y a pas de liste à greffer. On la dessine, avec
// le mécanisme du jeu, et sa conversation à lui s'ouvre par le chemin qu'il attend.

module AiNpc

enum AiNpcInbox {
    // Le mod ne fait rien : le jeu ouvre ce qu'il ouvre, y compris la liste où notre
    // conversation est déjà greffée.
    Game = 0,
    // Notre conversation, seule.
    Chat = 1,
    // Deux conversations, la nôtre et celle du mod qui livre la ligne.
    Shared = 2,
}

// `gameKnows` : le jeu a une entrée de contact pour cette ligne. `threadsVisible` : une liste de
// conversations est déjà à l'écran, donc la ligne EST une conversation et non un contact.
//
// Pure, et c'est ce qui la rend lisible : les deux faits que seul le jeu peut dire lui sont
// donnés, l'un par AiNpcGameKnowsContact, l'autre par le contrôleur du téléphone.
func AiNpcInboxOf(row: ref<ContactData>, gameKnows: Bool, threadsVisible: Bool) -> AiNpcInbox {
    if !IsDefined(row) {
        return AiNpcInbox.Game;
    }

    // La nôtre, sur quelque liste qu'elle se trouve. Testé en premier : c'est la seule ligne
    // dont la réponse ne dépend d'aucune des deux autres questions.
    if row.ainpcThread {
        return AiNpcInbox.Chat;
    }
    if threadsVisible {
        return AiNpcInbox.Game;
    }
    if !AiNpcIsContactSupported(row.contactId) {
        return AiNpcInbox.Game;
    }

    if gameKnows {
        // Une liste qui ne tiendrait que la nôtre : le jeu ouvre seul sa messagerie sur une
        // liste d'une seule conversation (m_isSingleThread), et le joueur verrait la liste
        // clignoter avant notre chat.
        if row.messagesCount == 0 && row.repliesCount == 0 {
            return AiNpcInbox.Chat;
        }
        return AiNpcInbox.Game;
    }
    return AiNpcInbox.Shared;
}

// Le jeu connaît-il ce contact. Un contact d'un autre mod porte un hachage qui n'adresse aucune
// entrée -- celui de Juli est un nombre écrit en dur dans son mod.
func AiNpcGameKnowsContact(hash: Int32) -> Bool {
    let journal = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journal) {
        return false;
    }
    return IsDefined(journal.GetEntry(Cast<Uint32>(hash)) as JournalContact);
}

// Les conversations d'un contact que deux mods se partagent, dans l'ordre où elles s'affichent :
// la nôtre d'abord, épinglée par son horodatage comme dans une liste du jeu.
func AiNpcSharedConversations(row: ref<ContactData>) -> array<ref<IScriptable>> {
    let rows: array<ref<IScriptable>>;
    if !IsDefined(row) {
        return rows;
    }
    ArrayPush(rows, AiNpcThreadRowOf(row.contactId, row.localizedName, row.avatarID, row.hash));
    ArrayPush(rows, AiNpcForeignConversation(row));
    return rows;
}

// La conversation de l'autre mod, en conversation plutôt qu'en contact.
//
// UNE COPIE, ET LE TYPE EST TOUTE LA RAISON. Reposer la ligne telle quelle en ferait un contact
// dans sa propre liste de conversations, que la touche des messages redéploierait par-dessus
// elle-même. En conversation, le geste vanilla ouvre la messagerie, et c'est là que le mod qui
// livre la ligne reprend la main -- il la reconnaît à son hachage, qui est conservé intact.
func AiNpcForeignConversation(row: ref<ContactData>) -> ref<ContactData> {
    let copy = new ContactData();
    copy.id = row.id;
    copy.contactId = row.contactId;
    copy.hash = row.hash;
    copy.conversationHash = row.conversationHash;
    copy.localizedName = row.localizedName;
    copy.avatarID = row.avatarID;
    copy.type = MessengerContactType.SingleThread;
    copy.isCallable = row.isCallable;
    copy.hasMessages = true;
    copy.messagesCount = row.messagesCount;
    copy.playerCanReply = row.playerCanReply;
    copy.playerIsLastSender = row.playerIsLastSender;
    copy.lastMesssagePreview = row.lastMesssagePreview;
    copy.localizedPreview = row.localizedPreview;
    copy.hasValidTitle = row.hasValidTitle;
    copy.timeStamp = row.timeStamp;
    return copy;
}
