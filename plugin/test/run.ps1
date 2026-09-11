# Builds and runs the plugin's offline suite.
#
# compile-check.ps1 does not see C++, so without this the whole native half of the mod would
# be checked only by launching the game -- which is the one thing an agent cannot do. What it
# covers is stated at the top of TestHost.cpp, along with the three things it cannot.
#
# It links only the files that have no RED4ext dependency, which is not a limitation but the
# design: a backend that needed the game to be asserted would be a backend nobody asserts.
#
# Usage: powershell -File plugin\test\run.ps1 [-Audible]
#
# -Audible makes the audio case play a tone instead of silence. Off by default: a suite
# that beeps during unrelated work is a suite people stop running.

param(
    [switch]$Audible
)

$ErrorActionPreference = "Stop"

$root   = Resolve-Path "$PSScriptRoot\..\.."
$outDir = Join-Path $root "plugin\build\test"

# Plugin.cpp and ScriptApi.cpp are deliberately absent: they are the RED4ext half, and their
# correctness is a launch checklist rather than a fixture.
$sources = @(
    "plugin\Audio.cpp",
    "plugin\ProcessOutput.cpp",
    "plugin\Speech.cpp",
    "plugin\SapiVoice.cpp",
    "plugin\PocketVoice.cpp",
    "plugin\VoiceArchive.cpp",
    "plugin\VoiceMake.cpp",
    "plugin\Json.cpp",
    "plugin\Stream.cpp",
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

# La voie parlee choisit entre deux moteurs, donc les deux se lient -- y compris ici, ou aucun
# des deux ne parle : la suite n'assert que le repli, sur une chaine fixe. Ce qui vient du
# moteur embarque est sa bibliotheque, pas son comportement.
#
# PocketVoice.cpp ne declare l'API C que pour l'appeler ; l'editeur de liens veut quand meme la
# trouver, donc le moteur doit avoir ete bati.
$pocketDep = Join-Path $root "vendor\pocket-deps"
$ortLib    = Join-Path $pocketDep "onnxruntime-win-x64-1.23.2\lib\onnxruntime.lib"
$spmLib    = Join-Path $pocketDep "build\sentencepiece.lib"
$engine    = Join-Path $root "vendor\PocketTTS.cpp\pocket_tts.cpp"
$ww2ogg    = Join-Path $root "vendor\ww2ogg"
$stb       = Join-Path $root "vendor\stb"
foreach ($needed in @($ortLib, $spmLib, $engine, "$ww2ogg\src\wwriff.cpp", "$stb\stb_vorbis.c")) {
    if (-not (Test-Path $needed)) {
        throw "The speech engine is not built: $needed is missing. Run: powershell -File tools\pocket-engineuild.ps1 -Fetch, then patch-runtime.py, then build.ps1"
    }
}
$sources += $engine
$sources += "$ww2ogg\src\wwriff.cpp", "$ww2ogg\src\codebook.cpp", "$ww2ogg\src\crc.c"

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "Visual Studio not found (vswhere.exe missing)." }

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw "No Visual Studio install with the C++ toolset." }

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$quoted = ($sources | ForEach-Object { "`"$_`"" }) -join " "
# winmm.lib: Audio.cpp plays a buffer through waveOut, which is the only path that needs
# no file on disk anywhere.
$includes = "/I`"$root\plugin`" /I`"$pocketDep\onnxruntime-win-x64-1.23.2\include`" /I`"$pocketDep\sentencepiece\src`" /I`"$pocketDep\dr_libs`" /I`"$ww2ogg\src`" /I`"$stb`""
$compile = "cl.exe /nologo /EHsc /std:c++20 /W3 /MD /O2 /DNDEBUG /DPTT_SHARED_LIB $includes $quoted /Fe:ai_npc_tests.exe /link winmm.lib ole32.lib ws2_32.lib `"$spmLib`" `"$ortLib`""

Write-Output "Building the plugin test host..."
$log = & cmd.exe /c "`"$vcvars`" >nul 2>&1 && cd /d `"$outDir`" && $compile" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output ($log -join "`n")
    throw "Test host build failed."
}
$log | Where-Object { $_ -match 'error|warning C' } | ForEach-Object { Write-Output $_ }

$exe = Join-Path $outDir "ai_npc_tests.exe"
Write-Output ""
$arguments = @()
if ($Audible) { $arguments += "-Audible" }
& $exe @arguments
$code = $LASTEXITCODE

if ($code -ne 0) {
    throw "Plugin tests failed."
}
