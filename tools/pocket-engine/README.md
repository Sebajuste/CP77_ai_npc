# Le moteur de parole : le batir, exporter ses modeles, l'ecouter

Outillage. Rien d'ici n'atteint le jeu — ce qui part dans le zip est le `.dll` et le dossier de
modeles que ces scripts produisent.

Les mesures qui justifient chaque choix sont dans `docs\MEASURE_VOICE_ENGINE.md` ; ce fichier
dit quoi taper.

---

## Une fois

```
powershell -File tools\pocket-engine\build.ps1 -Fetch
python tools\pocket-engine\patch-runtime.py
powershell -File tools\pocket-engine\build.ps1
```

Puis les modeles, dans un environnement a part parce que la version y est figee :

```
py -3.10 -m venv .venv-pocket
.venv-pocket\Scripts\pip install pocket-tts==2.1.0 onnx onnxruntime
.venv-pocket\Scripts\python tools\pocket-engine\export-models.py --out models\fr
```

`pocket-tts==2.1.0` n'est pas negociable : sur les onze versions publiees, c'est la seule qui
offre a la fois les internes que l'exporteur remplace a chaud et une configuration `french_24l`.

## Ecouter

```
cd vendor\PocketTTS.cpp
pocket-tts.exe --server --port 8231 --models-dir ..\..\models\fr --voices-dir ..\..\dist\voices --eos-extra 8
```

`--eos-extra` prend la valeur que `export-models.py` a ecrite dans `frames_after_eos.txt` a cote
des modeles. Le texte accentue **ne passe pas par la ligne de commande** sous Windows — `argv`
arrive en ANSI, SentencePiece attend de l'UTF-8 — donc on parle au serveur en JSON. C'est aussi
ce que fera la DLL.

## Les deux packs

| | commande | poids |
|---|---|---|
| libre, publie sur Nexus | `export-models.py --out models\fr` | 381,5 Mo |
| clonage, local | `export-models.py --out models\fr-clonage --cloning` | 420,8 Mo |

Ils ne different que par `mimi_encoder.onnx`. Verifie le 2026-09-01 : les autres fichiers
sortent identiques octet pour octet des deux jeux de poids, parce que les deux checkpoints ne
different que dans cet encodeur — dont la copie libre est a zero.

**Le pack de clonage ne se publie pas.** Il vient du depot `kyutai/pocket-tts`, sur liste
d'autorisation, et le fabriquer chez soi n'est pas le redistribuer.

## Attribution

Poids sous **CC-BY-4.0**, **Kyutai Labs** — a nommer partout ou le modele est credite.
`PocketTTS.cpp` et le paquet `pocket-tts` sont MIT.

---

## Les pieges, tous mesures, tous trouves a l'oreille

Le runtime a ete bati contre le seul checkpoint `english_2026-01` et **il n'ouvre aucun YAML**.
Chaque champ ou le francais s'ecarte de ce modele est un champ qu'il ignore, en silence.

| symptome | cause | ou c'est corrige |
|---|---|---|
| de la musique, quelques mots, aucune phrase | `bos_before_voice` absent de l'export | `patch-runtime.py`, `export-models.py` |
| un personnage a la voix du precedent | `voice_hash()` n'echantillonne que 16 flottants | le BOS se prefixe au conditionnement, pas a l'encodage |
| derniere phrase courte inaudible | une generation par phrase | regroupement a 50 jetons, `patch-runtime.py` |
| fin de replique coupee | `model_recommended_frames_after_eos: 8` ignore | `--eos-extra 8` |
| voix deformee, erreurs, musique | `flow_lm_flow` quantifie en INT8 | `export-models.py` ne le quantifie pas |

Le dernier est le contraire de l'intuition : `flow_lm_main` fait 302 M parametres et supporte
l'INT8 ; `flow_lm_flow` en fait 9,8 M et ne le supporte pas. C'est un solveur qui raffine par
integration, donc l'erreur y est reinjectee a chaque pas. Le garder en fp32 coute 29 Mo.

**Aucune mesure n'a signale l'un de ces cinq defauts.** Les cinq sont sortis d'une ecoute, et
trois fois une mesure a dit le contraire. Une sortie de la bonne duree, du bon niveau et sans
ecretage peut n'etre que du bruit qui articule.

## Ce que la DLL devra faire de plus

- **Convertir.** Le moteur rend du WAV **flottant 32 bits** ; `ainpc::audio::PlayWav` refuse
  tout ce qui n'est pas du PCM, et il a raison de refuser.
- **Choisir le palier par ce qui est sur le disque.** `mimi_encoder.onnx` present : une
  reference WAV est utilisable. Absent : une voix de catalogue, et rien d'autre.
