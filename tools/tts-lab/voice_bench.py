# -*- coding: utf-8 -*-
"""Ce qu'un banc de voix mesure, quel que soit le moteur qui parle.

Les entrees -- les repliques et les extraits de reference -- et les trois mesures qu'on prend
sur un rendu. Rien d'ici ne connait Zonos, PocketTTS ni aucun autre : un moteur fournit des
octets, ce fichier dit ce qu'ils valent.

Il existe parce que le second moteur allait en recopier soixante lignes, et deux copies d'une
mesure sont deux copies a garder d'accord.
"""
import io
import json
import os
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
VOICES = os.path.join(HERE, "..", "..", "dist", "voices")


def lines():
    """Les repliques du banc. Jamais retapees ailleurs : leurs accents sont porteurs, et une
    replique recopiee sans eux se prononce faux -- « Ramene » se dit « Amen »."""
    with io.open(os.path.join(HERE, "lines.json"), encoding="utf-8") as handle:
        return {entry["id"]: entry["text"] for entry in json.load(handle)["lines"]}


def references(directory=VOICES):
    """Les extraits de `voice-extract`, dans l'ordre du manifeste, sans doublon de fichier."""
    with io.open(os.path.join(directory, "voices.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    seen = set()
    out = []
    for entry in manifest["voices"]:
        if entry["file"] in seen:
            continue
        seen.add(entry["file"])
        out.append((entry["contactId"], os.path.join(directory, entry["file"])))
    return out


def samples(path):
    """Les echantillons d'un WAV, ramenes a [-1, 1] et en mono.

    Les moteurs ne rendent pas dans le meme format -- Zonos sort du PCM 32 bits entier,
    PocketTTS ecrit ce que scipy lui donne. Un banc qui suppose un format mesure l'un des deux
    et se trompe sur l'autre, sans rien dire.
    """
    with wave.open(path) as handle:
        raw = handle.readframes(handle.getnframes())
        width = handle.getsampwidth()
        rate = handle.getframerate()
        channels = handle.getnchannels()

    if width == 2:
        scale = 32768.0
        step = 2
    elif width == 4:
        scale = 2147483648.0
        step = 4
    else:
        raise ValueError("%s : %d octets par echantillon" % (path, width))

    values = [int.from_bytes(raw[i:i + step], "little", signed=True) / scale
              for i in range(0, len(raw) - step + 1, step)]
    if channels > 1:
        values = [sum(values[i:i + channels]) / channels
                  for i in range(0, len(values) - channels + 1, channels)]
    return values, rate


def level(values):
    """RMS et crete. Un moteur sature sans le dire."""
    total = sum(v * v for v in values)
    return (total / max(len(values), 1)) ** 0.5, max((abs(v) for v in values), default=0.0)


def truncated(values, rate, rms):
    """Le rendu s'arrete-t-il en pleine voix ?

    Une phrase finie retombe dans le silence ; une phrase coupee garde son energie jusqu'au
    dernier echantillon. Mesure du 2026-08-31 sur Zonos : il coupe une fois sur deux environ,
    et c'est la graine qui decide. Le meme controle vaut pour n'importe quel moteur -- c'est
    une propriete du rendu, pas du modele.
    """
    tail = values[-int(0.05 * rate):]
    if not tail or rms < 1e-9:
        return False
    tail_rms = (sum(v * v for v in tail) / len(tail)) ** 0.5
    return tail_rms / rms > 0.35


def report(name, seconds, path, note=""):
    """Une ligne par rendu, la meme pour tous les moteurs."""
    values, rate = samples(path)
    rms, peak = level(values)
    flags = note
    if truncated(values, rate, rms):
        flags += "  COUPE"
    if peak > 0.99:
        flags += "  SATURE"
    print("%-16s %5.1f s  %5.2f s audio  RMS %.4f  crete %.3f%s"
          % (name, seconds, len(values) / float(rate), rms, peak, flags))
    return rms, peak
