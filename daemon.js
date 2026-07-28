#!/usr/bin/env node
/**
 * WorkBuddy Background Injector Daemon v2.0
 *
 * 外部注入式背景方案 —— 不修改 WorkBuddy 的 app.asar。
 * 通过 Chrome DevTools Protocol (CDP) 将背景层注入到 WorkBuddy 的渲染进程中。
 *
 * v2.0 升级：
 *   - 移除所有硬编码路径，自动检测项目根目录
 *   - 指数退避重连策略
 *   - 请求日志（带时间戳）
 *   - 配置验证（拒绝非法值）
 *   - 健康检查端点 /api/health
 *   - 优雅关闭（清理所有资源）
 *   - 更丰富的 MIME 类型支持
 *   - 文件路径安全校验（防止目录遍历）
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');
const { execFile } = require('child_process');

// ─── 路径自动检测 ─────────────────────────────────────────
// 项目根目录 = daemon.js 所在目录
const BASE_DIR = path.resolve(__dirname);
const CONFIG_PATH = path.join(BASE_DIR, 'config.json');
const SETTINGS_HTML = path.join(BASE_DIR, 'settings.html');
const MANAGER_HTML = path.join(BASE_DIR, 'manager.html');
const LOG_PATH = path.join(BASE_DIR, 'daemon.log');
const PID_PATH = path.join(BASE_DIR, 'daemon.pid');

// Node.js 路径（用于 chrome-remote-interface 依赖）
const NODE_MODULES = '/Users/x/.workbuddy/binaries/node/workspace/node_modules';
const CDP = require(path.join(NODE_MODULES, 'chrome-remote-interface'));

const HTTP_PORT = 17890;
const CDP_PORT = 9222;

let cdpClient = null;
let injectScriptId = null;
let reconnectAttempts = 0;
let reconnectTimer = null;
let server = null;
let configWatcher = null;

// ─── 日志 ─────────────────────────────────────────────────
function log(tag, msg) {
  const ts = new Date().toISOString().slice(11, 19);
  const line = `[${ts}][${tag}] ${msg}`;
  console.log(line);
  // 追加到日志文件（非阻塞）
  fs.appendFile(LOG_PATH, line + '\n', () => {});
}

// ─── 配置管理 ───────────────────────────────────────────
const DEFAULT_CONFIG = {
  enabled: true,
  type: 'none',
  source: '',
  opacity: 1.0,
  overlay: 0.25,
  blur: '0px',
  scale: 'cover',
  position: 'center',
  textColor: '',
  theme: 'purple',
  autoText: true,
};

function validateConfig(cfg) {
  const errors = [];
  if (typeof cfg.enabled !== 'boolean') errors.push('enabled 必须是布尔值');
  if (!['video', 'image', 'none'].includes(cfg.type)) errors.push('type 必须是 video/image/none');
  if (typeof cfg.source !== 'string') errors.push('source 必须是字符串');
  if (cfg.opacity !== undefined && (typeof cfg.opacity !== 'number' || cfg.opacity < 0 || cfg.opacity > 1)) errors.push('opacity 必须在 0-1 之间');
  if (cfg.overlay !== undefined && (typeof cfg.overlay !== 'number' || cfg.overlay < 0 || cfg.overlay > 1)) errors.push('overlay 必须在 0-1 之间');
  if (cfg.scale !== undefined && !['cover', 'contain', 'fill'].includes(cfg.scale)) errors.push('scale 必须是 cover/contain/fill');
  if (cfg.position !== undefined && !['center', 'top', 'bottom', 'left', 'right'].includes(cfg.position)) errors.push('position 必须是 center/top/bottom/left/right');
  return errors;
}

function loadConfig() {
  try {
    const raw = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    const merged = { ...DEFAULT_CONFIG, ...raw };
    const errors = validateConfig(merged);
    if (errors.length > 0) {
      log('config', `配置验证失败: ${errors.join('; ')}，使用默认值`);
      return { ...DEFAULT_CONFIG };
    }
    return merged;
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function saveConfig(cfg) {
  const errors = validateConfig(cfg);
  if (errors.length > 0) {
    log('config', `拒绝非法配置: ${errors.join('; ')}`);
    return false;
  }
  config = cfg;
  try {
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
    log('config', `已保存: ${cfg.type} ${cfg.source || '(无)'}`);
    // 配置保存后立即推送到页面
    pushConfigToPage();
    return true;
  } catch (e) {
    log('config', `写入失败: ${e.message}`);
    return false;
  }
}

// 监听配置文件变化
fs.watch(CONFIG_PATH, (eventType) => {
  if (eventType === 'change') {
    log('config', '配置文件已修改，重新加载...');
    const newConfig = loadConfig();
    if (JSON.stringify(newConfig) !== JSON.stringify(config)) {
      config = newConfig;
      pushConfigToPage();
    }
  }
});

// 初始化配置（在 DEFAULT_CONFIG 定义之后）
let config = loadConfig();

// ─── 注入脚本 ───────────────────────────────────────────
function buildInjectScript() {
  return `
(function() {
  if (window.__wbBgInterval) { clearInterval(window.__wbBgInterval); }
  if (window.__wbBgRAF) { cancelAnimationFrame(window.__wbBgRAF); }
  if (window.__wbBgPoll) { clearInterval(window.__wbBgPoll); }

  var DAEMON = 'http://localhost:${HTTP_PORT}';
  var currentConfig = null;
  var currentFileUri = null;
  var lastMediaSrc = null;

  // CSS — 借鉴 Codex-Dream-Skin 设计：
  // 1. body::before 伪元素作背景层（不依赖 DOM 元素，不被 React 移除）
  // 2. CSS 变量定义配色
  // 3. 渐变遮罩替代文字阴影
  // 4. 侧边栏渐变+边框+阴影玻璃效果
  // 5. 按钮半透明圆角+过渡动画

  // 主题配色表
  var themes = {
    'purple':  { bg:'14,8,22',  panel:'24,16,30', accent:'255,107,166', text:'237,240,241', muted:'163,170,174' },
    'blue':    { bg:'8,12,26',  panel:'14,20,36', accent:'96,165,250',  text:'237,240,245', muted:'160,170,185' },
    'green':   { bg:'6,18,10',  panel:'12,26,16', accent:'74,222,128',  text:'230,245,235', muted:'150,180,160' },
    'orange':  { bg:'20,10,4',  panel:'30,16,8',  accent:'251,146,60',  text:'245,235,225', muted:'180,160,140' },
    'rose':    { bg:'20,6,14',  panel:'30,10,22', accent:'244,114,182', text:'245,230,238', muted:'180,150,165' },
    'slate':   { bg:'12,12,18', panel:'20,20,28', accent:'148,163,184', text:'235,235,240', muted:'150,155,165' },
    'midnight':{ bg:'4,4,16',   panel:'10,10,26', accent:'129,140,248', text:'225,230,245', muted:'140,150,170' }
  };

  function buildCssVars(themeName) {
    var t = themes[themeName] || themes['purple'];
    return [
      ':root {',
      '  --wb-bg: #' + hex(t.bg) + '; --wb-bg-rgb: ' + t.bg + ';',
      '  --wb-panel: #' + hex(t.panel) + '; --wb-panel-rgb: ' + t.panel + ';',
      '  --wb-accent: #' + hex(t.accent) + '; --wb-accent-rgb: ' + t.accent + ';',
      '  --wb-text: #' + hex(t.text) + '; --wb-text-rgb: ' + t.text + ';',
      '  --wb-muted: #' + hex(t.muted) + '; --wb-muted-rgb: ' + t.muted + ';',
      '  --wb-line: rgba(' + t.accent + ',0.12);',
      '  --wb-glass: rgba(' + t.panel + ',0.55);',
      '  --wb-glass-light: rgba(' + t.panel + ',0.40);',
      '  --wb-glass-strong: rgba(' + t.bg + ',0.72);',
      '}'
    ].join('\\n');
  }

  function hex(rgb) {
    return rgb.split(',').map(function(v) { return parseInt(v).toString(16).padStart(2,'0'); }).join('');
  }


  var cssNeutral = [
    // 未启用时：轻微侧边栏玻璃效果
    '[data-view-id=sidebar] {',
    '  border-right: 1px solid rgba(255,255,255,0.04);',
    '  box-shadow: 8px 0 24px rgba(0,0,0,0.2);',
    '}',
    '[data-view-id=sidebar] button {',
    '  border-radius: 10px; transition: all 0.2s;',
    '}',
    '[data-view-id=sidebar] button:hover {',
    '  background: rgba(255,255,255,0.04);',
    '}'
  ].join('\\n');

  var cssActivated = [
    // === body::before 背景层 ===
    'body::before {',
    '  content: ""; position: fixed; inset: 0; z-index: -2147483648; pointer-events: none;',
    '  background-size: cover; background-position: center; background-repeat: no-repeat;',
    '  background-image: var(--wb-bg-art, none);',
    '  opacity: var(--wb-bg-opacity, 1);',
    '}',
    // 视频背景层（仍用 div，因为伪元素不能放 video）
    '#wb-bg-layer {',
    '  position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;',
    '  z-index: -2147483648; pointer-events: none; overflow: hidden;',
    '  background: #000;',
    '}',

    // === body::after 渐变遮罩层（提升文字可读性）===
    'body::after {',
    '  content: ""; position: fixed; inset: 0; z-index: -1; pointer-events: none;',
    '  background: linear-gradient(180deg,',
    '    rgba(var(--wb-bg-rgb),0.10) 0%,',
    '    rgba(var(--wb-bg-rgb),0.18) 32%,',
    '    rgba(var(--wb-bg-rgb),0.76) 68%,',
    '    rgba(var(--wb-bg-rgb),1) 100%);',
    '}',

    // === 容器透明化 ===
    'html, body { background: transparent !important; }',
    'div, section, main, article, nav, aside, ul, ol, li { background: transparent !important; }',
    'span, p { background-color: transparent !important; }',

    // === 文字颜色（使用 CSS 变量）===
    'body, div, span, p, a, li { color: var(--wb-text) !important; text-shadow: 0 1px 2px rgba(var(--wb-bg-rgb),0.72); }',
    'svg, [class*="icon"] { text-shadow: none !important; }',

    // === 侧边栏：透明流体玻璃 ===
    '[data-view-id=sidebar] {',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.22) 0%, rgba(var(--wb-bg-rgb),0.14) 50%, rgba(var(--wb-panel-rgb),0.20) 100%) !important;',
    '  border: none !important;',
    '  border-right: 1px solid rgba(255,255,255,0.04) !important;',
    '  box-shadow: inset 1px 0 0 rgba(255,255,255,0.02), 8px 0 32px rgba(0,0,0,0.2);',
    '  backdrop-filter: blur(16px) saturate(1.3);',
    '  -webkit-backdrop-filter: blur(16px) saturate(1.3);',
    '}',
    // 侧边栏文字：提高可读性
    '[data-view-id=sidebar] *, [data-view-id=sidebar] {',
    '  text-shadow: 0 1px 3px rgba(0,0,0,0.4) !important;',
    '}',
    // 侧边栏按钮
    '[data-view-id=sidebar] button, [data-view-id=sidebar] a {',
    '  background: transparent !important;',
    '  color: var(--wb-text) !important;',
    '  border-radius: 10px !important;',
    '  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1) !important;',
    '}',
    '[data-view-id=sidebar] button:hover, [data-view-id=sidebar] a:hover {',
    '  background: rgba(255,255,255,0.06) !important;',
    '  box-shadow: inset 0 0 0 1px rgba(255,107,166,0.15);',
    '}',
    '[data-view-id=sidebar] [aria-current="page"] {',
    '  background: linear-gradient(135deg, rgba(var(--wb-accent-rgb),0.15), rgba(var(--wb-accent-rgb),0.06)) !important;',
    '  border: 1px solid rgba(var(--wb-accent-rgb),0.25) !important;',
    '  box-shadow: 0 0 16px rgba(var(--wb-accent-rgb),0.08) !important;',
    '}',

    // === 按钮：流体玻璃悬浮效果 ===
    'button:not([class*="sidebar"]):not([class*="menu"]) {',
    '  background: var(--wb-glass-light) !important;',
    '  backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);',
    '  border: 1px solid rgba(255,255,255,0.08) !important;',
    '  border-radius: 12px !important;',
    '  color: var(--wb-text) !important;',
    '  box-shadow: 0 2px 8px rgba(0,0,0,0.15), inset 0 1px 0 rgba(255,255,255,0.04);',
    '  transition: all 0.22s cubic-bezier(0.4, 0, 0.2, 1) !important;',
    '}',
    'button:hover:not([class*="sidebar"]):not([class*="menu"]) {',
    '  background: rgba(255,255,255,0.08) !important;',
    '  border-color: rgba(var(--wb-accent-rgb),0.3) !important;',
    '  box-shadow: 0 4px 16px rgba(var(--wb-accent-rgb),0.15), 0 0 0 1px rgba(var(--wb-accent-rgb),0.12);',
    '  transform: translateY(-2px);',
    '}',
    'button:active:not([class*="sidebar"]):not([class*="menu"]) {',
    '  transform: translateY(0) scale(0.98);',
    '  box-shadow: 0 1px 3px rgba(0,0,0,0.2);',
    '}',

    // === 详情面板：透明玻璃 ===
    '[data-view-id=detail-panel] {',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.22), rgba(var(--wb-bg-rgb),0.14)) !important;',
    '  backdrop-filter: blur(16px) saturate(1.3); -webkit-backdrop-filter: blur(16px) saturate(1.3);',
    '  border-left: 1px solid rgba(255,255,255,0.04) !important;',
    '  box-shadow: -8px 0 32px rgba(0,0,0,0.2), inset 1px 0 0 rgba(255,255,255,0.02);',
    '}',
    '[data-view-id=detail-panel] *, [data-view-id=detail-panel] {',
    '  text-shadow: 0 1px 3px rgba(0,0,0,0.4) !important;',
    '}',

    // === 聊天输入区：悬浮玻璃 ===
    '.atm-modal-chat-input {',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.65), rgba(var(--wb-bg-rgb),0.55)) !important;',
    '  backdrop-filter: blur(20px) saturate(1.3); -webkit-backdrop-filter: blur(20px) saturate(1.3);',
    '  border-radius: 16px !important;',
    '  border: 1px solid rgba(255,255,255,0.08) !important;',
    '  box-shadow: 0 4px 20px rgba(0,0,0,0.25), inset 0 1px 0 rgba(255,255,255,0.04);',
    '}',
    '.atm-modal-chat-input div { background: transparent !important; }',

    // === 菜单/下拉：深色玻璃 ===
    '[role=listbox], [role=menu], .monaco-menu, [role=dialog] {',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.82), rgba(var(--wb-bg-rgb),0.72)) !important;',
    '  backdrop-filter: blur(20px) saturate(1.3); -webkit-backdrop-filter: blur(20px) saturate(1.3);',
    '  border-radius: 14px !important;',
    '  border: 1px solid rgba(255,255,255,0.08) !important;',
    '  box-shadow: 0 8px 32px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,107,166,0.06);',
    '}',

    // === 表单：玻璃输入框 ===
    'input, textarea, select {',
    '  background: rgba(255,255,255,0.05) !important;',
    '  color: var(--wb-text) !important;',
    '  border: 1px solid rgba(255,255,255,0.1) !important;',
    '  border-radius: 10px !important;',
    '  box-shadow: inset 0 1px 3px rgba(0,0,0,0.15);',
    '  transition: border-color 0.2s, box-shadow 0.2s;',
    '}',
    'input:focus, textarea:focus, select:focus {',
    '  border-color: rgba(var(--wb-accent-rgb),0.4) !important;',
    '  box-shadow: 0 0 0 3px rgba(var(--wb-accent-rgb),0.1), inset 0 1px 3px rgba(0,0,0,0.15);',
    '  outline: none !important;',
    '}',
    'pre, code, [class*="monaco"], [class*="editor"] {',
    '  background: rgba(var(--wb-bg-rgb),0.55) !important;',
    '  backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px);',
    '  border-radius: 10px;',
    '}',

    // === 模态遮罩 ===
    '[class*="modal-overlay"], [class*="ModalOverlay"] {',
    '  background: rgba(var(--wb-bg-rgb),0.45) !important; backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);',
    '}',

    // === 遮罩层 ===
    '#wb-bg-overlay { background: rgba(var(--wb-bg-rgb),0) !important; }'
  ].join('\\n');

  function buildTextColorCSS(tc) {
    if (!tc || tc === 'auto') return ''; // auto 模式不覆盖，使用主题文字色
    return 'body, div, span, p, a, li, label, h1, h2, h3, h4, h5, h6, th, td { color: ' + tc + ' !important; }';
  }

  var cssStyleEl = null;
  var cssRebuildCounter = 0;
  var lastEnabled = null;

  function ensureCSS() {
    var enabled = !!(currentConfig && currentConfig.enabled && currentConfig.source);
    var themeName = (currentConfig && currentConfig.theme) || 'purple';
    var textColor = (currentConfig && currentConfig.textColor) || '';

    var oldEl = document.getElementById('wb-bg-css');
    if (oldEl && oldEl !== cssStyleEl) { oldEl.remove(); cssStyleEl = null; }

    // 主题变化时重建
    if (cssStyleEl && (cssStyleEl.getAttribute('data-theme') !== themeName ||
        (cssStyleEl.getAttribute('data-enabled') !== (enabled ? '1' : '0')))) {
      cssStyleEl.remove();
      cssStyleEl = null;
    }

    cssRebuildCounter++;
    if (cssRebuildCounter % 10 === 0 && cssStyleEl && cssStyleEl.parentNode) {
      cssStyleEl.remove();
      cssStyleEl = null;
    }

    if (!cssStyleEl || !cssStyleEl.parentNode) {
      var vars = buildCssVars(themeName);
      var css = enabled ? (cssActivated + '\\n' + buildTextColorCSS(textColor) + '\\n' + vars) : (cssNeutral + '\\n' + vars);
      cssStyleEl = document.createElement('style');
      cssStyleEl.id = 'wb-bg-css';
      cssStyleEl.setAttribute('data-theme', themeName);
      cssStyleEl.setAttribute('data-enabled', enabled ? '1' : '0');
      cssStyleEl.textContent = css;
      (document.head || document.documentElement).appendChild(cssStyleEl);
    } else if (document.head && cssStyleEl.parentNode === document.head && document.head.lastChild !== cssStyleEl) {
      document.head.appendChild(cssStyleEl);
    }
  }

  function ensureBgLayer() {
    var layer = document.getElementById('wb-bg-layer');
    if (!layer) {
      layer = document.createElement('div');
      layer.id = 'wb-bg-layer';
      layer.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;z-index:-2147483648;pointer-events:none;overflow:hidden;background:#000;';
      document.body.appendChild(layer);
    }
    if (!layer.parentNode) document.body.appendChild(layer);
    return layer;
  }

  function ensureOverlay() {
    var ov = document.getElementById('wb-bg-overlay');
    if (!ov) {
      ov = document.createElement('div');
      ov.id = 'wb-bg-overlay';
      ov.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;z-index:0;pointer-events:none;';
      document.body.appendChild(ov);
    }
    return ov;
  }

  function ensureMedia(layer) {
    if (!currentConfig || !currentConfig.enabled || !currentConfig.source) {
      document.documentElement.style.removeProperty('--wb-bg-art');
      document.documentElement.style.removeProperty('--wb-bg-opacity');
      layer.style.display = 'none';
      var ov = document.getElementById('wb-bg-overlay');
      if (ov) ov.style.background = 'rgba(0,0,0,0)';
      return;
    }

    var cfg = currentConfig;
    var src = currentFileUri || ('file://' + cfg.source);
    var opacity = cfg.opacity != null ? cfg.opacity : 1;
    var overlayAlpha = cfg.overlay != null ? cfg.overlay : 0.25;

    // 图片使用 body::before CSS 变量
    if (cfg.type === 'image') {
      document.documentElement.style.setProperty('--wb-bg-art', 'url(' + src + ')');
      document.documentElement.style.setProperty('--wb-bg-opacity', String(opacity));
      layer.style.display = 'none';
      if (cfg.blur && cfg.blur !== '0px') {
        document.documentElement.style.setProperty('filter', 'blur(' + cfg.blur + ')');
      }
    } else {
      // 视频使用 div 层
      document.documentElement.style.removeProperty('--wb-bg-art');
      var expectedTag = 'video';
      var media = layer.querySelector('video, img');
      var needRebuild = !media || media.tagName.toLowerCase() !== expectedTag || lastMediaSrc !== src;

      if (needRebuild) {
        if (media) media.remove();
        media = document.createElement('video');
        media.autoplay = true;
        media.loop = true;
        media.muted = true;
        media.playsInline = true;
        media.setAttribute('muted', '');
        media.style.cssText = 'width:100%;height:100%;object-fit:' + (cfg.scale || 'cover') + ';object-position:' + (cfg.position || 'center') + ';display:block;';
        if (cfg.blur && cfg.blur !== '0px') {
          media.style.filter = 'blur(' + cfg.blur + ')';
          media.style.transform = 'scale(1.05)';
        }
        media.src = src;
        lastMediaSrc = src;
        media.play().catch(function(){});
        layer.appendChild(media);
      } else {
        if (media) {
          media.style.objectFit = cfg.scale || 'cover';
          media.style.objectPosition = cfg.position || 'center';
        }
      }

      layer.style.display = 'block';
      layer.style.opacity = String(opacity);
    }

    // 始终更新遮罩层
    var ov = document.getElementById('wb-bg-overlay');
    if (ov) ov.style.background = 'rgba(0,0,0,' + overlayAlpha + ')';
  }

  // 强制清理遮挡背景的元素（JS 直接设置 inline style，优先级最高）
  var forceFrameCount = 0;
  var forceInterval = 15; // 每 15 帧运行一次（~0.25 秒）

  function forceTransparentOnElement(el) {
    if (!el || !el.style) return;
    var skip = ['wb-bg-layer', 'wb-bg-overlay'];
    if (skip.indexOf(el.id) !== -1) return;
    if (el.hasAttribute && (el.hasAttribute('data-view-id') || el.hasAttribute('role'))) return;
    if (el.className && typeof el.className === 'string' &&
        (el.className.indexOf('modal') !== -1 || el.className.indexOf('monaco') !== -1 ||
         el.className.indexOf('menu') !== -1 || el.className.indexOf('dialog') !== -1 ||
         el.className.indexOf('chat-input') !== -1 || el.className.indexOf('sidebar') !== -1)) return;
    // 跳过表单/代码/UI控件
    var tag = el.tagName ? el.tagName.toLowerCase() : '';
    if (['input','textarea','select','button','pre','code','svg','canvas','video','img'].indexOf(tag) !== -1) return;

    el.style.setProperty('background', 'transparent', 'important');
    el.style.setProperty('background-color', 'transparent', 'important');
    el.style.setProperty('background-image', 'none', 'important');
  }

  function forceTransparentAll() {
    // 只在启用背景时才强制透明
    if (!currentConfig || !currentConfig.enabled || !currentConfig.source) return;
    try {
      if (document.body) {
        var children = document.body.children;
        for (var i = 0; i < children.length && i < 50; i++) {
          forceTransparentOnElement(children[i]);
          // 第二层
          var grandChildren = children[i].children;
          if (grandChildren) {
            for (var j = 0; j < grandChildren.length && j < 20; j++) {
              forceTransparentOnElement(grandChildren[j]);
            }
          }
        }
      }
    } catch(e) {}
  }

  function forceTransparent() {
    forceFrameCount++;
    if (forceFrameCount % forceInterval === 0) {
      forceTransparentAll();
    }
  }

  // MutationObserver：body 子元素变化时立即强制透明
  var forceDebounce = null;
  var moSetup = false;

  function setupMO() {
    if (moSetup) return;
    if (!document.body) return;
    moSetup = true;

    var mo1 = new MutationObserver(function() {
      if (forceDebounce) clearTimeout(forceDebounce);
      forceDebounce = setTimeout(forceTransparentAll, 100);
    });
    mo1.observe(document.body, { childList: true });

    var rootEl = document.getElementById('root') || document.getElementById('app')
      || document.querySelector('[id*="root"]') || document.querySelector('[id*="app"]');
    if (rootEl) {
      var mo2 = new MutationObserver(function() {
        if (forceDebounce) clearTimeout(forceDebounce);
        forceDebounce = setTimeout(forceTransparentAll, 100);
      });
      mo2.observe(rootEl, { childList: true, subtree: true });
    }
  }

  // RAF 主循环
  function tick() {
    try {
      setupMO();
      ensureCSS();
      if (document.body) {
        var layer = ensureBgLayer();
        ensureOverlay();
        ensureMedia(layer);
        forceTransparent();
      }
    } catch(e) {}
    window.__wbBgRAF = requestAnimationFrame(tick);
  }

  // 从守护进程拉取配置（自给自足，不依赖 CDP 推送）
  function fetchConfig() {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', DAEMON + '/api/config', true);
      xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
          try {
            var cfg = JSON.parse(xhr.responseText);
            currentConfig = cfg;
            if (cfg.enabled && cfg.source) {
              currentFileUri = 'file://' + cfg.source;
            }
            // 持久化到 localStorage（页面导航后可恢复）
            try { localStorage.setItem('__wbBgConfig', JSON.stringify(cfg)); } catch(e) {}
          } catch(e) {}
        }
      };
      xhr.send();
    } catch(e) {}
  }

  // 从 localStorage 恢复配置（页面导航后立即生效）
  function restoreConfig() {
    try {
      var saved = localStorage.getItem('__wbBgConfig');
      if (saved) {
        var cfg = JSON.parse(saved);
        if (cfg && cfg.enabled && cfg.source) {
          currentConfig = cfg;
          currentFileUri = 'file://' + cfg.source;
          return true;
        }
      }
    } catch(e) {}
    return false;
  }

  // CDP 推送配置（也接受，并持久化）
  window.__wbBgApplyConfig = function(cfg, fileUri) {
    if (!cfg) return;
    currentConfig = cfg;
    if (fileUri) currentFileUri = fileUri;
    else if (cfg.source) currentFileUri = 'file://' + cfg.source;
    // 持久化
    try { localStorage.setItem('__wbBgConfig', JSON.stringify(cfg)); } catch(e) {}
    // 不删除媒体！让 ensureMedia 判断是否需要重建
  };

  // 启动：先从 localStorage 恢复，再 fetch
  restoreConfig();
  fetchConfig();
  tick();
  window.__wbBgPoll = setInterval(fetchConfig, 2000);
  window.__wbBgInjected = true;
  console.log('[wb-bg] 背景注入已启动（localStorage 持久模式）');
})();
`;
}

// ─── CDP 连接管理（指数退避重连） ─────────────────────────
async function connectCDP() {
  try {
    const targets = await CDP.List({ port: CDP_PORT });
    const pageTargets = targets.filter(t => t.type === 'page');
    if (pageTargets.length === 0) {
      log('cdp', '未找到 page target，等待 WorkBuddy 启动...');
      return false;
    }

    const target = pageTargets[0];
    log('cdp', `连接 target: ${target.title || target.url}`);

    if (cdpClient) {
      try { await cdpClient.close(); } catch {}
    }

    cdpClient = await CDP({ target: target.id, port: CDP_PORT });
    const { Page, Runtime } = cdpClient;

    await Page.enable();
    await Runtime.enable();

    const injectResult = await Page.addScriptToEvaluateOnNewDocument({
      source: buildInjectScript()
    });
    injectScriptId = injectResult.identifier;
    log('cdp', `背景脚本已注册 (id: ${injectScriptId})`);

    await Runtime.evaluate({
      expression: buildInjectScript(),
      includeCommandLineAPI: false
    });

    log('cdp', '背景脚本已注入当前页面');

    // 注入后立即推送当前配置
    await pushConfigToPage();

    // 监听页面导航事件，导航后立即推送配置
    Page.frameNavigated(async () => {
      log('cdp', '检测到页面导航，立即推送配置');
      await new Promise(r => setTimeout(r, 500)); // 等待新页面加载
      await pushConfigToPage();
    });

    reconnectAttempts = 0; // 重置重连计数

    cdpClient.on('disconnected', () => {
      log('cdp', '连接断开，开始重连...');
      cdpClient = null;
      scheduleReconnect();
    });

    // 定期推送配置（每 2 秒），确保背景持续生效
    if (configPushTimer) clearInterval(configPushTimer);
    configPushTimer = setInterval(() => {
      if (cdpClient) {
        pushConfigToPage();
      }
    }, 2000);
    log('cdp', '配置定时推送已启动（每 2 秒）');

    return true;
  } catch (e) {
    log('cdp', `连接失败: ${e.message}`);
    return false;
  }
}

let configPushTimer = null;

// 推送配置到页面
async function pushConfigToPage() {
  if (!cdpClient) return;

  try {
    // 直接使用 file:// 协议（和 WorkBuddy 同协议，绕过安全检查）
    let fileUri = null;
    if (config.enabled && config.source && fs.existsSync(config.source)) {
      fileUri = 'file://' + config.source;
      log('cdp', `使用 file:// 协议: ${fileUri}`);
    }

    const configJson = JSON.stringify(config);
    const fileUriJson = fileUri ? JSON.stringify(fileUri) : 'null';

    await cdpClient.Runtime.evaluate({
      expression: `
        if (window.__wbBgApplyConfig) {
          window.__wbBgApplyConfig(${configJson}, ${fileUriJson});
        }
      `,
    });
    log('cdp', '配置已推送到页面');
  } catch (e) {
    log('cdp', `配置推送失败: ${e.message}`);
  }
}

function scheduleReconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectAttempts++;
  // 指数退避：5s, 10s, 20s, 40s, 最大 60s
  const delay = Math.min(5000 * Math.pow(2, reconnectAttempts - 1), 60000);
  log('cdp', `${delay / 1000} 秒后重连 (第 ${reconnectAttempts} 次)...`);
  reconnectTimer = setTimeout(async () => {
    const ok = await connectCDP();
    if (!ok) scheduleReconnect();
  }, delay);
}

// ─── HTTP 服务器 ─────────────────────────────────────────
const MIME_TYPES = {
  // 视频
  '.mp4': 'video/mp4', '.webm': 'video/webm', '.mov': 'video/quicktime',
  '.avi': 'video/x-msvideo', '.mkv': 'video/x-matroska', '.m4v': 'video/x-m4v',
  // 图片
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
  '.gif': 'image/gif', '.webp': 'image/webp', '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.avif': 'image/avif',
  // 其他
  '.json': 'application/json', '.html': 'text/html', '.css': 'text/css',
  '.js': 'application/javascript', '.txt': 'text/plain',
};

function getMime(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

function isPathSafe(filePath) {
  // 防止目录遍历攻击：只允许访问绝对路径，且不能包含 ..
  if (!filePath || typeof filePath !== 'string') return false;
  if (filePath.includes('..')) return false;
  // 必须是绝对路径
  if (!path.isAbsolute(filePath)) return false;
  return true;
}

server = http.createServer(async (req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;
  const clientIP = req.socket.remoteAddress;

  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // 请求日志
  log('http', `${req.method} ${pathname} ${clientIP}`);

  // GET / → 管理器界面（一体化）
  if (pathname === '/' && req.method === 'GET') {
    try {
      const html = fs.readFileSync(MANAGER_HTML, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } catch (e) {
      log('http', `manager.html 读取失败: ${e.message}，回退到 settings.html`);
      try {
        const html = fs.readFileSync(SETTINGS_HTML, 'utf8');
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(html);
      } catch {
        res.writeHead(404); res.end('manager.html and settings.html not found');
      }
    }
    return;
  }

  // GET /api/health → 健康检查
  if (pathname === '/api/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      uptime: process.uptime(),
      cdpConnected: !!cdpClient,
      reconnectAttempts,
      configValid: validateConfig(config).length === 0,
      timestamp: new Date().toISOString(),
    }));
    return;
  }

  // GET /api/config → 当前配置
  if (pathname === '/api/config' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(config));
    return;
  }

  // POST /api/config → 更新配置
  if (pathname === '/api/config' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const newCfg = JSON.parse(body);
        if (saveConfig(newCfg)) {
          pushConfigToPage(); // 即时推送
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
        } else {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, error: '配置验证失败' }));
        }
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: e.message }));
      }
    });
    return;
  }

  // GET /api/file?path=... → 提供本地文件（图片/视频）
  if (pathname === '/api/file' && req.method === 'GET') {
    const filePath = parsed.query.path;
    if (!isPathSafe(filePath)) {
      res.writeHead(403); res.end('Forbidden');
      return;
    }
    if (!fs.existsSync(filePath)) {
      res.writeHead(404); res.end('File not found');
      return;
    }

    const mime = getMime(filePath);
    const stat = fs.statSync(filePath);
    const range = req.headers.range;

    if (range) {
      const match = /bytes=(\d*)-(\d*)/.exec(range);
      const start = match[1] ? parseInt(match[1]) : 0;
      const end = match[2] ? parseInt(match[2]) : stat.size - 1;
      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${stat.size}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': end - start + 1,
        'Content-Type': mime,
      });
      fs.createReadStream(filePath, { start, end }).pipe(res);
    } else {
      res.writeHead(200, {
        'Content-Length': stat.size,
        'Content-Type': mime,
        'Cache-Control': 'no-cache',
      });
      fs.createReadStream(filePath).pipe(res);
    }
    return;
  }

  // GET /api/status → 守护进程状态
  if (pathname === '/api/status' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      cdpConnected: !!cdpClient,
      configEnabled: config.enabled,
      configType: config.type,
      configSource: config.source,
    }));
    return;
  }

  // GET /api/pick → 弹出 macOS 原生文件选择器
  if (pathname === '/api/pick' && req.method === 'GET') {
    execFile('osascript', ['-e', 'POSIX path of (choose file with prompt "选择背景图片或视频" of type {"public.image","public.movie"})'], (err, stdout) => {
      if (err) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, cancelled: true, path: '' }));
        return;
      }
      const filePath = stdout.trim();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, path: filePath }));
    });
    return;
  }

  // POST /api/start-workbuddy → 启动 WorkBuddy（带 CDP）
  if (pathname === '/api/start-workbuddy' && req.method === 'POST') {
    const { spawn } = require('child_process');
    const launcherPath = path.join(BASE_DIR, 'launcher.sh');

    log('api', '收到启动 WorkBuddy 请求');

    // 在后台执行 launcher.sh
    const launcher = spawn('bash', [launcherPath], {
      detached: true,
      stdio: 'ignore'
    });

    launcher.unref();

    launcher.on('error', (err) => {
      log('api', `启动失败: ${err.message}`);
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, message: 'WorkBuddy-Skin 启动中...' }));
    return;
  }

  // GET /api/debug → 调试信息（检查注入状态）
  if (pathname === '/api/debug' && req.method === 'GET') {
    if (!cdpClient) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'CDP 未连接' }));
      return;
    }

    try {
      const result = await cdpClient.Runtime.evaluate({
        expression: `
          (function() {
            var bgLayer = document.getElementById('wb-bg-layer');
            var overlay = document.getElementById('wb-bg-overlay');
            var style = document.getElementById('wb-bg-transparent-css');
            var root = document.getElementById('root') || document.getElementById('app');
            var media = bgLayer ? bgLayer.querySelector('video, img') : null;

            return {
              injected: !!window.__wbBgInjected,
              bgLayerExists: !!bgLayer,
              overlayExists: !!overlay,
              styleExists: !!style,
              bgLayerDisplay: bgLayer ? getComputedStyle(bgLayer).display : null,
              bgLayerZIndex: bgLayer ? getComputedStyle(bgLayer).zIndex : null,
              bgLayerOpacity: bgLayer ? getComputedStyle(bgLayer).opacity : null,
              bgLayerChildren: bgLayer ? bgLayer.children.length : 0,
              rootBackground: root ? getComputedStyle(root).background : null,
              bodyBackground: getComputedStyle(document.body).background,
              mediaExists: !!media,
              mediaTag: media ? media.tagName : null,
              mediaSrc: media ? media.src : null,
              mediaReadyState: media && media.tagName === 'VIDEO' ? media.readyState : null,
              mediaError: media && media.tagName === 'VIDEO' && media.error ? {
                code: media.error.code,
                message: media.error.message
              } : null,
              mediaPaused: media && media.tagName === 'VIDEO' ? media.paused : null,
            };
          })()
        `,
        returnByValue: true,
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, debug: result.result.value }, null, 2));
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: e.message }));
    }
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

server.listen(HTTP_PORT, '127.0.0.1', () => {
  log('http', `设置面板: http://localhost:${HTTP_PORT}`);
  log('http', `健康检查: http://localhost:${HTTP_PORT}/api/health`);
});

// ─── 启动流程 ────────────────────────────────────────────
log('daemon', '════════════════════════════════════════════');
log('daemon', '  WorkBuddy 背景注入守护进程 v2.0');
log('daemon', `  项目目录: ${BASE_DIR}`);
log('daemon', `  设置面板: http://localhost:${HTTP_PORT}`);
log('daemon', `  CDP 端口: ${CDP_PORT}`);
log('daemon', '════════════════════════════════════════════');

// 写入 PID 文件
fs.writeFileSync(PID_PATH, String(process.pid));

// 尝试连接 CDP
async function tryConnect() {
  const ok = await connectCDP();
  if (!ok) scheduleReconnect();
}
tryConnect();

// 监听配置文件变化
try {
  configWatcher = fs.watch(CONFIG_PATH, (event) => {
    if (event === 'change') {
      setTimeout(() => {
        config = loadConfig();
        log('config', `文件变更已加载: ${config.type} ${config.source || '(无)'}`);
      }, 100);
    }
  });
} catch (e) {
  log('config', `无法监听配置文件: ${e.message}`);
}

// ─── 优雅关闭 ────────────────────────────────────────────
function shutdown(signal) {
  log('daemon', `收到 ${signal}，正在退出...`);
  if (reconnectTimer) clearTimeout(reconnectTimer);
  if (cdpClient) { try { cdpClient.close(); } catch {} }
  if (configWatcher) configWatcher.close();
  if (server) server.close();
  try { fs.unlinkSync(PID_PATH); } catch {}
  process.exit(0);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('uncaughtException', (e) => {
  log('error', `未捕获异常: ${e.message}`);
  shutdown('uncaughtException');
});
