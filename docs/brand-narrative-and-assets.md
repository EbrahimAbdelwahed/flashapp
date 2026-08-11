# FlashApp — Narrativa e asset di riferimento

Status: consolida in un unico posto (1) le idee dietro alla narrativa di prodotto e
(2) la posizione degli asset visivi/video usati per costruire l'identità e il
materiale di marketing. Sostituisce, per queste due cose, quanto era sparso nei
documenti in `DEPRECATED/`.

## Decisione: CTA rimossa dalla strategia attiva

La riga `"Link in bio → lista d'attesa, ti mando il link App Store al lancio."`
(usata come CTA fissa in `DEPRECATED/marketing-videos-spec.md`,
`DEPRECATED/docs/capcut-video-production-guide.md` e
`DEPRECATED/docs/flash-up-prelaunch-execution-package-v2.md`) **non fa più parte
della strategia di copy attiva**. I documenti in `DEPRECATED/` restano invariati
come archivio storico; qualunque nuovo materiale non deve riusarla.

## Narrativa — idee, non copy

**Questa sezione non è testo pubblicabile.** Sono le idee concettuali dietro al
prodotto, da cui derivare in seguito headline, sottotitoli e script — non
frasi pronte per landing page, video o App Store. Chi scrive il copy finale
parte da qui, rispettando comunque i vincoli di `flash-up-marketing-brief.md`
(vedi nota sui conflitti sotto).

- **Il problema di partenza:** lo studente ha già le card (spesso generate con
  ChatGPT), ma non ha un posto pensato per ripassarle davvero.
- **La soluzione:** revisione offline, su tutti i dispositivi Apple, con
  sincronizzazione — le card seguono lo studente ovunque studi.
- **Il contrasto commerciale:** niente cifra ricorrente paragonabile ai
  concorrenti premium (es. Anki a pagamento), niente setup complicato, niente
  abbonamento.
- **Nessun limite sugli import:** l'utente non deve razionare quante card
  importare (claim verificato, vedi nota sotto).
- **Il flusso in una frase:** crei le card, le importi, studi — ovunque, da
  qualsiasi dispositivo — al resto (sync, backup, ripetizione spaziata) ci
  pensa l'app.
- **Tre aggettivi di marca:** facile, conveniente, rapida.

### Decisioni confermate 2026-08-03

Le due note aperte nella versione precedente di questo documento sono state
risolte dal product owner:

1. **Si attacca Anki, prezzo incluso.** `flash-up-marketing-brief.md` §
   Competitive frame e § Copy principles sono stati aggiornati di conseguenza:
   FlashApp può nominare Anki e contrapporre il proprio prezzo una tantum ai
   suoi piani a pagamento. Resta vietato dire che i power user di Anki hanno
   torto a preferirlo, o rappresentare in modo scorretto cosa Anki costa/offre.
2. **"Nessun limite agli import" è un claim verificato**, non più in attesa di
   conferma prodotto. Aggiunto alle Supporting promises in
   `flash-up-marketing-brief.md` § Value proposition.

## Asset visivi (identità di marca)

Percorso: [`assets/brand/`](../assets/brand/) — 4 banner scaricati e rinominati
in modo descrittivo, tracciati in git (asset di marca finali, non materiale
grezzo).

| File | Schermata | Headline / sottotitolo |
|---|---|---|
| `banner-oggi.png` | Oggi | "Oggi" / "Il tuo piano di studio" |
| `banner-libreria.png` | Libreria | "Libreria" / "Tutti i tuoi mazzi" |
| `banner-gruppi.png` | Gruppi | "Gruppi" / "Studia insieme" |
| `banner-impostazioni.png` | Impostazioni | "Impostazioni" / "Tutto sotto controllo" |

Identità visiva che si può derivare da questi 4 banner:

- **Palette:** sfondo crema/beige caldo, accento terracotta/ruggine, testo
  principale quasi nero, testo secondario grigio-tortora.
- **Logo:** monogramma (le iniziali intrecciate) in terracotta dentro una
  cornice ovale sottile con piccoli punti decorativi.
- **Tipografia:** titolo in serif elegante (stile display/editoriale) per le
  headline; UI dell'app in un sans-serif pulito.
- **Dettaglio ricorrente:** un piccolo tratto/sottolineatura disegnata a mano
  sotto il sottotitolo, in terracotta.
- **Composizione:** headline + sottotitolo a sinistra, mockup iPhone reale
  dell'app a destra, linee sottili decorative sullo sfondo.

## Clip dell'applicazione in uso

Percorso: [`assets/clips/`](../assets/clips/) — 14 registrazioni schermo reali
dell'app (~96MB), consolidate da 14 cartelle singole in un'unica cartella.
**Non tracciate in git** (aggiunte a `.gitignore`): sono materiale grezzo di
partenza, non un deliverable versionato.

| File | Contenuto |
|---|---|
| `01_apertura-app-1.mov` | Apertura app |
| `02_libreriaview-import-creazionemazzo-copiaprompt-1.mov` | Libreria: import, creazione mazzo, copia prompt |
| `03_aperturachatgpt-incollaprompt-selezionefile-1.mov` | ChatGPT: incolla prompt, selezione file |
| `04_generazionecsv-1.mov` | Generazione CSV |
| `05_copiacsv-1.mov` | Copia CSV |
| `06_aperturaflashapp-pastetoimportcsv-importazione-1.mov` | FlashApp: paste-to-import CSV, importazione |
| `07_studiocards-1.mov` | Sessione di studio |
| `08_studiacards-funzcardprecedente-1.mov` | Studio: funzione card precedente |
| `09_terminasessione-oggiview-1.mov` | Fine sessione, vista Oggi |
| `10_statsview-1.mov` | Vista statistiche |
| `11_libreriaview-1.mov` | Vista Libreria |
| `12_cercainlibreriaview-1.mov` | Ricerca in Libreria |
| `13_modificacard-1.mov` | Modifica card |
| `14_impostazioniview-1.mov` | Vista Impostazioni |
