# Copies the last game launch's self-test results into the repository, as evidence.
#
# Usage: powershell -File tools\export-evidence.ps1 [-GameDir "D:\Jeux\Cyberpunk 2077"]
#
# WHY THE RESULTS HAVE TO TRAVEL WITH THE COMMIT. The runtime assertions only exist inside a
# launched game: no CI runner can produce them, now or ever. A gate that cannot see them can
# only gate on the text checks, and would let a release through on the strength of a linter.
# So the measurement is exported here, committed, and read back by tools\release-gate.ps1 --
# which is the thing GitHub runs on a pull request into main.
#
# WHAT MAKES IT EVIDENCE RATHER THAN A CLAIM: the file records the commit that last touched
# src\ when the measurement was taken. The gate recomputes that on the branch being merged and
# refuses when the two differ, so results measured before the code changed cannot be presented
# as if they described it. That is the whole mechanism; the pass/fail count is the easy half.

param(
    [string]$GameDir = $(if ($env:CP77_GAME_DIR) { $env:CP77_GAME_DIR } else { "D:\Jeux\Cyberpunk 2077" })
)

$ErrorActionPreference = "Stop"

$root    = Resolve-Path "$PSScriptRoot\.."
$results = Join-Path $GameDir "r6\storages\AiNpc\test-results.json"
$outPath = Join-Path $root "tools\runtime-evidence.json"

if (-not (Test-Path $results)) {
    throw "No self-test results at $results. Launch the game once with the debug build installed - the mod writes them at startup."
}

$measured = (Get-Item $results).LastWriteTimeUtc
$run      = Get-Content $results -Raw | ConvertFrom-Json

# The commit the measurement describes. Not HEAD: HEAD moves when documentation changes, and
# documentation cannot break an assertion. src\ is what the game ran.
Push-Location $root
try {
    $srcCommit = (& git log -1 --format=%H -- src) 2>$null
    $srcDate   = (& git log -1 --format=%cI -- src) 2>$null
} finally {
    Pop-Location
}
if (-not $srcCommit) { throw "Could not read the last commit touching src\ - is this a git checkout?" }

if ($measured -lt [datetime]::Parse($srcDate).ToUniversalTime()) {
    Write-Warning "These results predate the last change to src\ ($srcCommit). Exporting them anyway; release-gate.ps1 will refuse them."
}

$versionSource = Get-Content (Join-Path $root "src\r6\scripts\ai_npc\AiNpcVersion.reds") -Raw
$version = [regex]::Match($versionSource, '(?s)func AiNpcVersion\(\)[^\{]*\{\s*return\s*"([^"]+)"').Groups[1].Value

$evidence = [ordered]@{
    measuredAtUtc = $measured.ToString("yyyy-MM-ddTHH:mm:ssZ")
    srcCommit     = $srcCommit
    version       = $version
    passed        = $run.passed
    failed        = $run.failed
    total         = $run.total
    failures      = @($run.failures)
}

$json = ($evidence | ConvertTo-Json -Depth 4)
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "measured   $($evidence.measuredAtUtc)  (UTC)"
Write-Output "src commit $srcCommit"
Write-Output "version    $version"
Write-Output "result     $($run.passed) passed, $($run.failed) failed, of $($run.total)"
Write-Output ""
Write-Output "Written to tools\runtime-evidence.json. Commit it with the change it measures."
