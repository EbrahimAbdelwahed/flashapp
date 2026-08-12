import {
  createHmac,
  scryptSync,
  timingSafeEqual,
  randomBytes,
} from "node:crypto";

const SESSION_SECRET = process.env.SESSION_SECRET;
const ADMIN_PASSWORD_HASH = process.env.ADMIN_PASSWORD_HASH;

const COOKIE = "fa_admin";
const SESSION_SECONDS = 8 * 60 * 60;

function requireSecret() {
  if (!SESSION_SECRET || SESSION_SECRET.length < 32) {
    throw new Error("SESSION_SECRET mancante o troppo corta (min 32 caratteri).");
  }
  return SESSION_SECRET;
}

/** Confronto a tempo costante che non rivela la lunghezza degli operandi. */
function safeEqual(a, b) {
  const ha = createHmac("sha256", requireSecret()).update(String(a)).digest();
  const hb = createHmac("sha256", requireSecret()).update(String(b)).digest();
  return timingSafeEqual(ha, hb);
}

/* -------------------------------------------------------------------------
   Password admin — conservata come hash scrypt, mai in chiaro.

   Formato: scrypt:<N>:<r>:<p>:<salt base64url>:<hash base64url>

   Separatore ":" e base64**url** di proposito: il formato classico con "$" e
   base64 normale viene distrutto dalle shell e dai file .env, che espandono
   "$16384" come variabile. Qui non c'è nessun carattere da quotare.
   Generalo con: npm run hash
   ------------------------------------------------------------------------- */

const SCRYPT_MAXMEM = 64 * 1024 * 1024;

export function hashPassword(password) {
  const N = 16384, r = 8, p = 1, keylen = 64;
  const salt = randomBytes(16);
  const hash = scryptSync(password, salt, keylen, { N, r, p, maxmem: SCRYPT_MAXMEM });
  return `scrypt:${N}:${r}:${p}:${salt.toString("base64url")}:${hash.toString("base64url")}`;
}

/**
 * Legge sia il formato nuovo (":" + base64url) sia quello vecchio ("$" +
 * base64), così un hash già configurato e funzionante non smette di valere.
 * Ritorna null se la stringa non è interpretabile.
 */
function parseHash(stored) {
  const legacy = stored.startsWith("scrypt$");
  const parts = stored.split(legacy ? "$" : ":");
  if (parts.length !== 6 || parts[0] !== "scrypt") return null;

  const [, N, r, p, salt, hash] = parts;
  if (![N, r, p].every((n) => /^\d+$/.test(n))) return null;

  const encoding = legacy ? "base64" : "base64url";
  const expected = Buffer.from(hash, encoding);
  const saltBuf = Buffer.from(salt, encoding);
  if (expected.length < 32 || saltBuf.length < 8) return null;

  return { N: Number(N), r: Number(r), p: Number(p), salt: saltBuf, expected };
}

/**
 * Descrive perché la configurazione non è utilizzabile, o null se è a posto.
 * Serve a distinguere "password sbagliata" da "variabile d'ambiente rotta":
 * senza questa differenza un errore di setup sembra un errore di battitura.
 */
export function configError() {
  if (!SESSION_SECRET) return "SESSION_SECRET non è impostata.";
  if (SESSION_SECRET.length < 32) return "SESSION_SECRET è più corta di 32 caratteri.";
  if (!ADMIN_PASSWORD_HASH) return "ADMIN_PASSWORD_HASH non è impostata.";
  if (!parseHash(ADMIN_PASSWORD_HASH)) {
    return (
      "ADMIN_PASSWORD_HASH è arrivata corrotta (valore letto: " +
      `"${ADMIN_PASSWORD_HASH.slice(0, 12)}…", ${ADMIN_PASSWORD_HASH.length} caratteri). ` +
      "Di solito è la shell che ha mangiato i $: rigenerala con `npm run hash` e reincollala tra apici singoli."
    );
  }
  return null;
}

export function verifyPassword(password) {
  const parsed = parseHash(ADMIN_PASSWORD_HASH ?? "");
  if (!parsed) throw new Error("ADMIN_PASSWORD_HASH non utilizzabile.");

  const actual = scryptSync(password, parsed.salt, parsed.expected.length, {
    N: parsed.N,
    r: parsed.r,
    p: parsed.p,
    maxmem: SCRYPT_MAXMEM,
  });
  return timingSafeEqual(parsed.expected, actual);
}

/* -------------------------------------------------------------------------
   Sessione — cookie firmato HMAC, senza stato lato server.
   ------------------------------------------------------------------------- */

function sign(payload) {
  return createHmac("sha256", requireSecret()).update(payload).digest("base64url");
}

export function issueSession() {
  const payload = Buffer.from(
    JSON.stringify({ exp: Date.now() + SESSION_SECONDS * 1000 })
  ).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

function readCookie(req, name) {
  const header = req.headers.cookie;
  if (!header) return null;
  for (const part of header.split(";")) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    if (part.slice(0, eq).trim() === name) {
      return decodeURIComponent(part.slice(eq + 1).trim());
    }
  }
  return null;
}

export function isAuthenticated(req) {
  const token = readCookie(req, COOKIE);
  if (!token) return false;
  const dot = token.lastIndexOf(".");
  if (dot <= 0) return false;

  const payload = token.slice(0, dot);
  if (!safeEqual(token.slice(dot + 1), sign(payload))) return false;

  try {
    const { exp } = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    return typeof exp === "number" && exp > Date.now();
  } catch {
    return false;
  }
}

export function sessionCookie(value, maxAge) {
  return [
    `${COOKIE}=${value}`,
    "Path=/",
    "HttpOnly",
    "Secure",
    "SameSite=Strict",
    `Max-Age=${maxAge}`,
  ].join("; ");
}

export const SESSION_MAX_AGE = SESSION_SECONDS;

/* -------------------------------------------------------------------------
   Identità del chiamante per il rate limit.
   L'IP non viene mai salvato in chiaro: si conserva solo un HMAC troncato.
   ------------------------------------------------------------------------- */

export function clientKey(req) {
  const forwarded = req.headers["x-forwarded-for"];
  const ip =
    req.headers["x-real-ip"] ||
    (typeof forwarded === "string" ? forwarded.split(",")[0].trim() : "") ||
    req.socket?.remoteAddress ||
    "unknown";
  return createHmac("sha256", requireSecret()).update(ip).digest("hex").slice(0, 32);
}

/** Header applicati a ogni risposta delle API. */
export function apiHeaders(res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
}
