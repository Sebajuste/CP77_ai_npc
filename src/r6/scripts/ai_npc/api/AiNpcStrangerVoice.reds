// A voice for a character the game never voiced, such as a contact another mod mints at runtime.
//
// An anonymous civilian of the game, re-read at a drawn speed, so two strangers cut from the
// same civilian are still two people. Without the cloning pack the same draw picks a catalogue
// voice of the same sex, played at the same speed.

module AiNpc

// Civilians the recipe can cut. A draw is read modulo the size of each pool, so ANY change here,
// an addition included, re-voices every stranger already met. tools\lint.ps1 checks each name
// against the recipe.
func AiNpcStrangerReferences(female: Bool) -> array<String> {
    if female {
        return ["civ_high_f_01_enus_25.wav", "civ_high_f_04_enus_50.wav"];
    }
    return ["civ_mid_m_10_enus_30.wav", "civ_mid_m_04_enus_30.wav", "civ_high_m_07_enus_40.wav",
            "civ_high_m_02_enus_30.wav", "civ_mid_m_05_enus_40.wav"];
}

// Catalogue voices no character of ai_npc or joytoys speaks with, sorted by measured median
// pitch: under 135 Hz, over 170 Hz. alba, rafael and caro_davy sit between and are left out.
func AiNpcStrangerCatalogue(female: Bool) -> array<String> {
    if female {
        return ["fantine", "cosette", "jane", "azelma", "anna"];
    }
    return ["charles", "juergen", "peter_yearsley", "javert", "giovanni"];
}

// The range the 2026-09-10 bench kept: beyond eight percent a derived voice stops sounding
// like a person.
func AiNpcStrangerShifts() -> array<Float> {
    return [0.92, 0.96, 1.0, 1.04, 1.08];
}

func AiNpcDrawIndex(draw: Int32) -> Int32 {
    if draw < -2147483647 {
        return 0;
    }
    if draw < 0 {
        return -draw;
    }
    return draw;
}

// The sex of a stranger's voice. Functions rather than an enum, for the reason AiNpcApi.reds
// gives. Any value other than AiNpcVoiceFemale() reads as male.
public func AiNpcVoiceMale() -> Int32 {
    return 0;
}

public func AiNpcVoiceFemale() -> Int32 {
    return 1;
}

// `draw` is any Int32 the caller keeps stable for this contact: the same draw, the same voice,
// in every session. Reference, catalogue voice and speed are read from separate digits of it.
public func AiNpcStrangerVoice(draw: Int32, sex: Int32) -> ref<AiNpcVoiceDef> {
    let female = Equals(sex, AiNpcVoiceFemale());
    let references = AiNpcStrangerReferences(female);
    let catalogue = AiNpcStrangerCatalogue(female);
    let shifts = AiNpcStrangerShifts();
    let referenceCount = ArraySize(references);
    let catalogueCount = ArraySize(catalogue);
    let shiftCount = ArraySize(shifts);

    let rest = AiNpcDrawIndex(draw);
    let voice = new AiNpcVoiceDef();
    voice.clone = references[rest % referenceCount];
    rest = rest / referenceCount;
    voice.fallback = catalogue[rest % catalogueCount];
    rest = rest / catalogueCount;
    voice.shift = shifts[rest % shiftCount];
    voice.rate = voice.shift;
    return voice;
}
