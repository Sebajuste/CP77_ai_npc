# Builds ai_npc.dll, the RED4ext plugin that runs the CLI lanes.
#
# Deliberately no CMake: the plugin is a handful of translation units against a header-only
# SDK, so cl.exe is enough and the dependency list stays one header directory.
#
# Usage: powershell -File plugin\build.ps1 [-Config Release]
#
# There is no -Deploy. Deployment is the user's, through Vortex: see CLAUDE.md. What this
# produces is the DLL that tools\package.ps1 puts in the zip.

param(
    [ValidateSet("Release", "Debug")]
    [string]$Config = "Release"
)

$ErrorActionPreference = "Stop"

$root    = Resolve-Path "$PSScriptRoot\.."
$sdkInc  = Join-Path $root "vendor\RED4ext.SDK\include"
$outDir  = Join-Path $root "plugin\build"

# Le moteur de parole, compile DANS cette DLL. PTT_SHARED_LIB retire son main() et sa boucle de
# ligne de commande, en gardant l'API C que PocketVoice.cpp declare de son cote.
#
# La copie amont est patchee : voir tools\pocket-engine\. Sans le patch la DLL compile et se lie
# tout aussi bien, et le francais babille -- alors on refuse plutot que de le livrer.
$engine    = Join-Path $root "vendor\PocketTTS.cpp\pocket_tts.cpp"
$pocketDep = Join-Path $root "vendor\pocket-deps"
$ortDir    = Join-Path $pocketDep "onnxruntime-win-x64-1.23.2"
$spmDir    = Join-Path $pocketDep "sentencepiece"
$spmLib    = Join-Path $pocketDep "build\sentencepiece.lib"

# Le decodeur des repliques du jeu : ww2ogg reconstitue l'en-tete Vorbis que Wwise retire,
# stb_vorbis decode le resultat. C'est ce qui permet a la DLL de fabriquer une reference sans
# WolvenKit, sans SDK .NET et sans etape manuelle. Voir docs\PLAN_VOICE_LANE.md § 5.
$ww2ogg    = Join-Path $root "vendor\ww2ogg"
$stb       = Join-Path $root "vendor\stb"
# Enumerated from disk rather than listed: a file added to plugin\ and forgotten here would
# fail to link with a message about a missing symbol, which names the caller and not the file
# nobody compiled.
$sources = Get-ChildItem -Path (Join-Path $root "plugin") -Filter *.cpp -File |
           Sort-Object Name | ForEach-Object { $_.FullName }
if (-not $sources) { throw "No .cpp files found in plugin\." }

if (-not (Test-Path $sdkInc)) {
    throw "RED4ext SDK headers not found at $sdkInc. Run: git clone --depth 1 https://github.com/WopsS/RED4ext.SDK.git vendor\RED4ext.SDK"
}

foreach ($needed in @($engine, $ortDir, $spmDir, $spmLib, "$ww2ogg\src\wwriff.cpp", "$stb\stb_vorbis.c")) {
    if (-not (Test-Path $needed)) {
        throw "The speech engine is not built: $needed is missing. Run: powershell -File tools\pocket-engine\build.ps1 -Fetch, then patch-runtime.py, then build.ps1"
    }
}
if (-not (Select-String -Path "$ww2ogg\src\wwriff.h" -Pattern "istringstream _infile" -Quiet)) {
    throw "vendor\ww2ogg is unpatched: it only reads files, and the DLL has no file to give it. Run: python tools\pocket-engine\patch-decoder.py"
}
if (-not (Select-String -Path $engine -Pattern "load_bos" -Quiet)) {
    throw "vendor\PocketTTS.cpp\pocket_tts.cpp is unpatched: the French model would babble, and nothing in the DLL would say so. Run: python tools\pocket-engine\patch-runtime.py"
}
$sources += $engine
$sources += "$ww2ogg\src\wwriff.cpp", "$ww2ogg\src\codebook.cpp", "$ww2ogg\src\crc.c"

# Locate the MSVC environment. vcvars64.bat sets up cl.exe, the CRT and the Windows SDK.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "Visual Studio not found (vswhere.exe missing)." }

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw "No Visual Studio install with the C++ toolset." }

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars" }

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$optimisation = if ($Config -eq "Release") { "/O2 /DNDEBUG" } else { "/Od /Zi" }

$quotedSources = ($sources | ForEach-Object { "`"$_`"" }) -join " "

# /EHsc      C++ exceptions (std::wstring, std::thread)
# /std:c++20 the SDK headers require a recent standard, and so do designated initialisers
# /LD        build a DLL
$compile = @(
    "cl.exe /nologo /EHsc /std:c++20 /W3 /MD $optimisation /LD /DPTT_SHARED_LIB",
    "/I`"$sdkInc`"",
    "/I`"$(Join-Path $root 'plugin')`"",
    "/I`"$ortDir\include`"",
    "/I`"$spmDir\src`"",
    "/I`"$pocketDep\dr_libs`"",
    "/I`"$ww2ogg\src`"",
    "/I`"$stb`"",
    $quotedSources,
    # cmd cds into $outDir first, so plain output names keep MSVC's quote parser out of
    # trouble: a trailing backslash inside quotes escapes the closing quote.
    "/Fe:ai_npc.dll",
    # user32.lib: the SDK's address resolver reports a failure with MessageBoxW.
    # winmm.lib: Audio.cpp plays a generated buffer, which never becomes a file.
    # ole32.lib: Speech.cpp drives SAPI, which is COM.
    # winhttp.lib: HttpStream.cpp reads a response body as it arrives, and does its own TLS.
    # ws2_32.lib: the engine carries an HTTP server it never starts here -- it is outside the
    #   PTT_SHARED_LIB guard, so it links even though nothing calls it.
    "/link /DLL user32.lib winmm.lib ole32.lib winhttp.lib ws2_32.lib",
    "`"$spmLib`" `"$ortDir\lib\onnxruntime.lib`""
) -join " "

Write-Output "Building ai_npc.dll ($Config) from $($sources.Count) source file(s)..."
$log = & cmd.exe /c "`"$vcvars`" >nul 2>&1 && cd /d `"$outDir`" && $compile" 2>&1
$exit = $LASTEXITCODE

$log | Where-Object { $_ -match 'error|warning C' } | ForEach-Object { Write-Output $_ }

if ($exit -ne 0) {
    Write-Output ""
    Write-Output ($log -join "`n")
    throw "Build failed."
}

$dll = Join-Path $outDir "ai_npc.dll"
$size = [math]::Round((Get-Item $dll).Length / 1KB, 1)
Write-Output "Built $dll ($size KB)"

