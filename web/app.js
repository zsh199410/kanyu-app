/* 三术合参 Web 版 · app.js
 * 只调后端 REST API，不内嵌任何排盘算法。
 * 年份数字一律用 String(year) 直接输出，禁止千分位逗号。 */
(function () {
  'use strict';

  var API = '';
  var state = {
    people: [],
    cities: [],
    currentId: null,
    paipan: null,
    interpret: null,
    ziwei: null,
    ziweiYear: null,
    ziweiMonth: null,
    luncai: null,
    chenggu: null,
    lucky: null,
    accessories: null,
    accWx: '',
    annual: null,
    annualYear: null,
    chartdepth: null,
    chartdepthSel: null,
    chartdepthBound: false,
    reports: null,
    reportScope: 'all',
    divination: null,
    yunqi: null,
    yunqiYear: null,
    hecan: null,
    qimen: null,
    qimenUrl: null,
    astro: null,
    kanyu: null,
    compass: { info: null, heading: -1, magnetic: -1, mode: 'true', lock: null, supported: '', listening: false },
    fp: { data: null, img: null, mode: 'xk', cx: 0.5, cy: 0.5, dragging: false },
    verifyMarks: {},
    verifyCount: 0,
    posterStyle: 'qingdai',
    lang: 'zh-Hans',
    zhHantTerms: null,
    zejiDays: [],
    zejiMonth: ''
  };

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s === undefined || s === null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  // 年份直接输出，绝不用 toLocaleString
  function yearStr(y) { return String(y); }

  function showError(msg) {
    var bar = $('errorBar');
    bar.textContent = msg;
    bar.hidden = false;
  }
  function clearError() { $('errorBar').hidden = true; $('errorBar').textContent = ''; }
  var toastTimer = null;
  function toast(msg) {
    var t = $('toast');
    t.textContent = msg;
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, 3000);
  }

  var LANG_SKIP = ['/api/poster', '/api/family/poster', '/api/people', '/api/backup',
    '/api/files', '/api/verify', '/api/forecasts', '/api/health', '/api/cities', '/api/classics'];
  function langQuery() { return state.lang === 'zh-Hant' ? 'lang=zh-Hant' : ''; }
  function api(path, options) {
    options = options || {};
    // G13：繁体模式下 GET /api/* 自动带 lang=zh-Hant（跳过名单除外：海报 PNG
    // 暂只出简体版；人物姓名／档案原文、验真／前瞻原文、古籍原文不转换）。
    if ((!options.method || options.method === 'GET') && path.indexOf('/api/') === 0
        && state.lang === 'zh-Hant'
        && !LANG_SKIP.some(function (p) { return path === p || path.indexOf(p + '?') === 0 || path.indexOf(p + '/') === 0; })) {
      path += (path.indexOf('?') !== -1 ? '&' : '?') + 'lang=zh-Hant';
    }
    options.credentials = 'same-origin'; // 会话走 HttpOnly Cookie，必须带上
    return fetch(API + path, options).then(function (res) {
      if (!res.ok) throw new Error('请求失败（HTTP ' + String(res.status) + '）：' + path);
      var ct = res.headers.get('content-type') || '';
      if (ct.indexOf('application/json') !== -1) return res.json();
      return res.text();
    });
  }
  function apiGet(path) { return api(path); }
  function apiPost(path, body) {
    return api(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
  }

  /* ---------- 主题 ---------- */
  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    var btn = $('themeToggle');
    btn.textContent = theme === 'dark' ? '☀️ 浅色' : '🌙 墨色';
    try { localStorage.setItem('kanyu-theme', theme); } catch (e) {}
  }
  /* ---------- G13：简／繁切换 ---------- */
  function applyHantToDom() {
    if (state.lang !== 'zh-Hant' || !state.zhHantTerms) return;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        var el = node.parentElement;
        if (!el) return NodeFilter.FILTER_REJECT;
        var tag = el.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'TEXTAREA') return NodeFilter.FILTER_REJECT;
        if (el.closest('[data-hant-off]')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(function (node) {
      var text = node.nodeValue;
      var out = text;
      state.zhHantTerms.forEach(function (kv) {
        if (out.indexOf(kv[0]) !== -1) out = out.split(kv[0]).join(kv[1]);
      });
      if (out !== text) node.nodeValue = out;
    });
  }
  function loadZhHantTerms() {
    if (state.zhHantTerms) { applyHantToDom(); return; }
    fetch('/api/zh_hant_terms', { credentials: 'same-origin' }).then(function (res) {
      return res.json();
    }).then(function (d) {
      var keys = Object.keys(d.terms || {}).filter(function (k) { return d.terms[k] !== k; });
      keys.sort(function (a, b) { return b.length - a.length || (a < b ? -1 : 1); });
      state.zhHantTerms = keys.map(function (k) { return [k, d.terms[k]]; });
      applyHantToDom();
    }).catch(function () { /* 对照表拉不到时只影响静态文案，接口仍按 lang 返回繁体 */ });
  }
  function initLang() {
    try { state.lang = localStorage.getItem('kanyu-lang') || 'zh-Hans'; } catch (e) { state.lang = 'zh-Hans'; }
    if (state.lang !== 'zh-Hant') state.lang = 'zh-Hans';
    var hansBtn = $('langHans');
    var hantBtn = $('langHant');
    function paint() {
      if (hansBtn) hansBtn.classList.toggle('active', state.lang === 'zh-Hans');
      if (hantBtn) hantBtn.classList.toggle('active', state.lang === 'zh-Hant');
    }
    paint();
    function setLang(next) {
      if (next === state.lang) return;
      state.lang = next;
      try { localStorage.setItem('kanyu-lang', next); } catch (e) {}
      location.reload(); // 重载后全部接口按新脚本取数，静态文案再过对照表
    }
    if (hansBtn) hansBtn.addEventListener('click', function () { setLang('zh-Hans'); });
    if (hantBtn) hantBtn.addEventListener('click', function () { setLang('zh-Hant'); });
    if (state.lang === 'zh-Hant') loadZhHantTerms();
  }

  function initTheme() {
    var saved = null;
    try { saved = localStorage.getItem('kanyu-theme'); } catch (e) {}
    applyTheme(saved === 'dark' ? 'dark' : 'light');
    $('themeToggle').addEventListener('click', function () {
      var cur = document.documentElement.getAttribute('data-theme');
      applyTheme(cur === 'dark' ? 'light' : 'dark');
    });
  }

  /* ---------- 路由（hash） ---------- */
  var ROUTES = ['hecan', 'bazi', 'ziwei', 'astro', 'qimen', 'qimen-cases', 'kanyu', 'compass', 'floorplan', 'xiangpi', 'poster', 'poster-editor', 'zeji', 'settings', 'hepan', 'family', 'luncai', 'celebs', 'library', 'classics', 'quiz', 'academy', 'palm', 'chenggu', 'divination', 'yunqi', 'ask', 'lucky', 'accessories', 'annual', 'chartdepth', 'reports'];
  function currentRoute() {
    var h = location.hash.replace(/^#\/?/, '').split('?')[0] || 'hecan';
    return ROUTES.indexOf(h) !== -1 ? h : 'hecan';
  }
  function hashQuery() {
    var h = location.hash.replace(/^#\/?/, '');
    var q = h.indexOf('?') !== -1 ? h.split('?')[1] : '';
    var out = {};
    q.split('&').forEach(function (kv) {
      var p = kv.split('=');
      if (p[0]) out[p[0]] = decodeURIComponent(p[1] || '');
    });
    return out;
  }
  function renderRoute() {
    applyHantToDom();
    var route = currentRoute();
    ROUTES.forEach(function (r) {
      var el = $('view-' + r);
      if (el) el.hidden = (r !== route);
    });
    document.querySelectorAll('[data-route]').forEach(function (a) {
      a.classList.toggle('active', a.getAttribute('data-route') === route);
    });
    if (route === 'bazi') loadBazi();
    if (route === 'xiangpi') loadInterpret();
    if (route === 'poster') updatePoster();
    if (route === 'poster-editor') updateEditorPerson();
    if (route === 'ziwei') loadZiwei();
    if (route === 'astro') loadAstro();
    if (route === 'qimen') initQimenDefaults();
    if (route === 'qimen-cases') loadQimenCases();
    if (route === 'kanyu') initKanyuDefaults();
    if (route === 'compass') initCompassDefaults();
    if (route === 'floorplan') initFloorplanDefaults();
    if (route === 'hecan') { loadToday(); loadHecanSummary(); loadHecan(); }
    if (route === 'zeji' && state.zejiDays.length === 0) loadZeji();
    if (route === 'hepan') loadHepan();
    if (route === 'family') loadFamily();
    if (route === 'luncai') loadLuncai();
    if (route === 'chenggu') loadChenggu();
    if (route === 'lucky') loadLucky();
    if (route === 'accessories') loadAccessories();
    if (route === 'annual') initAnnualDefaults();
    if (route === 'chartdepth') loadChartDepth();
    if (route === 'reports') loadReports();
    if (route === 'divination') initDivinationDefaults();
    if (route === 'ask') initAsk();
    if (route === 'yunqi') loadYunqi();
    if (route === 'celebs') loadCelebs();
    if (route === 'library') initLibrary();
    if (route === 'classics') initClassics();
    if (route === 'quiz') initQuiz();
    if (route === 'academy') initAcademy();
    if (route === 'palm') initPalm();
  }
  window.addEventListener('hashchange', renderRoute);

  function currentPerson() {
    for (var i = 0; i < state.people.length; i++) {
      if (String(state.people[i].id) === String(state.currentId)) return state.people[i];
    }
    return null;
  }
  function personLabel(p) {
    if (!p) return '未选择';
    return p.name + '（' + (p.relation || '') + ' · ' + (p.birth || '') + '）';
  }
  function setCurrent(id, refresh) {
    state.currentId = id;
    try { localStorage.setItem('kanyu-current-person', String(id)); } catch (e) {}
    renderPeople();
    updatePersonLabels();
    if (refresh !== false) {
      state.paipan = null; state.interpret = null; state.ziwei = null; state.hecan = null;
      state.qimen = null; state.astro = null; state.luncai = null; state.chenggu = null;
      state.lucky = null; state.annual = null; state.reports = null;
      state.chartdepth = null; state.chartdepthSel = null;
      state.divination = null;
      state.yunqi = null; state.yunqiYear = null;
      renderRoute();
      loadInterpretRight();
    }
  }

  /* ---------- 人物 ---------- */
  function renderPeople() {
    var list = $('peopleList');
    var strip = $('personStrip');
    if (!state.people.length) {
      list.innerHTML = '<li class="muted">暂无档案，请新建。</li>';
      strip.innerHTML = '<span class="muted">暂无档案</span>';
      return;
    }
    list.innerHTML = state.people.map(function (p) {
      var active = String(p.id) === String(state.currentId) ? ' class="active"' : '';
      return '<li' + active + ' data-id="' + esc(p.id) + '"><span><strong>' + esc(p.name) + '</strong> · ' + esc(p.relation || '') + '<br><small class="muted">' + esc(p.birth || '') + ' ' + esc(p.province || '') + esc(p.city || '') + '</small></span>' +
        '<button type="button" class="del" data-del="' + esc(p.id) + '" title="删除此档案">删除</button></li>';
    }).join('');
    strip.innerHTML = state.people.map(function (p) {
      var active = String(p.id) === String(state.currentId) ? ' class="active"' : '';
      return '<button type="button"' + active + ' data-id="' + esc(p.id) + '">' + esc(p.name) + '</button>';
    }).join('');
    list.querySelectorAll('li[data-id]').forEach(function (li) {
      li.addEventListener('click', function (ev) {
        if (ev.target.getAttribute('data-del')) return;
        setCurrent(li.getAttribute('data-id'));
      });
    });
    list.querySelectorAll('[data-del]').forEach(function (btn) {
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();
        deletePerson(btn.getAttribute('data-del'));
      });
    });
    strip.querySelectorAll('button[data-id]').forEach(function (btn) {
      btn.addEventListener('click', function () { setCurrent(btn.getAttribute('data-id')); });
    });
  }
  function updatePersonLabels() {
    var p = currentPerson();
    $('stripCurrent').textContent = p ? ('当前：' + p.name) : '';
    $('hecanPerson').textContent = personLabel(p);
    $('baziPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('xiangpiPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('ziweiPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('luncaiPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('chengguPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('luckyPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('annualPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('chartDepthPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('reportsPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '全部人物';
    $('yunqiPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主（不选命主亦可只看年度五运六气）';
    $('astroPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('qimenPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('posterPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('zejiPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
    $('rightPerson').textContent = p ? ('当前命主：' + p.name) : '未选择命主';
  }

  function loadPeople() {
    return apiGet('/api/people').then(function (data) {
      clearError();
      state.people = Array.isArray(data) ? data : [];
      var saved = null;
      try { saved = localStorage.getItem('kanyu-current-person'); } catch (e) {}
      if (!state.currentId && saved && state.people.some(function (p) { return String(p.id) === String(saved); })) {
        state.currentId = saved;
      }
      if (!state.currentId && state.people.length) state.currentId = state.people[0].id;
      renderPeople();
      updatePersonLabels();
      return state.people;
    }).catch(function (err) {
      showError('人物列表加载失败：' + err.message + '。请确认后端已启动后刷新页面。');
      $('peopleList').innerHTML = '<li class="muted">加载失败，请稍后重试。</li>';
      $('personStrip').innerHTML = '<span class="muted">加载失败</span>';
    });
  }

  function deletePerson(id) {
    if (!window.confirm('确定删除该档案吗？')) return;
    fetch(API + '/api/people/' + encodeURIComponent(id), { method: 'DELETE', credentials: 'same-origin' })
      .then(function (res) { if (!res.ok) throw new Error('HTTP ' + String(res.status)); return res.json().catch(function () { return {}; }); })
      .then(function () {
        toast('已删除');
        if (String(state.currentId) === String(id)) state.currentId = null;
        loadPeople().then(function () { setCurrent(state.currentId, true); });
      })
      .catch(function (err) { showError('删除失败：' + err.message); });
  }

  /* ---------- 省市联动 + 真太阳时校正 ---------- */
  function correctionMinutes(lon) {
    if (lon === '' || lon === null || isNaN(Number(lon))) return null;
    // 真太阳时校正约 (经度 - 120) × 4 分钟（北京时基准）
    return Math.round((Number(lon) - 120) * 4);
  }
  function updateCorrection() {
    var lon = $('lonInput').value;
    var m = correctionMinutes(lon);
    $('correctionLine').textContent = m === null
      ? '真太阳时校正约 — 分钟（请先选择城市或填写经度）'
      : '真太阳时校正约 ' + (m >= 0 ? '+' : '') + String(m) + ' 分钟（经度 ' + esc(lon) + '°，以北京时间 120°E 为基准）';
  }
  function loadCities() {
    return apiGet('/api/cities').then(function (data) {
      state.cities = Array.isArray(data) ? data : [];
      var prov = $('provinceSel');
      prov.innerHTML = '<option value="">请选择省份</option>' + state.cities.map(function (g) {
        return '<option value="' + esc(g.province) + '">' + esc(g.province) + '</option>';
      }).join('');
      setDefaultCity();
    }).catch(function (err) {
      showError('城市数据加载失败：' + err.message);
    });
  }
  function onProvinceChange() {
    var provName = $('provinceSel').value;
    var citySel = $('citySel');
    var group = null;
    state.cities.forEach(function (g) { if (g.province === provName) group = g; });
    if (!group) { citySel.innerHTML = '<option value="">请先选择省份</option>'; return; }
    citySel.innerHTML = '<option value="">请选择城市</option>' + (group.cities || []).map(function (c) {
      return '<option value="' + esc(c.name) + '" data-lon="' + esc(c.lon) + '">' + esc(c.name) + '</option>';
    }).join('');
  }
  function onCityChange() {
    var opt = $('citySel').selectedOptions && $('citySel').selectedOptions[0];
    if (opt && opt.getAttribute('data-lon')) {
      $('lonInput').value = opt.getAttribute('data-lon');
      updateCorrection();
    }
  }
  // 新建档案默认出生地：重庆·梁平（用户所在地）。按名字精确匹配，cities.json
  // 的表顺序变了也不错位；表里找不到时静默回退为空选（现行行为），不阻塞建档。
  function setDefaultCity() {
    if (!state.cities.length) return;
    var group = null;
    state.cities.forEach(function (g) { if (g.province === '重庆') group = g; });
    if (!group) return;
    var hasLiangping = false;
    (group.cities || []).forEach(function (c) { if (c.name === '梁平') hasLiangping = true; });
    if (!hasLiangping) return;
    $('provinceSel').value = '重庆';
    onProvinceChange();
    $('citySel').value = '梁平';
    onCityChange();
  }

  function initPersonForm() {
    $('provinceSel').addEventListener('change', onProvinceChange);
    $('citySel').addEventListener('change', onCityChange);
    $('lonInput').addEventListener('input', updateCorrection);
    $('reloadPeople').addEventListener('click', function () { loadPeople(); });
    $('personForm').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var f = ev.target;
      var birth = f.birth.value.replace('T', ' ');
      var payload = {
        name: f.name.value.trim(),
        relation: f.relation.value,
        gender: f.gender.value,
        birth: birth,
        province: f.province.value,
        city: f.city.value,
        lon: f.lon.value === '' ? null : Number(f.lon.value),
        useLongitude: $('useLonCheck').checked
      };
      if (!payload.name || !payload.birth || !payload.province || !payload.city) {
        $('formMsg').textContent = '请完整填写姓名、出生时间、省份与城市。';
        return;
      }
      var birthYear = parseInt(String(payload.birth).slice(0, 4), 10);
      if (!birthYear || birthYear < 1900 || birthYear > 2100) {
        $('formMsg').textContent = '出生年份须在 1900–2100 之间（已验证范围）；超出范围的年份本工具未经三方互校，请勿建档。';
        return;
      }
      $('createBtn').disabled = true;
      $('formMsg').textContent = '新建中…';
      fetch(API + '/api/people', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify(payload)
      }).then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + String(res.status));
        return res.json();
      }).then(function (created) {
        $('formMsg').textContent = '新建成功：' + (created.name || payload.name);
        f.reset();
        $('useLonCheck').checked = true;
        setDefaultCity();
        updateCorrection();
        loadPeople().then(function () {
          if (created && created.id) setCurrent(created.id);
          toast('档案已新建');
          // 保存成功后直接跳到新命主的八字排盘，不停留在已清空的表单上
          if (location.hash.replace(/^#\/?/, '') !== 'bazi') location.hash = '#/bazi';
          else renderRoute();
          var mv = $('mainView');
          if (mv && mv.scrollIntoView) mv.scrollIntoView();
        });
      }).catch(function (err) {
        $('formMsg').textContent = '新建失败：' + err.message;
        showError('新建档案失败：' + err.message);
      }).finally(function () { $('createBtn').disabled = false; });
    });
  }

  /* ---------- 八字 ---------- */
  function pillarHtml(label, gz, shishen, canggan, nayin, changsheng) {
    return '<div class="pillar"><h3>' + esc(label) + '</h3><div class="gz">' + esc(gz || '—') + '</div>' +
      '<p>十神：' + esc(shishen || '—') + '</p>' +
      '<p>藏干：' + esc(canggan || '—') + '</p>' +
      '<p>纳音：' + esc(nayin || '—') + '</p>' +
      '<p>长生：' + esc(changsheng || '—') + '</p></div>';
  }
  function loadBazi() {
    var p = currentPerson();
    if (!p) { $('baziEmpty').hidden = false; $('baziContent').hidden = true; return; }
    $('baziEmpty').hidden = true;
    $('baziLoading').hidden = false;
    $('baziContent').hidden = true;
    var paipanP = apiGet('/api/paipan?person_id=' + encodeURIComponent(p.id));
    var interpP = apiGet('/api/interpret?person_id=' + encodeURIComponent(p.id));
    Promise.all([paipanP, interpP]).then(function (results) {
      clearError();
      var pp = results[0] || {};
      var it = results[1] || {};
      state.paipan = pp; state.interpret = it;
      $('baziLoading').hidden = true;
      $('baziContent').hidden = false;
      var sz = pp['四柱'] || pp.sizhu || {};
      var ss = pp['天干十神'] || {};
      var cg = pp['地支藏干'] || {};
      var cs = pp['长生十二宫'] || {};
      var ny = pp['纳音'] || {};
      function val(obj, k) { return obj ? (obj[k] || '') : ''; }
      $('pillars').innerHTML =
        pillarHtml('年柱', sz['年柱'], val(ss, '年柱'), val(cg, '年柱'), val(ny, '年柱'), val(cs, '年柱')) +
        pillarHtml('月柱', sz['月柱'], val(ss, '月柱'), val(cg, '月柱'), val(ny, '月柱'), val(cs, '月柱')) +
        pillarHtml('日柱', sz['日柱'], val(ss, '日柱'), val(cg, '日柱'), val(ny, '日柱'), val(cs, '日柱')) +
        pillarHtml('时柱', sz['时柱'], val(ss, '时柱'), val(cg, '时柱'), val(ny, '时柱'), val(cs, '时柱'));
      var meta = [
        ['日主', pp['日主'] || '—'], ['日柱旬空', pp['日柱旬空'] || '—'],
        ['胎元', (pp['胎元命宫'] && pp['胎元命宫']['胎元']) || '—'],
        ['命宫', (pp['胎元命宫'] && pp['胎元命宫']['命宫']) || '—'],
        ['起运', pp['起运'] || '—'], ['月令司令', pp['月令司令'] || '—'],
        ['夏令时', pp['夏令时'] || '—'], ['校验', pp['校验'] || '—'],
        ['验证范围', pp['范围'] || '—']
      ];
      $('baziMeta').innerHTML = meta.map(function (kv) {
        return '<dt>' + esc(kv[0]) + '</dt><dd>' + esc(kv[1]) + '</dd>';
      }).join('');
      // 五行力量条
      var wx = it.wuxing || {};
      var keys = ['木', '火', '土', '金', '水'];
      var max = 0;
      keys.forEach(function (k) { if (Number(wx[k] || 0) > max) max = Number(wx[k] || 0); });
      $('wuxingBars').innerHTML = keys.map(function (k, idx) {
        var v = Number(wx[k] || 0);
        var pct = max > 0 ? Math.round(v / max * 100) : 0;
        return '<div class="bar-row"><span>' + esc(k) + '</span><div class="bar"><i style="width:' + String(pct) + '%"></i></div><span>' + String(v) + '</span></div>';
      }).join('') || '<p class="muted">后端未返回五行数据。</p>';
      // 喜用忌
      var xj = it.xiji || {};
      $('xijiBox').innerHTML =
        '<p>喜：' + ((xj.xi || []).map(function (x) { return '<span class="chip xi">' + esc(x) + '</span>'; }).join('') || '—') + '</p>' +
        '<p>忌：' + ((xj.ji || []).map(function (x) { return '<span class="chip ji">' + esc(x) + '</span>'; }).join('') || '—') + '</p>' +
        '<p class="muted">等级：' + esc(xj.level || '—') + ' · 通关：' + esc(xj.tongDang || xj.tongGuan || '—') + ' · 调候：' + esc(xj.tiaoHou || '—') + '</p>';
      // 大运
      var dy = pp['大运'] || [];
      $('dayunList').innerHTML = dy.length ? dy.map(function (d) {
        return '<div class="dayun"><strong>' + esc(d['干支'] || d.ganzhi || '') + '</strong> · ' +
          esc(d['天干十神'] || d.shishen || '') + ' · 起岁 ' + String(d['起岁'] == null ? '—' : d['起岁']) +
          ' · 起年 ' + yearStr(d['起年'] == null ? '—' : d['起年']) + '</div>';
      }).join('') : '<p class="muted">后端未返回大运。</p>';
      initAgeSelector(p);
    }).catch(function (err) {
      $('baziLoading').hidden = true;
      $('baziEmpty').hidden = false;
      showError('排盘加载失败：' + err.message);
    });
  }

  function birthYear(p) {
    if (!p || !p.birth) return null;
    var y = parseInt(String(p.birth).slice(0, 4), 10);
    return isNaN(y) ? null : y;
  }
  function initAgeSelector(p) {
    var sel = $('ageSel');
    if (!sel.options.length) {
      var html = '';
      for (var age = 1; age <= 88; age++) html += '<option value="' + String(age) + '">' + String(age) + ' 岁</option>';
      sel.innerHTML = html;
      sel.addEventListener('change', loadYearly);
    }
    loadYearly();
  }
  function loadYearly() {
    var p = currentPerson();
    if (!p) return;
    var age = Number($('ageSel').value || 1);
    var by = birthYear(p);
    if (by === null) { $('yearlyBox').innerHTML = '<p class="muted">出生年份无法解析。</p>'; return; }
    var year = by + age - 1;
    $('yearlyYear').textContent = '对应公历 ' + yearStr(year) + ' 年';
    $('yearlyBox').innerHTML = '<p class="muted">加载中…</p>';
    apiGet('/api/yearly?person_id=' + encodeURIComponent(p.id) + '&year=' + String(year))
      .then(function (d) {
        clearError();
        var checks = d.checks || {};
        var xy = d.xiaoyun;
        var xyLine = xy ? '<p>小运（起运前）：' + esc(xy.ganzhi || '') + ' · ' + String(xy.age_xu || '') + ' 岁（虚岁）· ' + esc(xy.direction || '') + '——' + esc(xy.note || '') + '</p>' : '';
        $('yearlyBox').innerHTML =
          '<p><strong>' + yearStr(d.year || year) + ' 年 · ' + esc(d.ganzhi || '') + '</strong> · 流年十神：' + esc(d.liunian_shishen || '') + ' · 大运：' + esc(d.dayun || '') + '</p>' +
          xyLine +
          '<p>结论：' + esc(d.verdict || '—') + '</p>' +
          ['事业', '财运', '健康', '感情'].map(function (k) {
            return '<p>' + esc(k) + '：' + esc(checks[k] || '—') + '</p>';
          }).join('');
      })
      .catch(function (err) {
        $('yearlyBox').innerHTML = '<p class="muted">逐年数据加载失败：' + esc(err.message) + '</p>';
      });
  }

  /* ---------- 今日卡（G1：当日干支＋宜忌＋命主专属三行） ---------- */
  function loadToday() {
    var p = currentPerson();
    var url = '/api/today' + (p ? '?person_id=' + encodeURIComponent(p.id) : '');
    apiGet(url).then(function (d) {
      $('todayDate').textContent = d.date || '';
      $('todayGanzhi').innerHTML = '<strong>' + esc(d.ganzhi || '—') + '日</strong> · ' +
        esc(d.year_ganzhi || '') + '年 ' + esc(d.month_ganzhi || '') + '月 · ' + esc(d.lunar || '') +
        ' · 冲' + esc(d.chong || '') + ' 煞' + esc(d.sha || '');
      var yi = (d.yi || []).slice(0, 5).join(' · ') || '—';
      var ji = (d.ji || []).slice(0, 3).join(' · ') || '—';
      $('todayYiJi').textContent = '宜 ' + yi + '；忌 ' + ji;
      var box = $('todayLines');
      if (!d.lines) {
        box.innerHTML = '<p class="muted">请选择命主后查看今日五行旺衰、冲合与大运流年（三行由本机引擎现算）。</p>';
        return;
      }
      box.innerHTML = d.lines.map(function (ln) {
        return '<p><strong>' + esc(ln.title) + '：</strong>' + esc(ln.text) +
          '<br><small class="muted">' + esc(ln.basis || '') + '</small></p>';
      }).join('');
    }).catch(function () {
      $('todayGanzhi').innerHTML = '<span class="muted">今日卡加载失败，请稍后重试。</span>';
    });
  }

  function loadHecanSummary() {
    var p = currentPerson();
    if (!p) { $('hecanSummary').innerHTML = '<h3>当前命主排盘摘要</h3><p class="muted">请选择命主后查看八字摘要。</p>'; return; }
    if (state.paipan) { renderHecanSummary(); return; }
    apiGet('/api/paipan?person_id=' + encodeURIComponent(p.id)).then(function (pp) {
      state.paipan = pp || {};
      renderHecanSummary();
    }).catch(function () {
      $('hecanSummary').innerHTML = '<h3>当前命主排盘摘要</h3><p class="muted">摘要加载失败，请稍后重试。</p>';
    });
  }
  function renderHecanSummary() {
    var pp = state.paipan || {};
    var sz = pp['四柱'] || {};
    $('hecanSummary').innerHTML = '<h3>当前命主排盘摘要</h3><p>四柱：' + esc(sz['年柱'] || '—') + ' ' + esc(sz['月柱'] || '—') + ' ' + esc(sz['日柱'] || '—') + ' ' + esc(sz['时柱'] || '—') + ' · 日主：' + esc(pp['日主'] || '—') + '</p><p><a href="#/bazi">查看完整八字排盘 →</a></p>';
  }

  /* ---------- 紫微方盘（与海报方盘同 cellPos 口径） ---------- */
  var CELL_POS = { 5: [0, 0], 6: [0, 1], 7: [0, 2], 8: [0, 3], 4: [1, 0], 9: [1, 3], 3: [2, 0], 10: [2, 3], 2: [3, 0], 1: [3, 1], 0: [3, 2], 11: [3, 3] };
  function loadZiwei() {
    var p = currentPerson();
    $('ziweiEmpty').hidden = !!p;
    $('ziweiContent').hidden = true;
    if (!p) return;
    if (state.ziwei) { renderZiwei(); return; }
    $('ziweiLoading').hidden = false;
    var url = '/api/ziwei?person_id=' + encodeURIComponent(p.id);
    if (state.ziweiYear) {
      url += '&year=' + encodeURIComponent(state.ziweiYear);
      if (state.ziweiMonth) url += '&lunar_month=' + encodeURIComponent(state.ziweiMonth);
    }
    apiGet(url).then(function (d) {
      $('ziweiLoading').hidden = true;
      state.ziwei = d || {};
      renderZiwei();
    }).catch(function (err) {
      $('ziweiLoading').hidden = true;
      $('ziweiEmpty').hidden = false;
      $('ziweiEmpty').innerHTML = '<p>紫微排盘加载失败：' + esc(err.message) + '。请稍后重试。</p>';
    });
  }
  function initLiunianControls() {
    var now = new Date().getFullYear();
    if (!$('liunianYear').value) $('liunianYear').value = String(now);
    $('liunianPrev').addEventListener('click', function () {
      $('liunianYear').value = String(Math.max(1950, (parseInt($('liunianYear').value, 10) || now) - 1));
      reloadLiunian();
    });
    $('liunianNext').addEventListener('click', function () {
      $('liunianYear').value = String(Math.min(2100, (parseInt($('liunianYear').value, 10) || now) + 1));
      reloadLiunian();
    });
    $('liunianLoad').addEventListener('click', reloadLiunian);
  }
  function reloadLiunian() {
    var y = parseInt($('liunianYear').value, 10);
    var m = parseInt($('liunianMonth').value, 10);
    if (!y || y < 1950 || y > 2100) { showError('流年年份须在 1950–2100 之间'); return; }
    clearError();
    state.ziweiYear = y;
    state.ziweiMonth = (m >= 1 && m <= 12) ? m : null;
    state.ziwei = null;
    loadZiwei();
  }
  function liunianHtml(ln) {
    if (!ln) return '<p class="muted">选年份后查看流年命宫、小限、流年四化与斗君流月（与 App 紫微流年层同口径）。</p>';
    var hua = (ln.mutagens || []).map(function (x) {
      return esc(x.star) + '化' + esc(x.kind) + '入' + esc(x.target_palace);
    }).join('、');
    var mh = (ln.month_mutagens || []).map(function (x) {
      return esc(x.star) + '化' + esc(x.kind) + '入' + esc(x.target_palace);
    }).join('、');
    var grid = (ln.year_palace_names || []).map(function (r) {
      return '<div class="fp-cell' + (r.is_liunian_ming ? ' ming' : '') + '"><div class="fp-head"><strong class="fp-name">' +
        esc(r.liunian_name) + '</strong><span class="muted fp-gz">' + esc(r.branch_name) + ' · 本命' + esc(r.natal_name) + '</span></div></div>';
    }).join('');
    var dx = ln.daxian ? ('大限：' + esc(ln.daxian.palace) + '（' + yearStr(ln.daxian.range[0]) + '–' + yearStr(ln.daxian.range[ln.daxian.range.length - 1]) + '岁）') : '大限：—';
    return '<p><strong>' + yearStr(ln.year) + ' ' + esc(ln.ganzhi) + '年</strong> · 虚岁 ' + yearStr(ln.age_xu) +
      ' · 流年命宫 <strong>' + esc(ln.liunian_ming_palace) + '</strong> · 小限 <strong>' + esc(ln.xiaoxian_palace) +
      '</strong> · ' + esc(dx) + '</p>' +
      '<p>流年四化：' + esc(hua) + '</p>' +
      '<p>斗君流月命宫（农历 ' + yearStr(ln.lunar_month) + ' 月）：<strong>' + esc(ln.month_palace) + '</strong>（' + esc(ln.month_stem) + '干四化：' + esc(mh) + '）</p>' +
      '<div class="fangpan">' + grid + '</div>' +
      '<p class="hint">' + esc(ln.method || '') + '</p>';
  }
  function ziweiCellHtml(pal, chart) {
    var isMing = pal.branch === chart.ming_gong;
    var majors = (pal.majors || []).map(function (m) {
      var hua = m.mutagen ? '<span class="hua ' + (m.mutagen === '忌' ? 'ji' : '') + '">化' + esc(m.mutagen) + '</span>' : '';
      return '<span class="fp-star">' + esc(m.star) + '</span> <span class="muted">' + esc(m.brightness || '') + '</span>' + hua;
    }).join('<br>');
    if (!majors) majors = '<span class="muted">无主星 · 借对宫</span>';
    var minors = (pal.minors || []).map(function (m) { return esc(m.star); }).join(' ');
    var dec = pal.decadal || [];
    var pos = CELL_POS[pal.branch] || [0, 0];
    return '<div class="fp-cell' + (isMing ? ' ming' : '') + '" style="grid-row:' + String(pos[0] + 1) + ';grid-column:' + String(pos[1] + 1) + '">' +
      '<div class="fp-head"><strong class="fp-name">' + esc(pal.name) + '</strong>' +
      (pal.is_body ? '<span class="fp-badge">身</span>' : '') +
      '<span class="muted fp-gz">' + esc(pal.ganzhi || '') + '</span></div>' +
      '<div class="fp-majors">' + majors + '</div>' +
      (minors ? '<div class="fp-minors muted">' + minors + '</div>' : '') +
      (dec.length ? '<div class="fp-dec">' + String(dec[0]) + '–' + String(dec[dec.length - 1]) + '岁</div>' : '') +
      '</div>';
  }
  function renderZiwei() {
    var d = state.ziwei || {};
    var chart = d.chart || {};
    var pals = chart.palaces || [];
    var bodyName = '';
    pals.forEach(function (pp) { if (pp.is_body) bodyName = pp.name; });
    $('ziweiMeta').innerHTML = '<p>' + esc(chart.ju_name || '—') + ' · 命宫' + esc(chart.ming_gong_name || '—') + ' · 身宫' + esc(bodyName || '—') + ' · ' + esc(chart.lunar_text || '') + '</p>';
    var center = '<div class="fp-center"><div class="fp-center-name">' + esc((d.person && d.person.name) || '') + '</div>' +
      '<div class="fp-center-badges"><span class="chip">' + esc(chart.ju_name || '') + '</span> ' +
      '<span class="chip ji">命宫 · ' + esc(chart.ming_gong_name || '') + '</span> ' +
      '<span class="chip">身宫 · ' + esc(bodyName || '') + '</span></div>' +
      '<div class="muted">' + esc(chart.lunar_text || '') + '</div></div>';
    $('ziweiBoard').innerHTML = pals.map(function (pp) { return ziweiCellHtml(pp, chart); }).join('') + center;
    $('ziweiCards').innerHTML = (d.cards || []).map(function (c) {
      return '<article class="card interpret-card"><h3>' + esc(c.title || '') + '</h3><p>' + esc(c.conclusion || '') + '</p>' +
        '<div class="src"><p>盘面事实：' + esc(c.facts || '—') + '</p><p>出处：' + esc(c.source || '—') + '</p></div></article>';
    }).join('');
    $('liunianBox').innerHTML = liunianHtml(d.liunian || null);
    $('liunianYearLabel').textContent = d.liunian ? ('· ' + yearStr(d.liunian.year) + ' ' + d.liunian.ganzhi + '年') : '';
    $('ziweiContent').hidden = false;
  }

  /* ---------- 合参：四维裁决＋命宫定型＋海报下载 ---------- */
  function loadHecan() {
    var p = currentPerson();
    $('hecanContent').hidden = true;
    if (!p) return;
    if (state.hecan) { renderHecan(); return; }
    $('hecanLoading').hidden = false;
    apiGet('/api/hecan?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      $('hecanLoading').hidden = true;
      state.hecan = d || {};
      renderHecan();
    }).catch(function (err) {
      $('hecanLoading').hidden = true;
      showError('合参加载失败：' + err.message);
    });
  }
  function renderHecan() {
    var d = state.hecan || {};
    var p = currentPerson();
    var ming = d.ming_card || {};
    $('hecanMing').innerHTML = '<p><strong>' + esc(ming.title || '命宫定型') + '</strong></p><p>' + esc(ming.conclusion || '—') + '</p>' +
      (ming.facts ? '<p class="muted">盘面事实：' + esc(ming.facts) + '</p>' : '') +
      '<p class="muted">' + esc(d.bazi_verdict || '') + ' · ' + esc(d.hua_line || '') + '</p>';
    $('hecanCross').innerHTML = (d.cross_cards || []).map(function (c) {
      return '<article class="card cross-card"><h3>' + esc(c.dim || '') + '交叉裁决</h3>' +
        '<p><strong>八字：</strong>' + esc(c.bazi || '') + '</p>' +
        '<p><strong>紫微：</strong>' + esc(c.ziwei || '') + '</p>' +
        '<p class="verdict">裁决：' + esc(c.verdict || '') + '</p></article>';
    }).join('');
    if (p) {
      var url = '/api/poster?person_id=' + encodeURIComponent(p.id) + '&style=hecan';
      $('hecanPosterDownload').setAttribute('href', url);
      $('hecanPosterDownload').setAttribute('download', 'poster-hecan-' + String(p.id) + '.png');
    }
    $('hecanContent').hidden = false;
  }

  /* ---------- 奇门遁甲 ---------- */
  var QM_ROWS = [[4, 9, 2], [3, 5, 7], [8, 1, 6]]; // 九宫格行序，与 iOS boardCard 一致
  function qimenDefaultDt() {
    var now = new Date();
    function pad(n) { return (n < 10 ? '0' : '') + String(n); }
    return String(now.getFullYear()) + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate()) +
      'T' + pad(now.getHours()) + ':' + pad(now.getMinutes());
  }
  function initQimenDefaults() {
    if (!$('qimenDt').value) $('qimenDt').value = qimenDefaultDt();
  }
  function qimenTopicParam() {
    var t = $('qimenTopic').value;
    return t ? '&topic=' + encodeURIComponent(t) : '';
  }
  function qimenG3Params() {
    // G3：定局法／寄宫／暗干／真太阳时开关（未勾选时不传 lon，不校正）
    var p = '&dingju=' + encodeURIComponent($('qimenDingju').value || 'chaibu') +
      '&jigong=' + encodeURIComponent($('qimenJigong').value || 'kun2') +
      '&angan=' + ($('qimenAngan').checked ? 'true' : 'false');
    if ($('qimenSolar').checked) {
      p += '&solar=true';
      var lon = ($('qimenLon').value || '').trim();
      if (lon !== '') p += '&lon=' + encodeURIComponent(lon);
    }
    return p;
  }
  function loadQimen(url) {
    state.qimenUrl = url.replace(/&topic=[^&]*/, ''); // 记下不带 topic 的基地址，换用神时按同一方式重算
    $('qimenLoading').hidden = false;
    $('qimenContent').hidden = true;
    apiGet(url).then(function (d) {
      clearError();
      $('qimenLoading').hidden = true;
      state.qimen = d || {};
      renderQimen();
    }).catch(function (err) {
      $('qimenLoading').hidden = true;
      $('qimenEmpty').hidden = false;
      $('qimenEmpty').innerHTML = '<p>奇门起局失败：' + esc(err.message) + '。请检查起局时间后重试。</p>';
      showError('奇门起局失败：' + err.message);
    });
  }
  function loadRijia() {
    var dt = ($('qimenDt').value || '').replace('T', ' ');
    if (!dt) { showError('请先填写起局时间。'); return; }
    $('qimenEmpty').hidden = true;
    var url = '/api/qimen/rijia?datetime=' + encodeURIComponent(dt);
    if ($('qimenSolar').checked) {
      url += '&solar=true';
      var lon = ($('qimenLon').value || '').trim();
      if (lon !== '') url += '&lon=' + encodeURIComponent(lon);
    }
    $('qimenLoading').hidden = false;
    $('qimenContent').hidden = true;
    apiGet(url).then(function (d) {
      clearError();
      $('qimenLoading').hidden = true;
      state.qimen = state.qimen || {};
      state.qimen.rijia = (d || {}).chart || null;
      if (!state.qimen.chart) { state.qimen = { chart: null, rijia: state.qimen.rijia, glossary: {} }; }
      renderQimen();
    }).catch(function (err) {
      $('qimenLoading').hidden = true;
      $('qimenEmpty').hidden = false;
      $('qimenEmpty').innerHTML = '<p>日家起局失败：' + esc(err.message) + '。请检查起局时间后重试。</p>';
      showError('日家起局失败：' + err.message);
    });
  }
  function loadQimenCases() {
    $('qimenCasesLoading').hidden = false;
    apiGet('/api/qimen/cases').then(function (d) {
      $('qimenCasesLoading').hidden = true;
      var list = (d || {}).cases || [];
      $('qimenCasesList').innerHTML = list.map(function (c) {
        return '<div class="card"><h3>' + esc(c.title || '') + '</h3>' +
          '<p><strong>起局时间：</strong>' + esc(c.datetime || '') + ' · ' + esc(c.dingju || '') + ' ' +
          esc(c.dun || '') + ' ' + esc(String(c.ju == null ? '' : c.ju)) + ' 局 ' + esc(c.sanyuan || '') +
          '（' + esc(c.jieqi || '') + '）</p>' +
          '<p><strong>四柱：</strong>' + esc((c.pillars || []).join(' ')) + ' · <strong>值符：</strong>' + esc(c.zhifu || '') +
          ' · <strong>值使：</strong>' + esc(c.zhishi || '') + '</p>' +
          '<p><strong>局象原文：</strong>' + esc(c.source_text || '') + '</p>' +
          '<p><strong>引擎复核：</strong>' + esc(c.verified || '') + '</p>' +
          (c.zhifu_note ? '<p><strong>值符宫标注：</strong>' + esc(c.zhifu_note) + '</p>' : '') +
          (c.zhishi_note ? '<p><strong>值使宫标注：</strong>' + esc(c.zhishi_note) + '</p>' : '') +
          '<p><strong>应验记录：</strong>' + esc(c.yingyan || '') + ' · <strong>回验：</strong>' + esc(c.status || '') + '</p>' +
          '<p><strong>来源：</strong><a href="' + esc(c.source_url || '') + '" target="_blank" rel="noopener">' + esc(c.source_name || '') + '</a></p>' +
          '<div class="entry-links"><button type="button" class="btn" data-case-dt="' + esc(c.datetime || '') + '">查看本盘</button></div>' +
          '</div>';
      }).join('') || '<p>暂无案例。</p>';
      $('qimenCasesList').querySelectorAll('[data-case-dt]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var dt = btn.getAttribute('data-case-dt') || '';
          $('qimenDt').value = dt.replace(' ', 'T');
          location.hash = '#/qimen';
          $('qimenEmpty').hidden = true;
          loadQimen('/api/qimen?datetime=' + encodeURIComponent(dt) + qimenG3Params() + qimenTopicParam());
        });
      });
    }).catch(function (err) {
      $('qimenCasesLoading').hidden = true;
      $('qimenCasesList').innerHTML = '<p>案例库加载失败：' + esc(err.message) + '</p>';
    });
  }
  function renderQimen() {
    var d = state.qimen || {};
    var c = d.chart || {};
    var pals = {};
    (c.palaces || []).forEach(function (pp) { pals[pp.palace] = pp; });
    if (!c.palaces) {
      // 仅日家模式：时家部分留空，只渲染日家卡
      $('qimenMeta').innerHTML = '';
      $('qimenReceipt').textContent = '';
      $('qimenBoard').innerHTML = '';
      $('qimenPatterns').innerHTML = '';
      $('qimenLayers').innerHTML = '';
      $('qimenChangsheng').innerHTML = '';
      $('qimenYongshen').innerHTML = '';
      $('qimenGlossary').innerHTML = '';
    } else {
    var meta = [
      ['起局时间', c.datetime || '—'], ['四柱', (c.pillars || []).join(' ') || '—'],
      ['农历', c.lunar_text || '—'], ['节气', c.jieqi || '—'],
      ['局数', c.dun + ' ' + String(c.ju == null ? '—' : c.ju) + ' 局'], ['三元', c.sanyuan || '—'],
      ['定局法', (c.dingju || '拆补法') + (c.runqi ? '（闰奇）' : '')],
      ['寄宫', c.jigong || '恒寄坤二'],
      ['旬首', (c.xun_shou || '—') + '（遁 ' + (c.xun_dun || '—') + '）'],
      ['值符', c.zhifu_star_name || '—'], ['值使', c.zhishi_door_name || '—'],
      ['空亡', c.kong_wang || '—'], ['马星', c.ma_xing || '—']
    ];
    $('qimenMeta').innerHTML = '<dl class="kv">' + meta.map(function (kv) {
      return '<dt>' + esc(kv[0]) + '</dt><dd>' + esc(kv[1]) + '</dd>';
    }).join('') + '</dl>';
    $('qimenReceipt').textContent = (c.receipt && (c.receipt.text || c.receipt_text)) || c.receipt_text || '';
    $('qimenBoard').innerHTML = QM_ROWS.map(function (row) {
      return row.map(function (num) {
        var pp = pals[num] || {};
        var pats = (pp.patterns || []).map(function (pt) {
          return '<span class="qm-pat ' + (pt.good ? 'good' : 'bad') + '">' + esc(pt.name) + '</span>';
        }).join(' ');
        var sh = pp.si_hai || {};
        var shBadges = (sh.kong ? '<span class="qm-pat bad">空</span>' : '') +
          (sh.jixing ? '<span class="qm-pat bad">击刑</span>' : '') +
          (sh.rumu ? '<span class="qm-pat bad">入墓</span>' : '') +
          (sh.menpo ? '<span class="qm-pat bad">门迫</span>' : '');
        var ky = pp.keying ? '<div class="muted">克应：' + esc(pp.keying.name || '') + '</div>' : '';
        var cs = '';
        if (pp.changsheng_tian) {
          cs = '<div class="muted">长生：' + esc(typeof pp.changsheng_tian === 'string' ? pp.changsheng_tian :
            Object.keys(pp.changsheng_tian).map(function (b) { return b + pp.changsheng_tian[b]; }).join('／')) + '</div>';
        }
        var ag = pp.angan ? '<div class="muted">暗干：' + esc(pp.angan) + '</div>' : '';
        return '<div class="qm-cell' + (pp.is_zhifu ? ' zhifu' : '') + (pp.is_zhishi ? ' zhishi' : '') + '">' +
          '<div class="qm-head"><strong>' + esc(pp.name || '') + '宫</strong><span class="muted">' + esc(pp.direction || '') + ' · ' + esc(pp.wuxing || '') + '</span></div>' +
          '<div class="qm-stems"><span>天 ' + esc(pp.tian_stem || '—') + '</span><span>地 ' + esc(pp.di_stem || '—') + '</span></div>' +
          '<div class="qm-star">' + esc(pp.star_name || '—') + '</div>' +
          '<div>' + esc(pp.door_name || '—') + ' · ' + esc(pp.god || '—') + '</div>' +
          (pp.is_zhifu ? '<span class="qm-badge">值符</span>' : '') +
          (pp.is_zhishi ? '<span class="qm-badge">值使</span>' : '') +
          (pats ? '<div class="qm-pats">' + pats + '</div>' : '') +
          (shBadges ? '<div class="qm-pats">' + shBadges + '</div>' : '') +
          ky + cs + ag +
          '</div>';
      }).join('');
    }).join('');
    var pats = c.patterns || [];
    $('qimenPatterns').innerHTML = '<div class="card"><h3>格局</h3>' + (pats.length ? pats.map(function (pt) {
      return '<p><span class="qm-pat ' + (pt.good ? 'good' : 'bad') + '">' + esc(pt.name) + '</span> ' +
        esc(pt.palace_name || '') + '宫：' + esc(pt.note || '') + '</p>';
    }).join('') : '<p>本局无 v1 格局命中——无格局也是一种信息：盘面平顺，无特殊吉凶标记。</p>') + '</div>';
    // G3：四害与克应（每宫一条克应＋四害标记）
    var layerHtml = '<div class="card"><h3>四害与克应</h3>';
    layerHtml += (c.palaces || []).map(function (pp) {
      var sh = pp.si_hai || {};
      var marks = [];
      if (sh.kong) marks.push('空亡');
      if (sh.jixing) marks.push('击刑');
      if (sh.rumu) marks.push('入墓');
      if (sh.menpo) marks.push('门迫');
      var ky = pp.keying ? esc(pp.keying.name) + '：' + esc(pp.keying.note || '') : '—';
      return '<p><strong>' + esc(pp.name || '') + '宫</strong>（天 ' + esc(pp.tian_stem || '—') + '／地 ' + esc(pp.di_stem || '—') + '）' +
        (marks.length ? ' <span class="qm-pat bad">' + esc(marks.join('／')) + '</span>' : ' 无四害') +
        '<br>克应：' + ky + '</p>';
    }).join('');
    if (c.shi_gan_rumu) layerHtml += '<p><strong>时干入墓：</strong>本局时柱入墓，课中时下忌相逢。</p>';
    layerHtml += '</div>';
    $('qimenLayers').innerHTML = layerHtml;
    // G3：十二长生（日干／时干全表）
    var csd = c.changsheng || {};
    function csTable(label, gan, table) {
      if (!table) return '';
      return '<p><strong>' + esc(label) + '（' + esc(gan || '') + '）：</strong>' +
        table.map(function (r) { return esc(r.branch) + esc(r.stage); }).join('、') + '</p>';
    }
    $('qimenChangsheng').innerHTML = '<div class="card"><h3>十二长生（旺衰）</h3>' +
      csTable('日干', csd.ri_gan, csd.ri_gan_table) + csTable('时干', csd.shi_gan, csd.shi_gan_table) +
      '<p class="muted">阳顺阴逆；四正宫天盘干长生为单值，四维宫为两支各值，中宫无本位地支。</p></div>';
    }
    // G3：日家盘（与时家并列展示）
    var rj = d.rijia;
    if (rj) {
      var rpals = {};
      (rj.palaces || []).forEach(function (pp) { rpals[pp.palace] = pp; });
      $('qimenRijia').innerHTML = '<div class="card"><h3>日家盘（同时间）</h3>' +
        '<p>' + esc(rj.dun || '') + ' ' + esc(String(rj.ju == null ? '' : rj.ju)) + ' 局 · ' +
        esc((rj.pillars || []).join(' ')) + ' · ' + esc(rj.jieqi || '') + '</p>' +
        '<p class="hint">' + esc((rj.receipt && rj.receipt.text) || rj.receipt_text || '') + '</p>' +
        '<div class="qm-board">' + QM_ROWS.map(function (row) {
          return row.map(function (num) {
            var pp = rpals[num] || {};
            return '<div class="qm-cell"><div class="qm-head"><strong>' + esc(pp.name || '') + '宫</strong></div>' +
              '<div class="qm-stems"><span>地 ' + esc(pp.di_stem || '—') + '</span></div>' +
              '<div class="qm-star">' + esc(pp.star_name || '—') + '</div>' +
              '<div>' + esc(pp.door_name || '—') + '</div></div>';
          }).join('');
        }).join('') + '</div></div>';
    } else {
      $('qimenRijia').innerHTML = '';
    }
    if (!c.palaces) {
      $('qimenYongshen').innerHTML = '';
      $('qimenGlossary').innerHTML = '';
    } else {
    var ys = c.yong_shen;
    var ysAll = c.yong_shen_all || [];
    var ysHtml = '';
    if (ys) {
      ysHtml = '<p><strong>' + esc(ys.topic) + '</strong>：' + esc(ys.guide || '') + '</p>' +
        '<p>' + (ys.focus || []).map(function (f) {
          return esc(f.label) + '在' + esc(f.palace_name || '') + '宫';
        }).join('；') + '</p>';
    } else {
      ysHtml = '<p class="muted">未选定用神主题，以下为用神速查全表：</p>' +
        ysAll.map(function (y) { return '<p><strong>' + esc(y.topic) + '</strong>：' + esc(y.guide || '') + '</p>'; }).join('');
    }
    $('qimenYongshen').innerHTML = '<div class="card"><h3>用神释义</h3>' + ysHtml + '</div>';
    var g = d.glossary || {};
    function glossList(title, items) {
      if (!items || !items.length) return '';
      return '<h4>' + esc(title) + '</h4>' + items.map(function (x) {
        return '<p><strong>' + esc(x.name) + '</strong>：' + esc(x.note || '') + '</p>';
      }).join('');
    }
    $('qimenGlossary').innerHTML =
      glossList('八门', g.doors) + glossList('九星', g.stars) + glossList('八神', g.gods) + glossList('格局', g.patterns);
    }
    $('qimenEmpty').hidden = true;
    $('qimenContent').hidden = false;
  }
  function initQimen() {
    $('qimenSolar').addEventListener('change', function () {
      $('qimenLon').disabled = !$('qimenSolar').checked;
    });
    $('qimenDingju').addEventListener('change', function () {
      if (state.qimenUrl) { // 已起过局：换定局法即按同一方式重算
        $('qimenEmpty').hidden = true;
        loadQimen(state.qimenUrl.replace(/&dingju=[^&]*/, '') + '&dingju=' + encodeURIComponent($('qimenDingju').value) + qimenTopicParam());
      }
    });
    $('qimenJigong').addEventListener('change', function () {
      if (state.qimenUrl) { // 已起过局：换寄宫即按同一方式重算
        $('qimenEmpty').hidden = true;
        loadQimen(state.qimenUrl.replace(/&jigong=[^&]*/, '') + '&jigong=' + encodeURIComponent($('qimenJigong').value) + qimenTopicParam());
      }
    });
    $('qimenPersonBtn').addEventListener('click', function () {
      var p = currentPerson();
      if (!p) { showError('请先在左侧档案库选择一位命主。'); return; }
      $('qimenEmpty').hidden = true;
      loadQimen('/api/qimen?person_id=' + encodeURIComponent(p.id) + qimenG3Params() + qimenTopicParam());
    });
    $('qimenTimeBtn').addEventListener('click', function () {
      var dt = ($('qimenDt').value || '').replace('T', ' ');
      if (!dt) { showError('请先填写起局时间。'); return; }
      $('qimenEmpty').hidden = true;
      loadQimen('/api/qimen?datetime=' + encodeURIComponent(dt) + qimenG3Params() + qimenTopicParam());
    });
    $('qimenRijiaBtn').addEventListener('click', function () { loadRijia(); });
    $('qimenTopic').addEventListener('change', function () {
      if (state.qimenUrl) { // 已起过局：换用神即按同一方式重算
        $('qimenEmpty').hidden = true;
        loadQimen(state.qimenUrl + qimenTopicParam());
      }
    });
  }

  /* ---------- 星命合参 ---------- */
  function loadAstro() {
    var p = currentPerson();
    $('astroEmpty').hidden = !!p;
    $('astroContent').hidden = true;
    if (!p) return;
    if (state.astro) { renderAstro(); return; }
    $('astroLoading').hidden = false;
    apiGet('/api/astro?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      $('astroLoading').hidden = true;
      state.astro = d || {};
      renderAstro();
    }).catch(function (err) {
      $('astroLoading').hidden = true;
      $('astroEmpty').hidden = false;
      $('astroEmpty').innerHTML = '<p>星盘加载失败：' + esc(err.message) + '。请稍后重试。</p>';
    });
  }
  function renderAstro() {
    var d = state.astro || {};
    var c = d.chart || {};
    var tst = c.true_solar_time || {};
    $('astroPlanets').innerHTML = (c.planets || []).map(function (pl) {
      return '<div class="astro-card"><div class="astro-sym">' + esc(pl.symbol || '') + '</div>' +
        '<h4>' + esc(pl.name || '') + '</h4>' +
        '<p><strong>' + esc(pl.sign || '—') + ' ' + esc(pl.sign_symbol || '') + '</strong> ' +
        esc(pl.degree == null ? '' : String(pl.degree) + '°') + '</p>' +
        '<p>第 ' + String(pl.house == null ? '—' : pl.house) + ' 宫 · ' + esc(pl.element || '') + '</p>' +
        '<p class="muted">' + esc(pl.role || '') + ' · ' + esc(pl.nature || '') + '</p></div>';
    }).join('') || '<p class="muted">暂无三曜数据。</p>';
    $('astroTst').textContent = (tst.note || '') + (tst.applied ? '（真太阳时校正后）' : '');
    $('astroHouses').innerHTML = (c.houses || []).map(function (h) {
      return '<div class="astro-house"><span>第 ' + String(h.house) + ' 宫</span><strong>' +
        esc(h.sign || '—') + ' ' + esc(h.sign_symbol || '') + '</strong><span class="muted">宫头 ' +
        esc(h.cusp_degree == null ? '—' : String(h.cusp_degree) + '°') + '</span></div>';
    }).join('') || '<p class="muted">暂无宫位数据。</p>';
    $('astroCross').innerHTML = (d.cross || []).map(function (x) {
      return '<article class="card cross-card"><h3>' + esc(x.title || '') + ' · ' + esc(x.tag || '') + '</h3>' +
        '<p>' + esc(x.conclusion || '') + '</p>' +
        '<p class="muted">八字：' + esc(x.bazi_fact || '—') + '；星命：' + esc(x.astro_fact || '—') + '</p></article>';
    }).join('');
    $('astroContent').hidden = false;
  }

  /* ---------- 风水堪舆 ---------- */
  var KY_GRID = [['巽', '离', '坤'], ['震', '中', '兑'], ['艮', '坎', '乾']]; // 南上北下
  function initKanyuDefaults() {
    var now = new Date();
    if (!$('kanyuAnnual').value) $('kanyuAnnual').value = String(now.getFullYear());
  }
  function kanyuResidents() {
    var out = [];
    for (var i = 0; i < 3; i++) {
      var name = ($('kyR' + i + 'Name').value || '').trim();
      var yv = $('kyR' + i + 'Year').value;
      if (!name && !yv) continue;
      if (!yv) continue;
      out.push({ label: name || '住户', birth_year: Number(yv), gender: $('kyR' + i + 'Gender').value });
    }
    return out;
  }
  function loadKanyu() {
    var ori = $('kanyuOrientation').value;
    var deg = $('kanyuDegree').value;
    var year = $('kanyuYear').value;
    var annual = $('kanyuAnnual').value;
    if (!ori && (deg === '' || deg === null)) { showError('请先选坐向预设或填坐山度数。'); return; }
    var q = [];
    if (ori) q.push('orientation=' + encodeURIComponent(ori));
    else q.push('sit_degree=' + encodeURIComponent(deg));
    if (year) q.push('year=' + encodeURIComponent(year));
    if (annual) q.push('annual_year=' + encodeURIComponent(annual));
    var res = kanyuResidents();
    if (res.length) q.push('residents=' + encodeURIComponent(JSON.stringify(res)));
    $('kanyuLoading').hidden = false;
    $('kanyuContent').hidden = true;
    apiGet('/api/fengshui?' + q.join('&')).then(function (d) {
      clearError();
      $('kanyuLoading').hidden = true;
      state.kanyu = d || {};
      renderKanyu();
    }).catch(function (err) {
      $('kanyuLoading').hidden = true;
      showError('堪舆排盘失败：' + err.message);
    });
  }
  function renderKanyu() {
    var d = state.kanyu || {};
    var ch = d.chart || {};
    var meta = [
      ['坐向', (d.sit_mountain || '—') + '山' + (d.face_mountain || '—') + '向（坐' + (d.sit_palace || '—') + '向' + (d.face_palace || '—') + '）'],
      ['元运', String(d.period == null ? '—' : d.period) + '运' + (d.period_range ? '（' + yearStr(d.period_range[0]) + '–' + yearStr(d.period_range[1]) + '）' : '')],
      ['建成/入住年', d.year == null ? '未填' : yearStr(d.year)],
      ['正神', (d.gods && d.gods.zhengshen_palace) || '暂无'], ['零神', (d.gods && d.gods.lingshen_palace) || '暂无'],
      ['宅卦', (d.sit_palace || '—') + '宅 · ' + (d.house_group || '—')]
    ];
    $('kanyuMeta').innerHTML = '<dl class="kv">' + meta.map(function (kv) {
      return '<dt>' + esc(kv[0]) + '</dt><dd>' + esc(kv[1]) + '</dd>';
    }).join('') + '</dl>' +
      ((d.period_range || d.year) ? '' : '<p class="muted">未填建成年份时暂按九运排盘。</p>');
    var starName = { 1: '一白', 2: '二黑', 3: '三碧', 4: '四绿', 5: '五黄', 6: '六白', 7: '七赤', 8: '八白', 9: '九紫' };
    $('kanyuBoard').innerHTML = KY_GRID.map(function (row) {
      return row.map(function (pal) {
        var m = ch.mtn ? ch.mtn[pal] : null;
        var f = ch.face ? ch.face[pal] : null;
        var b = ch.base ? ch.base[pal] : null;
        return '<div class="ky-cell"><div class="qm-head"><strong>' + esc(pal) + '宫</strong></div>' +
          '<div>山星 ' + esc(m == null ? '—' : String(m) + ' ' + (starName[m] || '')) + '</div>' +
          '<div>向星 ' + esc(f == null ? '—' : String(f) + ' ' + (starName[f] || '')) + '</div>' +
          '<div class="muted">运星 ' + esc(b == null ? '—' : String(b)) + '</div></div>';
      }).join('');
    }).join('');
    $('kanyuPattern').innerHTML = '<div class="card"><h3>格局</h3><p>' + esc(d.pattern || '暂无') + '</p></div>';
    $('kanyuCombo').innerHTML = (d.combo_lines || []).length
      ? (d.combo_lines || []).map(function (l) { return '<p>' + esc(l) + '</p>'; }).join('')
      : '<p class="muted">暂无组合断语。</p>';
    var bz = d.bazhai || {};
    $('kanyuBazhai').innerHTML = '<p>四吉方：' + esc((d.four_good_directions || []).join('、') || '暂无') + '</p>' +
      Object.keys(bz).map(function (pal) {
        var b = bz[pal];
        return '<p><strong>' + esc(pal) + '宫</strong> ' + esc(b.star || '暂无') + (b.is_good ? ' · 四吉' : '') + ' — ' + esc(b.role || '') + '</p>';
      }).join('');
    $('kanyuConclusion').innerHTML = (d.conclusion_lines || []).map(function (l) {
      return '<p>' + esc(l) + '</p>';
    }).join('') || '<p class="muted">暂无结论。</p>';
    var res = d.residents || [];
    $('kanyuResidents').innerHTML = res.length ? '<div class="card"><h3>住户命卦</h3>' + res.map(function (r) {
      return '<p>' + esc(r.label || '') + '（' + yearStr(r.birth_year) + '年 · ' + esc(r.gender || '') + '）命卦' +
        esc(r.ming_gua || '—') + ' · ' + esc(r.group || '') + ' · ' + esc(r.verdict || '') + '</p>';
    }).join('') + '</div>' : '';
    $('kanyuEmpty').hidden = true;
    $('kanyuContent').hidden = false;
  }
  function initKanyu() {
    $('kanyuLoad').addEventListener('click', loadKanyu);
  }

  /* ---------- 户型压盘 ---------- */
  function fpParams() {
    var ori = $('fpOrientation').value;
    var deg = $('fpDegree').value;
    if (!ori && (deg === '' || deg === null)) return null;
    var q = [];
    if (ori) q.push('orientation=' + encodeURIComponent(ori));
    else q.push('sit_degree=' + encodeURIComponent(deg));
    q.push('cx=' + String(state.fp.cx));
    q.push('cy=' + String(state.fp.cy));
    return q.join('&');
  }
  function loadFloorplan() {
    var q = fpParams();
    if (!q) { showError('请先选坐向预设或填坐山度数。'); return; }
    apiGet('/api/floorplan?' + q).then(function (d) {
      clearError();
      state.fp.data = d || {};
      renderFloorplan();
    }).catch(function (err) {
      showError('户型压盘失败：' + err.message);
    });
  }
  function initFloorplanDefaults() { /* 首次进入不自动请求，等用户上传/选坐向后点压盘 */ }
  function renderFloorplan() {
    var d = state.fp.data || {};
    var cells = d.cells || [];
    $('fpEmpty').hidden = true;
    $('fpInfo').innerHTML = '<div class="card"><h3>定盘</h3><p>' +
      esc((d.sit_mountain || '') + '山' + (d.face_mountain || '') + '向 · ' + String(d.period == null ? '' : d.period) + '运') +
      (d.orientation_desc ? ' · ' + esc(d.orientation_desc) : '') + '</p><p>' + esc(d.pattern || '') + '</p>' +
      '<p class="muted">中宫：cx ' + String(state.fp.cx.toFixed(2)) + ' · cy ' + String(state.fp.cy.toFixed(2)) +
      '（拖动图中圆点可立极重算）</p></div>';
    var mode = state.fp.mode;
    $('fpCells').innerHTML = '<div class="card"><h3>' + (mode === 'xk' ? '玄空飞星 · 每格直断' : '八宅大游年 · 每格直断') + '</h3>' +
      cells.map(function (c) {
        var body = mode === 'xk'
          ? ('山星 ' + esc(c.mountain_star_name || '') + ' · 向星 ' + esc(c.face_star_name || '') + ' · ' + esc(c.advice_xuankong || ''))
          : (esc(c.younian_star || '暂无') + (c.younian_good ? ' · 四吉' : '') + ' — ' + esc(c.younian_role || '') + ' · ' + esc(c.advice_bazhai || ''));
        return '<p><strong>' + esc(c.palace || '') + '宫（' + esc(c.direction || '') + '）</strong> ' +
          '<span class="qm-pat ' + (c.verdict === '大吉' || c.verdict === '吉' ? 'good' : (c.verdict === '凶' || c.verdict === '大凶' ? 'bad' : '')) + '">' +
          esc(c.verdict_label || c.verdict || '') + '</span><br>' + body +
          (c.combo_note ? '<br>组合：' + esc(c.combo_note) : '') + '</p>';
      }).join('') + '</div>';
    drawFloorplanCanvas();
  }
  function drawFloorplanCanvas() {
    var cv = $('fpCanvas');
    var ctx = cv.getContext('2d');
    var W = cv.width, H = cv.height;
    ctx.clearRect(0, 0, W, H);
    var d = state.fp.data || {};
    var cells = d.cells || [];
    if (state.fp.img) {
      // 户型图按 contain 铺满画布（本地预览，不上传）
      var iw = state.fp.img.width, ih = state.fp.img.height;
      var s = Math.min(W / iw, H / ih);
      var dw = iw * s, dh = ih * s;
      ctx.drawImage(state.fp.img, (W - dw) / 2, (H - dh) / 2, dw, dh);
      ctx.fillStyle = 'rgba(246,241,230,0.55)';
      ctx.fillRect(0, 0, W, H);
    } else {
      ctx.fillStyle = '#F6F1E6';
      ctx.fillRect(0, 0, W, H);
    }
    var verdictFill = { '大吉': 'rgba(154,42,34,0.28)', '吉': 'rgba(46,107,58,0.22)', '平': 'rgba(158,120,47,0.14)', '凶': 'rgba(122,111,94,0.25)', '大凶': 'rgba(60,30,28,0.32)' };
    cells.forEach(function (c) {
      var b = c.bounds || {};
      var x0 = (b.x0 || 0) * W, y0 = (b.y0 || 0) * H;
      var x1 = (b.x1 || 1) * W, y1 = (b.y1 || 1) * H;
      ctx.fillStyle = verdictFill[c.verdict] || 'rgba(158,120,47,0.14)';
      ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
      ctx.strokeStyle = '#9E782F';
      ctx.lineWidth = 2;
      ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
      ctx.fillStyle = '#2B2620';
      ctx.font = 'bold 30px serif';
      ctx.textAlign = 'center';
      var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
      ctx.fillText((c.palace || '') + '宫', cx, cy - 34);
      ctx.font = '24px serif';
      if (c.palace !== '中') { // 中宫中央留给可拖动的立极圆点，不画会被遮住的山/向行
        if (state.fp.mode === 'xk') ctx.fillText('山' + String(c.mountain_star || '') + ' 向' + String(c.face_star || ''), cx, cy);
        else ctx.fillText(String(c.younian_star || '暂无'), cx, cy);
      }
      ctx.font = '22px serif';
      ctx.fillText(String(c.verdict_label || ''), cx, cy + 32);
    });
    // 中宫圆点（可拖动）
    var px = state.fp.cx * W, py = state.fp.cy * H;
    ctx.beginPath();
    ctx.arc(px, py, 22, 0, Math.PI * 2);
    ctx.fillStyle = '#9A2A22';
    ctx.fill();
    ctx.strokeStyle = '#FFF6E8';
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.fillStyle = '#FFF6E8';
    ctx.font = 'bold 22px serif';
    ctx.fillText('中', px, py + 8);
  }
  function initFloorplan() {
    $('fpFile').addEventListener('change', function (ev) {
      var f = ev.target.files && ev.target.files[0];
      if (!f) return;
      var reader = new FileReader();
      reader.onload = function () {
        var img = new Image();
        img.onload = function () {
          state.fp.img = img;
          if (state.fp.data) drawFloorplanCanvas();
          toast('户型图已本地载入（未上传）');
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(f); // 仅本地预览，不发往服务端
    });
    $('fpModeXk').addEventListener('click', function () {
      state.fp.mode = 'xk';
      $('fpModeXk').classList.add('active');
      $('fpModeBz').classList.remove('active');
      if (state.fp.data) renderFloorplan();
    });
    $('fpModeBz').addEventListener('click', function () {
      state.fp.mode = 'bz';
      $('fpModeBz').classList.add('active');
      $('fpModeXk').classList.remove('active');
      if (state.fp.data) renderFloorplan();
    });
    $('fpLoad').addEventListener('click', loadFloorplan);
    var cv = $('fpCanvas');
    function fpPos(ev) {
      var r = cv.getBoundingClientRect();
      var x = (ev.clientX - r.left) / r.width;
      var y = (ev.clientY - r.top) / r.height;
      return { x: Math.min(0.95, Math.max(0.05, x)), y: Math.min(0.95, Math.max(0.05, y)) };
    }
    cv.addEventListener('pointerdown', function (ev) {
      if (!state.fp.data) return;
      var p = fpPos(ev);
      if (Math.abs(p.x - state.fp.cx) < 0.08 && Math.abs(p.y - state.fp.cy) < 0.08) {
        state.fp.dragging = true;
        cv.setPointerCapture(ev.pointerId);
      }
    });
    cv.addEventListener('pointermove', function (ev) {
      if (!state.fp.dragging) return;
      var p = fpPos(ev);
      state.fp.cx = p.x; state.fp.cy = p.y;
      drawFloorplanCanvas();
    });
    cv.addEventListener('pointerup', function () {
      if (!state.fp.dragging) return;
      state.fp.dragging = false;
      loadFloorplan(); // 拖动结束按新中宫重算
    });
  }

  /* ---------- 罗盘实测（G4） ---------- */
  // 只调后端 REST API（/api/compass 磁偏角现算＋二十四山环），不内嵌排盘算法；
  // 传感器取向走 DeviceOrientationEvent，锁定只输出真北坐山度数，带入堪舆／户型压盘
  // 时只填度数输入框（与手动输入同度数走同一条后端路径）。
  var COMPASS_MOUNTAINS = ['子', '癸', '丑', '艮', '寅', '甲', '卯', '乙', '辰', '巽', '巳', '丙', '午', '丁', '未', '坤', '申', '庚', '酉', '辛', '戌', '乾', '亥', '壬'];
  var COMPASS_PALACES = ['坎', '艮', '震', '巽', '离', '坤', '兑', '乾'];
  function compassNorm(deg) { var d = deg % 360; return d < 0 ? d + 360 : d; }
  function compassMountainAt(deg) {
    var ring = (state.compass.info && state.compass.info.ring) || null;
    var idx = Math.floor((compassNorm(deg) + 7.5) / 15) % 24;
    if (ring && ring[idx]) return ring[idx];
    return { name: COMPASS_MOUNTAINS[idx], palace: COMPASS_PALACES[Math.floor((idx * 15 + 22.5) / 45) % 8] };
  }
  // 磁偏角解析（优先级：手动填入 ＞ /api/compass WMM2025 现算）。
  function compassDeclination() {
    var manual = $('compassManualDec').value;
    if (manual !== '' && manual !== null && !isNaN(Number(manual))) return { value: Number(manual), source: 'manual' };
    var info = state.compass.info;
    if (info && info.declination_deg !== null && info.declination_deg !== undefined) return { value: info.declination_deg, source: 'wmm2025' };
    return { value: 0, source: 'none' };
  }
  function compassDisplayHeading() {
    if (state.compass.mode === 'mag') return state.compass.magnetic;
    return state.compass.heading;
  }
  function compassUpdateReadout() {
    var h = compassDisplayHeading();
    var d = compassDeclination();
    if (h >= 0) {
      var m = compassMountainAt(h);
      $('compassReading').textContent = (state.compass.mode === 'mag' ? '磁北 ' : '真北 ') + h.toFixed(1) + '°';
      $('compassMountain').textContent = m.name + '山 · ' + m.palace + '宫';
    } else {
      $('compassReading').textContent = '—';
      $('compassMountain').textContent = '等待传感器…';
    }
    var info = state.compass.info;
    var decText;
    if (d.source === 'manual') decText = '磁偏角 ' + (d.value >= 0 ? '+' : '') + d.value.toFixed(1) + '°（手动填入）';
    else if (d.source === 'wmm2025') decText = '磁偏角 ' + (d.value >= 0 ? '+' : '') + d.value.toFixed(1) + '°（WMM2025 现算）';
    else decText = '磁偏角未知';
    if (info) decText += ' · 坐标 ' + String(info.latitude) + '，' + String(info.longitude);
    $('compassDeclination').textContent = decText;
    drawCompassDial();
  }
  // 传感器事件：iOS Safari 给 webkitCompassHeading（真北）；Android 给
  // deviceorientationabsolute（真北）或 deviceorientation（磁北）；alpha 为逆时针，
  // 罗盘度数顺时针，故取 360−alpha。
  function compassOnOrientation(ev) {
    var heading = null, isTrue = false;
    if (ev && typeof ev.webkitCompassHeading === 'number' && !isNaN(ev.webkitCompassHeading)) {
      heading = ev.webkitCompassHeading;
      isTrue = true;
    } else if (ev && typeof ev.alpha === 'number' && ev.alpha !== null) {
      heading = compassNorm(360 - ev.alpha);
      isTrue = ev.absolute === true;
    }
    if (heading === null || isNaN(heading)) return;
    var d = compassDeclination();
    if (isTrue) {
      state.compass.heading = heading;
      state.compass.magnetic = compassNorm(heading - d.value);
    } else {
      state.compass.magnetic = heading;
      state.compass.heading = compassNorm(heading + d.value);
    }
    $('compassLock').disabled = false;
    $('compassEmpty').hidden = true;
    compassUpdateReadout();
  }
  function compassAttachListeners() {
    if (state.compass.listening) return;
    state.compass.listening = true;
    if ('ondeviceorientationabsolute' in window) {
      window.addEventListener('deviceorientationabsolute', compassOnOrientation);
    } else {
      window.addEventListener('deviceorientation', compassOnOrientation);
    }
  }
  function compassFetchInfo(lat, lon) {
    var q = '';
    if (lat !== undefined && lon !== undefined) q = '?lat=' + encodeURIComponent(lat) + '&lon=' + encodeURIComponent(lon);
    apiGet('/api/compass' + q).then(function (d) {
      state.compass.info = d || null;
      compassUpdateReadout();
    }).catch(function () { /* 磁偏角加载失败不阻塞罗盘，读数仍可用磁北 */ });
  }
  function compassAfterEnable() {
    state.compass.supported = 'granted';
    $('compassStatus').textContent = '传感器已启用：竖屏持握，盘面随手机转动。';
    $('compassEnable').disabled = true;
    // 有定位时按当前位置重算磁偏角（被拒则沿用梁平默认坐标，不阻塞罗盘）。
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(function (pos) {
        compassFetchInfo(pos.coords.latitude, pos.coords.longitude);
      }, function () {}, { timeout: 8000 });
    }
  }
  function compassEnable() {
    var status = $('compassStatus');
    if (typeof DeviceOrientationEvent === 'undefined') {
      state.compass.supported = 'unsupported';
      status.textContent = '当前浏览器不支持方向传感器（DeviceOrientationEvent 不可用），请用手机 Safari / Chrome 打开，或改用 App 罗盘。';
      return;
    }
    if (typeof DeviceOrientationEvent.requestPermission === 'function') {
      // iOS Safari：须用户手势触发 requestPermission。
      DeviceOrientationEvent.requestPermission().then(function (resp) {
        if (resp === 'granted') {
          compassAttachListeners();
          compassAfterEnable();
        } else {
          status.textContent = '已拒绝方向传感器授权：请到 设置 → Safari → 动作与方向 进入允许，或改用 App 罗盘。';
        }
      }).catch(function (err) {
        status.textContent = '请求传感器授权失败：' + err.message;
      });
    } else {
      compassAttachListeners();
      compassAfterEnable();
    }
  }
  function compassLock() {
    var h = state.compass.heading;
    var m = state.compass.magnetic;
    if (h < 0 || m < 0) { showError('尚无罗盘读数，请先启用传感器并等待读数稳定。'); return; }
    var d = compassDeclination();
    var mt = compassMountainAt(h);
    var lock = {
      magnetic: Math.round(m * 10) / 10,
      trueNorth: Math.round(h * 10) / 10,
      declination: d.value,
      declinationSource: d.source,
      mountain: mt.name,
      palace: mt.palace,
      timestamp: new Date().toISOString()
    };
    state.compass.lock = lock;
    try { localStorage.setItem('kanyu-compass-lock', JSON.stringify(lock)); } catch (e) {}
    renderCompassLock();
    toast('已锁定 ' + mt.name + '山（真北 ' + lock.trueNorth.toFixed(1) + '°）');
  }
  function renderCompassLock() {
    var lock = state.compass.lock;
    if (!lock) { $('compassLockInfo').innerHTML = ''; $('compassBringRow').hidden = true; return; }
    var faceIdx = (COMPASS_MOUNTAINS.indexOf(lock.mountain) + 12) % 24;
    var face = COMPASS_MOUNTAINS[faceIdx];
    var src = lock.declinationSource === 'manual' ? '手动填入' : (lock.declinationSource === 'wmm2025' ? 'WMM2025 现算' : '未知');
    $('compassLockInfo').innerHTML = '<div class="card inner"><h3>已锁定</h3><p>真北 ' + esc(lock.trueNorth.toFixed(1)) + '° ' + esc(lock.mountain) + '山 · 磁北 ' + esc(lock.magnetic.toFixed(1)) + '°</p>' +
      '<p>坐向：' + esc(lock.mountain) + '山' + esc(face) + '向 · 磁偏角 ' + esc((lock.declination >= 0 ? '+' : '') + String(lock.declination)) + '°（' + esc(src) + '）</p>' +
      '<p class="muted">锁定时间 ' + esc(String(lock.timestamp).replace('T', ' ').slice(0, 16)) + '（UTC）</p></div>';
    $('compassBringRow').hidden = false;
  }
  function restoreCompassLock() {
    if (state.compass.lock) { renderCompassLock(); return; }
    try {
      var raw = localStorage.getItem('kanyu-compass-lock');
      if (raw) { state.compass.lock = JSON.parse(raw); renderCompassLock(); }
    } catch (e) {}
  }
  function compassToKanyu() {
    var lock = state.compass.lock;
    if (!lock) return;
    $('kanyuOrientation').value = '';
    $('kanyuDegree').value = String(lock.trueNorth);
    location.hash = '#/kanyu';
    toast('已带入堪舆：坐山度数 ' + lock.trueNorth.toFixed(1) + '°，点排盘即可');
  }
  function compassToFloorplan() {
    var lock = state.compass.lock;
    if (!lock) return;
    $('fpOrientation').value = '';
    $('fpDegree').value = String(lock.trueNorth);
    location.hash = '#/floorplan';
    toast('已带入户型压盘：坐山度数 ' + lock.trueNorth.toFixed(1) + '°，点压盘即可');
  }
  function drawCompassDial() {
    var cv = $('compassCanvas');
    if (!cv) return;
    var ctx = cv.getContext('2d');
    var W = cv.width, H = cv.height;
    var cx = W / 2, cy = H / 2, r = W / 2 - 10;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = '#111317';
    ctx.fillRect(0, 0, W, H);
    ctx.strokeStyle = 'rgba(209,172,83,0.55)';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke();
    ctx.strokeStyle = 'rgba(209,172,83,0.25)';
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(cx, cy, r - 46, 0, Math.PI * 2); ctx.stroke();
    var i, a, isLong, r1;
    for (i = 0; i < 72; i++) {
      a = i * 5 * Math.PI / 180;
      isLong = i % 3 === 0;
      r1 = r - (isLong ? 14 : 8);
      ctx.strokeStyle = isLong ? 'rgba(209,172,83,0.9)' : 'rgba(209,172,83,0.35)';
      ctx.lineWidth = isLong ? 2 : 1;
      ctx.beginPath();
      ctx.moveTo(cx + r * Math.sin(a), cy - r * Math.cos(a));
      ctx.lineTo(cx + r1 * Math.sin(a), cy - r1 * Math.cos(a));
      ctx.stroke();
    }
    var heading = compassDisplayHeading();
    var base = heading >= 0 ? heading : 0;
    var ring = (state.compass.info && state.compass.info.ring) || null;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (i = 0; i < 24; i++) {
      a = (i * 15 - base) * Math.PI / 180;
      ctx.fillStyle = i === 0 ? '#E05A47' : '#D1AC53';
      ctx.font = 'bold 15px serif';
      ctx.fillText(ring && ring[i] ? ring[i].name : COMPASS_MOUNTAINS[i], cx + (r - 34) * Math.sin(a), cy - (r - 34) * Math.cos(a));
    }
    for (i = 0; i < 8; i++) {
      a = (i * 45 - base) * Math.PI / 180;
      ctx.fillStyle = i === 0 ? '#E05A47' : '#EDE8DC';
      ctx.font = i % 2 === 0 ? 'bold 18px serif' : '16px serif';
      ctx.fillText(COMPASS_PALACES[i], cx + (r - 82) * Math.sin(a), cy - (r - 82) * Math.cos(a));
    }
    // 定盘针：金针指前＋朱砂尾点＋金芯
    ctx.fillStyle = '#D1AC53';
    ctx.beginPath();
    ctx.moveTo(cx, cy - 40);
    ctx.lineTo(cx - 8, cy - 26);
    ctx.lineTo(cx + 8, cy - 26);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#E05A47';
    ctx.beginPath(); ctx.arc(cx, cy + 24, 4, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#D1AC53';
    ctx.beginPath(); ctx.arc(cx, cy, 5, 0, Math.PI * 2); ctx.fill();
  }
  function initCompassDefaults() {
    if (!state.compass.info) compassFetchInfo();
    else compassUpdateReadout();
    restoreCompassLock();
  }
  function initCompass() {
    $('compassEnable').addEventListener('click', compassEnable);
    $('compassLock').addEventListener('click', compassLock);
    $('compassModeTrue').addEventListener('click', function () {
      state.compass.mode = 'true';
      $('compassModeTrue').classList.add('active');
      $('compassModeMag').classList.remove('active');
      compassUpdateReadout();
    });
    $('compassModeMag').addEventListener('click', function () {
      state.compass.mode = 'mag';
      $('compassModeMag').classList.add('active');
      $('compassModeTrue').classList.remove('active');
      compassUpdateReadout();
    });
    $('compassManualDec').addEventListener('input', compassUpdateReadout);
    $('compassToKanyu').addEventListener('click', compassToKanyu);
    $('compassToFloorplan').addEventListener('click', compassToFloorplan);
    $('compassClearLock').addEventListener('click', function () {
      state.compass.lock = null;
      try { localStorage.removeItem('kanyu-compass-lock'); } catch (e) {}
      renderCompassLock();
    });
    if (typeof DeviceOrientationEvent === 'undefined') {
      $('compassStatus').textContent = '当前浏览器不支持方向传感器（DeviceOrientationEvent 不可用），请用手机 Safari / Chrome 打开，或改用 App 罗盘。';
      $('compassEnable').disabled = true;
    }
    restoreCompassLock();
    drawCompassDial();
  }

  /* ---------- 详批 + 验真 ---------- */
  function loadVerifyMarks() {
    return apiGet('/api/verify').then(function (d) {
      state.verifyMarks = (d && d.marks) || {};
      state.verifyCount = (d && d.count != null) ? d.count : Object.keys(state.verifyMarks).filter(function (k) { return state.verifyMarks[k]; }).length;
      updateVerifyBadge();
    }).catch(function () { /* 验真标记加载失败不阻塞详批 */ });
  }
  function updateVerifyBadge() {
    $('verifyBadge').textContent = '已验准 ' + String(state.verifyCount) + ' 条';
  }
  function markVerify(title, verified) {
    fetch(API + '/api/verify', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify({ title: title, verified: verified })
    }).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + String(res.status));
      return res.json();
    }).then(function () {
      state.verifyMarks[title] = verified;
      state.verifyCount = Object.keys(state.verifyMarks).filter(function (k) { return state.verifyMarks[k]; }).length;
      updateVerifyBadge();
      toast(verified ? '已标记为已验准' : '已标记为待核验');
      renderInterpretCards();
    }).catch(function (err) { showError('验真打标失败：' + err.message); });
  }
  function interpretCardHtml(item) {
    var verified = !!state.verifyMarks[item.title];
    var facts = (Array.isArray(item.facts) ? item.facts : (item.facts ? [item.facts] : [])).map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('');
    return '<article class="card interpret-card"><h3>' + esc(item.title || '') + '</h3>' +
      '<p>' + esc(item.conclusion || '') + '</p>' +
      '<div class="src"><p>盘面事实：</p><ul>' + (facts || '<li>—</li>') + '</ul>' +
      '<p>五典出处：' + esc(item.source || '—') + '</p></div>' +
      '<div class="verify-row">' +
      '<button type="button" class="btn' + (verified ? ' verified' : '') + '" data-verify="true" data-title="' + esc(item.title || '') + '">已验准</button>' +
      '<button type="button" class="btn pending" data-verify="false" data-title="' + esc(item.title || '') + '">待核验</button>' +
      '<span class="muted">' + (verified ? '当前状态：已验准' : '当前状态：待核验') + '</span></div></article>';
  }
  function renderInterpretCards() {
    var items = (state.interpret && state.interpret.items) || [];
    if (!items.length) return;
    var html = items.map(interpretCardHtml).join('');
    $('xiangpiList').innerHTML = html;
    $('rightList').innerHTML = html;
    document.querySelectorAll('[data-verify]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        markVerify(btn.getAttribute('data-title'), btn.getAttribute('data-verify') === 'true');
      });
    });
  }
  function loadInterpret() {
    var p = currentPerson();
    if (!p) { $('xiangpiList').innerHTML = '<p class="muted">请先选择命主。</p>'; return; }
    $('xiangpiLoading').hidden = false;
    apiGet('/api/interpret?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      clearError();
      state.interpret = d || {};
      $('xiangpiLoading').hidden = true;
      renderInterpretCards();
      if (!((d.items || []).length)) $('xiangpiList').innerHTML = '<p class="muted">后端未返回详批条目。</p>';
    }).catch(function (err) {
      $('xiangpiLoading').hidden = true;
      $('xiangpiList').innerHTML = '<p class="muted">详批加载失败：' + esc(err.message) + '</p>';
      showError('详批加载失败：' + err.message);
    });
  }
  function loadInterpretRight() {
    var p = currentPerson();
    if (!p) { $('rightList').innerHTML = '<p class="muted">请选择命主后查看详批条目。</p>'; return; }
    if (state.interpret && state.interpret.items) { renderInterpretCards(); return; }
    $('rightLoading').hidden = false;
    apiGet('/api/interpret?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      state.interpret = d || {};
      $('rightLoading').hidden = true;
      renderInterpretCards();
    }).catch(function () {
      $('rightLoading').hidden = true;
      $('rightList').innerHTML = '<p class="muted">详批加载失败，请稍后重试。</p>';
    });
  }

  /* ---------- 海报 ---------- */
  function posterUrl() {
    var p = currentPerson();
    if (!p) return '';
    return '/api/poster?person_id=' + encodeURIComponent(p.id) + '&style=' + encodeURIComponent(state.posterStyle);
  }
  function updatePoster() {
    var p = currentPerson();
    var img = $('posterImg');
    var url = posterUrl();
    if (!p) {
      img.hidden = true; $('posterEmpty').hidden = false;
      $('posterDownload').setAttribute('href', '#');
      return;
    }
    $('posterEmpty').hidden = true;
    img.hidden = false;
    img.src = url;
    img.onerror = function () { showError('海报加载失败：请确认后端 /api/poster 可用。'); };
    $('posterDownload').setAttribute('href', url);
    $('posterDownload').setAttribute('download', 'poster-' + String(state.posterStyle) + '.png');
  }
  function initPoster() {
    document.querySelectorAll('.style-btn[data-style]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        document.querySelectorAll('.style-btn[data-style]').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        state.posterStyle = btn.getAttribute('data-style');
        updatePoster();
      });
    });
    $('posterNewTab').addEventListener('click', function () {
      var url = posterUrl();
      if (url) window.open(url, '_blank');
    });
  }

  /* ---------- 海报编辑器（G13：canvas 编辑，复用 /api/poster，不新增第三方请求） ---------- */
  /* 画布色值与字体均取 AGENTS.md §1–§2 定版令牌：--bg #F6F1E6、--gold #9E782F、
     --muted #7A6F5E、强调色四档 --red #9A2A22／--teal #1F4959／--gold #9E782F／--ink #2B2620，
     字体栈 "Songti SC","Noto Serif CJK SC","STSong",serif。 */
  var editorState = { style: 'qingdai', accent: '#9A2A22' };
  function updateEditorPerson() {
    var p = currentPerson();
    $('editorPerson').textContent = p ? ('当前命主：' + personLabel(p)) : '未选择命主';
  }
  function initPosterEditor() {
    document.querySelectorAll('[data-estyle]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        document.querySelectorAll('[data-estyle]').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        editorState.style = btn.getAttribute('data-estyle');
      });
    });
    document.querySelectorAll('[data-accent]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        document.querySelectorAll('[data-accent]').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        editorState.accent = btn.getAttribute('data-accent');
      });
    });
    $('editorRender').addEventListener('click', function () {
      var p = currentPerson();
      if (!p) { showError('请先在左侧档案库选择一位命主。'); return; }
      var url = '/api/poster?person_id=' + encodeURIComponent(p.id) + '&style=' + encodeURIComponent(editorState.style);
      var img = new Image();
      img.onload = function () {
        var band = 170;
        var cv = $('editorCanvas');
        var imgH = Math.round(img.height * 1080 / img.width);
        cv.width = 1080;
        cv.height = imgH + band;
        var ctx = cv.getContext('2d');
        ctx.fillStyle = '#F6F1E6';
        ctx.fillRect(0, 0, cv.width, cv.height);
        ctx.drawImage(img, 0, 0, 1080, imgH);
        var title = ($('editorTitle').value || '').trim() || p.name || '';
        var subtitle = ($('editorSubtitle').value || '').trim() || '三术合参 · 堪舆命理院 谨制';
        ctx.fillStyle = '#9E782F';
        ctx.fillRect(120, imgH + 28, 1080 - 240, 2);
        ctx.fillStyle = editorState.accent;
        ctx.textAlign = 'center';
        ctx.font = 'bold 64px "Songti SC","Noto Serif CJK SC","STSong",serif';
        ctx.fillText(title, 540, imgH + 108);
        ctx.font = '34px "Songti SC","Noto Serif CJK SC","STSong",serif';
        ctx.fillStyle = '#7A6F5E';
        ctx.fillText(subtitle, 540, imgH + 152);
        cv.hidden = false;
        $('editorEmpty').hidden = true;
        $('editorDownload').setAttribute('href', cv.toDataURL('image/png'));
        $('editorDownload').setAttribute('download', 'poster-editor-' + editorState.style + '.png');
      };
      img.onerror = function () { showError('海报加载失败：请确认后端 /api/poster 可用。'); };
      img.src = url;
    });
  }

  /* ---------- 择吉 ---------- */
  function defaultMonth() {
    var now = new Date();
    var m = now.getMonth() + 1;
    return String(now.getFullYear()) + '-' + (m < 10 ? '0' + String(m) : String(m));
  }
  function loadZeji() {
    var p = currentPerson();
    var month = $('zejiMonth').value || defaultMonth();
    state.zejiMonth = month;
    if (!p) { $('zejiGrid').innerHTML = '<p class="muted">请先选择命主。</p>'; return; }
    $('zejiLoading').hidden = false;
    apiGet('/api/zeji?person_id=' + encodeURIComponent(p.id) + '&month=' + encodeURIComponent(month))
      .then(function (days) {
        clearError();
        state.zejiDays = Array.isArray(days) ? days : [];
        $('zejiLoading').hidden = true;
        renderZejiGrid(month);
      })
      .catch(function (err) {
        $('zejiLoading').hidden = true;
        $('zejiGrid').innerHTML = '<p class="muted">择吉加载失败：' + esc(err.message) + '</p>';
        showError('择吉加载失败：' + err.message);
      });
  }
  function renderZejiGrid(month) {
    var parts = month.split('-');
    var y = parseInt(parts[0], 10);
    var m = parseInt(parts[1], 10);
    var first = new Date(y, m - 1, 1);
    var daysInMonth = new Date(y, m, 0).getDate();
    var startWeek = first.getDay(); // 0=周日
    var byDate = {};
    state.zejiDays.forEach(function (d) { byDate[d.date] = d; });
    var html = ['日', '一', '二', '三', '四', '五', '六'].map(function (w) {
      return '<div class="cal-head">' + w + '</div>';
    }).join('');
    for (var i = 0; i < startWeek; i++) html += '<div class="cal-day empty"></div>';
    for (var day = 1; day <= daysInMonth; day++) {
      var ds = month + '-' + (day < 10 ? '0' + String(day) : String(day));
      var info = byDate[ds];
      var clash = info && info.clash;
      var special = info && info.isSpecial;
      html += '<button type="button" class="cal-day' + (clash ? ' clash' : '') + (special ? ' special' : '') + '" data-date="' + ds + '">' +
        '<span class="d">' + String(day) + '</span>' +
        '<span class="gz">' + esc(info ? (info.ganzhi || '') : '') + '</span>' +
        (special ? '<span class="badge">大吉日</span>' : '') +
        (clash ? '<span class="gz">' + esc(info.reason || '冲克') + '</span>' : '') +
        '</button>';
    }
    $('zejiGrid').innerHTML = html;
    $('zejiGrid').querySelectorAll('.cal-day[data-date]').forEach(function (el) {
      el.addEventListener('click', function () { showZejiDay(el.getAttribute('data-date')); });
    });
  }
  function showZejiDay(date) {
    var info = null;
    state.zejiDays.forEach(function (d) { if (d.date === date) info = d; });
    $('zejiDay').hidden = false;
    $('zejiDayTitle').textContent = date + ' · 当日宜忌';
    $('zejiDayBody').innerHTML = '<p class="muted">加载当日黄历中…</p>';
    apiGet('/api/almanac?date=' + encodeURIComponent(date)).then(function (a) {
      clearError();
      var hoursHtml = '';
      var hours = (info && info.hours) || [];
      if (hours.length) {
        hoursHtml = '<h4>逐时辰</h4><table class="hours-table"><thead><tr><th>时辰</th><th>干支</th><th>吉凶</th><th>宜</th><th>忌</th></tr></thead><tbody>' +
          hours.map(function (h) {
            return '<tr><td>' + esc(h['时辰'] || '') + '</td><td>' + esc(h['时辰干支'] || '') + '</td>' +
              '<td>' + esc(h['吉凶'] || '') + '</td><td>' + esc((h['宜'] || []).join('、') || '—') + '</td>' +
              '<td>' + esc((h['忌'] || []).join('、') || '—') + '</td></tr>';
          }).join('') + '</tbody></table>';
      } else {
        hoursHtml = '<p class="muted">逐时辰：暂无</p>';
      }
      $('zejiDayBody').innerHTML =
        '<p>干支：' + esc(a.ganzhi || (info && info.ganzhi) || '—') + ' · 节气：' + esc(a.jieqi || '—') + '</p>' +
        '<p>宜：' + esc((a.yi || []).join('、') || '—') + '</p>' +
        '<p>忌：' + esc((a.ji || []).join('、') || '—') + '</p>' +
        (info ? '<p>' + (info.isSpecial ? '专属大吉日：' : '') + esc(info.reason || '') + (info.clash ? ' · 冲克：' + esc(info.clash) : '') + '</p>' : '') +
        hoursHtml;
    }).catch(function (err) {
      $('zejiDayBody').innerHTML = '<p class="muted">当日黄历加载失败：' + esc(err.message) + '</p>' +
        (info ? '<p>干支：' + esc(info.ganzhi || '—') + ' · ' + esc(info.reason || '') + '</p>' : '');
    });
  }
  function initZeji() {
    $('zejiMonth').value = defaultMonth();
    $('zejiLoad').addEventListener('click', loadZeji);
  }

  /* ---------- G8：五运六气年份按钮 ---------- */
  function initYunqi() {
    $('yunqiYear').value = String(new Date().getFullYear());
    $('yunqiLoad').addEventListener('click', function () {
      state.yunqi = null;
      state.yunqiYear = null;
      loadYunqi();
    });
  }

  /* ---------- G5：六爻／梅花起卦按钮 ---------- */
  function initDivination() {
    initDivinationDefaults();
    $('divCast').addEventListener('click', function () { castDivination(true); });
    $('divPreview').addEventListener('click', function () { castDivination(false); });
  }

  /* ---------- 备份 ---------- */
  function initBackup() {
    $('restoreBtn').addEventListener('click', function () {
      var file = $('restoreFile').files && $('restoreFile').files[0];
      if (!file) { $('restoreMsg').textContent = '请先选择 zip 备份文件。'; return; }
      var fd = new FormData();
      fd.append('file', file);
      $('restoreMsg').textContent = '恢复中…';
      fetch(API + '/api/backup/restore', { method: 'POST', body: fd, credentials: 'same-origin' })
        .then(function (res) {
          if (!res.ok) throw new Error('HTTP ' + String(res.status));
          return res.json();
        })
        .then(function (d) {
          var r = (d && d.restored) || {};
          var count = r.people != null ? String(r.people) : (r.count != null ? String(r.count) : '—');
          $('restoreMsg').textContent = '恢复成功，恢复人物 ' + count + ' 条。';
          toast('备份已恢复');
          loadPeople().then(function () { setCurrent(state.currentId, true); });
        })
        .catch(function (err) {
          $('restoreMsg').textContent = '恢复失败：' + err.message;
          showError('备份恢复失败：' + err.message);
        });
    });
  }

  /* ---------- G2：合盘 / 论财 / 名人库 / 图书馆 / 手相面相 ---------- */
  function cardHtml(c) {
    return '<article class="card interpret-card"><h3>' + esc(c.title || '') + '</h3><p>' + esc(c.conclusion || '') + '</p>' +
      '<div class="src"><p>盘面事实：' + esc(c.facts || '—') + '</p><p>出处：' + esc(c.source || '—') + '</p></div></article>';
  }
  function personOptions(sel, selectedId) {
    sel.innerHTML = state.people.map(function (p) {
      return '<option value="' + esc(p.id) + '"' + (String(p.id) === String(selectedId) ? ' selected' : '') + '>' + esc(p.name) + '</option>';
    }).join('');
  }
  function doHepan(a, b) {
    clearError();
    $('hepanLoading').hidden = false;
    $('hepanContent').hidden = true;
    $('hepanShare').hidden = true;
    apiGet('/api/hepan?person_a=' + encodeURIComponent(a) + '&person_b=' + encodeURIComponent(b)).then(function (d) {
      $('hepanLoading').hidden = true;
      var html = '<div class="card"><h3>' + esc(d.a.name) + ' × ' + esc(d.b.name) + '</h3><p>' +
        esc(d.a.name) + '日柱 ' + esc(d.a.day_pillar) + ' · ' + esc(d.a.level) + '，喜 ' + esc((d.a.xi || []).join('、') || '流通') +
        '；' + esc(d.b.name) + '日柱 ' + esc(d.b.day_pillar) + ' · ' + esc(d.b.level) + '，喜 ' + esc((d.b.xi || []).join('、') || '流通') + '</p></div>' +
        (d.cards || []).map(cardHtml).join('') +
        '<p class="hint">' + esc(d.zodiac_note || '') + '</p><p class="hint">' + esc(d.method || '') + '</p>';
      $('hepanContent').innerHTML = html;
      $('hepanContent').hidden = false;
      loadShareCard(a, b);
    }).catch(function (err) {
      $('hepanLoading').hidden = true;
      showError('合盘加载失败：' + err.message);
    });
  }
  function maybeAutoHepan() {
    var pair = hashQuery().pair;
    if (!pair) return;
    var ids = pair.split(',');
    if (ids.length !== 2 || !ids[0] || !ids[1]) { showError('分享链接格式不对：pair 须为两位人物 id，以逗号分隔'); return; }
    if (ids[0] === ids[1]) { showError('分享链接指向同一人，无法合盘'); return; }
    var have = state.people.map(function (p) { return String(p.id); });
    if (have.indexOf(ids[0]) === -1 || have.indexOf(ids[1]) === -1) {
      $('hepanContent').hidden = false;
      $('hepanContent').innerHTML = '<div class="card"><h3>分享链接指向的人物不在当前档案库</h3><p>该合盘链接的两人不在当前登录账号（或游客会话）的档案里，可能是另一账号的档案，或档案已被删除。请登录对应账号，或先在左侧「新建档案」建好两人档案，再打开链接。</p></div>';
      return;
    }
    if ($('hepanLoad').dataset.autopair === pair) return;
    $('hepanLoad').dataset.autopair = pair;
    $('hepanA').value = ids[0];
    $('hepanB').value = ids[1];
    doHepan(ids[0], ids[1]);
  }
  function loadHepan() {
    personOptions($('hepanA'), state.people[0] && state.people[0].id);
    personOptions($('hepanB'), state.people[1] && state.people[1].id);
    $('hepanEmpty').hidden = state.people.length >= 2;
    if ($('hepanLoad').dataset.bound) { maybeAutoHepan(); return; }
    $('hepanLoad').dataset.bound = '1';
    $('hepanLoad').addEventListener('click', function () {
      var a = $('hepanA').value, b = $('hepanB').value;
      if (!a || !b || a === b) { showError('合盘须选两位不同人物'); return; }
      doHepan(a, b);
    });
    maybeAutoHepan();
  }
  /* ---------- G10：合盘分享卡片（双盘速览＋总评一句＋二维码回链） ---------- */
  function drawShareQr(url) {
    var cv = $('shareQr');
    if (!cv) return;
    if (typeof qrcode === 'undefined') {
      $('shareQrWrap').innerHTML = '<p class="hint">二维码库未加载（qrcode.min.js 缺失），请用上方链接直接分享。</p>';
      return;
    }
    try {
      var qr = qrcode(0, 'M');
      qr.addData(url);
      qr.make();
      var ctx = cv.getContext('2d');
      var n = qr.getModuleCount();
      var quiet = 2;
      var total = n + quiet * 2;
      var cell = Math.floor(220 / total);
      var size = cell * total;
      var off = Math.floor((220 - size) / 2);
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, 220, 220);
      ctx.fillStyle = '#000000';
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          if (qr.isDark(r, c)) ctx.fillRect(off + (c + quiet) * cell, off + (r + quiet) * cell, cell, cell);
        }
      }
    } catch (e) {
      $('shareQrWrap').innerHTML = '<p class="hint">二维码生成失败：' + esc(e.message) + '，请用上方链接直接分享。</p>';
    }
  }
  function loadShareCard(a, b) {
    apiGet('/api/share-card?person_a=' + encodeURIComponent(a) + '&person_b=' + encodeURIComponent(b)).then(function (d) {
      var box = $('hepanShare');
      var html = '<div class="card"><h3>合盘分享卡片</h3>' +
        '<p><strong>' + esc(d.a.name) + '</strong>　' + esc(d.a.pillars_line) + ' · ' + esc(d.a.verdict) + '</p>' +
        '<p><strong>' + esc(d.b.name) + '</strong>　' + esc(d.b.pillars_line) + ' · ' + esc(d.b.verdict) + '</p>' +
        '<p>总评一句（只报计数事实）：' + esc(d.summary_line) + '</p>' +
        '<p>分享链接：<a id="shareLink" href="' + esc(d.share_url) + '">' + esc(d.share_url) + '</a></p>' +
        '<p><button type="button" class="btn" id="shareCopy">复制分享链接</button> <span id="shareCopyMsg"></span></p>' +
        '<div id="shareQrWrap"><canvas id="shareQr" width="220" height="220"></canvas>' +
        '<p class="hint">二维码由浏览器本地生成（qrcode-generator MIT），扫码即打开该合盘。</p></div>' +
        '<p class="hint">' + esc(d.method || '') + '</p></div>';
      box.innerHTML = html;
      box.hidden = false;
      drawShareQr(d.share_url);
      $('shareCopy').addEventListener('click', function () {
        var done = function () { $('shareCopyMsg').textContent = '已复制'; };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(d.share_url).then(done, function () { $('shareCopyMsg').textContent = '复制失败，请长按链接手动复制'; });
        } else {
          $('shareCopyMsg').textContent = '浏览器不支持一键复制，请长按链接手动复制';
        }
      });
    }).catch(function (err) {
      $('hepanShare').hidden = true;
      showError('分享卡片加载失败：' + err.message);
    });
  }
  /* ---------- Insight 第 2 批 G9：报告中心 ---------- */
  var reportsBound = false;
  function loadReports() {
    if (!reportsBound) {
      reportsBound = true;
      $('reportsScopeAll').addEventListener('click', function () {
        state.reportScope = 'all'; state.reports = null; loadReports();
      });
      $('reportsScopePerson').addEventListener('click', function () {
        if (!currentPerson()) { showError('请先在左侧档案库选择一位命主'); return; }
        state.reportScope = 'person'; state.reports = null; loadReports();
      });
      $('reportsReload').addEventListener('click', function () {
        state.reports = null; loadReports();
      });
    }
    var scope = state.reportScope || 'all'; // 'all' 全部 / 'person' 仅看此人
    var pid = (scope === 'person' && state.currentId) ? state.currentId : null;
    var url = '/api/reports' + (pid ? '?person_id=' + encodeURIComponent(pid) : '');
    $('reportsLoading').hidden = false;
    $('reportsContent').hidden = true;
    apiGet(url).then(function (d) {
      $('reportsLoading').hidden = true;
      state.reports = d;
      var html = '';
      if (!d.persons || d.persons.length === 0) {
        html = '<div class="card"><p>还没有人物档案，请先在左侧档案库新建。</p></div>';
      } else {
        d.persons.forEach(function (g) {
          html += '<article class="card"><h3>' + esc(g.person.name || '未命名') + ' · 共 ' +
            String(g.entries.length) + ' 份</h3>';
          if (g.tier_summary) html += '<p class="hint">' + esc(g.tier_summary) + '</p>';
          if (g.error) html += '<p class="hint">命书现算失败：' + esc(g.error) + '（海报与前瞻照常列出）</p>';
          g.entries.forEach(function (e) {
            html += '<div class="report-entry"><div><span class="report-kind">' + esc(e.kind) + '</span>';
            if (e.tier) html += ' <span class="tier-chip">' + esc(e.tier) + '</span>';
            if (e.hash_short) html += ' <span class="hash-code">哈希 ' + esc(e.hash_short) + '</span>';
            html += '<p class="hint">' + (e.generated_at ? esc(e.generated_at) : '未落盘 · 按需生成') +
              (e.text ? ' · ' + esc(e.text) : '') + '</p></div>';
            if (e.url) html += '<a class="btn" href="' + esc(e.url) + '" target="_blank" rel="noopener">' +
              (e.kind === '命书 PDF' ? '下载 PDF' : '打开海报') + '</a>';
            html += '</div>';
          });
          html += '</article>';
        });
      }
      $('reportsContent').innerHTML = html;
      $('reportsContent').hidden = false;
      $('reportsEmpty').hidden = true;
      $('reportsPerson').textContent = pid ? personLabel(currentPerson()) : '全部人物';
    }).catch(function (err) {
      $('reportsLoading').hidden = true;
      showError('报告中心加载失败：' + err.message);
    });
  }
  /* ---------- G10：全家盘 ---------- */
  function familyOptions(sel) {
    sel.innerHTML = '<option value="">未选</option>' + state.people.map(function (p) {
      return '<option value="' + esc(p.id) + '">' + esc(p.name) + '</option>';
    }).join('');
  }
  function loadFamily() {
    familyOptions($('familyA'));
    familyOptions($('familyB'));
    familyOptions($('familyC'));
    $('familyEmpty').hidden = state.people.length >= 3;
    if ($('familyLoad').dataset.bound) return;
    $('familyLoad').dataset.bound = '1';
    $('familyLoad').addEventListener('click', function () {
      var ids = [$('familyA').value, $('familyB').value, $('familyC').value];
      if (!ids[0] || !ids[1] || !ids[2]) { showError('全家盘须选三人'); return; }
      if (ids[0] === ids[1] || ids[0] === ids[2] || ids[1] === ids[2]) { showError('全家盘须选三位不同人物'); return; }
      clearError();
      $('familyLoading').hidden = false;
      $('familyContent').hidden = true;
      $('familyPosterLink').hidden = true;
      apiGet('/api/family?person_ids=' + ids.map(encodeURIComponent).join(',')).then(function (d) {
        $('familyLoading').hidden = true;
        var html = '<p class="hint">' + esc(d.method || '') + '</p>';
        html += d.members.map(function (m) {
          return '<article class="card interpret-card"><h3>' + esc(m.person.name) + ' · 四柱 ' + esc(m.pillars_line) + '</h3>' +
            '<p>' + esc(m.verdict) + '</p>' +
            '<p>' + esc(String(m.yearly.year)) + '年 ' + esc(m.yearly.ganzhi) + '年 · ' + esc(m.yearly.dayun) + '：' + esc(m.yearly.verdict) + '</p></article>';
        }).join('');
        html += '<div class="card"><h3>三对互补计数</h3><p>' + esc(d.pair_summary.text) + '</p></div>';
        html += d.pairs.map(function (pr) {
          return '<article class="card interpret-card"><h3>' + esc(pr.a_name) + ' × ' + esc(pr.b_name) + ' · 喜用互补</h3><p>' + esc(pr.hepan.cards[0].conclusion) + '</p><p>' + esc(pr.hepan.cards[1].conclusion) + '</p></article>';
        }).join('');
        html += (d.cross_cards || []).map(function (c) {
          return '<article class="card interpret-card"><h3>' + esc(c.dim) + ' · 全家交叉裁决</h3><p>' + esc(c.verdict) + '</p><div class="src"><p>' + esc(c.facts) + '</p><p>出处：' + esc(c.source) + '</p></div></article>';
        }).join('');
        $('familyContent').innerHTML = html;
        $('familyContent').hidden = false;
        var pl = $('familyPosterLink');
        pl.href = '/api/family/poster?person_ids=' + ids.map(encodeURIComponent).join(',');
        pl.hidden = false;
      }).catch(function (err) {
        $('familyLoading').hidden = true;
        showError('全家盘加载失败：' + err.message);
      });
    });
  }
  function loadLuncai() {
    var p = currentPerson();
    $('luncaiEmpty').hidden = !!p;
    $('luncaiContent').hidden = true;
    if (!p) return;
    if (state.luncai) { renderLuncai(); return; }
    $('luncaiLoading').hidden = false;
    apiGet('/api/luncai?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      $('luncaiLoading').hidden = true;
      state.luncai = d || {};
      renderLuncai();
    }).catch(function (err) {
      $('luncaiLoading').hidden = true;
      showError('论财加载失败：' + err.message);
    });
  }
  function renderLuncai() {
    var d = state.luncai || {};
    var f = d.facts || {};
    var subj = d.subject || {};
    var pohao = (f.po_hao_years || []).map(function (x) {
      return yearStr(x.year) + '年' + esc(x.ganzhi) + '（' + esc((x.reasons || []).join('、')) + '）';
    }).join('；');
    var dayun = (d.dayun_wealth || []).map(function (x) {
      return '<tr><td>' + esc(x.ganzhi) + '</td><td>' + yearStr(x.start_year) + '起</td><td>' + esc(x.stem_shishen) + '</td><td>' +
        (x.is_caiyun ? '财星运' : '—') + '</td><td>' + esc(x.mark) + '</td></tr>';
    }).join('');
    $('luncaiContent').innerHTML =
      '<div class="card"><h3>财星与财库（实算事实）</h3><p>日主 ' + esc(subj.day_master || '') + ' · ' +
      esc(subj.level || '') + ' · 财星合计 ' + String(f.cai_count === undefined ? '—' : f.cai_count) +
      ' 处 · 食伤 ' + String(f.shi_count === undefined ? '—' : f.shi_count) + ' 处 · 比劫 ' +
      String(f.bijie_count === undefined ? '—' : f.bijie_count) + ' 处</p><p>财库在 ' + esc(f.ku_branch || '—') +
      '支，盘里见 ' + String(f.ku_count === undefined ? '—' : f.ku_count) + ' 处；财根气：' + esc(f.cai_root || '—') +
      '；财气通门户：' + (f.tong_men ? '达成' : '未成') + '</p>' +
      (pohao ? '<p>破耗年份预警：' + pohao + '——这些年份钱财进出大，忌借贷担保与冲动置产。</p>' : '<p>近 12 年无破耗年份预警。</p>') + '</div>' +
      (d.items || []).map(cardHtml).join('') +
      '<div class="card"><h3>大运财运（逐运运干十神＋喜忌称重）</h3><table class="kv"><thead><tr><th>大运</th><th>起年</th><th>运干十神</th><th>财星运</th><th>喜忌</th></tr></thead><tbody>' +
      dayun + '</tbody></table></div>' +
      '<p class="hint">' + esc(d.method || '') + '</p>';
    $('luncaiContent').hidden = false;
  }
  /* ---------- G8：称骨独立工具 ---------- */
  function loadChenggu() {
    var p = currentPerson();
    $('chengguEmpty').hidden = !!p;
    $('chengguContent').hidden = true;
    if (!p) return;
    if (state.chenggu) { renderChenggu(); return; }
    $('chengguLoading').hidden = false;
    apiGet('/api/chenggu?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      $('chengguLoading').hidden = true;
      state.chenggu = d || {};
      renderChenggu();
    }).catch(function (err) {
      $('chengguLoading').hidden = true;
      showError('称骨加载失败：' + err.message);
    });
  }
  function renderChenggu() {
    var d = state.chenggu || {};
    var rows = (d.breakdown || []).map(function (b) {
      return '<tr><td>' + esc(b.part) + '</td><td>' + esc(b.key) + '</td><td>' + esc(b.text) + '</td></tr>';
    }).join('');
    var verse = (d.verse || []).map(function (line) {
      return '<p>' + esc(line) + '，</p>';
    }).join('');
    $('chengguContent').innerHTML =
      '<div class="card"><p><strong>' + esc(d.disclaimer || '') + '</strong></p>' +
      '<table class="kv"><thead><tr><th>四重</th><th>干支／农历</th><th>称重</th></tr></thead><tbody>' + rows + '</tbody></table>' +
      '<p>总骨重：<strong>' + esc(d.total_text || '—') + '</strong>' +
      (d.title ? ' · ' + esc(d.title) : '') + '</p>' +
      (d.reachable_note ? '<p class="muted">' + esc(d.reachable_note) + '</p>' : '') +
      '</div>' +
      '<div class="card"><h3>称骨歌诀（' + esc(d.total_text || '') + '）</h3>' + verse +
      '<p class="hint">' + esc(d.source || '') + '</p></div>';
    $('chengguContent').hidden = false;
  }

  /* ---------- Insight 第 2 批 G6：开运指南 ---------- */
  var LUCKY_FAV_KEY = 'kanyu-lucky-favorites-v1';
  function getLuckyFavs() {
    try {
      var raw = localStorage.getItem(LUCKY_FAV_KEY);
      var arr = raw ? JSON.parse(raw) : [];
      return Array.isArray(arr) ? arr : [];
    } catch (e) { return []; }
  }
  function toggleLuckyFav(name) {
    var favs = getLuckyFavs();
    var i = favs.indexOf(name);
    if (i === -1) favs.push(name); else favs.splice(i, 1);
    try { localStorage.setItem(LUCKY_FAV_KEY, JSON.stringify(favs)); } catch (e) {}
    renderLucky();
    toast(i === -1 ? ('已收藏：' + name) : ('已取消收藏：' + name));
  }
  function loadLucky() {
    var p = currentPerson();
    $('luckyEmpty').hidden = !!p;
    $('luckyContent').hidden = true;
    if (!p) return;
    if (state.lucky) { renderLucky(); return; }
    $('luckyLoading').hidden = false;
    apiGet('/api/lucky?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      $('luckyLoading').hidden = true;
      state.lucky = d || {};
      renderLucky();
    }).catch(function (err) {
      $('luckyLoading').hidden = true;
      showError('开运指南加载失败：' + err.message);
    });
  }
  function renderLucky() {
    var d = state.lucky || {};
    var favs = getLuckyFavs();
    function cardHtml(c) {
      var rows = c.names.map(function (n, i) {
        var rgb = (c.rgb && c.rgb[i]) ? c.rgb[i].join(', ') : '—';
        return '<p><strong>' + esc(n) + '</strong> · ' + esc(c.hex[i] || '') + ' · RGB(' + esc(rgb) + ')</p>';
      }).join('');
      var favBtn = '';
      if (c.role === '喜用') {
        favBtn = c.names.map(function (n) {
          var on = favs.indexOf(n) !== -1;
          return '<button type="button" class="btn" data-fav="' + esc(n) + '">' + (on ? '★ 已收藏' : '☆ 收藏') + ' ' + esc(n) + '</button>';
        }).join(' ');
      }
      return '<div class="color-card"><p><strong>' + esc(c.wuxing) + '行 · ' + esc(c.role) + '</strong></p>' + rows + favBtn + '</div>';
    }
    var xiCards = (d.colors || []).filter(function (c) { return c.role === '喜用'; });
    var jiCards = (d.colors || []).filter(function (c) { return c.role === '忌向'; });
    var nums = (d.numbers || []).map(function (n) {
      return '<tr><td>' + esc(n.wuxing) + '</td><td>' + esc(n.numbers) + '</td><td>' + esc(n.role) + '</td></tr>';
    }).join('');
    var dirs = (d.directions || []).map(function (n) {
      return '<tr><td>' + esc(n.wuxing) + '</td><td>' + esc(n.direction) + '</td><td>' + esc(n.role) + '</td></tr>';
    }).join('');
    var layers = ((d.remedies || {}).layers || []).map(function (l) {
      return '<div class="card"><h3>化解 · ' + esc(l.key) + '</h3><p>' + esc(l.text) + '</p></div>';
    }).join('');
    var scenes = (d.scenes || []).map(function (s) {
      return '<div class="card"><h3>' + esc(s.key) + '</h3><p>' + esc(s.text) + '</p><p class="muted">来源：' + esc(s.source) + '</p></div>';
    }).join('');
    $('luckyContent').innerHTML =
      '<div class="card"><p><strong>' + esc(d.layer_note || '') + '</strong></p>' +
      '<p>喜用五行：' + esc((d.xiji || {}).xi ? d.xiji.xi.join('、') : '') + ' · 忌向：' + esc((d.xiji || {}).ji ? d.xiji.ji.join('、') : '') + ' · 日主' + esc((d.xiji || {}).level || '') + '</p></div>' +
      '<div class="card"><h3>喜用色卡（中文色名＋HEX／RGB）</h3><div class="lucky-grid">' + xiCards.map(cardHtml).join('') + '</div></div>' +
      (jiCards.length ? '<div class="card"><h3>忌向色卡（大面积长期使用少一些）</h3><div class="lucky-grid">' + jiCards.map(cardHtml).join('') + '</div></div>' : '') +
      '<div class="card"><h3>吉祥数字（河图五行数）</h3><table class="kv"><thead><tr><th>五行</th><th>数字</th><th>喜忌</th></tr></thead><tbody>' + nums + '</tbody></table></div>' +
      '<div class="card"><h3>适宜方位</h3><table class="kv"><thead><tr><th>五行</th><th>方位</th><th>喜忌</th></tr></thead><tbody>' + dirs + '</tbody></table></div>' +
      '<div class="card"><h3>化解五路</h3><p>' + esc((d.remedies || {}).preamble || '') + '</p></div>' + layers +
      '<div class="card"><h3>场景分级</h3></div>' + scenes;
    $('luckyContent').hidden = false;
    Array.prototype.forEach.call($('luckyContent').querySelectorAll('[data-fav]'), function (btn) {
      btn.addEventListener('click', function () { toggleLuckyFav(btn.getAttribute('data-fav')); });
    });
  }

  /* ---------- Insight 第 2 批 G7：配饰材质库 ---------- */
  function loadAccessories() {
    $('accContent').hidden = true;
    if (state.accessories) { renderAccessories(); return; }
    $('accLoading').hidden = false;
    apiGet('/api/accessories').then(function (d) {
      $('accLoading').hidden = true;
      state.accessories = d || {};
      renderAccessories();
    }).catch(function (err) {
      $('accLoading').hidden = true;
      showError('配饰库加载失败：' + err.message);
    });
  }
  function renderAccessories() {
    var d = state.accessories || {};
    var items = d.items || [];
    var wx = state.accWx || '';
    var shown = wx ? items.filter(function (e) { return e.wuxing === wx; }) : items;
    var chips = ['', '木', '火', '土', '金', '水'].map(function (w) {
      var label = w === '' ? '全部' : w + '行';
      var cls = (state.accWx || '') === w ? 'btn active' : 'btn';
      return '<button type="button" class="' + cls + '" data-wx="' + esc(w) + '">' + esc(label) + '</button>';
    }).join(' ');
    var rows = shown.map(function (e) {
      return '<tr><td>' + esc(e.name) + '</td><td>' + esc(e.wuxing) + '</td><td>' + esc(e.source) + '</td><td>' + esc(e.confidence) + '</td><td>' + esc(e.note) + '</td></tr>';
    }).join('');
    $('accContent').innerHTML =
      '<div class="card"><p><strong>' + esc(d.disclaimer || '') + '</strong></p>' +
      '<p>共 ' + String(items.length) + ' 条 · 整体层级：' + esc(d.layer || '民间象征') + '</p>' +
      '<p class="acc-filter">' + chips + '</p>' +
      '<table class="kv"><thead><tr><th>材质</th><th>五行</th><th>来源</th><th>可信度</th><th>备注</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
    $('accContent').hidden = false;
    Array.prototype.forEach.call($('accContent').querySelectorAll('[data-wx]'), function (btn) {
      btn.addEventListener('click', function () {
        state.accWx = btn.getAttribute('data-wx');
        renderAccessories();
      });
    });
  }

  /* ---------- Insight 第 2 批 G8：年度报告 ---------- */
  var annualBound = false;
  function initAnnualDefaults() {
    if (!$('annualYear').value) $('annualYear').value = String(new Date().getFullYear());
    if (!annualBound) {
      annualBound = true;
      $('annualLoad').addEventListener('click', function () {
        state.annual = null;
        loadAnnual();
      });
    }
    loadAnnual();
  }
  function loadAnnual() {
    var p = currentPerson();
    $('annualEmpty').hidden = !!p;
    $('annualContent').innerHTML = '';
    if (!p) return;
    var year = Number($('annualYear').value);
    if (!year || year < 1900 || year > 2089) {
      $('annualContent').innerHTML = '<p class="muted">起始年份须在 1900–2089 之间。</p>';
      return;
    }
    if (state.annual && state.annualYear === year) { renderAnnual(); return; }
    $('annualLoading').hidden = false;
    apiGet('/api/annual?person_id=' + encodeURIComponent(p.id) + '&year=' + String(year)).then(function (d) {
      $('annualLoading').hidden = true;
      state.annual = d || {};
      state.annualYear = year;
      renderAnnual();
    }).catch(function (err) {
      $('annualLoading').hidden = true;
      showError('年度报告加载失败：' + err.message);
    });
  }
  function renderAnnual() {
    var d = state.annual || {};
    var counts = d.counts || {};
    var rows = (d.years || []).map(function (y) {
      var level = (y.verdict || '').split('：')[0];
      return '<tr><td>' + yearStr(y.year) + '</td><td>' + esc(y.ganzhi || '') + '</td><td>' + esc(level) + '</td><td>' + esc(y.verdict || '') + '</td></tr>';
    }).join('');
    $('annualContent').innerHTML =
      '<div class="card"><p class="annual-verdict"><strong>' + esc(d.verdict || '') + '</strong></p>' +
      '<p>' + esc(d.verdict_reason || '') + '</p>' +
      (d.verdict_note ? '<p>' + esc(d.verdict_note) + '</p>' : '') +
      '<p>关口级 ' + String(counts['关口级'] === undefined ? '—' : counts['关口级']) + ' 年 · 主线 ' + String(counts['主线'] === undefined ? '—' : counts['主线']) + ' 年 · 参考 ' + String(counts['参考'] === undefined ? '—' : counts['参考']) + ' 年 · 平年 ' + String(counts['平年'] === undefined ? '—' : counts['平年']) + ' 年</p>' +
      '<p>大运交接年份：' + ((d.turn_years || []).length ? (d.turn_years || []).map(yearStr).join('、') : '本轮无') + ' · 冲提纲年份：' + ((d.chong_tigang_years || []).length ? (d.chong_tigang_years || []).map(yearStr).join('、') : '本轮无') + '</p>' +
      '<p class="muted">' + esc(d.layer_note || '') + '</p></div>' +
      '<div class="card"><h3>连续 12 个流年（' + yearStr((d.span || [])[0]) + '–' + yearStr((d.span || [])[1]) + '）</h3>' +
      '<table class="kv"><thead><tr><th>年份</th><th>干支</th><th>定级</th><th>直断</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
  }

  /* ---------- G11：交互式五行十神深度图表 ---------- */
  /* 数据只取 /api/interpret 已返回的 chart＋wuxing＋xiji，不新增接口；
   * 联动纯函数在 static/chartdepth.js（window.ChartDepth），与 App
   * ChartDepthModule.swift 同款规则：点五行→含该五行的柱，
   * 点十神→该十神所在柱。条宽沿用八字页 .bar-row 的既有写法
   *（<i style="width:%">，数据驱动的宽度，非视觉魔法值）。 */
  /* 深度图表选中切换（点击与键盘 Enter／空格共用；只绑定一次的监听器调它，
   * 不读渲染闭包里的旧 sel，一律以 state.chartdepthSel 为准）。 */
  function cdApplySelection(el) {
    if (el.hasAttribute('data-cd-clear')) { state.chartdepthSel = null; renderChartDepth(); return; }
    var cur = state.chartdepthSel;
    if (el.hasAttribute('data-cd-wx')) {
      var wx = Number(el.getAttribute('data-cd-wx'));
      state.chartdepthSel = (cur && cur.kind === 'wuxing' && cur.key === wx) ? null : { kind: 'wuxing', key: wx };
    } else if (el.hasAttribute('data-cd-ss')) {
      var nm = el.getAttribute('data-cd-ss');
      state.chartdepthSel = (cur && cur.kind === 'shishen' && cur.key === nm) ? null : { kind: 'shishen', key: nm };
    } else if (el.hasAttribute('data-cd-pillar')) {
      var pi = Number(el.getAttribute('data-cd-pillar'));
      state.chartdepthSel = (cur && cur.kind === 'pillar' && cur.key === pi) ? null : { kind: 'pillar', key: pi };
    } else {
      return;
    }
    renderChartDepth();
  }

  function loadChartDepth() {
    var p = currentPerson();
    if (!p) {
      $('chartDepthEmpty').hidden = false;
      $('chartDepthContent').hidden = true;
      return;
    }
    $('chartDepthEmpty').hidden = true;
    if (state.chartdepth && state.chartdepth._pid === String(p.id)) { renderChartDepth(); return; }
    $('chartDepthLoading').hidden = false;
    $('chartDepthContent').hidden = true;
    apiGet('/api/interpret?person_id=' + encodeURIComponent(p.id)).then(function (d) {
      clearError();
      $('chartDepthLoading').hidden = true;
      $('chartDepthContent').hidden = false;
      d._pid = String(p.id);
      state.chartdepth = d || {};
      renderChartDepth();
    }).catch(function (err) {
      $('chartDepthLoading').hidden = true;
      $('chartDepthEmpty').hidden = false;
      showError('深度图表加载失败：' + err.message);
    });
  }

  function cdRadarSvg(t, kind) {
    var size = 260;
    var cx = size / 2;
    var cy = size / 2;
    var r = size / 2 * 0.78;
    var n = kind === 'wuxing' ? 5 : 10;
    var step = 360 / n;
    function pt(i, scale) {
      var a = (-90 + i * step) * Math.PI / 180;
      var rr = r * scale;
      return [cx + rr * Math.cos(a), cy + rr * Math.sin(a)];
    }
    function pts(scaleFn) {
      var arr = [];
      var i;
      for (i = 0; i < n; i++) {
        var q = pt(i, scaleFn(i));
        arr.push(q[0].toFixed(1) + ',' + q[1].toFixed(1));
      }
      return arr.join(' ');
    }
    var maxV = 1;
    var values = [];
    var i;
    if (kind === 'wuxing') {
      for (i = 0; i < 5; i++) {
        values.push(t.wuxing[i] || 0);
        if (t.wuxing[i] > maxV) maxV = t.wuxing[i];
      }
    } else {
      var maxC = 1;
      t.shiShenCounts.forEach(function (c) { if (c.count > maxC) maxC = c.count; });
      for (i = 0; i < 10; i++) {
        var hit = null;
        t.shiShenCounts.forEach(function (c) { if (c.name === ChartDepth.SHI_SHEN_ORDER[i]) hit = c; });
        values.push(hit ? hit.count : 0);
      }
      maxV = maxC;
    }
    function valScale(i) { return values[i] / maxV; }
    var spokes = '';
    for (i = 0; i < n; i++) {
      var e = pt(i, 1);
      spokes += '<line class="cd-spoke" x1="' + cx + '" y1="' + cy + '" x2="' + e[0].toFixed(1) + '" y2="' + e[1].toFixed(1) + '"/>';
    }
    var vtx = '';
    for (i = 0; i < n; i++) {
      var q = pt(i, 1.22);
      var label;
      var key;
      var sel = false;
      var off = false;
      if (kind === 'wuxing') {
        label = ChartDepth.WX_NAMES[i] + ' ' + String(Math.round(values[i])) + '%';
        key = 'data-cd-wx="' + String(i) + '"';
        sel = !!(state.chartdepthSel && state.chartdepthSel.kind === 'wuxing' && state.chartdepthSel.key === i);
      } else {
        var nm = ChartDepth.SHI_SHEN_ORDER[i];
        label = nm + ' ' + String(values[i]);
        key = 'data-cd-ss="' + esc(nm) + '"';
        sel = !!(state.chartdepthSel && state.chartdepthSel.kind === 'shishen' && state.chartdepthSel.key === nm);
        off = values[i] === 0;
      }
      vtx += '<g class="cd-vtx' + (sel ? ' cd-sel' : '') + (off ? ' cd-off' : '') + '" ' + key +
        ' tabindex="0" role="button" aria-label="' + esc(label) + '，点按定位">' +
        '<circle cx="' + q[0].toFixed(1) + '" cy="' + q[1].toFixed(1) + '" r="20"/>' +
        '<text x="' + q[0].toFixed(1) + '" y="' + (q[1] - 2).toFixed(1) + '">' + esc(label.split(' ')[0]) + '</text>' +
        '<text x="' + q[0].toFixed(1) + '" y="' + (q[1] + 12).toFixed(1) + '">' + esc(label.split(' ')[1] || '') + '</text></g>';
    }
    return '<svg class="cd-radar" viewBox="0 0 ' + size + ' ' + size + '" role="group" aria-label="' +
      (kind === 'wuxing' ? '五行雷达' : '十神雷达') + '">' +
      '<polygon class="cd-track" points="' + pts(function () { return 1; }) + '"/>' +
      '<polygon class="cd-track" points="' + pts(function () { return 0.5; }) + '"/>' +
      spokes +
      '<polygon class="cd-poly" points="' + pts(valScale) + '"/>' +
      vtx + '</svg>';
  }

  function cdStateLabel(p) {
    if (p >= 32) return '偏旺';
    if (p >= 22) return '得势';
    if (p >= 12) return '中和';
    if (p >= 3) return '偏弱';
    return '缺显';
  }

  function renderChartDepth() {
    var d = state.chartdepth || {};
    var t = ChartDepth.buildTargets(d.chart || {}, d);
    var sel = state.chartdepthSel;
    var matches = [];
    var selName = '';
    if (sel && sel.kind === 'wuxing') {
      matches = ChartDepth.pillarsForWuxing(t, sel.key);
      selName = ChartDepth.WX_NAMES[sel.key];
    } else if (sel && sel.kind === 'shishen') {
      matches = ChartDepth.pillarsForShishen(t, sel.key);
      selName = sel.key;
    } else if (sel && sel.kind === 'pillar') {
      matches = [{ pillar: sel.key, details: ['本柱'] }];
      selName = ChartDepth.PILLAR_NAMES[sel.key];
    }
    var hl = {};
    matches.forEach(function (m) { hl[m.pillar] = true; });
    var xj = d.xiji || {};
    var pillarsHtml = t.pillars.map(function (p, i) {
      var hide = p.hideGan.map(function (h, j) {
        return esc(h) + '（' + esc(p.hideShishen[j] || '') + '）';
      }).join(' ');
      return '<div class="pillar' + (hl[i] ? ' cd-hl' : '') + (sel && sel.kind === 'pillar' && sel.key === i ? ' cd-primary' : '') +
        '" data-cd-pillar="' + String(i) + '" tabindex="0" role="button" aria-label="' + esc(p.name + ' ' + p.ganzhi) + '，点按选中">' +
        '<h3>' + esc(p.name) + '</h3><div class="gz">' + esc(p.ganzhi) + '</div>' +
        '<p>' + esc(p.stemShishen) + '</p><p>' + (hide || '—') + '</p></div>';
    }).join('');
    var wxBars = ChartDepth.WX_NAMES.map(function (name, i) {
      var v = t.wuxing[i] || 0;
      var maxV = 1;
      t.wuxing.forEach(function (x) { if (x > maxV) maxV = x; });
      var pct = maxV > 0 ? Math.round(v / maxV * 100) : 0;
      var isSel = !!(sel && sel.kind === 'wuxing' && sel.key === i);
      return '<div class="cd-bar-row' + (isSel ? ' cd-sel' : '') + '" data-cd-wx="' + String(i) + '" tabindex="0" role="button" aria-label="' +
        esc(name) + '占比 ' + String(Math.round(v)) + '%，点按定位">' +
        '<span class="cd-name">' + esc(name) + '</span><div class="bar"><i style="width:' + String(pct) + '%"></i></div>' +
        '<span class="cd-val">' + String(Math.round(v)) + '%</span><span class="cd-note">' + esc(cdStateLabel(v)) + '</span></div>';
    }).join('');
    var maxC = 1;
    t.shiShenCounts.forEach(function (c) { if (c.count > maxC) maxC = c.count; });
    var ssBars = ChartDepth.SHI_SHEN_ORDER.map(function (name) {
      var hit = null;
      t.shiShenCounts.forEach(function (c) { if (c.name === name) hit = c; });
      var count = hit ? hit.count : 0;
      var pls = hit ? hit.pillars.map(function (pi) { return ChartDepth.PILLAR_NAMES[pi]; }).join('·') : '未出现';
      var pct = Math.round(count / maxC * 100);
      var isSel = !!(sel && sel.kind === 'shishen' && sel.key === name);
      return '<div class="cd-bar-row' + (isSel ? ' cd-sel' : '') + (count === 0 ? ' cd-off' : '') + '" data-cd-ss="' + esc(name) + '" tabindex="0" role="button" aria-label="' +
        esc(name) + '共 ' + String(count) + ' 处，点按定位">' +
        '<span class="cd-name">' + esc(name) + '</span><div class="bar"><i style="width:' + String(pct) + '%"></i></div>' +
        '<span class="cd-val">' + String(count) + '</span><span class="cd-note">' + esc(pls) + '</span></div>';
    }).join('');
    var detail;
    if (!sel) {
      detail = '<p class="muted">尚未选中。点上方五行雷达／占比条／十神条／十神雷达，或四柱卡，即在此处看到命中干支，并同步高亮上方四柱。</p>';
    } else {
      var rows = matches.map(function (m) {
        var p = t.pillars[m.pillar];
        return '<p><strong>' + esc(p.name) + ' ' + esc(p.ganzhi) + '</strong> · ' + esc(m.details.join(' · ')) + '</p>';
      }).join('');
      detail = '<p><strong>当前选中：' + esc(selName) + '</strong></p>' + rows +
        '<p class="muted">命中柱已在上方四柱中高亮；再点一次同一元素可取消选中。</p>';
    }
    $('chartDepthContent').innerHTML =
      '<div class="card"><p>喜：' + ((xj.xi || []).map(function (x) { return '<span class="chip xi">' + esc(x) + '</span>'; }).join('') || '—') + '</p>' +
      '<p>忌：' + ((xj.ji || []).map(function (x) { return '<span class="chip ji">' + esc(x) + '</span>'; }).join('') || '—') + '</p>' +
      '<p class="muted">等级：' + esc(xj.level || '—') + ' · 调候：' + esc(xj.tiaoHou || '—') + ' · 日主：' + esc(t.dayMaster || '—') + '</p></div>' +
      '<div class="card"><h3>四柱</h3><div class="pillars">' + pillarsHtml + '</div>' +
      '<p class="muted">高亮＝当前选中元素所在的柱；点柱卡可单独选中一柱。</p></div>' +
      '<div class="card"><h3>五行雷达 · 点顶点定位</h3>' + cdRadarSvg(t, 'wuxing') +
      '<p class="muted">占比取 /api/interpret 返回的 wuxing（天干各 1，藏干本气 1／中气 0.5／余气 0.3，归一化）。</p></div>' +
      '<div class="card"><h3>五行占比条 · 点行定位</h3>' + wxBars +
      '<p class="muted">强弱标签与 App WuxingBarsView 同口径：≥32 偏旺，≥22 得势，≥12 中和，≥3 偏弱，其余缺显。</p></div>' +
      '<div class="card"><h3>十神分布条 · 点行定位</h3>' + ssBars +
      '<p class="muted">计数＝天干十神＋全部藏干十神；未出现者显示 0，不可点。</p></div>' +
      '<div class="card"><h3>十神雷达 · 点顶点定位</h3>' + cdRadarSvg(t, 'shishen') +
      '<p class="muted">十轴按正官／七杀／正印／偏印／比肩／劫财／食神／伤官／正财／偏财顺序；半径按出现次数归一化。</p></div>' +
      '<div class="card"><h3>联动定位</h3>' + detail +
      (sel ? '<p><button type="button" class="btn" data-cd-clear="1">清除选中</button></p>' : '') + '</div>';
    if (!state.chartdepthBound) {
      state.chartdepthBound = true;
      $('chartDepthContent').addEventListener('click', function (ev) {
        var el = ev.target.closest('[data-cd-wx],[data-cd-ss],[data-cd-pillar],[data-cd-clear]');
        if (!el) return;
        cdApplySelection(el);
      });
      $('chartDepthContent').addEventListener('keydown', function (ev) {
        if (ev.key !== 'Enter' && ev.key !== ' ') return;
        var el = ev.target.closest('[data-cd-wx],[data-cd-ss],[data-cd-pillar]');
        if (!el) return;
        ev.preventDefault();
        cdApplySelection(el);
      });
    }
  }

  /* ---------- G8：五运六气年度页 ---------- */
  function loadYunqi() {
    var input = $('yunqiYear');
    if (!input.value) input.value = String(new Date().getFullYear());
    var year = Number(input.value);
    if (!year || year < 1900 || year > 2100) {
      $('yunqiContent').innerHTML = '<p class="muted">年份须在 1900–2100 之间。</p>';
      return;
    }
    var p = currentPerson();
    var url = '/api/wuyunliuqi?year=' + String(year);
    if (p) url += '&person_id=' + encodeURIComponent(p.id);
    if (state.yunqi && state.yunqiYear === year && state.yunqi._pid === (p ? String(p.id) : '')) {
      renderYunqi();
      return;
    }
    $('yunqiLoading').hidden = false;
    apiGet(url).then(function (d) {
      $('yunqiLoading').hidden = true;
      d._pid = p ? String(p.id) : '';
      state.yunqi = d || {};
      state.yunqiYear = year;
      renderYunqi();
    }).catch(function (err) {
      $('yunqiLoading').hidden = true;
      showError('五运六气加载失败：' + err.message);
    });
  }
  function renderYunqi() {
    var d = state.yunqi || {};
    var zy = d.zhongyun || {};
    var steps = (d.steps || []).map(function (s) {
      return '<tr><td>' + esc(s.step) + '</td><td>' + esc(s.jieqi) + '</td><td>' + esc(s.zhuqi) +
        '</td><td>' + esc(s.keqi) + '</td><td>' + esc(s.mark || '') +
        (s.tongqi ? ' · 主客同气' : '') + '</td></tr>';
    }).join('');
    var quarters = (d.quarters || []).map(function (q) {
      return '<p><strong>' + esc(q.season) + '季</strong>：主气 ' + esc((q.zhuqi || []).join('、')) +
        '；客气 ' + esc((q.keqi || []).join('、')) + '。' + esc(q.rhythm || '') + '</p>';
    }).join('');
    var xy = d.xiaoyun;
    $('yunqiContent').innerHTML =
      '<div class="card"><h3>' + yearStr(d.year || '') + ' 年 · ' + esc(d.ganzhi || '') + '</h3>' +
      '<p>中运（大运统岁）：<strong>' + esc(zy.text || '') + '</strong> · 上半年司天：<strong>' +
      esc(d.sitian || '') + '</strong> · 下半年在泉：<strong>' + esc(d.zaiquan || '') + '</strong></p>' +
      '<table class="kv"><thead><tr><th>六步</th><th>节气</th><th>主气</th><th>客气</th><th>标记</th></tr></thead><tbody>' +
      steps + '</tbody></table>' +
      '<p class="muted">主客同气为顺，客胜主为逆；此为《素问》运气节令通参，不作诊疗断语。</p></div>' +
      '<div class="card"><h3>季度提示（只讲节律）</h3>' + quarters + '</div>' +
      (xy ? '<div class="card"><h3>小运（起运前）</h3><p>' + yearStr(xy.year) + ' 年 · ' +
        String(xy.age_xu || '') + ' 岁（虚岁）· 小运 ' + esc(xy.ganzhi || '') + ' · ' +
        esc(xy.direction || '') + '。' + esc(xy.note || '') + '</p></div>' : '') +
      '<p class="hint">' + esc(d.source || '') + '</p>' +
      '<p class="hint">' + esc(d.disclaimer || '') + '</p>';
  }

  /* ---------- G5：六爻／梅花时间起卦 ---------- */
  function initDivinationDefaults() {
    if (!$('divDt').value) $('divDt').value = qimenDefaultDt();
  }
  function divinationParams() {
    var dt = ($('divDt').value || '').replace('T', ' ');
    var lon = parseFloat($('divLon').value);
    if (isNaN(lon)) lon = 107.8;
    return { datetime: dt || undefined, question: $('divQuestion').value || '', lon: lon };
  }
  function castDivination(register) {
    var p = divinationParams();
    if (!p.datetime) { showError('请先填写起卦时间。'); return; }
    $('divLoading').hidden = false;
    $('divContent').innerHTML = '';
    var done = function (d) {
      $('divLoading').hidden = true;
      state.divination = d || {};
      renderDivination(register);
    };
    if (register) {
      api('/api/divination', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(p)
      }).then(done).catch(function (err) {
        $('divLoading').hidden = true;
        showError('起卦失败：' + err.message);
      });
    } else {
      var url = '/api/divination?datetime=' + encodeURIComponent(p.datetime) + '&lon=' + String(p.lon);
      if (p.question) url += '&question=' + encodeURIComponent(p.question);
      apiGet(url).then(done).catch(function (err) {
        $('divLoading').hidden = true;
        showError('起卦失败：' + err.message);
      });
    }
  }
  function renderDivination(registered) {
    var d = state.divination || {};
    var mh = d.meihua || {};
    var ly = d.liuyao || {};
    var ben = mh.ben || {}, hu = mh.hu || {}, bian = mh.bian || {};
    var mv = mh.moving_yao || {};
    function guaCard(title, g) {
      return '<div class="card"><h3>' + esc(title) + ' · ' + esc(g.name || '—') + '</h3>' +
        '<p>' + esc(g.upper || '') + '上' + esc(g.lower || '') + '下</p>' +
        '<p>卦辞：' + esc(g.guaci || '—') + '</p>' +
        '<p class="muted">白话：' + esc(g.guaci_baihua || '') + '</p></div>';
    }
    var lines = (ly.lines || []).map(function (l) {
      var mark = '';
      if (l.pos === ly.shi) mark += ' · 世';
      if (l.pos === ly.ying) mark += ' · 应';
      if (l.pos === mh.moving) mark += ' · 动';
      return '<tr><td>' + esc(l.name) + '</td><td>' + esc(l.yin_yang || '') + '</td><td>' +
        esc(l.branch || '') + esc(l.wuxing || '') + '</td><td>' + esc(l.qin || '') +
        '</td><td>' + esc(mark) + '</td></tr>';
    }).join('');
    var bl = ly.moving_bian_line || {};
    $('divContent').innerHTML =
      '<div class="card"><h3>起卦收据</h3><p>钟表时间 ' + esc(d.clock || '') + ' · 真太阳时 ' +
      esc(d.corrected || '') + '（校正 ' + esc(String(d.correction_minutes)) + ' 分钟，经度 ' +
      esc(String(d.lon)) + '）</p><p>农历' + esc(d.lunar ? d.lunar.year_zhi : '') + '年' +
      esc(d.lunar ? String(d.lunar.month_used) : '') + '月' +
      esc(d.lunar ? String(d.lunar.day) : '') + '日' +
      esc(d.lunar ? d.lunar.hour_branch : '') + '时' +
      (d.lunar && d.lunar.is_leap ? '（闰月）' : '') + ' · 问事：' +
      esc(d.question || '（未填）') + '</p></div>' +
      guaCard('本卦', ben) + guaCard('互卦', hu) + guaCard('变卦', bian) +
      '<div class="card"><h3>动爻 · 第' + esc(String(mh.moving || '')) + '爻（' + esc(mv.title || '') + '）</h3>' +
      '<p>' + esc(mv.text || '—') + '</p><p class="muted">白话：' + esc(mv.baihua || '') + '</p>' +
      '<p>变爻：' + esc(bl.branch || '') + esc(bl.wuxing || '') + esc(bl.qin || '') +
      '（变卦' + esc(bian.name || '') + ' · ' + esc(ly.bian_palace || '') + ly.bian_generation + '）</p></div>' +
      '<div class="card"><h3>体用生克</h3><p><strong>' + esc(mh.tiyong_label || '') + '</strong>：' +
      esc(mh.tiyong_text || '') + '</p><p class="muted">' + esc(mh.hu_relation_text || '') + '</p></div>' +
      '<div class="card"><h3>六爻 · ' + esc(ly.palace || '') + esc(ly.generation || '') +
      '（世' + esc(String(ly.shi || '')) + '应' + esc(String(ly.ying || '')) + '）</h3>' +
      '<table class="kv"><thead><tr><th>爻位</th><th>阴阳</th><th>地支</th><th>六亲</th><th>标记</th></tr></thead><tbody>' +
      lines + '</tbody></table></div>' +
      '<p class="hint">' + esc(d.disclaimer || '') + '</p>' +
      '<p class="hint">' + esc(d.source || '') + '</p>' +
      (registered
        ? '<p class="hint">已自动进前瞻登记（登记号 ' + esc(d.forecast_id || '') + '），原文冻结，到期在备份页回验。</p>'
        : '<p class="hint">本次只起卦，未登记前瞻；点「起卦并登记前瞻」才会写入登记簿。</p>');
  }

  /* ---------- G6：约束式 AI 问答（只引本机引擎事实；记录只存本机 localStorage） ---------- */
  var askBound = false;
  function initAsk() {
    updateAskPerson();
    renderAskHistory();
    if (askBound) return;
    askBound = true;
    $('askSubmit').addEventListener('click', submitAsk);
    $('askQuestion').addEventListener('keydown', function (e) { if (e.key === 'Enter') submitAsk(); });
    $('askClearHistory').addEventListener('click', function () {
      try { localStorage.removeItem('kanyu-ask-history'); } catch (e) {}
      renderAskHistory();
    });
  }
  function updateAskPerson() {
    var p = currentPerson();
    $('askPerson').textContent = p
      ? ('命主：' + p.name + '（' + p.birth + '）')
      : '未选择命主（通用问题可不选；事业／财运／婚恋等问题需选命主）';
  }
  function submitAsk() {
    var q = ($('askQuestion').value || '').trim();
    if (q.length < 2) { showError('问题至少 2 个字。'); return; }
    if (q.length > 200) { showError('问题最多 200 字。'); return; }
    var p = currentPerson();
    $('askLoading').hidden = false;
    $('askResult').innerHTML = '';
    apiPost('/api/ask', { question: q, person_id: p ? p.id : null }).then(function (d) {
      $('askLoading').hidden = true;
      renderAskResult(d);
      saveAskHistory(q, d);
    }).catch(function (err) {
      $('askLoading').hidden = true;
      $('askResult').innerHTML = '<p class="error-bar">提问失败：' + esc(err.message) + '</p>';
    });
  }
  function renderAskResult(d) {
    var html = '';
    if (d.refused) {
      html += '<p class="error-bar">本系统不作答：健康问题不落病名，寿数断语不在五典论命范围之内。</p>';
    } else if (d.degraded) {
      html += '<p class="error-bar">模型暂不可用或回答未通过依据校验，以下是本机引擎现算的事实原文，仅供参考。'
        + (d.degraded_reason ? '（' + esc(d.degraded_reason) + '）' : '') + '</p>';
    }
    var ans = d.answer || '';
    if (ans.indexOf('盘上无据') === 0) {
      html += '<div class="no-evidence"><strong>盘上无据</strong>：' + esc(ans.replace(/^盘上无据[：:]/, '')) + '</div>';
    } else {
      html += '<p>' + esc(ans) + '</p>';
    }
    if (d.model) html += '<p class="muted">模型：' + esc(d.model) + '（FreeLLMAPI 免费池）</p>';
    (d.caveats || []).forEach(function (c) {
      html += '<p class="hint">口径提示：' + esc(c) + '</p>';
    });
    var facts = d.facts || [];
    if (facts.length) {
      html += '<details open><summary>依据链（' + facts.length + ' 条事实）</summary><ul>'
        + facts.map(function (f) {
          return '<li>[' + esc(f.engine) + ' · ' + esc(f.field) + '] ' + esc(f.text) + '</li>';
        }).join('') + '</ul></details>';
    }
    $('askResult').innerHTML = html;
  }
  function loadAskHistory() {
    try {
      var raw = localStorage.getItem('kanyu-ask-history');
      var arr = raw ? JSON.parse(raw) : [];
      return Array.isArray(arr) ? arr : [];
    } catch (e) { return []; }
  }
  function saveAskHistory(q, d) {
    try {
      var arr = loadAskHistory();
      arr.unshift({ q: q, a: d.answer || '', degraded: !!d.degraded, at: new Date().toISOString() });
      localStorage.setItem('kanyu-ask-history', JSON.stringify(arr.slice(0, 20)));
    } catch (e) {}
    renderAskHistory();
  }
  function renderAskHistory() {
    var arr = loadAskHistory();
    $('askHistory').innerHTML = arr.length
      ? arr.map(function (h) {
        return '<p><strong>问：</strong>' + esc(h.q) + '<br><strong>答：</strong>' + esc(h.a)
          + (h.degraded ? ' <span class="muted">（降级：事实原文）</span>' : '') + '</p>';
      }).join('')
      : '<p class="muted">暂无记录。</p>';
  }

  function loadCelebs() {
    if ($('celebsList').dataset.loaded) return;
    $('celebsLoading').hidden = false;
    apiGet('/api/celebrities').then(function (d) {
      $('celebsLoading').hidden = true;
      $('celebsList').dataset.loaded = '1';
      $('celebsList').innerHTML = '<p class="hint">' + esc(d.trust_note || '') + '</p>' +
        (d.items || []).map(function (c) {
          return '<article class="card"><h3><a href="#" data-celeb="' + String(c.id) + '">' + esc(c.name) + '</a>' +
            (c.trust === '低' ? ' <span class="badge">仅供参考</span>' : '') + '</h3><p>' +
            esc(c.birth.slice(0, 4)) + ' 年生 · ' + esc(c.place) + ' · 可信度 ' + esc(c.trust) + '</p><p class="muted">' + esc(c.note) + '</p>' +
            (c.source ? '<p class="muted">来源：' + esc(c.source) + '</p>' : '') + '</article>';
        }).join('');
      $('celebsList').querySelectorAll('[data-celeb]').forEach(function (a) {
        a.addEventListener('click', function (ev) { ev.preventDefault(); showCeleb(parseInt(a.getAttribute('data-celeb'), 10)); });
      });
    }).catch(function (err) {
      $('celebsLoading').hidden = true;
      showError('名人库加载失败：' + err.message);
    });
  }
  function showCeleb(cid) {
    $('celebDetail').hidden = true;
    apiGet('/api/celebrities/' + String(cid)).then(function (d) {
      var c = d.celeb || {};
      var ch = d.chart || {};
      var sz = ch['四柱'] || {};
      var html = '<div class="card"><h3>' + esc(c.name) + ' · ' + esc(c.place) + '</h3>' +
        (c.trust === '低' ? '<p class="error-bar">低可信度条目，仅供参考：出生时间未经核实，分歧见下。</p>' : '') +
        '<p>记载：' + esc(c.note) +
        '（可信度 ' + esc(c.trust) + '）。出生 ' + esc(c.birth) + '，经度 ' + String(c.lon) + '。</p>' +
        (c.source ? '<p class="muted">来源：' + esc(c.source) + '</p>' : '') +
        (d.chart ? '<p>四柱：' + esc(sz['年柱'] || '—') + ' ' + esc(sz['月柱'] || '—') + ' ' + esc(sz['日柱'] || '—') + ' ' + esc(sz['时柱'] || '—') +
        ' · 日主 ' + esc(ch['日主'] || '—') + '</p>' : '<p class="muted">排盘暂不可算：' + esc(d.chart_error || '') + '</p>') + '</div>';
      if (d.ziwei) {
        html += '<div class="card"><h3>紫微盘</h3><p>' + esc(d.ziwei.ju_name || '') + ' · 命宫' + esc(d.ziwei.ming_gong_name || '') +
          ' · ' + esc(d.ziwei.lunar_text || '') + '</p></div>' +
          (d.ziwei_cards || []).map(cardHtml).join('');
      }
      $('celebDetail').innerHTML = html;
      $('celebDetail').hidden = false;
      $('celebDetail').scrollIntoView();
    }).catch(function (err) { showError('名人详情加载失败：' + err.message); });
  }
  var libInited = false;
  function initLibrary() {
    if (libInited) return;
    libInited = true;
    apiGet('/api/library').then(function (d) {
      var sel = $('libCat');
      (d.categories || []).forEach(function (c) {
        var o = document.createElement('option');
        o.value = c; o.textContent = c; sel.appendChild(o);
      });
      renderLibList(d.items || []);
    }).catch(function (err) { showError('图书馆加载失败：' + err.message); });
    $('libSearch').addEventListener('click', searchLibrary);
    $('libQ').addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); searchLibrary(); } });
  }
  function searchLibrary() {
    $('libLoading').hidden = false;
    var url = '/api/library?';
    if ($('libCat').value) url += 'cat=' + encodeURIComponent($('libCat').value) + '&';
    if ($('libQ').value.trim()) url += 'q=' + encodeURIComponent($('libQ').value.trim());
    apiGet(url).then(function (d) {
      $('libLoading').hidden = true;
      renderLibList(d.items || []);
    }).catch(function (err) {
      $('libLoading').hidden = true;
      showError('图书馆检索失败：' + err.message);
    });
  }
  function renderLibList(items) {
    $('libDetail').hidden = true;
    $('libList').innerHTML = items.length ? items.map(function (e) {
      return '<article class="card"><h3><a href="#" data-lib="' + String(e.id) + '">' + esc(e.title) + '</a></h3><p class="muted">' +
        esc(e.cat) + ' · #' + String(e.id) + '</p></article>';
    }).join('') : '<p class="muted">没有命中条目，换个关键词或分类试试。</p>';
    $('libList').querySelectorAll('[data-lib]').forEach(function (a) {
      a.addEventListener('click', function (ev) {
        ev.preventDefault();
        apiGet('/api/library/' + a.getAttribute('data-lib')).then(function (e) {
          $('libDetail').innerHTML = '<h3>' + esc(e.title) + '</h3><p class="muted">' + esc(e.cat) + ' · #' + String(e.id) + '</p><pre class="lib-body">' + esc(e.body) + '</pre>';
          $('libDetail').hidden = false;
          $('libDetail').scrollIntoView();
        }).catch(function (err) { showError('条目加载失败：' + err.message); });
      });
    });
  }

  /* ---------- G11 古籍检索 ---------- */
  var clsInited = false;
  function initClassics() {
    if (clsInited) return;
    clsInited = true;
    apiGet('/api/classics').then(function (d) {
      $('clsNote').textContent = d.note || '';
      $('clsBooks').innerHTML = (d.books || []).map(function (b) {
        var inc = b.chapters.filter(function (c) { return c.status === 'included'; }).length;
        return '<article class="card"><h3>' + esc(b.title) + ' <span class="muted">（' + esc(b.author) + ' · ' + esc(b.script === 'traditional' ? '繁体' : '简体') + '）</span></h3>' +
          '<p class="muted">' + esc(b.source || '') + ' · 已入库 ' + inc + ' / ' + b.chapters.length + ' 篇' + (b.scope_note ? ' · ' + esc(b.scope_note) : '') + '</p>' +
          '<p>' + b.chapters.map(function (c) {
            return c.status === 'included'
              ? '<a href="#" data-cls-book="' + esc(b.id) + '" data-cls-ch="' + esc(c.id) + '">' + esc(c.no) + '·' + esc(c.title) + '</a>'
              : '<span class="muted">' + esc(c.no) + '·' + esc(c.title) + '（未收录）</span>';
          }).join(' · ') + '</p></article>';
      }).join('');
      $('clsBooks').querySelectorAll('[data-cls-ch]').forEach(function (a) {
        a.addEventListener('click', function (ev) {
          ev.preventDefault();
          apiGet('/api/classics/' + a.getAttribute('data-cls-book') + '/' + a.getAttribute('data-cls-ch')).then(function (d) {
            var c = d.chapter;
            $('clsDetail').innerHTML = '<h3>' + esc(d.book_title) + ' · ' + esc(c.no) + ' ' + esc(c.title) + '</h3>' +
              '<p class="muted">' + esc(c.source || '') + ' · ' + esc(d.source || '') + '</p>' +
              (c.lines || []).map(function (ln) {
                return '<p><strong>原文 ' + ln.n + '：</strong>' + esc(ln.orig) + '<br><span class="muted">白话转述：</span>' + esc(ln.baihua) +
                  (ln.note ? '<br><span class="muted">校勘：' + esc(ln.note) + '</span>' : '') + '</p>';
              }).join('');
            $('clsDetail').hidden = false;
            $('clsDetail').scrollIntoView();
          }).catch(function (err) { showError('篇目加载失败：' + err.message); });
        });
      });
    }).catch(function (err) { showError('古籍加载失败：' + err.message); });
    $('clsSearch').addEventListener('click', searchClassics);
    $('clsQ').addEventListener('keydown', function (ev) { if (ev.key === 'Enter') { ev.preventDefault(); searchClassics(); } });
  }
  function searchClassics() {
    var q = $('clsQ').value.trim();
    if (!q) { $('clsHits').innerHTML = '<p class="muted">请输入检索词。</p>'; return; }
    $('clsLoading').hidden = false;
    apiGet('/api/classics/search?q=' + encodeURIComponent(q)).then(function (d) {
      $('clsLoading').hidden = true;
      $('clsHits').innerHTML = '<h3>命中 ' + d.count + ' 句</h3>' + (d.hits || []).map(function (h) {
        return '<article class="card"><p><strong>原文：</strong>' + esc(h.orig) + '</p><p><span class="muted">白话转述：</span>' + esc(h.baihua) + '</p>' +
          '<p class="muted">' + esc(h.book_title) + ' · ' + esc(h.chapter_no) + ' ' + esc(h.chapter_title) + ' · ' + esc(h.source) + '</p></article>';
      }).join('') || '<p class="muted">没有命中，换个词试试。</p>';
    }).catch(function (err) {
      $('clsLoading').hidden = true;
      showError('古籍检索失败：' + err.message);
    });
  }

  /* ---------- G11 题库（服务端判分；只存 localStorage） ---------- */
  var quizInited = false, quizData = null;
  function quizStoreKey() { return 'kanyu-quiz-last'; }
  function initQuiz() {
    if (quizInited) return;
    quizInited = true;
    apiGet('/api/quiz').then(function (d) {
      quizData = d;
      $('quizCount').textContent = d.count;
      try {
        if (localStorage.getItem(quizStoreKey())) $('quizClear').hidden = false;
      } catch (e) {}
    }).catch(function (err) { showError('题库加载失败：' + err.message); });
    $('quizStart').addEventListener('click', renderQuiz);
    $('quizClear').addEventListener('click', function () {
      try { localStorage.removeItem(quizStoreKey()); } catch (e) {}
      $('quizClear').hidden = true;
      $('quizResult').hidden = true;
      $('quizBody').innerHTML = '<p class="muted">本机答题记录已清空。</p>';
    });
  }
  function renderQuiz() {
    if (!quizData) return;
    $('quizResult').hidden = true;
    $('quizBody').innerHTML = quizData.questions.map(function (q, i) {
      var body = '<h3>' + (i + 1) + '. ' + esc(q.q) + ' <span class="muted">（' + esc(q.point) + '）</span></h3>';
      if (q.type === 'choice') {
        body += q.options.map(function (o, j) {
          return '<label><input type="radio" name="quiz-' + q.id + '" value="' + j + '"> ' + esc(o) + '</label><br>';
        }).join('');
      } else {
        body += '<label><input type="radio" name="quiz-' + q.id + '" value="true"> 对</label> ' +
          '<label><input type="radio" name="quiz-' + q.id + '" value="false"> 错</label>';
      }
      return '<article class="card" id="quiz-q-' + q.id + '">' + body + '</article>';
    }).join('') + '<button type="button" class="btn primary" id="quizSubmit">交卷（服务端判分）</button>';
    $('quizSubmit').addEventListener('click', submitQuiz);
  }
  function submitQuiz() {
    var answers = {};
    quizData.questions.forEach(function (q) {
      var sel = document.querySelector('input[name="quiz-' + q.id + '"]:checked');
      if (!sel) return;
      answers[String(q.id)] = q.type === 'choice' ? parseInt(sel.value, 10) : (sel.value === 'true');
    });
    if (Object.keys(answers).length === 0) { showError('请至少答一题再交卷。'); return; }
    $('quizLoading').hidden = false;
    apiPost('/api/quiz/submit', { answers: answers }).then(function (d) {
      $('quizLoading').hidden = true;
      var html = '<h3>得分：' + d.score + ' / ' + d.total + '</h3><p class="muted">判分由服务端引擎现算复核，不信任前端答案；本记录只存本机。</p>';
      d.results.forEach(function (r, i) {
        html += '<article class="card"><p><strong>' + (i + 1) + '. ' + (r.correct ? '✓ 答对' : '✗ 答错') + '</strong> <span class="muted">（' + esc(r.point) + '）</span></p>' +
          '<p>' + esc(r.explain) + '</p><p class="muted">' + esc(r.source) + '</p></article>';
      });
      $('quizResult').innerHTML = html;
      $('quizResult').hidden = false;
      try {
        localStorage.setItem(quizStoreKey(), JSON.stringify({ score: d.score, total: d.total, wrong: d.wrong_ids, at: new Date().toISOString() }));
        $('quizClear').hidden = false;
      } catch (e) {}
      $('quizResult').scrollIntoView();
    }).catch(function (err) {
      $('quizLoading').hidden = true;
      showError('判分失败：' + err.message);
    });
  }

  /* ---------- G11 学堂（收拢入口，不新写课程） ---------- */
  var academyInited = false;
  function initAcademy() {
    if (academyInited) return;
    academyInited = true;
  }

  /* ---------- 手相面相（人工标点＋手描三线；无 Vision 自动识别） ---------- */
  var palmInited = false;
  var palmState = null, faceState = null;
  var PALM_LINES0 = [
    [[0.16, 0.30], [0.38, 0.27], [0.62, 0.27], [0.84, 0.30]],
    [[0.14, 0.44], [0.38, 0.45], [0.62, 0.48], [0.82, 0.54]],
    [[0.30, 0.36], [0.24, 0.55], [0.30, 0.74], [0.48, 0.88]]
  ];
  var PALM_LINE_NAMES = ['感情线', '智慧线', '生命线'];
  var PALM_LINE_CARDS = [
    '感情线看情感表达的方式：走向、深浅、终点位置三项，须以你修正后的描线为准细读。',
    '智慧线看思维与决断的方式：起止、倾斜、长短三项，须以你修正后的描线为准细读。',
    '生命线看体力与生活节奏的纹路：弧度、包围范围、清晰度三项，须以你修正后的描线为准细读；与寿命长短无关。'
  ];
  var PALM_MARKS0 = { wrist: [0.50, 0.92], indexMCP: [0.30, 0.62], middleMCP: [0.50, 0.58], littleMCP: [0.72, 0.62], middleTip: [0.50, 0.06], indexTip: [0.28, 0.14], ringTip: [0.64, 0.10] };
  var PALM_MARK_LABELS = { wrist: '腕', indexMCP: '食指根', middleMCP: '中指根', littleMCP: '小指根', middleTip: '中指尖', indexTip: '食指尖', ringTip: '无名指尖' };
  function svgEl(tag, attrs) {
    var el = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.keys(attrs).forEach(function (k) { el.setAttribute(k, attrs[k]); });
    return el;
  }
  function dist(a, b, aspect) {
    var dx = (a[0] - b[0]) * aspect, dy = a[1] - b[1];
    return Math.sqrt(dx * dx + dy * dy);
  }
  function palmMeasureHtml() {
    if (!palmState || !palmState.img) return '';
    var m = palmState.marks, aspect = palmState.aspect || 1;
    var palmLen = dist(m.wrist, m.middleMCP, aspect), palmWidth = dist(m.indexMCP, m.littleMCP, aspect);
    if (!palmLen) return '<p class="muted">请先拖动标点到对应位置。</p>';
    var ratio = palmWidth / palmLen;
    var type = ratio >= 0.95 ? '方掌（土型倾向）' : (ratio <= 0.85 ? '长掌（水型倾向）' : '混合掌');
    var r24 = dist(m.indexMCP, m.indexTip, aspect) / dist(m.ringMCP || m.middleMCP, m.ringTip, aspect);
    var mid = dist(m.middleMCP, m.middleTip, aspect) / palmLen;
    return '<div class="card"><h3>测量结果（人工标点现算 · 实测）</h3><p>掌型：' + esc(type) + '（掌宽/掌长 ' + ratio.toFixed(2) +
      '）</p><p>中指/掌长 ' + mid.toFixed(2) + ' · 食指/无名指 ' + r24.toFixed(2) + '（' + (r24 >= 1 ? '食指不短于无名指' : '无名指长于食指') +
      '）</p><p class="muted">判读要点（按相书通说，娱乐参考）：掌型定大框架——方掌重实际与秩序，长掌重感受与想象；指长比看行事风格的细腻度。细读须结合修正后的三线。</p></div>';
  }
  function drawPalm() {
    var svg = $('palmSvg');
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    svg.setAttribute('viewBox', '0 0 100 100');
    svg.setAttribute('preserveAspectRatio', 'none');
    var st = palmState;
    Object.keys(st.marks).forEach(function (k) {
      var pt = st.marks[k];
      var c = svgEl('circle', { cx: pt[0] * 100, cy: pt[1] * 100, r: 2.2, fill: '#2e7d6b', 'data-mark': k });
      c.style.cursor = 'move';
      svg.appendChild(c);
      var t = svgEl('text', { x: pt[0] * 100 + 2, y: pt[1] * 100 - 2, 'font-size': 3.2, fill: '#2e7d6b' });
      t.textContent = PALM_MARK_LABELS[k];
      svg.appendChild(t);
    });
    st.lines.forEach(function (line, li) {
      var path = 'M' + line.map(function (p) { return (p[0] * 100).toFixed(1) + ' ' + (p[1] * 100).toFixed(1); }).join(' L');
      svg.appendChild(svgEl('path', { d: path, stroke: li === st.selectedLine ? '#9a2a22' : '#b5892e', 'stroke-width': li === st.selectedLine ? 0.9 : 0.6, fill: 'none' }));
      if (li === st.selectedLine) {
        line.forEach(function (p, pi) {
          var c = svgEl('circle', { cx: p[0] * 100, cy: p[1] * 100, r: 2.2, fill: '#9a2a22', 'data-line': String(li), 'data-pt': String(pi) });
          c.style.cursor = 'move';
          svg.appendChild(c);
        });
      }
    });
    bindSvgDrag(svg, function (el, x, y) {
      if (el.getAttribute('data-mark')) st.marks[el.getAttribute('data-mark')] = [x, y];
      else if (el.getAttribute('data-line') !== null) st.lines[parseInt(el.getAttribute('data-line'), 10)][parseInt(el.getAttribute('data-pt'), 10)] = [x, y];
      drawPalm();
      $('palmMeasure').innerHTML = palmMeasureHtml();
    });
  }
  function bindSvgDrag(svg, onMove) {
    var dragEl = null;
    function pos(ev) {
      var r = svg.getBoundingClientRect();
      var cx = (ev.touches ? ev.touches[0].clientX : ev.clientX), cy = (ev.touches ? ev.touches[0].clientY : ev.clientY);
      return [Math.min(1, Math.max(0, (cx - r.left) / r.width)), Math.min(1, Math.max(0, (cy - r.top) / r.height))];
    }
    svg.addEventListener('pointerdown', function (ev) {
      if (ev.target.tagName === 'circle') { dragEl = ev.target; ev.preventDefault(); }
    });
    svg.addEventListener('pointermove', function (ev) {
      if (!dragEl) return;
      var p = pos(ev);
      onMove(dragEl, p[0], p[1]);
    });
    svg.addEventListener('pointerup', function () { dragEl = null; });
    svg.addEventListener('pointerleave', function () { dragEl = null; });
  }
  function faceResultHtml() {
    if (!faceState || !faceState.img) return '';
    var m = faceState.marks;
    var up = m[1] - m[0], mid = m[2] - m[1], low = m[3] - m[2], t = up + mid + low;
    if (t <= 0) return '';
    var p = [up / t * 100, mid / t * 100, low / t * 100];
    var even = Math.abs(p[0] - 33) <= 5 && Math.abs(p[1] - 33) <= 5 && Math.abs(p[2] - 33) <= 5;
    return '<div class="card"><h3>三停比例（人工校准现算 · 实测）</h3><p>上停 ' + p[0].toFixed(0) + '% · 中停 ' + p[1].toFixed(0) + '% · 下停 ' + p[2].toFixed(0) + '%</p><p class="muted">' +
      (even ? '三停接近均等：面部比例匀称（相书谓三停平等、五岳丰盈者福相）。' : '三停不均：以最长一停为主象细读——上停主早年与额相，中停主中年与鼻相，下停主晚年与地阁；须结合五官逐项看，不单凭比例下断。') + '</p></div>';
  }
  function drawFace() {
    var svg = $('faceSvg');
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    svg.setAttribute('viewBox', '0 0 100 100');
    svg.setAttribute('preserveAspectRatio', 'none');
    var labels = ['发际线', '眉线', '鼻底', '下颌'];
    faceState.marks.forEach(function (y, i) {
      svg.appendChild(svgEl('line', { x1: 0, y1: y * 100, x2: 100, y2: y * 100, stroke: (i === 0 || i === 3) ? '#9a2a22' : '#b5892e', 'stroke-width': 0.6 }));
      var c = svgEl('circle', { cx: 8, cy: y * 100, r: 2.2, fill: '#9a2a22', 'data-face': String(i) });
      c.style.cursor = 'move';
      svg.appendChild(c);
      var t = svgEl('text', { x: 12, y: y * 100 - 2, 'font-size': 3.2, fill: '#333' });
      t.textContent = labels[i];
      svg.appendChild(t);
    });
    bindSvgDrag(svg, function (el, x, y) {
      faceState.marks[parseInt(el.getAttribute('data-face'), 10)] = y;
      drawFace();
      $('faceResult').innerHTML = faceResultHtml();
    });
  }
  function palmRecords() {
    try { return JSON.parse(localStorage.getItem('kanyu-palm-records') || '[]'); } catch (e) { return []; }
  }
  function renderPalmRecords() {
    var recs = palmRecords();
    $('palmRecords').innerHTML = recs.length ? recs.map(function (r) {
      return '<article class="card"><h3>' + esc(r.name || '未命名') + ' · ' + esc(r.kind) + '</h3><p>' + esc(r.summary) + '</p>' +
        (r.url ? '<p><a href="' + esc(r.url) + '" target="_blank" rel="noopener">查看照片</a></p>' : '') +
        '<p class="muted">' + esc(r.created_at || '') + '</p></article>';
    }).join('') : '<p class="muted">暂无记录。</p>';
  }
  function uploadPhoto(file, done) {
    var fd = new FormData();
    fd.append('file', file);
    fetch('/api/upload', { method: 'POST', credentials: 'same-origin', body: fd }).then(function (res) {
      if (!res.ok) throw new Error('上传失败（HTTP ' + String(res.status) + '）');
      return res.json();
    }).then(done).catch(function (err) { showError('照片上传失败：' + err.message); });
  }
  function initPalm() {
    if (palmInited) { renderPalmRecords(); return; }
    palmInited = true;
    renderPalmRecords();
    $('palmUpload').addEventListener('click', function () {
      var f = $('palmFile').files[0];
      if (!f) { showError('请先选择一张手掌照片'); return; }
      clearError();
      uploadPhoto(f, function (d) {
        palmState = { img: d.url, aspect: 1, selectedLine: 0, lines: JSON.parse(JSON.stringify(PALM_LINES0)), marks: JSON.parse(JSON.stringify(PALM_MARKS0)) };
        var img = $('palmImg');
        img.onload = function () { palmState.aspect = img.naturalWidth / img.naturalHeight; $('palmMeasure').innerHTML = palmMeasureHtml(); };
        img.src = d.url;
        $('palmStage').hidden = false;
        $('palmLines').hidden = false;
        $('palmSaveRow').hidden = false;
        $('palmLineCard').hidden = false;
        $('palmLineCard').textContent = PALM_LINE_CARDS[0];
        drawPalm();
        $('palmMeasure').innerHTML = palmMeasureHtml();
      });
    });
    $('palmLines').querySelectorAll('.palm-line-btn').forEach(function (b) {
      b.addEventListener('click', function () {
        if (!palmState) return;
        palmState.selectedLine = parseInt(b.getAttribute('data-line'), 10);
        $('palmLines').querySelectorAll('.palm-line-btn').forEach(function (x) { x.classList.toggle('active', x === b); });
        $('palmLineCard').textContent = PALM_LINE_CARDS[palmState.selectedLine];
        drawPalm();
      });
    });
    $('palmSave').addEventListener('click', function () {
      if (!palmState) return;
      var m = palmState.marks, aspect = palmState.aspect || 1;
      var ratio = dist(m.indexMCP, m.littleMCP, aspect) / dist(m.wrist, m.middleMCP, aspect);
      var r24 = dist(m.indexMCP, m.indexTip, aspect) / dist(m.middleMCP, m.ringTip, aspect);
      var recs = palmRecords();
      recs.push({ kind: '手相', name: $('palmName').value.trim(), url: palmState.img,
        summary: '掌宽/掌长 ' + ratio.toFixed(2) + '；食指/无名指 ' + r24.toFixed(2) + '；三线已按真实掌纹手描修正',
        lines: palmState.lines, marks: palmState.marks, created_at: new Date().toISOString().slice(0, 19).replace('T', ' ') });
      try { localStorage.setItem('kanyu-palm-records', JSON.stringify(recs)); } catch (e) {}
      $('palmSave').textContent = '已保存到测量记录';
      renderPalmRecords();
    });
    $('faceUpload').addEventListener('click', function () {
      var f = $('faceFile').files[0];
      if (!f) { showError('请先选择一张正面照片'); return; }
      clearError();
      uploadPhoto(f, function (d) {
        faceState = { img: d.url, marks: [0.14, 0.40, 0.63, 0.93] };
        $('faceImg').src = d.url;
        $('faceStage').hidden = false;
        $('faceSaveRow').hidden = false;
        drawFace();
        $('faceResult').innerHTML = faceResultHtml();
      });
    });
    $('faceSave').addEventListener('click', function () {
      if (!faceState) return;
      var m = faceState.marks, up = m[1] - m[0], mid = m[2] - m[1], low = m[3] - m[2], t = up + mid + low;
      var recs = palmRecords();
      recs.push({ kind: '面相', name: $('faceName').value.trim(), url: faceState.img,
        summary: '三停 上 ' + (up / t * 100).toFixed(0) + '% · 中 ' + (mid / t * 100).toFixed(0) + '% · 下 ' + (low / t * 100).toFixed(0) + '%',
        marks: faceState.marks, created_at: new Date().toISOString().slice(0, 19).replace('T', ' ') });
      try { localStorage.setItem('kanyu-palm-records', JSON.stringify(recs)); } catch (e) {}
      $('faceSave').textContent = '已保存到测量记录';
      renderPalmRecords();
    });
  }

  /* ---------- 健康检查 ---------- */
  function checkHealth() {
    apiGet('/api/health').then(function (d) {
      var dot = $('healthDot');
      if (d && d.ok) { dot.textContent = '● 后端正常'; dot.classList.add('ok'); dot.classList.remove('bad'); }
      else { dot.textContent = '● 后端异常'; dot.classList.add('bad'); }
    }).catch(function () {
      var dot = $('healthDot');
      dot.textContent = '● 后端未连通';
      dot.classList.add('bad');
      showError('后端未连通：部分功能需要后端 /api 才能使用，请先启动后端服务。');
    });
  }

  /* ---------- 启动 ---------- */
  if (window.AuthUI) window.AuthUI.init(); // 登录胶囊＋公告横幅（auth.js）
  initTheme();
  initLang();
  initLiunianControls();
  initPersonForm();
  initPoster();
  initPosterEditor();
  initZeji();
  initYunqi();
  initDivination();
  initQimen();
  initKanyu();
  initFloorplan();
  initCompass();
  initBackup();
  updateCorrection();
  checkHealth();
  loadCities();
  loadVerifyMarks();
  loadPeople().then(function () {
    renderRoute();
    loadInterpretRight();
  });
  renderRoute();
})();
