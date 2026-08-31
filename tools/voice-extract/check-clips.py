"""Verifie les extraits produits : forme du WAV, duree, niveau, coherence du manifeste.

    python tools\\voice-extract\\check-clips.py dist\\voices
"""
import io
import json
import math
import os
import struct
import sys
import wave

MIN_SECONDS = 20.0
MAX_SECONDS = 40.0
MIN_RMS = 0.01


def measure(path):
    with wave.open(path) as w:
        frames = w.getnframes()
        samples = struct.unpack('<%dh' % frames, w.readframes(frames))
        rms = math.sqrt(sum(float(s) * s for s in samples) / max(frames, 1)) / 32768.0
        return {
            'channels': w.getnchannels(),
            'sampleRate': w.getframerate(),
            'width': w.getsampwidth(),
            'seconds': frames / float(w.getframerate()),
            'rms': rms,
        }


def main(directory):
    manifest_path = os.path.join(directory, 'voices.json')
    with io.open(manifest_path, encoding='utf-8') as f:
        manifest = json.load(f)

    failures = []
    for entry in manifest['voices']:
        name = entry['contactId']
        path = os.path.join(directory, entry['file'])
        if not os.path.exists(path):
            failures.append('%s : %s absent' % (name, entry['file']))
            continue
        m = measure(path)
        if m['channels'] != 1 or m['width'] != 2:
            failures.append('%s : %d canaux, %d octets par echantillon' % (name, m['channels'], m['width']))
        if m['sampleRate'] != entry['sampleRate']:
            failures.append('%s : %d Hz, le manifeste annonce %d'
                            % (name, m['sampleRate'], entry['sampleRate']))
        if not MIN_SECONDS <= m['seconds'] <= MAX_SECONDS:
            failures.append('%s : %.1f s hors de [%g, %g]' % (name, m['seconds'], MIN_SECONDS, MAX_SECONDS))
        if m['rms'] < MIN_RMS:
            failures.append('%s : RMS %.4f, extrait muet' % (name, m['rms']))
        if abs(m['seconds'] - entry['seconds']) > 0.05:
            failures.append('%s : le manifeste annonce %.2f s, le fichier en fait %.2f'
                            % (name, entry['seconds'], m['seconds']))
        print('%-16s %5.1f s  %5d Hz  %d canal  RMS %.3f  %2d repliques'
              % (name, m['seconds'], m['sampleRate'], m['channels'], m['rms'], entry['lines']))

    if failures:
        print('')
        for f in failures:
            print('ECHEC ' + f)
        return 1
    print('\n%d extraits conformes' % len(manifest['voices']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'dist/voices'))
