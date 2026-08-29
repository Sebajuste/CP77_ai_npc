# Writes the mod's version everywhere it is stated.
#
# Usage: powershell -File tools\set-version.ps1 1.0.0
#        powershell -File tools\set-version.ps1          (prints what is stated today)
#
# There are two carriers, and they are not interchangeable:
#
#   AiNpcVersion.reds     the source. It reaches the log line at startup, the journal header a
#                         player pastes into a bug report, and the name of the zip.
#   ai_npc.cpmodproj      what the WolvenKit tooling reads.
#
# This script is the convenience; it proves nothing. tools\lint.ps1 rule N+9 is what refuses a
# tree where the two disagree, and what fails on a third carrier appearing quietly. Editing
# either file by hand stays perfectly valid -- the lint says so either way, which is why this
# generates nothing and rewrites only the number.
#
# NOT touched, on purpose: RED4EXT_V1_SEMVER in plugin\Plugin.cpp. That is the DLL's own
# version, printed in RED4ext's log, and the DLL does not move with the scripts. It is declared
# in tools\version-allowances.txt with that reason.

param(
    [Parameter(Position = 0)]
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$root        = Resolve-Path "$PSScriptRoot\.."
$sourcePath  = Join-Path $root "src\r6\scripts\ai_npc\AiNpcVersion.reds"
$projectPath = Join-Path $root "ai_npc.cpmodproj"

function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path)
}

# UTF-8 without BOM, and the existing line endings: these files carry accented prose, and a BOM
# or a re-encoding here is invisible until the game reads it.
function Write-Utf8([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

$sourceText  = Read-Utf8 $sourcePath
$sourceMatch = [regex]::Match($sourceText, '(?s)(func AiNpcVersion\(\)[^\{]*\{\s*return\s*")([^"]+)(")')
if (-not $sourceMatch.Success) {
    throw "AiNpcVersion() not found in $sourcePath - nothing to read or write."
}
$current = $sourceMatch.Groups[2].Value

$project        = [xml](Get-Content $projectPath -Raw)
$projectVersion = $project.CP77Mod.Version

if (-not $Version) {
    Write-Output "AiNpcVersion()        $current"
    Write-Output "ai_npc.cpmodproj      $projectVersion"
    if ($current -ne $projectVersion) {
        Write-Output ""
        Write-Output "They disagree. Pass a version to settle it: tools\set-version.ps1 $current"
    }
    exit 0
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "'$Version' is not x.y.z. The zip is named after this, and so is the line a player pastes into a bug report."
}

Write-Utf8 $sourcePath ($sourceText.Remove($sourceMatch.Groups[2].Index, $sourceMatch.Groups[2].Length).Insert($sourceMatch.Groups[2].Index, $Version))

# Rewritten as text rather than saved through the XmlDocument: saving reformats the whole file,
# and a diff that touches every line hides the one that matters.
$projectText = Read-Utf8 $projectPath
$projectNew  = [regex]::Replace($projectText, '(<Version>)[^<]*(</Version>)', "`${1}$Version`${2}", 1)
if ($projectNew -eq $projectText -and $projectVersion -ne $Version) {
    throw "Could not find <Version> in $projectPath."
}
Write-Utf8 $projectPath $projectNew

Write-Output "AiNpcVersion()        $current -> $Version"
Write-Output "ai_npc.cpmodproj      $projectVersion -> $Version"
Write-Output ""
Write-Output "Run tools\lint.ps1 to confirm nothing else states a version."
