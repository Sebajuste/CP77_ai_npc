// Ce qu'un texte ecrit devient pour etre dit : l'heure collee a son unite.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel.

module AiNpc

func AiNpcTestVoiceFormatFrench(t: ref<AiNpcTestRunner>) -> Void {
    let fr = AiNpcLanguage.French;
    t.EqString("voice/an hour gets its word",
        AiNpcVoiceFormat("On se voit a 22h.", fr), "On se voit a 22 heures.");
    t.EqString("voice/minutes follow the word",
        AiNpcVoiceFormat("Passe vers 22h30, pas avant.", fr), "Passe vers 22 heures 30, pas avant.");
    t.EqString("voice/round minutes are not said",
        AiNpcVoiceFormat("22h00", fr), "22 heures");
    t.EqString("voice/one hour is singular",
        AiNpcVoiceFormat("1h du mat", fr), "1 heure du mat");
    t.EqString("voice/a spaced hour is untouched",
        AiNpcVoiceFormat("a 22 heures", fr), "a 22 heures");
    t.EqString("voice/a plain number is untouched",
        AiNpcVoiceFormat("Il reste 500 eddies", fr), "Il reste 500 eddies");
    t.EqString("voice/a code is not an hour",
        AiNpcVoiceFormat("Le A22h est la", fr), "Le A22h est la");
    t.EqString("voice/a word after the marker is not an hour",
        AiNpcVoiceFormat("22hab", fr), "22hab");
    t.EqString("voice/an impossible hour is untouched",
        AiNpcVoiceFormat("25h", fr), "25h");
    t.EqString("voice/impossible minutes are untouched",
        AiNpcVoiceFormat("22h75", fr), "22h75");
}

func AiNpcTestVoiceFormatLanguages(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("voice/german",
        AiNpcVoiceFormat("um 22h30", AiNpcLanguage.German), "um 22 Uhr 30");
    t.EqString("voice/spanish",
        AiNpcVoiceFormat("a las 22h", AiNpcLanguage.Spanish), "a las 22 horas");
    t.EqString("voice/spanish singular",
        AiNpcVoiceFormat("1h", AiNpcLanguage.Spanish), "1 hora");
    t.EqString("voice/italian",
        AiNpcVoiceFormat("alle 22h", AiNpcLanguage.Italian), "alle 22 ore");
    t.EqString("voice/portuguese",
        AiNpcVoiceFormat("as 22h", AiNpcLanguage.Portuguese), "as 22 horas");
    t.EqString("voice/english",
        AiNpcVoiceFormat("about 1h", AiNpcLanguage.English), "about 1 hour");
    t.EqString("voice/russian few",
        AiNpcVoiceFormat("в 22ч", AiNpcLanguage.Russian), "в 22 часа");
    t.EqString("voice/russian one",
        AiNpcVoiceFormat("в 21ч", AiNpcLanguage.Russian), "в 21 час");
    t.EqString("voice/russian many",
        AiNpcVoiceFormat("5ч", AiNpcLanguage.Russian), "5 часов");
    t.EqString("voice/ukrainian",
        AiNpcVoiceFormat("о 22год", AiNpcLanguage.Ukraine), "о 22 години");
}
