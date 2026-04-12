# Говорун

## What This Is

macOS menu bar приложение для голосового ввода на русском языке. Полностью офлайн STT + опциональная LLM нормализация (локальная и облачная).

## Core Value

Зажал клавишу → сказал → отпустил → чистый текст в активном поле. Три режима: Говорун (базовый), Говорун Super (локальный LLM), Говорун Cloud (GigaChat Max API).

## Current Milestone: v2.0 Говорун Cloud

**Goal:** Третий продукт-режим с GigaChat Max API — cloud dictate с улучшенным качеством нормализации.

**Target features:**
- CloudLLMClient — HTTP клиент к GigaChat API (порт из govorun репо)
- OAuth авторизация через Sber API (SberAuthService)
- API credentials в Keychain (clientId + clientSecret)
- ProductMode.cloud — третий режим рядом с standard и super
- Cloud dictate через GigaChat Max с production промптом
- UI: настройки Cloud режима (ввод ключей, статус подключения)

## Requirements

### Validated

- ✓ Голосовой ввод через GigaAM STT — existing
- ✓ Deterministic normalization pipeline — existing
- ✓ LLM normalization через llama-server (Говорун Super) — existing
- ✓ NormalizationGate с edit distance проверками — existing
- ✓ Menubar UI с настройками — existing
- ✓ Аналитика событий — existing
- ✓ SwiftData история — existing
- ✓ SuperTextStyle (relaxed/normal/formal) — v1.0
- ✓ SuperStyleEngine авто/ручной режим — v1.0
- ✓ NormalizationGate с .normalization и .rewriting контрактами — v1.0
- ✓ ListFormatter (списки в диктовке) — v0.2.3
- ✓ Formal ты→вы через .rewriting contract — v0.2.4

### Active

- ✓ SberRootCA.pem бандлинг + SberTrustPolicy (cert pinning *.sberbank.ru) — Phase 10
- ✓ CredentialStore (Security.framework Keychain) — Phase 10
- ✓ HTTPClient протокол + URLSession conformance — Phase 10
- ✓ SberAuthService actor (OAuth token + caching + coalescing) — Phase 11

### Out of Scope

- Rewrite mode (выделение + голосовая инструкция) — v2 scope
- Generate mode (ключевое слово «говорун, напиши...») — v2 scope
- Автодетект режима по выделению — v2 scope
- SaluteSpeech cloud STT — отдельный проект
- Per-app style overrides — глобальный переключатель

## Context

- Brownfield: govorun-app — macOS 14+, Apple Silicon, Swift 5.10
- Рабочий прототип cloud-клиента в /Users/sanyasamineva/Desktop/govorun (GigaChatClient, SberAuthService, CredentialStore)
- Pipeline: Activation → AudioCapture → STT → Dictionary → Snippets → DeterministicNormalizer → [Super/Cloud?] → LLM → Gate → ListFormatter → TextInserter
- 1139 тестов, TDD подход
- 2M токенов GigaChat Max для тестирования

## Constraints

- **Tech stack**: Swift 5.10+, macOS 14.0+, Apple Silicon only
- **Architecture**: Core/ без SwiftUI/AppKit, Services/ без AppKit, Models/ чистые value types
- **Testing**: TDD, моки через протоколы, без реального API в тестах
- **Conventions**: коммиты на русском, без Co-Authored-By, минимальные комментарии на русском
- **Security**: API credentials только в Keychain, не UserDefaults
- **Offline fallback**: Standard и Super режимы продолжают работать без интернета

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LLMOutputContract.rewriting для formal | Позволяет ты→вы без edit distance rejection | ✓ Shipped v0.2.4 |
| ListFormatter как final pass после style | Не мешает LLM/Gate, работает в обоих режимах | ✓ Shipped v0.2.3 |
| GigaChat Max API (не локальная модель) для Cloud | Лучшее качество, 2M тестовых токенов от Сбера | — v2.0 |
| OAuth под капотом, пользователь вводит clientId+secret | Прозрачно, без прокси-сервера | — v2.0 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-04-12 — Phase 11 complete (OAuth SberAuthService)*
