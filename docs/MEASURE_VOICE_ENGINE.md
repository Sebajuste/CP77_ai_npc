# The two gates of `BRIEF_VOICE_ENGINE.md`, answered

Measured 2026-09-01 on this machine. Nothing downstream of the gates was written: the second
gate says the embedded-model premise has to be revisited before any code, and it does.

---

## Gate 1 — does `PocketTTS.cpp` build with MSVC? **Yes, and without CMake.**

The upstream README names CMake 3.28+ and GCC or Clang. Neither is needed, and there is no
CMake on this machine at all — not on `PATH`, not inside the Visual Studio 2022 install. The
whole thing was built with `cl.exe` and `lib.exe`, which is what `plugin\build.ps1` already
drives.

`pocket_tts.cpp` itself carries `_WIN32` branches for its sockets, its `mkdir` and its file
handles; nothing in it needed changing.

### What was run

Three dependencies, none of them requiring a build system:

```
git clone --depth 1 https://github.com/VolgaGerm/PocketTTS.cpp.git
curl -L -o ort.zip https://github.com/microsoft/onnxruntime/releases/download/v1.23.2/onnxruntime-win-x64-1.23.2.zip
git clone --depth 1 https://github.com/mackron/dr_libs.git
git clone --depth 1 --branch v0.2.1 https://github.com/google/sentencepiece.git
```

ONNX Runtime ships a prebuilt `onnxruntime.lib` and `onnxruntime.dll` for MSVC. `dr_libs` is
header-only. Only SentencePiece has to be compiled, and its runtime half is 40 translation
units — the 26 bundled protobuf-lite sources, one bundled absl file, the two generated
`.pb.cc`, and eleven of its own:

```
cl /nologo /c /EHsc /std:c++17 /MD /O2 /W0 /utf-8
   /DHAVE_PTHREAD /D_USE_INTERNAL_STRING_VIEW /D_CRT_SECURE_NO_WARNINGS
   /I<build> /I<spm> /I<spm>\src /I<spm>\src\builtin_pb
   /I<spm>\third_party /I<spm>\third_party\protobuf-lite
   <40 sources>
lib /OUT:sentencepiece.lib *.obj
```

`config.h` is written by hand rather than generated: it holds four string macros and nothing
else. `/I<spm>` — the repository root — is the include path CMake supplies implicitly and the
one whose absence stops the build first, because `common.h` reaches for
`third_party/absl/strings/string_view.h`.

Then the engine, and the link:

```
cl /nologo /c /EHsc /std:c++17 /MD /O2
   /I<ort>\include /I<spm>\src /I<dr_libs>  pocket_tts.cpp
link /OUT:pocket-tts.exe pocket_tts.obj sentencepiece.lib onnxruntime.lib ws2_32.lib
```

Result: exit 0, two `C4267` narrowing warnings (one of them inside `dr_flac.h`), and a binary
that runs and prints its own usage. `sentencepiece.lib` is 14 MB; `onnxruntime.dll` is 14.2 MB
and is the one runtime file that would ship beside `ai_npc.dll`.

**So this is one build system, not two.** `plugin\build.ps1` grows an include path, three
libraries and one vendored source file; it does not grow a CMake dependency.

---

## Gate 2 — what does the INT8 French model weigh? **303 MB for the main model alone.**

The premise was ~170 MB, read as "672 MB in fp32, and INT8 is ~4× smaller". The 672 MB is the
`.safetensors` checkpoint, and **it is stored in half precision**: 336 M parameters at two
bytes. The ONNX export is fp32, so the base INT8 divides is 1209 MB, not 672.

| file | fp32 | INT8 |
|---|---:|---:|
| `flow_lm_main.onnx` | 1209.0 MB | **303.3 MB** |
| `flow_lm_flow.onnx` | 39.1 MB | 9.9 MB |
| `mimi_decoder.onnx` | ~41 MB (not exported, see below) | ~22 MB |
| `mimi_encoder.onnx` | 39.3 MB | not quantised — used as fp32 |
| `text_conditioner.onnx` | 16.4 MB | not quantised — used as fp32 |
| `tokenizer.model` | 0.06 MB | |
| **what would ship** | | **≈ 391 MB** |

Plus `onnxruntime.dll` at 14.2 MB. Compressed, `flow_lm_main_int8.onnx` alone is 214 MB in a
zip — quantised weights do not compress.

### The 170 MB figure is right, for the wrong model

French is `french_24l` and the name is the whole difference: 24 transformer layers where every
non-`24l` language has 6. `flow_lm.transformer` is 302 M of the model's 336 M parameters, so
the layer count is very nearly the entire file.

At 6 layers the same arithmetic gives ~76 MB for `flow_lm_main_int8`, and a shipping set of
**~163 MB** — which is the brief's number. English, German, Spanish, Italian and Portuguese all
have a 6-layer model. **French is the only language of the six with no small model**, and it is
the language this mod is developed in.

So the cost is per language, and the recipe already follows the player's language. Shipping one
language is 163 MB or 391 MB depending on which one; shipping all six is not a possibility worth
costing.

### How it was measured

The upstream `export_onnx.py` is hardcoded to one English checkpoint from a mirror repository,
and this is not a flag it exposes. Replacing its model-loading half with `french_24l.yaml` from
the installed package is enough — the exporters themselves read their dimensions from the model,
with one exception: `FlowLMMainWrapper.NUM_LAYERS` is a class constant set to 6 and has to be
set to 24, or the export fails on `IndexError: list index out of range` while unpacking the KV
cache states.

Sizes come from the files it produced. The `mimi_decoder` row is arithmetic on the checkpoint's
own tensors rather than a measured file, because of the next section; the encoder row is the
same arithmetic and lands on 39.0 MB against a measured 39.3, which is what makes the decoder
estimate worth quoting at all.

---

## The third finding, and it blocks the lane on its own

**`export_onnx.py` cannot export `mimi_decoder.onnx` against `pocket-tts` 3.0.2** — the version
installed here, and the one `pip install pocket-tts` gives today.

```
ImportError: cannot import name '_LinearKVCacheBackend' from 'pocket_tts.modules.transformer'
```

The exporter monkeypatches upstream internals to make their in-place state updates traceable,
and 3.0 restructured exactly those internals: `modules/transformer.py` now holds three classes
and none of them is a KV-cache backend. Two smaller drifts of the same kind were worked around
before reaching this one — `DEFAULT_LSD_DECODE_STEPS` became `DEFAULT_SAMPLER_DECODE_STEPS`, and
the matching keyword of `_from_pydantic_config_with_weights` renamed with it.

Four of the five models export cleanly. The missing one is the decoder — the half that turns
latents into audio — so the C++ runtime cannot speak at all without it.

The fix is not in doubt, but it is not small: either pin the `pocket-tts` version the exporter
was written against and re-export from there, or port the patches to 3.0's module layout. Both
are work on the export tool, and neither is in the brief.

---

## What was not done, and why

No DLL code was written. The brief makes gate 2 a stopping point in those words — *"if INT8 is
not around 170 MB, the 'everything is embedded' premise needs revisiting before any code is
written"* — and 391 MB for the French set is not a rounding error against 170.

Nothing here says the lane is impossible. Gate 1, the one the brief called decisive, came back
clean and cheaper than expected. What changed is the shape of the question: the cost is a
per-language download of 163 MB or 391 MB, which is a distribution decision rather than an
engineering one.

---

## Le dépôt libre : ce qu'il contient exactement

Mesuré le 2026-09-01, en comparant tenseur par tenseur les deux copies de `french_24l`
présentes dans le cache Hugging Face.

Les deux checkpoints ont **les mêmes 358 tenseurs et les mêmes 336 M paramètres**. 316 d'entre
eux sont identiques bit pour bit. Les 42 qui diffèrent sont tous dans le **Mimi encoder** —
la moitié qui écoute un extrait audio et en tire une identité de locuteur.

Et l'encodeur libre n'est pas entraîné différemment : **il est à zéro**. Sur
`mimi.encoder_transformer.…layers.0.self_attn.in_proj.weight`, la copie sur liste
d'autorisation donne `std=0.0968`, la copie libre donne `std=0`, `min=max=0`.

Donc le modèle libre est le même moteur de parole, au bit près, amputé de la faculté de
fabriquer une voix à partir d'un son. Ce n'est pas un modèle qui clone mal ; c'est un modèle
qui ne peut pas.

### Deux conséquences pour le runtime C++

**`mimi_encoder.onnx` devient inutile** (−39 Mo), et avec lui la seule façon dont
`PocketTTS.cpp` sait désigner une voix : un fichier WAV. Le runtime n'a pas d'autre entrée.

**Les voix prêtes de Kyutai ne sont pas des embeddings.** Le dépôt libre en livre 26 sous
`languages/french_24l/embeddings/`, et chacune est un instantané complet de l'état KV du
transformer après conditionnement : `(2, 1, 133, 16, 64)` en fp32 par couche, sur 24 couches,
soit **26 Mo par voix**. Les neuf voix retenues par `tools\tts-lab\fallback-voices.json` pèsent
235 Mo, 222 Mo une fois zippées.

| pack français | modèle | voix | total |
|---|---:|---:|---:|
| liste d'autorisation, clonage depuis un WAV | 391 Mo | ~1,5 Mo par perso, faites sur place | **391 Mo** |
| libre, 9 voix de catalogue | 351 Mo | 235 Mo | **586 Mo** |

Un levier mesurable sur les 235 Mo : le runtime lit ses caches KV **en fp16** — c'est ce que
l'export impose aux entrées de `flow_lm_main.onnx`. Les fichiers de Kyutai sont en fp32 et
seraient convertis au chargement de toute façon, donc les livrer déjà en fp16 est sans perte
et divise ce poste par deux. Non vérifié.

---

## Le blocage de l'exporteur est levé : `pocket-tts==2.1.0`

Des onze versions publiées, **2.1.0 est la seule à avoir les deux** choses dont l'export a
besoin : `_LinearKVCacheBackend`, que l'exporteur remplace à chaud, et une configuration
`french_24l`. Les 1.x n'ont qu'une seule langue ; les 3.x ont le français et ont supprimé la
classe.

| version | `_LinearKVCacheBackend` | `french_24l` |
|---|---|---|
| 1.0.3 → 1.1.1 | non | non |
| **2.0.0, 2.1.0** | **oui** | **oui** |
| 3.0.0 → 3.0.2 | non | oui |

Sa `french_24l.yaml` pointe sur les mêmes révisions de poids que la 3.0.2, donc le cache
Hugging Face est réutilisé tel quel. Les cinq modèles s'exportent, `mimi_decoder.onnx` compris :
41,4 Mo en fp32, **22,6 Mo en INT8** — l'estimation par comptage de tenseurs annonçait ~41 et
~22.

### Les deux packs sont le même jeu de fichiers, à un fichier près

Vérifié en comparant les deux exports, faits depuis des poids différents **et sous deux
versions différentes de `pocket-tts`** :

```
flow_lm_main_int8.onnx    IDENTIQUE
flow_lm_flow_int8.onnx    IDENTIQUE
text_conditioner.onnx     IDENTIQUE
```

Octet pour octet. C'est la conséquence directe des 316 tenseurs partagés. Donc :

| pack | contenu | poids |
|---|---|---:|
| **libre, publié** | les 5 fichiers + `voices\*.kv` du catalogue | 352 Mo + les voix |
| **clonage, local** | les mêmes 5 fichiers + `mimi_encoder.onnx` | +39 Mo |

Le pack de clonage n'est donc pas un second pack : c'est le premier, plus un fichier. Il se
fabrique par l'outil sur la machine de l'auteur et ne se publie pas.

---

## Le moteur parle, hors du jeu — étape 1 du brief

Mesuré le 2026-09-01 avec `pocket-tts.exe` bâti à l'étape 1, le modèle français 24 couches en
INT8, et les extraits de `dist\voices\` produits par `tools\voice-extract`.

| | |
|---|---|
| chargement du modèle | **2,35 s** |
| réchauffage | 112 ms |
| clonage d'une référence, à froid | ~3 à 4 s, une fois par personnage |
| une réplique, voix en cache | **1,15 s pour 4,15 s d'audio — 3,6× temps réel** |
| **premier son, en streaming** | **112 ms** |

Le brief demandait moins de 300 ms. Le banc Python mesurait 190 ms et 1,3× temps réel sur la
même machine ; le chemin C++ fait mieux sur les deux, ce qui est cohérent avec l'INT8.

Le texte accentué **ne passe pas par `argv`** sous Windows : `main` reçoit de l'ANSI et
SentencePiece attend de l'UTF-8. Sans objet pour la DLL, qui appellera l'API C avec ses propres
`std::string`, mais c'est ce qui rend une mesure en ligne de commande fausse sans le dire.

### Le piège pour l'intégration : le moteur rend du flottant

`PocketTTS.cpp` écrit du WAV **IEEE float 32 bits** (`wFormatTag=3`), et
`ainpc::audio::PlayWav` refuse tout ce qui n'est pas du PCM — c'est son `Status::NotPcm`. La
conversion en PCM 16 bits appartient donc au code qui remplit le tampon, pas à la voie audio,
qui a raison de refuser.

---

## Ce que rendait ce moteur : rien d'écoutable. La cause, et sa portée

**Jugé à l'oreille le 2026-09-01 : les trois rendus C++ contiennent de la musique et quelques
mots, aucune phrase.** Les chiffres de la section précédente mesuraient donc de la plomberie
qui marche autour d'un moteur mal conditionné. C'est précisément ce contre quoi le brief
prévenait, et l'ordre a été respecté : c'est l'oreille qui a tranché, pas la mesure.

### La cause : un vecteur que l'export laisse tomber

`french_24l.yaml` porte `insert_bos_before_voice: true`, et le checkpoint contient le tenseur
`flow_lm.bos_before_voice`. Côté Python, `tts_model.py` en fait ceci avant de construire l'état
de conditionnement :

```python
if self.flow_lm.insert_bos_before_voice:
    prompt = torch.cat([self.flow_lm.bos_before_voice, prompt], dim=1)
```

`export_onnx.py` ne mentionne jamais ce tenseur, et `pocket_tts.cpp` ne connaît pas la notion.
Le conditionnement C++ est donc bâti sans sa première ligne.

### Prouvé par ablation, pas par lecture

Le chemin **Python**, avec le même modèle et la même référence, `insert_bos_before_voice`
forcé à `False` :

| rendu | durée |
|---|---:|
| `ablation-judy-avecbos.wav` | 6,96 s |
| `ablation-judy-sansbos.wav` | **1,68 s** |
| `pocket-judy-argot.wav` (banc) | 5,12 s |

Privé du BOS, Python s'effondre sur une réplique qui demande cinq secondes. C'est la même
dégénérescence que les rendus C++, dont celui de Takemura à 1,9 s.

### Pourquoi personne en amont ne l'a vu

`PocketTTS.cpp` est bâti et validé contre le checkpoint `b6369a24`, qui est
`english_2026-01.yaml` — **la seule configuration du paquet, sur treize, dont
`insert_bos_before_voice` vaut `false`**. Toutes les autres, les six langues et les deux
anglais plus récents, ont besoin de ce vecteur.

Ce n'est donc pas une casse introduite en exportant le français : c'est une limite de portée du
runtime amont, qui n'a jamais rencontré un modèle en ayant besoin.

### Ce que ça coûte, et ce que ça n'atteint pas

Le correctif touche **deux fichiers amont** : l'exporteur doit livrer les 32 flottants de
`bos_before_voice`, et le runtime doit les préfixer aux latents avant la passe de
conditionnement. C'est petit, mais ça fait passer le moteur de « dépendance qu'on compile
telle quelle » à **fork maintenu**. C'est le vrai changement de nature.

**Le pack publié n'est pas concerné.** Le palier libre ne clone pas : il charge des états KV
tout faits, calculés par Kyutai en Python, BOS compris. Ce défaut ne frappe que le chemin
« WAV → conditionnement », c'est-à-dire le pack de clonage local. La moitié qui part sur Nexus
l'évite par construction.

### Le correctif, et sa forme heureuse

`flow_lm.bos_before_voice` a la forme **(1, 1, 1024)** — déjà la dimension du modèle, pas celle
des latents. Or le runtime C++ passe justement les latents de voix encodés par le port
`text_embeddings`, en 1024. **Le correctif est donc une rangée de données, pas une modification
de graphe** : sortir les 1024 flottants du checkpoint (4 Ko) et les préfixer aux latents dans
`encode_voice`. Rien à réexporter, aucun `.onnx` à refaire.

Mesuré avec le correctif, mêmes réplique et références :

| personnage | sans BOS | avec BOS | banc Python |
|---|---:|---:|---:|
| judy | 4,63 s | 3,91 s | 5,12 s |
| panam | 3,51 s | 3,99 s | — |
| takemura | **1,91 s** | **5,83 s** | — |

Takemura ne s'effondre plus, et les durées rentrent dans la plage du banc. Les chiffres de
débit, eux, se lisent enfin sur une sortie qui n'est pas tronquée : **2,3× temps réel** voix en
cache, **145 ms** avant le premier son. Les 112 ms annoncés plus haut étaient mesurés sur une
sortie dégénérée et ne valaient rien.

Reste à juger à l'oreille. Un rendu de la bonne durée n'est toujours pas un rendu correct, et
c'est la troisième fois dans ce document qu'une mesure a besoin de l'oreille pour être crue.

---

## Deux défauts de plus, trouvés à l'oreille

Verdict sur le premier correctif : « globalement mieux », mais **la dernière phrase manque**, et
**Takemura parle avec la voix de Judy**. Deux causes distinctes, dont une que j'avais créée.

### Takemura avec la voix de Judy : le correctif du BOS, mal placé

`make_gen` indexe son cache d'états KV sur `voice_hash(v)`, et cette fonction **n'échantillonne
que les seize premiers flottants** du tenseur de voix. En préfixant le BOS dans `encode_voice`,
ces seize flottants deviennent le début du BOS — le même pour tout le monde. Le cache en mémoire
répond donc toujours oui, et chaque personnage après le premier hérite de son état.

Le BOS appartient au conditionnement, pas à l'encodage : c'est exactement où Python le met,
entre `_encode_audio` et la construction de l'état. Déplacé dans le constructeur de `LatentGen`,
juste avant `cond_pass`, il laisse le tenseur caché intact et chaque voix retrouve la sienne.

La leçon à garder est sur `voice_hash` : seize flottants pour distinguer des voix est une
collision qui attend, et rien dans la sortie ne la signale — elle se manifeste comme un
personnage qui a la voix d'un autre.

### La phrase courte perdue : encore une valeur de config que le runtime ignore

`french_24l.yaml` porte `model_recommended_frames_after_eos: 8`, et Python s'en sert pour
**toutes** les phrases. En son absence, Python devine : `3 + 2 = 5` images pour une phrase de
quatre mots ou moins, `1 + 2 = 3` sinon. Le C++ code exactement ces deux constantes :

```cpp
int eos_extra = cfg_eos_extra >= 0 ? cfg_eos_extra : ((nwords <= 4) ? 5 : 3);
```

**Le français est la seule des douze configurations à déclarer cette valeur.** Le runtime a donc
raison pour onze modèles et tort pour le nôtre — le même motif que le BOS, à l'envers.

Et cette fois il n'y a rien à écrire : `--eos-extra 8` existe déjà.

| « Laisse tomber. » seule | durée |
|---|---:|
| C++, réglage automatique | 0,48 s |
| C++, `--eos-extra 8` | **0,72 s** |
| Python, référence | **0,72 s** |

La réplique entière, voix de Judy : 5,11 s en C++ contre 5,12 s au banc. Les deux chemins se
rejoignent.

### Le bilan des trois défauts

Aucun n'était dans notre code, et aucun n'est une modification de graphe :

| défaut | nature | correctif |
|---|---|---|
| BOS avant la voix | tenseur non exporté | 4 Ko + ~15 lignes dans `encode_voice`… **non**, dans `LatentGen` |
| voix partagées | `voice_hash` sur 16 flottants | placer le BOS après l'encodage |
| phrase courte tronquée | valeur de config ignorée | `--eos-extra 8`, drapeau existant |

Deux d'entre eux ont la même racine : `PocketTTS.cpp` a été bâti contre `english_2026-01`, et
chaque champ de configuration où le français s'écarte de ce modèle est un champ que le runtime
ne lit pas. Il faut supposer qu'il en reste.

---

## Quatrième défaut : une phrase par passe

Verdict sur le second correctif : la phrase courte **seule** est correcte (`cpp3-judy-courte`),
mais la même phrase **en fin de réplique** reste inaudible, et le rendu de Panam est coupé.
Deux symptômes, une cause, et elle n'est plus dans les valeurs de configuration.

Python ne génère pas phrase par phrase. `generate_audio_stream` appelle
`split_into_best_sentences(tokenizer, text, max_tokens)` avec `MAX_TOKEN_PER_CHUNK = 50` : il
**empile** les phrases jusqu'à ce budget. La réplique du banc fait 27 jetons, donc Python la dit
en **une seule passe**.

Le runtime C++ découpe sur la ponctuation, sans budget, et génère chaque phrase indépendamment
en repartant de l'état de voix :

```cpp
auto sentences = split_sentences(text);
for (size_t i = 0; i < sentences.size(); ++i) { ... }   // une generation chacune
```

« Laisse tomber. » devenait donc une génération de cinq jetons partie de zéro — le cas où ce
modèle dégénère, et celui que `pad_with_spaces_for_short_inputs` existe pour rattraper côté
Python. Seule, la même phrase a le contexte que lui donne son propre conditionnement et sort
correctement ; c'est ce qui rendait le symptôme illisible.

Porter le budget de jetons corrige les deux symptômes et **divise le temps par trois** — une
génération au lieu de deux, sans le fondu enchaîné entre elles :

| | avant | après |
|---|---:|---:|
| judy | 4,87 s d'audio en 6,81 s | 4,72 s en **1,97 s** |
| panam | 3,19 s (coupé) | 7,52 s en 3,01 s |
| takemura | 5,11 s | 6,48 s en 2,81 s |

### Le rendu Python vide était une faute de mon banc

`generate_audio` **mute** l'état de voix : `copy_state` vaut `False` par défaut. Le script qui a
produit `py-judy-courte.wav` réutilisait le même état pour deux rendus successifs. Avec un état
neuf par rendu, la phrase courte sort à 0,72 s comme en C++. Aucune conclusion à tirer de ce
fichier — la faute était dans la mesure, pas dans le moteur.

---

## Cinquième symptôme : la voix déformée, et ce qui est écarté

Verdict sur le regroupement : les phrases sont complètes, mais **la voix est déformée**.

Deux hypothèses écartées par la mesure, avant toute autre :

- **écrêtage à la conversion.** Le moteur rend du flottant, le banc convertit en PCM 16 bits en
  bornant à ±1. Mesuré sur les trois rendus : crêtes de 0,27 à 0,59, **zéro échantillon
  écrêté**. La conversion n'y est pour rien.
- **un rendu trop faible.** Les valeurs efficaces des rendus C++ (0,027 à 0,065) encadrent celle
  de la référence Python (0,041). Ce n'est pas un problème de niveau.

Le seul écart entre le rendu déformé et le précédent est la **longueur de la génération** :
27 jetons d'un coup au lieu de 22 puis 5. D'où le suspect suivant, et il touche le cœur de la
décision de distribution : **l'INT8 dérive-t-il sur une passe longue ?**

Le même jeu rendu en `--precision fp32`, à comparer à l'oreille :

| | INT8 | fp32 | Python |
|---|---:|---:|---:|
| judy | 4,72 s en 1,97 s | 6,56 s en 3,53 s | 6,64 s |
| panam | 7,52 s en 3,01 s | 4,88 s en 2,75 s | — |
| takemura | 6,48 s en 2,81 s | 5,68 s en 3,14 s | — |

Le fp32 est 1,8x plus lent et rend encore ~1,9x le temps reel, donc il reste jouable. Ce qu'il
coute est ailleurs : 1209 Mo au lieu de 303 pour le seul `flow_lm_main`, ce qui rouvre en grand
la question du paragraphe « Gate 2 ».

**Aucune mesure ne distingue les deux.** Cretes, valeurs efficaces et durees sont du meme ordre.
Si l'oreille les separe, c'est l'oreille qui a raison, et c'est la quatrieme fois dans ce
document.

### Rectification : `py-judy-courte` n'etait pas une faute de banc

Ecrit plus haut que le rendu Python vide venait de `copy_state`. **Faux** : avec un etat neuf
par rendu, `py-judy-courte2.wav` est toujours juge vide a l'oreille, alors qu'il mesure une
crete de 0,457 et une valeur efficace de 0,046 -- donc du signal franc, mais pas des mots. Le
premier fichier, lui, etait reellement silencieux (crete 0,006), et pour cette raison-la.

Il reste donc un cas ouvert : **une phrase de deux mots rendue seule**, que le C++ dit
correctement et que Python ne dit pas. Il n'entre pas dans le chemin du mod -- une replique
arrive en phrases groupees -- mais il n'est pas explique.

### L'INT8 est bien la cause -- reste a savoir lequel

Verdict : `fp32-judy` et `fp32-takemura` sont corrects. La quantification est donc responsable,
et le seul chiffre qui compte maintenant est *lequel des trois modeles quantifies* deforme.

Le runtime ne choisit qu'une precision pour les trois -- un seul suffixe `_int8`. On la
contourne sans toucher au code : presenter le fichier fp32 **sous le nom int8**. Trois rendus,
un modele en fp32 chacun, et ce que chacun couterait :

| jeu de modeles | poids | fichiers |
|---|---:|---|
| tout INT8 | 392 Mo | `cpp4-*` -- deforme |
| **decodeur en fp32** | **410 Mo** | `mixdec-*` |
| **flow en fp32** | **421 Mo** | `mixflow-*` |
| **principal en fp32** | **1 297 Mo** | `mixmain-*` |
| tout fp32 | 1 345 Mo | `fp32-*` -- correct |

Les deux premieres lignes coutent moins de trente megaoctets. La troisieme coute presque un
gigaoctet et remet le pack francais hors de portee d'un telechargement Nexus ordinaire. C'est
donc cette ecoute qui decide du poids du mod, pas la precedente.

### Le bruit de fond de Panam est un probleme de donnee, pas de moteur

`fp32-panam` porte du bruit au demarrage, ce que ni Judy ni Takemura ne font. Sa reference est
un collage de six a neuf repliques tirees du jeu ; si l'une vient d'une scene bruyante, le
modele clone l'ambiance avec la voix. Mesure des deux premieres secondes de `dist\voices\`, en
valeur efficace par demi-seconde :

```
judy       0,1071  0,0907  0,0999  0,0717
panam      0,1457  0,0485  0,0388  0,1468
takemura   0,0268  0,0747  0,1004  0,0948
```

Rien de concluant a ce niveau -- le creux central de Panam est un silence entre repliques, pas
du bruit. La verification appartient a `tools\voice-extract` : ecouter sa reference, et couper
la replique fautive de la recette. Aucun rapport avec la precision ni avec le runtime.

### Le coupable est le petit modele, pas le gros

Verdict : `mixflow` est bon, `mixmain` a des erreurs et de la musique. Le fautif est donc
**`flow_lm_flow`**, 9,8 M parametres -- et le gros `flow_lm_main`, 302 M, supporte parfaitement
la quantification. Le decodeur aussi.

Ce n'est pas contre-intuitif une fois pose : `flow_lm_flow` est le solveur qui raffine un
latent par integration. Une erreur de quantification y est reinjectee a chaque pas, la ou le
transformeur autoregressif la dilue. La taille d'un modele ne dit rien de sa sensibilite.

**Ne pas quantifier ce fichier coute 29 Mo** -- 9,9 Mo en INT8 contre 39,1 en fp32 -- au lieu
des 906 Mo qu'aurait coutes le gros modele. La question du poids ne se rouvre pas.

### La recette retenue

```
flow_lm_main_int8.onnx     303,3 Mo    quantifie
flow_lm_flow.onnx           39,1 Mo    fp32 -- ne jamais quantifier
mimi_decoder_int8.onnx      22,6 Mo    quantifie
text_conditioner.onnx       16,4 Mo
tokenizer.model              0,1 Mo
bos_before_voice.bin         4 Ko      sorti du checkpoint, absent de l'export amont
                           ────────
pack libre                 381,5 Mo
+ mimi_encoder.onnx         39,3 Mo    pack de clonage local seulement
                           ────────
pack clonage               420,8 Mo
```

Mesure de cette recette, `--eos-extra 8`, voix en cache :

| | |
|---|---|
| debit | **2,2 a 2,4x temps reel** |
| premier son en streaming | **123 ms** |
| judy, la replique du banc | 6,72 s d'audio en 2,79 s |

La reference Python donne 6,64 s pour la meme replique. Les deux chemins se rejoignent en duree
et, a l'oreille, en qualite.

---

## L'outillage, sorti du bac a sable

`tools\pocket-engine\` reproduit tout ce qui precede sans rien de cette session :

| | |
|---|---|
| `build.ps1 -Fetch` | clone PocketTTS.cpp, dr_libs, SentencePiece ; telecharge ONNX Runtime |
| `patch-runtime.py` | les trois ecarts du runtime, idempotent, annulable par `git checkout` |
| `build.ps1` | SentencePiece puis le moteur, avec `cl.exe` seul |
| `export-models.py` | le jeu de modeles d'une langue, pack libre ou pack de clonage |

Verifie le 2026-09-01 : la compilation part de zero et aboutit a `pocket-tts.exe` (723 Ko), et
l'export produit **381,50 Mo identiques bit pour bit** a ceux qui ont ete valides a l'oreille.
La copie amont et les modeles sont ignores par git -- le patch a une seule source de verite,
son script.

### Ce que le pack libre ne sait pas encore faire

Il ne contient pas `mimi_encoder.onnx`, et le runtime ne sait designer une voix que par un
fichier WAV qu'il donne a cet encodeur. **Le pack qui part sur Nexus n'est donc pas encore
jouable** : il lui faut charger un etat KV tout pret, ce que Kyutai livre pour ses vingt-six
voix de catalogue. C'est le prochain travail sur le moteur, et il est independant des cinq
defauts ci-dessus.

Le pack de clonage, lui, tourne : c'est celui qui a produit tous les rendus de ce document.

---

## Sixieme ecart, trouve en lisant : le rembourrage des phrases courtes

`prepare_text` rembourre toute phrase de moins de cinq mots avec huit espaces, sans condition :

```cpp
// Pad short text - model doesn't perform well with very few tokens
if (nwords < 5)
    text = "        " + text;  // 8 spaces, matching Python
```

Le commentaire dit vrai et se trompe de modele. Cote Python, ce rembourrage est garde par
`pad_with_spaces_for_short_inputs`, et **`english_2026-01` est la seule des douze configurations
a le mettre a `true`**. Le francais vaut `false`, donc Python ne rembourre pas ce que le runtime
rembourre.

Troisieme champ ou ce meme modele est le seul de son espece, apres `insert_bos_before_voice`
et `model_recommended_frames_after_eos`. Le motif n'a plus rien d'une coincidence : le runtime
est un portage fidele **d'un checkpoint**, pas du paquet.

Trouve en lisant, pas en ecoutant -- le premier des six. **Son effet audible n'est pas mesure** :
c'est une divergence par rapport a la reference, et il faudra une ecoute pour dire si la retirer
change quoi que ce soit au francais.

### Ce que SkyrimNet fait du meme probleme

SkyrimNet livre PocketTTS parmi huit moteurs, dans une DLL en processus, et annonce que
« la synthese commence a lire la premiere phrase pendant que le modele ecrit la seconde ». Il
donne donc bien **une phrase a la fois** au moteur, ce que `AiNpcCallSystem.SpeakStreamed` fait
deja de son cote.

Cela n'invalide pas l'avertissement, cela l'explique : SkyrimNet est anglais, et le modele
anglais **rembourre ses phrases courtes** la ou le francais ne le fait pas. La degenerescence
qui nous a coute trois ecoutes est probablement invisible dans leur langue.

---

## Etape 2 : le moteur dans `ai_npc.dll`

Bati le 2026-09-01. Vert hors ligne, **jamais lance**.

`pocket_tts.cpp` se compile dans la DLL avec `/DPTT_SHARED_LIB`, ce qui retire son `main()` et
garde l'API C que l'amont a ecrite pour etre embarquee. La DLL passe de 0,2 a 0,9 Mo et importe
`onnxruntime.dll`, 14,2 Mo, qui voyage a cote d'elle.

### Le decoupage

| fichier | responsabilite |
|---|---|
| `plugin\PocketVoice.cpp` | le moteur embarque : disponibilite, voix par contact, rendu en PCM |
| `plugin\SapiVoice.cpp` | la voix de Windows, sortie de `Speech.cpp` pour devenir un moteur parmi deux |
| `plugin\Speech.cpp` | la file, le worker, le choix du moteur, la remise a la voie audio |

Le choix se fait **par personnage et a chaque replique** : pack de modeles present *et*
`<contact>.wav` dans `r6\storages\AiNpc\voices\` donne la voix du personnage, tout le reste
donne celle de Windows. Un joueur qui a Judy et pas Rogue est dans l'etat normal, pas dans un
cas degrade.

`AiNpcAudio.Speak` prend un second parametre, `contactId` -- c'est l'etape 3 du brief, et elle
etait effectivement deux lignes. La ligne de V passe `"v"`, pour laquelle aucune recette ne
produit de reference : elle sort donc par la voix de secours, et sortira par la sienne le jour
ou un joueur en depose une, sans qu'une ligne change.

### Ce qui n'est pas fait, et pourquoi

**Le premier son n'arrive pas en 120 ms.** `PocketVoice::Render` accumule toute la replique
avant de la remettre, parce que `audio::Play` REMPLACE ce qui joue : livrer les morceaux un par
un ne ferait entendre que le dernier. Le streaming demande une voie audio qui enchaine, et c'est
l'etape 5 du brief.

**Une phrase courte remise seule reste le cas fragile.** `SpeakStreamed` donne une phrase a la
fois, donc le regroupement a 50 jetons ne peut rien pour elle. Le francais n'a pas le
`pad_with_spaces_for_short_inputs` qui protege l'anglais, et c'est pour cela que SkyrimNet ne
rencontre pas le probleme.

### Ce qu'il faut installer, et quoi lire

Deux archives, par Vortex, plus une copie a la main :

1. `dist\ai_npc.zip` -- le mod, avec les deux DLL ;
2. `dist\ai_npc-voice-fr-cloning-DO-NOT-PUBLISH.zip` -- 258 Mo, le pack local ;
3. `dist\voices\*.wav` et `voices.json` a copier dans `r6\storages\AiNpc\voices\` --
   `r6\storages\` n'est pas gere par Vortex, c'est le seul dossier ou une copie manuelle est
   sans risque.

Dans `red4ext\logs\ai_npc-*.log`, au premier appel :

```
AiNpc.AiNpcAudio registered.
Call: 'judy' says '...'. speak: queued; previous: pocket -- ok -- 229000 bytes in 2800 ms
```

**Le mot qui decide est `pocket` ou `sapi`.** `sapi` veut dire que la voie neuronale a ete
ecartee, et la raison suit sur la meme ligne : pack absent, pas de reference pour ce contact,
ou modele refuse. Rien d'autre dans le jeu ne distingue les deux.

---

## Le pipeline technique complet : le core detecte le pack et fabrique ses references

Bati le 2026-09-01. Vert hors ligne, **jamais lance**.

Decision : `dist\ai_npc-voice-fr-cloning-*.zip` installe est le declencheur. Sa presence -- lue
comme `mimi_encoder.onnx` sur le disque -- autorise le clonage, donc autorise l'extraction, donc
la DLL fabrique la reference d'un personnage a sa premiere replique. Sans le pack, rien de tout
cela n'arrive et la voix de secours parle. Il n'y a plus d'etape manuelle.

### Les trois portes, mesurees avant d'ecrire

| question | reponse |
|---|---|
| les `.wem` de doublage sont-ils lisibles sans Oodle ? | **oui** -- un seul segment, jamais compresse, verifie sur l'archive francaise |
| Cyberpunk a-t-il besoin des codebooks externes ? | **oui** -- l'inline echoue sur « nonsense codeword length », `packed_codebooks_aoTuV_603.bin` passe |
| la sortie de ww2ogg se decode-t-elle telle quelle ? | **oui** -- stb_vorbis la lit sans revorb : 4,17 s, crete 0,448 |

### Le decoupage

| fichier | responsabilite |
|---|---|
| `plugin\VoiceArchive.cpp` | lire une replique dans une archive RDAR, par son hachage |
| `plugin\VoiceMake.cpp` | recette -> repliques -> decodage -> montage -> `<contact>.wav` |
| `vendor\ww2ogg` | Wwise Vorbis -> Ogg, patche pour lire en memoire |
| `vendor\stb\stb_vorbis.c` | Ogg -> PCM |

Les archives sont ouvertes en `FILE_SHARE_READ | FILE_SHARE_WRITE` : le jeu tient les memes
fichiers ouverts, et un lecteur ne doit jamais poser un verrou plus fort que ce qu'il lit.

### Verifie contre l'outil C#

Les neuf references refaites par le code de la DLL, depuis les memes archives et la meme
recette :

| | outil C# | DLL |
|---|---|---|
| duree, RMS, crete | -- | **identiques a la quatrieme decimale sur les neuf** |
| cout | 18 s au depart a froid | **~200 ms par personnage** |

Elles ne sont PAS identiques octet pour octet, et ce n'etait pas le bon critere : le C# decode
avec NVorbis, la DLL avec stb_vorbis. Trois des neuf ne different que de -73 dB -- du bruit
d'arrondi. Les six autres portent une replique dont la longueur decodee differe d'un echantillon,
ce qui decale le montage sans en changer le contenu ; c'est ce que dit l'egalite des durees et
des niveaux.

Les ~200 ms confirment la mesure du § 5 du plan, et ils tombent dans l'aller-retour vers le
modele, ou personne ne les voit.

### Ce qui voyage, et ou

| fichier | archive | pourquoi la |
|---|---|---|
| `voices-recipe.json` | le **mod** | il depend de la version du JEU, pas du modele |
| `packed_codebooks_aoTuV_603.bin` | le **pack de clonage** | inutile sans l'encodeur |

### A ecouter

`refdll-judy-argot.wav` et `refdll-takemura-argot.wav` : la meme replique, clonee depuis les
references que **la DLL** a fabriquees. A comparer aux `final-*`, qui venaient de celles de
l'outil C#. Une reference de la bonne duree et du bon niveau n'est toujours pas une reference
correcte -- c'est la cinquieme fois que cette phrase s'ecrit ici.

---

## Premier lancement en jeu : ce que le journal a dit

2026-09-01, `red4ext\logs\ai_npc-*.log`, apres installation du mod et du pack de clonage.

**L'extraction a marche.** `r6\storages\AiNpc\voices\judy.wav` porte l'horodatage de la partie :
la DLL a ouvert les archives du joueur, decoupe les six repliques de la recette et ecrit
l'extrait, sans WolvenKit, sans SDK .NET et sans copie manuelle. C'est le § 5 du plan, en jeu.

**Deux defauts, tous les deux nommes par le journal**, ce qui etait le seul but de cette ligne :

```
sapi -- ok -- 180770 bytes in 139 ms -- no reference for v: the recipe has no lines for v;
sapi -- ok --  99634 bytes in  67 ms -- neural voice fell back: the speech model refused to load;
```

### Le premier : la ligne de V n'avait aucune voix a prendre

Le POC s'eprouve en tapant un message, et cette ligne appartient a V. Elle passait `"v"`, dont
aucune recette ne produit d'extrait, donc elle sortait par la voix de secours -- et la voie
neuronale n'etait jamais atteinte par le seul geste rapide dont on dispose.

Elle passe desormais le contact de la conversation. **C'est un choix de POC et il coute quelque
chose** : V s'entend avec la voix de son interlocuteur. Ce qu'il donne est le seul controle de la
chaine complete -- archives, extraction, clonage, lecture -- depuis une touche.

### Le second : le pack livre un fichier que le moteur ne cherchait pas

`--precision int8` fait ajouter `_int8` aux trois modeles quantifiables, sans regarder le
disque. Or la recette livre `flow_lm_flow` **en fp32**, et pas par oubli : quantifie, il deforme
la voix. Le moteur cherchait donc `flow_lm_flow_int8.onnx`, ne le trouvait pas, et `ptt_create`
echouait derriere un message qui ne nommait aucun fichier.

Le banc ne pouvait pas le voir : la mesure de precision melangee presentait le fichier fp32
**sous le nom int8**, par lien dur. Le pack, lui, porte son vrai nom.

Le correctif est un repli : `<nom>_int8.onnx` s'il existe, `<nom>.onnx` sinon. Le pack devient
auto-descriptif -- ce qui est livre est ce qui est charge -- et l'affaire ne peut plus se reposer
pour un autre modele. Verifie contre le jeu de modeles livre tel quel : le moteur charge, et
`ship-judy-argot.wav` est rendu depuis la reference que **la DLL a fabriquee en jeu**.

C'est le cinquieme ecart au runtime amont, et le premier qui ne vienne pas d'un champ de
configuration : celui-la vient de notre propre recette.

---

## Le prechauffage : sept secondes payees pendant la sonnerie

Bati le 2026-09-01 apres validation du POC. Vert hors ligne, jamais lance.

`AiNpcAudio.Warm(contactId, locale)` prepare une voix sans rien dire, et rend la main aussitot.
Ce qu'elle paie d'avance :

| | cout | frequence |
|---|---:|---|
| charger le modele | ~2,5 s | une fois par session |
| tailler la reference dans les archives | ~250 ms | une fois par personnage |
| cloner la reference | ~3 s | une fois par personnage |

Rien de cela ne depend de ce qui sera dit, donc rien n'oblige a le payer apres. Elle est appelee
a l'entree dans `Ringing`, et la sonnerie dure vingt secondes.

Elle passe **devant** dans la file du worker, et c'est la seule chose qui la distingue d'une
replique : une preparation arrivee apres la premiere replique n'aurait rien prepare. Elle ne
descend jamais jusqu'a la voix de secours -- SAPI n'a rien a preparer -- et son resultat se lit
dans le journal comme `warmed judy in 5800 ms`.

---

## La voix dans la fiche : deux paliers, deux entrees

Bati le 2026-09-01. Vert hors ligne, jamais lance.

```json
{"contactId": "judy", "voice": {"clone": "judy.wav", "fallback": "eve"}}
```

Declare dans `AiNpcCastJudy.reds` et surchargeable par le JSON, comme tout le reste d'une fiche.
C'est une donnee de personnage et pas un reglage : « la voix de Judy » ne se choisit pas dans un
menu, elle est un fait sur elle.

| entree | ce qu'elle nomme | defaut |
|---|---|---|
| `clone` | le fichier de reference dans `r6\storages\AiNpc\voices\` | `<contactId>.wav` |
| `fallback` | la voix du catalogue de PocketTTS | aucune, et la voix du systeme derriere |

Les neuf fiches portent desormais le repli qui vivait dans `tools\tts-lab\fallback-voices.json`
-- une table corrigee a l'oreille, qui etait hors du mod et qui n'y serait jamais entree seule.

**Le choix ENTRE les paliers reste a la DLL**, parce qu'il depend de ce qui est sur le disque et
que le disque change sans que le jeu redemarre : un pack installe en cours de partie doit
s'entendre.

### Ce qui est vivant, et ce qui ne l'est pas encore

`clone` est lu et utilise : `AiNpcVoiceChoiceFor` repond, `Speak` et `Warm` le portent, et
`VoiceMake` ecrit le fichier que la fiche nomme au lieu d'en deduire un.

**`fallback` est ecrit et n'est lu par personne.** Il attend le chargement d'un etat de
catalogue, qui n'existe pas dans le moteur. C'est nomme ici plutot que decouvert plus tard : la
table est de la connaissance acquise a l'oreille et elle est mieux dans les fiches que dans un
JSON d'outillage, mais elle ne fera parler personne tant que ce chargement n'est pas ecrit.

### Ce que le chargement de catalogue demandera

Verifie le 2026-09-01, sans l'ecrire : les « embeddings » de Kyutai et le cache `.kv` du runtime
sont **le meme objet** -- l'etat KV du transformeur apres conditionnement. Les formes
correspondent : `(2, 1, 133, 16, 64)` fp32 par couche d'un cote, `cache_k` / `cache_v` fp16
`[1, 1000, 16, 64]` plus un `offset` de l'autre. La conversion est un rempaquetage : fp32 vers
fp16, remplissage jusqu'a 1000, `offset = 133`.

Les deux cotes trient leurs couches **par chaine** -- `layers.0`, `layers.1`, `layers.10`,
`layers.11`, ... `layers.2` -- ce qui est le meme ordre des deux cotes et le piege evident si on
suppose un tri numerique. Un etat mal ordonne donnerait une voix qui babille, et ce document
sait a quoi cela ressemble.

---

## Le palier catalogue : le pack libre parle

Bati le 2026-09-01. Le moteur a ete entendu hors du jeu ; la voie complete est verte hors ligne
et n'a pas ete lancee.

C'etait le trou qui rendait la moitie distribuable muette : sans encodeur, le moteur ne peut pas
fabriquer une voix a partir d'un son. Mais il peut en CHARGER une deja faite, et Kyutai en livre
vingt-six par langue.

### La conversion

Les « embeddings » de Kyutai et le cache `.kv` du runtime sont le meme objet. `export-catalogue.py`
rempaquette l'un vers l'autre, et deux details font toute la difficulte :

- **deux ordres qui n'en sont pas un.** Les cles safetensors se listent en ordre de CHAINE --
  `layers.0`, `layers.1`, `layers.10`, ... `layers.2` -- tandis que les entrees `state_*` du
  graphe sont en ordre NUMERIQUE. Suivre l'ordre du fichier melangerait les couches, et un etat
  melange donne une voix qui babille sans que rien ne le signale ;
- **le fp16 se lit en tranche.** `restore_from_disk` compare la forme livree a celle que le
  graphe attend et replace la tranche dans le tampon complet. On ecrit donc les 133 images
  telles quelles, ce qui divise le poste par deux au passage : **120 Mo pour neuf voix** au lieu
  des 235 Mo annonces plus haut en fp32.

Les voix converties sont celles que les FICHES nomment, lues dans les sources. Une voix ajoutee
a une fiche entre dans le pack sans qu'on y pense ; une voix que personne ne nomme n'y entre pas,
et vingt-six existent.

### Le piege evite, qui etait deja connu

Une voix de catalogue n'a pas de latents. `voice_hash` echantillonne les seize premiers flottants
du tenseur de voix -- et deux tenseurs vides sont egaux. Le meme defaut que le correctif du BOS
avait cree : le deuxieme personnage avec la voix du premier.

Le patch hache donc **le nom** quand il y en a un. C'est exact au lieu d'etre probabiliste, et la
collision disparait pour tout le monde, pas seulement pour le catalogue.

### Mesure

Trois voix, dossier de references VIDE, aucun encodeur sollicite :

| voix | duree | rendu |
|---|---:|---:|
| `eve` (judy) | 5,28 s | 1,85 s |
| `paul` (takemura) | 4,72 s | 1,74 s |
| `mary` (panam) | 4,16 s | 1,46 s |

**Deux fois plus rapide que le clonage**, et pour une raison structurelle : il n'y a rien a
cloner. L'etat se restaure en quelques millisecondes la ou le conditionnement d'un WAV coute
trois secondes.

### Ce que les paliers donnent maintenant

| ce qui est installe | ce qu'on entend |
|---|---|
| rien | la voix de Windows |
| pack libre | neuf voix de catalogue distinctes, une par personnage |
| pack de clonage + archives du joueur | la voix du jeu, taillee sur place |

Et le choix se fait **par personnage a chaque replique** : Judy clonee, Rogue au catalogue et un
contact tiers sur Windows coexistent dans la meme partie.

| livrable | poids |
|---|---:|
| `ai_npc.zip` | 6,2 Mo |
| `ai_npc-voice-fr.zip` -- **publiable** | 346 Mo |
| `ai_npc-voice-fr-cloning-DO-NOT-PUBLISH.zip` | 364 Mo |

---

## La passe `holo` : une replique dite est sa propre passe

Batie le 2026-09-01. Verte hors ligne, jamais lancee. Rien ne change pour une installation qui
ne la relie pas.

Le mecanisme existait -- `passes` lie un slot et une recette, `docs\PLAN_PASSES.md` -- et il
attendait un cinquieme cas. Une replique dite en est un :

```json
{"passes": {"holo": {"slot": "dialogue", "recipe": "spoken"}}}
```

### Ce que la passe ouvre, et ce qu'elle ne change pas

Elle rend **exactement les memes deux messages** que la passe ecrite. C'est un personnage qui
parle dans les deux cas, donc le meme vocabulaire de blocs s'applique, et le meme constructeur
les batit. Ce qu'une passe distincte ouvre est une reliure :

- **un autre slot**, parce qu'une replique dite est plus courte et peut vivre sur un modele
  moins cher que celle qu'on relit ;
- **une autre recette**, parce que ce qui est dit ne se relit pas : la regle de longueur et la
  regle de forme sont les deux qu'on voudra changer en premier ;
- **deux totaux separes** dans le rapport du jour, entre une soiree d'appels et une soiree de
  textos.

Non reliee, elle se comporte comme la passe ecrite : le slot suit celui de `speaking` -- comme
le fait deja le test, et pour la meme raison -- et la recette est l'active.

### Le linter a corrige la conception avant qu'elle ne soit fausse

La premiere version repondait deux noms depuis `AiNpcPassConversation.Pass()`, selon un champ
`channel`. La regle « a request is assembled in one place » l'a refusee :

```
pass AiNpcLaneHolo() is in AiNpcPassNames and no builder declares it
```

Et elle avait raison. Une passe a un constructeur, un constructeur declare une passe ; une
methode qui repond deux noms selon un champ est une passe qu'aucune regle ne peut plus compter,
ni relier, ni totaliser. `AiNpcPassSpoken` est donc une classe, et le choix vit au seul endroit
qui connait le canal.

---

## G appelle, T ecrit

Bati le 2026-09-01. Vert hors ligne, jamais lance.

Deux verbes sur la meme ligne de la liste de contacts, et la ligne est celle que le composeur
designe -- aucun repli sur « le dernier contact », qui ouvrirait ce que le joueur ne montrait
pas. Le controle « on est bien sur la liste » vit avec les touches, parce que c'est un fait sur
elles : une ligne n'existe que sur cet ecran, et toutes les autres entrees nomment leur contact.

R et F appartiennent au jeu sur cet ecran. **Le mod ne mesure pas ce que le jeu lie** : il sait
seulement ce qu'il prend lui-meme, et G est le choix du joueur.

Le systeme d'appel repond par une phrase, qui va au journal telle quelle -- un refus a trois
causes, deja en ligne, contact inconnu, pas de session, et les trois se corrigent differemment.
Rien n'est ferme : la sonnerie est celle du jeu, et le telephone se comporte comme pour
n'importe quel appel entrant.

Pas d'indice a l'ecran, comme T n'en a pas : le bandeau appartient a l'ecran de chat.

---

## Le decroche est un evenement : la sonnerie EST le chargement

Bati le 2026-09-01. Vert hors ligne, jamais lance.

Le POC n'avait pas de decroche : il fallait un bouton dans la fenetre CET. Un delai fixe aurait
repondu, mal -- trop court, le personnage decroche et parle ensuite avec la voix de Windows ;
trop long, une machine prete depuis dix secondes sonne dans le vide. La chose qu'on attend est
la voix, alors c'est elle qu'on attend.

`AiNpcAudio.VoiceState(contactId)` repond un mot, et la voie d'appel en fait trois conduites :

| reponse | conduite |
|---|---|
| `ready` | on decroche |
| `unavailable` | on decroche **aussi, tout de suite** -- il n'y a rien a attendre |
| `unknown` | idem : personne ne prepare cette voix, donc rien n'arrivera |
| `pending` | on redemande dans 500 ms |

Quatre reponses et pas un booleen, parce que confondre `ready` et `unavailable` ferait sonner
vingt secondes pour rien une installation sans pack de modeles -- exactement le cas le plus
courant chez un joueur qui vient d'installer le mod seul.

Le delai de vingt secondes reste, comme **filet** : il mene a `Missed`, et c'est ce qui arrive
quand une voix ne devient jamais prete.

### Ce que cela range

Sept secondes de chargement cessent d'etre une attente et deviennent une sonnerie. Le joueur
n'entend pas une barre de progression : il entend un telephone, et quelqu'un decroche quand il
est pret a parler. C'est la regle « les personnages reagissent » de `CLAUDE.md` appliquee a un
cout technique -- l'etat change, un personnage l'annonce, et rien dans le HUD n'a besoin de le
dire.

---

## Etape 5 : la voie audio enchaine, et le premier son n'attend plus

Bati le 2026-09-02. Vert hors ligne, jamais lance.

Il y avait deja du streaming a deux etages -- le modele vers le texte, phrase par phrase, et le
moteur vers les echantillons, morceau par morceau. **La jonction manquait** : `ainpc::audio`
n'avait qu'un emplacement, et son contrat le disait -- *« a second call replaces what is
playing »*. Livrer les morceaux un par un n'aurait donc fait entendre que le dernier, et
`PocketVoice` les accumulait jusqu'a la fin de la synthese.

`Open(format)` / `Push(bytes)` / `Close()` : plusieurs `waveOutWrite` sur un peripherique qui
reste ouvert. « Une voix a la fois » ne bouge pas -- c'est la meme voix, elle arrive en plusieurs
fois, et `Open()` coupe la precedente comme un second `Play()` le faisait. `Play()` devient
Open + Push + Close, donc aucun appelant existant ne change.

### Ce que le banc de falsification a corrige

L'assertion ecrite d'abord comparait la DUREE : huit morceaux joues a la file durent huit fois un
morceau. Mesuree sur un banc minimal, elle ne prouvait rien :

```
emplacement (Play x8)  : 696 ms
file (Open/Push/Close) : 451 ms
```

L'emplacement est **plus long**, parce qu'il ouvre et ferme le peripherique huit fois -- tout en
ne faisant entendre qu'un seul morceau. La duree d'horloge ne separe pas les deux.

Ce qui les separe est ce qui RESTE a jouer. Cent cinquante millisecondes apres avoir remis 400 ms
de son :

```
emplacement : joue encore ? non
file        : joue encore ? oui
```

Verifie dans les deux sens avant d'etre ecrit dans la suite. Une assertion qui ne peut pas
echouer ne prouve rien, et celle-la ne le pouvait pas.

### Un plantage a la sortie, trouve au passage

Le fil de vidange se termine seul quand la prise est finie, et l'objet `std::thread` reste
**joignable** tant que personne ne l'a joint. Detruire un `std::thread` joignable appelle
`std::terminate` : un hote qui sort sans `Stop()` plantait a l'exit, apres avoir tout joue
correctement -- code 0xC0000409, mesure le 2026-09-02.

Le mod ne le voyait pas parce que `speech::Shutdown()` appelle `Stop()`, qui joint. Le banc, lui,
n'appelait rien. `Voice` a maintenant un destructeur qui coupe et joint.

### Ce que cela donne

| | avant | apres |
|---|---|---|
| premier son | fin de la synthese de la premiere phrase, 1 a 3 s | **~123 ms** |
| prechauffage | rendait un tampon jete | rend en mode muet, sans ouvrir le peripherique |
| repli SAPI | inchange | inchange -- il rend un tampon entier, joue par `Play()` |

---

## Un appel ne demandait rien au modele — corrige le 2026-09-02

Rapporte en jeu : G appelle Judy, elle decroche, le joueur tape une ligne, et **Judy lit le
texte du joueur**. Aucune reponse, rien de classe.

Deux causes, et les deux sont a moi.

### `ReportSpoken` ne faisait que parler

Son propre commentaire l'annonçait — *« Nobody answers it yet »* — et c'etait vrai depuis le
debut : la fonction synthetisait la ligne de V et la jouait, ce qui eprouvait la voie parlee
sans ouvrir aucune conversation. Tout ce qui a ete bati depuis — le moteur, les paliers, la
passe `holo`, le bloc `<channel>` — construit le PROMPT d'un appel ; rien ne partait le
demander.

Je ne l'ai pas vu parce que j'ai lu ce commentaire une fois, tot, et que j'ai ensuite decrit la
voie comme complete. Elle ne l'etait pas.

### Et la ligne de V sortait avec la voix du personnage

Le compromis de POC : `ReportSpoken` passait `this.m_contactId` au lieu de `"v"`, pour eprouver
le clonage depuis une touche. D'ou « Judy lit mon texte » — c'etait litteralement le montage.

**La ligne de V n'est plus dite du tout**, et ce n'est plus seulement une question de justesse :
la voie audio ne tient qu'une voix a la fois, donc la premiere phrase de la reponse couperait la
ligne de V au milieu.

### Le correctif

La sequence d'un tour appartient au canal, qui l'ecrit une fois pour toutes les surfaces. Elle
demandait une session de chat, qu'un appel n'a pas : la session porte le contact affiche et
l'echo dans la bulle, dont un appel n'a ni l'un ni l'autre.

`AiNpcChannel.SendFrom(contactId, text)` est la meme sequence sans la moitie qui peint —
appeler la voie, classer la ligne. `Send(session, ...)` l'appelle apres son echo, et
`ReportSpoken` l'appelle directement. Une seule sequence : deux copies deriveraient, et la
premiere derive serait un tour envoye au modele sans etre classe.

La voie de retour existait deja : `AiNpcStreamDeliver` porte chaque phrase finie a
`SpeakStreamed`, qui ne parle que sur un appel connecte.
