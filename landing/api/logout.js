import { sessionCookie, apiHeaders } from "../lib/auth.js";

export default function handler(req, res) {
  apiHeaders(res);

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ ok: false, error: "method_not_allowed" });
  }

  res.setHeader("Set-Cookie", sessionCookie("", 0));
  return res.status(200).json({ ok: true });
}
