# Few-shot examples

These examples reproduce the useful shape of the audited exogenous corpus—explicit fronts, bounded subcues, labeled morphology, and selective atomic follow-ups—while removing unverified images, factual noise, and overload. The source excerpts and locators are illustrative; replace them with evidence from the user's actual source.

Choose the example by retrieval job, not by superficial wording:

- heterogeneous dimensions of one object → labeled macro reconstruction;
- homogeneous canonical members → closed enumeration with an optional source-supported count;
- origin/insertion/action/innervation → bounded muscle profile;
- fragile distinction or clinical consequence → atomic Basic card;
- compact linked relation or sequence → contextual Cloze.

## Example 1: bounded morphological reconstruction

```json
{
  "front": "Quali sono i componenti di una vertebra tipica? [corpo - arco - processi - forame - fori]",
  "back": "<b>Corpo</b>: porzione anteriore portante.<br><b>Arco vertebrale</b>: peduncoli e lamine, disposto posteriormente al corpo.<br><b>Processi</b>: uno spinoso, due trasversi e quattro articolari.<br><b>Forame vertebrale</b>: compreso tra corpo e arco; la successione dei forami forma il canale vertebrale.<br><b>Fori intervertebrali</b>: derivano dall'accostamento delle incisure dei peduncoli adiacenti.",
  "tags": ["anatomia::locomotore::colonna_vertebrale"],
  "note_type": "basic",
  "role": "macro_reconstruction",
  "family": "topology",
  "cognitive_function": "reconstruct",
  "back_lines": ["<b>Corpo</b>: porzione anteriore portante.", "<b>Arco vertebrale</b>: peduncoli e lamine, disposto posteriormente al corpo.", "<b>Processi</b>: uno spinoso, due trasversi e quattro articolari.", "<b>Forame vertebrale</b>: compreso tra corpo e arco; la successione dei forami forma il canale vertebrale.", "<b>Fori intervertebrali</b>: derivano dall'accostamento delle incisure dei peduncoli adiacenti."],
  "checklist": ["corpo", "arco", "processi", "forame", "fori"],
  "source_refs": ["manuale-anatomia#vertebra-tipica"],
  "evidence": [{"source_ref": "manuale-anatomia#vertebra-tipica", "text": "La vertebra tipica presenta corpo, arco, sette processi e un forame vertebrale; le incisure delimitano i fori intervertebrali."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "Una vertebra tipica comprende corpo, arco, sette processi e un forame vertebrale.", "source_refs": ["manuale-anatomia#vertebra-tipica"]}, {"claim": "Le incisure dei peduncoli adiacenti delimitano i fori intervertebrali.", "source_refs": ["manuale-anatomia#vertebra-tipica"]}],
  "rationale": "Una sola ricostruzione conserva la gerarchia spaziale dei componenti senza frammentarli in etichette isolate.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

## Example 2: discriminazione atomica che merita una card

```json
{
  "front": "Quali sono i due rami terminali della carotide esterna?",
  "back": "L'arteria <b>mascellare</b> e l'arteria <b>temporale superficiale</b>.",
  "tags": ["anatomia::collo::carotide_esterna"],
  "note_type": "basic",
  "role": "atomic_discrimination",
  "family": "classification",
  "cognitive_function": "classify",
  "back_lines": ["L'arteria <b>mascellare</b> e l'arteria <b>temporale superficiale</b>."],
  "checklist": [],
  "source_refs": ["manuale-anatomia#carotide-esterna"],
  "evidence": [{"source_ref": "manuale-anatomia#carotide-esterna", "text": "La carotide esterna termina dividendosi nelle arterie mascellare e temporale superficiale."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "I rami terminali sono l'arteria mascellare e l'arteria temporale superficiale.", "source_refs": ["manuale-anatomia#carotide-esterna"]}],
  "rationale": "Il punto di biforcazione è una coppia ad alta utilità di richiamo e non richiede una risposta omnibus.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

## Example 3: Cloze selettivo per una relazione spaziale

```json
{
  "front": "Il forame vertebrale è delimitato anteriormente dal {{c1::corpo vertebrale}} e posteriormente dall'{{c1::arco vertebrale}}.",
  "back": "Relazione spaziale della vertebra tipica.",
  "tags": ["anatomia::locomotore::colonna_vertebrale"],
  "note_type": "cloze",
  "role": "atomic_discrimination",
  "family": "contextual_cloze",
  "cognitive_function": "complete_relation",
  "back_lines": ["Relazione spaziale della vertebra tipica."],
  "checklist": [],
  "source_refs": ["manuale-anatomia#vertebra-tipica"],
  "evidence": [{"source_ref": "manuale-anatomia#vertebra-tipica", "text": "Il forame vertebrale è compreso tra il corpo e l'arco della vertebra."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "Il corpo è anteriore e l'arco è posteriore al forame vertebrale.", "source_refs": ["manuale-anatomia#vertebra-tipica"]}],
  "rationale": "La frase conserva il rapporto antero-posteriore e testa una singola configurazione spaziale.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

The repeated `c1` index means that the two boundaries are deliberately recalled as one spatial unit. If the source also supplied a linked but complementary fact, such as the structure's extent, that fact could use `c2`.

## Example 4: profilo muscolare coerente

```json
{
  "front": "Qual è il profilo del muscolo esempio? [origine - inserzione - azione - innervazione]",
  "back": "<b>Origine</b>: punto di origine riportato dalla fonte.<br><b>Inserzione</b>: punto di inserzione riportato dalla fonte.<br><b>Azione</b>: movimento o funzione descritta dalla fonte.<br><b>Innervazione</b>: nervo e radici soltanto se presenti nella fonte.",
  "tags": ["anatomia::regione::muscolo_esempio"],
  "note_type": "basic",
  "role": "macro_reconstruction",
  "family": "muscle_profile",
  "cognitive_function": "recall_profile",
  "back_lines": ["<b>Origine</b>: punto di origine riportato dalla fonte.", "<b>Inserzione</b>: punto di inserzione riportato dalla fonte.", "<b>Azione</b>: movimento o funzione descritta dalla fonte.", "<b>Innervazione</b>: nervo e radici soltanto se presenti nella fonte."],
  "checklist": ["origine", "inserzione", "azione", "innervazione"],
  "source_refs": ["fonte-anatomia#muscolo-esempio"],
  "evidence": [{"source_ref": "fonte-anatomia#muscolo-esempio", "text": "Estratto che documenta origine, inserzione, azione e innervazione."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "Il profilo comprende i quattro campi documentati dalla fonte.", "source_refs": ["fonte-anatomia#muscolo-esempio"]}],
  "rationale": "I quattro campi formano un unico profilo anatomico convenzionale e vengono richiamati insieme.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

Do not use the higher density allowance to append unrelated clinical facts. A fifth field is allowed only when it belongs naturally to the profile and is present in the source.

## Example 5: enumerazione chiusa con cardinalità

```json
{
  "front": "Quali sono le quattro parti canoniche della struttura esempio (4)?",
  "back": "1) Prima parte descritta dalla fonte.<br>2) Seconda parte descritta dalla fonte.<br>3) Terza parte descritta dalla fonte.<br>4) Quarta parte descritta dalla fonte.",
  "tags": ["anatomia::regione::struttura_esempio"],
  "note_type": "basic",
  "role": "macro_reconstruction",
  "family": "classification",
  "cognitive_function": "classify",
  "back_lines": ["1) Prima parte descritta dalla fonte.", "2) Seconda parte descritta dalla fonte.", "3) Terza parte descritta dalla fonte.", "4) Quarta parte descritta dalla fonte."],
  "checklist": [],
  "source_refs": ["fonte-anatomia#elenco-canonico"],
  "evidence": [{"source_ref": "fonte-anatomia#elenco-canonico", "text": "La fonte presenta esplicitamente quattro parti canoniche."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "La struttura è suddivisa nelle quattro parti elencate.", "source_refs": ["fonte-anatomia#elenco-canonico"]}],
  "rationale": "Il numero anticipa la completezza richiesta senza suggerire l'identità dei membri.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

Use `(N)` only when the source defines a stable closed set, and place it immediately before the final question mark. Do not invent a count for an open-ended list.

## Example 6: sequenza con frecce

```json
{
  "front": "Come procede il percorso esempio dalla struttura A alla struttura D?",
  "back": "<b>Decorso</b>: struttura A → struttura B → struttura C → struttura D.",
  "tags": ["anatomia::regione::percorso_esempio"],
  "note_type": "basic",
  "role": "macro_reconstruction",
  "family": "process",
  "cognitive_function": "sequence",
  "back_lines": ["<b>Decorso</b>: struttura A → struttura B → struttura C → struttura D."],
  "checklist": [],
  "source_refs": ["fonte-anatomia#percorso"],
  "evidence": [{"source_ref": "fonte-anatomia#percorso", "text": "La fonte descrive in ordine il passaggio da A a B, C e D."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "Il percorso segue l'ordine A, B, C, D.", "source_refs": ["fonte-anatomia#percorso"]}],
  "rationale": "La notazione a frecce conserva l'ordine spaziale senza trasformarlo in prosa.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

## Example 7: secondo strato atomico

```json
{
  "front": "Quale rapporto distingue la struttura A dalla struttura B nel punto indicato?",
  "back": "La struttura A è <b>anteriore</b> alla struttura B nel punto indicato.",
  "tags": ["anatomia::regione::rapporto_esempio"],
  "note_type": "basic",
  "role": "atomic_discrimination",
  "family": "comparison",
  "cognitive_function": "compare",
  "back_lines": ["La struttura A è <b>anteriore</b> alla struttura B nel punto indicato."],
  "checklist": [],
  "source_refs": ["fonte-anatomia#rapporto-fragile"],
  "evidence": [{"source_ref": "fonte-anatomia#rapporto-fragile", "text": "Nel punto indicato A decorre anteriormente a B."}],
  "image_refs": [],
  "grounded_claims": [{"claim": "Nel punto indicato A è anteriore a B.", "source_refs": ["fonte-anatomia#rapporto-fragile"]}],
  "rationale": "La direzione è facilmente confondibile e merita una prova separata dalla mappa generale.",
  "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
  "provenance": {"generated_by": "codex", "provider": null, "model": null, "prompt_version": "generate-morphology-first-anatomy-cards@1"}
}
```

Do not copy every pattern into every cluster. Often one schema card is sufficient; add a profile, Cloze, sequence, or atomic follow-up only when the source and retrieval value justify that specific job.
