# Phase 14: Pipeline Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-19
**Phase:** 14-pipeline-hardening
**Areas discussed:** Snippets, NormalizationGate, Offline UX, Dictionary

---

## Area selection

User requested discussion of all 4 grey areas: Snippets, Gate, Offline, Dictionary.

---

## Snippets (embedded handling in Cloud)

| Option | Description | Selected |
|--------|-------------|----------|
| A: Standalone + mechanical fallback | Parity с Standard. `Trigger: content` format inside embedded phrases. 0ms latency. Ugly but predictable. | (initial pick, revisited) |
| B: Только standalone | Embedded ignored. 0ms. Feature regression. | |
| C: Второй cloud roundtrip (audio) | +500-2000ms per embedded. | |
| C-cheap: Текст-only второй roundtrip | +200-500ms per embedded. | |
| D: Placeholder в systemPrompt | One-call, cloud emits `[SNIP_N]`, локальная замена. Risk: prompt engineering. | |
| E: Direct substitution без `trigger:` | Like A but cleaner — word-boundary replace. 0ms. User rejected: «Вот моя sanya@example.com для связи» — грамматика ломается. | |
| **G: Cloud does inline grammatical substitution via systemPrompt** | Snippet dict injected into systemPrompt. One call. Cloud handles grammar. Risk: paraphrase/style conflict. | ✓ |

**User's choice:** Option G (snippet-aware systemPrompt, single call).

**Notes:**
- User explicitly wanted latency-free solution (отверг C и C-cheap ради single-call)
- User отверг E с примером «вот моя sanya@example.com для связи» — грамматически криво
- G принят несмотря на prompt engineering risk — cloud's grammar knowledge > local string manipulation
- Fallback: post-process `SnippetEngine.match` на cloud output + новый `cleanSubstitute` helper (direct word-boundary replace), используется только если cloud не выполнил substitution

---

## NormalizationGate

| Option | Description | Selected |
|--------|-------------|----------|
| **Skip Gate (MVP)** | No reference input for edit distance; cloud temp=0.1 = low hallucination; output-only sanity check deferred | ✓ |
| Tautology input=output | Gate runs as no-op; satisfies MODE-05 formally | |
| Output-only sanity check | New helper CloudOutputSanityCheck; expands scope beyond Phase 14 | |

**User's choice:** Skip Gate for MVP.

**Notes:**
- MODE-05 interpreted as «Gate code not modified», not «Gate must run on cloud output»
- Deferred: если в production появятся проблемы cloud hallucination — добавим output-only check в будущей фазе

---

## Offline degradation UX

| Option | Description | Selected |
|--------|-------------|----------|
| **Graceful fallback: local STT + DeterministicNormalizer** | NetworkMonitor check at processCloudPath entry → route to standard STT flow. Toast «нет сети». Matches Phase 14 criterion #4. | ✓ |
| Error toast + discard audio | Honest but UX-разочаровывающе | |
| Block activation key offline | Preventative; app feels broken | |

**User's choice:** Graceful fallback.

**Notes:**
- Local STT (GigaAM через Python worker) всегда доступен — не зависит от Cloud
- Phase 14 criterion #4 aligns: "fast-fails (NetworkMonitor check) and degrades to deterministic text"

---

## DictionaryStore in Cloud

| Option | Description | Selected |
|--------|-------------|----------|
| **Apply after cloud output, before SnippetEngine** | Cloud normalizes common brands; dict catches personal terms. Idempotent. Parity с другими режимами. | ✓ |
| Skip dictionary in Cloud | Cloud нормализует лучше; personal dict regression | |
| Inject dict в systemPrompt | Premature для MVP; systemPrompt conflict risk | |

**User's choice:** Apply after cloud output, before SnippetEngine.

---

## Claude's Discretion

- Wording snippet-aware systemPrompt extension (defer to plan with tests)
- NetworkMonitor injection strategy (protocol vs closure)
- Toast UI реализация (existing notification pattern)
- `cleanSubstitute` method placement (в SnippetReinserter рядом с mechanicalFallback)

## Deferred Ideas

- Output-only sanity check для cloud output (production feedback triggered)
- NormalizationGate adaptation для Cloud (content-only contract check)
- Snippet-aware prompt как отдельный `CloudSnippetPromptBuilder` компонент
- Offline indicator в menubar UI (Phase 15 scope)
- Quality benchmark cloud vs local для embedded snippets (Phase 16 scope)
