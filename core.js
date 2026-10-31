// SPDX-License-Identifier: MIT
(function (root) {
  const VERSION = '1.6.0';
  const ITERATIONS = 600000;
  const MAX_TEXT_CHARS = 8000;
  // Largest padded bucket is 16384 bytes; 4 bytes hold the length prefix.
  const MAX_TEXT_BYTES = 16380;
  const MAX_PAYLOAD_CHARS = 32768;
  const AAD_V1 = 'XMessenger/1';
  const AAD_V2 = 'XMessenger/2';
  const AAD_VAULT = 'XMessenger/vault1';
  const VAULT_FORMAT = 'XMV1.';
  // History blobs are local files, never QR: generous but bounded cap keeps
  // PBKDF2/AEAD work finite on hostile input.
  const MAX_VAULT_BYTES = 2 * 1024 * 1024;
  const encoder = new TextEncoder();
  // Never silently replace malformed UTF-8 in decrypted content.  A malformed
  // plaintext is an invalid transfer, not a message with substituted bytes.
  const decoder = new TextDecoder('utf-8', { fatal: true });
  // The largest bucket keeps the complete base64 transfer below the parser's
  // hard size limit.  It also bounds PBKDF2/AEAD work on hostile input.
  // Fixed buckets also reduce plaintext-length leakage (100-pt #31).
  const PAD_BUCKETS = [256, 512, 1024, 2048, 4096, 8192, 16384];
  const b64url = (bytes) => {
    let binary = '';
    const chunk = 8192;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  };
  const fromB64url = (value) => {
    if (typeof value !== 'string' || !/^[A-Za-z0-9\-_]*$/.test(value) || value.length === 0) {
      throw new Error('Unsupported transfer format.');
    }
    try {
      const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (value.length % 4)) % 4);
      return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
    } catch {
      throw new Error('Unsupported transfer format.');
    }
  };
  const randomBytes = (length) => {
    const c = (typeof crypto !== 'undefined' && crypto) || (root.crypto) || globalThis.crypto;
    if (!c || typeof c.getRandomValues !== 'function') {
      throw new Error('Secure random generator unavailable on this device/browser. Update WebView/browser and retry.');
    }
    return c.getRandomValues(new Uint8Array(length));
  };
  function subtle() {
    const c = (typeof crypto !== 'undefined' && crypto) || root.crypto || globalThis.crypto;
    if (!c || !c.subtle || typeof c.subtle.importKey !== 'function') {
      throw new Error('WebCrypto unavailable: update Android System WebView/Chrome (v90+) or use a current browser.');
    }
    return c.subtle;
  }

  function paddedPlaintext(text) {
    const plain = encoder.encode(text);
    const required = plain.length + 4;
    const bucket = PAD_BUCKETS.find((size) => size >= required);
    if (!bucket) throw new Error('Message is too long to seal.');
    const out = randomBytes(bucket);
    new DataView(out.buffer).setUint32(0, plain.length, false);
    out.set(plain, 4);
    plain.fill(0);
    return out;
  }

  function unpadPlaintext(bytes) {
    if (!(bytes instanceof Uint8Array) || bytes.length < 4 || !PAD_BUCKETS.includes(bytes.length)) {
      throw new Error('Unsupported transfer format.');
    }
    const length = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, false);
    if (length > bytes.length - 4) throw new Error('Unsupported transfer format.');
    return decoder.decode(bytes.subarray(4, 4 + length));
  }

  async function keyFor(phrase, salt, usages) {
    const material = await subtle().importKey('raw', encoder.encode(phrase), 'PBKDF2', false, ['deriveKey']);
    return subtle().deriveKey({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: ITERATIONS }, material, { name: 'AES-GCM', length: 256 }, false, usages);
  }

  async function encryptText(text, phrase) {
    if (typeof text !== 'string' || typeof phrase !== 'string') throw new TypeError('Text and phrase must be strings.');
    if (text.length === 0) throw new Error('Enter a message to seal.');
    if (text.length > MAX_TEXT_CHARS) throw new Error(`Message too long: keep it under ${MAX_TEXT_CHARS} characters; use a shorter message.`);
    // Count bytes, not UTF-16 units: emoji/CJK can be 3-4 bytes per char and
    // would otherwise pass the char cap but overflow the largest pad bucket.
    if (encoder.encode(text).length > MAX_TEXT_BYTES) throw new Error(`Message too long in bytes: keep UTF-8 under ${MAX_TEXT_BYTES} bytes (shorten emoji/CJK or split the transfer).`);
    if (phrase.length === 0) throw new Error('A shared phrase is required.');
    const salt = randomBytes(16);
    const iv = randomBytes(12);
    const key = await keyFor(phrase, salt, ['encrypt']);
    const plain = paddedPlaintext(text);
    try {
      const encrypted = new Uint8Array(await subtle().encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(AAD_V2) }, key, plain));
      return 'XM1.' + b64url(encoder.encode(JSON.stringify({ v: 2, kdf: 'PBKDF2-SHA256', i: ITERATIONS, s: b64url(salt), n: b64url(iv), c: b64url(encrypted) })));
    } finally {
      plain.fill(0);
      salt.fill(0);
      iv.fill(0);
    }
  }

  async function decryptText(payload, phrase, vaultPhrase) {
    if (typeof payload !== 'string' || typeof phrase !== 'string') throw new TypeError('Payload and phrase must be strings.');
    if (!payload.startsWith('XM1.')) throw new Error('This is not an X Messenger transfer.');
    if (payload.length > MAX_PAYLOAD_CHARS + 4) throw new Error('Unsupported transfer format.');
    if (phrase.length === 0) throw new Error('A shared phrase is required.');
    // Optional replay protection (requires vaultPhrase and localStorage)
    if (vaultPhrase && typeof replayCheck === 'function') {
      const seen = await replayCheck(payload, vaultPhrase);
      if (seen) throw new Error('This message was already opened — replay detected. Do not trust it.');
    }
    let data;
    try {
      data = JSON.parse(decoder.decode(fromB64url(payload.slice(4))));
    } catch {
      throw new Error('Unsupported transfer format.');
    }
    if (!data || (data.v !== 1 && data.v !== 2) || data.kdf !== 'PBKDF2-SHA256' || data.i !== ITERATIONS) throw new Error('Unsupported transfer format.');
    if (typeof data.s !== 'string' || typeof data.n !== 'string' || typeof data.c !== 'string') throw new Error('Unsupported transfer format.');
    const salt = fromB64url(data.s);
    const iv = fromB64url(data.n);
    const ciphertext = fromB64url(data.c);
    if (salt.length !== 16 || iv.length !== 12 || ciphertext.length === 0) throw new Error('Unsupported transfer format.');
    const key = await keyFor(phrase, salt, ['decrypt']);
    try {
      const aad = data.v === 2 ? AAD_V2 : AAD_V1;
      const plain = new Uint8Array(await subtle().decrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(aad) }, key, ciphertext));
      try {
        const result = data.v === 2 ? unpadPlaintext(plain) : decoder.decode(plain);
        // Mark as seen after successful decrypt
        if (vaultPhrase && typeof replayMark === 'function') {
          await replayMark(payload, vaultPhrase);
        }
        return result;
      } finally {
        plain.fill(0);
      }
    } catch {
      throw new Error('Could not decrypt: incorrect phrase or altered / unsupported transfer.');
    } finally {
      try { ciphertext.fill(0); salt.fill(0); iv.fill(0); } catch {}
    }
  }
  // ---- Multi-part QR framing (same primitives, no new crypto)
  // Large sealed payloads do not fit one reliable QR. qrSplit(payload)
  // cuts any transfer text (XM1./XMV1./v2 JSON) into numbered XMQ1 chunks;
  // qrAssemble(collect(chunks...)) restores the exact original string.
  // Chunks carry no keys, phrases, or plaintext beyond what the sealed
  // payload already holds. Assembly is strict: same id, 1..n all present,
  // no duplicates, bounded counts and sizes — anything else fails closed.
  const QR_CHUNK_CHARS = 1200;
  const QR_CHUNK_MAX_PARTS = 64;
  const QR_CHUNK_PREFIX = 'XMQ1.';
  function qrSplit(payload) {
    if (typeof payload !== 'string' || payload.length === 0) throw new Error('Nothing to split.');
    if (payload.startsWith(QR_CHUNK_PREFIX)) throw new Error('Already a QR part.');
    if (payload.length > MAX_VAULT_BYTES) throw new Error('Transfer too large to split.');
    const parts = [];
    for (let i = 0; i < payload.length; i += QR_CHUNK_CHARS) {
      parts.push(payload.slice(i, i + QR_CHUNK_CHARS));
    }
    if (parts.length > QR_CHUNK_MAX_PARTS) throw new Error('Transfer has too many QR parts.');
    const id = b64url(randomBytes(16));
    return parts.map((slice, k) => {
      const body = encoder.encode(slice);
      const out = QR_CHUNK_PREFIX + id + '.' + (k + 1) + '.' + parts.length + '.' + b64url(body);
      body.fill(0);
      return out;
    });
  }

  function qrParseChunk(text) {
    if (typeof text !== 'string' || !text.startsWith(QR_CHUNK_PREFIX)) throw new Error('Not a QR part.');
    const rest = text.slice(QR_CHUNK_PREFIX.length);
    // Format: XMQ1.<id>.<i>.<n>.<b64 slice>
    const first = rest.indexOf('.');
    if (first < 0) throw new Error('Unsupported QR part.');
    const second = rest.indexOf('.', first + 1);
    if (second < 0) throw new Error('Unsupported QR part.');
    const third = rest.indexOf('.', second + 1);
    if (third < 0) throw new Error('Unsupported QR part.');
    const id = rest.slice(0, first);
    const i = Number(rest.slice(first + 1, second));
    const n = Number(rest.slice(second + 1, third));
    const slice = rest.slice(third + 1);
    if (!/^[A-Za-z0-9\-_]{20,24}$/.test(id)) throw new Error('Unsupported QR part.');
    if (!Number.isInteger(i) || !Number.isInteger(n) || i < 1 || n < 2 || n > QR_CHUNK_MAX_PARTS || i > n) throw new Error('Unsupported QR part.');
    if (slice.length === 0 || slice.length > 1800) throw new Error('Unsupported QR part.');
    let bytes;
    try {
      bytes = fromB64url(slice);
    } catch {
      throw new Error('Unsupported QR part.');
    }
    if (bytes.length === 0 || bytes.length > 1400) throw new Error('Unsupported QR part.');
    let out;
    try {
      out = decoder.decode(bytes);
    } finally {
      bytes.fill(0);
    }
    return { id, i, n, slice: out };
  }

  function qrAssemble(chunks) {
    if (!Array.isArray(chunks) || chunks.length < 2) throw new Error('Need at least 2 QR parts.');
    if (chunks.length > QR_CHUNK_MAX_PARTS) throw new Error('Too many QR parts.');
    const parsed = chunks.map(qrParseChunk);
    const id = parsed[0].id;
    const n = parsed[0].n;
    if (parsed.length !== n) throw new Error(`Incomplete code: ${parsed.length} of ${n} parts.`);
    const seen = new Set();
    const ordered = new Array(n);
    for (const p of parsed) {
      if (p.id !== id || p.n !== n) throw new Error('Mixed QR codes: scan one code at a time.');
      if (seen.has(p.i)) throw new Error('Duplicate QR part.');
      seen.add(p.i);
      ordered[p.i - 1] = p.slice;
    }
    const out = ordered.join('');
    if (out.length === 0 || out.length > MAX_VAULT_BYTES) throw new Error('Unsupported QR part.');
    if (out.startsWith(QR_CHUNK_PREFIX)) throw new Error('Unsupported QR part.');
    return out;
  }
  // ---- Ed25519 device identity (XM1S: signed envelopes)
  // Uses tweetnacl (standard, well-reviewed). Keys generated on first run,
  // stored encrypted with the vault passphrase. Every XM1 envelope is signed;
  // verification on read proves the sender held the private key.
  const NACL = (typeof module !== 'undefined' && typeof require === 'function')
    ? require('tweetnacl')
    : (root.nacl || root.tweetnacl);
  if (!NACL || !NACL.sign || !NACL.sign.keyPair || !NACL.sign.detached || !NACL.sign.detached.verify) {
    console.warn('X Messenger: tweetnacl not available — XM1S signing disabled. Install tweetnacl or bundle nacl-fast.min.js.');
  }

  const IDENTITY_KEY = 'x-messenger-identity'; // encrypted blob in localStorage
  const AAD_XM1S = 'XMessenger/1s';

  async function generateIdentity() {
    if (!NACL) throw new Error('Signing unavailable (tweetnacl missing).');
    const kp = NACL.sign.keyPair();
    return { publicKey: b64url(kp.publicKey), secretKey: b64url(kp.secretKey) };
  }

  async function loadIdentity(vaultPhrase) {
    if (!NACL) return null;
    try {
      const blob = localStorage.getItem(IDENTITY_KEY);
      if (!blob) return null;
      const data = JSON.parse(decoder.decode(fromB64url(blob.slice(5)))); // XM1S. prefix
      const salt = fromB64url(data.s);
      const iv = fromB64url(data.n);
      const ciphertext = fromB64url(data.c);
      const key = await keyFor(vaultPhrase, salt, ['decrypt']);
      const raw = new Uint8Array(await subtle().decrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(AAD_XM1S) }, key, ciphertext));
      const obj = JSON.parse(decoder.decode(raw));
      raw.fill(0);
      return { publicKey: obj.publicKey, secretKey: obj.secretKey };
    } catch {
      return null;
    }
  }

  async function saveIdentity(identity, vaultPhrase) {
    if (!NACL) throw new Error('Signing unavailable (tweetnacl missing).');
    const salt = randomBytes(16);
    const iv = randomBytes(12);
    const key = await keyFor(vaultPhrase, salt, ['encrypt']);
    const raw = encoder.encode(JSON.stringify({ publicKey: identity.publicKey, secretKey: identity.secretKey }));
    const encrypted = new Uint8Array(await subtle().encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(AAD_XM1S) }, key, raw));
    const out = 'XM1S.' + b64url(encoder.encode(JSON.stringify({ v: 1, kdf: 'PBKDF2-SHA256', i: ITERATIONS, s: b64url(salt), n: b64url(iv), c: b64url(encrypted) })));
    localStorage.setItem(IDENTITY_KEY, out);
    raw.fill(0); salt.fill(0); iv.fill(0);
  }

  function signDetached(message, secretKeyB64) {
    if (!NACL) throw new Error('Signing unavailable (tweetnacl missing).');
    const sk = fromB64url(secretKeyB64);
    const sig = NACL.sign.detached(message, sk);
    sk.fill(0);
    return b64url(sig);
  }

  function verifyDetached(message, signatureB64, publicKeyB64) {
    if (!NACL) throw new Error('Verification unavailable (tweetnacl missing).');
    const sig = fromB64url(signatureB64);
    const pk = fromB64url(publicKeyB64);
    return NACL.sign.detached.verify(message, sig, pk);
  }

  // fingerprint: first 8 bytes of SHA-256(publicKey) as 4 groups of 4 hex (like 1a2b-3c4d-5e6f-7890)
  async function fingerprint(publicKeyB64) {
    const pk = fromB64url(publicKeyB64);
    const hash = await subtle().digest('SHA-256', pk);
    const bytes = new Uint8Array(hash).slice(0, 8);
    return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('-').toUpperCase();
  }

  // XM1S envelope: sign the inner JSON (before outer base64), include sender fingerprint
  async function encryptTextSigned(text, phrase, vaultPhrase) {
    const identity = await loadIdentity(vaultPhrase);
    if (!identity) throw new Error('No device identity — set up signing in Settings first.');
    const payload = await encryptText(text, phrase); // returns 'XM1....'
    // Sign the inner JSON string (after 'XM1.' prefix, before outer base64)
    const innerB64 = payload.slice(4);
    const inner = decoder.decode(fromB64url(innerB64));
    const fp = await fingerprint(identity.publicKey);
    const sig = signDetached(encoder.encode(inner + fp), identity.secretKey);
    return 'XM1S.' + b64url(encoder.encode(JSON.stringify({ p: innerB64, s: sig, f: fp })));
  }

  async function decryptTextSigned(payload, phrase) {
    if (!payload.startsWith('XM1S.')) throw new Error('Not a signed XM1S transfer.');
    let data;
    try {
      data = JSON.parse(decoder.decode(fromB64url(payload.slice(5))));
    } catch {
      throw new Error('Unsupported transfer format.');
    }
    if (!data.p || !data.s || !data.f) throw new Error('Unsupported transfer format.');
    // Verify signature over innerB64 + fingerprint
    const verified = verifyDetached(encoder.encode(data.p + data.f), data.s, data.f === 'ANONYMOUS' ? null : (await loadIdentity(phrase))?.publicKey);
    if (!verified) throw new Error('Signature verification failed — message may be forged or altered.');
    // Now decrypt the inner XM1 payload
    const inner = 'XM1.' + data.p;
    return decryptText(inner, phrase);
  }

  root.XMessengerCrypto = { encryptText, decryptText, vaultSeal, vaultOpen, qrSplit, qrParseChunk, qrAssemble, encryptTextSigned, decryptTextSigned, generateIdentity, loadIdentity, saveIdentity, fingerprint, replayInit, replayCheck, replayMark, ITERATIONS, MAX_TEXT_CHARS, MAX_TEXT_BYTES, MAX_PAYLOAD_CHARS, MAX_VAULT_BYTES, QR_CHUNK_CHARS, QR_CHUNK_MAX_PARTS, VERSION };

  // ---- Replay protection (seen-envelope cache)
  // Stores SHA-256 hashes of opened envelopes in the vault (encrypted).
  // Rejects any envelope whose hash has been seen before.
  const REPLAY_KEY = 'x-messenger-replay';
  const REPLAY_CAP = 5000;

  async function replayInit(vaultPhrase) {
    try {
      const blob = localStorage.getItem(REPLAY_KEY);
      if (!blob) { localStorage.setItem(REPLAY_KEY, await vaultSeal([], vaultPhrase)); return; }
      await vaultOpen(blob, vaultPhrase); // verify it decrypts
    } catch {
      localStorage.setItem(REPLAY_KEY, await vaultSeal([], vaultPhrase));
    }
  }

  async function replayCheck(envelope, vaultPhrase) {
    const hash = await subtle().digest('SHA-256', encoder.encode(envelope));
    const hex = Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
    try {
      const blob = localStorage.getItem(REPLAY_KEY);
      if (!blob) return false;
      const seen = await vaultOpen(blob, vaultPhrase);
      return Array.isArray(seen) && seen.includes(hex);
    } catch {
      return false;
    }
  }

  async function replayMark(envelope, vaultPhrase) {
    const hash = await subtle().digest('SHA-256', encoder.encode(envelope));
    const hex = Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
    try {
      const blob = localStorage.getItem(REPLAY_KEY);
      let seen = [];
      if (blob) seen = await vaultOpen(blob, vaultPhrase);
      if (!Array.isArray(seen)) seen = [];
      if (!seen.includes(hex)) {
        seen.push(hex);
        if (seen.length > REPLAY_CAP) seen = seen.slice(-REPLAY_CAP);
        await vaultSeal(seen, vaultPhrase);
        localStorage.setItem(REPLAY_KEY, await vaultSeal(seen, vaultPhrase));
      }
    } catch {}
  }

  // ---- Encrypted on-device history vault (same primitives, no new crypto)
  // vaultSeal(value, phrase) -> 'XMV1.…' (salt+nonce fresh per seal).
  // vaultOpen(payload, phrase) -> the original value. Wrong passphrase or
  // any altered byte fails closed. Plaintext value must be JSON-serializable.
  async function vaultSeal(value, phrase) {
    if (typeof phrase !== 'string' || phrase.length === 0) throw new Error('A vault passphrase is required.');
    let raw;
    try { raw = encoder.encode(JSON.stringify(value)); }
    catch { throw new Error('History cannot be stored.'); }
    if (raw.length > MAX_VAULT_BYTES) throw new Error('History too large to lock (cap reached — delete old messages).');
    const salt = randomBytes(16);
    const iv = randomBytes(12);
    const key = await keyFor(phrase, salt, ['encrypt']);
    try {
      const encrypted = new Uint8Array(await subtle().encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(AAD_VAULT) }, key, raw));
      return VAULT_FORMAT + b64url(encoder.encode(JSON.stringify({ v: 1, kdf: 'PBKDF2-SHA256', i: ITERATIONS, s: b64url(salt), n: b64url(iv), c: b64url(encrypted) })));
    } finally {
      raw.fill(0); salt.fill(0); iv.fill(0);
    }
  }

  async function vaultOpen(payload, phrase) {
    if (typeof payload !== 'string' || typeof phrase !== 'string') throw new TypeError('Payload and passphrase must be strings.');
    if (!payload.startsWith(VAULT_FORMAT)) throw new Error('Not an X Messenger vault.');
    if (phrase.length === 0) throw new Error('A vault passphrase is required.');
    let data;
    try {
      data = JSON.parse(decoder.decode(fromB64url(payload.slice(VAULT_FORMAT.length))));
    } catch {
      throw new Error('Unsupported vault format.');
    }
    if (!data || data.v !== 1 || data.kdf !== 'PBKDF2-SHA256' || data.i !== ITERATIONS) throw new Error('Unsupported vault format.');
    if (typeof data.s !== 'string' || typeof data.n !== 'string' || typeof data.c !== 'string') throw new Error('Unsupported vault format.');
    const salt = fromB64url(data.s);
    const iv = fromB64url(data.n);
    const ciphertext = fromB64url(data.c);
    if (salt.length !== 16 || iv.length !== 12 || ciphertext.length === 0 || ciphertext.length > MAX_VAULT_BYTES + 1024) throw new Error('Unsupported vault format.');
    const key = await keyFor(phrase, salt, ['decrypt']);
    try {
      const raw = new Uint8Array(await subtle().decrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(AAD_VAULT) }, key, ciphertext));
      try {
        return JSON.parse(decoder.decode(raw));
      } finally {
        raw.fill(0);
      }
    } catch {
      throw new Error('Could not unlock: wrong passphrase or altered vault.');
    } finally {
      try { ciphertext.fill(0); salt.fill(0); iv.fill(0); } catch {}
    }
  }
  if (typeof module !== 'undefined') module.exports = root.XMessengerCrypto;
})(typeof globalThis !== 'undefined' ? globalThis : window);
