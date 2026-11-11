#!/usr/bin/env python3
"""Verify recovered Web runtime is unchanged; this is not an API or browser test."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
web = root / 'web'
manifest = json.loads((web/'upstream-sha256.json').read_text())
for name, expected in manifest['sha256'].items():
    data = (web/name).read_bytes()
    if name == 'index.html':
        text = data.decode().replace('<link rel="stylesheet" href="./v6.css">\n','').replace('<script src="./v6.js"></script>\n','')
        data = text.encode()
    assert hashlib.sha256(data).hexdigest() == expected, f'Upstream runtime changed: {name}'
print('PASS: recovered production runtime unchanged; HTML adds only V6 CSS/JS references')
