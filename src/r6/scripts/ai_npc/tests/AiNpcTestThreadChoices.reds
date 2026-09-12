// Les choix du fil, et la ligne qu'ai_npc ajoute au telephone pour un contact d'un autre mod.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.
//
// Le fournisseur est construit ici et passe a la moitie pure : le registre n'existe pas encore
// quand ces lignes tournent.

module AiNpc

class AiNpcTestChoiceProvider extends AiNpcContactProvider {
    public let choices: array<ref<AiNpcThreadChoice>>;
    public let picked: array<String>;

    public func GetContactId() -> String {
        return "test_choices";
    }

    public func GetDisplayName() -> String {
        return "Choices";
    }

    public func WantsPhoneContact() -> Bool {
        return true;
    }

    public func GetThreadChoices() -> array<ref<AiNpcThreadChoice>> {
        return this.choices;
    }

    public func OnThreadChoice(choiceId: String) -> Void {
        ArrayPush(this.picked, choiceId);
    }
}

func AiNpcTestThreadChoices(t: ref<AiNpcTestRunner>) -> Void {
    t.EqInt("choices/key 1 picks the first", AiNpcThreadChoiceKeyIndex("IK_1"), 0);
    t.EqInt("choices/key 9 picks the ninth", AiNpcThreadChoiceKeyIndex("IK_9"), 8);
    t.EqInt("choices/key 0 picks none", AiNpcThreadChoiceKeyIndex("IK_0"), -1);
    t.EqInt("choices/a chat key picks none", AiNpcThreadChoiceKeyIndex("IK_R"), -1);

    let made = AiNpcThreadChoiceOf("block", "Bloquer");
    t.EqString("choices/a choice keeps its id", made.id, "block");
    t.EqString("choices/and its label", made.label, "Bloquer");

    let nobody: ref<AiNpcContactProvider>;
    let none = AiNpcThreadChoicesOf(nobody, "x");
    t.EqInt("choices/no provider offers none", ArraySize(none), 0);
    t.EqBool("choices/and nothing can be picked", AiNpcThreadChooseOn(nobody, "x", 0), false);

    let two = new AiNpcTestChoiceProvider();
    two.choices = [AiNpcThreadChoiceOf("a", "A"), AiNpcThreadChoiceOf("b", "B")];
    let shown = AiNpcThreadChoicesOf(two, two.GetContactId());
    t.EqInt("choices/every declared choice is shown", ArraySize(shown), 2);
    if ArraySize(shown) == 2 {
        t.EqString("choices/in the declared order", shown[1].id, "b");
    }
    t.EqBool("choices/a shown choice can be picked", AiNpcThreadChooseOn(two, two.GetContactId(), 1), true);
    t.EqInt("choices/the provider is told once", ArraySize(two.picked), 1);
    if ArraySize(two.picked) == 1 {
        t.EqString("choices/with the id of the one picked", two.picked[0], "b");
    }
    t.EqBool("choices/past the last one nothing is picked",
        AiNpcThreadChooseOn(two, two.GetContactId(), 2), false);
    t.EqBool("choices/nor before the first", AiNpcThreadChooseOn(two, two.GetContactId(), -1), false);
    t.EqInt("choices/and the provider is not told", ArraySize(two.picked), 1);

    let blank = new AiNpcTestChoiceProvider();
    blank.choices = [AiNpcThreadChoiceOf("", "Rien"), AiNpcThreadChoiceOf("c", "C")];
    let kept = AiNpcThreadChoicesOf(blank, blank.GetContactId());
    t.EqInt("choices/a choice with no id is not shown", ArraySize(kept), 1);
    AiNpcThreadChooseOn(blank, blank.GetContactId(), 0);
    if ArraySize(blank.picked) == 1 {
        t.EqString("choices/and positions count what is shown", blank.picked[0], "c");
    } else {
        t.Check("choices/and positions count what is shown", false);
    }

    let many = new AiNpcTestChoiceProvider();
    let i = 0;
    while i < AiNpcThreadChoiceLimit() + 2 {
        ArrayPush(many.choices, AiNpcThreadChoiceOf(s"c\(i)", s"C\(i)"));
        i += 1;
    }
    let capped = AiNpcThreadChoicesOf(many, many.GetContactId());
    t.EqInt("choices/no more than the keys can reach", ArraySize(capped), AiNpcThreadChoiceLimit());
}

// La ligne qu'ai_npc met dans le telephone : c'est elle qui ouvre son chat et qui offre F.
func AiNpcTestInjectedRow(t: ref<AiNpcTestRunner>) -> Void {
    let provider = new AiNpcTestChoiceProvider();

    let thread = AiNpcBuildContactData(provider, true);
    t.EqString("row/it names the provider's contact", thread.contactId, provider.GetContactId());
    t.Check("row/it is the mod's own conversation", thread.ainpcThread);
    t.Check("row/it offers F", thread.isCallable);
    t.Check("row/in the messages tab it is a thread",
        Equals(thread.type, MessengerContactType.SingleThread));
    t.Check("row/and the messages key opens the mod's chat",
        Equals(AiNpcInboxOf(thread, false, false), AiNpcInbox.Chat));

    let contact = AiNpcBuildContactData(provider, false);
    t.Check("row/in the contact list it is a contact", Equals(contact.type, MessengerContactType.Contact));
    t.Check("row/and it opens the mod's chat there too",
        Equals(AiNpcInboxOf(contact, false, false), AiNpcInbox.Chat));
    t.Check("row/it offers F there too", contact.isCallable);
}

// Un contact livre par un autre mod : le jeu n'en sait rien, donc c'est nous qui dessinons ses
// deux conversations. Le hachage est celui que Juli ecrit en dur dans son propre mod.
func AiNpcTestSharedInbox(t: ref<AiNpcTestRunner>) -> Void {
    let foreign = new ContactData();
    foreign.contactId = "JuliContact";
    foreign.hash = 55667788;
    foreign.localizedName = "Juli";
    foreign.type = MessengerContactType.Contact;
    foreign.messagesCount = 1;
    foreign.isCallable = true;

    // Non enregistre dans ce test, donc non porte par le mod : la ligne appartient au jeu.
    t.Check("inbox/a line the mod does not carry stays the game's",
        Equals(AiNpcInboxOf(foreign, false, false), AiNpcInbox.Game));

    let rows = AiNpcSharedConversations(foreign);
    t.EqInt("inbox/a shared contact has two conversations", ArraySize(rows), 2);

    let ours = rows[0] as ContactData;
    let theirs = rows[1] as ContactData;
    t.Check("inbox/ours comes first", IsDefined(ours) && ours.ainpcThread);
    t.Check("inbox/theirs is a conversation, not a contact",
        IsDefined(theirs) && Equals(theirs.type, MessengerContactType.SingleThread));
    t.Check("inbox/and theirs is not ours", IsDefined(theirs) && !theirs.ainpcThread);
    t.EqInt("inbox/theirs keeps the hash its own mod answers to", theirs.hash, foreign.hash);

    // Une liste deja a l'ecran : chaque ligne EST une conversation, et chacune s'ouvre chez son
    // proprietaire.
    t.Check("inbox/inside a list the game opens theirs",
        Equals(AiNpcInboxOf(theirs, false, true), AiNpcInbox.Game));
    t.Check("inbox/and ours still opens the chat",
        Equals(AiNpcInboxOf(ours, false, true), AiNpcInbox.Chat));
}
