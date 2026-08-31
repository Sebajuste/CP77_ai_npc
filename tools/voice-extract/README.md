# voice-extract — les voix de reference, prises dans le jeu du joueur

Fabrique un extrait de voix par personnage, a partir des archives de doublage de **la copie du
jeu du joueur**, pour alimenter le palier `clone` de la voix (`tools/tts-lab`).

Rien de ce que cet outil produit n'entre dans le depot, et rien n'est ecrit dans le dossier du
jeu. Les archives sont ouvertes **en lecture seule**, la sortie va dans `dist\voices\`, que
`.gitignore` couvre deja.

```
powershell -File tools\voice-extract\voice-extract.ps1             # les dix personnages
powershell -File tools\voice-extract\voice-extract.ps1 judy panam  # deux d'entre eux
powershell -File tools\voice-extract\voice-extract.ps1 -List       # compte sans rien extraire
powershell -File tools\voice-extract\voice-extract.ps1 -ShowLines  # dit ce qu'il retient, et pourquoi
python tools\voice-extract\check-clips.py dist\voices              # verifie ce qui est sorti
```

Options : `-Game`, `-WolvenKit`, `-Out`, `-Cache`, `-Recipe`, `-Language`, `-Pattern`,
`-Exclude`, `-Rate`, `-Raw`, `-FromRecipe`, `-Against`. Les valeurs par defaut sont celles de
cette machine.

`-Raw` ecrit en plus chaque replique retenue seule, telle qu'elle sort du jeu, dans
`<sortie>
aw\`. C'est par la qu'on ecoute la matiere plutot que le resultat, et c'est ce qui
a permis la comparaison ci-dessous.

**La langue de la reference doit etre celle que le moteur va parler.** Par defaut `fr`, parce
que c'est la langue du mod et celle du banc. Une reference anglaise passee a un moteur qui parle
francais rend un accent anglais : entendu le 2026-08-31, sur la premiere serie d'extraits, qui
etait tiree de `lang_en_voice.archive`. Les noms de fichiers sont **identiques d'une langue a
l'autre**, donc `-Language en` ou `-Language de` ne demandent aucun autre changement.

Depart a froid — compilation, fabrication du cache de chemins, dix extraits — **18 secondes**.
Le cache pese 130 Mo et ne se refait pas ; les extraits pesent 14 Mo au total.

Le joueur copie ensuite `dist\voices\` vers `<jeu>\r6\storages\AiNpc\voices\` **lui-meme**.
L'outil ne le fait pas et ne le fera pas.

## La recette : refaire les extraits sans WolvenKit

Une passe normale ecrit, en plus des `.wav`, un `voices-recipe.json` dans `toolsoice-extract\`.
Il contient **le resultat du choix** — les hachages des repliques retenues — et les seuils avec
lesquels on les assemble. Rien d'autre.

```
toolsoice-extractoice-extract.ps1 -FromRecipe -Out distoices-recette
```

Ce mode **n'ouvre pas le dictionnaire** : chaque replique est demandee a l'archive par son
FNV1a64, qui est la seule chose qu'une archive connaisse. `-Against <dossier>` compare ce qu'il
produit a une sortie de reference, octet pour octet.

**Verifie le 2026-08-31, dictionnaire deplace hors du disque** : les dix extraits francais et les
dix anglais ressortent identiques. Le fichier fait 25 Ko pour vingt voix et 149 repliques.

C'est ce qui rend une extraction cote joueur possible : il ne lui reste qu'a lire l'archive,
decoder et coller. Le detail de ce qui resterait a porter est dans `docs\PLAN_VOICE_LANE.md` § 5.

Une passe restreinte a la main (`-Pattern`, `-Exclude`) **n'ecrit pas la recette** : c'est un
essai, et un choix qu'on ne pourrait pas refaire depuis le casting n'a rien a y faire.

## Ce que ca demande

- **WolvenKit 8.20** decompresse quelque part sur le disque. Il n'est pas redistribue : le
  programme charge ses assemblages depuis l'installation existante (`-WolvenKit`). Trois choses
  en viennent — le dictionnaire de chemins depot, `kraken.dll` qui le decompresse, et
  `wwtools.dll` qui convertit le Wwise Vorbis.
- **.NET 8 SDK**. Le `.ps1` compile avant de lancer.
- Le jeu installe. Seules `lang_<langue>_voice.archive` sont ouvertes.

---

## La question qui decidait de tout, et sa reponse

> Peut-on lister, pour un personnage, les chemins depot de ses repliques sur une installation
> nue ?

**Oui.** Le doublage de Cyberpunk n'est pas cache dans des `.opuspak` indexes par hachage : ce
sont des fichiers depot ordinaires, un par replique, et **le personnage est dans le nom du
fichier**.

```
base\localization\en-us\vo\judy_sq026_f_1a9e5b8b494ea000.wem
base\localization\en-us\vo\panam_q103_f_...wem
ep1\localization\en-us\vo\songbird_q306_f_...wem
```

Mesure du 2026-08-31, sur `D:\Jeux\Cyberpunk 2077` (2.3, jeu de base + Phantom Liberty) :

| ce qui a ete compte | valeur |
|---|---|
| chemins dans le dictionnaire de WolvenKit | 1 723 496 |
| chemins `...\en-us\vo*\*.wem` (base + ep1) | 110 498 |
| dont **presents dans les deux archives** | 110 495 |
| etiquettes de voix distinctes | 196 |
| repliques retenues pour `judy` (`^judy_`, dossier `vo` seul) | 1 462 |

Trois chemins sur 110 498 ne repondent pas : le dictionnaire de WolvenKit couvre plusieurs
versions du jeu, pas exactement celle-ci. Le filtre est donc valide a 99,997 %.

Le hachage se verifie de la maniere la plus directe qui soit : FNV1a64 du chemin en minuscules,
compare a la table de l'archive. Il n'y a rien a deviner.

### L'etiquette de voix n'est pas toujours le nom du personnage

| `contactId` du mod | motif | repliques `en` | repliques `fr` |
|---|---|---|---|
| `judy` | `^judy_` | 1 462 | 1 519 |
| `panam` | `^panam_` | 2 352 | 2 413 |
| `river_ward` | `^sobchak_` | 1 067 | 1 084 |
| `takemura` | `^takemura_` | 948 | 981 |
| `songbird` | `^songbird_` | 1 550 | 1 597 |
| `rogue` | `^rogue_` | 1 061 | 1 060 |
| `victor_vector` | `^victor_vector_` | 380 | 402 |
| `kerry_eurodyne` | `^kerry_` | 845 | 871 |
| `jackie`, `jackie_dead` | `^jackie_` | 1 208 | 1 206 |

Les noms de fichiers sont les memes dans les deux archives ; les comptes different de quelques
unites parce que chaque doublage a ses propres variantes de prise.

**Aucun fichier ne contient `river`.** River Ward parle sous l'etiquette `sobchak`, et la preuve
est dans le deuxieme jeton du nom : ses 1 067 repliques se repartissent sur `sq021`, `sq029` et
`sq012` — *I Fought the Law*, *The Hunt*, *Following the River*, exactement sa ligne de quetes.
Meme logique pour `victor_vector`, ou l'orthographe du jeu est `victor`.

`stud` (Jesse) est un personnage ecrit pour le mod : il n'a pas de doublage vanilla, et l'outil
le dit au lieu de sortir un fichier vide.

### Songbird n'a pas de source propre, et c'est un resultat

Ecoute du 2026-08-31 : neuf extraits sur dix passent, **`songbird` non**. La raison n'est pas
dans l'outil : dans Phantom Liberty, Song So Mi est presque toujours entendue par lien relic ou
par comms, et son doublage porte deja le filtre. Il n'y a pas 30 secondes de voix nue a prendre.

Le profil de bande le montre — et montre aussi qu'on ne peut pas l'automatiser. Part d'energie
sous 300 Hz et au-dessus de 4 kHz, sur les repliques retenues :

| voix | grave | aigu |
|---|---|---|
| `panam` | 0,36 – 0,75 | 0,15 – 0,51 |
| `judy` | 0,38 – 0,54 | 0,15 – 0,39 |
| `takemura` | 0,37 – 0,62 | 0,17 – 0,43 |
| `songbird` | 0,33 – 0,61 | **0,09 – 0,30** |

Son aigu est plus bas, mais les plages se chevauchent : un seuil qui ecarterait ses repliques
traitees ecarterait aussi des repliques propres de Panam. **Aucun seuil n'est donc installe.**
Les deux mesures restent affichees par `-ShowLines`, parce que c'est avec elles qu'on choisit un
motif a la main.

C'est a ca que sert `-Pattern`, qui remplace le motif d'un personnage le temps d'un essai :

```
powershell -File toolsoice-extractoice-extract.ps1 -ShowLines -Pattern "^songbird_q306_" songbird
```

Restreindre a une quete ou la comedienne est physiquement presente est la seule piste ; elle se
tranche a l'oreille, quete par quete, et personne ne l'a encore fait.

---

## Le chemin des donnees

```
WolvenKit.Common (ressource usedhashes.kark)   1 723 496 chemins depot
   |  Oodle
   v
cache\depot-paths.txt                          135 Mo, fabrique une fois
   |  filtre : base|ep1 \localization\<langue>\vo\ + motif du personnage
   v
lang_<langue>_voice.archive                    lecture seule, un segment non compresse par .wem
   |  wwtools (Wwise Vorbis -> Ogg)
   v
NVorbis                                        PCM 48 kHz stereo
   |  moyenne des canaux, rognage du silence
   v
dist\voices\<contactId>.wav                    mono 22050 Hz 16 bits, ~30 s
```

Le doublage est du **Wwise Vorbis** (`fmt` 0xFFFF, en-tete de 66 octets), pas de l'Opus. Les
`.opuspak` existent ailleurs dans le jeu ; le doublage ne passe pas par eux, et `opus-tools` ne
sert a rien ici.

### Les seuils, et pourquoi ils sont la

Ils vivent dans `src\ClipRecipe.cs`, seuls, parce que ce sont les seules valeurs qu'on retouche
apres avoir ecoute.

- Repliques de **2 a 8 secondes**. En dessous ce sont des grognements et des interjections ; au
  dessus une seule replique mangerait la moitie de l'extrait.
- Silence de tete et de queue **rogne a -48 dBFS**, avant de mesurer la duree.
- Candidats examines dans l'ordre du **hachage de leur chemin**, pas de leur nom. Voir plus bas :
  c'est le seul reglage dont le reglage precedent produisait un extrait franchement faux.
- **Les voice sets sont ecartes** (`_vs_` ou `_vsets_` dans le nom). Ce sont les interjections
  d'ambiance et de combat, pas du dialogue. Celle de Jackie etait deux fois plus forte que ses
  repliques de scene et deux fois plus etroite de bande, et elle donnait un timbre metallique a
  tout l'extrait — entendu le 2026-08-31. Ecartee pour ce qu'elle est, pas pour ce qu'elle
  mesure. Le motif large attrape aussi `songbird_quest_1st_chars_vsets_...`, que la premiere
  version, ancree en debut de nom, laissait passer.
- Repliques **au-dessus de -26 dBFS RMS**. C'est le seuil qui compte, et il est explique plus
  bas : une prise enregistree bas est une prise lointaine ou traitee dans la fiction.
- **0,25 s de silence** entre deux repliques.
- Cible 30 s, plafond 40 s.
- **Une seule mise a niveau, a la fin, sur l'extrait entier** : -20 dBFS RMS, plafond de crete
  a 0,98. Le rapport de niveau entre deux prises n'est pas corrige.

**Les extraits sortent a 48000 Hz, le taux des archives**, et c'est une correction : ils etaient
a 22050 Hz, parce que le cahier des charges disait que c'est ce qu'on donne aux moteurs de
synthese. Ecoute du 2026-08-31, meme voix, meme replique : « le 48k est aussi beaucoup plus
precis ». Reechantillonner ne fait que retirer de la matiere a un moteur qui reechantillonne
lui-meme comme il l'entend.

`-Rate 22050` reste possible pour un moteur qui l'exigerait. Le reechantillonnage est alors un
sinus cardinal fenetre par Blackman, pas une interpolation lineaire : le repli de spectre
au-dessus de la demi-frequence s'entend sur les sifflantes.

### L'ordre d'examen, ou comment un tri par nom choisit les mauvaises repliques

Ecoute du 2026-08-31 : « les prises 03 et 04 sont en general meilleures ». Ce n'etait pas une
impression, c'etait structurel.

Les candidats etaient tries par chemin, puis parcourus par pas de `n/64`. Le pas etait cense
etaler les prises sur tout le corpus. Il ne le fait pas : **la boucle s'arrete des 30 secondes
atteintes**, apres une dizaine de candidats examines, donc elle ne voit jamais que le premier
sixieme de la liste. Et cette liste est alphabetique.

Pour Judy, cela donnait `finalboards`, `mq055_megabuilding`, `q004`, `q105` — messages holo et
appartement en tete, parce que `f` et `m` viennent avant `q`. Ses deux plus gros ensembles de
dialogue, `sq026` et `sq030`, **780 repliques a eux deux, n'etaient jamais atteints**.

La cle de tri est maintenant le FNV1a64 du chemin. Les dix premiers candidats examines sont
deja un echantillon de tout le corpus, et l'ordre reste deterministe. Judy tire desormais de
`q004`, `q105` et `sq030`, et ses prises font 3,5 a 6,7 s au lieu de 2 a 4.

Un tri deterministe n'est pas un tri representatif. Celui-la etait les deux a la fois en
apparence, et ni l'un ni l'autre en pratique.

### Le seuil de niveau, et l'hypothese fausse qu'il a remplacee

Premiere serie d'extraits, ecoutee le 2026-08-31 : **plusieurs voix sonnaient « telephone tres
compresse »**. Les extraits concernes — `kerry_eurodyne`, `victor_vector`, `river_ward` — etaient
faits pour moitie de repliques `finalboards`, les messages holo de l'epilogue.

L'hypothese evidente etait un filtre comms a la source : un passe-bande qui coupe l'aigu. Elle
est **fausse, et mesuree fausse**. Part d'energie au-dessus de 4 kHz, sur les memes fichiers :

| repliques | aigu au-dessus de 4 kHz |
|---|---|
| `finalboards` | 0,13 a 0,34 |
| repliques de quete | 0,11 a 0,21 |

Les `finalboards` ne sont pas plus filtrees que le reste. Ce qui les separe est le **niveau** :
RMS 0,014 a 0,048 contre 0,044 a 0,101 pour les repliques de quete — trois a cinq fois plus bas.

Et la cause de l'effet entendu etait **dans cet outil**, pas dans le jeu : chaque replique etait
ramenee au meme RMS avant d'etre collee aux autres. Une prise a 0,014 recevait donc un gain de
sept, son fond de salle avec — et l'extrait entier prenait la dynamique ecrasee d'une ligne
telephonique.

Deux consequences, et c'est la deuxieme qui compte :

- le plancher de niveau passe a **0,05**, ce qui ecarte toutes les `finalboards` sans avoir a
  les nommer ; un filtre sur le mot `finalboards` aurait rate les memes prises ailleurs ;
- **la normalisation par replique disparait.** Le rapport de niveau entre deux prises est une
  information sur la voix. Une seule mise a niveau, a la fin, sur l'extrait entier.

Le passe-haut biquad qui a servi a mesurer le tableau ci-dessus a ete **retire** : il ne
separait rien, et un filtre qui ne filtre pas n'a pas a rester dans le code. Les nombres restent
ici, c'est a ca que sert ce fichier.

---

## Ce qui a ete verifie, et ce qui ne l'est pas

### Verifie automatiquement — `check-clips.py`

Les dix extraits sont mono, 22050 Hz, 16 bits, entre 31,1 et 35,9 s, RMS entre 0,067 et 0,089,
et `voices.json` se relit. Aucun n'est muet.

Le spectre decroit regulierement et ne montre aucune bosse pres de Nyquist : le
reechantillonnage ne replie pas.

La hauteur mediane separe les voix comme attendu — `panam` 195 Hz, `rogue` 199, `judy` 184,
`songbird` 171, contre `river_ward` 91 Hz, `kerry` 105, `takemura` 116, `jackie` 134,
`victor_vector` 148. Une voix d'homme grave sous l'etiquette `sobchak`, ce que la
correspondance predisait.

### Verifie a moitie — le moteur les accepte

Zonos v0.1 (release SkyrimNet, sur 7860) a **accepte les neuf references distinctes et rendu
neuf repliques francaises**. Les rendus sont dans `tools	ts-lab\out\clone-<contactId>.wav`.

### Trois mesures qui ne predisent pas l'oreille

Ecoute du 2026-08-31, sur les neuf voix rendues : six passent, **`jackie`, `kerry_eurodyne` et
`victor_vector` restent « metalliques, comme dans une radio »**. Neuf etiquettes, donc de quoi
tester une regle au lieu d'en inventer une. Trois ont ete essayees, aucune ne separe :

| mesure | ce qui la tue |
|---|---|
| part d'energie au-dessus de 4 kHz | les `finalboards` n'etaient pas plus filtrees que le reste |
| part d'energie sous 300 Hz, moyennee | `rogue` 0,345 (bonne) contre `victor_vector` 0,348 (mauvaise) |
| energie sous 1,5 x F0, par replique | `river_ward` 0,045 (bonne) entre `kerry` 0,040 et `victor` 0,064 (mauvaises) |

La troisieme etait la mieux fondee — un filtre comms retire le fondamental d'une voix grave et
pas celui d'une voix aigue, donc le seuil doit se lire par rapport a la hauteur — et elle echoue
quand meme, parce qu'une voix tres grave (`river_ward`, 93 Hz) a naturellement peu d'energie
dans la fenetre etroite qu'on lui mesure.

Une quatrieme a suivi, cote moteur : la largeur de bande de la reference. Elle echoue aussi, et
a l'envers — `rogue` a la source la plus etroite du lot (rolloff 99 % a 6 646 Hz) et sonne bien,
`jackie` la plus riche en aigu (9 727 Hz) et sonne radio.

**Aucun seuil n'est installe**, et le code qui mesurait les bandes a ete **retire**. Le garder
n'aurait servi qu'a afficher deux colonnes dont on sait qu'elles ne predisent pas le jugement,
et a inviter le prochain a en tirer un seuil — ce qui a deja produit deux conclusions fausses.
Les nombres restent ici ; c'est a ca que sert ce fichier.

Ce qui est fourni a la place, c'est le choix a la main : `-ShowLines` pour voir ce qui est
retenu et pourquoi, `-Raw` pour ecouter chaque prise, `-Pattern` pour restreindre a une quete,
`-Exclude` pour en retirer une.

```
toolsoice-extractoice-extract.ps1 -Out distoices-essai -Pattern "^jackie_q003_" jackie
toolsoice-extractoice-extract.ps1 -Exclude "_sq017_" kerry_eurodyne
```

Les quetes disponibles, une fois les voice sets et les `finalboards` ecartes :

| voix | ensembles | l'hypothese, non verifiee |
|---|---|---|
| `jackie` | q005 413, q000 247, q003 226, q001 164 | q003 se joue a pied et face a face ; q001 et q005 se passent en voiture et en comms |
| `kerry_eurodyne` | sq017 306, sq011 136, sq028 127 | sq011 est la premiere rencontre chez lui |
| `victor_vector` | q307 111, q001 63, q101 51 | q101 se passe dans la clinique ; q307 est de l'epilogue, souvent au telephone |

Ce sont des paris tires du jeu, pas des mesures. Ils se tranchent a l'oreille.

### Le manifeste ne se laisse plus tronquer

Lancer l'outil sur un seul personnage reecrivait `voices.json` avec une seule entree, alors que
les neuf autres `.wav` restaient sur le disque. Le dossier et son manifeste se contredisaient en
silence, et tout ce qui lit le manifeste — `check-clips.py`, `clone-refs.py` — ne voyait plus
qu'une voix. Trouve le 2026-08-31 en cherchant pourquoi une serie de rendus n'en contenait
qu'un. Les entrees d'une execution remplacent desormais les leurs et laissent les autres.

### Ce que l'extracteur n'explique pas

Le 2026-08-31, l'utilisateur a reecoute les sources et les rendus : **les extraits sont bons, le
clone ne ressemble pas au personnage.** La suite de l'enquete est dans
`tools	ts-lab\README.md`, parce qu'elle porte sur le moteur et pas sur l'extraction. Ce qui a
ete elimine ici, et qu'il est inutile de rejouer :

- **le montage.** Une prise unique, brute, a la place des 30 secondes assemblees : meilleur pour
  deux personnages sur quatre, pire pour les deux autres. Aucun effet reproductible.

`-Rate` sert a essayer autre chose que 22050 Hz. La question n'est **pas tranchee** : la
premiere comparaison concluait « aucun effet », et elle etait fausse — les deux fichiers
s'appelaient `judy.wav` et le serveur de synthese met son cache sur le nom. Refaite, les deux
sorties different. Laquelle sonne mieux n'a pas ete ecoute.

### Ecoute — la seule mesure qui a trouve quelque chose

Deux series ecoutees le 2026-08-31, et chacune a change le code ou le constat.

| serie | verdict |
|---|---|
| references anglaises, niveau par replique | accent anglais sur tout ; « telephone compresse » sur trois voix |
| references francaises, niveau global | **neuf extraits sur dix passent** ; `songbird` non, faute de source propre |

Aucun des deux defauts de la premiere serie ne se voyait dans les mesures automatiques : les dix
extraits passaient deja mono / 22050 Hz / duree / RMS / spectre sans repli. Un extrait de
reference ne se juge pas sur son spectre.

## Ce qui n'a pas marche, pour que personne ne le refasse

- **`..\NA_PerspectiveFix\tools\wkdump\` ne sert a rien ici.** Son `bin\` n'a que
  `WolvenKit.Common`, `.Core` et `.RED4`, aucun assemblage audio, et son C# ne mentionne ni
  opus ni `.wem`. Seule sa maniere de charger WolvenKit par reflexion a ete reprise.
- **`HashService` de WolvenKit se charge et rend zero hachage.** `Load()` passe, `_isLoaded`
  vaut `true`, `_hashes` reste vide. On lit donc la ressource embarquee `usedhashes.kark`
  directement et on la passe a `Oodle.DecompressBuffer`. Sans `kraken.dll` a cote de
  l'executable, `DllNotFoundException` — et c'est le meme piege pour `wwtools.dll`.
- **L'en-tete de la table d'une archive RDAR se lit a l'octet pres.** `fileCount` est a
  l'offset 16 et `segmentCount` a 20, pas 20 et 24. Se tromper d'un champ ne produit pas
  d'erreur a l'ouverture : l'archive se lit, les chemins se resolvent, et l'index de segment
  deborde plusieurs milliers de fichiers plus loin.
- **Gradio refuse un chemin de reference relatif au dossier du serveur.** Ni
  `..\..\Documents\...\judy.wav`, ni un fichier depose dans le dossier du serveur lui-meme, ne
  passent : la reponse est `event: error` / `data: null`, sans message. Ce qui marche est de
  **televerser d'abord** sur `/gradio_api/upload`, qui rend un chemin `temp_dir\<hash>\<nom>`,
  et de passer **celui-la** dans `{"path": ..., "meta": {"_type": "gradio.FileData"}}`. Un
  chemin absolu est refuse, une chaine nue aussi.
- **Un extrait de reference n'est pas juge sur son spectre.** Les dix premiers extraits
  passaient toutes les mesures automatiques — mono, 22050 Hz, duree, RMS, spectre decroissant
  sans repli — et deux defauts audibles y ont survecu : l'accent et la dynamique ecrasee.
  Aucune des deux ne se voit dans un tableau de bandes. Il faut ecouter.

---

## Licence des voix

Les extraits sont fabriques sur la machine du joueur, a partir de sa propre copie du jeu. Ils
ne sont pas distribuables et ne sont pas distribues : ni dans le depot, ni dans le zip. C'est
la raison d'etre de cet outil plutot que d'un dossier de `.wav` livre avec le mod.
