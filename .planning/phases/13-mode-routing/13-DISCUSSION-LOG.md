# Phase 13: Mode & Routing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 13-mode-routing
**Areas discussed:** Cloud audio routing, usesLLM guard audit, CloudLLMClient lifecycle, Credentials gate

---

## Cloud Audio Routing

| Option | Description | Selected |
|--------|-------------|----------|
| Branch in PipelineEngine | PipelineEngine checks productMode at top of flow. If .cloud — call processAudio, skip STT+LLM. | ✓ |
| Separate CloudPipelineClient | New protocol/class wraps cloud flow. More abstraction. | |
| You decide | Claude picks. | |

**User's choice:** Branch in PipelineEngine
**Notes:** Minimal change, one clear fork point.

---

## usesLLM Guard Audit

| Option | Description | Selected |
|--------|-------------|----------|
| usesLocalLLM | New computed property, true only for .superMode. Guards switch to it. | ✓ |
| isCloud check | Add isCloud, each guard: usesLLM && !isCloud. Scattered. | |
| Claude decides | | |

**User's choice:** usesLocalLLM
**Notes:** User initially asked for clarification ("что?"). After simplified explanation in Russian, chose usesLocalLLM.

---

## CloudLLMClient Lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| Lazy, при переключении | Create at applyProductMode(.cloud). No overhead when unused. | ✓ |
| Eager, в init | Always create, stored property. Simpler but wasteful. | |
| Claude decides | | |

**User's choice:** Lazy creation at mode switch
**Notes:** None.

---

## Credentials Gate (MODE-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Guard в applyProductMode | Code-level check. No credentials → no switch. | |
| Published cloudAvailable | UI can disable Cloud option. Better UX. | |
| Оба: guard + cloudAvailable | Guard as safety net + Published property for UI. Defense in depth. | ✓ |

**User's choice:** Both (option 3)
**Notes:** User initially asked for simpler explanation. After clarification, chose "вариант 3, давай сделаем в UI". User noted that credentials are entered via app UI (Phase 15), not directly in Keychain.

---

## Claude's Discretion

- PipelineEngine fork implementation details
- Naming conventions for cloud-related methods
- Audio-in path protocol design
- ProductMode.cloud title string

## Deferred Ideas

None.
