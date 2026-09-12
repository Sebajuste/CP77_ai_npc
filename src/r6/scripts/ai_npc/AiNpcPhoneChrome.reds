// The frame the chat is drawn in, and the only file that knows its shape.
//
//     chat_root
//     +-- header_holder        the header band          (AiNpcPhoneHeader)
//     +-- chat_column
//         +-- chat_body
//         |   +-- conversation_column
//         |   |   +-- conversation
//         |   |   |   +-- message_scroll -> scroll_column -> message_list  <- messages go here
//         |   |   |   |                                   -> typing_indicator (AiNpcPhoneTyping)
//         |   |   |   +-- list_fade_mask, scroll_bar, conversation_plate
//         |   |   +-- reply_options         the typed line     (AiNpcPhoneInput)
//         |   +-- width_spacer
//         +-- body_rule
//         +-- hint_strip                    (Z) / R / C        (AiNpcPhoneHints)
//
// ORDER IS LOAD-BEARING: three of these containers are inkEChildOrder.Backward, so the LAST
// child added is the one UNDERNEATH. Reordering the calls below reorders the panel visually,
// though nothing about the code reads as positional.
//
// It returns six handles, the complete list of what the renderer can still touch after the
// build. Everything else is drawn once and never spoken to again, which is what makes the
// renderer droppable.

module AiNpc

public class AiNpcPhoneChrome {
    // The panel itself. Kept only to play the entrance animation on it.
    public let root: ref<inkCanvas>;
    // Where bubbles are appended.
    public let messages: ref<inkVerticalPanel>;
    // The three dots, toggled by visibility.
    public let typing: ref<inkFlex>;
    public let scroll: ref<inkScrollController>;
    public let input: ref<AiNpcPhoneInputRow>;
    // Where the thread's choices are drawn, beside the fixed hints.
    public let hints: ref<inkHorizontalPanel>;
}

func AiNpcPhoneBuildChrome(container: wref<inkCanvas>, contactName: String) -> ref<AiNpcPhoneChrome> {
    let chrome = new AiNpcPhoneChrome();

    let root = AiNpcInkCanvas(container, n"chat_root");
    root.SetStyle(AiNpcStyle.PanelStyle());
    root.BindProperty(n"tintColor", AiNpcStyle.PropCharacterTint());
    root.SetChildOrder(inkEChildOrder.Backward);
    root.SetTintColor(AiNpcStyle.Character());
    root.SetSize(new Vector2(1500.0, 1500.0));
    chrome.root = root;

    let headerHolder = AiNpcInkCanvas(root, n"header_holder");
    headerHolder.SetMargin(new inkMargin(100.0, 0.0, 0.0, 0.0));
    headerHolder.SetSize(new Vector2(1550.0, 1200.0));
    headerHolder.SetChildOrder(inkEChildOrder.Backward);
    AiNpcPhoneBuildHeader(headerHolder, contactName);

    let wrapper = AiNpcInkVertical(root, n"chat_column");
    wrapper.SetMargin(new inkMargin(100.0, 50.0, 0.0, 0.0));
    wrapper.SetFitToContent(true);

    let content = AiNpcInkFlex(wrapper, n"chat_body");
    content.SetAnchor(inkEAnchor.BottomLeft);
    content.SetHAlign(inkEHorizontalAlign.Left);
    content.SetVAlign(inkEVerticalAlign.Top);
    content.SetMargin(new inkMargin(120.0, 0.0, 0.0, 0.0));
    content.SetSizeRule(inkESizeRule.Stretch);
    content.SetSize(new Vector2(100.0, 100.0));
    content.SetAffectsLayoutWhenHidden(true);

    let inner = AiNpcInkVertical(content, n"conversation_column");
    inner.SetMargin(new inkMargin(0.0, 0.0, 24.0, 0.0));
    inner.SetFitToContent(false);

    let conversation = AiNpcInkCanvas(inner, n"conversation");
    conversation.SetSizeRule(inkESizeRule.Stretch);
    conversation.SetSize(new Vector2(1300.0, 1400.0));
    conversation.SetAffectsLayoutWhenHidden(true);
    conversation.SetChildOrder(inkEChildOrder.Backward);
    conversation.SetInteractive(true);

    let scrollArea = new inkScrollArea();
    scrollArea.SetName(n"message_scroll");
    scrollArea.SetMargin(new inkMargin(20.0, 0.0, 35.0, 0.0));
    scrollArea.SetAnchor(inkEAnchor.Fill);
    scrollArea.SetUseInternalMask(false);
    scrollArea.SetSize(new Vector2(600.0, 600.0));
    scrollArea.Reparent(conversation);

    // The scroll area's only child: its height is what says how far the list scrolls.
    let scrollContainer = AiNpcInkVertical(scrollArea, n"scroll_column");
    scrollContainer.SetHAlign(inkEHorizontalAlign.Left);
    scrollContainer.SetVAlign(inkEVerticalAlign.Top);
    scrollContainer.SetFitToContent(true);

    let messages = AiNpcInkVertical(scrollContainer, n"message_list");
    messages.SetHAlign(inkEHorizontalAlign.Left);
    messages.SetVAlign(inkEVerticalAlign.Top);
    messages.SetFitToContent(true);
    messages.SetMargin(new inkMargin(0.0, 40.0, 0.0, 40.0));
    messages.SetChildMargin(new inkMargin(0.0, 5.0, 0.0, 0.0));
    chrome.messages = messages;

    chrome.typing = AiNpcPhoneBuildTypingIndicator(scrollContainer, contactName);

    // Fades the top and bottom of the list rather than cutting it: a bubble sliced by a hard
    // edge reads as a rendering fault, a faded one reads as more conversation.
    let mask = new inkMask();
    mask.SetName(n"list_fade_mask");
    mask.SetDataSource(inkMaskDataSource.TextureAtlas);
    mask.SetTextureAtlas(AiNpcPhoneStyle.AtlasMasks());
    mask.SetTexturePart(n"gradMask_journal_description");
    mask.SetDynamicTexture(n"entry_mask");
    mask.SetOpacity(0.01);
    mask.SetAnchor(inkEAnchor.Fill);
    mask.SetSize(new Vector2(1920.0, 1500.0));
    mask.Reparent(conversation);

    let scrollBar = AiNpcInkVertical(conversation, n"scroll_bar");
    scrollBar.SetAnchor(inkEAnchor.RightFillVerticaly);
    scrollBar.SetMargin(new inkMargin(0.0, 0.0, -5.0, 0.0));
    scrollBar.SetSize(new Vector2(8.0, 1125.0));

    let scrollTrack = AiNpcInkCanvas(scrollBar, n"scroll_track");
    scrollTrack.SetSize(new Vector2(8.0, 1125.0));
    scrollTrack.SetChildOrder(inkEChildOrder.Backward);

    let handle = AiNpcInkRect(scrollTrack, n"scroll_handle", AiNpcStyle.Accent());
    handle.SetOpacity(0.3);
    handle.SetAnchor(inkEAnchor.TopFillHorizontaly);
    handle.SetMargin(new inkMargin(0.0, 788.07, 0.0, 0.0));
    handle.SetSize(new Vector2(64.0, 20.0));
    AiNpcInkBind(handle, AiNpcStyle.MainColorsStyle(), n"tintColor", AiNpcStyle.PropAccentTint());

    let trackFill = AiNpcInkRect(scrollTrack, n"scroll_track_fill", AiNpcStyle.BackdropDeep());
    trackFill.SetOpacity(0.8);
    trackFill.SetSize(new Vector2(64.0, 64.0));
    trackFill.SetAnchor(inkEAnchor.Fill);
    AiNpcInkBind(trackFill, AiNpcStyle.MainColorsStyle(), n"tintColor",
                 n"MainColors.Fullscreen_PrimaryBackgroundDarkest");

    let sliderController = new inkSliderController();
    sliderController.slidingAreaRef = inkWidgetRef.Create(scrollTrack);
    sliderController.handleRef = inkWidgetRef.Create(handle);
    sliderController.direction = inkESliderDirection.Vertical;
    sliderController.autoSizeHandle = true;
    sliderController.percentHandleSize = 0.4;
    sliderController.minHandleSize = 40.0;
    sliderController.Setup(0, 1, 0, 0);

    let scrollController = new inkScrollController();
    scrollController.ScrollArea = inkScrollAreaRef.Create(scrollArea);
    scrollController.VerticalScrollBarRef = inkWidgetRef.Create(scrollTrack);
    scrollController.autoHideVertical = true;

    scrollTrack.AttachController(sliderController);
    conversation.AttachController(scrollController);
    chrome.scroll = scrollController;

    let fill = AiNpcInkImage(conversation, n"conversation_plate", AiNpcPhoneStyle.AtlasShapes(),
                             n"item_bg", AiNpcStyle.Backdrop());
    fill.SetNineSliceScale(true);
    fill.SetTileHAlign(inkEHorizontalAlign.Left);
    fill.SetTileVAlign(inkEVerticalAlign.Top);
    fill.SetOpacity(0.2);
    fill.SetAnchor(inkEAnchor.Fill);
    fill.SetAnchorPoint(new Vector2(0.5, 0.5));
    fill.SetSize(new Vector2(500.0, 500.0));
    fill.SetFitToContent(true);
    fill.SetAffectsLayoutWhenHidden(true);

    chrome.input = AiNpcPhoneBuildInputRow(inner);

    // Holds the column open at a fixed width. Without it the panel breathes as messages of
    // different lengths arrive.
    let widthSpacer = AiNpcInkCanvas(content, n"width_spacer");
    widthSpacer.SetHAlign(inkEHorizontalAlign.Left);
    widthSpacer.SetVAlign(inkEVerticalAlign.Top);
    widthSpacer.SetMargin(new inkMargin(24.0, 0.0, 24.0, 0.0));
    widthSpacer.SetSize(new Vector2(1250.0, 1250.0));
    widthSpacer.SetChildOrder(inkEChildOrder.Backward);

    let rule = AiNpcInkRect(wrapper, n"body_rule", AiNpcStyle.Accent());
    rule.SetAnchor(inkEAnchor.BottomFillHorizontaly);
    rule.SetVAlign(inkEVerticalAlign.Bottom);
    rule.SetOpacity(AiNpcPhoneStyle.RuleOpacity());
    rule.SetMargin(new inkMargin(120.0, 10.0, 20.0, 0.0));
    rule.SetSize(new Vector2(0.0, AiNpcPhoneStyle.HairlineHeight()));
    rule.SetRenderTransformPivot(new Vector2(0, 0.5));
    AiNpcInkBind(rule, AiNpcStyle.MainColorsStyle(), n"tintColor", AiNpcStyle.PropAccentTint());

    chrome.hints = AiNpcPhoneBuildHints(wrapper);

    return chrome;
}
