// =========================================================================
// SpaceGame Launcher — Frontend Logic
// Flow: Check saved auth → Login/Register → Check updates → Play
// =========================================================================

// --- DOM ---
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

// --- Helpers ---

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / 1048576).toFixed(1) + " MB";
}

function setStatus(text) { statusText.textContent = text; }

function showProgress(label) {
  progressLabel.textContent = label;
  progressContainer.style.display = "block";
  progressFill.style.width = "0%";
  progressText.textContent = "0%";
}

function hideProgress() { progressContainer.style.display = "none"; }

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

function showAuth() {
  authSection.style.display = "block";
  mainSection.style.display = "none";
}

function showMain(username) {
  authSection.style.display = "none";
  mainSection.style.display = "block";
  userDisplay.textContent = username.toUpperCase();
}

// --- Progress listener ---

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
  btnUninstall.style.display = "none";
  showAuth();
});

// =========================================================================
// UPDATES & LAUNCH
// =========================================================================

async function checkUpdatesAndPrepare() {
  setStatus("Verification des mises a jour...");

  const info = await window.launcher.checkUpdates();

  launcherVersionEl.textContent = "v" + info.launcherVersion;
  gameVersionEl.textContent = info.gameVersion ? "v" + info.gameVersion : "Non installe";

  // Offline / error
  if (info.error) {
    setStatus("Serveur injoignable");
    if (info.gameInstalled) {
      btnPlay.disabled = false;
      btnUninstall.style.display = "block";
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

  // Auto-update launcher
  if (info.launcherNeedsUpdate && info.remote.launcher.download_url) {
    setStatus("Mise a jour du launcher...");
    showProgress("MISE A JOUR DU LAUNCHER");
    await window.launcher.updateLauncher(info.remote.launcher.download_url);
    setStatus("Redemarrage...");
    return;
  }

  // Auto-update game
  if (info.gameNeedsUpdate && info.remote.game.download_url) {
    setStatus("Mise a jour du jeu...");
    showProgress("MISE A JOUR DU JEU");
    try {
      await window.launcher.updateGame(info.remote.game.download_url, info.remote.game.version);
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
  btnUninstall.style.display = "block";
}

// Launch
btnPlay.addEventListener("click", async () => {
  btnPlay.disabled = true;
  setStatus("Lancement...");

  const result = await window.launcher.launchGame();
  if (result.error) {
    setStatus("Erreur: " + result.error);
    btnPlay.disabled = false;
    return;
  }

  setStatus("Jeu en cours");
  await sleep(1500);
  window.launcher.windowClose();
});

// Uninstall
btnUninstall.addEventListener("click", async () => {
  const result = await window.launcher.uninstall();
  if (result.success) {
    gameVersionEl.textContent = "Non installe";
    gameVersionEl.classList.remove("ok");
    btnPlay.disabled = true;
    btnUninstall.style.display = "none";
    setStatus("Desinstalle - relancez le launcher pour reinstaller");
  }
});

// Window controls
document.getElementById("btn-minimize").addEventListener("click", () => window.launcher.windowMinimize());
document.getElementById("btn-close").addEventListener("click", () => window.launcher.windowClose());

// =========================================================================
// INIT — Check saved session
// =========================================================================

async function init() {
  const auth = await window.launcher.getSavedAuth();
  if (auth?.access_token && auth?.username) {
    // Try to refresh token to verify it's still valid
    const refreshResult = await window.launcher.refreshToken();
    if (refreshResult.success) {
      showMain(auth.username);
      checkUpdatesAndPrepare();
      return;
    }
    // Token expired, show login
  }
  showAuth();
}

init();
