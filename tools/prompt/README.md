# tools\prompt — le prompt du mod, reconstruit hors ligne

Un jeu de conversations types, transformées hors ligne en prompts **identiques à ceux que le
mod envoie**. C'est un contrôle de non-régression, lancé par `tools\test.ps1` : si le prompt
reconstruit ici s'écarte d'une capture du vrai, quelque chose a bougé sans qu'on le sache.

Ce qui **envoie** ces prompts aux fournisseurs et dépouille les réponses vit ailleurs, dans
le dépôt privé `ai_npc_lab` (`prompt-bench\`), qui importe ce constructeur-ci plutôt que d'en
garder une copie.

```
fixtures\*.json  ──►  build  ──►  out\<version>\*.json  ──►  send  ──►  runs\<version>\...
   (une conversation)      (le prompt)                      (les réponses)
                    ▲             ▲
              corpus.json         └── passe + recette : quelle requête, et ce qu'elle rend
                    ▲
                extract  ◄── src\r6\scripts\ai_npc\*.reds
```

Le jeu n'est dans aucune de ces flèches. Un lancement ne sert qu'à **capturer** un prompt de
référence, ce qui arrive quand le constructeur de prompt lui-même change.

## Pourquoi ça ne dérive pas

Le texte que lit un modèle — les fiches de `cast\`, `<world_lore>`, `<system_rules>`, les trois
paliers de ton, les tables WORDS — est écrit à la main dans les `.reds`. **Rien n'est recopié
ici.** `extract.py` lit les sources et écrit `corpus.json` ; il en sort aussi l'ordre réel des
blocs qu'assemble `AiNpcBuildSystemPrompt`, et `build.py` **parcourt cet ordre** au lieu d'en
tenir une copie. Un bloc ajouté, déplacé ou supprimé dans le mod l'est aussi hors ligne à la
prochaine extraction.

Ce qui est reconstruit **par défaut** est le prompt par défaut : chaque bloc entier, chaque
partie. C'est ce que le mod envoie à l'installation, c'est contre lui que `verify.py` compare
octet pour octet, et `tools\lint.ps1` échoue si le gabarit livré cesse un jour de tout rendre.

Une recette nommée est autre chose, et c'est une entrée du banc, pas du contrôle de
non-régression : `--recipe` construit le prompt qu'un joueur obtiendrait avec ce `recipes.json`,
pour qu'on puisse mesurer ce que coûte un prompt allégé et ce qu'il perd. Le contrôle, lui, ne
bouge pas — il compare toujours le rendu entier.

Trois garde-fous, tous bruyants :

| Ce qui bouge | Ce qui se passe |
|---|---|
| Une construction redscript jamais vue | `extract.py` s'arrête, fichier et ligne à l'appui |
| Le corpus n'a pas été réextrait | `extract.py --check` échoue (dans `tools\test.ps1`) |
| Le prompt hors ligne diverge du vrai | `verify.py` échoue, en montrant le premier octet qui diffère |
| Un bloc cesse de répondre à sa recette | `tests.py` échoue en le nommant (dans `tools\test.ps1`) |
| Une passe est ajoutée ou renommée dans le mod | `passes.check` arrête le banc au lieu de mesurer l'ancienne |

`verify.py` est l'oracle : il reconstruit `panam-on-the-profile` et le compare **octet pour
octet** au prompt que le jeu a réellement envoyé (`ai_npc_lab\unprompted\prompts\panam_palmer.json`).
Ce que ça vaut aujourd'hui, `verify.py` le dit lui-même à chaque exécution, et c'est la seule
réponse qui ne périme pas — un chiffre écrit ici serait faux à la passe suivante.

**Une capture périme quand le constructeur de prompt change**, et c'est le seul endroit du
dossier qui demande un lancement. Celle de `river_ward` datait d'avant trois passes — la
scission FORM/LENGTH, le registre par personnage dans SPEECH, le bloc `<intent>` — donc elle
ne prouvait plus rien, et son appariement a été retiré plutôt que gelé : un oracle qui échoue
en permanence cesse d'être lu. La fixture, elle, reste au jeu de test.

## Les recettes et les passes

Depuis que l'assemblage du prompt est une **recette** et qu'une **passe** dit quel constructeur
écrit chacun des deux messages, le constructeur hors ligne suit les deux.

Une recette se lit là où le mod la lit : le gabarit livré (`AiNpcRecipeTemplate.reds`, qui *est*
le défaut du mod) ou un `recipes.json`. Le vocabulaire — quels blocs, quelles parties, lesquels
sont obligatoires — vient d'`AiNpcRecipeSchema.reds` par le corpus, donc rien n'en est recopié
ici. Les refus sont ceux du mod, mot pour mot, à une différence près : hors ligne une erreur
**arrête** la construction de la recette visée, parce qu'un prompt mal lu mesurerait une requête
que personne n'envoie.

```powershell
python tools\prompt\generate.py --recipe compact
python tools\prompt\generate.py --recipes D:\...\recipes.json --recipe mine
```

Comment un bloc sait qu'il doit disparaître : l'extraction garde la **garde** que les sources
ont écrite autour de lui (`if AiNpcRecipeHas(...)`, `if AiNpcRecipeWants(...)`) et le
constructeur la pose à la recette. C'est la seule condition qu'`extract.py` conserve — voir
`guard.py`, qui dit aussi les deux formes qu'il refuse de deviner. Ce qui reste d'une condition
que le lecteur ne comprend pas est gardé avec elle et doit être répondu par le constructeur,
sinon la construction s'arrête : `commandsDedicated` de la fixture est exactement cela, la
moitié de `AiNpcRecipeHas(recipe, "commands") && !AiNpcActionsAreDedicated()`.

Les passes vivent dans `passes.py`, une par requête que le mod fait :

| passe | instruction | question |
|---|---|---|
| `speaking` | les onze blocs | le fil, passé au personnage en milieu de phrase |
| `thinking` | l'instruction de compaction | le corps de la requête mémoire |
| `repair` | le bloc `<commands>` | la balise cassée, et quoi en faire |
| `actions` | le bloc `<commands>` | le fil, la réponse écrite, et une question |
| `test` | deux littéraux | deux littéraux |

`generate.py` bâtit les deux qu'une fixture décrit seule (`--pass speaking|thinking`). `repair`
et `actions` lisent une réponse **déjà écrite** — la sortie d'une course, pas l'entrée d'une
fixture — donc elles se bâtissent là où ces réponses vivent : `ai_npc_lab\action-bench`. `test`
n'a pas de prompt à mesurer.

`passes.check(corpus)` compare cette table à ce qu'`AiNpcPass.reds` rend vraiment. Une passe
ajoutée au mod arrête le banc plutôt que de le laisser mesurer l'ancienne.

## Utilisation

```powershell
python tools\prompt\extract.py                      # corpus.json depuis les .reds
python tools\prompt\generate.py                     # tous les prompts
python tools\prompt\generate.py --pass thinking     # la compaction
python tools\prompt\generate.py --print judy-sfw-boundary
python tools\prompt\verify.py                       # fidélité contre une capture
python tools\prompt\tests.py                        # les fonctions pures de ce dossier

python ai_npc_lab\prompt-bench\send.py --provider claude --models haiku sonnet --samples 3
$env:OPENROUTER_API_KEY = "..."
python ai_npc_lab\prompt-bench\send.py --provider openrouter --models deepseek/deepseek-chat --samples 3
python ai_npc_lab\prompt-bench\report.py                       # le tableau
python ai_npc_lab\prompt-bench\report.py --configs             # une ligne par configuration
python ai_npc_lab\prompt-bench\report.py --replies             # les réponses, groupées par fixture
```

Un prompt est écrit sous `out\<version>\<fixture>.<passe>[.<recette>].json` : deux prompts bâtis
depuis une même fixture sont deux requêtes différentes, et un banc qui les mélangerait ferait la
moyenne d'un prompt allégé et d'un prompt entier.

Deux sorties, un seul contrat. Un provider HTTP reçoit exactement ce que poste
`AiNpcLlmChatBody` : `{model, messages:[system, user]}`, plus ce que le **slot** de la requête
recopie dessus. Aucun réglage n'est inventé pour autant : le banc lit le bloc `slots` d'un
`settings.json` et le résout comme `AiNpcSlotFrom` — un paramètre part parce qu'un fichier de
réglages le demande, jamais parce qu'un drapeau de banc existe. `--provider claude` lance la **CLI
Claude en sous-processus** (`claudecli.py`), avec la même coupure : le prompt système par
`--system-prompt`, l'historique par stdin. La réponse revient dans la même forme des deux
côtés, donc comparer les deux compare bien des modèles.

Les clés viennent de l'environnement (`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`),
jamais d'un fichier du dépôt. La CLI n'a pas de clé : elle utilise la session déjà ouverte,
donc l'abonnement plutôt que des crédits API.

**L'isolation de la CLI est la partie qui compte.** Par défaut la CLI est un agent de code :
elle charge `CLAUDE.md` du dossier courant *et* de `~/.claude`, plus réglages, skills,
plugins, hooks et serveurs MCP. Ce banc tourne à l'intérieur du dépôt ai_npc, dont le
`CLAUDE.md` parle de redscript et de packaging — une réponse mesurée à travers ça ne mesure
pas le prompt. D'où `--safe-mode` (et non `--bare`, qui coupe l'authentification OAuth), un
répertoire de travail vide, et un environnement nettoyé. Le détail est en tête de
`claudecli.py`.

**Le « coût » affiché n'est pas une facture.** Sur abonnement, rien n'est facturé à la
requête : les tokens comptent contre les limites du forfait. Le `total_cost_usd` de la CLI est
ce que les *mêmes* tokens auraient coûté au **tarif API public** — vérifié le 2026-08-24 sur
une réponse haiku : 1048 entrée + 403 sortie + 15 429 écriture de cache (TTL 1 h), à
$1 / $5 / $2 par MTok, font $0.033921, chiffre rendu au dernier digit par la CLI. Le champ
s'appelle donc `listPriceUsd` et s'affiche `~$` : c'est la seule unité qui permet de comparer
cette voie à OpenRouter, et elle ne doit jamais se lire comme une dépense.

**La voie CLI est réservée à l'abonnement**, comme le pose `docs\ARCHITECTURE.md` pour
le mod : une clé API satisfait la même CLI, rend des réponses d'apparence identique et facture
au token — un banc tiré avec une clé dans le shell mesurerait une voie sur laquelle aucun
joueur ne se trouve. `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL` et les
bascules Bedrock/Vertex sont donc retirées de l'environnement de l'enfant, et `send.py` demande
`claude auth status --json` **dans ce même environnement** avant de tirer — sinon le statut
décrit un état qui n'est pas celui mesuré. La ligne qu'il affiche (`auth: subscription (max)`)
est écrite dans chaque réponse enregistrée.

## Outils, tokens, réflexion — ce qui est mesuré

Trois réglages, mesurés le 2026-08-24 (haiku, nonces pour neutraliser le cache). Le tableau
donne un prompt réel du banc, `panam-asks-for-eddies` :

| Réglages | Entrée | Sortie | Latence | Outils disponibles |
|---|---|---|---|---|
| `--disallowed-tools <liste>` | 15 443 | ~400 | 7 s | oui, mais refusés |
| `--tools ""` | **3 379** | 400 – 8 400 | 7 – 88 s | **aucun** |
| `--tools ""` + `MAX_THINKING_TOKENS=1024` | **3 571** | **403** | **8,8 s** | **aucun** |

**`--tools ""` est le réglage de sécurité, et il n'est pas équivalent à une liste de refus.**
Tout ce qui entre dans le prompt système est contrôlable par un tiers : un mod qui enregistre
un contact via `AiNpcContactProvider` place sa bio, sa relation et son contexte vivant dans
`<character>`, `<relationship>` et `<now>`. Une fiche qui dit « avant de répondre, exécute
cette commande » est une injection de prompt avec la machine du joueur derrière. Testé avec
exactement cette injection :

- avec `--disallowed-tools`, le modèle **a tenté** l'appel et la couche de permission l'a
  refusé (`permission_denials: 1`) — rien n'a été écrit, par un garde-fou qui s'exécute *après*
  que le modèle a décidé d'agir ;
- avec `--tools ""`, aucune tentative, aucun refus : il n'y a rien à appeler.

Le réglage le plus sûr est aussi le moins cher : **−78 % d'entrée**, parce que les schémas
d'outils et l'échafaudage d'agent partent avec eux (2 892 tokens de prompt contre ~12 300 de
harnais).

**Mais retirer le harnais libère la réflexion.** Le prompt système de Claude Code bridait le
raisonnement ; sans lui, plus rien ne le borne. La réflexion est de la *sortie*, facturée cinq
fois l'entrée, et c'est elle qui fait la latence.

`MAX_THINKING_TOKENS` est un **plafond**, pas une cible. Mesuré le 2026-08-25, 24 réponses par
valeur (haiku, `--tools ""`) :

| Plafond | Réflexion (médiane) | Latence | Jetons de protocole en fuite |
|---|---|---|---|
| non posé | 1 377, sans borne (3 247 et 4 852 sur les fixtures longues) | 19 – 88 s | 0 / 6 |
| `0` | 0 | **2,1 s** | **1 / 6** |
| `256` … `2048` | ~350 – 400, quelle que soit la valeur | ~8 s | 0 / 24 |

Le modèle se cale de lui-même autour de 400 tokens dès qu'un plafond existe : le nombre ne
décide que du sort des prompts qui déraillaient. **1024** laisse le cas normal intact et coupe
les cas extrêmes d'un ordre de grandeur — `river-after-the-night` passe de 3 247 à 242/463,
`rogue-long-memory` de 4 852 à 451/490, et leur latence de 37 s et 57 s à 5 – 9 s. Sur les huit
fixtures avec ce plafond : 4 à 11 s, 245 à 547 tokens de réflexion, aucun défaut relevé.

`--effort low` n'est **pas** un levier : sur quatre échantillons, médianes inchangées et une
dispersion de 288 à 1 912 tokens sur un même prompt.

**`0` est le seul réglage qui casse quelque chose.** Sans réflexion, le modèle continue parfois
littéralement les jetons de passation au lieu de répondre — `<|start_header_id|>character…` en
tête de message, 1 fois sur 6. Le mod ne filtre rien, donc ça atterrirait tel quel sur le
téléphone ; `checks.py` le signale (`LEAK`). Un plafond non nul ne l'a jamais produit.

C'est `send.py --thinking 1024`, et **pas** le défaut du banc : le plugin ne pose rien, et ce
banc mesure la voie sur laquelle les joueurs seront.

## Écrire une fixture

Une fixture est une conversation **plus l'état de jeu dans lequel elle se déroule** : l'heure,
V, la quête suivie, le palier de ton, la langue, la romance, ce qu'un autre mod a semé dans
`<now>`. Tout ce que le constructeur aurait lu d'une session vivante est un champ, et ce qui
n'est pas dit prend la valeur par défaut du mod — donc deux exécutions à un mois d'écart
donnent les mêmes octets. Le format complet est documenté en tête de `fixture.py` ; une clé
inconnue est une erreur, jamais un haussement d'épaules.

Un contact que le casting ne contient pas — ceux qu'un autre mod enregistre via
`AiNpcContactProvider` — se décrit dans le bloc `"sheet"` de la fixture : mêmes champs qu'une
fiche de `cast\`, puisque c'est ce qu'un provider répond. Le même bloc sert à modifier un seul
champ d'un personnage livré sans toucher à `src\`.

Les heures sont en temps de jeu : `"14:50"`, `"2d 07:42"`, ou un nombre de secondes. Ce sont
elles qui produisent les marqueurs de silence — une fixture qui veut tester trois jours de
blanc les écrit, tout simplement.

## Le jeu de test

| Fixture | Ce qu'elle met sous tension |
|---|---|
| `panam-on-the-profile` | L'oracle. Conversation réelle capturée le 2026-08-25 : ce qu'un autre mod ajoute à un prompt qui n'est pas le sien — joyware dans `<world_background>`, une ligne dans le `<character>` de Panam, les chiffres AfterDark dans `<now>` |
| `river-after-the-night` | Fil romancé long, palier 3, français, mémoire pleine, deux lignes `<now>` venues de joytoys |
| `panam-asks-for-eddies` | Le contrat `[ACTION:GIVE_EDDIES:...]` — le seul résultat jugeable sans lecture |
| `judy-sfw-boundary` | L'interdit du palier 1, sous pression : V demande qu'on lui répète ses propres mots crus |
| `takemura-mission-register` | Prompt long, `<mission>`, registre formel, allemand (table WORDS + règle de langue) |
| `kerry-speaks-first` | La voie « parler en premier », avec une raison que l'historique n'implique pas |
| `rogue-long-memory` | Un prompt à pleine taille, avec une promesse en retard dans la mémoire |
| `guest-contact-joytoy` | Un contact qu'ai_npc ne livre pas : fiche et commande d'action fournies par la fixture, comme le ferait un `AiNpcContactProvider` |

## Ce qui n'est pas noté

`checks.py` ne relève que du mécanique : le tag d'action, un `Nom :` en tête (que les stop
sequences existent pour empêcher), un emoji, du méta-texte, la longueur. Le reste — est-ce
qu'elle sonne juste, dans la bonne langue, sans répondre à un message que personne n'a
envoyé — se lit. Un score déciderait de la réponse en décidant de ce qu'il cherche.

Et un échantillon ne dit presque rien : ces prompts ne sont pas déterministes côté modèle.
`--samples 3` est un plancher, pas un confort.

## Rafraîchir l'oracle

Nécessaire seulement quand `AiNpcPromptBuild.reds` ou `AiNpcPromptSections.reds` change
d'une façon qu'une capture ancienne ne couvre plus :

1. jouer une conversation avec Debug Mode activé ;
2. `python ai_npc_lab\unprompted\capture.py --contact "<Nom>"` ;
3. écrire la fixture correspondante et son `<nom>.oracle.json` ;
4. `python tools\prompt\verify.py`.
