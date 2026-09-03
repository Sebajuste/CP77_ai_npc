# Recupere les dependances du moteur de parole et le batit avec cl.exe.
#
#   powershell -File tools\pocket-engine\build.ps1 -Fetch     # clone et telecharge (~90 Mo)
#   powershell -File tools\pocket-engine\build.ps1            # batit
#
# Produit vendor\PocketTTS.cpp\pocket-tts.exe, le banc hors jeu du moteur. Le meme
# `pocket_tts.cpp` entrera dans ai_npc.dll ; ce binaire existe pour ecouter une replique sans
# lancer Cyberpunk, ce qui est le seul controle qui ait jamais rien prouve ici.
#
# PAS DE CMAKE, et ce n'est pas une preference : il n'y en a aucun sur cette machine, pas meme
# dans Visual Studio. Le README amont annonce CMake 3.28+ et GCC ou Clang ; mesure le
# 2026-09-01, `cl.exe` et `lib.exe` suffisent, ce qui garde une seule chaine de compilation
# pour ce depot -- celle de plugin\build.ps1.

param(
    [switch]$Fetch
)

$ErrorActionPreference = "Stop"

$root   = Resolve-Path "$PSScriptRoot\..\.."
$vendor = Join-Path $root "vendor"
$engine = Join-Path $vendor "PocketTTS.cpp"
$deps   = Join-Path $vendor "pocket-deps"
$ww2ogg = Join-Path $vendor "ww2ogg"
$stb    = Join-Path $vendor "stb"
$ort    = Join-Path $deps "onnxruntime-win-x64-1.23.2"
$spm    = Join-Path $deps "sentencepiece"
$drlibs = Join-Path $deps "dr_libs"

if ($Fetch) {
    New-Item -ItemType Directory -Force $deps | Out-Null

    if (-not (Test-Path $engine)) {
        git clone --depth 1 https://github.com/VolgaGerm/PocketTTS.cpp.git $engine
    }
    if (-not (Test-Path $drlibs)) {
        git clone --depth 1 https://github.com/mackron/dr_libs.git $drlibs
    }
    if (-not (Test-Path $spm)) {
        git clone --depth 1 --branch v0.2.1 https://github.com/google/sentencepiece.git $spm
    }
    if (-not (Test-Path $ort)) {
        $zip = Join-Path $deps "onnxruntime.zip"
        Invoke-WebRequest -Uri "https://github.com/microsoft/onnxruntime/releases/download/v1.23.2/onnxruntime-win-x64-1.23.2.zip" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $deps -Force
        Remove-Item $zip -Force
    }

    # Le decodeur des repliques du jeu. Il n'a rien a voir avec la synthese : il fabrique les
    # REFERENCES a partir des archives du joueur, et le pack de clonage est ce qui le rend utile.
    # Meme chaine que le moteur -- clone, patche, compile avec cl.exe -- donc meme script.
    if (-not (Test-Path $ww2ogg)) {
        git clone --depth 1 https://github.com/hcs64/ww2ogg.git $ww2ogg
    }
    if (-not (Test-Path $stb)) {
        New-Item -ItemType Directory -Force $stb | Out-Null
    }
    $vorbis = Join-Path $stb "stb_vorbis.c"
    if (-not (Test-Path $vorbis)) {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nothings/stb/master/stb_vorbis.c" -OutFile $vorbis
    }

    Write-Output "Dependances en place. Appliquer les patchs :"
    Write-Output "  python tools\pocket-engine\patch-runtime.py"
    Write-Output "  python tools\pocket-engine\patch-decoder.py"
    return
}

foreach ($needed in @($engine, $ort, $spm, $drlibs)) {
    if (-not (Test-Path $needed)) { throw "$needed manque. Lancer d'abord : build.ps1 -Fetch" }
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "Visual Studio introuvable (vswhere.exe absent)." }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat introuvable dans $vsPath" }

$build = Join-Path $deps "build"
New-Item -ItemType Directory -Force $build | Out-Null

# ── SentencePiece ────────────────────────────────────────────────────────────
#
# Sa moitie d'execution fait quarante unites de traduction : les vingt-six sources de son
# protobuf-lite embarque, un fichier absl, les deux .pb.cc generes qu'il livre deja, et onze
# des siennes. Rien la-dedans ne demande un systeme de compilation.
$lib = Join-Path $build "sentencepiece.lib"
if (-not (Test-Path $lib)) {
    # `config.h` porte quatre macros de chaine et rien d'autre ; CMake le genere, on l'ecrit.
    $config = @"
#ifndef CONFIG_H_
#define CONFIG_H_
#define VERSION "0.2.1"
#define PACKAGE "sentencepiece"
#define PACKAGE_STRING "sentencepiece"
#define INSTALL_DATADIR ""
#endif  // CONFIG_H_
"@
    $config | Out-File -Encoding ascii (Join-Path $build "config.h")

    $spmSources = @()
    $spmSources += (Get-ChildItem "$spm\third_party\protobuf-lite\*.cc" | ForEach-Object { $_.FullName })
    $spmSources += "$spm\third_party\absl\flags\flag.cc"
    $spmSources += "$spm\src\builtin_pb\sentencepiece.pb.cc", "$spm\src\builtin_pb\sentencepiece_model.pb.cc"
    foreach ($n in @("bpe_model", "char_model", "error", "filesystem", "model_factory",
                     "model_interface", "normalizer", "sentencepiece_processor", "unigram_model",
                     "util", "word_model")) {
        $spmSources += "$spm\src\$n.cc"
    }
    $missing = $spmSources | Where-Object { -not (Test-Path $_) }
    if ($missing) { throw "sources SentencePiece introuvables : $($missing -join ', ')" }

    # /I"$spm" -- la racine du depot -- est l'inclusion que CMake fournit implicitement, et la
    # premiere dont l'absence arrete la compilation : common.h cherche third_party/absl/...
    $spmInc = "/I`"$build`" /I`"$spm`" /I`"$spm\src`" /I`"$spm\src\builtin_pb`" /I`"$spm\third_party`" /I`"$spm\third_party\protobuf-lite`""
    $spmArgs = ($spmSources | ForEach-Object { "`"$_`"" }) -join " "
    $spmCmd = "cl.exe /nologo /c /EHsc /std:c++17 /MD /O2 /DNDEBUG /W0 /utf-8 /DHAVE_PTHREAD /D_USE_INTERNAL_STRING_VIEW /D_CRT_SECURE_NO_WARNINGS $spmInc $spmArgs"

    Write-Output "Compilation de SentencePiece ($($spmSources.Count) unites)..."
    $script = Join-Path $build "spm.bat"
    "@echo off`r`ncall `"$vcvars`" >nul 2>&1`r`ncd /d `"$build`"`r`n$spmCmd`r`nif errorlevel 1 exit /b 1`r`nlib.exe /nologo /OUT:sentencepiece.lib *.obj" |
        Out-File -Encoding ascii $script
    $log = & cmd.exe /c "`"$script`"" 2>&1
    if ($LASTEXITCODE -ne 0) { $log | Where-Object { $_ -match 'error' }; throw "SentencePiece n'a pas compile." }
    Get-ChildItem "$build\*.obj" | Remove-Item -Force
}

# ── Le moteur ────────────────────────────────────────────────────────────────
$patched = Select-String -Path "$engine\pocket_tts.cpp" -Pattern "load_bos" -Quiet
if (-not $patched) {
    Write-Warning "pocket_tts.cpp n'est pas patche : le francais babillera. Lancer d'abord : python tools\pocket-engine\patch-runtime.py"
}

$engineCmd = "cl.exe /nologo /c /EHsc /std:c++17 /W3 /MD /O2 /DNDEBUG /I`"$ort\include`" /I`"$spm\src`" /I`"$drlibs`" `"$engine\pocket_tts.cpp`" /Fo:pocket_tts.obj"
$linkCmd = "link.exe /nologo /OUT:`"$engine\pocket-tts.exe`" pocket_tts.obj `"$lib`" `"$ort\lib\onnxruntime.lib`" ws2_32.lib"

Write-Output "Compilation du moteur..."
$script = Join-Path $build "engine.bat"
"@echo off`r`ncall `"$vcvars`" >nul 2>&1`r`ncd /d `"$build`"`r`n$engineCmd`r`nif errorlevel 1 exit /b 1`r`n$linkCmd" |
    Out-File -Encoding ascii $script
$log = & cmd.exe /c "`"$script`"" 2>&1
if ($LASTEXITCODE -ne 0) { $log | Where-Object { $_ -match 'error' }; throw "Le moteur n'a pas compile." }

Copy-Item "$ort\lib\onnxruntime.dll" $engine -Force
$size = [math]::Round((Get-Item "$engine\pocket-tts.exe").Length / 1KB, 1)
Write-Output "Bati $engine\pocket-tts.exe ($size Ko), avec onnxruntime.dll a cote."
