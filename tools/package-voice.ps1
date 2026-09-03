# Construit le pack de modeles de parole : le second livrable, installe a part.
#
#   powershell -File tools\package-voice.ps1 -Models models\fr -Language fr
#
# Produit dist\ai_npc-voice-<langue>.zip, une archive nue que Vortex depose a la racine du jeu.
# Pas de FOMOD : il n'y a aucune question a poser, et un XML de moins est une installation de
# moins qui peut echouer.
#
# UN SEUL FICHIER, ET SON NOM NE PORTE PAS DE VERSION. Vortex identifie une archive installee a
# la main par son nom, donc un nom fixe est deja ce qui fait qu'une reconstruction remplace la
# precedente au lieu de s'installer a cote -- le mod, lui, a besoin d'une copie a nom stable
# parce que son nom versionne change. Ce que ce nom porte a la place est de quel depot de poids
# le pack vient, et c'est la seule chose qu'on ait besoin de relire dans une semaine.
#
# POURQUOI UN SECOND ZIP. Le mod pese quinze megaoctets, le pack en pese quatre cents. Les
# reunir imposerait ce telechargement a chaque correctif du mod, et interdirait de publier une
# autre langue sans republier le tout. Ils s'installent comme deux mods distincts, se mettent a
# jour separement, et n'ecrivent pas un seul fichier en commun -- donc Vortex n'a aucun conflit
# a faire arbitrer par le joueur.
#
# CE QUI N'EST PAS ICI. Les voix : le mod n'en livre aucune. Une reference se fabrique sur la
# machine du joueur, a partir de sa propre copie du jeu, et vit dans r6\storages\AiNpc\voices\.
# Voir docs\PLAN_VOICE_LANE.md.

param(
    [Parameter(Mandatory = $true)][string]$Models,
    [Parameter(Mandatory = $true)][string]$Language
)

$ErrorActionPreference = "Stop"

$root    = Resolve-Path "$PSScriptRoot\.."
$distDir = Join-Path $root "dist"
$source  = Resolve-Path $Models

# Ce que le moteur ouvre au chargement. Enumere plutot que glob : un pack a qui il manque un
# fichier se charge a moitie et echoue a la premiere replique, loin d'ici.
#
# bos_before_voice.bin est le plus petit et le plus important : sans lui le francais babille,
# et rien dans la sortie ne dit pourquoi.
$required = @(
    "flow_lm_main_int8.onnx",
    "flow_lm_flow.onnx",
    "mimi_decoder_int8.onnx",
    "text_conditioner.onnx",
    "tokenizer.model",
    "bos_before_voice.bin"
)

# Facultatifs, et chacun dit quelque chose. mimi_encoder.onnx est la moitie qui clone : elle
# vient du depot sur liste d'autorisation, et un pack qui la porte NE SE PUBLIE PAS.
$optional = @("mimi_encoder.onnx", "frames_after_eos.txt")

# Les codebooks Vorbis dont le decodeur a besoin pour lire une replique du jeu, 74 Ko, sous la
# licence de ww2ogg. Mesure du 2026-09-01 : les .wem de Cyberpunk refusent les codebooks
# integres -- « nonsense codeword length » -- et passent avec celui-ci.
#
# Ils voyagent avec le PACK DE CLONAGE et pas avec le mod, parce qu'ils ne servent a rien sans
# l'encodeur : sans lui, une reference extraite ne peut pas devenir une voix.
$codebooks = Join-Path $root "vendor\ww2ogg\packed_codebooks_aoTuV_603.bin"

$missing = $required | Where-Object { -not (Test-Path (Join-Path $source $_)) }
if ($missing) {
    throw ("The model set is incomplete: " + ($missing -join ", ") +
        " missing from $source. Rebuild it with tools\pocket-engine\export-models.py.")
}

# La quantification qui deforme, refusee au packaging plutot qu'a l'oreille.
#
# flow_lm_flow doit etre en fp32. Mesure le 2026-09-01 : quantifie, il rend une voix deformee
# avec des erreurs et de la musique, tandis que le modele quinze fois plus gros supporte l'INT8
# sans qu'on l'entende. Un fichier de neuf megaoctets a cette place est donc le mauvais.
$flow = Get-Item (Join-Path $source "flow_lm_flow.onnx")
if ($flow.Length -lt 20MB) {
    throw ("flow_lm_flow.onnx weighs " + [math]::Round($flow.Length / 1MB, 1) +
        " MB, which is the INT8 shape. It must ship as fp32 (~39 MB): quantised, it distorts the voice. See docs\MEASURE_VOICE_ENGINE.md.")
}

$cloning = Test-Path (Join-Path $source "mimi_encoder.onnx")

$stage = Join-Path $env:TEMP "ai_npc-voice-$Language"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$target = Join-Path $stage "red4ext\plugins\ai_npc\models"
New-Item -ItemType Directory -Path $target -Force | Out-Null

foreach ($file in ($required + $optional)) {
    $path = Join-Path $source $file
    if (Test-Path $path) { Copy-Item $path $target -Force }
}

if ($cloning) {
    if (-not (Test-Path $codebooks)) {
        throw "$codebooks not found. The cloning pack cannot make a reference without it. Run: powershell -File tools\pocket-engine\build.ps1 -Fetch"
    }
    Copy-Item $codebooks $target -Force
}

# Les voix de catalogue : un etat deja conditionne par voix, ce qui fait parler le pack LIBRE.
# Son encodeur est a zero -- il ne fabrique aucune voix a partir d'un son -- mais il en charge de
# toutes faites, et c'est la difference entre onze personnages distincts et onze fois Windows.
#
# Exigees pour le pack libre, facultatives pour celui de clonage : la ou un clone est possible,
# elles ne servent qu'aux contacts sans reference.
$catalogue = Join-Path $source "catalogue"
$states = @()
if (Test-Path $catalogue) { $states = @(Get-ChildItem "$catalogue\*.kv") }
if ($states.Count -eq 0 -and -not $cloning) {
    throw "No catalogue voice in $catalogue. Without one the free pack loads and every character falls back to the system voice. Run: python tools\pocket-engine\export-catalogue.py --out $Models"
}
if ($states.Count -gt 0) {
    $catalogueTarget = Join-Path $target "catalogue"
    New-Item -ItemType Directory -Path $catalogueTarget -Force | Out-Null
    $states | Copy-Item -Destination $catalogueTarget -Force
}

if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }

# Le nom porte l'avertissement, parce que c'est la seule chose qui survit a la semaine.
$suffix  = if ($cloning) { "-cloning-DO-NOT-PUBLISH" } else { "" }
$zipPath = Join-Path $distDir "ai_npc-voice-$Language$suffix.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = $zip.Entries | ForEach-Object { $_.FullName.Replace("\", "/") }
} finally {
    $zip.Dispose()
}
$mustCarry = if ($cloning) { $required + @("packed_codebooks_aoTuV_603.bin") } else { $required }
foreach ($file in $mustCarry) {
    if ($names -notcontains "red4ext/plugins/ai_npc/models/$file") {
        throw "The zip is missing $file - the pack would install and the engine would fail on the first line."
    }
}

Remove-Item $stage -Recurse -Force

$size = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Output "Built $zipPath ($size MB)"
Write-Output ("  " + $states.Count + " catalogue voice(s)")
if ($cloning) {
    Write-Output "  CLONING PACK - local only. Its weights come from the allow-listed kyutai/pocket-tts repository; building it here is not redistributing it, publishing this file would be."
} else {
    Write-Output "  Free pack (CC-BY-4.0, Kyutai Labs - name them wherever the model is credited)."
}
