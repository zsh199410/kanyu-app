/* UI-only upgrade. Original routing, account, calculation and persistence code remain unchanged. */
(function () {
  'use strict';
  function setup() {
    const top = document.querySelector('.topnav');
    const bottom = document.querySelector('.bottom-nav');
    if (!top || !bottom) return;
    const routes = Array.from(top.querySelectorAll('a[data-route]')).map(a => a.cloneNode(true));
    const core = ['hecan', 'bazi', 'ziwei', 'qimen', 'kanyu'];
    const dialog = document.createElement('dialog');
    dialog.className = 'v6-tools';
    dialog.setAttribute('aria-labelledby', 'v6-tools-title');
    const heading = document.createElement('header');
    const title = document.createElement('h2'); title.id = 'v6-tools-title'; title.textContent = '全部工具';
    const close = document.createElement('button'); close.type = 'button'; close.className = 'v6-close'; close.textContent = '×'; close.setAttribute('aria-label', '关闭全部工具');
    close.addEventListener('click', () => dialog.close());
    heading.append(title, close);
    const search = document.createElement('input'); search.type = 'search'; search.placeholder = '搜索工具名称'; search.setAttribute('aria-label', '搜索全部工具');
    const directory = document.createElement('nav'); directory.setAttribute('aria-label', '全部工具目录');
    routes.forEach(a => directory.append(a));
    search.addEventListener('input', () => routes.forEach(a => { a.hidden = !a.textContent.includes(search.value.trim()); }));
    directory.addEventListener('click', event => { if (event.target.closest('a')) dialog.close(); });
    dialog.append(heading, search, directory); document.body.append(dialog);
    let opener;
    function moreButton() {
      const button = document.createElement('button'); button.type = 'button'; button.textContent = '工具'; button.className = 'theme-btn'; button.setAttribute('aria-haspopup', 'dialog');
      button.addEventListener('click', () => { opener = button; search.value = ''; routes.forEach(a => { a.hidden = false; }); dialog.showModal(); });
      return button;
    }
    dialog.addEventListener('close', () => { if (opener) opener.focus(); });
    [top, bottom].forEach(nav => {
      nav.replaceChildren();
      core.forEach(route => { const source = routes.find(a => a.dataset.route === route); if (source) nav.append(source.cloneNode(true)); });
      nav.append(moreButton());
    });
    function currentRoute() {
      const route = location.hash.replace(/^#\/?/, '').split('?')[0] || 'hecan';
      document.querySelectorAll('a[data-route]').forEach(a => {
        if (a.dataset.route === route) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
      });
    }
    window.addEventListener('hashchange', currentRoute); currentRoute();
    const aside = document.querySelector('.layout > .col-left');
    if (aside) {
      const details = document.createElement('details'); details.className = 'profile-panel col-left';
      const summary = document.createElement('summary'); summary.textContent = '人物档案 · 切换与新建';
      aside.before(details); aside.classList.remove('col-left'); details.append(summary, aside);
      const wide = matchMedia('(min-width:1200px)'); details.open = wide.matches;
      wide.addEventListener('change', event => { details.open = event.matches; });
    }
    const home = document.querySelector('#view-hecan .view-sub');
    if (home) {
      const grid = document.createElement('nav'); grid.className = 'v6-launchpad'; grid.setAttribute('aria-label', '核心排盘');
      [['bazi', '八字排盘', '四柱细盘与白话解读'], ['ziwei', '紫微斗数', '十二宫与四化层次'], ['qimen', '奇门遁甲', '九宫盘与起局依据'], ['palm', '手相面相', '采集、测量与记录']].forEach(([route, label, hint]) => {
        const a = document.createElement('a'); a.href = '#/' + route; a.dataset.route = route;
        const strong = document.createElement('strong'); strong.textContent = label;
        const text = document.createElement('span'); text.textContent = hint; a.append(strong, text); grid.append(a);
      });
      home.after(grid); currentRoute();
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup, { once: true }); else setup();
})();
