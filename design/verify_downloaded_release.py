#!/usr/bin/env python3
"""Verify downloaded V6 release files independently of the macOS build.

Requires: python3 -m pip install pillow pymupdf
Usage: python3 design/verify_downloaded_release.py DIRECTORY BUILD COMMIT [--require-backup]
DIRECTORY must contain Kanyu-unsigned.ipa, its .sha256, and UI-evidence.zip.
Writes QA-verification.json; does not install the IPA or modify app data.
"""
import argparse
import hashlib
import json
import plistlib
import re
import tempfile
import unicodedata
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

import fitz
from PIL import Image


def normalized(value):
    value = value.replace('\u2e3a', '——').replace('\u2e3b', '———')
    return ''.join(unicodedata.normalize('NFKC', value).split())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('build')
    parser.add_argument('commit')
    parser.add_argument('--require-backup', action='store_true')
    args = parser.parse_args()
    root = args.directory.resolve()
    ipa = root / 'Kanyu-unsigned.ipa'
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    assert digest == (root / 'Kanyu-unsigned.ipa.sha256').read_text().split()[0], 'IPA SHA256 mismatch'
    with ZipFile(ipa) as archive:
        assert archive.testzip() is None, 'IPA CRC failure'
        info = plistlib.loads(archive.read('Payload/Kanyu.app/Info.plist'))
        assert info['CFBundleVersion'] == args.build, 'Wrong build number'
        assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
        binary = archive.read('Payload/Kanyu.app/Kanyu')
        assert b'--v6-export-qa' not in binary, 'Debug QA launch flag in Release'
        assert b'backup-verification.json' not in binary, 'Debug backup QA in Release'
        assert b'--context-acceptance' not in binary, 'Debug context QA launch flag in Release'
    result = {'build': args.build, 'version': info['CFBundleShortVersionString'],
              'commit': args.commit, 'ipaBytes': ipa.stat().st_size, 'sha256': digest,
              'zipCRC': 'pass', 'releaseExcludesQALaunchFlag': True}
    with tempfile.TemporaryDirectory(prefix='kanyu-release-check-') as temporary:
        with ZipFile(root / 'UI-evidence.zip') as archive:
            assert archive.testzip() is None, 'Evidence CRC failure'
            for entry in archive.namelist():
                path = PurePosixPath(entry.replace('\\', '/'))
                assert not path.is_absolute() and '..' not in path.parts, 'Unsafe evidence path'
            archive.extractall(temporary)
        build = Path(temporary) / 'build'
        assert (build / 'commit.txt').read_text().strip() == args.commit, 'Wrong evidence source commit'
        log = (build / 'tests.log').read_text()
        assert '** TEST SUCCEEDED **' in log
        assert 'Executed 109 tests, with 0 failures' in log
        assert 'Executed 1 test, with 0 failures' in log
        result.update(unitTests=109, uiSmokeTests=1, failures=0)
        receipts = json.loads((build / 'report-receipts.json').read_text())
        assert len(receipts) == 3 and all(row['beijingBirthReceipt'] == 'pass' for row in receipts)
        native_text = json.loads((build / 'report-text-verification.json').read_text())
        assert native_text['status'] == 'success' and len(native_text['reports']) == 3
        assert all(not row['missingLines'] and not row.get('orphanHeadings', []) for row in native_text['reports'])
        expected = json.loads((build / 'poster-samples/report-expected-text.json').read_text())
        pdfs = list((build / 'report-samples').glob('*.pdf'))
        assert len(pdfs) == 3 and {row['tier'] for row in expected} == {'简洁', '专业', '完整'}
        footer = re.compile(r'三术合参·命书[—–-]第[0-9]+页\(共[0-9]+页\)')
        reports = []
        for row in expected:
            matches = [file for file in pdfs if '-' + row['tier'] + '-' in file.name]
            assert len(matches) == 1
            file = matches[0]
            assert file.name.endswith('-' + row['contentHash'][:12] + '.pdf')
            with fitz.open(file) as document:
                assert len(document) >= 3
                assert '2000-01-0108:00(北京时间UTC+8)' in normalized(document[0].get_text())
                body = footer.sub('', normalized(''.join(document[i].get_text() for i in range(2, len(document)))))
                source = normalized(''.join(row['lines']))
                assert body == source, f'Ordered PDF body differs: {row["tier"]}'
                for page in document:
                    for block in page.get_text('dict')['blocks']:
                        for line in block.get('lines', []):
                            for span in line['spans']:
                                x0, y0, x1, y1 = span['bbox']
                                assert x0 >= -.5 and y0 >= -.5 and x1 <= page.rect.width + .5 and y1 <= page.rect.height + .5, (file.name, span['text'])
                reports.append({'tier': row['tier'], 'pages': len(document), 'contentHash': row['contentHash'],
                                'orderedBodyEquality': True, 'normalizedBodyCharacters': len(source), 'outsidePageTextSpans': 0})
        result['pdfReports'] = reports
        result['pdfTextScope'] = 'Body pages after cover/contents; normalize NFKC and whitespace, expand two/three-em glyphs, remove exact page footers; ordered equality to complete native drawing inputs'
        result['textBoundsTolerancePt'] = 0.5
        samples = build / 'poster-samples'
        manifest = json.loads((samples / 'manifest.json').read_text())
        expected_png = {f'{kind}-{style}.png' for kind in ['bazi', 'ziwei', 'hecan'] for style in ['song', 'zhusha', 'xuanye']} | {'bazi-yucedan.png', 'palm-empty-photo.png'}
        assert manifest['status'] == 'success' and {row['file'] for row in manifest['samples']} == expected_png
        for row in manifest['samples']:
            file = samples / row['file']
            assert hashlib.sha256(file.read_bytes()).hexdigest() == row['sha256']
            with Image.open(file) as image:
                image.load()
                assert image.size == (row['width'], row['height']) and image.width == 1080 and image.height > image.width
        result['decodedPosterSamples'] = len(expected_png)
        backup_file = samples / 'backup-verification.json'
        if args.require_backup or backup_file.exists():
            backup = json.loads(backup_file.read_text())
            assert backup['status'] == 'success' and len(backup['checks']) == 17 and len(backup['archives']) == 3
            for row in backup['archives']:
                file = samples / row['file']
                assert hashlib.sha256(file.read_bytes()).hexdigest() == row['sha256']
                with ZipFile(file) as archive:
                    assert archive.testzip() is None
                    names = [name for name in archive.namelist() if name.endswith('/people.json') or name == 'people.json']
                    assert len(names) == 1
                    person = json.loads(archive.read(names[0]))
                    assert len(person) == 1 and person[0]['birthEpoch'] == 946684800
                    prefix = names[0][:-len('people.json')]
                    if row['file'] == 'backup-legacy.zip':
                        assert prefix + 'manifest.json' not in archive.namelist()
                    else:
                        contents = json.loads(archive.read(prefix + 'manifest.json'))
                        assert contents['schemaVersion'] == 2 and contents['files']
                        for entry in contents['files']:
                            payload = archive.read(prefix + entry['name'])
                            assert len(payload) == entry['byteCount'] and hashlib.sha256(payload).hexdigest() == entry['sha256']
            result['nativeBackupChecks'] = backup
    result['limits'] = ['Fixed synthetic samples, not all chart inputs or live profile restore paths',
                        'Not signed installation, sensor, iCloud, VoiceOver or performance acceptance']
    (root / 'QA-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
