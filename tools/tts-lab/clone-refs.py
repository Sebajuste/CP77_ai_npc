# -*- coding: utf-8 -*-
"""Passe les extraits de reference de `voice-extract` dans Zonos, un rendu par personnage.

    python tools\\tts-lab\\clone-refs.py                       # la replique "argot"
    python tools\\tts-lab\\clone-refs.py --line longue         # une autre de lines.json
    python tools\\tts-lab\\clone-refs.py judy panam            # deux personnages

Sortie : `out\\clone-<personnage>-<replique>.wav`. La replique est dans le nom parce qu'un
rendu ne se juge pas sans savoir ce qui a ete demande.

Le texte vient de `lines.json` et n'est jamais retape ici : ses accents sont porteurs, et une
replique recopiee sans eux se prononce faux -- « Ramene » se dit « Amen », « 22h » se dit
« vingt-deusse ». Mesure du 2026-08-31, sur une sonde qui avait justement retape le texte.

Zonos doit tourner (`2_Start_Zonos.bat`), et la reference doit lui etre **televersee** : un
chemin de fichier, meme relatif au dossier du serveur, est refuse par le garde de Gradio.
"""
import argparse
import hashlib
import io
import json
import os
import sys
import time
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lab  # noqa: E402
import voice_bench  # noqa: E402


def upload(url, path):
    """Televerse la reference, sous un nom qui porte l'empreinte de son contenu.

    Le serveur met l'embedding de locuteur en cache **par nom de fichier**. Mesure du
    2026-08-31 : l'audio de Takemura envoye sous un nom deja vu ressort avec la voix de Judy,
    au bit pres. Deux references differentes sous un meme nom sont donc silencieusement la
    meme voix, et une comparaison de references faite sous un nom stable ne compare rien.
    """
    with io.open(path, "rb") as handle:
        payload = handle.read()
    stem, extension = os.path.splitext(os.path.basename(path))
    filename = "%s-%s%s" % (stem, hashlib.sha256(payload).hexdigest()[:12], extension)

    boundary = uuid.uuid4().hex
    body = io.BytesIO()
    body.write(("--%s\r\n" % boundary).encode("utf-8"))
    body.write(('Content-Disposition: form-data; name="files"; filename="%s"\r\n'
                % filename).encode("utf-8"))
    body.write(b"Content-Type: audio/wav\r\n\r\n")
    body.write(payload)
    body.write(("\r\n--%s--\r\n" % boundary).encode("utf-8"))
    request = urllib.request.Request(
        url + "/gradio_api/upload", data=body.getvalue(),
        headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(request, timeout=180) as answer:
        return json.loads(answer.read().decode("utf-8"))[0]


def render(engine, order, text, reference, target, conditioning=None):
    overrides = dict(engine.config.get("parameters", {}))
    overrides.update(conditioning or {})
    overrides["text"] = text
    overrides["speaker_audio"] = {"path": reference, "meta": {"_type": "gradio.FileData"}}
    data = [overrides.get(name, default) for name, default in order]

    url = engine.config["url"]
    started = time.time()
    request = urllib.request.Request(
        url + "/gradio_api/call/generate_audio",
        data=json.dumps({"data": data}).encode("utf-8"),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as answer:
        event = json.loads(answer.read().decode("utf-8"))["event_id"]

    result = None
    with urllib.request.urlopen(url + "/gradio_api/call/generate_audio/" + event, timeout=900) as stream:
        for raw in stream:
            line = raw.decode("utf-8", "replace").strip()
            if line.startswith("data:"):
                body = line[len("data:"):].strip()
                if body and body != "null":
                    try:
                        result = json.loads(body)
                    except ValueError:
                        pass
    if not result:
        raise RuntimeError("le serveur n'a rien rendu")
    with urllib.request.urlopen(result[0]["url"], timeout=180) as download:
        payload = download.read()
    with io.open(target, "wb") as handle:
        handle.write(payload)
    return time.time() - started


def nyquist(path):
    """`fmax` doit annoncer la bande de la reference, pas celle du serveur.

    Zonos conditionne la generation sur `fmax`, et son defaut est 22050 quel que soit le
    fichier fourni. Une reference en 48 kHz porte du signal jusqu'a 24000 : lui annoncer 22050
    revient a decrire une bande plus etroite que celle qu'on donne -- c'est-a-dire une radio.
    Mesure du 2026-08-31 : c'est le seul conditionnement de qualite qui atteigne le modele,
    `dnsmos_ovrl` et `speaker_noised` sont sans effet.
    """
    with wave.open(path) as handle:
        return handle.getframerate() // 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("characters", nargs="*")
    # "argot" par defaut : la seule replique longue de lines.json sans chiffre. Les autres
    # portent un nombre, et un nombre colle a son unite ("22h") fait deraper le moteur --
    # ce qui masque la voix qu'on cherche justement a juger.
    parser.add_argument("--line", default="argot")
    parser.add_argument("--voices", default=voice_bench.VOICES)
    parser.add_argument("--tag", default="",
                        help="suffixe du nom de sortie, pour comparer deux jeux de references")
    parser.add_argument("--cfg", type=float, default=3.0,
                        help="cfg_scale ; 2.0 est le defaut du serveur, 3.0 a ete juge meilleur "
                             "a l'oreille le 2026-08-31")
    parser.add_argument("--tries", type=int, default=3,
                        help="rendus au plus par personnage : la graine avance tant que le "
                             "resultat est coupe")
    args = parser.parse_args()

    text = voice_bench.lines()[args.line]
    print(u'replique "%s" : %s' % (args.line, text))

    engine = lab.Zonos()
    if not engine.available():
        raise SystemExit("zonos.json absent ou sans url")
    order = engine.order()

    out = os.path.join(HERE, "out")
    if not os.path.isdir(out):
        os.makedirs(out)
    for contact, source in voice_bench.references(args.voices):
        if args.characters and contact not in args.characters:
            continue
        reference = upload(engine.config["url"], source)
        target = os.path.join(out, "clone-%s-%s%s.wav" % (contact, args.line, args.tag))
        conditioning = {"fmax": nyquist(source), "cfg_scale": args.cfg}

        seed = int(engine.config["parameters"].get("seed", 0))
        for attempt in range(args.tries):
            engine.config["parameters"]["seed"] = seed + attempt
            took = render(engine, order, text, reference, target, conditioning)
            values, rate = voice_bench.samples(target)
            rms, _ = voice_bench.level(values)
            if not voice_bench.truncated(values, rate, rms):
                break
        engine.config["parameters"]["seed"] = seed

        voice_bench.report(contact, took, target,
                           "  graine +%d" % attempt if attempt else "")


if __name__ == "__main__":
    main()
