#!/usr/bin/env node
/**
 * Genera ADMIN_PASSWORD_HASH e SESSION_SECRET da mettere tra le variabili
 * d'ambiente. La password in chiaro non viene mai scritta su disco.
 *
 *   npm run hash
 *
 * L'hashing vero sta in lib/auth.js: qui non è duplicato, così i due lati non
 * possono divergere e produrre un hash che il login non sa più leggere.
 */
import { createInterface } from "node:readline";
import { randomBytes } from "node:crypto";
import { hashPassword } from "../lib/auth.js";

const rl = createInterface({ input: process.stdin, output: process.stdout });

rl.question("Password admin (min 12 caratteri): ", (password) => {
  rl.close();

  if (password.length < 12) {
    console.error("\nTroppo corta: usane almeno 12. Riprova.");
    process.exit(1);
  }

  const hash = hashPassword(password);
  const secret = randomBytes(48).toString("hex");

  console.log(`
Incolla queste due variabili su Vercel → Settings → Environment Variables,
selezionando sia Production sia Preview:

ADMIN_PASSWORD_HASH
${hash}

SESSION_SECRET
${secret}

Da riga di comando servono gli apici singoli, altrimenti la shell interpreta
il contenuto prima di passarlo:

  vercel env add ADMIN_PASSWORD_HASH production
  (poi incolla il valore quando lo chiede — non passarlo con echo)

Dopo aver aggiunto le variabili serve un nuovo deploy: quelle esistenti non
vengono ricaricate a caldo.

  vercel deploy --prod

Verifica che l'hash sia arrivato intatto senza aspettare il deploy:

  npm run check

La password in chiaro non è salvata da nessuna parte: mettila nel tuo password
manager adesso.
`);
});
