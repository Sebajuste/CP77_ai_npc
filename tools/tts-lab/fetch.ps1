# Récupère les moteurs que le banc ne peut pas fabriquer lui-même.
#
# Séparé de lab.py, et lancé par l'utilisateur, parce que télécharger quelques centaines de
# mégaoctets sur la machine de quelqu'un n'est pas une décision d'agent. Le banc tourne sans
# rien de tout ça : SAPI est dans Windows, et c'est la référence.
#
# Usage : powershell -File tools\tts-lab\fetch.ps1 -Piper

param(
    [switch]$Piper
)

$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot "engines"

function Get-File($url, $target) {
    if (Test-Path $target) {
        Write-Output "déjà là : $target"
        return
    }
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Write-Output "téléchargement : $url"
    Invoke-WebRequest -Uri $url -OutFile $target
}

if ($Piper) {
    $dir = Join-Path $root "piper"
    $zip = Join-Path $dir "piper_windows_amd64.zip"

    # Le binaire, puis une voix française. Une voix Piper est deux fichiers : le modèle .onnx et
    # son .json, qui décrit l'échantillonnage et le phonémiseur -- l'un sans l'autre ne sert à
    # rien, et l'erreur est muette.
    Get-File "https://github.com/rhasspy/piper/releases/latest/download/piper_windows_amd64.zip" $zip
    if (Test-Path $zip) {
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        # L'archive contient un dossier piper\ ; on remonte son contenu d'un cran si besoin.
        $inner = Join-Path $dir "piper"
        if (Test-Path (Join-Path $inner "piper.exe")) {
            Get-ChildItem $inner | Move-Item -Destination $dir -Force
            Remove-Item $inner -Recurse -Force
        }
    }

    $base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium"
    Get-File "$base/fr_FR-siwis-medium.onnx" (Join-Path $dir "fr_FR-siwis-medium.onnx")
    Get-File "$base/fr_FR-siwis-medium.onnx.json" (Join-Path $dir "fr_FR-siwis-medium.onnx.json")

    Write-Output ""
    Write-Output "Piper est prêt. Mesure : python tools\tts-lab\lab.py --engine piper"
}

if (-not $Piper) {
    Write-Output "Rien demandé. Options : -Piper"
}
