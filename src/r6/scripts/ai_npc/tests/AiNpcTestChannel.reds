// Le canal : ce qui se stocke, ce qui se filtre, et ce qu'une voix ne doit pas dire.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.
//
// Tout ce qui est asserte ici est pur. `Send` et `Deliver` ne le sont pas et ne peuvent pas
// l'etre : ils atteignent des systemes, et aucun n'existe au moment ou ces lignes tournent.

module AiNpc

import RedData.Json.*

// La valeur relue du disque. Un entier hors table rend Text, parce qu'un journal ecrit par une
// version plus recente ne doit pas faire disparaitre une conversation.
func AiNpcTestChannelValue(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("channel/zero is text", Equals(AiNpcChannelFromInt(0), AiNpcChannelId.Text));
    t.Check("channel/one is a call", Equals(AiNpcChannelFromInt(1), AiNpcChannelId.Call));
    t.Check("channel/an unknown value reads as text",
        Equals(AiNpcChannelFromInt(7), AiNpcChannelId.Text));
    t.Check("channel/a negative value reads as text",
        Equals(AiNpcChannelFromInt(-1), AiNpcChannelId.Text));

    t.Check("channel/text resolves to the written channel",
        Equals(AiNpcChannelOf(AiNpcChannelId.Text).Id(), AiNpcChannelId.Text));
    t.Check("channel/call resolves to the spoken one",
        Equals(AiNpcChannelOf(AiNpcChannelId.Call).Id(), AiNpcChannelId.Call));

    t.Check("channel/the written thread paints text",
        AiNpcChannelOf(AiNpcChannelId.Text).ShowsInThread());
    t.Check("channel/it does not paint what was said",
        !AiNpcChannelOf(AiNpcChannelId.Call).ShowsInThread());
}

// Ce que le dehors lit du canal : un nom, et deux predicats. Le nom se compare pour un canal
// qu'on connait ; les predicats repondent pour ceux qu'on ne connait pas encore.
func AiNpcTestChannelPublicFace(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("channel/the written channel is named text",
        AiNpcChannelOf(AiNpcChannelId.Text).Name(), AiNpcTextChannel());
    t.EqString("channel/the call is named holo",
        AiNpcChannelOf(AiNpcChannelId.Call).Name(), AiNpcHoloChannel());
    t.Check("channel/two channels do not share a name",
        NotEquals(AiNpcTextChannel(), AiNpcHoloChannel()));

    t.Check("channel/a call is spoken", AiNpcChannelOf(AiNpcChannelId.Call).IsSpoken());
    t.Check("channel/the written channel is not",
        !AiNpcChannelOf(AiNpcChannelId.Text).IsSpoken());

    // Ce qu'un consommateur lit sur ce qu'AiNpcReadConversation lui rend : l'enregistrement
    // derive, il ne stocke pas -- une ligne relue d'un journal ancien repond comme les autres.
    let written = AiNpcMessageNewAt("salut", false, 100, AiNpcChannelId.Text);
    let spoken = AiNpcMessageNewAt("salut", false, 100, AiNpcChannelId.Call);

    t.EqString("channel/a stored line names its channel", written.Channel(), AiNpcTextChannel());
    t.EqString("channel/a spoken line names its own", spoken.Channel(), AiNpcHoloChannel());
    t.Check("channel/a spoken line says it was spoken", spoken.IsSpoken());
    t.Check("channel/a written line does not", !written.IsSpoken());
    t.Check("channel/the thread paints a written line", written.ShowsInThread());
    t.Check("channel/it does not paint a spoken one", !spoken.ShowsInThread());
}

// UNE SEULE CHRONOLOGIE, UN FILTRE AU BOUT. Le store garde les deux canaux meles ; c'est la
// lecture qui trie, et c'est ici que ce qui a ete dit reste hors du fil ecrit.
func AiNpcTestChannelFilter(t: ref<AiNpcTestRunner>) -> Void {
    let written = AiNpcMessageNewAt("salut", false, 100, AiNpcChannelId.Text);
    let spoken = AiNpcMessageNewAt("salut", false, 100, AiNpcChannelId.Call);

    t.Check("channel/a phone shows a written line",
        AiNpcIsDisplayableMessage(written, AiNpcChannelId.Text));
    t.Check("channel/a phone hides a spoken line",
        !AiNpcIsDisplayableMessage(spoken, AiNpcChannelId.Text));
    t.Check("channel/a holo shows a spoken line",
        AiNpcIsDisplayableMessage(spoken, AiNpcChannelId.Call));
    t.Check("channel/a holo hides a written line",
        !AiNpcIsDisplayableMessage(written, AiNpcChannelId.Call));

    // Le marqueur d'evenement systeme reste filtre comme avant, sur son propre canal.
    let marker = AiNpcMessageNewAt(AiNpcSystemEventMarker(), true, 100, AiNpcChannelId.Text);
    t.Check("channel/the system marker is still hidden",
        !AiNpcIsDisplayableMessage(marker, AiNpcChannelId.Text));
}

// Le cas qui a motive le champ : la session du telephone est encore enregistree quand un appel
// se termine, et une reponse parlee en retard atterrirait dans le fil SMS sans ce test.
func AiNpcTestChannelAccepts(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("channel/a written surface takes a written reply",
        AiNpcSessionAccepts("judy", "judy", AiNpcChannelId.Text, AiNpcChannelId.Text));
    t.Check("channel/a written surface refuses a spoken reply",
        !AiNpcSessionAccepts("judy", "judy", AiNpcChannelId.Text, AiNpcChannelId.Call));
    t.Check("channel/a spoken surface takes a spoken reply",
        AiNpcSessionAccepts("judy", "judy", AiNpcChannelId.Call, AiNpcChannelId.Call));
    t.Check("channel/a spoken surface refuses a written reply",
        !AiNpcSessionAccepts("judy", "judy", AiNpcChannelId.Call, AiNpcChannelId.Text));

    // Le contact continue de decider en premier : le canal ajoute une condition, il n'en
    // remplace aucune.
    t.Check("channel/the contact still decides",
        !AiNpcSessionAccepts("judy", "panam", AiNpcChannelId.Text, AiNpcChannelId.Text));
    t.Check("channel/a surface showing nothing still accepts nothing",
        !AiNpcSessionAccepts("", "judy", AiNpcChannelId.Text, AiNpcChannelId.Text));
}

// L'aller-retour par le disque. Le champ omis quand la ligne est ecrite est ce qui rend un
// journal d'avant ce champ identique a un journal d'aujourd'hui.
func AiNpcTestChannelJournal(t: ref<AiNpcTestRunner>) -> Void {
    let messages: array<ref<AiNpcMessage>>;
    ArrayPush(messages, AiNpcMessageNewAt("ecrit", true, 10, AiNpcChannelId.Text));
    ArrayPush(messages, AiNpcMessageNewAt("parle", false, 20, AiNpcChannelId.Call));

    let back = AiNpcMessagesFromJson(AiNpcMessagesToJson(messages));
    t.EqInt("channel/both messages survive the round trip", ArraySize(back), 2);
    if ArraySize(back) == 2 {
        t.Check("channel/the written one is still written",
            Equals(back[0].channel, AiNpcChannelId.Text));
        t.Check("channel/the spoken one is still spoken",
            Equals(back[1].channel, AiNpcChannelId.Call));
        t.EqString("channel/the text is untouched", back[1].text, "parle");
        t.EqInt("channel/and so is the clock", back[1].gameTimeSeconds, 20);
    }

    // Une ligne ecrite avant que le champ existe n'a pas de "ch" du tout.
    let old = ParseJson("[{\"p\":true,\"t\":\"vieux\",\"g\":5}]") as JsonArray;
    let read = AiNpcMessagesFromJson(old);
    t.EqInt("channel/a line written before the field still reads", ArraySize(read), 1);
    if ArraySize(read) == 1 {
        t.Check("channel/and it reads as written",
            Equals(read[0].channel, AiNpcChannelId.Text));
    }
}

// Ce qu'une voix ne peut pas dire. La regle du prompt le demande deja ; ceci est la garantie,
// et elle passe sur les deux chemins -- la replique complete et la phrase que le streaming
// remet a la voix.
func AiNpcTestChannelClean(t: ref<AiNpcTestRunner>) -> Void {
    let holo = AiNpcChannelOf(AiNpcChannelId.Call);
    let text = AiNpcChannelOf(AiNpcChannelId.Text);
    let fr = AiNpcLanguage.French;

    t.EqString("channel/asterisks are cut",
        holo.Clean("Salut *elle sourit* ca va ?", fr), "Salut ca va ?");
    t.EqString("channel/brackets are cut",
        holo.Clean("Salut [rires] ca va ?", fr), "Salut ca va ?");
    t.EqString("channel/a stage direction at the end takes its space with it",
        holo.Clean("Ca va *elle raccroche*", fr), "Ca va");
    t.EqString("channel/an unclosed marker is kept rather than eaten",
        holo.Clean("2 * 3 font 6", fr), "2 * 3 font 6");
    t.EqString("channel/a clean line is untouched",
        holo.Clean("T'as qu'a passer, j'suis a l'atelier.", fr), "T'as qu'a passer, j'suis a l'atelier.");
    t.EqString("channel/a call says the hour",
        holo.Clean("Rejoins-moi a 22h *elle sourit*", fr), "Rejoins-moi a 22 heures");

    // Le canal ecrit ne nettoie rien : le joueur SAUTE une didascalie, il ne l'entend pas, et
    // « 22h » se lit mieux qu'il ne se dit.
    t.EqString("channel/the written channel keeps what was written",
        text.Clean("Salut *elle sourit* ca va ?", fr), "Salut *elle sourit* ca va ?");
    t.EqString("channel/the written channel keeps the written hour",
        text.Clean("a 22h", fr), "a 22h");
}
