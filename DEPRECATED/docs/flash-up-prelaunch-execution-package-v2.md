# Flash Up — Pacchetto Pre-Launch Esecutivo (v2)

Eseguibile da una persona sola. Un giorno di full immersion + 1 ora al giorno.
Fonte di verità: il marketing brief esistente, con UN vincolo aggiornato (§0.1).
Nessuna feature inventata, nessun claim che l'app sia già scaricabile.

---

## 0.1 Vincolo aggiornato: la regola della provocazione

Il brief originale diceva "non attaccare Anki". Versione aggiornata:

- **Anki si attacca SOLO sulla complessità.** Interfaccia datata, curva di
  apprendimento, setup del sync, add-on necessari per funzioni base. È vero,
  è verificabile, e i power user che lo difenderanno nei commenti generano
  engagement nei NOSTRI commenti.
- **Anki NON si attacca MAI sul prezzo.** AnkiMobile è ~35€ una tantum;
  desktop e AnkiDroid sono gratis. Qualsiasi claim tipo "Anki costa 30€
  all'anno" è falso, viene smentito nel primo commento e brucia credibilità
  con il target esatto (studytok conosce Anki meglio di noi).
- **Flashka e gli abbonamenti mensili si attaccano su tutto:** prezzo
  ricorrente, paywall sull'import, complessità. Lì il contrasto
  "€1.99 una volta" è pulito e inattaccabile.
- Ogni video provocatorio deve chiudere con una **dimostrazione reale**
  entro 5 secondi dalla provocazione. Provocazione senza demo = view senza
  sign-up.

---

## 0.2 Piano del giorno di full immersion (8-9 ore)

**Prima della giornata (stasera, ~30 min di prompt):**
delega a Claude/Sonnet il blocco automatizzabile (§6): landing page deployata,
form Tally configurato, foglio di tracking, varianti caption. Così la mattina
parti con l'infrastruttura già in bozza da revisionare, non da creare.

**Mattina — infrastruttura e riprese (3h)**

| Ora | Attività |
|---|---|
| 0:00–0:30 | Revisiona e pubblica la landing generata (§1). Verifica che il hidden field `ref` arrivi nelle risposte Tally con un submit di prova. |
| 0:30–1:00 | Crea account TikTok e Instagram dedicati (nome coerente, bio con link alla landing). |
| 1:00–1:45 | Demo state deterministico: deck "Biochimica" con 40-60 card vere generate da ChatGPT (doppio uso: props per i video + tuo primo deck di ripasso reale). Build di sviluppo sul tuo iPhone via free provisioning. |
| 1:45–3:00 | Registra i clip sorgente (§2.5). Una volta, puliti: si riusano in tutti i video. Include i 2 clip extra per i video-provocazione. |

**Pomeriggio — produzione (4h)**

| Ora | Attività |
|---|---|
| 3:00–3:30 | 3 progetti-template in CapCut, uno per famiglia (§2). Voiceover: TTS integrato di CapCut, niente registrazioni vocali. |
| 3:30–6:30 | Monta i 12 video (§3), ~15 min l'uno coi template. Priorità: hook e demo. Il resto non deve essere perfetto. |
| 6:30–7:00 | Export 9:16, 1080×1920. Nomina i file con l'ID del brief (P1, F1, O1...). |

**Sera — programmazione (1-1.5h)**

| Ora | Attività |
|---|---|
| 7:00–7:45 | Programma i primi 7-10 giorni: TikTok web scheduler (max 10 giorni avanti) + Meta Business Suite per i Reels (fino a 29 giorni). Calendario §4. |
| 7:45–8:00 | Verifica il foglio di tracking (§5) e archivia i clip sorgente in una cartella ordinata: serviranno alla pipeline di fase 2 (§6.3). |

**Routine da 1 ora nei giorni successivi**
- 10 min: verifica pubblicazione del giorno; ricarica lo scheduler TikTok
  quando la finestra dei 10 giorni si esaurisce.
- 20 min: rispondi a TUTTI i commenti. Sui video-provocazione i commenti
  ostili sono il piano, non un incidente: rispondi con la demo
  ("nel video l'import dura 30 secondi, cronometrato"), mai con la difesa.
- 15 min: aggiorna il tracking (view, visite, sign-up per ref).
- 15 min: leggi i pattern. Dal giorno 6, raddoppia sulla famiglia che converte.

---

## 1. Landing page

### Narrativa (una schermata, sopra la piega)

**Headline:** Le tue flashcard da ChatGPT alla revisione in 30 secondi.

**Sottotitolo:** Generi le card con ChatGPT, le esporti in CSV, le importi
nell'app e inizi a studiare. Ripetizione spaziata e sincronizzazione incluse.
Nessun abbonamento: €1.99 una volta, al lancio su App Store.

**CTA (bottone):** Entra in lista d'attesa → ricevi il link App Store al lancio

**Sotto il form, tre righe di rinforzo:**
- Import diretto da CSV: le card che hai già, subito pronte da studiare.
- Revisione illimitata inclusa nel prezzo. Nessun costo mensile.
- Per iPhone e iPad. Zero setup: nessun manuale, nessun add-on.

**Domande nel form (oltre all'email):**
1. "€1.99 una tantum al lancio ti sembra un prezzo giusto?" [Sì / No / Dipende]
2. "Su cosa studierai?" [iPhone / iPad / Entrambi]
La prima misura il comfort sul prezzo, la seconda qualifica il sign-up
(utente Apple reale) come richiesto dal piano di validazione.

**Campo hidden nel form:** `ref` (precompilato dall'URL, vedi §5).

### Cosa NON mettere
- Niente "scarica ora", niente badge App Store cliccabile.
- Niente confronto nominale con Anki sulla landing: la provocazione vive nei
  video, la landing chiude la vendita e deve essere pulita.
- Niente screenshot sintetici: solo frame reali dell'app.

---

## 2. Tre formati video riutilizzabili

Tutti: 9:16, 20-35 secondi, testo overlay grande leggibile senza audio,
CTA finale identica: **"Link in bio → lista d'attesa, ti mando il link App
Store al lancio."**

### Formato P — "Provocazione + demo" (famiglia: subscription problem / complessità)
Struttura: hook provocatorio (contro la subscription fatigue O contro la
complessità di Anki, mai contro il suo prezzo) → 3-5s che concretizzano la
provocazione (mockup di paywall generici, oppure la schermata-labirinto) →
taglio secco sulla demo reale dell'app che risolve esattamente quel punto →
overlay di contrasto → CTA.
Durata: 20-30s. Il prezzo €1.99 si dice sempre quando l'attacco è agli
abbonamenti; si omette quando l'attacco è alla complessità (lì il contrasto
è il tempo, non il denaro).
Regola d'oro: massimo 5 secondi tra provocazione e demo.

### Formato F — "Dal prompt allo studio" (famiglia: import friction)
Struttura: screen recording del prompt ChatGPT che genera card → export CSV →
import nell'app → prima card che appare → sessione di revisione. Tutto reale,
velocizzato 2-4x con timer overlay ("30 secondi dopo…"). Prezzo solo se il
hook lo richiede.
Durata: 25-35s. È il formato-dimostrazione: il prodotto È il video.

### Formato O — "Studia e basta" (famiglia: study outcome)
Struttura: hook sul risultato ("il metodo che uso per non ripassare mai due
volte la stessa cosa inutilmente") → clip della revisione con spaced
repetition visibile → sync iPhone/iPad in clip affiancate → overlay sul
beneficio → CTA. Tono calmo, study-with-me adiacente.
Durata: 25-30s.

### 2.5 Clip sorgente da registrare (una sola volta)

1. ChatGPT (app o web) che genera 20 card di biochimica dal prompt.
2. Export/salvataggio del CSV.
3. Import del CSV nell'app: selezione file → anteprima → conferma.
4. Prima card mostrata, flip fronte/retro.
5. Sessione di revisione: 5-6 card giudicate, con indicatore di intervallo.
6. Schermata deck con contatore card.
7. Stessa card su iPhone e iPad (due riprese per il sync visivo).
8. B-roll: mano che tiene il telefono sul tavolo con appunti veri di biochimica.
9. **[nuovo]** Screen recording di Anki desktop appena installato: la finestra
   di setup/preferenze/sync navigata senza tagli per 10-15 secondi (materiale
   per i video-complessità; è la sua interfaccia reale, nessuna distorsione).
10. **[nuovo]** Cronometro a schermo (app orologio) da usare in split con i
    confronti di setup.

---

## 3. Dodici brief video

Convenzioni: [clip N] si riferisce a §2.5. Ogni caption termina con
"🔗 in bio per la lista d'attesa". Hashtag base:
`#studytok #flashcards #universita #medicina #studygram #metodostudio`
(2-3 tag per video, non di più).

---

### Famiglia P — Provocazione

**P1 — "Il conto degli abbonamenti"**
- Hook (0-2s, overlay): "Quanto ti costa studiare ogni mese?"
- Provocazione: mockup testuali di paywall che si accumulano: "9,99€/mese",
  "7,99€/mese", "4,99€/mese" → totale annuo a schermo. (Mockup generici,
  nessun logo altrui.)
- Demo: [clip 5] revisione fluida.
- Overlay finale: "Flashcard illimitate. €1.99. Una volta."
- Voiceover (TTS): "Ogni app di studio vuole un abbonamento. Questa no."
- CTA: standard.
- Caption TikTok: "gli abbonamenti per studiare sono una tassa sulla memoria 💸 €1.99 una volta e basta."
- Caption IG: "Studiare non dovrebbe costare un canone mensile. €1.99, una volta, flashcard illimitate. Al lancio su App Store."

**P2 — "Il tutorial da 40 minuti"**
- Hook: "Anki è potentissimo. Peccato che serva un tutorial di 40 minuti per iniziare."
- Provocazione: [clip 9] navigazione reale tra le preferenze/setup di Anki
  desktop, 4-5s, con overlay "giorno 1 su Anki".
- Demo: [clip 3]→[4] import e prima card, con overlay "giorno 1 da noi".
- Overlay finale: "Stesso metodo di studio. Zero manuale."
- CTA: standard.
- Caption TikTok: "rispetto per i power user di Anki 🫡 ma io volevo solo studiare"
- Caption IG: "La ripetizione spaziata non dovrebbe richiedere un corso. Import e via."
- Nota: MAI menzionare il prezzo di Anki, qui né nei commenti. Se lo
  chiedono: "AnkiMobile costa 35€ una tantum ed è un ottimo software; il
  nostro punto è la semplicità, non il prezzo di Anki."

**P3 — "Setup contro setup, cronometro"**
- Hook: "Setup di Anki vs setup nostro. Cronometro alla mano."
- Provocazione: split-screen: sopra [clip 9] con [clip 10] che corre; sotto
  [clip 3] che finisce in ~30 secondi mentre sopra il timer continua.
- Demo: integrata nello split.
- Overlay finale: "Il tempo di setup è tempo di studio perso."
- CTA: standard.
- Caption TikTok: "il cronometro non ha opinioni ⏱️"
- Caption IG: "Confronto onesto, interfacce reali, nessun montaggio creativo. Solo un cronometro."
- Nota: usare SOLO registrazioni reali di entrambe le interfacce; il vincolo
  "nessuna distorsione" vale anche per il software altrui.

**P4 — "La disdetta"**
- Hook: "Ho disdetto tutti gli abbonamenti di studio tranne zero."
- Provocazione: lista overlay di canoni mensili che si cancella riga per riga.
- Demo: [clip 3] + [clip 5].
- Overlay: "Import da ChatGPT ✓ Revisione illimitata ✓ Abbonamento ✗"
- CTA: standard.
- Caption TikTok: "la parte migliore? nessun rinnovo automatico da ricordarsi di disdire 😌"
- Caption IG: "Nessun rinnovo, nessun paywall sulla revisione base. Un solo pagamento al lancio."

**P5 — "Studente onesto" (founder story)**
- Hook (parlato o TTS su b-roll [clip 8]): "Sono uno studente di medicina e
  ho fatto un'app di flashcard perché ero stufo di pagarle ogni mese."
- Provocazione: subscription fatigue in una frase.
- Demo: [clip 3] veloce.
- Overlay: "Fatta da uno studente. Prezzata da uno studente. €1.99."
- CTA: standard.
- Caption TikTok: "made by a broke med student, for broke students 🩺"
- Caption IG: "L'ho costruita per il mio metodo di studio. €1.99 al lancio, lista d'attesa in bio."
- Nota: spesso il top performer organico; pubblicarlo quando l'account ha
  già 3-4 post di contesto.

---

### Famiglia F — Import

**F1 — "30 secondi"**
- Hook: "Da ChatGPT a flashcard pronte in 30 secondi. Cronometro."
- Flusso: [clip 1]→[2]→[3]→[4] con [clip 10] in overlay.
- Overlay finale: "30 secondi. Davvero."
- CTA: standard.
- Caption TikTok: "il cronometro non mente ⏱️"
- Caption IG: "ChatGPT genera, il CSV viaggia, l'app importa. Tu studi."

**F2 — "Il prompt esatto"**
- Hook: "Il prompt esatto che uso per generare flashcard perfette."
- Problema: "tutti generano card con ChatGPT, pochi sanno dove studiarle."
- Flusso: [clip 1] con prompt leggibile 2-3s → [3] → [5].
- Overlay: il prompt in card grafica salvabile.
- CTA: standard + "salva il video per il prompt".
- Caption TikTok: "salva questo per la prossima sessione di studio 📌"
- Caption IG: "Prompt nel video. Il posto dove studiare le card: in arrivo su App Store, lista in bio."
- Nota: i video "salva questo" hanno reach sproporzionata. Candidato al pin.

**F3 — "Ricopiare è finita"**
- Hook: "Se ricopi ancora le flashcard a mano, guarda qui."
- Problema: b-roll [clip 8] di appunti infiniti, 2s.
- Flusso: [2]→[3]→[4].
- Overlay: "Import CSV → studi subito."
- CTA: standard.
- Caption TikTok: "ore di ricopiatura → 30 secondi di import 🫠"
- Caption IG: "Le card che hai già generato meritano un'app che le importa e basta."

**F4 — "POV sessione"**
- Hook: "POV: domani hai biochimica e hai solo gli appunti."
- Problema: il panico pre-esame in una riga.
- Flusso: [1] (appunti incollati nel prompt) → [3] → [5].
- Overlay: "Appunti → card → revisione. Stasera."
- CTA: standard.
- Caption TikTok: "il glow-up degli appunti la sera prima 📚"
- Caption IG: "Dagli appunti alla prima sessione di ripasso in un'unica serata."

---

### Famiglia O — Outcome

**O1 — "Mai due volte inutilmente"**
- Hook: "Il motivo per cui non ripasso mai due volte la stessa cosa senza motivo."
- Flusso: [clip 5] con intervallo di ripetizione indicato da freccia.
- Overlay: "La ripetizione spaziata decide COSA ripassare. Tu ripassi."
- CTA: standard.
- Caption TikTok: "lascia che sia l'algoritmo a ricordarsi cosa devi ricordare 🧠"
- Caption IG: "Spaced repetition integrata: l'app sceglie le card, tu fai il lavoro che conta."

**O2 — "iPhone in aula, iPad a casa"**
- Hook: "Inizio il ripasso in aula, lo finisco sul divano."
- Flusso: [clip 7] split-screen sulla stessa card.
- Overlay: "Sincronizzazione automatica tra i tuoi dispositivi."
- CTA: standard.
- Caption TikTok: "i tempi morti tra le lezioni finalmente utili 🚇"
- Caption IG: "La sessione ti segue: iPhone in movimento, iPad alla scrivania."

**O3 — "Study with me, versione onesta"**
- Hook: "5 minuti di ripasso vero, nessun trucco." (calmo, quasi ASMR)
- Flusso: [clip 5] esteso a ritmo reale, apertura con [clip 8].
- Overlay: minimale, solo CTA finale.
- CTA: standard.
- Caption TikTok: "il suono di una sessione che si gestisce da sola 🌙"
- Caption IG: "Nessun montaggio frenetico: solo com'è studiare quando l'app non si mette in mezzo."

---

## 4. Calendario di pubblicazione (12 giorni, 1 post/giorno per piattaforma)

Ordine pensato per: aprire con la demo più forte, distribuire i video-
provocazione (mai due di fila: alternare attacco e dimostrazione mantiene
l'account credibile), tenere il founder-video dopo 4 post di contesto.

| Giorno | Video | Tipo | Orario consigliato |
|---|---|---|---|
| 1 | F1 (30 secondi) | Demo | 18:30 |
| 2 | P1 (conto abbonamenti) | Provocazione | 13:00 |
| 3 | O1 (mai due volte) | Outcome | 18:30 |
| 4 | P2 (tutorial 40 minuti) | Provocazione-Anki | 19:00 |
| 5 | P5 (studente onesto) | Founder | 13:00 |
| 6 | F2 (il prompt esatto) | Demo | 18:30 |
| 7 | O2 (iPhone/iPad) | Outcome | 18:30 |
| 8 | P3 (setup vs setup) | Provocazione-Anki | 21:00 |
| 9 | F4 (POV sessione) | Demo | 21:00 |
| 10 | P4 (la disdetta) | Provocazione | 13:00 |
| 11 | F3 (ricopiare è finita) | Demo | 18:30 |
| 12 | O3 (study with me) | Outcome | 21:00 |

- Stesso video lo stesso giorno su TikTok e Reels (caption diverse, nei brief).
- I due video-Anki (P2, P3) sono distanziati (giorni 4 e 8): se il giorno 4
  esplode nei commenti, il giorno 8 raccoglie; se il giorno 4 genera solo
  polemica senza sign-up, il giorno 8 si sostituisce con una variante F.
- Dal giorno 6: se una famiglia domina nei sign-up, i giorni 13+ si riempiono
  SOLO con varianti di quella famiglia (nuovi hook, stessi clip sorgente,
  generate con la pipeline di §6.3 se il volume lo giustifica).
- Orari: 13:00 (pausa pranzo universitaria) e 18:30-21:00 (post-studio) come
  punto di partenza; dopo una settimana comandano gli analytics reali.

---

## 5. Piano di misurazione

### Attribuzione per creative
- La bio punta a un URL con parametro: `landing.tld/?ref=f1`, `?ref=p2`, ecc.
- La bio è una sola → si aggiorna il parametro `ref` il giorno di ogni
  pubblicazione (il post del giorno genera il 90% del traffico nelle prime
  24h). Attribuzione più fine per piattaforma: `?ref=p2-tt` / `?ref=p2-ig`.
- Il form Tally legge `ref` dall'URL in un hidden field → ogni sign-up arriva
  etichettato con creative e piattaforma.

### Foglio di tracking (una riga per video per piattaforma, al giorno)
Colonne: data · video ID · piattaforma · view · like · commenti · salvataggi ·
visite landing · sign-up con quel ref · conversione visita→sign-up ·
risposta prezzo (Sì/No/Dipende) · dispositivo (iPhone/iPad/Entrambi).

### Metrica extra per i video-provocazione
Per P2 e P3 traccia anche il **rapporto commenti/sign-up**: se un video-Anki
fa 300 commenti e 2 sign-up, la provocazione attira il pubblico sbagliato
(difensori di Anki, non acquirenti) → si torna ad attaccare solo gli
abbonamenti. Se fa commenti E sign-up, è il formato da moltiplicare.

### Soglie di decisione
- **Verde (compra l'account Apple da 99€):** ~300 sign-up qualificati
  (studenti con dispositivo Apple, dal campo del form) E conversione
  visita→sign-up > 10% E maggioranza "Sì" sul prezzo.
- **Giallo:** conversione > 10% ma volumi bassi → il messaggio funziona, la
  distribuzione no: più varianti della famiglia migliore, non toccare
  prodotto né prezzo.
- **Rosso:** dopo 12 video, conversione < 5% e "No" prevalente sul prezzo →
  problema di messaggio o offerta: stop produzione, rileggere i commenti
  (ricerca di mercato gratuita), iterare sulla landing prima che sui video.
- Le view NON sono validazione. Un video da 100k view e 3 sign-up ha perso
  contro un video da 2k view e 40 sign-up.

### Cosa NON fare finché non scatta il verde
- Niente ads a pagamento.
- Niente tool a pagamento, avatar, publisher automatici.
- Niente secondo batch "perché sì": il secondo batch si guadagna con i dati.

---

## 6. Piano di automazione con Claude/Sonnet

Divisione onesta del lavoro: cosa delegare subito, cosa resta umano, cosa
si automatizza solo in fase 2.

### 6.1 Delegabile SUBITO, quasi zero babysitting (stasera, prima del full day)
- **Landing page:** un prompt a Claude Code → HTML/CSS statico con il copy di
  §1, deploy su GitHub Pages, form Tally embeddato con hidden field `ref`
  letto dall'URL. Revisione tua: 10 minuti.
- **Varianti testuali:** dare i 12 brief come few-shot e chiedere 30 hook
  alternativi + 30 coppie di caption per famiglia. Costo: un prompt. Uso: i
  giorni 13+ e gli A/B sugli hook.
- **Foglio di tracking:** generato con formule di conversione già pronte
  (Google Sheets o CSV).
- **Bozze di risposta ai commenti ricorrenti:** 10-15 risposte pre-approvate
  ("quando esce?", "e rispetto ad Anki?", "solo iOS?", "quanto costa?") —
  incluse le risposte oneste sul prezzo di Anki (§3, nota P2). Ti dimezzano
  i 20 minuti quotidiani di commenti.

### 6.2 NON delegabile (per definizione o per vincolo del brief)
- **Gli 8+2 clip sorgente (§2.5):** interfaccia reale, telefono tuo, ~45-60
  minuti. Vincolo del brief: nessuna sintesi/distorsione video. Collo di
  bottiglia incomprimibile.
- **La review pre-pubblicazione di ogni video:** unico controllo qualità tra
  un modello e il tuo pubblico. Mai delegarla.
- **Le risposte ai commenti "caldi"** (specie sui video-Anki): il tono lo
  decidi tu; le bozze di §6.1 sono un punto di partenza, non un autopilota.

### 6.3 Automatizzabile in FASE 2 (solo dopo che un formato converte)
- **Pipeline di rendering (Remotion o ffmpeg via Claude Code):** input = clip
  sorgente + JSON del brief (hook, overlay, timing, CTA) → output = video
  9:16 montato. Genera le varianti 13-50 dai tuoi stessi clip cambiando solo
  hook e overlay.
- **Trigger per costruirla:** una famiglia con conversione dimostrata E
  bisogno di più di ~3 varianti/settimana. Prima di allora, CapCut coi
  template è più veloce del debugging di font, timing e safe area.
- **Anche in fase 2 resta umano:** approvazione finale e pubblicazione
  (la tua ora al giorno diventa "approva → programma").

### 6.4 Montaggio batch 1: manuale, ed è la scelta giusta
CapCut con 3 template, TTS integrato per i voiceover, ~15 min a video.
Costruire la pipeline PRIMA di sapere quale formato converte significa
spendere il giorno di full immersion a debuggare invece che pubblicare —
il brief lo vieta esplicitamente (punto 9 della strategia approvata).