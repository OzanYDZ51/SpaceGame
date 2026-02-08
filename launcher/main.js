const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const fs = require("fs");
const https = require("https");
const http = require("http");
const { spawn } = require("child_process");
const AdmZip = require("adm-zip");

// --- Config ---
const BACKEND_URL =
  process.env.BACKEND_URL || "https://backend-production-05a9.up.railway.app";
const INSTALL_DIR = path.join(
  process.env.LOCALAPPDATA || app.getPath("userData"),
  "SpaceGame"
);
const GAME_DIR = path.join(INSTALL_DIR, "game");
const VERSION_FILE = path.join(INSTALL_DIR, "version.json");
const AUTH_FILE = path.join(INSTALL_DIR, "auth.json");

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    frame: false,
    resizable: false,
    backgroundColor: "#0a0e14",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());

// --- Helpers ---

function ensureDirs() {
  fs.mkdirSync(INSTALL_DIR, { recursive: true });
  fs.mkdirSync(GAME_DIR, { recursive: true });
}

function getGameVersion() {
  try {
    return JSON.parse(fs.readFileSync(VERSION_FILE, "utf-8")).version || null;
  } catch {
    return null;
  }
}

function setGameVersion(version) {
  fs.writeFileSync(VERSION_FILE, JSON.stringify({ version }), "utf-8");
}

function getLauncherVersion() {
  return app.getVersion();
}

function getSavedAuth() {
  try {
    return JSON.parse(fs.readFileSync(AUTH_FILE, "utf-8"));
  } catch {
    return null;
  }
}

function saveAuth(data) {
  fs.writeFileSync(AUTH_FILE, JSON.stringify(data), "utf-8");
}

function clearAuth() {
  try { fs.unlinkSync(AUTH_FILE); } catch {}
}

function httpRequest(method, urlStr, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const mod = url.protocol === "https:" ? https : http;
    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: {
        "User-Agent": "SpaceGameLauncher/1.0",
        "Content-Type": "application/json",
      },
    };

    const req = mod.request(options, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString();
        try {
          resolve({ status: res.statusCode, data: JSON.parse(text) });
        } catch {
          resolve({ status: res.statusCode, data: text });
        }
      });
      res.on("error", reject);
    });
    req.on("error", reject);

    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function downloadFile(url, destPath, progressCb) {
  return new Promise((resolve, reject) => {
    const doRequest = (requestUrl) => {
      const mod = requestUrl.startsWith("https") ? https : http;
      mod
        .get(requestUrl, { headers: { "User-Agent": "SpaceGameLauncher/1.0" } }, (res) => {
          if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
            return doRequest(res.headers.location);
          }
          if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));

          const total = parseInt(res.headers["content-length"] || "0", 10);
          let received = 0;
          const file = fs.createWriteStream(destPath);

          res.on("data", (chunk) => {
            received += chunk.length;
            file.write(chunk);
            if (progressCb) progressCb(received, total);
          });
          res.on("end", () => file.end(() => resolve()));
          res.on("error", (err) => { file.close(); reject(err); });
        })
        .on("error", reject);
    };
    doRequest(url);
  });
}

function compareVersions(a, b) {
  if (!a || !b) return -1;
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) < (pb[i] || 0)) return -1;
    if ((pa[i] || 0) > (pb[i] || 0)) return 1;
  }
  return 0;
}

// =========================================================================
// IPC — AUTH
// =========================================================================

ipcMain.handle("login", async (_event, username, password) => {
  try {
    const res = await httpRequest("POST", `${BACKEND_URL}/api/v1/auth/login`, {
      username, password,
    });
    if ((res.status === 200 || res.status === 201) && res.data.access_token) {
      saveAuth({
        access_token: res.data.access_token,
        refresh_token: res.data.refresh_token,
        username: res.data.player?.username || username,
      });
      return { success: true, username: res.data.player?.username || username };
    }
    return { error: res.data.error || "Identifiants invalides" };
  } catch (err) {
    return { error: "Serveur injoignable: " + err.message };
  }
});

ipcMain.handle("register", async (_event, username, email, password) => {
  try {
    const res = await httpRequest("POST", `${BACKEND_URL}/api/v1/auth/register`, {
      username, email, password,
    });
    if ((res.status === 200 || res.status === 201) && res.data.access_token) {
      saveAuth({
        access_token: res.data.access_token,
        refresh_token: res.data.refresh_token,
        username: res.data.player?.username || username,
      });
      return { success: true, username: res.data.player?.username || username };
    }
    return { error: res.data.error || "Inscription echouee" };
  } catch (err) {
    return { error: "Serveur injoignable: " + err.message };
  }
});

ipcMain.handle("get-saved-auth", () => getSavedAuth());

ipcMain.handle("logout", () => {
  const auth = getSavedAuth();
  if (auth?.refresh_token) {
    httpRequest("POST", `${BACKEND_URL}/api/v1/auth/logout`, {
      refresh_token: auth.refresh_token,
    }).catch(() => {});
  }
  clearAuth();
  return { success: true };
});

ipcMain.handle("refresh-token", async () => {
  const auth = getSavedAuth();
  if (!auth?.refresh_token) return { error: "no refresh token" };
  try {
    const res = await httpRequest("POST", `${BACKEND_URL}/api/v1/auth/refresh`, {
      refresh_token: auth.refresh_token,
    });
    if (res.status === 200 && res.data.access_token) {
      auth.access_token = res.data.access_token;
      auth.refresh_token = res.data.refresh_token;
      saveAuth(auth);
      return { success: true };
    }
    clearAuth();
    return { error: "session expired" };
  } catch {
    return { error: "server unreachable" };
  }
});

// =========================================================================
// IPC — UPDATES
// =========================================================================

ipcMain.handle("check-updates", async () => {
  ensureDirs();
  const launcherVersion = getLauncherVersion();
  const gameVersion = getGameVersion();
  const gameInstalled =
    gameVersion !== null && fs.existsSync(path.join(GAME_DIR, "SpaceGame.exe"));

  try {
    const res = await httpRequest("GET", `${BACKEND_URL}/api/v1/updates`);
    const updates = res.data;

    const launcherNeedsUpdate =
      updates.launcher && compareVersions(launcherVersion, updates.launcher.version) < 0;
    const gameNeedsUpdate =
      updates.game && (!gameInstalled || compareVersions(gameVersion, updates.game.version) < 0);

    return { launcherVersion, gameVersion, gameInstalled, remote: updates, launcherNeedsUpdate, gameNeedsUpdate };
  } catch (err) {
    return { launcherVersion, gameVersion, gameInstalled, remote: null, error: err.message };
  }
});

ipcMain.handle("update-launcher", async (_event, downloadUrl) => {
  const tempDir = app.getPath("temp");
  const installerPath = path.join(tempDir, "SpaceGameLauncherSetup.exe");
  const batPath = path.join(tempDir, "spacegame_launcher_update.bat");

  await downloadFile(downloadUrl, installerPath, (received, total) => {
    if (mainWindow && !mainWindow.isDestroyed())
      mainWindow.webContents.send("progress", { phase: "launcher", received, total });
  });

  const bat = `@echo off\ntimeout /t 3 /nobreak >nul\n"${installerPath}" /S\ndel "${batPath}"\n`;
  fs.writeFileSync(batPath, bat);

  const child = spawn("cmd.exe", ["/c", batPath], { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
  app.quit();
  return { success: true };
});

ipcMain.handle("update-game", async (_event, downloadUrl, version) => {
  ensureDirs();
  const zipPath = path.join(INSTALL_DIR, "SpaceGame.zip");

  await downloadFile(downloadUrl, zipPath, (received, total) => {
    if (mainWindow && !mainWindow.isDestroyed())
      mainWindow.webContents.send("progress", { phase: "game", received, total });
  });

  if (mainWindow && !mainWindow.isDestroyed())
    mainWindow.webContents.send("status", "Extraction en cours...");

  if (fs.existsSync(GAME_DIR)) fs.rmSync(GAME_DIR, { recursive: true, force: true });
  fs.mkdirSync(GAME_DIR, { recursive: true });

  const zip = new AdmZip(zipPath);
  zip.extractAllTo(GAME_DIR, true);
  fs.unlinkSync(zipPath);
  setGameVersion(version);
  return { success: true };
});

// =========================================================================
// IPC — LAUNCH
// =========================================================================

ipcMain.handle("launch-game", async () => {
  const exePath = path.join(GAME_DIR, "SpaceGame.exe");
  if (!fs.existsSync(exePath)) return { error: "SpaceGame.exe introuvable" };

  // Pass auth token to game if logged in
  const auth = getSavedAuth();
  const args = [];
  if (auth?.access_token) {
    args.push("--", "--auth-token", auth.access_token);
  }

  try {
    const child = spawn(exePath, args, {
      cwd: GAME_DIR,
      detached: true,
      stdio: "ignore",
      windowsHide: false,
    });
    child.unref();
    return { success: true };
  } catch (err) {
    return { error: "Impossible de lancer le jeu: " + err.message };
  }
});

ipcMain.handle("uninstall", async () => {
  if (fs.existsSync(GAME_DIR)) fs.rmSync(GAME_DIR, { recursive: true, force: true });
  if (fs.existsSync(VERSION_FILE)) fs.unlinkSync(VERSION_FILE);
  return { success: true };
});

// Window controls
ipcMain.on("window-minimize", () => mainWindow?.minimize());
ipcMain.on("window-close", () => mainWindow?.close());
