三术合参 iOS 四款海报动态绑定第二批

本次新增 Sources/PosterDynamicTemplateView.swift，映射 BaziChart、ZiweiChart、PalmRecord 和尊享现有布局的真实字段，图像样张中的生辰和测算数字一概不能成为用户结果。

八字与尊享作品库现在有当前人物的只读动态排版入口：字段与 Person.id 绑定，使用现有 BaziEngine.cachedPaipan 与 InterpretEngine.interpret，保留完整文本和字段出处，不写 PNG/PDF，不替换原导出器。

手相和紫微映射接口已准备，但未从真实业务页接线；旧 PalmRecord 只有 personName，必须单独补稳定人物 UUID 才能作为本人报告导出，禁止同名合并。

四种视觉语言：手相青黛金线 / 八字宋纸道家画卷 / 紫微玄夜观星 / 尊享朱砂册页。背景必须是无示例文字的独立纯画面，动态字段单独绘制。导出需 1080px 可变长图，与完整 A4 PDF 共享同源快照。

未验证：此新 head 的 Xcode 原生编译和实际视图、Palm/Ziwei 实接线、高清画面分层、PDF 动态导出、跨人物同名隔离、真机截图、IPA CRC/SHA。PR 继续 Draft，禁止合并或发布；不改 Web/NAS/PR25/G14/引擎/golden/既有 Tests。