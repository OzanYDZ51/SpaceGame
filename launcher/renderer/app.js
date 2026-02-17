// =========================================================================
// Imperion Online Launcher — Frontend Logic
// Flow: Check saved auth → Login/Register → Check updates → Play
// =========================================================================

// =========================================================================
// STARFIELD BACKGROUND
// =========================================================================

(function initStarfield() {
  const canvas = document.getElementById("starfield");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  let w, h;
  const stars = [];
  const COUNT = 80;

  function resize() {
    w = canvas.width = window.innerWidth;
    h = canvas.height = window.innerHeight;
  }
  resize();
  window.addEventListener("resize", resize);

  for (let i = 0; i < COUNT; i++) {
    stars.push({
      x: Math.random() * w,
      y: Math.random() * h,
      r: 0.4 + Math.random() * 1.2,
      speed: 0.08 + Math.random() * 0.15,
      phase: Math.random() * Math.PI * 2,
    });
  }

  function draw(t) {
    ctx.clearRect(0, 0, w, h);
    for (const s of stars) {
      s.y += s.speed;
      if (s.y > h) { s.y = 0; s.x = Math.random() * w; }
      const alpha = 0.3 + 0.5 * Math.sin(t * 0.001 + s.phase);
      ctx.beginPath();
      ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(0, 200, 255, ${alpha.toFixed(2)})`;
      ctx.fill();
    }
    requestAnimationFrame(draw);
  }
  requestAnimationFrame(draw);
})();

// =========================================================================
// DOM REFS
// =========================================================================

const authSection = document.getElementById("auth-section");
const mainSection = document.getElementById("main-section");
const loginForm = document.getElementById("login-form");
const registerForm = document.getElementById("register-form");
const loginError = document.getElementById("login-error");
const regError = document.getElementById("reg-error");
const userDisplay = document.getElementById("user-display");
const statusText = document.getElementById("status-text");
const launcherVersionEl = document.getElementById("launcher-version");
const gameVersionEl = document.getElementById("game-version");
const progressContainer = document.getElementById("progress-container");
const progressLabel = document.getElementById("progress-label");
const progressFill = document.getElementById("progress-fill");
const progressText = document.getElementById("progress-text");
const btnPlay = document.getElementById("btn-play");
const btnUninstall = document.getElementById("btn-uninstall");
const btnVerify = document.getElementById("btn-verify");
const changelogSection = document.getElementById("changelog-section");
const changelogList = document.getElementById("changelog-list");
const logoArea = document.querySelector(".logo-area");
const profilePanel = document.getElementById("profile-panel");
const settingsPanel = document.getElementById("settings-panel");

// =========================================================================
// HELPERS
// =========================================================================

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / 1048576).toFixed(1) + " MB";
}

function setStatus(text) { statusText.textContent = text; }

function showProgress(label) {
  progressLabel.textContent = label;
  progressContainer.style.display = "block";
  changelogSection.style.display = "none";
  progressFill.style.width = "0%";
  progressText.textContent = "0%";
}

function hideProgress() {
  progressContainer.style.display = "none";
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

function showAuth() {
  authSection.style.display = "block";
  mainSection.style.display = "none";
  logoArea.classList.remove("compact");
  profilePanel.style.display = "none";
  settingsPanel.style.display = "none";
}

function showMain(username) {
  authSection.style.display = "none";
  mainSection.style.display = "block";
  userDisplay.textContent = username.toUpperCase();
  logoArea.classList.add("compact");
  loadPlayerProfile();
  loadSettings();
}

function formatDate(dateStr) {
  try {
    const d = new Date(dateStr);
    return d.toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric" });
  } catch {
    return "";
  }
}

function formatCredits(n) {
  if (n == null) return "--";
  if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
  if (n >= 1000) return (n / 1000).toFixed(1) + "K";
  return String(n);
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

function showToast(message, type) {
  const existing = document.querySelector(".toast");
  if (existing) existing.remove();
  const el = document.createElement("div");
  el.className = "toast " + (type || "");
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3000);
}

// =========================================================================
// PROGRESS LISTENER
// =========================================================================

window.launcher.onProgress(({ phase, received, total }) => {
  if (total > 0) {
    const pct = Math.round((received / total) * 100);
    progressFill.style.width = pct + "%";
    progressText.textContent = `${formatBytes(received)} / ${formatBytes(total)}  (${pct}%)`;
  } else {
    progressText.textContent = formatBytes(received);
  }
});

window.launcher.onStatus((msg) => setStatus(msg));

// When game exits, re-enable the play button
window.launcher.onGameExited(() => {
  btnPlay.disabled = false;
  btnPlay.textContent = "JOUER";
  btnPlay.classList.add("ready");
});

// =========================================================================
// SERVER STATS POLLING
// =========================================================================

const serverDot = document.getElementById("server-dot");
const serverStatusText = document.getElementById("server-status-text");

async function pollServerStats() {
  try {
    const res = await window.launcher.getServerStats();
    if (res.success && res.stats) {
      serverDot.classList.remove("offline");
      serverDot.classList.add("online");
      serverStatusText.textContent = "EN LIGNE";

      const s = res.stats;
      document.querySelector("#server-online span").textContent = s.players_online ?? 0;
      document.querySelector("#server-total span").textContent = s.players_total ?? 0;
      document.querySelector("#server-corps span").textContent = s.corporations_total ?? 0;
    } else {
      serverDot.classList.remove("online");
      serverDot.classList.add("offline");
      serverStatusText.textContent = "HORS LIGNE";
    }
  } catch {
    serverDot.classList.remove("online");
    serverDot.classList.add("offline");
    serverStatusText.textContent = "HORS LIGNE";
  }
}

// Poll immediately and every 30s
pollServerStats();
setInterval(pollServerStats, 30000);

// =========================================================================
// PLAYER PROFILE
// =========================================================================

async function loadPlayerProfile() {
  try {
    const res = await window.launcher.getPlayerState();
    if (!res.success || !res.state) {
      profilePanel.style.display = "none";
      return;
    }

    const s = res.state;
    document.getElementById("profile-credits").textContent = formatCredits(s.credits);
    profilePanel.style.display = "block";

    // Load corporation if player has one
    const corpId = s.corporation_id || s.corp_id;
    const corpEl = document.getElementById("profile-corp");
    if (corpId) {
      const corpRes = await window.launcher.getCorporation(corpId);
      if (corpRes.success && corpRes.corporation) {
        document.getElementById("profile-corp-tag").textContent = "[" + (corpRes.corporation.tag || "???") + "]";
        document.getElementById("profile-corp-name").textContent = corpRes.corporation.name || "";
        corpEl.style.display = "flex";
      } else {
        corpEl.style.display = "none";
      }
    } else {
      corpEl.style.display = "none";
    }
  } catch {
    profilePanel.style.display = "none";
  }
}

// =========================================================================
// AUTH
// =========================================================================

// Toggle login/register forms
document.getElementById("show-register").addEventListener("click", (e) => {
  e.preventDefault();
  loginForm.style.display = "none";
  registerForm.style.display = "block";
  loginError.textContent = "";
  regError.textContent = "";
});

document.getElementById("show-login").addEventListener("click", (e) => {
  e.preventDefault();
  registerForm.style.display = "none";
  loginForm.style.display = "block";
  loginError.textContent = "";
  regError.textContent = "";
});

// Login
document.getElementById("btn-login").addEventListener("click", async () => {
  const username = document.getElementById("login-username").value.trim();
  const password = document.getElementById("login-password").value;
  if (!username || !password) {
    loginError.textContent = "Remplissez tous les champs";
    return;
  }
  loginError.textContent = "";
  document.getElementById("btn-login").disabled = true;
  document.getElementById("btn-login").textContent = "CONNEXION...";

  const result = await window.launcher.login(username, password);
  document.getElementById("btn-login").disabled = false;
  document.getElementById("btn-login").textContent = "CONNEXION";

  if (result.success) {
    showMain(result.username);
    checkUpdatesAndPrepare();
  } else {
    loginError.textContent = result.error;
  }
});

// Enter key on password field
document.getElementById("login-password").addEventListener("keydown", (e) => {
  if (e.key === "Enter") document.getElementById("btn-login").click();
});

// Register
document.getElementById("btn-register").addEventListener("click", async () => {
  const username = document.getElementById("reg-username").value.trim();
  const email = document.getElementById("reg-email").value.trim();
  const password = document.getElementById("reg-password").value;
  if (!username || !email || !password) {
    regError.textContent = "Remplissez tous les champs";
    return;
  }
  if (password.length < 8) {
    regError.textContent = "Le mot de passe doit faire au moins 8 caracteres";
    return;
  }
  regError.textContent = "";
  document.getElementById("btn-register").disabled = true;
  document.getElementById("btn-register").textContent = "CREATION...";

  const result = await window.launcher.register(username, email, password);
  document.getElementById("btn-register").disabled = false;
  document.getElementById("btn-register").textContent = "CREER UN COMPTE";

  if (result.success) {
    showMain(result.username);
    checkUpdatesAndPrepare();
  } else {
    regError.textContent = result.error;
  }
});

// Enter key on register password
document.getElementById("reg-password").addEventListener("keydown", (e) => {
  if (e.key === "Enter") document.getElementById("btn-register").click();
});

// Logout
document.getElementById("btn-logout").addEventListener("click", async (e) => {
  e.preventDefault();
  await window.launcher.logout();
  btnPlay.disabled = true;
  btnPlay.classList.remove("ready");
  btnUninstall.style.display = "none";
  btnVerify.style.display = "none";
  changelogSection.style.display = "none";
  showAuth();
});

// =========================================================================
// CHANGELOG (with is_major badges)
// =========================================================================

async function loadChangelog() {
  const result = await window.launcher.getChangelog();
  if (!result.entries || result.entries.length === 0) {
    changelogSection.style.display = "none";
    return;
  }

  changelogList.innerHTML = "";
  for (const entry of result.entries) {
    const isMajor = entry.is_major === true;
    const div = document.createElement("div");
    div.className = "changelog-entry" + (isMajor ? " major" : "");
    const badgeHtml = isMajor
      ? '<span class="changelog-badge major">MAJOR</span>'
      : '<span class="changelog-badge patch">PATCH</span>';
    div.innerHTML = `
      <div class="changelog-entry-header">
        <span class="changelog-version">v${entry.version} ${badgeHtml}</span>
        <span class="changelog-date">${formatDate(entry.created_at)}</span>
      </div>
      <div class="changelog-summary">${escapeHtml(entry.summary)}</div>
    `;
    changelogList.appendChild(div);
  }
  changelogSection.style.display = "block";
}

// =========================================================================
// SETTINGS PANEL
// =========================================================================

const btnSettings = document.getElementById("btn-settings");

btnSettings.addEventListener("click", () => {
  const visible = settingsPanel.style.display !== "none";
  settingsPanel.style.display = visible ? "none" : "block";
  btnSettings.classList.toggle("active", !visible);
});

async function loadSettings() {
  const settings = await window.launcher.getSettings();
  document.getElementById("setting-display").value = settings.display || "windowed";
  document.getElementById("setting-resolution").value = settings.resolution || "auto";
  document.getElementById("setting-quality").value = settings.quality || "high";
}

function onSettingChange() {
  const settings = {
    display: document.getElementById("setting-display").value,
    resolution: document.getElementById("setting-resolution").value,
    quality: document.getElementById("setting-quality").value,
  };
  window.launcher.saveSettings(settings);
}

document.getElementById("setting-display").addEventListener("change", onSettingChange);
document.getElementById("setting-resolution").addEventListener("change", onSettingChange);
document.getElementById("setting-quality").addEventListener("change", onSettingChange);

// =========================================================================
// VERIFY GAME FILES
// =========================================================================

btnVerify.addEventListener("click", async () => {
  btnVerify.disabled = true;
  btnVerify.textContent = "...";
  const result = await window.launcher.verifyGame();
  btnVerify.disabled = false;
  btnVerify.textContent = "VERIFIER";
  if (result.success) {
    showToast(result.message, "success");
  } else {
    showToast(result.message, "error");
  }
});

// =========================================================================
// UPDATES & LAUNCH
// =========================================================================

async function checkUpdatesAndPrepare() {
  setStatus("Verification des mises a jour...");

  // Load changelog in parallel
  loadChangelog();

  const info = await window.launcher.checkUpdates();

  launcherVersionEl.textContent = "v" + info.launcherVersion;
  gameVersionEl.textContent = info.gameVersion ? "v" + info.gameVersion : "Non installe";

  // Offline / error
  if (info.error) {
    setStatus("Serveur injoignable");
    if (info.gameInstalled) {
      btnPlay.disabled = false;
      btnPlay.classList.add("ready");
      btnUninstall.style.display = "block";
      btnVerify.style.display = "block";
      setStatus("Mode hors-ligne");
    }
    return;
  }

  // Show remote versions
  if (info.remote?.launcher) {
    launcherVersionEl.textContent = "v" + info.launcherVersion +
      (info.launcherNeedsUpdate ? " -> v" + info.remote.launcher.version : "");
    launcherVersionEl.classList.add(info.launcherNeedsUpdate ? "warning" : "ok");
  }

  if (info.remote?.game) {
    gameVersionEl.textContent = info.gameVersion
      ? "v" + info.gameVersion + (info.gameNeedsUpdate ? " -> v" + info.remote.game.version : "")
      : "Non installe -> v" + info.remote.game.version;
    gameVersionEl.classList.add(info.gameNeedsUpdate ? "warning" : (info.gameInstalled ? "ok" : ""));
  }

  // Auto-update game
  if (info.gameNeedsUpdate && info.remote.game.download_url) {
    setStatus("Verification des fichiers...");
    showProgress("MISE A JOUR DU JEU");
    try {
      const result = await window.launcher.updateGame(
        info.remote.game.download_url,
        info.remote.game.version,
        info.remote.game.manifest_url || null
      );
      if (!result.success) {
        setStatus("Erreur: " + (result.error || "Mise a jour echouee"));
        hideProgress();
        return;
      }
      if (result.skipped) {
        setStatus("Deja a jour");
      } else if (result.updated && result.updated.length > 0) {
        setStatus(`${result.updated.length} fichier(s) mis a jour`);
      }
      gameVersionEl.textContent = "v" + info.remote.game.version;
      gameVersionEl.classList.remove("warning");
      gameVersionEl.classList.add("ok");
      hideProgress();
    } catch (err) {
      setStatus("Erreur: " + err.message);
      hideProgress();
      return;
    }
  }

  // Ready
  setStatus("Pret");
  btnPlay.disabled = false;
  btnPlay.classList.add("ready");
  btnUninstall.style.display = "block";
  btnVerify.style.display = "block";
}

// Launch — minimize to tray instead of closing
btnPlay.addEventListener("click", async () => {
  btnPlay.disabled = true;
  btnPlay.classList.remove("ready");
  btnPlay.textContent = "EN COURS...";
  setStatus("Lancement...");

  const result = await window.launcher.launchGame();
  if (result.error) {
    setStatus("Erreur: " + result.error);
    btnPlay.disabled = false;
    btnPlay.textContent = "JOUER";
    btnPlay.classList.add("ready");
    return;
  }

  setStatus("Jeu en cours");
  // Launcher stays open (tray mode) — game exit event will re-enable button
});

// Uninstall
btnUninstall.addEventListener("click", async () => {
  const result = await window.launcher.uninstall();
  if (result.success) {
    gameVersionEl.textContent = "Non installe";
    gameVersionEl.classList.remove("ok");
    btnPlay.disabled = true;
    btnPlay.classList.remove("ready");
    btnUninstall.style.display = "none";
    btnVerify.style.display = "none";
    setStatus("Desinstalle - relancez le launcher pour reinstaller");
  }
});

// Window controls
document.getElementById("btn-minimize").addEventListener("click", () => window.launcher.windowMinimize());
document.getElementById("btn-close").addEventListener("click", () => window.launcher.windowClose());

// =========================================================================
// INIT — Check launcher update FIRST, then auth
// =========================================================================

async function init() {
  // Step 1: Check if the launcher itself needs an update (before login)
  try {
    const info = await window.launcher.checkUpdates();
    launcherVersionEl.textContent = "v" + info.launcherVersion;

    if (info.launcherNeedsUpdate && info.remote?.launcher?.download_url) {
      setStatus("Mise a jour du launcher...");
      showProgress("MISE A JOUR DU LAUNCHER");
      await window.launcher.updateLauncher(info.remote.launcher.download_url);
      setStatus("Redemarrage...");
      return; // Launcher will restart
    }
  } catch {
    // Server unreachable — continue with auth flow anyway
  }

  // Step 2: Auth flow
  const auth = await window.launcher.getSavedAuth();
  if (auth?.access_token && auth?.username) {
    const refreshResult = await window.launcher.refreshToken();
    if (refreshResult.success) {
      showMain(auth.username);
      checkUpdatesAndPrepare();
      return;
    }
  }
  showAuth();
}

init();
