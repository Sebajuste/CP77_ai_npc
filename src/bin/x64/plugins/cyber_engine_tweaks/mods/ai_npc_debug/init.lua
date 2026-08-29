-- ai_npc_debug -- a CET window onto the mod: what it is configured to talk to, and what it
-- has said.
--
-- Installed by the ai_npc archive, at the path CET reads. It lives under src\ rather than
-- tools\ because the pipeline is package -> install in Vortex: a file outside src\ is not part
-- of the mod and never reaches the game. Where CET is not installed this folder is simply
-- never read.
--
-- The Journal tab is shaped around one task: a savegame has been lost, play resumes from an
-- earlier one, and the conversations have to come back. Three questions in a row --
--
--   which branch was the lost playthrough?      -> the table, and the preview under it
--   how far into it do I want to go back?       -> the sequence field, prefilled with the head
--   put it on the game I am playing now.        -> Restore, with the pointer it replaces shown
--
-- which is why it replaces typing a pointer into a console: the pointer is what you are
-- trying to FIND, and a text box cannot show you the conversation that tells you which it is.
--
-- A redscript class inside a module is reached from CET by its module-qualified name. Nothing
-- here is Lua-side state about the journal: every value on screen is read back from the store.
--
-- The Setup tab is the half a new player meets first: what would otherwise be alt-tabbing out
-- of the game to paste a key into a JSON file under r6\storages\ and restarting. The settings
-- service re-reads its file (AiNpcStorageService.ReloadSettings), so nothing here needs a
-- restart to take effect.

local STORE = "AiNpc.AiNpcConversationStore"
local SETUP = "AiNpc.AiNpcSetupSystem"

local ui = {
    windowOpen = true,
    overlayOpen = false,
    branches = {},          -- rows read from the store
    selected = nil,         -- index into ui.branches
    seqText = "",           -- the sequence number to restore at
    detail = "",            -- the selected branch, replayed and described
    status = "",            -- what this session is on
    output = "",            -- the last thing that happened
    previous = nil,         -- the pointer we were on before a restore, for going back
    armedFor = nil,         -- the pointer whose restore has been armed by a first click
    armedFrom = nil,        -- the pointer it would replace, read when the restore was armed
    loaded = false,
}

local function system(name)
    local container = Game.GetScriptableSystemsContainer()
    if not container then
        return nil
    end
    return container:Get(name)
end

-- Every redscript call goes through here. pcall because this window's whole job is to be
-- usable when something is already wrong: a raw error inside onDraw takes the overlay down
-- with it, and the broken state is exactly what is worth reading. Failures come back as text,
-- which is also how the systems themselves report refusals -- so the output pane never has to
-- distinguish.
--
-- Varargs rather than one optional argument: SetSetting takes a key AND a value, and the
-- alternative was a "key=value" string that both sides would have to agree how to split -- on
-- values that are urls and API keys, which are exactly the strings that contain separators.
local function callOn(name, method, ...)
    local s = system(name)
    if not s then
        return nil, "No session: load a savegame first (these systems are per-playthrough)."
    end

    local args = table.pack(...)
    local ok, result = pcall(function()
        return s[method](s, table.unpack(args, 1, args.n))
    end)

    if not ok then
        return nil, "call failed: " .. tostring(result)
    end
    return tostring(result), nil
end

local function call(method, argument)
    if argument ~= nil then
        return callOn(STORE, method, argument)
    end
    return callOn(STORE, method)
end

local function callSetup(method, ...)
    return callOn(SETUP, method, ...)
end

local function split(text, sep)
    local out = {}
    for piece in string.gmatch(text .. sep, "([^" .. sep .. "]*)" .. sep) do
        table.insert(out, piece)
    end
    return out
end

-- id \t parent \t head \t lines \t present \t current
local function parseRows(text)
    local rows = {}
    for _, line in ipairs(split(text, "\n")) do
        if line ~= "" then
            local cell = split(line, "\t")
            if #cell >= 6 then
                table.insert(rows, {
                    id = cell[1],
                    parent = cell[2],
                    head = tonumber(cell[3]) or 0,
                    lines = tonumber(cell[4]) or 0,
                    present = cell[5] == "1",
                    current = cell[6] == "1",
                })
            end
        end
    end
    return rows
end

local function refresh()
    ui.loaded = true
    ui.selected = nil
    ui.detail = ""
    ui.armedFor = nil

    local status, err = call("DescribeState")
    ui.status = status or err

    local rows
    rows, err = call("JournalBranchRows")
    if not rows then
        ui.branches = {}
        ui.output = err
        return
    end
    ui.branches = parseRows(rows)
    if #ui.branches == 0 then
        ui.output = "No branch registered yet."
    end
end

-- Selecting a row is what costs a replay, and only for that row: the table itself is read
-- without parsing a single conversation.
--
-- Idempotent on purpose. ImGui.Selectable is documented as returning true on the click, but
-- a binding that returns "is selected" instead would call this on every frame -- which would
-- replay the branch sixty times a second and reset anything the frame before had set. The
-- guard costs one comparison and makes that difference unobservable.
local function selectRow(i)
    if ui.selected == i then
        return
    end
    ui.selected = i
    ui.armedFor = nil
    local row = ui.branches[i]
    ui.seqText = tostring(row.head)
    if not row.present then
        ui.detail = "b" .. row.id .. " has been purged from disk; nothing to restore from it."
        return
    end
    local detail, err = call("DescribeBranchDetail", "b" .. row.id .. ":" .. row.head)
    ui.detail = detail or err
end

local function preview()
    local row = ui.branches[ui.selected]
    if not row or not row.present then
        return
    end
    local detail, err = call("DescribeBranchDetail", "b" .. row.id .. ":" .. (tonumber(ui.seqText) or row.head))
    ui.detail = detail or err
end

local function restore(pointer)
    -- Read the pointer we are leaving BEFORE the import replaces it: it is the only way back
    -- to the history this savegame had, and after the fork nothing else remembers it.
    local before = call("GetPointer")
    local result, err = call("ImportFromPointer", pointer)
    ui.output = result or err
    ui.armedFor = nil
    if result and before and before ~= "" and string.find(result, "imported") then
        ui.previous = before
    end
    local status = call("DescribeState")
    if status then
        ui.status = status
    end
    local rows = call("JournalBranchRows")
    if rows then
        ui.branches = parseRows(rows)
    end
end

-- ---------------------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------------------

-- The provider buttons are not a list in this file: a window whose job is to render what
-- redscript describes has no business holding a second, hand-maintained copy of the same
-- list, and that copy went stale the moment the mod gained the CLI lanes.
--
-- The names come from DescribeProviders(), whose every line starts with the provider name.
-- FALLBACK_PROVIDERS is what is drawn if that call fails outright: one button, the lane that
-- needs no program installed, so a player is never left with no way back.
local FALLBACK_PROVIDERS = { "OpenRouter" }

local function parseProviderNames(text)
    local names = {}
    for _, line in ipairs(split(text, "\n")) do
        local name = string.match(line, "^(%S+)")
        if name then
            table.insert(names, name)
        end
    end
    if #names == 0 then
        return FALLBACK_PROVIDERS
    end
    return names
end

-- Looked up once, defensively: an older CET has no ImGuiInputTextFlags table, and reaching
-- into a nil global inside onDraw would take the whole overlay down every frame. Without the
-- flag the key is simply visible while it is typed, which is a cosmetic loss, not a broken
-- window.
local PASSWORD_FLAG = 0
do
    local ok, flag = pcall(function() return ImGuiInputTextFlags.Password end)
    if ok and flag then
        PASSWORD_FLAG = flag
    end
end

local setup = {
    loaded = false,
    status = "",            -- DescribeSetup, verbatim
    providers = "",         -- DescribeProviders, verbatim
    providerNames = {},     -- the buttons, read out of that same text
    fields = {},            -- the current provider's editable settings
    output = "",            -- the last thing that happened
    test = "",              -- the last test result
    testing = false,        -- whether a request is in flight, so we only poll while it is
    showKeys = false,
}

-- key \t label \t value \t secret
local function parseFields(text)
    local fields = {}
    for _, line in ipairs(split(text, "\n")) do
        if line ~= "" then
            local cell = split(line, "\t")
            if #cell >= 4 then
                table.insert(fields, {
                    key = cell[1],
                    label = cell[2],
                    shown = cell[3],      -- what is stored now; masked when secret
                    secret = cell[4] == "1",
                    text = "",            -- what the player is typing
                })
            end
        end
    end
    return fields
end

local function setupRefresh()
    setup.loaded = true

    local status, err = callSetup("DescribeSetup")
    setup.status = status or err

    if setup.providers == "" then
        local providers = callSetup("DescribeProviders")
        setup.providers = providers or ""
        setup.providerNames = parseProviderNames(setup.providers)
    end

    local rows
    rows, err = callSetup("EditableRows")
    if not rows then
        setup.fields = {}
        setup.output = err
        return
    end

    -- The typed-but-unsaved text is deliberately NOT carried across a refresh of the field
    -- list: a refresh happens after a save, after a provider switch, or on request, and in
    -- all three the box should show the state of the world rather than a leftover draft.
    -- Non-secret fields are prefilled with what is stored, so editing a model id means
    -- correcting a word rather than retyping it; a secret box starts empty, because the only
    -- thing we could prefill it with is a mask, and saving that mask would destroy the key.
    setup.fields = parseFields(rows)
    for _, f in ipairs(setup.fields) do
        if not f.secret then
            f.text = f.shown
        end
    end
end

local function setupTest()
    local text, err = callSetup("StartTest")
    setup.test = text or err
    setup.testing = text ~= nil and string.find(text, "^Testing") ~= nil
end

-- Polled from onDraw, and only while a request is actually in flight. The result lands in a
-- redscript field from an HTTP callback, so there is nothing to wait on from Lua: the window
-- simply asks again next frame until the answer stops being "Testing".
local function setupPoll()
    if not setup.testing then
        return
    end
    local text = callSetup("DescribeTest")
    if text then
        setup.test = text
        if string.find(text, "^Testing") == nil then
            setup.testing = false
            -- The status block quotes the credential state, and a test that just failed on a
            -- revoked key should not sit above a line still calling the setup "configured".
            local status = callSetup("DescribeSetup")
            if status then
                setup.status = status
            end
        end
    end
end

local function drawSetup()
    if not setup.loaded then
        setupRefresh()
    end

    if ImGui.Button("Refresh") then
        setupRefresh()
    end
    ImGui.SameLine()
    if ImGui.Button("Re-read settings.json") then
        local text, err = callSetup("ReloadSettings")
        setup.output = text or err
        setupRefresh()
    end

    ImGui.Separator()
    ImGui.Text(setup.status)
    ImGui.Separator()

    ImGui.Text("Provider")
    for i, name in ipairs(setup.providerNames) do
        if i > 1 then
            ImGui.SameLine()
        end
        if ImGui.Button(name) then
            local text, err = callSetup("SetProvider", name)
            setup.output = text or err
            setup.test = ""
            setup.testing = false
            setupRefresh()
        end
    end
    if ImGui.CollapsingHeader("Which one should I pick?") then
        ImGui.TextWrapped(setup.providers)
    end

    if #setup.fields > 0 then
        ImGui.Separator()
        for i, f in ipairs(setup.fields) do
            local flags = 0
            if f.secret and not setup.showKeys then
                flags = PASSWORD_FLAG
            end
            ImGui.PushItemWidth(360)
            f.text = ImGui.InputText(f.label .. "##field" .. i, f.text, 512, flags)
            ImGui.PopItemWidth()
            ImGui.SameLine()
            if ImGui.Button("Save##save" .. i) then
                local text, err = callSetup("SetSetting", f.key, f.text)
                setup.output = text or err
                setup.test = ""
                setup.testing = false
                setupRefresh()
            end
            ImGui.TextWrapped("    " .. f.key .. " is currently " .. f.shown)
        end

        -- A button rather than a checkbox, for the reason written out at the restore
        -- confirmation below: Button's return value means "clicked this frame" and nothing
        -- else, which is the only semantic this file relies on.
        if ImGui.Button(setup.showKeys and "Hide typed key" or "Show typed key") then
            setup.showKeys = not setup.showKeys
        end
    end

    ImGui.Separator()
    if setup.testing then
        ImGui.Text("Testing...")
    else
        if ImGui.Button("Test connection") then
            setupTest()
        end
    end
    if setup.test ~= "" then
        ImGui.TextWrapped(setup.test)
    end

    if setup.output ~= "" then
        ImGui.Separator()
        ImGui.TextWrapped(setup.output)
    end
end

-- Console use, for when the window is not the fastest way there:
--   print(GetMod("ai_npc_debug").setup())
--   print(GetMod("ai_npc_debug").provider("OpenRouter"))
--   print(GetMod("ai_npc_debug").set("openRouterApiKey", "sk-or-v1-..."))
--   print(GetMod("ai_npc_debug").test())
--   print(GetMod("ai_npc_debug").status())
--   print(GetMod("ai_npc_debug").branches())
--   print(GetMod("ai_npc_debug").restore("b14:467"))
--
-- The console is also the one place a key is typed in the clear and stays in the CET
-- scrollback. The window's box masks it and the redscript side never echoes it back in
-- full -- worth preferring on a machine that records footage.
local api = {}

function api.status()
    local text, err = call("DescribeState")
    return text or err
end

function api.branches()
    local text, err = call("DescribeBranches")
    return text or err
end

function api.detail(pointer)
    local text, err = call("DescribeBranchDetail", pointer)
    return text or err
end

function api.restore(pointer)
    restore(pointer)
    return ui.output
end

function api.setup()
    local text, err = callSetup("DescribeSetup")
    return text or err
end

-- The window is rebuilt from redscript after any of these, rather than patched: the provider
-- decides which fields exist, and a console call is exactly the case where the window is not
-- looking.
function api.provider(name)
    local text, err = callSetup("SetProvider", name)
    setup.loaded = false
    return text or err
end

function api.set(key, value)
    local text, err = callSetup("SetSetting", key, value)
    setup.loaded = false
    return text or err
end

-- Returns immediately: the answer arrives in a callback. Call setup() again, or read the
-- Setup tab, to see what the provider said.
function api.test()
    setupTest()
    setup.loaded = false
    return setup.test
end

registerForEvent("onOverlayOpen", function()
    ui.overlayOpen = true
    if not ui.loaded then
        refresh()
    end
end)

registerForEvent("onOverlayClose", function()
    ui.overlayOpen = false
end)

registerHotkey("ai_npc_journal", "AI NPC: toggle the setup / journal window", function()
    ui.windowOpen = not ui.windowOpen
end)

registerForEvent("onDraw", function()
    if not ui.overlayOpen or not ui.windowOpen then
        return
    end

    ImGui.SetNextWindowSize(680, 560, ImGuiCond.FirstUseEver)
    if ImGui.Begin("AI NPC") then
        -- Cheap and conditional: it returns immediately unless a test is in flight.
        -- Placed above the tab bar so a test keeps resolving while the Journal tab is
        -- the one on screen -- the request is already sent, and losing its answer to a
        -- click would be indistinguishable from the provider never replying.
        setupPoll()

        if ImGui.BeginTabBar("aiNpcTabs") then
            if ImGui.BeginTabItem("Setup") then
                drawSetup()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Journal") then
                if ImGui.Button("Refresh") then
                    refresh()
                end
                ImGui.SameLine()
                ImGui.TextWrapped(ui.status)
                ImGui.Separator()

                -- 1. Which branch was the lost playthrough?
                ImGui.Text("Branches on disk")
                ImGui.BeginChild("branches", 0, 150)
                for i, row in ipairs(ui.branches) do
                    local label = "b" .. row.id .. "   from " .. row.parent .. "   head " .. row.head
                    if not row.present then
                        label = label .. "   (purged)"
                    end
                    if row.current then
                        label = label .. "   <- this savegame"
                    end
                    if ImGui.Selectable(label .. "##row" .. i, ui.selected == i) then
                        selectRow(i)
                    end
                end
                ImGui.EndChild()

                if ui.selected then
                    local row = ui.branches[ui.selected]

                    -- 2. How far into it?
                    ImGui.PushItemWidth(120)
                    ui.seqText = ImGui.InputText("up to sequence", ui.seqText, 12)
                    ImGui.PopItemWidth()
                    ImGui.SameLine()
                    if ImGui.Button("Preview") then
                        preview()
                    end
                    ImGui.SameLine()
                    if ImGui.Button("Head (" .. row.head .. ")") then
                        ui.seqText = tostring(row.head)
                        preview()
                    end

                    ImGui.BeginChild("detail", 0, 190)
                    ImGui.TextWrapped(ui.detail)
                    ImGui.EndChild()

                    -- 3. Put it on the game being played now. Two steps, because this replaces what
                    -- the current savegame holds -- and the line above the button says what that is.
                    local pointer = "b" .. row.id .. ":" .. (tonumber(ui.seqText) or row.head)
                    if row.present and not row.current then
                        -- Two buttons rather than a checkbox and a button: a checkbox here kept
                        -- clearing itself between frames, and both plausible causes are coin
                        -- tosses -- whether ImGui.Checkbox's first return value is the new state
                        -- or the "changed" flag, and whether Selectable fires once or every
                        -- frame. A Button returns true on the click and on no other frame.
                        --
                        -- Arming is per pointer, so changing branch or sequence disarms by
                        -- itself, with nothing to reset.
                        if ui.armedFor ~= pointer then
                            if ImGui.Button("Restore " .. pointer .. " into this savegame...") then
                                ui.armedFor = pointer
                                -- Read once, on the click. The confirmation names the pointer being
                                -- replaced, and asking the store for it on every frame would be an
                                -- RTTI call per frame to render a line that cannot change while the
                                -- confirmation is up.
                                ui.armedFrom = call("GetPointer") or "?"
                            end
                        else
                            ImGui.TextWrapped("This replaces what this savegame currently holds (" ..
                                (ui.armedFrom or "?") .. ") with " .. pointer ..
                                ". Nothing is overwritten on disk: the savegame forks onto a branch of its own, " ..
                                "and Undo will offer the pointer you are leaving.")
                            if ImGui.Button("Confirm restore") then
                                restore(pointer)
                            end
                            ImGui.SameLine()
                            if ImGui.Button("Cancel") then
                                ui.armedFor = nil
                            end
                            ImGui.TextWrapped("Close the phone first: the import refuses while a conversation is on screen.")
                        end
                    elseif row.current then
                        ImGui.TextWrapped("This is the branch the savegame is already on.")
                    end
                end

                if ui.previous then
                    ImGui.Separator()
                    if ImGui.Button("Undo -- go back to " .. ui.previous) then
                        restore(ui.previous)
                    end
                end

                if ui.output ~= "" then
                    ImGui.Separator()
                    ImGui.TextWrapped(ui.output)
                end
                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        end
    end
    ImGui.End()
end)

return api
