// The chat as drawn on a computer terminal -- everything except the registration of the
// site. The BrowserExtension shell (AiNpcTerminalSite.reds) is behind @if(ModuleExists);
// this file compiles unconditionally, so the whole terminal UI is type-checked on a machine
// without BrowserExtension. The seam is AiNpcTerminalHost: Navigate and ReleaseFocus.
//
// What the device UI forces, measured in game on 2026-08-21 when this was built from anchors
// and fit-to-content like the phone chat -- the scroll did not work, the wheel opened a
// contact, and the input band was drawn off the bottom of the screen:
//
// 1. A page states its own size. BEF's Fill anchor fills page_content, which is bigger than
//    the frame the player sees: 3140 x 1200 units.
//
// 2. An inkScrollArea scrolls a sized canvas. A fit-to-content panel declares no height, so
//    the wheel has nothing to move. The height here is the layout cursor's final value.
//
// 3. n"OnClick" is not n"OnRelease". OnRelease fires for the release of any pointer action,
//    the wheel included, so a handler on it both opened a contact and ate the scroll event.
//    Rows and buttons register OnClick and still check IsAction(n"click").
//
// 4. A page never redraws itself: it is built once per navigation, and typing is not
//    navigation. Anything that changes without a click updates a kept widget handle.
//
// 5. Nothing may be measured or scrolled during construction: BEF reparents our widget after
//    GetWebPage returns. See m_pendingScroll.
//
// 6. A callback carries no data. Which row was clicked travels on a controller attached to
//    the row's widget, read back through evt.GetCurrentTarget().GetController().
//
// 7. Nothing here may set AiNpcSystem.chatOpen: that rebinds every key to the phone chat, so
//    "c" would close the conversation and "r" reset it while the player types.
//
// 8. The keyboard is mounted, not toggled. The capture belongs to the page, so whatever ends
//    the page ends it; the single unmount point is ForgetPage. The player also has the two
//    exits every text field has -- Escape, and a click elsewhere -- which is why the root
//    canvas has a click handler and everything above it consumes its own click.

module AiNpc

// The two things the page cannot do for itself: go somewhere else, and hand the keyboard back
// to the game. ReleaseFocus is here rather than in the field because the host is the only
// object that knows what kind of screen this is -- on a browser, RequestSetFocus(null) on the
// device's own controller.
public abstract class AiNpcTerminalHost extends IScriptable {
    public func Navigate(address: String) -> Void {
    }

    public func ReleaseFocus() -> Void {
    }
}

// The index carrier for a clickable row: a callback carries no data.
public class AiNpcTerminalRowController extends inkLogicController {
    public let index: Int32;
}

// Read by the player in the browser's bar, so it carries the app's name and not the mod's.
// Nothing persists an address -- BEF registers the site on every device at load -- so this can
// be renamed without stranding a savegame.
func AiNpcTerminalAddressHome() -> String {
    return "NETdir://agentlink.nc";
}

func AiNpcTerminalAddressChat() -> String {
    return "NETdir://agentlink.nc/chat";
}

// Lines of at most `budget` characters, broken on spaces where possible. The line count is
// the only way to know a bubble's height when nothing measures text for us.
func AiNpcTerminalWrapText(text: String, budget: Int32) -> String {
    // Below eight characters a line holds one short word: every reply becomes a column and
    // the height computed from the line count is taller than the page. Unwrapped is the
    // lesser failure, and no caller comes near it -- bubbles ask 78, row previews 90.
    if budget < AiNpcTerminalMinWrapBudget() {
        return text;
    }

    // Paragraphs the model wrote are kept: the one piece of shape a reply carries.
    let paragraphs = StrSplit(text, "\n");
    let paragraphCount = ArraySize(paragraphs);
    let out: String = "";
    let p: Int32 = 0;

    while p < paragraphCount {
        let words = StrSplit(paragraphs[p], " ");
        let count = ArraySize(words);
        let line: String = "";
        let i: Int32 = 0;

        while i < count {
            let word = words[i];
            if Equals(StrLen(line), 0) {
                line = word;
            } else {
                if StrLen(line) + 1 + StrLen(word) <= budget {
                    line = line + " " + word;
                } else {
                    if Equals(StrLen(out), 0) {
                        out = line;
                    } else {
                        out = out + "\n" + line;
                    }
                    line = word;
                }
            }
            i += 1;
        }

        if Equals(StrLen(out), 0) {
            out = line;
        } else {
            out = out + "\n" + line;
        }
        p += 1;
    }
    return out;
}

// The shortest line worth wrapping to, stated once so the assertions can ask about the floor
// instead of tripping over it.
func AiNpcTerminalMinWrapBudget() -> Int32 {
    return 8;
}

// Counted rather than recomputed, so the height and the text cannot disagree.
func AiNpcTerminalCountLines(text: String) -> Int32 {
    let parts = StrSplit(text, "\n");
    let count = ArraySize(parts);
    if count < 1 {
        return 1;
    }
    return count;
}

// One line of a conversation, shortened for a contact row.
func AiNpcTerminalPreview(text: String, budget: Int32) -> String {
    let flat = AiNpcReplaceAll(text, "\n", " ");
    if StrLen(flat) <= budget {
        return flat;
    }
    return StrLeft(flat, budget - 3) + "...";
}

public class AiNpcTerminalChat extends AiNpcChatRenderer {

    private let m_host: ref<AiNpcTerminalHost>;

    // What is shown, what is typed, whether a generation is in flight, and every policy that
    // goes with them. This object holds widgets and decides nothing.
    private let m_session: ref<AiNpcChatSession>;

    // Survives navigation to the contact list and back, which is why it is here and not in
    // the page.
    private let m_contactId: String;

    // Kept between builds: the field owns the text the player typed (see its header).
    private let m_field: ref<AiNpcTerminalField>;

    // Cleared by ForgetPage, and every use is guarded: a reply can land after the player has
    // walked away from the computer.
    private let m_content: ref<inkCanvas>;
    private let m_scroll: ref<inkScrollController>;
    private let m_status: ref<inkText>;
    private let m_typing: ref<inkText>;
    private let m_sendFill: ref<inkRectangle>;

    // Where the next row or bubble goes, and therefore the content height. The cursor that
    // placed the last one cannot drift from what was drawn, because it is what drew it.
    private let m_cursorY: Float;

    // The contact ids of the rows drawn on the contact list, in order.
    private let m_rows: array<String>;

    // Here rather than in the page, so opening a conversation and coming back does not put
    // the list back the way the player did not want it. Not persisted: a view preference,
    // defaulting to what a messaging app opens on.
    private let m_order: AiNpcTerminalOrder;

    // Nothing may be scrolled during construction; see point 5 of the header.
    private let m_pendingScroll: Bool;


    public final func Attach(host: ref<AiNpcTerminalHost>) -> Void {
        this.m_host = host;
        if !IsDefined(this.m_field) {
            this.m_field = new AiNpcTerminalField();
            this.m_field.Setup(AiNpcTerminalPlaceholder());
        }
        // The session outlives the page, as the field does: navigating to the contact list
        // and back must not lose what the conversation was.
        if !IsDefined(this.m_session) {
            this.m_session = new AiNpcChatSession();
        }
        this.m_session.Attach(this);
        let registry = AiNpcChatSessionRegistry.Get();
        if IsDefined(registry) {
            registry.Register(this.m_session);
        }
    }

    public final func Detach() -> Void {
        let registry = AiNpcChatSessionRegistry.Get();
        if IsDefined(registry) {
            registry.Unregister(this.m_session);
        }
        if IsDefined(this.m_session) {
            this.m_session.Detach();
        }
        this.ForgetPage();
        this.m_host = null;
    }

    public final func GetSession() -> ref<AiNpcChatSession> {
        return this.m_session;
    }

    // Both halves of letting go: the field is what believes it is focused, the host is what
    // the game asked. Either left alone is a player who cannot move.
    private func ReleaseKeyboard() -> Void {
        if IsDefined(this.m_field) {
            this.m_field.ReleaseKeyboard();
        }
        if IsDefined(this.m_host) {
            this.m_host.ReleaseFocus();
        }
    }

    // Drops every widget handle, when the page goes away and at the start of every build: a
    // handle from the previous page paints a bubble into a tree nobody is looking at.
    private func ForgetPage() -> Void {
        // The keyboard first: a page going away must not leave the capture behind. One call
        // covers every route here -- another of our pages, and Detach, which is the browser
        // closing, the Esc menu, and the player walking away.
        this.ReleaseKeyboard();
        AiNpcCloseConversation(this.m_session);
        this.m_content = null;
        this.m_scroll = null;
        this.m_status = null;
        this.m_typing = null;
        this.m_sendFill = null;
        this.m_cursorY = 0.0;
        this.m_pendingScroll = false;
    }


    public final func BuildPage(address: String) -> ref<inkCompoundWidget> {
        this.ForgetPage();
        if Equals(address, AiNpcTerminalAddressChat()) {
            return this.BuildChatPage();
        }
        return this.BuildContactsPage();
    }

    private func Navigate(address: String) -> Void {
        if IsDefined(this.m_host) {
            this.m_host.Navigate(address);
        }
    }

    //
    // Coordinates are frame units, used as written: Scale() moves font sizes, not boxes.

    private func Label(parent: ref<inkCompoundWidget>, text: String, size: Int32,
                       colour: Color, x: Float, y: Float) -> ref<inkText> {
        let label = new inkText();
        label.SetText(text);
        label.SetFontFamily(AiNpcTerminalStyle.FontFamily());
        label.SetFontStyle(AiNpcTerminalStyle.FontStyleBody());
        label.SetFontSize(size);
        label.SetLetterCase(textLetterCase.OriginalCase);
        label.SetTintColor(colour);
        label.SetHAlign(inkEHorizontalAlign.Left);
        label.SetVAlign(inkEVerticalAlign.Top);
        label.SetAnchorPoint(new Vector2(0.0, 0.0));
        label.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        label.SetFitToContent(true);
        // Never interactive: a text widget over a plate takes the plate's pointer events and
        // the wheel events the scroll area needs.
        label.SetInteractive(false);
        label.Reparent(parent);
        return label;
    }

    private func Bar(parent: ref<inkCompoundWidget>, colour: Color, opacity: Float,
                     x: Float, y: Float, w: Float, h: Float) -> ref<inkRectangle> {
        let bar = new inkRectangle();
        bar.SetTintColor(colour);
        bar.SetOpacity(opacity);
        bar.SetSize(new Vector2(w, h));
        bar.SetHAlign(inkEHorizontalAlign.Left);
        bar.SetVAlign(inkEVerticalAlign.Top);
        bar.SetAnchorPoint(new Vector2(0.0, 0.0));
        bar.SetMargin(new inkMargin(x, y, 0.0, 0.0));
        bar.Reparent(parent);
        return bar;
    }

    // The edge is what makes it read as a surface: a 10% wash alone blends into the background.
    private func Plate(parent: ref<inkCompoundWidget>, colour: Color, opacity: Float,
                       x: Float, y: Float, w: Float, h: Float) -> ref<inkRectangle> {
        let fill = this.Bar(parent, colour, opacity, x, y, w, h);
        this.Bar(parent, colour, AiNpcTerminalStyle.EdgeOpacity(), x, y,
                 AiNpcTerminalStyle.EdgeWidth(), h);
        return fill;
    }

    // `index` rides on a controller, `callback` is a method of this object. OnClick, never
    // OnRelease.
    private func Button(parent: ref<inkCompoundWidget>, caption: String, colour: Color,
                        x: Float, y: Float, w: Float, callback: CName,
                        index: Int32) -> ref<inkRectangle> {
        let height: Float = AiNpcTerminalStyle.ButtonHeight();
        let plate = this.Plate(parent, colour, AiNpcTerminalStyle.ButtonOpacity(),
                               x, y, w, height);
        plate.SetInteractive(true);
        plate.RegisterToCallback(n"OnClick", this, callback);

        let controller = new AiNpcTerminalRowController();
        controller.index = index;
        plate.AttachController(controller);

        this.Label(parent, caption, AiNpcTerminalStyle.FsHeading(), colour,
                   x + AiNpcTerminalStyle.ButtonTextInset(),
                   y + AiNpcTerminalStyle.ButtonTextDY());
        return plate;
    }


    private func NewRoot() -> ref<inkCanvas> {
        let root = new inkCanvas();
        root.SetName(n"ainpc_page");
        // The frame, stated: BEF anchors this Fill afterwards, which is harmless once a size
        // exists.
        root.SetSize(new Vector2(AiNpcTerminalStyle.PageWidth(),
                                 AiNpcTerminalStyle.PageHeight()));
        root.SetInteractive(true);
        root.SetSupportFocus(true);
        // Clicking anywhere that is not the field stops typing. The root is the bottom of the
        // pile, so a click on empty space reaches it; everything clickable is above it and
        // consumes its own click, the field included.
        root.RegisterToCallback(n"OnClick", this, n"OnAiNpcTerminalBackdrop");
        return root;
    }

    private func Header(root: ref<inkCanvas>, title: String, subtitle: String) -> Void {
        let left: Float = AiNpcTerminalStyle.SideMargin();
        this.Label(root, title, AiNpcTerminalStyle.FsTitle(), AiNpcTerminalStyle.ColNpc(),
                   left, AiNpcTerminalStyle.TitleY());
        this.Label(root, subtitle, AiNpcTerminalStyle.FsSmall(), AiNpcTerminalStyle.ColDim(),
                   left, AiNpcTerminalStyle.SubtitleY());
        this.Bar(root, AiNpcTerminalStyle.ColNpc(), 0.35, 0.0,
                 AiNpcTerminalStyle.HeaderHeight() - 14.0,
                 AiNpcTerminalStyle.PageWidth(), 3.0);
    }

    // Wrapper, viewport, sized content canvas, and a bar pinned to the frame; shaped after
    // NCA_SiteWidgets.NCA_SiteScrollPage. `available` is what is left between the header and
    // the footer, so a page with an input band gets a shorter list rather than one that runs
    // under it.
    private func ScrollShell(root: ref<inkCanvas>, available: Float) -> Void {
        let top: Float = AiNpcTerminalStyle.HeaderHeight();

        let wrapper = new inkCanvas();
        wrapper.SetName(n"ainpc_scroll_wrapper");
        wrapper.SetSize(new Vector2(AiNpcTerminalStyle.PageWidth(), available));
        wrapper.SetHAlign(inkEHorizontalAlign.Left);
        wrapper.SetVAlign(inkEVerticalAlign.Top);
        wrapper.SetAnchorPoint(new Vector2(0.0, 0.0));
        wrapper.SetMargin(new inkMargin(0.0, top, 0.0, 0.0));
        // The wheel is delivered to the widget the controller is attached to, so this is
        // interactive even though nothing on it is clickable.
        wrapper.SetInteractive(true);
        // Being interactive, it is also what a click on the conversation reaches, above the
        // root. Same handler: clicking a bubble is clicking away from the field. Rows are
        // above this one and consume.
        wrapper.RegisterToCallback(n"OnClick", this, n"OnAiNpcTerminalBackdrop");

        let viewport = new inkScrollArea();
        viewport.SetName(n"ainpc_scroll");
        viewport.SetSize(new Vector2(AiNpcTerminalStyle.ViewportWidth(), available - 20.0));
        viewport.SetHAlign(inkEHorizontalAlign.Left);
        viewport.SetVAlign(inkEVerticalAlign.Top);
        viewport.SetAnchorPoint(new Vector2(0.0, 0.0));
        // The left margin of every page, applied once. Pages draw from x = 0.
        viewport.SetMargin(new inkMargin(AiNpcTerminalStyle.SideMargin(), 10.0, 0.0, 0.0));
        viewport.SetUseInternalMask(AiNpcTerminalStyle.UseInternalMask());
        viewport.SetFitToContentDirection(inkFitToContentDirection.Horizontal);
        viewport.SetConstrainContentPosition(true);
        viewport.SetInteractive(true);
        viewport.Reparent(wrapper);

        let content = new inkCanvas();
        content.SetName(n"ainpc_scroll_content");
        // Height 0 for now: SyncContentHeight states it from the layout cursor as rows and
        // bubbles are added.
        content.SetSize(new Vector2(AiNpcTerminalStyle.ViewportWidth(), 0.0));
        content.SetHAlign(inkEHorizontalAlign.Left);
        content.SetVAlign(inkEVerticalAlign.Top);
        content.SetAnchorPoint(new Vector2(0.0, 0.0));
        content.Reparent(viewport);
        this.m_content = content;
        this.m_cursorY = 0.0;

        let track = new inkCanvas();
        track.SetName(n"ainpc_scrollbar");
        track.SetSize(new Vector2(AiNpcTerminalStyle.ScrollBarWidth(), available - 60.0));
        track.SetHAlign(inkEHorizontalAlign.Left);
        track.SetVAlign(inkEVerticalAlign.Top);
        track.SetAnchorPoint(new Vector2(0.0, 0.0));
        track.SetMargin(new inkMargin(AiNpcTerminalStyle.ScrollBarX(),
                                      AiNpcTerminalStyle.ScrollBarY(), 0.0, 0.0));
        this.Bar(track, AiNpcTerminalStyle.ColDim(), AiNpcTerminalStyle.ScrollTrackOpacity(),
                 4.0, 0.0, 4.0, available - 60.0);

        let handle = new inkRectangle();
        handle.SetName(n"ainpc_scroll_handle");
        handle.SetSize(new Vector2(AiNpcTerminalStyle.ScrollBarWidth(),
                                   AiNpcTerminalStyle.ScrollHandleHeight()));
        handle.SetTintColor(AiNpcTerminalStyle.ColNpc());
        handle.SetOpacity(AiNpcTerminalStyle.ScrollHandleOpacity());
        handle.SetInteractive(true);
        handle.Reparent(track);
        track.Reparent(wrapper);

        let slider = new inkSliderController();
        slider.slidingAreaRef = inkWidgetRef.Create(track);
        slider.handleRef = inkWidgetRef.Create(handle);
        slider.direction = inkESliderDirection.Vertical;
        slider.autoSizeHandle = true;
        slider.minHandleSize = AiNpcTerminalStyle.ScrollHandleMinSize();
        slider.Setup(0.0, 1.0, 0.0);
        track.AttachController(slider);

        let scroll = new inkScrollController();
        scroll.ScrollArea = inkScrollAreaRef.Create(viewport);
        scroll.VerticalScrollBarRef = inkWidgetRef.Create(track);
        // Absent rather than inert when the page fits: a bar that cannot move says the page is
        // longer than it is.
        scroll.autoHideVertical = true;
        wrapper.AttachController(scroll);
        wrapper.Reparent(root);
        this.m_scroll = scroll;
    }

    // The only place the content height is stated. Called after every row, every bubble and
    // every runtime append.
    private func SyncContentHeight() -> Void {
        if !IsDefined(this.m_content) {
            return;
        }
        this.m_content.SetSize(new Vector2(AiNpcTerminalStyle.ViewportWidth(),
                                           this.m_cursorY
                                               + AiNpcTerminalStyle.BottomPadding()));
        if IsDefined(this.m_scroll) {
            this.m_scroll.UpdateScrollPositionFromScrollArea();
        }
    }


    private func BuildContactsPage() -> ref<inkCompoundWidget> {
        let root = this.NewRoot();
        this.Header(root, AiNpcTerminalSiteTitle(), AiNpcTerminalContactsSubtitle());
        this.SortControl(root);
        this.ScrollShell(root, AiNpcTerminalStyle.PageHeight()
                               - AiNpcTerminalStyle.HeaderHeight() - 40.0);

        ArrayClear(this.m_rows);

        // Three arrays built in one pass, so they cannot disagree about which index is whose.
        // The ordering is pure and lives in AiNpcTerminalSort, testable without a session.
        let ids: array<String>;
        let names: array<String>;
        let times: array<Int32>;

        let contacts = AiNpcGetActiveContactIds();
        let count = ArraySize(contacts);
        let i: Int32 = 0;
        while i < count {
            let contactId = contacts[i];
            // Asked here rather than trusted from the list: a provider can disappear
            // mid-session, and a row that opens a conversation the mod refuses to voice is a
            // dead end. Resolved once for both questions, since asking by id costs a registry
            // scan each, per contact, every time this page is drawn.
            let provider = AiNpcProviderFor(contactId);
            if AiNpcIsContactReachable(contactId, provider) {
                ArrayPush(ids, contactId);
                ArrayPush(names, AiNpcNameOfProvider(provider));
                ArrayPush(times, this.LastMessageTime(contactId));
            }
            i += 1;
        }

        let ordered = AiNpcTerminalOrderIds(ids, names, times, this.m_order);
        let orderedCount = ArraySize(ordered);
        let drawn: Int32 = 0;
        while drawn < orderedCount {
            this.BuildContactRow(ordered[drawn], drawn);
            ArrayPush(this.m_rows, ordered[drawn]);
            drawn += 1;
        }

        if Equals(drawn, 0) {
            this.Label(this.m_content, AiNpcTerminalNoContactsLabel(),
                       AiNpcTerminalStyle.FsBody(), AiNpcTerminalStyle.ColDim(), 0.0, 20.0);
            this.m_cursorY = 120.0;
        }

        this.SyncContentHeight();
        return root;
    }

    private func BuildContactRow(contactId: String, index: Int32) -> Void {
        let y: Float = this.m_cursorY;
        let width: Float = AiNpcTerminalStyle.ViewportWidth() - 40.0;

        let plate = this.Plate(this.m_content, AiNpcTerminalStyle.ColNpc(),
                               AiNpcTerminalStyle.RowOpacity(), 0.0, y, width,
                               AiNpcTerminalStyle.RowHeight());
        plate.SetInteractive(true);
        plate.RegisterToCallback(n"OnClick", this, n"OnAiNpcTerminalRow");

        let controller = new AiNpcTerminalRowController();
        controller.index = index;
        plate.AttachController(controller);

        this.Label(this.m_content, AiNpcGetCharacterName(contactId),
                   AiNpcTerminalStyle.FsHeading(), AiNpcTerminalStyle.ColNpc(),
                   AiNpcTerminalStyle.RowTextInset(), y + 16.0);
        this.Label(this.m_content, this.LastLine(contactId), AiNpcTerminalStyle.FsSmall(),
                   AiNpcTerminalStyle.ColDim(), AiNpcTerminalStyle.RowTextInset(), y + 74.0);

        this.m_cursorY += AiNpcTerminalStyle.RowHeight() + AiNpcTerminalStyle.RowGap();
    }

    // A pair rather than one toggling button: a toggle reading "RECENT" cannot say whether
    // that is the current order or the one a click would switch to. The active one is drawn in
    // the site colour and the other dimmed, as elsewhere on the page.
    private func SortControl(root: ref<inkCanvas>) -> Void {
        let left: Float = AiNpcTerminalStyle.SideMargin();
        let y: Float = AiNpcTerminalStyle.NavY();
        let width: Float = AiNpcTerminalStyle.SortButtonWidth();

        this.Label(root, AiNpcTerminalSortByLabel(), AiNpcTerminalStyle.FsSmall(),
                   AiNpcTerminalStyle.ColDim(), left,
                   y + AiNpcTerminalStyle.ButtonTextDY() + 8.0);

        let recentColour = AiNpcTerminalStyle.ColDim();
        let nameColour = AiNpcTerminalStyle.ColDim();
        if Equals(this.m_order, AiNpcTerminalOrder.Alphabetical) {
            nameColour = AiNpcTerminalStyle.ColNpc();
        } else {
            recentColour = AiNpcTerminalStyle.ColNpc();
        }

        let x: Float = left + AiNpcTerminalStyle.SortLabelWidth();
        this.Button(root, AiNpcTerminalSortByRecentLabel(), recentColour, x, y, width,
                    n"OnAiNpcTerminalSort", EnumInt(AiNpcTerminalOrder.Recent));
        this.Button(root, AiNpcTerminalSortByNameLabel(), nameColour,
                    x + width + 20.0, y, width, n"OnAiNpcTerminalSort",
                    EnumInt(AiNpcTerminalOrder.Alphabetical));
    }

    // Absolute in-game seconds, 0 for no answer -- an empty conversation, or one written
    // before messages carried a time. Scanned backwards for the last message that has one: a
    // conversation whose newest line predates the field would otherwise sort to the bottom.
    private func LastMessageTime(contactId: String) -> Int32 {
        let messages = AiNpcStoredMessages(contactId);
        let i: Int32 = ArraySize(messages) - 1;
        while i >= 0 {
            if AiNpcMessageHasTime(messages[i]) {
                return messages[i].gameTimeSeconds;
            }
            i -= 1;
        }
        return AiNpcTimeUnknown();
    }

    // The last thing said in a conversation, or the "nothing yet" line.
    private func LastLine(contactId: String) -> String {
        let stored = AiNpcHistoryWithoutLiveCall(AiNpcStoredMessages(contactId),
            AiNpcLiveCallSince(contactId));
        let messages = AiNpcHistoryForThread(stored);
        let count = ArraySize(messages);
        if count <= 0 {
            return AiNpcTerminalEmptyThreadLabel();
        }
        return AiNpcTerminalPreview(messages[count - 1].text,
                                    AiNpcTerminalStyle.RowPreviewChars());
    }


    private func BuildChatPage() -> ref<inkCompoundWidget> {
        let root = this.NewRoot();
        this.Header(root, AiNpcGetCharacterName(this.m_contactId),
                    AiNpcTerminalContactsSubtitle());
        this.Button(root, AiNpcTerminalBackLabel(), AiNpcTerminalStyle.ColDim(),
                    AiNpcTerminalStyle.PageWidth() - AiNpcTerminalStyle.SideMargin()
                        - AiNpcTerminalStyle.ButtonWidth(),
                    AiNpcTerminalStyle.NavY(), AiNpcTerminalStyle.ButtonWidth(),
                    n"OnAiNpcTerminalBack", -1);

        this.ScrollShell(root, AiNpcTerminalStyle.PageHeight()
                               - AiNpcTerminalStyle.HeaderHeight()
                               - AiNpcTerminalStyle.FooterHeight() - 40.0);
        this.BuildFooter(root);

        AiNpcOpenConversation(this.m_session, this.m_contactId);
        this.FillConversation();

        // Not scrolled here: the tree is not laid out yet.
        this.m_pendingScroll = true;
        return root;
    }

    private func BuildFooter(root: ref<inkCanvas>) -> Void {
        let bandY: Float = AiNpcTerminalStyle.PageHeight()
                           - AiNpcTerminalStyle.FooterHeight();
        let left: Float = AiNpcTerminalStyle.SideMargin();
        let fieldWidth: Float = AiNpcTerminalStyle.PageWidth() - left * 2.0
                                - AiNpcTerminalStyle.ButtonWidth() - 40.0;

        this.m_typing = this.Label(root, "", AiNpcTerminalStyle.FsSmall(),
                                   AiNpcTerminalStyle.ColNpc(), left, bandY - 44.0);
        this.m_status = this.Label(root, AiNpcTerminalHintLabel(),
                                   AiNpcTerminalStyle.FsSmall(), AiNpcTerminalStyle.ColDim(),
                                   left + 900.0, bandY - 44.0);

        this.m_field.Build(root, left, bandY + 12.0, fieldWidth,
                           AiNpcTerminalStyle.ColTyped());
        // After the field's own handler, on the same widget, so the field has recorded the
        // Enter by the time this reads its text. Two listeners on one widget.
        let box = this.m_field.GetRootWidget();
        if IsDefined(box) {
            box.RegisterToCallback(n"OnInputKey", this, n"OnAiNpcTerminalFieldKey");
        }

        this.m_sendFill = this.Button(root, AiNpcTerminalSendLabel(),
                                      AiNpcTerminalStyle.ColPlayer(),
                                      AiNpcTerminalStyle.PageWidth() - left
                                          - AiNpcTerminalStyle.ButtonWidth(),
                                      bandY + 18.0, AiNpcTerminalStyle.ButtonWidth(),
                                      n"OnAiNpcTerminalSend", -1);

        this.SyncBusyState();
    }

    // Fetching is this side's business -- a renderer may reach for a system, a session may not.
    // What to do with the history is the session's: the window, the system marker and the
    // split live there, so both surfaces get the same answer.
    private func FillConversation() -> Void {
        this.m_session.Fill(AiNpcStoredMessages(this.m_contactId));
    }


    // Sized from its own line count and placed at the cursor. `animate` is ignored: a page is
    // built in one pass, and a bubble that faded in would do so during a build nobody is
    // watching yet.
    public func AppendMessage(text: String, fromPlayer: Bool, animate: Bool) -> Void {
        if !IsDefined(this.m_content) {
            return;
        }

        let colour = AiNpcTerminalStyle.ColNpc();
        if fromPlayer {
            colour = AiNpcTerminalStyle.ColPlayer();
        }

        let wrapped = AiNpcTerminalWrapText(text, AiNpcTerminalStyle.BubbleWrapChars());
        let lines: Int32 = AiNpcTerminalCountLines(wrapped);

        let padding = AiNpcTerminalStyle.BubblePadding();
        let lineHeight: Float = Cast<Float>(AiNpcTerminalStyle.FsBody())
                                * AiNpcTerminalStyle.BubbleLineFactor();
        let height: Float = Cast<Float>(lines) * lineHeight + padding.top + padding.bottom;
        let width: Float = AiNpcTerminalStyle.BubbleWidth();

        // V on the right, the character on the left, as on the phone.
        let x: Float = 0.0;
        if fromPlayer {
            x = AiNpcTerminalStyle.ViewportWidth() - 40.0 - width;
            if x < 0.0 {
                x = 0.0;
            }
        }

        if AiNpcTerminalStyle.UseAtlasBubbles() {
            let background = new inkImage();
            background.SetName(n"ainpc_bubble_bg");
            background.SetAtlasResource(AiNpcTerminalStyle.BubbleAtlas());
            if fromPlayer {
                background.SetTexturePart(AiNpcTerminalStyle.BubbleBackgroundPartPlayer());
            } else {
                background.SetTexturePart(AiNpcTerminalStyle.BubbleBackgroundPartNpc());
            }
            background.SetNineSliceScale(true);
            background.SetTintColor(colour);
            background.SetOpacity(AiNpcTerminalStyle.BubbleBackgroundOpacity());
            background.SetSize(new Vector2(width, height));
            background.SetHAlign(inkEHorizontalAlign.Left);
            background.SetVAlign(inkEVerticalAlign.Top);
            background.SetAnchorPoint(new Vector2(0.0, 0.0));
            background.SetMargin(new inkMargin(x, this.m_cursorY, 0.0, 0.0));
            background.SetInteractive(false);
            background.Reparent(this.m_content);
        } else {
            let plate = this.Plate(this.m_content, colour,
                                   AiNpcTerminalStyle.BubbleBackgroundOpacity(),
                                   x, this.m_cursorY, width, height);
            plate.SetInteractive(false);
        }

        // A sibling of the plate rather than a child: one less compound widget per bubble, and
        // nothing stacked over the plate to take a pointer event.
        this.Label(this.m_content, wrapped, AiNpcTerminalStyle.FsBody(), colour,
                   x + padding.left, this.m_cursorY + padding.top);

        this.m_cursorY += height + AiNpcTerminalStyle.BubbleGap();
        this.SyncContentHeight();
    }


    // Stick to the bottom only if that is where the player already was: being yanked to the
    // end mid-read is worse than having to scroll down.
    public func IsAtBottom() -> Bool {
        if !IsDefined(this.m_scroll) {
            return true;
        }
        return this.m_scroll.position > 0.95;
    }

    public func ScrollToBottom() -> Void {
        if IsDefined(this.m_scroll) {
            this.m_scroll.UpdateScrollPositionFromScrollArea();
            this.m_scroll.SetScrollPosition(1.0);
        }
    }

    // The deferred initial scroll, called from every event that proves the page is live and
    // laid out -- never from the build, where the tree has no size yet.
    private func FlushPendingScroll() -> Void {
        if this.m_pendingScroll {
            this.m_pendingScroll = false;
            this.ScrollToBottom();
        }
    }


    private func SendTyped() -> Void {
        if !IsDefined(this.m_field) {
            return;
        }
        let text = this.m_field.GetText();
        let http = GetAiNpcHttpSystem();
        if !IsDefined(http) {
            return;
        }

        // Read once and passed down, as the phone does: the request and V's own line are one
        // exchange and must not land in two different threads.
        let contactId = this.m_session.GetShownContactId();
        if Equals(StrLen(contactId), 0) {
            return;
        }

        // The two refusals that carry a message belong to this surface: the session has no
        // status line to write into.
        if http.GetIsGenerating() {
            this.SetStatus(AiNpcTerminalBusyLabel());
            return;
        }
        if !AiNpcIsContactSupported(contactId) {
            this.SetStatus(AiNpcTerminalUnsupportedLabel());
            return;
        }

        // La meme sequence que le telephone, et c'est le canal qui la porte -- voir
        // AiNpcChannel.Send, ou l'ordre entre l'envoi et le depot est explique une fois.
        AiNpcLog(s"Terminal: sending to '\(contactId)'.");
        AiNpcChannelOf(AiNpcChannelId.Text).Send(this.m_session, text);

        this.m_field.Clear();
        this.SyncBusyState();
    }

    private func SetStatus(text: String) -> Void {
        if IsDefined(this.m_status) {
            this.m_status.SetText(text);
        }
    }

    // The session pushes the same answer through SetBusy when the lane publishes it; this is
    // for the moments the surface catches up on its own, such as a page built while a
    // generation is already in flight.
    private func SyncBusyState() -> Void {
        let http = GetAiNpcHttpSystem();
        this.SetBusy(IsDefined(http) && http.GetIsGenerating());
    }

    // Greys the field and the send plate while a reply is in flight. The phone does the same
    // through SetInputMode.
    public func SetBusy(busy: Bool) -> Void {
        if IsDefined(this.m_field) {
            this.m_field.SetDisabled(busy);
        }
        if IsDefined(this.m_sendFill) {
            if busy {
                this.m_sendFill.SetOpacity(AiNpcTerminalStyle.ButtonOpacity() * 0.4);
            } else {
                this.m_sendFill.SetOpacity(AiNpcTerminalStyle.ButtonOpacity());
            }
        }
        if busy {
            this.SetStatus(AiNpcTerminalBusyLabel());
        } else {
            this.SetStatus(AiNpcTerminalHintLabel());
        }
    }

    //
    // The questions only this surface can answer. Who a reply is for, whether it needs
    // splitting and whether the view follows it down are the session's.

    // A page is rebuilt rather than emptied in normal use, so this covers the one case that is
    // not a rebuild: the session refilling a page already on screen.
    public func Clear() -> Void {
        if IsDefined(this.m_content) {
            this.m_content.RemoveAllChildren();
        }
        this.m_cursorY = 0.0;
        this.m_pendingScroll = false;
    }

    public func SetTypingIndicator(value: Bool) -> Void {
        if !IsDefined(this.m_typing) {
            return;
        }
        if value {
            this.m_typing.SetText(AiNpcGetCharacterName(this.m_session.GetShownContactId())
                                  + AiNpcIsTypingLabel(AiNpcResolveLanguage()));
        } else {
            this.m_typing.SetText("");
        }
    }

    // The field is greyed by SetBusy, which the lane drives. What is left for the mode is the
    // status line: a surface with no key hints says what state it is in with words or not at
    // all.
    public func SetInputMode(mode: AiNpcInputMode) -> Void {
        if Equals(mode, AiNpcInputMode.Disabled) {
            this.SetStatus(AiNpcTerminalBusyLabel());
        } else {
            this.SetStatus(AiNpcTerminalHintLabel());
        }
    }

    // Characters, not units: nothing on this side can measure text.
    public func SplitBudget() -> Int32 {
        return AiNpcTerminalStyle.BubbleSplitChars();
    }

    // A page is built in one pass, so an unbounded thread would be an unbounded build.
    public func HistoryLimit() -> Int32 {
        return AiNpcTerminalStyle.MaxMessagesShown();
    }

    // A reply can land after the player has walked away from the computer.
    public func Alive() -> Bool {
        return IsDefined(this.m_content);
    }

    //
    // Every one starts with the same two lines. A pointer callback is delivered for actions
    // this widget never asked for, the wheel among them, and acting on those both opened a
    // contact while scrolling and swallowed the event the scroll area needed. IsAction
    // filters; Consume stops what is under us from also seeing a handled click.

    // The other half of clicking into the field. Not consumed: a click on empty space is
    // noticed rather than handled, and consuming it would take it from whatever is drawn under
    // our frame.
    protected cb func OnAiNpcTerminalBackdrop(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        this.ReleaseKeyboard();
        return false;
    }

    protected cb func OnAiNpcTerminalRow(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        evt.Consume();

        let controller = evt.GetCurrentTarget().GetController() as AiNpcTerminalRowController;
        if !IsDefined(controller) {
            return false;
        }
        let count = ArraySize(this.m_rows);
        if controller.index < 0 || controller.index >= count {
            return false;
        }
        this.m_contactId = this.m_rows[controller.index];
        AiNpcLog(s"Terminal: opening '\(this.m_contactId)'.");
        this.Navigate(AiNpcTerminalAddressChat());
        return true;
    }

    // Re-navigating to the same address redraws the list: BEF re-enters GetWebPage, and the
    // contact page has nothing to lose by being rebuilt -- no field, so no keyboard focus, and
    // no scroll position worth keeping when the order has just changed.
    protected cb func OnAiNpcTerminalSort(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        evt.Consume();

        let controller = evt.GetCurrentTarget().GetController() as AiNpcTerminalRowController;
        if !IsDefined(controller) {
            return false;
        }
        if Equals(controller.index, EnumInt(AiNpcTerminalOrder.Alphabetical)) {
            this.m_order = AiNpcTerminalOrder.Alphabetical;
        } else {
            this.m_order = AiNpcTerminalOrder.Recent;
        }
        this.Navigate(AiNpcTerminalAddressHome());
        return true;
    }

    protected cb func OnAiNpcTerminalBack(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        evt.Consume();
        this.Navigate(AiNpcTerminalAddressHome());
        return true;
    }

    protected cb func OnAiNpcTerminalSend(evt: ref<inkPointerEvent>) -> Bool {
        if !evt.IsAction(n"click") {
            return false;
        }
        evt.Consume();
        this.FlushPendingScroll();
        this.SendTyped();
        return true;
    }

    // The field assembles the text, this decides what Enter means. Registered on the field's
    // own widget, after the field's handler.
    protected cb func OnAiNpcTerminalFieldKey(evt: ref<inkKeyInputEvent>) -> Bool {
        if NotEquals(evt.GetAction(), EInputAction.IACT_Press) {
            return true;
        }
        this.FlushPendingScroll();
        if IsDefined(this.m_field) && this.m_field.TakeSubmitted() {
            this.SendTyped();
        }
        return true;
    }
}
