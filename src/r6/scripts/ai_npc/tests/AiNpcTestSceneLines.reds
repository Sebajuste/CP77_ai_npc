// Les répliques d'un appel du jeu : le texte que le joueur lit, et jamais deux fois la même.

module AiNpc

func AiNpcTestSceneLines(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("scene/a plain line is its own text",
        AiNpcSceneLineText(false, false, "Hey V.", "", "", "", ""), "Hey V.");
    t.EqString("scene/a Kiroshi line reads the translation",
        AiNpcSceneLineText(true, false, "raw", "", "Hola", "Hello", ""), "Hello");
    t.EqString("scene/and keeps the words around it",
        AiNpcSceneLineText(true, false, "raw", "Well,", "Hola", "hello", "V."), "Well, hello V.");
    t.EqString("scene/a Kiroshi line with no translation is the raw line",
        AiNpcSceneLineText(true, false, "raw", "", "Hola", "", ""), "raw");
    t.EqString("scene/a mother tongue line keeps the foreign word",
        AiNpcSceneLineText(false, true, "raw", "Gracias,", "chica", "girl", ""), "Gracias, chica");

    let history = [AiNpcMessageNewAt("T'es encore là ?", false, AiNpcTimeUnknown(), AiNpcChannelId.Text), AiNpcMessageNewAt("Oui.", true, AiNpcTimeUnknown(), AiNpcChannelId.Text)];
    t.Check("scene/a line already in the thread is not filed again",
        !AiNpcSceneLineIsNew(history, "T'es encore là ?", false));
    t.Check("scene/the same words from the other side are new",
        AiNpcSceneLineIsNew(history, "Oui.", false));
    t.Check("scene/a new line is filed",
        AiNpcSceneLineIsNew(history, "J'attends, V...", false));
}
