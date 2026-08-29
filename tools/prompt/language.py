# -*- coding: utf-8 -*-
"""Dans quelle langue le modèle a-t-il répondu ?

`<system_rules>` porte une règle de langue obligatoire, et c'est la première que lâche un
petit modèle : il suit l'anglais des consignes au lieu du français de la conversation. Un
joueur verrait ses personnages basculer en anglais du jour au lendemain, sans rien dans le
jeu pour le dire. Jusqu'ici rien ne le mesurait — six fixtures non anglaises, aucun test.

MÉTHODE, ET SES LIMITES. Comptage de mots-outils : ils sont fréquents, courts, et propres à
chaque langue. Ça suffit à trancher « français ou anglais » sur trois phrases, et ça ne
prétend à rien de plus. Pas de dépendance, pas de modèle, rien à installer.

Ce que ça ne fait PAS : juger la qualité de la langue. Un français correct et un français
d'automate donnent le même verdict. La finesse se lit ; ici on ne détecte que la bascule.

Une réponse trop courte ne se décide pas : cinq mots peuvent appartenir à deux langues.
Dans ce cas la fonction rend "" plutôt que de deviner, et l'appelant ne compte pas de faute.
"""

import re
import unicodedata

# Mots-outils, choisis pour être fréquents ET propres à une seule de ces six langues. Un mot
# listé deux fois ne départage rien : il monte les deux scores ensemble, et l'écart de deux
# voix exigé plus bas n'est jamais atteint. C'est ce qui rendait l'espagnol et l'italien
# indécidables sur une réponse courte -- dix marqueurs étaient partagés, dont "que" par trois
# langues. Les paires qui se ressemblent sans être identiques restent séparément listées :
# "también" / "também", "mucho" / "molto" / "muito", "siempre" / "sempre".
MARKERS = {
    "English": {"the", "you", "your", "and", "that", "with", "what", "just", "don't",
                "i'm", "it's", "not", "for", "this", "about", "yeah", "here", "even",
                "if", "than", "them", "they", "but", "out", "get", "got", "know", "like",
                "want", "need", "back", "right", "can", "will", "were", "are",
                "of", "on", "to", "my", "me", "we", "she", "him", "her", "there",
                "don", "doesn", "isn", "won", "you're", "you've", "i'll", "that's"},
    "French": {"je", "tu", "pas", "qui", "est", "les", "des", "une", "vais",
               "moi", "toi", "c'est", "j'ai", "t'as", "avec", "ça",
               "elle", "nous", "vous", "sur", "dans", "faire", "veux", "peux", "sais",
               "quand", "comme", "encore", "rien", "tout", "plus", "aussi", "ton", "ta",
               "alors", "donc", "déjà", "jamais", "toujours", "très", "chez", "cette",
               "ces", "leur", "suis", "était", "fait", "voir", "parce", "ouais", "quoi",
               "où", "truc", "putain"},
    "German": {"ich", "du", "nicht", "das", "ist", "und", "mit", "aber", "wenn",
               "dich", "mir", "dir", "schon", "noch", "auch", "wird", "der", "die",
               "den", "sich", "sie", "hast", "habe", "kann", "muss", "auf", "für",
               "immer", "mehr", "sehr", "nur", "wie", "denn", "doch", "vielleicht",
               "wieder", "etwas", "nichts", "jetzt", "dann", "weil", "ohne", "über",
               "gegen", "kein", "keine", "mein", "dein", "uns", "würde", "können",
               "sollte", "gemacht", "gesagt"},
    "Spanish": {"los", "por", "con", "muy", "pero", "tienes",
                "eso", "estoy", "vas", "aquí", "una", "las", "más",
                "cuando", "algo", "todo", "hacer", "tengo", "puedes", "sé",
                "el", "ella", "así", "ahora", "siempre", "entonces", "también",
                "gracias", "qué", "cómo", "dónde", "quién", "cuánto", "quiero",
                "puedo", "voy", "dime", "sabes", "vale", "hasta", "desde", "aunque",
                "todavía", "contigo", "conmigo", "ellos", "nosotros", "tú", "esto",
                "ese", "esa", "mucho", "mejor", "nadie", "tiene", "estás", "están",
                "eres", "soy", "joder"},
    "Italian": {"che", "non", "sono", "per", "come", "questo", "però", "sei", "hai",
                "adesso", "cosa", "anche", "della", "delle", "sulla",
                "voglio", "niente", "tutto", "più", "già", "solo", "perché",
                "il", "lo", "gli", "nel", "nella", "alla", "dalla", "dei", "degli",
                "quello", "quella", "questa", "molto", "sempre", "ancora", "allora",
                "mai", "davvero", "ecco", "bene", "grazie", "abbiamo", "siamo",
                "fatto", "detto", "stato", "magari", "vero", "tuo", "tua", "mio",
                "mia", "essere", "fare", "dopo", "prima", "senza", "tutti",
                "ho", "così", "quindi", "invece", "proprio", "appena", "subito",
                "oppure", "neanche", "nemmeno", "qualcosa", "qualcuno"},
    "Portuguese": {"você", "não", "com", "isso", "vou", "tem",
                   "aqui", "mas", "então", "agora", "uma", "mais", "nunca",
                   "tudo", "fazer", "quero", "sabe", "já",
                   "ele", "ela", "muito", "obrigado", "até", "depois", "sem",
                   "coisa", "ainda", "assim", "meu", "teu", "dele", "dela",
                   "essa", "esse", "estou", "melhor", "pra", "também", "quando",
                   "só", "nós", "vocês", "porquê", "num", "numa", "pelo", "pela",
                   "às", "cá", "acho", "achas", "nem"},
}

# Un marqueur listé deux fois annule les deux langues qu'il prétend distinguer, en silence :
# le score monte des deux côtés et `detect` rend "". La faute est invisible à la lecture --
# il faut croiser six ensembles -- donc elle est vérifiée ici, au chargement du module.
_SEEN = {}
for _name, _words in MARKERS.items():
    for _word in _words:
        if _word in _SEEN:
            raise AssertionError('marqueur "%s" partagé entre %s et %s'
                                 % (_word, _SEEN[_word], _name))
        _SEEN[_word] = _name

CYRILLIC = re.compile(r"[Ѐ-ӿ]")
# Ce qui sépare l'ukrainien du russe : quatre lettres que le russe n'a pas.
UKRAINIAN_ONLY = set("їієґ")

WORD = re.compile(r"[\w']+", re.UNICODE)

# En dessous, un comptage de mots-outils ne tranche rien.
MIN_WORDS = 6


def detect(text):
    """La langue de `text`, ou "" quand elle ne peut pas être décidée."""
    if not text:
        return ""

    if CYRILLIC.search(text):
        lowered = text.lower()
        if any(letter in lowered for letter in UKRAINIAN_ONLY):
            return "Ukraine"
        return "Russian"

    words = [word.lower() for word in WORD.findall(text)]
    if len(words) < MIN_WORDS:
        return ""

    scores = {name: sum(1 for word in words if word in markers)
              for name, markers in MARKERS.items()}
    best = max(scores, key=scores.get)
    if scores[best] == 0:
        return ""

    # Une victoire d'une voix sur un texte court est du hasard. On exige une avance nette
    # sur le second, sinon on ne conclut pas -- un faux positif ici accuserait un modèle
    # d'une faute qu'il n'a pas commise.
    ranked = sorted(scores.values(), reverse=True)
    if len(ranked) > 1 and ranked[0] < ranked[1] + 2:
        return ""
    return best


def fold(text):
    """Sans accents, pour comparer deux noms de langue écrits différemment."""
    return "".join(char for char in unicodedata.normalize("NFD", text)
                   if not unicodedata.combining(char))
