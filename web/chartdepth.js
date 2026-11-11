/* 三术合参 Web 版 · 深度图表纯逻辑（Insight 第 3 批 G11）
 *
 * 只读 /api/interpret 已返回的数据，不新增后端接口、不新增请求：
 *   chart 四柱／天干十神／地支藏干／藏干十神／日主（paipan.py 输出），
 *   analysis.wuxing 五行占比字典（bazi_rules.analyze() 输出）。
 * 藏干十神由后端 chart「藏干十神」字段直接提供（paipan.py 按日主＋
 * CANG_GAN 用 bazi_rules.shi_shen 同口径现算）；前端不内嵌十神换算表
 *（kanyu-web/AGENTS.md §3.4：前端只调后端 REST API，不内嵌排盘算法）。
 * 五行归属与 BaziModule KyV2.element(ofChar:) 同口径（CHAR_WX 表）。
 * 联动规则与 App ChartDepthModule.swift 同款：
 *   点五行 → 含该五行的柱（天干／地支本气／任一藏干三处任一命中）；
 *   点十神 → 该十神所在柱（天干十神相同，或藏干十神含该十神）。
 * 本文件只含纯函数（无 DOM、无网络），供 app.js 渲染调用；
 * Node 下可直接 require（module.exports），供测试驱动。
 * 口径：只输出盘面事实（占比、计数、所在柱），不写断语。
 */
(function (global) {
  'use strict';

  var WX_NAMES = ['木', '火', '土', '金', '水'];
  var SHI_SHEN_ORDER = ['正官', '七杀', '正印', '偏印', '比肩', '劫财', '食神', '伤官', '正财', '偏财'];
  var PILLAR_NAMES = ['年柱', '月柱', '日柱', '时柱'];
  var PILLAR_KEYS = ['年柱', '月柱', '日柱', '时柱'];

  /* 干支单字 → 五行序号：与 KyV2.element(ofChar:) 同口径 */
  var CHAR_WX = {
    '甲': 0, '乙': 0, '寅': 0, '卯': 0,
    '丙': 1, '丁': 1, '巳': 1, '午': 1,
    '戊': 2, '己': 2, '辰': 2, '戌': 2, '丑': 2, '未': 2,
    '庚': 3, '辛': 3, '申': 3, '酉': 3,
    '壬': 4, '癸': 4, '亥': 4, '子': 4
  };

  function wxIndexOfChar(ch) {
    var v = CHAR_WX[ch];
    return (v === undefined) ? -1 : v;
  }

  /* 由 /api/interpret 返回的 chart＋analysis 建联动目标表。
   * chart: {四柱: {年柱, 月柱, 日柱, 时柱}, 天干十神: {年干, 月干, 时干},
   *         地支藏干: {年支, 月支, 日支, 时支},
   *         藏干十神: {年支, 月支, 日支, 时支}（后端现算，前端只读）,
   *         日主}
   * analysis: {wuxing: {木, 火, 土, 金, 水}} */
  function buildTargets(chart, analysis) {
    var sz = (chart && chart['四柱']) || {};
    var ss = (chart && chart['天干十神']) || {};
    var cg = (chart && chart['地支藏干']) || {};
    var cgss = (chart && chart['藏干十神']) || {};
    var dayMaster = (chart && chart['日主']) || '';
    var wx = (analysis && analysis.wuxing) || {};
    var pillars = [];
    var i, j;
    for (i = 0; i < 4; i++) {
      var gz = sz[PILLAR_KEYS[i]] || '';
      var stemKey = ['年干', '月干', '', '时干'][i];
      var stemSS = (i === 2) ? '日主' : (ss[stemKey] || '');
      var hideGan = cg[['年支', '月支', '日支', '时支'][i]] || '';
      var hideList = [];
      for (j = 0; j < hideGan.length; j++) hideList.push(hideGan[j]);
      var hideSS = cgss[['年支', '月支', '日支', '时支'][i]] || [];
      pillars.push({
        name: PILLAR_NAMES[i], ganzhi: gz,
        stem: gz ? gz[0] : '', branch: gz ? gz[1] : '',
        stemShishen: stemSS, hideGan: hideList, hideShishen: hideSS
      });
    }
    var wuxing = [];
    for (i = 0; i < 5; i++) wuxing.push(Number(wx[WX_NAMES[i]] || 0));
    var counts = [];
    SHI_SHEN_ORDER.forEach(function (name) {
      var count = 0;
      var pls = [];
      pillars.forEach(function (p, pi) {
        var hit = false;
        if (p.stemShishen === name) { count += 1; hit = true; }
        p.hideShishen.forEach(function (h) {
          if (h === name) { count += 1; hit = true; }
        });
        if (hit) pls.push(pi);
      });
      if (count > 0) counts.push({ name: name, count: count, pillars: pls });
    });
    return { pillars: pillars, wuxing: wuxing, shiShenCounts: counts, dayMaster: dayMaster };
  }

  /* 点五行 wx（0 木／1 火／2 土／3 金／4 水）→ 命中柱 [{pillar, details}] */
  function pillarsForWuxing(t, wx) {
    var out = [];
    t.pillars.forEach(function (p, i) {
      var details = [];
      if (p.stem && wxIndexOfChar(p.stem) === wx) details.push('天干 ' + p.stem);
      if (p.branch && wxIndexOfChar(p.branch) === wx) details.push('地支 ' + p.branch);
      p.hideGan.forEach(function (h) {
        if (wxIndexOfChar(h) === wx) details.push('藏干 ' + h);
      });
      if (details.length) out.push({ pillar: i, details: details });
    });
    return out;
  }

  /* 点十神 name → 命中柱 [{pillar, details}] */
  function pillarsForShishen(t, name) {
    var out = [];
    t.pillars.forEach(function (p, i) {
      var details = [];
      if (p.stemShishen === name) details.push('天干 ' + p.stem);
      p.hideGan.forEach(function (h, j) {
        if (p.hideShishen[j] === name) details.push('藏干 ' + h);
      });
      if (details.length) out.push({ pillar: i, details: details });
    });
    return out;
  }

  var api = {
    WX_NAMES: WX_NAMES,
    SHI_SHEN_ORDER: SHI_SHEN_ORDER,
    PILLAR_NAMES: PILLAR_NAMES,
    wxIndexOfChar: wxIndexOfChar,
    buildTargets: buildTargets,
    pillarsForWuxing: pillarsForWuxing,
    pillarsForShishen: pillarsForShishen
  };

  global.ChartDepth = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
