# Builds and runs the plugin's offline suite.
#
# compile-check.ps1 does not see C++, so without this the whole native half of the mod would
# be checked only by launching the game -- which is the one thing an agent cannot do. What it
# covers is stated at the top of TestHost.cpp, along with the three things it cannot.
#
# It links only the files that have no RED4ext dependency, which is not a limitation but the
# design: a backend that needed the game to be asserted would be a backend nobody asserts.
#
# Usage: powershell -File plugin\test\run.ps1

$ErrorActionPreference = "Stop"

$root   = Resolve-Path "$PSScriptRoot\..\.."
$outDir = Join-Path $root "plugin\build\test"

# Plugin.cpp and ScriptApi.cpp are deliberately absent: they are the RED4ext half, and their
# correctness is a launch checklist rather than a fixture.
$sources = @(
    "plugin\Json.cpp",
    "plugin\Transport.cpp",
    "plugin\Process.cpp",
    "plugin\Text.cpp",
    "plugin\ClaudeCli.cpp",
    "plugin\CodexCli.cpp",
    "plugin\Registry.cpp",
    "plugin\test\TestHost.cpp"
) | ForEach-Object { Join-Path $root $_ }

foreach ($source in $sources) {
    if (-not (Test-Path $source)) { throw "Missing source: $source" }
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "Visual Studio not found (vswhere.exe missing)." }

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw "No Visual Studio install with the C++ toolset." }

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$quoted = ($sources | ForEach-Object { "`"$_`"" }) -join " "
$compile = "cl.exe /nologo /EHsc /std:c++20 /W3 /MD /O2 /DNDEBUG $quoted /Fe:ai_npc_tests.exe"

Write-Output "Building the plugin test host..."
$log = & cmd.exe /c "`"$vcvars`" >nul 2>&1 && cd /d `"$outDir`" && $compile" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output ($log -join "`n")
    throw "Test host build failed."
}
$log | Where-Object { $_ -match 'error|warning C' } | ForEach-Object { Write-Output $_ }

$exe = Join-Path $outDir "ai_npc_tests.exe"
Write-Output ""
& $exe
$code = $LASTEXITCODE

if ($code -ne 0) {
    throw "Plugin tests failed."
}
