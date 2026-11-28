#!/usr/bin/env python3
"""Package evidence only; this cannot certify signing, visuals, or a physical iPhone."""
import argparse
import hashlib
import json
import plistlib
import subprocess
import struct
import zipfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('ipa', type=Path)
p.add_argument('--version', required=True)
p.add_argument('--build', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
sha = hashlib.file_digest(a.ipa.open('rb'), 'sha256').hexdigest()
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
with zipfile.ZipFile(a.ipa) as z:
    names = z.namelist()
    assert len(names) == len(set(names)), 'Duplicate ZIP entries'
    assert z.testzip() is None, 'ZIP CRC failed'
    root = 'Payload/Kanyu.app/'
    info = plistlib.loads(z.read(root + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.kanyu.survey'
    assert info['CFBundleShortVersionString'] == a.version
    assert info['CFBundleVersion'] == a.build
    assert info['CFBundlePackageType'] == 'APPL'
    assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
    assert info['MinimumOSVersion'] == '17.0'
    font_manifest = json.loads((Path(__file__).parent / 'font-provenance.json').read_text())
    expected_fonts = {Path(font['path']).name: font['sha256'] for font in font_manifest['fonts']}
    assert sorted(info.get('UIAppFonts', [])) == sorted(expected_fonts), 'Release font registration mismatch'
    bundled_fonts = {}
    for name, expected_sha in expected_fonts.items():
        actual_sha = hashlib.sha256(z.read(root + name)).hexdigest()
        assert actual_sha == expected_sha, f'Release font bytes mismatch: {name}'
        bundled_fonts[name] = actual_sha
    art_manifest = json.loads((Path(__file__).parent / 'asset-manifest.json').read_text())
    assert len(art_manifest['assets']) == 60
    bundled_artwork = {}
    for asset in art_manifest['assets']:
        filename = Path(asset['path']).name
        candidates = [name for name in names if name.startswith(root) and name.endswith('/' + filename)]
        assert len(candidates) == 1, f'Expected exactly one bundled artwork file: {filename}'
        actual_sha = hashlib.sha256(z.read(candidates[0])).hexdigest()
        assert actual_sha == asset['sha256'], f'Bundled art SHA mismatch: {filename}'
        bundled_artwork[filename] = actual_sha
    executable = info['CFBundleExecutable']
    assert executable and '/' not in executable and executable not in ('.', '..')
    binary = z.read(root + executable)
    assert binary[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'), 'Expected Mach-O device binary'
    # Validate actual device architecture/platform, not merely a Mach-O signature.
    device_slice = binary
    if binary[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', binary, 4)[0]
        assert 0 < count < 16
        found = []
        for index in range(count):
            cpu, subtype, offset, length, alignment = struct.unpack_from('>IIIII', binary, 8 + index*20)
            if cpu == 0x0100000c:
                assert offset + length <= len(binary)
                found.append(binary[offset:offset+length])
        assert len(found) == 1, 'Expected arm64 device slice'
        device_slice = found[0]
    assert device_slice[:4] == b'\xcf\xfa\xed\xfe'
    assert struct.unpack_from('<I', device_slice, 4)[0] == 0x0100000c, 'Expected ARM64'
    assert struct.unpack_from('<I', device_slice, 12)[0] == 2, 'Expected executable'
    commands = struct.unpack_from('<I', device_slice, 16)[0]
    cursor = 32; platforms = []
    for _ in range(commands):
        command, length = struct.unpack_from('<II', device_slice, cursor)
        assert length >= 8 and cursor + length <= len(device_slice), 'Invalid load command'
        if command == 0x32:
            platforms.append(struct.unpack_from('<I', device_slice, cursor+8)[0])
        cursor += length
    assert platforms == [2], f'Expected iPhoneOS platform, never simulator: {platforms}'
    for flag in (b'--v6-export-qa', b'--context-acceptance', b'backup-verification.json'):
        assert flag not in binary, f'Debug QA marker in Release: {flag}'
    signature = root + '_CodeSignature/CodeResources' in names
    provision = root + 'embedded.mobileprovision' in names
    assert not signature and not provision, 'Unexpected main app signing payload'
receipt = dict(commit=commit, version=a.version, build=a.build,
               bundleID=info['CFBundleIdentifier'], bytes=a.ipa.stat().st_size,
               sha256=sha, zipCRC='PASS', executable=executable, registeredFonts=bundled_fonts, bundledArtwork=bundled_artwork, artworkCount=len(bundled_artwork), architecture='ARM64', machoPlatform='iPhoneOS',
               mainAppCodeResources=signature, embeddedProvision=provision,
               signingRequested=False, classification='unsigned engineering candidate',
               fullVisualAcceptance=False, physicalDeviceAcceptance=False)
a.output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
a.ipa.with_suffix(a.ipa.suffix + '.sha256').write_text(f'{sha}  {a.ipa.name}\n')
print(json.dumps(receipt, ensure_ascii=False, indent=2))
