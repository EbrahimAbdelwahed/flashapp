# Decision Request: account-switch-data-boundary

Status: Resolved
Run ID: `flash-app-store-v1`
Bead: sas-03-private-sync
Agent: root
Created: 2026-08-19 21:04

## Severity

blocking

## Decision Type

safety

## Question

Quale confine dati deve applicare FlashApp quando il dispositivo passa dall’Apple Account A all’account B?

## Context

ADR-006 definisce un solo Private.sqlite e tratta no-account/offline come disponibilità, ma non distingue ritorno dello stesso account da cambio account. NSPersistentCloudKitContainer può iniziare il mirroring autonomamente; il solo CKAccountChanged non prova che i dati locali di A non vengano esportati a B. La security review blocca SAS-03 e i gate reali restano HUMAN_REQUIRED.

## Options

1. `per-account-stores`: Isolamento per account
   - Consequence: Preflight dell’identità CloudKit, store distinti per account e merge esplicito dei dati anonimi; richiede emendamento all’unico Private.sqlite e più lavoro.

2. `bound-store`: Store vincolato al primo account
   - Consequence: Conserva un solo store ma blocca mirroring/accesso al cambio identità finché l’utente esporta e cancella o torna all’account originale; richiede bootstrap identity-safe e gestione della race.

3. `same-account-only`: Supporto dichiarato solo same-account
   - Consequence: Mantiene architettura corrente ma non risolve tecnicamente il rischio di A→B; submission resta bloccata finché il comportamento non è provato e accettato.

## Recommendation

Recommended option: `per-account-stores`

Reason:

È l’unica opzione che offre un confine forte tra contenuti di account diversi senza affidarsi a una race con il mirroring automatico. Richiede però un emendamento esplicito ad ADR-006/brief/spec e rislicing di SAS-03.

## Default If Unanswered

keep-blocked

## Links

- `docs/tasks/flash-app-store-v1/sas-03-private-sync.md`

## Resolution

Answered by: owner
Answered at: 2026-08-20 11:04
Decision: per-account-stores
Follow-up beads:
