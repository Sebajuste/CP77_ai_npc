// The key hints along the bottom of the chat: undo when Debug Mode is on, reset, back, and the
// choices the contact's thread offers.
//
// A hint is a key and a word side by side. How one sits in the strip -- the anchoring, the two
// style bindings, the gap between key and word -- is stated once, because a hint that drifts out
// of line with the others does not look wrong enough for anyone to report it.

module AiNpc

// A hint with nothing in it yet, anchored to the top right of the strip.
func AiNpcPhoneHintFrame(strip: ref<inkCompoundWidget>, name: CName) -> ref<inkHorizontalPanel> {
    let hint = AiNpcInkHorizontal(strip, name);
    hint.SetAnchor(inkEAnchor.TopRight);
    hint.SetAnchorPoint(new Vector2(1, 0));
    hint.SetHAlign(inkEHorizontalAlign.Left);
    hint.SetVAlign(inkEVerticalAlign.Top);
    hint.SetFitToContent(true);
    return hint;
}

// The word after the key.
func AiNpcPhoneHintWord(hint: ref<inkCompoundWidget>, word: String) -> Void {
    let label = AiNpcInkText(hint, n"hint_label", word, AiNpcPhoneStyle.FsHint(), AiNpcStyle.Accent());
    label.SetFontStyle(n"Semi-Bold");
    label.SetLetterCase(AiNpcStyle.HeadingCase());
    label.SetAnchor(inkEAnchor.TopRight);
    label.SetAnchorPoint(new Vector2(1, 0));
    label.SetVAlign(inkEVerticalAlign.Center);
    label.SetMargin(new inkMargin(7.5, 5.0, 5.0, 0.0));
    label.SetSize(new Vector2(100.0, 32.0));
    label.SetFitToContent(true);
    label.SetStyle(AiNpcStyle.MainColorsStyle());
    // fontStyle bound to a SIZE constant. It reads as a typo and it is deliberate at this
    // point: this is what has always rendered, and pointing it at a weight constant would
    // change how the hint strip looks. Said out loud so nobody "fixes" it by accident.
    label.BindProperty(n"fontStyle", n"MainColors.ReadableSmall");
    label.BindProperty(n"tintColor", AiNpcStyle.PropAccentTint());
}

// A hint whose key has a keyboard glyph.
func AiNpcPhoneHint(strip: ref<inkCompoundWidget>, name: CName, glyph: CName, word: String) -> Void {
    let hint = AiNpcPhoneHintFrame(strip, name);

    let icon = AiNpcInkImage(hint, n"hint_icon", AiNpcPhoneStyle.AtlasKeyboard(), glyph,
                             AiNpcStyle.Character());
    icon.SetSize(AiNpcPhoneStyle.IconSize());
    icon.SetTileHAlign(inkEHorizontalAlign.Left);
    icon.SetTileVAlign(inkEVerticalAlign.Top);
    icon.SetAnchor(inkEAnchor.Centered);
    icon.SetHAlign(inkEHorizontalAlign.Center);
    icon.SetVAlign(inkEVerticalAlign.Center);
    AiNpcInkBindTint(icon, AiNpcStyle.PropCharacterTint());

    AiNpcPhoneHintWord(hint, word);
}

// A thread choice. Its key is the digit written out: the keyboard atlas is not known to carry
// the digits, and a missing part draws nothing.
func AiNpcPhoneChoiceHint(strip: ref<inkCompoundWidget>, index: Int32, word: String) -> Void {
    let hint = AiNpcPhoneHintFrame(strip, AiNpcPhoneChoiceHintName(index));

    let key = AiNpcInkText(hint, n"hint_key", s"\(index + 1)", AiNpcPhoneStyle.FsHint(),
                           AiNpcStyle.Character());
    key.SetFontStyle(n"Semi-Bold");
    key.SetVAlign(inkEVerticalAlign.Center);
    key.SetFitToContent(true);

    AiNpcPhoneHintWord(hint, word);
}

func AiNpcPhoneChoiceHintName(index: Int32) -> CName {
    return StringToName(s"hint_choice_\(index)");
}

// The choices of the thread now shown, in place of the previous thread's.
func AiNpcPhoneShowChoices(strip: ref<inkCompoundWidget>, choices: array<ref<AiNpcThreadChoice>>) -> Void {
    let i = 0;
    while i < AiNpcThreadChoiceLimit() {
        strip.RemoveChildByName(AiNpcPhoneChoiceHintName(i));
        i += 1;
    }
    let count = ArraySize(choices);
    i = 0;
    while i < count {
        AiNpcPhoneChoiceHint(strip, i, choices[i].label);
        i += 1;
    }
}

// The whole strip. The order is the order they appear, right to left as the panel lays them
// out, and it is the order the player learns: undo what was just said, reset the whole
// thread, go back to the contact list. Out of Debug Mode the first is absent, and so is
// the key -- see AiNpcUndoAvailable. The thread's choices are added after, per contact.
func AiNpcPhoneBuildHints(parent: ref<inkCompoundWidget>) -> ref<inkHorizontalPanel> {
    let strip = AiNpcInkHorizontal(parent, n"hint_strip");
    strip.SetHAlign(inkEHorizontalAlign.Right);
    strip.SetVAlign(inkEVerticalAlign.Top);
    strip.SetFitToContent(true);
    strip.SetTranslation(new Vector2(0.0, 25.0));
    strip.SetChildMargin(new inkMargin(30.0, 0.0, 0.0, 0.0));

    let language = AiNpcResolveLanguage();
    // Undo is a Debug Mode tool. The strip fits its content, so dropping the hint closes
    // the gap on its own and the two that remain keep their places.
    if AiNpcUndoAvailable() {
        AiNpcPhoneHint(strip, n"hint_undo", n"kb_z", AiNpcUndoLabel(language));
    }
    AiNpcPhoneHint(strip, n"hint_reset", n"kb_r", AiNpcResetLabel(language));
    AiNpcPhoneHint(strip, n"hint_back", n"kb_c", AiNpcBackLabel(language));
    return strip;
}
