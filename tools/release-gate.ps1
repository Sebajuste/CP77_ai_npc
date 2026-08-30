# Refuses a state that must not reach main.
#
# Usage: powershell -File tools\release-gate.ps1
#
# Run by .github\workflows\release-gate.yml on every pull request into main, and runnable here
# before opening one. It answers a single question -- may this become a release? -- and it
# answers it from evidence in the repository, never from what a runner can reach.
#
# THREE REFUSALS, and the second is the one that earns the file:
#
#   red        the exported run has failures. A release with a red assertion is a release
#              nobody can reason about later: the next failure looks like the old one.
#   stale      the evidence was measured on a different state of src\ than the one being
#              merged. Green results that describe other code are worse than no results,
#              because they read as proof.
#   mislabeled the evidence names a version the sources no longer state.
#
# WHAT IT DOES NOT PROVE. That the mod compiles, and that it runs. Both need a game install,
# neither is reachable from a runner, and no arrangement of YAML will change that. This gate
# checks that somebody measured, that they measured THIS code, and that the measurement was
# clean -- see docs\ARCHITECTURE.md, "What only a launch can prove".

$ErrorActionPreference = "Stop"

$root         = Resolve-Path "$PSScriptRoot\.."
$evidencePath = Join-Path $root "tools\runtime-evidence.json"
$refusals     = @()

if (-not (Test-Path $evidencePath)) {
    Write-Output "REFUSED: tools\runtime-evidence.json is missing."
    Write-Output "         Launch the game with the debug build, then: tools\export-evidence.ps1"
    exit 1
}

$evidence = Get-Content $evidencePath -Raw | ConvertFrom-Json

# 1. Red.
if ($evidence.failed -gt 0) {
    $shown = @($evidence.failures | Select-Object -First 5)
    $more  = $evidence.failed - $shown.Count
    $detail = "the last measured run has $($evidence.failed) failing assertion(s) of $($evidence.total):`n" +
              (($shown | ForEach-Object { "           $_" }) -join "`n")
    if ($more -gt 0) { $detail += "`n           ... and $more more" }
    $refusals += $detail
}

# 2. Stale. The commit that last touched src\ on the state being merged, recomputed here
#    rather than trusted: an evidence file may be edited, git history may not.
Push-Location $root
try { $srcCommit = (& git log -1 --format=%H -- src) } finally { Pop-Location }

if (-not $srcCommit) {
    $refusals += "cannot read the last commit touching src\ - fetch-depth: 0 is needed on the checkout."
} elseif ($evidence.srcCommit -ne $srcCommit) {
    $refusals += "the evidence was measured on src\ at $($evidence.srcCommit),`n" +
                 "           and this branch has src\ at $srcCommit.`n" +
                 "           Relaunch the game, then: tools\export-evidence.ps1"
}

# 3. Mislabeled.
$versionSource = Get-Content (Join-Path $root "src\r6\scripts\ai_npc\AiNpcVersion.reds") -Raw
$version = [regex]::Match($versionSource, '(?s)func AiNpcVersion\(\)[^\{]*\{\s*return\s*"([^"]+)"').Groups[1].Value
if ($evidence.version -ne $version) {
    $refusals += "the evidence measured version $($evidence.version), and the sources state $version."
}

if ($refusals.Count -gt 0) {
    foreach ($r in $refusals) { Write-Output "REFUSED: $r" }
    Write-Output ""
    Write-Output "main means release. Nothing here proves the mod runs - it proves somebody measured this code, and that the measurement was clean."
    exit 1
}

Write-Output "OK: $($evidence.passed) assertion(s) passed, none failed, measured $($evidence.measuredAtUtc) on src\ at $($srcCommit.Substring(0,8)), version $version."
exit 0
