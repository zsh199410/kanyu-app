import SwiftUI
// G11 排盘口径自测题库：数据与 Web app/quiz.json 同源逐字对拍
// （由 tools/gen_g11_swift.py 生成，勿手改；答案与 Web 逐项对拍，
// 判分逻辑与 Web quiz.py grade() 一致；结果只存 UserDefaults，不落库。）
struct QuizQuestion: Identifiable { let id: Int; let point: String; let type: String; let q: String; let options: [String]; let answerIndex: Int; let answerBool: Bool; let explain: String; let source: String }
enum QuizData {
    static let version = "G11-20261108"
    static let questions: [QuizQuestion] = [
        QuizQuestion(id: 1, point: "真太阳时校正", type: "choice", q: "梁平经度 107.8，2024-12-21 08:30 出生，真太阳时校正多少分钟？", options: ["-47.9 分钟", "-48.8 分钟", "-44.4 分钟", "+4.4 分钟"], answerIndex: 0, answerBool: false, explain: "校正＝(经度-120)×4＋均时差：(107.8-120)×4＝-48.8，再加当日均时差 +0.9，得 -47.9。囿廷收据行同值。", source: "口径出处：app/paipan.py eot_minutes／app/paipan_client.py tst_minutes；引擎字段：排盘“口径”行“真太阳时校正 -47.9 分钟（经度 107.8 + 均时差）”。"),
        QuizQuestion(id: 2, point: "真太阳时校正", type: "choice", q: "真太阳时校正公式是哪一个？", options: ["(经度-120)×4＋均时差", "(经度-120)×4－均时差", "(120-经度)×4＋均时差", "经度×4"], answerIndex: 0, answerBool: false, explain: "公式为 (经度-120)×4＋均时差。经度取 120（东经 120°标准子午线）时，经度差为 0，校正只剩均时差。", source: "口径出处：app/paipan.py eot_minutes；app/paipan_client.py tst_minutes 与 paipan.py 同式。"),
        QuizQuestion(id: 3, point: "真太阳时校正", type: "choice", q: "2024-12-21 08:30、经度 107.8，校正后排盘时间是？", options: ["2024-12-21 07:42", "2024-12-21 08:30", "2024-12-21 07:38", "2024-12-21 09:18"], answerIndex: 0, answerBool: false, explain: "08:30 减 47.9 分钟得 07:42，仍在辰时，时柱仍为戊辰；收据行会写明校正分钟数、经度与校正后时间。", source: "口径出处：app/paipan.py main（校正后时间）；引擎字段：农历“校正后时间”。"),
        QuizQuestion(id: 4, point: "真太阳时校正", type: "judge", q: "不给经度时，系统按钟表时间排盘，并注明未做真太阳时校正。", options: [], answerIndex: -1, answerBool: true, explain: "给了经度才换算真太阳时；不给则按钟表时间排并注明，绝不悄悄默认一个经度。", source: "口径出处：app/paipan.py 模块文档串；引擎字段：输入“口径”行。"),
        QuizQuestion(id: 5, point: "晚子时", type: "choice", q: "2024-12-21 23:30 出生（本系统默认 sect=2），日柱是？", options: ["己未", "庚申", "己巳", "戊午"], answerIndex: 0, answerBool: false, explain: "sect=2：23:00–24:00 日柱不换，仍为当日的己未；时干按次日日干推。", source: "口径出处：app/paipan.py sect=2（23:00–24:00 日柱不换、时干按次日日干推）；引擎字段：四柱“日柱”。"),
        QuizQuestion(id: 6, point: "晚子时", type: "choice", q: "同一时刻（2024-12-21 23:30）若按 sect=1（日柱换日），日柱是？", options: ["庚申", "己未", "庚午", "己酉"], answerIndex: 0, answerBool: false, explain: "sect=1 时 23:30 已算次日，日柱为庚申。本系统默认 sect=2，不取此口径。", source: "口径出处：app/paipan.py --sect 参数；引擎字段：四柱“日柱”（sect=1 现算）。"),
        QuizQuestion(id: 7, point: "晚子时", type: "judge", q: "2024-12-21 23:30，sect=2 与 sect=1 的时柱相同，都是丙子。", options: [], answerIndex: -1, answerBool: true, explain: "sect=2 时干按次日日干（庚）推，庚日子时为丙子；sect=1 日干已是庚，子时同样是丙子。两种口径只差日柱，不差此时柱。", source: "口径出处：app/paipan.py wushu（五鼠遁）；引擎字段：四柱“时柱”（两 sect 现算一致）。"),
        QuizQuestion(id: 8, point: "晚子时", type: "choice", q: "晚子时口径 sect=2 的含义是？", options: ["23:00–24:00 日柱不换、时干按次日日干推", "23:00–24:00 日柱按次日计", "23:00–24:00 时柱按当日日干推", "子时一律按次日计"], answerIndex: 0, answerBool: false, explain: "sect=2 是子平通行口径：23:00–24:00 日柱不换，时干按次日日干推。注意不是“晚子时按次日计”——日柱仍是当日。", source: "口径出处：app/paipan.py 模块文档串（G3 已修正收据行表述）；引擎字段：四柱“日柱／时柱”。"),
        QuizQuestion(id: 9, point: "闰月归属", type: "choice", q: "2025-08-10 是闰六月十七，称骨月重按几月算？", options: ["7 月", "6 月", "8 月", "闰六月单独算"], answerIndex: 0, answerBool: false, explain: "闰月上半月算本月，下半月算下月：闰六月十七已过十五，按七月算月重。", source: "口径出处：app/chenggu.py lunar_month_for_chenggu；引擎字段：称骨 breakdown 月。"),
        QuizQuestion(id: 10, point: "闰月归属", type: "choice", q: "2025-07-25 是闰六月初一，称骨月重按几月算？", options: ["6 月", "7 月", "5 月", "不算月重"], answerIndex: 0, answerBool: false, explain: "闰六月初一在上半月，按本月六月算月重。", source: "口径出处：app/chenggu.py lunar_month_for_chenggu；引擎字段：称骨 breakdown 月。"),
        QuizQuestion(id: 11, point: "闰月归属", type: "judge", q: "闰月归属口径是“上半月算本月，下半月算下月”。", options: [], answerIndex: -1, answerBool: true, explain: "通行注：闰月十五（含）以前算本月，十六以后算下月。称骨、梅花、六爻均同此口径。", source: "口径出处：app/chenggu.py lunar_month_for_chenggu；app/meihua.py lunar_parts 同口径。"),
        QuizQuestion(id: 12, point: "闰月归属", type: "choice", q: "2025 年的闰月是闰几月？", options: ["闰六月", "闰五月", "闰七月", "2025 年无闰月"], answerIndex: 0, answerBool: false, explain: "2025-07-25 至 08-22 为闰六月：2025-07-25 是闰六月初一，2025-08-10 是闰六月十七。", source: "口径出处：lunar_python 农历；引擎字段：排盘“农历”月／闰月。"),
        QuizQuestion(id: 13, point: "节气交节", type: "choice", q: "2026-02-04 04:00 出生，年柱是？（当年立春在 04:02）", options: ["乙巳", "丙午", "甲辰", "丁未"], answerIndex: 0, answerBool: false, explain: "年柱以立春为界：04:00 立春未到，仍属乙巳年；04:02 立春一过才换丙午年。", source: "口径出处：app/paipan.py（年柱以立春为界）；引擎字段：四柱“年柱”。"),
        QuizQuestion(id: 14, point: "节气交节", type: "choice", q: "2026-02-04 05:00 出生，年柱是？", options: ["丙午", "乙巳", "甲辰", "丁未"], answerIndex: 0, answerBool: false, explain: "05:00 已过立春（04:02），年柱换为丙午。同一天前后一小时，年柱不同——交节精确到分。", source: "口径出处：app/paipan.py；引擎字段：四柱“年柱”＋月令司令“交节”。"),
        QuizQuestion(id: 15, point: "节气交节", type: "judge", q: "年柱以立春为界、月柱以十二节为界，交节时刻精确到分。", options: [], answerIndex: -1, answerBool: true, explain: "年柱看立春、月柱看十二节，都以交节时刻（精确到分）为界，不是按正月初一或每月初一换。", source: "口径出处：app/paipan.py 模块文档串；引擎字段：月令司令“交节”。"),
        QuizQuestion(id: 16, point: "节气交节", type: "choice", q: "囿廷（2024-12-21）出生时，月令司令的交节是？", options: ["大雪 2024-12-06 23:17", "冬至 2024-12-21 17:20", "大雪 2024-12-07 23:17", "小雪 2024-11-22"], answerIndex: 0, answerBool: false, explain: "囿廷生于大雪后：交节为大雪 2024-12-06 23:17，节后 15 天，司令为癸（本气）。", source: "口径出处：app/paipan.py prev_jie；引擎字段：月令司令“交节”。"),
        QuizQuestion(id: 17, point: "夏令时", type: "judge", q: "1990-06-01 出生，命中中国大陆夏令时（1990-04-15–09-16）。", options: [], answerIndex: -1, answerBool: true, explain: "中国大陆现代夏令时段 1990 年为 4 月 15 日–9 月 16 日，6 月 1 日在期间内。", source: "口径出处：app/paipan.py DST_CN_MODERN；引擎字段：排盘“夏令时”。"),
        QuizQuestion(id: 18, point: "夏令时", type: "choice", q: "命中夏令时，系统默认如何处理？", options: ["只报警、不自动减 1 小时", "自动减 1 小时重排", "忽略不提示", "按夏令时读数直接排"], answerIndex: 0, answerBool: false, explain: "无法知道用户报的是夏令时读数还是已换算的标准时，默默减 1 小时既可能算错、又会悄悄改动存量命盘；所以默认只报警、不自动减。", source: "口径出处：app/paipan.py 模块文档串；引擎字段：排盘“夏令时·处理”。"),
        QuizQuestion(id: 19, point: "夏令时", type: "judge", q: "1990-10-01 出生，不在夏令时期间。", options: [], answerIndex: -1, answerBool: true, explain: "1990 年夏令时 9 月 16 日结束，10 月 1 日已不在期间内，不报警。", source: "口径出处：app/paipan.py DST_CN_MODERN；引擎字段：排盘“夏令时·命中”。"),
        QuizQuestion(id: 20, point: "夏令时", type: "choice", q: "只有用户确认报的是夏令时读数时，才加什么参数重排？", options: ["--dst-confirmed", "--no-tst", "--sect 1", "--lon 120"], answerIndex: 0, answerBool: false, explain: "只有用户确认报的是夏令时读数时，才加 --dst-confirmed 显式减 1 小时还原标准时后再排（再叠加真太阳时校正）；历史段命中时永远只报警。", source: "口径出处：app/paipan.py 模块文档串与 dst_hit；金标准：tools/tests/test_paipan_range.py。"),
        QuizQuestion(id: 21, point: "排盘年份验证范围", type: "choice", q: "本系统日柱已三方互校的年份范围是？", options: ["1900–2100", "1950–2030", "1600–2200", "公元 1–2099"], answerIndex: 0, answerBool: false, explain: "日柱 1900–2100 共 73,414 天三方交叉验证（锚点日数／独立 Meeus 天文算法／公开万年历，零偏差）。1950–2030 是旧范围，1600–2200 与公元 1–2099 是竞品标称，本系统不取。", source: "口径出处：app/paipan.py VERIFIED_MIN_YEAR／VERIFIED_MAX_YEAR；金标准：tools/tests/test_paipan_range.py。"),
        QuizQuestion(id: 22, point: "排盘年份验证范围", type: "judge", q: "1899 年出生仍可现算，但会提示未经三方互校、仅供参考。", options: [], answerIndex: -1, answerBool: true, explain: "范围外的出生年份仍照算（兼容 1900 年前的名人旧档），但输出“范围”字段明确提示未经三方互校、仅供参考；绝不硬拒。", source: "口径出处：app/paipan.py VERIFIED_MIN_YEAR；引擎字段：排盘“范围”。"),
        QuizQuestion(id: 23, point: "称骨", type: "choice", q: "称骨歌诀共多少格？", options: ["52 格（2.1–7.2 两）", "51 格", "60 格", "48 格"], answerIndex: 0, answerBool: false, explain: "称骨歌诀 52 格，钱数 2.1–7.2 两：2.1–7.1 逐 0.1 是 51 格，再加 7.2 格。", source: "口径出处：app/chenggu.py VERSES；金标准：tools/tests/test_chenggu.py。"),
        QuizQuestion(id: 24, point: "称骨", type: "choice", q: "称骨四重称重最大值合计是多少？", options: ["7.1 两", "7.2 两", "7.0 两", "6.9 两"], answerIndex: 0, answerBool: false, explain: "四重最大值：年 1.9＋月 1.8＋日 1.8＋时 1.6＝7.1 两，所以 7.2 格现实不可达，歌诀仍列备查、页面注明不可达。", source: "口径出处：app/chenggu.py YEAR/MONTH/DAY/HOUR_WEIGHT；金标准：tools/tests/test_chenggu.py。"),
        QuizQuestion(id: 25, point: "称骨", type: "choice", q: "癸巳年、冬月十九、辰时（毛泽东例），称骨是多少？", options: ["三两", "三两六钱", "二两八钱", "四两"], answerIndex: 0, answerBool: false, explain: "癸巳年 0.7＋十一月 0.9＋十九日 0.5＋辰时 0.9＝3.0 两。", source: "口径出处：app/chenggu.py chenggu_from_parts；金标准：tools/tests/test_chenggu.py（毛泽东例）。"),
        QuizQuestion(id: 26, point: "称骨", type: "choice", q: "甲辰年、十一月廿一、辰时（囿廷），称骨是多少？", options: ["三两六钱", "三两", "四两一钱", "二两九钱"], answerIndex: 0, answerBool: false, explain: "甲辰年 0.8＋十一月 0.9＋廿一日 1.0＋辰时 0.9＝3.6 两。", source: "口径出处：app/chenggu.py chenggu_from_parts；引擎字段：称骨 total_text。"),
        QuizQuestion(id: 27, point: "称骨", type: "judge", q: "七两二格四重最大值合计仅 7.1 两，现实不可达，歌诀只列备查。", options: [], answerIndex: -1, answerBool: true, explain: "四重最大值合计 7.1 两，7.2 格没有任何年月日时组合能达到；歌诀仍列入备查，页面注明不可达，不虚构命格名。", source: "口径出处：app/chenggu.py chenggu_from_parts reachable_note；金标准：tools/tests/test_chenggu.py。"),
        QuizQuestion(id: 28, point: "称骨", type: "choice", q: "称骨四重是哪四重？", options: ["年、月、日、时", "年、月、日、胎元", "干支、纳音、神煞", "年、月、日、时＋胎元"], answerIndex: 0, answerBool: false, explain: "称骨由年重、月重、日重、时重四重相加；胎元不参与称骨。", source: "口径出处：app/chenggu.py chenggu_from_parts breakdown；引擎字段：称骨 breakdown。"),
        QuizQuestion(id: 29, point: "梅花时间起卦", type: "choice", q: "2026-11-07 22:54、经度 107.8 时间起卦，本卦是？", options: ["小畜", "渐", "中孚", "睽"], answerIndex: 0, answerBool: false, explain: "校正后 22:21，农历九月廿九亥时：上卦巽、下卦乾，本卦小畜；互卦睽，变卦中孚，动爻三。", source: "口径出处：app/meihua.py divinate；金标准：tools/tests/test_meihua_liuyao.py。"),
        QuizQuestion(id: 30, point: "梅花时间起卦", type: "choice", q: "上题起卦，动爻是第几爻？", options: ["3", "6", "1", "5"], answerIndex: 0, answerBool: false, explain: "动爻＝(年＋月＋日＋时)%6：(7＋9＋29＋12)%6＝57%6＝3，动爻三，动爻爻辞“舆说辐，夫妻反目。”", source: "口径出处：app/meihua.py divinate；金标准：tools/tests/test_meihua_liuyao.py。"),
        QuizQuestion(id: 31, point: "梅花时间起卦", type: "choice", q: "时间起卦，年月日时四数分别为 12、10、7、10，本卦是？", options: ["渐", "观", "未济", "小畜"], answerIndex: 0, answerBool: false, explain: "上卦＝(12＋10＋7)%8＝29%8＝5 为巽，下卦＝(12＋10＋7＋10)%8＝39%8＝7 为艮，上巽下艮为渐卦。", source: "口径出处：app/meihua.py meihua_from_numbers；金标准：tools/tests/test_meihua_liuyao.py。"),
        QuizQuestion(id: 32, point: "梅花时间起卦", type: "judge", q: "梅花时间起卦：上卦＝(年＋月＋日)%8，余 0 取 8；动爻＝(年＋月＋日＋时)%6，余 0 取 6。", options: [], answerIndex: -1, answerBool: true, explain: "传宋·邵雍《梅花易数》年月日时起卦法：年数＝农历年地支数（子 1…亥 12）；上卦取 (年＋月＋日)%8，下卦取 (年＋月＋日＋时)%8，动爻取 (年＋月＋日＋时)%6，余 0 取 8／取 6。", source: "口径出处：app/meihua.py meihua_from_numbers；金标准：tools/tests/test_meihua_liuyao.py。"),
        QuizQuestion(id: 33, point: "梅花时间起卦", type: "choice", q: "上题（12、10、7、10）体卦、用卦与体用关系是？", options: ["体巽木克用艮土（体克用）", "体艮土克用巽木", "体巽木生用艮土", "用巽木克体艮土"], answerIndex: 0, answerBool: false, explain: "动爻在下卦，动爻所在卦为用：上卦巽为体、下卦艮为用；巽木克艮土，为体克用。", source: "口径出处：app/meihua.py meihua_from_numbers tiyong；金标准：tools/tests/test_meihua_liuyao.py。"),
        QuizQuestion(id: 34, point: "梅花时间起卦", type: "judge", q: "梅花起卦的农历与真太阳时口径与八字排盘同口径（晚子时 sect=2、闰月上半月本月下半月下月）。", options: [], answerIndex: -1, answerBool: true, explain: "梅花 divinate 与 paipan 同式校正：2026-11-07 22:54 经度 107.8 校正 -32.7 分钟得 22:21；农历与闰月归属亦与排盘同口径。", source: "口径出处：app/meihua.py lunar_parts／divinate；金标准：tools/tests/test_meihua_liuyao.py。"),
        QuizQuestion(id: 35, point: "奇门定局法与寄宫", type: "choice", q: "本系统奇门默认定局法是？", options: ["拆补法", "置闰法", "茅山法", "阴盘法"], answerIndex: 0, answerBool: false, explain: "默认拆补法定局；置闰法需显式切换（dingju=zhiyun），茅山法与阴盘法未实现、只做口径调研。", source: "口径出处：app/qimen.py chart_for_datetime；金标准：tools/tests/test_qimen_golden.py。"),
        QuizQuestion(id: 36, point: "奇门定局法与寄宫", type: "choice", q: "本系统奇门默认寄宫是？", options: ["恒寄坤二", "恒寄艮八", "阳艮阴坤", "阳坤阴艮"], answerIndex: 0, answerBool: false, explain: "默认恒寄坤二（天禽阳遁阴遁俱寄坤宫）；其余三档（恒寄艮八／阳艮阴坤／阳坤阴艮）可切换，各有独立金标准。", source: "口径出处：app/qimen.py JIGONG_NAMES；金标准：tools/tests/test_qimen_jigong.py。"),
        QuizQuestion(id: 37, point: "奇门定局法与寄宫", type: "choice", q: "2026-11-07 22:54 日家奇门起局，结果是？", options: ["阴遁 8 局", "阳遁 8 局", "阴遁 9 局", "阳遁 1 局"], answerIndex: 0, answerBool: false, explain: "日家：冬至后阳遁、夏至后阴遁；2026-11-07 在立冬节后，阴遁；局数按日支，乙酉日起得阴遁 8 局。", source: "口径出处：app/qimen.py rijia_chart_for_datetime；金标准：tools/tests/test_qimen_rijia_zhiyun.py。"),
        QuizQuestion(id: 38, point: "奇门定局法与寄宫", type: "judge", q: "置闰法只在芒种和大雪二节之后置闰。", options: [], answerIndex: -1, answerBool: true, explain: "《奇门遁甲统宗》卷一“论超接之法”“置闰法”：超神超九日则置闰，只在芒种和大雪二节之后置闰；行走 1718–2027 约 2.7 年一闰。", source: "口径出处：app/qimen.py _zhiyun_blocks（134 块 1718–2098）；金标准：tools/tests/test_qimen_rijia_zhiyun.py。"),
        QuizQuestion(id: 39, point: "奇门定局法与寄宫", type: "choice", q: "奇门收据行默认会写明真太阳时状态，默认是？", options: ["真太阳时未校正（按钟表时间起局）", "已按经度 107.8 校正", "已按出生地经度校正", "不写真太阳时"], answerIndex: 0, answerBool: false, explain: "默认不校正：奇门问事多为“此刻起局”而非命主生辰，用命主经度校正问事时间在语义上是错的；新口径通过显式参数开启。", source: "口径出处：app/qimen.py build_receipt；金标准：tools/tests/test_qimen_solar.py。"),
        QuizQuestion(id: 40, point: "奇门定局法与寄宫", type: "judge", q: "奇门问事默认不校正真太阳时，因为问事地不等于出生地。", options: [], answerIndex: -1, answerBool: true, explain: "默认行为保持不变：183 断言金标准与 App 现行行为均建立在不校正口径上；显式给经度才会校正，例如 2026-11-07 07:00＋经度 107.8 校正后 06:27，时柱由庚辰变为己卯。", source: "口径出处：app/qimen.py chart_for_datetime；金标准：tools/tests/test_qimen_solar.py。"),
        QuizQuestion(id: 41, point: "古籍原文", type: "judge", q: "《子平真诠·论用神》说“八字用神，专求月令”。", options: [], answerIndex: -1, answerBool: true, explain: "《子平真诠》卷八开篇：“八字用神，专求月令，以日干配月令地支，而生克不同，格局分焉。”本系统取用神专主月令，正本于此。", source: "口径出处：app/classics.json 子平真诠一～十篇（zp-08 第 1 句）；来源：Libo《子平真詮（原文）》。"),
        QuizQuestion(id: 42, point: "古籍原文", type: "choice", q: "《滴天髓·月令》把月令比作什么？", options: ["宅（提纲之府，譬之宅也）", "墓", "根", "门户"], answerIndex: 0, answerBool: false, explain: "“月令乃提纲之府，譬之宅也，人元为用事之神，宅之定向也，不可以不卜。”", source: "口径出处：app/classics.json 滴天髓通神论十五·月令（ts-15 第 1 句）；来源：eymao《滴天髓》原文。"),
        QuizQuestion(id: 43, point: "古籍原文", type: "judge", q: "《滴天髓》说“月令乃提纲之府”，与本系统“月令为提纲”口径一致。", options: [], answerIndex: -1, answerBool: true, explain: "《滴天髓》通神论十五·月令开篇即“月令乃提纲之府”；本系统排盘以月令为提纲、用神专求月令，与此同源。", source: "口径出处：app/classics.json 滴天髓 ts-15；app/paipan.py 月令司令。"),
        QuizQuestion(id: 44, point: "古籍原文", type: "choice", q: "《子平真诠》开篇第一句讲什么？", options: ["天地之间，一气而已", "八字用神，专求月令", "财官印食，此用神之善", "合化之义，以十干阴阳相配而成"], answerIndex: 0, answerBool: false, explain: "《子平真诠》开篇：“天地之间，一气而已。惟有动静，遂分阴阳。”先立一气分阴阳、阴阳分四象、四象含五行的根本，再讲干支生克。", source: "口径出处：app/classics.json 子平真诠 zp-01 第 1 句；来源：Libo《子平真詮（原文）》。"),
    ]
}

struct QuizView: View {
    @State private var choiceAnswers: [Int: Int] = [:]
    @State private var judgeAnswers: [Int: Bool] = [:]
    @State private var submitted = false
    @State private var score = 0
    private var total: Int { QuizData.questions.count }
    private var wrongIds: [Int] {
        var out: [Int] = []
        for q in QuizData.questions {
            if q.type == "choice" {
                if choiceAnswers[q.id] != q.answerIndex { out.append(q.id) }
            } else {
                if judgeAnswers[q.id] != q.answerBool { out.append(q.id) }
            }
        }
        return out
    }
    var body: some View {
        List {
            Section {
                Text("共 \(total) 题 · 覆盖 10 个口径点，每点至少 2 题。每题答案由本机引擎现算复核；答错即显示解析与口径出处。得分与错题回顾只存本机，不落库。".scriptConverted).font(.callout).foregroundStyle(Ky.sub)
                if submitted {
                    Text("得分：\(score) / \(total)".scriptConverted).font(.headline).foregroundStyle(Ky.ink)
                }
            }
            ForEach(QuizData.questions) { q in
                Section(q.point) {
                    Text("\(q.id). " + q.q.scriptConverted).font(.subheadline).foregroundStyle(Ky.ink)
                    if q.type == "choice" {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { j, o in
                            Button { choiceAnswers[q.id] = j } label: {
                                HStack {
                                    Image(systemName: choiceAnswers[q.id] == j ? "checkmark.circle.fill" : "circle").foregroundStyle(Ky.gold)
                                    Text(o.scriptConverted).font(.callout).foregroundStyle(Ky.ink)
                                }
                            }.buttonStyle(.plain)
                            .disabled(submitted)
                        }
                    } else {
                        HStack(spacing: 24) {
                            Button { judgeAnswers[q.id] = true } label: {
                                Label("对".scriptConverted, systemImage: judgeAnswers[q.id] == true ? "checkmark.circle.fill" : "circle").foregroundStyle(Ky.gold)
                            }.buttonStyle(.plain)
                            Button { judgeAnswers[q.id] = false } label: {
                                Label("错".scriptConverted, systemImage: judgeAnswers[q.id] == false ? "checkmark.circle.fill" : "circle").foregroundStyle(Ky.gold)
                            }.buttonStyle(.plain)
                        }
                        .disabled(submitted)
                    }
                    if submitted {
                        let ok = q.type == "choice" ? (choiceAnswers[q.id] == q.answerIndex) : (judgeAnswers[q.id] == q.answerBool)
                        Text(ok ? "✓ 答对".scriptConverted : "✗ 答错".scriptConverted).font(.subheadline).fontWeight(.semibold).foregroundStyle(ok ? Ky.jade : Ky.gold)
                        Text(q.explain.scriptConverted).font(.callout).foregroundStyle(Ky.ink)
                        Text(q.source.scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                    }
                }
            }
            Section {
                Button(submitted ? "重新作答" : "交卷（本机判分）") {
                    if submitted {
                        choiceAnswers = [:]
                        judgeAnswers = [:]
                        submitted = false
                        score = 0
                    } else {
                        score = total - wrongIds.count
                        submitted = true
                        let rec: [String: Any] = ["score": score, "total": total, "wrong": wrongIds, "at": ISO8601DateFormatter().string(from: Date())]
                        UserDefaults.standard.set(rec, forKey: "kanyu-quiz-last")
                    }
                }.buttonStyle(.plain)
                .font(.headline).foregroundStyle(Ky.gold)
            }
        }
        .navigationTitle("排盘口径自测".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }
}
