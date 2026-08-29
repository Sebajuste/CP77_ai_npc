module AiNpc

// Les reglages lus au demarrage, et ce que le monde y ajoute.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

func AiNpcTestConfigHelpers(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("join/empty separator handling", AiNpcJoinStrings(["a", "b", "c"], ", "), "a, b, c");
    let single = ["only"];
    t.EqString("join/single item", AiNpcJoinStrings(single, ", "), "only");
    let none: array<String>;
    t.EqString("join/empty list", AiNpcJoinStrings(none, ", "), "");

    let sorted = AiNpcSortStrings(["characters.zed.json", "characters.abc.json", "characters.mid.json"]);
    t.EqString("sort/orders file names", AiNpcJoinStrings(sorted, "|"),
        "characters.abc.json|characters.mid.json|characters.zed.json");
    let already = AiNpcSortStrings(["a", "b"]);
    t.EqString("sort/already ordered", AiNpcJoinStrings(already, "|"), "a|b");
    let one = AiNpcSortStrings(["a"]);
    t.EqString("sort/single element", AiNpcJoinStrings(one, "|"), "a");

    // Variant conditions are a closed vocabulary: config may carry text, never predicates.
    let conditions = AiNpcVariantConditions();
    t.EqInt("variants/vocabulary size", ArraySize(conditions), 14);
    t.Check("variants/romanced is known", ArrayContains(conditions, "romanced"));
    t.Check("variants/an invented condition is not known", !ArrayContains(conditions, "whenever"));
    t.EqBool("variants/unknown condition never fires",
        AiNpcEvaluateVariantCondition("whenever", "panam", true), false);
    t.EqBool("variants/romanced follows its argument",
        AiNpcEvaluateVariantCondition("romanced", "panam", true), true);
    t.EqBool("variants/notRomanced is the negation",
        AiNpcEvaluateVariantCondition("notRomanced", "panam", true), false);

    // THE ARC CONDITIONS, and the two things worth asserting without a save.
    //
    // The vocabulary must name them -- the loader validates a file's `when` against this list
    // and drops what it does not recognise, so a condition the sheets use and the list omits
    // would silently delete every variant a player wrote with it.
    t.Check("variants/romanceFailed is known", ArrayContains(conditions, "romanceFailed"));
    t.Check("variants/randyDead is known", ArrayContains(conditions, "randyDead"));
    t.Check("variants/evelynDead is known", ArrayContains(conditions, "evelynDead"));
    t.Check("variants/evelynRescued is known", ArrayContains(conditions, "evelynRescued"));
    t.Check("variants/cloudsSettled is known", ArrayContains(conditions, "cloudsSettled"));
    t.Check("variants/leftNightCity is known", ArrayContains(conditions, "leftNightCity"));
    t.Check("variants/johnnyRevealed is known", ArrayContains(conditions, "johnnyRevealed"));
    t.Check("variants/johnnyDateDone is known", ArrayContains(conditions, "johnnyDateDone"));

    // Same guard as AiNpcRomanceFailedFor below: a per-contact rule must not leak.
    t.EqBool("variants/leaving is per contact, not a global",
        AiNpcHasLeftNightCity("panam"), false);
    t.EqBool("variants/what V did for one contact is not read for another",
        AiNpcEvelynWasRescued("panam"), false);

    // Judy's plain relationship must assert NOTHING about what V did: without this guard it
    // said "you came for Evelyn with me" in a playthrough where the two had never spoken. What
    // holds it is a variant, not a cautiously worded sentence.
    let judySheet = AiNpcBuiltinSheet("judy");
    t.Check("variants/judy's plain relationship claims nothing V may not have done",
        !StrContains(judySheet.relationship, "went after Evelyn with you"));
    let named = false;
    let jr = 0;
    while jr < ArraySize(judySheet.variants) {
        if Equals(judySheet.variants[jr].when, "evelynRescued")
            && NotEquals(StrLen(judySheet.variants[jr].relationship), 0) {
            named = true;
        }
        jr += 1;
    }
    t.Check("variants/and a guarded variant is what names it", named);

    // And a contact with no rule answers false rather than inheriting somebody else's. Panam
    // is the live case, not a hypothetical: her failure fact has not been located, so she must
    // read as "never refused" instead of borrowing Judy's answer.
    t.EqBool("variants/an unmapped contact never reads as failed",
        AiNpcRomanceFailedFor("panam"), false);
    t.EqBool("variants/nor does a contact from another mod",
        AiNpcRomanceFailedFor("some_mod_contact"), false);

    // The three the sheets rely on are mapped. Asserted through the vocabulary rather than by
    // reading facts, which needs a session: what this guards is a contact id renamed on one
    // side only, which turns the whole variant off with nothing in any log.
    let mapped = ["judy", "kerry_eurodyne", "river_ward"];
    let m = 0;
    while m < ArraySize(mapped) {
        let sheet = AiNpcBuiltinSheet(mapped[m]);
        t.Check(s"variants/\(mapped[m]) is still a shipped contact", IsDefined(sheet));
        let hasFailed = false;
        let v = 0;
        while v < ArraySize(sheet.variants) {
            if Equals(sheet.variants[v].when, "romanceFailed") {
                hasFailed = true;
            }
            v += 1;
        }
        t.Check(s"variants/\(mapped[m]) carries the refused text", hasFailed);
        m += 1;
    }

    // River says the boy before he says the romance, and the order is the claim: the first
    // variant supplying a field wins, so a playthrough with both would otherwise answer with
    // whichever was written first.
    let river = AiNpcBuiltinSheet("river_ward");
    let firstWhen = "";
    let r = 0;
    while r < ArraySize(river.variants) {
        if Equals(StrLen(firstWhen), 0) && NotEquals(StrLen(river.variants[r].relationship), 0) {
            firstWhen = river.variants[r].when;
        }
        r += 1;
    }
    t.EqString("variants/river grieves before he is refused", firstWhen, "randyDead");

    // Rogue, and the same shape as Judy's Evelyn guard: her plain relationship must not claim
    // she knows what is in V's head. She learns it in Chippin' In, and in the branch where V
    // never lets Johnny take the wheel she never learns it at all -- so the default is "does
    // not know" and the engram is asserted by a variant only.
    let rogue = AiNpcBuiltinSheet("rogue");
    t.Check("variants/rogue's plain relationship does not know about the engram",
        !StrContains(rogue.relationship, "engram"));
    let engramNamed = false;
    let rogueFirst = "";
    let rg = 0;
    while rg < ArraySize(rogue.variants) {
        if Equals(StrLen(rogueFirst), 0) && NotEquals(StrLen(rogue.variants[rg].relationship), 0) {
            rogueFirst = rogue.variants[rg].when;
        }
        if Equals(rogue.variants[rg].when, "johnnyRevealed")
            && StrContains(rogue.variants[rg].relationship, "engram") {
            engramNamed = true;
        }
        rg += 1;
    }
    t.Check("variants/and a guarded variant is what names it", engramNamed);
    // Both hold in any save that reached the drive-in, so the order is the claim: the evening
    // is the later state and it speaks first.
    t.EqString("variants/rogue answers from the evening before the night at the bar",
        rogueFirst, "johnnyDateDone");

    // A seed fact cannot be varied (AiNpcVariantFields), so one naming the engram would tell
    // her about Johnny in a brand-new game, past every guard above.
    let seeded = false;
    let rs = 0;
    while rs < ArraySize(rogue.seedFacts) {
        if StrContains(rogue.seedFacts[rs], "engram") {
            seeded = true;
        }
        rs += 1;
    }
    t.Check("variants/no unvariable seed fact leaks the engram", !seeded);

    // Judy's three lived-experience variants run newest first, for the same reason: all three
    // are true at once in a late save, and only one of them gets liveContext.
    let judy = AiNpcBuiltinSheet("judy");
    let lived: array<String>;
    let jv = 0;
    while jv < ArraySize(judy.variants) {
        if NotEquals(StrLen(judy.variants[jv].liveContext), 0) {
            ArrayPush(lived, judy.variants[jv].when);
        }
        jv += 1;
    }
    t.EqInt("variants/judy carries three lived states", ArraySize(lived), 3);
    t.EqString("variants/judy speaks from where she is first", lived[0], "leftNightCity");
    t.EqString("variants/then how the club ended", lived[1], "cloudsSettled");
    t.EqString("variants/then the loss that started it", lived[2], "evelynDead");

    // No variant of hers may write bio: it replaces the field whole, so one would delete the
    // action criteria in a playthrough nobody is looking at.
    let wroteBio = false;
    let jb = 0;
    while jb < ArraySize(judy.variants) {
        if NotEquals(StrLen(judy.variants[jb].bio), 0) {
            wroteBio = true;
        }
        jb += 1;
    }
    t.EqBool("variants/judy keeps her criteria in every state", wroteBio, false);

    // The language keys prompts.json is validated against must line up with the enum the
    // settings menu exposes, or an override silently never applies.
    let languages = AiNpcLanguageNames();
    t.EqInt("languages/name list matches the enum", ArraySize(languages), 8);
    t.EqString("languages/first is English", languages[0], "English");

    t.EqBool("contacts/builtin id recognised", AiNpcIsBuiltinContactId("judy"), true);
    t.EqBool("contacts/foreign id is not builtin", AiNpcIsBuiltinContactId("JoytoysVIP101"), false);
}

/// Per-contact prompt overrides ///

// The chain is contact -> prompts.json -> built-in, and the level that carries the risk is
// the first: it is the only one that can be half-filled. An override object whose
// worldMechanics is empty must leave <mechanics> resolving further down, not blank it --
// a silently emptied section is the failure mode that looks like a working prompt.

func AiNpcTestLanguageFromLocale(t: ref<AiNpcTestRunner>) -> Void {
    t.EqInt("locale/french", EnumInt(AiNpcLanguageFromLocale(n"fr-fr")), EnumInt(AiNpcLanguage.French));
    t.EqInt("locale/german", EnumInt(AiNpcLanguageFromLocale(n"de-de")), EnumInt(AiNpcLanguage.German));
    t.EqInt("locale/italian", EnumInt(AiNpcLanguageFromLocale(n"it-it")), EnumInt(AiNpcLanguage.Italian));
    t.EqInt("locale/russian", EnumInt(AiNpcLanguageFromLocale(n"ru-ru")), EnumInt(AiNpcLanguage.Russian));
    t.EqInt("locale/brazilian portuguese", EnumInt(AiNpcLanguageFromLocale(n"pt-br")), EnumInt(AiNpcLanguage.Portuguese));

    t.EqInt("locale/castilian spanish", EnumInt(AiNpcLanguageFromLocale(n"es-es")), EnumInt(AiNpcLanguage.Spanish));
    t.EqInt("locale/latin american spanish", EnumInt(AiNpcLanguageFromLocale(n"es-mx")), EnumInt(AiNpcLanguage.Spanish));

    // A language the mod has no prompt text for falls back to English, never to Auto:
    // Auto is a setting value, and returning it here would loop back into the resolver.
    t.EqInt("locale/english", EnumInt(AiNpcLanguageFromLocale(n"en-us")), EnumInt(AiNpcLanguage.English));
    t.EqInt("locale/unsupported falls back to english", EnumInt(AiNpcLanguageFromLocale(n"pl-pl")), EnumInt(AiNpcLanguage.English));
    t.EqInt("locale/missing value falls back to english", EnumInt(AiNpcLanguageFromLocale(n"")), EnumInt(AiNpcLanguage.English));

    // AiNpcCurrentLanguageName indexes AiNpcLanguageNames by enum value, so Auto must
    // never reach it -- and the real members must stay contiguous from 0.
    let names = AiNpcLanguageNames();
    t.EqInt("locale/auto is outside the name list", ArraySize(names), 8);
    t.Check("locale/auto is not a language name", !ArrayContains(names, "Auto"));
}

/// AiNpcTrimLeadingBlanks ///

func AiNpcTestWeather(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("weather/a named state wins over the rain",
        AiNpcWeatherWord(n"24h_weather_sandstorm", worldRainIntensity.NoRain), "sandstorm");
    t.EqString("weather/states sharing a word share a case",
        AiNpcWeatherWord(n"24h_weather_fog_dense", worldRainIntensity.NoRain), "fog");

    // A weather mod's own state, or a vanilla one nobody has seen yet: the rain is the only
    // reading that cannot be wrong.
    t.EqString("weather/an unknown state falls back on the rain",
        AiNpcWeatherWord(n"other_mod_ashfall", worldRainIntensity.HeavyRain), "heavy rain");
    t.EqString("weather/and on clear when it is not raining",
        AiNpcWeatherWord(n"other_mod_ashfall", worldRainIntensity.NoRain), "clear");

    t.EqString("weather/rain has three readings", AiNpcRainWord(worldRainIntensity.LightRain), "rain");
}

/// Rule composition ///
