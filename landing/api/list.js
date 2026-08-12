import { sql, ensureSchema } from "../lib/db.js";
import { isAuthenticated, apiHeaders } from "../lib/auth.js";

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
      ORDER BY created_at DESC
      LIMIT 5000
    `;
    const bySource = await sql`
      SELECT source, COUNT(*)::int AS count
      FROM subscribers
      GROUP BY source
      ORDER BY count DESC
    `;

    return res.status(200).json({ ok: true, total: rows.length, bySource, rows });
  } catch (err) {
    console.error("list failed:", err?.message ?? err);
    return res.status(500).json({ ok: false, error: "server_error" });
  }
}
