iOS PDF 动态目录分页修复（独立 Draft）

已定位问题：ReportModule 旧 drawTOCItemCell 测量长标题 h，但外层目录一律 y += 16，可能覆盖邻项或页脚。

本 PR 新增 ReportTOCPlanner，对章节标题与左右栏逐条测量行高，并把长目录拆分为多页。makePDF 仍只做一次正文 paginate，目录页数决定正文绝对页码偏移；对旧单页目录仍使用第 2 页目录和第 3 页首正文。所有行文本、内容 hash、引擎版本及既有 Tests/golden 不变。

特别注意：页数扩展仅修改显示的目录和页脚总页数，导出时需真实生成 4/14/26 页与极端长标题样本检查文本完整、页码对应和无叠印。source 中保留旧 drawTOC（不再调用）方便精确视觉比对，尚未运行原生 Xcode。只做 iOS，不碰 Web/NAS/PR25/G14 或 PR53 海报模块；合并前需精确 SHA CI、PDF 实文件和人工预览。
