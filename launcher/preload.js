const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("launcher", {
  // Auth
  login: (username, password) => ipcRenderer.invoke("login", username, password),
  register: (username, email, password) => ipcRenderer.invoke("register", username, email, password),
  getSavedAuth: () => ipcRenderer.invoke("get-saved-auth"),
  logout: () => ipcRenderer.invoke("logout"),
  refreshToken: () => ipcRenderer.invoke("refresh-token"),

  // Updates
  checkUpdates: () => ipcRenderer.invoke("check-updates"),
  updateLauncher: (downloadUrl) => ipcRenderer.invoke("update-launcher", downloadUrl),
  updateGame: (downloadUrl, version) => ipcRenderer.invoke("update-game", downloadUrl, version),

  // Changelog
  getChangelog: () => ipcRenderer.invoke("get-changelog"),

  // Server stats / Player state / Corporation
  getServerStats: () => ipcRenderer.invoke("get-server-stats"),
  getPlayerState: () => ipcRenderer.invoke("get-player-state"),
  getCorporation: (corpId) => ipcRenderer.invoke("get-corporation", corpId),

  // Settings
  getSettings: () => ipcRenderer.invoke("get-settings"),
  saveSettings: (settings) => ipcRenderer.invoke("save-settings", settings),

  // Verify
  verifyGame: () => ipcRenderer.invoke("verify-game"),

  // Launch
  launchGame: () => ipcRenderer.invoke("launch-game"),
  uninstall: () => ipcRenderer.invoke("uninstall"),

  // Events from main process
  onProgress: (cb) => ipcRenderer.on("progress", (_, data) => cb(data)),
  onStatus: (cb) => ipcRenderer.on("status", (_, msg) => cb(msg)),
  onGameExited: (cb) => ipcRenderer.on("game-exited", () => cb()),

  // Window controls
  windowMinimize: () => ipcRenderer.send("window-minimize"),
  windowClose: () => ipcRenderer.send("window-close"),
});
