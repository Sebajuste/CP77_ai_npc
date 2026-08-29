# Offline static checks on the ai_npc sources. Pure text analysis: no game, no compiler,
# runs in under a second. Covers the failure classes redscript cannot catch, because they
# are agreements between a prompt string and the code that parses its output, or between
# an enum and the settings UI that exposes it.
#
# Usage: powershell -File tools\lint.ps1

$ErrorActionPreference = "Stop"

$root   = Resolve-Path "$PSScriptRoot\.."
$modSrc = Join-Path $root "src\r6\scripts\ai_npc"
# Every subfolder is included deliberately: every rule below searches the concatenation of
# these files, and a file that is not in it is code no rule can see.
#
# api\ was missing until 2026-08-28, and the omission cost exactly what it looks like it would.
# The public surface was the one place nothing checked, so it accumulated the things the rules
# forbid everywhere else -- a raw conversation store handle in AiNpcApi, a reach for the
# speaking lane in AiNpcClient -- and it did so in the folder whose whole claim is that it
# delegates in one line. A rule is only as wide as its file list.
$files  = @(Get-ChildItem (Join-Path $modSrc "*.reds")) +
          @(Get-ChildItem (Join-Path $modSrc "cast\*.reds")) +
          @(Get-ChildItem (Join-Path $modSrc "api\*.reds")) +
          @(Get-ChildItem (Join-Path $modSrc "tests\*.reds"))

# Plusieurs regles admettent les assertions la ou elles refusent tout le reste : un test
# nomme ce qu'il verifie, c'est son travail. Elles vivaient dans un fichier, elles vivent
# dans un dossier -- la question se pose une fois ici, et pas dans six listes de noms.
function Test-IsSelfTest($f) { return (Split-Path (Split-Path $f.FullName -Parent) -Leaf) -eq "tests" }

# Drops whole-line // comments. Deliberately does not touch trailing comments, so that
# URLs inside string literals ("https://...") survive intact.
function Read-Code([string]$path) {
    $lines = [System.IO.File]::ReadAllLines($path) | Where-Object { $_.TrimStart() -notmatch '^//' }
    return ($lines -join "`n")
}

# Every source file's code, concatenated.
#
# Checks below search THIS rather than a named file. A rule pinned to "AiNpcUtilities.reds"
# does not fail when the function it checks moves to another file -- it stops finding anything
# and passes, which is the worst of both. A check that cannot say "not found" is not a check.
function Read-AllCode {
    $parts = @()
    foreach ($f in $files) { $parts += (Read-Code $f.FullName) }
    return ($parts -join "`n")
}
$allText = Read-AllCode

$script:failures = 0
function Report-Fail([string]$check, [string]$detail) {
    Write-Output "FAIL  $check"
    $detail -split "`n" | ForEach-Object { Write-Output "        $_" }
    $script:failures++
}
function Report-Pass([string]$check) { Write-Output "ok    $check" }

# --- 1. No credentials in source -------------------------------------------------------
$leaks = $files | Select-String -Pattern 'sk-proj-|sk-or-v1-|"[0-9a-f]{32,}"'
if ($leaks) {
    Report-Fail "no credentials in source" (($leaks | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join "`n")
} else {
    Report-Pass "no credentials in source"
}

# --- 2. No duplicate top-level declarations --------------------------------------------
# One name, one declaration, across the whole module.
#
# A repeated name is NOT a compile error: redscript compiles the tree with zero errors and
# zero warnings, and the file loaded last simply wins -- so which copy is live depends on load
# order. Measured against a stale copy of AiNpcPhoneContacts.reds left in the game folder,
# redeclaring four free functions the live copy also declared. The blast radius is this module
# alone, since ai_npc's declarations live in `module AiNpc`.
#
# The lookbehind skips a declaration whose line directly above is an @if(...): conditional
# compilation declares the SAME name twice on purpose -- once per build shape, and exactly one
# of the two ever reaches the compiler (AiNpcSelfTest.reds, AiNpcTerminalSite.reds).
$decls = @()
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    foreach ($m in [regex]::Matches($text, '(?m)(?<!@if\([^\r\n]*\)\r?\n)^(?:public |private |protected )?(?:static )?(?:class|enum|func) ([A-Za-z_]\w*)')) {
        $decls += $m.Groups[1].Value
    }
}
$dupes = $decls | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
if ($dupes) {
    Report-Fail "no duplicate top-level declarations" ($dupes -join ", ")
} else {
    Report-Pass "no duplicate top-level declarations"
}

# --- 3. Every action tag written anywhere matches a declared command -------------------
# The prompt teaches the model a command syntax and the dispatcher matches it literally, so a
# stray space or a renamed tag silently disables the feature with no runtime error.
#
# Since the action lane was unified there is only one place a command can come from: a
# declaration. AddAction carries the pattern, a character sheet's AiNpcAction carries a plain
# tag, and the built-in transfer declares its own. The block the model reads is RENDERED from
# those patterns, so a hard-coded tag in prompt text is now always a mistake -- it is either a
# command nobody implements, or a second spelling of one that exists.
$declared = @()
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    foreach ($m in [regex]::Matches($text, 'AiNpcAction\(\s*"(\[ACTION[^"]*\])"')) {
        $declared += $m.Groups[1].Value
    }
    foreach ($m in [regex]::Matches($text, '(?:AddAction|RegisterAction)\([^"]*"(\[ACTION[^"]*\])"')) {
        $declared += $m.Groups[1].Value
    }
    foreach ($m in [regex]::Matches($text, 'AiNpcTransferPattern\(\)\s*->\s*String\s*\{\s*return\s*"(\[ACTION[^"]*)"')) {
        $declared += $m.Groups[1].Value
    }
}
if (-not $declared) {
    Report-Fail "action tags match a declared command" `
        "no command declaration found - AddAction or AiNpcTransferPattern moved or was inlined"
}

# A pattern claims by its head: the literal run before the first {slot}.
$heads = @()
foreach ($pattern in ($declared | Sort-Object -Unique)) {
    $brace = $pattern.IndexOf('{')
    if ($brace -lt 0) { $heads += $pattern } else { $heads += $pattern.Substring(0, $brace) }
}

$advertised = @()
foreach ($f in $files) {
    # The lane itself is not prompt text. These files own the SHAPE of a tag, so "[ACTION:"
    # appears in them as a thing being parsed or tested, never as something a model is told to
    # emit. AiNpcConfig.reds is the loader: every tag it names is either a shape in an error
    # message or a line of characters.example.json, written to disk for a person to read.
    if ($f.Name -in @("AiNpcActionTag.reds", "AiNpcActionPattern.reds", "AiNpcActionTable.reds",
                      "AiNpcActionRegistry.reds", "AiNpcActionDispatch.reds", "AiNpcActionPrompt.reds",
                      "AiNpcTransferHandler.reds", "AiNpcDataAction.reds", "AiNpcConfig.reds",
                      "AiNpcActionHandler.reds", "AiNpcClient.reds",
                      "AiNpcExtension.reds", "AiNpcContactTags.reds")) { continue }
    if (Test-IsSelfTest $f) { continue }
    $text = Read-Code $f.FullName
    foreach ($m in [regex]::Matches($text, '\[ACTION\s*:[^\]]*\]')) {
        $advertised += $m.Value
    }
}

$orphans = $advertised | Sort-Object -Unique | Where-Object {
    $tag = $_
    -not ($heads | Where-Object { $tag.StartsWith($_) })
}
if ($orphans) {
    Report-Fail "action tags match a declared command" `
        (("declared heads: " + ($heads -join ", ")),
         ("matching nothing: " + ($orphans -join ", ")) -join "`n")
} else {
    Report-Pass "action tags match a declared command ($($heads.Count) head(s) declared)"
}

# --- 4. Every enum surfaced in Mod Settings exposes all of its members ----------------
# A member with no displayValue shows up blank in the settings menu, and a member added
# without one is invisible -- which is how the LocalBridge provider could have been
# missed. Checked for every enum, not just the character list.
$settingsText = Read-Code (Join-Path $modSrc "AiNpcModSettings.reds")

$enumGaps = @()
$enumsChecked = 0
foreach ($enumMatch in [regex]::Matches($allText, '(?s)enum (\w+)\s*\{(.*?)\}')) {
    $enumName = $enumMatch.Groups[1].Value
    $members = @()
    foreach ($m in [regex]::Matches($enumMatch.Groups[2].Value, '(?m)^\s*([A-Za-z_]\w*)\s*=')) {
        $members += $m.Groups[1].Value
    }
    if ($members.Count -eq 0) { continue }

    # Only enums the settings menu actually surfaces are in scope.
    $exposed = $members | Where-Object { $settingsText -match [regex]::Escape("ModSettings.displayValues.$_") }
    if ($exposed.Count -eq 0) { continue }

    $enumsChecked++
    foreach ($member in $members) {
        if ($settingsText -notmatch [regex]::Escape("ModSettings.displayValues.$member")) {
            $enumGaps += "$enumName.$member"
        }
    }
}
if ($enumsChecked -eq 0) {
    # Nothing matched at all: the enums moved somewhere this rule no longer reads, or the
    # displayValues annotations left AiNpcModSettings.reds. Either way the check is inert, and
    # an inert check must fail rather than report a clean run over nothing. It has fired once,
    # on the pass that moved the fields off AiNpcSystem -- which is the whole point of it.
    Report-Fail "every Mod Settings enum exposes all its members" "no settings-backed enum found - the rule is reading nothing"
} elseif ($enumGaps) {
    Report-Fail "every Mod Settings enum exposes all its members" ($enumGaps -join ", ")
} else {
    Report-Pass "every Mod Settings enum exposes all its members ($enumsChecked enum(s))"
}

# --- 4b. The memory slider advertises the range the code enforces ----------------------
# The menu's min/max are annotation STRINGS and the clamp is redscript; nothing makes them
# agree. Drift is silent and one-directional in the worst way: a menu offering 4 while the
# clamp floors at 8 lets a player set a budget that never takes effect, and the symptom is a
# character that does not forget when they asked it to. The default is pinned too, so the
# slider's starting position stays the number docs\MEMORY.md justifies.
$memText = Read-Code (Join-Path $modSrc "AiNpcMemory.reds")

$clampBlock = [regex]::Match($memText, '(?s)func AiNpcMemoryClampFactBudget\(.*?\n\}')
$floorCode  = [regex]::Match($clampBlock.Value, 'value\s*<\s*(\d+)')
$ceilCode   = [regex]::Match($clampBlock.Value, 'value\s*>\s*(\d+)')
$defCode    = [regex]::Match($memText, '(?s)func AiNpcMemoryDefaultMaxFacts\(\)[^\{]*\{\s*return\s+(\d+)')

# Anchored on the FIELD, not on the display name: a label is a text a player reads and may be
# reworded any afternoon, and the rule must not go quietly inert when it is.
$sliderBlock = [regex]::Match($settingsText, '(?s)ModSettings\.min", "(?<min>\d+)".*?memoryFacts: Int32 = (\d+);')
$minMenu = [regex]::Match($sliderBlock.Value, 'ModSettings\.min", "(\d+)"')
$maxMenu = [regex]::Match($sliderBlock.Value, 'ModSettings\.max", "(\d+)"')

$sliderGaps = @()
if (-not $clampBlock.Success -or -not $sliderBlock.Success -or -not $defCode.Success) {
    # Same reasoning as everywhere else here: a rule that finds neither side compares nothing
    # and passes. Absence is the failure.
    $sliderGaps += "AiNpcMemoryClampFactBudget, AiNpcMemoryDefaultMaxFacts or the Memory Size field not found - the rule is reading nothing"
} else {
    if ($minMenu.Groups[1].Value -ne $floorCode.Groups[1].Value) {
        $sliderGaps += "menu min $($minMenu.Groups[1].Value) vs clamp floor $($floorCode.Groups[1].Value)"
    }
    if ($maxMenu.Groups[1].Value -ne $ceilCode.Groups[1].Value) {
        $sliderGaps += "menu max $($maxMenu.Groups[1].Value) vs clamp ceiling $($ceilCode.Groups[1].Value)"
    }
    if ($sliderBlock.Groups[1].Value -ne $defCode.Groups[1].Value) {
        $sliderGaps += "field default $($sliderBlock.Groups[1].Value) vs AiNpcMemoryDefaultMaxFacts $($defCode.Groups[1].Value)"
    }
}

# The switch's own description promises a number of turns to a player who turns memory off.
# It is the one figure in the menu that states what the code will then do, so it is pinned
# to the code the same way -- a menu that promises 20 and trims at 12 is a lie nobody would
# catch, because the two live four files apart.
$turnsMenu = [regex]::Match($settingsText, 'ModSettings.description", "[^"]*?last (\d+) turns')
$turnsCode = [regex]::Match($memText, '(?s)func AiNpcMemoryLegacyMaxTurns\(\)[^\{]*\{\s*return\s+(\d+)')
if (-not $turnsMenu.Success -or -not $turnsCode.Success) {
    $sliderGaps += "the 'last N turns' promise or AiNpcMemoryLegacyMaxTurns not found - that half of the rule is reading nothing"
} elseif ($turnsMenu.Groups[1].Value -ne $turnsCode.Groups[1].Value) {
    $sliderGaps += "menu promises $($turnsMenu.Groups[1].Value) turns with memory off vs AiNpcMemoryLegacyMaxTurns $($turnsCode.Groups[1].Value)"
}
if ($sliderGaps) {
    Report-Fail "the memory slider advertises the range the code enforces" ($sliderGaps -join ", ")
} else {
    Report-Pass "the memory slider advertises the range the code enforces ($($minMenu.Groups[1].Value)-$($maxMenu.Groups[1].Value), default $($defCode.Groups[1].Value))"
}

# --- 5. Contact id list matches the shipped cast ----------------------------------------
# AiNpcGetAllContactIds seeds conversations.json and is read on every message, so it is
# written out by hand rather than derived from the cast. That makes drift possible, and
# drift is invisible: an id with no sheet is a contact with no bio, and a sheet with no id
# is a character the phone never offers.
$listBlock = [regex]::Match($allText, '(?s)func AiNpcGetAllContactIds\(\)[^\{]*\{(.*?)\n\}')
$declared = @()
foreach ($m in [regex]::Matches($listBlock.Groups[1].Value, '"([^"]+)"')) { $declared += $m.Groups[1].Value }

# One sheet per file in cast\, each stating its own id.
$sheets = @()
foreach ($f in $files) {
    if ($f.Directory.Name -ne "cast") { continue }
    $text = Read-Code $f.FullName
    $m = [regex]::Match($text, 'c\.contactId\s*=\s*"([^"]+)"')
    if ($m.Success) { $sheets += $m.Groups[1].Value }
    else { $sheets += "<no contactId in $($f.Name)>" }
}

# Same reasoning as elsewhere: a rule that finds neither side would compare two empty lists
# and pass. Absence is a failure, not a clean result.
if (-not $listBlock.Success -or $sheets.Count -eq 0) {
    Report-Fail "contact id list matches the cast" "AiNpcGetAllContactIds or the cast\ sheets not found - the rule is reading nothing"
} else {
    $onlySheet = $sheets   | Sort-Object -Unique | Where-Object { $declared -notcontains $_ }
    $onlyList  = $declared | Sort-Object -Unique | Where-Object { $sheets   -notcontains $_ }
    if ($onlySheet -or $onlyList) {
        $detail = @()
        if ($onlySheet) { $detail += "has a sheet but is not declared: " + ($onlySheet -join ", ") }
        if ($onlyList)  { $detail += "declared but has no sheet: " + ($onlyList -join ", ") }
        Report-Fail "contact id list matches the cast" ($detail -join "`n")
    } else {
        Report-Pass "contact id list matches the cast ($($declared.Count) contacts)"
    }
}

# --- 5b. Every sheet is in the cast -----------------------------------------------------
# A sheet nobody calls is a file that compiles, reads correctly, and describes a character
# the mod never registers. The failure is silent in exactly the way this refactor set out
# to remove, so it is checked rather than trusted.
$castBlock = [regex]::Match($allText, '(?s)func AiNpcBuiltinCast\(\)[^\{]*\{(.*?)\n\}')
$listed = @()
foreach ($m in [regex]::Matches($castBlock.Groups[1].Value, 'AiNpcSheet(\w+)\(\)')) { $listed += $m.Groups[1].Value }
$defined = @()
# `public` is optional here on purpose: a sheet is reached only from inside the module, so
# exporting one is not required and the visibility pass took the keyword off. Pinning the rule
# to `public func` made it stop finding anything and say so -- which is the failure mode the
# file header warns about, caught by the check's own "reading nothing" guard.
foreach ($m in [regex]::Matches($allText, '(?m)^(public\s+)?func AiNpcSheet(\w+)\(\)')) { $defined += $m.Groups[2].Value }

if (-not $castBlock.Success -or $defined.Count -eq 0) {
    Report-Fail "every sheet is in the cast" "AiNpcBuiltinCast or the sheet functions not found - the rule is reading nothing"
} else {
    $orphans = $defined | Sort-Object -Unique | Where-Object { $listed -notcontains $_ }
    $missing = $listed  | Sort-Object -Unique | Where-Object { $defined -notcontains $_ }
    if ($orphans -or $missing) {
        $detail = @()
        if ($orphans) { $detail += "written but never registered: " + (($orphans | ForEach-Object { "AiNpcSheet$_" }) -join ", ") }
        if ($missing) { $detail += "registered but not written: " + (($missing | ForEach-Object { "AiNpcSheet$_" }) -join ", ") }
        Report-Fail "every sheet is in the cast" ($detail -join "`n")
    } else {
        Report-Pass "every sheet is in the cast ($($defined.Count) sheets)"
    }
}

# --- 6. The RedFileSystem storage name is legal ----------------------------------------
# RedFileSystem validates storage names against [A-Za-z]{3,24}. An illegal name is not a
# warning: GetStorage returns null and the whole service dies with it. "ai_npc" was
# rejected for its underscore, which took settings, history and the self-tests down.
$storageText = Read-Code (Join-Path $modSrc "AiNpcStorage.reds")
$nameMatch = [regex]::Match($storageText, 'MOD_STORAGE_NAME:\s*String\s*=\s*"([^"]*)"')
if (-not $nameMatch.Success) {
    Report-Fail "storage name is legal for RedFileSystem" "MOD_STORAGE_NAME not found"
} elseif ($nameMatch.Groups[1].Value -cnotmatch '^[A-Za-z]{3,24}$') {
    Report-Fail "storage name is legal for RedFileSystem" `
        ("`"" + $nameMatch.Groups[1].Value + "`" does not match [A-Za-z]{3,24} - letters only, no digits or underscore")
} else {
    Report-Pass ("storage name is legal for RedFileSystem (" + $nameMatch.Groups[1].Value + ")")
}

# --- 7. The history model stays pure ---------------------------------------------------
# These are the modules that can be unit-tested cheaply, and that holds only as long as they
# touch no game API, no file system and no global state. Guard the boundary.
$pureModules = @("AiNpcHistory.reds", "AiNpcActionTag.reds", "AiNpcActionPattern.reds",
                 "AiNpcTemplate.reds", "AiNpcText.reds",
                 "AiNpcPendingContext.reds", "AiNpcRepair.reds", "AiNpcGeneration.reds",
                 "AiNpcExtensionRules.reds", "AiNpcTicketBook.reds",
                 "AiNpcTransferLedger.reds")
$forbidden = @('GameInstance', 'FileSystem', 'ParseJson', 'GetAiNpcSystem', 'GetAiNpcHttpSystem', 'AiNpcConversationStore', '^import ')
$impure = @()
foreach ($module in $pureModules) {
    $text = Read-Code (Join-Path $modSrc $module)
    foreach ($pattern in $forbidden) {
        if ($text -match $pattern) { $impure += "$module -> " + $pattern.TrimStart('^').Trim() }
    }
}
if ($impure) {
    Report-Fail "pure modules have no game dependencies" ($impure -join "`n")
} else {
    Report-Pass "pure modules have no game dependencies ($($pureModules.Count))"
}

# --- 7b. The journal model stays testable ----------------------------------------------
# AiNpcJournal.reds cannot be on the list above: it serializes, so it needs RedData.Json.
# The property that matters for it is the same one though -- a replay must be assertable
# without a game session and without a disk, which is what makes "a reload rebuilds what
# the session had" a test rather than a hope. So the boundary is drawn one notch out: data
# libraries yes, game and filesystem no.
$dataModules = @("AiNpcJournal.reds", "AiNpcMemory.reds", "AiNpcResponses.reds")
$dataForbidden = @('GameInstance', 'FileSystem', 'GetAiNpcSystem', 'GetAiNpcHttpSystem',
                   'AiNpcConversationStore', 'ScriptableSystem', 'ScriptableService', 'AiNpcLog')
$leaky = @()
foreach ($module in $dataModules) {
    $text = Read-Code (Join-Path $modSrc $module)
    foreach ($pattern in $dataForbidden) {
        if ($text -match $pattern) { $leaky += "$module -> $pattern" }
    }
}
if ($leaky) {
    Report-Fail "journal model has no game or disk dependencies" ($leaky -join "`n")
} else {
    Report-Pass "journal model has no game or disk dependencies ($($dataModules.Count))"
}

# --- 7c. A resolved section reads the SAME field at both levels ------------------------
# AiNpcConfiguredSection takes the contact's text and the global default as two plain
# strings, which is what let the three-level chain be written once instead of eight times.
# The cost of that shape is that nothing in the language stops the two arguments naming
# DIFFERENT fields -- resolving `over.worldMechanics` against `prompts.worldBackground`
# compiles, runs, and produces a prompt that is wrong in a way no error will ever mention.
#
# So the agreement is checked here. Only calls whose two arguments are both plain field
# accesses are in scope; the tone sections pass AiNpcPickTone(...) and the mechanics section
# passes "" for a level it deliberately skips, and neither is a field to compare.
$sectionMismatches = @()
$sectionsChecked = 0
foreach ($m in [regex]::Matches($allText, '(?s)AiNpcConfiguredSection\(\s*contactId,\s*([^,;]*?)\.(\w+),\s*([^,;]*?)\.(\w+)\)')) {
    $sectionsChecked++
    if ($m.Groups[2].Value -ne $m.Groups[4].Value) {
        $sectionMismatches += ("contact level reads ." + $m.Groups[2].Value +
                               " but the global level reads ." + $m.Groups[4].Value)
    }
}
if ($sectionMismatches) {
    Report-Fail "a resolved section reads the same field at both levels" ($sectionMismatches -join "`n")
} elseif ($sectionsChecked -eq 0) {
    Report-Fail "a resolved section reads the same field at both levels" "no AiNpcConfiguredSection call with two field arguments found - the rule is reading nothing"
} else {
    Report-Pass "a resolved section reads the same field at both levels ($sectionsChecked section(s))"
}

# --- 8. Array intrinsics are never applied to a call result ----------------------------
# REDscript array intrinsics take their operand by reference. A function's return value is
# a temporary with no stable slot, so ArrayContains(GetIds(), x) compiles cleanly, reads
# the wrong stack slot, and silently returns garbage -- false for every name, or the size
# of the *argument* array instead of the result. This is what disabled every contact and
# made the chat impossible to open. Bind to a local first; there is no runtime error to
# catch this, and redscript emits no warning.
$badIntrinsics = @()
foreach ($f in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        # Array<Op>( <identifier or a.b.c> (   <-- first argument is a call
        if ($line -match 'Array(Size|Contains|Push|Pop|Clear|Erase|Remove|RemoveAll|Insert|Resize|Grow|Last|FindFirst|FindLast)\s*\(\s*[A-Za-z_]\w*(?:\.\w+)*\s*\(') {
            $badIntrinsics += "$($f.Name):$lineNo  $($line.Trim())"
        }
    }
}
if ($badIntrinsics) {
    Report-Fail "array intrinsics operate on locals, not call results" ($badIntrinsics -join "`n")
} else {
    Report-Pass "array intrinsics operate on locals, not call results"
}

# --- 8b. A call result is never indexed ------------------------------------------------
# The same defect as check 8, in the form the intrinsic rule cannot see. A returned object
# is a temporary with no stable slot, so Clamp(m).facts[0] reads back empty rather than the
# first element -- silently, with no warning and nothing in the log. This is what kept
# "memory/the cut keeps the start intact" red for days while the code under it was correct,
# and reading a red suite as normal is how the next real failure gets ignored.
# Bind the result to a local, then index the local.
$badIndexing = @()
foreach ($f in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        # <call>( ... ) [  or  <call>( ... ) .field[  -- indexing straight off a call
        if ($line -match '[A-Za-z_]\w*\s*\([^()]*\)\s*(\.\w+\s*)*\[') {
            $badIndexing += "$($f.Name):$lineNo  $($line.Trim())"
        }
    }
}
if ($badIndexing) {
    Report-Fail "a call result is bound before it is indexed" ($badIndexing -join "`n")
} else {
    Report-Pass "a call result is bound before it is indexed"
}

# --- 8c. The palette lives in one file --------------------------------------------------
# A colour written at a call site is a colour that cannot be changed. The mod has two chat
# surfaces and the identity is the thing they share, so a literal outside AiNpcStyle.reds is
# either a role that should have been named or a drift waiting to happen -- sixteen copies of
# the same cyan were spelled out in the phone chat before this rule existed.
#
# Exempt: AiNpcStyle.reds itself, and AiNpcHudKeyProbe.reds, whose deliberately garish magenta
# is a diagnostic marker rather than part of the identity (and which is switched off).
$paletteExempt = @("AiNpcStyle.reds", "AiNpcHudKeyProbe.reds")
$badColours = @()
foreach ($f in $files) {
    if ($paletteExempt -contains $f.Name) { continue }
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        if ($line -match 'new\s+Color\s*\(') {
            $badColours += "$($f.Name):$lineNo  $($line.Trim())"
        }
    }
}
if ($badColours) {
    Report-Fail "colours come from AiNpcStyle, not from call sites" ($badColours -join "`n")
} else {
    Report-Pass "colours come from AiNpcStyle, not from call sites"
}

# --- 8d. The chat session reaches for nothing -------------------------------------------
# Rule 3b of docs/VIEW_ARCHITECTURE.md. The self-tests run from a ScriptableService at game
# start, BEFORE any ScriptableSystem exists, so a session that called AiNpcConversationStore.Get()
# or GetAiNpcHttpSystem() inside a policy would be exactly as untestable as the registry was --
# and the whole reason the session is worth having is that the suite can reach it. A caller
# hands it data; it never fetches.
$sessionFile = $files | Where-Object { $_.Name -eq "AiNpcChatSession.reds" }
$badReaches = @()
if ($sessionFile) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($sessionFile.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        if ($line -match 'Get[A-Za-z]*System\s*\(' -or $line -match '[A-Za-z_]\w*\.Get\s*\(\s*\)') {
            $badReaches += "AiNpcChatSession.reds:$lineNo  $($line.Trim())"
        }
    }
}
if ($badReaches) {
    Report-Fail "the chat session is handed its data, never fetches it" ($badReaches -join "`n")
} else {
    Report-Pass "the chat session is handed its data, never fetches it"
}

# --- 8g. The conversation store is reached from its own layer only ----------------------
# AiNpcConversationApi is the door for everything ABOVE the store layer, and saying so in its
# header was not enough: two callers had drifted past it, each one line that looked local and
# correct. The client's ForgetConversation cleared a thread without refilling that contact's
# transfer allowance, which the door does -- so the public API and the mod's own reset left the
# save in two different states, and neither call site could see the other.
#
# The layer is not a single file, and stating it as one is what made the claim false. Four
# files ARE the store layer:
#
#   AiNpcConversationStore   the store itself
#   AiNpcConversationApi     the door the layer offers everything above it
#   AiNpcMemoryService       a compaction reads the messages, reads the memory and writes both
#                            under one consistency check -- one operation, not three calls
#   AiNpcJournalApi          the branch/import surface, reached from Lua by qualified name
#                            because a scripted global in a module is not a Lua global
#
# Adding a fifth name here is the decision that the file belongs to that layer. The compiler
# will not make it for you, and neither will a code review of one line.
$storeLayer = @("AiNpcConversationStore.reds", "AiNpcConversationApi.reds",
                "AiNpcMemoryService.reds", "AiNpcJournalApi.reds")
$storeStrays = @()
$storeLayerHits = 0
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    $hits = ([regex]'AiNpcConversationStore\s*\.\s*Get\s*\(').Matches($text).Count
    if ($hits -eq 0) { continue }
    if ($storeLayer -contains $f.Name) {
        $storeLayerHits += $hits
    } else {
        $storeStrays += "$($f.Name): $hits direct store handle(s)"
    }
}
if ($storeLayerHits -eq 0) {
    Report-Fail "the store is reached from its own layer only" `
        "AiNpcConversationStore.Get() found nowhere - the rule is reading nothing"
} elseif ($storeStrays.Count -gt 0) {
    Report-Fail "the store is reached from its own layer only" `
        (($storeStrays -join "`n") + "`nGo through AiNpcConversationApi; see its header for why the layer is not one file.")
} else {
    Report-Pass "the store is reached from its own layer only ($($storeLayer.Count) file(s))"
}

# --- 8i. A conversation opens and closes through one door -------------------------------
# The same failure as 8g, one layer up. A session's shown contact IS the conversation, so
# Show/Close are the two moments a thread opens and ends; the announcement that goes with them
# lived in AiNpcSystem.ShowModChat, which is the PHONE's door. AGENT LINK therefore opened
# conversations no listener saw, and -- the part that cost something -- never reached
# AiNpcMemoryService.NotifyConversationOpened, which is idle compaction's single trigger point.
# A terminal-only player never compacted. Switching contact inside the phone was silent for the
# same reason: SwitchChatTo repaints, it does not reopen.
#
# Two files may touch a session's Show/Close: the door, and the tests that assert the door.
# Everything else calls AiNpcOpenConversation / AiNpcCloseConversation.
$doorOwners = @("AiNpcChatDoor.reds")
$doorStrays = @()
$doorHits = 0
foreach ($f in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        # Anchored on a receiver whose NAME ends in "session", so AiNpcPhoneClaim.Close() and
        # the renderer's own Show* helpers are not swept in with it. A surface that reaches a
        # session through a differently named handle escapes this; the naming is the codebase's
        # and the rule follows it rather than matching every Show( in the mod.
        if ($line -notmatch '\b[A-Za-z_]*[Ss]ession\s*\.\s*(Show|Close)\s*\(') { continue }
        if (($doorOwners -contains $f.Name) -or (Test-IsSelfTest $f)) {
            $doorHits++
        } else {
            $doorStrays += "$($f.Name):$lineNo  $($line.Trim())"
        }
    }
}
if ($doorHits -eq 0) {
    Report-Fail "a conversation opens through one door" `
        "no session Show/Close found anywhere - the rule is reading nothing"
} elseif ($doorStrays.Count -gt 0) {
    Report-Fail "a conversation opens through one door" `
        (($doorStrays -join "`n") + "`nCall AiNpcOpenConversation / AiNpcCloseConversation; see the head of AiNpcChatDoor.reds.")
} else {
    Report-Pass "a conversation opens through one door ($doorHits call(s) in the door)"
}

# --- 8j. The two conversation events are announced from the door only -------------------
# The other half of 8i, and the half that actually drifted: publishing is what a surface forgot,
# not the Show. Pinned separately so that moving an announcement back into a surface fails here
# even if the Show stayed where it belongs.
$eventOwners = @("AiNpcChatDoor.reds", "AiNpcExtensionRegistry.reds", "AiNpcMemoryService.reds")
$eventStrays = @()
$eventHits = 0
foreach ($f in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        if ($line -notmatch '\b(AiNpcPublishConversation(Opened|Closed)|NotifyConversationOpened)\s*\(') { continue }
        if ($eventOwners -contains $f.Name) {
            $eventHits++
        } else {
            $eventStrays += "$($f.Name):$lineNo  $($line.Trim())"
        }
    }
}
if ($eventHits -eq 0) {
    Report-Fail "conversation events are announced from the door" `
        "no conversation event found anywhere - the rule is reading nothing"
} elseif ($eventStrays.Count -gt 0) {
    Report-Fail "conversation events are announced from the door" `
        (($eventStrays -join "`n") + "`nA surface announcing for itself is what left AGENT LINK silent; announce in AiNpcChatDoor.reds.")
} else {
    Report-Pass "conversation events are announced from the door ($eventHits site(s))"
}

# --- 8k. The shared storage folder is opened in one place --------------------------------
# Not the RedFileSystem claim -- check 6 and AiNpcStorageService cover that -- but the four
# byte-identical copies of "ask the service, null-check it, return its folder" that had grown in
# the config loader, the conversation store, the usage ledger, and in api\AiNpcApi.reds, whose
# own header forbids it from holding any logic at all. Four copies of one null check is four
# chances to write the fifth without it.
$folderStrays = @()
foreach ($f in $files) {
    if ($f.Name -eq "AiNpcStorage.reds") { continue }
    $text = Read-Code $f.FullName
    $hits = ([regex]'GetFileStorage\s*\(\s*\)').Matches($text).Count
    if ($hits -gt 0) { $folderStrays += "$($f.Name): $hits direct folder handle(s)" }
}
$folderOwner = ([regex]'GetFileStorage\s*\(\s*\)').Matches((Read-Code (Join-Path $modSrc "AiNpcStorage.reds"))).Count
if ($folderOwner -eq 0) {
    Report-Fail "the shared storage folder is opened in one place" `
        "GetFileStorage() not found in AiNpcStorage.reds - the rule is reading nothing"
} elseif ($folderStrays.Count -gt 0) {
    Report-Fail "the shared storage folder is opened in one place" `
        (($folderStrays -join "`n") + "`nCall AiNpcModStorage(); api\AiNpcSharedStorage delegates to it in one line.")
} else {
    Report-Pass "the shared storage folder is opened in one place"
}

# --- 8h. A thread is erased through one door --------------------------------------------
# The companion to 8g, and the reason it exists. Clearing a thread also refills that contact's
# transfer allowance, because the cap stops one character from minting eddies and a conversation
# that no longer exists has spent nothing. Two call sites doing that is two chances to forget
# the second half; the store layer itself replays operations and must NOT refill anything, so
# the rule is on the callers rather than inside Clear.
$clearStrays = @()
foreach ($f in $files) {
    if ($f.Name -eq "AiNpcConversationApi.reds") { continue }
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        if ($line -match '\bstore\s*\.\s*Clear\s*\(') {
            $clearStrays += "$($f.Name):$lineNo  $($line.Trim())"
        }
    }
}
if ($clearStrays) {
    Report-Fail "a thread is erased through one door" `
        (($clearStrays -join "`n") + "`nCall AiNpcResetConversation: it refills the contact's transfer allowance too.")
} else {
    Report-Pass "a thread is erased through one door (AiNpcResetConversation)"
}

# --- 8j. ai_npc contributes through its own client ---------------------------------------
# The mod's own contributions -- the romance rubric, the eddie transfer -- are the first
# consumer of the public API, and that is the only thing keeping the API honest. Both went
# straight to the registry instead, under a hand-written "ai_npc", while both file headers said
# in as many words that they came through the public door.
#
# It WORKED, which is why it survived a rewrite whose whole subject was this file's privileges.
# What it cost is one line: opening a client claims the mod id, so ai_npc was the one
# contributor absent from AiNpcExplainCharacter -- the diagnostic the API offers precisely for
# reading who contributed what to a character.
#
# AiNpcDataAction is the one caller that stays direct, and not by concession: it registers on
# behalf of a synthetic per-sheet mod id it invents from a contact id, and clears that id's
# earlier commands first. It speaks for a character file, never for ai_npc.
$registrarOwners = @("api/AiNpcClient.reds", "AiNpcExtensionRegistry.reds",
                     "AiNpcActionRegistry.reds", "AiNpcDataAction.reds")
$registrarStrays = @()
$registrarHits = 0
foreach ($f in $files) {
    $lineNo = 0
    $owned = ($registrarOwners | Where-Object { $f.Name -eq ($_ -split '/')[-1] }).Count -gt 0 -or (Test-IsSelfTest $f)
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        if ($line -match '\bregistry\s*\.\s*(RegisterExtension|RegisterAction)\s*\(') {
            if ($owned) { $registrarHits++ } else {
                $registrarStrays += "$($f.Name):$lineNo  $($line.Trim())"
            }
        }
    }
}
if ($registrarHits -eq 0) {
    Report-Fail "ai_npc contributes through its own client" `
        "no direct registration found anywhere - the rule is reading nothing"
} elseif ($registrarStrays.Count -gt 0) {
    Report-Fail "ai_npc contributes through its own client" `
        (($registrarStrays -join "`n") + "`nUse AiNpcOpenClient(AiNpcOwnModId()); the claim is what puts ai_npc in its own diagnostics.")
} else {
    Report-Pass "ai_npc contributes through its own client ($registrarHits owned registration(s))"
}

# --- 8i. The speaking lane answers only for the generation -------------------------------
# The sibling of N+4, one system further in. AiNpcHttpSystem holds the request in flight, and
# it also used to hold the context mods had seeded -- which is a fact about the contacts, not
# about a request. Hosting it there made three callers with no business in the lane reach for
# GetAiNpcHttpSystem(): seeding a line, forgetting a withdrawn mod's lines, reading a budget.
# None of the three could be answered without a handle on a generation they never used.
#
# The allowed files are the ones that genuinely start, observe or stop a request. Everything
# else asks a named question -- AiNpcSetPendingContext, AiNpcIsGenerating -- and a question that
# does not exist yet is the signal that something else has moved into the lane.
$laneAllowed = @("AiNpcHttp.reds", "AiNpcSystem.reds", "AiNpcChatSession.reds",
                 "AiNpcTerminalChat.reds", "AiNpcPhoneWidgets.reds", "AiNpcLaneCallback.reds",
                 "AiNpcSpeechQueue.reds", "AiNpcConversationApi.reds", "AiNpcUtilities.reds",
                 "AiNpcClientRegistry.reds")
$laneStrays = @()
$laneAllowedHits = 0
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    $hits = ([regex]'GetAiNpcHttpSystem\s*\(').Matches($text).Count
    if ($hits -eq 0) { continue }
    if (($laneAllowed -contains $f.Name) -or (Test-IsSelfTest $f)) {
        $laneAllowedHits += $hits
    } else {
        $laneStrays += "$($f.Name): $hits reach(es) into the speaking lane"
    }
}
if ($laneAllowedHits -eq 0) {
    Report-Fail "the speaking lane answers only for the generation" `
        "GetAiNpcHttpSystem() found nowhere - the rule is reading nothing"
} elseif ($laneStrays.Count -gt 0) {
    Report-Fail "the speaking lane answers only for the generation" `
        (($laneStrays -join "`n") + "`nIf the question is not about a request in flight, it does not live on that system.")
} else {
    Report-Pass "the speaking lane answers only for the generation ($($laneAllowed.Count) file(s) allowed)"
}

# --- 8e. The borrowed phone has exactly one owner ---------------------------------------
# Drawing the mod's chat borrows two things from the vanilla phone -- its contact input and its
# contact list -- and both have to be given back, together, whatever ends the chat. Deleting
# one still compiles, and leaves the player on an invisible contact list over an input-dead
# phone: nothing fails, nothing logs.
#
# The owner is AiNpcPhoneClaim.reds -- Take() and Release() move both halves or neither, and
# m_held makes them idempotent -- so this is a rule about WHERE code may appear rather than
# about what a particular function contains today.
#
# AiNpcPhoneRenderer.reds is allowed because it DECLARES ToggleContactList; the pattern below
# matches calls (a leading dot), so the declaration does not trip it.
$claimOwners = @("AiNpcPhoneClaim.reds")
$claimPattern = '\.DisableContactsInput\(|\.EnableContactsInput\(|\.ToggleContactList\('
$claimStrays = @()
$claimOwnerHits = 0
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    $hits = ([regex]$claimPattern).Matches($text).Count
    if ($hits -eq 0) { continue }
    if ($claimOwners -contains $f.Name) { $claimOwnerHits += $hits }
    else { $claimStrays += "$($f.Name): $hits call(s)" }
}
if ($claimOwnerHits -eq 0) {
    Report-Fail "the borrowed phone has one owner" `
        "no borrow/return call found in AiNpcPhoneClaim.reds - the rule is reading nothing"
} elseif ($claimStrays.Count -gt 0) {
    Report-Fail "the borrowed phone has one owner" `
        (($claimStrays -join "`n") + "`nBorrowing and returning the phone happen in AiNpcPhoneClaim.reds, in pairs, or not at all.")
} else {
    Report-Pass "the borrowed phone has one owner ($claimOwnerHits call(s))"
}

# --- 8f. The phone's state is stored once ----------------------------------------------
# "The chat is on screen" is stored ONCE, in the state machine's screen:
# AiNpcPhoneStateMachine.IsChatOpen() / IsTyping(), the phone claim and the session registry
# all follow it. Four representations of one fact are sixteen combinations of which two are
# legal, and keeping the other fourteen unreached is not the same as unreachable. This rule
# keeps a convenience field from quietly reintroducing a second opinion.
$sysFields = @()
foreach ($m in [regex]::Matches($settingsText, '(?m)^\s*(?:public|private|protected)\s+let\s+(\w+)\s*:\s*Bool')) {
    $sysFields += $m.Groups[1].Value
}
$mirrorNames = @("chatOpen", "isTyping", "unread", "isVanillaChatOpen", "npcChatOpen", "typing")
$mirrors = $sysFields | Where-Object { $mirrorNames -contains $_ }
if ($mirrors) {
    Report-Fail "the phone's state is stored once" `
        (("AiNpcSystem carries a Bool that mirrors the screen: " + ($mirrors -join ", ")) + `
         "`nAsk AiNpcPhoneStateMachine instead; it is the only place a screen is written.")
} else {
    Report-Pass "the phone's state is stored once ($($sysFields.Count) Bool field(s), none mirroring the screen)"
}

# --- 9. The built-in command has no privileges left -------------------------------------
# It used to have several, and each one was a place where the announcement and the dispatch
# could drift: a parser that ran before everybody else, a veto named after it in the public
# interface, a block of prompt text written by hand beside the section that suppressed it.
# All four defects in docs/PLAN_ACTION_LANE.md grew in that gap.
#
# The transfer now registers through AddAction like any mod's command, so no other file has any
# business naming it. That is the invariant, and it is cheap to check: the name appears in its
# own handler and in the tests, nowhere else.
$transferOwners = @("AiNpcTransferHandler.reds", "AiNpcConfig.reds")
$leaks = @()
foreach ($f in $files) {
    if (($f.Name -in $transferOwners) -or (Test-IsSelfTest $f)) { continue }
    $text = Read-Code $f.FullName
    if ($text -match 'GIVE_EDDIES') { $leaks += $f.Name }
}
# AiNpcConfig.reds is allowed one mention, in the line of characters.example.json that shows a
# player how to refuse the command. That is documentation written to disk, never prompt text.
$exampleMentions = ([regex]::Matches((Read-Code (Join-Path $modSrc "AiNpcConfig.reds")), 'GIVE_EDDIES')).Count
if ($exampleMentions -gt 1) {
    $leaks += "AiNpcConfig.reds ($exampleMentions mentions, expected 1 in characters.example.json)"
}

$privileged = @("AllowsGenericTransfer", "noGenericTransfer", "AiNpcIsBuiltinActionTag",
                "AiNpcParseActions", "AiNpcStripTransfers")
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    foreach ($name in $privileged) {
        if ($text -match [regex]::Escape($name)) { $leaks += "$($f.Name) -> $name" }
    }
}

if ($leaks) {
    Report-Fail "the built-in command has no privileges" (($leaks | Sort-Object -Unique) -join "`n")
} else {
    Report-Pass "the built-in command has no privileges (declared once, like any other)"
}

# --- 10. Language names match the language enum ---------------------------------------
# prompts.json keys its language overrides by enum member name. A name that drifts from
# the enum is not an error anywhere: the override is simply never selected, and the
# built-in text is used instead -- a silent no-op, which is the whole failure mode moving
# prompts to data introduced.
$langEnum = [regex]::Match($allText, '(?s)enum AiNpcLanguage\s*\{(.*?)\}')
$langMembers = @()
foreach ($m in [regex]::Matches($langEnum.Groups[1].Value, '(?m)^\s*([A-Za-z_]\w*)\s*=')) {
    $langMembers += $m.Groups[1].Value
}

$langNamesBlock = [regex]::Match($allText, '(?s)func AiNpcLanguageNames\(\)[^\{]*\{(.*?)\n\}')
$langNames = @()
foreach ($m in [regex]::Matches($langNamesBlock.Groups[1].Value, '"([^"]+)"')) { $langNames += $m.Groups[1].Value }

# Every member is a real language now: the "Auto" sentinel is gone with the setting it
# belonged to, the reply language being read from the game and nothing else. So the two
# lists must match exactly, with nothing excluded.

if (($langMembers -join ",") -ne ($langNames -join ",")) {
    Report-Fail "language names match the language enum" `
        (("enum:  " + ($langMembers -join ", ")), ("names: " + ($langNames -join ", ")) -join "`n")
} else {
    Report-Pass "language names match the language enum ($($langNames.Count) language(s))"
}

# --- N. Every source file declares the module ------------------------------------------
# `module AiNpc` is what third-party mods guard on with @if(ModuleExists("AiNpc")) to take
# this mod as an OPTIONAL dependency, and it is also what keeps a declaration that is not
# marked `public` invisible outside ai_npc.
#
# A file that forgets the line still compiles: its declarations simply land in the global
# namespace instead. That is the failure this check exists for -- the symbol stays reachable
# from everywhere, so nothing breaks today, and the encapsulation the module is supposed to
# provide is quietly gone for that file. Both shipped script folders are covered; the second
# exists only to control @wrapMethod ordering, which modules do not change.
#
# Submodules count: tests\AiNpcTestSuite.reds declares `module AiNpc.TestSuite` so that the rest
# of the mod can ask @if(ModuleExists("AiNpc.TestSuite")) whether the self-tests are in this
# build, which is what lets a release drop them (see AiNpcSelfTest.reds). It is still inside
# ai_npc's namespace, which is all this check is defending.
$allSources = Get-ChildItem -Path (Join-Path $root "src/r6/scripts") -Recurse -Filter "*.reds"
$noModule = @()
foreach ($f in $allSources) {
    $code = Read-Code $f.FullName
    if ($code -notmatch '(?m)^module\s+AiNpc(\.[A-Za-z_]\w*)*\s*$') { $noModule += $f.Name }
}
if ($noModule.Count -gt 0) {
    Report-Fail "every source file declares 'module AiNpc'" ($noModule -join ", ")
} else {
    Report-Pass "every source file declares 'module AiNpc' ($($allSources.Count) file(s))"
}

# --- N+0.5. The FOMOD installer is valid XML -------------------------------------------
# Vortex parses fomod\ModuleConfig.xml BEFORE it copies anything. Malformed XML there does not
# degrade the install, it cancels it: "Invalid installer script", no files written, and the
# only clue is a line number in Vortex's own log -- the mod is never blamed, because it never
# gets installed.
#
# The trap: an XML comment may not contain a double dash, and this repo's house style puts
# double dashes in every comment it writes. The rule is that ONE habit meeting ONE format,
# rather than a general "check the XML is well-formed".
$fomodIssues = @()
foreach ($xmlName in @("ModuleConfig.xml", "info.xml")) {
    $xmlPath = Join-Path $root "fomod\$xmlName"
    if (-not (Test-Path $xmlPath)) {
        $fomodIssues += "fomod\$xmlName is missing - the Nexus installer would not run"
    } else {
        try {
            [xml](Get-Content $xmlPath -Raw) | Out-Null
        } catch {
            $fomodIssues += "fomod\$xmlName : $($_.Exception.Message)"
        }
    }
}
if ($fomodIssues.Count -gt 0) {
    Report-Fail "the FOMOD installer is valid XML" ($fomodIssues -join "`n")
} else {
    Report-Pass "the FOMOD installer is valid XML (2 file(s))"
}

# --- N+1. No class is looked up by a literal name ---------------------------------------
# Inside a module a class is registered in RTTI under its QUALIFIED name, so
# Get(n"AiNpcConversationStore") returns null where it used to work. NameOf<T>() spells the
# qualified name for us and moves with the class. This is the same fix Dark Future carries
# for the same reason, and the failure it prevents is silent: a null system handle reads as
# "the feature is off", not as an error.
#
# It also decides, in passing, how a callback method may be named. An ink callback is a
# CName too, resolved on the target object rather than through RTTI, so n"AiNpcSomething"
# there would be correct code that this check cannot tell from a class lookup. Rather than
# exempt it -- and lose the check on every line that registers one -- the terminal UI names
# its handlers On* (OnAiNpcTerminalRow, OnAiNpcFieldKey), which is the engine's own
# convention for a cb func anyway.
$literalLookups = @()
foreach ($f in $allSources) {
    $code = Read-Code $f.FullName
    foreach ($m in [regex]::Matches($code, 'n"(AiNpc[A-Za-z0-9_]*)"')) {
        $literalLookups += "$($f.Name): $($m.Value)"
    }
}
if ($literalLookups.Count -gt 0) {
    Report-Fail "classes are looked up with NameOf<T>(), not a literal CName" ($literalLookups -join "`n")
} else {
    Report-Pass "classes are looked up with NameOf<T>(), not a literal CName"
}

# --- N+2. The built-in world lore states a posture, not just a set of facts -------------
# This is the default every contact inherits, third-party ones included, and the only place
# that tells the model which century's assumptions about the body apply. Two failures, both
# observed in play. With no rule stated the model supplies its own -- condoms, testing, "be
# careful" -- and a character gives twenty-first century health advice in a world that
# engineered the problem away; it reads as prudishness, not as a bug, which is what makes it
# survive. And prose that states the world declaratively is prose the model recites back, so a
# character answered a friend in trouble with "that's just Night City, you get used to it".
# The load-bearing sentence is the ban on narrating the norm, inside HOW IT SHOWS: drop it and
# the recitation comes straight back.
#
# Checked here rather than in AiNpcTests because it is a property of the PROSE: the runtime
# test pins the structure, this pins that the headings still say something. The three named
# brands are what makes BODY concrete rather than abstract -- a rewrite that keeps the heading
# and drops every product name has lost the argument the paragraph exists to make.
# The pattern is written on one line on purpose. Spelling it across three put a REAL
# newline inside the literal, and git checks this file out with CRLF while $allText is
# joined with LF -- so the tail could never match and the check failed on every run,
# reporting a function that is right there. Same trap below, same fix.
$loreMatch = [regex]::Match($allText, '(?s)func AiNpcBuiltinWorldLoreFor\([^\)]*\)[^\{]*\{(?<body>.*?)\r?\n\}')
$loreIssues = @()
if (-not $loreMatch.Success) {
    $loreIssues += "AiNpcBuiltinWorldLoreFor() not found - the built-in lore moved or was inlined again"
} else {
    $lore = $loreMatch.Groups["body"].Value
    $required = @{
        "LIVED:"           = "what the character has already seen, written as experience"
        "reaches you is people" = "the asymmetry -- habituated to the city, not to people"
        "HOW IT SHOWS:"    = "the rule in the negative: habituation shows in what is omitted"
        "leave out"        = "the omission the rubric turns on"
        "how this world works" = "the ban on narrating the norm - without it the model recites the lore"
        "local weather"    = "the image that carries the ban, and the only form of it left in the block"
        "WRONG:"           = "the wrong half of the contrast pairs"
        "RIGHT:"           = "the right half of the contrast pairs"
        "BODY:"            = "the paragraph on implants and biomonitors"
        "VIOLENCE:"        = "the paragraph on violence being ordinary, paid and advertised"
        "SEX:"             = "the paragraph on the trade being legal and unremarkable"
        "ECONOMY:"         = "the paragraph on nothing being a right and everything a price"
        "not a verdict on it" = "the clause that keeps ECONOMY from handing out an opinion about corps - V may be corpo, and Takemura is loyal to one"
        "COST:"            = "the paragraph on what this world actually charges"
        "NIGHT CITY"       = "the anchors a thin model reuses instead of inventing a place"
        "biomonitor"       = "the mechanism that makes real-world health advice an anachronism"
        "immunosuppress"   = "the recurring cost that replaces it"
        "reputation"       = "the social half of the cost"
    }

    # The pairs are the calibration, and one of the three is deliberately on a subject no
    # rubric covers -- that is the one proving the posture generalises rather than looking
    # things up. Below three, it stops being a pattern and starts being an example.
    $rightCount = ([regex]::Matches($lore, "RIGHT:")).Count
    if ($rightCount -lt 3) {
        $loreIssues += "only $rightCount calibration pairs - three is what makes it a pattern"
    }
    foreach ($needle in $required.Keys) {
        if ($lore -notmatch [regex]::Escape($needle)) {
            $loreIssues += "missing '$needle' - $($required[$needle])"
        }
    }
    $brands = @("Dynalar", "Kiroshi", "Midnight Lady")
    $present = $brands | Where-Object { $lore -match [regex]::Escape($_) }
    if ($present.Count -lt 2) {
        $loreIssues += "names fewer than two in-world brands - BODY has gone abstract"
    }
}
# The vocabulary table is checked apart from the block, because its failure is a different
# one: not a missing rule but a language quietly served the English words. Cyberpunk 2077
# localised some of these terms and kept others, so a French list that still says "ripperdoc"
# or "gonk" is not a translation gap the compiler or the tests can see -- the reply stays
# fluent, it just uses words no French player has ever read on screen. The needles are the
# terms the official localisation actually changed.
$wordsMatch = [regex]::Match($allText, '(?s)func AiNpcWorldLoreWords\([^\)]*\)[^\{]*\{(?<body>.*?)\r?\n\}')
if (-not $wordsMatch.Success) {
    $loreIssues += "AiNpcWorldLoreWords() not found - the per-language vocabulary was inlined back into the lore"
} else {
    $words = $wordsMatch.Groups["body"].Value
    foreach ($needle in @("charcudoc", "paumard", "trait plat", "danse sensorielle")) {
        if ($words -notmatch [regex]::Escape($needle)) {
            $loreIssues += "the French vocabulary is missing '$needle' - an official term fell back to English"
        }
    }
    # "gonk (idiot)" and not "ripperdoc": the French line quotes the English terms in order
    # to ban them, so a needle they share would pass on a body that lost the English table
    # entirely -- and that table is the one every unlisted language gets.
    if ($words -notmatch [regex]::Escape("gonk (idiot)")) {
        $loreIssues += "the English vocabulary is gone - it is the fallback every unlisted language gets"
    }
}

if ($loreIssues.Count -gt 0) {
    Report-Fail "the built-in world lore states a posture, not just facts" ($loreIssues -join "`n")
} else {
    Report-Pass "the built-in world lore states a posture, not just facts"
}

# --- Sources stay UTF-8 without BOM -----------------------------------------------------
# The mod ships accented and Cyrillic string literals (AiNpcCarrierMessageFor), so the encoding
# of these files is player-visible. Both ways it can rot are invisible to the compiler, which
# is why they need a check rather than a convention:
#
#   * a BOM, which Windows PowerShell's -Encoding utf8 adds silently;
#   * a mojibake round trip, from any Get-Content -> Set-Content pass, which re-reads the
#     UTF-8 bytes as ANSI and writes back a two-character sequence where the source said one accented letter.
#
# scc.exe compiles a file damaged either way without a word, and the damage only surfaces
# as garbled text in a chat bubble on someone else's machine.
$encodingIssues = @()
foreach ($f in $allSources) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encodingIssues += "$($f.Name): starts with a UTF-8 BOM"
        continue
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $strict.GetString($bytes)
    } catch {
        $encodingIssues += "$($f.Name): not valid UTF-8"
        continue
    }
    # U+00C3 followed by another U+0080-U+00BF character is the signature of UTF-8
    # bytes read back as ANSI: e-acute (C3 A9) resurfaces as two characters.
    #
    # Built from code points rather than written out, because this script is itself read
    # as ANSI by Windows PowerShell 5.1 -- a literal high character in the pattern would
    # be mangled by the very bug it is looking for, and the check would quietly stop
    # matching without ever failing.
    $mojibake = [string][char]0x00C3 + '[' + [char]0x0080 + '-' + [char]0x00BF + ']'
    if ($text -match $mojibake) {
        $encodingIssues += "$($f.Name): looks like mojibake - UTF-8 re-read as ANSI somewhere"
    }
}
if ($encodingIssues.Count -gt 0) {
    Report-Fail "sources are UTF-8 without BOM" ($encodingIssues -join "`n")
} else {
    Report-Pass "sources are UTF-8 without BOM ($($allSources.Count) file(s))"
}

# --- N+3. Foreign widget trees have exactly one owner -----------------------------------
# A positional address into a tree this mod does not own -- GetWidget(2), the parentWidget
# walk, GetWidgetByIndex -- asserts a shape that belongs to the game and to every other mod
# touching the phone. When the shape changes the address does not fail cleanly: it resolves to
# something else, or to null halfway down a walk, and the deref that follows is a silent
# script error rather than a crash.
#
# So the rule is not "check for null". It is that every such walk lives in ONE function that
# returns a fully validated bundle or nothing, and those functions live in these files.
# AiNpcHooks.reds is deliberately NOT on the list: it is the file the rule most needs to keep
# clean. AiNpcPhoneInput.reds owns the walk into Codeware's HubTextInput -- the one FOREIGN-MOD
# tree the phone reads, as opposed to the vanilla HUD trees the others resolve.
$treeOwners = @("AiNpcPhoneRenderer.reds", "AiNpcPhoneWidgets.reds", "AiNpcWidgets.reds", "AiNpcPhoneInput.reds")
$treePattern = '\.GetWidget\(|\.parentWidget|inkWidgetRef\.Get\(|FindWidgetWithName\(|GetWidgetByIndex\('
$treeStrays = @()
$treeOwnerHits = 0
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    $hits = ([regex]$treePattern).Matches($text).Count
    if ($hits -eq 0) { continue }
    if ($treeOwners -contains $f.Name -or $f.Name -like "AiNpcTerminal*") {
        $treeOwnerHits += $hits
    } else {
        $treeStrays += "$($f.Name): $hits traversal(s)"
    }
}
# Absence checks pass vacuously when they find nothing at all -- see the header. If not one
# owner file contains a traversal, the pattern has stopped matching and the rule is blind.
if ($treeOwnerHits -eq 0) {
    Report-Fail "foreign widget trees have one owner" `
        "no traversal found in any owner file - the rule is reading nothing"
} elseif ($treeStrays.Count -gt 0) {
    Report-Fail "foreign widget trees have one owner" (($treeStrays -join "`n") + "`nAllowed: " + ($treeOwners -join ", ") + ", AiNpcTerminal*")
} else {
    Report-Pass "foreign widget trees have one owner ($treeOwnerHits traversal(s) in $($treeOwners.Count) file(s))"
}

# --- N+4. Nothing reads the system ambiently --------------------------------------------
# GetAiNpcSystem() is reachable from anywhere, which is what let the http lane paint a widget:
# "a generation started" is a fact about the lane, "is anything on screen" is not its
# question, and it dereferenced null on the notification path every turn.
#
# Every ScriptableSystem in REDscript is a global, so "remove the singleton" is not
# achievable. The narrower disease is a global holding mutable state that a caller READS
# instead of being told, and the cure is a function that names the question --
# AiNpcToneTier(), AiNpcProviderSetting(), AiNpcCurrentContactId(). The allowlist below is
# exactly the files that own one, plus the three that legitimately drive the system:
#
#   AiNpcSystem      it is the system
#   AiNpcHooks       the game calls it; converting these to events is a separate pass
#   AiNpcSetup       wiring, at startup
#   AiNpcSeed        the public API other mods drive the chat through
#   AiNpcPhoneView   the phone's painter
#   AiNpcTests       exercises the accessors
#   the rest         each declares one named accessor over one field
#
# The rule's job is to stop a twelfth file appearing on this list without anyone deciding
# it should. Adding a name here is the decision; the compiler will not make it for you.
#
# A FILE ADMITTED FOR ONE REASON IS NOT ADMITTED FOR EVERY READ, which is how this list leaked
# once already: AiNpcSetup is here for "wiring, at startup", true of the one write it makes and
# false of the three reads of aiModel it also had -- ambient reads of a setting whose named
# accessor, AiNpcProviderSetting, was two files away. Rule N+4b below counts those separately,
# and no file is excused from it.
$ambientAllowed = @("AiNpcSystem.reds", "AiNpcHooks.reds", "AiNpcSetup.reds", "AiNpcSeed.reds",
                    "AiNpcPhoneRenderer.reds", "AiNpcUtilities.reds",
                    "AiNpcContacts.reds", "AiNpcContactRegistry.reds", "AiNpcLanguage.reds",
                    "AiNpcPlayer.reds")
$ambientStrays = @()
$ambientAllowedHits = 0
foreach ($f in $files) {
    $text = Read-Code $f.FullName
    $hits = ([regex]'GetAiNpcSystem\(\)').Matches($text).Count
    if ($hits -eq 0) { continue }
    if (($ambientAllowed -contains $f.Name) -or (Test-IsSelfTest $f)) {
        $ambientAllowedHits += $hits
    } else {
        $ambientStrays += "$($f.Name): $hits ambient read(s)"
    }
}
if ($ambientAllowedHits -eq 0) {
    Report-Fail "the system is not read ambiently" `
        "GetAiNpcSystem() found nowhere - the rule is reading nothing"
} elseif ($ambientStrays.Count -gt 0) {
    Report-Fail "the system is not read ambiently" `
        (($ambientStrays -join "`n") + "`nAsk a named accessor instead; see AiNpcUtilities.reds.")
} else {
    Report-Pass "the system is not read ambiently ($($ambientAllowed.Count) file(s) allowed)"
}

# --- N+4b. A setting is asked by name, never read off the field -------------------------
# The ten Mod Settings fields are a surface, not state a caller may reach into: the menu writes
# them, AiNpcUtilities names one question per field and answers each with the field's own
# default while the service is not up yet. A call site that reads the field instead is a call
# site that has to know about the not-yet case, and every one of them was written as though it
# did not exist.
#
# Per read rather than per file, unlike N+4, and with no allowlist at all -- because the leak
# this catches happened INSIDE an allowed file. AiNpcModSettings declares the fields, and
# AiNpcUtilities is the only reader; anything else naming one is asking the wrong thing of the
# wrong object, whatever else that file is allowed to do.
$settingFields = @("aiModel", "conversationType", "retryActions", "logging", "debugMode",
                   "memoryEnabled", "memoryFacts", "dailyLimitEnabled", "dailyTokens",
                   "unpromptedEnabled")
$fieldReaders = @("AiNpcModSettings.reds", "AiNpcUtilities.reds")
$fieldStrays = @()
$fieldHits = 0
foreach ($f in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $lineNo++
        if ($line.TrimStart().StartsWith("//")) { continue }
        foreach ($field in $settingFields) {
            # A qualified read: <something>.<field>, which is what reaching past the accessor
            # looks like. The declarations themselves are `public let <field>`, unqualified.
            if ($line -match "[A-Za-z_)\]]\s*\.\s*$field\b") {
                if ($fieldReaders -contains $f.Name) {
                    $fieldHits++
                } else {
                    $fieldStrays += "$($f.Name):$lineNo  $($line.Trim())"
                }
            }
        }
    }
}
if ($fieldHits -eq 0) {
    Report-Fail "a setting is asked by name, never read off the field" `
        "no qualified read found in AiNpcUtilities - the rule is reading nothing"
} elseif ($fieldStrays.Count -gt 0) {
    Report-Fail "a setting is asked by name, never read off the field" `
        (($fieldStrays -join "`n") + "`nAsk the named accessor in AiNpcUtilities.reds; add one if the question has no name yet.")
} else {
    Report-Pass "a setting is asked by name, never read off the field ($fieldHits read(s) in $($fieldReaders.Count) file(s))"
}

# --- N+5. Hooks report, they never decide ----------------------------------------------
# The companion to N+4. N+4 says the system is not READ ambiently, and allows AiNpcHooks.reds
# because the game calls it -- which is what let a wrapper on
# PhoneDialerLogicController.OnAllElementsSpawned read `unread`, read `IsOnContactsTab()`, and
# conclude "open the chat", so pressing D to switch tabs opened the mod's chat by itself.
#
# The defect is not the two reads. It is that a callback firing when WIDGETS SPAWN was allowed
# to infer that the player wanted something, and no guard fixes that: a spawn event does not
# carry an intention, whatever you test alongside it. So the rule is about the shape of the
# file rather than about any one condition --
#
#     every call AiNpcHooks.reds makes on the system is GetAiNpcSystem().Report*(...)
#
# -- and the decisions live one level up, in AiNpcSystem, next to the state machine that can
# tell a tab switch from the phone being taken out. Adding a non-Report method call here is
# what a future auto-open would look like on its way back in, and this is where it stops.
$hookFile = $files | Where-Object { $_.Name -eq "AiNpcHooks.reds" }
if (-not $hookFile) {
    Report-Fail "hooks report, they never decide" "AiNpcHooks.reds not found - the rule is reading nothing"
} else {
    $hookCode = Read-Code $hookFile.FullName
    $hookCalls = ([regex]'GetAiNpcSystem\(\)\.([A-Za-z_]\w*)').Matches($hookCode)
    $hookStrays = @()
    foreach ($m in $hookCalls) {
        $member = $m.Groups[1].Value
        if ($member -notlike "Report*") { $hookStrays += $member }
    }
    if ($hookCalls.Count -eq 0) {
        Report-Fail "hooks report, they never decide" `
            "no GetAiNpcSystem() call in AiNpcHooks.reds - the rule is reading nothing"
    } elseif ($hookStrays.Count -gt 0) {
        Report-Fail "hooks report, they never decide" `
            (("decides instead of reporting: " + (($hookStrays | Sort-Object -Unique) -join ", ")) + `
             "`nA hook says what happened. Name a Report* method on AiNpcSystem and decide there.")
    } else {
        Report-Pass "hooks report, they never decide ($($hookCalls.Count) report(s))"
    }
}

# --- N+6. Typed text is measured in characters, never in bytes -------------------------
# StrLen, StrLeft, StrRight and StrMid count BYTES. An accent is two of them, so a backspace
# written as StrLeft(text, StrLen(text) - 1) removes half a character and leaves the lead byte
# inside the string. Nothing reports it: the compiler is happy, the field looks right, and the
# broken byte is filed into the journal and re-sent with every later request for that contact,
# which fails at status 0 with no log line anywhere.
#
# The rule is scoped by what a file DOES rather than by its name: a file that reads characters
# off key events is a hand-rolled text field, and that is the one place where the byte-counting
# version looks correct. Any future surface that assembles its own input is caught the day it
# is written, without anyone remembering to add it here.
#
# Everywhere else keeps the byte functions on purpose -- trimming a trailing "\n" is a byte and
# a character at once, and parsing json is byte work.
$byteOps   = 'StrLen|StrLeft|StrRight|StrMid'
$typedText = @()
foreach ($f in $files) {
    $code = Read-Code $f.FullName
    if ($code -notmatch 'IsCharacter\(\)|GetCharacter\(\)') { continue }

    $offenders = @()
    foreach ($line in ($code -split "`n")) {
        # UTF8StrLen and friends carry the same names with a prefix; a bare match would flag
        # the fix itself.
        $stripped = $line -replace 'UTF8Str\w*', ''
        # "is it empty" is byte-safe and stays: a string of zero bytes is a string of zero
        # characters, whatever is in it. Only measuring and CUTTING are the bug.
        $stripped = $stripped -replace '(Equals|NotEquals)\s*\(\s*StrLen\s*\([^()]*\)\s*,\s*0\s*\)', ''
        if ($stripped -match "\b($byteOps)\s*\(") { $offenders += $line.Trim() }
    }
    if ($offenders.Count -gt 0) {
        $typedText += "$($f.Name): " + ($offenders -join " | ")
    }
}
if ($typedText.Count -gt 0) {
    Report-Fail "typed text is measured in characters" `
        (($typedText -join "`n") + `
         "`nThis file assembles text from key events, so its strings can hold multi-byte characters." + `
         "`nUse AiNpcUtf8Len / AiNpcUtf8Left / AiNpcUtf8Right / AiNpcUtf8DropLast (AiNpcUtf8.reds).")
} else {
    Report-Pass "typed text is measured in characters"
}

# --- N. The CET window's provider buttons come from DescribeProviders ------------------
# The overlay reads the provider names out of DescribeProviders(), taking the first word of
# each line, rather than holding a copy of the list: a Lua array beside a REDscript enum is an
# agreement between two languages, and one that went stale the day the CLI lanes arrived.
#
# So: every line of that text must start with a real AiNpcProvider member, and every member
# must appear. A provider added to the enum and forgotten here is a lane the player cannot
# select from the only window that can switch lanes without a restart.
#
# Indented continuation lines are skipped by the Lua side (^%S+ does not match a leading
# space) and are skipped here for the same reason: wrapping a description is allowed.
$providerEnum = [regex]::Match($allText, '(?s)enum AiNpcProvider\s*\{(?<body>.*?)\}')
$describe = [regex]::Match($allText,
    '(?s)func DescribeProviders\(\)[^\{]*\{(?<body>.*?)\n    \}')
$providerIssues = @()
if (-not $providerEnum.Success) {
    $providerIssues += "enum AiNpcProvider not found - this rule is reading nothing"
} elseif (-not $describe.Success) {
    $providerIssues += "DescribeProviders() not found - the CET window would have no buttons"
} else {
    $members = @()
    foreach ($m in [regex]::Matches($providerEnum.Groups["body"].Value, '(?m)^\s*(\w+)\s*=')) {
        $members += $m.Groups[1].Value
    }

    # The literal as the player sees it: the quoted pieces joined, then cut on the \n the
    # source writes as two characters.
    $literal = ""
    foreach ($m in [regex]::Matches($describe.Groups["body"].Value, '"((?:[^"\\]|\\.)*)"')) {
        $literal += $m.Groups[1].Value
    }
    $named = @()
    foreach ($line in ($literal -split '\\n')) {
        $first = [regex]::Match($line, '^(\S+)')
        if ($first.Success) { $named += $first.Groups[1].Value }
    }

    foreach ($name in $named) {
        if ($members -notcontains $name) {
            $providerIssues += "DescribeProviders lists '$name', which is not an AiNpcProvider member"
        }
    }
    foreach ($member in $members) {
        if ($named -notcontains $member) {
            $providerIssues += "$member has no line in DescribeProviders - the CET window cannot offer it"
        }
    }
}
if ($providerIssues.Count -gt 0) {
    Report-Fail "the CET window can offer every provider" ($providerIssues -join "`n")
} else {
    Report-Pass "the CET window can offer every provider"
}

# --- N+7. Everything docs\API.md offers is declared under api\ --------------------------
# api\AiNpcApi.reds opens by saying the folder IS the boundary: what is not in it is an
# internal that moves without warning. It was not true. Twelve names shown to integrators were
# declared elsewhere -- including AiNpcOpenClient and AiNpcWhenReady, the two doors everything
# else goes through -- so the promise "read one folder to see the contract" did not hold, and
# nothing said so.
#
# Anchored on CODE, not on prose: a name inside a fenced block or a signature table is being
# shown as something to call, while the same name in a sentence may be explaining where a
# default comes from. AiNpcBuiltinWorldLore is the second kind and deliberately out of scope --
# widening this to every backticked word would put the whole internals of the prompt builder
# under api\ to satisfy a paragraph.
#
# Nothing here checks the reverse direction. A function under api\ that the document forgot is
# a documentation gap, not a broken boundary, and conflating the two would make one rule fail
# for two unrelated reasons.
$apiDoc = Join-Path $root "docs\API.md"
$apiFiles = @(Get-ChildItem (Join-Path $modSrc "api\*.reds"))
$apiText = ""
foreach ($f in $apiFiles) { $apiText += (Read-Code $f.FullName) + "`n" }

# The one name a consumer calls that CANNOT live under api\: the head of ai_npc's own transfer
# command belongs beside the pattern that declares it and the parser that recognises it, and
# rule 9 above fails the moment it appears anywhere else. A contract name pinned outside the
# folder by another invariant is a decision, and this is the list of them.
$apiElsewhere = @("AiNpcTransferHead")

$docLines = [System.IO.File]::ReadAllLines($apiDoc)
$inFence = $false
$offered = @{}
foreach ($line in $docLines) {
    if ($line.TrimStart().StartsWith('```')) { $inFence = -not $inFence; continue }
    # A table row is a signature list when it is a row at all: | `AiNpcX(...)` | meaning |
    $isSignatureRow = $line.TrimStart().StartsWith('|') -and $line -match '`[^`]*AiNpc\w+\s*\('
    if (-not ($inFence -or $isSignatureRow)) { continue }
    foreach ($m in [regex]::Matches($line, '\b(AiNpc\w+)\s*\(')) {
        $offered[$m.Groups[1].Value] = $true
    }
}

$outside = @()
foreach ($name in ($offered.Keys | Sort-Object)) {
    if ($apiElsewhere -contains $name) { continue }
    if ($apiText -match ("(func|class)\s+" + [regex]::Escape($name) + "\b")) { continue }
    # Not declared under api\ -- say whether it is declared at all, because "documented and
    # never written" and "documented and misplaced" need different fixes.
    if ($allText -match ("(func|class)\s+" + [regex]::Escape($name) + "\b")) {
        $outside += "$name is offered in docs\API.md but declared outside api\"
    } else {
        $outside += "$name is offered in docs\API.md and declared nowhere"
    }
}
if ($offered.Count -eq 0) {
    Report-Fail "the contract is declared under api\" `
        "no callable name found in docs\API.md code blocks - the rule is reading nothing"
} elseif ($outside.Count -gt 0) {
    Report-Fail "the contract is declared under api\" `
        (($outside -join "`n") + "`nMove the declaration, or stop showing it as a call.")
} else {
    Report-Pass "the contract is declared under api\ ($($offered.Count) name(s) offered)"
}

# --- N+7b. Every installer answer is filled by the packager -----------------------------
# AiNpcInstallPreset.reds is a set of functions returning "", and the archive only carries an
# answer for the ones package.ps1 rewrites. Adding a fourth question is two edits in two
# languages, and forgetting the second one is silent in every direction: the mod compiles, the
# packager succeeds, the installer offers the choice, and the game applies the empty default.
#
# The packager checks the reverse -- Set-PresetAnswer throws on a function it cannot find, so a
# rename is caught. This is the direction it cannot see.
$presetFile = Join-Path $modSrc "AiNpcInstallPreset.reds"
$packager   = Join-Path $PSScriptRoot "package.ps1"
if (-not (Test-Path $presetFile) -or -not (Test-Path $packager)) {
    Report-Fail "every installer answer is filled by the packager" "AiNpcInstallPreset.reds or package.ps1 not found - the rule is reading nothing"
} else {
    $presetFns = @([regex]::Matches(
        [System.IO.File]::ReadAllText($presetFile),
        '(?m)^func\s+(AiNpcInstallPreset\w+)\s*\(') | ForEach-Object { $_.Groups[1].Value })
    $packagerText = [System.IO.File]::ReadAllText($packager)
    $unfilled = @($presetFns | Where-Object { $packagerText -notmatch [regex]::Escape($_) })
    if ($presetFns.Count -eq 0) {
        Report-Fail "every installer answer is filled by the packager" "no AiNpcInstallPreset* function found - the rule is reading nothing"
    } elseif ($unfilled.Count -gt 0) {
        Report-Fail "every installer answer is filled by the packager" `
            (($unfilled -join ", ") + "`nDeclared in AiNpcInstallPreset.reds and never named by package.ps1: every preset would ship it empty.")
    } else {
        Report-Pass "every installer answer is filled by the packager ($($presetFns.Count) answer(s))"
    }
}

# --- N+8. The export surface does not grow ----------------------------------------------
# `public` in a module means EXPORTED, not "visible to the rest of ai_npc" -- declarations are
# shared between files of one module either way. So every `public` outside api\ widens the
# surface a consumer can reach past the contract, and the count has form: api\AiNpcApi.reds
# measured 351 funcs and 63 classes on 2026-08-22 and called that an accident. It had roughly
# doubled by 2026-08-28, with the facade in place the whole time.
#
# Top-level declarations only -- the regex is anchored at column 0, where this codebase writes
# them, so a `public func` method inside a class is not counted. A method's reachability is its
# class's to decide, and folding the two together would make the number mean nothing and move
# for the wrong reasons.
#
# A per-file budget rather than one total, and a ratchet rather than a target. The cleanup is a
# separate pass and cannot be validated here: the plugin looks AiNpcCliDeliver up by qualified
# name and CET reaches AiNpc.AiNpcConversationStore from Lua, so whether an unexported
# declaration stays reachable through RTTI is a question only a launched game answers. Six
# hundred visibility changes made blind is how a mod stops booting with a message that names
# the mod and not the cause.
#
# What the ratchet buys meanwhile: the number cannot drift upward while nobody is looking, and
# each verified batch lowers a line in tools\export-budget.txt.
$budgetFile = Join-Path $PSScriptRoot "export-budget.txt"
$exportCounts = @{}
foreach ($f in $files) {
    if ($f.FullName -like "*\api\*") { continue }
    $text = Read-Code $f.FullName
    $n = ([regex]::Matches($text, '(?m)^public\s+(static\s+)?(func|abstract class|native class|class)\s')).Count
    if ($n -gt 0) { $exportCounts[$f.Name] = $n }
}
if (-not (Test-Path $budgetFile)) {
    $lines = @("# Exports outside api\ -- see tools\lint.ps1 rule N+8.",
               "# One line per file: <count> <file>. A count may go DOWN and never up.",
               "# Regenerate a lowered line by hand after checking the game still boots.")
    foreach ($name in ($exportCounts.Keys | Sort-Object)) { $lines += "$($exportCounts[$name]) $name" }
    [System.IO.File]::WriteAllLines($budgetFile, $lines)
    Report-Pass "the export surface does not grow (budget written: $($exportCounts.Count) file(s))"
} else {
    $budget = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($budgetFile)) {
        if ($line.TrimStart().StartsWith("#") -or $line.Trim() -eq "") { continue }
        $parts = $line.Trim() -split '\s+', 2
        $budget[$parts[1]] = [int]$parts[0]
    }
    $grown = @()
    $total = 0
    foreach ($name in ($exportCounts.Keys | Sort-Object)) {
        $now = $exportCounts[$name]
        $total += $now
        if (-not $budget.ContainsKey($name)) {
            $grown += "$name is new, with $now export(s) - add it to tools\export-budget.txt if they are all contract"
        } elseif ($now -gt $budget[$name]) {
            $grown += "$name has $now export(s), budgeted $($budget[$name])"
        }
    }
    if ($grown.Count -gt 0) {
        Report-Fail "the export surface does not grow" `
            (($grown -join "`n") + "`nInside one module `public` means exported. Drop it, or budget it on purpose.")
    } else {
        Report-Pass "the export surface does not grow ($total export(s) outside api\, budgeted)"
    }
}

Write-Output ""
if ($script:failures -gt 0) {
    Write-Output "$($script:failures) check(s) failed."
    exit 1
}
Write-Output "All checks passed."
exit 0
