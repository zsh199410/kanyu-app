import Foundation

/// Position diagrams for traditional terminology education only.
/// Coordinates describe an idealized illustration, never measurements of a person's photograph.
enum PhysiognomyGuideKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case hand
    case face

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hand: return "掌纹与掌部图例"
        case .face: return "面部宫位与三停图例"
        }
    }
}

/// Normalized illustration position: top-left (0, 0), bottom-right (1, 1).
struct PhysiognomyGuidePoint: Equatable, Codable, Sendable {
    let x: Double
    let y: Double
}

struct PhysiognomyGuideEntry: Identifiable, Codable, Sendable {
    let id: String
    let kind: PhysiognomyGuideKind
    let title: String
    let group: String
    let region: String
    let plainMeaning: String
    let observationSteps: [String]
    let commonMisread: String
    let point: PhysiognomyGuidePoint
}

/// Original explanatory copy; no unverified quotations or individual predictions.
/// Hand: palm facing the viewer, thumb on illustration-left; wrist at the bottom.
/// Face: frontal schematic, person's right on illustration-left; hairline around y=0.16,
/// brow around y=0.39, nose base around y=0.59, chin around y=0.80.
/// Point marks label anchors, not the complete extent of a line, mound, palace or region.
enum PhysiognomyGuideContent {
    static let introduction = "这些名称来自传统手相与面相文化，用来认识图例和阅读旧式术语。图中文字只说明部位、名称与观察方法，不根据真人的掌纹、长相或照片推断健康、财富、人格、关系或命运。"
    static let sourceNote = "本页为原创位置释义，不是古籍原文。传统图谱的名称与边界可能因版本不同而变化；本页未标出已核验的古籍版本、篇章或页码，不据此声称某一种图式为唯一标准。"
    static let handOrientation = "掌心朝向观察者，图中拇指在左、腕部在下。示意点用于定位名称；左右手可镜像对照，不附加男女或左右手的命运规则。"
    static let faceOrientation = "正面示意图。图左对应人物右侧；眉、眼、鼻与下巴用于定位。成对部位只标一侧锚点，阅读时同时认识另一侧。"

    static let handEntries: [PhysiognomyGuideEntry] = [
        .init(id: "hand.line.life", kind: .hand, title: "生命线（传统名称）", group: "三主线", region: "拇指根部外围的弧形掌纹", plainMeaning: "传统图谱把从虎口附近起、沿拇指根部外侧向腕部弯曲的一道掌褶称为生命线。这里的生命只是旧名称，不是寿命量尺。", observationSteps: ["在食指与拇指之间找到虎口。", "沿拇指根部外缘观察弧形掌褶，辨认它与横向掌纹的区别。", "仅记录走向与位置；看不清时保留不确定。"], commonMisread: "长短、深浅、断续不能用于判断寿命、疾病或体力；皮肤折叠和光线也会改变外观。", point: .init(x: 0.320, y: 0.680)),
        .init(id: "hand.line.head", kind: .hand, title: "智慧线（头线，传统名称）", group: "三主线", region: "掌心中部横向或斜向的掌纹", plainMeaning: "传统智慧线通常指虎口附近向掌心另一侧延伸的中部掌褶。它是图谱分类名，不是智力测试。", observationSteps: ["先认出拇指侧与小指侧。", "从虎口附近寻找穿过掌心中段的横纹或斜纹。", "若与其他掌纹相连，先按位置区分，再阅读名称。"], commonMisread: "不能凭纹路长短、分叉或弯直判断聪明程度、学习能力或人格。", point: .init(x: 0.560, y: 0.590)),
        .init(id: "hand.line.heart", kind: .hand, title: "感情线（心线，传统名称）", group: "三主线", region: "手指根部下方的上部横纹", plainMeaning: "传统感情线多指从小指侧进入、横过掌心上方的掌褶。感情是旧式象征命名，不表示可以读出真实关系。", observationSteps: ["找到小指根部下方的掌缘。", "辨认向食指或中指方向延伸的上部横纹。", "与较靠下的智慧线分开定位。"], commonMisread: "分叉、岛纹或断续不能用来推断恋爱经历、忠诚程度或婚姻结果。", point: .init(x: 0.570, y: 0.440)),
        .init(id: "hand.line.career", kind: .hand, title: "事业线（命运线，传统名称）", group: "其他传统线名", region: "掌心向中指根部方向延伸的纵纹", plainMeaning: "传统事业线是掌心纵向纹路的一种图谱称呼，常以朝向中指根部来辨认。它可能不明显，也可能由几段纹路组成。", observationSteps: ["先定位中指根部。", "向下寻找掌心中轴附近的纵纹。", "记录位置，不强行把零散细纹连成一条。"], commonMisread: "没有明显事业线不表示没有事业；长度与分段不能预测工作成败或具体年份。", point: .init(x: 0.520, y: 0.730)),
        .init(id: "hand.line.sun", kind: .hand, title: "太阳线（传统名称）", group: "其他传统线名", region: "无名指根部下方的纵向细纹", plainMeaning: "太阳线是传统图谱对无名指下方部分纵纹的命名。太阳在这里是象征名称，与天文观测无关。", observationSteps: ["找到无名指。", "在其根部下方寻找大致纵向的细纹。", "与中指下方的事业线分开辨认。"], commonMisread: "不能根据是否出现太阳线判断名气、艺术天赋、成功或收入。", point: .init(x: 0.660, y: 0.570)),
        .init(id: "hand.line.marriage", kind: .hand, title: "婚姻线（传统名称）", group: "其他传统线名", region: "小指根部与感情线之间的掌侧短纹", plainMeaning: "传统婚姻线通常指小指侧掌缘的一组短横纹，正面示意图只能提示其所在区域。", observationSteps: ["找到小指根部及感情线在掌侧的起点。", "辨认两者之间的掌缘区域。", "将图上点位理解为侧缘提示，不当作掌心中央的纹路。"], commonMisread: "短纹条数不等于结婚次数，也不能判断婚期、伴侣或关系质量。", point: .init(x: 0.800, y: 0.400)),
        .init(id: "hand.line.wealth", kind: .hand, title: "财运线（传统名称）", group: "其他传统线名", region: "部分图谱指小指根部下方的短纵纹", plainMeaning: "财运线并非各图谱统一的名称；本图用它说明小指下方常被如此标注的细纵纹位置，不把它等同实际财务状况。", observationSteps: ["先找到小指根部。", "查看其下方掌区的细纵纹。", "阅读其他资料时先核对作者给财运线划定的部位。"], commonMisread: "不同资料可能指不同纹路；不能据此推断财富多少、赚钱能力或投资结果。", point: .init(x: 0.760, y: 0.520)),
        .init(id: "hand.mount.jupiter", kind: .hand, title: "木星丘", group: "掌丘", region: "食指根部下方的掌区", plainMeaning: "掌丘指传统图谱给掌面局部区域取的名称；木星丘位于食指下方。木星是借用的象征名，不指皮肤中的实际结构。", observationSteps: ["找到食指根部。", "向掌心方向看紧接其下的区域。"], commonMisread: "区域饱满或平坦不能用于推断权力欲、领导力、人格或社会地位。", point: .init(x: 0.380, y: 0.430)),
        .init(id: "hand.mount.saturn", kind: .hand, title: "土星丘", group: "掌丘", region: "中指根部下方的掌区", plainMeaning: "土星丘是中指下方掌区的传统称呼，便于在图谱中定位。", observationSteps: ["找到中指根部。", "辨认它下方、邻近上部横纹的掌区。"], commonMisread: "名称不意味着能从该区域判断责任感、孤独、遭遇或命运。", point: .init(x: 0.520, y: 0.410)),
        .init(id: "hand.mount.sun", kind: .hand, title: "太阳丘", group: "掌丘", region: "无名指根部下方的掌区", plainMeaning: "太阳丘是无名指下方的传统区域名，与太阳线属于不同层次：一个是区域，一个是纹路名称。", observationSteps: ["找到无名指根部。", "先认区域，再区分区域内是否有被图谱命名的纹路。"], commonMisread: "不能把掌区形状当成审美、天赋、声望或运势的证据。", point: .init(x: 0.660, y: 0.430)),
        .init(id: "hand.mount.mercury", kind: .hand, title: "水星丘", group: "掌丘", region: "小指根部下方的掌区", plainMeaning: "水星丘是小指下方掌区的传统名称；它和位于附近的掌侧短纹需要分开认识。", observationSteps: ["找到小指根部。", "辨认其下方掌面，与更外侧的掌缘区分。"], commonMisread: "不能据此判断口才、商业能力、诚信或健康。", point: .init(x: 0.770, y: 0.440)),
        .init(id: "hand.mount.venus", kind: .hand, title: "金星丘", group: "掌丘", region: "拇指根部的较大掌区", plainMeaning: "金星丘通常指拇指根部、生命线弧形内侧的区域。这里的丘是图谱区域名。", observationSteps: ["找到拇指根部。", "对照生命线的弧形走向，辨认靠拇指一侧的区域。"], commonMisread: "掌区厚薄受多种实际因素影响，不能推断感情、精力、健康或人格。", point: .init(x: 0.270, y: 0.680)),
        .init(id: "hand.mount.moon", kind: .hand, title: "月丘（太阴丘）", group: "掌丘", region: "小指侧、靠近腕部的外侧掌区", plainMeaning: "月丘又称太阴丘，常指掌面下部远离拇指的一侧区域。", observationSteps: ["找到腕部。", "沿小指一侧向下定位外侧掌区。", "与拇指根部的金星丘分开认识。"], commonMisread: "不能据此判断想象力、情绪、旅行经历或未来迁移。", point: .init(x: 0.730, y: 0.760)),
        .init(id: "hand.mount.mars", kind: .hand, title: "火星区（七丘简图用名）", group: "掌丘", region: "掌心中部及两侧的相关传统分区", plainMeaning: "七丘简图常将火星作为一类；更细的传统图谱会区分第一火星丘、第二火星丘与火星平原。本图锚点提示中央区域，不把这些分区说成同一个精确部位。", observationSteps: ["先看当前图例采用七丘简图还是细分图。", "认识中央掌区及两侧相关标名。", "对照其他资料时分别核对各火星区边界。"], commonMisread: "七丘是简化目录，不代表所有图谱都只画七个独立区域；不能据此判断勇气、攻击性或处事方式。", point: .init(x: 0.530, y: 0.640)),
        .init(id: "hand.finger.thumb", kind: .hand, title: "拇指", group: "五指", region: "图左侧、与其余四指相对的手指", plainMeaning: "拇指是手部位置参照，根部邻近传统金星丘，和食指之间为虎口。", observationSteps: ["按示意图朝向找到图左侧拇指。", "认识指根、指节与虎口的区别。"], commonMisread: "长短、粗细、弯曲或张开角度不能用于推断意志力、人格或命运。", point: .init(x: 0.160, y: 0.490)),
        .init(id: "hand.finger.index", kind: .hand, title: "食指", group: "五指", region: "紧邻拇指的手指", plainMeaning: "食指位于拇指与中指之间，其根部下方在传统图谱中称木星丘。", observationSteps: ["从拇指向其余手指数第一根。", "沿指身向下定位指根。"], commonMisread: "手指比例或指向不能证明领导力、野心、地位或人格。", point: .init(x: 0.380, y: 0.220)),
        .init(id: "hand.finger.middle", kind: .hand, title: "中指", group: "五指", region: "食指与无名指之间的手指", plainMeaning: "中指位于四根并列手指的中间，其下方是传统土星丘的定位参照。", observationSteps: ["找到食指和无名指之间的手指。", "把指根作为区分掌区的参照。"], commonMisread: "长短与弯直不能推断责任感、性格、寿命或遭遇。", point: .init(x: 0.520, y: 0.160)),
        .init(id: "hand.finger.ring", kind: .hand, title: "无名指", group: "五指", region: "中指与小指之间的手指", plainMeaning: "无名指是太阳丘及太阳线名称的定位参照；指本身、掌丘和纹路是三个不同对象。", observationSteps: ["找到中指与小指之间的手指。", "沿指根向掌面辨认相邻区域。"], commonMisread: "指长比例不能用于推断天赋、关系、财富或人格。", point: .init(x: 0.660, y: 0.220)),
        .init(id: "hand.finger.little", kind: .hand, title: "小指", group: "五指", region: "远离拇指、位于图右侧的手指", plainMeaning: "小指位于手掌外侧，其根部是水星丘与掌侧短纹的位置参照。", observationSteps: ["找到示意图最右侧手指。", "区分指根下方掌面与外侧掌缘。"], commonMisread: "长短、位置高低或弯曲不能用于推断口才、诚信、财运或生育健康。", point: .init(x: 0.790, y: 0.310))
    ]

    static let faceEntries: [PhysiognomyGuideEntry] = [
        .init(id: "face.palace.life", kind: .face, title: "命宫（印堂附近）", group: "十二宫", region: "两眉之间、鼻根上方", plainMeaning: "传统面相命宫常定位在两眉之间的印堂附近。这里的宫是图谱分区名称，与紫微命宫不是同一个概念。", observationSteps: ["先找到两眉的内端。", "辨认两眉之间与鼻根上方的区域。", "把位置名称与其他术数中的同名词分开。"], commonMisread: "眉间宽窄、纹理或肤色不能用于判断命运、健康、情绪或人格。", point: .init(x: 0.500, y: 0.380)),
        .init(id: "face.palace.wealth", kind: .face, title: "财帛宫", group: "十二宫", region: "鼻部，常以鼻头及鼻翼为中心", plainMeaning: "财帛原指钱财物资，财帛宫是传统图谱给鼻部相关区域的名称，不是财务状况的测量点。", observationSteps: ["定位鼻梁、鼻头与两侧鼻翼。", "查看图例采用整段鼻部还是偏重鼻头鼻翼的范围。"], commonMisread: "鼻形、大小或肤色不能说明收入、资产、理财能力或未来财富。", point: .init(x: 0.500, y: 0.550)),
        .init(id: "face.palace.siblings", kind: .face, title: "兄弟宫", group: "十二宫", region: "两眉及邻近眉部", plainMeaning: "兄弟宫是传统图谱对眉部的称呼。兄弟是旧时关系类象名称，不是通过眉毛确认现实亲属关系。", observationSteps: ["找到两侧眉部。", "注意成对区域，图上点位只作一侧提示。"], commonMisread: "眉毛疏密、形状不能判断手足人数、亲疏、性格或人缘。", point: .init(x: 0.350, y: 0.390)),
        .init(id: "face.palace.home", kind: .face, title: "田宅宫", group: "十二宫", region: "眉与上眼睑之间", plainMeaning: "田宅原指田地房宅；常见图谱把眉眼之间的上眼睑区域称作田宅宫，不同版本边界可能不同。", observationSteps: ["先分别定位眉毛与眼睛。", "观察两者之间的区域，避免与眼下的子女宫混淆。"], commonMisread: "眉眼距离或眼睑形态不能用于判断房产、继承、家庭资源或居住运势。", point: .init(x: 0.350, y: 0.415)),
        .init(id: "face.palace.children", kind: .face, title: "子女宫（泪堂附近）", group: "十二宫", region: "下眼睑及眼下区域", plainMeaning: "子女宫常标在眼下，泪堂、卧蚕等相近称谓在旧图谱中使用范围并不完全一致；这里仅介绍常见位置。", observationSteps: ["找到下眼睑。", "辨认紧邻眼睛下方的区域。", "对照资料时核对作者是否将泪堂与卧蚕分开。"], commonMisread: "眼下外观不能用于判断子女人数、生育能力、亲子关系或健康。", point: .init(x: 0.350, y: 0.490)),
        .init(id: "face.palace.servants", kind: .face, title: "奴仆宫（传统旧称）", group: "十二宫", region: "下颌与两侧下颌附近", plainMeaning: "奴仆宫是带有古代社会等级背景的旧名，常标在下颌一带。现代阅读只把它作为图谱术语，不沿用其评价人的关系。", observationSteps: ["定位下巴及两侧下颌边缘。", "与中心较常标为地阁的位置一并认识。", "注意不同图谱对范围的划分差异。"], commonMisread: "不能据下颌形态判断下属、朋友、人缘、忠诚程度或社会地位。", point: .init(x: 0.320, y: 0.740)),
        .init(id: "face.palace.spouse", kind: .face, title: "夫妻宫（奸门附近）", group: "十二宫", region: "两眼外眼角外侧，靠近太阳穴", plainMeaning: "夫妻宫常定位在外眼角附近，传统术语奸门也是这个位置的旧名。名称中的字不表示道德评判。", observationSteps: ["找到外眼角，而不是靠鼻侧的内眼角。", "向外侧辨认邻近太阳穴的区域。"], commonMisread: "细纹、凹凸或肤色不能判断婚姻次数、伴侣忠诚、关系质量或婚期。", point: .init(x: 0.240, y: 0.440)),
        .init(id: "face.palace.illness", kind: .face, title: "疾厄宫（山根附近）", group: "十二宫", region: "两眼之间的鼻根及邻近鼻梁", plainMeaning: "疾厄宫是传统图谱的旧名称，通常以山根，即鼻梁靠近两眼之间的起点，作为定位参照。它不是医学检查部位的结论。", observationSteps: ["找到两眼之间的鼻根。", "与其上方两眉之间的印堂分开。", "核对当前图例是否延伸到邻近鼻梁。"], commonMisread: "鼻根高低、纹理或颜色不能用于诊断疾病、推断体质或安排治疗。", point: .init(x: 0.500, y: 0.440)),
        .init(id: "face.palace.travel", kind: .face, title: "迁移宫", group: "十二宫", region: "额头两侧、靠近额角与太阳穴上方", plainMeaning: "迁移指旧式图谱中的出行与迁居主题名称；迁移宫常标在额头两侧，具体边界随图谱而异。", observationSteps: ["定位额头两侧的额角。", "与较靠下、邻近外眼角的夫妻宫区分。"], commonMisread: "额角形状、发际或肤色不能预测出行安全、定居地点、迁居或旅行结果。", point: .init(x: 0.250, y: 0.280)),
        .init(id: "face.palace.career", kind: .face, title: "官禄宫", group: "十二宫", region: "额头中央", plainMeaning: "官禄原与旧时官职、俸禄有关；官禄宫是额头中央的传统图谱名称，不是职业测评。", observationSteps: ["找到两眉之间的中轴。", "向上定位额头中央，注意与两侧迁移宫的区别。"], commonMisread: "额形、纹路或高低不能判断学历、职业、能力、升职或地位。", point: .init(x: 0.500, y: 0.270)),
        .init(id: "face.palace.blessing", kind: .face, title: "福德宫", group: "十二宫", region: "眉上、额头两侧的相关区域", plainMeaning: "福德宫是传统图谱的主题区域名，常见位置在眉上与额侧，不同资料与迁移宫等区域可能邻接或部分重叠。", observationSteps: ["先找眉上区域。", "查看当前图例如何分出额中与额侧。", "比较其他资料时不要假定边界完全一致。"], commonMisread: "不能凭这一区域判断福气、道德、心理状态、享受能力或人生等级。", point: .init(x: 0.340, y: 0.320)),
        .init(id: "face.palace.parents", kind: .face, title: "父母宫（日角、月角）", group: "十二宫", region: "额头上部左右两侧", plainMeaning: "父母宫在常见图谱中与日角、月角相联系，常分别指额头上部左右区域。正面图的左右与人物自身左右相反。", observationSteps: ["找到额头上部两侧。", "核对图例以人物还是观察者为左右基准。", "本图锚点在图左，另一侧为对应区域。"], commonMisread: "额部外观不能判断父母寿命、亲缘、家庭经历或遗传健康；左右对应应按具体资料核对。", point: .init(x: 0.380, y: 0.210)),
        .init(id: "face.section.upper", kind: .face, title: "上停", group: "三停", region: "发际至眉部的示意分段", plainMeaning: "三停是把正面纵向分成上、中、下三段的传统图例方法。上停通常以发际到眉部为参照，不是人生早期的时间表。", observationSteps: ["辨认示意发际与眉部。", "把两者之间作为上段参照。", "注意真实发际、发型与图示边界未必一致。"], commonMisread: "比例长短不能用于判断童年经历、智力或早年命运；三停不对应可验证的逐岁预测。", point: .init(x: 0.650, y: 0.270)),
        .init(id: "face.section.middle", kind: .face, title: "中停", group: "三停", region: "眉部至鼻底的示意分段", plainMeaning: "中停是三停的中间一段，常以眉部和鼻底作为上下参照。它用于认识图谱分区。", observationSteps: ["定位眉部水平与鼻底。", "区分鼻头和鼻底，后者是鼻部下缘的参照。", "将中停作为区域阅读，不测算命运。"], commonMisread: "中段比例不能判断中年成败、能力、财富或健康。", point: .init(x: 0.650, y: 0.490)),
        .init(id: "face.section.lower", kind: .face, title: "下停", group: "三停", region: "鼻底至下巴底部的示意分段", plainMeaning: "下停是三停的下段，包含口部及下巴一带。传统资料有细分名称，本页先说明总体位置。", observationSteps: ["找到鼻底与下巴底部。", "认识两者之间包括口唇及颏部。", "与面相十二宫的主题分区分开阅读。"], commonMisread: "下段外观不能判断晚年、子女关系、生活保障、人格或寿命。", point: .init(x: 0.650, y: 0.710))
    ]

    static var allEntries: [PhysiognomyGuideEntry] { handEntries + faceEntries }

    static func entries(for kind: PhysiognomyGuideKind) -> [PhysiognomyGuideEntry] {
        switch kind {
        case .hand: return handEntries
        case .face: return faceEntries
        }
    }

    static func entry(id: String) -> PhysiognomyGuideEntry? {
        allEntries.first { $0.id == id }
    }
}
