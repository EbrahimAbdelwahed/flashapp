import { neon } from "@neondatabase/serverless";

const CONNECTION_STRING =
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  process.env.POSTGRES_URL_NON_POOLING;

if (!CONNECTION_STRING) {
  throw new Error("DATABASE_URL non configurata: collega un Postgres al progetto.");
}

export const sql = neon(CONNECTION_STRING);

/**
 * Lo schema viene creato al primo cold start e poi memoizzato per istanza,
 * così non serve un passaggio di migrazione manuale al primo deploy.
 */
let schemaReady;

export function ensureSchema() {
  if (!schemaReady) {
    schemaReady = (async () => {
      await sql`
        CREATE TABLE IF NOT EXISTS subscribers (
          id          BIGSERIAL PRIMARY KEY,
          email       TEXT        NOT NULL UNIQUE,
          source      TEXT        NOT NULL,
          landing     TEXT,
          created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `;
      await sql`
        CREATE TABLE IF NOT EXISTS rate_events (
          id          BIGSERIAL PRIMARY KEY,
          bucket      TEXT        NOT NULL,
          created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `;
      await sql`
        CREATE INDEX IF NOT EXISTS rate_events_bucket_time
        ON rate_events (bucket, created_at DESC)
      `;
    })().catch((err) => {
      // Non memoizzare un fallimento: il prossimo tentativo deve riprovare.
      schemaReady = undefined;
      throw err;
    });
  }
  return schemaReady;
}

/**
 * Rate limit su finestra scorrevole, tenuto nel database perché le istanze
 * serverless non condividono memoria. Ritorna true se la richiesta passa.
 */
export async function allow(bucket, limit, windowSeconds) {
  const [{ count }] = await sql`
    SELECT COUNT(*)::int AS count
    FROM rate_events
    WHERE bucket = ${bucket}
      AND created_at > now() - make_interval(secs => ${windowSeconds})
  `;
  if (count >= limit) return false;

  await sql`INSERT INTO rate_events (bucket) VALUES (${bucket})`;

  // Pulizia opportunistica: tiene la tabella piccola senza un cron dedicato.
  if (Math.random() < 0.02) {
    await sql`DELETE FROM rate_events WHERE created_at < now() - INTERVAL '1 day'`;
  }
  return true;
}
