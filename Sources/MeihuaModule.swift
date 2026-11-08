// MeihuaModule.swift — 六爻／梅花时间起卦（G5，2026-11-07）
// 与 Web app/meihua.py 同口径：64 卦表由 Web 引擎原样生成（见 kanyu-web/tools/gen_meihua_swift.py），
// 起卦法、体用、八宫纳甲、世应六亲、真太阳时与农历口径均与 Web 一致。
// 解卦只给《周易》卦辞／爻辞原文＋白话直述＋体用生克结论，不编断语、不落病名、不做寿数断语。
// 起卦自动写入 ForecastStore（前瞻登记），到期回验走现有前瞻流程。
import SwiftUI
import LunarSwift

struct MeihuaYao {
    let title: String
    let text: String
    let baihua: String
}

struct MeihuaHexagram {
    let name: String
    let upper: String
    let lower: String
    let guaci: String
    let guaciBaihua: String
    let yao: [MeihuaYao]
    let yong: MeihuaYao?
}

struct MeihuaLine {
    let pos: Int
    let name: String
    let yinYang: String
    let branch: String
    let wuxing: String
    let qin: String
}

struct MeihuaResult {
    let clock: Date
    let corrected: Date
    let correctionMinutes: Double
    let lon: Double
    let yearBranch: String
    let month: Int
    let day: Int
    let hourBranch: String
    let isLeap: Bool
    let numbers: (year: Int, month: Int, day: Int, hour: Int)
    let ben: MeihuaHexagram
    let hu: MeihuaHexagram
    let bian: MeihuaHexagram
    let moving: Int
    let movingYao: MeihuaYao
    let tiyongLabel: String
    let tiyongText: String
    let huRelationText: String
    let palace: String
    let generation: String
    let shi: Int
    let ying: Int
    let lines: [MeihuaLine]
    let movingBianLine: MeihuaLine
    let bianPalace: String
    let bianGeneration: String
    let question: String
}

enum MeihuaEngine {
    static let defaultLon = 107.8
    static let disclaimer = "占卜只作辅助决疑：本页只给《周易》卦辞／爻辞原文＋白话直述与体用生克结论，不编具体吉凶断语、不落病名、不做寿数断语。"
    static let source = "起卦法传为宋·邵雍《梅花易数》年月日时起卦；六爻世应六亲为京房八宫纳甲通行口径；卦辞爻辞为公有领域《周易》通行本原文。"
    static let dz = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let yaoNames = ["初", "二", "三", "四", "五", "上"]
    // 先天数（乾 1…坤 8）与八卦五行；bits 自下而上（bit0＝初爻）。
    static let trigramNumber: [String: Int] = ["乾": 1, "兑": 2, "离": 3, "震": 4, "巽": 5, "坎": 6, "艮": 7, "坤": 8]
    static let trigramWuxing: [String: String] = ["乾": "金", "兑": "金", "震": "木", "巽": "木", "坎": "水", "离": "火", "艮": "土", "坤": "土"]
    static let trigramBits: [String: [Int]] = ["乾": [1, 1, 1], "兑": [0, 1, 1], "离": [1, 0, 1], "震": [0, 0, 1], "巽": [1, 1, 0], "坎": [0, 1, 0], "艮": [1, 0, 0], "坤": [0, 0, 0]]
    static let branchWuxing: [String: String] = ["子": "水", "丑": "土", "寅": "木", "卯": "木", "辰": "土", "巳": "火", "午": "火", "未": "土", "申": "金", "酉": "金", "戌": "土", "亥": "水"]
    // 宫五行：乾兑金、震巽木、坎水、离火、艮坤土。
    static let palaceWuxing: [String: String] = ["乾宫": "金", "兑宫": "金", "震宫": "木", "巽宫": "木", "坎宫": "水", "离宫": "火", "艮宫": "土", "坤宫": "土"]
    // 世应：世代 -> (世， 应）。
    static let shiYing: [String: (Int, Int)] = ["本宫": (6, 3), "一世": (1, 4), "二世": (2, 5), "三世": (3, 6), "四世": (4, 1), "五世": (5, 2), "游魂": (4, 1), "归魂": (3, 6)]

    static let palaceOf: [String: (String, String)] = [
        "中孚": ("艮宫", "游魂"),
        "丰": ("坎宫", "五世"),
        "临": ("坤宫", "二世"),
        "乾": ("乾宫", "本宫"),
        "井": ("震宫", "五世"),
        "兑": ("兑宫", "本宫"),
        "剥": ("乾宫", "五世"),
        "升": ("震宫", "四世"),
        "同人": ("离宫", "归魂"),
        "否": ("乾宫", "三世"),
        "咸": ("兑宫", "三世"),
        "噬嗑": ("巽宫", "五世"),
        "困": ("兑宫", "一世"),
        "坎": ("坎宫", "本宫"),
        "坤": ("坤宫", "本宫"),
        "复": ("坤宫", "一世"),
        "大壮": ("坤宫", "四世"),
        "大有": ("乾宫", "归魂"),
        "大畜": ("艮宫", "二世"),
        "大过": ("震宫", "游魂"),
        "夬": ("坤宫", "五世"),
        "姤": ("乾宫", "一世"),
        "家人": ("巽宫", "二世"),
        "小畜": ("巽宫", "一世"),
        "小过": ("兑宫", "游魂"),
        "履": ("艮宫", "五世"),
        "屯": ("坎宫", "二世"),
        "巽": ("巽宫", "本宫"),
        "师": ("坎宫", "归魂"),
        "归妹": ("兑宫", "归魂"),
        "恒": ("震宫", "三世"),
        "损": ("艮宫", "三世"),
        "旅": ("离宫", "一世"),
        "无妄": ("巽宫", "四世"),
        "既济": ("坎宫", "三世"),
        "明夷": ("坎宫", "游魂"),
        "晋": ("乾宫", "游魂"),
        "未济": ("离宫", "三世"),
        "比": ("坤宫", "归魂"),
        "泰": ("坤宫", "三世"),
        "涣": ("离宫", "五世"),
        "渐": ("艮宫", "归魂"),
        "益": ("巽宫", "三世"),
        "睽": ("艮宫", "四世"),
        "离": ("离宫", "本宫"),
        "艮": ("艮宫", "本宫"),
        "节": ("坎宫", "一世"),
        "萃": ("兑宫", "二世"),
        "蒙": ("离宫", "四世"),
        "蛊": ("巽宫", "归魂"),
        "观": ("乾宫", "四世"),
        "解": ("震宫", "二世"),
        "讼": ("离宫", "游魂"),
        "谦": ("兑宫", "五世"),
        "豫": ("震宫", "一世"),
        "贲": ("艮宫", "一世"),
        "蹇": ("兑宫", "四世"),
        "遁": ("乾宫", "二世"),
        "随": ("震宫", "归魂"),
        "需": ("坤宫", "游魂"),
        "震": ("震宫", "本宫"),
        "革": ("坎宫", "四世"),
        "颐": ("巽宫", "游魂"),
        "鼎": ("离宫", "二世"),
    ]

    static let najia: [String: (String, String)] = [
        "乾": ("子寅辰", "午申戌"),
        "坤": ("未巳卯", "丑亥酉"),
        "震": ("子寅辰", "午申戌"),
        "巽": ("丑亥酉", "未巳卯"),
        "坎": ("寅辰午", "申戌子"),
        "离": ("卯丑亥", "酉未巳"),
        "艮": ("辰午申", "戌子寅"),
        "兑": ("巳卯丑", "亥酉未"),
    ]

    static let hexagrams: [MeihuaHexagram] = [
    MeihuaHexagram(name: "乾", upper: "乾", lower: "乾",
        guaci: "元亨，利贞。", guaciBaihua: "大为亨通，利于守正。",
        yao: [
            MeihuaYao(title: "初九", text: "潜龙，勿用。", baihua: "龙潜于渊，时机未到，不宜有所作为。"),
            MeihuaYao(title: "九二", text: "见龙在田，利见大人。", baihua: "龙现于田野，利于见到有德有位的人。"),
            MeihuaYao(title: "九三", text: "君子终日乾乾，夕惕若，厉，无咎。", baihua: "君子整日勤勉不懈，夜晚警惕自省，虽处危境，只要谨慎便无过失。"),
            MeihuaYao(title: "九四", text: "或跃在渊，无咎。", baihua: "龙或跃出深渊，进退未定，只要审时度势便无过失。"),
            MeihuaYao(title: "九五", text: "飞龙在天，利见大人。", baihua: "龙飞于天，利于见到有德有位的人。"),
            MeihuaYao(title: "上九", text: "亢龙有悔。", baihua: "龙飞得过高，必有悔恨。")
        ], yong: MeihuaYao(title: "用九", text: "见群龙无首，吉。", baihua: "众龙并见而不以首领自居，吉。")),

    MeihuaHexagram(name: "坤", upper: "坤", lower: "坤",
        guaci: "元亨，利牝马之贞。君子有攸往，先迷后得主，利。西南得朋，东北丧朋。安贞吉。", guaciBaihua: "大为亨通，利于如牝马般柔顺守正。君子有所前往，先会迷失，后得主人，利于西南得友、东北失友，安守正道则吉。",
        yao: [
            MeihuaYao(title: "初六", text: "履霜，坚冰至。", baihua: "脚踏秋霜，坚冰将至——微兆已见，当知所戒。"),
            MeihuaYao(title: "六二", text: "直，方，大不习，无不利。", baihua: "正直、方正、宽大，不必刻意修习，无所不利。"),
            MeihuaYao(title: "六三", text: "含章，可贞。或从王事，无成有终。", baihua: "内含美德，可以守正；或为王事效力，不居其功而有善终。"),
            MeihuaYao(title: "六四", text: "括囊；无咎，无誉。", baihua: "扎紧口袋，不出头：无过失，也无声誉。"),
            MeihuaYao(title: "六五", text: "黄裳，元吉。", baihua: "黄色的下裳，中正之德，大吉。"),
            MeihuaYao(title: "上六", text: "龙战于野，其血玄黄。", baihua: "龙在野外相战，血流玄黄——阴阳相争，两败俱伤。")
        ], yong: MeihuaYao(title: "用六", text: "利永贞。", baihua: "利于永远守正。")),

    MeihuaHexagram(name: "屯", upper: "坎", lower: "震",
        guaci: "元亨，利贞，勿用有攸往，利建侯。", guaciBaihua: "大为亨通，利于守正，不宜有所前往，利于建立诸侯。",
        yao: [
            MeihuaYao(title: "初九", text: "磐桓，利居贞，利建侯。", baihua: "徘徊难进，利于安居守正，利于建立诸侯。"),
            MeihuaYao(title: "六二", text: "屯如邅如，乘马班如，匪寇婚媾。女子贞不字，十年乃字。", baihua: "艰难徘徊，车马回旋，不是盗寇，而是来求婚的。女子守正不嫁，十年后才出嫁。"),
            MeihuaYao(title: "六三", text: "即鹿无虞，惟入于林中，君子几不如舍，往吝。", baihua: "追鹿没有向导，只会迷入林中，君子见机不如舍弃，前往必有遗憾。"),
            MeihuaYao(title: "六四", text: "乘马班如，求婚媾，往吉，无不利。", baihua: "车马回旋，前来求婚，前往则吉，无所不利。"),
            MeihuaYao(title: "九五", text: "屯其膏，小贞吉，大贞凶。", baihua: "恩泽被壅塞，小事守正则吉，大事守正则凶。"),
            MeihuaYao(title: "上六", text: "乘马班如，泣血涟如。", baihua: "车马回旋，血泪涟涟。")
        ], yong: nil),

    MeihuaHexagram(name: "蒙", upper: "艮", lower: "坎",
        guaci: "亨，匪我求童蒙，童蒙求我。初筮告，再三渎，渎则不告。利贞。", guaciBaihua: "亨通。不是我求蒙昧的童子，而是童子来求我。初次占问便告知，反复占问就是亵渎，亵渎便不再告知。利于守正。",
        yao: [
            MeihuaYao(title: "初六", text: "发蒙，利用刑人，用说桎梏，以往吝。", baihua: "启发蒙昧，宜用刑罚惩治，解开枷锁，前往则有遗憾。"),
            MeihuaYao(title: "九二", text: "包蒙吉。纳妇吉，子克家。", baihua: "包容蒙昧则吉。娶妻则吉，儿子能治家。"),
            MeihuaYao(title: "六三", text: "勿用取女，见金夫，不有躬，无攸利。", baihua: "不宜娶此女，她见了有钱的男子便失了自身，无所利。"),
            MeihuaYao(title: "六四", text: "困蒙，吝。", baihua: "困于蒙昧，有遗憾。"),
            MeihuaYao(title: "六五", text: "童蒙，吉。", baihua: "如童子般蒙昧而虚心求教，吉。"),
            MeihuaYao(title: "上九", text: "击蒙，不利为寇，利御寇。", baihua: "打击蒙昧，不宜做盗寇，利于抵御盗寇。")
        ], yong: nil),

    MeihuaHexagram(name: "需", upper: "坎", lower: "乾",
        guaci: "有孚，光亨，贞吉。利涉大川。", guaciBaihua: "心怀诚信，光明亨通，守正则吉，利于渡过大河。",
        yao: [
            MeihuaYao(title: "初九", text: "需于郊，利用恒，无咎。", baihua: "在郊野等待，利于恒久等待，无过失。"),
            MeihuaYao(title: "九二", text: "需于沙，小有言，终吉。", baihua: "在沙地等待，稍有言语议论，最终吉。"),
            MeihuaYao(title: "九三", text: "需于泥，致寇至。", baihua: "在泥泞中等待，会招来盗寇。"),
            MeihuaYao(title: "六四", text: "需于血，出自穴。", baihua: "在血泊中等待，从洞穴中脱出。"),
            MeihuaYao(title: "九五", text: "需于酒食，贞吉。", baihua: "在酒食宴乐中等待，守正则吉。"),
            MeihuaYao(title: "上六", text: "入于穴，有不速之客三人来，敬之终吉。", baihua: "进入洞穴，有三位不请自来的客人，恭敬相待则终吉。")
        ], yong: nil),

    MeihuaHexagram(name: "讼", upper: "乾", lower: "坎",
        guaci: "有孚，窒惕。中吉，终凶。利见大人，不利涉大川。", guaciBaihua: "心怀诚信，窒塞警惕，中途吉，最终凶，利于见大人，不利渡大河。",
        yao: [
            MeihuaYao(title: "初六", text: "不永所事，小有言，终吉。", baihua: "不长久纠缠此事，稍有言语，最终吉。"),
            MeihuaYao(title: "九二", text: "不克讼，归而逋，其邑人三百户，无眚。", baihua: "争讼不能胜，归去逃避，邑中三百户人家，无灾祸。"),
            MeihuaYao(title: "六三", text: "食旧德，贞厉，终吉，或从王事，无成。", baihua: "享用旧有的德行，守正而危厉，最终吉；或为王事效力，不居其功。"),
            MeihuaYao(title: "九四", text: "不克讼，复即命渝，安贞吉。", baihua: "争讼不能胜，回来顺从天命，改过自新，安守正道则吉。"),
            MeihuaYao(title: "九五", text: "讼元吉。", baihua: "争讼而得大吉。"),
            MeihuaYao(title: "上九", text: "或锡之鞶带，终朝三褫之。", baihua: "或被赐予大带，一天之内三次被夺去。")
        ], yong: nil),

    MeihuaHexagram(name: "师", upper: "坤", lower: "坎",
        guaci: "贞丈人，吉。无咎。", guaciBaihua: "守正而任用有威望的长者则吉，无过失。",
        yao: [
            MeihuaYao(title: "初六", text: "师出以律，否臧凶。", baihua: "军队出征以纪律为要，纪律不好则凶。"),
            MeihuaYao(title: "九二", text: "在师中吉，无咎，王三锡命。", baihua: "身在军中则吉，无过失，君王多次赐命嘉奖。"),
            MeihuaYao(title: "六三", text: "师或舆尸，凶。", baihua: "军队或载尸而归，凶。"),
            MeihuaYao(title: "六四", text: "师左次，无咎。", baihua: "军队退守左方，无过失。"),
            MeihuaYao(title: "六五", text: "田有禽，利执言，无咎。长子帅师，弟子舆尸，贞凶。", baihua: "田中有禽兽，利于执言捕捉，无过失。长子率军、弟子载尸，守正则凶。"),
            MeihuaYao(title: "上六", text: "大君有命，开国承家，小人勿用。", baihua: "君王有命，分封诸侯、承继家业，小人不可用。")
        ], yong: nil),

    MeihuaHexagram(name: "比", upper: "坎", lower: "坤",
        guaci: "吉，原筮，元永贞，无咎。不宁方来，后夫凶。", guaciBaihua: "吉。原先占问，大而永守正道，无过失。不安宁的诸方前来亲附，来得迟的凶。",
        yao: [
            MeihuaYao(title: "初六", text: "有孚比之，无咎。有孚盈缶，终来有它吉。", baihua: "心怀诚信而亲附，无过失。诚信满溢如缶，终会带来意外的吉。"),
            MeihuaYao(title: "六二", text: "比之自内，贞吉。", baihua: "由内心亲附，守正则吉。"),
            MeihuaYao(title: "六三", text: "比之匪人。", baihua: "亲附了不该亲附的人。"),
            MeihuaYao(title: "六四", text: "外比之，贞吉。", baihua: "向外亲附，守正则吉。"),
            MeihuaYao(title: "九五", text: "显比，王用三驱，失前禽。邑人不诫，吉。", baihua: "光明正大地亲附，君王田猎三面驱赶，纵走前面的禽兽，邑中人不加戒备，吉。"),
            MeihuaYao(title: "上六", text: "比之无首，凶。", baihua: "亲附而无首领，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "小畜", upper: "巽", lower: "乾",
        guaci: "亨，密云不雨，自我西郊。", guaciBaihua: "亨通。密云不雨，云从西郊而来。",
        yao: [
            MeihuaYao(title: "初九", text: "复自道，何其咎，吉。", baihua: "返回自己的正道，有什么过失呢，吉。"),
            MeihuaYao(title: "九二", text: "牵复，吉。", baihua: "被牵引而返回，吉。"),
            MeihuaYao(title: "九三", text: "舆说辐，夫妻反目。", baihua: "车轮脱落，夫妻反目。"),
            MeihuaYao(title: "六四", text: "有孚，血去惕出，无咎。", baihua: "心怀诚信，血光消去、警惕解除，无过失。"),
            MeihuaYao(title: "九五", text: "有孚挛如，富以其邻。", baihua: "诚信相连，富及邻里。"),
            MeihuaYao(title: "上九", text: "既雨既处，尚德载，妇贞厉。月几望，君子征凶。", baihua: "既已降雨又已停歇，崇尚德行可以满载。妇人守正则危厉。月近满，君子出征凶。")
        ], yong: nil),

    MeihuaHexagram(name: "履", upper: "乾", lower: "兑",
        guaci: "履虎尾，不咥人，亨。", guaciBaihua: "踩着老虎尾巴，老虎不咬人，亨通。",
        yao: [
            MeihuaYao(title: "初九", text: "素履，往无咎。", baihua: "以素朴之履前往，无过失。"),
            MeihuaYao(title: "九二", text: "履道坦坦，幽人贞吉。", baihua: "行走在平坦大道上，幽居之人守正则吉。"),
            MeihuaYao(title: "六三", text: "眇能视，跛能履，履虎尾，咥人，凶。武人为于大君。", baihua: "瞎了一只眼还能看，跛了脚还能走，踩着虎尾被咬，凶。武夫妄为大君。"),
            MeihuaYao(title: "九四", text: "履虎尾，愬愬，终吉。", baihua: "踩着虎尾，心怀恐惧，最终吉。"),
            MeihuaYao(title: "九五", text: "夬履，贞厉。", baihua: "果决而行，守正而危厉。"),
            MeihuaYao(title: "上九", text: "视履考祥，其旋元吉。", baihua: "回顾所行而考察祥瑞，回旋反顾则大吉。")
        ], yong: nil),

    MeihuaHexagram(name: "泰", upper: "坤", lower: "乾",
        guaci: "小往大来，吉，亨。", guaciBaihua: "小的离去、大的到来，吉，亨通。",
        yao: [
            MeihuaYao(title: "初九", text: "拔茅茹，以其汇，征吉。", baihua: "拔起茅草，连根带出，同类相随，出征则吉。"),
            MeihuaYao(title: "九二", text: "包荒，用冯河，不遐遗，朋亡，得尚于中行。", baihua: "包容荒秽，能渡大河，不遗漏远方，朋党消亡，得配中行之道。"),
            MeihuaYao(title: "九三", text: "无平不陂，无往不复，艰贞无咎。勿恤其孚，于食有福。", baihua: "没有平地不起伏，没有前往不返回，艰难中守正则无过失。不必忧虑诚信，在饮食中有福。"),
            MeihuaYao(title: "六四", text: "翩翩，不富以其邻，不戒以孚。", baihua: "翩然来归，不以富自居而与邻同享，不加戒备而以诚信相待。"),
            MeihuaYao(title: "六五", text: "帝乙归妹，以祉元吉。", baihua: "帝乙嫁妹，因而得福，大吉。"),
            MeihuaYao(title: "上六", text: "城复于隍，勿用师。自邑告命，贞吝。", baihua: "城墙倒塌入护城壕，不宜用兵。自邑中发布命令，守正则有遗憾。")
        ], yong: nil),

    MeihuaHexagram(name: "否", upper: "乾", lower: "坤",
        guaci: "否之匪人，不利君子贞，大往小来。", guaciBaihua: "闭塞而非人道，不利于君子守正，大的离去、小的到来。",
        yao: [
            MeihuaYao(title: "初六", text: "拔茅茹，以其汇，贞吉，亨。", baihua: "拔起茅草，连根带出，同类相随，守正则吉，亨通。"),
            MeihuaYao(title: "六二", text: "包承。小人吉，大人否，亨。", baihua: "包容承受。小人吉，大人闭塞，亨通。"),
            MeihuaYao(title: "六三", text: "包羞。", baihua: "包藏羞辱。"),
            MeihuaYao(title: "九四", text: "有命，无咎，畴离祉。", baihua: "奉有天命，无过失，同类都得福祉。"),
            MeihuaYao(title: "九五", text: "休否，大人吉。其亡其亡，系于苞桑。", baihua: "休止闭塞，大人吉。常念其亡其亡，系于牢固的桑树根上。"),
            MeihuaYao(title: "上九", text: "倾否，先否后喜。", baihua: "倾覆闭塞，先闭塞而后喜悦。")
        ], yong: nil),

    MeihuaHexagram(name: "同人", upper: "乾", lower: "离",
        guaci: "同人于野，亨。利涉大川，利君子贞。", guaciBaihua: "与人在野外相合，亨通，利于渡大河，利于君子守正。",
        yao: [
            MeihuaYao(title: "初九", text: "同人于门，无咎。", baihua: "在门内与人相合，无过失。"),
            MeihuaYao(title: "六二", text: "同人于宗，吝。", baihua: "只与宗族相合，有遗憾。"),
            MeihuaYao(title: "九三", text: "伏戎于莽，升其高陵，三岁不兴。", baihua: "埋伏兵甲于草莽，登上高陵，三年不能兴兵。"),
            MeihuaYao(title: "九四", text: "乘其墉，弗克攻，吉。", baihua: "登上城墙，不能攻克，反而吉。"),
            MeihuaYao(title: "九五", text: "同人，先号啕而后笑。大师克相遇。", baihua: "与人相合，先号啕大哭而后欢笑，大军克敌而相遇。"),
            MeihuaYao(title: "上九", text: "同人于郊，无悔。", baihua: "在郊野与人相合，无悔恨。")
        ], yong: nil),

    MeihuaHexagram(name: "大有", upper: "离", lower: "乾",
        guaci: "元亨。", guaciBaihua: "大为亨通。",
        yao: [
            MeihuaYao(title: "初九", text: "无交害，匪咎，艰则无咎。", baihua: "不与人交往而招害，不是过失，艰难中谨慎则无过失。"),
            MeihuaYao(title: "九二", text: "大车以载，有攸往，无咎。", baihua: "大车满载，有所前往，无过失。"),
            MeihuaYao(title: "九三", text: "公用亨于天子，小人弗克。", baihua: "公侯用以献享于天子，小人不能胜任。"),
            MeihuaYao(title: "九四", text: "匪其彭，无咎。", baihua: "不自大炫耀，无过失。"),
            MeihuaYao(title: "六五", text: "厥孚交如，威如，吉。", baihua: "诚信交相感应，威严并存，吉。"),
            MeihuaYao(title: "上九", text: "自天佑之，吉，无不利。", baihua: "得上天保佑，吉，无所不利。")
        ], yong: nil),

    MeihuaHexagram(name: "谦", upper: "坤", lower: "艮",
        guaci: "亨，君子有终。", guaciBaihua: "亨通，君子有善终。",
        yao: [
            MeihuaYao(title: "初六", text: "谦谦君子，用涉大川，吉。", baihua: "谦而又谦的君子，可以渡大河，吉。"),
            MeihuaYao(title: "六二", text: "鸣谦，贞吉。", baihua: "谦德声闻，守正则吉。"),
            MeihuaYao(title: "九三", text: "劳谦，君子有终，吉。", baihua: "劳而谦下，君子有善终，吉。"),
            MeihuaYao(title: "六四", text: "无不利，撝谦。", baihua: "无所不利，发挥谦德。"),
            MeihuaYao(title: "六五", text: "不富，以其邻，利用侵伐，无不利。", baihua: "不以富自居，与邻同享，利于征伐，无所不利。"),
            MeihuaYao(title: "上六", text: "鸣谦，利用行师，征邑国。", baihua: "谦德声闻，利于兴师，征伐邑国。")
        ], yong: nil),

    MeihuaHexagram(name: "豫", upper: "震", lower: "坤",
        guaci: "利建侯，行师。", guaciBaihua: "利于建立诸侯，出动军队。",
        yao: [
            MeihuaYao(title: "初六", text: "鸣豫，凶。", baihua: "以豫乐自鸣，凶。"),
            MeihuaYao(title: "六二", text: "介于石，不终日，贞吉。", baihua: "坚守如磐石，不待终日，守正则吉。"),
            MeihuaYao(title: "六三", text: "盱豫，悔，迟有悔。", baihua: "仰视豫乐而生悔，迟疑更有悔。"),
            MeihuaYao(title: "九四", text: "由豫，大有得。勿疑，朋盍簪。", baihua: "由豫乐而行，大有所得。不要疑虑，朋友会合而来。"),
            MeihuaYao(title: "六五", text: "贞疾，恒不死。", baihua: "守正而有疾病，久而不死。"),
            MeihuaYao(title: "上六", text: "冥豫，成有渝，无咎。", baihua: "昏暗中豫乐，事情有变，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "随", upper: "兑", lower: "震",
        guaci: "元亨利贞，无咎。", guaciBaihua: "大为亨通，利于守正，无过失。",
        yao: [
            MeihuaYao(title: "初九", text: "官有渝，贞吉。出门交有功。", baihua: "主事者有变，守正则吉。出门交际有功。"),
            MeihuaYao(title: "六二", text: "系小子，失丈夫。", baihua: "系住了小子，失去了丈夫。"),
            MeihuaYao(title: "六三", text: "系丈夫，失小子。随有求得，利居贞。", baihua: "系住了丈夫，失去了小子。随从他人而有所求得，利于安居守正。"),
            MeihuaYao(title: "九四", text: "随有获，贞凶。有孚在道，以明，何咎。", baihua: "随从他人而有所获，守正则凶。心怀诚信在正道上，以明智行事，有何过失。"),
            MeihuaYao(title: "九五", text: "孚于嘉，吉。", baihua: "诚信于美善，吉。"),
            MeihuaYao(title: "上六", text: "拘系之，乃从；维之，王用亨于西山。", baihua: "拘系他，他才跟从；维系他，君王用以祭享于西山。")
        ], yong: nil),

    MeihuaHexagram(name: "蛊", upper: "艮", lower: "巽",
        guaci: "元亨，利涉大川。先甲三日，后甲三日。", guaciBaihua: "大为亨通，利于渡大河。甲日前三日、甲日后三日，宜审慎行事。",
        yao: [
            MeihuaYao(title: "初六", text: "干父之蛊，有子，考无咎，厉，终吉。", baihua: "整治父辈的弊病，有能干的儿子，父辈无过失，虽危厉，最终吉。"),
            MeihuaYao(title: "九二", text: "干母之蛊，不可贞。", baihua: "整治母辈的弊病，不可过于守正。"),
            MeihuaYao(title: "九三", text: "干父之蛊，小有悔，无大咎。", baihua: "整治父辈的弊病，小有悔恨，无大过失。"),
            MeihuaYao(title: "六四", text: "裕父之蛊，往见吝。", baihua: "宽容父辈的弊病，前往则见遗憾。"),
            MeihuaYao(title: "六五", text: "干父之蛊，用誉。", baihua: "整治父辈的弊病，因而得美誉。"),
            MeihuaYao(title: "上九", text: "不事王侯，高尚其事。", baihua: "不侍奉王侯，高尚其行。")
        ], yong: nil),

    MeihuaHexagram(name: "临", upper: "坤", lower: "兑",
        guaci: "元，亨，利，贞。至于八月有凶。", guaciBaihua: "大，亨通，利于守正。到了八月有凶。",
        yao: [
            MeihuaYao(title: "初九", text: "咸临，贞吉。", baihua: "以感应之心临下，守正则吉。"),
            MeihuaYao(title: "九二", text: "咸临，吉，无不利。", baihua: "以感应之心临下，吉，无所不利。"),
            MeihuaYao(title: "六三", text: "甘临，无攸利。既忧之，无咎。", baihua: "以甘言临下，无所利；既已忧虑，便无过失。"),
            MeihuaYao(title: "六四", text: "至临，无咎。", baihua: "以至诚临下，无过失。"),
            MeihuaYao(title: "六五", text: "知临，大君之宜，吉。", baihua: "以明智临下，是大君所宜，吉。"),
            MeihuaYao(title: "上六", text: "敦临，吉，无咎。", baihua: "以敦厚临下，吉，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "观", upper: "巽", lower: "坤",
        guaci: "盥而不荐，有孚顒若。", guaciBaihua: "祭祀时洗手而不进献，心怀诚信而肃穆恭敬。",
        yao: [
            MeihuaYao(title: "初六", text: "童观，小人无咎，君子吝。", baihua: "如童子般浅观，小人无过失，君子有遗憾。"),
            MeihuaYao(title: "六二", text: "闚观，利女贞。", baihua: "从门缝窥观，利于女子守正。"),
            MeihuaYao(title: "六三", text: "观我生，进退。", baihua: "观察我的所作所为，以定进退。"),
            MeihuaYao(title: "六四", text: "观国之光，利用宾于王。", baihua: "观察国家的光华，利于作王的宾客。"),
            MeihuaYao(title: "九五", text: "观我生，君子无咎。", baihua: "观察我的所作所为，君子无过失。"),
            MeihuaYao(title: "上九", text: "观其生，君子无咎。", baihua: "观察他的所作所为，君子无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "噬嗑", upper: "离", lower: "震",
        guaci: "亨，利用狱。", guaciBaihua: "亨通，利于用刑狱。",
        yao: [
            MeihuaYao(title: "初九", text: "屦校灭趾，无咎。", baihua: "脚戴刑具、伤了脚趾，无过失。"),
            MeihuaYao(title: "六二", text: "噬肤灭鼻，无咎。", baihua: "咬噬肌肤、伤了鼻子，无过失。"),
            MeihuaYao(title: "六三", text: "噬腊肉，遇毒；小吝，无咎。", baihua: "咬噬腊肉，遇到毒物，小有遗憾，无过失。"),
            MeihuaYao(title: "九四", text: "噬干胏，得金矢，利艰贞，吉。", baihua: "咬噬带骨的干肉，得到金箭，利于艰难中守正，吉。"),
            MeihuaYao(title: "六五", text: "噬干肉，得黄金，贞厉，无咎。", baihua: "咬噬干肉，得到黄金，守正而危厉，无过失。"),
            MeihuaYao(title: "上九", text: "何校灭耳，凶。", baihua: "颈戴重枷、伤了耳朵，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "贲", upper: "艮", lower: "离",
        guaci: "亨，小利有攸往。", guaciBaihua: "亨通，小利于有所前往。",
        yao: [
            MeihuaYao(title: "初九", text: "贲其趾，舍车而徒。", baihua: "修饰脚趾，舍弃车子而徒步。"),
            MeihuaYao(title: "六二", text: "贲其须。", baihua: "修饰胡须。"),
            MeihuaYao(title: "九三", text: "贲如濡如，永贞吉。", baihua: "修饰得光润，永远守正则吉。"),
            MeihuaYao(title: "六四", text: "贲如皤如，白马翰如，匪寇婚媾。", baihua: "修饰得洁白，白马奔驰而来，不是盗寇，而是来求婚的。"),
            MeihuaYao(title: "六五", text: "贲于丘园，束帛戋戋，吝，终吉。", baihua: "修饰丘园，束帛虽少，有遗憾，最终吉。"),
            MeihuaYao(title: "上九", text: "白贲，无咎。", baihua: "以素白为饰，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "剥", upper: "艮", lower: "坤",
        guaci: "不利有攸往。", guaciBaihua: "不利于有所前往。",
        yao: [
            MeihuaYao(title: "初六", text: "剥床以足，蔑贞凶。", baihua: "剥落床足，蔑视正道则凶。"),
            MeihuaYao(title: "六二", text: "剥床以辨，蔑贞凶。", baihua: "剥落床边，蔑视正道则凶。"),
            MeihuaYao(title: "六三", text: "剥之，无咎。", baihua: "剥落而无过失。"),
            MeihuaYao(title: "六四", text: "剥床以肤，凶。", baihua: "剥落床面、伤及肌肤，凶。"),
            MeihuaYao(title: "六五", text: "贯鱼，以宫人宠，无不利。", baihua: "如贯鱼般依次进献，以宫人受宠，无所不利。"),
            MeihuaYao(title: "上九", text: "硕果不食，君子得舆，小人剥庐。", baihua: "大果不被吃掉，君子得到车舆，小人剥落庐舍。")
        ], yong: nil),

    MeihuaHexagram(name: "复", upper: "坤", lower: "震",
        guaci: "亨，出入无疾，朋来无咎。反复其道，七日来复，利有攸往。", guaciBaihua: "亨通，出入无疾病，朋友来而无过失。反复于其道，七日便返回，利于有所前往。",
        yao: [
            MeihuaYao(title: "初九", text: "不远复，无祗悔，元吉。", baihua: "不远便返回，无须悔恨，大吉。"),
            MeihuaYao(title: "六二", text: "休复，吉。", baihua: "安然返回，吉。"),
            MeihuaYao(title: "六三", text: "频复，厉，无咎。", baihua: "频繁返回，危厉，无过失。"),
            MeihuaYao(title: "六四", text: "中行独复。", baihua: "中道独行而返回。"),
            MeihuaYao(title: "六五", text: "敦复，无悔。", baihua: "敦厚返回，无悔恨。"),
            MeihuaYao(title: "上六", text: "迷复，凶，有灾眚。用行师，终有大败，以其国君凶，至于十年不克征。", baihua: "迷失而返回，凶，有灾祸。用以行军，最终大败，君王凶，十年不能出征。")
        ], yong: nil),

    MeihuaHexagram(name: "无妄", upper: "乾", lower: "震",
        guaci: "元亨，利贞。其匪正有眚，不利有攸往。", guaciBaihua: "大为亨通，利于守正。若有不正便有灾祸，不利于有所前往。",
        yao: [
            MeihuaYao(title: "初九", text: "无妄，往吉。", baihua: "不妄为，前往则吉。"),
            MeihuaYao(title: "六二", text: "不耕获，不菑畲，则利有攸往。", baihua: "不耕种而求收获，不开荒而求熟田，则利于有所前往。"),
            MeihuaYao(title: "六三", text: "无妄之灾，或系之牛，行人之得，邑人之灾。", baihua: "无妄之灾，或系牛被牵走，行人得牛，邑人遭灾。"),
            MeihuaYao(title: "九四", text: "可贞，无咎。", baihua: "可以守正，无过失。"),
            MeihuaYao(title: "九五", text: "无妄之疾，勿药有喜。", baihua: "无妄之疾，不用药而有喜。"),
            MeihuaYao(title: "上九", text: "无妄行有眚，无攸利。", baihua: "无妄而行却有灾祸，无所利。")
        ], yong: nil),

    MeihuaHexagram(name: "大畜", upper: "艮", lower: "乾",
        guaci: "利贞。不家食，吉。利涉大川。", guaciBaihua: "利于守正。不在家吃饭，吉，利于渡大河。",
        yao: [
            MeihuaYao(title: "初九", text: "有厉，利已。", baihua: "有危厉，利于停止。"),
            MeihuaYao(title: "九二", text: "舆说輹。", baihua: "车轮脱落。"),
            MeihuaYao(title: "九三", text: "良马逐，利艰贞。曰闲舆卫，利有攸往。", baihua: "良马竞逐，利于艰难中守正。练习车马防卫，利于有所前往。"),
            MeihuaYao(title: "六四", text: "童牛之牿，元吉。", baihua: "给小牛加上横木，大吉。"),
            MeihuaYao(title: "六五", text: "豮豕之牙，吉。", baihua: "阉猪的獠牙，吉。"),
            MeihuaYao(title: "上九", text: "何天之衢，亨。", baihua: "通往天衢的大道，亨通。")
        ], yong: nil),

    MeihuaHexagram(name: "颐", upper: "艮", lower: "震",
        guaci: "贞吉。观颐，自求口实。", guaciBaihua: "守正则吉。观察颐养之道，自己求取口中食物。",
        yao: [
            MeihuaYao(title: "初九", text: "舍尔灵龟，观我朵颐，凶。", baihua: "舍弃自己的灵龟，观我颐颔而动，凶。"),
            MeihuaYao(title: "六二", text: "颠颐，拂经于丘颐，征凶。", baihua: "颠倒颐养，违背常道而求养于丘陵，出征凶。"),
            MeihuaYao(title: "六三", text: "拂颐，贞凶，十年勿用，无攸利。", baihua: "违背颐养之道，守正则凶，十年不可用，无所利。"),
            MeihuaYao(title: "六四", text: "颠颐，吉。虎视眈眈，其欲逐逐，无咎。", baihua: "颠倒颐养，吉。如虎视眈眈，其欲望急切，无过失。"),
            MeihuaYao(title: "六五", text: "拂经，居贞吉，不可涉大川。", baihua: "违背常道，安居守正则吉，不可渡大河。"),
            MeihuaYao(title: "上九", text: "由颐，厉吉，利涉大川。", baihua: "由颐养而行，危厉而吉，利于渡大河。")
        ], yong: nil),

    MeihuaHexagram(name: "大过", upper: "兑", lower: "巽",
        guaci: "栋桡，利有攸往，亨。", guaciBaihua: "栋梁弯曲，利于有所前往，亨通。",
        yao: [
            MeihuaYao(title: "初六", text: "藉用白茅，无咎。", baihua: "垫用白茅，无过失。"),
            MeihuaYao(title: "九二", text: "枯杨生稊，老夫得其女妻，无不利。", baihua: "枯杨生出新芽，老夫娶得年轻妻子，无所不利。"),
            MeihuaYao(title: "九三", text: "栋桡，凶。", baihua: "栋梁弯曲，凶。"),
            MeihuaYao(title: "九四", text: "栋隆，吉。有它，吝。", baihua: "栋梁隆起，吉。若有他求，则有遗憾。"),
            MeihuaYao(title: "九五", text: "枯杨生华，老妇得士夫，无咎无誉。", baihua: "枯杨开花，老妇嫁得士夫，无过失也无声誉。"),
            MeihuaYao(title: "上六", text: "过涉灭顶，凶，无咎。", baihua: "涉水过深、灭顶，凶，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "坎", upper: "坎", lower: "坎",
        guaci: "习坎，有孚，维心亨，行有尚。", guaciBaihua: "重重险陷，心怀诚信，惟心亨通，行事有所崇尚。",
        yao: [
            MeihuaYao(title: "初六", text: "习坎，入于坎窞，凶。", baihua: "重重险陷，落入深坑，凶。"),
            MeihuaYao(title: "九二", text: "坎有险，求小得。", baihua: "险陷中有险，求小的可得。"),
            MeihuaYao(title: "六三", text: "来之坎坎，险且枕，入于坎窞，勿用。", baihua: "来去皆是险陷，险而又险，落入深坑，不可用。"),
            MeihuaYao(title: "六四", text: "樽酒簋，贰用缶，纳约自牖，终无咎。", baihua: "一樽酒、一簋食，再用瓦缶，从窗户纳约，最终无过失。"),
            MeihuaYao(title: "九五", text: "坎不盈，祗既平，无咎。", baihua: "险陷未满，刚刚平满，无过失。"),
            MeihuaYao(title: "上六", text: "系用徽纆，置于丛棘，三岁不得，凶。", baihua: "用绳索捆绑，置于丛棘之中，三年不得脱，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "离", upper: "离", lower: "离",
        guaci: "利贞，亨。畜牝牛，吉。", guaciBaihua: "利于守正，亨通。蓄养牝牛，吉。",
        yao: [
            MeihuaYao(title: "初九", text: "履错然，敬之，无咎。", baihua: "行走错杂，恭敬谨慎，无过失。"),
            MeihuaYao(title: "六二", text: "黄离，元吉。", baihua: "黄色附丽，大吉。"),
            MeihuaYao(title: "九三", text: "日昃之离，不鼓缶而歌，则大耋之嗟，凶。", baihua: "日落西山之时，不击缶歌唱，便是老耋的嗟叹，凶。"),
            MeihuaYao(title: "九四", text: "突如其来如，焚如，死如，弃如。", baihua: "突然到来，如火焚烧，如死寂，如被抛弃。"),
            MeihuaYao(title: "六五", text: "出涕沱若，戚嗟若，吉。", baihua: "涕泪滂沱，悲戚嗟叹，吉。"),
            MeihuaYao(title: "上九", text: "王用出征，有嘉折首，获匪其丑，无咎。", baihua: "君王用以出征，嘉奖斩首之功，俘获非其同类，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "咸", upper: "兑", lower: "艮",
        guaci: "亨，利贞。取女吉。", guaciBaihua: "亨通，利于守正，娶女吉。",
        yao: [
            MeihuaYao(title: "初六", text: "咸其拇。", baihua: "感应于脚趾。"),
            MeihuaYao(title: "六二", text: "咸其腓，凶，居吉。", baihua: "感应于小腿，凶，安居则吉。"),
            MeihuaYao(title: "九三", text: "咸其股，执其随，往吝。", baihua: "感应于大腿，执着于跟随，前往有遗憾。"),
            MeihuaYao(title: "九四", text: "贞吉，悔亡。憧憧往来，朋从尔思。", baihua: "守正则吉，悔恨消亡。心意往来不定，朋友顺从你的思虑。"),
            MeihuaYao(title: "九五", text: "咸其脢，无悔。", baihua: "感应于背脊，无悔恨。"),
            MeihuaYao(title: "上六", text: "咸其辅颊舌。", baihua: "感应于口颊舌。")
        ], yong: nil),

    MeihuaHexagram(name: "恒", upper: "震", lower: "巽",
        guaci: "亨，无咎，利贞，利有攸往。", guaciBaihua: "亨通，无过失，利于守正，利于有所前往。",
        yao: [
            MeihuaYao(title: "初六", text: "浚恒，贞凶，无攸利。", baihua: "深求恒久，守正则凶，无所利。"),
            MeihuaYao(title: "九二", text: "悔亡。", baihua: "悔恨消亡。"),
            MeihuaYao(title: "九三", text: "不恒其德，或承之羞，贞吝。", baihua: "不能恒守其德，或招羞辱，守正则有遗憾。"),
            MeihuaYao(title: "九四", text: "田无禽。", baihua: "田中无禽。"),
            MeihuaYao(title: "六五", text: "恒其德，贞，妇人吉，夫子凶。", baihua: "恒守其德，守正，妇人吉，男子凶。"),
            MeihuaYao(title: "上六", text: "振恒，凶。", baihua: "振动恒久，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "遁", upper: "乾", lower: "艮",
        guaci: "亨，小利贞。", guaciBaihua: "亨通，小利于守正。",
        yao: [
            MeihuaYao(title: "初六", text: "遁尾，厉，勿用有攸往。", baihua: "退避在后，危厉，不宜有所前往。"),
            MeihuaYao(title: "六二", text: "执之用黄牛之革，莫之胜说。", baihua: "用黄牛皮革紧紧系住，无人能解开。"),
            MeihuaYao(title: "九三", text: "系遁，有疾厉；畜臣妾，吉。", baihua: "被系住而退避，有疾病危厉；蓄养臣妾则吉。"),
            MeihuaYao(title: "九四", text: "好遁，君子吉，小人否。", baihua: "喜好退避，君子吉，小人闭塞。"),
            MeihuaYao(title: "九五", text: "嘉遁，贞吉。", baihua: "嘉美的退避，守正则吉。"),
            MeihuaYao(title: "上九", text: "肥遁，无不利。", baihua: "远遁高飞，无所不利。")
        ], yong: nil),

    MeihuaHexagram(name: "大壮", upper: "震", lower: "乾",
        guaci: "利贞。", guaciBaihua: "利于守正。",
        yao: [
            MeihuaYao(title: "初九", text: "壮于趾，征凶，有孚。", baihua: "强壮于脚趾，出征凶，但心怀诚信。"),
            MeihuaYao(title: "九二", text: "贞吉。", baihua: "守正则吉。"),
            MeihuaYao(title: "九三", text: "小人用壮，君子用罔，贞厉。羝羊触藩，羸其角。", baihua: "小人用强壮，君子不用强，守正而危厉。如公羊触藩篱，角被困住。"),
            MeihuaYao(title: "九四", text: "贞吉，悔亡。藩决不羸，壮于大舆之輹。", baihua: "守正则吉，悔恨消亡。藩篱决开而不被困，强壮于大车的车辐。"),
            MeihuaYao(title: "六五", text: "丧羊于易，无悔。", baihua: "在交易场上丢失羊，无悔恨。"),
            MeihuaYao(title: "上六", text: "羝羊触藩，不能退，不能遂，无攸利，艰则吉。", baihua: "公羊触藩，不能退，不能进，无所利，艰难中谨慎则吉。")
        ], yong: nil),

    MeihuaHexagram(name: "晋", upper: "离", lower: "坤",
        guaci: "康侯用锡马蕃庶，昼日三接。", guaciBaihua: "安康的侯王受赐马匹众多，白日多次接见。",
        yao: [
            MeihuaYao(title: "初六", text: "晋如摧如，贞吉。罔孚，裕无咎。", baihua: "前进又受摧抑，守正则吉。未得信任，宽裕待之则无过失。"),
            MeihuaYao(title: "六二", text: "晋如愁如，贞吉。受兹介福，于其王母。", baihua: "前进而忧愁，守正则吉。受此大福，在于王母。"),
            MeihuaYao(title: "六三", text: "众允，悔亡。", baihua: "众人信从，悔恨消亡。"),
            MeihuaYao(title: "九四", text: "晋如鼫鼠，贞厉。", baihua: "前进如鼫鼠，守正而危厉。"),
            MeihuaYao(title: "六五", text: "悔亡，失得勿恤，往吉，无不利。", baihua: "悔恨消亡，得失不必忧虑，前往则吉，无所不利。"),
            MeihuaYao(title: "上九", text: "晋其角，维用伐邑，厉吉，无咎，贞吝。", baihua: "前进到了角尖，只宜讨伐邑国，危厉而吉，无过失，守正则有遗憾。")
        ], yong: nil),

    MeihuaHexagram(name: "明夷", upper: "坤", lower: "离",
        guaci: "利艰贞。", guaciBaihua: "利于艰难中守正。",
        yao: [
            MeihuaYao(title: "初九", text: "明夷于飞，垂其翼。君子于行，三日不食。有攸往，主人有言。", baihua: "光明受损而飞翔，垂下翅膀。君子出行，三日不食。有所前往，主人有言语。"),
            MeihuaYao(title: "六二", text: "明夷，夷于左股，用拯马壮，吉。", baihua: "光明受损，伤及左股，用壮马拯救，吉。"),
            MeihuaYao(title: "九三", text: "明夷于南狩，得其大首，不可疾贞。", baihua: "光明受损而南狩，获得大首，不可急于守正。"),
            MeihuaYao(title: "六四", text: "入于左腹，获明夷之心，出于门庭。", baihua: "进入左腹，获得受损光明之心，走出门庭。"),
            MeihuaYao(title: "六五", text: "箕子之明夷，利贞。", baihua: "如箕子般光明受损，利于守正。"),
            MeihuaYao(title: "上六", text: "不明晦，初登于天，后入于地。", baihua: "不明而昏暗，初登于天，后入于地。")
        ], yong: nil),

    MeihuaHexagram(name: "家人", upper: "巽", lower: "离",
        guaci: "利女贞。", guaciBaihua: "利于女子守正。",
        yao: [
            MeihuaYao(title: "初九", text: "闲有家，悔亡。", baihua: "防范于有家之时，悔恨消亡。"),
            MeihuaYao(title: "六二", text: "无攸遂，在中馈，贞吉。", baihua: "无所遂求，在于主中馈，守正则吉。"),
            MeihuaYao(title: "九三", text: "家人嗃嗃，悔厉，吉。妇子嘻嘻，终吝。", baihua: "家人严厉呵斥，悔而危厉，吉。妇人孩子嘻笑，最终有遗憾。"),
            MeihuaYao(title: "六四", text: "富家，大吉。", baihua: "家道富足，大吉。"),
            MeihuaYao(title: "九五", text: "王假有家，勿恤，吉。", baihua: "君王至于有家，不必忧虑，吉。"),
            MeihuaYao(title: "上九", text: "有孚威如，终吉。", baihua: "心怀诚信而有威严，最终吉。")
        ], yong: nil),

    MeihuaHexagram(name: "睽", upper: "离", lower: "兑",
        guaci: "小事吉。", guaciBaihua: "小事吉。",
        yao: [
            MeihuaYao(title: "初九", text: "悔亡，丧马勿逐，自复。见恶人，无咎。", baihua: "悔恨消亡，丢失的马不必追逐，自会回来。见到恶人，无过失。"),
            MeihuaYao(title: "九二", text: "遇主于巷，无咎。", baihua: "在巷中遇见主人，无过失。"),
            MeihuaYao(title: "六三", text: "见舆曳，其牛掣，其人天且劓，无初有终。", baihua: "见车被拖曳，牛被牵制，那人被剃发、割鼻，无初而有终。"),
            MeihuaYao(title: "九四", text: "睽孤，遇元夫，交孚，厉，无咎。", baihua: "乖离孤独，遇见善人，交相诚信，危厉，无过失。"),
            MeihuaYao(title: "六五", text: "悔亡，厥宗噬肤，往何咎。", baihua: "悔恨消亡，同宗噬肤而合，前往有何过失。"),
            MeihuaYao(title: "上九", text: "睽孤，见豕负涂，载鬼一车。先张之弧，后说之弧，匪寇婚媾，往遇雨则吉。", baihua: "乖离孤独，见猪负泥涂，车载鬼魅。先张弓，后放弓，不是盗寇，而是来求婚的，前往遇雨则吉。")
        ], yong: nil),

    MeihuaHexagram(name: "蹇", upper: "坎", lower: "艮",
        guaci: "利西南，不利东北。利见大人，贞吉。", guaciBaihua: "利于西南，不利于东北。利于见大人，守正则吉。",
        yao: [
            MeihuaYao(title: "初六", text: "往蹇，来誉。", baihua: "前往艰难，回来有誉。"),
            MeihuaYao(title: "六二", text: "王臣蹇蹇，匪躬之故。", baihua: "王臣艰难重重，不是为自身之故。"),
            MeihuaYao(title: "九三", text: "往蹇，来反。", baihua: "前往艰难，回来反顾。"),
            MeihuaYao(title: "六四", text: "往蹇，来连。", baihua: "前往艰难，回来相连。"),
            MeihuaYao(title: "九五", text: "大蹇，朋来。", baihua: "大艰难，朋友来助。"),
            MeihuaYao(title: "上六", text: "往蹇，来硕，吉。利见大人。", baihua: "前往艰难，回来大有收获，吉，利于见大人。")
        ], yong: nil),

    MeihuaHexagram(name: "解", upper: "震", lower: "坎",
        guaci: "利西南。无所往，其来复吉。有攸往，夙吉。", guaciBaihua: "利于西南。无所前往，其来复则吉。有所前往，早行则吉。",
        yao: [
            MeihuaYao(title: "初六", text: "无咎。", baihua: "无过失。"),
            MeihuaYao(title: "九二", text: "田获三狐，得黄矢，贞吉。", baihua: "田猎获三只狐狸，得到黄色箭矢，守正则吉。"),
            MeihuaYao(title: "六三", text: "负且乘，致寇至，贞吝。", baihua: "背负重物又乘车，招致盗寇，守正有遗憾。"),
            MeihuaYao(title: "九四", text: "解而拇，朋至斯孚。", baihua: "解开脚拇，朋友至而诚信。"),
            MeihuaYao(title: "六五", text: "君子维有解，吉。有孚于小人。", baihua: "君子维系解脱，吉。对小人也有诚信。"),
            MeihuaYao(title: "上六", text: "公用射隼于高墉之上，获之，无不利。", baihua: "公侯射高墙上的隼鸟而获之，无所不利。")
        ], yong: nil),

    MeihuaHexagram(name: "损", upper: "艮", lower: "兑",
        guaci: "有孚，元吉，无咎，可贞，利有攸往。曷之用，二簋可用享。", guaciBaihua: "心怀诚信，大吉，无过失，可以守正，利于有所前往。用什么祭享呢？两簋便可祭享。",
        yao: [
            MeihuaYao(title: "初九", text: "已事遄往，无咎，酌损之。", baihua: "完成事情速速前往，无过失，斟酌损益。"),
            MeihuaYao(title: "九二", text: "利贞，征凶，弗损，益之。", baihua: "利于守正，出征凶，不损己而益人。"),
            MeihuaYao(title: "六三", text: "三人行则损一人，一人行则得其友。", baihua: "三人同行则损一人，一人独行则得其友。"),
            MeihuaYao(title: "六四", text: "损其疾，使遄有喜，无咎。", baihua: "减损疾病，使其速愈有喜，无过失。"),
            MeihuaYao(title: "六五", text: "或益之，十朋之龟弗克违，元吉。", baihua: "或有人益助，十朋之龟也不能违背，大吉。"),
            MeihuaYao(title: "上九", text: "弗损益之，无咎，贞吉，利有攸往，得臣无家。", baihua: "不损己而益人，无过失，守正则吉，利于有所前往，得臣而不居家。")
        ], yong: nil),

    MeihuaHexagram(name: "益", upper: "巽", lower: "震",
        guaci: "利有攸往，利涉大川。", guaciBaihua: "利于有所前往，利于渡大河。",
        yao: [
            MeihuaYao(title: "初九", text: "利用为大作，元吉，无咎。", baihua: "利于大有作为，大吉，无过失。"),
            MeihuaYao(title: "六二", text: "或益之十朋之龟，弗克违，永贞吉。王用享于帝，吉。", baihua: "或有人益助十朋之龟也不能违背，永守正则吉。君王用以祭享上帝，吉。"),
            MeihuaYao(title: "六三", text: "益之用凶事，无咎。有孚中行，告公用圭。", baihua: "益助用于凶事，无过失。心怀诚信而行中道，告公而用圭。"),
            MeihuaYao(title: "六四", text: "中行，告公从。利用为依迁国。", baihua: "行中道，告公而从。利于依附迁国。"),
            MeihuaYao(title: "九五", text: "有孚惠心，勿问元吉，有孚惠我德。", baihua: "心怀诚信而惠及人心，不必占问，大吉，诚信惠及我的德行。"),
            MeihuaYao(title: "上九", text: "莫益之，或击之，立心勿恒，凶。", baihua: "无人益助，或有人击打，立心不恒，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "夬", upper: "兑", lower: "乾",
        guaci: "扬于王庭，孚号，有厉，告自邑，不利即戎，利有攸往。", guaciBaihua: "扬言于王庭，诚信呼号，有危厉，告于自邑，不利于立即动武，利于有所前往。",
        yao: [
            MeihuaYao(title: "初九", text: "壮于前趾，往不胜为咎。", baihua: "强壮于前趾，前往不能胜便是过失。"),
            MeihuaYao(title: "九二", text: "惕号，莫夜有戎，勿恤。", baihua: "警惕呼号，莫夜有兵戎，不必忧虑。"),
            MeihuaYao(title: "九三", text: "壮于頄，有凶。君子夬夬，独行遇雨若濡，有愠，无咎。", baihua: "强壮于面颊，有凶。君子果决独行，遇雨沾湿，有愠怒，无过失。"),
            MeihuaYao(title: "九四", text: "臀无肤，其行次且。牵羊悔亡，闻言不信。", baihua: "臀部无皮，行走艰难。牵羊则悔亡，听到言语却不信。"),
            MeihuaYao(title: "九五", text: "苋陆夬夬，中行无咎。", baihua: "如苋陆般果决，中道而行，无过失。"),
            MeihuaYao(title: "上六", text: "无号，终有凶。", baihua: "无处呼号，最终有凶。")
        ], yong: nil),

    MeihuaHexagram(name: "姤", upper: "乾", lower: "巽",
        guaci: "女壮，勿用取女。", guaciBaihua: "女子强壮，不宜娶女。",
        yao: [
            MeihuaYao(title: "初六", text: "系于金柅，贞吉，有攸往，见凶。羸豕孚蹢躅。", baihua: "系于金车闩，守正则吉，有所前往则见凶。瘦弱的猪诚信地徘徊。"),
            MeihuaYao(title: "九二", text: "包有鱼，无咎，不利宾。", baihua: "包中有鱼，无过失，不利于宾客。"),
            MeihuaYao(title: "九三", text: "臀无肤，其行次且，厉，无大咎。", baihua: "臀部无皮，行走艰难，危厉，无大过失。"),
            MeihuaYao(title: "九四", text: "包无鱼，起凶。", baihua: "包中无鱼，兴起则凶。"),
            MeihuaYao(title: "九五", text: "以杞包瓜，含章，有陨自天。", baihua: "以杞柳包瓜，内含文采，有物自天陨落。"),
            MeihuaYao(title: "上九", text: "姤其角，吝，无咎。", baihua: "相遇于角端，有遗憾，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "萃", upper: "兑", lower: "坤",
        guaci: "亨，王假有庙，利见大人，亨，利贞。用大牲吉，利有攸往。", guaciBaihua: "亨通，君王至于宗庙，利于见大人，亨通，利于守正。用大牲祭祀吉，利于有所前往。",
        yao: [
            MeihuaYao(title: "初六", text: "有孚不终，乃乱乃萃，若号一握为笑，勿恤，往无咎。", baihua: "诚信不能终，聚合纷乱，若呼号一声便化为笑，不必忧虑，前往无过失。"),
            MeihuaYao(title: "六二", text: "引吉，无咎，孚乃利用禴。", baihua: "引而前行则吉，无过失，诚信则利于薄祭。"),
            MeihuaYao(title: "六三", text: "萃如嗟如，无攸利。往无咎，小吝。", baihua: "聚合而嗟叹，无所利，前往无过失，小有遗憾。"),
            MeihuaYao(title: "九四", text: "大吉，无咎。", baihua: "大吉，无过失。"),
            MeihuaYao(title: "九五", text: "萃有位，无咎。匪孚，元永贞，悔亡。", baihua: "聚合而有位，无过失。若无诚信，大而永守正则悔亡。"),
            MeihuaYao(title: "上六", text: "赍咨涕洟，无咎。", baihua: "咨嗟涕泪，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "升", upper: "坤", lower: "巽",
        guaci: "元亨，用见大人，勿恤，南征吉。", guaciBaihua: "大为亨通，宜见大人，不必忧虑，南征吉。",
        yao: [
            MeihuaYao(title: "初六", text: "允升，大吉。", baihua: "诚信上升，大吉。"),
            MeihuaYao(title: "九二", text: "孚乃利用禴，无咎。", baihua: "诚信则利于薄祭，无过失。"),
            MeihuaYao(title: "九三", text: "升虚邑。", baihua: "上升于空虚之邑。"),
            MeihuaYao(title: "六四", text: "王用亨于岐山，吉，无咎。", baihua: "君王用以祭享于岐山，吉，无过失。"),
            MeihuaYao(title: "六五", text: "贞吉，升阶。", baihua: "守正则吉，升上台阶。"),
            MeihuaYao(title: "上六", text: "冥升，利于不息之贞。", baihua: "昏暗中上升，利于不息地守正。")
        ], yong: nil),

    MeihuaHexagram(name: "困", upper: "兑", lower: "坎",
        guaci: "亨，贞，大人吉，无咎。有言不信。", guaciBaihua: "亨通，守正，大人吉，无过失。有言语而不被相信。",
        yao: [
            MeihuaYao(title: "初六", text: "臀困于株木，入于幽谷，三岁不觌。", baihua: "臀困于树桩，进入幽谷，三年不见天日。"),
            MeihuaYao(title: "九二", text: "困于酒食，朱绂方来，利用享祀，征凶，无咎。", baihua: "困于酒食，朱色蔽膝方来，利于祭祀，出征凶，无过失。"),
            MeihuaYao(title: "六三", text: "困于石，据于蒺蔾，入于其宫，不见其妻，凶。", baihua: "困于石上，据于蒺藜，进入其宫，不见其妻，凶。"),
            MeihuaYao(title: "九四", text: "来徐徐，困于金车，吝，有终。", baihua: "来得缓慢，困于金车，有遗憾，有终。"),
            MeihuaYao(title: "九五", text: "劓刖，困于赤绂，乃徐有说，利用祭祀。", baihua: "割鼻断足，困于赤色蔽膝，渐渐有所解脱，利于祭祀。"),
            MeihuaYao(title: "上六", text: "困于葛藟，于臲卼，曰动悔。有悔，征吉。", baihua: "困于葛藤，处于危不安之地，说动则悔。有悔，出征吉。")
        ], yong: nil),

    MeihuaHexagram(name: "井", upper: "坎", lower: "巽",
        guaci: "改邑不改井，无丧无得。往来井井，汔至，亦未繘井，羸其瓶，凶。", guaciBaihua: "改邑而不改井，无丧失也无所得。往来于井，几乎到井边，又未及汲水，瓶子破损，凶。",
        yao: [
            MeihuaYao(title: "初六", text: "井泥不食，旧井无禽。", baihua: "井底泥污不可食，旧井无禽鸟。"),
            MeihuaYao(title: "九二", text: "井谷射鲋，瓮敝漏。", baihua: "井底射鲋鱼，瓮破漏水。"),
            MeihuaYao(title: "九三", text: "井渫不食，为我心恻，可用汲，王明，并受其福。", baihua: "井已淘净却无人食，令我心痛，可以汲用，君王明智，并受其福。"),
            MeihuaYao(title: "六四", text: "井甃，无咎。", baihua: "井壁修砌，无过失。"),
            MeihuaYao(title: "九五", text: "井冽，寒泉食。", baihua: "井水清冽，寒泉可食。"),
            MeihuaYao(title: "上六", text: "井收勿幕，有孚元吉。", baihua: "汲水而不盖井，有诚信，大吉。")
        ], yong: nil),

    MeihuaHexagram(name: "革", upper: "兑", lower: "离",
        guaci: "巳日乃孚，元亨，利贞，悔亡。", guaciBaihua: "巳日才有诚信，大为亨通，利于守正，悔恨消亡。",
        yao: [
            MeihuaYao(title: "初九", text: "巩用黄牛之革。", baihua: "用黄牛皮革牢固束缚。"),
            MeihuaYao(title: "六二", text: "巳日乃革之，征吉，无咎。", baihua: "巳日才变革，出征吉，无过失。"),
            MeihuaYao(title: "九三", text: "征凶，贞厉，革言三就，有孚。", baihua: "出征凶，守正危厉，变革之言三次成就，方有诚信。"),
            MeihuaYao(title: "九四", text: "悔亡。有孚改命，吉。", baihua: "悔恨消亡。心怀诚信而改命，吉。"),
            MeihuaYao(title: "九五", text: "大人虎变，未占有孚。", baihua: "大人如虎般变革，未占已有诚信。"),
            MeihuaYao(title: "上六", text: "君子豹变，小人革面，征凶。居贞吉。", baihua: "君子如豹般变革，小人改变面目，出征凶，安居守正则吉。")
        ], yong: nil),

    MeihuaHexagram(name: "鼎", upper: "离", lower: "巽",
        guaci: "元吉，亨。", guaciBaihua: "大吉，亨通。",
        yao: [
            MeihuaYao(title: "初六", text: "鼎颠趾，利出否，得妾以其子，无咎。", baihua: "鼎颠覆脚趾，利于倒出秽物，得妾及其子，无过失。"),
            MeihuaYao(title: "九二", text: "鼎有实，我仇有疾，不我能即，吉。", baihua: "鼎中有实物，我的仇人有疾病，不能接近我，吉。"),
            MeihuaYao(title: "九三", text: "鼎耳革，其行塞，雉膏不食，方雨亏悔，终吉。", baihua: "鼎耳变革，行动受阻，雉膏不食，方雨而悔损，最终吉。"),
            MeihuaYao(title: "九四", text: "鼎折足，覆公餗，其形渥，凶。", baihua: "鼎折断足，倾覆公侯的美食，形体沾污，凶。"),
            MeihuaYao(title: "六五", text: "鼎黄耳，金铉，利贞。", baihua: "鼎有黄耳、金铉，利于守正。"),
            MeihuaYao(title: "上九", text: "鼎玉铉，大吉，无不利。", baihua: "鼎有玉铉，大吉，无所不利。")
        ], yong: nil),

    MeihuaHexagram(name: "震", upper: "震", lower: "震",
        guaci: "亨，震来虩虩，笑言哑哑。震惊百里，不丧匕鬯。", guaciBaihua: "亨通，雷来时恐惧，笑言和乐。雷惊百里，不失匕鬯。",
        yao: [
            MeihuaYao(title: "初九", text: "震来虩虩，后笑言哑哑，吉。", baihua: "雷来时恐惧，后来笑言和乐，吉。"),
            MeihuaYao(title: "六二", text: "震来厉，亿丧贝，跻于九陵，勿逐，七日得。", baihua: "雷来危厉，丧失大量财贝，登上九陵，不必追逐，七日可得。"),
            MeihuaYao(title: "六三", text: "震苏苏，震行无眚。", baihua: "雷震而苏醒，雷行而无灾祸。"),
            MeihuaYao(title: "九四", text: "震遂泥。", baihua: "雷震陷入泥中。"),
            MeihuaYao(title: "六五", text: "震往来厉，亿无丧，有事。", baihua: "雷震往来危厉，大量财物无丧，有事可为。"),
            MeihuaYao(title: "上六", text: "震索索，视矍矍，征凶。震不于其躬，于其邻，无咎。婚媾有言。", baihua: "雷震索索，视瞻惊惧，出征凶。雷震不在自身，在于邻人，无过失。婚媾有言语。")
        ], yong: nil),

    MeihuaHexagram(name: "艮", upper: "艮", lower: "艮",
        guaci: "艮其背，不获其身，行其庭，不见其人，无咎。", guaciBaihua: "止于背，不获其身，行于庭中，不见其人，无过失。",
        yao: [
            MeihuaYao(title: "初六", text: "艮其趾，无咎，利永贞。", baihua: "止于脚趾，无过失，利于永远守正。"),
            MeihuaYao(title: "六二", text: "艮其腓，不拯其随，其心不快。", baihua: "止于小腿，不能拯救跟随者，其心不快。"),
            MeihuaYao(title: "九三", text: "艮其限，列其夤，厉薰心。", baihua: "止于腰际，列其脊肉，危厉熏心。"),
            MeihuaYao(title: "六四", text: "艮其身，无咎。", baihua: "止于身体，无过失。"),
            MeihuaYao(title: "六五", text: "艮其辅，言有序，悔亡。", baihua: "止于口辅，言语有序，悔恨消亡。"),
            MeihuaYao(title: "上九", text: "敦艮，吉。", baihua: "敦厚止静，吉。")
        ], yong: nil),

    MeihuaHexagram(name: "渐", upper: "巽", lower: "艮",
        guaci: "女归吉，利贞。", guaciBaihua: "女子出嫁吉，利于守正。",
        yao: [
            MeihuaYao(title: "初六", text: "鸿渐于干，小子厉，有言，无咎。", baihua: "鸿雁渐进于水边，小子危厉，有言语，无过失。"),
            MeihuaYao(title: "六二", text: "鸿渐于磐，饮食衎衎，吉。", baihua: "鸿雁渐进于磐石，饮食和乐，吉。"),
            MeihuaYao(title: "九三", text: "鸿渐于陆，夫征不复，妇孕不育，凶。利御寇。", baihua: "鸿雁渐进于陆地，丈夫出征不归，妇人怀孕不育，凶，利于抵御盗寇。"),
            MeihuaYao(title: "六四", text: "鸿渐于木，或得其桷，无咎。", baihua: "鸿雁渐进于树木，或得其桷，无过失。"),
            MeihuaYao(title: "九五", text: "鸿渐于陵，妇三岁不孕，终莫之胜，吉。", baihua: "鸿雁渐进于丘陵，妇人三年不孕，最终无人能胜，吉。"),
            MeihuaYao(title: "上九", text: "鸿渐于陆，其羽可用为仪，吉。", baihua: "鸿雁渐进于陆地，其羽可用作仪饰，吉。")
        ], yong: nil),

    MeihuaHexagram(name: "归妹", upper: "震", lower: "兑",
        guaci: "征凶，无攸利。", guaciBaihua: "出征凶，无所利。",
        yao: [
            MeihuaYao(title: "初九", text: "归妹以娣，跛能履，征吉。", baihua: "嫁妹为娣，跛足能行，出征吉。"),
            MeihuaYao(title: "九二", text: "眇能视，利幽人之贞。", baihua: "瞎了一只眼还能看，利于幽居之人守正。"),
            MeihuaYao(title: "六三", text: "归妹以须，反归以娣。", baihua: "嫁妹为须，反归为娣。"),
            MeihuaYao(title: "九四", text: "归妹愆期，迟归有时。", baihua: "嫁妹误期，迟归有待。"),
            MeihuaYao(title: "六五", text: "帝乙归妹，其君之袂，不如其娣之袂良。月几望，吉。", baihua: "帝乙嫁妹，其君的衣袖不如娣的衣袖美。月近满，吉。"),
            MeihuaYao(title: "上六", text: "女承筐无实，士刲羊无血，无攸利。", baihua: "女子捧筐而无实物，男子宰羊而无血，无所利。")
        ], yong: nil),

    MeihuaHexagram(name: "丰", upper: "震", lower: "离",
        guaci: "亨，王假之，勿忧，宜日中。", guaciBaihua: "亨通，君王至于此，不必忧虑，宜于日中。",
        yao: [
            MeihuaYao(title: "初九", text: "遇其配主，虽旬无咎，往有尚。", baihua: "遇到相配之主，虽经十日无过失，前往有崇尚。"),
            MeihuaYao(title: "六二", text: "丰其蔀，日中见斗，往得疑疾，有孚发若，吉。", baihua: "丰大其遮蔽，日中见北斗，前往得疑疾，有诚信发露，吉。"),
            MeihuaYao(title: "九三", text: "丰其沛，日中见沬，折其右肱，无咎。", baihua: "丰大其幡，日中见微光，折断右臂，无过失。"),
            MeihuaYao(title: "九四", text: "丰其蔀，日中见斗，遇其夷主，吉。", baihua: "丰大其遮蔽，日中见北斗，遇到平易之主，吉。"),
            MeihuaYao(title: "六五", text: "来章，有庆誉，吉。", baihua: "文采来临，有庆誉，吉。"),
            MeihuaYao(title: "上六", text: "丰其屋，蔀其家，窥其户，阒其无人，三岁不觌，凶。", baihua: "丰大其屋，遮蔽其家，窥其门户，寂静无人，三年不见，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "旅", upper: "离", lower: "艮",
        guaci: "小亨，旅贞吉。", guaciBaihua: "小亨通，旅居守正则吉。",
        yao: [
            MeihuaYao(title: "初六", text: "旅琐琐，斯其所取灾。", baihua: "旅居琐细烦扰，此为取灾之道。"),
            MeihuaYao(title: "六二", text: "旅即次，怀其资，得童仆贞。", baihua: "旅居安于住处，怀藏资财，得童仆守正。"),
            MeihuaYao(title: "九三", text: "旅焚其次，丧其童仆，贞厉。", baihua: "旅居焚毁住处，丧失童仆，守正危厉。"),
            MeihuaYao(title: "九四", text: "旅于处，得其资斧，我心不快。", baihua: "旅居于处，得资财斧钺，我心不快。"),
            MeihuaYao(title: "六五", text: "射雉，一矢亡，终以誉命。", baihua: "射雉，一箭亡失，最终以誉命。"),
            MeihuaYao(title: "上九", text: "鸟焚其巢，旅人先笑后号啕，丧牛于易，凶。", baihua: "鸟焚其巢，旅人先笑后号啕，在交易场上丧牛，凶。")
        ], yong: nil),

    MeihuaHexagram(name: "巽", upper: "巽", lower: "巽",
        guaci: "小亨，利攸往，利见大人。", guaciBaihua: "小亨通，利于有所前往，利于见大人。",
        yao: [
            MeihuaYao(title: "初六", text: "进退，利武人之贞。", baihua: "进退不定，利于武人守正。"),
            MeihuaYao(title: "九二", text: "巽在床下，用史巫纷若，吉，无咎。", baihua: "顺伏于床下，用史巫纷纷祈祷，吉，无过失。"),
            MeihuaYao(title: "九三", text: "频巽，吝。", baihua: "频繁顺从，有遗憾。"),
            MeihuaYao(title: "六四", text: "悔亡，田获三品。", baihua: "悔恨消亡，田猎获三品。"),
            MeihuaYao(title: "九五", text: "贞吉悔亡，无不利，无初有终。先庚三日，后庚三日，吉。", baihua: "守正则吉，悔亡，无所不利，无初而有终。庚日前三日、庚日后三日，吉。"),
            MeihuaYao(title: "上九", text: "巽在床下，丧其资斧，贞凶。", baihua: "顺伏于床下，丧失资财斧钺，守正则凶。")
        ], yong: nil),

    MeihuaHexagram(name: "兑", upper: "兑", lower: "兑",
        guaci: "亨，利贞。", guaciBaihua: "亨通，利于守正。",
        yao: [
            MeihuaYao(title: "初九", text: "和兑，吉。", baihua: "和悦相说，吉。"),
            MeihuaYao(title: "九二", text: "孚兑，吉，悔亡。", baihua: "诚信相说，吉，悔恨消亡。"),
            MeihuaYao(title: "六三", text: "来兑，凶。", baihua: "前来相说，凶。"),
            MeihuaYao(title: "九四", text: "商兑未宁，介疾有喜。", baihua: "商量相说而未安宁，疾病得解而有喜。"),
            MeihuaYao(title: "九五", text: "孚于剥，有厉。", baihua: "诚信于剥落，有危厉。"),
            MeihuaYao(title: "上六", text: "引兑。", baihua: "引而相说。")
        ], yong: nil),

    MeihuaHexagram(name: "涣", upper: "巽", lower: "坎",
        guaci: "亨，王假有庙，利涉大川，利贞。", guaciBaihua: "亨通，君王至于宗庙，利于渡大河，利于守正。",
        yao: [
            MeihuaYao(title: "初六", text: "用拯马壮，吉。", baihua: "用壮马拯救，吉。"),
            MeihuaYao(title: "九二", text: "涣奔其机，悔亡。", baihua: "涣散奔向几案，悔恨消亡。"),
            MeihuaYao(title: "六三", text: "涣其躬，无悔。", baihua: "涣散自身，无悔恨。"),
            MeihuaYao(title: "六四", text: "涣其群，元吉。涣有丘，匪夷所思。", baihua: "涣散群聚，大吉。涣散而有丘，非平常所能思及。"),
            MeihuaYao(title: "九五", text: "涣汗其大号，涣王居，无咎。", baihua: "涣散汗水般的大号令，涣散王的居所，无过失。"),
            MeihuaYao(title: "上九", text: "涣其血，去逖出，无咎。", baihua: "涣散其血，远去而出，无过失。")
        ], yong: nil),

    MeihuaHexagram(name: "节", upper: "坎", lower: "兑",
        guaci: "亨，苦节，不可贞。", guaciBaihua: "亨通，苦节不可守正。",
        yao: [
            MeihuaYao(title: "初九", text: "不出户庭，无咎。", baihua: "不出门户庭院，无过失。"),
            MeihuaYao(title: "九二", text: "不出门庭，凶。", baihua: "不出门庭，凶。"),
            MeihuaYao(title: "六三", text: "不节若，则嗟若，无咎。", baihua: "不节制，则嗟叹，无过失。"),
            MeihuaYao(title: "六四", text: "安节，亨。", baihua: "安于节制，亨通。"),
            MeihuaYao(title: "九五", text: "甘节，吉；往有尚。", baihua: "甘于节制，吉，前往有崇尚。"),
            MeihuaYao(title: "上六", text: "苦节，贞凶，悔亡。", baihua: "苦于节制，守正则凶，悔恨消亡。")
        ], yong: nil),

    MeihuaHexagram(name: "中孚", upper: "巽", lower: "兑",
        guaci: "豚鱼吉，利涉大川，利贞。", guaciBaihua: "豚鱼吉，利于渡大河，利于守正。",
        yao: [
            MeihuaYao(title: "初九", text: "虞吉，有它不燕。", baihua: "虞度则吉，有他求则不安。"),
            MeihuaYao(title: "九二", text: "鸣鹤在阴，其子和之，我有好爵，吾与尔靡之。", baihua: "鹤鸣于阴，其子和应，我有好酒，与你共享。"),
            MeihuaYao(title: "六三", text: "得敌，或鼓或罢，或泣或歌。", baihua: "得敌，或鼓或罢，或泣或歌。"),
            MeihuaYao(title: "六四", text: "月几望，马匹亡，无咎。", baihua: "月近满，马匹亡失，无过失。"),
            MeihuaYao(title: "九五", text: "有孚挛如，无咎。", baihua: "诚信相连，无过失。"),
            MeihuaYao(title: "上九", text: "翰音登于天，贞凶。", baihua: "鸡鸣登于天，守正则凶。")
        ], yong: nil),

    MeihuaHexagram(name: "小过", upper: "震", lower: "艮",
        guaci: "亨，利贞，可小事，不可大事。飞鸟遗之音，不宜上，宜下。大吉。", guaciBaihua: "亨通，利于守正，可做小事，不可做大事。飞鸟遗下音声，不宜上，宜下，大吉。",
        yao: [
            MeihuaYao(title: "初六", text: "飞鸟以凶。", baihua: "飞鸟因飞而凶。"),
            MeihuaYao(title: "六二", text: "过其祖，遇其妣；不及其君，遇其臣，无咎。", baihua: "超过其祖，遇到其妣；不及君，遇到臣，无过失。"),
            MeihuaYao(title: "九三", text: "弗过防之，从或戕之，凶。", baihua: "不过分防备，跟从者或伤害之，凶。"),
            MeihuaYao(title: "九四", text: "无咎，弗过遇之。往厉，必戒。勿用永贞。", baihua: "无过失，不过分而相遇。前往危厉，必须戒备。不可永远守正。"),
            MeihuaYao(title: "六五", text: "密云不雨，自我西郊，公弋取彼在穴。", baihua: "密云不雨，云从西郊而来，公射取穴中之物。"),
            MeihuaYao(title: "上六", text: "弗遇过之，飞鸟离之，凶，是谓灾眚。", baihua: "不相遇而超过，飞鸟离去，凶，这就是灾祸。")
        ], yong: nil),

    MeihuaHexagram(name: "既济", upper: "坎", lower: "离",
        guaci: "亨，小利贞。初吉，终乱。", guaciBaihua: "亨通，小利于守正。初吉，终乱。",
        yao: [
            MeihuaYao(title: "初九", text: "曳其轮，濡其尾，无咎。", baihua: "拖曳车轮，沾湿尾巴，无过失。"),
            MeihuaYao(title: "六二", text: "妇丧其茀，勿逐，七日得。", baihua: "妇人丢失车盖，不必追逐，七日可得。"),
            MeihuaYao(title: "九三", text: "高宗伐鬼方，三年克之，小人勿用。", baihua: "高宗讨伐鬼方，三年克胜，小人不可用。"),
            MeihuaYao(title: "六四", text: "繻有衣袽，终日戒。", baihua: "船有衣袽以备漏，终日戒备。"),
            MeihuaYao(title: "九五", text: "东邻杀牛，不如西邻之禴祭，实受其福。", baihua: "东邻杀牛祭祀，不如西邻薄祭，实在受福。"),
            MeihuaYao(title: "上六", text: "濡其首，厉。", baihua: "沾湿其首，危厉。")
        ], yong: nil),

    MeihuaHexagram(name: "未济", upper: "离", lower: "坎",
        guaci: "亨。小狐汔济，濡其尾，无攸利。", guaciBaihua: "亨通。小狐几乎渡济，沾湿尾巴，无所利。",
        yao: [
            MeihuaYao(title: "初六", text: "濡其尾，吝。", baihua: "沾湿尾巴，有遗憾。"),
            MeihuaYao(title: "九二", text: "曳其轮，贞吉。", baihua: "拖曳车轮，守正则吉。"),
            MeihuaYao(title: "六三", text: "未济，征凶，利涉大川。", baihua: "未渡济，出征凶，利于渡大河。"),
            MeihuaYao(title: "九四", text: "贞吉，悔亡。震用伐鬼方，三年有赏于大国。", baihua: "守正则吉，悔恨消亡。震动用以讨伐鬼方，三年有赏于大国。"),
            MeihuaYao(title: "六五", text: "贞吉，无悔。君子之光有孚，吉。", baihua: "守正则吉，无悔恨。君子之光有诚信，吉。"),
            MeihuaYao(title: "上九", text: "有孚于饮酒，无咎。濡其首，有孚失是。", baihua: "诚信于饮酒，无过失。沾湿其首，诚信失当。")
        ], yong: nil)
    ]

    static let byName: [String: MeihuaHexagram] = {
        var d: [String: MeihuaHexagram] = [:]
        for g in hexagrams {
            d[g.name] = g
        }
        return d
    }()

    static func linesOf(_ g: MeihuaHexagram) -> [Int] {
        return (trigramBits[g.lower] ?? [0, 0, 0]) + (trigramBits[g.upper] ?? [0, 0, 0])
    }

    static func hexagram(upper: String, lower: String) -> MeihuaHexagram {
        for g in hexagrams where g.upper == upper && g.lower == lower {
            return g
        }
        return hexagrams[0]
    }

    static func trigram(of n: Int) -> String {
        for (k, v) in trigramNumber where v == n {
            return k
        }
        return "坤"
    }

    static func relation(_ a: String, _ b: String) -> String {
        // a 对 b 的关系：生／被生／克／被克／比和。
        if a == b {
            return "比和"
        }
        let sheng: [String: String] = ["木": "火", "火": "土", "土": "金", "金": "水", "水": "木"]
        let ke: [String: String] = ["木": "土", "土": "水", "水": "火", "火": "金", "金": "木"]
        if sheng[a] == b {
            return "生"
        }
        if sheng[b] == a {
            return "被生"
        }
        if ke[a] == b {
            return "克"
        }
        if ke[b] == a {
            return "被克"
        }
        return "比和"
    }

    static func qin(me: String, other: String) -> String {
        // 生我父母、我生子孙、克我官鬼、我克妻财、同我兄弟。
        if me == other {
            return "兄弟"
        }
        let sheng: [String: String] = ["木": "火", "火": "土", "土": "金", "金": "水", "水": "木"]
        let ke: [String: String] = ["木": "土", "土": "水", "水": "火", "火": "金", "金": "木"]
        if sheng[other] == me {
            return "父母"
        }
        if sheng[me] == other {
            return "子孙"
        }
        if ke[other] == me {
            return "官鬼"
        }
        return "妻财"
    }

    // 农历与真太阳时与 Web paipan.py 同口径：钟表时间先按经度校正，
    // 再取 LunarSwift 农历；晚子时 sect=2；闰月上半月本月、下半月下月。
    static func lunarParts(clock: Date, longitude: Double?) -> (yearBranch: String, month: Int, day: Int, hourBranch: String, isLeap: Bool, corrected: Date, correctionMinutes: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current
        let used = longitude.map { TrueSolarTime.corrected(clock: clock, longitude: $0, calendar: cal) } ?? clock
        let corr = used.timeIntervalSince(clock) / 60.0
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        let y = min(max(c.year ?? 2026, 1901), 2099)
        let m = min(max(c.month ?? 1, 1), 12)
        let d = min(max(c.day ?? 1, 1), 31)
        let h = min(max(c.hour ?? 0, 0), 23)
        let solar = Solar.fromYmdHms(year: y, month: m, day: d, hour: h, minute: c.minute ?? 0)
        let lunar = solar.lunar
        let ec = lunar.eightChar
        ec.sect = 2
        let yBranch = dz[(lunar.yearZhiIndex % 12 + 12) % 12]
        let hBranch = String(ec.time.last ?? "?")
        let rawMonth = lunar.month
        let isLeap = rawMonth < 0
        var usedMonth = abs(rawMonth)
        if isLeap && lunar.day > 15 {
            usedMonth = min(usedMonth + 1, 12)
        }
        return (yBranch, usedMonth, lunar.day, hBranch, isLeap, used, corr)
    }

    static func divinate(clock: Date, lon: Double = defaultLon, question: String = "") -> MeihuaResult {
        let lp = lunarParts(clock: clock, longitude: lon)
        let yearNum = (dz.firstIndex(of: lp.yearBranch) ?? 0) + 1
        let hourNum = (dz.firstIndex(of: lp.hourBranch) ?? 0) + 1
        let total = yearNum + lp.month + lp.day
        let upperNum = total % 8 == 0 ? 8 : total % 8
        let lowerNum = (total + hourNum) % 8 == 0 ? 8 : (total + hourNum) % 8
        let moving = (total + hourNum) % 6 == 0 ? 6 : (total + hourNum) % 6
        let ben = hexagram(upper: trigram(of: upperNum), lower: trigram(of: lowerNum))
        let bl = linesOf(ben)
        let huLowerBits = [bl[1], bl[2], bl[3]]
        let huUpperBits = [bl[2], bl[3], bl[4]]
        let huLowerName = trigramBits.first(where: { $0.value == huLowerBits })?.key ?? "坤"
        let huUpperName = trigramBits.first(where: { $0.value == huUpperBits })?.key ?? "坤"
        let hu = hexagram(upper: huUpperName, lower: huLowerName)
        var bianLines = bl
        bianLines[moving - 1] = 1 - bianLines[moving - 1]
        let bianLowerBits = Array(bianLines[0..<3])
        let bianUpperBits = Array(bianLines[3..<6])
        let bianLowerName = trigramBits.first(where: { $0.value == bianLowerBits })?.key ?? "坤"
        let bianUpperName = trigramBits.first(where: { $0.value == bianUpperBits })?.key ?? "坤"
        let bian = hexagram(upper: bianUpperName, lower: bianLowerName)
        let movingYao = ben.yao[moving - 1]
        let movingUpper = moving > 3
        let ti = movingUpper ? ben.upper : ben.lower
        let yong = movingUpper ? ben.lower : ben.upper
        let tiWx = trigramWuxing[ti] ?? "土"
        let yongWx = trigramWuxing[yong] ?? "土"
        let rel = relation(tiWx, yongWx)
        let tiYongLabel: String
        let tiYongText: String
        if rel == "比和" {
            tiYongLabel = "体用比和"
            tiYongText = "体用比和：体卦\(ti)（\(tiWx)）与用卦\(yong)（\(yongWx)）五行相同。"
        } else if rel == "生" {
            tiYongLabel = "体生用"
            tiYongText = "体生用：体卦\(ti)（\(tiWx)）生用卦\(yong)（\(yongWx)）。"
        } else if rel == "被生" {
            tiYongLabel = "用生体"
            tiYongText = "用生体：用卦\(yong)（\(yongWx)）生体卦\(ti)（\(tiWx)）。"
        } else if rel == "克" {
            tiYongLabel = "体克用"
            tiYongText = "体克用：体卦\(ti)（\(tiWx)）克用卦\(yong)（\(yongWx)）。"
        } else {
            tiYongLabel = "用克体"
            tiYongText = "用克体：用卦\(yong)（\(yongWx)）克体卦\(ti)（\(tiWx)）。"
        }
        let huUpWx = trigramWuxing[hu.upper] ?? "土"
        let huLoWx = trigramWuxing[hu.lower] ?? "土"
        let huRel = relation(huLoWx, huUpWx)
        let huRelationText: String
        if huRel == "比和" {
            huRelationText = "互卦下卦\(hu.lower)（\(huLoWx)）与上卦\(hu.upper)（\(huUpWx)）五行相同。"
        } else if huRel == "生" {
            huRelationText = "互卦下卦\(hu.lower)（\(huLoWx)）生上卦\(hu.upper)（\(huUpWx)）。"
        } else if huRel == "被生" {
            huRelationText = "互卦上卦\(hu.upper)（\(huUpWx)）生下卦\(hu.lower)（\(huLoWx)）。"
        } else if huRel == "克" {
            huRelationText = "互卦下卦\(hu.lower)（\(huLoWx)）克上卦\(hu.upper)（\(huUpWx)）。"
        } else {
            huRelationText = "互卦上卦\(hu.upper)（\(huUpWx)）克下卦\(hu.lower)（\(huLoWx)）。"
        }
        let (palace, generation) = palaceOf[ben.name] ?? ("乾宫", "本宫")
        let palaceWx = palaceWuxing[palace] ?? "土"
        let (shi, ying) = shiYing[generation] ?? (6, 3)
        let lines = liuyaoLines(for: ben, palaceWuxing: palaceWx)
        let (bianPalace, bianGeneration) = palaceOf[bian.name] ?? ("乾宫", "本宫")
        let bianPalaceWx = palaceWuxing[bianPalace] ?? "土"
        let bianYaoLines = liuyaoLines(for: bian, palaceWuxing: bianPalaceWx)
        return MeihuaResult(
            clock: clock, corrected: lp.corrected, correctionMinutes: lp.correctionMinutes, lon: lon,
            yearBranch: lp.yearBranch, month: lp.month, day: lp.day, hourBranch: lp.hourBranch,
            isLeap: lp.isLeap, numbers: (yearNum, lp.month, lp.day, hourNum),
            ben: ben, hu: hu, bian: bian, moving: moving, movingYao: movingYao,
            tiyongLabel: tiYongLabel, tiyongText: tiYongText, huRelationText: huRelationText,
            palace: palace, generation: generation, shi: shi, ying: ying,
            lines: lines, movingBianLine: bianYaoLines[moving - 1],
            bianPalace: bianPalace, bianGeneration: bianGeneration, question: question)
    }

    static func liuyaoLines(for g: MeihuaHexagram, palaceWuxing: String) -> [MeihuaLine] {
        let inner = najia[g.lower] ?? ("", "")
        let outer = najia[g.upper] ?? ("", "")
        let branches = Array(inner.0) + Array(outer.1)
        let bits = linesOf(g)
        var out: [MeihuaLine] = []
        for i in 0..<6 {
            let br = String(branches[i])
            let wx = branchWuxing[br] ?? "土"
            out.append(MeihuaLine(pos: i + 1, name: yaoNames[i], yinYang: bits[i] == 1 ? "阳" : "阴",
                                  branch: br, wuxing: wx, qin: qin(me: palaceWuxing, other: wx)))
        }
        return out
    }

    // 前瞻登记文本（与 Web meihua.forecast_text 同格式，原文冻结）。
    static func forecastText(_ r: MeihuaResult) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let q = r.question.isEmpty ? "" : "问事：\(r.question)；"
        return "\(q)起卦 \(fmt.string(from: r.corrected))（农历\(r.yearBranch)年\(r.month)月\(r.day)日\(r.hourBranch)时）；本卦\(r.ben.name)，动爻第\(r.moving)爻（\(r.movingYao.title)：\(r.movingYao.text)），变卦\(r.bian.name)；\(r.tiyongLabel)（\(r.tiyongText)）原文登记，到期回验。"
    }
}

// MARK: - 起卦页
struct MeihuaView: View {
    @StateObject private var store = ForecastStore()
    @State private var date = Date()
    @State private var question = ""
    @State private var lonText = "107.8"
    @State private var result: MeihuaResult?
    @State private var registered = false
    @State private var errorText = ""

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("梅花六爻 · 时间起卦".scriptConverted)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("只做时间起卦：一事一断的占卜辅助线，不编断语。起卦后自动进前瞻登记，到期回验。".scriptConverted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("起卦时间".scriptConverted, selection: $date)
                    TextField("问事（可选）", text: $question)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("经度".scriptConverted)
                        TextField("107.8", text: $lonText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("默认梁平 107.8".scriptConverted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button("起卦并登记前瞻".scriptConverted) {
                            cast(register: true)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("只起卦不登记".scriptConverted) {
                            cast(register: false)
                        }
                        .buttonStyle(.bordered)
                    }
                    if !errorText.isEmpty {
                        Text(errorText.scriptConverted)
                            .foregroundStyle(.red)
                    }
                }
                if let r = result {
                    resultView(r)
                } else {
                    KyEmptyState(icon: "moon.stars.fill", title: "尚未起卦", message: "只做时间起卦：一事一断的占卜辅助线，不编断语。起卦后自动进前瞻登记，到期回验。", actionTitle: "现在起卦", action: { cast(register: true) })
                }
                Text(MeihuaEngine.disclaimer.scriptConverted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(MeihuaEngine.source.scriptConverted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("依据与金标准：起卦法传为宋·邵雍《梅花易数》年月日时起卦；农历与真太阳时与 Web paipan.py 同口径（默认经度 107.8 梁平，晚子时 sect=2，闰月上半月本月、下半月下月）；六爻世应六亲为京房八宫纳甲通行口径。金标准见 Web test_meihua_liuyao.py（13 例时间起卦＋乾坤本宫＋闰月／晚子时边界逐项复算）。".scriptConverted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func cast(register: Bool) {
        let lon = Double(lonText) ?? MeihuaEngine.defaultLon
        let r = MeihuaEngine.divinate(clock: date, lon: lon, question: question)
        result = r
        registered = register
        errorText = ""
        if register {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current
            let targetYear = (cal.dateComponents([.year], from: date).year ?? 2026) + 1
            store.add(ForecastEntry(personName: question.isEmpty ? "占卜问事" : question,
                                    text: MeihuaEngine.forecastText(r),
                                    targetYear: targetYear,
                                    status: "待验"))
        }
    }

    private func guaCard(title: String, g: MeihuaHexagram) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(g.name)".scriptConverted)
                .font(.headline)
            Text("\(g.upper)上\(g.lower)下")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("卦辞：\(g.guaci)")
            Text("白话：\(g.guaciBaihua)".scriptConverted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func resultView(_ r: MeihuaResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("起卦收据".scriptConverted)
                    .font(.headline)
                Text("钟表时间 \(dateFormatter.string(from: r.clock)) · 真太阳时 \(dateFormatter.string(from: r.corrected))（校正 \(String(format: "%.1f", r.correctionMinutes)) 分钟，经度 \(String(format: "%.1f", r.lon))）".scriptConverted)
                    .font(.subheadline)
                let lunarHead: String = "农历".scriptConverted + "\(r.yearBranch)年\(r.month)月\(r.day)日\(r.hourBranch)时" + (r.isLeap ? "（闰月）".scriptConverted : "")
                let lunarLine: String = lunarHead + " · 问事：".scriptConverted + (r.question.isEmpty ? "（未填）" : r.question)
                Text(lunarLine)
                    .font(.subheadline)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            guaCard(title: "本卦", g: r.ben)
            guaCard(title: "互卦", g: r.hu)
            guaCard(title: "变卦", g: r.bian)
            VStack(alignment: .leading, spacing: 6) {
                Text("动爻 · 第\(r.moving)爻（\(r.movingYao.title)）".scriptConverted)
                    .font(.headline)
                Text(r.movingYao.text)
                Text("白话：\(r.movingYao.baihua)".scriptConverted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("变爻：\(r.movingBianLine.branch)\(r.movingBianLine.wuxing)\(r.movingBianLine.qin)（变卦\(r.bian.name) · \(r.bianPalace)\(r.bianGeneration)）".scriptConverted)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            VStack(alignment: .leading, spacing: 6) {
                Text("体用生克".scriptConverted)
                    .font(.headline)
                Text("\(r.tiyongLabel)：\(r.tiyongText)".scriptConverted)
                Text(r.huRelationText.scriptConverted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            VStack(alignment: .leading, spacing: 6) {
                Text("六爻 · \(r.palace)\(r.generation)（世\(r.shi)应\(r.ying)）".scriptConverted)
                    .font(.headline)
                ForEach(r.lines, id: \.pos) { l in
                    HStack {
                        Text(l.name)
                        Text(l.yinYang)
                        Text("\(l.branch)\(l.wuxing)")
                        Text(l.qin.scriptConverted)
                        Spacer()
                        if l.pos == r.shi {
                            Text("世".scriptConverted)
                        }
                        if l.pos == r.ying {
                            Text("应".scriptConverted)
                        }
                        if l.pos == r.moving {
                            Text("动".scriptConverted)
                        }
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            if registered {
                Text("已自动进前瞻登记，原文冻结，到期在前瞻登记簿回验。".scriptConverted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("本次只起卦，未登记前瞻；点「起卦并登记前瞻」才会写入登记簿。".scriptConverted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
