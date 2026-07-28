---
name: study-rag-architect
description: Design source-grounded retrieval, indexing, citation, PageIndex, and RAG framework integration for the study-agent platform without overcoupling the core domain to any one library.
---

# Study RAG Architect

Use this skill when a feature involves ingestion, indexing, retrieval, PageIndex, source citations, RAG answer generation, or external RAG frameworks such as LlamaIndex.

## Principle

Use mature frameworks where they reduce complexity, but keep the study-agent domain portable.

Framework-specific objects must stay behind adapters. Core packages should depend on interfaces such as:

```ts
interface StudyRetriever {
  search(query: StudyQuery): Promise<RetrievalResult[]>
}
```

## Design Questions

Answer these before implementation:

- What source types are indexed?
- What is the canonical chunk model?
- How are page, section, and source offsets represented?
- Is retrieval keyword, vector, hybrid, or PageIndex-aware?
- How are citations resolved?
- How does the system behave when evidence is insufficient?
- What is framework-owned versus domain-owned?

## Recommended Boundaries

- `core`: study domain types only.
- `retrieval`: interfaces and domain retrieval contracts.
- `adapters/llamaindex`: LlamaIndex-specific implementation.
- `evals`: retrieval and citation fixtures.
- `generation`: answer/card/quiz generation using retrieved evidence.

## Verification

RAG changes should include:

- retrieval fixture tests;
- citation mapping tests;
- insufficient-evidence tests;
- regression examples with expected source IDs;
- prompt evals if generation behavior changes.

## Output

Return an architecture note, adapter boundary, task beads, and verification plan.
