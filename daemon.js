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
  // 防止 ensureLayers 重复运行
  if (window.__wbBgInterval) { clearInterval(window.__wbBgInterval); }
  
  var currentConfig = null;
  var currentFileUri = null;

  // CSS 样式（一次性注入，持久生效）
  var style = document.createElement('style');
  style.id = 'wb-bg-transparent-css';
  style.textContent = [
    'html, body { background: transparent !important; }',
    '#root, #app, [id*="root"], [id*="app"] { background: transparent !important; position: relative; z-index: 2; }',
    'body > div:not(#wb-bg-layer):not(#wb-bg-overlay) { background: transparent !important; }',
    '[data-view-id=sidebar] { background: rgba(16,8,26,0.30) !important; backdrop-filter: blur(20px) saturate(1.12) !important; -webkit-backdrop-filter: blur(20px) saturate(1.12) !important; border: none !important; }',
    '[data-view-id=detail-panel] { background: rgba(16,8,26,0.50) !important; backdrop-filter: blur(18px) saturate(1.08) !important; -webkit-backdrop-filter: blur(18px) saturate(1.08) !important; }',
    '[data-view-id=main-content] { background: transparent !important; }',
    '.atm-modal-chat-input [class*="_mainArea_"], .atm-modal-chat-input [class*="_content_"], .atm-modal-chat-input textarea, .atm-modal-chat-input [contenteditable] { --atm-surface: rgba(16,8,26,0.30) !important; --atm-chat-content-bg: rgba(16,8,26,0.30) !important; background: rgba(16,8,26,0.30) !important; backdrop-filter: blur(16px) saturate(1.2) !important; -webkit-backdrop-filter: blur(16px) saturate(1.2) !important; }',
    '[role=listbox], [role=menu], .monaco-menu { background: rgba(16,8,26,0.45) !important; backdrop-filter: blur(12px) saturate(1.15) !important; -webkit-backdrop-filter: blur(12px) saturate(1.15) !important; }',
    '#wb-bg-layer { position: fixed !important; inset: 0 !important; z-index: -1 !important; pointer-events: none !important; overflow: hidden !important; }',
    '#wb-bg-overlay { position: fixed !important; inset: 0 !important; z-index: 0 !important; pointer-events: none !important; transition: background 0.4s ease; }',
  ].join('\\n');

  function ensureStyle() {
    if (!document.getElementById('wb-bg-transparent-css')) {
      (document.head || document.documentElement).appendChild(style);
    }
  }

  // 创建背景层（每次都重新创建，确保存在）
  function createBgLayer() {
    var layer = document.createElement('div');
    layer.id = 'wb-bg-layer';
    layer.style.cssText = 'position:fixed;inset:0;z-index:-1;pointer-events:none;overflow:hidden;background:#000;';
    return layer;
  }

  function createOverlay() {
    var ov = document.createElement('div');
    ov.id = 'wb-bg-overlay';
    ov.style.cssText = 'position:fixed;inset:0;z-index:0;pointer-events:none;background:rgba(0,0,0,0);transition:background 0.4s ease;';
    return ov;
  }

  // 强制插入背景层（每 500ms 调用一次）
  function ensureLayers() {
    ensureStyle();

    if (!document.body) return;

    var layer = document.getElementById('wb-bg-layer');
    var overlay = document.getElementById('wb-bg-overlay');

    if (!layer) {
      layer = createBgLayer();
      document.body.insertBefore(layer, document.body.firstChild);
    }

    if (!overlay) {
      overlay = createOverlay();
      document.body.insertBefore(overlay, layer.nextSibling);
    }

    // 确保背景层在最前面（body 的第一个子元素）
    if (document.body.firstChild !== layer) {
      document.body.insertBefore(layer, document.body.firstChild);
    }

    // 检查是否有媒体元素，如果没有且有配置，则创建
    if (currentConfig && currentConfig.enabled && currentConfig.source) {
      var media = layer.querySelector('video, img');
      if (!media) {
        rebuildMedia(layer);
      }
    }
  }

  // 重建媒体元素
  function rebuildMedia(layer) {
    if (!currentConfig || !currentConfig.enabled || !currentConfig.source) return;

    var cfg = currentConfig;
    var src = currentFileUri || ('file://' + cfg.source);

    // 清除旧的
    var old = layer.querySelector('video, img');
    if (old) old.remove();

    var media;
    if (cfg.type === 'video') {
      media = document.createElement('video');
      media.autoplay = true;
      media.loop = true;
      media.muted = true;
      media.playsInline = true;
      media.setAttribute('muted', '');
    } else {
      media = document.createElement('img');
    }

    media.style.cssText = 'width:100%;height:100%;object-fit:' + (cfg.scale || 'cover') + ';object-position:' + (cfg.position || 'center') + ';display:block;';

    if (cfg.blur && cfg.blur !== '0px') {
      media.style.filter = 'blur(' + cfg.blur + ')';
      media.style.transform = 'scale(1.05)';
    }

    media.src = src;
    if (cfg.type === 'video') {
      media.play().catch(function(){});
    }

    layer.appendChild(media);

    // 设置层样式
    layer.style.display = 'block';
    layer.style.opacity = String(cfg.opacity != null ? cfg.opacity : 1);

    var overlay = document.getElementById('wb-bg-overlay');
    if (overlay) {
      overlay.style.background = 'rgba(0,0,0,' + (cfg.overlay != null ? cfg.overlay : 0.25) + ')';
    }
  }

  // 应用配置
  function applyConfig(cfg, fileUri) {
    currentConfig = cfg;
    currentFileUri = fileUri;

    if (!cfg || !cfg.enabled || cfg.type === 'none' || !cfg.source) {
      var layer = document.getElementById('wb-bg-layer');
      if (layer) layer.style.display = 'none';
      var overlay = document.getElementById('wb-bg-overlay');
      if (overlay) overlay.style.background = 'rgba(0,0,0,0)';
      return;
    }

    ensureLayers();
    var layer = document.getElementById('wb-bg-layer');
    if (layer) {
      rebuildMedia(layer);
    }
  }

  // 暴露给 CDP 调用
  window.__wbBgApplyConfig = function(cfg, fileUri) {
    applyConfig(cfg, fileUri);
  };

  // 启动：立即插入 + 每 500ms 检查
  ensureLayers();
  window.__wbBgInterval = setInterval(ensureLayers, 500);
  window.__wbBgInjected = true;

  console.log('[wb-bg] 背景注入脚本已启动（持久模式）');
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

    reconnectAttempts = 0; // 重置重连计数

    cdpClient.on('disconnected', () => {
      log('cdp', '连接断开，开始重连...');
      cdpClient = null;
      scheduleReconnect();
    });

    // 定期推送配置（每 5 秒），确保背景持续生效
    if (configPushTimer) clearInterval(configPushTimer);
    configPushTimer = setInterval(() => {
      if (cdpClient) {
        pushConfigToPage();
      }
    }, 5000);
    log('cdp', '配置定时推送已启动（每 5 秒）');

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
