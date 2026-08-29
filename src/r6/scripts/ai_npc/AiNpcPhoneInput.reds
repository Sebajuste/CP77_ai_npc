// The line the player types into, and the walk into the field another mod owns.
//
// Building the row and reading what is in it are here together because the second only works
// if you know how the first built the row: the field is at index 1 of the wrapper BECAUSE
// this file put it there. Split them and a positional read in one file is justified by a
// decision in another.
//
// Codeware's HubTextInput is another mod's widget, and reading the text means four positional
// steps into its innards. Same rule as every other foreign tree here -- one resolver, all or
// nothing: AiNpcPhoneInputField is the single walk, so a Codeware version that nests one
// level differently costs an empty string rather than the chat.
//
// This is the mod's last dependence on Codeware. It is removable -- a widget listening for
// n"OnInputKey" does receive keys inside inkHUDLayer, which AiNpcHudKeyProbe measured -- but
// removing it is a rewrite of the input row, not a tidy-up.

module AiNpc

// The one dependency this surface has on another mod, and it is confined to this file --
// see the header. AiNpcPhoneChrome, AiNpcPhoneHeader, AiNpcPhoneBubble and the rest draw
// with vanilla ink only.
import Codeware.UI.*

// The player's field, or null when there is none on screen.
//
// "There is nothing there" is the COMMON case, not an error: the field exists only while the
// player is actually typing, and every send removes it before the next input refresh asks
// for it again. A caller that assumes the answer is yes dereferences null on the ORDINARY
// path, once per turn.
func AiNpcPhoneTypedInput(wrapper: wref<inkHorizontalPanel>) -> wref<inkCompoundWidget> {
    if !IsDefined(wrapper) || wrapper.GetNumChildren() <= 1 {
        return null;
    }
    return wrapper.GetWidget(1) as inkCompoundWidget;
}

// The one walk into Codeware's tree. Every step guarded, one answer, and a miss costs the
// text rather than the session.
func AiNpcPhoneInputField(input: wref<inkCompoundWidget>) -> wref<inkText> {
    if !IsDefined(input) {
        return null;
    }
    let level1 = input.GetWidget(1) as inkCompoundWidget;
    if !IsDefined(level1) {
        return null;
    }
    let level2 = level1.GetWidget(0) as inkCompoundWidget;
    if !IsDefined(level2) {
        return null;
    }
    return level2.GetWidget(1) as inkText;
}

// What the player typed, or "" -- which is a usable "nothing to send" for every caller, so
// there is nothing to gain from asserting a shape we do not own.
func AiNpcPhoneGetInputText(wrapper: wref<inkHorizontalPanel>) -> String {
    let field = AiNpcPhoneInputField(AiNpcPhoneTypedInput(wrapper));
    if !IsDefined(field) {
        return "";
    }
    return field.GetText();
}

// Takes the field away if there is one.
func AiNpcPhoneRemoveInput(wrapper: wref<inkHorizontalPanel>) -> Void {
    let input = AiNpcPhoneTypedInput(wrapper);
    if IsDefined(input) {
        wrapper.RemoveChildByName(input.GetName());
    }
}

// Puts a field in the row and gives it the keyboard.
func AiNpcPhoneBeginInput(wrapper: wref<inkHorizontalPanel>) -> Void {
    let inkSystem = GameInstance.GetInkSystem();
    let input = HubTextInput.Create();
    input.SetText("");
    input.Reparent(wrapper);

    let widget = AiNpcPhoneTypedInput(wrapper);
    if IsDefined(widget) {
        widget.RemoveChildByName(n"theme");
        widget.SetTranslation(new Vector2(0.0, -9.0));

        // Cosmetic: not finding the caret costs a yellow that is not there, and nothing else.
        let field = AiNpcPhoneInputField(widget);
        if IsDefined(field) {
            field.SetTintColor(AiNpcStyle.Caret());
        }
    }

    inkSystem.SetFocus(input.GetRootWidget());
}

// What the caller keeps: the wrapper a field is put into, the resting label, and the click
// hint whose glyph changes between "click to type" and "press enter".
public class AiNpcPhoneInputRow {
    public let wrapper: ref<inkHorizontalPanel>;
    public let label: ref<inkText>;
    public let hint: ref<inkImage>;
}

func AiNpcPhoneBuildInputRow(parent: ref<inkCompoundWidget>) -> ref<AiNpcPhoneInputRow> {
    let options = AiNpcInkVertical(parent, n"reply_options");
    options.SetAnchor(inkEAnchor.BottomLeft);
    options.SetMargin(new inkMargin(0.0, 10.0, 0.0, 10.0));
    options.SetSizeCoefficient(0.5);
    options.SetFitToContent(true);

    // The vanilla messenger's own "selected reply" state, borrowed: it is what makes the row
    // read as a thing you can click rather than a label.
    let item = AiNpcInkHorizontal(options, n"reply_item");
    item.SetHAlign(inkEHorizontalAlign.Right);
    item.SetVAlign(inkEVerticalAlign.Top);
    item.SetMargin(new inkMargin(0.0, 10.0, 0.0, 0.0));
    item.SetFitToContent(true);
    item.SetStyle(AiNpcStyle.MessengerStyle());
    item.SetState(n"QuestSelected");
    item.SetChildMargin(new inkMargin(0.0, 0.0, 0.0, 7.0));

    let textFlex = AiNpcInkFlex(item, n"reply_row");
    textFlex.SetHAlign(inkEHorizontalAlign.Right);
    textFlex.SetVAlign(inkEVerticalAlign.Top);
    textFlex.SetMargin(new inkMargin(10.0, 0.0, 0.0, 0.0));
    textFlex.SetSizeRule(inkESizeRule.Stretch);
    textFlex.SetFitToContent(true);
    textFlex.SetSize(new Vector2(100.0, 100.0));

    let background = AiNpcInkImage(textFlex, n"reply_plate", AiNpcPhoneStyle.AtlasPhone(),
                                   n"msgBuble_reply_bg", AiNpcStyle.Trim());
    background.SetNineSliceScale(true);
    background.SetTileHAlign(inkEHorizontalAlign.Left);
    background.SetTileVAlign(inkEVerticalAlign.Top);
    background.SetOpacity(0.15);
    background.SetSize(new Vector2(32.0, 32.0));
    background.SetFitToContent(true);
    AiNpcInkBind(background, AiNpcStyle.MainColorsStyle(), n"tintColor", n"MessageReply.BackgroundColor");
    background.BindProperty(n"opacity", n"MessageReply.BackgroundOpacity");

    let row = new AiNpcPhoneInputRow();

    let wrapper = AiNpcInkHorizontal(textFlex, n"reply_wrapper");
    wrapper.SetHAlign(inkEHorizontalAlign.Right);
    wrapper.SetVAlign(inkEVerticalAlign.Center);
    wrapper.SetFitToContent(true);
    row.wrapper = wrapper;

    // Index 0 of the wrapper. The field lands at index 1, which is the fact
    // AiNpcPhoneTypedInput depends on.
    let label = AiNpcInkText(wrapper, n"reply_label",
                             AiNpcSendMessageLabel(AiNpcResolveLanguage()),
                             AiNpcPhoneStyle.FsInput(), AiNpcStyle.Caret());
    label.SetLetterCase(AiNpcStyle.BodyCase());
    label.SetOverflowPolicy(textOverflowPolicy.DotsEnd);
    label.SetWrappingAtPosition(1000);
    label.SetHAlign(inkEHorizontalAlign.Left);
    label.SetVAlign(inkEVerticalAlign.Center);
    label.SetMargin(new inkMargin(17.0, 17.0, 30.0, 30.0));
    label.SetSize(new Vector2(750.0, 63.0));
    label.SetFitToContent(true);
    label.SetTranslation(new Vector2(0.50, 0.50));
    label.SetStyle(AiNpcStyle.MainColorsStyle());
    label.BindProperty(n"fontSize", n"MainColors.ReadableMedium");
    label.BindProperty(n"fontStyle", n"MainColors.BodyFontWeight");
    label.BindProperty(n"tintColor", n"MessageReply.TextColor");
    label.BindProperty(n"opacity", n"MessageReply.TextOpacity");
    row.label = label;

    let border = AiNpcInkImage(textFlex, n"reply_edge", AiNpcPhoneStyle.AtlasPhone(),
                               n"msgBuble_reply_fg", AiNpcStyle.Trim());
    border.SetNineSliceScale(true);
    border.SetTileHAlign(inkEHorizontalAlign.Left);
    border.SetTileVAlign(inkEVerticalAlign.Top);
    border.SetSize(new Vector2(32.0, 32.0));
    border.SetFitToContent(true);
    AiNpcInkBind(border, AiNpcStyle.MainColorsStyle(), n"tintColor", n"MessageReply.BorderColor");
    border.BindProperty(n"opacity", n"MessageReply.BorderOpacity");

    let bullet = AiNpcInkCanvas(item, n"reply_bullet");
    bullet.SetVAlign(inkEVerticalAlign.Bottom);
    bullet.SetMargin(new inkMargin(10.0, 0.0, 0.0, 0.0));
    bullet.SetSize(new Vector2(43.0, 43.0));
    bullet.SetAffectsLayoutWhenHidden(true);
    AiNpcInkBind(bullet, AiNpcStyle.MainColorsStyle(), n"opacity", n"MessageReply.SelectionBulletOpacity");
    bullet.SetChildOrder(inkEChildOrder.Backward);

    let hintRow = AiNpcInkHorizontal(bullet, n"reply_hint_row");
    hintRow.SetAnchor(inkEAnchor.CenterRight);
    hintRow.SetAnchorPoint(new Vector2(1, 1));
    hintRow.SetHAlign(inkEHorizontalAlign.Left);
    hintRow.SetVAlign(inkEVerticalAlign.Top);
    hintRow.SetMargin(new inkMargin(0.0, 0.0, -36.0, 0.0));
    hintRow.SetFitToContent(true);
    hintRow.SetChildMargin(new inkMargin(0.0, 0.0, 10.0, 0.0));

    let hint = AiNpcInkImage(hintRow, n"reply_hint_icon", AiNpcPhoneStyle.AtlasKeyboard(),
                             n"mouse_left", AiNpcStyle.Character());
    hint.SetTileHAlign(inkEHorizontalAlign.Left);
    hint.SetTileVAlign(inkEVerticalAlign.Top);
    hint.SetAnchor(inkEAnchor.Centered);
    hint.SetHAlign(inkEHorizontalAlign.Center);
    hint.SetVAlign(inkEVerticalAlign.Center);
    hint.SetSize(AiNpcPhoneStyle.IconSize());
    AiNpcInkBindTint(hint, AiNpcStyle.PropCharacterTint());
    row.hint = hint;

    return row;
}
