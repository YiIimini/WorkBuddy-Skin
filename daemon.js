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

// 依赖路径多候选解析（跨平台：macOS 托管目录 / 项目本地 / 环境变量 / 全局）
const DEP_CANDIDATES = [
  process.env.WBSKIN_NODE_MODULES,
  path.join(BASE_DIR, 'node_modules'),
  '/Users/x/.workbuddy/binaries/node/workspace/node_modules',
].filter(Boolean);

function requireFromCandidates(name) {
  for (const p of DEP_CANDIDATES) {
    try { return require(path.join(p, name)); } catch {}
  }
  return require(name); // 兜底：标准解析（全局或上级 node_modules）
}

function resolveDist(rel) {
  for (const p of DEP_CANDIDATES) {
    const f = path.join(p, rel);
    if (fs.existsSync(f)) return f;
  }
  return null;
}

const CDP = requireFromCandidates('chrome-remote-interface');

// GSAP 库路径（通过 /vendor/gsap.min.js 提供给注入页面；未安装时路由返回 404，注入侧静默降级）
const GSAP_DIST = resolveDist(path.join('gsap', 'dist', 'gsap.min.js'));

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

  // 代际守卫：每次注入递增全局代际号，旧 RAF 循环检测到代际不符即自毁，
  // 防止多次注入（守护进程重启/重复 evaluate）导致新旧脚本循环互抢样式表
  window.__wbBgGen = (window.__wbBgGen || 0) + 1;
  var __gen = window.__wbBgGen;
  // 立即清除旧样式表残影（含历史版本注入的）
  try { var staleCss = document.getElementById('wb-bg-css'); if (staleCss) staleCss.remove(); } catch(e) {}

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
    '  filter: var(--wb-bg-blur, none);',
    '  transform: var(--wb-bg-scale, none);',
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

    // === 文字颜色（使用 CSS 变量；排除 pre/code 子树，保留语法高亮 hljs 配色）===
    'body:not(pre *):not(code *), div:not(pre *):not(code *), span:not(pre *):not(code *), p:not(pre *):not(code *), a:not(pre *):not(code *), li:not(pre *):not(code *) { color: var(--wb-text) !important; text-shadow: 0 1px 2px rgba(var(--wb-bg-rgb),0.72); }',
    'svg, [class*="icon"] { text-shadow: none !important; }',
    'pre, pre *, code, code *, .hljs, .hljs *, [class*="execute-command"], [class*="execute-command"] * { text-shadow: none !important; }',

    // === 终端命令组件：实底代码风格 + 等宽字体 + 可横向滚动看全内容 ===
    '[class*="execute-command"] {',
    '  background: rgba(var(--wb-bg-rgb),0.68) !important;',
    '  border: 1px solid rgba(var(--wb-accent-rgb),0.16) !important;',
    '  border-radius: 10px !important;',
    '  box-shadow: inset 0 1px 0 rgba(255,255,255,0.03) !important;',
    '}',
    '[class*="execute-command"] [class*="__command"] {',
    '  font-family: "SF Mono", Menlo, Consolas, monospace !important;',
    '  font-size: 12.5px !important;',
    '  color: var(--wb-text) !important;',
    '}',
    '[class*="execute-command"] [class*="__header"], [class*="execute-command"] [class*="__command"] {',
    '  overflow-x: auto !important;',
    '  text-overflow: clip !important;',
    '  scrollbar-width: thin;',
    '}',

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
    '  transition: background 0.2s, box-shadow 0.2s, border-color 0.2s, color 0.2s !important;',
    '  will-change: transform;',
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

    // === 按钮：流体玻璃悬浮效果（transform 交由 GSAP 驱动，CSS 只过渡颜色/阴影）===
    'button:not([class*="sidebar"]):not([class*="menu"]) {',
    '  background: var(--wb-glass-light) !important;',
    '  backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);',
    '  border: 1px solid rgba(255,255,255,0.08) !important;',
    '  border-radius: 12px !important;',
    '  color: var(--wb-text) !important;',
    '  box-shadow: 0 2px 8px rgba(0,0,0,0.15), inset 0 1px 0 rgba(255,255,255,0.04);',
    '  transition: background 0.2s, border-color 0.2s, box-shadow 0.2s, color 0.2s !important;',
    '  will-change: transform;',
    '}',
    'button:hover:not([class*="sidebar"]):not([class*="menu"]) {',
    '  background: rgba(255,255,255,0.08) !important;',
    '  border-color: rgba(var(--wb-accent-rgb),0.3) !important;',
    '  box-shadow: 0 4px 16px rgba(var(--wb-accent-rgb),0.15), 0 0 0 1px rgba(var(--wb-accent-rgb),0.12);',
    '}',
    'button:active:not([class*="sidebar"]):not([class*="menu"]) {',
    '  box-shadow: 0 1px 3px rgba(0,0,0,0.2);',
    '}',

    // === 文字/链接按钮：主题色 + 悬浮下划线（窗口中的纯文字按钮）===
    '[class*="text-button"], [class*="TextButton"], [class*="link-button"], [class*="LinkButton"], [role="link"], button[class*="text-only"] {',
    '  background: transparent !important;',
    '  border: none !important;',
    '  box-shadow: none !important;',
    '  color: var(--wb-accent) !important;',
    '  font-weight: 500 !important;',
    '  text-underline-offset: 3px;',
    '  transition: color 0.2s, text-decoration-color 0.2s !important;',
    '}',
    '[class*="text-button"]:hover, [class*="TextButton"]:hover, [class*="link-button"]:hover, [class*="LinkButton"]:hover, [role="link"]:hover, button[class*="text-only"]:hover {',
    '  text-decoration: underline;',
    '  text-decoration-color: rgba(var(--wb-accent-rgb),0.7);',
    '  filter: brightness(1.15);',
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

    // === 聊天输入区：悬浮玻璃（--wb-glow/--wb-type 由 GSAP 驱动，CSS 不含 box-shadow 过渡）===
    '.atm-modal-chat-input {',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.65), rgba(var(--wb-bg-rgb),0.55)) !important;',
    '  backdrop-filter: blur(20px) saturate(1.3); -webkit-backdrop-filter: blur(20px) saturate(1.3);',
    '  border-radius: 16px !important;',
    '  border: 1px solid rgba(255,255,255,0.08) !important;',
    '  box-shadow: 0 4px 20px rgba(0,0,0,0.25),',
    '    0 0 calc(var(--wb-glow, 0) * 28px) rgba(var(--wb-accent-rgb), calc(var(--wb-glow, 0) * 0.28)),',
    '    0 0 0 calc(var(--wb-glow, 0) * 1.5px) rgba(var(--wb-accent-rgb), calc(var(--wb-glow, 0) * 0.50)),',
    '    0 0 calc(var(--wb-type, 0) * 18px) rgba(var(--wb-accent-rgb), calc(var(--wb-type, 0) * 0.35)),',
    '    inset 0 1px 0 rgba(255,255,255,0.04);',
    '  transition: border-color 0.25s, background 0.25s !important;',
    '  will-change: transform, box-shadow;',
    '}',
    '.atm-modal-chat-input:focus-within {',
    '  border-color: rgba(var(--wb-accent-rgb),0.45) !important;',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.72), rgba(var(--wb-bg-rgb),0.62)) !important;',
    '}',
    '.atm-modal-chat-input div { background: transparent !important; }',

    // === 菜单/下拉：深色玻璃 ===
    '[role=listbox], [role=menu], .monaco-menu, [role=dialog] {',
    '  background: linear-gradient(180deg, rgba(var(--wb-panel-rgb),0.82), rgba(var(--wb-bg-rgb),0.72)) !important;',
    '  backdrop-filter: blur(20px) saturate(1.3); -webkit-backdrop-filter: blur(20px) saturate(1.3);',
    '  border-radius: 14px !important;',
    '  border: 1px solid rgba(255,255,255,0.08) !important;',
    '  box-shadow: 0 8px 32px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,107,166,0.06);',
    '  transform-origin: top center;',
    '  will-change: transform, opacity;',
    '}',

    // === 表单：高可读性玻璃输入框 ===
    'input:not([type=button]):not([type=submit]), textarea, select, [contenteditable], .ProseMirror {',
    '  background: rgba(255,255,255,0.10) !important;',
    '  color: var(--wb-text) !important;',
    '  border: 1px solid rgba(255,255,255,0.15) !important;',
    '  border-radius: 10px !important;',
    '  box-shadow: inset 0 1px 3px rgba(0,0,0,0.15);',
    '  text-shadow: none !important;',
    '  caret-color: var(--wb-accent) !important;',
    '}',
    'textarea, [contenteditable], .ProseMirror {',
    '  line-height: 1.7 !important;',
    '  letter-spacing: 0.012em !important;',
    '  font-size: 14px !important;',
    '  word-break: break-word !important;',
    '}',
    'input, textarea { padding: 8px 12px !important; }',
    '.ProseMirror { padding: 6px 8px !important; }',
    'body { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }',
    'input:focus, textarea:focus, select:focus, [contenteditable]:focus, .ProseMirror-focused {',
    '  border-color: rgba(var(--wb-accent-rgb),0.5) !important;',
    '  box-shadow: 0 0 0 3px rgba(var(--wb-accent-rgb),0.12), inset 0 1px 3px rgba(0,0,0,0.15);',
    '  outline: none !important;',
    '  background: rgba(255,255,255,0.15) !important;',
    '}',
    'pre, code, [class*="monaco"], [class*="editor"] {',
    '  background: rgba(var(--wb-bg-rgb),0.6) !important;',
    '  color: var(--wb-text) !important;',
    '  border: 1px solid rgba(var(--wb-accent-rgb),0.12) !important;',
    '  border-radius: 10px !important;',
    '  text-shadow: none !important;',
    '}',

    // === 语法高亮配色（宿主 hljs 无 token 配色，补 VS Code Dark+ 调色板）===
    '.hljs-keyword, .hljs-selector-tag, .hljs-tag { color: #c586c0 !important; }',
    '.hljs-string, .hljs-attr, .hljs-attribute, .hljs-regexp { color: #ce9178 !important; }',
    '.hljs-comment, .hljs-quote { color: #6a9955 !important; font-style: italic; }',
    '.hljs-number, .hljs-literal { color: #b5cea8 !important; }',
    '.hljs-title, .hljs-name, .hljs-section { color: #dcdcaa !important; }',
    '.hljs-type, .hljs-class, .hljs-built_in { color: #4ec9b0 !important; }',
    '.hljs-selector-id, .hljs-selector-class, .hljs-symbol { color: #4fc1ff !important; }',
    '.hljs-variable, .hljs-template-variable, .hljs-params { color: #9cdcfe !important; }',
    '.hljs-meta, .hljs-operator, .hljs-punctuation { color: #d4d4d4 !important; }',

    // === 文本选择 & 光标美化（GSAP 焦点光晕的静态底座）===
    '::selection { background: rgba(var(--wb-accent-rgb),0.38) !important; color: #ffffff !important; text-shadow: none !important; }',
    'input, textarea, [contenteditable], .ProseMirror { caret-color: var(--wb-accent) !important; }',
    'input::placeholder, textarea::placeholder { color: rgba(var(--wb-muted-rgb),0.55) !important; font-style: normal; }',
    '.ProseMirror p.is-editor-empty:first-child::before { color: rgba(var(--wb-muted-rgb),0.55) !important; }',

    // === 深度思考内容：去模糊（实底玻璃 + 无阴影 + 全不透明度）===
    '[class*="think"], [class*="Think"], [class*="reason"], [class*="Reason"], [data-thinking] {',
    '  background: rgba(var(--wb-bg-rgb),0.62) !important;',
    '  backdrop-filter: none !important; -webkit-backdrop-filter: none !important;',
    '  filter: none !important; opacity: 1 !important;',
    '  border: 1px solid rgba(255,255,255,0.07) !important;',
    '  border-radius: 12px !important;',
    '}',
    '[class*="think"] *, [class*="Think"] *, [class*="reason"] *, [class*="Reason"] *, [data-thinking] * {',
    '  text-shadow: none !important;',
    '  opacity: 1 !important;',
    '  filter: none !important;',
    '  color: var(--wb-text) !important;',
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
      document.documentElement.style.removeProperty('--wb-bg-blur');
      document.documentElement.style.removeProperty('--wb-bg-scale');
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
        document.documentElement.style.setProperty('--wb-bg-blur', 'blur(' + cfg.blur + ')');
        document.documentElement.style.setProperty('--wb-bg-scale', 'scale(1.05)');
      } else {
        document.documentElement.style.removeProperty('--wb-bg-blur');
        document.documentElement.style.removeProperty('--wb-bg-scale');
      }
    } else {
      // 视频使用 div 层
      document.documentElement.style.removeProperty('--wb-bg-art');
      document.documentElement.style.removeProperty('--wb-bg-blur');
      document.documentElement.style.removeProperty('--wb-bg-scale');
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
         el.className.indexOf('chat-input') !== -1 || el.className.indexOf('sidebar') !== -1 ||
         el.className.indexOf('command') !== -1 || el.className.indexOf('markdown-pre') !== -1 ||
         el.className.indexOf('think') !== -1 || el.className.indexOf('Think') !== -1 ||
         el.className.indexOf('reason') !== -1 || el.className.indexOf('Reason') !== -1)) return;
    // 跳过表单/代码/UI控件
    var tag = el.tagName ? el.tagName.toLowerCase() : '';
    if (['input','textarea','select','button','pre','code','svg','canvas','video','img'].indexOf(tag) !== -1) return;
    if (el.isContentEditable) return;

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
    if (window.__wbBgGen !== __gen) return; // 已有更新版本接管，本旧循环退出
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

  // ═══ GSAP 动效美化（按钮 / 弹窗 / 输入焦点光晕） ═══
  var reduceMotion = false;
  try { reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}

  function accentRgb() {
    var v = '255,107,166';
    try {
      var c = getComputedStyle(document.documentElement).getPropertyValue('--wb-accent-rgb');
      if (c && c.trim()) v = c.trim();
    } catch (e) {}
    return v;
  }

  function loadGsap(cb) {
    if (window.gsap) { cb(window.gsap); return; }
    var s = document.createElement('script');
    s.src = DAEMON + '/vendor/gsap.min.js';
    s.async = true;
    s.onload = function () { if (window.gsap) cb(window.gsap); };
    (document.head || document.documentElement).appendChild(s);
  }

  function initGsapUI(g) {
    if (window.__wbGsapUi) return;
    window.__wbGsapUi = true;
    if (reduceMotion) return; // 尊重系统"减少动态效果"，保留静态美化

    g.defaults({ duration: 0.25, ease: 'power2.out' });

    // ── 1. 按钮：磁吸悬浮 + 按压回弹（事件委托，兼容 React 动态 DOM）──
    var hoverBtn = null;

    function btnOf(t) {
      if (!t || !t.closest) return null;
      var b = t.closest('button, [role="button"]');
      if (!b || b.disabled || b.getAttribute('aria-disabled') === 'true') return null;
      return b;
    }

    document.addEventListener('pointerover', function (e) {
      var b = btnOf(e.target);
      if (!b || b === hoverBtn) return;
      if (hoverBtn) g.to(hoverBtn, { y: 0, scale: 1, duration: 0.3, overwrite: 'auto' });
      hoverBtn = b;
      g.to(b, { y: -2, scale: 1.04, duration: 0.28, ease: 'back.out(2.2)', overwrite: 'auto' });
    }, true);

    document.addEventListener('pointerout', function (e) {
      var b = btnOf(e.target);
      if (!b || b !== hoverBtn) return;
      if (e.relatedTarget && b.contains(e.relatedTarget)) return; // 子元素间移动不触发
      hoverBtn = null;
      g.to(b, { y: 0, scale: 1, duration: 0.32, ease: 'power2.out', overwrite: 'auto' });
    }, true);

    document.addEventListener('pointerdown', function (e) {
      var b = btnOf(e.target);
      if (!b) return;
      g.to(b, { scale: 0.94, y: 0, duration: 0.1, ease: 'power2.in', overwrite: 'auto' });
    }, true);

    document.addEventListener('pointerup', function (e) {
      var b = btnOf(e.target);
      if (!b) return;
      var still = (b === hoverBtn); // 回弹到悬浮态或静止态
      g.to(b, { scale: still ? 1.04 : 1, y: still ? -2 : 0, duration: 0.45, ease: 'elastic.out(1, 0.45)', overwrite: 'auto' });
    }, true);

    // ── 2. 弹窗/菜单/对话框：弹簧进场 + 子项 stagger（MutationObserver 捕获动态新增）──
    var POPUP_SEL = '[role="menu"], [role="listbox"], [role="dialog"], [role="alertdialog"], [role="tooltip"], .monaco-menu';
    var ITEM_SEL = '[role="menuitem"], [role="option"], [role="menuitemcheckbox"], [role="menuitemradio"]';
    var pending = [];
    var flushScheduled = false;

    function animatePopup(el) {
      if (el.__wbAnimated) return;
      el.__wbAnimated = true;
      var isTip = el.getAttribute('role') === 'tooltip';
      var tl = g.timeline();
      tl.fromTo(el,
        { autoAlpha: 0, y: isTip ? 4 : -10, scale: isTip ? 1 : 0.96 },
        { autoAlpha: 1, y: 0, scale: 1, duration: isTip ? 0.2 : 0.34, ease: isTip ? 'power2.out' : 'back.out(1.7)' });
      var items = el.querySelectorAll(ITEM_SEL);
      if (items.length) {
        var list = Array.prototype.slice.call(items, 0, 14);
        tl.fromTo(list, { autoAlpha: 0, x: -6 }, { autoAlpha: 1, x: 0, duration: 0.18, stagger: 0.024, ease: 'power2.out' }, '-=0.18');
      }
    }

    function flushPopups() {
      flushScheduled = false;
      var nodes = pending; pending = [];
      for (var i = 0; i < nodes.length && i < 60; i++) {
        var n = nodes[i];
        if (n.nodeType !== 1) continue;
        try {
          if (n.matches && n.matches(POPUP_SEL)) animatePopup(n);
          var found = n.querySelectorAll ? n.querySelectorAll(POPUP_SEL) : [];
          for (var k = 0; k < found.length && k < 8; k++) animatePopup(found[k]);
        } catch (e) {}
      }
    }

    var popupMO = new MutationObserver(function (recs) {
      for (var i = 0; i < recs.length; i++) {
        var added = recs[i].addedNodes;
        for (var j = 0; j < added.length; j++) pending.push(added[j]);
      }
      if (!flushScheduled && pending.length) {
        flushScheduled = true;
        requestAnimationFrame(flushPopups); // rAF 批处理，避免高频 DOM 变动抖动
      }
    });
    popupMO.observe(document.documentElement, { childList: true, subtree: true });

    // ── 3. 输入框：字段呼吸光晕 + 聊天容器聚焦悬浮 + 打字辉光 ──
    var INPUT_SEL = 'input:not([type=button]):not([type=submit]):not([type=checkbox]):not([type=radio]), textarea, [contenteditable="true"], .ProseMirror';
    var CHATBOX_SEL = '.atm-modal-chat-input';

    function chatBoxOf(el) { return el && el.closest ? el.closest(CHATBOX_SEL) : null; }

    document.addEventListener('focusin', function (e) {
      var t = e.target;
      var el = (t && t.matches && t.matches(INPUT_SEL)) ? t
        : (t && t.closest ? t.closest('[contenteditable="true"], .ProseMirror') : null);
      if (!el) return;
      if (el.__wbFocusTl) { el.__wbFocusTl.kill(); el.__wbFocusTl = null; }
      var rgb = accentRgb();
      var glowA = '0 0 0 3px rgba(' + rgb + ',0.10), 0 0 12px rgba(' + rgb + ',0.10), inset 0 1px 3px rgba(0,0,0,0.15)';
      var glowB = '0 0 0 3px rgba(' + rgb + ',0.24), 0 0 22px rgba(' + rgb + ',0.20), inset 0 1px 3px rgba(0,0,0,0.15)';
      g.fromTo(el,
        { boxShadow: '0 0 0 0 rgba(' + rgb + ',0), inset 0 1px 3px rgba(0,0,0,0.15)' },
        { boxShadow: glowA, duration: 0.28, ease: 'power2.out', overwrite: 'auto' });
      // 呼吸光晕（失焦时 kill，防止泄漏）
      el.__wbFocusTl = g.timeline({ repeat: -1, yoyo: true, delay: 0.3 })
        .to(el, { boxShadow: glowB, duration: 1.1, ease: 'sine.inOut' });
      // 聊天容器：聚焦悬浮 + 光环点亮（GSAP 驱动 CSS 变量 --wb-glow）
      var box = chatBoxOf(el);
      if (box) {
        g.to(box, { y: -3, '--wb-glow': 1, duration: 0.4, ease: 'power3.out', overwrite: 'auto' });
      }
    }, true);

    document.addEventListener('focusout', function (e) {
      var el = e.target;
      if (!el) return;
      if (el.__wbFocusTl) {
        el.__wbFocusTl.kill(); el.__wbFocusTl = null;
        g.to(el, { boxShadow: 'inset 0 1px 3px rgba(0,0,0,0.15)', duration: 0.3, ease: 'power2.out', overwrite: 'auto' });
      }
      var box = chatBoxOf(el);
      if (box) {
        g.to(box, { y: 0, '--wb-glow': 0, '--wb-type': 0, duration: 0.45, ease: 'power2.out', overwrite: 'auto' });
      }
    }, true);

    // 打字辉光：每次击键点亮 --wb-type，停笔后自然衰减
    document.addEventListener('input', function (e) {
      var t = e.target;
      var el = (t && t.matches && t.matches(INPUT_SEL)) ? t
        : (t && t.closest ? t.closest('[contenteditable="true"], .ProseMirror') : null);
      if (!el) return;
      var box = chatBoxOf(el) || el;
      g.set(box, { '--wb-type': 0.85 });
      g.to(box, { '--wb-type': 0, duration: 0.9, ease: 'power2.out', delay: 0.25, overwrite: 'auto' });
    }, true);

    // 聊天容器首次出现：上浮进场（最多轮询 30 秒，兼容异步渲染）
    var chatSeen = false;
    var chatCheck = setInterval(function () {
      var box = document.querySelector(CHATBOX_SEL);
      if (box) {
        chatSeen = true;
        clearInterval(chatCheck);
        g.fromTo(box, { autoAlpha: 0, y: 24 }, { autoAlpha: 1, y: 0, duration: 0.6, ease: 'power3.out' });
      }
    }, 800);
    setTimeout(function () { if (!chatSeen) clearInterval(chatCheck); }, 30000);

    // ── 4. 自定义高亮光标：原生 caret 上叠加发光层（GSAP 呼吸闪烁）──
    var caretEl = null;
    var caretVisible = false;

    function ensureCaret() {
      if (!caretEl || !caretEl.parentNode) {
        caretEl = document.createElement('div');
        caretEl.id = 'wb-caret';
        document.body.appendChild(caretEl);
      }
      return caretEl;
    }

    function caretFieldOf() {
      var ae = document.activeElement;
      if (!ae) return null;
      if (ae.isContentEditable || (ae.classList && ae.classList.contains('ProseMirror'))) return ae;
      if (ae.closest) return ae.closest('[contenteditable="true"], .ProseMirror');
      return null;
    }

    function caretRect() {
      // 仅对 contenteditable/ProseMirror 精确定位；input/textarea 用原生彩色 caret 即可
      if (!caretFieldOf()) return null;
      try {
        var sel = window.getSelection();
        if (!sel || !sel.rangeCount) return null;
        var r = sel.getRangeAt(0).cloneRange();
        r.collapse(true);
        var rects = r.getClientRects();
        if (rects && rects.length) return rects[0];
        var br = r.getBoundingClientRect();
        if (br && (br.height || br.top)) return br;
      } catch (e) {}
      return null;
    }

    function paintCaretStyle(c) {
      var rgb = accentRgb();
      c.style.cssText = 'position:fixed;z-index:2147483646;pointer-events:none;width:2px;border-radius:2px;opacity:0;'
        + 'background:linear-gradient(180deg, rgba(' + rgb + ',0.95), rgba(' + rgb + ',0.60));'
        + 'box-shadow:0 0 6px rgba(' + rgb + ',0.85), 0 0 16px rgba(' + rgb + ',0.45);';
    }

    function updateCaret() {
      var rc = caretRect();
      if (!rc) { hideCaret(); return; }
      var c = ensureCaret();
      paintCaretStyle(c);
      c.style.left = rc.left + 'px';
      c.style.top = rc.top + 'px';
      c.style.height = (rc.height || 18) + 'px';
      if (!caretVisible) {
        caretVisible = true;
        g.to(c, { opacity: 0.95, duration: 0.18, ease: 'power2.out' });
        c.__wbPulse = g.timeline({ repeat: -1, yoyo: true })
          .to(c, { opacity: 0.35, duration: 0.55, ease: 'sine.inOut' });
      }
    }

    function hideCaret() {
      if (!caretEl || !caretVisible) return;
      caretVisible = false;
      if (caretEl.__wbPulse) { caretEl.__wbPulse.kill(); caretEl.__wbPulse = null; }
      g.to(caretEl, { opacity: 0, duration: 0.15, ease: 'power1.out' });
    }

    var caretRaf = false;
    function scheduleCaret() {
      if (caretRaf) return;
      caretRaf = true;
      requestAnimationFrame(function () { caretRaf = false; updateCaret(); });
    }
    document.addEventListener('selectionchange', scheduleCaret);
    document.addEventListener('scroll', scheduleCaret, true);
    document.addEventListener('focusout', hideCaret, true);

    console.log('[wb-bg] GSAP UI 动效已启用');
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
  loadGsap(initGsapUI); // 异步加载 GSAP 并启用 UI 动效（失败时静默降级为静态美化）
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

  // GET /vendor/gsap.min.js → GSAP 动画库（供注入页面加载）
  if (pathname === '/vendor/gsap.min.js' && req.method === 'GET') {
    try {
      const js = fs.readFileSync(GSAP_DIST);
      res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8', 'Cache-Control': 'no-cache' });
      res.end(js);
    } catch (e) {
      log('http', `gsap.min.js 读取失败: ${e.message}`);
      res.writeHead(404); res.end('gsap not installed');
    }
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

  // GET /api/pick → 弹出系统原生文件选择器（macOS: osascript / Windows: PowerShell）
  if (pathname === '/api/pick' && req.method === 'GET') {
    if (process.platform === 'win32') {
      const ps = 'Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = "图片/视频|*.jpg;*.jpeg;*.png;*.gif;*.webp;*.bmp;*.mp4;*.webm;*.mov;*.mkv"; if ($d.ShowDialog() -eq "OK") { $d.FileName }';
      execFile('powershell', ['-NoProfile', '-Command', ps], (err, stdout) => {
        if (err || !stdout.trim()) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, cancelled: true, path: '' }));
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, path: stdout.trim() }));
      });
      return;
    }
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

  // POST /api/start-workbuddy → 启动 WorkBuddy（带 CDP，按平台选择启动器）
  if (pathname === '/api/start-workbuddy' && req.method === 'POST') {
    const { spawn } = require('child_process');
    const isWin = process.platform === 'win32';
    const launcherPath = path.join(BASE_DIR, isWin ? 'launcher.ps1' : 'launcher.sh');

    log('api', `收到启动 WorkBuddy 请求（${isWin ? 'Windows' : 'macOS'}）`);

    // 在后台执行启动器
    const launcher = isWin
      ? spawn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', launcherPath], { detached: true, stdio: 'ignore' })
      : spawn('bash', [launcherPath], { detached: true, stdio: 'ignore' });

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
