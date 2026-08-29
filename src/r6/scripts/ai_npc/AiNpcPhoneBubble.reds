// One message on the phone: a plate, a border, and the words.
//
// The whole difference between V and the character is six properties at the bottom of this
// file -- which side of the list the bubble hugs, which texture part the plate uses, and
// three colours. Everything above them is common to both, and stated once.
//
// It deliberately does NOT scroll: whether the view follows a new message down is the
// SESSION's decision, taken before the message is painted, so a player who had scrolled up is
// left where they were. And it does not send: `animate` means the message is arriving now and
// nothing else. The send sequence is AiNpcSystem.SendTyped.

module AiNpc

func AiNpcPhoneBuildMessage(parent: wref<inkVerticalPanel>, player: wref<PlayerPuppet>,
                                   text: String, fromPlayer: Bool, animate: Bool) -> Void {
    if !IsDefined(parent) {
        return;
    }

    // A model that starts its reply with a blank line would otherwise open the bubble with
    // an empty row, and the plate is sized from its content.
    while StrBeginsWith(text, "\n") || StrBeginsWith(text, " ") {
        text = StrRight(text, StrLen(text) - 1);
    }

    let message = AiNpcInkFlex(parent, n"message_bubble");
    message.SetHAlign(inkEHorizontalAlign.Left);
    message.SetSize(new Vector2(100.0, 100.0));
    message.SetStyle(AiNpcStyle.MessengerStyle());

    // Holds the row open to full width so a short message does not shrink the list.
    let wide = AiNpcInkCanvas(message, n"bubble_width_spacer");
    wide.SetHAlign(inkEHorizontalAlign.Left);
    wide.SetSize(new Vector2(1200.0, 600.0));
    wide.SetChildOrder(inkEChildOrder.Backward);

    let container = AiNpcInkFlex(message, n"bubble_body");
    container.SetVAlign(inkEVerticalAlign.Top);
    container.SetSize(new Vector2(100.0, 100.0));

    let background = AiNpcInkImage(container, n"bubble_plate", AiNpcPhoneStyle.AtlasPhone(),
                                   n"msgBuble_bg", AiNpcStyle.CharacterPlate());
    background.SetNineSliceScale(true);
    background.SetTileHAlign(inkEHorizontalAlign.Left);
    background.SetTileVAlign(inkEVerticalAlign.Top);
    background.SetSize(new Vector2(32.0, 32.0));
    background.SetFitToContent(true);
    AiNpcInkBind(background, AiNpcStyle.MainColorsStyle(), n"tintColor", n"Message.BackgroundColor");
    background.BindProperty(n"opacity", n"Message.BackgroundOpacity");

    let border = AiNpcInkImage(container, n"bubble_edge", AiNpcPhoneStyle.AtlasPhone(),
                               n"msgBuble_fg", AiNpcStyle.CharacterEdge());
    border.SetNineSliceScale(true);
    border.SetTileHAlign(inkEHorizontalAlign.Left);
    border.SetTileVAlign(inkEVerticalAlign.Top);
    border.SetOpacity(0.5);
    border.SetSize(new Vector2(32.0, 32.0));
    border.SetFitToContent(true);
    AiNpcInkBind(border, AiNpcStyle.MainColorsStyle(), n"tintColor", n"Message.BorderColor");

    let content = AiNpcInkVertical(container, n"bubble_content");
    content.SetHAlign(inkEHorizontalAlign.Left);
    content.SetVAlign(inkEVerticalAlign.Top);
    content.SetMargin(new inkMargin(24.0, 20.0, 20.0, 30.0));
    content.SetFitToContent(true);

    let body = AiNpcInkText(content, n"bubble_text", text, AiNpcPhoneStyle.FsInput(),
                            AiNpcStyle.Character());
    body.SetLetterCase(AiNpcStyle.BodyCase());
    body.SetContentVAlign(inkEVerticalAlign.Top);
    body.SetWrapping(true);
    body.SetWrappingAtPosition(1000);
    body.SetHAlign(inkEHorizontalAlign.Left);
    body.SetVAlign(inkEVerticalAlign.Top);
    body.SetMargin(new inkMargin(0.0, 0.0, 10.0, 0.0));
    body.SetSize(new Vector2(0.0, 32.0));
    body.SetFitToContent(true);
    body.SetStyle(AiNpcStyle.MainColorsStyle());
    body.BindProperty(n"tintColor", n"Message.TextColor");
    body.BindProperty(n"fontSize", n"MainColors.ReadableMedium");

    //
    // The plain colours below are overridden by the bindings above wherever the HUD's style
    // resolves; they are the fallback, and they are also what a reader of this file goes by.

    if fromPlayer {
        message.SetState(n"Player");
        container.SetHAlign(inkEHorizontalAlign.Right);
        background.SetTexturePart(n"msgBuble_reply_bg");
        background.SetTintColor(AiNpcStyle.PlayerEdge());
        background.SetOpacity(0.05);
        border.SetTexturePart(n"msgBuble_reply_fg");
        border.SetTintColor(AiNpcStyle.PlayerEdge());
        body.SetTintColor(AiNpcStyle.Player());
    } else {
        container.SetHAlign(inkEHorizontalAlign.Left);
        background.SetOpacity(0.35);
    }

    if animate {
        message.PlayAnimation(AiNpcPhoneMessageAnim());
        AiNpcPhonePlaySound(player, n"ui_messenger_recieved");
    }
}
