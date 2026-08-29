// The strings the terminal site shows, and nothing else.
//
// Same shape as the chat-window labels in AiNpcLanguage.reds: one pure table per string,
// keyed by language, with English as the default so a language added to the enum without a
// line here half-works in English rather than showing nothing.
//
// Two deliberate differences:
//
//   * The tables that already exist are REUSED rather than re-translated -- the input
//     placeholder and the typing indicator are the phone's. A second translation of the same
//     sentence is a second thing to keep in step.
//   * The site's own name is not translated. "AGENT LINK" is a brand, and it is NOT the name
//     of the mod: "ai_npc" says what this is made of, which no application on a Night City
//     desktop would announce.
//
// Accented literals are safe in a .reds. The rule is about the FILE (UTF-8, no BOM, never
// written through PowerShell's Get-Content/Set-Content), and tools\lint.ps1 guards it.

module AiNpc

// The site's name, in the browser's site list and at the top of every page.
//
// An Agent is the pocket assistant every citizen carries -- the device the phone screen
// belongs to. This site is its companion on a desk: the same conversations, the other
// screen. Hence the name, which describes the pairing rather than the contents.
func AiNpcTerminalSiteTitle() -> String {
    return "AGENT LINK";
}

// The short name BrowserExtension puts under the icon. Kept separate from the title
// because that list has no room for a sentence.
func AiNpcTerminalSiteShortName() -> String {
    return "AGENT LINK";
}

func AiNpcTerminalContactsSubtitleFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "conversations";
        case AiNpcLanguage.Spanish:    return "conversaciones";
        case AiNpcLanguage.French:     return "conversations";
        case AiNpcLanguage.German:     return "Unterhaltungen";
        case AiNpcLanguage.Italian:    return "conversazioni";
        case AiNpcLanguage.Portuguese: return "conversas";
        case AiNpcLanguage.Russian:    return "переписки";
        case AiNpcLanguage.Ukraine:    return "розмови";
        default: return "conversations";
    }
}

func AiNpcTerminalNoContactsFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "No contact answers here yet.";
        case AiNpcLanguage.Spanish:    return "Ningún contacto responde aquí todavía.";
        case AiNpcLanguage.French:     return "Aucun contact ne répond ici pour l'instant.";
        case AiNpcLanguage.German:     return "Noch antwortet hier kein Kontakt.";
        case AiNpcLanguage.Italian:    return "Nessun contatto risponde qui per ora.";
        case AiNpcLanguage.Portuguese: return "Nenhum contacto responde aqui por agora.";
        case AiNpcLanguage.Russian:    return "Здесь пока никто не отвечает.";
        case AiNpcLanguage.Ukraine:    return "Тут поки ніхто не відповідає.";
        default: return "No contact answers here yet.";
    }
}

func AiNpcTerminalEmptyThreadFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "no messages";
        case AiNpcLanguage.Spanish:    return "sin mensajes";
        case AiNpcLanguage.French:     return "aucun message";
        case AiNpcLanguage.German:     return "keine Nachrichten";
        case AiNpcLanguage.Italian:    return "nessun messaggio";
        case AiNpcLanguage.Portuguese: return "sem mensagens";
        case AiNpcLanguage.Russian:    return "нет сообщений";
        case AiNpcLanguage.Ukraine:    return "немає повідомлень";
        default: return "no messages";
    }
}

func AiNpcTerminalBackFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "BACK";
        case AiNpcLanguage.Spanish:    return "VOLVER";
        case AiNpcLanguage.French:     return "RETOUR";
        case AiNpcLanguage.German:     return "ZURÜCK";
        case AiNpcLanguage.Italian:    return "INDIETRO";
        case AiNpcLanguage.Portuguese: return "VOLTAR";
        case AiNpcLanguage.Russian:    return "НАЗАД";
        case AiNpcLanguage.Ukraine:    return "НАЗАД";
        default: return "BACK";
    }
}

func AiNpcTerminalSendFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "SEND";
        case AiNpcLanguage.Spanish:    return "ENVIAR";
        case AiNpcLanguage.French:     return "ENVOYER";
        case AiNpcLanguage.German:     return "SENDEN";
        case AiNpcLanguage.Italian:    return "INVIA";
        case AiNpcLanguage.Portuguese: return "ENVIAR";
        case AiNpcLanguage.Russian:    return "ОТПРАВИТЬ";
        case AiNpcLanguage.Ukraine:    return "НАДІСЛАТИ";
        default: return "SEND";
    }
}

// The one line of instruction the page carries. A terminal has no key hints of its own --
// the phone chat's C / R / Z do not exist here -- so this says the only thing a player
// cannot guess: that the field takes the keyboard once clicked.
func AiNpcTerminalHintFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "Click the field, type, Enter to send.";
        case AiNpcLanguage.Spanish:    return "Haz clic en el campo, escribe, Intro para enviar.";
        case AiNpcLanguage.French:     return "Cliquer dans le champ, écrire, Entrée pour envoyer.";
        case AiNpcLanguage.German:     return "Feld anklicken, tippen, Enter zum Senden.";
        case AiNpcLanguage.Italian:    return "Clicca sul campo, scrivi, Invio per inviare.";
        case AiNpcLanguage.Portuguese: return "Clica no campo, escreve, Enter para enviar.";
        case AiNpcLanguage.Russian:    return "Нажмите на поле, наберите текст, Enter — отправить.";
        case AiNpcLanguage.Ukraine:    return "Натисніть на поле, наберіть текст, Enter — надіслати.";
        default: return "Click the field, type, Enter to send.";
    }
}

func AiNpcTerminalBusyFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "waiting for an answer...";
        case AiNpcLanguage.Spanish:    return "esperando respuesta...";
        case AiNpcLanguage.French:     return "en attente d'une réponse...";
        case AiNpcLanguage.German:     return "warte auf Antwort...";
        case AiNpcLanguage.Italian:    return "in attesa di risposta...";
        case AiNpcLanguage.Portuguese: return "à espera de resposta...";
        case AiNpcLanguage.Russian:    return "ждём ответа...";
        case AiNpcLanguage.Ukraine:    return "чекаємо на відповідь...";
        default: return "waiting for an answer...";
    }
}

func AiNpcTerminalUnsupportedFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "this contact does not answer here";
        case AiNpcLanguage.Spanish:    return "este contacto no responde aquí";
        case AiNpcLanguage.French:     return "ce contact ne répond pas ici";
        case AiNpcLanguage.German:     return "dieser Kontakt antwortet hier nicht";
        case AiNpcLanguage.Italian:    return "questo contatto non risponde qui";
        case AiNpcLanguage.Portuguese: return "este contacto não responde aqui";
        case AiNpcLanguage.Russian:    return "этот контакт здесь не отвечает";
        case AiNpcLanguage.Ukraine:    return "цей контакт тут не відповідає";
        default: return "this contact does not answer here";
    }
}

func AiNpcTerminalSortByRecentFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "RECENT";
        case AiNpcLanguage.Spanish:    return "RECIENTES";
        case AiNpcLanguage.French:     return "RECENTS";
        case AiNpcLanguage.German:     return "NEUESTE";
        case AiNpcLanguage.Italian:    return "RECENTI";
        case AiNpcLanguage.Portuguese: return "RECENTES";
        case AiNpcLanguage.Russian:    return "НЕДАВНИЕ";
        case AiNpcLanguage.Ukraine:    return "НЕЩОДАВНІ";
        default: return "RECENT";
    }
}

// Not translated on purpose: A-Z is read as an ordering everywhere the mod speaks, and a
// localised "alphabetical" is a long word in a short button.
func AiNpcTerminalSortByNameLabel() -> String {
    return "A - Z";
}

// The word in front of the two buttons, so a player knows the pair is a control rather
// than two more destinations.
func AiNpcTerminalSortByFor(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.English:    return "sort";
        case AiNpcLanguage.Spanish:    return "orden";
        case AiNpcLanguage.French:     return "tri";
        case AiNpcLanguage.German:     return "Sortierung";
        case AiNpcLanguage.Italian:    return "ordine";
        case AiNpcLanguage.Portuguese: return "ordem";
        case AiNpcLanguage.Russian:    return "сортировка";
        case AiNpcLanguage.Ukraine:    return "сортування";
        default: return "sort";
    }
}

//
// The page code calls these, never the tables above: a drawing function that has to ask what
// language is in force before it can write a caption is a drawing function with a setting in
// it.

func AiNpcTerminalContactsSubtitle() -> String {
    return AiNpcTerminalContactsSubtitleFor(AiNpcResolveLanguage());
}

func AiNpcTerminalNoContactsLabel() -> String {
    return AiNpcTerminalNoContactsFor(AiNpcResolveLanguage());
}

func AiNpcTerminalEmptyThreadLabel() -> String {
    return AiNpcTerminalEmptyThreadFor(AiNpcResolveLanguage());
}

func AiNpcTerminalBackLabel() -> String {
    return AiNpcTerminalBackFor(AiNpcResolveLanguage());
}

func AiNpcTerminalSendLabel() -> String {
    return AiNpcTerminalSendFor(AiNpcResolveLanguage());
}

func AiNpcTerminalHintLabel() -> String {
    return AiNpcTerminalHintFor(AiNpcResolveLanguage());
}

func AiNpcTerminalBusyLabel() -> String {
    return AiNpcTerminalBusyFor(AiNpcResolveLanguage());
}

func AiNpcTerminalUnsupportedLabel() -> String {
    return AiNpcTerminalUnsupportedFor(AiNpcResolveLanguage());
}

func AiNpcTerminalSortByRecentLabel() -> String {
    return AiNpcTerminalSortByRecentFor(AiNpcResolveLanguage());
}

func AiNpcTerminalSortByLabel() -> String {
    return AiNpcTerminalSortByFor(AiNpcResolveLanguage());
}

// The input placeholder is the phone's own: the same field, on another screen.
func AiNpcTerminalPlaceholder() -> String {
    return AiNpcStartTypingLabel(AiNpcResolveLanguage());
}
