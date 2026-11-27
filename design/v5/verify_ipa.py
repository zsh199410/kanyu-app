#!/usr/bin/env python3
"""Package evidence only; this cannot certify signing, visuals, or a physical iPhone."""
import argparse
import hashlib
import json
import plistlib
import subprocess
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
    executable = info['CFBundleExecutable']
    assert executable and '/' not in executable and executable not in ('.', '..')
    binary = z.read(root + executable)
    assert binary[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'), 'Expected Mach-O device binary'
    for flag in (b'--v6-export-qa', b'--context-acceptance', b'backup-verification.json'):
        assert flag not in binary, f'Debug QA marker in Release: {flag}'
    signature = root + '_CodeSignature/CodeResources' in names
    provision = root + 'embedded.mobileprovision' in names
    assert not signature and not provision, 'Unexpected main app signing payload'
receipt = dict(commit=commit, version=a.version, build=a.build,
               bundleID=info['CFBundleIdentifier'], bytes=a.ipa.stat().st_size,
               sha256=sha, zipCRC='PASS', executable=executable, registeredFonts=bundled_fonts,
               mainAppCodeResources=signature, embeddedProvision=provision,
               signingRequested=False, classification='unsigned engineering candidate',
               fullVisualAcceptance=False, physicalDeviceAcceptance=False)
a.output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
a.ipa.with_suffix(a.ipa.suffix + '.sha256').write_text(f'{sha}  {a.ipa.name}\n')
print(json.dumps(receipt, ensure_ascii=False, indent=2))
