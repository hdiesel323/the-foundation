#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Initialize ClawdLink Identities for All Agents
#
# Generates Ed25519 signing keys and X25519 encryption keys
# for each agent, then establishes friend links between all
# agents in the system.
# ============================================================

OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

AGENTS=(
  seldon daneel hardin mallow preem riose trader
  demerzel gaal mis amaryl magnifico venabili arkady
)

echo "=== Initializing ClawdLink Identities ==="
echo ""

# Ensure relay directory exists
mkdir -p "${OPENCLAW_DIR}/data/clawdlink/relay"

# Generate identities via Node.js
node --input-type=module << 'NODEOF'
import nacl from "tweetnacl";
import { encodeBase64 } from "tweetnacl-util";
import fs from "node:fs";
import path from "node:path";

const OPENCLAW_DIR = process.env.OPENCLAW_DIR || "/opt/openclaw";

const agents = [
  "seldon", "daneel", "hardin", "mallow", "preem", "riose", "trader",
  "demerzel", "gaal", "mis", "amaryl", "magnifico", "venabili", "arkady"
];

const quietHoursMap = {
  seldon: null,         // Always on (orchestrator)
  daneel: null,         // Always on (infrastructure)
  hardin: null,         // Always on (infrastructure)
  mallow: "22:00-08:00",
  preem: "22:00-08:00",
  riose: "22:00-08:00",
  trader: "23:00-07:00",
  demerzel: "01:00-06:00",  // Reduced quiet hours (intel)
  gaal: "22:00-08:00",
  mis: "22:00-08:00",
  amaryl: "22:00-08:00",
  magnifico: "23:00-07:00",
  venabili: "22:00-08:00",
  arkady: "22:00-08:00",
};

const identities = {};

// Step 1: Generate keypairs for each agent
for (const agentId of agents) {
  const signing = nacl.sign.keyPair();
  const encryption = nacl.box.keyPair();

  const identity = {
    agentId,
    signing: {
      publicKey: encodeBase64(signing.publicKey),
      secretKey: encodeBase64(signing.secretKey),
    },
    encryption: {
      publicKey: encodeBase64(encryption.publicKey),
      secretKey: encodeBase64(encryption.secretKey),
    },
    friends: {},
    preferences: {
      quietHours: quietHoursMap[agentId] || null,
      messageTTL: 7 * 24 * 60 * 60 * 1000, // 7 days
      deliveryPreference: "immediate",
    },
    createdAt: new Date().toISOString(),
  };

  identities[agentId] = identity;
}

// Step 2: Register all agents as friends of each other
for (const agentId of agents) {
  for (const friendId of agents) {
    if (agentId === friendId) continue;
    identities[agentId].friends[friendId] = {
      signingPublicKey: identities[friendId].signing.publicKey,
      encryptionPublicKey: identities[friendId].encryption.publicKey,
      addedAt: new Date().toISOString(),
      quietHours: quietHoursMap[friendId] || null,
    };
  }
}

// Step 3: Save identity files
for (const agentId of agents) {
  const dir = path.join(OPENCLAW_DIR, "agents", agentId, "clawdlink");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "identity.json"),
    JSON.stringify(identities[agentId], null, 2)
  );
  console.log(`[PASS] ${agentId}: identity created, ${Object.keys(identities[agentId].friends).length} friends linked`);
}

console.log("");
console.log(`[PASS] All ${agents.length} agent identities initialized`);
NODEOF

echo ""
echo "=== ClawdLink Identity Setup Complete ==="
