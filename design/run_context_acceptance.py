#!/usr/bin/env python3
"""Build and exercise a separate QA bundle; never uninstall or reset the production app.

Needs macOS, Xcode and XcodeGen. --generate-only can inspect the derived JSON spec elsewhere.
Existing project.yml, Tests/, UITests/ and golden data are not rewritten.
"""
import argparse
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'com.kanyu.survey.contextqa'
CASES = {
    'light-standard': ('testLightStandard', 'light', 'large'),
    'dark-standard': ('testDarkStandard', 'dark', 'large'),
    'light-accessibility': ('testLightAccessibility', 'light', 'accessibility-extra-extra-extra-large'),
    'dark-accessibility': ('testDarkAccessibility', 'dark', 'accessibility-extra-extra-extra-large'),
}


def command(args, *, log=None, check=True):
    print('QA command: ' + ' '.join(map(str, args)), flush=True)
    if log:
        with log.open('w') as output:
            result = subprocess.run(list(map(str, args)), cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        if check and result.returncode:
            print('\n'.join(log.read_text(errors='replace').splitlines()[-60:]), flush=True)
            raise subprocess.CalledProcessError(result.returncode, args)
    else:
        result = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, text=True)
        if check and result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
    return result


def specification(directory):
    return {
        'include': [{'path': str(ROOT / 'project.yml'), 'relativePaths': True}],
        'name': 'KanyuContext',
        'targets': {
            'Kanyu': {
                'sources:REPLACE': [{'path': str(ROOT / 'Sources'), 'excludes': ['Info.plist']}, str(ROOT / 'Resources')],
                'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': BUNDLE}},
                'info': {'path': str(directory / 'ContextApp-Info.plist'), 'properties': {'CFBundleDisplayName': '三术合参 QA'}},
            },
            'KanyuContextUITests': {
                'type': 'bundle.ui-testing', 'platform': 'iOS',
                'sources': [str(ROOT / 'design/acceptance/ProfileContextTests.swift')],
                'dependencies': [{'target': 'Kanyu'}],
                'settings': {'base': {'TEST_TARGET_NAME': 'Kanyu', 'SWIFT_VERSION': '5.9',
                                      'PRODUCT_BUNDLE_IDENTIFIER': BUNDLE + '.tests', 'GENERATE_INFOPLIST_FILE': 'YES'}},
            },
        },
        'schemes': {'KanyuContext': {'build': {'targets': {'Kanyu': 'all', 'KanyuContextUITests': ['test']}},
                                     'test': {'targets': ['KanyuContextUITests']}}},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=CASES, required=True)
    parser.add_argument('--generate-only', action='store_true')
    args = parser.parse_args()
    directory = ROOT / 'build/context'
    evidence = ROOT / 'build/context-evidence'
    directory.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    spec = directory / 'project.json'
    spec.write_text(json.dumps(specification(directory), ensure_ascii=False, indent=2))
    if args.generate_only:
        print(spec)
        return
    if sys.platform != 'darwin':
        raise RuntimeError('Actual UI acceptance requires a macOS Xcode simulator; not run here')
    method, theme, content_size = CASES[args.case]
    commit = command(['git', 'rev-parse', 'HEAD']).stdout.strip()
    report = {'case': args.case, 'commit': commit, 'bundleIdentifier': BUNDLE, 'status': 'failure',
              'scope': 'Synthetic profile lifecycle through real UI in a separate simulator bundle; not hardware, iCloud or all tool algorithms'}
    result_bundle = directory / 'Results.xcresult'
    device = None
    try:
        generated = directory / 'generated'
        generated.mkdir(exist_ok=True)
        command(['xcodegen', 'generate', '--spec', spec, '--project', generated])
        devices = json.loads(command(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']).stdout)['devices']
        phones = [(runtime, item) for runtime, group in devices.items() for item in group if 'iPhone' in item['name']]
        assert phones, 'No iPhone simulator'
        runtime, phone = next((row for row in phones if row[1]['state'] == 'Booted'), phones[0])
        device = phone['udid']
        if phone['state'] != 'Booted':
            command(['xcrun', 'simctl', 'boot', device])
        command(['xcrun', 'simctl', 'bootstatus', device, '-b'])
        command(['xcrun', 'simctl', 'uninstall', device, BUNDLE], check=False)
        command(['xcrun', 'simctl', 'ui', device, 'appearance', theme])
        command(['xcrun', 'simctl', 'ui', device, 'content_size', content_size])
        report.update(device=phone['name'], runtime=runtime, appearance=theme,
                      contentSize=command(['xcrun', 'simctl', 'ui', device, 'content_size']).stdout.strip())
        common = ['xcodebuild', '-project', generated / 'KanyuContext.xcodeproj', '-scheme', 'KanyuContext',
                  '-destination', 'platform=iOS Simulator,id=' + device,
                  '-derivedDataPath', directory / 'DD', '-clonedSourcePackagesDirPath', ROOT / 'build/SourcePackages',
                  'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=']
        command(common + ['build-for-testing'], log=evidence / 'build.log')
        app = directory / 'DD/Build/Products/Debug-iphonesimulator/Kanyu.app'
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == BUNDLE, 'Refuse to exercise the normal app bundle'
        command(common + ['test-without-building', '-resultBundlePath', result_bundle,
                          '-only-testing:KanyuContextUITests/ProfileContextTests/' + method], log=evidence / 'tests.log')
        log = (evidence / 'tests.log').read_text()
        assert re.search(r'Executed 1 test, with 0 failures', log), 'Expected one actually executed acceptance test'
        assert '** TEST SUCCEEDED **' in log or '** TEST EXECUTE SUCCEEDED **' in log
        container = Path(command(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data']).stdout.strip())
        people_file = container / 'Documents/people.json'
        assert people_file.is_file(), 'UI did not persist any profile lifecycle data'
        people = json.loads(people_file.read_text())
        assert people == [], 'UI deletion left profile records behind'
        shutil.copyfile(people_file, evidence / 'people-after.json')
        report.update(status='success', testsExecuted=1, failures=0, peopleAfterDeletion=0)
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if result_bundle.exists():
            command(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', result_bundle,
                     '--output-path', evidence / 'screenshots'], check=False)
        (evidence / 'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        (evidence / 'commit.txt').write_text(commit + '\n')
        if device:
            command(['xcrun', 'simctl', 'terminate', device, BUNDLE], check=False)
        print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
