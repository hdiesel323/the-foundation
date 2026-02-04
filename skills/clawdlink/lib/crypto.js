// ============================================================
// ClawdLink Crypto Module
//
// Implements XChaCha20-Poly1305 encryption and Ed25519 signatures
// for secure agent-to-agent messaging.
// ============================================================

import nacl from "tweetnacl";
import { encodeBase64, decodeBase64, encodeUTF8, decodeUTF8 } from "tweetnacl-util";

/**
 * Generate a new Ed25519 signing keypair.
 * @returns {{ publicKey: string, secretKey: string }} Base64-encoded keys
 */
export function generateSigningKeypair() {
  const kp = nacl.sign.keyPair();
  return {
    publicKey: encodeBase64(kp.publicKey),
    secretKey: encodeBase64(kp.secretKey),
  };
}

/**
 * Generate an X25519 encryption keypair for key exchange.
 * @returns {{ publicKey: string, secretKey: string }} Base64-encoded keys
 */
export function generateEncryptionKeypair() {
  const kp = nacl.box.keyPair();
  return {
    publicKey: encodeBase64(kp.publicKey),
    secretKey: encodeBase64(kp.secretKey),
  };
}

/**
 * Derive a shared secret from our secret key and their public key (X25519).
 * @param {string} ourSecretKeyB64 - Our X25519 secret key (base64)
 * @param {string} theirPublicKeyB64 - Their X25519 public key (base64)
 * @returns {Uint8Array} 32-byte shared secret
 */
export function deriveSharedSecret(ourSecretKeyB64, theirPublicKeyB64) {
  const ourSecret = decodeBase64(ourSecretKeyB64);
  const theirPublic = decodeBase64(theirPublicKeyB64);
  return nacl.box.before(theirPublic, ourSecret);
}

/**
 * Encrypt a message using XChaCha20-Poly1305 (NaCl secretbox with shared key).
 * @param {string} plaintext - Message to encrypt
 * @param {Uint8Array} sharedKey - 32-byte shared secret
 * @returns {{ ciphertext: string, nonce: string }} Base64-encoded ciphertext and nonce
 */
export function encrypt(plaintext, sharedKey) {
  const nonce = nacl.randomBytes(nacl.secretbox.nonceLength);
  const messageBytes = decodeUTF8(plaintext);
  const ciphertext = nacl.secretbox(messageBytes, nonce, sharedKey);

  return {
    ciphertext: encodeBase64(ciphertext),
    nonce: encodeBase64(nonce),
  };
}

/**
 * Decrypt a message using XChaCha20-Poly1305.
 * @param {string} ciphertextB64 - Base64 ciphertext
 * @param {string} nonceB64 - Base64 nonce
 * @param {Uint8Array} sharedKey - 32-byte shared secret
 * @returns {string|null} Decrypted plaintext or null on failure
 */
export function decrypt(ciphertextB64, nonceB64, sharedKey) {
  const ciphertext = decodeBase64(ciphertextB64);
  const nonce = decodeBase64(nonceB64);
  const plaintext = nacl.secretbox.open(ciphertext, nonce, sharedKey);

  if (!plaintext) return null;
  return encodeUTF8(plaintext);
}

/**
 * Sign a message with Ed25519.
 * @param {string} message - Message to sign
 * @param {string} secretKeyB64 - Ed25519 secret key (base64)
 * @returns {string} Base64-encoded signature
 */
export function sign(message, secretKeyB64) {
  const secretKey = decodeBase64(secretKeyB64);
  const messageBytes = decodeUTF8(message);
  const signature = nacl.sign.detached(messageBytes, secretKey);
  return encodeBase64(signature);
}

/**
 * Verify an Ed25519 signature.
 * @param {string} message - Original message
 * @param {string} signatureB64 - Base64-encoded signature
 * @param {string} publicKeyB64 - Ed25519 public key (base64)
 * @returns {boolean} True if signature is valid
 */
export function verify(message, signatureB64, publicKeyB64) {
  const publicKey = decodeBase64(publicKeyB64);
  const signature = decodeBase64(signatureB64);
  const messageBytes = decodeUTF8(message);
  return nacl.sign.detached.verify(messageBytes, signature, publicKey);
}

/**
 * Create a sealed message: encrypted + signed envelope.
 * @param {string} plaintext - Message content
 * @param {Uint8Array} sharedKey - Shared encryption key
 * @param {string} signingSecretKeyB64 - Sender's Ed25519 secret key
 * @returns {{ ciphertext: string, nonce: string, signature: string }}
 */
export function sealMessage(plaintext, sharedKey, signingSecretKeyB64) {
  const { ciphertext, nonce } = encrypt(plaintext, sharedKey);
  const signature = sign(`${ciphertext}:${nonce}`, signingSecretKeyB64);
  return { ciphertext, nonce, signature };
}

/**
 * Open a sealed message: verify signature + decrypt.
 * @param {{ ciphertext: string, nonce: string, signature: string }} sealed
 * @param {Uint8Array} sharedKey - Shared encryption key
 * @param {string} senderPublicKeyB64 - Sender's Ed25519 public key
 * @returns {string|null} Decrypted plaintext or null if verification fails
 */
export function openMessage(sealed, sharedKey, senderPublicKeyB64) {
  const { ciphertext, nonce, signature } = sealed;

  // Verify signature first
  const valid = verify(`${ciphertext}:${nonce}`, signature, senderPublicKeyB64);
  if (!valid) return null;

  return decrypt(ciphertext, nonce, sharedKey);
}
