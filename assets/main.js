/* imac-setup 안내 페이지 동작: 테마, 복사, 명령 탭, 키캡 데모, 목차 강조, 등장 모션 */
(function () {
  'use strict';

  var THEME_KEY = 'imac-setup-theme';
  var COPY_FEEDBACK_MS = 1600;
  var KEY_PRESS_MS = 130;
  var KEY_AUTO_MS = 3200;
  var REVEAL_THRESHOLD = 0.15;
  var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function readStoredTheme() {
    try { return localStorage.getItem(THEME_KEY); } catch (e) { return null; }
  }
  function storeTheme(value) {
    try { localStorage.setItem(THEME_KEY, value); } catch (e) { /* 저장 불가 환경은 무시 */ }
  }
  function currentTheme() {
    var explicit = document.documentElement.dataset.theme;
    if (explicit === 'light' || explicit === 'dark') return explicit;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  function setupThemeToggle() {
    var button = document.querySelector('[data-theme-toggle]');
    if (!button) return;
    button.addEventListener('click', function () {
      var next = currentTheme() === 'dark' ? 'light' : 'dark';
      document.documentElement.dataset.theme = next;
      storeTheme(next);
    });
  }

  function writeClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      document.body.removeChild(area);
      ok ? resolve() : reject(new Error('copy command failed'));
    });
  }
  function setupCopyButtons() {
    var blocks = document.querySelectorAll('[data-copy-block]');
    Array.prototype.forEach.call(blocks, function (block) {
      var button = block.querySelector('[data-copy-btn]');
      var source = block.querySelector('[data-copy-text]');
      if (!button || !source) return;
      var label = button.querySelector('.copy-label');
      var timer = null;
      button.addEventListener('click', function () {
        var text = source.textContent.replace(/\s+$/, '');
        writeClipboard(text).then(function () {
          button.classList.remove('is-failed');
          button.classList.add('is-copied');
          if (label) label.textContent = '복사됨';
        }, function () {
          button.classList.add('is-failed');
          if (label) label.textContent = '직접 선택해 복사하세요';
        }).then(function () {
          clearTimeout(timer);
          timer = setTimeout(function () {
            button.classList.remove('is-copied', 'is-failed');
            if (label) label.textContent = '복사';
          }, COPY_FEEDBACK_MS);
        });
      });
    });
  }

  function setupCommandSwitcher() {
    var root = document.querySelector('[data-cmd-switcher]');
    if (!root) return;
    var tabs = Array.prototype.slice.call(root.querySelectorAll('[role="tab"]'));
    var target = root.querySelector('[data-cmd-target]');
    var desc = root.querySelector('[data-cmd-desc-target]');
    var panel = root.querySelector('[role="tabpanel"]');
    if (!tabs.length || !target) return;

    function activate(tab) {
      tabs.forEach(function (other) {
        var selected = other === tab;
        other.setAttribute('aria-selected', selected ? 'true' : 'false');
        other.tabIndex = selected ? 0 : -1;
      });
      target.textContent = tab.dataset.cmd;
      if (desc) desc.textContent = tab.dataset.cmdDesc || '';
      if (panel) panel.setAttribute('aria-labelledby', tab.id);
    }
    tabs.forEach(function (tab, index) {
      tab.addEventListener('click', function () { activate(tab); });
      tab.addEventListener('keydown', function (event) {
        var delta = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
        if (!delta) return;
        event.preventDefault();
        var next = tabs[(index + delta + tabs.length) % tabs.length];
        activate(next);
        next.focus();
      });
    });
  }

  function setupKeycapDemo() {
    var key = document.querySelector('[data-demo-key]');
    var glyph = document.querySelector('[data-demo-glyph]');
    var menu = document.querySelector('[data-demo-menu]');
    if (!key || !glyph || !menu) return;
    var items = Array.prototype.slice.call(menu.querySelectorAll('.menu-item'));
    var glyphs = items.map(function (item) {
      var g = item.querySelector('.menu-glyph');
      return g ? g.textContent : '';
    });
    var state = 0;
    var autoTimer = null;

    function render() {
      items.forEach(function (item, i) { item.classList.toggle('is-active', i === state); });
      glyph.textContent = glyphs[state];
      key.classList.toggle('is-lit', state !== 0);
      if (!prefersReducedMotion) {
        glyph.classList.add('is-flip');
        setTimeout(function () { glyph.classList.remove('is-flip'); }, 240);
      }
    }
    function advance() {
      state = (state + 1) % items.length;
      if (prefersReducedMotion) { render(); return; }
      key.classList.add('is-pressed');
      setTimeout(function () {
        key.classList.remove('is-pressed');
        render();
      }, KEY_PRESS_MS);
    }
    function scheduleAuto() {
      if (prefersReducedMotion || document.hidden) return;
      clearTimeout(autoTimer);
      autoTimer = setTimeout(function () { advance(); scheduleAuto(); }, KEY_AUTO_MS);
    }
    key.addEventListener('click', function () { advance(); scheduleAuto(); });
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) clearTimeout(autoTimer); else scheduleAuto();
    });
    scheduleAuto();
  }

  function setupReveal() {
    var targets = document.querySelectorAll('.reveal');
    if (!targets.length) return;
    if (prefersReducedMotion || !('IntersectionObserver' in window)) {
      Array.prototype.forEach.call(targets, function (el) { el.classList.add('is-visible'); });
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      });
    }, { threshold: REVEAL_THRESHOLD, rootMargin: '0px 0px -8% 0px' });
    Array.prototype.forEach.call(targets, function (el) { observer.observe(el); });
  }

  function setupScrollSpy() {
    var links = Array.prototype.slice.call(document.querySelectorAll('[data-toc] a'));
    if (!links.length || !('IntersectionObserver' in window)) return;
    var byId = {};
    links.forEach(function (link) { byId[link.getAttribute('href').slice(1)] = link; });
    var sections = Object.keys(byId).map(function (id) { return document.getElementById(id); }).filter(Boolean);
    var visible = {};
    function refresh() {
      var first = sections.filter(function (s) { return visible[s.id]; })[0];
      links.forEach(function (link) { link.classList.remove('is-active'); });
      if (first) byId[first.id].classList.add('is-active');
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) { visible[entry.target.id] = entry.isIntersecting; });
      refresh();
    }, { rootMargin: '-25% 0px -60% 0px', threshold: 0 });
    sections.forEach(function (s) { observer.observe(s); });
  }

  setupThemeToggle();
  setupCopyButtons();
  setupCommandSwitcher();
  setupKeycapDemo();
  setupReveal();
  setupScrollSpy();
})();
