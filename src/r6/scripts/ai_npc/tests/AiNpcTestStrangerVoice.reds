// La voix d'un inconnu : un tirage stable, et le nom de fichier que la DLL relit.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

module AiNpc

func AiNpcTestStrangerVoice(t: ref<AiNpcTestRunner>) -> Void {
    let first = AiNpcStrangerVoice(123456, AiNpcVoiceMale());
    let again = AiNpcStrangerVoice(123456, AiNpcVoiceMale());
    t.EqString("stranger/the same draw gives the same reference", again.clone, first.clone);
    t.EqString("stranger/and the same catalogue voice", again.fallback, first.fallback);
    t.Check("stranger/and the same shift", Equals(again.shift, first.shift));
    t.Check("stranger/the catalogue plays at the clone's speed", Equals(first.rate, first.shift));

    let men = AiNpcStrangerReferences(false);
    let menCatalogue = AiNpcStrangerCatalogue(false);
    let women = AiNpcStrangerReferences(true);
    let womenCatalogue = AiNpcStrangerCatalogue(true);
    let shifts = AiNpcStrangerShifts();

    t.Check("stranger/a man is cut from a man", ArrayContains(men, first.clone));
    t.Check("stranger/and falls back on a man", ArrayContains(menCatalogue, first.fallback));
    t.Check("stranger/his shift is one of the steps", ArrayContains(shifts, first.shift));

    let woman = AiNpcStrangerVoice(123456, AiNpcVoiceFemale());
    t.Check("stranger/a woman is cut from a woman", ArrayContains(women, woman.clone));
    t.Check("stranger/and falls back on a woman", ArrayContains(womenCatalogue, woman.fallback));

    let lowest = AiNpcStrangerVoice(-2147483647 - 1, AiNpcVoiceMale());
    t.Check("stranger/the lowest Int32 still gives a voice", ArrayContains(men, lowest.clone));
    let negative = AiNpcStrangerVoice(-42, AiNpcVoiceMale());
    t.Check("stranger/a negative draw gives a voice", ArrayContains(men, negative.clone));

    let reached: array<String>;
    let draw = 0;
    while draw < ArraySize(men) {
        let clone = AiNpcStrangerVoice(draw, AiNpcVoiceMale()).clone;
        if !ArrayContains(reached, clone) {
            ArrayPush(reached, clone);
        }
        draw += 1;
    }
    t.EqInt("stranger/every man in the pool can be drawn", ArraySize(reached), ArraySize(men));
}

func AiNpcTestDerivedVoiceFile(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("voicefile/a shift of one keeps the name", AiNpcDerivedVoiceFile("civ.wav", 1.0), "civ.wav");
    t.EqString("voicefile/a shift up is written in the name",
        AiNpcDerivedVoiceFile("civ.wav", 1.04), "civ-x1.04.wav");
    t.EqString("voicefile/a shift down keeps its leading zero",
        AiNpcDerivedVoiceFile("civ.wav", 0.96), "civ-x0.96.wav");
    t.EqString("voicefile/a single-digit fraction keeps two digits",
        AiNpcDerivedVoiceFile("civ.wav", 1.05), "civ-x1.05.wav");
    t.EqString("voicefile/a name without an extension gets one",
        AiNpcDerivedVoiceFile("civ", 1.08), "civ-x1.08.wav");
    t.EqString("voicefile/a shift out of range is held",
        AiNpcDerivedVoiceFile("civ.wav", 2.0), "civ-x1.15.wav");
    t.EqString("voicefile/a shift that rounds to one keeps the name",
        AiNpcDerivedVoiceFile("civ.wav", 1.004), "civ.wav");

    let none = AiNpcVoiceChoiceFor("");
    t.EqString("voicefile/no contact names no file", none.file, "");
    t.Check("voicefile/and plays at speed one", Equals(none.rate, 1.0));
}
