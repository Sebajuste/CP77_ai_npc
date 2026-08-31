# tts-lab — calibrating the voice, from the best rendering down

**Not a search for a winner.** Every engine is run on this machine, from the best rendering to
the worst, so that the ladder can be measured rather than argued — and the mod ends with
**presets**, chosen by what the player's machine can do. A build with a 4080 and one with an
integrated GPU do not get the same voice, and the only way to say what each gets is to have
measured both ends here.

That is the same shape as the model lanes: one dimension, several tiers, a default that works
everywhere and better options for those who can run them.

Outside the game, on purpose. What decides here is an ear and a stopwatch, and neither needs
Cyberpunk to be running. The mod already plays whatever buffer it is handed
(`plugin/Audio.cpp`); what this answers is what should fill it.

**Every run records the machine it ran on** — CPU, cores, GPU, VRAM — into `out/results.json`,
appended rather than overwritten. A table of timings without the machine that produced them says
nothing about the machine in front of the player, and a preset is exactly a pairing of the two.

Nothing here ships. `tools/` is development tooling — see the table in `CLAUDE.md`.

---

## The questions, in the order that lets you stop

Each one can kill the next. Do them in order.

1. **Does a CPU engine speak acceptable French, faster than real time?**
   If no, the whole "local voice" branch is dead and the answer is a cloud service or nothing.
   Nothing about timbre matters yet.

2. **Does the timbre converter run on that output, on CPU, inside the budget?**
   The converter is the part that makes it Judy rather than a narrator. OpenVoice's converter is
   documented at under 100 ms per utterance and 3–5× real time on one core; this is where that
   claim meets this machine.

3. **Does it sound like her?**
   No metric. Listen to the `.wav` files.

### What question 2 turned out to be

The first plan was Piper plus a tone-colour converter: cheap words, cloned timbre. The
arithmetic worked — `1/13 + 1/4` of real time — and it answered the wrong question. **A
converter changes timbre, not prosody.** Piper's delivery is flat, and converting it to Judy's
timbre yields a robotic Judy. Heard on 2026-08-31, and it is why the ladder starts at the top
now: intonation comes from model capacity (Piper ~20M parameters, XTTS a few hundred, Zonos
1.6B), not from a stage bolted on afterwards.

### The tiers

| tier | what it is | what it needs |
|---|---|---|
| `cloné` | the character's own timbre, prosody generated | a GPU, and a local server |
| `neuronal` | generated prosody, generic voice | CPU only |
| `recollé` | recorded fragments, prosody from rules | nothing at all |

A local server is addressed over HTTP — the shape XTTS and Zonos both take, and SkyrimNet's
design. The API is not guessed: copy `server.example.json` to `server.json` and describe it
there.

The number that matters throughout is **time to first sound**, not total time. A reply that
starts speaking in 400 ms and finishes in four seconds beats one that appears whole in two —
the player is waiting for the first syllable, not the last.

---

## What is measured

For every line and every engine:

| column | meaning |
|---|---|
| `first_ms` | wall time until the first audio byte exists. The one that matters. |
| `total_ms` | until the utterance is complete |
| `audio_s` | how long the result plays for |
| `rtf` | `audio_s / (total_ms/1000)` — above 1.0 is faster than real time |

`first_ms` equals `total_ms` for an engine that has no streaming. That is not a flaw in the
measurement, it is the fact being measured.

---

## Running it

```
python tools\tts-lab\lab.py                 # every engine that is installed
python tools\tts-lab\lab.py --engine sapi   # just one
```

**SAPI needs nothing installed.** It goes through PowerShell's `System.Speech`, which is part of
Windows, so the lab runs on a bare machine and has a reference to compare against — the voice
the mod speaks with today.

Everything else needs models, and downloading a few hundred megabytes is the user's call, not
the agent's:

```
powershell -File tools\tts-lab\fetch.ps1 -Piper
```

## The lines

`lines.json`, and they are deliberately not "testing one two three". A real reply carries
apostrophes, slang, a number, and a length that no demo sentence has. An engine that handles
*Bonjour* and stumbles on *T'as qu'à passer, j'suis à l'atelier jusqu'à 22h* has not been tested.

## Measured, 2026-08-31

SAPI (Windows, concatenative) against Piper `fr_FR-siwis-medium` (neural, CPU), on the six
lines of `lines.json`.

| line | audio | piper `infer_ms` | piper rtf |
|---|---|---|---|
| court | 1.3 s | 97 | 13.0 |
| elisions | 3.6 s | 254 | 14.1 |
| nombre | 2.9 s | 223 | 13.2 |
| argot | 4.8 s | 361 | 13.3 |
| longue | 12.3 s | 936 | 13.2 |
| question | 2.9 s | 198 | 14.5 |

**Question 1 is answered: yes.** A CPU engine speaks French at **13× real time**, steadily,
whatever the length. A reply of the size this mod actually produces — three to five seconds of
speech — costs **200 to 360 ms of model time**. That is not close to a budget; it is a tenth of
one.

It also settles the next question before it is asked. OpenVoice's tone-colour converter is
documented at 3–5× real time on one core. Two stages in series cost `1/13 + 1/4 ≈ 0.33` of
real time — still **three times faster than the speech is spoken**. The two-stage pipeline is
arithmetically viable on CPU, on measured numbers rather than hope.

**Read the columns as they are meant.** `first_ms` and `total_ms` are cold: a process launched
and a 63 MB model loaded for one line. The mod will not do that — SkyrimNet's design, a resident
local service, is exactly the thing those columns are not measuring. `infer_ms` is the model
alone, published by the engine, and it is what a resident process costs.

`first_ms` equals `total_ms` for Piper here because `--output_file` writes everything at the
end. Piper can stream with `--output_raw`, and on the 12-second line that is the difference
between speaking after 936 ms and speaking after the first clause. Worth doing before the
converter, because it is the number the player feels.

## The `cloné` tier: Zonos

SkyrimNet drives Zonos over HTTP at `localhost:7860`, using the Windows fork
[langfod/Zonos](https://github.com/langfod/Zonos). Its requirements are hard ones: **Python
3.12, the Visual Studio x64 C++ build tools, and an NVIDIA GPU with 6 GB or more** — Ampere and
older are not supported, Ada and Blackwell are.

### Install (the user's, not the agent's)

1. Take the fork, unzip it.
2. `1_Install.bat` — it builds its own virtual environment and pulls torch and the model.
3. `2_Start_Zonos.bat` starts the fork's Gradio UI on 7860. Useful to prove the install works;
   the bench does not use it.

### Why the bench brings its own server

That fork exposes a Gradio interface and a Python API, and **no REST endpoint**. Driving Gradio
from a bench means binding to a graphical interface — function indices, session hashes, audio
returned as URLs. `server/zonos_server.py` is sixty lines around the Python API instead, and it
gives three things Gradio would not:

- **the speaker embedding is computed once per reference clip and kept.** That is the "clone
  once per NPC" question, answered where it is actually true: encoding the reference voice is
  never paid again. Generation still is, and no cache avoids that.
- **the conditioning parameters are discovered, not guessed.** The exact names for emotion,
  speaking rate and pitch variation are documented neither upstream nor in the fork. The server
  reads `make_cond_dict`'s signature at startup, prints it, serves it on `/health`, and passes
  through only what the installed model accepts. A client sending an unknown key gets it back in
  `X-Rejected-Conditioning` rather than an AttributeError five frames deep.
- **the model's own time is reported separately** from the HTTP round trip, in `X-Infer-Ms`, so
  the table keeps measuring synthesis rather than a loopback.

Run it with the fork's Python — the one that has torch and zonos:

```
<fork>\.venv\Scripts\python.exe tools	ts-lab\server\zonos_server.py --model-dir <fork>
```

It listens on 7861, because 7860 is the fork's own UI. `server.json` already points at it; fill
in `speaker` with the path of a reference `.wav` to clone a character, or leave it empty for the
model's default voice.

Nothing here has been run: the fork is not installed on this machine yet, so every line of this
section is written from the documentation and waits for a first launch to become a measurement.

## The ladder, measured on an RTX 4080 SUPER — 2026-08-31

Warm figures. Zonos' **first** call after a start costs 30 to 50 seconds: Triton compiles its
kernels once. It is not a property of any line — `elisions` was 28 s on the first pass and
2.4 s on the two after it. A resident server pays that once; a bench that reports it as the
cost of speaking would be lying.

| tier | engine | rtf | a 4-second reply takes |
|---|---|---|---|
| `cloné` | Zonos v0.1 (GPU) | 1.3 – 1.55 | ~2.9 s |
| `neuronal` | Piper (CPU) | ~13 | ~0.3 s |
| `recollé` | SAPI | 5 – 46 | ~0.3 s |

**A tenfold gap, and the top of the ladder is the slow one.** That is the whole trade, stated in
numbers rather than adjectives.

### The number that saves it: rtf above 1

Zonos synthesises **faster than the speech is spoken** — 1.4 seconds of audio per second of
compute. So the cost is not throughput, it is the wait before the first syllable: three seconds
of silence after V stops talking, which is precisely the complaint Mantella's players make most.

Cut the reply into sentences and that wait becomes the first sentence alone — roughly 0.7 s for
a short one — and every later sentence is synthesised while the previous one plays, staying
ahead because rtf is above 1. **The fix for the latency is chunking, not a faster model.**

It costs something on our side: `plugin/Audio.cpp` plays one buffer and replaces it on the next
call, which is right for one utterance and wrong for a queue. Sentence streaming needs it to
hold a queue of buffers and play them back to back without a gap. That is a real change, and it
is the one this measurement argues for.

## What this cannot answer

Whether the game's audio engine and a converter can share a machine while the game renders. The
lab runs alone; the game does not. Every number here is an upper bound on what a launch gets.

## Les references de personnages — `clone-refs.py`

`tools/voice-extract` fabrique un extrait de voix par personnage a partir des archives du jeu ;
`clone-refs.py` les passe dans Zonos, un rendu par personnage, pour l'ecoute.

```
python tools	ts-lab\clone-refs.py                # la replique "elisions" pour tous
python tools	ts-lab\clone-refs.py --line longue  # une autre replique de lines.json
python tools	ts-lab\clone-refs.py judy panam     # deux personnages
```

Deux choses qui ont coute une passe chacune, et que ce script tient a la place de l'appelant :

- **le texte vient de `lines.json`, jamais retape.** Une replique recopiee sans ses accents se
  prononce faux, et pas un peu : « Ramene » devient « Amen », « jusqu'a 22h » devient
  « vingt-deusse, un de deux ». Entendu le 2026-08-31 sur une sonde qui avait retape le texte.
- **la reference est televersee sur `/gradio_api/upload`.** Un chemin de fichier — absolu,
  relatif au dossier du serveur, ou meme un fichier depose dans ce dossier — est refuse par le
  garde de Gradio, avec `event: error` / `data: null` et aucun message. L'upload rend un chemin
  `temp_dir\<hash>\<nom>`, et c'est celui-la qui passe dans le `gradio.FileData`.

Le script affiche le RMS et la crete de chaque rendu, et marque `SATURE` au-dela de 0,99. C'est
utile : sur la meme replique, les rendus vont de 0,009 a 0,13 de RMS selon le personnage, et
`jackie` sature. Le niveau de sortie de Zonos suit celui de la reference sans etre borne.

**La replique par defaut est `argot`, la seule longue de `lines.json` sans chiffre.** Les autres
en portent un, et un nombre colle a son unite fait deraper le moteur : le rendu se juge alors
sur le derapage et plus sur la voix. Le nom du fichier porte la replique
(`clone-<personnage>-<replique>.wav`) parce qu'un rendu ne se juge pas sans savoir ce qui a ete
demande.

## Les nombres, et ce que le moteur en fait — 2026-08-31

Ecoute : « jusqu'a vingt deux / vingt deusse / vingt deuze », et **le mot « heure » n'est jamais
prononce**. Meme voix de reference, seul le texte change :

| texte envoye | audio rendu |
|---|---|
| `jusqu'a 22h` | 3,77 s |
| `jusqu'a 22 heures` | 3,83 s |
| `jusqu'a vingt-deux heures` | **3,12 s** |
| `500 eddies` | 3,61 s |
| `cinq cents eddies` | **3,15 s** |

La forme en chiffres collee est plus **longue** que la forme en lettres : le moteur ne saute pas
le mot, il patauge et fabrique des syllabes autour du nombre.

**A l'ecoute, la regle est plus simple que la duree ne le laissait croire** : un espace suffit.
`22 heures` se dit correctement, `vingt-deux heures` aussi ; seul `22h`, colle, echoue. J'avais
lu l'inverse dans les durees — `22 heures` rendait 3,83 s contre 3,12 s pour la forme en lettres
— et j'en avais conclu a tort que l'espace ne reglait rien. La duree ne dit pas si c'est juste.

Les rendus sont dans `out\chiffres\`.

**Consequence pour le mod.** Ce que le modele ecrit passe tel quel au moteur, et un modele qui
repond « dispo jusqu'a 22h » sera inintelligible. **Tranche le 2026-08-31 : ca appartient au
canal**, pas a une regle globale — un SMS n'est jamais lu a voix haute et doit rester lisible,
`22h` etant meilleur a l'ecrit et pire dans une bouche. La demande ira dans le prompt du canal
`Call` et la garantie dans son `Clean`, comme pour les didascalies. Voir
`docs\PLAN_HOLO_CHANNEL.md` § 6. **Rien n'est ecrit** : le canal ne sait pas encore porter une
regle de prompt.

`lines.json` n'a pas ete modifie. Ses `22h` et `500` sont des pieges deliberes, et ils viennent
d'attraper quelque chose.

## Le piege qui a fausse trois mesures : le cache d'embedding est sur le NOM

Mesure du 2026-08-31, et il faut la connaitre avant de croire quoi que ce soit sur le clonage.

Le serveur (`skyrimnet-zonos.exe`, l'interface Gradio du fork) garde l'embedding de locuteur
d'une reference a l'autre — c'est voulu, « cloner une fois par PNJ ». Mais **la cle est le nom
du fichier**, pas son contenu.

L'experience : quatre rendus, meme texte, avec deux audios differents.

| envoi | contenu | nom | sortie |
|---|---|---|---|
| 1 | judy | `reference.wav` | `c0b4f10dc265` |
| 2 | **takemura** | `reference.wav` | `c0b4f10dc265` — **la voix de Judy** |
| 3 | judy | `judy-source.wav` | `c0b4f10dc265` |
| 4 | takemura | `takemura-source.wav` | `85bd39d42d94` |

L'envoi 2 est la preuve : un autre comedien, sous un nom deja vu, ressort au bit pres avec la
voix precedente. Et le televersement de Gradio ne protege pas — il range pourtant le fichier
sous un dossier nomme par l'empreinte de son contenu, mais le cache ne regarde que le nom final.

**Ce que ca a fausse**, et qui a ete refait depuis :

- toute reference reenvoyee sous un nom stable entre deux series — donc chaque
  `<personnage>.wav` de `clone-refs.py` a partir de la deuxieme execution. Les rendus etaient
  identiques au bit pres a ceux de la serie precedente, ce qui est ce qui a mis la puce a
  l'oreille ;
- la comparaison **22050 Hz contre 48000 Hz**, dont les deux fichiers s'appelaient `judy.wav`.
  La conclusion « aucun effet, sortie identique » etait un artefact du cache. Refaite proprement,
  les deux sorties **different** (RMS 0,056 contre 0,052, crete 0,92 contre 0,57). Laquelle est
  meilleure reste a l'oreille.

`clone-refs.py` televerse desormais sous `<nom>-<sha256[:12]>.wav`. Deux contenus differents ne
peuvent plus partager un nom, et deux noms differents pour un meme contenu redonnent bien le
meme rendu — verifie.

## Le palier `clone` clone un peu, et pas assez — 2026-08-31

Mesure refaite apres la correction ci-dessus.

Enveloppe spectrale moyenne en 32 bandes mel sur les trames voisees, centree, distance cosinus.
**L'instrument a ete valide avant d'etre cru** : sur des repliques brutes du jeu il reconnait
Judy parmi dix voix 6 fois sur 8 (hasard : 0,8 sur 8).

Rang de la bonne reference, pour chacun des neuf rendus : 1, 2, 2, 2, 3, 3, 4, 5, 7.

**Rang moyen 3,22 la ou le hasard donne 5** — z = -2,07, soit p ~ 0,02 unilateral. Il y a donc
un transfert de timbre, faible mais reel. Une seule reference sur neuf arrive en tete.

Cela s'accorde avec l'ecoute : « tres loin d'un vrai clone ». Le moteur va dans la direction du
personnage sans y arriver.

Une reserve qui reste entiere : la mesure compare deux chaines d'enregistrement — doublage de
jeu d'un cote, synthese de l'autre — alors que sa validation s'est faite dans une seule. Elle
appuie une ecoute, elle ne la remplace pas.

Ce qui n'a pas ete essaye : un autre moteur (XTTS-v2 fait du clonage multilingue), un etage de
conversion de timbre apres la synthese, une reference plus longue que 30 s.

## Zonos coupe une fois sur deux, et c'est la graine qui decide — 2026-08-31

Ecoute : « ca coupe a heures ». Mesure : sur la replique `argot`, qui ne contient aucun chiffre,
trois rendus sur dix s'arretent en pleine voix.

Le detecteur est simple et sans reglage a deviner : **l'energie des 50 dernieres millisecondes,
rapportee au RMS du rendu**. Une phrase finie retombe dans le silence et donne moins de 0,05 ;
une phrase coupee garde sa voix jusqu'au dernier echantillon et donne 0,3 a 1,25.

Ce n'est ni la voix ni le debit :

| `speaking_rate` | duree | fin |
|---|---|---|
| 13 | 4,99 s | 0,02 |
| 15 | 4,30 s | **1,25 coupe** |
| 17 | 3,76 s | 0,01 |
| 19 | 3,30 s | **0,72 coupe** |

Non monotone, donc pas un budget de longueur. La graine, elle, tranche — et **de la meme facon
pour deux voix differentes** :

| graine | jackie | songbird |
|---|---|---|
| 420 | **coupe** (1,25) | **coupe** (1,08) |
| 421 | 0,02 | 0,06 |
| 422 | **coupe** (0,46) | **coupe** (0,62) |
| 423 | 0,02 | 0,03 |

C'est donc le tirage, et il est independant du locuteur. `zonos.json` fixe `seed: 420`, une des
mauvaises : tous les rendus du banc partaient avec une chance sur deux d'etre tronques.

**Ce que ca implique pour le mod, et ce n'est pas fait** : la voie parlante ne peut pas jouer ce
que le moteur rend sans le regarder. Il lui faut le meme controle -- mesurer la fin, et relancer
avec la graine suivante quand elle est chaude. `clone-refs.py` le fait maintenant (`--tries`,
trois essais par defaut) et sert de reference d'implementation. La question du reglage de
`zonos.json` reste ouverte : changer `seed` deplace le probleme sans le supprimer.

## Le timbre metallique vient du moteur — 2026-08-31

Ecoute : trois voix sur neuf sonnent « metallique, comme dans une radio » (`jackie`,
`kerry_eurodyne`, `victor_vector`). **Les references, elles, sont toutes jugees bonnes.** Le
defaut est donc dans le rendu, pas dans l'extraction, et deux tentatives de le corriger en
changeant la selection ont echoue : restreindre Jackie a `q003` ne change rien, et restreindre
Kerry a `sq011` donne une voix qui crie.

Cote moteur, sur `jackie`, meme reference et meme texte :

| conditionnement | effet |
|---|---|
| `dnsmos_ovrl` 3, 4, 5 | **aucun** — sortie identique au bit pres |
| `speaker_noised` vrai | **aucun** — identique au bit pres |
| `vq_single` 1.0 | le serveur ne rend rien |
| `cfg_scale` 3.0 | change le rendu |
| **`fmax`** 16000 / 22050 / 24000 | change le rendu |

Deux conditionnements de qualite sur trois n'atteignent pas le modele sur ce serveur : les
passer est sans effet, et silencieusement.

`fmax` est le seul qui decrive la bande passante, et **il vaut 22050 par defaut alors que les
references sortent maintenant en 48 kHz**, dont la frequence de Nyquist est 24000. Annoncer au
modele une bande plus etroite que celle du fichier qu'on lui donne, c'est litteralement lui
decrire une radio. L'hypothese est donc que `fmax` doit suivre le taux de la reference.

Les rendus sont dans `out\conditionnement\`. Les variantes bit-identiques au temoin ont ete
supprimees pour ne pas faire perdre de temps a l'ecoute.

**Tranche a l'oreille le 2026-08-31 : `fmax` 24000 avec `cfg_scale` 3,0 est le meilleur.**

`clone-refs.py` applique donc les deux : `fmax` est **derive du taux de la reference** (sa
frequence de Nyquist, donc 24000 pour un fichier en 48 kHz) et non plus laisse au defaut du
serveur, et `cfg_scale` vaut 3,0, reglable par `--cfg`.

Ce que cela dit du reste du banc : la serie precedente, celle qui a produit le « judy-48k »
juge bon, tournait avec **les defauts du serveur** — `fmax` 22050 et `cfg_scale` 2,0.
`zonos.json` ne surcharge que sept valeurs et ne touche ni l'un ni l'autre. Judy sonnait donc
bien *malgre* un `fmax` trop etroit, pas grace a un reglage.

`zonos.json` n'est toujours pas modifie : le conditionnement se derive de la reference, ce qui
n'est pas la meme chose qu'une constante a poser dans une configuration.

## Une seule configuration, et un residu — 2026-08-31

Contrainte posee par l'utilisateur : **le mod ne peut pas se permettre une configuration par
personnage**, parce que la voie parlante tourne toute seule. Elle est tenue.

| ce qui varie d'un personnage a l'autre | comment |
|---|---|
| `fmax` | **derive** de la reference (sa frequence de Nyquist), pas choisi |
| `cfg_scale` | 3,0 pour tous |
| la graine | avancee automatiquement tant que le rendu est coupe |
| la selection des repliques | meme regle pour tous : ordre par hachage, plancher de niveau, voice sets ecartes |

Le seul motif propre a un personnage est `^sobchak_` pour River Ward, et c'est une **donnee de
casting** — le nom de son etiquette de doublage dans le jeu — pas un reglage. `-Pattern` et
`-Exclude` existent pour enqueter ; la passe par defaut ne s'en sert pas.

### Le residu : jackie

Neuf voix sur dix sont jugees bonnes avec cette configuration unique. `jackie` s'ameliore mais
reste metallique, et **rien de mesurable ne l'explique**. Sa reference est parmi les plus larges
du lot :

| reference | rolloff 99 % | energie au-dessus de 8 kHz |
|---|---|---|
| `rogue` | 6 646 Hz | 0,0036 |
| `river_ward` | 8 031 Hz | 0,0102 |
| **`jackie`** | **9 727 Hz** | **0,0339** |
| `songbird` | 11 349 Hz | 0,0247 |

`rogue` a la source la plus etroite et sonne bien ; `jackie` a la plus riche en aigu et sonne
radio. Restreindre sa selection a une seule quete (`q003`, jouee a pied et face a face) ne change
rien non plus — essaye, ecoute, sans effet.

Quatre hypotheses ont ete essayees et falsifiees sur ce point : bande au-dessus de 4 kHz,
energie sous 300 Hz, energie sous 1,5 x F0, largeur de bande de la reference. **Aucun seuil
n'est installe**, et il n'en sera pas installe sur la foi de dix points.

Ce qui reste, et c'est une decision, pas une mesure : accepter `jackie` tel quel, ou changer de
moteur pour tout le monde. Une exception de configuration pour lui seul est exclue par la
contrainte.
