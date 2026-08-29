// The three animated dots, and the line that says who is writing them.
//
// The dots differ from each other in nothing at all, and from the label in exactly two
// properties -- the font weight and the constant that weight binds to -- so there is one
// builder called four times, and those two properties are its only parameters.

module AiNpc

// One piece of the indicator: the label, or a dot.
//
// Everything else about them is identical, including the wrapping position -- which looks
// wrong on a full stop and is not: they sit in the same horizontal panel and a dot with a
// different wrap would sit on a different baseline.
func AiNpcPhoneTypingPart(parent: ref<inkCompoundWidget>, text: String,
                          weight: CName, weightBinding: CName) -> ref<inkText> {
    let part = AiNpcInkText(parent, n"typing_part", text, AiNpcPhoneStyle.FsHint(),
                            AiNpcStyle.Character());
    part.SetFontStyle(weight);
    part.SetLetterCase(AiNpcStyle.BodyCase());
    part.SetContentVAlign(inkEVerticalAlign.Top);
    part.SetWrappingAtPosition(800);
    part.SetHAlign(inkEHorizontalAlign.Left);
    part.SetVAlign(inkEVerticalAlign.Top);
    part.SetSize(new Vector2(0.0, 32.0));
    part.SetFitToContent(true);
    part.SetStyle(AiNpcStyle.MainColorsStyle());
    part.BindProperty(n"tintColor", n"Message.TextColor");
    part.BindProperty(n"fontSize", n"MainColors.ReadableSmall");
    part.BindProperty(n"fontStyle", weightBinding);
    return part;
}

// The whole indicator, hidden. Returns the widget whose visibility IS the indicator being
// on or off -- the caller keeps that one handle and nothing else from in here.
func AiNpcPhoneBuildTypingIndicator(parent: ref<inkCompoundWidget>,
                                           contactName: String) -> ref<inkFlex> {
    let indicator = AiNpcInkFlex(parent, n"typing_indicator");
    indicator.SetVAlign(inkEVerticalAlign.Bottom);
    indicator.SetSize(new Vector2(100.0, 100.0));
    indicator.SetVisible(false);

    let row = AiNpcInkHorizontal(indicator, n"typing_row");
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.SetVAlign(inkEVerticalAlign.Top);
    row.SetMargin(new inkMargin(0.0, 0.0, 0.0, 25.0));
    row.SetFitToContent(true);
    row.SetStyle(AiNpcStyle.MessengerStyle());
    row.SetChildMargin(new inkMargin(0.0, 0.0, 4.0, 0.0));

    AiNpcPhoneTypingPart(row, contactName + AiNpcIsTypingLabel(AiNpcResolveLanguage()),
                         AiNpcStyle.FontStyleBody(), n"MainColors.BodyFontWeight");

    let dot: Int32 = 0;
    while dot < 3 {
        AiNpcPhoneTypingPart(row, ".", n"Semi-Bold", n"MainColors.HeaderFontWeight");
        dot += 1;
    }

    return indicator;
}
