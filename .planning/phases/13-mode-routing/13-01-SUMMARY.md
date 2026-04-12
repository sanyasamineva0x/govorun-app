---
phase: 13-mode-routing
plan: 01
subsystem: core-pipeline
tags: [product-mode, cloud, pipeline, tdd]
dependency_graph:
  requires: []
  provides: [ProductMode.cloud, CloudAudioProcessing, PipelineEngine.processCloudPath]
  affects: [Govorun/Models/ProductMode.swift, Govorun/Core/PipelineEngine.swift, Govorun/Services/CloudLLMClient.swift]
tech_stack:
  added: [CloudAudioProcessing protocol]
  patterns: [protocol-based-mocking, 5-tuple-snapshot, cloud-fork-before-stt]
key_files:
  created:
    - GovorunTests/ProductModeTests.swift
  modified:
    - Govorun/Models/ProductMode.swift
    - Govorun/Core/PipelineEngine.swift
    - Govorun/Services/CloudLLMClient.swift
    - GovorunTests/PipelineEngineTests.swift
decisions:
  - CloudAudioProcessing протокол вместо конкретного типа CloudLLMClient для тестируемости
metrics:
  duration: 7m
  completed: "2026-04-12T18:11:27Z"
  tasks: 2
  files: 5
  tests_added: 24
  tests_total: 1229
---

# Phase 13 Plan 01: ProductMode.cloud + PipelineEngine Cloud Fork Summary

CloudAudioProcessing протокол + ProductMode.cloud enum case + PipelineEngine cloud fork, маршрутизирующий аудио напрямую в облачный API минуя STT

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | ProductMode.cloud enum case с usesLocalLLM, isCloud | 99cf728 | ProductMode.swift, ProductModeTests.swift |
| 2 | PipelineEngine cloud fork с _cloudClient, updateCloudClient, processCloudPath | 64767ad | PipelineEngine.swift, PipelineEngineTests.swift, CloudLLMClient.swift |

## Key Changes

### ProductMode.swift
- `case cloud` с rawValue "cloud"
- `usesLLM` возвращает true для .superMode и .cloud
- `usesLocalLLM` возвращает true только для .superMode
- `isCloud` возвращает true только для .cloud
- title "Говорун Cloud", subtitle "Голосовой ввод через GigaChat Max"

### PipelineEngine.swift
- `CloudAudioProcessing` протокол (Sendable) с `processAudio(audioData:superStyle:hints:)`
- `_cloudClient: CloudAudioProcessing?` stored property под NSLock
- `updateCloudClient(_:)` для инжекции cloud клиента
- `snapshotConfig()` расширен до 5-tuple с CloudAudioProcessing?
- Cloud fork в `stopRecording()`: если `productMode.isCloud`, вызывает `processCloudPath`
- `processCloudPath`: stops recording, guards empty audio, calls cloudClient.processAudio, applies post-processing (terminal period, applyDeterministic, ListFormatter)
- `NormalizationPath.cloud` и `.cloudFailed`
- Standard и Super пути без изменений

### CloudLLMClient.swift
- `extension CloudLLMClient: CloudAudioProcessing {}` (метод processAudio уже существовал)

## Test Results

- 14 тестов ProductModeTests (rawValue, usesLLM, usesLocalLLM, isCloud, title, subtitle, codable, caseIterable)
- 10 тестов PipelineEngineTests для cloud mode (skips STT, calls processAudio, empty audio, post-processing, failure, cancellation, super/standard unchanged, rawTranscript, nil client)
- Полный прогон: 1229 тестов, 0 failures

## Decisions Made

- **CloudAudioProcessing протокол**: CloudLLMClient final class, нельзя подклассировать для моков. Создан легковесный протокол CloudAudioProcessing для тестируемости. CloudLLMClient конформит автоматически (метод processAudio уже имеет нужную сигнатуру). PipelineEngine хранит `_cloudClient: CloudAudioProcessing?`.

## Deviations from Plan

None -- план выполнен точно как написано.

## Threat Mitigations Applied

- T-13-02 (DoS): processCloudPath проверяет cancellation до и после вызова processAudio
- T-13-04 (EoP): PipelineEngine доверяет productMode от вызывающего кода, gatekeeper в AppState (Plan 02)

## Self-Check: PASSED

- All 6 files found on disk
- Both commits (99cf728, 64767ad) present in git log
- All acceptance criteria patterns found in source files
- Full test suite: 1229 tests, 0 failures
