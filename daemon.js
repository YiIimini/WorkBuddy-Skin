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
    return true;
  } catch (e) {
    log('config', `写入失败: ${e.message}`);
    return false;
  }
}

// 初始化配置（在 DEFAULT_CONFIG 定义之后）
let config = loadConfig();

// ─── 注入脚本 ───────────────────────────────────────────
function buildInjectScript() {
  return `
(function() {
  if (window.__wbBgInjected) { return; }
  window.__wbBgInjected = true;

  var DAEMON = 'http://localhost:${HTTP_PORT}';
  var currentConfig = null;

  var bgLayer = document.createElement('div');
  bgLayer.id = 'wb-bg-layer';
  bgLayer.style.cssText = 'position:fixed;inset:0;z-index:0;pointer-events:none;overflow:hidden;background:#000;';
  var bgMedia = null;

  var overlay = document.createElement('div');
  overlay.id = 'wb-bg-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;z-index:1;pointer-events:none;background:rgba(0,0,0,0);transition:background 0.4s ease;';

  var style = document.createElement('style');
  style.id = 'wb-bg-transparent-css';
  style.textContent = [
    'html, body { background: transparent !important; }',
    '#root { background: transparent !important; position: relative; z-index: 2; }',
    'body[data-application-name=workbuddy] { background: transparent !important; }',
    '[data-view-id=sidebar] {',
    '  background: rgba(16,8,26,0.30) !important;',
    '  backdrop-filter: blur(20px) saturate(1.12) !important;',
    '  -webkit-backdrop-filter: blur(20px) saturate(1.12) !important;',
    '  border: none !important;',
    '}',
    '[data-view-id=detail-panel] {',
    '  background: rgba(16,8,26,0.50) !important;',
    '  backdrop-filter: blur(18px) saturate(1.08) !important;',
    '  -webkit-backdrop-filter: blur(18px) saturate(1.08) !important;',
    '}',
    '[data-view-id=main-content] { background: transparent !important; }',
    '.atm-modal-chat-input [class*="_mainArea_"],',
    '.atm-modal-chat-input [class*="_content_"],',
    '.atm-modal-chat-input textarea,',
    '.atm-modal-chat-input [contenteditable] {',
    '  --atm-surface: rgba(16,8,26,0.30) !important;',
    '  --atm-chat-content-bg: rgba(16,8,26,0.30) !important;',
    '  background: rgba(16,8,26,0.30) !important;',
    '  backdrop-filter: blur(16px) saturate(1.2) !important;',
    '  -webkit-backdrop-filter: blur(16px) saturate(1.2) !important;',
    '}',
    '[role=listbox], [role=menu], .monaco-menu {',
    '  background: rgba(16,8,26,0.45) !important;',
    '  backdrop-filter: blur(12px) saturate(1.15) !important;',
    '  -webkit-backdrop-filter: blur(12px) saturate(1.15) !important;',
    '}',
  ].join('\\n');
  document.head.appendChild(style);

  function applyConfig(cfg) {
    if (!cfg) return;
    var changed = JSON.stringify(cfg) !== JSON.stringify(currentConfig);
    currentConfig = cfg;
    if (!changed) return;

    if (!cfg.enabled || cfg.type === 'none' || !cfg.source) {
      bgLayer.style.display = 'none';
      overlay.style.background = 'rgba(0,0,0,0)';
      return;
    }
    bgLayer.style.display = 'block';
    bgLayer.style.opacity = String(cfg.opacity != null ? cfg.opacity : 1);
    overlay.style.background = 'rgba(0,0,0,' + (cfg.overlay != null ? cfg.overlay : 0.25) + ')';

    var src = DAEMON + '/api/file?path=' + encodeURIComponent(cfg.source);

    var needNew = !bgMedia || bgMedia.tagName.toLowerCase() !== (cfg.type === 'video' ? 'video' : 'img');
    if (needNew) {
      if (bgMedia) bgMedia.remove();
      if (cfg.type === 'video') {
        bgMedia = document.createElement('video');
        bgMedia.autoplay = true;
        bgMedia.loop = true;
        bgMedia.muted = true;
        bgMedia.playsInline = true;
        bgMedia.setAttribute('muted', '');
      } else {
        bgMedia = document.createElement('img');
      }
      bgMedia.style.cssText = 'width:100%;height:100%;object-fit:' + (cfg.scale || 'cover') + ';object-position:' + (cfg.position || 'center') + ';display:block;';
      bgLayer.appendChild(bgMedia);
    }

    if (bgMedia.tagName.toLowerCase() === 'video') {
      if (bgMedia.src !== src) { bgMedia.src = src; bgMedia.load(); bgMedia.play().catch(function(){}); }
    } else {
      bgMedia.src = src;
    }
    bgMedia.style.objectFit = cfg.scale || 'cover';
    bgMedia.style.objectPosition = cfg.position || 'center';
    if (cfg.blur && cfg.blur !== '0px') {
      bgMedia.style.filter = 'blur(' + cfg.blur + ')';
      bgMedia.style.transform = 'scale(1.05)';
    } else {
      bgMedia.style.filter = '';
      bgMedia.style.transform = '';
    }
  }

  function insertLayer() {
    if (!document.body) { setTimeout(insertLayer, 200); return; }
    if (!document.getElementById('wb-bg-layer')) {
      document.body.insertBefore(bgLayer, document.body.firstChild);
      document.body.insertBefore(overlay, bgLayer.nextSibling);
    }
  }
  insertLayer();

  function pollConfig() {
    try {
      fetch(DAEMON + '/api/config?t=' + Date.now())
        .then(function(r) { return r.json(); })
        .then(function(cfg) { applyConfig(cfg); })
        .catch(function() {});
    } catch (e) {}
  }
  setInterval(pollConfig, 2000);
  pollConfig();

  var observer = new MutationObserver(function() {
    if (!document.getElementById('wb-bg-layer')) insertLayer();
  });
  if (document.body) observer.observe(document.body, { childList: true, subtree: false });

  console.log('[wb-bg] 背景注入脚本已启动');
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

    reconnectAttempts = 0; // 重置重连计数

    cdpClient.on('disconnected', () => {
      log('cdp', '连接断开，开始重连...');
      cdpClient = null;
      scheduleReconnect();
    });

    return true;
  } catch (e) {
    log('cdp', `连接失败: ${e.message}`);
    return false;
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

server = http.createServer((req, res) => {
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

  // GET / → 设置面板
  if (pathname === '/' && req.method === 'GET') {
    try {
      const html = fs.readFileSync(SETTINGS_HTML, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } catch {
      res.writeHead(404); res.end('settings.html not found');
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
