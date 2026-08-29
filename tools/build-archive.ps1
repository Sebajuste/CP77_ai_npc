# Builds src\archive\pc\mod\ai_npc.archive from the depot tree in source\archive\.
#
# The archive holds one thing: the AGENT LINK site icon. It is a build output like the zip,
# not a binary copied out of WolvenKit's packed\ folder by hand -- see docs\branding\README.md
# for the one step that IS still by hand (a .png becoming a .xbm in the GUI).
#
# Usage: powershell -File tools\build-archive.ps1

$ErrorActionPreference = "Stop"

$root    = Resolve-Path "$PSScriptRoot\.."
$depot   = Join-Path $root "source\archive"
$project = Join-Path $root "tools\archive"
$outPath = Join-Path $root "src\archive\pc\mod\ai_npc.archive"

if (-not (Test-Path $depot)) {
    throw "No depot tree at $depot - nothing to pack. The .xbm files are imported in WolvenKit; see docs\branding\README.md."
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet is not on PATH. tools\archive needs the .NET 8 SDK to build."
}

$build = & dotnet build $project -v q --nologo 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output $build
    throw "tools\archive failed to build - the WolvenKit 8.20 DLLs it references may have moved."
}

$packed = & dotnet run --project $project --no-build -- $depot $outPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output $packed
    throw "Packing the archive failed."
}
Write-Output $packed
