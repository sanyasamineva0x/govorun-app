# Говорун

macOS menu bar приложение для голосового ввода на русском языке. Полностью офлайн.
Зажал клавишу → сказал → отпустил → чистый текст в активном поле.

## Стек

- Swift 5.10+, macOS 14.0+ (Sonoma), Apple Silicon (M1+)
- SwiftUI + AppKit (NSStatusItem, NSPanel, NSEvent, AXUIElement)
- Python 3.13 worker (unix socket IPC, embedded Python.framework)
- onnx-asr (GigaAM-v3 e2e_rnnt), Silero VAD
- GigaChat 3.1 10B-A1.8B Q4_K_M (llama-server, Говорун Super)
- Sparkle 2 (автообновление EdDSA), SwiftData
- XCTest (955 тестов)

## Конвенции

- Язык кода: Swift + Python. Комментарии минимальные, на русском
- Коммиты на русском: `feat: добавить X`, `fix: исправить Y`
- **Нет Co-Authored-By** — публичный репо, без признаков AI
- TDD: тест (red) → код (green) → рефактор
- Все сервисы через протоколы (STTClient, LLMClient, SuperAssetsManaging, LLMRuntimeManaging)
- Моки в тестах, никогда реальный Python worker или модели
- Ошибки типизированы: `enum XxxError: Error, LocalizedError { ... }`
- async/await, не completion handlers
- @MainActor только для UI-кода
- Нет force unwrap (!) в production коде
- Zero API credentials — всё локально
- Liquid Glass API за `#if compiler(>=6.2)` + `#available(macOS 26, *)`

## Слои

- Core/ НЕ импортирует SwiftUI или AppKit (чистый Swift)
- Services/ НЕ импортирует AppKit
- Models/ — чистые value types
- worker/ — Python, общается ТОЛЬКО через unix socket

## Сборка

**ВАЖНО: приложение не запускается через ⌘R без подготовки.**

```bash
# Первая сборка
bash scripts/fetch-python-framework.sh  # Python.framework (63 МБ)
bash scripts/download-wheels.sh         # wheels для pip (124 МБ)
xcodegen generate

# Собрать DMG и установить (однострочник)
pkill -f Govorun 2>/dev/null; sleep 1; bash scripts/build-unsigned-dmg.sh 2>&1 | grep '(готов)' && rm -rf /Applications/Govorun.app && hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null && MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}') && cp -R "$MOUNT/Govorun.app" /Applications/ && hdiutil detach "$MOUNT" 2>/dev/null && xattr -cr /Applications/Govorun.app && open /Applications/Govorun.app
```

DMG — единственный надёжный способ тестирования. Accessibility сбрасывается при каждой переустановке.

## Команды

```bash
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation  # Swift тесты
cd worker && python3 -m pytest test_server.py -v  # Python тесты
xcodegen generate  # После изменений project.yml
```

## Git-процесс

- `feat/<name>` или `fix/<name>` → PR → squash merge → delete branch
- Не коммитить в main напрямую
- Одна живая ветка за раз

## Релиз

Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` в `project.yml` → коммит → `git tag v0.X.Y && git push --tags` → CI делает всё (xcodegen → тесты → DMG → Sparkle EdDSA → GitHub Release → appcast.xml → Homebrew Cask).

## Pipeline

```
Activation key → AudioCapture (16kHz) → STT (unix socket → Python worker → GigaAM) →
→ DictionaryStore → SnippetEngine →
→ DeterministicNormalizer (филлеры, числа, бренды, канон) →
→ [Говорун Super?] → LocalLLMClient → NormalizationGate →
→ TextInserter (AX → composition → clipboard)
```

Два режима:
- **Говорун** (standard) — deterministic only, дефолт, всегда работает
- **Говорун Super** — deterministic + LLM, opt-in, требует llama-server + GGUF

## Модели

| Модель | Размер | RAM | Путь |
|--------|--------|-----|------|
| GigaAM-v3 e2e_rnnt (3 ONNX) | ~892 MB | ~1.5 GB | `~/.cache/huggingface/hub/` |
| Silero VAD (ONNX) | ~2 MB | ~50 MB | в bundle |
| GigaChat 3.1 Q4_K_M | ~6 GB | ~7-8 GB | `~/.govorun/models/gigachat-gguf.gguf` |

LLM параметры: temperature=0, max_tokens=128, stop=["\n\n"], llama-server localhost:8080.

## IPC (unix socket)

`~/.govorun/worker.sock`. JSON: `{"wav_path": "..."}` → `{"text": "..."}`. Stateless, 300s timeout.

## Известные особенности

- Python.framework и wheels в .gitignore — скачивать через scripts/
- Accessibility сбрасывается при reinstall (code signature), Sparkle сохраняет
- Flaky тест `test_stop_then_start_relaunches_worker` — race condition, не блокер
