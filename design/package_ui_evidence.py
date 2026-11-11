#!/usr/bin/env python3
"""Write UTF-8 ZIP names, including Chinese PDF filenames; retain partial evidence on failure."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

paths = ['build/screenshots', 'build/tests.log', 'build/commit.txt', 'build/report-samples',
         'build/archive-verification.json', 'build/report-receipts.json', 'build/poster-samples']
with ZipFile('UI-evidence.zip', 'w', ZIP_DEFLATED) as archive:
    for name in paths:
        path = Path(name)
        if not path.exists():
            continue
        for file in sorted(path.rglob('*')) if path.is_dir() else [path]:
            if file.is_file():
                archive.write(file, str(file))
with ZipFile('UI-evidence.zip') as archive:
    assert archive.testzip() is None
print('PASS: verification ZIP CRC and UTF-8 filenames')
