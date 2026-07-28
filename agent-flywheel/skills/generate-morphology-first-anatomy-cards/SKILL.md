---
name: generate-morphology-first-anatomy-cards
description: Generate or regenerate source-grounded anatomy Anki cards that prioritize morphological reconstruction, spatial organization, relations, components, and discriminating landmarks. Use for anatomy lessons, atlases, lecture notes, transcripts, or card exports when Codex must emulate the useful pedagogical style of a morphology-first deck while correcting factual errors, controlling overload, preserving provenance, and producing validated JSON for Basic cards with selective Cloze use.
---

# Generate Morphology-First Anatomy Cards

Produce a parsimonious two-layer study set: first let the learner reconstruct an anatomical object, then test only the isolated distinctions that remain fragile. Preserve the source's scope and terminology; never fill a source gap from memory.

## Required references

Read [references/style-contract.md](references/style-contract.md) before planning or generating cards. Read [references/few-shot-examples.md](references/few-shot-examples.md) when calibrating format, card roles, or output JSON.

## Workflow

1. Inventory the supplied sources and assign stable `source_ref` values with locators. Stop or mark an explicit source gap when a claim lacks evidence.
2. Cluster the material by anatomical object or region. For each cluster, choose the minimum cards that cover morphology, organization, relations, vascularization/innervation, function, and high-value exceptions actually present in the source.
3. Start with one or more `macro_reconstruction` Basic cards for coherent morphological schemas. Add `atomic_discrimination` cards only for confusable landmarks, directional relations, branch points, exceptions, clinical distinctions, or facts that remain hard to retrieve from the macro card. The rationale must name the concrete confusion or retrieval failure that earns the extra card; “important fact” is not sufficient. Assign a semantic `family` and `cognitive_function` rather than inferring pedagogy from wording alone.
4. Write explicit fronts, normally beginning with `Quali`, `Qual è`, `Come`, `Cosa`, or `Dove`. Use bracketed subcues such as `[componenti - rapporti - continuità]` only when they define a bounded reconstruction path. A source-supported count may cue a canonical closed list without becoming a checklist; place it immediately before the final question mark, as in `Quali sono le parti (4)?`.
5. Write Anki-safe backs using plain text plus `<b>` and `<br>` only. Keep `back_lines` semantic, parallel, and identical to the `<br>`-joined back. Map every bracketed checklist cue to one answer line. Use labeled lines for heterogeneous dimensions and a simple ordered enumeration for homogeneous members of a closed set. Do not place Markdown or image HTML in card fields.
6. Default to `basic`. Use `cloze` only for a compact relation, ordered sequence, or contrast whose surrounding sentence is itself useful context; keep Cloze cards in the atomic role. Reuse a deletion index only for spans intentionally recalled as one semantic unit.
7. Include source evidence, rationale, generation provenance, and only verified image references. If natural-language processing is delegated to an external provider, use DeepSeek through an isolated service and environment-based credentials, then record provider, model, and prompt version.
8. Emit one JSON document using the schema in the style contract. Run `python3 scripts/validate_cards.py OUTPUT.json`; correct every error and review warnings before delivery.

## Non-negotiable gates

- Do not call or mutate live Anki unless the user separately authorizes it.
- Do not copy a corpus claim merely because it appears in an existing card; verify it against the supplied source.
- Do not create unsupported facts, invisible citations, unverified media, or path-traversing media names.
- Do not split every label into its own card. Each atomic card must earn its retrieval cost.
- Do not reproduce overloaded omnibus cards. Split when a learner cannot state the requested schema in one coherent response.
- Do not imitate incidental corpus noise such as raw image tags, Markdown bullets, inconsistent HTML entities, or arbitrary capitalization.
- Keep Basic cards dominant; Cloze is a selective instrument, not the default note type.

## Deliverable

Return the validated JSON plus a short report of source gaps, validator warnings, and the command used. A successful validation establishes structural compliance, not medical correctness; medically review uncertain or high-stakes claims against the cited source.
