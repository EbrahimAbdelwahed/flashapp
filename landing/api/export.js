import { sql, ensureSchema } from "../lib/db.js";
import { isAuthenticated, apiHeaders } from "../lib/auth.js";

/**
 * Escape CSV + difesa contro la formula injection: Excel e Numbers eseguono
 * le celle che iniziano con = + - @, quindi vengono neutralizzate.
 */
function cell(value) {
  const text = value == null ? "" : String(value);
  const safe = /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
  return `"${safe.replace(/"/g, '""')}"`;
}

export default async function handler(req, res) {
  apiHeaders(res);

  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ ok: false, error: "method_not_allowed" });
  }
  if (!isAuthenticated(req)) {
    return res.status(401).json({ ok: false, error: "unauthorized" });
  }

  try {
    await ensureSchema();

    const rows = await sql`
      SELECT email, source, landing, created_at
      FROM subscribers
      ORDER BY created_at ASC
    `;

    const csv = [
      ["email", "canale", "landing", "iscritto_il"].join(","),
      ...rows.map((r) =>
        [
          cell(r.email),
          cell(r.source),
          cell(r.landing),
          cell(new Date(r.created_at).toISOString()),
        ].join(",")
      ),
    ].join("\r\n");

    const stamp = new Date().toISOString().slice(0, 10);
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="flashapp-iscritti-${stamp}.csv"`
    );
    // BOM: così Excel apre gli accenti senza sfasare la codifica.
    return res.status(200).send("\uFEFF" + csv);
  } catch (err) {
    console.error("export failed:", err?.message ?? err);
    return res.status(500).json({ ok: false, error: "server_error" });
  }
}
