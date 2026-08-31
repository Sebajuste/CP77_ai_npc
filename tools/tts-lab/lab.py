# -*- coding: utf-8 -*-
"""Le banc de synthèse vocale. Voir README.md pour les questions qu'il répond, dans l'ordre.

Un moteur est une classe avec deux méthodes : `available()` dit si la machine peut le faire
tourner, `render(text, path)` écrit un .wav et rend le moment où le premier octet d'audio a
existé. Ajouter un moteur, c'est ajouter une classe et une ligne dans ENGINES -- rien d'autre
dans ce fichier ne connaît la liste.

Le .wav sur disque n'est pas une contradiction avec la règle du mod : ici on est dans tools\\,
et ce qui est produit sert à écouter et à comparer, jamais à être joué par le jeu.
"""

import argparse
import datetime
import io
import json
import os
import platform
import struct
import subprocess
import sys
import time

# La console Windows n'est pas en UTF-8 par defaut, et ce banc affiche du francais.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")


def machine():
    """De quoi la mesure a été faite.

    SANS CECI LE BANC NE SERT À RIEN, et c'est la seule chose qui change quand on passe de
    « choisir un moteur » à « définir des presets » : un tableau de temps sans la machine qui
    les a produits ne dit rien sur la machine d'en face. Un preset, c'est un couple mesure +
    machine.
    """
    facts = {
        "cpu": platform.processor() or "?",
        "cores": os.cpu_count(),
        "os": platform.platform(),
        "gpu": "aucun détecté",
        "vram_mb": 0,
    }
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
            capture_output=True, timeout=10)
        row = out.stdout.decode("utf-8", "replace").strip().splitlines()
        if row:
            name, vram = row[0].split(",")
            facts["gpu"] = name.strip()
            facts["vram_mb"] = int(vram.strip())
    except Exception:
        pass
    return facts


def wav_seconds(path):
    """La durée du .wav, lue dans son en-tête. Sans dépendance : le format est trois champs."""
    try:
        with io.open(path, "rb") as handle:
            data = handle.read(64)
    except OSError:
        return 0.0
    if len(data) < 44 or data[0:4] != b"RIFF" or data[8:12] != b"WAVE":
        return 0.0

    at = 12
    rate, block = 0, 0
    while at + 8 <= len(data):
        tag = data[at:at + 4]
        size = struct.unpack("<I", data[at + 4:at + 8])[0]
        if tag == b"fmt " and at + 8 + 16 <= len(data):
            rate = struct.unpack("<I", data[at + 12:at + 16])[0]
            block = struct.unpack("<H", data[at + 20:at + 22])[0]
            break
        at += 8 + size + (size & 1)

    if rate == 0 or block == 0:
        return 0.0
    return max(0.0, (os.path.getsize(path) - 44) / float(rate * block))


# Les paliers de rendu, du meilleur au pire. C'est l'axe du banc : on ne cherche pas un
# gagnant, on calibre une échelle pour en tirer des presets selon la machine cible. Un moteur
# déclare le sien, et le tableau se lit de haut en bas.
TIER_CLONED = "cloné"        # le timbre du personnage, prosodie générée
TIER_NEURAL = "neuronal"     # prosodie générée, voix générique
TIER_SPLICED = "recollé"     # fragments enregistrés, prosodie par règles


class Zonos(object):
    """Zonos, tel que la release SkyrimNet le sert. Le palier haut de l'échelle.

    Ce serveur n'expose PAS de route REST : son API est un endpoint Gradio nommé,
    `/generate_audio`, et Gradio répond en deux temps — on poste et on reçoit un identifiant
    d'événement, puis on lit un flux qui finit par donner un CHEMIN de fichier, qu'il faut
    ensuite télécharger. D'où les trois étapes ci-dessous là où les autres moteurs en ont une.

    Les paramètres sont POSITIONNELS, ce qui est le vrai piège : insérer un argument en amont
    décale tout le reste en silence, et le son sort quand même. L'ordre est donc construit à
    partir du schéma que le serveur publie sur /gradio_api/info, jamais écrit à la main.
    """

    name = "zonos"
    label = "Zonos v0.1 (release SkyrimNet, GPU)"
    tier = TIER_CLONED

    def __init__(self):
        self.config = None
        path = os.path.join(HERE, "zonos.json")
        if os.path.isfile(path):
            try:
                with io.open(path, encoding="utf-8") as handle:
                    self.config = json.load(handle)
            except ValueError:
                self.config = None

    def available(self):
        return bool(self.config and self.config.get("url"))

    def order(self):
        """L'ordre des arguments, demandé au serveur plutôt que recopié.

        Un banc qui code cet ordre en dur se trompe le jour où le serveur change de version, et
        se trompe SANS ERREUR : Gradio prend une liste, pas des noms.
        """
        import urllib.request

        with urllib.request.urlopen(self.config["url"] + "/gradio_api/info", timeout=30) as answer:
            info = json.loads(answer.read().decode("utf-8"))
        parameters = info["named_endpoints"]["/generate_audio"]["parameters"]
        return [(p.get("parameter_name"), p.get("parameter_default")) for p in parameters]

    def render(self, text, path):
        import urllib.request

        overrides = dict(self.config.get("parameters", {}))
        overrides["text"] = text

        data = []
        for name, default in self.order():
            data.append(overrides.get(name, default))

        started = time.time()
        request = urllib.request.Request(
            self.config["url"] + "/gradio_api/call/generate_audio",
            data=json.dumps({"data": data}).encode("utf-8"),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as answer:
            event = json.loads(answer.read().decode("utf-8"))["event_id"]

        # Le flux d'événements. Le son n'existe qu'à la ligne "complete" : Zonos ne diffuse pas
        # au fil de l'eau, donc le premier son et le dernier arrivent ensemble.
        result = None
        with urllib.request.urlopen(
                self.config["url"] + "/gradio_api/call/generate_audio/" + event, timeout=600) as stream:
            for raw in stream:
                line = raw.decode("utf-8", "replace").strip()
                if line.startswith("data:"):
                    body = line[len("data:"):].strip()
                    if body and body != "null":
                        try:
                            result = json.loads(body)
                        except ValueError:
                            pass
        first = time.time()

        if not result:
            raise RuntimeError("le serveur n'a rien rendu")

        audio = result[0]
        url = audio.get("url") if isinstance(audio, dict) else None
        if not url:
            raise RuntimeError("pas d'audio dans la reponse : {0}".format(str(result)[:120]))

        with urllib.request.urlopen(url, timeout=120) as download:
            payload = download.read()
        with io.open(path, "wb") as handle:
            handle.write(payload)
        done = time.time()

        # infer_ms est le temps du serveur, hors telechargement du fichier rendu.
        return first - started, done - started, first - started


class Sapi(object):
    """La référence, et elle n'installe rien.

    System.Speech fait partie de Windows, donc ce moteur tourne sur une machine nue et donne le
    point de comparaison qui compte : la voix que le mod a aujourd'hui.
    """

    name = "sapi"
    label = "Windows SAPI (System.Speech)"
    tier = TIER_SPLICED

    def available(self):
        return os.name == "nt"

    # ATTENTION EN LISANT LA COLONNE : ce moteur paie un lancement de processus PowerShell,
    # de l'ordre de 200 ms, que les autres ne paient pas. Le chiffre en processus est celui de
    # la suite du plugin (`plugin\test\run.ps1`), qui appelle le meme SAPI sans intermediaire.
    # Ici la ligne SAPI est donc une borne haute, et elle sert de repere, pas de record.
    def render(self, text, path):
        script = (
            "Add-Type -AssemblyName System.Speech; "
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            "$s.SetOutputToWaveFile('{path}'); "
            "$s.Speak([Console]::In.ReadToEnd()); "
            "$s.Dispose()"
        ).format(path=path.replace("'", "''"))

        started = time.time()
        subprocess.run(["powershell", "-NoProfile", "-Command", script],
                       input=text.encode("utf-8"), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
        # Pas de streaming : le premier son et le dernier arrivent au même moment, et c'est le
        # fait mesuré plutôt qu'un défaut de la mesure.
        done = time.time()
        return done - started, done - started, None


class Piper(object):
    """Petit modèle neuronal, CPU, et il écrit son .wav au fil de l'eau.

    Le premier octet est donc mesurable séparément du dernier, ce qui est toute la raison de
    l'essayer : c'est le seul étage de base qui peut commencer à parler avant d'avoir fini.
    """

    name = "piper"
    label = "Piper (neuronal, CPU)"
    tier = TIER_NEURAL

    def __init__(self):
        self.exe = os.path.join(HERE, "engines", "piper", "piper.exe")
        self.voice = os.path.join(HERE, "engines", "piper", "fr_FR-siwis-medium.onnx")

    def available(self):
        return os.path.isfile(self.exe) and os.path.isfile(self.voice)

    def render(self, text, path):
        started = time.time()
        process = subprocess.Popen(
            [self.exe, "--model", self.voice, "--output_file", path],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        _, notes = process.communicate(text.encode("utf-8"))
        done = time.time()

        # Le premier octet AUDIBLE, pas le premier du fichier : un .wav commence par 44 octets
        # d'en-tête. Avec --output_file, piper écrit tout à la fin, donc il n'y a rien à guetter
        # -- le premier son et le dernier arrivent ensemble, et c'est le fait mesuré.
        return done - started, done - started, self.InferSeconds(notes)

    # Le temps que le MODÈLE a passé, tel que piper le publie lui-même. C'est le seul chiffre du
    # tableau qui ne paie ni lancement de processus ni chargement du modèle -- donc le seul qui
    # dise ce que coûterait un service résident, qui charge une fois et répond ensuite.
    def InferSeconds(self, notes):
        # piper l'ecrit colle a une parenthese : "(infer=0.0823318 sec,". Le mot n'est donc
        # jamais nu, et un startswith() dessus renvoie toujours rien -- silencieusement.
        for word in (notes or b"").decode("utf-8", "replace").replace("(", " ").split():
            if word.startswith("infer="):
                try:
                    return float(word[len("infer="):])
                except ValueError:
                    return None
        return None


# Du meilleur rendu attendu au pire : c'est l'ordre dans lequel le tableau se lit.
ENGINES = [Zonos(), Piper(), Sapi()]


def run(engines, lines):
    if not os.path.isdir(OUT):
        os.makedirs(OUT)

    facts = machine()
    print("")
    print("machine : {0}, {1} coeurs, {2} ({3} Mo)".format(
        facts["cpu"], facts["cores"], facts["gpu"], facts["vram_mb"]))
    print("")
    print("{:<10} {:<10} {:<10} {:>9} {:>9} {:>9} {:>8} {:>6}".format(
        "moteur", "palier", "réplique", "first_ms", "total_ms", "infer_ms", "audio_s", "rtf"))
    print("-" * 78)
    rows = []

    for engine in engines:
        for line in lines:
            path = os.path.join(OUT, "{0}-{1}.wav".format(engine.name, line["id"]))
            try:
                first, total, infer = engine.render(line["text"], path)
            except Exception as error:  # un moteur qui casse ne doit pas emporter le banc
                print("{:<10} {:<10}  {}".format(engine.name, line["id"], error))
                continue

            seconds = wav_seconds(path)
            # Le facteur temps-réel se calcule sur l'inférence quand le moteur la publie : sinon
            # il mesure surtout un lancement de processus, ce qui n'est pas la question.
            basis = infer if infer else total
            rtf = (seconds / basis) if basis > 0 else 0.0
            rows.append({"engine": engine.name, "tier": engine.tier, "line": line["id"],
                         "first_ms": round(first * 1000.0), "total_ms": round(total * 1000.0),
                         "infer_ms": round(infer * 1000.0) if infer else None,
                         "audio_s": round(seconds, 2), "rtf": round(rtf, 2)})
            print("{:<10} {:<10} {:<10} {:>9.0f} {:>9.0f} {:>9} {:>8.2f} {:>6.2f}".format(
                engine.name, engine.tier, line["id"], first * 1000.0, total * 1000.0,
                "{:.0f}".format(infer * 1000.0) if infer else "-", seconds, rtf))

    # Accumulé plutôt qu'écrasé : un preset se définit en comparant des machines, donc chaque
    # passage garde le sien.
    results = os.path.join(OUT, "results.json")
    history = []
    if os.path.isfile(results):
        try:
            with io.open(results, encoding="utf-8") as handle:
                history = json.load(handle)
        except ValueError:
            history = []
    history.append({"when": datetime.datetime.now().isoformat(timespec="seconds"),
                    "machine": facts, "rows": rows})
    with io.open(results, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(history, ensure_ascii=False, indent=2))

    print("")
    print("Les .wav sont dans {0} -- écoute-les, c'est la seule mesure qui reste.".format(OUT))
    print("Les chiffres sont gardés dans out\\results.json, avec la machine qui les a produits.")
    print("first_ms / total_ms sont mesurés À FROID : un processus lancé et un modèle chargé")
    print("pour une seule réplique. Ce n'est pas ainsi que le mod l'appellera. infer_ms est le")
    print("temps du modèle seul, publié par le moteur -- c'est lui qui dit ce que coûterait un")
    print("service résident, et rtf est calculé dessus quand il existe.")


def main():
    parser = argparse.ArgumentParser(description="Banc de synthèse vocale pour ai_npc.")
    parser.add_argument("--engine", help="n'en mesurer qu'un")
    parser.add_argument("--line", help="ne dire qu'une réplique, par son id")
    args = parser.parse_args()

    with io.open(os.path.join(HERE, "lines.json"), encoding="utf-8") as handle:
        lines = json.load(handle)["lines"]
    if args.line:
        lines = [line for line in lines if line["id"] == args.line]
        if not lines:
            print("Aucune réplique de cet id.")
            return 1

    chosen = [e for e in ENGINES if not args.engine or e.name == args.engine]
    if not chosen:
        print("Aucun moteur de ce nom. Connus : " + ", ".join(e.name for e in ENGINES))
        return 1

    ready = [e for e in chosen if e.available()]
    for engine in chosen:
        if engine not in ready:
            print("absent : {0} ({1}) -- voir fetch.ps1".format(engine.name, engine.label))
    if not ready:
        print("Rien à mesurer.")
        return 1

    run(ready, lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
