// Registering the chat as a website on every in-game computer.
//
// Everything BrowserExtension-shaped is in this file, and nothing else is. The chat itself is
// AiNpcTerminalChat, which compiles whether or not BrowserExtension is installed; this is the
// shell that hands it a page to draw into and a way to navigate. That split is what lets the
// terminal UI be type-checked and linted on a machine without the framework.
//
// EVERY DECLARATION CARRIES @if. REDscript compiles every mod in the game together, so an
// unconditional import of a module the player does not have fails EVERY redscript mod in that
// installation, not just this one. Without the framework this file contributes nothing.
//
// BEF wants one listener per BrowserGameController, built in OnInitialize and torn down in
// OnUninitialize, and asks it for a widget per address. That is also the natural place to
// register the chat as the mod's active view: it has exactly the lifetime of "a browser is on
// screen".
//
// The one hook that is not BEF's is BrowserController.LoadWebPage, the vanilla funnel every
// navigation goes through. It is the only place that knows the page on screen is being
// replaced by one that is NOT ours -- BEF only ever calls us for addresses under our own -- so
// without it the chat is never told it has left the screen and the keyboard capture it took
// stays behind. See AiNpcKeyboard.reds.

module AiNpc

@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.DataStructures.*
@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.Classes.*
@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.System.*

// The chat's way out to the browser. Two methods, and this class is the only thing in the
// whole terminal UI that needs a BrowserExtension type.
@if(ModuleExists("BrowserExtension.System"))
public class AiNpcTerminalBrowserHost extends AiNpcTerminalHost {

    private let m_controller: wref<BrowserGameController>;

    public final func Bind(controller: ref<BrowserGameController>) -> Void {
        this.m_controller = controller;
    }

    public func Navigate(address: String) -> Void {
        if IsDefined(this.m_controller) {
            this.m_controller.LoadPageByAddress(address);
        }
    }

    // Giving the keyboard back the way the game does, from the one object that can: the
    // device's game controller. Null is the vanilla form of "nothing is focused".
    public func ReleaseFocus() -> Void {
        if IsDefined(this.m_controller) {
            this.m_controller.RequestSetFocus(null);
        }
    }
}

@if(ModuleExists("BrowserExtension.System"))
public class AiNpcTerminalListener extends BrowserEventsListener {

    private let m_chat: ref<AiNpcTerminalChat>;
    private let m_host: ref<AiNpcTerminalBrowserHost>;

    public func Init(logic: ref<BrowserGameController>) {
        super.Init(logic);

        this.m_siteData.address = AiNpcTerminalAddressHome();
        this.m_siteData.shortName = AiNpcTerminalSiteShortName();
        // The app's own icon, from the one .archive this mod ships (src\\archive\\, built by
        // tools\\build-archive.ps1). The depot path carries the app's name, not the mod's:
        // "ai_npc" is a folder on a modder's disk and has no business anywhere near a Night
        // City desktop.
        this.m_siteData.iconAtlasPath = r"agentlink\\icons\\agentlink.inkatlas";
        this.m_siteData.iconTexturePart = n"agentlink";

        this.m_host = new AiNpcTerminalBrowserHost();
        this.m_host.Bind(logic);

        this.m_chat = new AiNpcTerminalChat();
        this.m_chat.Attach(this.m_host);

        AiNpcLog("Terminal site registered on this computer.");
    }

    public func Uninit() {
        // Before super.Uninit(), which unregisters us from BEF: the reply path must stop
        // finding this view at the same moment its widgets stop being on screen. The
        // registry clears by identity, so a listener built for the next page cannot be
        // unregistered by this one's teardown.
        if IsDefined(this.m_chat) {
            this.m_chat.Detach();
            this.m_chat = null;
        }
        this.m_host = null;
        super.Uninit();
    }

    public func GetWebPage(address: String) -> ref<inkCompoundWidget> {
        if !IsDefined(this.m_chat) {
            return null;
        }
        return this.m_chat.BuildPage(address);
    }
}

//
// The three hooks, verbatim from the framework's contract. The field is on the controller
// rather than on a singleton because a listener belongs to one computer: two devices are two
// listeners, and BEF matches pages to the device that asked.

@if(ModuleExists("BrowserExtension.System"))
@addField(BrowserGameController)
private let m_aiNpcTerminalListener: ref<AiNpcTerminalListener>;

@if(ModuleExists("BrowserExtension.System"))
@wrapMethod(BrowserGameController)
protected cb func OnInitialize() -> Bool {
    wrappedMethod();
    this.m_aiNpcTerminalListener = new AiNpcTerminalListener();
    this.m_aiNpcTerminalListener.Init(this);
}

@if(ModuleExists("BrowserExtension.System"))
@wrapMethod(BrowserGameController)
protected cb func OnUninitialize() -> Bool {
    wrappedMethod();
    if IsDefined(this.m_aiNpcTerminalListener) {
        this.m_aiNpcTerminalListener.Uninit();
    }
    this.m_aiNpcTerminalListener = null;
}

// The unmount for everything that is not us.
//
// Released before the page is loaded, not after: the next page may be one of ours and may
// claim the keyboard while it is built, and an unmount that ran afterwards would take that
// fresh claim away instead of the stale one. The registry releases by identity for the same
// reason.
@if(ModuleExists("BrowserExtension.System"))
@wrapMethod(BrowserController)
private final func LoadWebPage(const address: script_ref<String>) -> Void {
    AiNpcReleaseKeyboardCapture();
    wrappedMethod(address);
}
