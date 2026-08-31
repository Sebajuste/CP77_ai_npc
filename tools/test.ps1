# Runs the full offline test suite: static lint, then isolated type-check.
# Usage: powershell -File tools\test.ps1 [-GameDir "D:\Jeux\Cyberpunk 2077"]

param([string]$GameDir = "D:\Jeux\Cyberpunk 2077")

$ErrorActionPreference = "Continue"
$failed = 0

Write-Output "== lint =="
& "$PSScriptRoot\lint.ps1"
if ($LASTEXITCODE -ne 0) { $failed++ }

Write-Output ""
Write-Output "== compile-check =="
& "$PSScriptRoot\compile-check.ps1" -GameDir $GameDir
if ($LASTEXITCODE -ne 0) { $failed++ }

# The shape that ships. package.ps1 -Release drops the whole r6\scripts\ai_npc\tests\
# folder -- the assertions and the marker module that says they are there -- which
# flips the @if seam in AiNpcSelfTest.reds to its no-op branch. That is a shape the run above
# never compiles, and a branch nobody compiles is a branch that rots into a compile error in
# the player game. -WithoutTests removes the same two files, so what is checked here is the
# file list that ships rather than an approximation of it.
Write-Output ""
Write-Output "== compile-check (release shape) =="
& "$PSScriptRoot\compile-check.ps1" -GameDir $GameDir -WithoutTests
if ($LASTEXITCODE -ne 0) { $failed++ }

# The plugin's own suite. compile-check does not see C++, so without this the native half of
# the mod -- the command lines it builds, and what it makes of the four ways a CLI can answer
# -- would be checked only by launching the game. Skipped rather than failed when there is no
# C++ toolset: a scripts-only contributor should still get a green suite.
Write-Output ""
Write-Output "== plugin (offline C++ suite) =="
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Output "no Visual Studio C++ toolset - skipped."
} else {
    & "$PSScriptRoot\..\plugin\test\run.ps1"
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

# The offline prompt builder (tools\prompt) reads the mod's own .reds for every word it
# sends. Both checks below are about that link and cost nothing: the first says the corpus
# still matches the sources, the second rebuilds a prompt the game really sent and compares
# it byte for byte. A red line here means an offline prompt has drifted from the shipped one,
# which is invisible everywhere else -- the prompt still comes out, it is simply not ours.
Write-Output ""
Write-Output "== prompt corpus =="
$python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Output "python.exe not on PATH - skipped."
} else {
    & $python.Source "$PSScriptRoot\prompt\extract.py" --check
    if ($LASTEXITCODE -ne 0) { $failed++ }
    & $python.Source "$PSScriptRoot\prompt\verify.py"
    if ($LASTEXITCODE -ne 0) { $failed++ }
    # The pure functions of that tooling: the language detector, and -- since the prompt
    # became a recipe -- that the shipped template still renders everything, that a recipe
    # removes what it names, and that the offline pass table still matches the mod's.
    & $python.Source "$PSScriptRoot\prompt\tests.py"
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

Write-Output ""
Write-Output "== runtime self-tests (from last game launch) =="
$resultsPath = Join-Path $GameDir "r6\storages\AiNpc\test-results.json"
if (-not (Test-Path $resultsPath)) {
    Write-Output "no results yet - launch the game once with ai_npc installed."
} else {
    $r = Get-Content $resultsPath -Raw | ConvertFrom-Json
    $age = [math]::Round(((Get-Date) - (Get-Item $resultsPath).LastWriteTime).TotalHours, 1)
    Write-Output "$($r.passed)/$($r.total) passed  (results are $age h old)"
    if ($r.failed -gt 0) {
        $r.failures | ForEach-Object { Write-Output "    $_" }
        $failed++
    }
}

Write-Output ""
if ($failed -gt 0) {
    Write-Output "SUITE FAILED ($failed stage(s))."
    exit 1
}
Write-Output "SUITE PASSED."
exit 0
