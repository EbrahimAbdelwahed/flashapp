# Morphology-first anatomy card contract

## Pedagogical target

Build retrieval around anatomical objects rather than isolated sentences. Use a two-layer architecture: a bounded schema card first, followed only when useful by precisely graded discriminations. This retains the exogenous corpus's reconstructive strength and the pipeline corpus's strongest atomic behavior.

### Card roles

- `macro_reconstruction`: ask for a coherent schema such as components, surfaces, relations, course, subdivisions, or origin/insertion/action/innervation. The answer should be reconstructable as a compact labeled map, not an essay.
- `atomic_discrimination`: isolate a high-confusion fact, exception, boundary, branch, directional relation, or clinically meaningful distinction. Do not atomize facts that are already easy to retrieve from the macro card. Its `rationale` must name a concrete failure mode such as directional inversion, confusion between a named pair, loss of an exception, or a clinically consequential distinction.

Prefer one macro plus zero to three atomic cards per compact source cluster. A one-card set may be atomic; every set with at least two cards must contain a macro card, and atomic cards must never exceed three times the macro-card count. Set an explicit card budget before generation.

## Style rules

- Ask an explicit question: name the anatomical object and the requested dimensions.
- Prefer the short retrieval-key openings observed repeatedly in the sampled corpus: `Quali`, `Qual è`, `Come`, `Cosa`, and `Dove`. Do not force one opening when another is clearer.
- Add bracketed subcues only to bound a multi-part reconstruction, for example `[corpo - arco - processi - forami]`.
- A source-supported cardinality cue such as `(4)` may be used for a canonical closed enumeration. Place it immediately before the final question mark: `Quali sono le parti (4)?`. It is not a substitute for named bracketed cues when the requested dimensions are heterogeneous.
- Choose one `family`: `atomic_locator`, `definition`, `classification`, `topology`, `comparison`, `process`, `muscle_profile`, or `contextual_cloze`. Record the actual `cognitive_function`: `locate`, `define`, `classify`, `reconstruct`, `compare`, `sequence`, `recall_profile`, or `complete_relation`.
- Avoid vague fronts such as `Parlami di...`, `Descrivi...`, or pronouns without an antecedent. `Descrivi` is acceptable only when followed by an explicit bounded schema and no interrogative form is clearer.
- Use stable parallel labels on macro backs when answer lines represent different dimensions: `<b>Componente</b>: ...<br><b>Rapporti</b>: ...`. For homogeneous members of a closed set, concise ordered lines without invented labels are acceptable.
- Use `<b>` and `<br>` only. No Markdown, CSS, tables, lists, or embedded `<img>` tags.
- Keep the answer semantically dense but visually segmented. Keep Basic fronts around 35–105 visible characters (hard limit 125, except a bounded `muscle_profile`) and backs around 80–360 with at most six semantic lines. A source-defined closed enumeration may use seven short lines; this is the only line-count exception. The hard back limit is 450 visible characters, or 520 for a coherent `muscle_profile`; this narrow exception accommodates origin/insertion/action/innervation profiles rather than arbitrary extra facts. Split an omnibus card when its sections are only loosely connected or exceed a realistic single recall act.
- Keep checklists to five cues. Store them in `checklist` and map them one-to-one, in order, to `back_lines`. A muscle profile uses at most five labeled dimensions, normally origin/insertion/action/innervation plus one source-relevant field.
- Default to `basic`. Allow `cloze` only for compact relations, contrasts, or sequences; a Cloze card must use `atomic_discrimination`. A shared `cN` binds spans intentionally recalled as one semantic unit; use a second index only for a linked complementary unit.
- Preserve source vocabulary when correct. Normalize casing and obvious transcription noise without silently changing meaning.

The direct sample comprised 39 complete exogenous notes and 32 complete pipeline notes across major anatomical regions and varied answer lengths. The exogenous cards favored compact prompts, schema reconstruction, spatial verification images, labeled profiles, cardinality cues, and selective contextual Cloze. Pipeline cards favored short, precisely graded clinical and directional discriminations. Treat these observations as a form contract, not factual authority. Do not copy raw image HTML, inconsistent entities, Markdown-like bullets, or maximum-length omnibus answers. The validator enforces the hard limits and warns outside the target ranges.

## Source and media policy

Every card must cite at least one `source_ref`, and every cited ref must have a matching evidence item. Evidence must be a short source excerpt or faithful locator-bound observation, not a model-authored justification.

Never use model memory to repair a source gap. Omit the claim or surface the gap for review. Existing cards are style exemplars, not medical ground truth.

Keep images outside `front` and `back`. Add `image_refs` only when the exact local Anki media file has been verified and its SHA-256 recorded. Each image reference must include:

- a basename-only `media` value;
- a 64-character lowercase `sha256`;
- `verified: true`;
- a `source_ref` present on the card;
- meaningful `alt` text.

Use at most one verified image per card and render it back-only downstream, after the textual answer. Its pedagogical role is post-recall spatial verification: the card must remain answerable without it. Never embed it in `front` or `back`.

## External text processing

Direct source-grounded authoring does not require a provider. If an external model performs extraction, rewriting, classification, or generation, use DeepSeek through a dedicated service/module, read credentials from environment variables, and record `generated_by: "model"`, `provider: "deepseek"`, the model, and a versioned prompt. Never put credentials in output.

## JSON schema

Emit a single UTF-8 JSON object:

```json
{
  "schema_version": "morphology-first-anatomy-cards@1",
  "cards": [
    {
      "front": "Quali sono ...? [componenti - rapporti]",
      "back": "<b>Componenti</b>: ...<br><b>Rapporti</b>: ...",
      "tags": ["anatomia::regione::argomento"],
      "note_type": "basic",
      "role": "macro_reconstruction",
      "family": "topology",
      "cognitive_function": "reconstruct",
      "back_lines": ["<b>Componenti</b>: ...", "<b>Rapporti</b>: ..."],
      "checklist": ["componenti", "rapporti"],
      "source_refs": ["source-a#p12"],
      "evidence": [
        {"source_ref": "source-a#p12", "text": "Breve estratto o osservazione fedele alla fonte."}
      ],
      "image_refs": [],
      "grounded_claims": [
        {"claim": "La struttura comprende ...", "source_refs": ["source-a#p12"]}
      ],
      "rationale": "Una frase che spiega perché questa unità di recupero è utile.",
      "quality": {"factual_review": "source_checked", "overload": "pass", "image_status": "none"},
      "provenance": {
        "generated_by": "codex",
        "provider": null,
        "model": null,
        "prompt_version": "generate-morphology-first-anatomy-cards@1"
      }
    }
  ],
  "summary": {
    "card_count": 1,
    "macro_count": 1,
    "atomic_count": 0,
    "cloze_count": 0,
    "source_count": 1,
    "card_budget": {"min": 1, "max": 2},
    "coverage": ["morfologia generale"],
    "source_gaps": [],
    "provenance_note": "Generazione diretta e source-grounded; nessun provider esterno."
  }
}
```

Required card keys are exactly those illustrated except that `image_refs` may be omitted when empty. `back` must equal `back_lines` joined by `<br>`. Every `grounded_claims[].source_refs` entry must belong to the card and have evidence. `quality.factual_review` is `source_checked` or `needs_review`; `quality.overload` is `pass`; `quality.image_status` is `none` or `verified` and must match `image_refs`. Additional keys are allowed for downstream lifecycle metadata. Summary counts must match the cards, `source_count` is the number of distinct cited refs, and `card_count` must remain within `card_budget`.

### Cloze syntax

For `note_type: "cloze"`, use family `contextual_cloze`, cognitive function `complete_relation`, two to four balanced deletion spans, no more than two deletion indices, and at most 220 visible characters. Spans sharing an index must form one intended recall unit; a second index must represent a linked complementary unit rather than arbitrary concealment. Keep `back` empty or use it only for a short source-grounded clarification. Do not use Cloze for macro reconstruction. Keep Cloze at roughly 5% or less of a non-trivial set.

## Final review

Before delivery, confirm:

1. Every claim is supported by cited evidence.
2. Macro cards reconstruct coherent objects rather than chapters.
3. Atomic cards encode real discrimination value.
4. Basic cards dominate and the card budget is respected.
5. Backs are scannable Anki-safe HTML.
6. Media, if any, are verified and checksummed.
7. Deterministic validation passes and warnings have been reviewed.
