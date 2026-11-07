import SwiftUI
// G11 古籍检索：数据与 Web app/classics.json 同源逐字对拍
// （由 tools/gen_g11_swift.py 生成，勿手改；白话为本系统自己的字面疏解，
// 与原文严格区分，白话不得冒充原文；未收录篇目标明“未收录”。）
struct ClassicLine: Identifiable { let id: String; let n: Int; let orig: String; let baihua: String; let note: String }
struct ClassicChapter: Identifiable { let id: String; let no: String; let title: String; let status: String; let source: String; let lines: [ClassicLine] }
struct ClassicBook: Identifiable { let id: String; let title: String; let author: String; let script: String; let source: String; let sourceURL: String; let scopeNote: String; let chapters: [ClassicChapter] }
enum ClassicsData {
    static let version = "G11-20261108"
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
        ClassicBook(id: "ziping", title: "子平真诠", author: "清·沈孝瞻", script: "traditional", source: "", sourceURL: "https://libokang.com/zh-hant/classics/bazi/%E5%AD%90%E5%B9%B3%E7%9C%9F%E8%A9%AE%E5%8E%9F%E6%96%87/", scopeNote: "本批入库一～十篇全文逐句（干支基础与用神总论）；十一～四十七篇篇目在位、状态未收录，留待后续批次。篇数说明：任务简报称 48 篇；本底本正文为一～四十七篇，凡例亦自述分列 47 篇，48 篇之说当为含附篇的别种计数，本批按底本实际 47 篇入库。底本讹字照录不改，校勘见各句 note。", chapters: [
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
            ClassicChapter(id: "zp-11", no: "十一", title: "論用神純雜", status: "not_included", source: "《子平真詮》十一·論用神純雜", lines: [
            ]),
            ClassicChapter(id: "zp-12", no: "十二", title: "論用神格局高低", status: "not_included", source: "《子平真詮》十二·論用神格局高低", lines: [
            ]),
            ClassicChapter(id: "zp-13", no: "十三", title: "論用神因成得敗因敗得成", status: "not_included", source: "《子平真詮》十三·論用神因成得敗因敗得成", lines: [
            ]),
            ClassicChapter(id: "zp-14", no: "十四", title: "論用神配氣候得失", status: "not_included", source: "《子平真詮》十四·論用神配氣候得失", lines: [
            ]),
            ClassicChapter(id: "zp-15", no: "十五", title: "論相神緊要", status: "not_included", source: "《子平真詮》十五·論相神緊要", lines: [
            ]),
            ClassicChapter(id: "zp-16", no: "十六", title: "論雜氣如何取用", status: "not_included", source: "《子平真詮》十六·論雜氣如何取用", lines: [
            ]),
            ClassicChapter(id: "zp-17", no: "十七", title: "論墓庫刑沖之說", status: "not_included", source: "《子平真詮》十七·論墓庫刑沖之說", lines: [
            ]),
            ClassicChapter(id: "zp-18", no: "十八", title: "論四吉神能破格", status: "not_included", source: "《子平真詮》十八·論四吉神能破格", lines: [
            ]),
            ClassicChapter(id: "zp-19", no: "十九", title: "論四凶神能成格", status: "not_included", source: "《子平真詮》十九·論四凶神能成格", lines: [
            ]),
            ClassicChapter(id: "zp-20", no: "二十", title: "論生克先後分吉凶", status: "not_included", source: "《子平真詮》二十·論生克先後分吉凶", lines: [
            ]),
            ClassicChapter(id: "zp-21", no: "二十一", title: "論星辰無關格局", status: "not_included", source: "《子平真詮》二十一·論星辰無關格局", lines: [
            ]),
            ClassicChapter(id: "zp-22", no: "二十二", title: "論外格用舍", status: "not_included", source: "《子平真詮》二十二·論外格用舍", lines: [
            ]),
            ClassicChapter(id: "zp-23", no: "二十三", title: "論宮分用神配六親", status: "not_included", source: "《子平真詮》二十三·論宮分用神配六親", lines: [
            ]),
            ClassicChapter(id: "zp-24", no: "二十四", title: "論妻子", status: "not_included", source: "《子平真詮》二十四·論妻子", lines: [
            ]),
            ClassicChapter(id: "zp-25", no: "二十五", title: "論行運", status: "not_included", source: "《子平真詮》二十五·論行運", lines: [
            ]),
            ClassicChapter(id: "zp-26", no: "二十六", title: "論行運成格變格", status: "not_included", source: "《子平真詮》二十六·論行運成格變格", lines: [
            ]),
            ClassicChapter(id: "zp-27", no: "二十七", title: "論喜忌干支有別", status: "not_included", source: "《子平真詮》二十七·論喜忌干支有別", lines: [
            ]),
            ClassicChapter(id: "zp-28", no: "二十八", title: "論支中喜忌逢運透清", status: "not_included", source: "《子平真詮》二十八·論支中喜忌逢運透清", lines: [
            ]),
            ClassicChapter(id: "zp-29", no: "二十九", title: "論時說拘泥格局", status: "not_included", source: "《子平真詮》二十九·論時說拘泥格局", lines: [
            ]),
            ClassicChapter(id: "zp-30", no: "三十", title: "論時說以訛傳訛", status: "not_included", source: "《子平真詮》三十·論時說以訛傳訛", lines: [
            ]),
            ClassicChapter(id: "zp-31", no: "三十一", title: "論正官", status: "not_included", source: "《子平真詮》三十一·論正官", lines: [
            ]),
            ClassicChapter(id: "zp-32", no: "三十二", title: "論正官取運", status: "not_included", source: "《子平真詮》三十二·論正官取運", lines: [
            ]),
            ClassicChapter(id: "zp-33", no: "三十三", title: "論財", status: "not_included", source: "《子平真詮》三十三·論財", lines: [
            ]),
            ClassicChapter(id: "zp-34", no: "三十四", title: "論財取運", status: "not_included", source: "《子平真詮》三十四·論財取運", lines: [
            ]),
            ClassicChapter(id: "zp-35", no: "三十五", title: "論印綬", status: "not_included", source: "《子平真詮》三十五·論印綬", lines: [
            ]),
            ClassicChapter(id: "zp-36", no: "三十六", title: "論印綬取運", status: "not_included", source: "《子平真詮》三十六·論印綬取運", lines: [
            ]),
            ClassicChapter(id: "zp-37", no: "三十七", title: "論食神", status: "not_included", source: "《子平真詮》三十七·論食神", lines: [
            ]),
            ClassicChapter(id: "zp-38", no: "三十八", title: "論食神取運", status: "not_included", source: "《子平真詮》三十八·論食神取運", lines: [
            ]),
            ClassicChapter(id: "zp-39", no: "三十九", title: "論偏官", status: "not_included", source: "《子平真詮》三十九·論偏官", lines: [
            ]),
            ClassicChapter(id: "zp-40", no: "四十", title: "論偏官取運", status: "not_included", source: "《子平真詮》四十·論偏官取運", lines: [
            ]),
            ClassicChapter(id: "zp-41", no: "四十一", title: "論傷官", status: "not_included", source: "《子平真詮》四十一·論傷官", lines: [
            ]),
            ClassicChapter(id: "zp-42", no: "四十二", title: "論傷官取運", status: "not_included", source: "《子平真詮》四十二·論傷官取運", lines: [
            ]),
            ClassicChapter(id: "zp-43", no: "四十三", title: "論陽刃", status: "not_included", source: "《子平真詮》四十三·論陽刃", lines: [
            ]),
            ClassicChapter(id: "zp-44", no: "四十四", title: "論陽刃取運", status: "not_included", source: "《子平真詮》四十四·論陽刃取運", lines: [
            ]),
            ClassicChapter(id: "zp-45", no: "四十五", title: "論建祿月劫", status: "not_included", source: "《子平真詮》四十五·論建祿月劫", lines: [
            ]),
            ClassicChapter(id: "zp-46", no: "四十六", title: "論建祿月劫取運", status: "not_included", source: "《子平真詮》四十六·論建祿月劫取運", lines: [
            ]),
            ClassicChapter(id: "zp-47", no: "四十七", title: "論雜格", status: "not_included", source: "《子平真詮》四十七·論雜格", lines: [
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
        List {
            if !query.isEmpty {
                Section("检索命中 \(hits.count) 句") {
                    ForEach(hits, id: \.2.id) { b, c, ln in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ln.orig).font(.callout).foregroundStyle(Ky.ink)
                            Text("白话转述：" + ln.baihua).font(.caption).foregroundStyle(Ky.sub)
                            Text("\(b.title) · \(c.no) \(c.title) · \(c.source) 第 \(ln.n) 句").font(.caption2).foregroundStyle(Ky.sub)
                        }
                    }
                    if hits.isEmpty { Text("没有命中，换个词试试。").font(.callout).foregroundStyle(Ky.sub) }
                }
            }
            ForEach(ClassicsData.books) { b in
                Section(b.title + "（" + b.author + "）") {
                    Text(b.source).font(.caption).foregroundStyle(Ky.sub)
                    if !b.scopeNote.isEmpty { Text(b.scopeNote).font(.caption).foregroundStyle(Ky.sub) }
                    ForEach(b.chapters) { c in
                        if c.status == "included" {
                            NavigationLink { ClassicChapterView(book: b, chapter: c) } label: {
                                Text(c.no + " · " + c.title + "（\(c.lines.count) 句）").font(.subheadline).foregroundStyle(Ky.ink)
                            }
                        } else {
                            Text(c.no + " · " + c.title + "（未收录）").font(.subheadline).foregroundStyle(Ky.sub)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜原文或白话（如：提纲、用神、月令）")
        .navigationTitle("古籍检索")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ClassicChapterView: View {
    let book: ClassicBook
    let chapter: ClassicChapter
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(chapter.source).font(.caption).foregroundStyle(Ky.sub)
                ForEach(chapter.lines) { ln in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("原文 \(ln.n)：" + ln.orig).font(.callout).foregroundStyle(Ky.ink)
                        Text("白话转述：" + ln.baihua).font(.callout).foregroundStyle(Ky.sub)
                        if !ln.note.isEmpty { Text("校勘：" + ln.note).font(.caption).foregroundStyle(Ky.sub) }
                    }
                    Divider()
                }
                Text("白话为本系统自己的字面疏解，与原文严格区分，不得冒充原文。").font(.caption2).foregroundStyle(Ky.sub)
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
            Section("研习入口") {
                NavigationLink { LibraryView() } label: { Text("图书馆 —— 100 条研习文本与典籍纲要，检索＋分类＋出处").font(.subheadline).foregroundStyle(Ky.ink) }
                NavigationLink { ClassicsView() } label: { Text("古籍检索 —— 《滴天髓》《子平真诠》公有领域原文逐句对照＋检索").font(.subheadline).foregroundStyle(Ky.ink) }
                NavigationLink { QuizView() } label: { Text("排盘口径自测 —— 44 题口径自测，答案由引擎现算复核").font(.subheadline).foregroundStyle(Ky.ink) }
            }
            Section("依据与金标准（D3）") {
                Text("每条断语、每个口径都以可复核的金标准为据：三方互校日柱 1900–2100、奇门 183 断言、紫微 14 例、堪舆 114 断言、户型 69 断言。不编造、无依据的断语不上线。").font(.callout).foregroundStyle(Ky.ink)
            }
            Section("排盘口径收据行说明") {
                Text("每张排盘都附收据行，写明本次排盘用的口径：真太阳时校正分钟数与经度、晚子时 sect=2（23:00–24:00 日柱不换、时干按次日日干推）、节气交节时刻、夏令时命中与处理、年份验证范围 1900–2100。收据行与引擎同式现算，口径有变即随盘更新。").font(.callout).foregroundStyle(Ky.ink)
            }
        }
        .navigationTitle("学堂")
        .navigationBarTitleDisplayMode(.inline)
    }
}
