// The key hints along the bottom of the chat: reset, back, and undo when Debug Mode is on.
//
// They differ in exactly two things -- the keyboard glyph and the word -- so there is
// one builder and three calls. Everything else about a hint (the anchoring, the two style
// bindings, the gap between glyph and word) is stated once, because a hint that drifts out
// of line with the other two does not look wrong enough for anyone to report it.

module AiNpc

// One hint: a glyph and a word, side by side, anchored to the top right of the strip.
func AiNpcPhoneHint(strip: ref<inkCompoundWidget>, name: CName, glyph: CName, word: String) -> Void {
    let hint = AiNpcInkHorizontal(strip, name);
    hint.SetAnchor(inkEAnchor.TopRight);
    hint.SetAnchorPoint(new Vector2(1, 0));
    hint.SetHAlign(inkEHorizontalAlign.Left);
    hint.SetVAlign(inkEVerticalAlign.Top);
    hint.SetFitToContent(true);

    let icon = AiNpcInkImage(hint, n"hint_icon", AiNpcPhoneStyle.AtlasKeyboard(), glyph,
                             AiNpcStyle.Character());
    icon.SetSize(AiNpcPhoneStyle.IconSize());
    icon.SetTileHAlign(inkEHorizontalAlign.Left);
    icon.SetTileVAlign(inkEVerticalAlign.Top);
    icon.SetAnchor(inkEAnchor.Centered);
    icon.SetHAlign(inkEHorizontalAlign.Center);
    icon.SetVAlign(inkEVerticalAlign.Center);
    AiNpcInkBindTint(icon, AiNpcStyle.PropCharacterTint());

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

// The whole strip. The order is the order they appear, right to left as the panel lays them
// out, and it is the order the player learns: undo what was just said, reset the whole
// thread, go back to the contact list. Out of Debug Mode the first is absent, and so is
// the key -- see AiNpcUndoAvailable.
func AiNpcPhoneBuildHints(parent: ref<inkCompoundWidget>) -> Void {
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
}
