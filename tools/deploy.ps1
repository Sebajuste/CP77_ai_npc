# Puts the current sources in the game so the next launch runs them.
#
# There is no "build" for the REDscript half of this mod: the game compiles r6\scripts\*.reds
# at every launch. Deploying is therefore a file copy -- but not to one place, because this
# mod is installed through Vortex, and Vortex owns a staging copy that it hardlinks into the
# game folder.
#
# Writing only to the game folder works until Vortex next deploys or purges, at which point
# it overwrites or deletes the edits and the mod silently reverts. Writing only to staging
# does nothing until Vortex deploys. So both are synchronised here, as plain copies rather
# than hardlinks: re-establishing the links is Vortex's job, not this script's, and Vortex
# reporting "external changes" afterwards is correct -- there were.
#
# Usage:
#   powershell -File tools\deploy.ps1
#   powershell -File tools\deploy.ps1 -SkipChecks        # skip the type-check
#   powershell -File tools\deploy.ps1 -GameDir "D:\..." -StagingDir "D:\..."

param(
    [string]$GameDir    = "D:\Jeux\Cyberpunk 2077",
    [string]$StagingDir = "D:\Modding\Vortex Mods\cyberpunk2077\ai_npc-0.7.0",
    [switch]$SkipChecks
)

$ErrorActionPreference = "Stop"

$root   = Resolve-Path "$PSScriptRoot\.."
$srcDir = Join-Path $root "src\r6\scripts\ai_npc"

if (-not (Test-Path $srcDir))  { throw "Missing sources: $srcDir" }
if (-not (Test-Path $GameDir)) { throw "Game directory not found: $GameDir" }

# A script that does not compile still deploys fine and then takes the whole mod down at
# launch, with the failure showing up as a redscript error wall rather than as anything
# pointing here. Check first; it costs about ten seconds.
if (-not $SkipChecks) {
    Write-Output "== type-check =="
    & powershell -File (Join-Path $PSScriptRoot "compile-check.ps1") -GameDir $GameDir
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed - nothing deployed." }
    Write-Output ""
}

# The staging folder is named after the installed archive, so it moves whenever the mod is
# reinstalled from a differently named zip -- which is exactly why package.ps1 now also
# emits a stable ai_npc.zip. Until that one is installed the folder still carries a version
# suffix, so rather than hardcoding a name that goes stale, fall back to whatever ai_npc*
# folder is actually there and say which one was picked.
if (-not (Test-Path $StagingDir)) {
    $parent = Split-Path $StagingDir -Parent
    $found = @()
    if (Test-Path $parent) {
        $found = @(Get-ChildItem $parent -Directory -Filter "ai_npc*" | Sort-Object Name)
    }
    if ($found.Count -eq 1) {
        $StagingDir = $found[0].FullName
        Write-Warning "Staging folder not at the default path; using the one found: $StagingDir"
    } elseif ($found.Count -gt 1) {
        throw ("Several ai_npc staging folders exist, refusing to guess:`n  " +
               (($found | ForEach-Object { $_.FullName }) -join "`n  ") +
               "`nPass -StagingDir explicitly, or remove the stale ones from Vortex.")
    }
}

# Every script folder in src, not just ai_npc. The second one exists only to control
# @wrapMethod ordering (see AiNpcPhoneContacts.reds), and a deploy tool that knows about one
# folder silently stops shipping the other -- which is the same trap compile-check.ps1 fell
# into. Enumerated from disk so a folder added later is picked up without editing this.
$scriptRoot  = Join-Path $root "src\r6\scripts"
$modFolders  = @(Get-ChildItem -Path $scriptRoot -Directory)

$targetRoots = @()
if (Test-Path $StagingDir) {
    $targetRoots += (Join-Path $StagingDir "r6\scripts")
} else {
    Write-Warning "No Vortex staging folder found, deploying to the game only."
    Write-Warning "The next Vortex deploy or purge will revert this."
}
$targetRoots += (Join-Path $GameDir "r6\scripts")

$targets = @()
foreach ($targetRoot in $targetRoots) {
    foreach ($folder in $modFolders) {
        $targets += (Join-Path $targetRoot $folder.Name)
    }
}

foreach ($target in $targets) {
    # Stale removal below compares against the sources of THIS folder only; comparing against
    # every folder's files at once would let a script deleted from one survive because a file
    # of the same name exists in another.
    $sourceFiles = @(Get-ChildItem (Join-Path (Join-Path $scriptRoot (Split-Path $target -Leaf)) "*.reds"))

    if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }

    # Remove .reds that no longer exist in src. A renamed or deleted script left behind
    # still gets compiled by the game, and a stale duplicate declaration is a compile
    # error in the flat REDscript namespace -- one that does not reproduce from source.
    $stale = Get-ChildItem (Join-Path $target "*.reds") |
             Where-Object { $sourceFiles.Name -notcontains $_.Name }
    foreach ($f in $stale) {
        Remove-Item $f.FullName -Force
        Write-Output "  removed stale $($f.Name)"
    }

    $copied = 0
    foreach ($f in $sourceFiles) {
        $dest = Join-Path $target $f.Name
        if ((Test-Path $dest) -and ((Get-FileHash $dest).Hash -eq (Get-FileHash $f.FullName).Hash)) {
            continue
        }
        Copy-Item $f.FullName $dest -Force
        $copied++
    }
    Write-Output "$target  ($copied file(s) updated, $($sourceFiles.Count) total)"
}

Write-Output ""
Write-Output "Deployed. Launch the game to compile and to run the self-tests;"
Write-Output "then 'powershell -File tools\test.ps1' reports their result."
