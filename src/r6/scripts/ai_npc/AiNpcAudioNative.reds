// The second half of ai_npc.dll's native surface: sound.
//
// Read the head of AiNpcCliNative.reds before adding anything here. A native class that no
// loaded plugin registered does not fail gracefully -- RED4ext validates the compiled blob
// after every plugin has loaded and refuses it, and the GAME does not start. This file is the
// second line that error can carry, and there must not be a third without a reason.
//
// It is a class of its own rather than a function bolted onto AiNpcCli because the name would
// then lie: `AiNpcCli.Beep()` says the CLI lanes make sound, and nothing about the two is
// related beyond sharing a DLL. One line of boot risk is the price of a name that is true.
//
// @if(ModuleExists()) cannot guard any of this: the validation happens against the compiled
// blob, before a conditional would be evaluated.

module AiNpc

public native class AiNpcAudio {
    // Plays a short tone through the system's audio output, generated in the DLL: no asset,
    // no manifest, no file read or written. It is the proof that the mod can make a sound at
    // all, and it is the only thing this class does today.
    //
    // Returns what the device said, in words, and writes the same sentence to
    // red4ext\logs\ai_npc-*.log. A String rather than a Bool because the answer IS the
    // measurement: silence has two causes that look identical from a chair -- the device
    // refused the format, or it took the buffer and played it somewhere nobody is listening --
    // and only the device can tell them apart.
    public static native func Beep() -> String;

    // Says a line out loud, and plays it on the same path as everything else this class makes:
    // memory to speakers, no file.
    //
    // `voiceFile` is the reference the character's sheet names -- AiNpcVoiceChoiceFor() answers
    // it, and `judy.wav` is what it answers when the sheet says nothing.
    //
    // `catalogueVoice` is what speaks when no clone is possible -- AiNpcVoiceChoiceFor()
    // answers it. It is the only tier the free model pack can offer, and the difference between
    // eleven distinct characters and eleven identical Windows voices.
    //
    // `contactId` is who speaks, and it is what the extraction recipe is keyed by. The DLL answers it per line
    // and per character: the model pack plus a reference for that contact gives the character's
    // own voice, anything less gives the system synthesiser. A player will have Judy and not
    // Rogue, so the question is asked for each of them rather than once for all.
    //
    // An empty contact is not an error -- it is a line that belongs to no character, and the
    // fallback voice is the right one for it.
    //
    // Returns at once, so the answer describes the PREVIOUS line -- the one just handed over
    // has not been spoken yet, and the delay it reports is what the voice lane is judged on.
    // It names the engine that spoke, because three seconds of the character's voice and three
    // seconds of Windows' do not mean the same thing.
    // `voiceOverLocale` is what the game answers for its SPOKEN language, not its written one --
    // the two are installed separately, and it is the spoken archives a reference is cut from.
    // Pass AiNpcVoiceOverLocale(); an empty string means the fallback voice, which is honest.
    // `rate` is the playback speed AiNpcVoiceChoiceFor() answers; 1.0 plays the voice as rendered.
    public static native func Speak(text: String, contactId: String, voiceFile: String,
                                   catalogueVoice: String, voiceOverLocale: String, rate: Float) -> String;

    // Ce que le haut-parleur dit a cet instant, mot pour mot. Vide quand rien ne joue.
    //
    // Une reponse arrive phrase par phrase et la file les joue dans l'ordre : au moment ou la
    // troisieme est envoyee, c'est la premiere qu'on entend. Une surface qui afficherait ce
    // qu'elle vient d'envoyer afficherait donc la mauvaise, et une duree estimee ne la
    // rattrape pas -- elle derive a chaque phrase. Demander a la file est le seul moyen d'etre
    // en phase avec elle.
    public static native func Speaking() -> String;

    // La replique de V, dite de sa voix. Meme file que celles du personnage, donc dite avant la
    // reponse qu'elle precede ; jamais passee au filtre radio, parce que V n'est pas au bout du fil.
    public static native func SpeakAsPlayer(text: String, voiceFile: String, catalogueVoice: String,
                                            voiceOverLocale: String) -> String;

    // La replique entendue est-elle celle de V. Faux quand rien ne joue.
    public static native func SpeakingPlayer() -> Bool;

    // Coupe le son tout de suite : ce qui joue s'arrete, ce qui attendait est jete, et la
    // replique en cours de synthese est abandonnee.
    //
    // Appelee quand le joueur raccroche. Sans elle, un personnage finit sa phrase dans un appel
    // termine -- et le premier mot du prochain appel attend la fin de la precedente, parce que
    // la voie parlee dit une replique a la fois.
    //
    // Ne refroidit aucune voix : leur preparation a coute sept secondes et ne depend d'aucun
    // appel en particulier.
    public static native func Silence() -> Void;

    // Ouvre la sortie audio pendant que le modele ecrit la reponse. Une sortie qui vient
    // d'ouvrir avale le debut de ce qu'elle joue en premier : ouverte d'avance, elle avale son
    // propre silence au lieu du premier mot. A appeler par tout canal parle au moment ou il
    // demande une reponse ; sans effet sur une sortie deja ouverte, qui se ferme seule apres
    // 20 s sans parole. Memes arguments que Speak() pour la voix : c'est elle qui fixe le format.
    public static native func Prime(voiceFile: String, catalogueVoice: String, rate: Float) -> Void;

    // Prepares a character's voice without saying anything. Returns at once.
    //
    // A first line costs about seven seconds nobody sees coming: loading the model, cutting the
    // reference out of the player's own archives, and cloning it. None of that depends on what
    // is going to be said, so none of it has to wait for it -- and a call rings for twenty
    // seconds during which nothing is happening.
    //
    // Harmless when everything is already warm, and does nothing at all without the model pack.
    public static native func Warm(contactId: String, voiceFile: String, catalogueVoice: String,
                                  voiceOverLocale: String) -> String;

    // Hands the DLL the voice-over lines a character's reference is to be cut from, under the
    // name that reference carries. Says nothing and prepares nothing: it only answers, in
    // advance, a question the recipe cannot answer for a character ai_npc never shipped.
    //
    // Declared rather than searched because the archives hold no path at all -- only the hash
    // of one -- so nothing in the DLL can look for a character's lines by tag.
    //
    // `lines` are file names without a folder, identical in every language. Declaring twice
    // replaces: the last mod to speak is the one that knows.
    public static native func DeclareVoice(voiceName: String, lines: array<String>) -> Void;

    // Where that preparation has got to, in one word: "ready", "pending", "unavailable", or
    // "unknown" for a voice nobody asked for.
    //
    // Four answers rather than a Bool, because a caller does three different things with them:
    // wait, answer, and answer AT ONCE. Collapsing the last two would leave an installation
    // with no model pack ringing into the void for the whole timeout.
    public static native func VoiceState(contactId: String) -> String;
}
