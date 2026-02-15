#!/usr/bin/env node
/**
 * godot-mcp-proxy.mjs — Multiplexer for godot-mcp
 *
 * Problem: Each Claude Code instance spawns its own godot-mcp process,
 * but Godot only accepts ONE WebSocket connection at a time.
 *
 * Solution:
 *   - First instance = "hub": spawns the real godot-mcp, opens a local
 *     TCP server on port 19542, and multiplexes requests from all clients.
 *   - Subsequent instances = "clients": connect to the hub via TCP and
 *     proxy their MCP traffic through it.
 *   - If the hub dies, a client automatically promotes itself to hub.
 */

import net from "node:net";
import { spawn } from "node:child_process";

const HUB_PORT = 19542;

// =============================================================
// Content-Length framing (MCP stdio protocol, like LSP)
// =============================================================
class ContentLengthReader {
	constructor(stream, onMessage) {
		this._buf = Buffer.alloc(0);
		this._len = -1;
		this._onMessage = onMessage;
		stream.on("data", (chunk) => {
			this._buf = Buffer.concat([this._buf, chunk]);
			this._drain();
		});
	}
	_drain() {
		for (;;) {
			if (this._len < 0) {
				const i = this._buf.indexOf("\r\n\r\n");
				if (i < 0) return;
				const hdr = this._buf.subarray(0, i).toString();
				const m = hdr.match(/Content-Length:\s*(\d+)/i);
				if (!m) {
					// Discard malformed header
					this._buf = this._buf.subarray(i + 4);
					continue;
				}
				this._len = parseInt(m[1], 10);
				this._buf = this._buf.subarray(i + 4);
			}
			if (this._buf.length < this._len) return;
			const body = this._buf.subarray(0, this._len).toString();
			this._buf = this._buf.subarray(this._len);
			this._len = -1;
			try {
				this._onMessage(JSON.parse(body));
			} catch {
				/* ignore parse errors */
			}
		}
	}
}

function clWrite(stream, obj) {
	if (stream.destroyed || !stream.writable) return;
	const s = JSON.stringify(obj);
	stream.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`);
}

// =============================================================
// Newline-delimited JSON (hub ↔ client TCP link)
// =============================================================
class LineReader {
	constructor(stream, onMessage) {
		this._buf = "";
		stream.setEncoding("utf8");
		stream.on("data", (chunk) => {
			this._buf += chunk;
			const lines = this._buf.split("\n");
			this._buf = lines.pop();
			for (const l of lines) {
				if (!l.trim()) continue;
				try {
					onMessage(JSON.parse(l));
				} catch {
					/* ignore */
				}
			}
		});
	}
}

function nlWrite(stream, obj) {
	if (!stream.destroyed && stream.writable) {
		stream.write(JSON.stringify(obj) + "\n");
	}
}

// =============================================================
// Entry point
// =============================================================
async function main() {
	const hub = await tryConnect();
	if (hub) {
		runAsClient(hub);
	} else {
		try {
			await runAsHub();
		} catch {
			// Race condition: another instance became hub first
			setTimeout(() => main(), 500 + Math.random() * 500);
		}
	}
}

function tryConnect() {
	return new Promise((resolve) => {
		const s = net.createConnection({ port: HUB_PORT, host: "127.0.0.1" });
		const t = setTimeout(() => {
			s.destroy();
			resolve(null);
		}, 2000);
		s.on("connect", () => {
			clearTimeout(t);
			resolve(s);
		});
		s.on("error", () => {
			clearTimeout(t);
			resolve(null);
		});
	});
}

// =============================================================
// Client mode
// =============================================================
function runAsClient(socket) {
	// Claude Code stdin (Content-Length) → parse → hub (newline TCP)
	new ContentLengthReader(process.stdin, (msg) => nlWrite(socket, msg));

	// Hub (newline TCP) → parse → Claude Code stdout (Content-Length)
	new LineReader(socket, (msg) => clWrite(process.stdout, msg));

	socket.on("close", () => setTimeout(() => main(), 1000));
	socket.on("error", () => setTimeout(() => main(), 1000));

	process.stdin.on("end", () => {
		socket.destroy();
		process.exit(0);
	});
}

// =============================================================
// Hub mode
// =============================================================
function runAsHub() {
	return new Promise((resolve, reject) => {
		let nextId = 1;
		const pending = new Map(); // remappedId → { send, originalId, isInit }
		const tcpClients = new Set();
		let initResponse = null; // cached initialize result
		let stdinClosed = false;

		// --- Start real godot-mcp ---
		const child = spawn("npx", ["-y", "@satelliteoflove/godot-mcp"], {
			stdio: ["pipe", "pipe", "inherit"],
			shell: true,
			windowsHide: true,
		});

		// --- Read responses from godot-mcp ---
		new ContentLengthReader(child.stdout, (msg) => {
			if (msg.id != null && pending.has(msg.id)) {
				const { send, originalId, isInit } = pending.get(msg.id);
				pending.delete(msg.id);
				if (isInit && msg.result) {
					initResponse = JSON.parse(JSON.stringify(msg.result));
				}
				msg.id = originalId;
				send(msg);
			} else {
				// Notification → broadcast to everyone
				clWrite(process.stdout, msg);
				for (const c of tcpClients) nlWrite(c, msg);
			}
		});

		// --- Forward a request to godot-mcp with ID remapping ---
		function forward(msg, sendFn) {
			// Return cached initialize response for subsequent clients
			if (msg.method === "initialize" && initResponse) {
				sendFn({
					jsonrpc: "2.0",
					id: msg.id,
					result: initResponse,
				});
				return;
			}
			// Swallow duplicate initialized notifications
			if (msg.method === "notifications/initialized" && initResponse) {
				return;
			}
			// Remap request ID
			if (msg.id != null) {
				const rid = nextId++;
				pending.set(rid, {
					send: sendFn,
					originalId: msg.id,
					isInit: msg.method === "initialize",
				});
				msg = { ...msg, id: rid };
			}
			clWrite(child.stdin, msg);
		}

		// --- Own stdio (this Claude Code instance) ---
		new ContentLengthReader(process.stdin, (msg) => {
			forward(msg, (resp) => clWrite(process.stdout, resp));
		});

		process.stdin.on("end", () => {
			stdinClosed = true;
			maybeExit();
		});

		function maybeExit() {
			if (stdinClosed && tcpClients.size === 0) {
				try {
					child.kill();
				} catch {}
				try {
					server.close();
				} catch {}
				process.exit(0);
			}
		}

		// --- TCP server for other Claude Code instances ---
		const server = net.createServer((socket) => {
			tcpClients.add(socket);

			new LineReader(socket, (msg) => {
				forward(msg, (resp) => nlWrite(socket, resp));
			});

			socket.on("close", () => {
				tcpClients.delete(socket);
				maybeExit();
			});
			socket.on("error", () => {
				tcpClients.delete(socket);
				maybeExit();
			});
		});

		server.on("error", (e) => {
			try {
				child.kill();
			} catch {}
			reject(e);
		});

		server.listen(HUB_PORT, "127.0.0.1", () => resolve());

		// --- Cleanup ---
		child.on("exit", () => {
			try {
				server.close();
			} catch {}
			process.exit(0);
		});

		process.on("exit", () => {
			try {
				child.kill();
			} catch {}
			try {
				server.close();
			} catch {}
		});
		process.on("SIGINT", () => process.exit(0));
		process.on("SIGTERM", () => process.exit(0));
	});
}

main();
