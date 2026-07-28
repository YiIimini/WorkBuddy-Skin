#!/usr/bin/env node
/**
 * WorkBuddy-Skin 托盘守护进程
 *
 * 功能：
 * - 常驻后台，监控 WorkBuddy 进程
 * - 自动启动/注入背景
 * - 提供 HTTP API 供快速操作
 * - 无需用户干预，静默运行
 */

const { spawn, exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const http = require('http');

const BASE_DIR = __dirname;
const CONFIG_FILE = path.join(BASE_DIR, 'config.json');
const LOG_FILE = path.join(BASE_DIR, 'tray.log');
const PID_FILE = path.join(BASE_DIR, 'tray.pid');
const DAEMON_SCRIPT = path.join(BASE_DIR, 'daemon.js');
const LAUNCHER_SCRIPT = path.join(BASE_DIR, 'launcher.sh');
const TRAY_PORT = 17891;

let workbuddyMonitorInterval = null;
let daemonProcess = null;

// 日志
function log(msg) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${msg}\n`;
  console.log(line.trim());
  fs.appendFileSync(LOG_FILE, line);
}

// 检查 WorkBuddy 是否运行（带 CDP）
function isWorkBuddyRunning() {
  return new Promise((resolve) => {
    exec('pgrep -f "remote-debugging-port=9222"', (err) => {
      resolve(!err);
    });
  });
}

// 检查守护进程是否运行
function isDaemonRunning() {
  return new Promise((resolve) => {
    exec('curl -s http://localhost:17890/api/health', (err) => {
      resolve(!err);
    });
  });
}

// 启动 WorkBuddy + 守护进程
async function startWorkBuddySkin() {
  log('启动 WorkBuddy-Skin...');

  return new Promise((resolve, reject) => {
    const proc = spawn('bash', [LAUNCHER_SCRIPT], {
      detached: true,
      stdio: 'ignore'
    });

    proc.unref();

    proc.on('error', (err) => {
      log(`启动失败: ${err.message}`);
      reject(err);
    });

    // 等待 5 秒检查是否成功
    setTimeout(async () => {
      const running = await isWorkBuddyRunning();
      if (running) {
        log('WorkBuddy-Skin 启动成功');
        resolve();
      } else {
        log('WorkBuddy-Skin 启动失败');
        reject(new Error('启动超时'));
      }
    }, 5000);
  });
}

// 监控 WorkBuddy 进程
async function monitorWorkBuddy() {
  const wbRunning = await isWorkBuddyRunning();
  const daemonRunning = await isDaemonRunning();

  if (!wbRunning) {
    log('WorkBuddy 未运行（CDP 模式）');
    if (daemonRunning) {
      log('守护进程仍在运行，但 WorkBuddy 已退出');
    }
  } else {
    if (!daemonRunning) {
      log('WorkBuddy 运行中但守护进程未运行，尝试启动守护进程...');
      startDaemon();
    }
  }
}

// 启动守护进程（仅守护进程，不启动 WorkBuddy）
function startDaemon() {
  if (daemonProcess) {
    log('守护进程已在运行');
    return;
  }

  log('启动守护进程...');

  const nodePath = '/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node';
  daemonProcess = spawn(nodePath, [DAEMON_SCRIPT], {
    detached: true,
    stdio: 'ignore'
  });

  daemonProcess.unref();

  daemonProcess.on('error', (err) => {
    log(`守护进程启动失败: ${err.message}`);
    daemonProcess = null;
  });

  daemonProcess.on('exit', (code) => {
    log(`守护进程退出 (code: ${code})`);
    daemonProcess = null;
  });

  log(`守护进程 PID: ${daemonProcess.pid}`);
}

// HTTP API
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${TRAY_PORT}`);

  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Access-Control-Allow-Origin', '*');

  if (url.pathname === '/api/status') {
    const wbRunning = await isWorkBuddyRunning();
    const daemonRunning = await isDaemonRunning();

    res.end(JSON.stringify({
      workbuddy: wbRunning,
      daemon: daemonRunning,
      config: fs.existsSync(CONFIG_FILE) ? JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')) : null
    }));
  }
  else if (url.pathname === '/api/start') {
    try {
      await startWorkBuddySkin();
      res.end(JSON.stringify({ success: true, message: 'WorkBuddy-Skin 已启动' }));
    } catch (err) {
      res.statusCode = 500;
      res.end(JSON.stringify({ success: false, error: err.message }));
    }
  }
  else if (url.pathname === '/api/set-background' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const { filePath } = JSON.parse(body);
        const setBgScript = path.join(BASE_DIR, 'set-background.sh');

        exec(`bash "${setBgScript}" "${filePath}"`, (err, stdout, stderr) => {
          if (err) {
            res.statusCode = 500;
            res.end(JSON.stringify({ success: false, error: stderr }));
          } else {
            res.end(JSON.stringify({ success: true, message: '背景已设置' }));
          }
        });
      } catch (err) {
        res.statusCode = 400;
        res.end(JSON.stringify({ success: false, error: err.message }));
      }
    });
  }
  else {
    res.statusCode = 404;
    res.end(JSON.stringify({ error: 'Not found' }));
  }
});

// 启动
async function main() {
  log('=== WorkBuddy-Skin 托盘守护进程启动 ===');

  // 写入 PID
  fs.writeFileSync(PID_FILE, String(process.pid));

  // 启动 HTTP 服务
  server.listen(TRAY_PORT, '127.0.0.1', () => {
    log(`HTTP API 监听在 http://localhost:${TRAY_PORT}`);
  });

  // 检查当前状态
  const wbRunning = await isWorkBuddyRunning();
  const daemonRunning = await isDaemonRunning();

  log(`WorkBuddy 运行状态: ${wbRunning ? '是' : '否'}`);
  log(`守护进程运行状态: ${daemonRunning ? '是' : '否'}`);

  // 如果 WorkBuddy 运行但守护进程未运行，启动守护进程
  if (wbRunning && !daemonRunning) {
    startDaemon();
  }

  // 每 10 秒监控一次
  workbuddyMonitorInterval = setInterval(monitorWorkBuddy, 10000);

  log('托盘守护进程已就绪');
}

// 优雅退出
process.on('SIGINT', () => {
  log('收到 SIGINT，正在退出...');
  if (workbuddyMonitorInterval) clearInterval(workbuddyMonitorInterval);
  server.close();
  fs.unlinkSync(PID_FILE);
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('收到 SIGTERM，正在退出...');
  if (workbuddyMonitorInterval) clearInterval(workbuddyMonitorInterval);
  server.close();
  fs.unlinkSync(PID_FILE);
  process.exit(0);
});

main().catch(err => {
  log(`启动失败: ${err.message}`);
  process.exit(1);
});
