import SwiftUI
import PhotosUI

struct FloorPlanOverlayView: View {
@State private var selectedPeriod: Int = 9 // 默认下元九运 (2024–2043)
@State private var selectedOrientationIndex: Int = 0 // 默认子山午向
@State private var overlayMode: Int = 0 // 0: 玄空飞星, 1: 八宅大游年
@State private var overlayOpacity: Double = 0.55
@State private var centerOffset: CGSize = .zero // 中宫立极拖拽偏移量
@State private var lastOffset: CGSize = .zero // 上一轮拖拽结束后的累计偏移（防新一轮拖拽跳回）
@State private var selectedPalace: String = "离" // 默认聚焦正南向星
@State private var selectedPhotoItem: PhotosPickerItem? = nil
@State private var userImage: UIImage? = nil

private struct HouseOrientation {
let name: String
let sitMtn: String
let sitPal: String
let faceMtn: String
let facePal: String
let desc: String
}

private let orientations: [HouseOrientation] = [
HouseOrientation(name: "子山午向（坐北朝南）", sitMtn: "子", sitPal: "坎", faceMtn: "午", facePal: "离", desc: "正针南向 · 离宫双九会向大旺"),
HouseOrientation(name: "壬山丙向（正北朝偏南）", sitMtn: "壬", sitPal: "坎", faceMtn: "丙", facePal: "离", desc: "兼向进气 · 离宫向星得令"),
HouseOrientation(name: "癸山丁向（偏北朝偏南）", sitMtn: "癸", sitPal: "坎", faceMtn: "丁", facePal: "离", desc: "正南纳气 · 丁星生旺"),
HouseOrientation(name: "午山子向（坐南朝北）", sitMtn: "午", sitPal: "离", faceMtn: "子", facePal: "坎", desc: "向首九紫火 · 九运零神在坎"),
HouseOrientation(name: "卯山酉向（坐东朝西）", sitMtn: "卯", sitPal: "震", faceMtn: "酉", facePal: "兑", desc: "正西兑宫 · 兑金管局"),
HouseOrientation(name: "酉山卯向（坐西朝东）", sitMtn: "酉", sitPal: "兑", faceMtn: "卯", facePal: "震", desc: "正东震宫 · 震木发荣"),
HouseOrientation(name: "艮山坤向（坐东北朝西南）", sitMtn: "艮", sitPal: "艮", faceMtn: "坤", facePal: "坤", desc: "西南坤位 · 土星生养"),
HouseOrientation(name: "乾山巽向（坐西北朝东南）", sitMtn: "乾", sitPal: "乾", faceMtn: "巽", facePal: "巽", desc: "东南巽位 · 东南临风")
]

private var currentOri: HouseOrientation {
orientations[selectedOrientationIndex]
}

private var xuanKongChart: FengshuiEngine.Chart {
FengshuiEngine.chart(
period: selectedPeriod,
sitMountain: currentOri.sitMtn,
sitPalace: currentOri.sitPal,
faceMountain: currentOri.faceMtn,
facePalace: currentOri.facePal
)
}

/// 八宅大游年：直接复用 FengshuiEngine.youNian（《八宅明镜》变爻口诀，与 App 内勘察盘同源），
/// 按坐宫现算八方游年星；中宫不在游年表内，单列为立极太极。
private var baZhaiTable: [String: (name: String, isGood: Bool, role: String)] {
let roles: [String: String] = [
"生气": "大财位 · 宜大门客厅",
"天医": "财帛健康 · 宜卧室书房",
"延年": "长寿和谐 · 宜主卧客厅",
"伏位": "大平稳 · 宜静养卧室",
"绝命": "极凶煞位 · 宜卫浴仓库",
"祸害": "口舌是非 · 忌做主卧",
"六煞": "桃花损耗 · 忌做主卧",
"五鬼": "火灾躁动 · 忌设炉灶"
]
var out: [String: (name: String, isGood: Bool, role: String)] = [:]
for (palace, star) in FengshuiEngine.youNian(house: currentOri.sitPal) {
out[palace] = (star, FengshuiEngine.goodStars.contains(star), roles[star] ?? "")
}
out["中"] = ("中宫", true, "立极太极 · 宜宽敞明亮")
return out
}

private let gridPalaces = [
["巽", "离", "坤"],
["震", "中", "兑"],
["艮", "坎", "乾"]
]

var body: some View {
ScrollView {
VStack(alignment:.leading, spacing: 14) {
// 1. 顶部控制条（坐向与元运选择）
VStack(alignment:.leading, spacing: 10) {
HStack {
VStack(alignment:.leading, spacing: 2) {
Text("户型图立极压盘器")
.font(.system(.headline, design:.serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
Text("拖动准星立极中宫 · 压盘透视分室吉凶").font(.caption2).foregroundStyle(Ky.gold)
}
Spacer()
KySeal(text: "三元九运")
}

HStack(spacing: 8) {
Menu {
ForEach(orientations.indices, id: \.self) { idx in
Button(orientations[idx].name) { selectedOrientationIndex = idx}
}
} label: {
HStack(spacing: 4) {
Image(systemName: "safari")
Text(currentOri.name).lineLimit(1)
Image(systemName: "chevron.down").font(.caption2)
}
.font(.system(size: 12, weight:.bold)).foregroundStyle(Ky.qingdai)
.padding(.horizontal, 10).padding(.vertical, 7).background(Ky.elevated).clipShape(RoundedRectangle(cornerRadius: 10))
}

Spacer()

Picker("元运", selection: $selectedPeriod) {
Text("九运 (2024–43)").tag(9)
Text("八运 (2004–23)").tag(8)
Text("七运 (1984–03)").tag(7)
}
.pickerStyle(.menu).font(.system(size: 11))
}

HStack {
Picker("压盘模式", selection: $overlayMode) {
Text("玄空飞星盘").tag(0)
Text("八宅大游年").tag(1)
}
.pickerStyle(.segmented)

Spacer()

HStack(spacing: 4) {
Text("透视").font(.caption2).foregroundStyle(Ky.sub)
Slider(value: $overlayOpacity, in: 0.2...0.9).frame(width: 80)
}
}
}
.kyCard()

// 2. 核心压盘交互视口（户型底图 + 拖拽中宫 + 九宫覆盖）
VStack(spacing: 8) {
HStack {
Text("📐 户型图透视压盘区（南上北下）").font(.system(size: 11.5, weight:.bold, design:.serif)).foregroundStyle(Ky.sub)
Spacer()
Button {
withAnimation(.spring()) { centerOffset = .zero; lastOffset = .zero}
} label: {
HStack(spacing: 3) {
Image(systemName: "arrow.counterclockwise")
Text("中宫居中")
}
.font(.system(size: 10.5)).foregroundStyle(Ky.qingdai)
}
}

ZStack {
Group {
if let img = userImage {
Image(uiImage: img).resizable().scaledToFit()
} else {
demoFloorPlanBlueprint
}
}
.frame(maxWidth:.infinity, maxHeight: 310)
.background(Color(red: 0.95, green: 0.94, blue: 0.92))
.clipShape(RoundedRectangle(cornerRadius: 16))

// 半透明九宫网格（支持手势拖拽中宫定位）
VStack(spacing: 3) {
ForEach(0..<3, id: \.self) { row in
HStack(spacing: 3) {
ForEach(0..<3, id: \.self) { col in
let palace = gridPalaces[row][col]
palaceOverlayCell(palace: palace)
}
}
}
}
.padding(6).frame(width: 290, height: 290).offset(centerOffset)
.gesture(
DragGesture()
.onChanged { val in
centerOffset = CGSize(width: lastOffset.width + val.translation.width, height: lastOffset.height + val.translation.height)
}
.onEnded { val in
lastOffset = CGSize(width: lastOffset.width + val.translation.width, height: lastOffset.height + val.translation.height)
}
)

// 中宫立极红色十字准心
ZStack {
Circle().stroke(Ky.cinnabar, lineWidth: 1.5).frame(width: 26, height: 26)
Circle().fill(Ky.cinnabar).frame(width: 5, height: 5)
Path { p in
p.move(to: CGPoint(x: 13, y: 0)); p.addLine(to: CGPoint(x: 13, y: 26))
p.move(to: CGPoint(x: 0, y: 13)); p.addLine(to: CGPoint(x: 26, y: 13))
}.stroke(Ky.cinnabar, lineWidth: 0.8)
}
.offset(centerOffset).allowsHitTesting(false)
}
.frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 18))
.overlay(RoundedRectangle(cornerRadius: 18).stroke(Ky.line, lineWidth: 1))

HStack {
PhotosPicker(selection: $selectedPhotoItem, matching:.images) {
HStack(spacing: 4) {
Image(systemName: "photo.badge.plus")
Text(userImage == nil ? "导入真实户型图" : "更换户型图")
}
.font(.system(size: 11.5, weight:.semibold)).foregroundStyle(Ky.qingdai)
}
.onChange(of: selectedPhotoItem) { _, newItem in
Task {
if let data = try? await newItem?.loadTransferable(type: Data.self),
let ui = UIImage(data: data) {
userImage = ui
}
}
}

Spacer()

if userImage != nil {
Button("恢复示范图") {
userImage = nil; selectedPhotoItem = nil
}
.font(.system(size: 11)).foregroundStyle(Ky.sub)
}
}
.padding(.horizontal, 4)
}
.kyCard()

// 3. 聚焦宫位分室详析卡片
VStack(alignment:.leading, spacing: 10) {
HStack {
Text("分室断吉凶")
.font(.system(.subheadline, design:.serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
Spacer()
palaceBadge(palace: selectedPalace)
}

if overlayMode == 0 {
let m = xuanKongChart.mtn[selectedPalace] ?? 5
let f = xuanKongChart.face[selectedPalace] ?? 5
let b = xuanKongChart.base[selectedPalace] ?? 9
let comboKey = "\(min(m, f))-\(max(m, f))"
let note = FengshuiEngine.comboNotes[comboKey] ?? ""

VStack(alignment:.leading, spacing: 6) {
HStack(spacing: 12) {
Text("山星 \(m)（人丁健康）").font(.system(size: 12, weight:.bold)).foregroundStyle(Ky.qingdai)
Text("向星 \(f)（财帛进气）").font(.system(size: 12, weight:.bold)).foregroundStyle(Ky.cinnabar)
Text("运星 \(b)").font(.system(size: 12)).foregroundStyle(Ky.sub)
}
if !note.isEmpty {
Text("• 飞星凶意提示：\(note)").font(.system(size: 11.5)).foregroundStyle(Ky.cinnabar)
}
Text(palaceRoomAdvice(palace: selectedPalace, faceStar: f, mtnStar: m))
.font(.system(size: 12)).foregroundStyle(Ky.ink).lineSpacing(3)
}
} else {
let bz = baZhaiTable[selectedPalace] ?? ("平", true, "")
VStack(alignment:.leading, spacing: 6) {
HStack {
Text("八宅九星：\(bz.name)").font(.system(size: 13, weight:.bold)).foregroundStyle(bz.isGood ? Ky.jade : Ky.cinnabar)
Text(bz.role).font(.system(size: 11.5)).foregroundStyle(Ky.sub)
}
Text(baZhaiRoomAdvice(palace: selectedPalace, isGood: bz.isGood, name: bz.name))
.font(.system(size: 12)).foregroundStyle(Ky.ink).lineSpacing(3)
}
}
}
.kyCard()
}
.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
}
.background(Ky.bg)
.navigationTitle("户型图立极压盘")
.navigationBarTitleDisplayMode(.inline)
}

private func palaceOverlayCell(palace: String) -> some View {
let isSelected = selectedPalace == palace
let m = xuanKongChart.mtn[palace] ?? 5
let f = xuanKongChart.face[palace] ?? 5
let b = xuanKongChart.base[palace] ?? 9
let bz = baZhaiTable[palace] ?? ("平", true, "")

return Button {
withAnimation(.easeInOut(duration: 0.15)) { selectedPalace = palace}
} label: {
ZStack {
RoundedRectangle(cornerRadius: 8, style:.continuous)
.fill(cellBgColor(palace: palace, faceStar: f, bzGood: bz.isGood).opacity(overlayOpacity))

RoundedRectangle(cornerRadius: 8, style:.continuous)
.stroke(isSelected ? Ky.gold : Color.white.opacity(0.4), lineWidth: isSelected ? 2.0 : 0.7)

VStack(spacing: 2) {
if overlayMode == 0 {
HStack {
Text("\(m)").font(.system(size: 10, weight:.bold)).foregroundStyle(Ky.qingdai)
Spacer()
Text("\(f)").font(.system(size: 11, weight:.heavy)).foregroundStyle(f == selectedPeriod ? Ky.cinnabar : Ky.ink)
}
.padding(.horizontal, 4)
Text(palace).font(.system(size: 14, weight:.bold, design:.serif)).foregroundStyle(Ky.ink)
Text("运 \(b)").font(.system(size: 8)).foregroundStyle(Ky.sub)
} else {
Text(palace).font(.system(size: 12, weight:.bold, design:.serif)).foregroundStyle(Ky.ink)
Text(bz.name).font(.system(size: 12, weight:.heavy)).foregroundStyle(bz.isGood ? Ky.jade : Ky.cinnabar)
}
}
.padding(3)
}
}
.buttonStyle(.plain)
}

private func cellBgColor(palace: String, faceStar: Int, bzGood: Bool) -> Color {
if overlayMode == 0 {
if faceStar == selectedPeriod { return Color(red: 0.85, green: 0.25, blue: 0.20)}
if faceStar == 5 { return Color(red: 0.45, green: 0.25, blue: 0.15)}
if faceStar == 2 { return Color(red: 0.60, green: 0.45, blue: 0.20)}
if [1, 6, 8].contains(faceStar) { return Color(red: 0.25, green: 0.60, blue: 0.45)}
return Color(red: 0.90, green: 0.88, blue: 0.84)
} else {
return bzGood ? Color(red: 0.25, green: 0.65, blue: 0.45) : Color(red: 0.75, green: 0.35, blue: 0.30)
}
}

private func palaceBadge(palace: String) -> some View {
if overlayMode == 0 {
let f = xuanKongChart.face[palace] ?? 5
if f == selectedPeriod { return KyBadge(text: "九运大财位", color: Ky.cinnabar)}
if f == 5 { return KyBadge(text: "五黄大煞", color: Ky.cinnabar)}
if f == 2 { return KyBadge(text: "二黑病符", color: Ky.gold)}
return KyBadge(text: "平稳进气", color: Ky.qingdai)
} else {
let bz = baZhaiTable[palace] ?? ("平", true, "")
return KyBadge(text: bz.name, color: bz.isGood ? Ky.jade : Ky.cinnabar)
}
}

private func palaceRoomAdvice(palace: String, faceStar: Int, mtnStar: Int) -> String {
if faceStar == selectedPeriod {
return "此宫为下元九运「当令大财位」，见大门、明堂或客厅最佳。动线宜开阔明亮，可摆放常青阔叶植物生旺财气；不宜作暗卫或堆放杂物。"
} else if faceStar == 5 || mtnStar == 5 {
return "此宫逢五黄大煞，最忌红色火源与动土装修。宜作次卧、客房或储物间；若为主卧，床头忌靠动土墙体，宜用六帝钱或金属铜钟泄化土煞。"
} else if faceStar == 2 || mtnStar == 2 {
return "此宫逢二黑病符，留意肠胃呼吸小疾。若为厨房炉灶，勤通风保持干燥洁净；可悬挂纯铜葫芦收纳晦气。"
} else {
return "气场平和通畅，适合做常态起居室、儿童房或书房。保持光照充足、家具摆放方正即可。"
}
}

private func baZhaiRoomAdvice(palace: String, isGood: Bool, name: String) -> String {
if isGood {
return "逢\(name)临照，气脉生旺。宜设置大门、主卧床位或主办公桌，能够助长屋主身心和顺与事业声望。"
} else {
return "逢\(name)管局。传统风水正法讲究「坐凶向吉」，适合将卫浴、杂物间或厨房炉灶设于此（以灶火压煞），不宜作常住主卧床头。"
}
}

private var demoFloorPlanBlueprint: some View {
ZStack {
Color(red: 0.12, green: 0.16, blue: 0.22)
VStack(spacing: 0) {
HStack(spacing: 0) {
blueprintRoom("主卧 (南)", "18㎡", Color.indigo.opacity(0.2))
blueprintRoom("客厅 · 景观阳台", "32㎡", Color.cyan.opacity(0.25))
blueprintRoom("次卧 (南)", "14㎡", Color.indigo.opacity(0.2))
}.frame(height: 120)
HStack(spacing: 0) {
blueprintRoom("主卫", "6㎡", Color.gray.opacity(0.2))
blueprintRoom("餐厅 · 玄关入户", "16㎡", Color.orange.opacity(0.2))
blueprintRoom("客卫", "5㎡", Color.gray.opacity(0.2))
}.frame(height: 80)
HStack(spacing: 0) {
blueprintRoom("书房 (北)", "11㎡", Color.teal.opacity(0.2))
blueprintRoom("公共走道", "", Color.clear)
blueprintRoom("厨房 (北)", "8㎡", Color.orange.opacity(0.2))
}.frame(height: 90)
}.padding(12)

Text("示例户型图：标准三室两厅（正南朝向）")
.font(.system(size: 9.5, weight:.medium, design:.monospaced))
.foregroundStyle(Color.white.opacity(0.45))
.frame(maxHeight:.infinity, alignment:.bottomLeading).padding(16)
}
}

private func blueprintRoom(_ title: String, _ area: String, _ bg: Color) -> some View {
ZStack {
Rectangle().fill(bg)
Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 1)
VStack(spacing: 2) {
Text(title).font(.system(size: 11, weight:.bold)).foregroundStyle(Color.white.opacity(0.9))
if !area.isEmpty {
Text(area).font(.system(size: 8.5)).foregroundStyle(Color.white.opacity(0.6))
}
}
}
}
}
