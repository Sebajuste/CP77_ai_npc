// The band across the top: MESSAGES, an arrow, and who you are talking to.
//
//     [envelope] MESSAGES  >  PANAM PALMER  ------------------
//     ==========            ==============
//     TRN_TCLAS_800095                            VER_M6A6T6I
//
// A breadcrumb, in the game's own idiom: the thick cyan rules under each label, the coral
// hairline running off to the right, and two serial numbers in the corners that mean nothing
// and are there because every panel in this game has them.
//
// It returns nothing, because nothing in here is ever touched again: the contact's name is
// baked in at build time, since the chat is rebuilt when the contact changes, and a handle
// kept for a swap that never happens is a handle that can outlive its tree.

module AiNpc

// One of the two corner serial numbers. Identical but for the text and which corner they
// hang in, which is the whole reason this is a function.
func AiNpcPhoneHeaderFluff(parent: ref<inkCompoundWidget>, name: CName, text: String,
                           alignment: inkEHorizontalAlign, margin: inkMargin) -> Void {
    let fluff = AiNpcInkText(parent, name, text, AiNpcPhoneStyle.FsFluff(), AiNpcStyle.Accent());
    fluff.SetLetterCase(AiNpcStyle.HeadingCase());
    fluff.SetAnchor(inkEAnchor.TopRight);
    fluff.SetHAlign(alignment);
    if Equals(alignment, inkEHorizontalAlign.Right) {
        fluff.SetVAlign(inkEVerticalAlign.Bottom);
        fluff.SetRenderTransformPivot(new Vector2(1, 0.5));
    } else {
        fluff.SetVAlign(inkEVerticalAlign.Top);
    }
    fluff.SetMargin(margin);
    fluff.SetSize(new Vector2(100.0, 32.0));
    fluff.SetFitToContent(true);
    fluff.SetStyle(AiNpcStyle.MainColorsStyle());
    fluff.BindProperty(n"fontStyle", n"MainColors.BodyFontWeight");
    fluff.BindProperty(n"tintColor", AiNpcStyle.PropAccentTint());
}

func AiNpcPhoneBuildHeader(parent: ref<inkCompoundWidget>, contactName: String) -> Void {
    let holder = AiNpcInkFlex(parent, n"header_band");
    holder.SetAnchor(inkEAnchor.TopFillHorizontaly);
    holder.SetHAlign(inkEHorizontalAlign.Left);
    holder.SetVAlign(inkEVerticalAlign.Top);
    holder.SetMargin(new inkMargin(120.0, -60.0, 0.0, 0.0));
    holder.SetSize(new Vector2(100.0, 100.0));

    let row = AiNpcInkHorizontal(holder, n"header_row");
    row.SetSize(new Vector2(100.0, 100.0));
    row.SetFitToContent(true);
    row.SetVAlign(inkEVerticalAlign.Top);

    let pathColumn = AiNpcInkVertical(row, n"breadcrumb_column");
    pathColumn.SetHAlign(inkEHorizontalAlign.Left);
    pathColumn.SetVAlign(inkEVerticalAlign.Top);
    pathColumn.SetPadding(new inkMargin(0.0, 0.0, 20.0, 0.0));
    pathColumn.SetFitToContent(true);

    let path = AiNpcInkHorizontal(pathColumn, n"breadcrumb_row");
    path.SetOpacity(0.6);
    path.SetHAlign(inkEHorizontalAlign.Left);
    path.SetVAlign(inkEVerticalAlign.Top);
    path.SetSizeRule(inkESizeRule.Stretch);
    path.SetFitToContent(true);
    path.SetChildMargin(new inkMargin(0.0, 20.0, 0.0, 20.0));

    let pathRule = AiNpcInkRect(pathColumn, n"breadcrumb_rule", AiNpcStyle.Character());
    pathRule.SetMargin(new inkMargin(-20.0, 0.0, -20.0, 0.0));
    pathRule.SetSize(new Vector2(0.0, AiNpcPhoneStyle.RuleHeight()));
    AiNpcInkBindTint(pathRule, AiNpcStyle.PropCharacterTint());

    let envelope = AiNpcInkImage(path, n"breadcrumb_icon", AiNpcPhoneStyle.AtlasCommonIcons(),
                                 n"ico_envelelope", AiNpcStyle.Character());
    envelope.SetTileHAlign(inkEHorizontalAlign.Left);
    envelope.SetTileVAlign(inkEVerticalAlign.Top);
    envelope.SetHAlign(inkEHorizontalAlign.Center);
    envelope.SetVAlign(inkEVerticalAlign.Center);
    envelope.SetSize(new Vector2(48.0, 48.0));
    envelope.SetFitToContent(true);
    AiNpcInkBindTint(envelope, AiNpcStyle.PropCharacterTint());
    envelope.BindProperty(n"opacity", AiNpcStyle.PropLabelOpacity());

    let pathText = AiNpcInkText(path, n"breadcrumb_label", AiNpcMessagesHeaderLabel(AiNpcResolveLanguage()),
                                AiNpcPhoneStyle.FsHeading(), AiNpcStyle.Character());
    pathText.SetLetterCase(AiNpcStyle.HeadingCase());
    pathText.SetVerticalAlignment(textVerticalAlignment.Center);
    pathText.SetContentHAlign(inkEHorizontalAlign.Center);
    pathText.SetContentVAlign(inkEVerticalAlign.Center);
    pathText.SetHAlign(inkEHorizontalAlign.Left);
    pathText.SetVAlign(inkEVerticalAlign.Center);
    pathText.SetAnchor(inkEAnchor.Centered);
    pathText.SetAnchorPoint(new Vector2(0.5, 0.5));
    pathText.SetMargin(new inkMargin(10.0, 0.0, 0.0, 0.0));
    pathText.SetFitToContent(true);
    AiNpcInkBindTint(pathText, AiNpcStyle.PropCharacterTint());
    pathText.BindProperty(n"fontSize", n"MainColors.ReadableFontSize");
    pathText.BindProperty(n"opacity", AiNpcStyle.PropLabelOpacity());

    let arrow = AiNpcInkImage(row, n"breadcrumb_arrow", AiNpcPhoneStyle.AtlasNotification(), n"+1",
                              AiNpcStyle.Character());
    arrow.SetTileHAlign(inkEHorizontalAlign.Left);
    arrow.SetTileVAlign(inkEVerticalAlign.Top);
    arrow.SetHAlign(inkEHorizontalAlign.Center);
    arrow.SetVAlign(inkEVerticalAlign.Center);
    arrow.SetMargin(new inkMargin(0.0, -20.0, 0.0, 0.0));
    arrow.SetSize(new Vector2(20.0, 20.0));
    arrow.SetFitToContent(true);
    arrow.SetRotation(90);
    AiNpcInkBindTint(arrow, AiNpcStyle.PropCharacterTint());

    let nameHolder = AiNpcInkFlex(row, n"contact_holder");
    nameHolder.SetMargin(new inkMargin(20.0, 0.0, 0.0, 0.0));
    nameHolder.SetSize(new Vector2(100.0, 100.0));

    let nameRule = AiNpcInkRect(nameHolder, n"contact_rule", AiNpcStyle.Character());
    nameRule.SetVAlign(inkEVerticalAlign.Bottom);
    nameRule.SetMargin(new inkMargin(-20.0, 0.0, -20.0, 0.0));
    nameRule.SetSize(new Vector2(300.0, AiNpcPhoneStyle.RuleHeight()));
    AiNpcInkBindTint(nameRule, AiNpcStyle.PropCharacterTint());

    let nameText = AiNpcInkText(nameHolder, n"contact_name", contactName,
                                AiNpcPhoneStyle.FsHeading(), AiNpcStyle.Character());
    nameText.SetLetterCase(AiNpcStyle.HeadingCase());
    nameText.SetHorizontalAlignment(textHorizontalAlignment.Center);
    nameText.SetVerticalAlignment(textVerticalAlignment.Center);
    nameText.SetContentHAlign(inkEHorizontalAlign.Left);
    // A name too long to fit scrolls rather than being cut: a truncated contact name is the
    // one label in this panel a player could mistake for a different person.
    nameText.SetOverflowPolicy(textOverflowPolicy.AutoScroll);
    nameText.SetWrappingAtPosition(700);
    nameText.SetHAlign(inkEHorizontalAlign.Left);
    nameText.SetVAlign(inkEVerticalAlign.Center);
    nameText.SetMargin(new inkMargin(0.0, -12.0, 0.0, 0.0));
    nameText.SetSizeRule(inkESizeRule.Stretch);
    nameText.SetSize(new Vector2(900.0, 63.0));
    nameText.SetFitToContent(true);
    AiNpcInkBindTint(nameText, AiNpcStyle.PropCharacterTint());

    let hairline = AiNpcInkRect(row, n"header_hairline", AiNpcStyle.Accent());
    hairline.SetVAlign(inkEVerticalAlign.Center);
    hairline.SetMargin(new inkMargin(30.0, 92.0, 270.0, 0.0));
    hairline.SetSizeRule(inkESizeRule.Stretch);
    hairline.SetSize(new Vector2(0.0, AiNpcPhoneStyle.HairlineHeight()));
    hairline.SetRenderTransformPivot(new Vector2(1, 0.5));
    AiNpcInkBind(hairline, AiNpcStyle.MainColorsStyle(), n"tintColor", n"MainColors.PanelRed");

    AiNpcPhoneHeaderFluff(holder, n"header_serial_left", "TRN_TCLAS_800095",
                          inkEHorizontalAlign.Left, new inkMargin(0.0, -20.0, 0.0, 0.0));
    AiNpcPhoneHeaderFluff(holder, n"header_serial_right", "VER_M6A6T6I",
                          inkEHorizontalAlign.Right, new inkMargin(0.0, 0.0, 269.00, 10.00));
}
