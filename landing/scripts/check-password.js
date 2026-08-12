#!/usr/bin/env node
/**
 * Diagnostica del login senza dover fare un deploy.
 *
 *   npm run check
 *
 * Chiede l'hash **così come l'hai incollato su Vercel** e la password che stai
 * provando a usare, e dice quale dei due è il problema.
 */
import { createInterface } from "node:readline";

// Un solo iteratore sulle righe: con rl.question() a catena lo script si
// pianta quando l'input arriva da una pipe invece che dalla tastiera.
const rl = createInterface({ input: process.stdin, terminal: false });
const lines = rl[Symbol.asyncIterator]();

async function ask(prompt) {
  process.stdout.write(prompt);
  const { value, done } = await lines.next();
  if (done) {
    console.error("\nInput terminato prima della risposta.");
    process.exit(1);
  }
  if (!process.stdin.isTTY) process.stdout.write("\n");
  return value;
}

const hash = (await ask("Incolla il valore di ADMIN_PASSWORD_HASH: ")).trim();
const password = await ask("Password che stai provando: ");
rl.close();

// Le funzioni leggono l'ambiente all'import: va preparato prima.
process.env.ADMIN_PASSWORD_HASH = hash;
process.env.SESSION_SECRET ||= "x".repeat(64); // solo per superare il controllo
const { configError, verifyPassword } = await import("../lib/auth.js");

const problem = configError();
if (problem) {
  console.log(`\n✗ L'hash non è utilizzabile.\n  ${problem}\n`);
  if (hash.includes("$")) {
    console.log(
      "  Contiene dei $: o è il vecchio formato, o la shell lo ha già rovinato.\n" +
        "  Rigeneralo con `npm run hash` e incollalo nel pannello Vercel, non da riga di comando.\n"
    );
  }
  process.exit(1);
}

if (verifyPassword(password)) {
  console.log(
    "\n✓ Hash e password combaciano.\n" +
      "  Se il login continua a fallire il problema è altrove:\n" +
      "  · la variabile non è impostata sull'ambiente giusto (Production vs Preview)\n" +
      "  · il deploy è precedente all'aggiunta delle variabili → rilancia `vercel deploy --prod`\n" +
      "  · SESSION_SECRET manca o è più corta di 32 caratteri\n"
  );
} else {
  console.log(
    "\n✗ L'hash è valido ma la password non corrisponde.\n" +
      "  Rigenerane uno con `npm run hash`.\n"
  );
  process.exit(1);
}
