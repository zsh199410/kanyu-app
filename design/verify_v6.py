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
    after = '                signBanner\n                personSwitcherCard\n                    .accessibilityElement(children: .contain)\n                    .accessibilityIdentifier("workspace.workbench")\n                    .accessibilityValue(peopleStore.currentPerson?.name ?? "未建档")'
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
    text = text.replace(before, '            RootTabView()\n                .modifier(V6ExportQAHost())\n                .modifier(ContextAcceptanceHost())\n')
    before = '        }.buttonStyle(.plain)\n    }\n\n}\n\n// MARK: - Tab 4：「堪舆」独立工作台'
    after = '        }.buttonStyle(.plain)\n            .accessibilityIdentifier("home.alltools")\n    }\n\n}\n\n// MARK: - Tab 4：「堪舆」独立工作台'
    assert text.count(before) == 1, "Context UI anchor drift"
    text = text.replace(before, after)
    before = '                .buttonStyle(.plain)\n            }\n            .navigationTitle(Text("切换命主".scriptConverted))'
    after = '                .buttonStyle(.plain)\n                .accessibilityLabel("选择命主：\\(p.name)")\n            }\n            .navigationTitle(Text("切换命主".scriptConverted))'
    assert text.count(before) == 1, "Context UI anchor drift"
    text = text.replace(before, after)
    # Plain List button rows must be tappable across Spacer, including their center.
    before = r'''                        if peopleStore.currentPersonId == p.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ky.qingdai)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择命主：\(p.name)")'''
    after = r'''                        if peopleStore.currentPersonId == p.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ky.qingdai)
                        }
                    }
                    // A plain button's Spacer is otherwise not part of its hit target.
                    // Make the entire profile row tappable, including its center.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择命主：\(p.name)")'''
    assert text.count(before) == 1, "Profile picker hit target anchor drift"
    text = text.replace(before, after)
    before = '                        .simultaneousGesture(TapGesture().onEnded { _ in AllToolsData.recordRecent(tool: "astro") })'
    after = '                        .simultaneousGesture(TapGesture().onEnded { _ in AllToolsData.recordRecent(tool: "astro") })\n                        .accessibilityIdentifier("home.astro")'
    assert text.count(before) == 1, "Context shortcut anchor drift"
    text = text.replace(before, after)
    before = '                NavigationLink { ContextualToolDestination(item: item) } label: {\n                    homeChipLabel(item)\n                }\n                .buttonStyle(.plain)'
    after = '                NavigationLink { ContextualToolDestination(item: item) } label: {\n                    homeChipLabel(item)\n                }\n                .buttonStyle(.plain)\n                .accessibilityIdentifier("home.recent.\\(item.id)")'
    assert text.count(before) == 1, "Context shortcut anchor drift"
    text = text.replace(before, after)
    # Specific iOS accessibility subtree refresh, permitted only at this reviewed anchor.
    before = '                onOpenDetail: { showingPersonDetail = true }\n            )'
    after = before + '\n            // Rebuild the visible profile and its accessibility subtree when selection changes.\n            .id(p.id)'
    assert text.count(before) == 1, 'Selected-person accessibility anchor drift'
    text = text.replace(before, after)
    before = '        }\n        .background(Ky.bg)\n        .navigationBarTitleDisplayMode(.inline)\n        .toolbarBackground(Ky.bg, for: .navigationBar)'
    after = before.replace('        .background(Ky.bg)', '        .accessibilityIdentifier("home.scroll")\n        .background(Ky.bg)')
    assert text.count(before) == 1, 'Home scroll accessibility anchor drift'
    text = text.replace(before, after)
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

# V5 strengthens the added-file bridge contract without exempting legacy files.
if (ROOT/'Sources/V5ProShell.swift').exists():
    contract = json.loads((ROOT/'design/v5/ui-bridges.json').read_text())
    for path in {p['path'] for p in contract['patches']}:
        expected = subprocess.check_output(['git', 'show', contract['base'] + ':' + path], cwd=ROOT, text=True)
        for patch in [p for p in contract['patches'] if p['path'] == path]:
            assert expected.count(patch['before']) == patch['count'], 'V5 bridge anchor drift: ' + path
            expected = expected.replace(patch['before'], patch['after'])
        assert expected == (ROOT/path).read_text(), 'Unreviewed V5 bridge: ' + path

patches = json.loads((ROOT/'design/ui-patches-v6.json').read_text())
def apply_ui_patches(path, value):
    for patch in [p for p in patches if p['path'] == path]:
        assert value.count(patch['before']) == patch['count'], f'Patch anchor drift: {path}'
        value = value.replace(patch['before'], patch['after'])
    return value

# P2 permits only these exact UI layout transformations; all other app code stays protected.
assert mask_app(apply_ui_patches('Sources/KanyuApp.swift', home_layout_v6(original('Sources/KanyuApp.swift')))) == mask_app((ROOT/'Sources/KanyuApp.swift').read_text()), 'Engine or other app code changed'
# Keep everything outside the first card wrapper unchanged, including the complete settings code.
def mask_card(text):
    a = text.index('extension View {\n', text.index('struct KyWorkspaceHeading'))
    b = text.index('    /// 浅染内嵌卡', a)
    return text[:a] + '<CARD-WRAPPER>\n' + text[b:]
assert mask_card(apply_ui_patches('Sources/DesignSystemV2.swift', original('Sources/DesignSystemV2.swift'))) == mask_card((ROOT/'Sources/DesignSystemV2.swift').read_text()), 'Non-card code changed'
# Additional mixed files permit only reviewed literal UI/export/backup patches, never whole-file exemptions.
patched_paths = {p['path'] for p in patches}
for path in patched_paths:
    expected = home_layout_v6(original(path)) if path == 'Sources/KanyuApp.swift' else original(path)
    for patch in [p for p in patches if p['path'] == path]:
        assert expected.count(patch['before']) == patch['count'], f'Patch anchor drift: {path}'
        expected = expected.replace(patch['before'], patch['after'])
    actual = (ROOT/path).read_text()
    if path == 'Sources/KanyuApp.swift':
        assert mask_app(expected) == mask_app(actual), f'Unreviewed change outside exact UI patches: {path}'
    else:
        assert (mask_card(expected) == mask_card(actual) if path == 'Sources/DesignSystemV2.swift' else expected == actual), f'Unreviewed change outside exact UI patches: {path}'
# Compare every baseline file except explicitly allowed presentation/doc additions.
allowed = {'Sources/KanyuApp.swift', 'Sources/DesignSystemV2.swift'}
files = subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
for path in files:
    if path in allowed or path in patched_paths or path.startswith(('docs/', 'design/')): continue
    data = subprocess.check_output(['git','show',f'{BASE}:{path}'],cwd=ROOT)
    assert (ROOT/path).is_file() and (ROOT/path).read_bytes() == data, f'Protected baseline file changed: {path}'
# Permit only these independently reviewed, newly added regression tests.
# Their exact Git blob hashes are pinned; all baseline files remain byte-identical.
new_test_blobs = {
    'Tests/V5PosterShareItemTests.swift': '1c4db140dbffe77f00a24c5adfae620479a16519',
    'UITests/V5PosterSharingUITests.swift': 'ad24618c66359c58a7b7dfcabc5af91da3cc0446',
    'Tests/V5ArtworkStoreTests.swift': 'f5754442804c258b10685e628c999d37375e1729',
    'Tests/V5TypographyTests.swift': '23e893251767b083e343f5f07b3aca165b4fcaae',
    'Resources/Fonts/LICENSE-NotoSerifCJK.txt': 'd952d62c065f3f35fb83a173496e90b21525aef3',
    'Resources/Fonts/NotoSerifCJKsc-SemiBold.otf': '41668d00fa67926d143544ddba2937b7d7f6fcf6',
    'Resources/Fonts/NotoSerifCJKsc-Regular.otf': 'cba8a4783cc38574ac7cda52cae7d9b4241c07a5',
    'UITests/V5HomeQuickCreateUITests.swift': 'e0cbb2a53541329f4c78a470d5f19a4658eddb57',
    'Tests/V5WorkThumbnailTests.swift': 'd24215c16216f3d25945968387c3f10a9e046632',
    'UITests/V5ArchiveCreationUITests.swift': '6aca4e99c4f51d5952787fb6fec9512c67a90500',
    'UITests/V5PublicationSharingUITests.swift': '93a9231c15fcfde6e1f8d63d2ca1278273cf728f',
    'Tests/V5BottomNavigationTests.swift': '2f0a83c7adb6afcb65efa8ba7e5fad495dcda1c0',
    'Tests/V5FormalPDFExportTests.swift': '8d3a2f094cda7f87d5a25322fd956307cdb03cda',
    'Tests/V5PublicationStyleTests.swift': '8b1b394fab0b986790e2033286f08b93e455b739',
    'UITests/V5VisualAcceptanceTests.swift': '73db2e447be313d441f115f5430c83ca6a30a815',
    'Tests/PosterCanvasMatteTests.swift': '54cfbde4618d5f7e4e5ec5148f5530174c21cbfd',
    'Tests/V5NavigationPathIsolationTests.swift': 'a1c08bbcdcee1803835cfce7485960c259969bf9',
    'Tests/V5ReportOwnershipTests.swift': 'd410caff7130929567b3aa8c1a5156c879e7f16f',
    'Tests/V5ThemePreferenceTests.swift': '94dacaf509735536cd5ddf72b540ad1e4f97b1a3',
    'Tests/V5IPAInspectionTests.swift': '4f484408fcf7d1ff15533177d8f34d84122efeca',
    'UITests/V5PersonLifecycleUITests.swift': '2bb2c597b4d7678f6279f77ba8a012a155e6ea0c',
    'UITests/V5NavigationUITests.swift': '65b6d72b989bf883074118121ab9c6bd4b6434ba',
    'Tests/V5ArchitectureTests.swift': '3a0ec127afd87615cd0acd857dc3912ebd31cc22',
    'Tests/PosterFamilyBitmapRegressionTests.swift': 'd4af33788334ccb77bf5cbe14043b929ba1fe93b',
    'Tests/BackupRestoreTests.swift': '9f65869e6e3aa2c937f564f8b3323590f07c8f96',
    'Tests/PersonIsolationTests.swift': 'ef72047459e4278a5bd466ad2836d6677c14a97e',
    'Tests/PeopleStoreTests.swift': '117f02ef7595c3163fa4b9bf9cb337c1bca944d8',
    'Tests/PersonCascadeTests.swift': 'c1d35f2c4ef1add97f12a6228060b5eed1cda261',
    'Tests/PersonUUIDIsolationTests.swift': '04c05754a54393c0257631bda20d70415e5f04a8',
    'Tests/PosterRealDataBindingTests.swift': 'c2882f8cbdd7de07538d7b8f03d341a7cf8d3e5c',
    'Tests/PosterDynamicSnapshotTests.swift': '4bf2f9f9a43268ffa3a93966b7b8bfc764d21714',
    'Tests/PosterBatch2OwnershipTests.swift': '04a129c6bbac6b407e5779957ef2c6e20c1a3d2b',
    'Tests/PosterFormalExportTests.swift': '442bce8a0e2f8f98e836084aa80152340085fa5e',
    'Tests/PosterFamilyExportPathTests.swift': 'ee53f3951c496a881ae246d37881f5c92b8fe482',
    'Tests/PosterOwnershipGatesTests.swift': 'c3f8a0379d0fa3281941d76c6fc74cc2725d9c5b',
    'UITests/PosterExportAcceptanceUITests.swift': 'b2581be6ea39110b1e1233ea181e10022ed6ad9c',
    'Resources/PosterDesignPreviews/PosterConceptBazi.jpg': '530227d387a88685055dd801d9f1c92d16b4795c',
    'Resources/PosterDesignPreviews/PosterConceptPalm.jpg': '90add3b72576d4fe3f893796dd23ed403e9c8e0d',
    'Resources/PosterDesignPreviews/PosterConceptPremium.jpg': '0cbf272c127ff4e9c26e65757efdf83ad1c4a092',
    'Resources/PosterDesignPreviews/PosterConceptZiwei.jpg': 'ef4432dc0f9948ebf7922a14356e3d7207275357',
}
# GPT supplies immutable art files on its separate branch. Permit only the 60 exact
# role paths with a matching manifest SHA256; this never exempts existing resources.
import hashlib
art_manifest = json.loads((ROOT/'design/v5/asset-manifest.json').read_text())
art_roles = {'landscape', 'emblem', 'person-object', 'book-cover-art', 'texture', 'flourish',
             'glyph-bazi', 'glyph-ziwei', 'glyph-palm', 'glyph-face', 'glyph-survey',
             'nav-home', 'nav-measure', 'nav-reports', 'nav-profiles'}
expected_art = {f'Resources/V5Artwork/v5-{theme}-{role}.png'
                for theme in ['song', 'night', 'celadon', 'collection'] for role in art_roles}
assert len(art_manifest['assets']) == 60 and {a['path'] for a in art_manifest['assets']} == expected_art, 'Artwork role/path contract drift'
verified_art = set()
for asset in art_manifest['assets']:
    assert asset['path'] == f"Resources/V5Artwork/v5-{asset['theme']}-{asset['role']}.png", 'Artwork theme/role mismatch'
    path = ROOT/asset['path']
    if path.exists():
        assert path.is_file() and not path.is_symlink(), 'Artwork must be a regular bundled file'
        assert asset.get('sha256') == hashlib.sha256(path.read_bytes()).hexdigest(), 'Artwork SHA must be pinned by GPT: ' + asset['path']
        verified_art.add(asset['path'])
for folder in ['Tests','UITests','Resources']:
    tracked = {x for x in files if x.startswith(folder+'/')}
    actual = {str(x.relative_to(ROOT)) for x in (ROOT/folder).rglob('*') if x.is_file()}
    extras = actual - tracked
    permitted = {path for path in new_test_blobs if path.startswith(folder+'/')} | (verified_art if folder == 'Resources' else set())
    assert extras <= permitted and tracked <= actual, f'Protected folder file list changed: {folder}'
    for path in extras - verified_art:
        actual_blob = subprocess.check_output(['git', 'hash-object', path], cwd=ROOT, text=True).strip()
        assert actual_blob == new_test_blobs[path], f'Unreviewed new test content: {path}'
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
