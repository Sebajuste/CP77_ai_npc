<#
.SYNOPSIS
    Fabrique les extraits de voix de reference d'ai_npc a partir des archives du jeu.

.EXAMPLE
    .\tools\voice-extract\voice-extract.ps1 -List
    .\tools\voice-extract\voice-extract.ps1 judy panam
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Characters,

    [string] $Game = 'D:\Jeux\Cyberpunk 2077',
    [string] $WolvenKit = 'C:\Users\sebaj\Documents\CP77_mods\WolvenKit-8.20.0',
    [string] $Out = 'dist\voices',
    [string] $Cache = 'tools\voice-extract\cache',
    [string] $Language = 'fr',
    [switch] $List,
    [switch] $ShowLines,
    [string] $Pattern,
    [string] $Exclude,
    [int] $Rate = 48000,
    [switch] $Raw
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$project = Join-Path $PSScriptRoot 'src\voice-extract.csproj'

if (-not (Test-Path $WolvenKit)) { throw "WolvenKit introuvable : $WolvenKit" }
if (-not (Test-Path $Game)) { throw "Cyberpunk 2077 introuvable : $Game" }

dotnet build $project -c Release --nologo -v q "/p:WolvenKitDir=$WolvenKit"
if ($LASTEXITCODE -ne 0) { throw 'la compilation a echoue' }

$exe = Join-Path $PSScriptRoot 'src\bin\Release\net8.0-windows\voice-extract.exe'
function Resolve-Under($base, $path) {
    if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $base $path }
}

$argv = @('--game', $Game, '--wolvenkit', $WolvenKit,
          '--out', (Resolve-Under $root $Out), '--cache', (Resolve-Under $root $Cache),
          '--language', $Language)
if ($List) { $argv += '--list' }
if ($ShowLines) { $argv += '--show-lines' }
if ($Pattern) { $argv += @('--pattern', $Pattern) }
if ($Exclude) { $argv += @('--exclude', $Exclude) }
$argv += @('--rate', $Rate)
if ($Raw) { $argv += '--raw' }
if ($Characters) { $argv += $Characters }

& $exe @argv
exit $LASTEXITCODE
