// What language the mod speaks, and everything keyed by that answer: the locale table, the
// enum member names prompts.json is keyed by, the language rule sent to the model, the default
// form of address, and the carrier message. One file, because a language added to the enum
// without a line in each of these half works, and adjacency is what makes that visible.

module AiNpc

// The one thing the player is told when a reply cannot be produced. Every failure reads as the
// carrier being down, whatever happened: a chat window is V's phone, not a console, and "[NO
// SIGNAL: HTTP 0]" broke the fiction while telling the player nothing they could act on. The
// cause goes to the log through FTLogError instead, unconditionally, naming the provider and
// the url.
//
// The support number is in the +1 555 range, reserved for fiction, so it can never dial a real
// person -- and it is a stable string to grep the log and the journal for.
//
// Accented literals are safe: measured 2026-08-19, 784 installed .reds files carry 423
// non-ASCII literals. The rule is about the file, not the letters -- UTF-8, no BOM, never
// written through PowerShell's Get-Content/Set-Content, which tools/lint.ps1 guards.
//
// Keyed by language rather than resolved here, so the table is pure and every member can be
// pinned without a session.
func AiNpcCarrierMessageFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.French:
            return "Réseau mobile Night City injoignable. Contactez notre support au +1 555 0134";
        case AiNpcLanguage.Spanish:
            return "Red móvil de Night City no disponible. Contacte con soporte en el +1 555 0134";
        case AiNpcLanguage.German:
            return "Mobilfunknetz Night City nicht erreichbar. Support erreichbar unter +1 555 0134";
        case AiNpcLanguage.Italian:
            return "Rete mobile di Night City irraggiungibile. Contatta l'assistenza al +1 555 0134";
        case AiNpcLanguage.Portuguese:
            return "Rede móvel de Night City indisponível. Contacte o suporte pelo +1 555 0134";
        case AiNpcLanguage.Russian:
            return "Мобильная сеть Найт-Сити недоступна. Служба поддержки: +1 555 0134";
        case AiNpcLanguage.Ukraine:
            return "Мобільна мережа Найт-Сіті недоступна. Служба підтримки: +1 555 0134";
    }
    // English, and the fallback for anything added to the enum without a line here: a missing
    // case must still produce a sentence, never an empty bubble.
    return "Night City mobile network unreachable. Contact support at +1 555 0134";
}

// The same message for the language in force. Not pure, which is why the table above is a
// separate function.
func AiNpcCarrierMessage() -> String {
    return AiNpcCarrierMessageFor(AiNpcResolveLanguage());
}

// What the player is told when the day's token budget is spent: a telecom fact, not an error --
// an allowance ran out, it comes back tomorrow, and there is a number to call.
//
// Not the carrier line, which means the network is down: reusing it would send a player
// hunting a connection problem they do not have, when what happened is a ceiling they set
// themselves in a menu.
//
// Keyed by language rather than resolved here, so every member can be pinned with no session.
func AiNpcBudgetSpentMessageFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.French:
            return "Forfait data épuisé pour aujourd'hui. Remise à zéro demain. Rechargez au +1 555 0134";
        case AiNpcLanguage.Spanish:
            return "Datos del día agotados. Se restablecen mañana. Recarga en el +1 555 0134";
        case AiNpcLanguage.German:
            return "Tagesdatenvolumen aufgebraucht. Zurücksetzung morgen. Aufladen unter +1 555 0134";
        case AiNpcLanguage.Italian:
            return "Dati giornalieri esauriti. Azzeramento domani. Ricarica al +1 555 0134";
        case AiNpcLanguage.Portuguese:
            return "Dados diários esgotados. Reposição amanhã. Carregue pelo +1 555 0134";
        case AiNpcLanguage.Russian:
            return "Дневной лимит данных исчерпан. Обновление завтра. Пополнение: +1 555 0134";
        case AiNpcLanguage.Ukraine:
            return "Денний ліміт даних вичерпано. Оновлення завтра. Поповнення: +1 555 0134";
    }
    return "Daily data allowance spent. It resets tomorrow. Top up at +1 555 0134";
}

// The line before it, at four fifths of the budget, sent once a day. Without it the ceiling is
// met mid-conversation, which reads as a character who stopped answering, and the player has
// no chance to spend what is left on the conversation they care about.
func AiNpcBudgetWarningMessageFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.French:
            return "Info réseau : 80% de votre forfait data du jour est consommé. Rechargez au +1 555 0134";
        case AiNpcLanguage.Spanish:
            return "Aviso de red: has consumido el 80% de tus datos del día. Recarga en el +1 555 0134";
        case AiNpcLanguage.German:
            return "Netzhinweis: 80% Ihres Tagesdatenvolumens sind verbraucht. Aufladen unter +1 555 0134";
        case AiNpcLanguage.Italian:
            return "Avviso di rete: hai consumato l'80% dei dati giornalieri. Ricarica al +1 555 0134";
        case AiNpcLanguage.Portuguese:
            return "Aviso de rede: consumiu 80% dos dados do dia. Carregue pelo +1 555 0134";
        case AiNpcLanguage.Russian:
            return "Сеть: израсходовано 80% дневного лимита данных. Пополнение: +1 555 0134";
        case AiNpcLanguage.Ukraine:
            return "Мережа: витрачено 80% денного ліміту даних. Поповнення: +1 555 0134";
    }
    return "Network notice: 80% of your daily data allowance is gone. Top up at +1 555 0134";
}

// The same two for the language in force. Not pure, which is why the tables above are separate
// functions.
func AiNpcBudgetSpentMessage() -> String {
    return AiNpcBudgetSpentMessageFor(AiNpcResolveLanguage());
}

func AiNpcBudgetWarningMessage() -> String {
    return AiNpcBudgetWarningMessageFor(AiNpcResolveLanguage());
}

// The same failure, said technically: the bug report, delivered where the failure was noticed
// rather than in a log the player has to know exists. It comes after the carrier line -- the
// first is what the phone would say, the second what the mod knows.
//
// Sent only with Debug Mode on, and that gate lives at the call site so this function stays
// pure and always answers.
//
// Not translated: it is meant to be pasted into an issue and grepped for, and someone who
// turned Debug Mode on is reading it as a diagnostic rather than as dialogue.
func AiNpcDiagnosticMessage(provider: String, url: String, detail: String) -> String {
    let out = s"[ai_npc] provider \(provider)";
    if NotEquals(StrLen(url), 0) {
        out += s"\nurl \(url)";
    }
    if NotEquals(StrLen(detail), 0) {
        out += s"\n\(detail)";
    }
    return out;
}

// Enum member names as strings, in declaration order. prompts.json keys its language overrides
// by these, so a typo can be reported instead of silently doing nothing.
func AiNpcLanguageNames() -> array<String> {
    return ["English", "Spanish", "French", "German", "Italian", "Portuguese", "Russian", "Ukraine"];
}

// The locale the game displays text in. Read from the vanilla user settings rather than
// Codeware's LocalizationSystem: it is the /language OnScreen var the player picked, and it
// costs no extra dependency. n"" before the settings system exists, read as "keep English".
func AiNpcGameTextLanguage() -> CName {
    let settings = GameInstance.GetSettingsSystem(GetGameInstance());
    if !IsDefined(settings) {
        return n"";
    }

    let var = settings.GetVar(n"/language", n"OnScreen") as ConfigVarListName;
    if !IsDefined(var) {
        return n"";
    }
    return var.GetValue();
}

// The locale the game SPEAKS in, which is not the one it writes in.
//
// Cyberpunk installs voice-over and subtitles separately, and a player on French subtitles with
// English voice-over is an ordinary configuration -- the launcher offers exactly that. The
// reference clips a cloned voice is built from live in lang_<code>_voice.archive, so this is the
// one that decides which archive to open. Reading the text language here would clone the wrong
// performance, and it would do it silently: the accent is the only symptom.
//
// n"" before the settings system exists. The DLL answers "no voice-over is known for the locale"
// and falls back to the system voice, which is the truthful outcome.
func AiNpcVoiceOverLocale() -> String {
    let settings = GameInstance.GetSettingsSystem(GetGameInstance());
    if !IsDefined(settings) {
        return "";
    }

    let var = settings.GetVar(n"/language", n"VoiceOver") as ConfigVarListName;
    if !IsDefined(var) {
        return "";
    }
    return NameToString(var.GetValue());
}

// Locale code to the closest language the mod can write prompts in. Anything unmapped falls
// back to English rather than to silence: an English instruction produces an English reply,
// where no instruction produces whatever the model feels like.
func AiNpcLanguageFromLocale(code: CName) -> AiNpcLanguage {
    switch code {
        case n"es-es":
        case n"es-mx":
            return AiNpcLanguage.Spanish;
        case n"fr-fr":
            return AiNpcLanguage.French;
        case n"de-de":
            return AiNpcLanguage.German;
        case n"it-it":
            return AiNpcLanguage.Italian;
        case n"pt-br":
            return AiNpcLanguage.Portuguese;
        case n"ru-ru":
            return AiNpcLanguage.Russian;
        // Not an official CDPR locale; set by the community Ukrainian localisation.
        case n"uk-ua":
        case n"ua-ua":
            return AiNpcLanguage.Ukraine;
        default:
            return AiNpcLanguage.English;
    }
}

// The game's own text language, always. Nothing to configure, for the same reason V's gender
// is not: the game already answers, and a menu that can disagree with it can be wrong.
public func AiNpcResolveLanguage() -> AiNpcLanguage {
    return AiNpcLanguageFromLocale(AiNpcGameTextLanguage());
}

// The T-V distinction, which only some languages have. It belongs to the speech style rather
// than the language rule, because it is a fact about a character -- a fixer and a corporate
// client do not address V the same way -- and inside the language rule it would be MANDATORY,
// which no per-contact text can outrank.
func AiNpcDefaultSpeechStyle() -> String {
    switch AiNpcResolveLanguage() {
        case AiNpcLanguage.French:
            return "Les personnages se tutoient.";
        case AiNpcLanguage.Spanish:
            return "Los personajes se tutean.";
        case AiNpcLanguage.German:
            return "Die Charaktere duzen sich.";
        case AiNpcLanguage.Italian:
            return "I personaggi si danno del tu.";
        case AiNpcLanguage.Portuguese:
            return "As personagens tratam-se por tu.";
        case AiNpcLanguage.Russian:
            return "Персонажи обращаются друг к другу на «ты».";
        case AiNpcLanguage.Ukraine:
            return "Персонажі звертаються одне до одного на «ти».";
        default:
            // English has no T-V distinction; there is nothing to say by default.
            return "";
    }
}

// The current language as its enum member name, which is how prompts.json keys its
// language overrides.
func AiNpcCurrentLanguageName() -> String {
    let names = AiNpcLanguageNames();
    let index = EnumInt(AiNpcResolveLanguage());
    if index >= 0 && index < ArraySize(names) {
        return names[index];
    }
    return "English";
}

// The one section that does not go through AiNpcConfiguredSection: it must not be expanded,
// since this text is itself the {language} variable and the expansion pass would loop, and its
// global level is a lookup rather than a field.
//
// Written out by hand, with the same three levels and the same "" for no opinion. Neither
// source can be null, so there is no IsDefined test and adding one would imply a state that
// cannot occur.
func AiNpcGetLanguagePrompt(contactId: String) -> String {
    let over = AiNpcPromptOverridesFor(contactId).language;
    if NotEquals(StrLen(over), 0) {
        return over;
    }

    let global = AiNpcGetPromptConfig().GetLanguage(AiNpcCurrentLanguageName());
    if NotEquals(StrLen(global), 0) {
        return global;
    }

    return AiNpcBuiltinLanguageRule(AiNpcResolveLanguage());
}

// Keyed by language rather than resolving it, like every other table in this file: the eight
// rules are then assertable without a session, and a language added to the enum with no case
// of its own falls to English rather than to nothing.
func AiNpcBuiltinLanguageRule(language: AiNpcLanguage) -> String {
    // Two clauses, and no more: the language to write in, and the ban on the transcript's own
    // grammar. Everything the inherited version also said -- keep it short, write as the
    // character, answer like a text message -- is stated once elsewhere, in LENGTH, in FORM
    // and in <fiction>, and saying it a second time here taught the model it had two rules to
    // arbitrate between.
    //
    // The name ban is the one clause that has no home but this block: the transcript is built
    // as "<name>: line" and the stop sequences read that grammar, so a reply that opens with
    // its own name is cut at the colon.
    //
    // Each rule is written IN its language, which is the priming this block exists for -- a
    // model told in French to write French does both at once. English is the fallthrough, so a
    // member added to the enum without a line here still gets a whole rule.
    switch language {
        case AiNpcLanguage.Spanish:
            return "LANGUAGE: es. Escribe únicamente en español. Nunca pongas tu nombre delante de tu respuesta, como \"nombre: mensaje\".";
        case AiNpcLanguage.French:
            // No tutoiement rule here: it is a character trait, not a property of French.
            // AiNpcDefaultSpeechStyle applies it and lets a contact say otherwise, which a
            // line in this block could not.
            return "LANGUAGE: fr. Écris uniquement en français. Ne mets jamais ton nom devant ta réponse, comme \"nom : message\".";
        case AiNpcLanguage.German:
            return "LANGUAGE: de. Schreibe ausschließlich auf Deutsch. Stelle deiner Antwort niemals deinen eigenen Namen voran, wie \"Name: Nachricht\".";
        case AiNpcLanguage.Italian:
            return "LANGUAGE: it. Scrivi esclusivamente in italiano. Non anteporre mai il tuo nome alla risposta, come \"nome: messaggio\".";
        case AiNpcLanguage.Portuguese:
            return "LANGUAGE: pt. Escreva apenas em português. Nunca coloque seu nome antes da resposta, como \"nome: mensagem\".";
        case AiNpcLanguage.Russian:
            return "LANGUAGE: ru. Пиши только на русском. Никогда не ставь своё имя перед ответом, как \"имя: сообщение\".";
        case AiNpcLanguage.Ukraine:
            return "LANGUAGE: uk. Пиши лише українською. Ніколи не став своє ім’я перед відповіддю, як \"ім’я: повідомлення\".";
    }

    return "LANGUAGE: en. Write only in English. Never put your own name in front of your reply, as in \"name: message\".";
}

/// UI labels ///

// The strings the chat window shows: the typing indicator, the header, the input placeholder
// and the four key hints. Tables keyed by AiNpcLanguage like everything above, so adding a
// language does not mean remembering a second file. Pure, so all forty-eight translations are
// assertable without a session.

// Leading space included in every translation: the caller concatenates it onto the contact's
// name, and a name is not a place for a separator that varies by language.
func AiNpcIsTypingLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:
            return " is typing";
        case AiNpcLanguage.Spanish:
            return " está escribiendo";
        case AiNpcLanguage.French:
            return " écrit";
        case AiNpcLanguage.German:
            return " schreibt";
        case AiNpcLanguage.Italian:
            return " sta scrivendo";
        case AiNpcLanguage.Portuguese:
            return " está digitando";
        case AiNpcLanguage.Russian:
            return " печатает";
        case AiNpcLanguage.Ukraine:
            return " Друкує";
        default:
            return " is typing";
    }
}


// The header title.
func AiNpcMessagesHeaderLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Messages";
        case AiNpcLanguage.Spanish:    return "Mensajes";
        case AiNpcLanguage.French:     return "Messages";
        case AiNpcLanguage.German:     return "Nachrichten";
        case AiNpcLanguage.Italian:    return "Messaggi";
        case AiNpcLanguage.Portuguese: return "Mensagens";
        case AiNpcLanguage.Russian:    return "Сообщения";
        case AiNpcLanguage.Ukraine:    return "Повідомлення";
        default: return "Messages";
    }
}

// The resting input line.
func AiNpcSendMessageLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Send a message.";
        case AiNpcLanguage.Spanish:    return "Enviar mensaje.";
        case AiNpcLanguage.French:     return "Envoyer un message.";
        case AiNpcLanguage.German:     return "Nachricht senden.";
        case AiNpcLanguage.Italian:    return "Invia messaggio.";
        case AiNpcLanguage.Portuguese: return "Enviar mensagem.";
        case AiNpcLanguage.Russian:    return "Отправить сообщение.";
        case AiNpcLanguage.Ukraine:    return "Відправити повідомлення.";
        default: return "Send a message.";
    }
}

// The input placeholder, once the field has focus.
func AiNpcStartTypingLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Start Typing...";
        case AiNpcLanguage.Spanish:    return "Escribir mensaje...";
        case AiNpcLanguage.French:     return "Écrire un message...";
        case AiNpcLanguage.German:     return "Nachricht eingeben...";
        case AiNpcLanguage.Italian:    return "Scrivi messaggio...";
        case AiNpcLanguage.Portuguese: return "Escrever mensagem...";
        case AiNpcLanguage.Russian:    return "Написать сообщение...";
        case AiNpcLanguage.Ukraine:    return "Написати повідомлення...";
        default: return "Start Typing...";
    }
}

// What C does on the chat: one screen up, onto the contact list. It says back rather than
// close, because on this screen it closes nothing.
func AiNpcBackLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Back";
        case AiNpcLanguage.Spanish:    return "Volver";
        case AiNpcLanguage.French:     return "Retour";
        case AiNpcLanguage.German:     return "Zurück";
        case AiNpcLanguage.Italian:    return "Indietro";
        case AiNpcLanguage.Portuguese: return "Voltar";
        case AiNpcLanguage.Russian:    return "Назад";
        case AiNpcLanguage.Ukraine:    return "Назад";
        default: return "Back";
    }
}

// What R does.
func AiNpcResetLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Reset";
        case AiNpcLanguage.Spanish:    return "Reiniciar";
        case AiNpcLanguage.French:     return "Réinitialiser";
        case AiNpcLanguage.German:     return "Zurücksetzen";
        case AiNpcLanguage.Italian:    return "Reimposta";
        case AiNpcLanguage.Portuguese: return "Reiniciar";
        case AiNpcLanguage.Russian:    return "Сброс";
        case AiNpcLanguage.Ukraine:    return "Скидання";
        default: return "Reset";
    }
}

// R on a call.
func AiNpcCallReplyLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Reply";
        case AiNpcLanguage.Spanish:    return "Responder";
        case AiNpcLanguage.French:     return "Répondre";
        case AiNpcLanguage.German:     return "Antworten";
        case AiNpcLanguage.Italian:    return "Rispondi";
        case AiNpcLanguage.Portuguese: return "Responder";
        case AiNpcLanguage.Russian:    return "Ответить";
        case AiNpcLanguage.Ukraine:    return "Відповісти";
        default: return "Reply";
    }
}

// Hold T on a call the mod placed.
func AiNpcCallHangUpLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Hang up";
        case AiNpcLanguage.Spanish:    return "Colgar";
        case AiNpcLanguage.French:     return "Raccrocher";
        case AiNpcLanguage.German:     return "Auflegen";
        case AiNpcLanguage.Italian:    return "Riaggancia";
        case AiNpcLanguage.Portuguese: return "Desligar";
        case AiNpcLanguage.Russian:    return "Завершить";
        case AiNpcLanguage.Ukraine:    return "Завершити";
        default: return "Hang up";
    }
}

// What Z does, in Debug Mode.
func AiNpcUndoLabel(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Undo";
        case AiNpcLanguage.Spanish:    return "Deshacer";
        case AiNpcLanguage.French:     return "Annuler";
        case AiNpcLanguage.German:     return "Rückgängig";
        case AiNpcLanguage.Italian:    return "Annulla";
        case AiNpcLanguage.Portuguese: return "Desfazer";
        case AiNpcLanguage.Russian:    return "Отменить";
        case AiNpcLanguage.Ukraine:    return "Скасувати";
        default: return "Undo";
    }
}

// The crude vocabulary the explicitness tiers hand out, in the language the conversation is
// written in. Read out of the game rather than written from memory, by ai_npc_lab/lexicon: for one
// English term, take every on-screen line carrying it, look at the same lines in French, and
// keep the word that covers them. Measured 2026-08-27, with the evidence each answer rests on:
// putain (x62), merde (x67, plus the UI label "Merde"), foutre (x25), cul (x23), salope (x8),
// couilles (x4), bite (x4), pute (x5), connard (x4), enfoire (x2), chatte (one line).
//
// Left out for lack of a sure answer, the same rule the WORDS table follows: cunt, which the
// game renders as enfoire rather than with a word of its own; whore and slut, already covered
// by pute and salope; tits, whose French line is seins -- anatomical, not crude, and a wrong
// entry in a list of crudest words. cock appears in no English line of the game at all.
//
// A language with no table gets the English words marked as English, so a model writing German
// reads them as the measure of how far it may go rather than as the words to type. That is the
// fallback, not the answer: the answer is a table read out of the game, and there is one only
// for the language somebody here can proofread.
func AiNpcCrudeWordsFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.French:
            return "CRUDE WORDS -- write these rather than a polite synonym. They are what Cyberpunk 2077 itself says in French: putain, merde, foutre, cul, couilles, bite, chatte, salope, pute, connard, enfoiré.";
    }

    return "CRUDE WORDS -- write the crudest word your language has rather than a polite synonym. In English: pussy, cunt, cock, fuck, motherfucker, whore, slut, asshole.";
}
