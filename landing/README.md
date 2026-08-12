# FlashApp — landing di prelancio

Pagina da linkare nella bio e nei video promozionali. Raccoglie **email** +
**canale di provenienza** (Reddit, TikTok, Instagram, passaparola, altro) e
comunica il prezzo: **1,99 €** entro il **18 agosto 2026**, **4,99 €** dopo,
sull'App Store.

Le iscrizioni finiscono in un database Postgres e si leggono da `/admin`, una
dashboard protetta da password con export CSV. **Nessun endpoint pubblico
espone la lista.**

```
landing/
├── index.html              la landing (CSS inline, JS in assets/app.js)
├── admin.html              dashboard privata: login, tabella, download CSV
├── robots.txt
├── vercel.json             header di sicurezza (CSP, HSTS, no-frame…)
├── package.json
├── assets/                 logo, ritagli iPhone, og-image, app.js, admin.js
├── lib/
│   ├── db.js               connessione Postgres, schema, rate limit
│   └── auth.js             password scrypt, sessione firmata, hash IP
├── api/
│   ├── subscribe.js        POST pubblico — l'unico che scrive
│   ├── login.js  logout.js
│   ├── list.js             GET protetto — JSON per la dashboard
│   └── export.js           GET protetto — CSV
└── scripts/hash-password.js
```

---

## Messa in produzione (una volta sola, ~10 minuti)

### 1. Database

Su Vercel → progetto → **Storage** → **Create Database** → **Neon (Postgres)**,
piano gratuito. Vercel inietta da solo `DATABASE_URL` / `POSTGRES_URL`.
Le tabelle si creano da sole alla prima chiamata: nessuna migrazione manuale.

### 2. Password admin e chiave di sessione

```bash
cd landing && npm install && npm run hash
```

Ti chiede una password (min 12 caratteri) e stampa due valori. La password in
chiaro **non viene salvata da nessuna parte**: mettila nel tuo password manager.

Su Vercel → **Settings → Environment Variables**, aggiungi a *Production* e
*Preview*:

| Variabile | Valore |
|---|---|
| `ADMIN_PASSWORD_HASH` | la riga `scrypt:16384:8:1:…` stampata dal comando |
| `SESSION_SECRET` | la riga esadecimale stampata dal comando |

Poi **rifai il deploy**: le variabili nuove non entrano in un deploy già fatto.

> L'hash usa `:` e base64url apposta, così non contiene `$`, `+`, `/` o `=` e
> sopravvive a shell e file `.env` senza bisogno di apici. Gli hash nel vecchio
> formato con `$` continuano comunque a funzionare.

Se `SESSION_SECRET` cambia, tutte le sessioni aperte decadono — è il modo per
buttare fuori tutti se sospetti qualcosa.

### Il login non funziona?

```bash
npm run check
```

Incolli l'hash **come sta su Vercel** e la password che stai provando, e ti dice
qual è dei due il problema. Il pannello `/admin` distingue già i casi da solo:
"Password errata" solo per un 401, mentre un errore di configurazione mostra la
causa esatta.

Le tre cause tipiche:

1. **L'hash è arrivato corrotto.** Se l'hai passato da riga di comando senza
   apici singoli, la shell può averlo mangiato. Reincollalo dal pannello Vercel.
2. **Deploy precedente alle variabili.** Rilancia `vercel deploy --prod`.
3. **Ambiente sbagliato.** La variabile è su Production ma stai usando una URL
   di Preview (o viceversa).

### 3. Deploy

```bash
npx vercel deploy --prod
```

Poi la dashboard è su `https://<dominio>/admin`.

### In locale

```bash
cd landing && npx vercel dev
```

Serve comunque un Postgres raggiungibile: metti `DATABASE_URL`,
`ADMIN_PASSWORD_HASH` e `SESSION_SECRET` in `landing/.env.local`
(già in `.gitignore`).

---

## Come sono protette le email

| Rischio | Difesa |
|---|---|
| Qualcuno scarica la lista | `/api/list` e `/api/export` rispondono **401** senza un cookie di sessione valido. Non esiste nessun'altra via di lettura. |
| Brute force sulla password | Password conservata come **hash scrypt** (N=16384), confronto **timing-safe**, max **8 tentativi ogni 15 minuti** per chiamante. |
| Cookie rubato o falsificato | Sessione **firmata HMAC-SHA256**, cookie `HttpOnly` + `Secure` + `SameSite=Strict`, scadenza 8 ore. Modificare payload o firma invalida il token. |
| XSS che ruba la sessione | CSP con `script-src 'self'`: niente JS inline, niente CDN. La dashboard costruisce la tabella con `textContent`, mai `innerHTML` sui dati. |
| Spam / flood di iscrizioni | Max **5 invii l'ora** per chiamante, canale ristretto a una whitelist di 5 valori, email validata e troncata. |
| Enumerazione degli iscritti | `ON CONFLICT DO NOTHING`: una mail già presente dà la **stessa identica risposta** di una nuova. Il form non rivela chi è iscritto. |
| Formula injection nel CSV | Le celle che iniziano con `= + - @` vengono neutralizzate prima dell'export. |
| Tracciamento degli utenti | L'IP **non viene mai salvato**: per il rate limit se ne conserva solo un HMAC troncato, e le email non finiscono nei log. |
| Indicizzazione della dashboard | `robots.txt` + `X-Robots-Tag: noindex` + `<meta name="robots">`. |

Restano fuori dal codice, in mano tua: la robustezza della password e chi ha
accesso al progetto Vercel. Attiva la 2FA sull'account.

---

## Contenuti

### Date e prezzi

Il countdown legge `DEADLINE` in [assets/app.js](assets/app.js). **I prezzi sono
scritti a mano nel testo**: cerca `1,99` e `4,99` in `index.html` per trovare
tutti i punti (header, hero, form, sezione prezzo, CTA finale).

### Distinguere i video

`landing` salva path + query string, quindi link tipo `.../?v=tiktok-03`
finiscono nel CSV senza toccare il codice.

### Scelte fatte

- **Gruppi è etichettato "In arrivo"**: lo screenshot dell'app dice testualmente
  "I gruppi non sono ancora pronti", quindi non è venduto come disponibile.
- **Nessun confronto numerico con Anki**: il brief lo consente ma solo se
  onesto, e i prezzi non sono verificati. La pagina si limita a "non è un
  abbonamento".
- **Nessun claim su tempi di import** ("dieci secondi" ecc.), come da
  `flash-up-marketing-brief.md` § Claims requiring product verification.

### Rigenerare i ritagli delle schermate

```python
from PIL import Image
BOX = {"oggi":(802,14,1288,932), "libreria":(850,12,1370,936),
       "gruppi":(800,16,1292,936), "impostazioni":(938,34,1400,912)}
for name, box in BOX.items():
    crop = Image.open(f"assets/brand/banner-{name}.png").convert("RGB").crop(box)
    w = int(crop.size[0] * 900 / crop.size[1])
    crop.resize((w, 900), Image.LANCZOS).save(
        f"landing/assets/screen-{name}.webp", "WEBP", quality=88, method=6)
```
