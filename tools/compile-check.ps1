# Offline type-check: compiles ai_npc with the redscript compiler, against the VANILLA
# script bundle and only its declared dependencies -- without launching the game and
# without touching the game's script cache.
#
# This catches what a text linter cannot: unresolved functions, wrong argument types,
# missing enum cases, duplicate declarations, and accidental reliance on symbols that
# happen to be provided by some other mod installed locally.
#
# The terminal site is OPTIONAL: everything BrowserExtension-shaped sits behind
# @if(ModuleExists("BrowserExtension.System")), so the mod has two valid shapes and only one
# of them is compiled by a single run. -WithoutBrowserExtension compiles the other. Both must
# pass before a release -- an @if branch that nobody compiles is a branch that rots, and its
# failure mode is a compile error in the player's game, which takes down every redscript mod
# installed, not just this one.
#
# The self-tests are OPTIONAL in the same way, for a different reason: tools\package.ps1
# drops the whole r6\scripts\ai_npc\tests\ folder from a release build (see its header), which
# turns the @if(ModuleExists("AiNpc.TestSuite")) seam in AiNpcSelfTest.reds over to its no-op branch.
# -WithoutTests compiles that shape -- the one that actually ships.
#
# Usage: powershell -File tools\compile-check.ps1 [-GameDir "D:\Jeux\Cyberpunk 2077"]
#        powershell -File tools\compile-check.ps1 -WithoutBrowserExtension
#        powershell -File tools\compile-check.ps1 -WithoutTests

param(
    [string]$GameDir = "D:\Jeux\Cyberpunk 2077",
    [string]$WorkDir = (Join-Path $env:TEMP "ai_npc-compile-check"),
    [switch]$WithoutBrowserExtension,
    [switch]$WithoutTests
)

$ErrorActionPreference = "Stop"

$root   = Resolve-Path "$PSScriptRoot\.."
$modSrc = Join-Path $root "src\r6\scripts\ai_npc"

# Every script folder this mod ships, not just the main one. The second folder exists purely
# to control @wrapMethod ordering -- see the header of AiNpcPhoneContacts.reds -- and pointing
# this tool at "src\r6\scripts\ai_npc" alone once reported PASS for a file it had never
# compiled. Enumerated from disk so a folder added later cannot be forgotten here.
$scriptRoot = Join-Path $root "src\r6\scripts"
$modFolders = @(Get-ChildItem -Path $scriptRoot -Directory)

$scc          = Join-Path $GameDir "engine\tools\scc.exe"
$vanillaCache = Join-Path $GameDir "r6\cache\final.redscripts"

foreach ($p in @($scc, $vanillaCache, $modSrc)) {
    if (-not (Test-Path $p)) { throw "Not found: $p" }
}

# Declared dependencies only. If ai_npc ever compiles here but fails for a user, the
# cause is a missing entry in this list -- which is exactly what we want to detect.
$deps = @{
    "RedData"       = (Join-Path $GameDir "r6\scripts\RedData")
    "RedFileSystem" = (Join-Path $GameDir "r6\scripts\RedFileSystem")
    "RedHttpClient" = (Join-Path $GameDir "r6\scripts\RedHttpClient")
    "Codeware"      = (Join-Path $GameDir "red4ext\plugins\Codeware\Scripts")
    "ModSettings"   = (Join-Path $GameDir "red4ext\plugins\mod_settings")
}

# Optional, and the only one of its kind here: the terminal chat needs it, the rest of the
# mod does not, and a player without it must still get a mod that compiles.
if (-not $WithoutBrowserExtension) {
    $deps["BrowserExtension"] = (Join-Path $GameDir "r6\scripts\BrowserExtension")
}

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path "$WorkDir\scripts" -Force | Out-Null
New-Item -ItemType Directory -Path "$WorkDir\cache"   -Force | Out-Null

foreach ($name in $deps.Keys) {
    $srcPath = $deps[$name]
    if (-not (Test-Path $srcPath)) { throw "Missing dependency '$name': $srcPath" }
    $target = Join-Path "$WorkDir\scripts" $name
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    # RECURSIVE, and it has to be. ai_npc keeps its public surface in a subfolder (api\), and
    # a flat "*.reds" copy would leave it out of every offline compile -- silently, because
    # nothing else in the tree references those functions by name. The mod would pass this
    # check and fail in the game of anybody with an integrating mod installed.
    Copy-Item (Join-Path $srcPath "*.reds") $target -Recurse -Force
}

foreach ($folder in $modFolders) {
    Copy-Item $folder.FullName (Join-Path "$WorkDir\scripts" $folder.Name) -Recurse -Force
}

# Deleted from the copy, exactly as package.ps1 deletes it from the staging folder -- so what
# is checked here is the file list that ships, not an approximation of it.
# One folder, and it carries its own marker: tests\ holds the assertions and, in
# AiNpcTestSuite.reds, the module AiNpcSelfTest.reds asks about. Dropping the assertions without
# the marker is a build that compiles into a mod nobody would want -- see that file's head.
if ($WithoutTests) {
    $copy = Join-Path "$WorkDir\scripts" "ai_npc\tests"
    if (-not (Test-Path $copy)) { throw "the self-tests were not found at $copy - the folder moved, and this switch would silently check nothing." }
    if (-not (Test-Path (Join-Path $copy "AiNpcTestSuite.reds"))) { throw "AiNpcTestSuite.reds is not in $copy - the marker module left the folder, so this switch would check a shape package.ps1 never builds." }
    Remove-Item $copy -Recurse -Force
}
Copy-Item $vanillaCache "$WorkDir\cache\final.redscripts" -Force

$shape = if ($WithoutTests) { "release shape - no self-tests" } else { "debug shape - self-tests included" }
Write-Output "Compiling $($modFolders.Count) script folder(s) against vanilla bundle ($shape)..."
$output = & $scc -compile "$WorkDir\scripts" "$WorkDir\cache\final.redscripts" 2>&1
$code = $LASTEXITCODE

$problems = $output | Where-Object { $_ -match '^\[(ERROR|WARN)' -or $_ -match '^\s{4}' -or $_ -match '\^\^\^' }
if ($problems) { $problems | ForEach-Object { Write-Output $_ } }

if ($code -ne 0) {
    Write-Output ""
    Write-Output "FAIL: compilation errors above."
    exit 1
}

$warnCount = ($output | Where-Object { $_ -match '^\[WARN' }).Count
Write-Output ""
Write-Output "PASS: ai_npc compiles cleanly ($warnCount warning(s))."
exit 0
