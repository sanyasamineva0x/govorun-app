# Говорун

macOS menu bar приложение для голосового ввода на русском языке. Полностью офлайн.

Зажал **Option (⌥)** → сказал → отпустил → чистый текст в активном поле.

## Возможности

- Полностью офлайн — данные не покидают ваш Mac
- GigaAM-v3 (ONNX) — распознавание речи с пунктуацией
- Silero VAD — нарезка длинных записей на сегменты
- Сниппеты — "мой имейл" → подставляет email
- Словарь замен — "жира" → "Jira"
- Нормализация чисел — "двадцать пять процентов" → "25%"
- Вставка через Accessibility API с clipboard fallback
- Apple Silicon (M1+), macOS 14 Sonoma+

## Установка

### Homebrew (рекомендуется)

```bash
brew tap sanyasamineva0x/govorun
brew install --cask govorun
```

### Сборка из исходников

**Требования:** Xcode 15.4+, macOS 14+, Apple Silicon

```bash
# 1. Клонировать
git clone https://github.com/sanyasamineva0x/govorun-app.git
cd govorun-app

# 2. Скачать Python.framework (63MB, нужен один раз)
bash scripts/download-python-framework.sh

# 3. Сгенерировать Xcode проект
brew install xcodegen
xcodegen generate

# 4. Собрать и запустить
open Govorun.xcodeproj
# ⌘R в Xcode
```

При первом запуске скачивается модель GigaAM-v3 (~900 MB).

## Как пользоваться

1. Запустите Говоруна — иконка появится в menu bar
2. Зажмите **Option (⌥)** на 200мс — начнётся запись
3. Говорите
4. Отпустите **Option** — текст вставится в активное поле
5. **Esc** — отмена

## Архитектура

```
Swift App (menu bar)                    Python Worker
┌──────────────────────┐               ┌──────────────────────┐
│ Option Key Monitor   │               │ onnx-asr             │
│ AudioCapture (16kHz) │──── unix ────▶│ GigaAM-v3 e2e_rnnt   │
│ PipelineEngine       │    socket     │ Silero VAD           │
│ DeterministicNorm    │◀─────────────│                      │
│ NumberNormalizer     │               └──────────────────────┘
│ TextInserter (AX)    │
└──────────────────────┘
```

- **Swift App** — UI, аудио, вставка текста
- **Python Worker** — ASR через unix socket (JSON протокол)
- **IPC**: `{"wav_path": "/tmp/govorun_xxx.wav"}` → `{"text": "распознанный текст"}`

## Модели

| Модель | Размер | RAM | Назначение |
|--------|--------|-----|------------|
| GigaAM-v3 e2e_rnnt | ~892 MB | ~1.5 GB | Распознавание речи |
| Silero VAD | ~2 MB | ~50 MB | Нарезка аудио |

Модели скачиваются автоматически при первом запуске в `~/.cache/huggingface/hub/`.

## Технологии

- Swift 5.10, SwiftUI + AppKit
- AVAudioEngine (микрофон)
- Python 3.13 (embedded framework)
- onnx-asr, ONNX Runtime, Silero VAD
- SwiftData (история, словарь, сниппеты)
- XCTest (680+ тестов)

## Разработка

```bash
# Тесты
xcodebuild test -scheme Govorun -destination 'platform=macOS'

# Python worker (ручной запуск)
cd worker && bash setup.sh && python3 server.py

# Python тесты
cd worker && python3 -m pytest test_server.py -v
```

## Лицензия

[MIT](LICENSE)
