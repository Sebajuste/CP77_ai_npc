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
# Enumerated from disk rather than listed: a file added to plugin\ and forgotten here would
# fail to link with a message about a missing symbol, which names the caller and not the file
# nobody compiled.
$sources = Get-ChildItem -Path (Join-Path $root "plugin") -Filter *.cpp -File |
           Sort-Object Name | ForEach-Object { $_.FullName }
if (-not $sources) { throw "No .cpp files found in plugin\." }

if (-not (Test-Path $sdkInc)) {
    throw "RED4ext SDK headers not found at $sdkInc. Run: git clone --depth 1 https://github.com/WopsS/RED4ext.SDK.git vendor\RED4ext.SDK"
}

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
    "cl.exe /nologo /EHsc /std:c++20 /W3 /MD $optimisation /LD",
    "/I`"$sdkInc`"",
    "/I`"$(Join-Path $root 'plugin')`"",
    $quotedSources,
    # cmd cds into $outDir first, so plain output names keep MSVC's quote parser out of
    # trouble: a trailing backslash inside quotes escapes the closing quote.
    "/Fe:ai_npc.dll",
    # user32.lib: the SDK's address resolver reports a failure with MessageBoxW.
    # winmm.lib: Audio.cpp plays a generated buffer, which never becomes a file.
    # ole32.lib: Speech.cpp drives SAPI, which is COM.
    "/link /DLL user32.lib winmm.lib ole32.lib"
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

