import SwiftUI
// G11 古籍检索：数据与 Web app/classics.json 同源逐字对拍
// （由 tools/gen_g11_swift.py 生成，勿手改；白话为本系统自己的字面疏解，
// 与原文严格区分，白话不得冒充原文；未收录篇目标明“未收录”。）
struct ClassicLine: Identifiable { let id: String; let n: Int; let orig: String; let baihua: String; let note: String }
struct ClassicChapter: Identifiable { let id: String; let no: String; let title: String; let status: String; let source: String; let lines: [ClassicLine] }
struct ClassicBook: Identifiable { let id: String; let title: String; let author: String; let script: String; let source: String; let sourceURL: String; let scopeNote: String; let chapters: [ClassicChapter] }
enum ClassicsData {
    static let version = "G17-20261109"
    static let note = "古籍只收公有领域原文；白话为本系统自己的字面疏解，与原文严格区分，白话不得冒充原文。原文逐句标出处（书名／卷／篇／句序号＋来源链接）。"
    static let books: [ClassicBook] = [
        ClassicBook(id: "ditian", title: "滴天髓", author: "相传宋·京图撰／明·刘基注；清·任铁樵阐微", script: "simplified", source: "", sourceURL: "https://www.eymao.com/gxml/44930.html", scopeNote: "本批只收歌诀原文逐句（通神颂＋通神论34篇＋六亲论29篇，共64篇目）；原注、任氏曰与命例未收录，留待后续批次。异文：各章歌诀与通神颂同句有字异时，以任铁樵阐微本章句为准，异文见各句 note。", chapters: [
            ClassicChapter(id: "tongshen-song", no: "颂", title: "通神颂", status: "included", source: "《滴天髓》通神颂", lines: [
                ClassicLine(id: "tongshen-song-1", n: 1, orig: "欲识三元万法宗，先观帝载与神功。", baihua: "要懂得天元、地元、人元三元所统摄的万法宗旨，先要看阴阳太极（帝载）与五行四时运行（神功）。", note: ""),
                ClassicLine(id: "tongshen-song-2", n: 2, orig: "坤元合德机缄通，五气偏全论吉凶。", baihua: "地道坤元与天合德，机缄相通；五行之气或偏或全，由此定吉凶。", note: ""),
                ClassicLine(id: "tongshen-song-3", n: 3, orig: "戴天履地唯人贵，顺则吉兮凶则悖。", baihua: "人头顶天、脚踏地，独得五行之全，所以为贵；顺五行之理则吉，违背则凶。", note: ""),
                ClassicLine(id: "tongshen-song-4", n: 4, orig: "要与人间开聋聩，顺悖之机须理会。", baihua: "要为人间开启聋聩，顺与悖的关键机括必须理会明白。", note: ""),
                ClassicLine(id: "tongshen-song-5", n: 5, orig: "理乘气兮岂有常，进兮退兮宜抑扬。", baihua: "理是乘着气而行的，没有固定不变的常形；进退之间应当抑扬得宜。", note: ""),
                ClassicLine(id: "tongshen-song-6", n: 6, orig: "配合干支仔细详，断人祸福与灾祥。", baihua: "把天干地支的配合仔细推详，就能断人祸福灾祥。", note: ""),
            ]),
            ClassicChapter(id: "ts-01", no: "通神论一", title: "天道", status: "included", source: "《滴天髓》通神论一·天道", lines: [
                ClassicLine(id: "ts-01-1", n: 1, orig: "欲识三元万法宗，先观帝载与神功。", baihua: "要懂得三元万法的宗旨，先看帝载与神功。", note: ""),
            ]),
            ClassicChapter(id: "ts-02", no: "通神论二", title: "地道", status: "included", source: "《滴天髓》通神论二·地道", lines: [
                ClassicLine(id: "ts-02-1", n: 1, orig: "坤元合德机缄通，五气偏全定吉凶。", baihua: "坤元与天合德，机缄相通；五行或偏或全，由此定吉凶。", note: "异文：通行歌诀本有作“五气偏全论吉凶”者；此从任铁樵阐微本“定吉凶”。"),
            ]),
            ClassicChapter(id: "ts-03", no: "通神论三", title: "人道", status: "included", source: "《滴天髓》通神论三·人道", lines: [
                ClassicLine(id: "ts-03-1", n: 1, orig: "戴天覆地人为贵，顺则吉兮凶则悖。", baihua: "人顶天覆地，独得五行之全而为贵；顺则吉，悖则凶。", note: "异文：通神颂作“戴天履地唯人贵”；此章从任铁樵阐微本“戴天覆地人为贵”。"),
            ]),
            ClassicChapter(id: "ts-04", no: "通神论四", title: "知命", status: "included", source: "《滴天髓》通神论四·知命", lines: [
                ClassicLine(id: "ts-04-1", n: 1, orig: "要与人间开聋聩，顺逆之机须理会。", baihua: "要为人间开启聋聩，顺与逆的关键机括必须理会。", note: "异文：通神颂作“顺悖之机须理会”；此章从通行本“顺逆之机须理会”。"),
            ]),
            ClassicChapter(id: "ts-05", no: "通神论五", title: "理气", status: "included", source: "《滴天髓》通神论五·理气", lines: [
                ClassicLine(id: "ts-05-1", n: 1, orig: "理承气行岂有常，进兮退兮宜抑扬。", baihua: "理是承着气而行的，哪有固定不变的常形；进退之间应当抑扬得宜。", note: "异文：通神颂作“理乘气兮岂有常”；此章从通行本“理承气行岂有常”。"),
            ]),
            ClassicChapter(id: "ts-06", no: "通神论六", title: "配合", status: "included", source: "《滴天髓》通神论六·配合", lines: [
                ClassicLine(id: "ts-06-1", n: 1, orig: "配合干支仔细详，定人福祸与灾祥。", baihua: "把干支配合仔细推详，就能定人福祸灾祥。", note: "异文：通神颂作“断人祸福与灾祥”；此章从通行本“定人福祸与灾祥”。"),
            ]),
            ClassicChapter(id: "ts-07", no: "通神论七", title: "天干", status: "included", source: "《滴天髓》通神论七·天干", lines: [
                ClassicLine(id: "ts-07-1", n: 1, orig: "五阳皆阳丙为最，五阴皆阴癸为至。", baihua: "五个阳干中丙火最阳，五个阴干中癸水最阴。", note: ""),
                ClassicLine(id: "ts-07-2", n: 2, orig: "五阳从气不从势，五阴从势无情义。", baihua: "五阳干看气不看势，五阴干看势而不讲情义。", note: ""),
                ClassicLine(id: "ts-07-3", n: 3, orig: "甲木参天，脱胎要火。", baihua: "甲木如参天大树，要得火来脱胎换骨。", note: ""),
                ClassicLine(id: "ts-07-4", n: 4, orig: "春不容金，秋不容土。", baihua: "春天甲木旺不容金来克，秋天甲木弱不容土来耗。", note: ""),
                ClassicLine(id: "ts-07-5", n: 5, orig: "火炽乘龙，水宕骑虎。", baihua: "火旺时甲木借辰龙之水库得济，水荡时甲木借寅虎之木禄得安。", note: ""),
                ClassicLine(id: "ts-07-6", n: 6, orig: "地阔天和，植立千古。", baihua: "地势宽广、天时和顺，甲木就能长久植立。", note: ""),
                ClassicLine(id: "ts-07-7", n: 7, orig: "乙木虽柔，刲羊解牛。", baihua: "乙木虽柔，却能像刲羊解牛那样以柔克刚。", note: ""),
                ClassicLine(id: "ts-07-8", n: 8, orig: "怀丁抱丙，跨凤乘猴。", baihua: "乙木怀抱丁火、丙火，跨凤（酉）乘猴（申）而得势。", note: ""),
                ClassicLine(id: "ts-07-9", n: 9, orig: "虚湿之地，骑马亦忧。", baihua: "到了虚湿之地，乙木即便骑马（午）也堪忧。", note: ""),
                ClassicLine(id: "ts-07-10", n: 10, orig: "藤萝系甲，可春可秋。", baihua: "乙木如藤萝依附甲木，春夏秋冬都可生长。", note: ""),
                ClassicLine(id: "ts-07-11", n: 11, orig: "丙火猛烈，欺霜侮雪。", baihua: "丙火猛烈，能欺霜侮雪而不惧寒。", note: ""),
                ClassicLine(id: "ts-07-12", n: 12, orig: "能煅庚金，逢辛反怯。", baihua: "丙火能煅炼庚金，遇到辛金反而怯弱。", note: ""),
                ClassicLine(id: "ts-07-13", n: 13, orig: "土众成慈，水猖显节。", baihua: "土多时丙火显慈和，水旺时丙火显节操。", note: ""),
                ClassicLine(id: "ts-07-14", n: 14, orig: "虎马犬乡，甲来焚灭。", baihua: "到了寅午戌火乡，甲木来会被焚灭。", note: ""),
                ClassicLine(id: "ts-07-15", n: 15, orig: "丁火柔中，内性昭融。", baihua: "丁火外柔内刚，内里性情昭明融和。", note: ""),
                ClassicLine(id: "ts-07-16", n: 16, orig: "抱乙而孝，合壬而忠。", baihua: "丁火抱乙木如孝，合壬水如忠。", note: ""),
                ClassicLine(id: "ts-07-17", n: 17, orig: "旺而不烈，衰而不穷。", baihua: "丁火旺而不烈，衰而不穷。", note: ""),
                ClassicLine(id: "ts-07-18", n: 18, orig: "如有嫡母，可秋可冬。", baihua: "丁火若有甲木嫡母生扶，秋冬也可通行。", note: ""),
                ClassicLine(id: "ts-07-19", n: 19, orig: "戊土固重，既中且正。", baihua: "戊土稳固厚重，既居中又得正。", note: ""),
                ClassicLine(id: "ts-07-20", n: 20, orig: "静翕动辟，万物司命。", baihua: "戊土静则收敛、动则开辟，是万物性命所系。", note: ""),
                ClassicLine(id: "ts-07-21", n: 21, orig: "水润物生，火燥物病。", baihua: "戊土得水润则万物生，得火燥则万物病。", note: ""),
                ClassicLine(id: "ts-07-22", n: 22, orig: "若在艮坤，怕冲宜静。", baihua: "戊土若在艮坤之位，怕冲而宜静。", note: ""),
                ClassicLine(id: "ts-07-23", n: 23, orig: "己土卑湿，中正蓄藏。", baihua: "己土卑下湿润，中正而善于蓄藏。", note: ""),
                ClassicLine(id: "ts-07-24", n: 24, orig: "不愁木胜，不畏水狂。", baihua: "己土不愁木旺来克，不畏水狂来冲。", note: ""),
                ClassicLine(id: "ts-07-25", n: 25, orig: "火少火晦，金多金光。", baihua: "己土火少则晦暗，金多则光亮。", note: ""),
                ClassicLine(id: "ts-07-26", n: 26, orig: "若要物旺，宜助宜帮。", baihua: "若要万物旺盛，己土宜得帮助。", note: ""),
                ClassicLine(id: "ts-07-27", n: 27, orig: "庚金带煞，刚健为最。", baihua: "庚金带着肃杀之气，刚健为十干之最。", note: ""),
                ClassicLine(id: "ts-07-28", n: 28, orig: "得水而清，得火而锐。", baihua: "庚金得水则清，得火则锐。", note: ""),
                ClassicLine(id: "ts-07-29", n: 29, orig: "土润则生，土乾则脆。", baihua: "土润时庚金得生，土燥时庚金变脆。", note: ""),
                ClassicLine(id: "ts-07-30", n: 30, orig: "能赢甲兄，输于乙妹。", baihua: "庚金能胜甲木兄，却输给乙木妹。", note: ""),
                ClassicLine(id: "ts-07-31", n: 31, orig: "辛金软弱，温润而清，畏土之叠，乐水之盈。", baihua: "辛金软弱温润而清，怕土重叠来埋，喜水盈满来洗。", note: ""),
                ClassicLine(id: "ts-07-32", n: 32, orig: "能扶社稷，能救生灵。", baihua: "辛金能扶社稷，能救生灵。", note: ""),
                ClassicLine(id: "ts-07-33", n: 33, orig: "热则喜母，寒则喜丁。", baihua: "辛金热时喜母（土）来生，寒时喜丁火来暖。", note: ""),
                ClassicLine(id: "ts-07-34", n: 34, orig: "壬水通河，能泄金气。", baihua: "壬水如通达的大河，能泄金之气。", note: ""),
                ClassicLine(id: "ts-07-35", n: 35, orig: "刚中之德，周流不滞。", baihua: "壬水有刚中之德，周流而不停滞。", note: ""),
                ClassicLine(id: "ts-07-36", n: 36, orig: "通根透癸，冲天奔地。", baihua: "壬水通根透癸，能冲天奔地。", note: ""),
                ClassicLine(id: "ts-07-37", n: 37, orig: "化则有情，从则相济。", baihua: "壬水化合则有情，顺从则相济。", note: ""),
                ClassicLine(id: "ts-07-38", n: 38, orig: "癸水至弱，达于天津。", baihua: "癸水至弱，却能通达天上银河。", note: ""),
                ClassicLine(id: "ts-07-39", n: 39, orig: "得龙而运，功化斯神。", baihua: "癸水得龙（辰）而运行，功化就神妙了。", note: ""),
                ClassicLine(id: "ts-07-40", n: 40, orig: "不愁火土，不论庚辛。", baihua: "癸水不愁火土来克，不论庚辛来生。", note: ""),
                ClassicLine(id: "ts-07-41", n: 41, orig: "合戊见火，化象斯真。", baihua: "癸水合戊土见火，化火之象才算真。", note: ""),
            ]),
            ClassicChapter(id: "ts-08", no: "通神论八", title: "地支", status: "included", source: "《滴天髓》通神论八·地支", lines: [
                ClassicLine(id: "ts-08-1", n: 1, orig: "阳支动且强，速达显灾祥。", baihua: "阳支主动而强，吉凶灾祥来得快而明显。", note: ""),
                ClassicLine(id: "ts-08-2", n: 2, orig: "阴支静且专，否泰每经年。", baihua: "阴支主静而专，否泰变化常常经年才见。", note: ""),
                ClassicLine(id: "ts-08-3", n: 3, orig: "生方怕动库宜开，败地逢冲仔细推。", baihua: "长生之方怕动，墓库宜开；败地逢冲要仔细推。", note: ""),
                ClassicLine(id: "ts-08-4", n: 4, orig: "支神只以冲为重，刑与穿兮动不动。", baihua: "地支之神只以冲为重，刑与穿（害）要看动还是不动。", note: ""),
                ClassicLine(id: "ts-08-5", n: 5, orig: "暗冲暗合犹为喜，彼冲我冲皆冲起。", baihua: "暗冲暗合还算喜事，对方来冲、我去冲都算冲起。", note: ""),
                ClassicLine(id: "ts-08-6", n: 6, orig: "旺者冲衰衰者拔，衰神冲旺旺神发。", baihua: "旺神冲衰神则衰者被拔去，衰神冲旺神则旺者被激发。", note: ""),
            ]),
            ClassicChapter(id: "ts-09", no: "通神论九", title: "干支总论", status: "included", source: "《滴天髓》通神论九·干支总论", lines: [
                ClassicLine(id: "ts-09-1", n: 1, orig: "阴阳顺逆之说，洛书流行之用，其理信有之也，其法不可执一。", baihua: "阴阳顺逆的说法、洛书流行的用法，道理确实有，但方法不可执着一端。", note: ""),
                ClassicLine(id: "ts-09-2", n: 2, orig: "天地顺遂而精粹者昌，阴阳乖悖而混乱者亡。", baihua: "天地顺遂而精粹的就昌盛，阴阳乖悖而混乱的就衰亡。", note: ""),
                ClassicLine(id: "ts-09-3", n: 3, orig: "天全一气，不可使地德莫之载；地全三物，不可使天道莫之容。", baihua: "天若全是一气，不可没有地德来承载；地若全是三物，不可没有天道来包容。", note: ""),
                ClassicLine(id: "ts-09-4", n: 4, orig: "阳乘阳位阳气昌，最要行程安顿；阴乘阴位阴气盛，还须道路光亨。", baihua: "阳干乘阳位则阳气昌盛，最要紧的是行运安顿；阴干乘阴位则阴气盛，还须道路光亨。", note: ""),
                ClassicLine(id: "ts-09-5", n: 5, orig: "地生天者，天衰怕冲；天合地者，地旺喜静。", baihua: "地支生天干的，天干衰弱时怕冲；天干合地支的，地支旺盛时喜静。", note: ""),
                ClassicLine(id: "ts-09-6", n: 6, orig: "甲申戊寅，真为杀印相生；庚寅癸丑，也作两神兴旺。", baihua: "甲申日、戊寅时一类，真是杀印相生；庚寅日、癸丑时一类，也算两神兴旺。", note: ""),
                ClassicLine(id: "ts-09-7", n: 7, orig: "上下贵乎情协，左右贵乎同志。", baihua: "上下干支贵在情意相协，左右干支贵在志同道合。", note: ""),
                ClassicLine(id: "ts-09-8", n: 8, orig: "始其所始，终其所终，富贵福寿，永乎无穷。", baihua: "从它所始的地方开始，到它所终的地方结束，富贵福寿，就永无穷尽。", note: ""),
            ]),
            ClassicChapter(id: "ts-10", no: "通神论十", title: "形象", status: "included", source: "《滴天髓》通神论十·形象", lines: [
                ClassicLine(id: "ts-10-1", n: 1, orig: "两气合而成象，象不可破也。", baihua: "两种气相合而成象，象成了就不可破。", note: ""),
                ClassicLine(id: "ts-10-2", n: 2, orig: "五气聚而成形，形不可害也。", baihua: "五种气聚合而成形，形全了就不可害。", note: ""),
                ClassicLine(id: "ts-10-3", n: 3, orig: "独象喜行化地，而化神要昌。", baihua: "独成一象的，喜行化神之地，而化神要旺。", note: ""),
                ClassicLine(id: "ts-10-4", n: 4, orig: "全象喜行财地，而财神要旺。", baihua: "全成一象的，喜行财神之地，而财神要旺。", note: ""),
                ClassicLine(id: "ts-10-5", n: 5, orig: "形全者宜损其有余，形缺者宜补其不足。", baihua: "形全的应当损去有余，形缺的应当补足不足。", note: ""),
            ]),
            ClassicChapter(id: "ts-11", no: "通神论十一", title: "方局", status: "included", source: "《滴天髓》通神论十一·方局", lines: [
                ClassicLine(id: "ts-11-1", n: 1, orig: "方是方兮局是局，方要得方莫混局。", baihua: "方就是方，局就是局；成方要得方，不要混成局。", note: ""),
                ClassicLine(id: "ts-11-2", n: 2, orig: "局混方兮有纯疵，行运喜南或喜北。", baihua: "局里混了方就有纯疵，行运要看喜南还是喜北。", note: ""),
                ClassicLine(id: "ts-11-3", n: 3, orig: "若然方局一齐来，须要干头无反覆。", baihua: "若是方与局一齐来了，须要天干上没有反复。", note: ""),
                ClassicLine(id: "ts-11-4", n: 4, orig: "成方干透一元神，生地库地皆为福。", baihua: "成方而天干透出一位元神，生地库地都算福。", note: ""),
                ClassicLine(id: "ts-11-5", n: 5, orig: "成局干透一官星，左边右边空碌碌。", baihua: "成局而天干透出一位官星，左右两边就空空碌碌了。", note: ""),
            ]),
            ClassicChapter(id: "ts-12", no: "通神论十二", title: "八格", status: "included", source: "《滴天髓》通神论十二·八格", lines: [
                ClassicLine(id: "ts-12-1", n: 1, orig: "财官印绶分偏正，兼论食伤八格定。", baihua: "财官印绶分偏正，再兼论食神伤官，八格就定了。", note: ""),
                ClassicLine(id: "ts-12-2", n: 2, orig: "影响遥系既为虚，杂气财官不可拘。", baihua: "影响遥系的既算虚，杂气里的财官也不可拘泥。", note: ""),
            ]),
            ClassicChapter(id: "ts-13", no: "通神论十三", title: "体用", status: "included", source: "《滴天髓》通神论十三·体用", lines: [
                ClassicLine(id: "ts-13-1", n: 1, orig: "道有体用，不可以一端论也，要在扶之抑之得其宜。", baihua: "道有体有用，不可以只从一端来论，关键在扶它还是抑它要得宜。", note: ""),
            ]),
            ClassicChapter(id: "ts-14", no: "通神论十四", title: "精神", status: "included", source: "《滴天髓》通神论十四·精神", lines: [
                ClassicLine(id: "ts-14-1", n: 1, orig: "人有精神，不可以一偏求也，要在损之益之得其中。", baihua: "人有精神，不可以偏于一端来求，关键在损它还是益它要得其中。", note: ""),
            ]),
            ClassicChapter(id: "ts-15", no: "通神论十五", title: "月令", status: "included", source: "《滴天髓》通神论十五·月令", lines: [
                ClassicLine(id: "ts-15-1", n: 1, orig: "月令乃提纲之府，譬之宅也，人元为用事之神，宅之定向也，不可以不卜。", baihua: "月令是提纲所在的府，好比住宅；人元是用事之神，好比住宅的定向，不可以不占卜清楚。", note: ""),
            ]),
            ClassicChapter(id: "ts-16", no: "通神论十六", title: "生时", status: "included", source: "《滴天髓》通神论十六·生时", lines: [
                ClassicLine(id: "ts-16-1", n: 1, orig: "生时乃归宿之地，譬之墓也，人元为用事之神，墓之定方也，不可以不辨。", baihua: "生时是归宿之地，好比墓地；人元是用事之神，好比墓地的定方，不可以不辨明。", note: ""),
            ]),
            ClassicChapter(id: "ts-17", no: "通神论十七", title: "衰旺", status: "included", source: "《滴天髓》通神论十七·衰旺", lines: [
                ClassicLine(id: "ts-17-1", n: 1, orig: "能知旺衰之真机，其于三命之奥，思过半矣。", baihua: "能知道旺衰的真正机括，对于三命的奥妙，就思索过半了。", note: ""),
            ]),
            ClassicChapter(id: "ts-18", no: "通神论十八", title: "中和", status: "included", source: "《滴天髓》通神论十八·中和", lines: [
                ClassicLine(id: "ts-18-1", n: 1, orig: "既识中和之正理，其于五行之妙，有能全焉。", baihua: "既已识得中和的正理，对于五行的精妙，就能全盘掌握了。", note: ""),
            ]),
            ClassicChapter(id: "ts-19", no: "通神论十九", title: "源流", status: "included", source: "《滴天髓》通神论十九·源流", lines: [
                ClassicLine(id: "ts-19-1", n: 1, orig: "何处起根源？流到何方住？", baihua: "根源从何处起？又流到何方停住？", note: ""),
                ClassicLine(id: "ts-19-2", n: 2, orig: "机括此中求，知来亦知去。", baihua: "机括就在这中间求，既知来处也知去处。", note: ""),
            ]),
            ClassicChapter(id: "ts-20", no: "通神论二十", title: "通关", status: "included", source: "《滴天髓》通神论二十·通关", lines: [
                ClassicLine(id: "ts-20-1", n: 1, orig: "关内有织女，关外有牛郎，此关若通也，相邀入洞房。", baihua: "关内有织女，关外有牛郎，这一关若是通了，就相邀着进了洞房。", note: ""),
            ]),
            ClassicChapter(id: "ts-21", no: "通神论二十一", title: "官杀", status: "included", source: "《滴天髓》通神论二十一·官杀", lines: [
                ClassicLine(id: "ts-21-1", n: 1, orig: "官杀混杂来问我，有可有不可。", baihua: "官杀混杂来问我，有的可以，有的不可。", note: ""),
            ]),
            ClassicChapter(id: "ts-22", no: "通神论二十二", title: "伤官", status: "included", source: "《滴天髓》通神论二十二·伤官", lines: [
                ClassicLine(id: "ts-22-1", n: 1, orig: "伤官见官果难辨，可见可不见。", baihua: "伤官见官果然难辨，有的可见，有的可不见。", note: ""),
            ]),
            ClassicChapter(id: "ts-23", no: "通神论二十三", title: "清气", status: "included", source: "《滴天髓》通神论二十三·清气", lines: [
                ClassicLine(id: "ts-23-1", n: 1, orig: "一清到底有精神，管取平生富贵真。", baihua: "一清到底就有精神，管保平生富贵是真的。", note: ""),
                ClassicLine(id: "ts-23-2", n: 2, orig: "澄浊求清清得去，时来寒谷也回春。", baihua: "澄清浊气求得清，时运一来寒谷也能回春。", note: ""),
            ]),
            ClassicChapter(id: "ts-24", no: "通神论二十四", title: "浊气", status: "included", source: "《滴天髓》通神论二十四·浊气", lines: [
                ClassicLine(id: "ts-24-1", n: 1, orig: "满盘浊气令人苦，一局清枯也苦人。", baihua: "满盘浊气让人受苦，一局清而枯也苦人。", note: ""),
                ClassicLine(id: "ts-24-2", n: 2, orig: "半清半浊犹是可，多成多败度晨昏。", baihua: "半清半浊还算可以，只是多成多败地度过晨昏。", note: ""),
            ]),
            ClassicChapter(id: "ts-25", no: "通神论二十五", title: "真神", status: "included", source: "《滴天髓》通神论二十五·真神", lines: [
                ClassicLine(id: "ts-25-1", n: 1, orig: "令上寻真聚得真，假神休要乱真神。", baihua: "在月令上寻真、聚得真，假神不要来乱真神。", note: ""),
                ClassicLine(id: "ts-25-2", n: 2, orig: "真神得用生平贵，用假终为碌碌人。", baihua: "真神得用，一生就贵；用假神终究只是碌碌无为的人。", note: ""),
            ]),
            ClassicChapter(id: "ts-26", no: "通神论二十六", title: "假神", status: "included", source: "《滴天髓》通神论二十六·假神", lines: [
                ClassicLine(id: "ts-26-1", n: 1, orig: "真假参差难辩论，不明不暗受邅迍。", baihua: "真假参差难辩论，不明不暗地受困顿。", note: ""),
                ClassicLine(id: "ts-26-2", n: 2, orig: "提纲不与真神照，暗处寻真也有真。", baihua: "提纲不与真神相照，在暗处寻真也有真。", note: ""),
            ]),
            ClassicChapter(id: "ts-27", no: "通神论二十七", title: "刚柔", status: "included", source: "《滴天髓》通神论二十七·刚柔", lines: [
                ClassicLine(id: "ts-27-1", n: 1, orig: "刚柔不一也，善为制者，但引其性情而已矣。", baihua: "刚柔各不相同，善于制伏的人，不过是顺引它的性情罢了。", note: ""),
            ]),
            ClassicChapter(id: "ts-28", no: "通神论二十八", title: "顺逆", status: "included", source: "《滴天髓》通神论二十八·顺逆", lines: [
                ClassicLine(id: "ts-28-1", n: 1, orig: "顺逆不齐也，不可逆者，顺其气势而已矣。", baihua: "顺逆并不齐整，不可逆的，就顺着它的气势罢了。", note: ""),
            ]),
            ClassicChapter(id: "ts-29", no: "通神论二十九", title: "寒暖", status: "included", source: "《滴天髓》通神论二十九·寒暖", lines: [
                ClassicLine(id: "ts-29-1", n: 1, orig: "天道有寒暖，发育万物，人道得之，不可过也。", baihua: "天道有寒暖，化育万物；人道得了它，不可过分。", note: ""),
            ]),
            ClassicChapter(id: "ts-30", no: "通神论三十", title: "燥湿", status: "included", source: "《滴天髓》通神论三十·燥湿", lines: [
                ClassicLine(id: "ts-30-1", n: 1, orig: "地道有燥湿，生成品汇，人道得之，不可偏也。", baihua: "地道有燥湿，生成万物；人道得了它，不可偏颇。", note: ""),
            ]),
            ClassicChapter(id: "ts-31", no: "通神论三十一", title: "隐显", status: "included", source: "《滴天髓》通神论三十一·隐显", lines: [
                ClassicLine(id: "ts-31-1", n: 1, orig: "吉神太露，起争夺之风；凶物深藏，成养虎之患。", baihua: "吉神太露出来，会引起争夺之风；凶物深藏不露，会养成虎之患。", note: ""),
            ]),
            ClassicChapter(id: "ts-32", no: "通神论三十二", title: "众寡", status: "included", source: "《滴天髓》通神论三十二·众寡", lines: [
                ClassicLine(id: "ts-32-1", n: 1, orig: "强众而敌寡者，势在去其寡。", baihua: "强的一方人多、敌方人少，势头在于去掉那少的。", note: ""),
                ClassicLine(id: "ts-32-2", n: 2, orig: "强寡而敌众者，势在成乎众。", baihua: "强的一方人少、敌方人多，势头在于成就那多的。", note: ""),
            ]),
            ClassicChapter(id: "ts-33", no: "通神论三十三", title: "震兑", status: "included", source: "《滴天髓》通神论三十三·震兑", lines: [
                ClassicLine(id: "ts-33-1", n: 1, orig: "震兑主仁义之真机，势不两立，而有相成者存。", baihua: "震兑主宰仁义的真正机括，势头不两立，却有相成的地方。", note: ""),
            ]),
            ClassicChapter(id: "ts-34", no: "通神论三十四", title: "坎离", status: "included", source: "《滴天髓》通神论三十四·坎离", lines: [
                ClassicLine(id: "ts-34-1", n: 1, orig: "坎离宰天地之中气，成不独成，而有相济者在。", baihua: "坎离主宰天地之间的中气，成不是独成，而有相济的地方。", note: ""),
            ]),
            ClassicChapter(id: "lq-01", no: "六亲论一", title: "夫妻", status: "included", source: "《滴天髓》六亲论一·夫妻", lines: [
                ClassicLine(id: "lq-01-1", n: 1, orig: "夫妻姻缘宿世来，喜神有意傍天财。", baihua: "夫妻姻缘是宿世带来的，喜神有意傍着天财。", note: ""),
            ]),
            ClassicChapter(id: "lq-02", no: "六亲论二", title: "子女", status: "included", source: "《滴天髓》六亲论二·子女", lines: [
                ClassicLine(id: "lq-02-1", n: 1, orig: "子女根枝一世传，喜神看与杀神连。", baihua: "子女如根枝一世相传，看喜神与杀神相连与否。", note: ""),
            ]),
            ClassicChapter(id: "lq-03", no: "六亲论三", title: "父母", status: "included", source: "《滴天髓》六亲论三·父母", lines: [
                ClassicLine(id: "lq-03-1", n: 1, orig: "父母或降与或替，岁月所关果非细。", baihua: "父母或降或替，都与岁月有关，实在不是小事。", note: ""),
            ]),
            ClassicChapter(id: "lq-04", no: "六亲论四", title: "兄弟", status: "included", source: "《滴天髓》六亲论四·兄弟", lines: [
                ClassicLine(id: "lq-04-1", n: 1, orig: "兄弟谁废与谁兴，提用财神问重轻。", baihua: "兄弟谁废谁兴，要提用神、问财神的轻重。", note: ""),
            ]),
            ClassicChapter(id: "lq-05", no: "六亲论五", title: "何知章", status: "included", source: "《滴天髓》六亲论五·何知章", lines: [
                ClassicLine(id: "lq-05-1", n: 1, orig: "何知其人富，财气通门户。", baihua: "怎么知道这人富？财气通达门户。", note: ""),
                ClassicLine(id: "lq-05-2", n: 2, orig: "何知其人贵，官星有理会。", baihua: "怎么知道这人贵？官星有理会。", note: ""),
                ClassicLine(id: "lq-05-3", n: 3, orig: "何知其人贫，财神反不真。", baihua: "怎么知道这人贫？财神反而不真。", note: ""),
                ClassicLine(id: "lq-05-4", n: 4, orig: "何知其人贱，官星还不见。", baihua: "怎么知道这人贱？官星还不见。", note: ""),
                ClassicLine(id: "lq-05-5", n: 5, orig: "何知其人吉，喜神为辅弼。", baihua: "怎么知道这人吉？喜神为辅弼。", note: ""),
                ClassicLine(id: "lq-05-6", n: 6, orig: "何知其人凶，忌神辗转攻。", baihua: "怎么知道这人凶？忌神辗转攻来。", note: ""),
                ClassicLine(id: "lq-05-7", n: 7, orig: "何知其人寿，性定元神厚。", baihua: "怎么知道这人寿？性情定、元神厚。", note: ""),
                ClassicLine(id: "lq-05-8", n: 8, orig: "何知其人夭，气浊神枯了。", baihua: "怎么知道这人夭？气浊神枯了。", note: ""),
            ]),
            ClassicChapter(id: "lq-06", no: "六亲论六", title: "女命章", status: "included", source: "《滴天髓》六亲论六·女命章", lines: [
                ClassicLine(id: "lq-06-1", n: 1, orig: "论夫论子要安祥，气静平和妇道章。", baihua: "论丈夫论子女要安祥，气静平和才是妇道。", note: ""),
                ClassicLine(id: "lq-06-2", n: 2, orig: "三奇二德虚好话，咸池驿马半推详。", baihua: "三奇二德是虚好话，咸池驿马只能推详一半。", note: ""),
            ]),
            ClassicChapter(id: "lq-07", no: "六亲论七", title: "小儿", status: "included", source: "《滴天髓》六亲论七·小儿", lines: [
                ClassicLine(id: "lq-07-1", n: 1, orig: "论财论杀论精神，四柱平和易养成。", baihua: "论财论杀论精神，四柱平和就容易养成。", note: ""),
                ClassicLine(id: "lq-07-2", n: 2, orig: "气势攸长无削丧，杀关虽有不伤身。", baihua: "气势悠长、没有削丧，杀关虽有也不伤身。", note: ""),
            ]),
            ClassicChapter(id: "lq-08", no: "六亲论八", title: "才德", status: "included", source: "《滴天髓》六亲论八·才德", lines: [
                ClassicLine(id: "lq-08-1", n: 1, orig: "德胜才者，局全君子之风；才胜德者，用显多能之象。", baihua: "德胜过才的，格局全是君子之风；才胜过德的，用神显出多能之象。", note: ""),
            ]),
            ClassicChapter(id: "lq-09", no: "六亲论九", title: "奋郁", status: "included", source: "《滴天髓》六亲论九·奋郁", lines: [
                ClassicLine(id: "lq-09-1", n: 1, orig: "局中显奋发之机者，神舒意畅。", baihua: "局中显出奋发之机的，神舒意畅。", note: ""),
                ClassicLine(id: "lq-09-2", n: 2, orig: "象内多沉埋之气者，心郁志灰。", baihua: "象内多沉埋之气的，心郁志灰。", note: ""),
            ]),
            ClassicChapter(id: "lq-10", no: "六亲论十", title: "恩怨", status: "included", source: "《滴天髓》六亲论十·恩怨", lines: [
                ClassicLine(id: "lq-10-1", n: 1, orig: "两意情通中有媒，虽然遥立意寻追；", baihua: "两情相通、中间有媒，虽然遥遥相对、意在寻追；", note: ""),
                ClassicLine(id: "lq-10-2", n: 2, orig: "有情却被人离间，怨起恩中死不灰。", baihua: "有情却被人离间，怨从恩中起来、到死也不灰。", note: ""),
            ]),
            ClassicChapter(id: "lq-11", no: "六亲论十一", title: "闲神", status: "included", source: "《滴天髓》六亲论十一·闲神", lines: [
                ClassicLine(id: "lq-11-1", n: 1, orig: "一二闲神用去么，不去何妨莫动他。", baihua: "一两个闲神用得去吗？用不去又何妨，不要动它。", note: ""),
                ClassicLine(id: "lq-11-2", n: 2, orig: "半局闲神任闲着，要紧之场作自豪。", baihua: "半局闲神任它闲着，到了要紧场合自会逞豪。", note: ""),
                ClassicLine(id: "lq-11-3", n: 3, orig: "出门要向天涯游，何事裙钗恣意留。", baihua: "出门要向天涯游去，何事留恋裙钗、恣意停留。", note: ""),
                ClassicLine(id: "lq-11-4", n: 4, orig: "不管白雪与明月，任君策马朝天阙。", baihua: "不管白雪与明月，任凭你策马朝向天阙。", note: ""),
            ]),
            ClassicChapter(id: "lq-12", no: "六亲论十二", title: "从象", status: "included", source: "《滴天髓》六亲论十二·从象", lines: [
                ClassicLine(id: "lq-12-1", n: 1, orig: "从得真者只论从，从神又有吉和凶。", baihua: "从得真的人只论从，从神又有吉和凶。", note: ""),
            ]),
            ClassicChapter(id: "lq-13", no: "六亲论十三", title: "化象", status: "included", source: "《滴天髓》六亲论十三·化象", lines: [
                ClassicLine(id: "lq-13-1", n: 1, orig: "化得真者只论化，化神还有几般话。", baihua: "化得真的人只论化，化神还有几般说法。", note: ""),
            ]),
            ClassicChapter(id: "lq-14", no: "六亲论十四", title: "假从", status: "included", source: "《滴天髓》六亲论十四·假从", lines: [
                ClassicLine(id: "lq-14-1", n: 1, orig: "真从之家有几人，假从亦可发其身。", baihua: "真从的人家有几个？假从也可以发达自身。", note: ""),
            ]),
            ClassicChapter(id: "lq-15", no: "六亲论十五", title: "假化", status: "included", source: "《滴天髓》六亲论十五·假化", lines: [
                ClassicLine(id: "lq-15-1", n: 1, orig: "假化之人亦多贵，异姓孤儿能出类。", baihua: "假化的人也多有贵，异姓孤儿能出类拔萃。", note: ""),
            ]),
            ClassicChapter(id: "lq-16", no: "六亲论十六", title: "顺局", status: "included", source: "《滴天髓》六亲论十六·顺局", lines: [
                ClassicLine(id: "lq-16-1", n: 1, orig: "一出门来要见儿，吾儿成气构门闾；从儿不管身强弱，只要吾儿又得儿。", baihua: "一出门来要见儿，吾儿成气、构起门闾；从儿就不管身强身弱，只要吾儿又得儿。", note: ""),
            ]),
            ClassicChapter(id: "lq-17", no: "六亲论十七", title: "反局", status: "included", source: "《滴天髓》六亲论十七·反局", lines: [
                ClassicLine(id: "lq-17-1", n: 1, orig: "君赖臣生理最微，儿能救母泄天机。", baihua: "君赖臣生、道理最微，儿能救母、泄漏天机。", note: ""),
                ClassicLine(id: "lq-17-2", n: 2, orig: "母慈灭子关因异，夫健何为又怕妻。", baihua: "母慈灭子、关因有异，夫健又何必怕妻。", note: ""),
            ]),
            ClassicChapter(id: "lq-18", no: "六亲论十八", title: "战局", status: "included", source: "《滴天髓》六亲论十八·战局", lines: [
                ClassicLine(id: "lq-18-1", n: 1, orig: "天战犹自可，地战急如火。", baihua: "天战还算可以，地战急如火。", note: ""),
            ]),
            ClassicChapter(id: "lq-19", no: "六亲论十九", title: "合局", status: "included", source: "《滴天髓》六亲论十九·合局", lines: [
                ClassicLine(id: "lq-19-1", n: 1, orig: "合有宜不宜，合多不为奇。", baihua: "合有宜与不宜，合多了就不算奇。", note: ""),
            ]),
            ClassicChapter(id: "lq-20", no: "六亲论二十", title: "君象", status: "included", source: "《滴天髓》六亲论二十·君象", lines: [
                ClassicLine(id: "lq-20-1", n: 1, orig: "君不可亢也，贵乎损上以益下。", baihua: "君不可亢，贵在损上以益下。", note: ""),
            ]),
            ClassicChapter(id: "lq-21", no: "六亲论二十一", title: "臣象", status: "included", source: "《滴天髓》六亲论二十一·臣象", lines: [
                ClassicLine(id: "lq-21-1", n: 1, orig: "臣不可过也。贵乎损下而益上。", baihua: "臣不可过，贵在损下而益上。", note: ""),
            ]),
            ClassicChapter(id: "lq-22", no: "六亲论二十二", title: "母象", status: "included", source: "《滴天髓》六亲论二十二·母象", lines: [
                ClassicLine(id: "lq-22-1", n: 1, orig: "知慈母恤孤之道，始有瓜瓞无疆之庆。", baihua: "懂得慈母抚恤孤儿的道理，才有瓜瓞绵绵、无疆之庆。", note: ""),
            ]),
            ClassicChapter(id: "lq-23", no: "六亲论二十三", title: "子象", status: "included", source: "《滴天髓》六亲论二十三·子象", lines: [
                ClassicLine(id: "lq-23-1", n: 1, orig: "知孝子奉亲之方，始成克谐大顺之风。", baihua: "懂得孝子奉养双亲的方法，才成克谐大顺之风。", note: ""),
            ]),
            ClassicChapter(id: "lq-24", no: "六亲论二十四", title: "性情", status: "included", source: "《滴天髓》六亲论二十四·性情", lines: [
                ClassicLine(id: "lq-24-1", n: 1, orig: "五气不戾，性正情和。", baihua: "五气不乖戾，性正情和。", note: ""),
                ClassicLine(id: "lq-24-2", n: 2, orig: "浊混偏枯，性乖情逆。", baihua: "气浊混乱、偏枯，人的性情就乖张逆反。", note: ""),
                ClassicLine(id: "lq-24-3", n: 3, orig: "火烈而性燥者，遇金水之激。", baihua: "火烈而性燥的人，遇到金水来激。", note: ""),
                ClassicLine(id: "lq-24-4", n: 4, orig: "水奔而性柔者，全金木之神。", baihua: "水奔而性柔的人，全靠金木之神。", note: ""),
                ClassicLine(id: "lq-24-5", n: 5, orig: "木奔南而软怯，金见水以流通。", baihua: "木奔向南方而软怯，金见水得以流通。", note: ""),
                ClassicLine(id: "lq-24-6", n: 6, orig: "最拗者西水还南，至刚者东火转北。", baihua: "最拗的是西方之水还向南方，最刚的是东方之火转往北方。", note: ""),
                ClassicLine(id: "lq-24-7", n: 7, orig: "顺生之机，遇击神而亢。", baihua: "顺生之机，遇到击神就亢奋。", note: ""),
                ClassicLine(id: "lq-24-8", n: 8, orig: "逆生之序，见闲神而狂。", baihua: "逆生之序，见到闲神就狂乱。", note: ""),
                ClassicLine(id: "lq-24-9", n: 9, orig: "阳明遇金，郁而多烦。", baihua: "阳明遇到金，郁闷而多烦恼。", note: ""),
                ClassicLine(id: "lq-24-10", n: 10, orig: "阴浊藏火，包而多滞。", baihua: "阴浊藏着火，包藏而多滞塞。", note: ""),
                ClassicLine(id: "lq-24-11", n: 11, orig: "羊刃局，强则逞威，弱则怕事；伤官格，清则谦和，浊则刚猛。", baihua: "羊刃局：强就逞威，弱就怕事；伤官格：清就谦和，浊就刚猛。", note: ""),
                ClassicLine(id: "lq-24-12", n: 12, orig: "用神多者，情性不常。", baihua: "用神多的人，情性不常。", note: ""),
                ClassicLine(id: "lq-24-13", n: 13, orig: "时支浊者，虎头蛇尾。", baihua: "时支浊的人，虎头蛇尾。", note: ""),
            ]),
            ClassicChapter(id: "lq-25", no: "六亲论二十五", title: "疾病", status: "included", source: "《滴天髓》六亲论二十五·疾病", lines: [
                ClassicLine(id: "lq-25-1", n: 1, orig: "五行和者，一世无灾。", baihua: "五行和的人，一世无灾。", note: ""),
                ClassicLine(id: "lq-25-2", n: 2, orig: "血气乱者，生平多疾。", baihua: "血气乱的人，生平多疾病。", note: ""),
                ClassicLine(id: "lq-25-3", n: 3, orig: "忌神入五脏而病凶，客神游六经而灾小。", baihua: "忌神入五脏则病凶，客神游六经则灾小。", note: ""),
                ClassicLine(id: "lq-25-4", n: 4, orig: "木不受水者血病，土不受火者气伤。", baihua: "木不受水的人血有病，土不受火的人气受伤。", note: ""),
                ClassicLine(id: "lq-25-5", n: 5, orig: "金水伤官，寒则冷嗽，热则痰火；火土印绶，热则风痰，燥则皮痒。", baihua: "金水伤官：寒就冷嗽，热就痰火；火土印绶：热就风痰，燥就皮痒。", note: ""),
                ClassicLine(id: "lq-25-6", n: 6, orig: "论痰多木火，生毒郁火金。", baihua: "论痰多是木火，生毒是郁结的火金。", note: ""),
                ClassicLine(id: "lq-25-7", n: 7, orig: "金水枯伤而肾经虚，水土相胜而脾胃泄。", baihua: "金水枯伤则肾经虚，水土相胜则脾胃泄。", note: ""),
            ]),
            ClassicChapter(id: "lq-26", no: "六亲论二十六", title: "出身", status: "included", source: "《滴天髓》六亲论二十六·出身", lines: [
                ClassicLine(id: "lq-26-1", n: 1, orig: "巍巍科第迈等伦，一个玄机暗里存。", baihua: "巍巍科第超过同伦，一个玄机暗里藏着。", note: ""),
                ClassicLine(id: "lq-26-2", n: 2, orig: "清得尽时黄榜客，虽存浊气亦中式。", baihua: "清得尽时是黄榜客，即便还存浊气也能中式。", note: ""),
                ClassicLine(id: "lq-26-3", n: 3, orig: "秀才不是尘凡子，清气还嫌官不起。", baihua: "秀才不是尘凡子，清气还嫌官星不起。", note: ""),
                ClassicLine(id: "lq-26-4", n: 4, orig: "异路功名莫轻说，日干得气遇财星。", baihua: "异路功名不要轻说，要看日干得气、遇到财星。", note: ""),
            ]),
            ClassicChapter(id: "lq-27", no: "六亲论二十七", title: "地位", status: "included", source: "《滴天髓》六亲论二十七·地位", lines: [
                ClassicLine(id: "lq-27-1", n: 1, orig: "台阁勋名百世传，天然清气显机权。", baihua: "台阁勋名百世流传，天然清气显出机权。", note: ""),
                ClassicLine(id: "lq-27-2", n: 2, orig: "兵权獬豸弁冠客，刃煞神清气势特。", baihua: "掌兵权、做法官的人，刃煞神清、气势特异。", note: ""),
                ClassicLine(id: "lq-27-3", n: 3, orig: "分藩司牧财官和，格局清纯神气多。", baihua: "分藩司牧的人财官和，格局清纯、神气多。", note: ""),
                ClassicLine(id: "lq-27-4", n: 4, orig: "便是诸司并首领，也从清浊分形影。", baihua: "便是各司首领，也从清浊分形影。", note: ""),
            ]),
            ClassicChapter(id: "lq-28", no: "六亲论二十八", title: "岁运", status: "included", source: "《滴天髓》六亲论二十八·岁运", lines: [
                ClassicLine(id: "lq-28-1", n: 1, orig: "休咎系乎运，尤系乎岁，战冲视其孰降，和好视其孰切。", baihua: "休咎系于运，尤其系于岁；战冲看谁降服谁，和好看谁亲切谁。", note: ""),
                ClassicLine(id: "lq-28-2", n: 2, orig: "何为战？何为冲？何为和？何为好？", baihua: "什么叫战？什么叫冲？什么叫和？什么叫好？", note: ""),
            ]),
            ClassicChapter(id: "lq-29", no: "六亲论二十九", title: "贞元", status: "included", source: "《滴天髓》六亲论二十九·贞元", lines: [
                ClassicLine(id: "lq-29-1", n: 1, orig: "造化起于元，亦起于贞。", baihua: "造化起于元，也起于贞。", note: ""),
                ClassicLine(id: "lq-29-2", n: 2, orig: "再肇贞元之会，胚胎嗣续之机。", baihua: "再开贞元之会，是胚胎嗣续的机括。", note: ""),
                ClassicLine(id: "lq-29-3", n: 3, orig: "何为元？何为亨？何为利？何为贞？", baihua: "什么叫元？什么叫亨？什么叫利？什么叫贞？", note: ""),
            ]),
        ]),
        ClassicBook(id: "ziping", title: "子平真诠", author: "清·沈孝瞻", script: "traditional", source: "", sourceURL: "https://libokang.com/zh-hant/classics/bazi/%E5%AD%90%E5%B9%B3%E7%9C%9F%E8%A9%AE%E5%8E%9F%E6%96%87/", scopeNote: "全书一～四十七篇全文逐句已入库（一～十篇干支基础与用神总论；十一～四十七篇 G17 续补）。篇数说明：任务简报称 48 篇；本底本正文为一～四十七篇，凡例亦自述分列 47 篇，48 篇之说当为含附篇的别种计数，本批按底本实际 47 篇入库。底本讹字照录不改，校勘见各句 note。", chapters: [
            ClassicChapter(id: "zp-01", no: "一", title: "論十干十二支", status: "included", source: "《子平真詮》一·論十干十二支", lines: [
                ClassicLine(id: "zp-01-1", n: 1, orig: "天地之間，一氣而己。", baihua: "天地之间，本原只是一团气而已。", note: "底本「一氣而己」，「己」為「已」之訛，通行本作「一氣而已」。"),
                ClassicLine(id: "zp-01-2", n: 2, orig: "惟有動靜，遂分陰陽。", baihua: "这团气有动有静，于是分出阴阳。", note: ""),
                ClassicLine(id: "zp-01-3", n: 3, orig: "有老少，遂分四象。", baihua: "动静又有老少之别，于是分出四象。", note: ""),
                ClassicLine(id: "zp-01-4", n: 4, orig: "老者極動靜之時，是為太陽太陰；少者初動初靜之際，是為少陰少陽。", baihua: "动静到极处叫老，是太阳太阴；刚开始动静叫少，是少阴少阳。", note: ""),
                ClassicLine(id: "zp-01-5", n: 5, orig: "有是四象，而五行具於其中矣。", baihua: "有了这四象，五行也就包含在其中了。", note: ""),
                ClassicLine(id: "zp-01-6", n: 6, orig: "水者，太陰也；火者，太陽也；木者，少陽也；金者，少陰也；土者，陰陽老少、木火金水沖氣所結也。", baihua: "水是太阴，火是太阳，木是少阳，金是少阴；土是阴阳老少、木火金水冲和之气凝结而成。", note: ""),
                ClassicLine(id: "zp-01-7", n: 7, orig: "有是五行，何以又有十干十二支乎？蓋有陰陽，因生五行，而五行之中，各有陰陽。即以木論，甲乙者，木之陰陽也。甲者，乙之氣；乙者，甲之質。", baihua: "既然有了五行，为什么还要再立十干十二支？因为先有阴阳才生五行，而五行之中每一行又各有阴阳。就拿木来说，甲乙就是木的阴阳：甲是乙的气，乙是甲的质。", note: ""),
                ClassicLine(id: "zp-01-8", n: 8, orig: "在天為生氣，而流行於萬物者，甲也；在地為萬物，而承茲生氣者，乙也。", baihua: "在天上作为生发之气、流行于万物的，是甲；在地上凝成万物形体、承受这股生气的，是乙。", note: ""),
                ClassicLine(id: "zp-01-9", n: 9, orig: "又細分之，生氣之散佈者，甲之甲，而生氣之凝成者，甲之乙；萬木之所以有枝葉者，乙之甲，而萬木之枝枝葉葉者，乙之乙也。方其為甲，而乙之氣已備；及其為乙，而甲之質乃堅。有是甲乙，而木之陰陽具矣。", baihua: "再细分：生气散布的状态是甲之中的甲，生气凝聚的状态是甲之中的乙；草木长出枝叶的力量是乙之中的甲，实际长成的一枝一叶是乙之中的乙。当它还是甲时，乙的成形之机已蕴含在内；等它成了乙，甲的生气也固结为坚实的形质。有了甲乙这一对，木的阴阳就齐备了。", note: ""),
                ClassicLine(id: "zp-01-10", n: 10, orig: "何以復有寅卯者，又與甲乙分陰陽天地而言之者也。以甲乙而分陰陽，則甲為陽，乙為陰，木之行於天而為陰陽者也。以寅卯而陰陽，則寅為陽，卯為陰，木之存乎地而為陰陽者也。", baihua: "为什么还要再有寅卯？这是因为甲乙与寅卯之间，还要按天与地再分一层阴阳：单就甲乙相比，甲为阳乙为阴，这是木行于天时的阴阳；单就寅卯相比，寅为阳卯为阴，这是木存于地时的阴阳。", note: ""),
                ClassicLine(id: "zp-01-11", n: 11, orig: "以甲乙寅卯而統分陰陽，則甲乙為陽，寅卯為陰，木之在天成象而在地成形者也。甲乙行乎天，而寅卯受之；寅卯存乎也，而甲乙施焉。", baihua: "把甲乙寅卯合起来通盘划分，则甲乙整体属阳、寅卯整体属阴，因为甲乙是木在天上成象，寅卯是木在地上成形。甲乙之气运行在天，寅卯在地上承受它；寅卯静守于地，甲乙的生气则施加于其上。", note: "底本「寅卯存乎也」，「也」為「地」之訛，當作「寅卯存乎地」。"),
                ClassicLine(id: "zp-01-12", n: 12, orig: "是故甲乙如官長，寅卯如該管地方。甲祿於寅，乙祿於卯，如府官之在郡，縣官之在邑，而各司一月之令也。", baihua: "所以甲乙好比朝廷派下的官长，寅卯好比这位官长所管辖的地方。甲的禄在寅、乙的禄在卯，就像知府坐镇本郡、知县坐镇本邑，各自主管一个月的时令。", note: ""),
                ClassicLine(id: "zp-01-13", n: 13, orig: "甲乙在天，故動而不居。建寅之月，豈必當甲？建卯之月，豈必當乙？寅卯在地，故止而不遷。甲雖遞易，月必建寅；乙雖遞易，月必建卯。", baihua: "甲乙属天，是流动不居的，所以正月建寅时未必恰好轮到甲、二月建卯时也未必恰好轮到乙。寅卯属地，是固定不迁的，所以无论天干怎样更替，正月一定建寅、二月一定建卯。", note: ""),
                ClassicLine(id: "zp-01-14", n: 14, orig: "以氣而論，甲旺於乙；以質而論，乙堅於甲。而俗書謬論，以甲為大林，盛而宜斬，乙為微苗，脆而莫傷，可為不知陰陽之理者矣。", baihua: "就气而论，甲的生气比乙旺盛；就质而论，乙的形体比甲坚实。可是俗本命书胡乱比附，说甲是参天大林、长得旺就该砍伐，乙是纤细幼苗、脆弱不可伤损，这种说法完全不懂阴阳气质的分别。", note: ""),
                ClassicLine(id: "zp-01-15", n: 15, orig: "以木類推，餘者可知，惟土為木火金水沖氣，故寄旺於四時，而陰陽氣質之理，亦同此論。欲學命者，必須先知干支之說，然後可以入門。", baihua: "以木一行类推，其余火土金水也都是这个道理；只有土是木火金水四者的冲和之气，所以寄旺于四季之末，但它阴阳与气质的分别，仍与上面所讲的一样。想学命理的人，必须先把干支的这套道理弄明白，然后才谈得上入门。", note: ""),
            ]),
            ClassicChapter(id: "zp-02", no: "二", title: "論陰陽生克", status: "included", source: "《子平真詮》二·論陰陽生克", lines: [
                ClassicLine(id: "zp-02-1", n: 1, orig: "四時之運，相生而成，故木生火，火生土，土生金，金生水，水復生木，即相生之序，循環迭運，而時行不匱。", baihua: "四季的运行靠相生来完成：木生火、火生土、土生金、金生水、水又回过头来生木，这就是相生的次序，循环往复不断轮转，所以时令流转永不匮乏。", note: ""),
                ClassicLine(id: "zp-02-2", n: 2, orig: "然而有生又必有克，生而不克，則四時亦不成矣。克者，所以節而止之，使之收斂，以為發洩之機，故曰“天地節而四時成”。", baihua: "但是有生就一定要有克，只生不克，四季反而成不了。克的作用是节制、遏止，把外散的气收敛回来，为下一轮的发泄储备本钱，所以《周易》说“天地节而四时成”。", note: ""),
                ClassicLine(id: "zp-02-3", n: 3, orig: "即以木論，木盛於夏，殺於秋，殺者，使發洩於外者藏收內，是殺正所以為生，大易以收劍為性情之實，以兌為萬物所說，至哉言乎！", baihua: "以木为例：木在夏天最盛，到秋天被金所杀伐；这个杀是把已经向外发散的生气收藏回内里，所以杀恰恰正是为了下一次的生。《周易》把收敛看作性情的实处，又以属秋属金的兑卦为万物所喜悦，这话真是说到根子上了。", note: "底本「大易以收劍為性情之實」，「劍」為「斂」之訛，當作「大易以收斂為性情之實」。"),
                ClassicLine(id: "zp-02-4", n: 4, orig: "譬如人之養生，固以飲食為生，然使時時飲食，而不使稍飢以待將來，人壽其能久乎？是以四時之運，生與克同用，克與生同功。", baihua: "打个比方：人靠饮食活命，可是如果一刻不停地吃，从不让肚子稍微饿一饿、留出下一次进食的余地，人还能长寿吗？所以四季运行之中，生与克是并用的，克的功劳和生一样大。", note: ""),
                ClassicLine(id: "zp-02-5", n: 5, orig: "然以五行而統論之，則水木相生，金木相剋。以五行之陰陽而分配之，則生克之中，又有異同。此所以水同生木，而印有偏正；金同克木，而局有官煞也。", baihua: "不过，如果只笼统按五行来说，那就是水生木、金克木两句话。可是一旦把五行各自的阴阳再分开配对，生与克之中就又有了同异之别。这正是为什么同样是水生木，生我者却要分正印与偏印；同样是金克木，成局却要分正官与七煞。", note: ""),
                ClassicLine(id: "zp-02-6", n: 6, orig: "印綬之中，偏正相似，生克之殊，可置勿論；而相剋之內，一官一煞，淑慝判然，其理不可不細詳也。", baihua: "印绶这一类里，偏印正印性质相近，那点阴阳差别可以暂且不论；但在相克这一类里，一个是正官、一个是七煞，一善一恶界限分明，其中道理不能不细细分辨。", note: ""),
                ClassicLine(id: "zp-02-7", n: 7, orig: "即以甲乙庚辛言之。甲者，陽木也，木之生氣也；乙者，陰木也，木之形質也。庚者，陽金也，秋天肅殺之氣也；辛者，陰金也，人間五金之質也。木之生氣，寄於木而行於天，故逢秋天為官，而乙則反是，庚官而辛殺也。", baihua: "就用甲乙庚辛四个字来说明：甲是阳木，代表木的生发之气；乙是阴木，代表木的形体质地。庚是阳金，是秋天肃杀的杀伐之气；辛是阴金，是人间金银铜铁一类的金属实体。木的生气寄托在木上而运行于天，遇上秋天的肃杀之气就要受它节制；乙的情形正相反，对乙来说庚是正官而辛是七煞。", note: "底本此句作「逢秋天為官」，按十神通例甲逢庚同為陽，當作七煞，此處疑有訛字，今照錄不改。"),
                ClassicLine(id: "zp-02-8", n: 8, orig: "又以丙丁庚辛言之。丙者，陽火也，融和之氣也；丁者，陰火也，薪傳之火也。秋天肅殺之氣，逢陽和而克去，而人間之金，不畏陽和，此庚以丙為殺，而辛以丙為官也。", baihua: "再用丙丁庚辛四个字来说。丙是阳火，是温暖融和、弥漫无形的阳和之气；丁是阴火，是柴薪相传、附着于物的灯烛炉火。秋天那股肃杀之气也就是庚，一遇到弥漫的阳和之气就被化解克去；可是人间的金属实体也就是辛，却不怕这种温和的暖气——所以对庚来说丙是七煞，对辛来说丙是正官。", note: ""),
                ClassicLine(id: "zp-02-9", n: 9, orig: "人間金鐵之質，逢薪傳之火而立化，而肅殺之氣，不畏薪傳之火。此所以辛以丁為殺，而庚以丁為官也。即此以推，而餘者以相剋可知矣。", baihua: "反过来，人间金铁的形质遇上柴薪炉火立刻熔化，而无形的肃杀之气却不怕这种有形的薪火——所以对辛来说丁是七煞，对庚来说丁是正官。照这个思路推下去，其余各行相克时的官煞分别，也都可以举一反三地明白。", note: ""),
            ]),
            ClassicChapter(id: "zp-03", no: "三", title: "論陰陽生死", status: "included", source: "《子平真詮》三·論陰陽生死", lines: [
                ClassicLine(id: "zp-03-1", n: 1, orig: "五行干支之說，已詳論於干支篇。干動而不息，支靜而有常。以每干流行於十二支之月，而生旺墓絕繫焉。陽主聚，以進為進，故主順；陰主散，以退為退，故主逆。", baihua: "五行与干支的基本道理，前面《论十干十二支》一篇已经讲得很详细了。要点是：天干属动，运行不停；地支属静，位置恒常。把每一个天干放到十二支所代表的十二个月里走一遍，长生、帝旺、墓、绝这一套十二长生的位次就系在上面了。阳干主聚合，以向前推进为进，所以在十二支上顺行；阴干主发散，以向后回缩为进，所以在十二支上逆行。", note: ""),
                ClassicLine(id: "zp-03-2", n: 2, orig: "此生沐浴等項，所以有陽順陰逆之殊也。四時之運，功成者去，等用者進，故每流行於十二支之月，而生旺墓絕，又有一定。陽之所生，即陰之所死，彼此互換，自然之運也。", baihua: "长生、沐浴这一系列名目之所以有阳顺阴逆的分别，原因就在这里。四季的运行是功成者退去、待用者上前，所以每个天干在十二个月中走过，生旺墓绝各有一定的位置。阳干长生之处正是阴干死绝之处，彼此互相交换，这是自然而然的气运，并非人为安排。", note: "底本「此生沐浴等項」，「此」下脫一「長」字，當作「此長生沐浴等項」；「等用者進」之「等」為「待」之訛。"),
                ClassicLine(id: "zp-03-3", n: 3, orig: "即以甲乙論，甲為木之陽，木之枝枝葉葉，受天生氣，己收藏飽足，可以為來克發洩之機，此其所以生於亥也。", baihua: "就用甲乙来说。甲是木的阳面，代表生气。到了亥月，草木的枝枝叶叶已经把从天而降的生气收藏得饱满充足，正好作为来年春天重新发泄的本钱，所以甲的长生定在亥。", note: "底本「己收藏飽足」之「己」為「已」之訛；「可以為來克發洩之機」之「克」為「春」之訛，當作「來春發洩之機」。"),
                ClassicLine(id: "zp-03-4", n: 4, orig: "木當午月，正枝葉繁盛之候，而甲何以死？卻不是外雖繁盛，而內之生氣發洩已盡，此其所以死於午也。乙木反是，午月枝葉繁盛，即為之生，亥月枝葉剝落，即為之死。以質而論，自與氣殊也。以甲乙為例，餘可知矣。", baihua: "可是木到了午月，正是枝繁叶茂的时候，甲为什么反而算死？须知外表虽然繁盛，内里的生气却已经发泄殆尽——正因为如此，甲的死才定在午。乙木的情形恰好相反：午月枝叶最盛，对代表形质的乙来说就是生；亥月枝叶凋落，对乙来说就是死。可见按形质来论，本来就与按气来论不同。拿甲乙作例子，其余各干阳顺阴逆的道理也就可以推知了。", note: ""),
                ClassicLine(id: "zp-03-5", n: 5, orig: "支有十二月，故每干長生至胎養，亦分十二位。氣之由盛而衰，衰而復盛，逐節細分，遂成十二。而長生沐浴等名，則假借形容之詞也。", baihua: "地支共有十二位，对应十二个月，所以每个天干从长生一路排到胎、养，也正好分成十二个位次。气由盛转衰、由衰再转盛，把这个过程逐节细分，就成了十二段。至于长生、沐浴这些名称，都是借人一生的经历打的比方，是形容之词，不可拘泥字面。", note: ""),
                ClassicLine(id: "zp-03-6", n: 6, orig: "長生者，猶人之初生也。沐浴者，猶人既生之後，而沐浴以去垢；如果核既為苗，則前之青殼，洗而去之矣。冠帶者，形氣漸長，猶人之年長而冠帶也。臨官者，由長而壯，猶人之可以出仕也。帝旺者，壯盛之極，猶人之可以輔帝而大有為也。", baihua: "长生，好比人刚出生。沐浴，好比人生下来之后洗去污垢；就像果核已经发成幼苗，先前包裹它的青壳就要洗刷掉。冠带，是形体气力渐渐长成，好比人成年行冠礼、束衣带。临官，是由长成而壮实，好比人可以出来做官任事。帝旺，是壮盛到了极点，好比人可以辅佐帝王大有作为。", note: ""),
                ClassicLine(id: "zp-03-7", n: 7, orig: "衰者，盛極而衰，物之初變也。病者，衰之甚也。死者，氣之盡而無餘也。墓者，造化收藏，猶人之埋於土者也。絕者，前之氣已絕，後之氣將續也。胎者，後之氣續而結聚成胎也。養者，如人養母腹也。自是而後，長生循環無端矣。", baihua: "衰，是盛极而转衰，事物开始起变化。病，是衰得更厉害了。死，是气耗尽而一无所余。墓，是造化把它收藏起来，好比人死后埋入土中。绝，是前一轮的气已经断绝、后一轮的气尚未接上。胎，是后一轮的气接续上了、凝结成胎。养，好比胎儿在母腹中受养。从养再往下，就又回到长生，如此循环不息，没有起点也没有终点。", note: ""),
                ClassicLine(id: "zp-03-8", n: 8, orig: "人之日主，不必生逢祿旺，即月令休囚，而年日時中，得長祿旺，便不為弱，就使逢庫，亦為有根。時產謂投庫而必沖者，俗書之謬也。", baihua: "一个人的日主，也就是日柱天干、代表命主本人，不一定非要生在临官帝旺之月才算强。即使月令对日主是休囚失气的，只要年柱、日支、时柱中能碰上长生或禄旺，就不算弱；哪怕只是碰上墓库，也算通根有依托。俗书说日主入库就必须靠冲开才能用，那是荒谬之谈。", note: "底本「得長祿旺」，「長」下脫一「生」字，當作「得長生祿旺」；「時產謂投庫而必沖者」之「時產」二字為「俗」之訛。"),
                ClassicLine(id: "zp-03-9", n: 9, orig: "但陽長生有力，而陰長生不甚有力，然亦不弱。若是逢庫，則陽為有根，而陰為無用。蓋陽大陰小，陽得兼陰，陰不能兼陽，自然之理也。", baihua: "不过其中要分轻重：阳干的长生力量足，阴干的长生力量就差些，但也不能算弱。至于遇到墓库，阳干算有根，阴干则派不上用场。这是因为阳大阴小，阳能兼容阴，阴却兼容不了阳，乃是自然之理。", note: ""),
            ]),
            ClassicChapter(id: "zp-04", no: "四", title: "論十干配合性情", status: "included", source: "《子平真詮》四·論十干配合性情", lines: [
                ClassicLine(id: "zp-04-1", n: 1, orig: "合化之義，以十干陰陽相配而成。河圖之數，以一二三四五配六七八十，先天之道也。故始於太陰之水，而終於沖氣之土，以氣而語其生之序也。", baihua: "天干合化的道理，是由十干按阴阳相配而成的。《河图》之数，以一二三四五配六七八九十，这是先天生成之数。若按气来讲五行相生的次序，则从太阴之水开始，到冲和之气的土结束。", note: "底本「配六七八十」，「八」下脫一「九」字，當作「配六七八九十」。"),
                ClassicLine(id: "zp-04-2", n: 2, orig: "蓋未有五行之先，必先有陰陽老少，而後沖氣，故生以土。終之既有五行，則萬物又生於土，而水火木金，亦寄質焉，故以土先之。", baihua: "因为在五行未分之前，先有阴阳老少，然后才有冲和之气，所以土排在生序的最后。可是等到五行已经齐备，万物却又都从土里生出来，水火木金也都要寄托形质于土，所以论万物化生时又要把土排在最前。", note: ""),
                ClassicLine(id: "zp-04-3", n: 3, orig: "是以甲己相合之始，則化為土；土則生金，故乙庚化金次之；金生水，故丙辛化水又次之；水生木，故丁壬化木又次之；木生火，故戊癸化火又次之，而五行遍焉。先之以土，相生之序，自然如此。此十干合化之義也。", baihua: "正因如此，天干合化从甲与己相合开始，化出的是土；土能生金，所以乙与庚合化金排第二；金生水，所以丙与辛合化水排第三；水生木，所以丁与壬合化木排第四；木生火，所以戊与癸合化火排第五——一轮下来，五行就走遍了。合化以土打头，正是顺着相生之序自然排下来的。以上就是十干合化的义理所在。", note: ""),
                ClassicLine(id: "zp-04-4", n: 4, orig: "其性情何也？蓋既有配合，必有向背。如甲用辛官，透丙作合，而官非其官；甲用癸印，透戊作合，而印非其印；甲用己財，己與別位之甲作合，而財非其財。", baihua: "那么合化在性情上有什么讲究呢？既然有了两干相配，就必然产生亲向与背离的分别。举例来说：甲日主本来要用辛作正官，偏偏命里透出丙，丙与辛相合，辛的心思被丙牵走，这个正官就不再为我所用了；甲要用癸作正印，却透出戊，戊癸相合，这个印也不是我的印了；甲要用己作正财，可是己已经和别的位置上的甲合住，这个财也不是我的财了。", note: ""),
                ClassicLine(id: "zp-04-5", n: 5, orig: "如年己月甲，年上之財，被月合去，而日主之甲乙無分；年甲月己，月上之財，被年合去，而日主之甲乙不與是也。甲用丙食與辛作合，而非其食，此四喜神因合而無用者也。", baihua: "比如年干是己、月干是甲，年上那个财已被月干合走，日主甲乙就分不到；反过来年干是甲、月干是己，月上那个财被年干合走，日主同样沾不上边。又如甲用丙作食神，丙却与辛相合，这个食神也就不成其为食神。以上是正官、正印、正财、食神这四个喜神因为被合而失去作用的情形。", note: ""),
                ClassicLine(id: "zp-04-6", n: 6, orig: "又如甲逢庚為煞，與乙作合，而煞不攻身；甲逢乙為劫財，甲逢丁為傷，與壬作合，而丁不為傷官；甲逢壬為梟，與丁作合，而壬不奪食。此四忌神因合化吉者也。", baihua: "反过来看凶神也一样。甲遇到庚是七煞，若有乙来与庚相合，庚被牵住，七煞就不来攻身了；甲遇到丁是伤官，若丁与壬相合，丁就不再逞其伤官之性；甲遇到壬是枭神，本会夺食，若壬与丁相合，壬也就夺不了食神。这是七煞、劫财、伤官、枭神这四个忌神因为被合而转凶为吉的情形。", note: ""),
                ClassicLine(id: "zp-04-7", n: 7, orig: "蓋有所合則有所忌，逢吉不為吉，逢凶不為凶。即以六親言之，如男以財為妻，而被別干合去，財妻豈能親其夫乎？女以官為夫，而被他干合去，官夫豈能愛其妻乎？此謂配合之性情，因向背而殊也。", baihua: "总之，只要发生了相合，就有所牵制：碰上吉神未必真吉，碰上凶神也未必真凶。就六亲来讲也是这个道理：男命以正财为妻，财若被别的天干合走，这个财妻还能亲近自己的丈夫吗？女命以正官为夫，官若被别的天干合走，这个官夫还能疼爱自己的妻子吗？这就是所谓配合的性情，会因为亲向或背离而大不相同。", note: ""),
            ]),
            ClassicChapter(id: "zp-05", no: "五", title: "論十干合而不合", status: "included", source: "《子平真詮》五·論十干合而不合", lines: [
                ClassicLine(id: "zp-05-1", n: 1, orig: "十干化合之義，前篇既明之矣，然而亦有合而不合者，何也？蓋隔於有所間也，譬如人彼此相好，而有人從中間之，則交必不能成。", baihua: "十干合化的义理，上一篇已经讲明白了。但还有一种看着是合、实际不合的情形，这是为什么呢？原因在于两干之间被别的东西隔断了。好比两个人本来相好，中间偏有第三者插进来横加阻拦，这交情就成不了。", note: ""),
                ClassicLine(id: "zp-05-2", n: 2, orig: "譬如甲與己合，而甲己中間，以庚間隔之，則甲豈能越克我之庚而合己？此制於勢然也，合而不敢合也，有若無也。", baihua: "比如甲与己本该相合，可甲己之间夹着一个庚，庚是克甲的七煞，甲连自身都要提防，哪里还敢越过克我的庚去与己相合？这是被形势所制，属于想合而不敢合，等于没有合。", note: ""),
                ClassicLine(id: "zp-05-3", n: 3, orig: "又有隔位太遠，如甲在年干，己在時上，心雖相契，地則相遠，如人天南地北，不能相合一般。然於有所制而不敢合者，亦稍有差，合而不能合也，半合也，其為禍福得十之二三而已。", baihua: "还有一种是位置隔得太远，比如甲在年干、己在时干，中间隔了两位，心虽相契而地却相远，像两个人一在天南、一在地北，根本合不拢。不过这种情形与前面被制而不敢合还略有差别：它是想合而合不上，只能算半合，吉凶应验大约只有十分之二三的力量。", note: ""),
                ClassicLine(id: "zp-05-4", n: 4, orig: "又有合而無傷於合者，何也？如甲生寅卯，月時兩透辛官，以年丙合月辛，是為合一留一，官星反輕。甲逢月刃，庚辛並透，丙與辛合，是為合官留煞，而煞刃依然成格，皆無傷於合也。又有合而不以合論者，何也？本身之合也。", baihua: "还有一种情形，虽然发生了相合却并不因此坏事，这是为什么？比如甲日主生在寅月或卯月，月干和时干都透出辛作正官，官星重叠本是毛病，此时年干有丙来合住月干的辛，合掉一个、留下一个，官星的分量反而恰到好处。又比如甲日主生在卯月坐羊刃，庚这个七煞与辛这个正官同时透出，成了官煞混杂，这时丙来与辛相合，把正官合去、留下七煞，煞刃相济的格局照样成立。这两例中的合，不但无害，反而有功。另外还有一种虽合而不按合去论的情形，那就是日主本身与人相合。", note: ""),
                ClassicLine(id: "zp-05-5", n: 5, orig: "蓋五陽逢財，五陰遇官，俱是作合，惟是本身十干合之，不為合去。假如乙用庚官，日干之乙，與庚作合，是我之官，是我合之。何為合去？若庚在年上，乙在月上，則月上之乙，先去合庚，而日干反不能合，是為合去也。", baihua: "五个阳干遇到与自己相合的那个字，那个字正好是它的正财；五个阴干遇到与自己相合的那个字，那个字正好是它的正官——这些都构成相合。但只要是日主本人去与它相合，就不算合去。比如乙日主用庚为正官，日干的乙与庚相合，这本来就是我的官、又是我亲自去合它，等于牢牢握在手里，怎么能算合去呢？可是如果庚在年干、另一个乙在月干，那么月干的乙先一步把庚合住，日干反而合不着，这才叫合去。", note: ""),
                ClassicLine(id: "zp-05-6", n: 6, orig: "又如女以官為夫，丁日逢壬，是我之夫，是我合之，正如夫妻相親，其情愈密。惟壬在月上，而年丁合之，日干之丁，反不能合，是以己之夫星，被姊妹合去，夫星透而不透矣。", baihua: "又比如女命以正官为丈夫，丁日主遇到壬，壬是我的丈夫、又由我亲自去合，正如夫妻相亲，情分愈发亲密。可要是壬在月干而年干另有一个丁去合它，日干的丁便合不上——自己的夫星被姐妹合走了，夫星虽然透出，等于没透。", note: ""),
                ClassicLine(id: "zp-05-7", n: 7, orig: "然又有爭合妒合之說，何也？如兩辛合丙，兩丁合壬之類，一夫不娶二妻，一女不配二夫，所以有爭合妒合之說。然到底終有合意，但情不專耳。若以兩合一而隔位，則全無爭妒。", baihua: "另外还有争合妒合的说法，那是什么意思？比如两个辛同时去合一个丙、两个丁同时去合一个壬之类。一个丈夫不能娶两个妻子，一个女子不能配两个丈夫，所以叫争合、妒合。不过到底还是有相合之意在，只是感情不专一罢了。倘若这两个来合一个的字彼此隔着位置，那就谈不上争妒。", note: ""),
                ClassicLine(id: "zp-05-8", n: 8, orig: "如庚午、乙酉、甲子、乙亥，兩乙合庚，甲日隔之，此高太尉命，仍作合煞留官，無減福也。化氣有真有假。上兩造為化氣之真者，亦有化氣有餘，而日帶根苗劫印者；有日主無根，而化神不足者；更有合化雖真，而閒神來傷化氣者，皆為假化。", baihua: "例如庚午、乙酉、甲子、乙亥这个八字，月干与时干两个乙都要去合年干的庚，中间隔着甲日主，这是高太尉的命，仍旧按合煞留官来论，乙合去庚煞、留下酉中辛金正官，福分并不因争合而减损。至于合化，有真化也有假化。上面所举的命造属于化气之真的；此外还有几种情形：化神有余而日主自身另带根苗、劫财或印绶牵扯的，日主无根而化出来的那一行气又不足的，以及虽然合化是真、却有闲神来损伤化神的——这些都算假化。", note: ""),
            ]),
            ClassicChapter(id: "zp-06", no: "六", title: "論十干得時不旺失時不弱", status: "included", source: "《子平真詮》六·論十干得時不旺失時不弱", lines: [
                ClassicLine(id: "zp-06-1", n: 1, orig: "書云，得時俱為旺論，失時便作衰看，雖是至理，亦死法也。然亦可活看。夫五行之氣，流行四時，雖日干各有專令，而其實專令之中，亦有並存者在。", baihua: "命书上说“得时就一律按旺看，失时就一律按衰看”，这话虽是至理，却也是死法，还可以活看。五行之气在四季中流转，虽然每个天干各有自己当令的季节，但在某一行专主时令的同时，别行也并没有消失。", note: ""),
                ClassicLine(id: "zp-06-2", n: 2, orig: "假若春木司令，甲乙雖旺，而此時休囚之戊己，亦嘗豔於天地也。特時當退避，不能爭先，而其實春土何嘗不生萬物，冬日何嘗不照萬國乎？", baihua: "譬如春天木当令，甲乙固然旺，可是此刻处于休囚的戊己土，难道就不存在于天地之间了吗？只是时令轮不到它，它得退避一步、不能争先罢了；实际上春天的土何尝不生养万物？冬天的太阳何尝不照耀四方？", note: "底本「亦嘗豔於天地也」，「豔」為「存」之訛，當作「亦嘗存於天地也」。"),
                ClassicLine(id: "zp-06-3", n: 3, orig: "況八字雖以月令為重，而旺相休囚，年月日時，亦有損益之權，故生月即不值令，而年時如值祿旺，豈便為衰？不可執一而論。", baihua: "何况八字虽以月令为最重，但旺相休囚的判断，年柱、月柱、日支、时柱都各有加减的权重。所以即便生月不当令，只要年柱、时柱上碰到临官、帝旺，怎么就能断为衰弱？这种事不可执着一端来论。", note: ""),
                ClassicLine(id: "zp-06-4", n: 4, orig: "猶如春木雖強，金太重而木亦危。干庚辛而支酉丑，無火制而晃富，逢土生而必夭，是以得時而不旺也。", baihua: "好比春天的木虽然当令强旺，可如果金太重，木照样危险：天干透庚辛、地支坐酉丑成金局，若没有火来制金，就算侥幸富裕也难长久，再遇土来生金必定短寿——这就是“得时而不旺”。", note: ""),
                ClassicLine(id: "zp-06-5", n: 5, orig: "秋木雖弱，木根深而木亦強。干甲乙而支寅卯，遇官透而能受，逢水生而太過，是失時不弱也。是故十干不論月令休囚，只要四柱有根，便能受財官食神而當傷官七煞。", baihua: "反过来，秋天的木虽然失令而弱，可只要木的根扎得深，木也一样强：天干透甲乙、地支坐寅卯，遇到官星透出也承受得住，再遇水来生木反而嫌太过——这就是“失时而不弱”。所以说，十天干不必只看月令是不是休囚，只要四柱之中有根，就能担得起财、官、食神这些顺用的吉神，也顶得住伤官、七煞这些逆用的凶神。", note: ""),
                ClassicLine(id: "zp-06-6", n: 6, orig: "長生祿旺，根之重者也；墓庫餘氣，根之輕者也。得一比肩，不如得支中一墓庫，如甲逢未、丙逢戌之類。乙逢戌、丁逢丑，不作此論，以戌中無藏木，丑中無藏火也。", baihua: "所谓通根，分量有轻有重：地支坐到长生、临官、帝旺，是重根；坐到墓库、余气，是轻根。得一个比肩帮身，还不如地支里得一个墓库来得实在——比如甲见未，未中藏乙木；丙见戌，戌中藏丁火。但乙见戌、丁见丑就不能这样算，因为戌中并不藏木、丑中并不藏火。", note: ""),
                ClassicLine(id: "zp-06-7", n: 7, orig: "得二比肩，不如得一餘氣，如乙逢辰、丁逢未之類。得三比肩，不如得一長生祿刃，如甲逢亥子寅卯之類。陰長生不作此論，如乙逢午、丁逢酉之類，然亦為明根，比得一餘氣。", baihua: "得两个比肩，还不如得一个余气，比如乙见辰，辰是木的余气；丁见未，未是火的余气。得三个比肩，还不如得一个长生、临官或羊刃，比如甲见亥为长生、见子为沐浴、见寅为临官、见卯为羊刃。阴干的长生不照此例算，比如乙见午、丁见酉，力量要打折扣；不过毕竟也是明摆着的根，大约相当于得一个余气。", note: ""),
                ClassicLine(id: "zp-06-8", n: 8, orig: "蓋比劫如朋友之相扶，通根如室家之可住；干多不如根重，理固然也。今人不知命理，見夏水冬火，不問有無通根，便為之弱。更有陽干逢庫，如壬逢辰、丙坐戌之類，不以為水火通根身庫，甚至求刑沖開之。此種謬論，必宜一切掃除也。", baihua: "这是因为比肩劫财好比朋友来搭把手，通根却好比自己有房有家可以安身；天干上帮手再多，也不如地支里根扎得深——道理本来如此。如今有些人不懂命理，一看见夏天生的水日主、冬天生的火日主，也不管地支里有没有根，张口就断为身弱。更有甚者，阳干坐到自己的墓库，例如壬见辰、辰是水库，丙坐戌、戌是火库，本是水火通根于身库，他们却不承认，甚至还要去求刑冲把库打开。这类谬论，必须一概扫除干净。", note: ""),
            ]),
            ClassicChapter(id: "zp-07", no: "七", title: "論刑沖會合解法", status: "included", source: "《子平真詮》七·論刑沖會合解法", lines: [
                ClassicLine(id: "zp-07-1", n: 1, orig: "刑者，三刑也，子卯巳申之類是也。沖者，六沖也，子午卯酉之類是也。會者，三會也，申子辰之類是也。合者，六合也，子與丑合之類是也。", baihua: "先把名目分清。“刑”指三刑，如子刑卯、巳刑申之类。“冲”指六冲，如子午相冲、卯酉相冲之类。“会”指三合会局，如申子辰会成水局之类。“合”指六合，如子与丑相合之类。", note: ""),
                ClassicLine(id: "zp-07-2", n: 2, orig: "此皆以地支宮分而言，繫對射之意也。三方為會，朋友之意也。並對為合，比鄰之意也。至於三刑取廡，姑且闕疑，雖不知其所以然，於命理亦無害也。八字支中，刑沖俱非美事，而三合六合，可以解之。", baihua: "这些都是就地支所占的方位宫分而言的：冲是两支正对而相射；会是三个地支分处三方、遥相呼应，取朋友相聚之意；合是两支并列相邻、彼此亲附，取邻里相好之意。至于三刑究竟取的什么义理，姑且存疑不论，虽然说不清所以然，对推命也没有妨碍。总之八字地支里出现刑与冲都不是好事，但三合与六合可以化解它们。", note: "底本「至於三刑取廡」，「廡」為「義」之訛，當作「三刑取義」。"),
                ClassicLine(id: "zp-07-3", n: 3, orig: "假如甲生酉月，逢卯則沖，而或支中有戌，則卯與戌合而不沖；有辰，則酉與辰合而不沖；有亥與未，則卯與亥未會而不沖；有巳與丑，則酉與巳丑會而不沖。是會合可以解沖也。", baihua: "举例说明。甲日主生在酉月，月令是正官，地支若再见卯，卯酉相冲，就要冲坏月令。可是地支中若另有戌，卯与戌六合，卯被绊住就不去冲了；若另有辰，辰与酉六合，酉被护住也就不受冲；若另有亥和未，卯与亥未三合成木局，心思用在会局上，也不冲了；若另有巳和丑，酉与巳丑三合成金局，同样不冲。这就是会与合可以解冲。", note: ""),
                ClassicLine(id: "zp-07-4", n: 4, orig: "又如丙生子月，逢卯則刑，而或支中有戌，則與戌合而不刑；有丑，則子與丑合而不刑；有亥與未，則卯與亥未會而不刑；有申與辰，則子與申辰會而不刑。是會合可以解刑也。", baihua: "再如丙日主生在子月，地支见卯，子卯相刑。可是若另有戌，卯与戌合就不刑；若另有丑，子与丑合就不刑；若另有亥和未，卯去会成木局就不刑；若另有申和辰，子去会成水局也不刑。这就是会与合可以解刑。", note: "底本此句作「則與戌合而不刑」，「則」下脫一「卯」字，當作「則卯與戌合而不刑」。"),
                ClassicLine(id: "zp-07-5", n: 5, orig: "又有因解而反得刑沖者，何也？假如甲生子月，支逢二卯相併，二卯不刑一子，而支又逢戌，戌與卯合，本為解刑，而合去其一，則一合而一刑，是因解而反得刑沖也。", baihua: "还有一种本想解救、反而招来刑冲的情形，是怎么回事？譬如甲日主生在子月，地支并排出现两个卯，两卯争着刑一个子，力量分散，反倒刑不成；这时地支又来一个戌，戌与其中一个卯相合，本意是解刑，可它只合走了一个，剩下那个卯就单独去刑子了——一合一刑，反因解救而招致刑冲。", note: ""),
                ClassicLine(id: "zp-07-6", n: 6, orig: "又有刑沖而會合不能解者，何也？假如子年午月，日坐丑位，丑與子合，可以解沖，而時逢巳酉，則丑與巳酉會，而子復沖午；子年卯月，日坐戌位，戌與卯合，可以解刑，而或時逢寅午，則戌與寅午會，而卯復刑子。是會合而不能解刑沖也。", baihua: "又有一種已经有会合、却解不了刑冲的情形：比如年支子、月支午，子午本冲，日支坐丑，丑与子合，本可解冲；偏偏时支逢巳或酉，丑被拉去与巳酉会成金局，撇下了子，子又回过头来冲午。再如年支子、月支卯，日支坐戌，戌与卯合本可解刑；偏偏时支逢寅或午，戌被拉去与寅午会成火局，卯又回头来刑子。这就是有会合而不能解刑冲。", note: ""),
                ClassicLine(id: "zp-07-7", n: 7, orig: "更有刑沖而可以解刑者，何也？蓋四柱之中，刑沖俱不為美，而刑沖用神，尤為破格，不如以另位之刑沖，解月令之刑沖矣。", baihua: "更有一种用刑冲来解刑冲的办法，那是什么道理？四柱之中刑与冲都不是好事，但其中最要命的是刑冲伤到用神，那是直接破格。既然如此，不如用别的位置上的刑冲，把月令上的刑冲引开。", note: ""),
                ClassicLine(id: "zp-07-8", n: 8, orig: "假如丙生子月，卯以刑子，而支又逢酉，則又與酉沖不刑月令之官。甲生酉月，卯日沖之，而時逢子立，則卯與子刑，而月令官星，沖之無力，雖於別宮刑沖，六親不無刑剋，而月官猶在，其格不破。是所謂以刑沖而解刑沖也。", baihua: "譬如丙日主生在子月，子中癸水是正官，地支有卯来刑子，这时若再见一个酉，卯酉相冲，卯先顾着与酉相斗，就顾不上刑月令的官星了。又如甲日主生在酉月，正官在月令，日支卯来冲酉，这时时支若坐子，卯与子相刑，卯被牵制，冲月令官星的力量就弱了。虽然别的宫位起了刑冲，六亲上难免有些刑克，但月令的官星保住了，格局不至于破——这就是所谓以刑冲解刑冲。", note: ""),
            ]),
            ClassicChapter(id: "zp-08", no: "八", title: "論用神", status: "included", source: "《子平真詮》八·論用神", lines: [
                ClassicLine(id: "zp-08-1", n: 1, orig: "八字用神，專求月令，以日干配月令地支，而生克不同，格局分焉。財官印食，此用神之善而順用之者也；煞傷劫刃，用神之不善而逆用之者也。當順而順，當逆而逆，配合得宜，皆為貴格。", baihua: "八字取用神专从月令去找：拿日干与月令地支相配，两者之间生克关系不同，格局也就随之分立。财、官、印、食这四种是性质善良的用神，要顺着它的性子去用，叫顺用；煞、伤、劫、刃这四种是性质不善的用神，要逆着它的性子去制，叫逆用。该顺的就顺、该逆的就逆，配搭得宜，都能成为贵格。", note: ""),
                ClassicLine(id: "zp-08-2", n: 2, orig: "是以善而順用之，則財喜食神以相生，生官以護財；官喜透財以相生，生印以護官；印喜官煞以相生，劫才以護印；食喜身旺以相生，生財以護食。", baihua: "所以顺用善神时：财喜有食神来生它，又要生出官星来保护财；官喜透出财来生它，又要生出印来保护官；印喜有官煞来生它，又要靠劫财分掉财以保护印；食神喜身旺来供它发泄，又要生出财来保护食。", note: "底本「劫才以護印」，「才」為「財」之訛。"),
                ClassicLine(id: "zp-08-3", n: 3, orig: "不善而逆用之，則七煞喜食神以制伏，忌財印以資扶；傷官喜佩印以制伏，生財以化傷；陽刃喜官煞以制伏，忌官煞之俱無；月劫喜透官以制伏，利用財而透食以化劫。此順逆之大路也。", baihua: "逆用凶神时：七煞喜食神来制伏，忌财与印去资助它；伤官喜佩印来制伏，或生财来泄化伤气；阳刃喜官煞来制伏，最怕官煞一个都没有；月劫喜透出官星来制伏，也可以用财，但要再透食神来化开劫财。这就是顺用逆用的大方向。", note: ""),
                ClassicLine(id: "zp-08-4", n: 4, orig: "今人不知專主提綱，然後將四柱干支，字字統歸月令，以觀喜忌，甚至見正官佩印，則以為官印雙全，與印綬用官者同論；見財透食神，不以為財逢食生，而以為食神生財，與食神生財同論；見偏印透食，不以為洩身之秀，而以為梟神奪食，宜用財制，與食神逢梟同論；見煞逢食制而露印者，不為去食護煞，而以為煞印相生，與印綬逢煞者同論；更有煞格逢刃，不以為刃可幫身制煞，而以為七煞制刃，與陽刃露煞者同論。此皆由不知月令而妄論之故也。", baihua: "如今的人不懂得应当以提纲也就是月令为主，把四柱干支一个字一个字都归到月令上去权衡喜忌，于是弄出许多颠倒：看见正官格佩印，就说是官印双全，把它和印绶格用官星混为一谈；看见财格透出食神，不说是财得食神来生，反说成食神生财，把它和食神格生财混为一谈；看见偏印格透出食神，不说是泄身而成秀气，反说成枭神夺食、应当用财来制，把它和食神格遇枭混为一谈；看见七煞格有食神制煞而天干又露印，不说这是要去掉食神以护煞，反说成煞印相生，把它和印绶格逢煞混为一谈；更有七煞格遇到羊刃，不说羊刃可以帮身抗煞，反说成七煞制刃，把它和阳刃格露煞混为一谈。这些错误，都因为不知道一切以月令为准而胡乱议论。", note: ""),
                ClassicLine(id: "zp-08-5", n: 5, orig: "然亦有月令無用神者，將若之何？如木生寅卯，日與月同，本身不可為用，必看四柱有無財官煞食透干會支，另取用神；然終以月令為主，然後尋用，是建祿月劫之格，非用而即用神也。", baihua: "但也有月令本身取不出用神的情形，那该怎么办？比如木日主生在寅月或卯月，日干与月令同气，自己不能拿自己当用神，就必须看四柱中有没有财、官、煞、食透出天干或会成地支局，另外取一个用神；不过终究还是先以月令为主，然后才去别处寻用——这就是建禄月劫两格，它们是月令本身无从作用、而不得不另找用神的格。", note: ""),
            ]),
            ClassicChapter(id: "zp-09", no: "九", title: "論用神成敗救應", status: "included", source: "《子平真詮》九·論用神成敗救應", lines: [
                ClassicLine(id: "zp-09-1", n: 1, orig: "用神專尋月令，以四柱配之，必有成敗。何謂成？如官逢財印，又無刑沖破害，官格成也。財生官旺，或財逢食生而身強帶比，或財格透印而位置妥貼，兩不相剋，財格成也。印輕逢煞，或官印雙全，或身印兩旺而用食傷洩氣，或印多逢財而財透根輕，印格成也。食神生財，或食帶煞而無財，棄食就煞而透印，食格成也。身強七煞逢制，煞格成也。", baihua: "用神专从月令上寻，再拿四柱去配它，配的结果必然有成有败。什么叫成格？举例说：正官格遇到财来生官、印来护官，又没有刑冲破害去伤它，官格就成了。财格若能生出旺官，或者财得食神来生而日主身强、又带比肩帮身，或者财格透出印而印与财的位置安排妥当、彼此不相克，财格就成了。印格若印轻而遇七煞来生印，或者官印双全，或者身与印都旺而用食伤来泄秀，或者印太多而遇财来抑制、财又透干但根不深，印格就成了。食神格若能生财，或者带七煞而无财党煞，或者索性舍食就煞而透出印来，食格就成了。七煞格若日主身强而煞有制伏，煞格就成了。", note: ""),
                ClassicLine(id: "zp-09-2", n: 2, orig: "傷官生財，或傷官佩印而傷官旺，印有根，或傷官旺、身主弱而透煞印，或傷官帶煞而無財，傷官格成也。陽刃透官煞而露財印，不見傷官，陽刃格成也。建祿月劫，透官而逢財印，透財而逢食傷，透煞而遇制伏，建祿月劫之格成也。", baihua: "伤官格若能生财，或者佩印而伤官旺、印又有根，或者伤官旺、日主弱而透出煞与印来生身，或者带七煞而没有财去党煞，伤官格就成了。阳刃格若透出官或煞、又露出财与印，且不见伤官来伤官星，阳刃格就成了。建禄月劫格若透出官星而有财印相随，或透出财而有食伤化劫生财，或透出七煞而有制伏，建禄月劫格就成了。", note: ""),
                ClassicLine(id: "zp-09-3", n: 3, orig: "何謂敗？官逢傷克刑沖，官格敗也；財輕比重，財透七煞，財格敗也；印輕逢財，或身強印重而透煞，印格敗也；食神逢梟，或生財露煞，食神格敗也；七煞逢財無制，七煞格敗也；傷官非金水而見官，或生財生帶煞，或佩印而傷輕身旺，傷官格敗也；陽刃無官煞，刃格敗也；建祿月劫，無財官，透煞印，建祿月劫之格敗也。", baihua: "那么什么叫败格？正官格遇伤官来克、或遭刑冲，官格败；财格若财轻而比劫重、或财透出而带七煞，财格败；印格若印轻而遇财来坏印、或身强印又重却再透七煞，印格败；食神格若遇枭神夺食、或既生财又露煞，食神格败；七煞格若有财党煞而无制伏，煞格败；伤官格若不是金水伤官却见官星、或生财时又带煞、或佩印而伤官轻日主又旺，伤官格败；阳刃格若一个官煞都没有，刃格败；建禄月劫格若无财无官、反透煞与印，建禄月劫格败。", note: "底本「或生財生帶煞」，下一「生」字為「而」之訛，當作「或生財而帶煞」。"),
                ClassicLine(id: "zp-09-4", n: 4, orig: "成中有敗，必是帶忌；敗中有成，全憑救應。何謂帶忌？如正官逢財而又逢傷；透官而又逢合；財旺生官而又逢傷逢合；印透食以洩氣，而又遇財露；透煞以生印，而又透財，以去印存煞；食神帶煞印而又逢財；七煞逢食制而又逢印；傷官生財而財又逢合；佩印而印又遭傷，透財而逢煞，是皆謂之帶忌也。", baihua: "格局已成却又转败，一定是因为带忌，也就是夹带了坏事的字；格局已败却又转成，全靠救应，也就是有别的字出来解救。什么叫带忌？比如正官格得了财来生，偏偏又见伤官来克官；官星透出，偏偏又被别的天干合走；财旺生官，偏偏又逢伤官或逢合；印格透出食神来泄秀，偏偏又露出财来坏印；透出七煞来生印，偏偏又透财去掉印、只剩下煞来攻身；食神格带煞与印，偏偏又逢财来党煞；七煞格得食神制煞，偏偏又逢印来夺食护煞；伤官生财，偏偏财又被合走；佩印而印又被伤，透财而又逢煞。这些都叫带忌。", note: ""),
                ClassicLine(id: "zp-09-5", n: 5, orig: "何謂救應？如官逢傷而透印以解之，雜煞而合煞以清之，刑沖而會合以解之；財逢劫而透食以化之，生官以制之，逢煞而食神制煞以生財，或存財而合煞；印逢財而劫財以解之，或合財而存印；食逢梟而就煞以成格，或生財以護食；煞逢食制，印來護煞，而逢財以去印存食；傷官生財透煞而煞逢合；陽刃用官煞帶傷食，而重印以護之；建祿月劫用官，遇傷而傷被合，用財帶煞而煞被合，是謂之救應也。", baihua: "什么叫救应？比如正官遇伤官来克，透出印来制伤，官就保住了；官格夹杂七煞，用别的干把煞合走，格就清了；地支有刑冲，用会局或六合来化解。财格遇劫财来夺，透出食神把劫气化成财，或者生出官星来制住劫财；财格遇七煞，用食神制煞、腾出手来生财，或者保住财而把煞合掉。印格遇财来坏印，用劫财去分掉那个财，或者把财合住而保全印。食神格遇枭神夺食，索性转去就七煞而另成格，或者用生财来护住食神。七煞格本有食神制煞，却来了印护煞，就用财去掉印、保住食神。伤官生财而又透煞，把煞合掉。阳刃格用官煞制刃却带着伤食来伤官煞，就用厚重的印来护住官煞。建禄月劫格用官星，遇伤官而伤官被合走；用财而带煞、煞又被合走。这些都叫救应。", note: ""),
                ClassicLine(id: "zp-09-6", n: 6, orig: "八字妙用，全在成敗救應，其中權輕權重，甚是活潑。學者從此留心，能於萬變中融以一理，則於命之一道，其庶幾乎！", baihua: "八字推断的精妙处，全在成败救应四个字上，其中孰轻孰重要随局而定，极其灵活。学命的人若从这里留心，能在千变万化中融会出一条贯通的道理，那么对于命学一道，也就差不多算入门了。", note: ""),
            ]),
            ClassicChapter(id: "zp-10", no: "十", title: "論用神變化", status: "included", source: "《子平真詮》十·論用神變化", lines: [
                ClassicLine(id: "zp-10-1", n: 1, orig: "用神既主月令矣，然月令所藏不一，而用神遂有變化。如十二支中，除子午卯酉外，餘皆有藏，不必四庫也。", baihua: "用神既然以月令为主，可月令地支里往往藏着不止一个天干，于是用神就有了变化。十二地支中，除了子、午、卯、酉四个专气之支以外，其余八个都有所藏，并不限于辰戌丑未四个库。", note: ""),
                ClassicLine(id: "zp-10-2", n: 2, orig: "即以寅論，甲為本主，如郡之有府，丙其長生，如郡之有同知，戊亦長生，如郡之有通判；假使寅月為提，不透甲而透丙，則如知府不臨郡，而同知得以作主。此變化之由也。", baihua: "就拿寅来说：寅中甲木是本气之主，好比一郡有知府；丙火在寅长生，好比郡里有同知；戊土也在寅长生，好比郡里有通判。假使月令提纲是寅，天干却不透甲而透丙，那就好比知府不到任，由同知代为作主——用神的变化就是这样来的。", note: ""),
                ClassicLine(id: "zp-10-3", n: 3, orig: "故若丁生亥月，本為正官，支全卯未，則化為印。己生申月，本屬傷官。藏庚透壬，則化為財。凡此之類皆用神之變化也。", baihua: "所以丁日主生在亥月，亥中壬水本是正官，可地支若再凑齐卯与未，亥卯未三合成木局，官就化成了印。己日主生在申月，申中庚金本属伤官，可申中同时藏壬，天干把壬透出来，伤就化成了财。凡属这一类，都叫用神的变化。", note: ""),
                ClassicLine(id: "zp-10-4", n: 4, orig: "變之而善，其格愈美；變之不善，其格遂壞，何謂變之而善？如辛生寅月，逢丙而化財為官；壬生戌月逢辛而化煞為印。癸生寅月，不專以煞論。此二者以透出而變化者也。", baihua: "变化得好，格局就更美；变化得不好，格局就此败坏。什么叫变得好？比如辛日主生在寅月，寅中甲木本是辛的正财，寅中丙火透出来，就把财化成了官；壬日主生在戌月，戌中戊土本是七煞，戌中辛金透出来，就把煞化成了印。癸日主生在寅月，寅中戊土虽是煞，但因寅中还藏甲丙，就不能一味只按七煞论。以上两例是靠天干透出而发生的变化。", note: ""),
                ClassicLine(id: "zp-10-5", n: 5, orig: "癸生寅月，月令傷官秉令，藏甲透丙，會午會戌，則寅午戌三合，傷化為財；加以丙火透出，完全作為財論，即使不透丙而透戊土，亦作財旺生官論。蓋寅午戌三合變化在前，不作傷官見官論也。乙生寅月，月劫秉令，會午會戌，則劫化為食傷，透戊則為食傷生財，不作比劫爭財論。", baihua: "再看癸日主生在寅月，月令伤官当权，寅中藏甲又透丙，地支再会上午、会起戌，寅午戌三合成火局，伤官就化成了财；加上丙火透干，完全按财格论；即便不透丙而透戊土，也按财旺生官论。这是因为寅午戌三合的变化在先，所以不再按伤官见官那一套凶断。又如乙日主生在寅月，月令是劫财当权，地支会午会戌成火局，劫财就化成了食伤；再透戊土，就是食伤生财，不再按比劫争财论。", note: ""),
                ClassicLine(id: "zp-10-6", n: 6, orig: "此二者因會合而變化者。因變化而忌化為喜，為變之善者。又有變之而不失本格者。如辛生寅月，透丙化官，而又透甲，格成正財，正官乃其兼格也。", baihua: "以上两例是靠地支会合而发生的变化。因为变化而把忌神转成喜神，这就是变得好。另外还有一种变了却不失原来本格的情形。比如辛日主生在寅月，透丙把财化成官，可同时又透出甲木，甲是辛的正财，于是格局仍成正财，正官只是兼带的格。", note: ""),
                ClassicLine(id: "zp-10-7", n: 7, orig: "乙生申月，透壬化印，而又透戊，則財能生官，印逢財而退位，雖通月令，格成傷官，百戊官忌見。丙生寅月，午戌會劫，而又或透甲，或透壬，則仍為印而格不破。丙生申月，逢壬化煞，而又透戊，則食神能制煞生財，仍為財格，不失富貴。", baihua: "乙日主生在申月，透壬把官化成印，可同时又透戊土，戊财能生申中庚官，印遇财而退居其次，虽然壬印通根月令，格局却仍成伤官，这时戊土官星就成了忌见之物。丙日主生在寅月，地支午戌会成火局本把寅木化为劫，可若又透甲或透壬，寅中甲木仍是丙的偏印，格局照旧作印论而不破。丙日主生在申月，逢壬把申金之财化成七煞，可若又透戊土，食神既能制煞又能生财，格局仍作财论，不失富贵。", note: "底本「格成傷官，百戊官忌見」之「百」字為衍文，評註本作「格成傷官，戊官忌見」。"),
                ClassicLine(id: "zp-10-8", n: 8, orig: "如此之類甚多，是皆變而不失本格者也。是故八字非用神不立，用神非變化不靈，善觀命者，必於此細詳之。", baihua: "这一类例子很多，都是变了而不失本格的。所以说，八字没有用神就立不起来，用神不懂变化就活不了；善于看命的人，一定要在细细分辨。", note: ""),
            ]),
            ClassicChapter(id: "zp-11", no: "十一", title: "論用神純雜", status: "included", source: "《子平真詮》十一·論用神純雜", lines: [
                ClassicLine(id: "zp-11-1", n: 1, orig: "用神既有變化，則變化之中，遂分純、雜。純者吉，雜者凶。", baihua: "用神既然會變化，變化之中又分出純與雜兩種：純的吉利，雜的凶險。", note: ""),
                ClassicLine(id: "zp-11-2", n: 2, orig: "何謂純？互用而兩相得者是也。如辛生寅月，甲丙並透，財與官相生，兩相得也。戊生申月，庚壬並透，財與食相生，兩相得也。癸生未月，乙己並透，煞與食相剋，相剋而得其當，亦兩相得也。如此之類，皆用神之純者。", baihua: "什麼叫純？兩個字互相為用而彼此得力，就是純。比如辛日主生在寅月，甲木與丙火一齊透出，財能生官；戊日主生在申月，庚金與壬水一齊透出，食神能生財；癸日主生在未月，乙木與己土一齊透出，食神克煞而克得恰當。這些都屬於用神之純。", note: ""),
                ClassicLine(id: "zp-11-3", n: 3, orig: "何謂雜？互用而兩不相謀者是也。如壬生未月，乙己並透，官與傷相剋，兩不相謀也。甲也辰月，戊壬並透，印與財相剋，亦兩不相謀也。如此之類，皆用之雜者也。", baihua: "什麼叫雜？兩個字互相為用卻各行其是、彼此不相顧，就是雜。比如壬日主生在未月，乙木與己土一齊透出，傷官來克官星；甲日主生在辰月，戊土與壬水一齊透出，財來克印。這些都屬於用神之雜。", note: "底本「甲也辰月」，「也」為「生」之訛，當作「甲生辰月」。"),
            ]),
            ClassicChapter(id: "zp-12", no: "十二", title: "論用神格局高低", status: "included", source: "《子平真詮》十二·論用神格局高低", lines: [
                ClassicLine(id: "zp-12-1", n: 1, orig: "八字既有用神，必有格局，有格局必有高低，財官印食煞傷劫刃，何格無貴？何格無賤？由極貴而至極賤，萬有不齊，其變千狀，豈可言傳？然其理之大綱，亦在有情、有力無力之間而已。", baihua: "八字既然有用神，就必定有格局；既然有格局，格局就必定分高低。財、官、印、食、煞、傷、劫、刃這八種，哪一種沒有出過貴命？哪一種沒有出過賤命？從極貴到極賤，千差萬別，變化萬端，哪裡能用幾句話說盡？不過其中道理的大綱，也不外「有情無情」與「有力無力」這兩層而已。", note: "底本「亦在有情、有力無力之間而已」，「有情」下脫「無情」二字，《子平真詮評註》本作「亦在有情無情、有力無力之間而已」。"),
                ClassicLine(id: "zp-12-2", n: 2, orig: "如正官佩印，不如透財，而四柱帶傷，反推佩印。故甲透酉官，透丁合壬，是謂合傷存官，遂成貴格，以其有情也。", baihua: "舉例說：正官格佩印，一般不如透財來生官；可要是四柱帶著傷官，就反過來該取佩印，因為印能制傷護官。所以甲日主透出酉金正官，天干又透丁火傷官，若再有壬水來與丁相合，這叫「合傷存官」，於是成為貴格——之所以貴，是因為這一合安排得恰到好處，術語叫「有情」。", note: ""),
                ClassicLine(id: "zp-12-3", n: 3, orig: "財忌比劫，而與煞作合，劫反為用。故甲生辰月，透戊成格，遇乙為劫，逢庚為煞，二者相合，皆得其用，遂成貴格，亦以其有情也。", baihua: "財格最怕比劫來奪，可要是這個劫財恰好去與七煞相合，劫財反倒成了有用之物。所以甲日主生在辰月，透出戊土成偏財格，命中又有乙木是劫財、庚金是七煞，乙與庚相合，一個絆住了煞、一個也不來奪財，兩者都各得其用，於是成為貴格——這也是因為有情。", note: ""),
                ClassicLine(id: "zp-12-4", n: 4, orig: "身強煞露而食神又旺，如乙生酉月，辛金透，丁火剛，秋木盛，三者皆備，極等之貴，以其有力也。官強財透，身逢祿刃，如丙生子月，癸水透，庚金露，而坐寅午，三者皆均，遂成大貴，亦以其有力也。", baihua: "再看有力的例子：日主身強、七煞透出而食神又旺，如乙日主生在酉月，辛金七煞透干，丁火食神剛銳，而秋天的乙木自身仍旺——身、煞、食三者都夠分量，就是極品之貴，因為「有力」。又如官星強、財又透出、日主自身坐在祿或刃上，如丙日主生在子月，癸水正官透出，庚金財星露出，而日支時支坐寅坐午——官、財、身三者力量均衡，於是大貴，這也是因為有力。", note: ""),
                ClassicLine(id: "zp-12-5", n: 5, orig: "又有有情而兼有力，有力而兼有情者。如甲用酉官，壬合丁以清官，而壬水根深，是有情而兼有力者也。乙用酉煞，辛逢丁制，而辛之祿即丁之長生，同根月令，是有力而兼有情者也。是皆格之最高者也。", baihua: "還有既有情又有力、既有力又有情的。比如甲日主用酉中辛金為正官，透出丁火傷官，用壬水去合丁以澄清官星，而這個壬水根基又深——這就是有情而兼有力。又如乙日主用酉中辛金為七煞，透丁火食神來制煞，而辛的臨官之地正是酉、丁的長生之地也是酉，兩者同根於月令，制得貼切——這就是有力而兼有情。這兩種都是格局中最高的。", note: ""),
                ClassicLine(id: "zp-12-6", n: 6, orig: "如甲用酉官，透丁逢癸，癸克不如壬合，是有情而非情之至。乙逢酉逢煞，透丁以制，而或煞強而丁稍弱，丁旺而煞不昂，又或辛丁並旺而乙根不甚深，是有力而非力之全，格之高而次者也。", baihua: "相比之下：甲用酉官，透丁傷官而只有癸水來克丁，癸克丁不如壬合丁來得乾淨利落，這就是有情而未達極致。乙用酉煞、透丁制煞，若煞強而丁稍弱，或丁旺而煞不夠挺，又或者辛丁都旺而乙木自身根不夠深，這就是有力而未能力全。這些是高一等之中稍遜的格。", note: ""),
                ClassicLine(id: "zp-12-7", n: 7, orig: "至如印用七煞，本為貴格，而身強印旺，透煞孤貧，蓋身旺不勞印生，印旺何勞煞助？偏之又偏，以其無情也。傷官佩印，本秀而貴，而身主甚旺，傷官甚淺，印又太重，不貴不秀，蓋欲助身則身強，制傷則傷淺，要此重印何用？是亦無情也。", baihua: "至於印格用七煞來生印，本是貴格，可若日主已經身強、印又已旺，再透七煞，反而孤苦貧寒——因為身已旺就用不著印來生，印已旺又何必再要煞來幫？偏上加偏，這就是「無情」。傷官佩印本來清秀而貴，可若日主極旺、傷官極淺、印又太重，就既不貴也不秀——想靠印助身吧，身本來就強；想靠印制傷吧，傷本來就淺，要這麼重的印做什麼？這也是無情。", note: ""),
                ClassicLine(id: "zp-12-8", n: 8, orig: "又如煞強食旺而身無根，身強比重而財無氣，或夭或貧，以其無力也。是皆格之低而無用者也。然其中高低之故，變化甚微，或一字而有千鈞之力，或半字而敗全局之美，隨時觀理，難以擬議，此特大略而已。", baihua: "再如七煞強、食神旺而日主毫無根氣，或者日主身強、比劫又重而財毫無氣勢，結果不是夭折就是貧窮，這是「無力」。這些都是格局低下而無用的。不過其中高低的緣故變化極其細微：有時一個字就有千鈞之力，有時半個字就敗掉全局之美，只能隨局觀理，難以預先擬定，上面所說不過是個大概而已。", note: ""),
            ]),
            ClassicChapter(id: "zp-13", no: "十三", title: "論用神因成得敗因敗得成", status: "included", source: "《子平真詮》十三·論用神因成得敗因敗得成", lines: [
                ClassicLine(id: "zp-13-1", n: 1, orig: "八字之中，變化不一，遂分成敗；而成敗之中，又變化不測，遂有因成得敗，因敗得成之奇。是故化傷為財，格之成也，然辛生亥月，透丁為用，卯未會財，乃以黨煞，因成得敗矣。印用七煞，格之成也，然癸生申月，秋金重重，略帶財以損太過，逢煞則煞印忌財，因成得敗也。如此之類，不可勝數，皆因成得敗之例也。", baihua: "八字之中變化不一，於是分出成格與敗格；而在成敗之中又有難以預料的變化，於是出現了「因成得敗」「因敗得成」這樣的奇局。比如把傷官化成財，本是成格；可辛日主生在亥月，亥中壬水是傷官，天干透丁火七煞為用，地支卯未來與亥會成木局、化傷為財，這財卻反過來黨助七煞攻身——本來成了，反倒敗了。又如印格用七煞來生印，本是成格；可癸日主生在申月，秋金重重、印已太旺，略帶一點財來損其太過原是好事，一旦又逢七煞，煞印相生的格局最忌見財，財與煞兩下衝突——同樣是本來成了反倒敗了。這一類例子數不勝數，都屬於因成得敗。", note: ""),
                ClassicLine(id: "zp-13-2", n: 2, orig: "官印逢傷，格之敗也，然辛生戊戌月，年丙時壬，壬不能越戊克丙，而反能洩身為秀，是因敗得成矣。煞刃逢食，格之敗也，然庚生酉月，年丙月丁，時上逢壬，則食神合官留煞，而官煞不雜，煞刃局清，是因敗得成矣。如此之類，亦不可勝數，皆因敗得成之例也。", baihua: "官印格遇上傷官，本是敗格；可辛日主生在戌月，年干丙火為正官、時干壬水為傷官，中間隔著戌中戊土，壬水越不過戊土去克丙火，反倒能洩辛金之秀氣——本來敗了，反倒成了。煞刃格遇上食神，本是敗格；可庚日主生在酉月坐羊刃，年干丙火為七煞、月干丁火為正官，官煞混雜，時上逢壬水食神，壬與丁合，把正官合走、留下七煞，官煞不再混雜，煞刃格反而清純——也是本來敗了反倒成了。這一類例子同樣數不勝數，都屬於因敗得成。", note: "底本作「辛生戊戌月」，「戊」為衍字，當作「辛生戌月」。"),
                ClassicLine(id: "zp-13-3", n: 3, orig: "其間奇奇怪怪，變幼無窮，惟以理權衡之，隨在觀理，因時運化，由他奇奇怪怪，自有一種至當不易不論。觀命者毋眩而無主、執而不化也。", baihua: "其間奇奇怪怪、變幻無窮，只能拿道理去權衡，隨處觀理、因時變通；任它千奇百怪，總有一個最恰當而不可移易的斷法。看命的人切不可被表象弄花了眼而沒有主見，也不可死抱教條而不知變通。", note: "底本「變幼無窮」之「幼」為「幻」之訛，「至當不易不論」之「不論」為「之論」之訛。"),
            ]),
            ClassicChapter(id: "zp-14", no: "十四", title: "論用神配氣候得失", status: "included", source: "《子平真詮》十四·論用神配氣候得失", lines: [
                ClassicLine(id: "zp-14-1", n: 1, orig: "論命惟以月令用神為主，然亦須配氣候而互參之。譬如英雄豪傑，生得其時，自然事半功倍；遭時不順，雖有奇才，成功不易。", baihua: "論命固然以月令用神為主，但還必須配合寒暖燥濕的氣候一併參看。好比英雄豪傑，生逢其時自然事半功倍；時運不順，縱有奇才也難成功。", note: ""),
                ClassicLine(id: "zp-14-2", n: 2, orig: "是以印綬遇官，此謂官印雙全，無人不貴。而冬木逢水，雖透官星，亦難必貴，蓋金寒而水益凍，凍水不能生木，其理然也。", baihua: "所以印綬格遇到官星，叫作官印雙全，照理沒有不貴的；可是冬天生的木日主，印是水，即便透出官星金來生水，也未必就貴——因為金本身已寒，反使水更凍，凍住的水生不了木，道理就在這裡。", note: ""),
                ClassicLine(id: "zp-14-3", n: 3, orig: "身印兩旺，透食則貴，凡印格皆然。而用之冬木，尤為秀氣，以冬木逢火，不惟可以洩身，而即可以調候也。", baihua: "再如身與印都旺、透出食神來洩秀就貴，這在各種印格都通用；而用在冬天的木日主身上尤其秀氣，因為冬木遇火，不但能洩身成秀，同時還能暖局調候，一舉兩得。", note: ""),
                ClassicLine(id: "zp-14-4", n: 4, orig: "傷官見官，為禍百端，而金水見之，反為秀氣。非官之不畏夫傷，而調候為急，權而用之也。", baihua: "傷官見官，一般是百般為禍的；唯獨金水傷官見官，反成秀氣。這並不是說官星不怕傷官，而是因為冬金水寒，暖局調候更為緊急，只好權變著借官星那點火氣來用。", note: ""),
                ClassicLine(id: "zp-14-5", n: 5, orig: "傷官帶煞，隨時可用，而用之冬金，其秀百倍。傷官佩印，隨時可用，而用之夏木，其秀百倍，火濟水，水濟火也。", baihua: "傷官帶七煞，各季都可以用，但用在冬天的金日主身上，秀氣加倍。傷官佩印，各季都可以用，但用在夏天的木日主身上，秀氣加倍——因為夏木火炎、水印來潤，正是火與水互相濟助。", note: ""),
                ClassicLine(id: "zp-14-6", n: 6, orig: "傷官用財，本為貴格，而用之冬水，即使小富，亦多不貴，凍水不能生木也。傷官用財，即為秀氣，而用之夏木，貴而不甚秀，燥土不甚靈秀也。", baihua: "傷官用財本是貴格，但用在冬天的水日主身上，即便小富也多半不貴，因為凍水生不了木。傷官用財本是秀氣，但用在夏天的木日主身上，貴是貴了卻不甚清秀，因為夏天的土燥而不靈。", note: ""),
                ClassicLine(id: "zp-14-7", n: 7, orig: "春木逢火，則為木為通明，而夏木不作此論；秋金遇水，則為金水相涵，而冬金不作此論。氣有衰旺，取用不同也。", baihua: "春木遇火叫「木火通明」，夏木遇火就不能這樣論；秋金遇水叫「金水相涵」，冬金遇水也不能這樣論。氣有衰有旺，季節不同，取用也就不同。", note: "底本作「則為木為通明」，下一「為」字為「火」之訛，當作「則為木火通明」。"),
                ClassicLine(id: "zp-14-8", n: 8, orig: "春木逢火，木火通明，不利見官；而秋金遇水，金水相涵，見官無礙。假如庚生申月，而支中或子或辰，會成水局，天干透丁，以為官星，只要壬癸不透露干頭，便為貴格，與食神傷官喜見官之說同論，亦調候之道也。", baihua: "同樣是洩秀，春木遇火成木火通明，卻不宜再見官星來克身；秋金遇水成金水相涵，見官星反而無妨。譬如庚日主生在申月，地支中或有子、或有辰，會成水局，天干透出丁火作官星，只要壬癸不透到天干上來直接克丁，就是貴格——這與「食神傷官喜見官」的說法同一道理，也是調候的需要。", note: ""),
                ClassicLine(id: "zp-14-9", n: 9, orig: "食神雖逢正印，亦謂奪食，而夏木火盛，輕用之亦秀而貴，與木火傷官喜見水同論，亦調候之謂也。", baihua: "又如食神格遇到正印，本該叫奪食，可是夏天的木日主火氣太盛，略用一點印水來潤澤，反而清秀而貴——這與「木火傷官喜見水」同一道理，同樣是調候的緣故。", note: ""),
                ClassicLine(id: "zp-14-10", n: 10, orig: "此類甚多，不能悉述，在學者引伸觸類，神而明之而已。", baihua: "這一類情形很多，無法一一列舉，學者只要觸類旁通、心領神會就是了。", note: ""),
            ]),
            ClassicChapter(id: "zp-15", no: "十五", title: "論相神緊要", status: "included", source: "《子平真詮》十五·論相神緊要", lines: [
                ClassicLine(id: "zp-15-1", n: 1, orig: "月令既得用神，則別位亦必有相，若君之有相，輔者是也。如官逢財生，則官為用，財為相；財旺生官，則財為用，官為相；煞逢食制，則煞為用，食為相。", baihua: "月令上既然定下了用神，四柱別的位置上就必定有個「相神」，好比君主之下有宰相，是輔佐用神成格的那個字。比如正官得財來生，官是用神、財就是相神；財旺而生官，財是用神、官就是相神；七煞得食神制伏，煞是用神、食神就是相神。", note: ""),
                ClassicLine(id: "zp-15-2", n: 2, orig: "然此乃一定之法，非通變之妙。要而言之，凡全局之格，賴此一字而成者，均謂之相也。傷用神甚於傷身，傷相甚於傷用。", baihua: "不過這只是一般定法，還不是隨機應變的妙處。概括地說：凡是全局的格局全靠某一個字才得以成立，那個字就叫相神。傷到用神比傷到日主本身還嚴重，而傷到相神又比傷到用神更嚴重——因為用神被傷尚且可能有救，相神一倒，整個格就散了。", note: ""),
                ClassicLine(id: "zp-15-3", n: 3, orig: "如甲用酉官，透丁逢壬，則合傷存官以成格者，全賴壬之相；戊用子財，透甲並己，則合煞存財以成格者，全賴己之相；乙用酉煞，年丁月癸，時上逢戊，則合去癸印以使丁得制煞者，全賴戊之相。", baihua: "舉例來看。甲日主用酉中辛金為正官，天干透丁火傷官，幸有壬水來與丁合，合傷存官才成了格，全靠壬這個相神。戊日主用子中癸水為正財，天干透出甲木七煞，又有己土來合甲，合煞存財才成了格，全靠己這個相神。乙日主用酉中辛金為七煞，年干丁火食神本可制煞，月干卻有癸水偏印要來克丁，幸而時上逢戊土把癸合去，丁才騰得出手來制煞，全靠戊這個相神。", note: ""),
                ClassicLine(id: "zp-15-4", n: 4, orig: "癸生亥月，透丙為財，財逢月劫，而卯未來會，則化水為木而轉劫以生財者，全賴於卯未之相。庚生申月，透癸洩氣，不通月令而金氣不甚靈，子辰會局，則化金為水而成金水相涵者，全賴於子辰之相。", baihua: "癸日主生在亥月，透丙火為財，可亥是癸的月劫，劫財要來奪財；地支卯未來與亥會成木局，把水化成木，反把劫財轉成了生財之物，全靠卯未這兩個相神。庚日主生在申月，透癸水洩秀，可癸不通月令本氣，金氣顯不出靈秀；地支子辰來會成水局，把金化為水而成金水相涵，全靠子辰這兩個相神。", note: ""),
                ClassicLine(id: "zp-15-5", n: 5, orig: "如此之類，皆相神之緊要也。", baihua: "諸如此類，都可見相神何等緊要。", note: ""),
                ClassicLine(id: "zp-15-6", n: 6, orig: "相神無破，貴格已成；相神相傷，立敗其格。", baihua: "相神沒有被破壞，貴格就算成立；相神一旦被傷，格局立刻敗掉。", note: ""),
                ClassicLine(id: "zp-15-7", n: 7, orig: "如甲用酉官，透丁逢癸印，制傷以護官矣，而又逢戊，癸合戊而不制丁，癸水之相傷矣；丁用酉財，透癸逢己，食制煞以生財矣，而又透甲，己合甲而不制癸，己土之相傷矣。", baihua: "比如甲日主用酉官，透丁火傷官，幸有癸水正印來制傷護官；可命裡又出來一個戊土，癸與戊相合，癸就顧不上去制丁了——這是相神癸水被傷。又如丁日主用酉中辛金為財，透出癸水七煞，幸有己土食神制煞以生財；可命裡又透出甲木，己與甲相合，己就顧不上去制癸了——這是相神己土被傷。", note: ""),
                ClassicLine(id: "zp-15-8", n: 8, orig: "是皆有情而化無情，有用而成無用之格也。凡八字排定，必有一種議論，一種作用，一種棄取，隨地換形，難以虛擬，學命者其可忽諸？", baihua: "這兩種都是本來有情卻化為無情、本來有用卻變成無用的格局。總之，凡是八字一排定，就必定有一套相應的議論、一種特定的作用、一番具體的取捨，隨著排列位置的不同而形態各異，無法憑空擬定；學命的人怎麼可以忽視相神呢？", note: ""),
            ]),
            ClassicChapter(id: "zp-16", no: "十六", title: "論雜氣如何取用", status: "included", source: "《子平真詮》十六·論雜氣如何取用", lines: [
                ClassicLine(id: "zp-16-1", n: 1, orig: "四墓者，沖氣也，何以謂之雜氣？以其所藏者多，用神不一，故謂之雜氣也。如辰本藏戊，而又為水庫，為乙餘氣，三者俱有，於何取用？然而甚易也，透干會取其清者用之，雜而不雜也。", baihua: "辰戌丑未這四個墓庫之支，是四時之氣交接沖和的地方，為什麼叫「雜氣」？因為它們裡面所藏的天干不止一個，可取的用神也就不止一個，所以叫雜氣。譬如辰，本氣藏戊土，同時又是水的墓庫而藏癸，還是木的餘氣而藏乙，三樣都有，究竟拿哪一個當用神？其實很容易：看天干透出了哪一個、地支會成了哪一局，取其中清純明確的那個來用，雖雜而不亂。", note: ""),
                ClassicLine(id: "zp-16-2", n: 2, orig: "何謂透干？如甲生辰月，透戊則用偏財，透癸則用正印，透乙則用月劫是也。", baihua: "什麼叫「透干」？比如甲日主生在辰月，天干透戊就用偏財，透癸就用正印，透乙就用月劫，乙對甲而言是劫財。", note: ""),
                ClassicLine(id: "zp-16-3", n: 3, orig: "何謂會支？如甲生辰月，逢申與子會局，則用水印是也。", baihua: "什麼叫「會支」？比如甲日主生在辰月，地支再逢申與子，申子辰三合成水局，就用水作印。", note: ""),
                ClassicLine(id: "zp-16-4", n: 4, orig: "一透則一用，兼透則兼用，透而又會，則透與會並用。", baihua: "透出一個就用一個，兩個都透就兩個兼用，既有透干又有會支，就把透與會合起來一併用。", note: ""),
                ClassicLine(id: "zp-16-5", n: 5, orig: "其合而有情者吉，其合而無情者則不吉。何謂有情？順而相成者是也。", baihua: "這幾樣湊在一起若能彼此配合、互相成全，就吉；若各行其是、互相拆台，就不吉。什麼叫「有情」？順著一個方向互相成就，就是有情。", note: ""),
                ClassicLine(id: "zp-16-6", n: 6, orig: "如甲生辰月，透癸為印，而又會子會申以成局，印綬之格，清而不雜，是透干與會支，合而有情也。又如丙生辰月，透癸為官，而又逢己以為印，官與印相生，而印又能去辰中暗土以清官，是兩干並透，合而情也。又如甲生丑月，辛透為官，或巳酉會成金局，而又透己財以生官，是兩干並透，與會支合而有情也。", baihua: "比如甲日主生在辰月，透癸水為正印，地支又會子會申成水局，印綬格清純而不雜，這是透干與會支配合有情。又如丙日主生在辰月，透癸水為正官，同時又逢一個能作印的木，印既生身，又能克去辰中暗藏的戊土以澄清官星，官與印相生，這是兩干並透而配合有情。又如甲日主生在丑月，丑中辛金透干為正官，或者地支巳酉丑會成金局，同時又透己土為財來生官，這是兩干並透加上會支，配合有情。", note: "底本此句作「而又逢己以為印」，己對丙實為傷官而非印，《子平真詮評註》本作「逢乙以為印」，當從乙；句末「合而情也」，「合」下脫一「有」字，當作「合而有情也」。"),
                ClassicLine(id: "zp-16-7", n: 7, orig: "何謂無情？逆而相背者是也。", baihua: "什麼叫「無情」？彼此背道而馳、互相抵消，就是無情。", note: ""),
                ClassicLine(id: "zp-16-8", n: 8, orig: "如壬生未月，透己為官，而地支會亥卯以成傷官之局，是透官與會支，合而無情者也。又如甲生辰月，透戊為財，又或透壬癸以為印，透癸則戊癸作合，財印兩失，透壬則財印兩傷，又以貪財壞印，是兩干並透，合而無情也。又如甲生戌月，透辛為官，而又透丁以傷官，月支又會寅會午以成傷官之局，是兩干並透，與會支合而無情也。", baihua: "比如壬日主生在未月，未中己土透干為正官，可地支卻會上亥、卯成木局，木是壬的傷官，傷官局要來克官——這是透干與會支配合無情。又如甲日主生在辰月，透戊土為偏財，同時又透壬或癸為印：透癸的話戊癸相合，財與印兩下都失了作用；透壬的話財要克印、印又礙財，兩敗俱傷，還落一個「貪財壞印」——這是兩干並透而配合無情。又如甲日主生在戌月，戌中辛金透干為正官，同時又透丁火傷官來克官，月支戌再會寅會午成火局，傷官之勢更旺——這是兩干並透加上會支，配合無情。", note: ""),
                ClassicLine(id: "zp-16-9", n: 9, orig: "又有有情而卒成無情者，何也？", baihua: "還有一種本來有情、最終卻變成無情的，是怎麼回事？", note: ""),
                ClassicLine(id: "zp-16-10", n: 10, orig: "如甲生辰月，逢壬為印，而又逢丙，印綬本喜洩身為秀，似成格矣，而火能生土，似又助辰中之戊，印格不清，是必壬干透而支又會申會子，則透丙亦無所礙。又有甲生辰月，透壬為印，雖不露丙而支逢戌位，戌與辰沖，二者為月沖而土動，干頭之壬難通月令，印格不成，是皆有情而卒無情，富而不貴者也。", baihua: "比如甲日主生在辰月，逢壬水為印，同時又逢丙火食神。印格本來喜歡用食傷洩身成秀，看似成格了；可丙火能生土，等於又去幫辰中那個戊土財星，印格就不清了。這種情形必須壬水透干、地支又會申會子成水局把印坐實，才可以不怕丙火。又比如甲日主生在辰月，透壬為印，雖然沒有露丙，可地支逢一個戌，辰戌相沖，沖的正是月令，土一震動，天干那個壬就通不了月令之根，印格也就不成。這些都是本來有情、最終歸於無情，往往富而不貴。", note: ""),
                ClassicLine(id: "zp-16-11", n: 11, orig: "又有無情而終有情者，何也？", baihua: "還有一種看著無情、最終卻是有情的，是怎麼回事？", note: ""),
                ClassicLine(id: "zp-16-12", n: 12, orig: "如癸生辰月，透戊為官，又有會申會子以成水局，透干與會支相剋矣。然所克者乃是劫財，譬如月劫用官，何傷之有？", baihua: "比如癸日主生在辰月，透戊土為正官，地支又會申會子成水局，透干的官與會支的水互相剋伐，似乎無情。可細想，被官所克的其實是水局裡的劫財，就好比月劫格用官星來制劫，有什麼妨礙？", note: ""),
                ClassicLine(id: "zp-16-13", n: 13, orig: "又如丙生辰月，透戊為食，而又透壬為煞，是兩干並透，而相剋也。然所克者乃是偏官，譬如食神帶煞，煞逢食制，二者皆是美格，其局愈貴。", baihua: "又如丙日主生在辰月，透戊土為食神，同時又透壬水為七煞，兩干並透而互相剋，似乎無情。可被食神所克的正是七煞，就好比食神格帶煞、煞得食神制伏，這兩樣本來都是美格，配在一起格局反而更貴。", note: ""),
                ClassicLine(id: "zp-16-14", n: 14, orig: "是皆無情而終為有情也。如此之類，不可勝數，即此為例，旁悟而已。", baihua: "這些都是看似無情而終歸有情。這一類情形數不勝數，舉這幾個例子，讓人由此旁通就是了。", note: ""),
            ]),
            ClassicChapter(id: "zp-17", no: "十七", title: "論墓庫刑沖之說", status: "included", source: "《子平真詮》十七·論墓庫刑沖之說", lines: [
                ClassicLine(id: "zp-17-1", n: 1, orig: "辰戌丑未，最喜刑沖，財官入庫不沖不發——此說雖俗書盛稱之，然子平先生造命，無是說也。", baihua: "辰戌丑未最喜刑沖、財官入庫不沖不發——這種說法雖然俗書裡大肆稱道，但子平先生論命根本沒有這種說法。", note: ""),
                ClassicLine(id: "zp-17-2", n: 2, orig: "夫雜氣透干會支，豈不甚美？又何勞刑沖乎？", baihua: "要知道雜氣只要透干會支，格局已經很美了，又何必再勞煩刑沖呢？", note: ""),
                ClassicLine(id: "zp-17-3", n: 3, orig: "假如甲生辰月，戊土透豈非偏財？申子會豈非印綬？若戊土不透，即辰戌相沖，財格猶不甚清也。", baihua: "比如甲日主生在辰月，戊土透出來不就是偏財格？申子會成水局不就是印綬格？若是戊土不透，即便辰戌相沖，財格仍然不甚清純。", note: ""),
                ClassicLine(id: "zp-17-4", n: 4, orig: "至於透壬為印，辰戌相沖，將以累印，謂之沖開印庫可乎？", baihua: "至於透出壬水為印，辰戌一沖反而會連累印星，難道這也能叫「沖開印庫」嗎？", note: ""),
                ClassicLine(id: "zp-17-5", n: 5, orig: "況四庫之中，雖五行俱有，而終以土為主。土沖則靈，金木水火，豈取勝以四庫之沖而動乎？", baihua: "何況四庫之中雖然五行俱全，但終究以土為主；土一沖動就靈了，金木水火又豈能靠四庫的沖動來取勝呢？", note: ""),
                ClassicLine(id: "zp-17-6", n: 6, orig: "故財官屬土，沖則庫啟，如甲用戊財而辰戌沖，壬用己官而丑未沖之類是也。然終以戊己干頭為清用，干既透，即不沖而亦得也。", baihua: "所以財官屬土，沖了庫就開了，比如甲日主用戊土財星而辰戌相沖、壬日主用己土官星而丑未相沖，都是這個道理。不過終究還是以戊己透干為清純的用法，干既然透出來了，不沖也照樣得用。", note: ""),
                ClassicLine(id: "zp-17-7", n: 7, orig: "至於財官為水，沖則反累，如己生辰月，壬透為財，戌沖則劫動，何益之有？丁生辰月，透壬為官，戌沖則傷官，豈能無害？其可謂之逢沖而壬水之財庫官庫開乎？", baihua: "至於財官屬水的情形，沖了反而連累：比如己日主生在辰月，壬水透干為財，戌一沖辰就動了劫財，有什麼好處？丁日主生在辰月，壬水透干為官，戌一沖就動了傷官，怎麼會沒有害處？這樣的沖，難道也能叫「逢沖而壬水的財庫官庫開了」嗎？", note: ""),
                ClassicLine(id: "zp-17-8", n: 8, orig: "今人不知此理，甚有以出庫為投庫。", baihua: "今人不知道這個道理，甚至把「出庫」當作「投庫」，實在可笑。", note: ""),
                ClassicLine(id: "zp-17-9", n: 9, orig: "如丁生辰月，壬官透干，不以為庫內之壬，干頭透出，而反為干頭之壬，逢辰入庫，求戌以沖土，不顧其官之傷。", baihua: "比如丁日主生在辰月，壬水官星透干，本該看作是庫裡的壬水透到了干頭，可有人卻反把干頭的壬水當作入了庫的壬水，硬要找個戌來沖辰土，全然不顧官星因此受傷。", note: ""),
                ClassicLine(id: "zp-17-10", n: 10, orig: "更有可笑者，月令本非四墓，別有用神，年月日時中一帶四墓，便求刑沖；日臨四庫不以為身坐庫根，而以為身主入庫，求沖以解。", baihua: "更有可笑的：月令本來不是四墓，另有別的用神，只因年月日時中帶了一個四墓之支，便到處求刑沖；日主臨四庫，本該看作是日主坐在庫根上，卻說成是日主入了庫，求沖來解救。", note: ""),
                ClassicLine(id: "zp-17-11", n: 11, orig: "種種謬論，令人掩耳。", baihua: "種種謬論，聽了只想掩耳不聽。", note: ""),
                ClassicLine(id: "zp-17-12", n: 12, orig: "然亦有逢沖而發者，何也？如官最忌沖，而癸生辰月，透戊為官，與戌相沖，不見破格，四庫喜沖，不為不足。", baihua: "不過也確實有「逢沖而發」的情形，是怎麼回事呢？比如官星最怕被沖，可癸日主生在辰月，透出戊土為官，與戌相沖卻不見破格——四庫喜沖，這一點不算欠缺。", note: ""),
                ClassicLine(id: "zp-17-13", n: 13, orig: "卻不知子午卯酉之類，二者相仇，乃沖剋之沖，而四墓土自為沖，乃沖動之沖，非沖剋之沖也。然既以土為官，何害於事乎？", baihua: "要知道子午卯酉之類的沖，是兩者相仇的沖剋之沖；而四墓土之間的沖，是沖動之沖，不是沖剋之沖。既然已經以土為官，沖動了它又有什麼妨害呢？", note: ""),
            ]),
            ClassicChapter(id: "zp-18", no: "十八", title: "論四吉神能破格", status: "included", source: "《子平真詮》十八·論四吉神能破格", lines: [
                ClassicLine(id: "zp-18-1", n: 1, orig: "財官印食，四吉神也，然用之不當，亦能破格。如食神帶煞，透財為害，財能破格也；春木火旺，見官則忌，官能破格也；煞逢食制，透印無功，印能破格也；財旺生官，露食則雜，食能破格也。", baihua: "財、官、印、食是四個吉神，但用得不當也會破格。比如食神帶煞又透財，財反而有害，因為財能破格；春木火旺再見官星就忌，因為官能破格；煞逢食制又透印，印無功用，因為印能破格；財旺生官又露食神就雜，因為食能破格。", note: ""),
                ClassicLine(id: "zp-18-2", n: 2, orig: "是故官用食破，印用財破。譬之用藥，參苓芪術，本屬良材，用之失宜，亦能害人。", baihua: "所以說官格用食神來破、印格用財來破。打個比方說，用藥如人參、茯苓、黃芪、白朮，本來都是良材，用得不合適也能害人。", note: ""),
                ClassicLine(id: "zp-18-3", n: 3, orig: "官忌食傷，財畏比劫，印懼財破，食畏印奪，參合錯綜，各極其妙。弱者以生扶為喜，強者因生扶而反害；衰者以裁抑為忌，太旺者反以裁抑而得益。吉凶喜忌，全在是否合於需要，不因名稱而有分別也。", baihua: "正官怕食傷，偏財怕比劫，正印怕財來破，食神怕印來奪——彼此參合錯綜，各有精妙之處。日主弱的以生扶為喜，日主強的反因生扶而受害；局中衰的以裁抑為忌，太旺的反因裁抑而得益。吉凶喜忌全在於是否合乎需要，不能只看名稱來分別。", note: ""),
            ]),
            ClassicChapter(id: "zp-19", no: "十九", title: "論四凶神能成格", status: "included", source: "《子平真詮》十九·論四凶神能成格", lines: [
                ClassicLine(id: "zp-19-1", n: 1, orig: "煞傷梟刃，四凶神也，然施之得宜，亦能成格。", baihua: "七煞、傷官、梟印、羊刃是四個凶神，但用得其所也能成格。", note: ""),
                ClassicLine(id: "zp-19-2", n: 2, orig: "如印綬根輕，透煞為助，煞能成格也。財逢比劫，傷官可解，傷能成格也。食神帶煞，靈梟得用，梟能成格也。財逢七煞，刃可解厄，刃能成格也。", baihua: "比如印綬根氣輕，透出七煞來幫忙，煞能成格；財格逢比劫，傷官可以化解，傷能成格；食神帶煞，梟印得用，梟能成格；財格逢七煞，羊刃可以解厄，刃能成格。", note: ""),
                ClassicLine(id: "zp-19-3", n: 3, orig: "是故財不忌傷，官不忌梟，煞不忌刃，如治國長搶大戟，本非美具，而施之得宜，可以戡亂。", baihua: "所以說財格不忌傷官、官格不忌梟印、煞格不忌羊刃，正如治國用長槍大戟——兵器本身不是美物，用得其所卻可以平定禍亂。", note: "底本「如治國長搶大戟」，「搶」為「槍」之訛。"),
            ]),
            ClassicChapter(id: "zp-20", no: "二十", title: "論生克先後分吉凶", status: "included", source: "《子平真詮》二十·論生克先後分吉凶", lines: [
                ClassicLine(id: "zp-20-1", n: 1, orig: "月令用神，配以四柱，固有每字之生克以分吉凶，然有同此生克，而先後之間，遂分吉凶者，尤談命之奧也。", baihua: "月令用神配上四柱，固然每個字的生克都能分出吉凶，但更有同樣的生克、只因先後不同而吉凶頓異的情形，這正是論命最精妙的地方。", note: ""),
                ClassicLine(id: "zp-20-2", n: 2, orig: "如正官同是財傷並透，而先後有殊。假如甲用酉官，丁先戊後，後則以財為解傷，即不能貴，後運必有結局。若戊先而丁後時，則為官遇財生，而後因傷破，即使上運稍順，終無結局，子嗣亦難矣。", baihua: "比如正官格同樣是財與傷官並透，先後卻大不相同。假如甲日主用酉金正官，丁火傷官先透、戊土財星後透，後來的財可以化解先來的傷，雖然不能大貴，晚運必有好結局。若是戊土先透、丁火後透，就成了官星先得財生、隨後又被傷官所破，即使早運稍順，終究沒有好結局，連子嗣也難保。", note: ""),
                ClassicLine(id: "zp-20-3", n: 3, orig: "印格同是貪格壞印，而先後有殊。如甲用子印，己先癸後，即使不富，稍順晚境；若癸先而己在時，晚景亦悴矣。", baihua: "印格同樣是「貪財壞印」，先後也大不相同。比如甲日主用子水為印，己土財星先透、癸水印星後透，即使不富，晚境也還稍順；若是癸水先透、己土在時柱，晚景就淒涼了。", note: "底本「印格同是貪格壞印」，「格」為「財」之訛，當作「貪財壞印」。"),
                ClassicLine(id: "zp-20-4", n: 4, orig: "食神同是財梟並透，而先後有殊。如壬用甲食，庚先丙後，晚運必亨，格亦富而望貴。若丙先而庚在時，晚運必淡，富貴兩空矣。", baihua: "食神格同樣是財與梟印並透，先後也大不相同。比如壬日主用甲木食神，庚金梟印先透、丙火財星後透，晚運必定亨通，格局也富而有望貴。若是丙火先透、庚金在時柱，晚運必定淡薄，富貴兩空。", note: ""),
                ClassicLine(id: "zp-20-5", n: 5, orig: "七煞同是財食並透，而先後大殊。如己生卯月，癸先辛後，則為財以助用，而後煞用食制，不失大貴。若辛先而癸在時，則煞逢食制，而財轉食黨煞，非特不貴，後運蕭索，兼難永壽矣。", baihua: "七煞格同樣是財與食神並透，先後卻大不相同。比如己日主生在卯月，癸水財星先透、辛金食神後透，財先助煞、食後制煞，不失為大貴。若是辛金先透、癸水在時柱，煞先被食制、財後來黨煞，不但不貴，晚運蕭索，壽命也難長久。", note: ""),
                ClassicLine(id: "zp-20-6", n: 6, orig: "他如此類，可以例推。", baihua: "其他情形都可以由此類推。", note: ""),
                ClassicLine(id: "zp-20-7", n: 7, orig: "然猶吉凶易者也，至丙生甲寅月，年癸時戊，官能生印，而不怕戊合；戊能洩身為秀，而不得越甲以合癸，大貴之格也。假使年月戊癸而時甲，或年甲而月癸時戊，則戊無所隔而合全癸，格大破矣。", baihua: "以上還是吉凶容易分辨的；至於丙日主生在甲寅月，年干癸水、時干戊土，官星癸水能生印星甲木，不怕戊土來合；戊土能洩身為秀，又隔著甲木合不到癸水，是大貴之格。假使年月是戊癸並透而時上是甲，或者年上是甲而月癸時戊，戊土就沒有阻隔、把癸水全合走了，格局大破。", note: ""),
                ClassicLine(id: "zp-20-8", n: 8, orig: "丙生辛酉，年癸時己，傷因財間，傷之無力，間有小貴。假如癸己產並而中無辛隔，格盡破矣。", baihua: "丙日主生在辛酉月，年干癸水、時干己土，傷官因財星間隔而無力，間或有小貴。假如癸水己土並透而中間沒有辛金隔開，格局就全破了。", note: "底本「假如癸己產並而中無辛隔」，「產」為衍字。"),
                ClassicLine(id: "zp-20-9", n: 9, orig: "辛生申月，年壬月戊，時上丙官，不愁隔戊之壬，格亦許貴。假使年丙月壬而時戊，或年戊月丙而時壬，則壬能克丙，無望其貴矣。", baihua: "辛日主生在申月，年干壬水、月干戊土，時上丙火正官，不愁壬水隔著戊土去克丙火，格局也許貴。假使年丙月壬而時戊，或者年戊月丙而時壬，壬水就能克到丙火，就沒有指望貴了。", note: ""),
                ClassicLine(id: "zp-20-10", n: 10, orig: "如此之類，不可勝數，其中吉凶似難猝喻。然細思其故，理甚顯然，特難為淺者道耳。", baihua: "諸如此類數不勝數，其中吉凶似乎難以一下子說清；但細想其中的道理，其實很明白，只是難以向淺學者道出罷了。", note: ""),
            ]),
            ClassicChapter(id: "zp-21", no: "二十一", title: "論星辰無關格局", status: "included", source: "《子平真詮》二十一·論星辰無關格局", lines: [
                ClassicLine(id: "zp-21-1", n: 1, orig: "八字格局，專以月令配四柱，至於星辰好歹，既不能為生克之用，又何以操成敗之權？", baihua: "八字的格局，專門以月令配四柱來定；至於星辰的好壞，既然不能參與生克起作用，又怎麼能操縱成敗的權柄呢？", note: ""),
                ClassicLine(id: "zp-21-2", n: 2, orig: "況於局有礙，即財官美物，尚不能濟，何論吉星？於局有用，即七煞傷官，何謂凶神乎？", baihua: "何況對局勢有妨礙的，即使是財官這樣的美物尚且救不了，吉星又有什麼用？對局勢有用的，即使是七煞傷官，又憑什麼說它是凶神呢？", note: ""),
                ClassicLine(id: "zp-21-3", n: 3, orig: "是以格局既成，即使滿盤孤辰入煞，何損其貴？格局既破，即使満盤天德貴人，何以為功？", baihua: "所以格局既然成了，即使滿盤都是孤辰入煞，又損得了貴氣分毫？格局既然破了，即使滿盤都是天德貴人，又能有什麼功用？", note: ""),
                ClassicLine(id: "zp-21-4", n: 4, orig: "今人不知輕重，見是吉星，遂致拋卻用神，不管四柱，妄論貴賤，謬談禍福，甚可笑也。", baihua: "今人不知道輕重，見到是吉星，就拋開用神、不管四柱，妄論貴賤、胡談禍福，實在可笑。", note: ""),
                ClassicLine(id: "zp-21-5", n: 5, orig: "況書中所云祿貴，往往指正官而言，不是祿堂人貴人。", baihua: "何況書中所說的祿貴，往往是指正官而言，不是說祿堂和人貴人。", note: "底本「不是祿堂人貴人」，「人貴人」當作「天乙貴人」。"),
                ClassicLine(id: "zp-21-6", n: 6, orig: "如正財得傷貴為奇，傷貴也，傷官乃生財之具，正財得之，所以為奇，若指貴人，則傷貴為何物乎？", baihua: "比如正財得傷官而貴為奇格：傷官本是生財的工具，正財得了它，所以稱為奇；若把這裡的「貴」指作貴人，那「傷貴」又是個什麼東西呢？", note: ""),
                ClassicLine(id: "zp-21-7", n: 7, orig: "又若因得祿而避位，得祿者，得官也，運得官鄉，宜乎進爵，然如財用傷官食神，運透官則格條，正官運又遇官則重，凡此之類，只可避位也。", baihua: "又比如「因得祿而避位」：得祿就是得官，行運到了官鄉，本該進爵升官；可要是財格用傷官食神，行運透官就破格，正官運又遇官星就重疊——凡是這類情形，只宜避位。", note: "底本「格條」疑為「格破」之訛，今照錄不改。"),
                ClassicLine(id: "zp-21-8", n: 8, orig: "若作祿堂，不獨無是理，抑且得祿避位，文法上下相顧。古人作書，何至不通若是！", baihua: "若把這裡的「祿」作祿堂來解，不但沒有這個道理，而且「得祿避位」這句話上下文法也對不上。古人寫書，怎麼會不通到這種地步！", note: ""),
                ClassicLine(id: "zp-21-9", n: 9, orig: "又若女命，有云“貴眾則舞裙歌扇”。", baihua: "又比如女命，有句話叫「貴眾則舞裙歌扇」。", note: ""),
                ClassicLine(id: "zp-21-10", n: 10, orig: "貴眾者，官眾也，女以官為夫，正夫豈可疊出乎？一女眾夫，舞裙歌扇，理固然也。", baihua: "所謂貴眾，就是官眾：女命以官星為夫，正夫怎麼可以疊出呢？一女而有眾夫，不是舞裙歌扇之流是什麼？這道理本來很明白。", note: ""),
                ClassicLine(id: "zp-21-11", n: 11, orig: "若作貴人，乃是天星，並非夫主，何礙於眾，而必為娼妓乎？然星辰命書，亦有談及，不善看書者執之也。", baihua: "若把這裡的「貴」作貴人來解，貴人只是天上的星辰，並不是夫主，多幾個又有什麼妨礙，憑什麼就斷她必為娼妓呢？不過星辰命書裡也有這樣談的，是不善看書的人執著於此罷了。", note: ""),
                ClassicLine(id: "zp-21-12", n: 12, orig: "如“貴人頭上帶財官，門充馳馬”，蓋財官如人美貌，貴人如人衣服，貌之美者，衣服美則現。", baihua: "又比如「貴人頭上帶財官，門充馳馬」：財官好比人的美貌，貴人好比人的衣服，貌美的人，衣服美才顯得出來。", note: ""),
                ClassicLine(id: "zp-21-13", n: 13, orig: "其實財官成格，即非貴人頭上，怕不門充馳馬！", baihua: "其實財官一旦成格，即使不在貴人頭上，難道還怕門庭不車馬盈門嗎！", note: ""),
                ClassicLine(id: "zp-21-14", n: 14, orig: "又局清貴，又帶二德，必受榮封。若專主二德，則何不竟云帶二德受兩國之封，而秘先曰無煞乎？", baihua: "又說局勢清純而貴、又帶二德，就必定受榮封。若是專講二德，那為什麼不乾脆說「帶二德受兩國之封」，而必定要先說「無煞」呢？", note: "底本「而秘先曰無煞乎」，「秘」為「必」之訛。"),
                ClassicLine(id: "zp-21-15", n: 15, orig: "若云命逢險格，柱有二德，逢凶有救，右免於危，則亦有之，然終無關於格局之貴賤也。", baihua: "若是說命逢險格、柱中有二德，逢凶能得救、也免於危難，這話倒也有些道理，但終究與格局的貴賤無關。", note: "底本「右免於危」，「右」為「亦」之訛。"),
            ]),
            ClassicChapter(id: "zp-22", no: "二十二", title: "論外格用舍", status: "included", source: "《子平真詮》二十二·論外格用舍", lines: [
                ClassicLine(id: "zp-22-1", n: 1, orig: "八字用神既專主月令，何以又有外格乎？外格者，蓋因月令無用，權而用之，故曰外格也。", baihua: "八字的用神既然專主月令，為什麼又會有外格呢？所謂外格，是因為月令之中沒有可用的用神，才權宜地在月令之外取用，所以叫外格。", note: ""),
                ClassicLine(id: "zp-22-2", n: 2, orig: "如春木冬水、土生四季之類，日與月同，難以作用，類象、屬象、沖財、會祿、刑合、遙迎、井欄、朝陽諸格，皆可用也。", baihua: "比如春木、冬水、土生四季之類，日主與月令同氣、難以作用，像類象、屬象、沖財、會祿、刑合、遙迎、井欄、朝陽這些格，都是可以用的。", note: ""),
                ClassicLine(id: "zp-22-3", n: 3, orig: "若月令自有用神，豈可另尋外格？又或春木冬水，干頭己有財官七煞，而棄之以就外格，亦太謬矣。", baihua: "若是月令自有可用的用神，怎麼可以另尋外格？又比如春木冬水，干頭已經有了財官七煞，卻棄置不用而去就外格，也實在太荒謬了。", note: ""),
                ClassicLine(id: "zp-22-4", n: 4, orig: "是故干頭有財，何用沖財？干頭有官，何用合祿？書云“提綱有用提綱重”，又曰“有官莫尋格局”，不易之論也。", baihua: "所以說：干頭有財，何必用沖財格？干頭有官，何必用合祿格？書上說「提綱有用提綱重」，又說「有官莫尋格局」，都是不可移易的至理。", note: ""),
                ClassicLine(id: "zp-22-5", n: 5, orig: "然所謂月令無用者，原是月令本無用神，而今人不知，往往以財被劫官被傷之類。用神已破，皆以為月令無取，而棄之以就外格，則謬之又謬矣。", baihua: "然而所謂「月令無用」，本來是指月令之中本無用神；而今人不知道這一點，往往把財被劫奪、官被傷破之類用神已破的情形，都當作月令無取，棄置不用而去就外格，那就謬上加謬了。", note: ""),
            ]),
            ClassicChapter(id: "zp-23", no: "二十三", title: "論宮分用神配六親", status: "included", source: "《子平真詮》二十三·論宮分用神配六親", lines: [
                ClassicLine(id: "zp-23-1", n: 1, orig: "人有六親，配之八字，亦存於命。", baihua: "人有六親，配到八字裡，也都存在於命局之中。", note: ""),
                ClassicLine(id: "zp-23-2", n: 2, orig: "其由宮分配之者，則年月日時，自上而下，祖父妻子，亦自上而下。以地相配，適得其宜，不易之位也。", baihua: "按宮位來分配，六親從年月日時自上而下排布：祖父、父母、妻子、兒女，也是自上而下。以地支宮位相配，恰得其宜，是不可移易的位置。", note: ""),
                ClassicLine(id: "zp-23-3", n: 3, orig: "其由用神配之者，則正印也母，身所自出，取其生我也。", baihua: "按用神來配：正印是母親，因為日主是從印星生出來的，取其生我之義。", note: "底本「則正印也母」，「也」為「為」之訛，當作「正印為母」。"),
                ClassicLine(id: "zp-23-4", n: 4, orig: "若偏財受我剋制，何反為父？偏財者，母之正夫也，正印為母，則偏才為父矣。", baihua: "若偏財受我剋制，為什麼反而是父親呢？偏財是母親的正夫：正印既然為母，偏財自然就是父了。", note: "底本「則偏才為父矣」，「才」為「財」之訛。"),
                ClassicLine(id: "zp-23-5", n: 5, orig: "正財為妻，受我剋制，夫為妻綱，妻則從夫。", baihua: "正財為妻，因為正財受我剋制；夫為妻之綱，妻則從夫。", note: ""),
                ClassicLine(id: "zp-23-6", n: 6, orig: "若官煞則剋制乎我，何以反為子女也？官煞者，財所生也，財為妻妾，則官煞為子女矣。", baihua: "若官煞剋制著我，為什麼反而是子女呢？官煞是財所生的：財既然為妻妾，官煞自然就是子女了。", note: ""),
                ClassicLine(id: "zp-23-7", n: 7, orig: "至於比肩為兄弟，又理之顯然者。", baihua: "至於比肩為兄弟，又是道理很明白的事。", note: ""),
                ClassicLine(id: "zp-23-8", n: 8, orig: "其間有無得力，或吉或凶，則以四柱所存或年月或日時財官傷刃，繫是何物，然後以六親配之用神。局中作何喜忌，參而配之，可以瞭然矣。", baihua: "其間六親有沒有得力、是吉是凶，就要看四柱之中存著的、或在年月或在日時的是財官傷刃中的哪一個，然後再按六親配用神。局中作何喜忌，參合配比，就可以瞭然了。", note: ""),
            ]),
            ClassicChapter(id: "zp-24", no: "二十四", title: "論妻子", status: "included", source: "《子平真詮》二十四·論妻子", lines: [
                ClassicLine(id: "zp-24-1", n: 1, orig: "大凡命中吉凶，於人愈近，其驗益靈。富貴貧賤，本身之事，無論矣，至於六親，妻以配身，子為後嗣，亦是切身之事。", baihua: "大凡命中的吉凶，關係到人越近，應驗就越靈。富貴貧賤是本身的事，不必說了；至於六親，妻子配身、兒子是後嗣，也都是切身的事。", note: ""),
                ClassicLine(id: "zp-24-2", n: 2, orig: "故看命者，妻財子提綱得力，或年干有用，皆主父母身所自出，亦自有驗。所以提綱得力，或年干有用，皆主父母雙全得力。", baihua: "所以看命的人說：妻財子星在提綱得力，或者年干有用，都主父母——因為父母是自身所從出的，自然也有應驗。所以提綱得力、或者年干有用，都主父母雙全得力。", note: ""),
                ClassicLine(id: "zp-24-3", n: 3, orig: "至於祖宗兄弟，不甚驗矣。", baihua: "至於祖宗兄弟，就不太應驗了。", note: ""),
                ClassicLine(id: "zp-24-4", n: 4, orig: "以妻論之，坐下財官，妻當賢貴；然亦有坐財官而妻不利，逢傷刃而妻反吉者，何也？此蓋月令用神，配成喜忌。", baihua: "拿妻子來論：坐下是財官，妻子應當賢貴；然而也有坐財官而妻子不利、逢傷官羊刃而妻子反吉的，這是為什麼？這是因為月令用神配成的喜忌不同。", note: ""),
                ClassicLine(id: "zp-24-5", n: 5, orig: "如妻宮坐財，吉也，而印格逢之，反為不美。妻坐官，吉也，而傷官逢之，豈能順意？妻坐傷官，凶也，而財格逢之，可以生堸，煞格逢之，可以制煞，反主妻能內助。妻坐陽刃，凶也，而或財官煞傷等格，四柱已成格局，而日主無氣，全憑日刃幫身，則妻必能相關。", baihua: "比如妻宮坐財，本是吉，可印格逢了它反而不美。妻坐官，本是吉，可傷官格逢了它怎麼能順意？妻坐傷官，本是凶，可財格逢了它可以生財、煞格逢了它可以制煞，反主妻子能內助。妻坐陽刃，本是凶，可若是財官煞傷等格、四柱已成格局而日主無氣、全憑日刃幫身，妻子必定能相助。", note: "底本「可以生堸」，「堸」為「財」之訛，當作「可以生財」。"),
                ClassicLine(id: "zp-24-6", n: 6, orig: "其理不可執一。", baihua: "其中的道理不可執著一端。", note: ""),
                ClassicLine(id: "zp-24-7", n: 7, orig: "既看妻宮，又看妻星。妻星者，干頭之財也。", baihua: "既要看妻宮，又要看妻星。妻星就是干頭的財。", note: ""),
                ClassicLine(id: "zp-24-8", n: 8, orig: "妻透而成局，若官格透財、印多逢財、食傷透財為用之類，即坐下無用，亦主內助。", baihua: "妻星透出來而成局，比如官格透財、印多逢財、食傷透財為用之類，即使坐下無用，也主妻子能內助。", note: ""),
                ClassicLine(id: "zp-24-9", n: 9, orig: "妻透而破格，若印輕財露、食神傷官、透煞逢財之類，即坐下有用，亦防刑剋。", baihua: "妻星透出來而破格，比如印輕財露、食神傷官、透煞逢財之類，即使坐下有用，也要防刑剋。", note: ""),
                ClassicLine(id: "zp-24-10", n: 10, orig: "又有妻透成格，或妻宮有用而坐下刑沖，未免得美妻而難偕老。又若妻星兩透，偏正雜出，何一夫而多妻？亦防刑剋之道也。", baihua: "又有妻星透出而成格、或者妻宮有用卻坐下刑沖的，難免得了美妻卻難以偕老。又若妻星兩透、偏正雜出，豈是一個丈夫配多個妻子？這也是要防刑剋的道理。", note: ""),
                ClassicLine(id: "zp-24-11", n: 11, orig: "至於子息，其看宮分與星所透喜忌，理與論妻略同。", baihua: "至於子息，看宮分與所透之星的喜忌，道理與論妻略同。", note: ""),
                ClassicLine(id: "zp-24-12", n: 12, orig: "但看子息，長生沐浴之歌，亦當熟讀，如“長生四子中旬半，沐浴一雙保吉祥，冠帶臨官三子位，旺中五子自成行，衰中二子病中一，死中至老沒兒郞，除非養取他之子，入墓之時命夭亡，受氣為絕一個子，胎中頭產養姑娘，養中三子只留一，男子宮中子細詳”是也。", baihua: "但看子息時，長生沐浴之歌也應當熟讀，比如「長生四子中旬半，沐浴一雙保吉祥，冠帶臨官三子位，旺中五子自成行，衰中二子病中一，死中至老沒兒郎，除非養取他之子，入墓之時命夭亡，受氣為絕一個子，胎中頭產養姑娘，養中三子只留一，男子宮中子細詳」就是。", note: ""),
                ClassicLine(id: "zp-24-13", n: 13, orig: "然長生論法，用陽而不用陰。如甲乙日只用庚金長生，巳酉丑順數之局，而不用辛金逆數之子申辰。", baihua: "不過長生論法，只用陽、不用陰。比如甲乙日只用庚金長生、巳酉丑順數之局，而不用辛金逆數之子申辰。", note: ""),
                ClassicLine(id: "zp-24-14", n: 14, orig: "雖書有官為女煞為男之說，然終不可以甲用庚男而用陽局，乙用辛男而陰局。蓋木為日主，不問甲乙，總以庚為男辛為女，其理為然，拘於官煞，其能驗乎？", baihua: "雖然書上有「官為女、煞為男」的說法，但終究不能因為甲用庚為男就用陽局、乙用辛為男就用陰局。因為木是日主，不問甲乙，總以庚為男、辛為女，這個道理才是對的；拘泥於官煞之說，怎麼能應驗呢？", note: ""),
                ClassicLine(id: "zp-24-15", n: 15, orig: "所以八字到手，要看子息，先看時支。如甲乙生日，其時果係庚金何宮？或生旺，或死絕，其多寡己有定數，然後以時干子星配之。", baihua: "所以八字到手，要看子息，先看時支。比如甲乙日生的人，時支果然是庚金在哪一宮？或是生旺、或是死絕，子息的多寡已經有定數，然後再以時干子星來配。", note: ""),
                ClassicLine(id: "zp-24-16", n: 16, orig: "如財格而時干透食，官格而時干透財之類，皆謂時干有用，即使時逢死絕，亦主子貴，但不甚繁耳。", baihua: "比如財格而時干透食神、官格而時干透財之類，都叫時干有用，即使時支逢死絕，也主兒子貴，只是不太繁盛罷了。", note: ""),
                ClassicLine(id: "zp-24-17", n: 17, orig: "若又逢生旺，則麟兒繞膝，豈可量乎？", baihua: "若是又逢生旺，麟兒繞膝，數目豈可限量？", note: ""),
                ClassicLine(id: "zp-24-18", n: 18, orig: "若時干不好，子透破局，即逢生旺，難為子息。若又死絕，無所望矣。此論妻子之大略也。", baihua: "若是時干不好，子星透出來破局，即使逢生旺，也難有子息。若是又逢死絕，就沒有指望了。這就是論妻子的概略。", note: ""),
            ]),
            ClassicChapter(id: "zp-25", no: "二十五", title: "論行運", status: "included", source: "《子平真詮》二十五·論行運", lines: [
                ClassicLine(id: "zp-25-1", n: 1, orig: "論運與看命無二法也。看命以四柱干支，配月令之喜忌，而取運則又以運之干，配八字之喜忌。故運中每運行一字，即必以此一字，配命中干支而統觀之，為喜為忌，吉凶判然矣。", baihua: "論運與看命沒有兩種方法。看命以四柱干支配月令的喜忌，取運則又以運的干支配八字的喜忌。所以運中每運行一個字，就必定拿這一個字配命中的干支統觀全局，是喜是忌，吉凶就判然了。", note: ""),
                ClassicLine(id: "zp-25-2", n: 2, orig: "何為喜？命中所喜之神，我得而助之者是也。如官用印以制傷，而運助印；財生官而身輕，而運助身；印帶財以為忌，而運劫財；食帶煞以成格，身輕而運逢印，煞重而運助食；傷官佩印，而運行官煞；陽刃用官，而運助財鄉；月劫用財，而運行傷食。", baihua: "什麼叫喜？命中所喜之神，我得到它來相助就是。比如官格用印來制傷，行運助印；財生官而身輕，行運助身；印格帶財以為忌，行運劫財；食神帶煞而成格，身輕而行運逢印，煞重而行運助食；傷官佩印，行運逢官煞；陽刃用官，行運助財鄉；月劫用財，行運行傷食。", note: ""),
                ClassicLine(id: "zp-25-3", n: 3, orig: "如此之類，皆美運也。", baihua: "諸如此類，都是美運。", note: ""),
                ClassicLine(id: "zp-25-4", n: 4, orig: "何謂忌？命中所忌，我逆而施之者是也。如正官無印，而運行傷；財不透食，而運行煞；印綬用官，而運合官；食神帶煞，而運行財；七煞食制，而運逢梟；傷官佩印，而運行財；陽刃用煞，而運逢食；建祿用官，而運逢傷。", baihua: "什麼叫忌？命中所忌之神，我逆著它去施為就是。比如正官無印，行運逢傷；財不透食，行運逢煞；印綬用官，行運合官；食神帶煞，行運逢財；七煞得食制，行運逢梟；傷官佩印，行運行財；陽刃用煞，行運逢食；建祿用官，行運逢傷。", note: ""),
                ClassicLine(id: "zp-25-5", n: 5, orig: "如此之類，皆敗運也。", baihua: "諸如此類，都是敗運。", note: ""),
                ClassicLine(id: "zp-25-6", n: 6, orig: "其有似喜而實忌者，何也？如官逢印運，而本命有合，印逢官運，而本命用煞之類是也。", baihua: "又有看似喜而實際是忌的，是怎麼回事？比如官格逢印運，而本命有合；印格逢官運，而本命用煞之類就是。", note: ""),
                ClassicLine(id: "zp-25-7", n: 7, orig: "有似忌而實喜者，何也？如官逢傷運，而命透印，財行煞運，而命透食之類是也。", baihua: "又有看似忌而實際是喜的，是怎麼回事？比如官格逢傷運，而命透印；財行煞運，而命透食之類就是。", note: ""),
                ClassicLine(id: "zp-25-8", n: 8, orig: "又有行干而不行支者，何也？如丙生子月亥年，逢丙丁則幫身，逢巳午則相沖是也。", baihua: "又有行干而不行支的，是怎麼回事？比如丙日主生在子月亥年，逢丙丁就幫身，逢巳午就相沖，就是這個道理。", note: ""),
                ClassicLine(id: "zp-25-9", n: 9, orig: "又有行支而不行干者，何也？如甲生酉月，辛金透而官猶弱，逢申酉則官植根，逢庚辛則混煞重官之類是也。", baihua: "又有行支而不行干的，是怎麼回事？比如甲日主生在酉月，辛金透出而官星還弱，逢申酉官星就植了根，逢庚辛就混煞重官之類就是。", note: ""),
                ClassicLine(id: "zp-25-10", n: 10, orig: "又有干同一類而不兩行者，何也？如丁生亥月，而年透壬官，逢丙則幫身，逢丁則合官之類是也。", baihua: "又有干同一類而不兩行的，是怎麼回事？比如丁日主生在亥月，年干透壬水正官，逢丙火就幫身，逢丁火就合官之類就是。", note: ""),
                ClassicLine(id: "zp-25-11", n: 11, orig: "又有支同一類而不兩行者，何也？如戊生卯月，丑年，逢申則自坐長生，逢酉則會丑以傷官之類是也。", baihua: "又有支同一類而不兩行的，是怎麼回事？比如戊日主生在卯月、丑年，逢申就自坐長生，逢酉就與丑會成傷官之類就是。", note: ""),
                ClassicLine(id: "zp-25-12", n: 12, orig: "又有同是相沖而分緩急者，何也？沖年月則急，沖日時則緩也。", baihua: "又有同是相沖而分緩急的，是怎麼回事？沖年月就急，沖日時就緩。", note: ""),
                ClassicLine(id: "zp-25-13", n: 13, orig: "又有同是相沖而分輕重者，何也？運本美而逢沖則輕，運既忌面又沖則重也。", baihua: "又有同是相沖而分輕重的，是怎麼回事？運本來美、逢沖就輕，運本來忌、又逢沖就重。", note: "底本「運既忌面又沖則重也」，「面」為「而」之訛。"),
                ClassicLine(id: "zp-25-14", n: 14, orig: "又有逢沖而不沖，何也？如甲用酉官，行卯則沖，而本命巳酉相會，則沖無力；年支亥未，則卯逢年會而不沖月官之類是也。", baihua: "又有逢沖而不沖的，是怎麼回事？比如甲日主用酉官，行卯運就沖，可本命巳酉相會，沖就無力；年支有亥未，卯逢年支會合而不沖月令官星之類就是。", note: ""),
                ClassicLine(id: "zp-25-15", n: 15, orig: "又有一沖而得兩沖者，何也？如乙用申官，兩申並而不沖一寅，運又逢寅，則運與本命，合成二寅，以沖二申之類是也。", baihua: "又有一沖而得兩沖的，是怎麼回事？比如乙日主用申官，兩申並列而不沖一寅，行運又逢寅，運與本命合成二寅、來沖二申之類就是。", note: ""),
            ]),
            ClassicChapter(id: "zp-26", no: "二十六", title: "論行運成格變格", status: "included", source: "《子平真詮》二十六·論行運成格變格", lines: [
                ClassicLine(id: "zp-26-1", n: 1, orig: "命之格局，成於八字，然配之以運，亦有成格變格之要權。其成格變格，較之喜忌禍福尤重。", baihua: "命的格局成於八字，但配上行運，也有成格變格的權衡。成格變格的輕重，比喜忌禍福還要重要。", note: ""),
                ClassicLine(id: "zp-26-2", n: 2, orig: "何為成格？本命用神，成而未全，從而就之者是也。如丁生辰月，透壬為宮，而運逢申子以會之；乙生辰月，或申或子會印成局，而運逢壬癸以透之。如此之類，皆成格也。", baihua: "什麼叫成格？本命用神已經成了、但還未全，行運來補足它就是。比如丁日主生在辰月，透壬水為官，行運逢申子來會成水局；乙日主生在辰月，或申或子會印成局，行運逢壬癸來透出。", note: "底本「透壬為宮」，「宮」為「官」之訛。"),
                ClassicLine(id: "zp-26-3", n: 3, orig: "何為變格？如丁生辰月，透壬為官，而運逢戌，透出辰中傷官；壬生戌月，丁己並透，而支又會寅會午，作財旺生官矣，而運逢戊土，透出戌中七煞；壬生亥月，透己為用，作建祿用官矣，而運逢卯未，會亥成本，又化建祿為傷。如此之類，皆變格也。", baihua: "什麼叫變格？比如丁日主生在辰月，透壬水為官，行運逢戌，透出辰中傷官；壬日主生在戌月，丁己並透，支又會寅會午，作成財旺生官，行運逢戊土，透出戌中七煞；壬日主生在亥月，透己土為用，作成建祿用官，行運逢卯未，會亥成本，又把建祿化成了傷官。諸如此類，都是變格。", note: ""),
                ClassicLine(id: "zp-26-4", n: 4, orig: "然亦有逢成格而不喜者，何也？如壬生午月，運透己官，而本命有甲乙之類是也。", baihua: "然而也有逢成格而不喜的，是怎麼回事？比如壬日主生在午月，行運透己土官星，而本命有甲乙木之類就是。", note: ""),
                ClassicLine(id: "zp-26-5", n: 5, orig: "又有逢變格而不忌者，何也？如丁生辰月，透壬用官，逢戊而命有甲；壬生亥月，透己用官，運逢卯未，而命有庚辛之類是也。", baihua: "又有逢變格而不忌的，是怎麼回事？比如丁日主生在辰月，透壬水用官，逢戊土而命中有甲木；壬日主生在亥月，透己土用官，行運逢卯未而命中有庚辛之類就是。", note: ""),
                ClassicLine(id: "zp-26-6", n: 6, orig: "成格變格，關係甚大，取運者其細詳之。", baihua: "成格變格關係甚大，取運的人要細細詳究。", note: ""),
            ]),
            ClassicChapter(id: "zp-27", no: "二十七", title: "論喜忌干支有別", status: "included", source: "《子平真詮》二十七·論喜忌干支有別", lines: [
                ClassicLine(id: "zp-27-1", n: 1, orig: "命中喜忌，雖支干俱有，而干主天，動而有為，支主地，靜以待用，且干主一而支藏多，為福為禍，安不得殊？", baihua: "命中的喜忌，雖然干支都有，但天干主天、動而有為，地支主地、靜以待用；而且天干主一、地支藏多，為福為禍，怎麼能沒有分別？", note: ""),
                ClassicLine(id: "zp-27-2", n: 2, orig: "譬如甲用酉官，逢庚辛則官煞雜，而申酉不作此例。申亦辛之旺地，辛坐申酉，如府官又掌道印也。", baihua: "譬如甲日主用酉金正官，逢庚辛天干就官煞混雜，而逢申酉地支就不作此論。申也是辛金的旺地，辛金坐在申酉上，就像府官又掌道印一樣。", note: ""),
                ClassicLine(id: "zp-27-3", n: 3, orig: "逢二辛則官犯重，而二酉不作此例。辛坐二酉，如一府而攝二郡也，透丁則傷官，而逢午不作此例。", baihua: "逢兩個辛金天干就官星犯重，而逢兩個酉金地支就不作此論。辛金坐在兩個酉上，就像一個府管攝兩個郡一樣；透出丁火就傷官，而逢午火地支就不作此論。", note: ""),
                ClassicLine(id: "zp-27-4", n: 4, orig: "丁動而午靜，且丁巳並藏，安知其為財也？", baihua: "丁火動而午火靜，而且丁與巳並藏在午中，怎麼知道它就是財星呢？", note: "底本「丁巳並藏」，「巳」為「己」之訛，當作「丁己並藏」。"),
                ClassicLine(id: "zp-27-5", n: 5, orig: "然亦有支而能作禍福者，何也？如甲用酉官，逢午酉未能傷，而又遇寅遇戌，不隔二位，二者合而火動，亦能傷矣。", baihua: "然而也有地支能作禍福的，是怎麼回事？比如甲日主用酉官，逢午酉還未能傷官，可又遇到寅、遇到戌，不隔兩個位置，兩者一合火就動了，也能傷官。", note: ""),
                ClassicLine(id: "zp-27-6", n: 6, orig: "即此反觀，如甲生甲月，午不制煞，會寅會戌，二者清局而火動，亦能矣。", baihua: "即此反觀：比如甲日主生在申月，午火不制煞，會寅會戌，兩者清局而火動，也能傷官。", note: "底本「如甲生甲月」，據文義當為申月。"),
                ClassicLine(id: "zp-27-7", n: 7, orig: "然必會有動，是正與干有別也。即此一端，餘者可知。", baihua: "然而必定要有動，這正是地支與天干不同的地方。即此一端，其餘的就可以知道了。", note: "底本末句「亦能矣」下脫一字，《子平真詮評註》本作「亦能傷矣」。"),
            ]),
            ClassicChapter(id: "zp-28", no: "二十八", title: "論支中喜忌逢運透清", status: "included", source: "《子平真詮》二十八·論支中喜忌逢運透清", lines: [
                ClassicLine(id: "zp-28-1", n: 1, orig: "支中喜忌，固與干有別矣，而運逢透清，則靜而待用者，正得其用，而喜忌之驗，於此乃見。", baihua: "支中喜忌固然與干有分別，但行運逢到透清，靜以待用的地支正好得了它的用，喜忌的應驗就在這裡顯現。", note: ""),
                ClassicLine(id: "zp-28-2", n: 2, orig: "何謂透清？如甲用酉官，逢辰未即為財，而運透戊，逢午未即為傷，而運透丁之類是也。", baihua: "什麼叫透清？比如甲日主用酉官，逢辰未就是財，行運透出戊土；逢午未就是傷，行運透出丁火之類就是。", note: ""),
                ClassicLine(id: "zp-28-3", n: 3, orig: "若命與運二支會局，亦作清論。如甲用酉官，本命有午，而運逢寅戌之類。", baihua: "若是命與運兩個地支會局，也作清純來論。比如甲日主用酉官，本命有午火，行運逢寅戌之類。", note: ""),
                ClassicLine(id: "zp-28-4", n: 4, orig: "然在年則重，在日次之，至於時生於午，而運逢寅戌會局，則緩而不急矣。", baihua: "然而在年柱就重，在日柱次之，至於時柱生在午，行運逢寅戌會局，就緩而不急了。", note: ""),
                ClassicLine(id: "zp-28-5", n: 5, orig: "雖格之成敗高低，八字己有定論，與命中原有者不同，而此五年中，亦能炒其禍福。", baihua: "雖然格的成敗高低，八字已經有定論，與命中原有的不同，但這五年之中，也能操縱它的禍福。", note: "底本「八字己有定論」之「己」為「已」之訛，「亦能炒其禍福」之「炒」為「操」之訛。"),
                ClassicLine(id: "zp-28-6", n: 6, orig: "若月令之物，而運中透清，則與命中原有者，不甚相懸，即前篇所謂行運成格變格是也。", baihua: "若是月令的東西，行運中透清，就與命中原有的相差不遠，就是前篇所說的行運成格變格。", note: ""),
                ClassicLine(id: "zp-28-7", n: 7, orig: "故凡一八字到手，必須逐干逐支，上下統看。支為干之生地，干為支之發用。", baihua: "所以凡是一個八字到手，必須逐干逐支、上下統看。地支是天干的生地，天干是地支的發用。", note: ""),
                ClassicLine(id: "zp-28-8", n: 8, orig: "如命中有一甲字，則統觀四支，有寅亥卯未等字否，有一字，皆甲木之根也。", baihua: "比如命中有一甲字，就統觀四支，有沒有寅、亥、卯、未這些字，有一個字，都是甲木的根。", note: ""),
                ClassicLine(id: "zp-28-9", n: 9, orig: "有一亥字，則統觀四支，有壬甲二字否。有壬，則亥為壬祿，以壬水用；用甲，則亥為甲長生，以甲木用；用壬甲俱全，則一以祿為根，一以長生為根，二者並用。", baihua: "有一亥字，就統觀四支，有沒有壬、甲兩個字。有壬，亥就是壬的祿，以壬水為用；用甲，亥就是甲的長生，以甲木為用；壬甲俱全，就一個以祿為根、一個以長生為根，兩者並用。", note: ""),
                ClassicLine(id: "zp-28-10", n: 10, orig: "取運亦用此術，將本命八字，逐干支配之而已。", baihua: "取運也用這個方法，把本命八字逐干支配比就是了。", note: ""),
            ]),
            ClassicChapter(id: "zp-29", no: "二十九", title: "論時說拘泥格局", status: "included", source: "《子平真詮》二十九·論時說拘泥格局", lines: [
                ClassicLine(id: "zp-29-1", n: 1, orig: "八字用神專憑月令，月無用神，臺尋格局。月令，本也；外格，未也。", baihua: "八字的用神專憑月令；月令若沒有用神，才到月令之外尋格局。月令是根本，外格是末梢。", note: "底本「臺尋格局」，「臺」字為訛文，《子平真詮評註》本作「徐尋格局」；又作「外格，未也」，「未」為「末」之訛。"),
                ClassicLine(id: "zp-29-2", n: 2, orig: "今人不知輕重，拘泥格局，執假失真。", baihua: "今人不知道輕重，拘泥於格局，執著虛假、失了真實。", note: ""),
                ClassicLine(id: "zp-29-3", n: 3, orig: "故戊生甲寅之月，時上庚甲，不以為明煞有制，而以為專食之格，逢甲減福。丙生子月，時逢巳祿，不以為正官之格，歸祿幫身，而以為日祿歸時，逢官破局。辛日透丙，時遇戊子，不以為辛日得官逢印，而以為朝陽之格，因丙無成。", baihua: "所以戊日主生在甲寅月，時上見庚甲，不當作明煞有制，反當作專食之格、逢甲減福。丙日主生在子月，時逢巳祿，不當作正官之格、歸祿幫身，反當作日祿歸時、逢官破局。辛日透丙火，時遇戊子，不當作辛日得官逢印，反當作朝陽之格、因丙無成。", note: ""),
                ClassicLine(id: "zp-29-4", n: 4, orig: "財逢時煞，不以為生煞攻身，而以為時上偏官。癸生巳月，時遇甲寅，不以為暗官受破，而以為刑合成格。癸生冬月，酉日亥時，透戊坐戌，不以為月劫建祿，用官通根，而以為拱戌之格，填實不利。辛日坐丑，寅年，亥月，卯時，不以為正財之格，而以為填實拱貴。乙逢寅月，時遇丙子，不以為木火通明，而以為格成鼠貴。", baihua: "財格逢時上七煞，不當作生煞攻身，反當作時上偏官。癸日主生在巳月，時遇甲寅，不當作暗官受破，反當作刑合成格。癸日主生在冬月，酉日亥時，透戊坐戌，不當作月劫建祿、用官通根，反當作拱戌之格、填實不利。辛日坐丑，寅年、亥月、卯時，不當作正財之格，反當作填實拱貴。乙日主逢寅月，時遇丙子，不當作木火通明，反當作格成鼠貴。", note: ""),
                ClassicLine(id: "zp-29-5", n: 5, orig: "如此謬論，百無一是，此皆由不知命理，妄為評斷。", baihua: "如此謬論，百無一是，都是因為不知道命理、妄加評斷。", note: ""),
            ]),
            ClassicChapter(id: "zp-30", no: "三十", title: "論時說以訛傳訛", status: "included", source: "《子平真詮》三十·論時說以訛傳訛", lines: [
                ClassicLine(id: "zp-30-1", n: 1, orig: "八字本有定理，理之不明，遂生導端，妄言妄聽，牢不可破。", baihua: "八字本來有定理，道理不明，就生出異端，妄言妄聽，牢不可破。", note: "底本「遂生導端」之「導端」當作「異端」。"),
                ClassicLine(id: "zp-30-2", n: 2, orig: "如論干支，則不知陰陽之理，而以俗書體象歌訣為確論；論格局，則不知專尋月令，而以拘泥外格為活變；論生克，則不察喜忌，而以傷旺扶弱為定法；論行運，則不問同中有導，而以干支相類為一例。", baihua: "比如論干支，不知陰陽之理，卻以俗書體象歌訣為確論；論格局，不知專尋月令，卻以拘泥外格為活變；論生克，不察喜忌，卻以傷旺扶弱為定法；論行運，不問同中有異，卻以干支相類為一例。", note: "底本「同中有導」之「導」當作「異」。"),
                ClassicLine(id: "zp-30-3", n: 3, orig: "究其緣由，一則書中用字輕重，不知其意，而謬生偏見；一則以鵒書無知妄作，誤會其說，而深入迷途；一則論命取運，偶然湊合，而遂以己見為不易，一則以古人命式，亦有誤收，即收之不誤，又以己意入外格，尤為害人不淺。", baihua: "追究其緣由：一是書中用字的輕重，不知其意，因而謬生偏見；二是以俗書無知妄作，誤會其說，因而深入迷途；三是論命取運偶然湊合，就以己見為不易；四是以古人命式也有誤收，即使收得不誤，又以己意入外格，尤其害人不淺。", note: "底本「以鵒書無知妄作」之「鵒書」當作「俗書」。"),
                ClassicLine(id: "zp-30-4", n: 4, orig: "如壬申、癸丑、己丑、甲戌，本雜氣財旺生官也，而以為乙亥時，作時上偏官論，豈知旺財生煞，將救死之不暇，於何取貴？此類甚多，皆誤收格局也。", baihua: "比如壬申、癸丑、己丑、甲戌四柱，本是雜氣財旺生官，卻以為是乙亥時、作時上偏官來論，豈知旺財生煞，救死都來不及，還從哪裡取貴？這一類很多，都是誤收格局。", note: ""),
                ClassicLine(id: "zp-30-5", n: 5, orig: "如己未、壬申、戊子、庚申，本食神生財也，而欲棄月令，以為戊日庚申合祿之格，豈知本身自有財食，豈不甚美？又何勞以庚合乙，求局外之官乎，此類甚多，皆硬入外格也。", baihua: "比如己未、壬申、戊子、庚申四柱，本是食神生財，卻要棄置月令，以為是戊日庚申合祿之格，豈知本身自有財食，豈不是很美？又何必以庚合乙、求局外之官呢？這一類很多，都是硬入外格。", note: ""),
                ClassicLine(id: "zp-30-6", n: 6, orig: "人苟中無定見，察理不精，睹此謬論，豈能無惑？何況近日貴格不可解者，亦往往有之乎？", baihua: "人若心中沒有定見、察理不精，看到這種謬論，怎麼能不疑惑？何況近日那些不可解的貴格，也往往有這種情形呢？", note: ""),
                ClassicLine(id: "zp-30-7", n: 7, orig: "豈知行術之人，必以貴命為指歸，或將風聞為實據，或探其生日，而即以己意加之生時，謬造貴格，其人之八字，時多未確，即彼本身，亦不自知。", baihua: "豈知行術的人，必定以貴命為指歸，或者把風聞當作實據，或者探得其生日，就以己意加上生時，謬造貴格；那人的八字，時辰多半不確，連他本人也不自知。", note: ""),
                ClassicLine(id: "zp-30-8", n: 8, orig: "若看命者不究其本，而徒以彼既富貴遷就其說以相從，無惑乎終身無解日矣！", baihua: "若看命的人不追究其根本，只因對方既然富貴就遷就其說來附和，難怪終身沒有解開的一天！", note: ""),
            ]),
            ClassicChapter(id: "zp-31", no: "三十一", title: "論正官", status: "included", source: "《子平真詮》三十一·論正官", lines: [
                ClassicLine(id: "zp-31-1", n: 1, orig: "官以克身，雖與七煞有別，終受彼制，何以切忌刑沖破害，尊之若是乎？", baihua: "官星以克身為職，雖然與七煞有分別，終究受它克制，為什麼要切忌刑沖破害、尊敬它到這種地步呢？", note: ""),
                ClassicLine(id: "zp-31-2", n: 2, orig: "豈知人生天地間，必無矯焉自尊之理，雖貴極天子，亦有天祖臨之。正官者分所當尊，如在國有君，在家有親，刑沖破害，以下犯上，烏乎可乎？以刑沖破害為忌，則以生之護之為喜矣。", baihua: "豈知人生在天地之間，必定沒有矯揉造作、自尊自大的道理，即使貴到天子，也有天祖在上臨御。正官是分所當尊的，就像在國有君、在家有親；刑沖破害是以下犯上，怎麼可以呢？既然以刑沖破害為忌，就以生它護它為喜了。", note: ""),
                ClassicLine(id: "zp-31-3", n: 3, orig: "存其喜而去其忌則貴，而貴之中又有高低者，何也？以財印並透者論之，兩不相礙，其貴也大。", baihua: "存其所喜、去其所忌就貴；貴之中又有高低，是為什麼呢？拿財印並透的來論，兩者互不相礙，貴就大。", note: ""),
                ClassicLine(id: "zp-31-4", n: 4, orig: "如薛相公命，甲申、壬申、乙巳、戊寅，壬印戊財，以乙隔之，水與土不相礙，故為大貴。", baihua: "比如薛相公命：甲申、壬申、乙巳、戊寅，壬水為印、戊土為財，中間以乙木隔開，水與土互不相礙，所以大貴。", note: ""),
                ClassicLine(id: "zp-31-5", n: 5, orig: "若壬戌、丁未、戊甲、乙卯，雜氣正官，透干會支，最為貴格，而壬財丁印，二者相合，仍以孤官無輔論，所以不上七品。", baihua: "若是壬戌、丁未、戊申、乙卯四柱，雜氣正官，透干會支，最為貴格，可壬水財與丁火印兩者相合，仍以孤官無輔來論，所以上不了七品。", note: "底本日柱作「戊甲」，「甲」是天干不能居日支，當為「戊申」之訛。"),
                ClassicLine(id: "zp-31-6", n: 6, orig: "若財印不以兩用，則單用印不若單用財，以印能護官，亦能洩官，而財生官也。若化官為印而透財，則又為甚秀，大貴之格也。如金狀元命，乙卯、丁亥、丁未、庚戌，此並用財印，無傷官而不雜煞，所謂去其忌而存其喜者也。", baihua: "若是財印不能兩用，單用印就不如單用財，因為印能護官、也能洩官，而財能生官。若是化官為印又透財，就更為清秀，是大貴之格。比如金狀元命：乙卯、丁亥、丁未、庚戌，這是並用財印，沒有傷官、也不雜七煞，就是所謂去其所忌、存其所喜。", note: ""),
                ClassicLine(id: "zp-31-7", n: 7, orig: "然而遇傷在於佩印，混煞貴乎取清。", baihua: "然而遇到傷官要用印來佩，混雜七煞要用取清來貴。", note: ""),
                ClassicLine(id: "zp-31-8", n: 8, orig: "如宣參國命，己卯、辛未、壬寅、辛亥，未中己官透干用清，支會水局，兩辛解之，是遇傷而佩印也。李參政命，庚寅、乙酉、甲子、戊辰，甲用酉官，庚金混雜，乙以合之，合煞留官，是雜煞而取清也。", baihua: "比如宣參國命：己卯、辛未、壬寅、辛亥，未中己土官星透干取清，地支會成水局，兩個辛金解開了它，這是遇傷而佩印。又如李參政命：庚寅、乙酉、甲子、戊辰，甲日主用酉金正官，庚金七煞混雜，乙木與庚相合，合煞留官，這是雜煞而取清。", note: "底本「支會水局」，「水」為「木」之訛，亥卯未所會正是木局。"),
                ClassicLine(id: "zp-31-9", n: 9, orig: "至於官格透傷用印者，又忌見財，以財能去印，未能生官，而適以護傷故也。", baihua: "至於官格透傷用印的，又忌見財，因為財能去印、卻不能生官，反而恰好護住了傷官。", note: ""),
                ClassicLine(id: "zp-31-10", n: 10, orig: "然亦有逢財而反大貴者，如范太傅命，丁丑、壬寅、己巳、丙寅，支具巳丑，會金傷官，丙丁解之，透壬豈非破格？卻不知丙丁並透，用一而足，以丁合壬而財去，以丙制傷而官清，無情而愈有情。此正造化之妙，變幻無窮，焉得不貴？", baihua: "然而也有逢財反而大貴的，比如范太傅命：丁丑、壬寅、己巳、丙寅，地支巳丑會金為傷官，丙丁火解開了它，透出壬水豈不是破格？卻不知丙丁並透，用一個就夠了：以丁合壬、財就去了，以丙制傷、官就清了，無情反而愈發有情。這正是造化之妙、變幻無窮，怎麼能不貴？", note: ""),
                ClassicLine(id: "zp-31-11", n: 11, orig: "至若地支刑沖，會合可解，已見前篇，不必再述，而以後諸格，亦不談及矣。", baihua: "至於地支刑沖、會合可以化解，前面已經見過，不必再說；以後諸格，也不再談及了。", note: ""),
            ]),
            ClassicChapter(id: "zp-32", no: "三十二", title: "論正官取運", status: "included", source: "《子平真詮》三十二·論正官取運", lines: [
                ClassicLine(id: "zp-32-1", n: 1, orig: "取運之道，一八字則有一八字這論，其理甚精，其法甚活，只可大略言之。變化在人，不可泥也。", baihua: "取運的道理，一個八字就有一套論法，道理很精、方法很活，只能大略說說。變化在人，不可拘泥。", note: ""),
                ClassicLine(id: "zp-32-2", n: 2, orig: "如正官取運，即以正官所統之格分而配之。正官而用財印，身稍輕則取助身，官稍輕則助官。", baihua: "比如正官取運，就按正官所統的格局分而配之。正官而用財印，身稍輕就取助身，官稍輕就助官。", note: ""),
                ClassicLine(id: "zp-32-3", n: 3, orig: "若官露而不可逢合，不可雜煞，不可重官。與地支刑沖，不問所就何局，皆不利也。", baihua: "若是官星露出，就不可逢合、不可雜煞、不可重官。至於地支刑沖，不問所成的是什麼局，都不利。", note: ""),
                ClassicLine(id: "zp-32-4", n: 4, orig: "正官用財，運喜印受身旺之地，切忌食傷。若身旺而財輕官弱，即仍取財官運可也。", baihua: "正官用財，行運喜歡印來受身、身旺的地方，最忌食傷。若是身旺而財輕官弱，就仍取財官運也可以。", note: ""),
                ClassicLine(id: "zp-32-5", n: 5, orig: "正官佩印，運喜財鄉，傷食反吉。", baihua: "正官佩印，行運喜歡財鄉，傷食反而吉利。", note: ""),
                ClassicLine(id: "zp-32-6", n: 6, orig: "若官重身輕而佩印，則身旺為宜，不必財運也。", baihua: "若是官重身輕而佩印，就以身旺為宜，不必走財運。", note: ""),
                ClassicLine(id: "zp-32-7", n: 7, orig: "正官帶傷食而用印制，運喜官旺印旺之鄉，財運切忌。若印綬疊出，財運亦無害矣。", baihua: "正官帶傷食而用印來制，行運喜歡官旺印旺的地方，財運最忌。若是印綬疊出，財運也無害了。", note: ""),
                ClassicLine(id: "zp-32-8", n: 8, orig: "正官而帶煞，傷食反為不礙。其命中用劫合煞，則財運可行，傷食可行，身旺，印綬亦可行，只不過復露七煞。若命用傷官合煞，則傷食與財俱可行，而不宜逢印矣。", baihua: "正官而帶煞，傷食反而不礙事。其中用劫財合煞的，財運可行、傷食可行，身旺時印綬也可行，只不過又露出七煞。若是用傷官合煞的，傷食與財都可行，而不宜逢印。", note: ""),
                ClassicLine(id: "zp-32-9", n: 9, orig: "此皆大略言之，其八字各有議論。運中每遇一字，各有研究，隨時取用，不可言形。凡格皆然，不獨正官也。", baihua: "以上都是大略說說，每個八字各有議論。行運中每遇到一個字，各有講究，隨時取用，不可言說其形狀。凡是格局都這樣，不獨正官。", note: ""),
            ]),
            ClassicChapter(id: "zp-33", no: "三十三", title: "論財", status: "included", source: "《子平真詮》三十三·論財", lines: [
                ClassicLine(id: "zp-33-1", n: 1, orig: "財為我克，使用之物也，以能生官，所以為美。為財帛，為妻妾，為才能，為驛馬，皆財類也。", baihua: "財是我所克、供我使用的東西，因為能生官，所以為美。作財帛、作妻妾、作才能、作驛馬，都是財的類別。", note: ""),
                ClassicLine(id: "zp-33-2", n: 2, orig: "財喜根深，不宜太露，然透一位以清用，格所最喜，不為之露。即非月令用神，若寅透乙、卯透甲之類，一亦不為過，太多則露矣。", baihua: "財喜歡根深，不宜太露；然而透出一位來清純取用，是格局最喜歡的，不算太露。即使不是月令用神，像寅透乙、卯透甲之類，一個也不算過多，太多就露了。", note: ""),
                ClassicLine(id: "zp-33-3", n: 3, orig: "然而財旺生官，露亦不忌，蓋露不忌，蓋露以防劫，生官則劫退，譬如府庫錢糧，有官守護，即使露白，誰敢劫之？", baihua: "然而財旺生官，露出來也不忌，因為露出來也不怕被劫，生官就能使劫退去，好比府庫的錢糧有官守護，即使露白，誰敢來劫？", note: "底本「露亦不忌，蓋露不忌，蓋露以防劫」，「蓋露不忌」四字重出，當為傳抄衍文，今照錄不改。"),
                ClassicLine(id: "zp-33-4", n: 4, orig: "如葛參政命，壬申、壬子、戊午、乙卯，豈非財露？唯其生官，所以不忌也。", baihua: "比如葛參政命：壬申、壬子、戊午、乙卯，豈不是財露？只因它生官，所以不忌。", note: ""),
                ClassicLine(id: "zp-33-5", n: 5, orig: "財格之貴局不一，有財旺生官者，身強而不透傷官，不混七煞，貴格也。有財用食生者，身強而不露官，略帶一位比劫，益覺有情，如壬寅、壬寅、庚辰、辛巳，楊待郎之命是也。透官身弱，則格壞矣。", baihua: "財格的貴局不止一種：有財旺生官的，身強而不透傷官、不混七煞，是貴格。有財用食生的，身強而不露官，略帶一位比劫，更覺有情，比如壬寅、壬寅、庚辰、辛巳，楊侍郎的命就是。透官而身弱，格局就壞了。", note: "底本「楊待郎」，「待」為「侍」之訛。"),
                ClassicLine(id: "zp-33-6", n: 6, orig: "有財格佩印者，蓋孤財不貴，佩印幫身，即印取貴。如乙未、甲申、丙申、庚寅，曾參政之命是也，然財印宜相併，如乙未、己卯、庚寅、辛巳，乙與己兩不相能，即有好處，小富而已。", baihua: "有財格佩印的，因為孤財不貴，佩印來幫身，就是印取貴。比如乙未、甲申、丙申、庚寅，曾參政的命就是；然而財印應當相併，比如乙未、己卯、庚寅、辛巳，乙與己兩不相能，即使有好處，也不過小富罷了。", note: ""),
                ClassicLine(id: "zp-33-7", n: 7, orig: "有用食而兼用印者，食與印兩不相礙，或有暗官而去食護官，皆貴格也。如吳榜眼命，庚戌、戊子、戊子、丙辰，庚與丙隔兩戊而不相剋，是食與印不相礙也。如平江伯命，壬辰、乙巳、癸巳、辛酉，雖食印相剋，而欲存巳戊官，是去食護官也。", baihua: "有用食而兼用印的，食與印兩不相礙，或者有暗官而去食護官，都是貴格。比如吳榜眼命：庚戌、戊子、戊子、丙辰，庚與丙隔兩個戊而不相剋，這是食與印不相礙。又如平江伯命：壬辰、乙巳、癸巳、辛酉，雖然食印相剋，卻要存巳中戊土官星，這是去食護官。", note: ""),
                ClassicLine(id: "zp-33-8", n: 8, orig: "反是則減福矣。", baihua: "反過來就減福了。", note: ""),
                ClassicLine(id: "zp-33-9", n: 9, orig: "有財用傷官者，財不甚旺而比強，輅露一位傷官以化之，如甲子、辛未、辛酉、壬辰，甲透未庫，逢辛為劫，壬以化劫生財，汪學士命是也。", baihua: "有財用傷官的，財不太旺而比劫強，露出一位傷官來化解它，比如甲子、辛未、辛酉、壬辰，甲木透出未庫，逢辛金為劫，壬水化劫生財，汪學士的命就是。", note: ""),
                ClassicLine(id: "zp-33-10", n: 10, orig: "財旺無劫而透傷，反為不利，蓋傷官本非美物，財輕透劫，不得己而用之。旺而露傷，何苦用彼？徒使財遇傷而死生官之具，安望富貴乎？", baihua: "財旺而無劫卻透傷官，反而不利，因為傷官本來不是美物，財輕透劫，不得已才用它。財旺而露傷，何苦用它？徒使財遇傷而死、失了生官的工具，還指望什麼富貴呢？", note: ""),
                ClassicLine(id: "zp-33-11", n: 11, orig: "有財帶七煞者，或合煞存財，或制煞生財，皆貴格也，如毛狀元命，乙酉、庚辰、甲午、戊辰，合煞存財也；李御史命，庚辰、戊子、戊寅、甲寅，制煞生財也。", baihua: "有財帶七煞的，或者合煞存財、或者制煞生財，都是貴格，比如毛狀元命：乙酉、庚辰、甲午、戊辰，是合煞存財；李御史命：庚辰、戊子、戊寅、甲寅，是制煞生財。", note: ""),
                ClassicLine(id: "zp-33-12", n: 12, orig: "有財用煞印者，黨煞為忌，印以化之，格成富局，若冬土逢之亦貴格。如趙待郎命，乙丑、丁亥、乙亥，化煞而即以解凍，又不露財以雜其印，所以貴也。若財用煞印而印獨，財煞並透，非特不貴，亦不富也。", baihua: "有財用煞印的，黨煞為忌，印來化它，格局就成富局，若是冬土逢了它也是貴格。比如趙侍郎命：乙丑、丁亥、乙亥，化煞的同時解凍，又不露財來雜亂它的印，所以貴。若是財用煞印而印獨、財煞並透，不但不貴，也不富。", note: "底本「趙待郎」，「待」為「侍」之訛。"),
                ClassicLine(id: "zp-33-13", n: 13, orig: "至於壬生午月，癸生巳月，單透財而亦貴，又月令有暗官也。如丙寅、癸巳、癸未、壬戌，林尚書命是也。", baihua: "至於壬日主生在午月、癸日主生在巳月，單透財也貴，因為月令裡有暗官。比如丙寅、癸巳、癸未、壬戌，林尚書的命就是。", note: ""),
                ClassicLine(id: "zp-33-14", n: 14, orig: "又壬生巳月，單透財而亦貴，以其透丙藏戊，棄煞就財，美者存在贈者棄也。如丙辰、癸巳、壬戌、壬寅，王太僕命是也。", baihua: "又如壬日主生在巳月，單透財也貴，因為它透丙藏戊、棄煞就財，美好的留存、可憎的拋棄。比如丙辰、癸巳、壬戌、壬寅，王太僕的命就是。", note: "底本「美者存在贈者棄也」，「存在贈者棄」當作「存而憎者棄」。"),
                ClassicLine(id: "zp-33-15", n: 15, orig: "至於劫刃太重，棄財就煞，如一尚書命，丙辰、丙申、丙午、壬辰，此變之又變者也。", baihua: "至於劫刃太重，棄財就煞，比如一位尚書命：丙辰、丙申、丙午、壬辰，這是變了又變的情形。", note: ""),
            ]),
            ClassicChapter(id: "zp-34", no: "三十四", title: "論財取運", status: "included", source: "《子平真詮》三十四·論財取運", lines: [
                ClassicLine(id: "zp-34-1", n: 1, orig: "財格取運，即以財格所就之局，分而配之。", baihua: "財格取運，就按財格所成的局分而配之。", note: ""),
                ClassicLine(id: "zp-34-2", n: 2, orig: "其財旺生官者，運喜身旺印緩，不利七煞傷官；若生官而後透印，傷官之地，不甚有害。", baihua: "其中財旺生官的，行運喜歡身旺印綬，不利七煞傷官；若是生官而後透印，傷官的地方，不太有害。", note: "底本「運喜身旺印緩」，「緩」為「綬」之訛，當作「印綬」。"),
                ClassicLine(id: "zp-34-3", n: 3, orig: "至於生官而帶食破局，則運喜印綬，而逢煞反吉矣。", baihua: "至於生官而帶食破局的，行運喜歡印綬，逢煞反而吉利。", note: ""),
                ClassicLine(id: "zp-34-4", n: 4, orig: "財用食生，財食重而身輕，則喜助身；財食輕而身重，則仍行財食。煞運不忌，官印反晦矣。", baihua: "財用食生，財食重而身輕，就喜歡助身；財食輕而身重，就仍行財食。煞運不忌，官印反而晦暗。", note: ""),
                ClassicLine(id: "zp-34-5", n: 5, orig: "財格佩印，運喜官鄉，身弱逢之，最喜印旺。財用食印，財輕則喜財食，身輕則喜比印，官運有礙，煞反不忌也。財帶傷官，財運則亨，煞運不利，運行官印，未見其美矣。財帶七煞，不論合煞制煞，運喜食傷身旺之方。", baihua: "財格佩印，行運喜歡官鄉，身弱逢了它，最喜歡印旺。財用食印，財輕就喜歡財食，身輕就喜歡比印，官運有礙，煞反而不忌。財帶傷官，財運就亨通，煞運不利，行運逢官印，也未見其美。財帶七煞，不論合煞制煞，行運喜歡食傷身旺的地方。", note: ""),
                ClassicLine(id: "zp-34-6", n: 6, orig: "財用煞印，印旺最宜，逢財必忌。傷食之方，亦任意矣。", baihua: "財用煞印，印旺最合宜，逢財必定忌。傷食的地方，也任意行之。", note: ""),
            ]),
            ClassicChapter(id: "zp-35", no: "三十五", title: "論印綬", status: "included", source: "《子平真詮》三十五·論印綬", lines: [
                ClassicLine(id: "zp-35-1", n: 1, orig: "印綬喜其生身，正偏同為美格，故財與印不分偏正，同為一格而論之。印綬之格局亦不一，有印而透官者，正官不獨取其生印，而即可以為用，與用煞者不同。故身旺印強，不愁太過，只要官星清純，如丙寅、戊戌、辛酉、戊子，張參政之命是也。", baihua: "印綬喜歡生身，正印偏印同為美格，所以財與印不分偏正，同作一格來論。印綬的格局也不止一種：有印而透官的，正官不獨取它生印，而且即可以為用，與用煞的不同。所以身旺印強，不愁太過，只要官星清純，比如丙寅、戊戌、辛酉、戊子，張參政的命就是。", note: ""),
                ClassicLine(id: "zp-35-2", n: 2, orig: "然亦有帶傷食而貴者，則如朱尚書命，丙戌、戊戌、辛未、壬辰，壬為戊制，不傷官也。又如臨淮侯命，乙亥、己卯、丁酉、壬寅，己為乙制，己不礙官也。", baihua: "然而也有帶傷食而貴的，比如朱尚書命：丙戌、戊戌、辛未、壬辰，壬水被戊土制住，不傷官星。又如臨淮侯命：乙亥、己卯、丁酉、壬寅，己土被乙木制住，己土不礙官星。", note: ""),
                ClassicLine(id: "zp-35-3", n: 3, orig: "有印而用傷食者，身強印旺，恐其太過，洩身以為秀氣。如戊戌、乙卯、丙午、乙亥，李狀元命也，若印淺身輕，而用層層傷食，則寒貧之局矣。", baihua: "有印而用傷食的，身強印旺，恐怕它太過，洩身以為秀氣。比如戊戌、乙卯、丙午、乙亥，李狀元的命；若是印淺身輕，卻用層層傷食，就是寒貧之局了。", note: ""),
                ClassicLine(id: "zp-35-4", n: 4, orig: "有用偏官者，偏官本非美物，藉其生印，不得已而用之。故必身重印輕，或身輕印重，有所不足，始為有性。如茅狀元命，己巳、癸酉、癸未、庚申，此身輕印重也。馬參政命，壬寅、戊申、壬辰、壬寅，此身重印輕也。", baihua: "有用偏官的，偏官本來不是美物，藉它生印，不得已才用它。所以必須身重印輕、或身輕印重，有所不足，才開始有情。比如茅狀元命：己巳、癸酉、癸未、庚申，這是身輕印重。馬參政命：壬寅、戊申、壬辰、壬寅，這是身重印輕。", note: "底本「始為有性」，「性」當為「情」之訛，今照錄不改。"),
                ClassicLine(id: "zp-35-5", n: 5, orig: "若身印並重而用七煞，非孤則貧矣。", baihua: "若是身印並重而用七煞，不是孤獨就是貧窮。", note: ""),
                ClassicLine(id: "zp-35-6", n: 6, orig: "有用煞而兼帶傷食者，則用煞而有制，生身而有洩，不論身旺印重，皆為貴格。", baihua: "有用煞而兼帶傷食的，用煞而有制、生身而有洩，不論身旺印重，都是貴格。", note: ""),
                ClassicLine(id: "zp-35-7", n: 7, orig: "有印多而用財者，印重身強，透財以抑太過，權而用之，只要根深，無防財破。如辛酉、丙申、壬申、辛亥，汪侍郎命是也。若印輕財重，又無劫財以救，則為貪財破印，貧賤之局也。即或印重財輕而兼露傷食，財與食相生，輕而不輕，即可就富，亦不貴矣。", baihua: "有印多而用財的，印重身強，透財來抑其太過，權宜而用，只要根深，就不怕財破印。比如辛酉、丙申、壬申、辛亥，汪侍郎的命就是。若是印輕財重，又沒有劫財來救，就是貪財破印、貧賤之局。即使印重財輕而兼露傷食，財與食相生，輕而不輕，也可以就富，但不貴了。", note: ""),
                ClassicLine(id: "zp-35-8", n: 8, orig: "然亦有帶食而貴者，何也？如庚寅、乙酉、癸亥、丙辰，此牛監薄命，乙合庚而不生癸，所以為貴，若合財存食，又可類推矣。如己未、甲戌、辛未、癸已，此合財存食之貴也。", baihua: "然而也有帶食而貴的，是為什麼呢？比如庚寅、乙酉、癸亥、丙辰，這是牛監簿命，乙木合庚金而不生癸水，所以為貴；若是合財存食，又可以類推了。比如己未、甲戌、辛未、癸巳，這是合財存食之貴。", note: "底本作「牛監薄命」，「薄」疑為「簿」之訛，今照錄不改；又作「癸已」，「已」疑為「巳」之訛，今照錄不改。"),
                ClassicLine(id: "zp-35-9", n: 9, orig: "又有印而兼透官煞者，或合煞，或有制，皆為貴格。如辛亥、庚子、甲辰、乙亥，此合煞留官也；壬子、癸卯、丙子、己亥、此官煞有制也。", baihua: "又有印而兼透官煞的，或者合煞、或者有制，都是貴格。比如辛亥、庚子、甲辰、乙亥，這是合煞留官；壬子、癸卯、丙子、己亥，這是官煞有制。", note: ""),
                ClassicLine(id: "zp-35-10", n: 10, orig: "至於化印為劫；棄之以就財官，如趙知府命，丙午、庚寅、丙午、癸已，則變之又變者矣。更有印透七煞，而劫財以存煞印，亦有貴格，如庚戌、戊子、甲戌、乙亥是也。然此格畢竟難看，宜細詳之。", baihua: "至於化印為劫、棄了印去就財官，比如趙知府命：丙午、庚寅、丙午、癸巳，就是變了又變的情形。更有印透七煞、而劫財來存煞印的，也有貴格，比如庚戌、戊子、甲戌、乙亥就是。然而這個格畢竟難看，應當細細詳究。", note: "底本作「癸已」，「已」疑為「巳」之訛，今照錄不改。"),
            ]),
            ClassicChapter(id: "zp-36", no: "三十六", title: "論印綬取運", status: "included", source: "《子平真詮》三十六·論印綬取運", lines: [
                ClassicLine(id: "zp-36-1", n: 1, orig: "印格取運，即以印格所成之局，分而配之。", baihua: "印格取運，就按印格所成的局分而配之。", note: ""),
                ClassicLine(id: "zp-36-2", n: 2, orig: "其印綬用官者，官露印重，財運反吉，傷食之方，亦為最利。若用官而帶傷食，運喜官旺印綬之鄉，傷食為害，逢煞不忌矣。", baihua: "其中印綬用官的，官露印重，財運反而吉利，傷食的地方，也最為有利。若是用官而帶傷食，行運喜歡官旺印綬的地方，傷食為害，逢煞不忌。", note: ""),
                ClassicLine(id: "zp-36-3", n: 3, orig: "印綬而用傷食，財運反吉，傷食亦利，若行官運，反見其災，煞運則反能為福矣。印用七煞，運喜傷食，身旺之方，亦為美地，一見財鄉，其凶立至。", baihua: "印綬而用傷食，財運反而吉利，傷食也利，若是行官運，反而見災，煞運反而能為福。印用七煞，行運喜歡傷食、身旺的地方，也為美地，一旦見到財鄉，凶禍立刻就到。", note: ""),
                ClassicLine(id: "zp-36-4", n: 4, orig: "若用煞而兼帶傷食，運喜身旺印綬之方，傷食亦美，逢官遇財，皆不吉也。印綬遇財，運喜劫地，官印亦亨，財鄉則忌。", baihua: "若是用煞而兼帶傷食，行運喜歡身旺印綬的地方，傷食也美，逢官遇財，都不吉利。印綬遇財，行運喜歡劫地，官印也亨通，財鄉就忌。", note: ""),
                ClassicLine(id: "zp-36-5", n: 5, orig: "印格而官煞競透，運喜食神傷官，印旺身旺，行之亦利。若再透官煞，行財運，立見其災矣。印用食傷，印輕者亦不利見財也。", baihua: "印格而官煞競透，行運喜歡食神傷官，印旺身旺，行了也利。若是再透官煞、行財運，立刻見災。印用食傷，印輕的也不利見財。", note: ""),
            ]),
            ClassicChapter(id: "zp-37", no: "三十七", title: "論食神", status: "included", source: "《子平真詮》三十七·論食神", lines: [
                ClassicLine(id: "zp-37-1", n: 1, orig: "食神本屬洩氣，以其能生正財，所以喜之。故食神生財，美格也。", baihua: "食神本屬洩氣，因為它能生正財，所以喜歡它。所以食神生財，是美格。", note: ""),
                ClassicLine(id: "zp-37-2", n: 2, orig: "財要有根，不必偏正疊出，如身強食旺而財透，大貴之格。若丁未、癸卯、癸亥、癸丑，梁丞相之命是也；己未、壬申、戊子、庚申，謝閣老之命是也。藏食露傷，主人性剛如丁亥、癸卯、癸卯、甲寅，沈路分命是也。偏正疊出，富貴不巨，職甲午、丁卯、癸丑、丙辰，龔知縣命是也。", baihua: "財要有根，不必偏正疊出，比如身強食旺而財透，是大貴之格。若丁未、癸卯、癸亥、癸丑，梁丞相的命就是；己未、壬申、戊子、庚申，謝閣老的命就是。藏食露傷，主人性剛，比如丁亥、癸卯、癸卯、甲寅，沈路分的命就是。偏正疊出，富貴不大，比如職甲午、丁卯、癸丑、丙辰，龔知縣的命就是。", note: ""),
                ClassicLine(id: "zp-37-3", n: 3, orig: "夏木用財，火炎土燥，貴多就武。如己未、已巳、甲寅、丙寅，黃都督之命是也。", baihua: "夏木用財，火炎土燥，貴多就武。比如己未、已巳、甲寅、丙寅，黃都督的命就是。", note: ""),
                ClassicLine(id: "zp-37-4", n: 4, orig: "若不用財而就煞印，最為威權顯赫。如辛卯、辛卯、癸酉、己未，常國公命是也。若無印綬而單露偏官，只要無財，亦為貴格，如戊戌、壬戌、丙子、戊戌，胡會元命是也。若金水食神而用煞，貴而且秀，職丁亥、壬子、辛巳、丁酉，舒尚書命是也。", baihua: "若是不用財而就煞印，最為威權顯赫。比如辛卯、辛卯、癸酉、己未，常國公的命就是。若是沒有印綬而單露偏官，只要沒有財，也是貴格，比如戊戌、壬戌、丙子、戊戌，胡會元的命就是。若是金水食神而用煞，貴而且秀，比如職丁亥、壬子、辛巳、丁酉，舒尚書的命就是。", note: ""),
                ClassicLine(id: "zp-37-5", n: 5, orig: "至於食神忌印，夏火太炎而木焦，透印不礙，如丙午、癸巳、甲子、丙寅，錢參政命是也。食神忌官，金水不忌，即金水傷官可見官之謂。", baihua: "至於食神忌印，夏火太炎而木焦，透印不礙，比如丙午、癸巳、甲子、丙寅，錢參政的命就是。食神忌官，金水不忌，就是金水傷官可見官的意思。", note: ""),
                ClassicLine(id: "zp-37-6", n: 6, orig: "至若單用食神，作食神有氣，有財運則富，無財運則貧。更有印來奪食，透財以解，亦有富貴，須就其全局之勢而斷之。至於食神而官煞競出，亦可成局，但不甚貴耳。更有食神合煞存財，最為貴格。", baihua: "至於單用食神，作食神有氣，有財運就富、無財運就貧。更有印來奪食，透財來解，也有富貴，須就全局之勢來斷。至於食神而官煞競出，也可以成局，只是不太貴罷了。更有食神合煞存財，最為貴格。", note: ""),
                ClassicLine(id: "zp-37-7", n: 7, orig: "至若食神透煞。本忌見財，而財先煞後，食以間之，而財不能黨煞，亦可就貴。如劉提臺命，癸酉、辛酉、己卯、乙亥是也。", baihua: "至於食神透煞，本來忌見財，可財先煞後、食神隔在中間，財不能黨煞，也可以就貴。比如劉提臺命：癸酉、辛酉、己卯、乙亥就是。", note: ""),
                ClassicLine(id: "zp-37-8", n: 8, orig: "其餘變化，不能盡述，類而推之可也。", baihua: "其餘變化，不能盡述，類推就是了。", note: ""),
            ]),
            ClassicChapter(id: "zp-38", no: "三十八", title: "論食神取運", status: "included", source: "《子平真詮》三十八·論食神取運", lines: [
                ClassicLine(id: "zp-38-1", n: 1, orig: "食神取運，即以食神所成之局，分而配之。", baihua: "食神取運，就按食神所成的局分而配之。", note: ""),
                ClassicLine(id: "zp-38-2", n: 2, orig: "食神生財，財重食輕，則行財食，財食重則喜幫身。官煞之方，俱為不美。", baihua: "食神生財，財重食輕就走財食運，財食重就喜歡幫身。官煞的地方，都不美。", note: ""),
                ClassicLine(id: "zp-38-3", n: 3, orig: "食用煞印，運喜印旺，切忌財鄉。身旺，食傷亦為福運，行官行煞，亦為吉也。", baihua: "食用煞印，行運喜歡印旺，最忌財鄉。身旺時，食傷也為福運，行官行煞，也為吉。", note: ""),
                ClassicLine(id: "zp-38-4", n: 4, orig: "食傷帶煞，喜行印綬，身旺，食傷亦為美運，財則最忌。若食太重而煞輕，印運最利，逢財反吉矣。", baihua: "食傷帶煞，喜歡走印綬，身旺時食傷也為美運，財最忌。若是食太重而煞輕，印運最利，逢財反而吉利。", note: ""),
                ClassicLine(id: "zp-38-5", n: 5, orig: "食神太旺而帶印，運最利財，食傷亦吉，印則最忌，官煞皆不吉也。若食神帶印，透財以解，運喜財旺，食傷亦吉，印與官煞皆忌也。", baihua: "食神太旺而帶印，行運最利財，食傷也吉，印最忌，官煞都不吉。若是食神帶印、透財來解，行運喜歡財旺，食傷也吉，印與官煞都忌。", note: ""),
            ]),
            ClassicChapter(id: "zp-39", no: "三十九", title: "論偏官", status: "included", source: "《子平真詮》三十九·論偏官", lines: [
                ClassicLine(id: "zp-39-1", n: 1, orig: "煞以攻身，似非美物，百大貴之格，多存七煞。蓋控制得宜，煞為我用，如大英雄大豪傑，似難駕馭，而處之有方，則驚天動地之功，忽焉而就。此王侯將相所以多存七煞也。", baihua: "煞以攻身，好像不是美物，可極大貴的格局，多半存著七煞。因為控制得宜，煞就為我所用，就像大英雄大豪傑，好像難以駕馭，可處置得法，驚天動地的功業忽然就成就了。這就是王侯將相多半存七煞的原因。", note: ""),
                ClassicLine(id: "zp-39-2", n: 2, orig: "七煞之格局亦不一：煞用食制者，上也，煞旺食強而身健，極為貴格。如乙亥、乙酉、乙卯、丁丑，極等之貴也。", baihua: "七煞的格局也不止一種：煞用食制的最好，煞旺食強而身健，是極貴之格。比如乙亥、乙酉、乙卯、丁丑，就是極等之貴。", note: ""),
                ClassicLine(id: "zp-39-3", n: 3, orig: "煞用食制，不要露財透印，以財能轉食生煞，而印能去食護煞也。然而財先食後，財生煞而食以制之，或印先食後，食太旺而印制，則格成大貴。", baihua: "煞用食制，不要露財透印，因為財能轉食生煞、印能去食護煞。然而財先食後，財生煞而食來制它；或者印先食後，食太旺而印來制它，格局就成大貴。", note: ""),
                ClassicLine(id: "zp-39-4", n: 4, orig: "如脫脫丞相命，壬辰、甲胡、丙戌、戊戌，辰中暗煞，壬以透之，戊坐四支，食太重而透甲印，以損太過，豈非貴格？", baihua: "比如脫脫丞相命：壬辰、甲辰、丙戌、戊戌，辰中暗煞，壬水透出來，戊土坐四支，食太重而透甲木印星來損其太過，豈不是貴格？", note: "底本月柱作「甲胡」，據下文「辰中暗煞」當為甲辰之訛，今照錄不改。"),
                ClassicLine(id: "zp-39-5", n: 5, orig: "若煞強食洩而印露，則破局矣。", baihua: "若是煞強食洩而印露出來，格局就破了。", note: ""),
                ClassicLine(id: "zp-39-6", n: 6, orig: "有七煞用印者，印能護煞，本非所宜，而印有情，便為貴格。如何參政命，丙寅、戊戌、壬戌、辛丑，戊與辛同通月令，是煞印有情也。", baihua: "有七煞用印的，印能護煞，本來不是合宜的，可印有情，就成貴格。比如何參政命：丙寅、戊戌、壬戌、辛丑，戊土與辛金同通月令，這是煞印有情。", note: ""),
                ClassicLine(id: "zp-39-7", n: 7, orig: "亦有煞重身輕，用食則身不能當，不若轉而就印，雖不通根月令，亦為無情而有情。格亦許貴，但不大耳。有煞而用財者，財以黨煞，本非所喜，而或食被制，不能伏煞，而財以去印存食，便為貴格。", baihua: "也有煞重身輕，用食身不能當，不如轉而就印，雖然不通根月令，也是無情而有情。格局也許貴，但不大。還有煞而用財的，財來黨煞，本來不是喜歡的，可食被制、不能伏煞，而財來去印存食，就成貴格。", note: ""),
                ClassicLine(id: "zp-39-8", n: 8, orig: "如周丞相命，戊戌、甲子，丁未、庚戌，戊被制不能伏煞，時透庚財，即以清食者，生不足之煞。生煞即以制煞，兩得其用，尤為大貴。", baihua: "比如周丞相命：戊戌、甲子、丁未、庚戌，戊土被制不能伏煞，時上透庚金財星，就以清食的、來生不足的煞。生煞就是制煞，兩得其用，尤其大貴。", note: ""),
                ClassicLine(id: "zp-39-9", n: 9, orig: "又有身重煞輕，煞又化印，用神不清，而借財以清格，亦為貴格。如甲申、乙亥、丙戌、庚寅，劉運使命是也。", baihua: "又有身重煞輕，煞又化印，用神不清，而借財來清格，也是貴格。比如甲申、乙亥、丙戌、庚寅，劉運使的命就是。", note: ""),
                ClassicLine(id: "zp-39-10", n: 10, orig: "更有雜氣七煞，干頭不透財以清用，亦可取貴。", baihua: "更有雜氣七煞，干頭不透財來清用，也可以取貴。", note: ""),
                ClassicLine(id: "zp-39-11", n: 11, orig: "有煞而雜官者，或去官，或去煞，取清則貴。如嶽統制命，癸卯、丁巳、庚寅、庚辰，去官留煞也。", baihua: "有煞而雜官的，或者去官、或者去煞，取清就貴。比如嶽統制命：癸卯、丁巳、庚寅、庚辰，是去官留煞。", note: ""),
                ClassicLine(id: "zp-39-12", n: 12, orig: "夫官為貴氣，去官何如去煞？豈知月令偏官，煞為用而官非用，各從其重。若官格雜煞而去官留煞，不能如是之清矣。如沈郎中命，丙子、甲午、辛亥、辛卯，子沖午而克煞，是去煞留官也。", baihua: "官是貴氣，去官怎麼比得上去煞？豈知月令是偏官，煞為用而官不是用，各從其重。若是官格雜煞而去官留煞，就不能像這樣清純了。比如沈郎中命：丙子、甲午、辛亥、辛卯，子沖午而克煞，是去煞留官。", note: ""),
                ClassicLine(id: "zp-39-13", n: 13, orig: "有煞無食制而用印當者，如戊辰、甲寅、戊寅、戊午、趙員外命是也。至書有制煞不可太過之說，雖亦有理，然運行財印，亦能發福，不可執一也，乃若棄命從煞，則於外格詳之。", baihua: "有煞無食制而用印來當的，比如戊辰、甲寅、戊寅、戊午，趙員外的命就是。至於書上說制煞不可太過，雖然也有道理，但行運逢財印，也能發福，不可執著一端；至於棄命從煞，就在外格裡詳說。", note: ""),
            ]),
            ClassicChapter(id: "zp-40", no: "四十", title: "論偏官取運", status: "included", source: "《子平真詮》四十·論偏官取運", lines: [
                ClassicLine(id: "zp-40-1", n: 1, orig: "取運偏官取運，即以偏官所成之局分而配之。", baihua: "取運偏官取運，就按偏官所成的局分而配之。", note: ""),
                ClassicLine(id: "zp-40-2", n: 2, orig: "煞用食制，煞重食輕則助食，煞輕食重則助煞，煞食均而日主根輕則助身。忌正官之混雜，畏印綬之奪食。煞用印綬，不利財鄉，傷官為美，印綬身旺，俱為福地。", baihua: "煞用食制，煞重食輕就助食，煞輕食重就助煞，煞食均衡而日主根輕就助身。忌正官混雜，怕印綬奪食。煞用印綬，不利財鄉，傷官為美，印綬身旺，都是福地。", note: ""),
                ClassicLine(id: "zp-40-3", n: 3, orig: "七煞用財，其以財而去印存食者，不利劫財，傷食皆吉，喜財怕印，透煞亦順。其以財而助煞不及者，財已足，則喜食印與幫身；財未足，則喜財旺而露煞。煞帶正官，不論去官留煞，去煞留官，身輕則喜助身，食輕則喜助食。莫去取清之物，無傷制煞之神。", baihua: "七煞用財，其中以財來去印存食的，不利劫財，傷食都吉，喜歡財怕印，透煞也順。其中以財來助煞不及的，財已足就喜歡食印與幫身，財未足就喜歡財旺而露煞。煞帶正官，不論去官留煞、去煞留官，身輕就喜歡助身，食輕就喜歡助食。不要去掉取清的東西，不要傷了制煞的神。", note: ""),
                ClassicLine(id: "zp-40-4", n: 4, orig: "煞無食制而用刃當煞，煞輕刃重則喜助煞，刃輕煞重，則宜制伏，無食可奪，印運何傷？七煞既純，雜官不利。", baihua: "煞無食制而用刃來當煞，煞輕刃重就喜歡助煞，刃輕煞重就宜制伏，沒有食可奪，印運又有什麼妨害？七煞既然純粹，雜官就不利。", note: ""),
            ]),
            ClassicChapter(id: "zp-41", no: "四十一", title: "論傷官", status: "included", source: "《子平真詮》四十一·論傷官", lines: [
                ClassicLine(id: "zp-41-1", n: 1, orig: "傷官雖非吉神，實為秀氣，故文人學士，多於傷官格內得之。而夏木見水，冬金見火，則又為秀之尤秀者也。", baihua: "傷官雖然不是吉神，實際上卻是秀氣，所以文人學士多半在傷官格裡得之。夏天的木見水、冬天的金見火，又是秀中之最秀。", note: ""),
                ClassicLine(id: "zp-41-2", n: 2, orig: "其中格局比他格多，變化尤多，在查其氣候，量其強弱，審其喜忌，觀其純雜，微之又微，不可執也。", baihua: "其中格局比別的格多，變化尤其多，要察其氣候、量其強弱、審其喜忌、觀其純雜，細微之又細微，不可執著。", note: ""),
                ClassicLine(id: "zp-41-3", n: 3, orig: "故有傷官用財者，蓋傷不利於民，所以為凶，傷官生財，則以傷官為生官之具，轉凶為吉，故最利。只要身強而有根，便為貴格，如壬午、己酉、戊午、庚申，史春芳命也。", baihua: "所以有傷官用財的：傷官不利於官，所以為凶；傷官生財，就以傷官為生官的工具，轉凶為吉，所以最利。只要身強而有根，就是貴格，比如壬午、己酉、戊午、庚申，史春芳的命。", note: "底本「蓋傷不利於民」，「民」為「官」之訛，當作「蓋傷不利於官」。"),
                ClassicLine(id: "zp-41-4", n: 4, orig: "至於化傷為財，大為秀氣，如羅狀元命，甲子、乙亥、辛未、戊子，干頭之甲，通根於亥，然又會未成局，化水為木，化之生財，尤為有情，所以傷官生財，冬金不貴，以凍水不能生木。若乃化木，不待於生，安得不為殿元乎？至於財傷有情，與化傷為財者，其秀氣不相上下，如秦龍圖命，己卯、丁丑、丙寅、庚寅，已與庚同根月令是也。", baihua: "至於化傷為財，大為秀氣，比如羅狀元命：甲子、乙亥、辛未、戊子，干頭的甲木通根於亥，又會未成局，化水為木、化了生財，尤其有情；所以傷官生財，冬金不貴，因為凍水不能生木。若是化木，不必等待先生，怎麼能不中殿元呢？至於財傷有情，與化傷為財的，秀氣不相上下，比如秦龍圖命：己卯、丁丑、丙寅、庚寅，己土與庚金同根月令就是。", note: ""),
                ClassicLine(id: "zp-41-5", n: 5, orig: "有傷官佩印者，印能制傷，所以為貴，反要傷官旺，身稍弱，始為秀氣。如孛羅平章命，壬申、丙午、申午、壬申、傷官旺，印根深，身又弱，又是夏木逢潤，其秀百倍，所以一品之貴。然印旺極深，不必多見，偏正疊出，反為不秀，故傷輕身重而印綬多見，貧窮之格也。", baihua: "有傷官佩印的，印能制傷，所以為貴，反而要傷官旺、身稍弱，才開始有秀氣。比如孛羅平章命：壬申、丙午、申午、壬申，傷官旺、印根深、身又弱，又是夏木逢潤，秀氣加倍，所以一品之貴。然而印旺到極深，不必多見，偏正疊出，反而不秀，所以傷輕身重而印綬多見，是貧窮之格。", note: "底本日柱作「申午」，「申」當為「甲」之訛，今照錄不改。"),
                ClassicLine(id: "zp-41-6", n: 6, orig: "有傷官兼用財印者，財印相剋，本不併用，只要干頭兩清而不相礙；又必生財者，財太旺而帶印，佩印者印太重而帶財，調停中和，遂為貴格。", baihua: "有傷官兼用財印的，財印相剋，本來不併用，只要干頭兩清而不相礙；又必須生財的，財太旺而帶印，佩印的印太重而帶財，調停中和，就成貴格。", note: ""),
                ClassicLine(id: "zp-41-7", n: 7, orig: "如丁酉、己酉、戊子、壬子，財太重而帶印，而丁與壬隔以戊已，兩不礙，且金水多而覺寒，得火融和，都統制命也。又如壬戌、己酉、戊午、丁巳，印太重而隔戊已，而丁與壬不相礙，一丞相命也。反是則財印不併用而不秀矣。", baihua: "比如丁酉、己酉、戊子、壬子，財太重而帶印，丁火與壬水隔著戊己，兩不相礙，而且金水多而覺寒，得火融和，是都統制的命。又如壬戌、己酉、戊午、丁巳，印太重而隔著戊己，丁火與壬水不相礙，是一位丞相的命。反過來財印不併用就不秀了。", note: ""),
                ClassicLine(id: "zp-41-8", n: 8, orig: "有傷官用煞印者，傷多身弱，賴煞生印以邦身而制傷，如己未、丙子、庚子、丙子，蔡貴妃也。煞因傷而有制，兩得其宜，只要無財，便為貴格，如壬寅、丁未、丙寅，夏閣老命是也。", baihua: "有傷官用煞印的，傷多身弱，靠煞生印來幫身而制傷，比如己未、丙子、庚子、丙子，蔡貴妃的命。煞因傷而有制，兩得其宜，只要沒有財，就是貴格，比如壬寅、丁未、丙寅，夏閣老的命。", note: "此造只存三柱，時柱已佚。"),
                ClassicLine(id: "zp-41-9", n: 9, orig: "有傷官用官者，他格不用，金水獨宜，然要財印為輔，不可傷官並透。如戊申、甲子、庚午、丁丑，藏癸露丁，戊甲為輔，官又得祿，所以為丞相之格。若孤官無輔，或官傷並透，則發福不大矣。", baihua: "有傷官用官的，別的格不用，唯獨金水適宜，然而要財印為輔，不可傷官並透。比如戊申、甲子、庚午、丁丑，藏癸露丁，戊甲為輔，官又得祿，所以是丞相之格。若是孤官無輔、或者官傷並透，發福就不大了。", note: ""),
                ClassicLine(id: "zp-41-10", n: 10, orig: "若冬金用官，而又化傷為財，則尤為極秀極貴。如丙申、己亥、辛未、己亥，鄭丞相命是也。然亦有非金水而見官，何也？化傷為財，傷非其傷，作財旺生官而不作傷官見官，如甲子、壬申、己亥、辛未，章丞相命也。", baihua: "若是冬金用官，又化傷為財，尤其極秀極貴。比如丙申、己亥、辛未、己亥，鄭丞相的命就是。然而也有不是金水而見官的，是為什麼呢？化傷為財，傷不是它的傷，作財旺生官而不作傷官見官，比如甲子、壬申、己亥、辛未，章丞相的命。", note: ""),
                ClassicLine(id: "zp-41-11", n: 11, orig: "至於傷官而官煞並透，只要干頭取清，金水得之亦清，不然則空結構而已。", baihua: "至於傷官而官煞並透，只要干頭取清，金水得了也清，不然就只是空結構罷了。", note: ""),
            ]),
            ClassicChapter(id: "zp-42", no: "四十二", title: "論傷官取運", status: "included", source: "《子平真詮》四十二·論傷官取運", lines: [
                ClassicLine(id: "zp-42-1", n: 1, orig: "傷官取運，即以傷官所成之局，分而配之。", baihua: "傷官取運，就按傷官所成的局分而配之。", note: ""),
                ClassicLine(id: "zp-42-2", n: 2, orig: "傷官用財，財旺身輕，則利印比；身強財淺，則喜財運，傷官亦宜。傷官佩印，運行官煞為宜，印運亦吉，傷食不礙，財地則凶。", baihua: "傷官用財，財旺身輕就利印比；身強財淺就喜歡財運，傷官也宜。傷官佩印，行運以官煞為宜，印運也吉，傷食不礙，財地就凶。", note: ""),
                ClassicLine(id: "zp-42-3", n: 3, orig: "傷官而兼用財印，其財多而帶印者，運喜助印，印多而帶財者，運喜助財。傷官而用煞印，印運最利，傷食亦亨，雜官非吉，逢財即危。", baihua: "傷官而兼用財印，其中財多而帶印的，行運喜歡助印；印多而帶財的，行運喜歡助財。傷官而用煞印，印運最利，傷食也亨通，雜官不吉，逢財就危險。", note: ""),
                ClassicLine(id: "zp-42-4", n: 4, orig: "傷官帶煞，喜印忌財，然傷重煞輕，運喜印而財亦吉。惟七根重，則運喜傷食，印綬身旺亦吉，而逢財為凶矣。", baihua: "傷官帶煞，喜歡印忌財，然而傷重煞輕，行運喜歡印、財也吉。唯獨七煞根重的，行運喜歡傷食，印綬身旺也吉，而逢財就凶了。", note: "底本「惟七根重」，「七」下當脫「煞」字，今照錄不改。"),
                ClassicLine(id: "zp-42-5", n: 5, orig: "傷官用官，運喜財印，不利食傷，若局中官露而財印兩旺，則比劫傷官，未紿非吉矣。", baihua: "傷官用官，行運喜歡財印，不利食傷，若是局中官露而財印兩旺，比劫傷官，也未必不是吉。", note: ""),
            ]),
            ClassicChapter(id: "zp-43", no: "四十三", title: "論陽刃", status: "included", source: "《子平真詮》四十三·論陽刃", lines: [
                ClassicLine(id: "zp-43-1", n: 1, orig: "陽刃者，劫我正財之神，乃正財之七煞也。祿前一位，惟五陽有之，故為旭刃。不曰劫而曰刃，劫之甚也。刃宜伏制，官煞皆宜，財印相隨，尤為貴顯。", baihua: "陽刃是劫我正財的神，就是正財的七煞。祿前一位，只有五陽干才有，所以叫陽刃。不說劫而說刃，是劫到了極處。刃宜伏制，官煞都宜，財印相隨，尤其貴顯。", note: "底本「故為旭刃」，「旭」當為「陽」之訛，今照錄不改。"),
                ClassicLine(id: "zp-43-2", n: 2, orig: "夫正官而財印相隨美矣，七煞得之，夫乃甚乎？豈知他格以煞能傷身，故喜制伏，忌財印；陽刃用之，則賴以制刃，不怕傷身，故反喜財印，忌制伏也。", baihua: "正官而財印相隨固然美，七煞得了財印，難道就更甚嗎？豈知別的格以煞能傷身，所以喜歡制伏、忌財印；陽刃用煞，就靠它來制刃，不怕傷身，所以反而喜歡財印、忌制伏。", note: ""),
                ClassicLine(id: "zp-43-3", n: 3, orig: "陽刃用官，透刃不慮；陽刃露煞，透刃無成。蓋官能制刃，透而不為害；刃能合煞，則有何功？如丙生午月，透壬制刃，而又露丁，丁與壬合，則七煞有貪合忘克之意，如何制刃？故無功也。", baihua: "陽刃用官，透出羊刃也不慮；陽刃露煞，透出羊刃就無成。因為官能制刃，透出來不為害；刃能合煞，又有什麼功？比如丙日主生在午月，透壬水制刃，又露出丁火，丁與壬相合，七煞就有了貪合忘克的意思，還怎麼制刃？所以無功。", note: ""),
                ClassicLine(id: "zp-43-4", n: 4, orig: "然同是官煞制刃，而格亦有高低，如官煞露而根深，其貴也大；官煞藏而不露，或露而根淺，其貴也小。若己酉、丙子、壬寅、丙午，官透有力，旺財生之，丞相命也。又辛酉、甲午、丙申、壬辰，透煞根淺，財印助之，亦丞相命也。", baihua: "然而同是官煞制刃，格局也有高低，比如官煞露出而根深，貴就大；官煞藏而不露、或者露出而根淺，貴就小。若己酉、丙子、壬寅、丙午，官星透出有力、旺財生它，是丞相命。又如辛酉、甲午、丙申、壬辰，透煞根淺、財印助它，也是丞相命。", note: ""),
                ClassicLine(id: "zp-43-5", n: 5, orig: "然亦有官煞制刃帶傷食而貴者，何也？或是印護，或是煞太重而裁損之，官煞輕而取清之，如穆同知命，甲午、癸酉、庚寅、戊寅，癸水傷寅午之官，而戊以合之，所謂印護也。如賈平章命，甲寅、庚午、戊申、甲寅，煞兩透而根太重，食以制之，所謂裁損也。如丙戌、丁酉、庚申、壬午，官煞競出，而壬合丁官，煞純而不雜。況陽刃之格，利於留煞，所謂取清也。", baihua: "然而也有官煞制刃帶傷食而貴的，是為什麼呢？或是印來護，或是煞太重而裁損它，官煞輕而取清它，比如穆同知命：甲午、癸酉、庚寅、戊寅，癸水傷了寅午的官，而戊土與癸相合，這就是所謂印護。又如賈平章命：甲寅、庚午、戊申、甲寅，煞兩透而根太重，食神來制它，這就是所謂裁損。又如丙戌、丁酉、庚申、壬午，官煞競出，而壬水合丁火官星，煞純而不雜。何況陽刃之格，利於留煞，這就是所謂取清。", note: ""),
                ClassicLine(id: "zp-43-6", n: 6, orig: "其於丙生午月，內藏己土，可以克水，尤宜帶財佩印，若戊生午月，干透丙火，支會火乙，則化刃為印，或官或煞，透則去刃存印其格愈清。倘或財煞並透露，則犯去印存煞之忌，不作生煞制煞之例，富貴兩空矣。", baihua: "至於丙日主生在午月，內藏己土，可以克水，尤其宜帶財佩印；若是戊日主生在午月，干透丙火，支會火局，就化刃為印，或官或煞，透出來就去刃存印，格局愈發清純。倘若財煞並透，就犯了去印存煞的忌，不作生煞制煞的例子，富貴兩空了。", note: "底本「支會火乙」，「乙」字疑為「局」之訛，今照錄不改。"),
                ClassicLine(id: "zp-43-7", n: 7, orig: "更若陽刃用財，格所不喜，然財根深而用傷食，以轉刃生財，雖不比建祿月劫，可以取貴，亦可就富。不然，則刃與財相搏，不成局矣。", baihua: "更若陽刃用財，本是格局不喜歡的，然而財根深而用傷食，來轉刃生財，雖然比不上建祿月劫，可以取貴，也可以就富。不然，刃與財相搏，就不成局了。", note: ""),
            ]),
            ClassicChapter(id: "zp-44", no: "四十四", title: "論陽刃取運", status: "included", source: "《子平真詮》四十四·論陽刃取運", lines: [
                ClassicLine(id: "zp-44-1", n: 1, orig: "陽刃用官，則運喜助官，然命中官星根深，則印綬比劫之方，反為美運，但不喜傷食合官耳。陽刃用煞，煞不甚旺，則運喜助煞；煞若太重，則運喜身旺印綬，傷食亦不為忌。陽刃而官煞並出，不論去官去煞，運喜制伏，身旺亦利，財地官鄉反為不吉也。", baihua: "陽刃用官，行運喜歡助官，然而命中官星根深，印綬比劫的地方，反而為美運，只是不喜歡傷食合官罷了。陽刃用煞，煞不太旺，行運喜歡助煞；煞若太重，行運喜歡身旺印綬，傷食也不為忌。陽刃而官煞並出，不論去官去煞，行運喜歡制伏，身旺也利，財地官鄉反而為不吉。", note: ""),
            ]),
            ClassicChapter(id: "zp-45", no: "四十五", title: "論建祿月劫", status: "included", source: "《子平真詮》四十五·論建祿月劫", lines: [
                ClassicLine(id: "zp-45-1", n: 1, orig: "建祿者，月建逢祿堂也，祿即是劫。或以祿堂透出，即可依以用者，非也。故建祿與月劫，可同一格，不必加分，皆以透干支，別取財官煞食為用。祿格用官，干頭透出為奇，又要財印相隨，不可孤官無輔。", baihua: "建祿是月建逢祿堂，祿就是劫。有人以為祿堂透出來，就可以依它取用，是不對的。所以建祿與月劫，可以同一格，不必再分，都是以透干支，另取財官煞食為用。祿格用官，干頭透出來為奇，又要財印相隨，不可孤官無輔。", note: ""),
                ClassicLine(id: "zp-45-2", n: 2, orig: "有用官而印護者，如庚戌、戊子、癸酉、癸亥，金丞相命是也。有用官而財助者，如丁酉、丙午、丁巳、壬寅，李知府命是也。有官而兼帶財印者，所謂身強值三奇，尤為貴氣。三奇者，財官印也，只要以官隔之，使財印兩不相傷，其格便大，如庚午、戊子、癸卯、丁巳，王少師命是也。", baihua: "有用官而印護的，比如庚戌、戊子、癸酉、癸亥，金丞相的命就是。有用官而財助的，比如丁酉、丙午、丁巳、壬寅，李知府的命就是。有官而兼帶財印的，就是所謂身強值三奇，尤其貴氣。三奇就是財官印，只要以官隔開它，使財印兩不相傷，格局就大，比如庚午、戊子、癸卯、丁巳，王少師的命就是。", note: ""),
                ClassicLine(id: "zp-45-3", n: 3, orig: "祿劫用財，須帶食傷，蓋月令為劫而以財作用，二財相剋，必以傷食化之，始可轉劫生財，如甲子、丙子、癸丑、壬辰，張都統命是也。至於化劫為財，與化劫為生，尤為秀氣。", baihua: "祿劫用財，須帶食傷，因為月令是劫而以財為作用，兩個財相剋，必須以傷食化它，才可以轉劫生財，比如甲子、丙子、癸丑、壬辰，張都統的命就是。至於化劫為財，與化劫為生，尤其秀氣。", note: ""),
                ClassicLine(id: "zp-45-4", n: 4, orig: "如己未、已巳、丁未、辛丑，丑與巳會，即以劫財之火為金局之財，安得不為大貴？所謂化劫為財也。如高尚書命，庚子、甲申、庚子、甲申，即以劫財之金，化為生財之水，所謂化劫為生也。", baihua: "比如己未、已巳、丁未、辛丑，丑與巳相會，就以劫財的火為金局的財，怎麼能不大貴？這就是所謂化劫為財。又如高尚書命：庚子、甲申、庚子、甲申，就以劫財的金，化為生財的水，這就是所謂化劫為生。", note: ""),
                ClassicLine(id: "zp-45-5", n: 5, orig: "祿劫用煞，必須制伏臺，如婁參政命，丁巳、壬子、癸卯、己未，壬合丁財以去其黨煞，卯未會局以制伏是也。至用煞而又財，本為不美，然能去煞存財，又成貴格。戊辰、癸亥、壬午、丙午，合煞存財，袁內閣命是也。", baihua: "祿劫用煞，必須制伏，比如婁參政命：丁巳、壬子、癸卯、己未，壬水合丁火財來去它黨煞，卯未會局來制伏就是。至於用煞而又帶財，本來不美，然而能去煞存財，又成貴格。戊辰、癸亥、壬午、丙午，合煞存財，袁內閣的命就是。", note: "底本「必須制伏臺」，「臺」字疑衍，今照錄不改。"),
                ClassicLine(id: "zp-45-6", n: 6, orig: "其祿劫之格，無財官而用傷食，洩其太過，亦為秀氣。唯春木秋金，用之則貴，蓋木逢火則明，金生水則靈。如張狀元命，甲子、丙寅、甲子、丙寅，木火通明也；又癸卯、庚申、庚子、庚辰，金水相涵也。", baihua: "至於祿劫之格，沒有財官而用傷食，洩其太過，也是秀氣。唯獨春木秋金，用了就貴，因為木逢火就明、金生水就靈。比如張狀元命：甲子、丙寅、甲子、丙寅，是木火通明；又如癸卯、庚申、庚子、庚辰，是金水相涵。", note: ""),
                ClassicLine(id: "zp-45-7", n: 7, orig: "更有祿劫而官煞競出，必取清方為貴格。如一平章命，辛丑、庚寅、甲辰、乙亥、合煞留這也；如辛亥、庚寫、甲申、丙寅，制煞留官也。倘或兩官競出，亦須制伏，所謂爭正官不可無傷也。", baihua: "更有祿劫而官煞競出，必須取清才為貴格。比如一位平章命：辛丑、庚寅、甲辰、乙亥，是合煞留官；又如辛亥、庚寅、甲申、丙寅，是制煞留官。倘若兩官競出，也須制伏，這就是所謂爭正官不可無傷。", note: "底本「合煞留這」，「這」當為「官」之訛；月支作「寫」，當為「寅」之訛，今照錄不改。"),
                ClassicLine(id: "zp-45-8", n: 8, orig: "若夫用官而孤官無輔，格局更小，難於取貴，若透傷食便不破格。然亦有官傷並透而貴者，何也？如己酉、乙亥、壬戌、庚子，庚合乙而去傷存官，王總兵命也。", baihua: "若是用官而孤官無輔，格局更小，難以取貴，若是透傷食就不破格。然而也有官傷並透而貴的，是為什麼呢？比如己酉、乙亥、壬戌、庚子，庚金合乙木而去傷存官，王總兵的命。", note: ""),
                ClassicLine(id: "zp-45-9", n: 9, orig: "用財而不透傷食，便難於發端，然干頭透一位而不雜，地支根多，亦可取富，但不貴耳。用官煞重而無制伏，運行制伏，亦可發財，但不可官煞太重，致令身危也。", baihua: "用財而不透傷食，就難於發端，然而干頭透一位而不雜、地支根多，也可以取富，只是不貴罷了。用官煞重而無制伏，行運制伏，也可以發財，但不可官煞太重，以致令身危險。", note: ""),
            ]),
            ClassicChapter(id: "zp-46", no: "四十六", title: "論建祿月劫取運", status: "included", source: "《子平真詮》四十六·論建祿月劫取運", lines: [
                ClassicLine(id: "zp-46-1", n: 1, orig: "祿劫取運，即以祿劫所成之局，分而配之。祿劫用官，印護者喜財，怕官星之逢合，畏七煞這相乘。傷食不能為害，劫比未即為凶。", baihua: "祿劫取運，就按祿劫所成的局分而配之。祿劫用官，印護的喜歡財，怕官星逢合，畏七煞相乘。傷食不能為害，劫比也不即為凶。", note: "底本「畏七煞這相乘」，「這」當為「之」之訛，今照錄不改。"),
                ClassicLine(id: "zp-46-2", n: 2, orig: "財生喜印，宜官星之植根，畏傷食之相侮，逢財愈見其功，雜煞豈能無礙？祿劫用財而帶傷食，財食重則喜印綬，而不書法比肩；財食輕則宜助財，而不喜印比。逢煞無傷，遇官非福。", baihua: "財生喜歡印，宜官星植根，畏傷食相侮，逢財愈見其功，雜煞怎麼能無礙？祿劫用財而帶傷食，財食重就喜歡印綬，而不書法比肩；財食輕就宜助財，而不喜歡印比。逢煞無傷，遇官不是福。", note: "底本「不書法比肩」四字有訛，今照錄不改。"),
                ClassicLine(id: "zp-46-3", n: 3, orig: "祿劫用煞食制，食重煞輕，則運宜助煞；食輕煞重，則運喜助食。若用煞而帶財，命中合煞存財，則傷食為宜，財運不忌，透官無慮，身旺亦亨。若命中合財存煞，而用食制，煞輕則助煞，食輕則助食則已。", baihua: "祿劫用煞食制，食重煞輕，行運宜助煞；食輕煞重，行運喜歡助食。若是用煞而帶財，命中合煞存財，傷食為宜，財運不忌，透官無慮，身旺也亨通。若是命中合財存煞、而用食制，煞輕就助煞，食輕就助食就是了。", note: ""),
                ClassicLine(id: "zp-46-4", n: 4, orig: "祿劫而用傷食，財運最宜，煞亦不忌，行印非吉，透官不美。若命中傷食太重，則財運固利，而印亦不忌矣。祿劫而官煞並出，不論合煞留官，存官制煞，運喜傷食，比肩亦宜，印綬未為良圖，財官亦非福運。", baihua: "祿劫而用傷食，財運最宜，煞也不忌，行印不吉，透官不美。若是命中傷食太重，財運固然利，印也不忌了。祿劫而官煞並出，不論合煞留官、存官制煞，行運喜歡傷食，比肩也宜，印綬不是良圖，財官也不是福運。", note: ""),
            ]),
            ClassicChapter(id: "zp-47", no: "四十七", title: "論雜格", status: "included", source: "《子平真詮》四十七·論雜格", lines: [
                ClassicLine(id: "zp-47-1", n: 1, orig: "雜格者，月令無用，以外格而用之，其格甚多，故謂之雜。大約要干頭無官無煞，方成格，如有官煞，則自有官煞為用，列外格矣。若透財尚可取格，然財根深，或財透兩位，則亦以財為重，不取外格也。", baihua: "雜格是月令無用、以外格取用的，格很多，所以叫雜。大約要干頭無官無煞，才成格，若是有官煞，自然有官煞為用，就列入外格了。若是透財還可以取格，然而財根深、或者財透兩位，也以財為重，不取外格。", note: ""),
                ClassicLine(id: "zp-47-2", n: 2, orig: "試以諸格論之，有取五行一方秀氣者，取甲乙全亥卯未、寅卯辰，又生春月之類，本是一派劫財，以五行各得其全體，所以成格，喜印露而體純。如癸亥、乙卯、乙未、壬午，吳相公命是也。運亦喜印綬比劫之鄉，財食亦吉，官煞則忌矣。", baihua: "試拿諸格來論：有取五行一方秀氣的，取甲乙全亥卯未、寅卯辰，又生在春月之類，本是一派劫財，因為五行各得其全體，所以成格，喜歡印露而體純。比如癸亥、乙卯、乙未、壬午，吳相公的命就是。行運也喜歡印綬比劫的地方，財食也吉，官煞就忌了。", note: ""),
                ClassicLine(id: "zp-47-3", n: 3, orig: "有從化取格者，要化出之物，得時乘令，四支局全。如丁壬化木，地支全亥卯未、寅卯辰，而又生於春月，方為大貴。否則，亥未之月亦是木地，次等之貴，如甲戌、丁卯、壬寅、甲辰，一品貴格命也。運喜所化之物，與所化之印綬，財傷亦可，不利官煞。", baihua: "有從化取格的，要化出來的東西，得時乘令、四支局全。比如丁壬化木，地支全亥卯未、寅卯辰，又生在春月，才為大貴。不然，亥未之月也是木地，是次等之貴，比如甲戌、丁卯、壬寅、甲辰，是一品貴格命。行運喜歡所化之物、與所化的印綬，財傷也可以，不利官煞。", note: ""),
                ClassicLine(id: "zp-47-4", n: 4, orig: "有倒沖成格者，以四柱列財官而對面以沖之，要支中字多，方沖得動。譬如以弱主邀強官，主不眾則賓不從。如戊午、戊午、戊午、戊午，是沖子財也；甲寅、庚午、丙午、甲午，是沖子官也。運忌填實，餘俱可行。", baihua: "有倒沖成格的，以四柱列財官而對面沖它，要支中字多，才沖得動。譬如以弱主邀強官，主不多賓就不從。比如戊午、戊午、戊午、戊午，是沖子財；甲寅、庚午、丙午、甲午，是沖子官。行運忌填實，其餘都可以走。", note: ""),
                ClassicLine(id: "zp-47-5", n: 5, orig: "有朝陽成格者，戊去朝丙，辛日得官，以丙戊同祿於巳，即以引汲之意。要干頭無木火，方成其格，蓋有火則無待於朝，有木財觸戊之怒，而不為我朝。如戊辰、辛酉、戊子，張知縣命是也。運喜土金水，木運平平，火則忌矣。", baihua: "有朝陽成格的，戊去朝丙，辛日得官，因為丙戊同祿於巳，就是引汲的意思。要干頭無木火，才成此格，因為有火就無待於朝，有木財觸戊之怒，而不為我朝。比如戊辰、辛酉、戊子，張知縣的命就是。行運喜歡土金水，木運平平，火就忌了。", note: "此造只存三柱，時柱已佚。"),
                ClassicLine(id: "zp-47-6", n: 6, orig: "有合祿成格者，命無官星，借干支以合之。戊日庚申，以庚合乙，因其主而得其偶。如己未、戊辰、戊辰、庚申，蜀王命是也。癸日庚申，以申合巳，因其主而得其朋，如己酉、癸未、癸未、庚申，起丞相命是也。運亦忌填實，不利官煞，理會不宜以火克金，使彼受制而不能合，餘則吉矣。", baihua: "有合祿成格的，命無官星，借干支來合它。戊日庚申，以庚合乙，因為它主而得它偶。比如己未、戊辰、戊辰、庚申，蜀王的命就是。癸日庚申，以申合巳，因為它主而得它朋，比如己酉、癸未、癸未、庚申，某丞相的命就是。行運也忌填實，不利官煞，理會不宜以火克金，使它受制而不能合，其餘就吉了。", note: "底本「起丞相」，「起」當為姓氏之訛，今照錄不改。"),
                ClassicLine(id: "zp-47-7", n: 7, orig: "有棄命保財者，四柱皆財而身無氣，舍而從之，格成大貴。若透印則身賴印生而不從，有官煞則亦無從財兼從煞之理，其格不成。如庚申、乙酉、丙申、乙丑，王十萬命造也。運喜傷食財鄉，不宜身旺。", baihua: "有棄命從財的，四柱皆財而身無氣，捨了從它，格成大貴。若是透印，身就靠印生而不從；有官煞也沒有從財兼從煞的道理，格局不成。比如庚申、乙酉、丙申、乙丑，王十萬的命造。行運喜歡傷食財鄉，不宜身旺。", note: "底本作「棄命保財」，當作「棄命從財」。"),
                ClassicLine(id: "zp-47-8", n: 8, orig: "有棄命從煞者，四柱皆煞，而日主無根，舍而從之，格成大貴。若有傷食，則煞受制而不從，有印則印以化煞而不從。如乙酉、乙酉、乙酉、甲申，李侍郎命是也。運喜財官，不宜身旺，食傷則尤忌矣。", baihua: "有棄命從煞的，四柱皆煞，而日主無根，捨了從它，格成大貴。若是有傷食，煞受制而不從；有印，印就化煞而不從。比如乙酉、乙酉、乙酉、甲申，李侍郎的命就是。行運喜歡財官，不宜身旺，食傷尤其忌。", note: ""),
                ClassicLine(id: "zp-47-9", n: 9, orig: "有井攔成格者，庚金生三七月，方用此格。以申子辰沖寅午戌，財官印綬，合而沖之，若透丙丁，有巳午，以現有財官，而無待於沖，乃非井攔之格矣。如戊子、庚申、庚申、庚申，郭統制命也。運喜財，不利填實，餘亦吉也。", baihua: "有井欄成格的，庚金生在三七月，才用此格。以申子辰沖寅午戌，財官印綬，合而沖它，若是透丙丁、有巳午，因為現有財官、而無待於沖，就不是井欄之格了。比如戊子、庚申、庚申、庚申，郭統制的命。行運喜歡財，不利填實，其餘也吉。", note: ""),
                ClassicLine(id: "zp-47-10", n: 10, orig: "有刑合成格者，癸日甲寅時，寅刑巳而得財官，格與合祿相似，但合祿則喜以合之，而刑合則硬以致之也。命有庚申，則木被沖剋而不能刑；有戊已字，則現透官煞而無待於刑，非此格矣。如乙未、癸卯、癸卯、甲寅，十二節度使命是也。運忌填實，不利金鄉，餘則吉矣。", baihua: "有刑合成格的，癸日甲寅時，寅刑巳而得財官，格與合祿相似，但合祿喜歡以合它，而刑合是硬以致它。命中有庚申，木被沖剋而不能刑；有戊己字，現透官煞而無待於刑，就不是此格了。比如乙未、癸卯、癸卯、甲寅，十二節度使的命就是。行運忌填實，不利金鄉，其餘就吉了。", note: ""),
                ClassicLine(id: "zp-47-11", n: 11, orig: "有遙合成格者，巳與丑會，本同一局，丑多則會巳而辛丑處官，亦合祿之意也。如辛丑、辛丑、辛丑、庚寅，章統制命是也。若命是有子字，則丑與子合而不遙，有丙丁戊已，則辛癸之官煞已透，而無待於遙，另有取用，非此格矣。至於甲子遙已，轉輾求俁，似覺無情，此格可廢，因羅御史命，聊復存之。為甲申、甲戌、甲子、甲子，羅御史命是也。", baihua: "有遙合成格的，巳與丑會，本同一局，丑多就會巳而辛丑處官，也是合祿的意思。比如辛丑、辛丑、辛丑、庚寅，章統制的命就是。若是命中有子字，丑與子合而不遙；有丙丁戊己，辛癸的官煞已透、而無待於遙，另有取用，不是此格了。至於甲子遙巳，轉輾求合，好像無情，此格可廢，因為羅御史的命，姑且存它。為甲申、甲戌、甲子、甲子，羅御史的命就是。", note: "底本「辛丑處官」，文字有訛，今照錄不改。"),
                ClassicLine(id: "zp-47-12", n: 12, orig: "若夫拱祿、拱貴、趨乾、歸祿、夾戌、鼠貴、騎龍、日貴、日德、富祿、魁罡、食神時墓、兩干不雜、干支一氣、五行具足之類，一切無理之格，既置勿取。即古人格內，亦有成式，總之意為牽就，硬填人格，百無一是，徒誤後學而已。乃若天地雙飛，雖富貴亦有自有格，不全賴此。而亦能增重基格，即用神不甚有用，偶有依以為用，亦成美格。然而有用神不吉，即以為凶，不可執也。", baihua: "至於拱祿、拱貴、趨乾、歸祿、夾戌、鼠貴、騎龍、日貴、日德、富祿、魁罡、食神時墓、兩干不雜、干支一氣、五行具足之類，一切無理之格，既然置下就不要取。即使古人格裡也有成式，總的意思是牽就、硬填人格，百無一是，只誤後學罷了。至於天地雙飛，雖然富貴也有自己的格，不全靠它。而也能增重本格，即使是用神不太有用，偶爾依它為用，也成美格。然而有用神不吉，就以為凶，不可執著。", note: ""),
                ClassicLine(id: "zp-47-13", n: 13, orig: "其於傷官傷盡，謂是傷盡，不宜一見官，必盡力以傷之，使之無地容身，現行傷運，便能富貴，不知官有何罪，而惡之如此？況見官而傷，則以官非美物，而傷以制之，又何傷官之謂凶神，而見官之為禍百端乎？予用是術以歷試，但有貧賤，並無富貴，未輕信也，近亦見有大貴者，不知何故。然要之極賤者多，不得不觀其人物以衡之。", baihua: "至於傷官傷盡，說是傷盡，不宜一見官，必定盡力傷它，使它無地容身，現行傷運，就能富貴，不知官有什麼罪，要這樣厭惡它？何況見官而傷，就以官不是美物、而傷來制它，又何必說傷官是凶神、而見官是禍百端呢？我用這術歷試，只有貧賤、並無富貴，未曾輕信，近來也見有大貴的，不知是什麼緣故。然而終究極賤的多，不得不觀其人物來衡量。", note: ""),
            ]),
        ]),
    ]
}

struct ClassicsView: View {
    @State private var query = ""
    private var allLines: [(ClassicBook, ClassicChapter, ClassicLine)] {
        var out: [(ClassicBook, ClassicChapter, ClassicLine)] = []
        for b in ClassicsData.books {
            for c in b.chapters {
                for ln in c.lines {
                    out.append((b, c, ln))
                }
            }
        }
        return out
    }
    private var hits: [(ClassicBook, ClassicChapter, ClassicLine)] {
        if query.isEmpty { return [] }
        return allLines.filter { _, c, ln in
            ln.orig.contains(query) || ln.baihua.contains(query) || c.title.contains(query)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            KySearchBar(text: $query, placeholder: "搜原文或白话（如：提纲、用神、月令）")
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            List {
            if !query.isEmpty {
                Section("检索命中 \(hits.count) 句".scriptConverted) {
                    ForEach(hits, id: \.2.id) { b, c, ln in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ln.orig).font(.callout).foregroundStyle(Ky.ink)
                            Text("白话转述：".scriptConverted + ln.baihua.scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                            Text("\(b.title) · \(c.no) \(c.title) · \(c.source) 第 \(ln.n) 句".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
                        }
                    }
                    if hits.isEmpty {
                        KyEmptyState(icon: "magnifyingglass", title: "没有命中", message: "没有命中，换个词试试。")
                    }
                }
            }
            ForEach(ClassicsData.books) { b in
                Section(b.title + "（" + b.author + "）") {
                    Text(b.source.scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                    if !b.scopeNote.isEmpty { Text(b.scopeNote.scriptConverted).font(.caption).foregroundStyle(Ky.sub) }
                    ForEach(b.chapters) { c in
                        if c.status == "included" {
                            NavigationLink { ClassicChapterView(book: b, chapter: c) } label: {
                                Text((c.no + " · " + c.title + "（\(c.lines.count) 句）").scriptConverted).font(.subheadline).foregroundStyle(Ky.ink)
                            }
                        } else {
                            Text((c.no + " · " + c.title + "（未收录）").scriptConverted).font(.subheadline).foregroundStyle(Ky.sub)
                        }
                    }
                }
            }
            }
        }
        .navigationTitle("古籍检索".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ClassicChapterView: View {
    let book: ClassicBook
    let chapter: ClassicChapter
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(chapter.source.scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                ForEach(chapter.lines) { ln in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("原文 \(ln.n)：" + ln.orig).font(.callout).foregroundStyle(Ky.ink)
                        Text("白话转述：".scriptConverted + ln.baihua.scriptConverted).font(.callout).foregroundStyle(Ky.sub)
                        if !ln.note.isEmpty { Text("校勘：".scriptConverted + ln.note.scriptConverted).font(.caption).foregroundStyle(Ky.sub) }
                    }
                    Divider()
                }
                Text("白话为本系统自己的字面疏解，与原文严格区分，不得冒充原文。".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(book.title + " · " + chapter.no + " " + chapter.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 学堂（收拢入口，不新写课程，不做视频课、不做付费课）
struct AcademyView: View {
    var body: some View {
        List {
            Section("研习入口".scriptConverted) {
                NavigationLink { LibraryView() } label: { Text("图书馆 —— 100 条研习文本与典籍纲要，检索＋分类＋出处".scriptConverted).font(.subheadline).foregroundStyle(Ky.ink) }
                NavigationLink { ClassicsView() } label: { Text("古籍检索 —— 《滴天髓》《子平真诠》公有领域原文逐句对照＋检索".scriptConverted).font(.subheadline).foregroundStyle(Ky.ink) }
                NavigationLink { QuizView() } label: { Text("排盘口径自测 —— 44 题口径自测，答案由引擎现算复核".scriptConverted).font(.subheadline).foregroundStyle(Ky.ink) }
            }
            Section("依据与金标准（D3）".scriptConverted) {
                Text("每条断语、每个口径都以可复核的金标准为据：三方互校日柱 1900–2100、奇门 183 断言、紫微 14 例、堪舆 114 断言、户型 69 断言。不编造、无依据的断语不上线。".scriptConverted).font(.callout).foregroundStyle(Ky.ink)
            }
            Section("排盘口径收据行说明".scriptConverted) {
                Text("每张排盘都附收据行，写明本次排盘用的口径：真太阳时校正分钟数与经度、晚子时 sect=2（23:00–24:00 日柱不换、时干按次日日干推）、节气交节时刻、夏令时命中与处理、年份验证范围 1900–2100。收据行与引擎同式现算，口径有变即随盘更新。".scriptConverted).font(.callout).foregroundStyle(Ky.ink)
            }
        }
        .navigationTitle("学堂".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }
}
