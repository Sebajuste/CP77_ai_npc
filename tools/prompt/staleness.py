# -*- coding: utf-8 -*-
"""Une capture est-elle plus vieille que le prompt qu'elle prétend prouver ?

Sans cette question, `verify.py` n'a qu'un seul verdict — « ça ne correspond pas » — et il
recouvre deux situations opposées :

    PÉRIMÉ      le mod a changé depuis la capture. La différence est attendue, elle décrit un
                travail à faire (relancer le jeu, recapturer), pas un défaut.
    DIVERGENT   les sources n'ont pas bougé et les octets diffèrent quand même. Là, c'est
                l'outillage hors ligne qui ment, et la suite doit tomber.

Pourquoi ça compte plus qu'il n'y paraît : une suite rouge que personne ne peut réparer sans
lancer le jeu est une suite qu'on apprend à ignorer. Au bout de quelques jours le rouge est du
décor, et le jour où il signale une vraie divergence, il se noie dedans. Le seul rouge qui
survit est celui qui est réparable.

La comparaison est mécanique et ne devine rien : la capture porte sa date, les `.reds` qui
définissent le prompt portent la leur. Un fichier plus récent que la capture est nommé.
"""

import datetime
import io
import json
import os
import re

CAPTURED_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})")


def capture_time(capture):
    """L'instant de la capture, ou None si elle ne le dit pas.

    None n'est pas une erreur : les toutes premières captures n'horodataient pas. Une capture
    sans date ne peut simplement pas être déclarée périmée -- on la traite comme actuelle,
    ce qui la rend plus sévère et non plus laxiste.
    """
    match = CAPTURED_RE.match(str(capture.get("captured", "")))
    if not match:
        return None
    return datetime.datetime(*(int(part) for part in match.groups()))


def prompt_sources(script_dir, cast_dir, names):
    """Les fichiers dont dépend le texte du prompt, avec leur date de modification."""
    out = {}
    for name in names:
        path = os.path.join(script_dir, name)
        if os.path.exists(path):
            out[name] = datetime.datetime.fromtimestamp(os.path.getmtime(path))
    if os.path.isdir(cast_dir):
        for name in sorted(os.listdir(cast_dir)):
            if name.endswith(".reds"):
                path = os.path.join(cast_dir, name)
                out["cast/" + name] = datetime.datetime.fromtimestamp(os.path.getmtime(path))
    return out


def moved_since(capture, script_dir, cast_dir, names):
    """Les sources modifiées après la capture, de la plus récente à la plus ancienne.

    Vide = la capture est à jour, et une différence d'octets est alors un vrai défaut.
    """
    taken = capture_time(capture)
    if taken is None:
        return []
    newer = [(when, name) for name, when in
             prompt_sources(script_dir, cast_dir, names).items() if when > taken]
    newer.sort(reverse=True)
    return [(name, when) for when, name in newer]


def read_capture(path):
    return json.load(io.open(path, encoding="utf-8"))
