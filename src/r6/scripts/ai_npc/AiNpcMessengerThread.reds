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
    return AiNpcThreadRowOf(contactId, entry.GetLocalizedName(journal), entry.GetAvatarID(journal),
                            contactHash);
}

// Notre conversation en tant que ligne. Le journal du jeu n'entre pas ici : un contact livré par
// un autre mod n'y a pas d'entrée, et sa conversation se dessine comme celle d'un contact du jeu.
func AiNpcThreadRowOf(contactId: String, name: String, avatar: TweakDBID,
                      contactHash: Int32) -> ref<ContactData> {
    let row = new ContactData();
    row.id = contactId;
    row.contactId = contactId;
    row.hash = contactHash;
    row.localizedName = name;
    row.avatarID = avatar;
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
