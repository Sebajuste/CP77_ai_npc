# Plan : `<channel>`, et la passe vocale qui s'y appuie

Regrouper dans un bloc `<channel>` tout ce que le prompt affirme du **médium**, puis brancher la
passe parlée dessus. La refonte est plus large que la passe : elle touche des règles écrites
avant que les canaux existent.

---

## 1. Ce qui existe, et ce qui n'existe pas

Bâti le 2026-09-01, vert hors ligne, jamais lancé :

| pièce | état |
|---|---|
| la voie `holo`, son constructeur `AiNpcPassSpoken` | écrits |
| `passes.holo = {slot, recipe}` | lu et résolu ; non relié, le slot suit `speaking` |
| la recette `spoken` | déclarée dans le gabarit, **sans effet** |

**`<channel>` n'existe pas.** Le schéma compte onze blocs — `system`, `explicitness`,
`character`, `target`, `relationship`, `world`, `commands`, `memory`, `intent`, `quest`, `now` —
plus `instruction` et `ask`, qui ne rendent rien. Le mot « channel » n'apparaît que dans des
commentaires.

---

## 2. L'argument qui décide, et il est de cache

Le médium est affirmé à deux endroits aujourd'hui, tous deux **au-dessus de `<now>`** :

| affirmation | où | texte |
|---|---|---|
| `<fiction>` | dans `<system>`, construit en dur | *« …not an assistant, texting V on a phone. »* |
| rubrique `REACH` | dans `<system_rules>` | *« You reach V only by text message, and the commands in `<mechanics>`… »* |

Et `<now>` **décide où finit le préfixe cacheable** — c'est écrit dans `AiNpcPromptBuild.reds`.

Ma proposition précédente plaçait les règles parlées dans `<system_rules>`, donc au-dessus de
cette ligne. **Elle était mauvaise** : `<system_rules>` serait devenu dépendant du canal, et un
joueur qui alterne SMS et appels aurait payé **deux préfixes** au lieu d'un. Le bloc à part,
placé sous `<now>`, ne coûte rien qui n'était pas déjà dépensé.

C'est l'argument que `PLAN_HOLO_CHANNEL.md` § 6 avait déjà posé, et je l'avais lu sans en tirer
la conséquence sur ma propre proposition.

---

## 3. Ce que `<channel>` porte

Tout ce qui dépend **exclusivement** du médium, et rien d'autre.

| | `Text` | `Call` |
|---|---|---|
| le fait | on s'écrit | on se parle |
| les smileys tapés | admis | interdits |
| les nombres | chiffres acceptés | en toutes lettres |
| abréviations, sigles, symboles | admis | écrits en entier |
| astérisques, mise en forme | (à trancher, § 6) | interdits |

Un texte par canal, **sans rubriques et sans contribution** — la forme de `<explicitness>`, qui
refuse déjà toutes les voies d'apport parce qu'il répond à une question posée au joueur. Ici la
raison est jumelle : le canal répond à une question posée par la surface, et aucun personnage
n'a voix au chapitre.

**Position : après `</now>`, avant le rappel final d'`<explicitness>`.** Ce dernier occupe la
dernière place pour une raison mesurée — sans lui, le palier SFW répétait les mots explicites de
V 10 fois sur 10.

---

## 4. Ce que la refonte casse

Sept points, et les trois premiers ne sont pas des détails.

### 4.1 `REACH` perd la moitié de son sens, et c'est visible de l'API

La rubrique porte **deux affirmations sous une seule clé** :

> *You reach V only by text message* — dépend du canal
> *and the commands in `<mechanics>` are the only way you can act on the world* — vrai partout

Elle est **contribuable** : seules `FORM`, `TIME` et `LENGTH` sont verrouillées. Un mod tiers
peut donc la remplacer aujourd'hui, et il écrit les deux moitiés. Après la coupe, sa moitié
« médium » est ignorée en silence.

`docs\API.md` pose la règle : additif seulement, jamais de signature changée. Le sens d'une
rubrique contribuable qui change relève de la même classe. Rien n'est publié, donc c'est encore
gratuit — mais c'est une décision, pas un nettoyage.

### 4.2 `<fiction>` perd trois mots, et il faut savoir ce qui les remplace

> *This is fiction. You are a character from Cyberpunk 2077, not an assistant, **texting V on a
> phone**. No therapist or customer-service tone, no disclaimers, no meta-text.*

Le commentaire dit ce que cette phrase fait : elle nomme la fiction, **les deux parties**, et le
registre d'assistant avec ses trois signes. Retirer « texting V on a phone » retire aussi
« V » — donc la mention des deux parties, que le commentaire désigne comme *« la moitié qu'une
bio tierce mince oublie »*.

Il faut donc une formulation qui garde les parties sans nommer le médium. C'est de la prose de
prompt : elle se propose et se valide, elle ne s'écrit pas seule.

### 4.3 Un troisième bloc requis, là où le schéma en argumente deux

`AiNpcRecipeSchema.reds` déclare `system` et `explicitness` requis, et argumente chacun. Un
recipe qui laisserait tomber `<channel>` laisserait un personnage croire qu'il envoie des SMS
pendant un appel : c'est un troisième cas, et il doit être argumenté au même endroit.

Conséquence sur le linter : sa règle *« tout bloc qu'une recette peut retirer est interrogé par
quelqu'un »* exempte les blocs requis. `<channel>` y entre.

### 4.4 Deux ordres que rien ne compare

> *L'ordre de cette table EST l'ordre du prompt, et `AiNpcBuildSystemPromptWith` parcourt la même
> séquence à la main. Rien ne compare les deux ordres.*

Le commentaire assume ce coût : *« un bloc déplacé ici et pas là coûte ses repères à un lecteur,
pas son prompt à un joueur »*. Avec un bloc **requis**, ce n'est plus vrai : déclaré et jamais
rendu, il disparaît sans un mot. La refonte rend ce contrôle manquant plus cher qu'il ne l'était.

### 4.5 La garantie « octet pour octet » tombe jusqu'à une nouvelle capture

`tools\prompt` reconstruit le vrai prompt hors du jeu et le compare **octet pour octet** à une
capture — `captures\panam_palmer.json`, une seule. Un bloc de plus casse la comparaison par
construction.

La capture vient du jeu. **Il faut donc une partie lancée pour la refaire**, et jusque-là le
harnais ne prouve plus rien. C'est le coût le plus concret de la refonte, et le seul qu'un agent
ne peut pas payer.

### 4.6 Le gabarit livré et les assertions

- `AiNpcRecipeTemplate.reds` doit nommer `channel`, sinon le linter refuse : *« a fresh install
  would not render it »*. Et il est écrit en `recipes.example.json` à chaque lancement, donc
  c'est aussi la documentation joueur.
- `tests\AiNpcTestPrompt.reds` et `tests\AiNpcTestRecipe.reds` fixent la forme du prompt et le
  vocabulaire des recettes. Les deux bougent.

### 4.7 `FORM` perd sa phrase sur les smileys

> *« Typed smileys like :) ;) :/ xD are fine. »*

Elle part dans `<channel>`, côté `Text`. `FORM` garde ce qui vaut sur les deux surfaces : la
première personne, un seul message, ne pas parler ni agir pour V, ne pas se répéter.

Aucun verrou ne bouge — `FORM` reste incontribuable, et `<channel>` refuse tout le monde.

---

## 5. Ce que la refonte range

- **un seul préfixe cacheable** pour un joueur qui alterne les deux surfaces, au lieu de deux ;
- le médium cesse d'être affirmé à deux endroits qui se contredisent pendant un appel ;
- la règle des smileys, celle des nombres et les contraintes de prononçabilité se retrouvent
  **dans un bloc, sous un propriétaire** ;
- la rubrique `SPOKEN` que je proposais **disparaît** : elle devient le contenu `Call` de
  `<channel>` ;
- et `PLAN_HOLO_CHANNEL.md` § 6 cesse d'être un plan en attente : c'est ce paragraphe-ci qui
  l'exécute.

---

## 5 bis. Le registre parlé appartient à la fiche — décidé 2026-09-01

Le prompt rendu l'a montré avant qu'on y pense : la part `SPEECH` de `<character>`, pour Judy,
prescrit *« Emoticons are constant -- :) ;) :P xD »*. Sur un appel, `<channel>` les interdit
pendant que la fiche les prescrit.

**Trois sorties ont été pesées, et la deuxième est retenue** : chaque fiche déclare son registre
parlé, à côté de son registre écrit. Les deux autres — laisser la position trancher, ou faire
dire à `<channel>` que la fiche ne s'applique pas — laissaient une contradiction dans le prompt
ou faisaient porter de la prose de personnage à un bloc dont le sujet est le médium.

La division qui en sort est nette, et c'est elle qui rend la refonte tenable :

| | sujet | exemple |
|---|---|---|
| `<channel>` | le texte comme artefact | nombres en toutes lettres, pas d'abréviations, pas d'emoji |
| `<character>` → `SPEECH` | comment cette personne parle | l'argot de Judy, ses emoticônes, ses phrases courtes |

Les emoticônes tombent des deux côtés sans se contredire : le canal affirme qu'une bouche ne les
prononce pas, la fiche affirme que Judy en tape **quand elle tape**.

### Ce que cette position coûte, mesuré

`<character>` commence au caractère **2 253** d'un prompt système de 12 757 ; `</now>` finit à
**12 561**. Un `<character>` dépendant du canal remonte donc la frontière du préfixe cacheable de
la fin du prompt à son premier cinquième : **10 308 caractères, 81 %**, cessent d'être partagés
entre les deux surfaces.

Ce n'est pas 81 % à chaque message — à l'intérieur d'un appel le préfixe reste stable et se
réescompte dès le deuxième tour. C'est : **chaque appel démarre à froid**, au lieu de réutiliser
le préfixe que les SMS avec ce contact ont déjà chauffé. Et c'est le pire cas pour un appel,
parce qu'un appel est court : trois tours ne rentabilisent pas un préfixe froid.

**Accepté comme la conséquence d'un fait** : la manière de parler dépend réellement de la
surface, et un personnage vit haut dans le prompt. Le chiffre est ici pour qu'on n'ait pas à le
remesurer le jour où quelqu'un s'étonnera du coût d'un appel.

---

## 6. Ce qu'il reste à trancher

**Les astérisques dans le fil écrit.** `AiNpcChannelHolo` affirme que le prompt interdit déjà les
didascalies. **Il ne les interdit nulle part** — vérifié sur `AiNpcPromptSections.reds`,
`AiNpcRules.reds` et `AiNpcCharacterRender.reds`. Seul `AiNpcStripNarration` les retire, et
seulement sur l'appel. Donc dans une bulle de téléphone, un `*soupir*` passe et personne ne l'a
jamais demandé au modèle. Interdire à l'écrit aussi est une question de goût ; interdire à l'oral
ne l'est pas.

**Le texte des deux canaux.** Cinq à six lignes de prose de prompt, sans aucun exemple — la
leçon de `TIME` est mesurée : montrer le marqueur faisait recopier la chaîne dans 22 % des
réponses, 7 sur 24 mot pour mot.

**Le remplacement des trois mots de `<fiction>`.**

---

## 7. Ce que ce plan n'inclut pas

**La garantie sur les nombres — écrite le 2026-09-10, jamais lancée.** Décision de l'utilisateur :
pas d'expansion en toutes lettres, seulement l'heure collée. `AiNpcVoiceFormat` rend « 22h30 »
« 22 heures 30 », par langue (`Uhr`, `horas`, `ore`, `часа`…), appelée par
`AiNpcChannelHolo.Clean`, qui reçoit maintenant la langue de la réplique. Le banc disait que
l'espace et le mot suffisent ; les chiffres restent.

**La porte vocale.** `PLAN_HOLO_CHANNEL.md` § 6, décidée et non écrite.

**Le premier son en 120 ms.** Bâti le 2026-09-02 (`MEASURE_VOICE_ENGINE.md`, étape 5) : la
voie audio enchaîne `Open`/`Push`/`Close`, et `PocketVoice::Render` pousse chaque morceau.

---

## 9. Écrit le 2026-09-01 — état

Vert hors ligne, **jamais lancé**. La capture octet pour octet est périmée et le harnais le dit
lui-même : *« 1 oracle sur 1 précède le mod actuel. Rien ne prouve qu'ils soient faux — ils ne
prouvent simplement plus rien de la moitié qui a changé. »* À refaire au prochain lancement.

| | |
|---|---|
| `<channel>` | bloc requis, après `</now>`, un texte par canal, aucune contribution |
| `<fiction>` | *« and V is the person you are talking to »* remplace *« texting V on a phone »* |
| `FORM` | perd les emoji et les smileys : ce sont des contraintes de rendu |
| `REACH` | perd *« You reach V only by text message »* |
| `AiNpcCharacterDef.spokenStyle` | le registre à voix haute, l'écrit à défaut |
| fiches | Judy, Kerry, Rogue, Takemura ont le leur ; les cinq autres décrivent une personne |
| `AiNpcContactProvider.GetSpokenStyle()` | additif, corps par défaut vide |
| recette `spoken` | retire `<commands>` |

### Ce que l'outillage hors jeu a demandé

Il refuse ce qu'il ne connaît pas, et c'est ce qui l'a tenu à jour :

- le lecteur de fiches a appris `spokenStyle`, `voice`, et **l'affectation imbriquée**
  `c.voice.fallback = "eve"` — un seul niveau, au-delà une fiche décrirait une structure ;
- le constructeur a appris le local `pass`, l'énum `AiNpcChannelId` et les deux appels ;
- l'extracteur a appris `AiNpcChannelPromptFor`, **écrite en `switch` avec un retour final**
  plutôt qu'en chaîne de `if` : c'est la forme qu'il sait récolter, celle de la règle de langue ;
- une fixture peut désormais dire `"pass": "holo"`. Absente, elle décrit une conversation
  écrite — ce que toutes celles écrites avant les canaux décrivaient.

### Les deux prompts, rendus pour de vrai

Même conversation, même personnage, deux passes. Seules deux régions diffèrent :

```
écrit  SPEECH: You type fast and sloppy: lowercase openings, apostrophes missing…
       <channel>You and V are texting. Emoji and other pictographs cannot be displayed;
                typed smileys like :) ;) :/ xD are fine.</channel>

parlé  SPEECH: You talk in short bursts, never in paragraphs, and you swear easily and hard…
       <channel>You and V are on a call. Your reply is read out loud by a speech engine.
                Write every number, time and amount in words…</channel>
```

`<fiction>`, `FORM` et `REACH` sont désormais **identiques sur les deux**, ce qui était l'objet
de la refonte.
