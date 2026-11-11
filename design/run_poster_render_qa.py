#!/usr/bin/env python3
"""Launch the Debug-only renderer on an installed XCTest simulator app; preserve real PNGs."""
import hashlib
import json
import shutil
import struct
import subprocess
import time
from pathlib import Path

def simctl(*args):
    print(f'QA stage: simctl {args[0]} started', flush=True)
    output = subprocess.check_output(['xcrun', 'simctl', *args], text=True).strip()
    print(f'QA stage: simctl {args[0]} completed', flush=True)
    return output

devices = json.loads(simctl('list', 'devices', 'available', '-j'))['devices']
iPhones = [device for group in devices.values() for device in group if 'iPhone' in device['name']]
assert iPhones, 'No available iPhone simulator'
device = next((item for item in iPhones if item['state'] == 'Booted'), iPhones[0])
udid = device['udid']
if device['state'] != 'Booted':
    simctl('boot', udid)
simctl('bootstatus', udid, '-b')
app = Path('build/SimulatorDD/Build/Products/Debug-iphonesimulator/Kanyu.app')
assert app.is_dir(), 'Missing actual Debug app built by the unchanged XCTest suite'
simctl('install', udid, str(app.resolve()))
data = Path(simctl('get_app_container', udid, 'com.kanyu.survey', 'data'))
source = data / 'Library/Caches/V6ExportQA'
if source.exists():
    shutil.rmtree(source)
simctl('launch', '--terminate-running-process', udid, 'com.kanyu.survey', '--v6-export-qa')
try:
    deadline = time.monotonic() + 180
    manifest_path = source / 'manifest.json'
    while not manifest_path.exists() and time.monotonic() < deadline:
        time.sleep(1)
    assert manifest_path.exists(), 'Native renderer did not produce a manifest within 180 seconds'
    manifest = json.loads(manifest_path.read_text())
    print(f"QA manifest received: {manifest['status']}, {len(manifest['samples'])} valid samples", flush=True)
    assert manifest['status'] == 'success', manifest
    expected = {f'{kind}-{style}.png' for kind in ['bazi', 'ziwei', 'hecan']
                for style in ['song', 'zhusha', 'xuanye']} | {'bazi-yucedan.png', 'palm-empty-photo.png'}
    assert {row['file'] for row in manifest['samples']} == expected
    for row in manifest['samples']:
        payload = (source / row['file']).read_bytes()
        assert payload[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', payload[16:24])
        assert (width, height) == (row['width'], row['height'])
        assert width == 1080 and height > width
        assert hashlib.sha256(payload).hexdigest() == row['sha256']
    backup = json.loads((source / 'backup-verification.json').read_text())
    assert backup['status'] == 'success' and len(backup['checks']) == 17
    assert len(backup['archives']) == 3
    for row in backup['archives']:
        payload = (source / row['file']).read_bytes()
        assert payload[:2] == b'PK' and hashlib.sha256(payload).hexdigest() == row['sha256']
    print(f"PASS: {len(backup['checks'])} native production backup helper checks and three actual ZIP SHA256 values")
    print(f'PASS: {len(expected)} actual native PNGs, width/height, decoding and SHA256 verified; visual review still required')
finally:
    # Preserve partial images even if rendering crashes or times out before the manifest.
    if source.exists():
        shutil.copytree(source, Path('build/poster-samples'), dirs_exist_ok=True)
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, 'com.kanyu.survey'], check=False)
