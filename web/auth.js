/* 三术合参 Web 版 · auth.js — 极简账户前端（不依赖任何框架）
 * 挂载点（由 INTEGRATION.md 在 index.html 里加）：
 *   <div id="authCapsule"></div>           —— 导航栏右上角用户胶囊
 *   <div id="announceBar" hidden></div>    —— 顶栏下方置顶公告横幅
 *   <script src="./auth.js"></script>       —— 在 app.js 之前或之后均可，本文件自初始化
 * 所有请求带 credentials:'same-origin'（会话走 HttpOnly Cookie）。
 * 注册成功后若 guest_pending 为真，弹窗问是否把当前游客档案一键绑定到新账号。
 */
(function () {
  'use strict';

  var API = '';

  function esc(s) {
    return String(s === undefined || s === null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function api(path, options) {
    options = options || {};
    options.credentials = 'same-origin';
    options.headers = Object.assign({ 'Content-Type': 'application/json' }, options.headers || {});
    return fetch(API + path, options).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (body) {
        if (!res.ok) throw new Error((body && body.detail) || ('请求失败（HTTP ' + res.status + '）'));
        return body;
      });
    });
  }

  function injectStyle() {
    if (document.getElementById('authStyle')) return;
    var st = document.createElement('style');
    st.id = 'authStyle';
    st.textContent = [
      '.auth-capsule{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}',
      '.auth-capsule .auth-user{color:var(--gold);font-weight:600}',
      '.auth-btn{border:1px solid var(--gold);background:transparent;color:var(--ink);border-radius:999px;padding:.35rem .9rem;cursor:pointer;font-size:.9rem}',
      '.auth-btn.primary{background:var(--red);border-color:var(--red);color:#FFF6E8}',
      '.auth-modal{position:fixed;inset:0;background:rgba(20,16,12,.55);display:grid;place-items:center;z-index:80}',
      '.auth-card{width:min(92vw,380px);background:var(--surface);border:1px solid var(--gold);border-radius:14px;padding:1.2rem 1.3rem;box-shadow:var(--shadow)}',
      '.auth-card h2{margin:.1em 0 .6em;border-left:4px solid var(--red);padding-left:.5rem}',
      '.auth-card input{width:100%;padding:.55rem .6rem;margin:.25rem 0 .7rem;border:1px solid var(--line);border-radius:8px;background:var(--surface);color:var(--ink)}',
      '.auth-card .auth-error{color:var(--red);min-height:1.2em;font-size:.9rem}',
      '.auth-tabs{display:flex;gap:.5rem;margin-bottom:.6rem}',
      '.auth-tabs button{flex:1;border:1px solid var(--line);background:var(--surface2);border-radius:999px;padding:.4rem 0;cursor:pointer;color:var(--ink)}',
      '.auth-tabs button.active{background:var(--red);border-color:var(--red);color:#FFF6E8}',
      '.announce-bar{background:var(--surface2);border-bottom:2px solid var(--gold);color:var(--ink);padding:.45rem 1rem;font-size:.92rem;text-align:center}',
      '.announce-bar b{color:var(--red)}'
    ].join('\n');
    document.head.appendChild(st);
  }

  /* ---------- 用户胶囊 ---------- */
  function renderCapsule(me) {
    var host = document.getElementById('authCapsule');
    if (!host) return;
    if (me && me.user) {
      host.innerHTML =
        '<span class="auth-capsule">' +
        '<span class="auth-user">◈ ' + esc(me.user.username) + '</span>' +
        (me.user.role === 'admin' ? '<a class="auth-btn" href="./admin.html">后台</a>' : '') +
        '<button type="button" class="auth-btn" id="authLogout">退出</button>' +
        '</span>';
      var btn = document.getElementById('authLogout');
      if (btn) btn.addEventListener('click', function () {
        api('/api/auth/logout', { method: 'POST' }).then(function () { location.reload(); });
      });
    } else {
      host.innerHTML =
        '<span class="auth-capsule">' +
        '<button type="button" class="auth-btn primary" id="authOpen">登录 / 注册</button>' +
        '</span>';
      var open = document.getElementById('authOpen');
      if (open) open.addEventListener('click', function () { openModal('login'); });
    }
  }

  /* ---------- 公告横幅 ---------- */
  function renderAnnouncement() {
    var bar = document.getElementById('announceBar');
    if (!bar) return;
    api('/api/announcement').then(function (res) {
      var text = (res && res.announcement) || '';
      if (text) {
        bar.innerHTML = '<b>公告</b>　' + esc(text);
        bar.hidden = false;
      } else {
        bar.hidden = true;
      }
    }).catch(function () { bar.hidden = true; });
  }

  /* ---------- 登录 / 注册弹窗 ---------- */
  var modalMode = 'login';

  function openModal(mode) {
    modalMode = mode || 'login';
    closeModal();
    var wrap = document.createElement('div');
    wrap.className = 'auth-modal';
    wrap.id = 'authModal';
    wrap.innerHTML =
      '<div class="auth-card" role="dialog" aria-label="登录或注册">' +
      '<h2>三术合参 · 账户</h2>' +
      '<div class="auth-tabs">' +
      '<button type="button" id="authTabLogin" class="' + (modalMode === 'login' ? 'active' : '') + '">登录</button>' +
      '<button type="button" id="authTabRegister" class="' + (modalMode === 'register' ? 'active' : '') + '">注册</button>' +
      '</div>' +
      '<label>账号<input id="authUsername" type="text" autocomplete="username" placeholder="2–20 位字母 / 数字 / 中文"></label>' +
      '<label>密码<input id="authPassword" type="password" autocomplete="current-password" placeholder="至少 6 位"></label>' +
      '<p class="auth-error" id="authError"></p>' +
      '<button type="button" class="auth-btn primary" id="authSubmit" style="width:100%">登录</button>' +
      '<p class="hint" style="margin-top:.6rem">注册只需账号＋密码；密码经单向哈希存储。未登录也可排盘，注册后可把游客档案一键绑定到新账号。</p>' +
      '<p style="text-align:right"><button type="button" class="auth-btn" id="authClose">关闭</button></p>' +
      '</div>';
    document.body.appendChild(wrap);
    var submit = document.getElementById('authSubmit');
    function refreshTab() {
      document.getElementById('authTabLogin').className = modalMode === 'login' ? 'active' : '';
      document.getElementById('authTabRegister').className = modalMode === 'register' ? 'active' : '';
      submit.textContent = modalMode === 'login' ? '登录' : '注册并登录';
    }
    document.getElementById('authTabLogin').addEventListener('click', function () { modalMode = 'login'; refreshTab(); });
    document.getElementById('authTabRegister').addEventListener('click', function () { modalMode = 'register'; refreshTab(); });
    document.getElementById('authClose').addEventListener('click', closeModal);
    wrap.addEventListener('click', function (e) { if (e.target === wrap) closeModal(); });
    refreshTab();
    submit.addEventListener('click', function () {
      var username = document.getElementById('authUsername').value.trim();
      var password = document.getElementById('authPassword').value;
      var errEl = document.getElementById('authError');
      errEl.textContent = '';
      var path = modalMode === 'login' ? '/api/auth/login' : '/api/auth/register';
      api(path, { method: 'POST', body: JSON.stringify({ username: username, password: password }) })
        .then(function (res) {
          if (modalMode === 'register' && res.guest_pending) {
            if (window.confirm('检测到当前游客名下已有档案，是否一键绑定到新账号「' + username + '」？')) {
              return api('/api/auth/adopt', { method: 'POST', body: '{}' }).then(function (ad) {
                var n = (ad.adopted && ad.adopted.people || 0) + (ad.adopted && ad.adopted.forecasts || 0);
                alert('已绑定 ' + n + ' 条游客档案到新账号。');
                location.reload();
              });
            }
          }
          location.reload();
        })
        .catch(function (e) { errEl.textContent = e.message || '操作失败'; });
    });
    var first = document.getElementById('authUsername');
    if (first) first.focus();
  }

  function closeModal() {
    var m = document.getElementById('authModal');
    if (m) m.parentNode.removeChild(m);
  }

  function init() {
    injectStyle();
    api('/api/auth/me').then(renderCapsule).catch(function () { renderCapsule(null); });
    renderAnnouncement();
  }

  window.AuthUI = { init: init, openModal: openModal, renderCapsule: renderCapsule };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
