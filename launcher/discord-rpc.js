// Discord Rich Presence Bridge
// Receives game state from Godot client via local TCP (port 27150)
// and forwards it to Discord Rich Presence.

const net = require("net");

// Discord RPC Application ID — set this after creating the app on Discord Developer Portal
const DISCORD_APP_ID = process.env.DISCORD_APP_ID || "1470475382628159489";
const RPC_PORT = 27150;

let rpcClient = null;
let rpcReady = false;
let currentActivity = null;
let tcpServer = null;

/**
 * Initialize Discord Rich Presence and start the TCP bridge server.
 * Call this when the game launches.
 */
function start() {
  startTcpServer();
  initDiscordRPC();
}

/**
 * Clean up Discord RPC and TCP server.
 * Call this when the game exits.
 */
function stop() {
  if (tcpServer) {
    tcpServer.close();
    tcpServer = null;
  }
  if (rpcClient) {
    try {
      rpcClient.destroy();
    } catch (_) {}
    rpcClient = null;
    rpcReady = false;
  }
}

function initDiscordRPC() {
  try {
    const DiscordRPC = require("discord-rpc");
    rpcClient = new DiscordRPC.Client({ transport: "ipc" });

    rpcClient.on("ready", () => {
      rpcReady = true;
      console.log("[discord-rpc] Connected to Discord");
      setActivity({
        state: "Dans le launcher",
        details: "ImperionOnline",
        largeImageKey: "imperion_logo",
        largeImageText: "ImperionOnline",
      });
    });

    rpcClient.on("disconnected", () => {
      rpcReady = false;
      console.log("[discord-rpc] Disconnected from Discord");
    });

    rpcClient.login({ clientId: DISCORD_APP_ID }).catch((err) => {
      console.log("[discord-rpc] Failed to connect:", err.message);
      rpcClient = null;
    });
  } catch (err) {
    console.log("[discord-rpc] discord-rpc package not available:", err.message);
  }
}

function setActivity(activity) {
  if (!rpcClient || !rpcReady) return;
  currentActivity = activity;

  const activityData = {
    state: activity.state || "En vol",
    details: activity.details || "ImperionOnline",
    largeImageKey: activity.large_image || activity.largeImageKey || "imperion_logo",
    largeImageText: activity.largeImageText || "ImperionOnline",
    startTimestamp: activity.startTimestamp || Date.now(),
    instance: false,
  };

  if (activity.party_size && activity.party_max) {
    activityData.partySize = activity.party_size;
    activityData.partyMax = activity.party_max;
  }

  rpcClient.setActivity(activityData).catch((err) => {
    console.log("[discord-rpc] Failed to set activity:", err.message);
  });
}

function startTcpServer() {
  if (tcpServer) return;

  tcpServer = net.createServer((socket) => {
    let buffer = "";

    socket.on("data", (data) => {
      buffer += data.toString();
      // Process complete JSON messages (newline-delimited)
      const lines = buffer.split("\n");
      buffer = lines.pop(); // Keep incomplete line in buffer

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const msg = JSON.parse(line);
          setActivity(msg);
        } catch (err) {
          console.log("[discord-rpc] Invalid JSON from game:", err.message);
        }
      }
    });

    socket.on("error", () => {}); // Ignore connection errors
  });

  tcpServer.on("error", (err) => {
    console.log("[discord-rpc] TCP server error:", err.message);
    tcpServer = null;
  });

  tcpServer.listen(RPC_PORT, "127.0.0.1", () => {
    console.log(`[discord-rpc] TCP bridge listening on 127.0.0.1:${RPC_PORT}`);
  });
}

module.exports = { start, stop, setActivity };
