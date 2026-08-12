import { ensureSchema, allow } from "../lib/db.js";
import {
  verifyPassword,
  configError,
  issueSession,
  sessionCookie,
  clientKey,
  apiHeaders,
  SESSION_MAX_AGE,
} from "../lib/auth.js";

export default async function handler(req, res) {
  apiHeaders(res);

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ ok: false, error: "method_not_allowed" });
  }

  let body = req.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body);
    } catch {
      return res.status(400).json({ ok: false, error: "bad_request" });
    }
  }

  // Una configurazione rotta non deve somigliare a una password sbagliata:
  // il messaggio dice esattamente cosa manca, senza rivelare nessun valore.
  const misconfigured = configError();
  if (misconfigured) {
    console.error("login: configurazione non valida —", misconfigured);
    return res
      .status(500)
      .json({ ok: false, error: "server_misconfigured", detail: misconfigured });
  }

  const password = String(body?.password ?? "");
  if (!password || password.length > 512) {
    return res.status(401).json({ ok: false, error: "invalid_credentials" });
  }

  try {
    await ensureSchema();

    // 8 tentativi ogni 15 minuti per chiamante: rende inutile il brute force
    // senza bloccare chi sbaglia a digitare.
    if (!(await allow(`login:${clientKey(req)}`, 8, 900))) {
      return res.status(429).json({ ok: false, error: "rate_limited" });
    }

    if (!verifyPassword(password)) {
      return res.status(401).json({ ok: false, error: "invalid_credentials" });
    }

    res.setHeader("Set-Cookie", sessionCookie(issueSession(), SESSION_MAX_AGE));
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error("login failed:", err?.message ?? err);
    return res.status(500).json({ ok: false, error: "server_error" });
  }
}
