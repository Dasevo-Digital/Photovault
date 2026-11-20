"""Explizit freizugebende Wartung; keine Serverzugriffe beim Import."""
import hashlib
import json
import os
import shlex
import subprocess
import uuid
from pathlib import Path


def aktualisieren(ziele, paket, fassung):
    if not paket.is_file():
        raise SystemExit('Serverpaket fehlt.')
    daten = ziele.get('server_daten')
    if not isinstance(daten, str) or not daten.startswith('/') or daten == '/':
        raise SystemExit('server_daten muss den zuvor inventarisierten absoluten Datenordner nennen.')
    kennung = uuid.uuid4().hex
    mit = ['-i', os.path.expanduser(ziele['server_schluessel']), '-o',
           'UserKnownHostsFile=' + os.path.expanduser(ziele['server_known_hosts']),
           '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10']
    name = '/tmp/pv-wartung-' + kennung + '.tar.gz'
    digest=hashlib.sha256()
    with paket.open('rb') as quelle:
        for block in iter(lambda:quelle.read(1024*1024),b''):
            digest.update(block)
    sha=digest.hexdigest()
    subprocess.run(['scp', '-q', *mit, str(paket), ziele['server_ssh'] + ':' + name], check=True)
    args = json.dumps({'paket': name, 'sha256': sha, 'daten': daten,
                       'fassung': fassung, 'kennung': kennung})
    code = Path(__file__).with_name('server_wartung_fern.py').read_text()
    subprocess.run(['ssh', *mit, ziele['server_ssh'], 'python3 - ' + shlex.quote(args)],
                   input=code, text=True, check=True)
