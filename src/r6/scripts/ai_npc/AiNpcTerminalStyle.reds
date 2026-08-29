// Every number and every colour the computer-terminal chat draws with.
//
// The browser gives a page a frame of about 3140 x 1200 units, NOT pixels, which is why
// font sizes of 32 to 76 are ordinary here. A page states its own size: SetAnchor(Fill)
// fills page_content, which is larger than the visible frame, and inkScrollArea needs a
// content widget with a declared size or it has nothing to scroll.
//
// Lengths are frame units used as written; Scale() applies to font sizes only, so shrinking
// the text gives the page more room instead of the same proportion of a smaller box. The
// one length it reaches is a bubble's height, a line count times the body font size.

module AiNpc

public abstract class AiNpcTerminalStyle {

    // 0.8 measured, not chosen: the smallest size read as comfortable off a screen with a
    // live A- / A+ dial, against this same base set (76 / 46 / 40 / 32).
    public static func Scale() -> Float {
        return 0.8;
    }

    public static func Scaled(base: Int32) -> Int32 {
        let value: Int32 = Cast<Int32>(Cast<Float>(base) * AiNpcTerminalStyle.Scale());
        if value < 12 {
            // Below this nothing is legible at any distance, and a zero would be an
            // invisible widget that reads as a build failure rather than a bad setting.
            return 12;
        }
        return value;
    }

    public static func ScaledF(base: Float) -> Float {
        return base * AiNpcTerminalStyle.Scale();
    }

    //

    // The scroll area clips its own content. The phone's inkMask bound to the dynamic
    // texture n"entry_mask" is HUD machinery that fails silently on a device screen: no
    // clipping at all.
    public static func UseInternalMask() -> Bool {
        return true;
    }

    public static func PageWidth() -> Float {
        return 3140.0;
    }

    public static func PageHeight() -> Float {
        return 1200.0;
    }

    // Applied once, to the viewport, so no page can forget it.
    public static func SideMargin() -> Float {
        return 180.0;
    }

    public static func TitleY() -> Float {
        return 40.0;
    }

    public static func SubtitleY() -> Float {
        return 150.0;
    }

    public static func NavY() -> Float {
        return 200.0;
    }

    // Derived from the navigation row, never typed: two constants that have to agree
    // eventually will not, and the failure is rows drawn through the buttons.
    public static func HeaderHeight() -> Float {
        return AiNpcTerminalStyle.NavY() + AiNpcTerminalStyle.ButtonHeight() + 30.0;
    }

    public static func FooterHeight() -> Float {
        return 150.0;
    }

    public static func ViewportWidth() -> Float {
        return AiNpcTerminalStyle.PageWidth() - AiNpcTerminalStyle.SideMargin() - 260.0;
    }

    public static func BottomPadding() -> Float {
        return 60.0;
    }

    public static func FontFamily() -> String {
        return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily";
    }

    public static func FontStyleBody() -> CName {
        return n"Medium";
    }

    public static func FontStyleBold() -> CName {
        return n"Semi-Bold";
    }

    public static func FsTitle() -> Int32 {
        return AiNpcTerminalStyle.Scaled(76);
    }

    public static func FsHeading() -> Int32 {
        return AiNpcTerminalStyle.Scaled(46);
    }

    public static func FsBody() -> Int32 {
        return AiNpcTerminalStyle.Scaled(40);
    }

    public static func FsSmall() -> Int32 {
        return AiNpcTerminalStyle.Scaled(32);
    }

    //
    // Plain Color values, never BindProperty. MainColors.* / Message.* are constants of the
    // HUD's readability style: the wrong authority on a screen rendered into a texture, and
    // a bound value cannot be corrected from here. AiNpcStyle carries both halves.

    public static func ColPlayer() -> Color {
        return AiNpcStyle.Player();
    }

    public static func ColNpc() -> Color {
        return AiNpcStyle.Character();
    }

    public static func ColBone() -> Color {
        return AiNpcStyle.Body();
    }

    public static func ColDim() -> Color {
        return AiNpcStyle.Dim();
    }

    public static func ColAccent() -> Color {
        return AiNpcStyle.Accent();
    }

    public static func RowHeight() -> Float {
        return 130.0;
    }

    public static func RowGap() -> Float {
        return 14.0;
    }

    public static func RowOpacity() -> Float {
        return 0.10;
    }

    // The solid edge down a plate's left side: a 10% wash alone blends into the background.
    public static func EdgeWidth() -> Float {
        return 6.0;
    }

    public static func EdgeOpacity() -> Float {
        return 0.55;
    }

    public static func RowTextInset() -> Float {
        return 30.0;
    }

    // Characters, not units: nothing on this side can measure text.
    public static func RowPreviewChars() -> Int32 {
        return 90;
    }

    // The character budget one line of a bubble gets, which is what decides how wide a
    // bubble looks.
    public static func BubbleWrapChars() -> Int32 {
        return 78;
    }

    // Paired with BubbleWrapChars by eye: too narrow and the text runs out of the plate,
    // too wide and a one-word reply is a banner.
    public static func BubbleWidth() -> Float {
        return 1700.0;
    }

    public static func BubblePadding() -> inkMargin {
        return new inkMargin(30.0, 22.0, 30.0, 24.0);
    }

    public static func BubbleGap() -> Float {
        return 16.0;
    }

    // A multiple of the body font size: raise it if lines overlap, lower it if bubbles look
    // padded.
    public static func BubbleLineFactor() -> Float {
        return 1.35;
    }

    public static func BubbleBackgroundOpacity() -> Float {
        return 0.12;
    }

    public static func BubbleBorderOpacity() -> Float {
        return 0.5;
    }

    // A reply longer than this is drawn as two bubbles. The phone splits at 1000: past some
    // length a single text widget stops laying out correctly, and where that length falls on
    // a device screen is unmeasured.
    public static func BubbleSplitChars() -> Int32 {
        return 1000;
    }

    // The nine-slice plates the phone bubbles are made of. False draws flat rectangles, the
    // fallback if atlas scaling looks wrong at texture resolution.
    public static func UseAtlasBubbles() -> Bool {
        return false;
    }

    public static func BubbleAtlas() -> ResRef {
        return r"base\\gameplay\\gui\\widgets\\phone\\new_phone_assets.inkatlas";
    }

    public static func BubbleBackgroundPartNpc() -> CName {
        return n"msgBuble_bg";
    }

    public static func BubbleBorderPartNpc() -> CName {
        return n"msgBuble_fg";
    }

    public static func BubbleBackgroundPartPlayer() -> CName {
        return n"msgBuble_reply_bg";
    }

    public static func BubbleBorderPartPlayer() -> CName {
        return n"msgBuble_reply_fg";
    }

    // How many stored messages a page draws. Older messages stay in the history and in the
    // prompt; they are simply not drawn.
    public static func MaxMessagesShown() -> Int32 {
        return 40;
    }

    //
    // The track is pinned near the right edge of the FRAME, never anchored to the viewport:
    // an anchored track and a sized viewport disagree about where the travel starts, and the
    // handle then leads or lags the content.

    public static func ScrollBarX() -> Float {
        return 3090.0;
    }

    public static func ScrollBarY() -> Float {
        return 32.0;
    }

    public static func ScrollBarWidth() -> Float {
        return 12.0;
    }

    public static func ScrollHandleHeight() -> Float {
        return 120.0;
    }

    public static func ScrollHandleMinSize() -> Float {
        return 70.0;
    }

    public static func ScrollTrackOpacity() -> Float {
        return 0.22;
    }

    public static func ScrollHandleOpacity() -> Float {
        return 0.80;
    }

    public static func FieldHeight() -> Float {
        return 104.0;
    }

    public static func FieldTextInset() -> Float {
        return 24.0;
    }

    public static func FieldFillOpacity() -> Float {
        return 0.10;
    }

    public static func FieldFocusOpacity() -> Float {
        return 0.22;
    }

    // Beyond this the field shows only the tail of what was typed.
    public static func FieldVisibleChars() -> Int32 {
        return 74;
    }

    // The phone caps nothing, but a terminal field shows one line, and a player who cannot
    // see what they typed cannot correct it.
    public static func FieldMaxLength() -> Int32 {
        return 320;
    }

    public static func ButtonWidth() -> Float {
        return 420.0;
    }

    public static func ButtonHeight() -> Float {
        return 92.0;
    }

    public static func ButtonOpacity() -> Float {
        return 0.13;
    }

    public static func ButtonTextInset() -> Float {
        return 28.0;
    }

    public static func ButtonTextDY() -> Float {
        return 22.0;
    }

    // Narrower than a destination button: a pair of full-width plates reads as navigation
    // rather than as a control.
    public static func SortButtonWidth() -> Float {
        return 320.0;
    }

    // Room for the word in front of them; the longest of the eight languages decides this.
    public static func SortLabelWidth() -> Float {
        return 260.0;
    }
}
