# Créer un personnage

La procédure. La grammaire d'un critère est dans `CHARACTER_RULES.md` : ce document ne la
recopie pas, il l'appelle.

**Sortie : le chat, et rien d'autre.** Aucun fichier de `cast\` n'est écrit pendant cette
procédure. On valide un personnage avant de l'implémenter, et l'implémentation est une
passe séparée qui commence quand celle-ci est finie.

Quatre étapes, séparées par des arrêts durs. **On rend une étape, on s'arrête, on attend.**
Ce n'est pas de la politesse : les erreurs se composent. Un graphe construit sur une
recherche contaminée est faux de bout en bout, et le seul endroit où ça se voit encore est
la fin de l'étape 1.

## Pourquoi ce document est aussi contraignant

Il est écrit à partir d'une session réelle (Viktor Vektor, 2026-08-25) où **aucune des
quatre fautes commises n'a été rattrapée par une relecture de l'agent**. Toutes ont été
arrêtées par l'utilisateur. L'agent avait lu `CHARACTER_RULES.md`, qui décrit précisément
deux d'entre elles.

La conclusion pratique : décrire une faute n'empêche pas de la commettre. Ce qui l'empêche,
c'est **d'obliger à produire l'artefact qui la rend visible**. Chaque étape ci-dessous rend
un tableau plutôt qu'un jugement, pour cette raison-là et pas pour la forme.

## Étape 1 — La table de preuves

**Interdit tant que l'étape 3 n'est pas rendue :** ouvrir la fiche existante du personnage,
son ancien prompt, ou la fiche d'un autre mod qui le décrit. Ce qu'on lit, on le réécrit
sans le savoir.

On cherche ce dont le personnage est fait — biographie, ce qu'il a perdu, ce qu'il veut —
et en priorité les trois choses qui produisent des critères, listées dans
`CHARACTER_RULES.md` : une blessure, une trahison, une contradiction.

### Ce qu'on rend

Un tableau, une ligne par fait retenu :

| Fait | Source | Exact ou paraphrase |
|---|---|---|
| Deuxième au Watson Grand Prix, avril 2061 | shard CERTIFICATE | exact |
| « Un jour j'ai tout lâché et je n'ai jamais regardé en arrière » | dump des scripts, *The Ripperdoc* | exact |
| Laisse un message à V dans toutes les fins | wiki, section Endings | paraphrase |

**On ne met entre guillemets que ce que la colonne dit « exact ».** Une paraphrase de wiki
citée comme une réplique est une invention, même quand elle est fidèle — et c'est la faute
la plus facile à commettre, parce qu'un résumé de wiki est écrit au style direct.

### Où chercher, concrètement

- **Le wiki Fandom refuse WebFetch (HTTP 402) et `?action=raw` (403).** L'API passe :

  ```bash
  curl -s -H "User-Agent: Mozilla/5.0 Chrome/126.0" \
    "https://cyberpunk.fandom.com/api.php?action=parse&page=Viktor_Vektor&prop=wikitext&format=json&formatversion=2"
  ```

  La sous-page `<Personnage>/Computers` vaut souvent mieux que l'article : les mails et les
  shards disent ce que les résumés lissent.
- **Les répliques du jeu** : le dump des scripts sur `https://arasakas-ronin.netlify.app/`
  (une seule page, ~4 Mo). On le télécharge, on retire les balises, et on relève les lignes
  qui suivent `<Nom>:`. C'est la seule source de sa voix réelle et des didascalies.
- Les analyses de fans servent à orienter la recherche, jamais à remplir la table.

### Arrêt

On rend la table et la liste de ce qu'on n'a pas trouvé. **Les trous se déclarent** : chez
Viktor, le jeu ne dit jamais pourquoi il a arrêté la boxe, et l'inventer aurait produit
un personnage plausible, c'est-à-dire générique.

## Étape 2 — Le graphe

La grammaire du graphe est dans `CHARACTER_RULES.md`, section « Combien de critères : le
graphe » : **les nœuds sont des propositions sur lui, les arêtes sont ses critères d'action.**
Ce document ne la recopie pas ; il dit ce qu'on rend et ce qui a fait échouer les tentatives.

### Ce qui s'ajoute à `CHARACTER_RULES.md`

- **On part de la conclusion qu'il ne peut pas tirer, pas de ce qu'il veut.** Un but se
  reformule facilement en `intent` existant — chez Viktor, le premier but rendu était l'ancien
  `intent` recopié. La conclusion interdite, elle, se lit dans la table de preuves ou n'y est
  pas.
- **Deux propositions qui se contrarient, au minimum.** Un personnage dont tout va dans le même
  sens n'a pas de branche d'échec, donc pas de caractère.
- **On prend de la distance.** Un nœud se nomme par classe, jamais par instance : « ce qu'il
  vaut lui vient du dehors », pas « Saburo l'a choisi ».
- **Le nombre de critères se décide ici**, en nommant les arêtes, avant d'écrire une phrase.
  Cinq ou six ; douze est un plafond, pas une cible. Un agent qui décide après en produit dix
  et les défend tous.

### La règle des trois situations

Un trait n'entre dans une fiche que s'il est attesté dans **trois situations sans rapport entre
elles** — et ce qu'on retient est **ce qui les cause**, jamais ce qu'elles ont en commun.

Compter ne suffit pas : six occurrences peuvent partager une forme sans partager une cause.
D'où le test, qui est le vrai garde-fou :

> **Invente une quatrième occurrence qui ne ressemble à aucune des trois. Si tu n'y arrives
> pas, tu as écrit leur forme et pas leur cause.**

Ce qu'il attrape, mesuré sur une session réelle (Judy Álvarez, 2026-08-26) où les trois fautes
ont été arrêtées par l'utilisateur, et aucune par une relecture de l'agent :

| Ce qui était écrit | Quatrième occurrence non ressemblante | Verdict |
|---|---|---|
| un état « elle a quelqu'un pour l'aider » | aucune — l'état venait d'une seule quête | mort |
| « elle répare ce qu'on lui montre » | aucune — il n'y a qu'un camion de pompiers | mort |
| « elle donne un lieu et une heure » | six mois passés à retaper une épave, sans rendez-vous ni personne | la forme tombe, la cause reste : elle s'engage |
| « elle s'engage pour les siens » | un dossier de compensation rouvert des années après, pour elle-même adolescente | tient |

La troisième ligne est celle qui coûte : le trait passait le comptage à six occurrences et
restait faux.

### Ce qu'on rend

**Le graphe, dessiné**, en Artifact — un graphe est fait pour être vu d'un coup d'œil, et c'est
comme ça qu'on repère un nœud qui ne mène nulle part ou un pivot qu'on n'avait pas vu. Un bloc
`mermaid` collé dans le chat n'est pas un graphe : dans un terminal, c'est du texte.

Avec, et pas à la place :

| | Ce qu'il porte |
|---|---|
| **les nœuds** | une proposition chacun, à plat et au positif, avec son assise dans la table de preuves |
| **les arêtes** | le critère, et le message qui le déclenche |
| **le pivot** | le nœud dont partent la plupart des arêtes. S'il n'y en a pas, le graphe n'est pas encore fait |
| **ce qui manque** | un nœud sans arête se déclare, il ne se comble pas |
| **le dénombrement** | le nombre d'arêtes nommées, qui est le nombre de critères |

**Un nœud sans assise est une décoration ; une arête sans message qui la déclenche n'est pas un
critère.** C'est le même garde-fou mécanique que la colonne « exact ou paraphrase » de l'étape 1.

### Ce qui a fait échouer les quatre premières tentatives sur Takemura

Aucune n'a été vue par l'agent qui l'a faite. Toutes ont été arrêtées par l'utilisateur, et
l'agent avait lu ce document.

| La version | Ce que ses nœuds étaient vraiment |
|---|---|
| « le refus d'autorité », « la défense du mobile » | des **types de réponse** — un protocole de dialogue, donc le gameplay du mod |
| « l'autorité meurt », « le mandat du mort » | des **événements du scénario**. Personne ne se définit par un événement : il avait cinquante ans de vie avant |
| « la règle tient », « la règle manque » | **un mot qui expliquait tout** — un rang, une recette, une dette et un mobile. Donc rien |
| des nœuds justes, remplis de « donc il récite », « donc il pirate » | **la fiche imprimée une deuxième fois** : ce sont les critères, pas des propositions |

La cinquième a tenu parce que les critères y sont devenus les **arêtes**. C'est le seul
changement, et il rend le reste évident : le pivot apparaît tout seul, et le critère qui coûte
est celui dont l'arête retombe dessus.

### Arrêt

On rend : le graphe dessiné, les nœuds avec leur assise, les arêtes avec leur déclencheur, le
dénombrement, et **ce que les propositions rendent insoluble**. Un personnage dont toutes les
propositions vont dans le même sens est apaisé, c'est-à-dire plat.

## Étape 3 — Les critères

**La version plate d'abord.** On écrit chaque critère dans la langue la plus ordinaire
possible, on vérifie le gabarit après. Le gabarit est un contrôle ; utilisé comme plan de
rédaction, il se remplit de mots qui ont la bonne fonction et aucun contenu — c'est écrit
dans `CHARACTER_RULES.md`, et ça n'a pas suffi.

### Ce qu'on rend

Un tableau. Pas une liste de phrases.

| Critère | Message qui le déclenche | Message qui ne le déclenche pas | Ligne de la table de preuves |
|---|---|---|---|

**Un critère à qui il manque une colonne est coupé.** C'est le garde-fou principal de tout
ce document, et il est mécanique : on ne peut pas écrire le message qui déclenche
*« parce que ta décision n'a tenu que parce que personne ne te l'avait dictée »*. On écrit
sans effort celui de *« parce qu'il ira de toute façon »*.

### Les deux signaux à surveiller sur soi

- **Le POURQUOI doit pouvoir être contredit** (`CHARACTER_RULES.md`, « Ce que chaque fente
  admet »). Ni vrai ni faux = glose.
- **La charpente.** Quand toutes les phrases d'une fiche ont la même syntaxe — *X n'a tenu
  que parce que Y*, *ferait de Z une fuite* —, c'est la charpente qui écrit, pas l'auteur.
  Une bonne phrase stylisée n'est pas une bonne phrase.

### La livraison des faiblesses

On termine en désignant **les deux critères qu'on juge les plus fragiles, et pourquoi**. Un
agent qui s'auto-note se donne la moyenne ; un agent qui doit livrer ses suspects en trouve.

### Arrêt

## Étape 4 — La confrontation et le test

Seulement maintenant on ouvre la fiche existante, et on rend deux choses :

1. **Ce que l'ancienne fiche affirme et que la table ne soutient pas.** Chez Viktor : un âge
   (« 70+ ans, n'en paraît pas 45 ») qu'aucune source ne donne, et des phrases de contrôle
   (« patient, talented and professional », « reject any romantic advances outright ») dont
   la seconde faisait doublon avec un mécanisme du mod.
2. **Ce que l'ancienne fiche savait et que la recherche a raté.** Ça arrive, et c'est la
   raison pour laquelle on la lit à la fin plutôt que jamais.

Puis le test, qui est le seul juge :

```powershell
python tools\prompt\extract.py
python tools\prompt\generate.py --fixture <nom-de-la-fixture>
python ai_npc_lab\prompt-bench\send.py --provider claude --models haiku --fixture <nom> --samples 3
```

**La fixture vise le critère qui coûte** — celui qui rend le personnage moins agréable,
jamais le critère flatteur. C'est celui-là qu'un modèle lisse quand il ne l'a pas compris.
Pour Viktor : « il dit où frapper à celui qui y va quand même », et pas « il demande comment
tu vas ».

Un critère est du papier tant qu'on ne l'a pas vu produire une réponse.

## Les fautes de référence

Aucune n'a été vue par l'agent qui l'a faite. Toutes ont été arrêtées par l'utilisateur.

| Faute | Ce que ça donnait | Ce qui l'arrête |
|---|---|---|
| **Contamination** | le premier but du graphe était l'`intent` de la fiche recopié | étape 1 : ne pas lire la fiche |
| **Fausse citation** | une paraphrase de wiki rendue entre guillemets comme une réplique | la colonne « exact ou paraphrase » |
| **Glose** | « parce que ta décision n'a tenu que parce que personne ne te l'avait dictée » | la colonne « message qui déclenche » |
| **Sujet manquant** | « tu le dis une fois » — le « le » n'avait pas d'antécédent | relire la phrase seule, hors contexte |
| **Altitude de la source** | un graphe dont les nœuds étaient les quêtes redessinées, et des traits tirés d'un seul événement | le test des vingt ans / soixante ans |
| **Le graphe recopié** | des nœuds justes, remplis de « donc il récite », « donc il pirate » — les critères imprimés deux fois | aucun verbe qu'il exécute dans un nœud |
| **Le mot qui explique tout** | un nœud couvrant un rang, une recette, une dette et un mobile | un seul mot ne doit pas tout expliquer |
| **La forme prise pour la cause** | « elle donne un lieu et une heure », vrai six fois et faux quand même | le test de la quatrième occurrence |

Les quatre premières viennent d'une session (Viktor Vektor, 2026-08-25), les trois suivantes
d'une autre (Judy Álvarez, 2026-08-26), et les deux dernières d'une troisième (Goro Takemura,
2026-08-27) — où l'agent avait lu le document contenant les sept premières, et a produit cinq
graphes faux avant le bon.

## Après

L'implémentation est une autre passe : `bio`, `relationship`, `intent`, `speechStyle`,
variantes, `seedFacts`, contextes de quête. Ce qui y va et où est dans
`CHARACTER_RULES.md` (« Où les critères atterrissent ») et dans `API.md`.

Une règle qui ne s'y trouve pas encore et qui coûte cher : **ne jamais déclarer une
`action` pour un personnage si rien ne l'exécute en jeu.** Un tag déclaré est annoncé au
modèle, donc le modèle se met à promettre la chose, et un fait que personne ne lit produit
un rendez-vous qui n'existe pas. Le bloc `<interactions>` du prompt l'interdit déjà en
toutes lettres.
