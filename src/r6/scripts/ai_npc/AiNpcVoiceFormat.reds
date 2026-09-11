// Ce qu'un texte écrit devient pour être dit.
//
// Mesuré au banc : « 22h » est lu « vingt deusse » et le mot heures est avalé, alors que
// « 22 heures » est dit correctement, chiffres compris. L'unité écrite en toutes lettres suffit ;
// les chiffres restent.

module AiNpc

func AiNpcVoiceFormat(text: String, language: AiNpcLanguage) -> String {
    let marker = AiNpcHourMarker(language);
    let out = "";
    let count = StrLen(text);
    let i = 0;
    while i < count {
        if !AiNpcIsDigits(StrMid(text, i, 1)) {
            out += StrMid(text, i, 1);
            i += 1;
        } else {
            let start = i;
            while i < count && AiNpcIsDigits(StrMid(text, i, 1)) {
                i += 1;
            }
            let hours = StrMid(text, start, i - start);

            let end = -1;
            if StrLen(hours) <= 2 && StringToInt(hours) <= 24
                && (start == 0 || AiNpcSeparatesWords(StrMid(text, start - 1, 1))) {
                end = AiNpcClockEnd(text, i, marker);
            }

            if end < 0 {
                out += hours;
            } else {
                let minutes = StrMid(text, i + StrLen(marker), end - i - StrLen(marker));
                out += s"\(hours) \(AiNpcHourWord(StringToInt(hours), language))";
                if StrLen(minutes) > 0 && NotEquals(minutes, "00") {
                    out += s" \(minutes)";
                }
                i = end;
            }
        }
    }
    return out;
}

// La fin d'une heure collée qui commence au marqueur, minutes comprises, ou -1. Une lettre juste
// après le marqueur en fait un mot, pas une heure.
func AiNpcClockEnd(text: String, from: Int32, marker: String) -> Int32 {
    let size = StrLen(marker);
    if NotEquals(StrLower(StrMid(text, from, size)), marker) {
        return -1;
    }

    let end = from + size;
    let minutes = StrMid(text, end, 2);
    if StrLen(minutes) == 2 && AiNpcIsDigits(minutes) && StringToInt(minutes) < 60
        && !AiNpcIsDigits(StrMid(text, end + 2, 1)) {
        end += 2;
    }

    if end < StrLen(text) && !AiNpcSeparatesWords(StrMid(text, end, 1)) {
        return -1;
    }
    return end;
}

// ASCII seulement : un octet isolé d'un caractère multi-octet ne doit rien pouvoir y trouver.
func AiNpcSeparatesWords(c: String) -> Bool {
    return StrFindFirst(" \n.,;:!?()[]\"'-/", c) >= 0;
}

func AiNpcHourMarker(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.Russian: return "ч";
        case AiNpcLanguage.Ukraine: return "год";
    }
    return "h";
}

func AiNpcHourWord(hours: Int32, language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.French:
            if hours <= 1 { return "heure"; }
            return "heures";
        case AiNpcLanguage.Spanish:
            if hours == 1 { return "hora"; }
            return "horas";
        case AiNpcLanguage.Portuguese:
            if hours == 1 { return "hora"; }
            return "horas";
        case AiNpcLanguage.Italian:
            if hours == 1 { return "ora"; }
            return "ore";
        case AiNpcLanguage.German:
            return "Uhr";
        case AiNpcLanguage.Russian:
            return AiNpcSlavicPlural(hours, "час", "часа", "часов");
        case AiNpcLanguage.Ukraine:
            return AiNpcSlavicPlural(hours, "година", "години", "годин");
    }
    if hours == 1 { return "hour"; }
    return "hours";
}

// 1, 21 : one ; 2-4, 22-24 : few ; le reste, 11 à 14 compris : many.
func AiNpcSlavicPlural(n: Int32, one: String, few: String, many: String) -> String {
    let unit = n % 10;
    let tens = n % 100;
    if unit == 1 && tens != 11 {
        return one;
    }
    if unit >= 2 && unit <= 4 && (tens < 12 || tens > 14) {
        return few;
    }
    return many;
}
