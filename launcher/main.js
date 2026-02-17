const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage } = require("electron");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const https = require("https");
const http = require("http");
const { spawn } = require("child_process");
const AdmZip = require("adm-zip");
const discordRpc = require("./discord-rpc");

// --- Config ---
const BACKEND_URL =
  process.env.BACKEND_URL || "https://backend-production-05a9.up.railway.app";
const INSTALL_DIR = path.join(
  process.env.LOCALAPPDATA || app.getPath("userData"),
  "ImperionOnline"
);
const GAME_DIR = path.join(INSTALL_DIR, "game");
const VERSION_FILE = path.join(INSTALL_DIR, "version.json");
const AUTH_FILE = path.join(INSTALL_DIR, "auth.json");

const SETTINGS_FILE = path.join(INSTALL_DIR, "settings.json");
const MANIFEST_FILE = path.join(INSTALL_DIR, "manifest.json");

let mainWindow;
let tray = null;
let gameProcess = null;
let isGameRunning = false;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 650,
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

  // Prevent window close when game is running — minimize to tray instead
  mainWindow.on("close", (e) => {
    if (isGameRunning && tray) {
      e.preventDefault();
      mainWindow.hide();
    }
  });
}

function createTray() {
  // Create a simple tray icon
  const iconPath = path.join(__dirname, "assets", "icon.ico");
  let trayIcon;
  if (fs.existsSync(iconPath)) {
    trayIcon = nativeImage.createFromPath(iconPath);
  } else {
    trayIcon = nativeImage.createEmpty();
  }

  tray = new Tray(trayIcon);
  tray.setToolTip("Imperion Online Launcher");

  const updateTrayMenu = () => {
    const contextMenu = Menu.buildFromTemplate([
      {
        label: isGameRunning ? "Imperion Online en cours..." : "Imperion Online Launcher",
        enabled: false,
      },
      { type: "separator" },
      {
        label: "Ouvrir le launcher",
        click: () => {
          if (mainWindow) {
            mainWindow.show();
            mainWindow.focus();
          }
        },
      },
      { type: "separator" },
      {
        label: "Quitter",
        click: () => {
          isGameRunning = false;
          if (tray) {
            tray.destroy();
            tray = null;
          }
          app.quit();
        },
      },
    ]);
    tray.setContextMenu(contextMenu);
  };

  updateTrayMenu();
  tray.on("double-click", () => {
    if (mainWindow) {
      mainWindow.show();
      mainWindow.focus();
    }
  });

  return updateTrayMenu;
}

app.whenReady().then(() => {
  ensureDirs();
  createWindow();
  createTray();
});

app.on("window-all-closed", () => {
  if (!isGameRunning) {
    app.quit();
  }
});

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
        "User-Agent": "ImperionOnlineLauncher/1.0",
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

function httpRequestAuth(method, urlStr, token, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const mod = url.protocol === "https:" ? https : http;
    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: {
        "User-Agent": "ImperionOnlineLauncher/1.0",
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
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

function getSettings() {
  try {
    return JSON.parse(fs.readFileSync(SETTINGS_FILE, "utf-8"));
  } catch {
    return { display: "windowed", resolution: "auto", quality: "high" };
  }
}

function saveSettings(settings) {
  fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2), "utf-8");
}

function downloadFile(url, destPath, progressCb) {
  return new Promise((resolve, reject) => {
    const doRequest = (requestUrl) => {
      const mod = requestUrl.startsWith("https") ? https : http;
      mod
        .get(requestUrl, { headers: { "User-Agent": "ImperionOnlineLauncher/1.0" } }, (res) => {
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

function getLocalManifest() {
  try {
    return JSON.parse(fs.readFileSync(MANIFEST_FILE, "utf-8"));
  } catch {
    return null;
  }
}

function saveLocalManifest(data) {
  fs.writeFileSync(MANIFEST_FILE, JSON.stringify(data, null, 2), "utf-8");
}

function computeFileHash(filePath) {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(filePath)) return resolve(null);
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", reject);
  });
}

function downloadToBuffer(url) {
  return new Promise((resolve, reject) => {
    const doRequest = (requestUrl) => {
      const mod = requestUrl.startsWith("https") ? https : http;
      mod.get(requestUrl, { headers: { "User-Agent": "ImperionOnlineLauncher/1.0" } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          return doRequest(res.headers.location);
        }
        if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
        res.on("error", reject);
      }).on("error", reject);
    };
    doRequest(url);
  });
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
    gameVersion !== null && fs.existsSync(path.join(GAME_DIR, "ImperionOnline.exe"));

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
  const installerPath = path.join(tempDir, "ImperionOnlineLauncherSetup.exe");
  const batPath = path.join(tempDir, "imperion_launcher_update.bat");

  await downloadFile(downloadUrl, installerPath, (received, total) => {
    if (mainWindow && !mainWindow.isDestroyed())
      mainWindow.webContents.send("progress", { phase: "launcher", received, total });
  });

  // Resolve the launcher install dir so silent update installs to the same place
  const launcherExe = process.execPath;
  const launcherDir = path.dirname(launcherExe);
  const bat = [
    `@echo off`,
    `timeout /t 3 /nobreak >nul`,
    `"${installerPath}" /S /D=${launcherDir}`,
    `timeout /t 2 /nobreak >nul`,
    `start "" "${launcherExe}"`,
    `del "${batPath}"`,
  ].join("\r\n");
  fs.writeFileSync(batPath, bat);

  const child = spawn("cmd.exe", ["/c", batPath], { detached: true, stdio: "ignore", windowsHide: true });
  child.unref();
  app.quit();
  return { success: true };
});

ipcMain.handle("update-game", async (_event, downloadUrl, version, manifestUrl) => {
  ensureDirs();
  fs.mkdirSync(GAME_DIR, { recursive: true });

  let remoteManifest = null;
  let filesToUpdate = null; // null = update all, array = selective
  let filesToDelete = [];

  // --- Delta check via manifest ---
  if (manifestUrl) {
    try {
      if (mainWindow && !mainWindow.isDestroyed())
        mainWindow.webContents.send("status", "Verification des fichiers...");

      const raw = await downloadToBuffer(manifestUrl);
      remoteManifest = JSON.parse(raw);
      const localManifest = getLocalManifest();

      if (remoteManifest && remoteManifest.files) {
        filesToUpdate = [];

        // Check each remote file against local
        for (const [fileName, remoteHash] of Object.entries(remoteManifest.files)) {
          const localPath = path.join(GAME_DIR, fileName);
          const localHash = await computeFileHash(localPath);
          if (localHash !== remoteHash) {
            filesToUpdate.push(fileName);
          }
        }

        // Check for local files that no longer exist in remote manifest
        if (localManifest && localManifest.files) {
          for (const fileName of Object.keys(localManifest.files)) {
            if (!remoteManifest.files[fileName]) {
              filesToDelete.push(fileName);
            }
          }
        }

        // Nothing to do — already up to date
        if (filesToUpdate.length === 0 && filesToDelete.length === 0) {
          saveLocalManifest(remoteManifest);
          setGameVersion(version);
          return { success: true, skipped: true, message: "Deja a jour" };
        }
      }
    } catch {
      // Manifest fetch/parse failed — fall back to full download
      remoteManifest = null;
      filesToUpdate = null;
    }
  }

  // --- Download zip ---
  const zipPath = path.join(INSTALL_DIR, "ImperionOnline.zip");

  if (mainWindow && !mainWindow.isDestroyed()) {
    const count = filesToUpdate ? filesToUpdate.length : "tous les";
    mainWindow.webContents.send("status", `Telechargement (${count} fichier(s))...`);
  }

  await downloadFile(downloadUrl, zipPath, (received, total) => {
    if (mainWindow && !mainWindow.isDestroyed())
      mainWindow.webContents.send("progress", { phase: "game", received, total });
  });

  if (mainWindow && !mainWindow.isDestroyed())
    mainWindow.webContents.send("status", "Extraction en cours...");

  // --- Extract (selective or full) ---
  const zip = new AdmZip(zipPath);

  if (filesToUpdate && filesToUpdate.length > 0) {
    // Selective extraction — only changed files
    for (const fileName of filesToUpdate) {
      const entry = zip.getEntry(fileName);
      if (entry) {
        zip.extractEntryTo(entry, GAME_DIR, false, true);
      }
    }
  } else {
    // Full extraction
    zip.extractAllTo(GAME_DIR, true);
  }

  fs.unlinkSync(zipPath);

  // --- Delete obsolete files ---
  for (const fileName of filesToDelete) {
    const filePath = path.join(GAME_DIR, fileName);
    try { fs.unlinkSync(filePath); } catch {}
  }

  // --- Post-extraction verification ---
  if (remoteManifest && remoteManifest.files) {
    const verifyErrors = [];
    for (const [fileName, expectedHash] of Object.entries(remoteManifest.files)) {
      const localHash = await computeFileHash(path.join(GAME_DIR, fileName));
      if (localHash !== expectedHash) {
        verifyErrors.push(fileName);
      }
    }
    if (verifyErrors.length > 0) {
      return { success: false, error: "Verification echouee: " + verifyErrors.join(", ") };
    }
  }

  // --- Save manifest + version ---
  if (remoteManifest) {
    saveLocalManifest(remoteManifest);
  }
  setGameVersion(version);
  return { success: true, updated: filesToUpdate };
});

// =========================================================================
// IPC — CHANGELOG
// =========================================================================

ipcMain.handle("get-changelog", async () => {
  try {
    const res = await httpRequest("GET", `${BACKEND_URL}/api/v1/changelog?limit=10`);
    if (res.status === 200 && Array.isArray(res.data)) {
      return { entries: res.data };
    }
    return { entries: [] };
  } catch {
    return { entries: [] };
  }
});

// =========================================================================
// IPC — SERVER STATS / PLAYER STATE / CORPORATION
// =========================================================================

ipcMain.handle("get-server-stats", async () => {
  try {
    const res = await httpRequest("GET", `${BACKEND_URL}/api/v1/public/stats`);
    if (res.status === 200) return { success: true, stats: res.data };
    return { error: "stats unavailable" };
  } catch {
    return { error: "server unreachable" };
  }
});

ipcMain.handle("get-player-state", async () => {
  const auth = getSavedAuth();
  if (!auth?.access_token) return { error: "not authenticated" };
  try {
    const res = await httpRequestAuth("GET", `${BACKEND_URL}/api/v1/player/state`, auth.access_token);
    if (res.status === 200) return { success: true, state: res.data };
    return { error: "state unavailable" };
  } catch {
    return { error: "server unreachable" };
  }
});

ipcMain.handle("get-corporation", async (_event, corpId) => {
  const auth = getSavedAuth();
  if (!auth?.access_token) return { error: "not authenticated" };
  try {
    const res = await httpRequestAuth("GET", `${BACKEND_URL}/api/v1/corporations/${corpId}`, auth.access_token);
    if (res.status === 200) return { success: true, corporation: res.data };
    return { error: "corporation not found" };
  } catch {
    return { error: "server unreachable" };
  }
});

// =========================================================================
// IPC — SETTINGS
// =========================================================================

ipcMain.handle("get-settings", () => getSettings());

ipcMain.handle("save-settings", (_event, settings) => {
  saveSettings(settings);
  return { success: true };
});

// =========================================================================
// IPC — VERIFY GAME FILES
// =========================================================================

ipcMain.handle("verify-game", async () => {
  const manifest = getLocalManifest();
  const missing = [];
  const corrupted = [];

  if (manifest && manifest.files) {
    // Verify against manifest hashes
    for (const [fileName, expectedHash] of Object.entries(manifest.files)) {
      const filePath = path.join(GAME_DIR, fileName);
      if (!fs.existsSync(filePath)) {
        missing.push(fileName);
        continue;
      }
      const localHash = await computeFileHash(filePath);
      if (localHash !== expectedHash) {
        corrupted.push(fileName);
      }
    }
  } else {
    // No manifest — basic existence check
    if (!fs.existsSync(path.join(GAME_DIR, "ImperionOnline.exe"))) missing.push("ImperionOnline.exe");
    if (!fs.existsSync(path.join(GAME_DIR, "ImperionOnline.pck"))) missing.push("ImperionOnline.pck");
  }

  if (missing.length === 0 && corrupted.length === 0) {
    return { success: true, message: "Tous les fichiers sont intacts" };
  }

  const parts = [];
  if (missing.length > 0) parts.push("Manquants: " + missing.join(", "));
  if (corrupted.length > 0) parts.push("Corrompus: " + corrupted.join(", "));
  return { success: false, message: parts.join(" | ") };
});

// =========================================================================
// IPC — LAUNCH (with tray mode + Discord RPC)
// =========================================================================

ipcMain.handle("launch-game", async () => {
  const exePath = path.join(GAME_DIR, "ImperionOnline.exe");
  if (!fs.existsSync(exePath)) return { error: "ImperionOnline.exe introuvable" };

  // Pass auth token and settings to game
  const auth = getSavedAuth();
  const settings = getSettings();
  const args = [];

  // Display mode
  if (settings.display === "fullscreen") args.push("--fullscreen");
  else if (settings.display === "borderless") args.push("--fullscreen", "--borderless");
  else args.push("--windowed");

  // Resolution
  if (settings.resolution && settings.resolution !== "auto") {
    args.push("--resolution", settings.resolution);
  }

  // Auth token (after --)
  if (auth?.access_token) {
    args.push("--", "--auth-token", auth.access_token);
  }

  try {
    gameProcess = spawn(exePath, args, {
      cwd: GAME_DIR,
      detached: false,
      stdio: "ignore",
      windowsHide: false,
    });

    isGameRunning = true;

    // Start Discord Rich Presence bridge
    discordRpc.start();

    // When game exits, restore launcher
    gameProcess.on("exit", () => {
      isGameRunning = false;
      gameProcess = null;
      discordRpc.stop();

      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.show();
        mainWindow.focus();
        mainWindow.webContents.send("status", "Pret");
        mainWindow.webContents.send("game-exited");
      }
    });

    gameProcess.on("error", () => {
      isGameRunning = false;
      gameProcess = null;
      discordRpc.stop();
    });

    return { success: true };
  } catch (err) {
    return { error: "Impossible de lancer le jeu: " + err.message };
  }
});

ipcMain.handle("uninstall", async () => {
  if (fs.existsSync(GAME_DIR)) fs.rmSync(GAME_DIR, { recursive: true, force: true });
  if (fs.existsSync(VERSION_FILE)) fs.unlinkSync(VERSION_FILE);
  try { fs.unlinkSync(MANIFEST_FILE); } catch {}
  return { success: true };
});

// Window controls
ipcMain.on("window-minimize", () => mainWindow?.minimize());
ipcMain.on("window-close", () => {
  if (isGameRunning && tray) {
    mainWindow?.hide();
  } else {
    mainWindow?.close();
  }
});
