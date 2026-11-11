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
def refine_home_v6(text):
    before = '                brandHeader\n                    .accessibilityIdentifier("workspace.workbench")\n                signBanner\n                personSwitcherCard'
    after = '                signBanner\n                personSwitcherCard\n                    .accessibilityElement(children: .contain)\n                    .accessibilityIdentifier("workspace.workbench")'
    assert text.count(before) == 1, "Home UI anchor drift"
    text = text.replace(before, after)
    before = '            ToolbarItem(placement: .principal) {\n                HStack(spacing: 6) {\n                    Text("三术合参".scriptConverted)'
    after = '            ToolbarItem(placement: .principal) {\n                HStack(spacing: 6) {\n                    AppLogoView(size: 24).accessibilityHidden(true)\n                    Text("三术合参".scriptConverted)'
    assert text.count(before) == 1, "Home UI anchor drift"
    text = text.replace(before, after)
    before = '            ToolbarItem(placement: .topBarTrailing) {\n                HStack(spacing: 8) {\n                    Button { showingNewPerson = true } label: {\n                    HStack(spacing: 4) {\n                        Image(systemName: "person.badge.plus")\n                        Text("建档")\n                    }\n                    .font(.caption).fontWeight(.bold)\n                    .foregroundStyle(Ky.qingdai)\n                }\n                .accessibilityLabel("新建人物档案")\n                }\n            }\n        }\n'
    after = '            ToolbarItem(placement: .topBarTrailing) {\n                Button { showingMyView = true } label: {\n                    ZStack {\n                        Circle().fill(Ky.card)\n                        if currentPersonNameForHeader.isEmpty {\n                            Image(systemName: "person.crop.circle")\n                        } else {\n                            Text(String(currentPersonNameForHeader.prefix(1)))\n                                .font(.system(.headline, design: .serif))\n                        }\n                    }\n                    .foregroundStyle(Ky.qingdai)\n                    .frame(width: 44, height: 44)\n                    .overlay(Circle().strokeBorder(Ky.line, lineWidth: 0.7).allowsHitTesting(false))\n                }\n                .buttonStyle(.plain)\n                .accessibilityLabel("个人中心与全局设置")\n            }\n        }\n'
    assert text.count(before) == 1, "Home UI anchor drift"
    text = text.replace(before, after)
    before = '        return AnyView(TodayFortuneCard(person: nil, chart: nil))'
    after = '        return AnyView(\n            HStack(spacing: 10) {\n                Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Ky.gold)\n                Text("建档后可查看命主专属的今日解读。".scriptConverted)\n                    .font(.subheadline).foregroundStyle(Ky.sub)\n            }\n            .frame(maxWidth: .infinity, alignment: .leading)\n            .kyCard()\n        )'
    assert text.count(before) == 1, "Home UI anchor drift"
    text = text.replace(before, after)
    before = '                VStack(alignment: .leading, spacing: 10) {\n                    KySectionTitle(title: "勘察案件", trailing: "现场记录")\n                    casesSection\n                }'
    assert text.count(before) == 1, "Survey UI anchor drift"
    text = text.replace(before, '                casesSection')
    before = '            RootTabView()\n'
    assert text.count(before) == 1, "QA host anchor drift"
    text = text.replace(before, '            RootTabView()\n                .modifier(V6ExportQAHost())\n')
    return text

def home_layout_v6(text):
    start=text.index('struct HomePageView: View')
    head, home=text[:start], text[start:]
    home=home.replace('    @State private var showingNewPerson = false', '    @Environment(\\.dynamicTypeSize) private var homeTypeSize\n    @State private var showingNewPerson = false',1)
    home=home.replace('''            // 120Hz：外层改回 LazyVStack，只渲染可见区段（纠正 build-72 的说法——VStack 全量预布局抬高首帧挂载成本，长页正确做法是可见区渲染）
            LazyVStack(alignment: .leading, spacing: 16) {
                KyWorkspaceHeading(title: "选择人物，开始合参", detail: "从命盘进入解读、回验和报告。", icon: "person.crop.circle")''','''            // Keep the workspace lazy; frame pacing requires device measurement.
            LazyVStack(alignment: .leading, spacing: KanyuV6.Metric.cardGap) {
                brandHeader''',1)
    home=home.replace('''                personSwitcherCard
                primaryBentoGrid''','''                personSwitcherCard
                todaySection
                V6ReadingTopicLinks()
                primaryBentoGrid''',1)
    home=home.replace('''                todaySection
                // 05 最近使用''','''                // 05 最近使用''',1)
    home=home.replace('''                allToolsLink
                brandHeader''','''                allToolsLink''',1)
    home=home.replace('''            .padding(.horizontal, 16)
            .padding(.top, 6)''','''            .padding(.horizontal, KanyuV6.Metric.pageInset)
            .padding(.top, 6)''',1)
    a=home.index('    private var primaryBentoGrid: some View {')
    b=home.index('    private func bentoCard(',a)
    grid=home[a:b].replace('spacing: 10','spacing: KanyuV6.Metric.cardGap',1).replace('HStack(spacing: 12) {','coreRowLayout {')
    helper='''    private var coreRowLayout: AnyLayout {
        homeTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: KanyuV6.Metric.cardGap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: KanyuV6.Metric.cardGap))
    }

'''
    return refine_home_v6(head+home[:a]+helper+grid+home[b:])

patches = json.loads((ROOT/'design/ui-patches-v6.json').read_text())
def apply_ui_patches(path, value):
    for patch in [p for p in patches if p['path'] == path]:
        assert value.count(patch['before']) == patch['count'], f'Patch anchor drift: {path}'
        value = value.replace(patch['before'], patch['after'])
    return value

# P2 permits only these exact UI layout transformations; all other app code stays protected.
assert mask_app(home_layout_v6(original('Sources/KanyuApp.swift'))) == mask_app((ROOT/'Sources/KanyuApp.swift').read_text()), 'Engine or other app code changed'
# Keep everything outside the first card wrapper unchanged, including the complete settings code.
def mask_card(text):
    a = text.index('extension View {\n', text.index('struct KyWorkspaceHeading'))
    b = text.index('    /// 浅染内嵌卡', a)
    return text[:a] + '<CARD-WRAPPER>\n' + text[b:]
assert mask_card(apply_ui_patches('Sources/DesignSystemV2.swift', original('Sources/DesignSystemV2.swift'))) == mask_card((ROOT/'Sources/DesignSystemV2.swift').read_text()), 'Non-card code changed'
# Additional mixed files permit only reviewed literal UI/export/backup patches, never whole-file exemptions.
patched_paths = {p['path'] for p in patches}
for path in patched_paths:
    expected = original(path)
    for patch in [p for p in patches if p['path'] == path]:
        assert expected.count(patch['before']) == patch['count'], f'Patch anchor drift: {path}'
        expected = expected.replace(patch['before'], patch['after'])
    actual = (ROOT/path).read_text()
    assert (mask_card(expected) == mask_card(actual) if path == 'Sources/DesignSystemV2.swift' else expected == actual), f'Unreviewed change outside exact UI patches: {path}'
# Compare every baseline file except explicitly allowed presentation/doc additions.
allowed = {'Sources/KanyuApp.swift', 'Sources/DesignSystemV2.swift'}
files = subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
for path in files:
    if path in allowed or path in patched_paths or path.startswith(('docs/', 'design/')): continue
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
assert tokens['poster']['innerFrameInsetPt'] + tokens['poster']['innerFrameStrokePt'] == tokens['poster']['innerFrameInnerEdgePt']
assert (tokens['poster']['textInsetPt']-tokens['poster']['innerFrameInnerEdgePt'])*tokens['poster']['scale'] >= 28

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
for element in ['wood','fire','earth','metal','water']:
    for variant, surface in [('Light','ivory'),('Dark','jadeCard')]:
        pairs.append((element+' '+variant, tokens['colors'][element+variant], tokens['colors'][surface]))
lines = ['# V6 静态核查', '', '| 色对 | 对比度 |', '| --- | ---: |']
for name,a,b in pairs:
    value = ratio(a,b)
    assert value>=4.5, (name,value)
    lines.append(f'| {name} | {value:.2f}:1 |')
lines += ['', '已核对：排盘引擎保持冻结；其他变更仅限精确合同登记的 UI、导出与备份修复；Tests/UITests/Resources 文件与基线逐字节相同；Swift/JSON/Web 主要语义色一致；海报几何预算通过。',
          '此结果不是 Xcode 编译、截图、VoiceOver 或真机性能验收。']
(ROOT/'docs/design-v6/STATIC-VERIFICATION.md').write_text('\n'.join(lines)+'\n')
print('PASS: protected files, reviewed exact diff, Swift/CSS palette parity, text contrast pairs and export geometry')
