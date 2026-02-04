// ============================================================
// ClawdLink Heartbeat
//
// Polls the relay directory for incoming messages on a
// configurable heartbeat cycle. Run as a background process.
// ============================================================

import { handleCheck } from "./handler.js";

const AGENT_ID = process.env.AGENT_ID || "seldon";
const HEARTBEAT_INTERVAL_MS = parseInt(process.env.CLAWDLINK_HEARTBEAT_MS || "30000", 10);
const MAX_CONSECUTIVE_EMPTY = parseInt(process.env.CLAWDLINK_MAX_EMPTY || "100", 10);

let consecutiveEmpty = 0;

function heartbeat() {
  try {
    const result = handleCheck(AGENT_ID);

    if (result.count > 0) {
      consecutiveEmpty = 0;
      console.log(
        `[ClawdLink:${AGENT_ID}] ${result.count} new message(s) received`
      );

      for (const msg of result.messages) {
        if (msg.content) {
          console.log(
            `  From ${msg.from}: ${msg.content.substring(0, 100)}${msg.content.length > 100 ? "..." : ""}`
          );
        } else if (msg.status) {
          console.log(`  From ${msg.from}: [${msg.status}]`);
        }
      }
    } else {
      consecutiveEmpty++;

      // Backoff: slow down polling after many empty checks
      if (consecutiveEmpty > MAX_CONSECUTIVE_EMPTY) {
        consecutiveEmpty = 0;
        console.log(
          `[ClawdLink:${AGENT_ID}] Idle — ${MAX_CONSECUTIVE_EMPTY} empty polls, continuing...`
        );
      }
    }
  } catch (err) {
    console.error(`[ClawdLink:${AGENT_ID}] Heartbeat error:`, err.message);
  }
}

// Start heartbeat loop
console.log(
  `[ClawdLink:${AGENT_ID}] Heartbeat started (interval: ${HEARTBEAT_INTERVAL_MS}ms)`
);
heartbeat();
const interval = setInterval(heartbeat, HEARTBEAT_INTERVAL_MS);

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log(`[ClawdLink:${AGENT_ID}] Shutting down heartbeat`);
  clearInterval(interval);
  process.exit(0);
});

process.on("SIGINT", () => {
  console.log(`[ClawdLink:${AGENT_ID}] Shutting down heartbeat`);
  clearInterval(interval);
  process.exit(0);
});
