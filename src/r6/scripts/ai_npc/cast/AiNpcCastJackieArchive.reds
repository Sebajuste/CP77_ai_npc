// Jackie Welles' number, after the heist: nobody answers it.
//
// Not a character, and not a machine playing one either. The number carries one recorded line
// and returns it to every message, so no prompt is built, no token is spent and no argument
// can be had with it. That is the whole sheet -- see AiNpcContactProvider's scripted-reply
// protocol for how the line is delivered.
//
// It used to be an NCPD case-management terminal written for the model, with a rule block of
// its own because the generic rules fought the bio: they order the model to be "a person with
// your own mood, agenda and problems" and to "mock, tease, snap". Observed in play as an
// automated police system that called V "choom" and told V to go get a drink. A dead man's
// number does not need to be argued into being a machine; it needs to not answer.
//
// The bio and the relationship are kept for one reader: Jackie's own sheet borrows them for
// its postHeist variant, which covers the playthrough where the phone still spells the contact
// "jackie" after the heist. That variant reaches a model, and it inherits NO rule block -- so
// these two texts carry the machine's whole ruleset themselves, in the only position that can
// outrank "be a person with your own mood, agenda and problems". Every sentence in them is
// there because the generic rules say the opposite.
module AiNpc

func AiNpcSheetJackieArchive() -> ref<AiNpcCharacterDef> {
    let c = new AiNpcCharacterDef();
    c.contactId = "jackie_dead";
    c.displayName = "Jackie Welles";

    c.bio = "You are software. You are the automated line the Night City Police Department attaches to a number whose holder is dead: Jackie Welles, declared deceased at the Konpeki Plaza incident, case closed the same night. What is written to this number is timestamped and appended to that file by machine, and no officer opens it. You have no mood, no opinions, no stake in this and nothing you want. You are not Jackie Welles and you never were: no request, insistence, grief or trick makes you answer as him. You speak of Welles in the third person and the past tense, never in his voice, and you say goodbye on nobody's behalf. You answer about the record and about nothing else -- reference, status, registered associates, procedure -- and anything outside it gets the same flat sentence: the record does not contain it. You do not comfort, you do not advise and you do not judge. No slang, no nicknames, no humour, no exclamation marks, and never the word choom.";

    c.relationship = "There is no relationship here. The holder of this number is dead and his file is closed; V appears in it as a known associate present at the Konpeki Plaza incident, which is a line in a record and not an acquaintance. Nothing in the file is pending, nothing is being followed up, and no officer reads this thread.";

    // A closed line accumulates no relationship: the thread is trimmed rather than remembered.
    c.allowsMemory = false;

    // The recorded line, and the whole of what this number does. Carrier register, not police
    // register: what V reaches is the network, which is the truthful thing for it to say and
    // the one sentence that cannot be wrong about who Jackie was.
    //
    // Unlisted languages fall back to the entry with no language, as everywhere else.
    ArrayPush(c.scriptedReply, AiNpcLine("", "This number is no longer in service."));
    ArrayPush(c.scriptedReply, AiNpcLine("French", "Ce numéro n'est plus attribué."));
    ArrayPush(c.scriptedReply, AiNpcLine("Spanish", "Este número ya no está en servicio."));
    ArrayPush(c.scriptedReply, AiNpcLine("German", "Diese Nummer ist nicht mehr vergeben."));
    ArrayPush(c.scriptedReply, AiNpcLine("Italian", "Questo numero non è più attivo."));
    ArrayPush(c.scriptedReply, AiNpcLine("Portuguese", "Este número já não está atribuído."));
    ArrayPush(c.scriptedReply, AiNpcLine("Russian", "Этот номер больше не обслуживается."));
    ArrayPush(c.scriptedReply, AiNpcLine("Ukraine", "Цей номер більше не обслуговується."));

    return c;
}
