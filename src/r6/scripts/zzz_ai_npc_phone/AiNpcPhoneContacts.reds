// Making sure a registered contact is actually REACHABLE in the phone.
//
// Registering a provider makes a contact supported, not visible: the row the player clicks
// comes from the phone's contact array, which some other mod is usually responsible for
// filling. Two different things can go wrong there, they look identical from inside the game
// -- "the contact is not in my list" -- and they need opposite fixes.
//
//   1. THE ENTRY EXISTS BUT IS EMPTY. A ContactData with no messages is nothing to show, and
//      `hasMessages` / `messagesCount` are not obvious fields: a mod that forgets them gets a
//      contact that appears only once a real thread exists, so it works in testing and looks
//      broken on a fresh save. Found in the wild -- two contacts from the SAME mod, one
//      setting those fields and one not, with nothing in any log to say so.
//
//      Repaired here for every registered provider, with no opt-in. Repair is safe because it
//      MUTATES AN ENTRY THAT IS ALREADY THERE: it cannot duplicate a row, and the fields it
//      raises are already true for a contact that was displaying correctly.
//
//   2. THE ENTRY DOES NOT EXIST AT ALL. Nothing to repair, so a row has to be created. That
//      is WantsPhoneContact, opt-in because it is the dangerous half: a provider whose
//      contact is already supplied by its own mod's framework would get a second row.
//
// Both run inside the same wrapper, and both are idempotent -- the array is scanned for the
// contactId before anything is added, so repeated calls converge on one entry.
//
// WHY THIS FILE LIVES IN ITS OWN FOLDER, AND WHY THE NAME IS UGLY.
//
// REDscript applies @wrapMethod in compile order, and the LAST wrapper compiled is the
// OUTERMOST one -- it runs first and calls the others through wrappedMethod. Compile order is
// the folder name, case-insensitively.
//
// From `ai_npc\`, this wrapper would sit INSIDE Phone Extension's (`PhoneExtension\` sorts
// later): its wrapper would run first and call ours, so ours would see only the vanilla array
// -- the contact it is about to add is not there yet, and the pass becomes a silent no-op
// that looks exactly like a correct one.
//
// `zzz_` is the blunt instrument that fixes it, and it is the local convention. Renaming this
// folder to something that sorts earlier silently reintroduces the bug, and a mod sorting
// after `zzz_ai_npc_phone` would put us back inside its wrapper -- hence the shape below:
// repair is automatic because its failure mode is "no change", injection is opt-in because
// its failure mode is "two rows".

// Fields the phone needs before it will draw a row for a contact. Raised only when unset, so
// a mod that already fills them in keeps its own values -- including its message preview,
// which is content and is never touched here.
module AiNpc

func AiNpcMakeContactVisible(data: ref<ContactData>) -> Bool {
    if !IsDefined(data) {
        return false;
    }
    if data.hasMessages && data.messagesCount > 0 {
        return false;
    }

    data.hasMessages = true;
    if data.messagesCount <= 0 {
        data.messagesCount = 1;
    }
    data.playerCanReply = true;
    return true;
}

// A row for a contact nothing else supplies: name, id and a hash, which is all the phone
// needs to draw it and all ai_npc needs to route it back to the provider.
func AiNpcBuildContactData(provider: ref<AiNpcContactProvider>, isText: Bool) -> ref<ContactData> {
    let data = new ContactData();

    let id = provider.GetContactId();
    // The same stable hash a mod would use to register with Phone Extension, so a contact
    // injected here and one registered there identify as the same correspondent.
    data.hash = AiNpcContactHash(id);
    data.contactId = id;
    data.id = id;
    data.localizedName = provider.GetDisplayName();
    data.avatarID = provider.GetPhoneAvatarId();

    // The mod's own conversation: its chat opens from this row on both tabs, and F places the
    // call, as on any contact the mod drives.
    data.ainpcThread = true;
    data.isCallable = true;
    data.questRelated = false;
    data.playerIsLastSender = false;

    if isText {
        data.type = MessengerContactType.SingleThread;
    } else {
        data.type = MessengerContactType.Contact;
    }

    AiNpcMakeContactVisible(data);
    return data;
}

// Whether the array already carries this contact, by contactId. The id is the identity that
// matters -- two mods can disagree about the display name of the same correspondent, and
// deduplicating on the name would then create the duplicate this exists to prevent.
func AiNpcFindContactData(contacts: script_ref<array<ref<IScriptable>>>, contactId: String) -> ref<ContactData> {
    let i = 0;
    let count = ArraySize(Deref(contacts));
    while i < count {
        let data = Deref(contacts)[i] as ContactData;
        if IsDefined(data) && Equals(data.contactId, contactId) {
            return data;
        }
        i += 1;
    }
    return null;
}

// Which of the two lists is being built, for the log. A named function rather than an inline
// conditional: REDscript has no ternary operator.
func AiNpcPhoneListName(isText: Bool) -> String {
    if isText {
        return "messages";
    }
    return "contacts";
}

// The whole pass, over every registered and currently available provider.
//
// EVERYTHING IN HERE IS PAID ONCE PER REDRAW, AND THE PHONE REDRAWS A LOT. Three things
// follow from that:
//
//   * it walks PROVIDERS, not ids. Asking the registry for ids and handing each one back to
//     Find() is a linear scan of the provider list per contact, comparing GetContactId() on
//     everything it walks past. AllAvailableProviders hands over what the scan already found.
//   * the built-in id list is bound ONCE, above the loop. AiNpcIsBuiltinContactId builds its
//     array on every call (see the note in AiNpcContacts.reds about binding an array before
//     ArrayContains), so asking it per contact allocated the same eleven strings per redraw.
//   * the log lines are behind AiNpcLogging(). An interpolated string is assembled at the call
//     site whatever the setting says, and the third branch writes one per unlisted contact.
//
// The parameter is by value, so it is already this function's own copy: appended to and
// returned directly rather than copied a second time into a `result`.
public func AiNpcApplyPhoneContacts(contacts: array<ref<IScriptable>>, isText: Bool) -> array<ref<IScriptable>> {
    let registry = AiNpcGetContactRegistry();
    if !IsDefined(registry) {
        return contacts;
    }

    let builtin = AiNpcGetAllContactIds();
    let logging = AiNpcLogging();

    let providers = registry.AllAvailableProviders();
    let i = 0;
    let count = ArraySize(providers);
    while i < count {
        let provider = providers[i];
        let id = provider.GetContactId();

        // Built-in contacts are CDPR's own and are already in the array on their own terms.
        // Touching those would be this mod editing the vanilla phone, which is not what
        // registering a provider asks for.
        if ArrayContains(builtin, id) {
            i += 1;
        } else {
            let existing = AiNpcFindContactData(contacts, id);

            if IsDefined(existing) {
                if AiNpcMakeContactVisible(existing) && logging {
                    AiNpcLog(s"Phone contact '\(id)' had no messages and would not have been drawn; made visible.");
                }
            } else {
                if provider.WantsPhoneContact() {
                    ArrayPush(contacts, AiNpcBuildContactData(provider, isText));
                    if logging {
                        AiNpcLog(s"Phone contact '\(id)' was absent; injected.");
                    }
                } else {
                    // "Not there, and not asked to add it" is the one outcome with nothing to
                    // show for itself, and a compile-order problem looks exactly like it, so
                    // silence would leave a log with no trace of this file. Chatty: the phone
                    // rebuilds these lists often.
                    if logging {
                        AiNpcLog(s"Phone contact '\(id)' is not in the \(AiNpcPhoneListName(isText)) array; not injected (WantsPhoneContact is false).");
                    }
                }
            }
            i += 1;
        }
    }

    return contacts;
}

/// Hooks ///

// The contacts list: the pass above, then the rows of every contact the mod carries told to
// offer F and the messages key.
//
// THE SECOND PASS LIVES HERE FOR THE REASON THE FILE EXISTS, and it was measured the hard way on
// 2026-09-12. A framework inserts its contacts AFTER its own wrappedMethod returns
// (PhoneExtension.Overrides.reds:47), so a wrapper of ours running inside theirs walks an array
// their rows are not in yet: Mira's row never got isCallable, and the game hides the call hint
// on a row that says false (phoneDialerContact.script:128). F still worked, which is what makes
// the defect so quiet -- CallContact is answered by the mod before the vanilla check reads the
// field, so the gesture and its hint disagreed.
@wrapMethod(JournalManager)
public final func GetContactDataArray(includeUnknown: Bool, includeNonCallable: Bool) -> array<ref<IScriptable>> {
    let rows = AiNpcApplyPhoneContacts(wrappedMethod(includeUnknown, includeNonCallable), false);
    AiNpcGraftContactRows(rows);
    return rows;
}

// The messages list. Same pass, and the reason it is not skipped: a contact repaired in one
// list and not the other is exactly the half-present state this file exists to remove.
@wrapMethod(MessengerUtils)
public final static func GetSimpleContactDataArray(journal: ref<JournalManager>, includeUnknown: Bool, skipEmpty: Bool, includeWithNoUnread: Bool, opt activeDataSync: wref<MessengerContactSyncData>) -> array<ref<IScriptable>> {
    return AiNpcApplyPhoneContacts(
        wrappedMethod(journal, includeUnknown, skipEmpty, includeWithNoUnread, activeDataSync), true);
}
