# Builds a distributable zip for the ai_npc mod.
# The archive mirrors the game folder layout, so users unzip it at the Cyberpunk 2077 root.
#
# Produces two identical archives in dist\:
#   ai_npc-<version>.zip   versioned, for archiving and for uploading to Nexus
#   ai_npc.zip             stable name, for installing into Vortex (see the note below)
#
# Usage: powershell -File tools\package.ps1 [-Config Release|Debug] [-Version 0.7.0]
#                                            [-SkipPlugin] [-NoStableCopy]
#
# The version comes from AiNpcVersion() in the sources; -Version only asserts it.
#
# TWO BUILDS, and the difference is one folder:
#
#   Release  ai_npc-<version>.zip         what goes on Nexus. The self-tests are dropped:
#                                         the whole r6\scripts\ai_npc\tests\ folder.
#   Debug    ai_npc-<version>-debug.zip   what gets tested here. Tests run at startup and
#                                         write r6\storages\AiNpc\test-results.json, which
#                                         is what tools\test.ps1 reads.
#
# Release is the default, deliberately: the build that leaves this machine is the one that
# must not need a flag to be correct. Forgetting -Config Debug costs a rebuild; forgetting a
# hypothetical -Release would put 5000 lines of assertions on Nexus.
#
# Nothing else changes between the two. AiNpcSelfTest.reds ships in both builds and asks
# @if(ModuleExists("AiNpc.TestSuite")) which one it is in, so dropping the folder is a
# deletion and not an edit -- no production source is rewritten on the way into the zip.
#
# THE MARKER LIVES IN THE FOLDER. tests\AiNpcTestSuite.reds declares the module that answers
# that question, so it leaves with the assertions and cannot be forgotten. Left outside, it
# would survive the release build, the suite would compile out of reach, and the mod would
# report "0 tests" -- which reads exactly like a mod that never started.

param(
    [ValidateSet("Release", "Debug")]
    [string]$Config = "Release",
    [string]$Version = "",
    [switch]$SkipPlugin,
    [switch]$NoStableCopy
)

$ErrorActionPreference = "Stop"

$root    = Resolve-Path "$PSScriptRoot\.."
$srcDir  = Join-Path $root "src"
$distDir = Join-Path $root "dist"

if (-not (Test-Path $srcDir)) { throw "Missing src directory: $srcDir" }

# The version lives in AiNpcVersion() in the sources, not in this parameter. Nothing reads an
# archive's name once the mod is installed -- Vortex included -- so a version that exists only
# as a file name cannot be checked against anything later; -Version only asserts what the
# sources already say.
#
# Searched across every source file rather than read from a named one, and refused if it is
# declared twice: exactly one answer to "which build is this?".
$sourceFiles = Get-ChildItem (Join-Path $srcDir "r6\scripts") -Recurse -Filter *.reds
$versionHits = @()
foreach ($f in $sourceFiles) {
    $m = [regex]::Match(
        [System.IO.File]::ReadAllText($f.FullName),
        '(?s)func AiNpcVersion\(\)[^\{]*\{\s*return\s*"([^"]+)"')
    if ($m.Success) { $versionHits += [pscustomobject]@{ File = $f.Name; Version = $m.Groups[1].Value } }
}
if ($versionHits.Count -eq 0) {
    throw "Could not find AiNpcVersion() in any source file - packaging would produce an unidentifiable build."
}
if ($versionHits.Count -gt 1) {
    throw ("AiNpcVersion() is declared in " + $versionHits.Count + " files (" +
        (($versionHits | ForEach-Object { $_.File }) -join ", ") +
        ") - the build would have no single identity.")
}
$versionFile   = $versionHits[0].File
$sourceVersion = $versionHits[0].Version

if ($Version -and $Version -ne $sourceVersion) {
    throw "Version mismatch: -Version $Version, but AiNpcVersion() says $sourceVersion. Edit AiNpcVersion() in $versionFile - it is the source of truth."
}
$Version = $sourceVersion

# The configuration is in the file name, not only in the console output that scrolled away.
# A zip on disk has to be able to say what it is a week later, when it is about to be
# uploaded: "ai_npc-0.7.0.zip" is the release, anything with -debug is not.
$suffix  = if ($Config -eq "Debug") { "-debug" } else { "" }
$stage   = Join-Path $env:TEMP "ai_npc-package-$Version$suffix"
$zipPath = Join-Path $distDir "ai_npc-$Version$suffix.zip"

# Refuse to ship credentials.
#
# Across every script folder, not just ai_npc: the mod ships a second one to control
# @wrapMethod ordering, and a check that only looked at the first would pass while shipping a
# key from the second. Enumerated recursively rather than globbed, so a folder added a level
# down is covered the day it appears.
$scriptFiles = Get-ChildItem (Join-Path $srcDir "r6\scripts") -Recurse -Filter *.reds
$leaks = $scriptFiles | Select-String -Pattern 'sk-proj-|sk-or-v1-' -ErrorAction SilentlyContinue
if ($leaks) {
    $leaks | ForEach-Object { Write-Warning "$($_.Path):$($_.LineNumber)" }
    throw "An API key is hardcoded in the sources. Move it to settings.json before packaging."
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

# --- REDscript ---
Copy-Item (Join-Path $srcDir "r6") $stage -Recurse -Force

# The self-tests are dev scaffolding: ~5000 lines of assertions the player never reads,
# compiled at every game start. A release build drops the whole tests\ folder from the staging
# copy -- src\ is untouched, and nothing in the mod refers to them, so this is the whole of it.
#
# A folder rather than a list of names: a test file added under tests\ leaves the release build
# alone, where a name that nobody thought to add to a list used to ship 5000 lines of assertions
# to every player. The two checks below are what a list gave for free and a folder does not --
# that the folder is there at all, and that the marker module went with it.
$testDir = Join-Path $stage "r6\scripts\ai_npc\tests"
if ($Config -eq "Release") {
    if (-not (Test-Path $testDir)) {
        throw "The self-tests are not where the release build expects them ($testDir). The folder moved or was renamed - find it before shipping, because the check below can only prove a folder is absent, not that the tests are."
    }
    if (-not (Test-Path (Join-Path $testDir "AiNpcTestSuite.reds"))) {
        throw "AiNpcTestSuite.reds is not in $testDir. It declares module AiNpc.TestSuite, which AiNpcSelfTest.reds asks about: left outside the folder it survives the release build, the suite compiles out, and the mod reports 0 tests instead of shipping without them."
    }
    Remove-Item $testDir -Recurse -Force
}

# --- CET mod (the journal window) ---
# Ships inside the same archive, at the game-folder path CET reads, because the pipeline is
# package -> install in Vortex: anything left outside src\ is not part of the mod and never
# reaches the game. It costs nothing where CET is absent -- that folder is then simply never
# read -- and it is exactly the situation a player needs it in (a lost savegame) that they
# cannot be asked to go and fetch a loose file for.
$binDir = Join-Path $srcDir "bin"
if (Test-Path $binDir) {
    Copy-Item $binDir $stage -Recurse -Force
}

# --- The site icon (one .archive, holding one icon) ---
# Repacked from source\archive\ every time, so the zip cannot carry an icon older than the
# atlas it was built from. This throws rather than warns when the depot tree is missing: an
# archive that quietly fails to build is a site whose icon is a blank square, and nothing
# downstream would say so.
& (Join-Path $PSScriptRoot "build-archive.ps1")

$archiveDir = Join-Path $srcDir "archive"
if (Test-Path $archiveDir) {
    Copy-Item $archiveDir $stage -Recurse -Force
}

# --- RED4ext plugin (the CLI lanes; OpenRouter works without it) ---
#
# One file: the plugin runs the CLI and returns its output, so there is no bridge, no port and
# no launch argument. See docs\ARCHITECTURE.md.
#
# -SkipPlugin still produces a usable archive: a player on OpenRouter never calls into the
# DLL. What they cannot do is select a CLI lane, and the mod says so when they try.
$dll = Join-Path $root "plugin\build\ai_npc.dll"
if (-not $SkipPlugin) {
    if (-not (Test-Path $dll)) {
        throw "plugin\build\ai_npc.dll not found. Run plugin\build.ps1 first, or pass -SkipPlugin."
    }

    $pluginDir = Join-Path $stage "red4ext\plugins\ai_npc"
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
    Copy-Item $dll $pluginDir -Force
}

# --- FOMOD installer + the provider presets it chooses between ---
#
# The installer is the one part of this archive that is NOT a game file: Vortex and MO2 read
# fomod\ModuleConfig.xml out of the archive and never deploy it. That is why it lives in
# fomod\ at the repo root rather than under src\ -- the rule that everything shipped lives at
# its real game path still holds, and this has no game path.
#
# A FOMOD can only decide which files get copied, so the provider question is answered by a
# file: one variant of AiNpcInstallPreset.reds per provider, generated here from the shipped
# default rather than kept as five near-identical files in the repo. They differ by one
# returned string, and a hand-maintained copy of a file that must stay in sync with the real
# one is a copy that will not.
$fomodSrc = Join-Path $root "fomod"
if (Test-Path $fomodSrc) {
    Copy-Item $fomodSrc $stage -Recurse -Force

    $presetSource = Join-Path $srcDir "r6\scripts\ai_npc\AiNpcInstallPreset.reds"
    $presetText   = [System.IO.File]::ReadAllText($presetSource)

    # Two answers now, so the empty string is filled per FUNCTION rather than per literal:
    # `return "";` appears once for the provider and once for the model, and a plain string
    # replacement would write the provider into both.
    function Set-PresetAnswer([string]$text, [string]$fn, [string]$value) {
        $pattern = "(?s)(func\s+$fn\(\)\s*->\s*String\s*\{\s*return\s+)`"`""
        if ($text -notmatch $pattern) {
            throw "AiNpcInstallPreset.reds no longer has an empty '$fn'; the installer presets cannot be generated."
        }
        return [regex]::Replace($text, $pattern, "`${1}`"$value`"")
    }

    # UTF-8 without BOM, written the only way that is safe here: Set-Content would re-encode
    # and add one, and redscript files in this repo are UTF-8 no-BOM by rule.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    # A provider name must match AiNpcProviderFromName, which reads the string back: a preset
    # naming a provider that does not exist is ignored in silence rather than refused.
    #
    # Only the providers the INSTALLER offers. OpenAI is redundant with OpenRouter, which
    # proxies the same models for one fewer key; CodexCli has never been run in game and its
    # safe-for-work tier is unmeasured (docs\ARCHITECTURE.md). Both stay selectable in
    # Mod Settings, and a preset folder fomod\ModuleConfig.xml never names would be dead
    # weight in every archive.
    #
    # THREE OpenRouter answers, one per price. That is the question the installer can answer
    # and Mod Settings cannot answer for a player who has not launched yet. The model ids are
    # the measured recommendation of docs\MODEL_BENCH.md; changing one here changes what a
    # fresh install runs, so the two are read together.
    #
    # Unprompted is answered only where the answer differs from the shipped default. The free
    # lane is that one place: a character writing first spends a request the player never
    # typed, and the free pool answers HTTP 429 more often than it answers, so the feature
    # would show up as popups that never come. Everything else leaves the field empty and
    # inherits the default.
    $presets = @(
        @{ Folder = "OpenRouter-Free";     Provider = "OpenRouter"; Model = "google/gemma-4-31b-it:free"; Unprompted = "off" },
        @{ Folder = "OpenRouter-Cheapest"; Provider = "OpenRouter"; Model = "qwen/qwen3-235b-a22b-2507";  Unprompted = "" },
        @{ Folder = "OpenRouter-Tiers";    Provider = "OpenRouter"; Model = "meta-llama/llama-4-maverick"; Unprompted = "" },
        @{ Folder = "ClaudeCli";           Provider = "ClaudeCli";  Model = "";                            Unprompted = "" }
    )
    foreach ($preset in $presets) {
        $target = Join-Path $stage "presets\$($preset.Folder)\r6\scripts\ai_npc"
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        $text = Set-PresetAnswer $presetText "AiNpcInstallPresetProvider" $preset.Provider
        if ($preset.Model) {
            $text = Set-PresetAnswer $text "AiNpcInstallPresetOpenRouterModel" $preset.Model
        }
        if ($preset.Unprompted) {
            $text = Set-PresetAnswer $text "AiNpcInstallPresetUnprompted" $preset.Unprompted
        }
        [System.IO.File]::WriteAllText((Join-Path $target "AiNpcInstallPreset.reds"), $text, $utf8NoBom)
    }

    # The list above and the installer have to name the same folders, and neither says so: a
    # pattern pointing at a folder nobody generates installs no preset, and a folder nobody
    # points at rides in every archive doing nothing. Both are silent, and both end with a
    # player on a provider they did not pick. Read out of the staged XML rather than trusted.
    $named = @([regex]::Matches(
        [System.IO.File]::ReadAllText((Join-Path $stage "fomod\ModuleConfig.xml")),
        'source="presets\\([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $built = @($presets | ForEach-Object { $_.Folder } | Sort-Object -Unique)
    $orphanPattern = @($named | Where-Object { $built -notcontains $_ })
    $orphanFolder  = @($built | Where-Object { $named -notcontains $_ })
    if ($orphanPattern.Count -gt 0) {
        throw "fomod\ModuleConfig.xml installs presets nothing generates: $($orphanPattern -join ', ')"
    }
    if ($orphanFolder.Count -gt 0) {
        throw "presets generated but never installed by fomod\ModuleConfig.xml: $($orphanFolder -join ', ')"
    }

    # The instructions, in the one place a player can still read them tomorrow.
    #
    # Vortex renders a FOMOD description as plain text in a label: measured in its own bundle,
    # so no link on that screen is clickable, and the screen cannot be reopened once the
    # install is done. Every url the installer shows is therefore repeated in this file, which
    # lands next to REDprelauncher.exe where it can be copied from. It travels in guide\ rather
    # than loose at the archive root because the FOMOD copies folders, and a file at the root
    # is installed by nobody.
    $guideSrc = Join-Path $srcDir "AI NPC - read me.txt"
    if (-not (Test-Path $guideSrc)) {
        throw "Missing $guideSrc - the installer points every provider page at a file the archive would not contain."
    }
    $guideDir = Join-Path $stage "guide"
    New-Item -ItemType Directory -Path $guideDir -Force | Out-Null
    Copy-Item $guideSrc $guideDir -Force

    # A scripts-only build has no red4ext\ folder, and a FOMOD option pointing at a folder
    # that is not in the archive is an install-time error rather than a skipped option. Only
    # that one line is dropped, from the copy in the staging folder: the local model option
    # itself stays, because the provider preset is what it is really for and a local server
    # started by hand needs no plugin at all. The file in the repo keeps the line.
    if ($SkipPlugin) {
        $configPath = Join-Path $stage "fomod\ModuleConfig.xml"
        $fomodXml = [System.IO.File]::ReadAllText($configPath)
        $fomodXml = [regex]::Replace($fomodXml,
            '[ \t]*<folder source="red4ext"[^>]*/>\r?\n', '')
        [System.IO.File]::WriteAllText($configPath, $fomodXml, $utf8NoBom)
        Write-Output "  (FOMOD: bridge plugin dropped from the local model option - none in this build)"
    }

    # Parsed, not just copied. Vortex reads ModuleConfig.xml before it writes a single file, so
    # anything malformed aborts the install entirely -- "Invalid installer script", no files,
    # and the mod page gets the blame while the archive itself is perfectly good. A double dash
    # inside an XML comment is the way it happens here.
    #
    # Checked on the STAGING copy rather than on fomod\ in the repo, because this script edits
    # it (the -SkipPlugin line above) and it is the edited copy that ships. lint.ps1 checks the
    # repo copy, which catches the same mistake seconds after it is typed.
    foreach ($xmlName in @("ModuleConfig.xml", "info.xml")) {
        $xmlPath = Join-Path $stage "fomod\$xmlName"
        if (-not (Test-Path $xmlPath)) { throw "fomod\$xmlName is missing from the staging folder - the installer would not run." }
        try {
            [xml](Get-Content $xmlPath -Raw) | Out-Null
        } catch {
            throw "fomod\$xmlName is not valid XML, so Vortex would refuse the whole install: $($_.Exception.Message)"
        }
    }

    # Valid XML is not the same as an installable one. Every <folder source="..."> has to exist
    # in the staging folder: a source that does not is an install-time error at the player's
    # end rather than an option that quietly does nothing.
    #
    # Not $config: that is this script's own -Config parameter, and PowerShell variable names
    # are case insensitive, so assigning here failed its ValidateSet.
    $fomodConfig = [xml](Get-Content (Join-Path $stage "fomod\ModuleConfig.xml") -Raw)
    $missingSources = @()
    foreach ($folder in $fomodConfig.SelectNodes("//folder")) {
        $source = $folder.GetAttribute("source")
        if ($source -and -not (Test-Path (Join-Path $stage $source))) {
            $missingSources += $source
        }
    }
    if ($missingSources.Count -gt 0) {
        throw ("The installer points at folder(s) the archive does not contain: " +
            (($missingSources | Sort-Object -Unique) -join ", ") +
            " - the install would fail after the player has chosen.")
    }
}

if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Kept until the checks below have read the installer out of it: they verify the zip against
# the ModuleConfig.xml that actually went into it, not the one in the repo.
$stageKeep = $stage

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -CompressionLevel Optimal

# The archive is checked inside the zip rather than in src\, because that is where the
# failure lives: a file can be at the right path in the repo and absent from what ships.
# The FOMOD also has to list archive\ in its requiredInstallFiles, or the file travels in
# the zip and is never installed -- the same symptom, one step later.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = $zip.Entries | ForEach-Object { $_.FullName.Replace("\", "/") }
} finally {
    $zip.Dispose()
}
if ($names -notcontains "archive/pc/mod/ai_npc.archive") {
    throw "The zip is missing archive/pc/mod/ai_npc.archive - the AGENT LINK icon would not ship."
}

# The installer, and every folder it names.
#
# A FOMOD that points at a folder the zip does not carry is an install-time error rather than
# a skipped option, and it surfaces on the player's machine. The list is READ FROM the
# installer instead of being repeated here, so an option added is an option checked.
foreach ($required in @("fomod/ModuleConfig.xml", "fomod/info.xml")) {
    if ($names -notcontains $required) { throw "The zip is missing $required - Vortex would install it as a plain archive, with no provider question." }
}

$installer = [xml](Get-Content (Join-Path $stageKeep "fomod\ModuleConfig.xml") -Raw)
$missing = @()
foreach ($folder in $installer.SelectNodes("//folder")) {
    $source = $folder.GetAttribute("source").Replace("\", "/").TrimEnd("/")
    if (-not ($names | Where-Object { $_ -eq $source -or $_.StartsWith("$source/") })) {
        $missing += $source
    }
}
if ($missing.Count -gt 0) {
    throw ("The installer offers folder(s) the zip does not contain: " + ($missing -join ", ") +
        ". Vortex fails the install rather than skipping the option.")
}

# Both directions, because both failures are silent. A release that still carries the tests
# ships scaffolding to players; a debug build without them reports "0 tests" from
# tools\test.ps1, which reads exactly like a mod that never started.
foreach ($name in $testFiles) {
    $entry = "r6/scripts/ai_npc/$name"
    if ($Config -eq "Release" -and ($names -contains $entry)) {
        throw "Release build still contains $entry."
    }
    if ($Config -eq "Debug" -and ($names -notcontains $entry)) {
        throw "Debug build is missing $entry - the self-tests would never run and test.ps1 would report nothing."
    }
}

Remove-Item $stageKeep -Recurse -Force

$size = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
Write-Output "Built $zipPath ($size KB)   [$Config]"
if ($Config -eq "Release") {
    Write-Output "  (self-tests dropped - this is the build to upload)"
} else {
    Write-Output "  (self-tests included - do NOT upload this one; run tools\test.ps1 after a game launch)"
}
if ($SkipPlugin) { Write-Output "  (scripts only - no RED4ext plugin)" }

# A second copy under a stable name, for installing into Vortex.
#
# Vortex derives a manually installed mod's identity from the archive file name -- there
# is no version attribute, no modId, nothing read from inside the archive (verified in
# Vortex's own state db). So ai_npc-0.6.2.zip and ai_npc-0.7.0.zip install as two
# unrelated mods, and Vortex never offers to replace one with the other: the "already
# installed" prompt keys off that derived identity, and two different names never collide.
#
# Keeping the name fixed is what makes successive builds collide on purpose, which is what
# produces the Replace prompt. The version is not lost by dropping it from the file name --
# it is compiled into AiNpcVersion() and logged at every startup, which is the only place
# it could be checked after installation anyway.
#
# ONE stable name for both configurations, and it must stay that way: ai_npc.zip and
# ai_npc-debug.zip would be two unrelated mods to Vortex, deployed side by side, and the
# duplicate .reds files would then fight -- the "stale file in the game folder" failure, with
# both copies live. So this slot holds whatever was built last, and the line below says which.
if (-not $NoStableCopy) {
    $stablePath = Join-Path $distDir "ai_npc.zip"
    Copy-Item $zipPath $stablePath -Force
    Write-Output "Built $stablePath ($size KB)   [$Config - install this one in Vortex -> Replace]"
}
