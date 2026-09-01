# The voice lane: what ships, what is made locally, and the seam between them

The mod ships **no voice data**. It ships the ability to speak, and reads whatever voices are
present. Making a voice that sounds like the game's own character is a separate, optional,
out-of-game step the player performs once.

That split is not a legal fig leaf bolted onto a technical plan — it is the only shape that
works, and each half fails without it:

- **the mod cannot do the making.** It is redscript plus a small DLL. Decoding Wwise
  soundbanks, mapping line ids to a speaker and assembling thirty clean seconds is hundreds of
  megabytes of intermediates and minutes of work. That is not a thing a game mod does while the
  player waits at a loading screen.
- **the tool cannot do the speaking.** It has no session, no contact, no reply.

Mantella and SkyrimNet both land here — voices are an installation step, not a feature of the
mod. What this document adds is that **the artefact between the two halves is ours**, specified
below, rather than an accident of whichever tool made it.

---

## 1. The three tiers, and what each needs from the player

| tier | voice | what the player installs |
|---|---|---|
| `recollé` | Windows' own | nothing |
| `neuronal` | a generic neural voice | a local engine |
| `cloné` | as close to the game's as we can get | an engine **and** a reference clip |

**The first two ship working.** A player who installs nothing still hears a character speak.
That is the floor, and it is what makes the voice lane an improvement rather than a dependency.

The third needs one file per character, and where that file comes from is not the mod's
business — see § 3.

---

## 2. The seam: a folder and a manifest, never a code dependency

The tool writes; the mod reads. Neither imports the other, and the mod must run identically
when the tool has never been installed.

```
r6\storages\AiNpc\voices\
    voices.json          the manifest: which character has what
    judy.wav             a reference clip
    panam.wav
```

**`r6\storages\` and nowhere else.** It is the one place this project may write at runtime,
precisely because Vortex does not manage it — `r6\audioware\` and `r6\scripts\` are hardlinks
into the staging folder, and writing there corrupts the source copy of a mod, silently. A voice
made after installation is not part of the mod and must not sit where the mod's own files sit.

### What the artefact is: the clip, not the embedding

A speech engine turns a reference clip into a speaker embedding. It is tempting to store that
embedding, since it is what the model actually consumes and computing it costs a second.

**Store the clip.** The embedding is bound to one engine *and one model version* — Zonos caches
its own under `cache\embeds\Zonos-v0.1-transformer\`, and the version is in the path for a
reason. A clip survives changing the engine, upgrading the model, or the player switching tiers;
an embedding survives none of those, and a stale one fails in the worst way available: it works,
and sounds like somebody else.

The engines already cache embeddings themselves, keyed by the clip. Storing the clip therefore
costs nothing per reply and keeps the artefact portable.

### The manifest

Per character: the file, where it came from, how long it is, and when it was made. The origin
matters because a clip a player recorded and a clip taken from the game are the same file to us
and not the same thing to them.

A character with no entry falls back to the tier below, **per character**. A player will have
Judy and not Rogue, and the mod has to be right in that state rather than treating "cloned
voices" as one switch.

---

## 3. The tool, and the one thing that decides whether it is a weekend or a month

It runs outside the game, once, on the player's own files, and produces the folder above.

The steps are known, except one:

1. find the voice-over archives — known;
2. read `.opusinfo` / `.opuspak` and decode the Opus streams — known, and WolvenKit does it,
   though **the assembly that carries audio export is not the one this repo's `wkdump` harness
   holds**: it has `Common`, `Core` and `RED4`, no audio at all, and its own sources never
   mention opus, `.wem` or soundbanks;
3. **keep only the lines spoken by one character** — answered, see below;
4. concatenate thirty clean seconds, write the clip and the manifest entry.

### Step 3 is a filename, not a puzzle

`cp2077-voiceswap` does this by **regular expression on the depot path**: its documented example
is `v_(?!posessed).*_f_.*` for female V's lines, excluding the Johnny-possessed variants. The
speaker is in the path. No metadata to cross-reference, no matching subtitles to audio.

The real dependency is elsewhere and is a data one: **archives store only the FNV1a64 of the
lowercased path**, never the path. Filtering by regex therefore needs a dictionary of known
paths — the one WolvenKit ships.

**Verified, 2026-08-31.** 110 495 of the 110 498 English voice-over paths in that dictionary
resolve against a plain install, base game and Phantom Liberty. `^judy_` selects 1 462 lines.
Step 2 above is wrong on one point: the voice-over is **not** Opus in `.opuspak` — it is Wwise
Vorbis in ordinary depot files, one per line. `tools\voice-extract\README.md` carries the
measurements; § 5 below carries what it takes to do the same without WolvenKit.

### A reference does not have to come from the game

The cloning measured on 2026-08-31 used a Piper output as its reference — a generated French
voice, cloned successfully. Any clean thirty seconds works.

So the tool is one supplier of clips, not the definition of the tier. A player who drops their
own recording in gets the `cloné` tier with no extraction at all, and the archive route can fail
without taking the feature with it.

---

## 4. What this does not fix

**The wait.** Zonos synthesises at about 1.4× real time, so a four-second reply is three seconds
of silence first. Cloning changes who speaks, not when.

Cutting the reply into sentences helps, but the better answer hides the synthesis inside a delay
the player is already paying: **stream the model's output, and send each sentence to the voice as
it completes.** The first sentence is spoken while the model is still writing the second, so the
voice costs nothing the text lane was not costing already.

**Our transport cannot do that today, and that is the real work.** The speaking lane posts a
request and waits for a whole reply; RedHttpClient is a request/response API with no streaming.
The lane that *could* stream is the one in `ai_npc.dll` — it already owns an HTTP client's worth
of ground, it already runs off the game thread, and **it is already where the audio lives**. A
streaming request there, feeding sentences to the speech worker as they arrive, is the single
change that makes a cloned voice arrive on time.

So the order is: streaming first, voices second. A beautiful voice that arrives three seconds
late is the defect Mantella's players report most, and it would be ours by construction.

---

## 5. Extraire sans dependance externe

L'extracteur de `tools\voice-extract` marche, et il demande au joueur d'installer WolvenKit et
le SDK .NET. Aucun joueur ne fera ca. Voici ce que chaque piece sert, et laquelle tombe.

| piece | a quoi elle sert | evitable |
|---|---|---|
| dictionnaire `usedhashes` de WolvenKit, 135 Mo | resoudre chemin -> hachage | **oui** |
| `kraken.dll` | decompresser ce dictionnaire | oui, par consequence |
| lecture RDAR | trouver le fichier dans l'archive | non, mais c'est cent lignes |
| `wwtools.dll` | Wwise Vorbis -> Ogg | non, a porter |
| NVorbis | Ogg -> PCM | non, `stb_vorbis` est un seul fichier |
| SDK .NET 8 | compiler | oui, si le code vit dans le plugin |

### Le levier : la selection est une decision de fabrication, pas d'execution

Le dictionnaire ne sert qu'a **choisir** les repliques. Ce choix, on le fait ici, une fois, et
on ne livre que son resultat. Un extrait fini est fait de six a neuf repliques ; les designer
par leur FNV1a64 coute huit octets chacune.

```
voices-recipe.json     contactId -> langue -> les hachages des repliques retenues
```

Cote joueur il ne reste donc plus qu'a ouvrir l'archive, aller chercher sept fichiers, les
decoder et les coller. Deux mesures rendent ca simple :

- sur 401 fichiers echantillonnes parmi les 103 221 du doublage francais : **un seul segment,
  jamais compresse, `fmt` de 66 octets, sans exception**. Donc **aucun Oodle** sur ce chemin, et
  un seul format de conteneur a decoder ;
- sept repliques font environ 1,5 Mo a lire dans une archive de 5 Go, et la decoder prend une
  fraction de seconde.

### Ce que ca change au § 3

Le § 3 ecarte l'idee que le mod fasse l'extraction lui-meme, au motif que c'est « des centaines
de megaoctets d'intermediaires et des minutes de travail ». **Avec une recette, ce n'est plus
vrai** : c'est 1,5 Mo et moins d'une seconde. L'argument tombe, et l'extraction peut vivre dans
`ai_npc.dll` — qui tient deja l'audio (`plugin\Audio.cpp`), tourne deja hors du fil de jeu, et
n'ajoute aucune installation pour le joueur.

Ce qui reste a ecrire est un seul portage : **ww2ogg puis `stb_vorbis`**, tous deux tenant dans
un fichier et tous deux redistribuables. C'est le seul vrai travail de cette moitie.

**Et le jeu partage ses archives** -- mesure le 2026-09-01, jeu lance : l'extraction sort les dix
extraits en 2,9 s au lieu de 2,8, identiques octet pour octet. C'etait la seule hypothese qui
pouvait tuer l'idee, et elle tient. Le cout est par personnage : 200 ms pour ouvrir les index,
puis ~250 ms chacun. Fabriquer la voix d'un contact **la premiere fois qu'il doit parler** met
donc ces 250 ms dans l'aller-retour vers le modele, ou personne ne les voit. Au lancement, en
revanche, ce serait 2,9 s ajoutees au chargement pour dix voix dont neuf ne serviront peut-etre
pas.

### Le risque a nommer

Une recette est liee a une version du jeu **et** a une langue. Un correctif qui reencode le
doublage invalide les hachages. Le repli est de livrer aussi, par personnage, la liste complete
de ses chemins — environ dix mille pour tout le casting, ce qui tient dans quelques centaines de
kilooctets — et de refaire la selection sur place quand un hachage manque.

---

## 6. Parler avec la voix du jeu : quatre routes, et ce que chacune coute

| route | installe quoi | dit un texte quelconque | c'est sa voix |
|---|---|---|---|
| serveur de clonage local | un moteur, un GPU 6 Go et plus | oui | oui, mesure 9 fois sur 10 |
| service de clonage en ligne | rien | oui | oui |
| `recolle` : les repliques du jeu | rien | **non** | oui, c'est elle exactement |
| neuronal sur processeur | un moteur leger | oui | non |

**Le serveur local est ce qui a ete mesure ici**, et c'est la forme que prennent Mantella et
SkyrimNet : le mod livre le client, jamais le moteur. Il marche — neuf voix sur dix jugees
bonnes — et il exclut tout joueur sans GPU recent.

**Le service en ligne** demanderait un seul appel HTTP, sur une voie que le mod possede deja
pour le modele de langue. Mais il suppose de **televerser un clone d'une interpretation
protegee chez un tiers**, ce qui n'est pas la meme position que de fabriquer ce clone sur la
machine du joueur, a partir de sa propre copie du jeu. C'est une question a trancher avant
d'ecrire la moindre ligne, pas apres.

**Le `recolle` est la seule route sans installation qui donne la vraie voix.** Il ne peut pas
dire un texte quelconque : il rejoue des repliques du jeu. C'est beaucoup moins qu'une synthese,
et c'est exactement le personnage. `-Raw` produit deja la matiere, replique par replique. Ce
qu'il demande en plus est un travail de conception qui n'est pas commence : un vocabulaire, et
un modele contraint a n'y puiser que ce qui existe.

Rien de tout cela ne change l'echelle du § 1. Ce qui change, c'est que la moitie « fabriquer le
clone » peut cesser d'etre une installation, et que la moitie « parler » ne le peut pas — sauf
en renoncant a dire un texte quelconque.

---

## 7. Ce que chaque partie autorise, et la decision du 2026-09-01

Trois textes s'appliquent a un palier clone, et ils ne disent pas la meme chose. Ils sont
resumes ici parce que l'envie de supposer est forte et que chacun se verifie en une minute.

### CDPR : le confinement est leur clause, pas notre attenuation

Le **REDmod EULA** exige :

> You may use Mods created and developed with REDmod **only as part of Cyberpunk and not with
> other games or on a standalone basis and only for non-commercial purposes**

Un mod qui ne laisse pas la voix sortir du jeu satisfait donc CDPR sur ce point, et ce n'est pas
une interpretation genereuse : c'est le texte. **Le document est en revanche silencieux sur
l'audio** -- pas un mot sur les voix, les comediens, l'extraction ou les oeuvres derivees. Il
n'autorise rien de ce cote, il n'interdit rien non plus.

Les **Fan Content Guidelines** ajoutent la reserve qui compte : CDPR ne detient pas tous les
droits sur tout ce que le jeu contient, et des tiers peuvent devoir etre consultes. Les droits
d'interpretes sont exactement cette couche.

### PocketTTS : la clause vise l'acte, pas la diffusion

Les poids qui savent cloner sont sur liste d'autorisation, et la politique qu'on accepte pour
l'obtenir interdit :

> voice impersonation or cloning **without explicit and lawful consent**

Le confinement au jeu ne l'ecarte pas : ce qui est interdit est de **cloner**, pas de diffuser
le clone. Cette clause n'a rien de propre a PocketTTS -- Zonos, XTTS et ElevenLabs ont
l'equivalent, ElevenLabs plus strict. PocketTTS a seulement le merite de l'ecrire et de la faire
accepter.

### Nexus : pas une interdiction, un retrait sur plainte

Position publiee en avril 2023, apres l'affaire ci-dessous :

> AI-generated mod content is **not against our rules**, but may be removed if we receive a
> credible complaint from an affected creator/rights holder.

Le risque est donc un **retrait**, pas une infraction aux regles de la plateforme.

### L'affaire qui a produit cette position

Juillet 2023 : des mods pornographiques pour Skyrim mettaient en scene des personnages du jeu
avec les voix de leurs comediens d'origine, synthetisees par ElevenLabs sans accord. Cindy
Robinson (Valerica) a demande le retrait d'un mod la mettant en scene ; Ben Diskin a pose qu'il
fallait un consentement « absolu, clair, specifique et indubitable » ; la NAVA a souligne que
les comediens n'ont pas de recours juridique efficace.

**Ce qui a declenche les plaintes etait le contenu, pas la technique.** Un mod de conversation
n'a pas la meme exposition -- difference de degre, pas de nature.

Et le fait que d'autres mods clonent n'etablit rien : c'est une information sur ce qui est
tolere, pas sur ce qui est permis.

### La decision

**Le palier de repli est construit, le palier clone reste une possibilite technique.**

Le repli -- les voix du catalogue de PocketTTS, depot libre -- ne rencontre aucune de ces trois
clauses. Il coute une dependance embarquee et rien d'autre, et il donne un mod distribuable
sans reserve.

Le clone reste **possible et non promis**. L'architecture du § 2 le permet sans effort : le mod
lit ce qu'il trouve dans `voices\` et ne sait pas d'ou ca vient, il ne livre aucune voix, et
l'extracteur vit dans `tools\` qui n'atteint pas le zip.

**La ligne est documentaire avant d'etre technique.** « La voix de Judy » ne doit pas devenir un
argument de la page Nexus : la capacite reste, la promesse non. C'est cette distinction qui
tient ou qui s'use, et elle ne s'use que si on la vend.

Ce qui n'a pas ete fait et qui trancherait : demander a Kyutai, dont le formulaire d'acces
collecte justement les coordonnees, et demander a Nexus, qui a une position ecrite. Une reponse
vaut mieux qu'une lecture -- y compris celle-ci, qui n'est pas un avis juridique.
