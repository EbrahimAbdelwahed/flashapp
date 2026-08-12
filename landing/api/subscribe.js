import { sql, ensureSchema, allow } from "../lib/db.js";
import { clientKey, apiHeaders } from "../lib/auth.js";

const SOURCES = new Set(["Reddit", "TikTok", "Instagram", "Passaparola", "Altro"]);
const EMAIL = /^[^\s@]{1,64}@[^\s@.]+(\.[^\s@.]+)+$/;

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
  if (!body || typeof body !== "object") {
    return res.status(400).json({ ok: false, error: "bad_request" });
  }

  const email = String(body.email ?? "").trim().toLowerCase();
  const source = String(body.source ?? "");
  const landing = String(body.landing ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, "") // via i caratteri di controllo
    .slice(0, 200);

  if (email.length > 254 || !EMAIL.test(email) || !SOURCES.has(source)) {
    return res.status(400).json({ ok: false, error: "invalid_input" });
  }

  try {
    await ensureSchema();

    const key = clientKey(req);
    if (!(await allow(`sub:${key}`, 5, 3600))) {
      return res.status(429).json({ ok: false, error: "rate_limited" });
    }

    // ON CONFLICT DO NOTHING: un indirizzo già presente non produce errori
    // e non cambia la risposta, così la pagina non diventa un modo per
    // scoprire chi è iscritto.
    await sql`
      INSERT INTO subscribers (email, source, landing)
      VALUES (${email}, ${source}, ${landing || null})
      ON CONFLICT (email) DO NOTHING
    `;

    return res.status(200).json({ ok: true });
  } catch (err) {
    // L'indirizzo non finisce mai nei log.
    console.error("subscribe failed:", err?.message ?? err);
    return res.status(500).json({ ok: false, error: "server_error" });
  }
}
