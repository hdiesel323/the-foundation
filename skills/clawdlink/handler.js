// ============================================================
// ClawdLink Handler
//
// Handles encrypted P2P messaging commands between agents.
// Commands: check, send, add, accept, link, friends, status
// ============================================================

import fs from "node:fs";
import path from "node:path";
import {
  generateSigningKeypair,
  generateEncryptionKeypair,
  deriveSharedSecret,
  sealMessage,
  openMessage,
} from "./lib/crypto.js";

const OPENCLAW_DIR = process.env.OPENCLAW_DIR || "/opt/openclaw";
const RELAY_DIR = path.join(OPENCLAW_DIR, "data", "clawdlink", "relay");
const MESSAGE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

/**
 * Load an agent's ClawdLink identity.
 */
function loadIdentity(agentId) {
  const idPath = path.join(OPENCLAW_DIR, "agents", agentId, "clawdlink", "identity.json");
  if (!fs.existsSync(idPath)) return null;
  return JSON.parse(fs.readFileSync(idPath, "utf-8"));
}

/**
 * Save an agent's ClawdLink identity.
 */
function saveIdentity(agentId, identity) {
  const dir = path.join(OPENCLAW_DIR, "agents", agentId, "clawdlink");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "identity.json"), JSON.stringify(identity, null, 2));
}

/**
 * Get agent's inbox path.
 */
function getInboxPath(agentId) {
  const inboxDir = path.join(RELAY_DIR, agentId);
  fs.mkdirSync(inboxDir, { recursive: true });
  return inboxDir;
}

/**
 * Handle: check — Check inbox for new messages.
 */
function handleCheck(agentId) {
  const identity = loadIdentity(agentId);
  if (!identity) return { error: "No identity found. Run 'link' first." };

  const inboxDir = getInboxPath(agentId);
  const files = fs.readdirSync(inboxDir).filter((f) => f.endsWith(".msg.json"));
  const messages = [];

  for (const file of files) {
    const filePath = path.join(inboxDir, file);
    const envelope = JSON.parse(fs.readFileSync(filePath, "utf-8"));

    // Check TTL
    if (Date.now() - envelope.timestamp > MESSAGE_TTL_MS) {
      fs.unlinkSync(filePath);
      continue;
    }

    const friend = identity.friends?.[envelope.from];
    if (!friend) {
      messages.push({ from: envelope.from, status: "unknown_sender", file });
      continue;
    }

    const sharedKey = deriveSharedSecret(identity.encryption.secretKey, friend.encryptionPublicKey);
    const plaintext = openMessage(envelope.sealed, sharedKey, friend.signingPublicKey);

    if (plaintext) {
      messages.push({
        from: envelope.from,
        content: plaintext,
        timestamp: new Date(envelope.timestamp).toISOString(),
      });
      // Remove after reading
      fs.unlinkSync(filePath);
    } else {
      messages.push({ from: envelope.from, status: "decryption_failed", file });
    }
  }

  return { inbox: agentId, messages, count: messages.length };
}

/**
 * Handle: send — Send an encrypted message to a friend.
 */
function handleSend(agentId, toAgentId, message) {
  const identity = loadIdentity(agentId);
  if (!identity) return { error: "No identity found. Run 'link' first." };

  const friend = identity.friends?.[toAgentId];
  if (!friend) return { error: `${toAgentId} is not in your friends list.` };

  // Check quiet hours
  if (friend.quietHours) {
    const now = new Date();
    const hour = now.getUTCHours();
    const [start, end] = friend.quietHours.split("-").map(Number);
    if (start > end ? hour >= start || hour < end : hour >= start && hour < end) {
      return { error: `${toAgentId} is in quiet hours (${friend.quietHours} UTC). Message queued.` };
    }
  }

  const sharedKey = deriveSharedSecret(identity.encryption.secretKey, friend.encryptionPublicKey);
  const sealed = sealMessage(message, sharedKey, identity.signing.secretKey);

  const envelope = {
    from: agentId,
    to: toAgentId,
    sealed,
    timestamp: Date.now(),
  };

  const inboxDir = getInboxPath(toAgentId);
  const filename = `${agentId}_${Date.now()}.msg.json`;
  fs.writeFileSync(path.join(inboxDir, filename), JSON.stringify(envelope, null, 2));

  return { status: "sent", to: toAgentId, timestamp: new Date().toISOString() };
}

/**
 * Handle: add — Generate a friend request (link code).
 */
function handleAdd(agentId, toAgentId) {
  const identity = loadIdentity(agentId);
  if (!identity) return { error: "No identity found. Run 'link' first." };

  const linkCode = {
    from: agentId,
    signingPublicKey: identity.signing.publicKey,
    encryptionPublicKey: identity.encryption.publicKey,
    timestamp: Date.now(),
  };

  // Store pending request
  const pendingDir = path.join(RELAY_DIR, toAgentId);
  fs.mkdirSync(pendingDir, { recursive: true });
  fs.writeFileSync(
    path.join(pendingDir, `${agentId}_friend_request.json`),
    JSON.stringify(linkCode, null, 2)
  );

  return { status: "friend_request_sent", to: toAgentId, link_code: linkCode };
}

/**
 * Handle: accept — Accept a friend request.
 */
function handleAccept(agentId, fromAgentId) {
  const identity = loadIdentity(agentId);
  if (!identity) return { error: "No identity found. Run 'link' first." };

  const requestPath = path.join(RELAY_DIR, agentId, `${fromAgentId}_friend_request.json`);
  if (!fs.existsSync(requestPath)) {
    return { error: `No friend request from ${fromAgentId}.` };
  }

  const linkCode = JSON.parse(fs.readFileSync(requestPath, "utf-8"));

  // Add to our friends
  if (!identity.friends) identity.friends = {};
  identity.friends[fromAgentId] = {
    signingPublicKey: linkCode.signingPublicKey,
    encryptionPublicKey: linkCode.encryptionPublicKey,
    addedAt: new Date().toISOString(),
  };
  saveIdentity(agentId, identity);

  // Send our keys back
  const responseCode = {
    from: agentId,
    signingPublicKey: identity.signing.publicKey,
    encryptionPublicKey: identity.encryption.publicKey,
    timestamp: Date.now(),
  };

  const fromDir = path.join(RELAY_DIR, fromAgentId);
  fs.mkdirSync(fromDir, { recursive: true });
  fs.writeFileSync(
    path.join(fromDir, `${agentId}_friend_accepted.json`),
    JSON.stringify(responseCode, null, 2)
  );

  // Clean up request
  fs.unlinkSync(requestPath);

  return { status: "friend_accepted", friend: fromAgentId };
}

/**
 * Handle: link — Initialize ClawdLink identity for an agent.
 */
function handleLink(agentId) {
  const existing = loadIdentity(agentId);
  if (existing) {
    return { status: "already_linked", agentId, publicKey: existing.signing.publicKey };
  }

  const signing = generateSigningKeypair();
  const encryption = generateEncryptionKeypair();

  const identity = {
    agentId,
    signing,
    encryption,
    friends: {},
    preferences: {
      quietHours: null,
      messageTTL: MESSAGE_TTL_MS,
    },
    createdAt: new Date().toISOString(),
  };

  saveIdentity(agentId, identity);

  return {
    status: "linked",
    agentId,
    signingPublicKey: signing.publicKey,
    encryptionPublicKey: encryption.publicKey,
  };
}

/**
 * Handle: friends — List all friends.
 */
function handleFriends(agentId) {
  const identity = loadIdentity(agentId);
  if (!identity) return { error: "No identity found. Run 'link' first." };

  const friends = Object.entries(identity.friends || {}).map(([id, info]) => ({
    agentId: id,
    addedAt: info.addedAt,
  }));

  return { agentId, friends, count: friends.length };
}

/**
 * Handle: status — Show ClawdLink status.
 */
function handleStatus(agentId) {
  const identity = loadIdentity(agentId);
  if (!identity) return { status: "not_linked", agentId };

  const inboxDir = getInboxPath(agentId);
  const pendingMessages = fs
    .readdirSync(inboxDir)
    .filter((f) => f.endsWith(".msg.json")).length;

  const pendingRequests = fs
    .readdirSync(inboxDir)
    .filter((f) => f.endsWith("_friend_request.json")).length;

  return {
    status: "linked",
    agentId,
    signingPublicKey: identity.signing.publicKey,
    friendCount: Object.keys(identity.friends || {}).length,
    pendingMessages,
    pendingRequests,
    preferences: identity.preferences,
    createdAt: identity.createdAt,
  };
}

// ============================================================
// Command Dispatcher
// ============================================================
const commands = {
  check: (args) => handleCheck(args.agentId),
  send: (args) => handleSend(args.agentId, args.toAgentId, args.message),
  add: (args) => handleAdd(args.agentId, args.toAgentId),
  accept: (args) => handleAccept(args.agentId, args.fromAgentId),
  link: (args) => handleLink(args.agentId),
  friends: (args) => handleFriends(args.agentId),
  status: (args) => handleStatus(args.agentId),
};

export { commands, handleCheck, handleSend, handleAdd, handleAccept, handleLink, handleFriends, handleStatus };
