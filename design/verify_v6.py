#!/usr/bin/env python3
"""Static design contract checks, not XCTest or a visual/performance certification."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '1ae6503994940414ab31afb4906cb7b32d291d82'

def original(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT, text=True)

def replace_region(text, first, last):
    a = text.index(first)
    b = text.index(last, a)
    return text[:a] + '<PRESENTATION-ONLY>\n' + text[b:]

# Mask by the stable section following KyMotion, independent of struct/alias syntax.
def mask_app(text):
    text = replace_region(text, 'enum Ky {', '/// 动效标准')
    start = text.index('enum KyMotion {')
    end = text.index('\n}\n', start) + len('\n}\n')
    tail = text.index('extension View {', end)
    return text[:end] + '<BUTTON-STYLE>\n' + text[tail:]
assert mask_app(original('Sources/KanyuApp.swift')) == mask_app((ROOT/'Sources/KanyuApp.swift').read_text()), 'Engine or other app code changed'
# Keep everything outside the first card wrapper unchanged, including the complete settings code.
def mask_card(text):
    a = text.index('extension View {\n', text.index('struct KyWorkspaceHeading'))
    b = text.index('    /// 浅染内嵌卡', a)
    return text[:a] + '<CARD-WRAPPER>\n' + text[b:]
assert mask_card(original('Sources/DesignSystemV2.swift')) == mask_card((ROOT/'Sources/DesignSystemV2.swift').read_text()), 'Non-card code changed'
# Compare every baseline file except explicitly allowed presentation/doc additions.
allowed = {'Sources/KanyuApp.swift', 'Sources/DesignSystemV2.swift'}
files = subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
for path in files:
    if path in allowed or path.startswith(('docs/', 'design/')): continue
    data = subprocess.check_output(['git','show',f'{BASE}:{path}'],cwd=ROOT)
    assert (ROOT/path).is_file() and (ROOT/path).read_bytes() == data, f'Protected baseline file changed: {path}'
for folder in ['Tests','UITests','Resources']:
    tracked = [x for x in files if x.startswith(folder+'/')]
    actual = [str(x.relative_to(ROOT)) for x in (ROOT/folder).rglob('*') if x.is_file()]
    assert set(actual) == set(tracked), f'Protected folder file list changed: {folder}'
tokens = json.loads((ROOT/'design/tokens-v6.json').read_text())
swift = (ROOT/'Sources/DesignSystemV6.swift').read_text()
for key, value in tokens['colors'].items():
    assert f'static let {key}: UInt32 = 0x{value[1:]}' in swift, f'Palette drift: {key}'
assert '\\.accessibilityContrast' not in swift, 'Invalid SwiftUI contrast environment key'
assert swift.count('@Environment(\\.colorSchemeContrast)') == 2
css = (ROOT/'design/web/kanyu-v6.css').read_text().lower()
roles = {
    'paper': '--ky-bg', 'ivory': '--ky-card', 'ink': '--ky-ink',
    'indigo': '--ky-action', 'secondaryLight': '--ky-secondary',
    'obsidian': '--ky-bg', 'jadeCard': '--ky-card',
    'foregroundDark': '--ky-ink', 'champagne': '--ky-action',
    'secondaryDark': '--ky-secondary',
}
light_css, dark_css = css.split('[data-kanyu-theme="dark"] {', 1)
dark_css = dark_css.split('}', 1)[0]
for key, role in roles.items():
    part = dark_css if key in {'obsidian','jadeCard','foregroundDark','champagne','secondaryDark'} else light_css
    assert f'{role}:{tokens["colors"][key].lower()}' in part, f'CSS palette drift: {key}'
assert tokens['poster']['textInsetPt']*2 == 64
assert (tokens['poster']['textInsetPt']-tokens['poster']['innerFrameInsetPt'])*2 >= 28

def luminance(hex_color):
    values = [int(hex_color[i:i+2],16)/255 for i in (1,3,5)]
    values = [v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in values]
    return sum(a*b for a,b in zip(values,[.2126,.7152,.0722]))
def ratio(a,b):
    values = sorted([luminance(a),luminance(b)])
    return (values[1]+.05)/(values[0]+.05)
pairs = [('Light body','#2B2723','#FCFBF7'),('Light secondary','#6D665D','#F6F1E6'),
         ('Light action','#FFFFFF','#1F4959'),('Light action highlight','#FFFFFF','#2C5B6B'),
         ('Dark body','#F2EBDD','#1A1D23'),('Dark secondary','#B5AEA2','#111317'),
         ('Dark action','#111317','#D1AC53'),('Dark action highlight','#111317','#DABB76'),
         ('Functional bronze','#80601F','#FCFBF7')]
lines = ['# V6 静态核查', '', '| 色对 | 对比度 |', '| --- | ---: |']
for name,a,b in pairs:
    value = ratio(a,b)
    assert value>=4.5, (name,value)
    lines.append(f'| {name} | {value:.2f}:1 |')
lines += ['', '已核对：引擎与非呈现代码不变，Tests/UITests/Resources 文件与基线逐字节相同；Swift/JSON/Web 主要语义色一致；海报几何预算通过。',
          '此结果不是 Xcode 编译、截图、VoiceOver 或真机性能验收。']
(ROOT/'docs/design-v6/STATIC-VERIFICATION.md').write_text('\n'.join(lines)+'\n')
print('PASS: protected files, UI-only diff, Swift/CSS palette parity, text contrast pairs and export geometry')
