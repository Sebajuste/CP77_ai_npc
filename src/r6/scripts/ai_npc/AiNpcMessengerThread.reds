// La conversation du mod, logée dans le téléphone du jeu : une conversation de plus dans la
// liste d'un contact, épinglée en tête. Aucune touche n'est ajoutée à la liste de contacts.
//
// Les lignes de contact des personnages du mod sont rendues appelables et « avec messages »,
// pour que F et la touche des messages s'y offrent comme sur n'importe quel contact. Ce que le
// jeu sait vraiment d'un appel se relit dans le journal (AiNpcVanillaCallable), jamais ici.

module AiNpc

@addField(ContactData)
public let ainpcThread: Bool;

func AiNpcGraftContactRows(rows: array<ref<IScriptable>>) -> Void {
    let count = ArraySize(rows);
    let i = 0;
    while i < count {
        let row = rows[i] as ContactData;
        if IsDefined(row) && AiNpcIsContactSupported(row.contactId) {
            row.isCallable = true;
            row.hasMessages = true;
        }
        i += 1;
    }
}

// Null pour un contact que le mod ne gère pas.
func AiNpcThreadRowFor(journal: ref<JournalManager>, contactHash: Int32) -> ref<ContactData> {
    if !IsDefined(journal) {
        return null;
    }
    let entry = journal.GetEntry(Cast<Uint32>(contactHash)) as JournalContact;
    if !IsDefined(entry) {
        return null;
    }
    let contactId = entry.GetId();
    if !AiNpcIsContactSupported(contactId) {
        return null;
    }

    let row = new ContactData();
    row.id = contactId;
    row.contactId = contactId;
    row.hash = contactHash;
    row.localizedName = entry.GetLocalizedName(journal);
    row.avatarID = entry.GetAvatarID(journal);
    row.type = MessengerContactType.SingleThread;
    row.isCallable = true;
    row.ainpcThread = true;
    // La liste est triée par date : l'heure courante l'épingle en tête.
    row.timeStamp = GameInstance.GetTimeSystem(GetGameInstance()).GetGameTime();
    AiNpcThreadPreview(row, contactId);
    return row;
}

func AiNpcThreadPreview(row: ref<ContactData>, contactId: String) -> Void {
    let messages = AiNpcStoredMessages(contactId);
    let i = ArraySize(messages) - 1;
    while i >= 0 {
        let message = messages[i];
        if message.ShowsInThread() {
            row.lastMesssagePreview = message.text;
            row.playerIsLastSender = message.fromPlayer;
            return;
        }
        i -= 1;
    }
    row.hasValidTitle = true;
    row.localizedPreview = AiNpcStartTypingLabel(AiNpcResolveLanguage());
}

// Une ligne qui ouvre le chat du mod : sa conversation, ou un contact dont la liste ne
// tiendrait qu'elle. Le second cas évite au jeu d'ouvrir seul sa messagerie sur une liste
// d'une seule conversation (m_isSingleThread).
func AiNpcOpensModChat(row: ref<ContactData>) -> Bool {
    if !IsDefined(row) {
        return false;
    }
    if row.ainpcThread {
        return true;
    }
    return Equals(row.type, MessengerContactType.Contact)
        && row.messagesCount == 0 && row.repliesCount == 0
        && AiNpcIsContactSupported(row.contactId);
}
