# Говорун

macOS menu bar приложение для голосового ввода на русском языке. Полностью офлайн.

Зажал клавишу → сказал → отпустил → чистый текст в активном поле.

## Возможности

- Полностью офлайн — данные не покидают ваш Mac
- GigaAM-v3 (ONNX) — распознавание речи с пунктуацией
- Silero VAD — нарезка длинных записей на сегменты
- Настраиваемая клавиша активации — ⌥, любая клавиша, или комбинация (⌘K, ⇧F5, ...)
- Два режима: Push to Talk (удерживай) и Toggle (нажми — нажми)
- Сниппеты — "мой имейл" → подставляет email
- Словарь замен — "жира" → "Jira"
- Нормализация чисел — "двадцать пять процентов" → "25%"
- Вставка через Accessibility API с clipboard fallback
- Автообновление через Sparkle
- Apple Silicon (M1+), macOS 14 Sonoma+

## Установка

### Homebrew (рекомендуется)

```bash
brew tap sanyasamineva0x/govorun
brew install --cask govorun
```

### Сборка из исходников

**Требования:** Xcode 26+, macOS 14+, Apple Silicon

```bash
# 1. Клонировать
git clone https://github.com/sanyasamineva0x/govorun-app.git
cd govorun-app

# 2. Скачать Python.framework (63 МБ, один раз)
bash scripts/fetch-python-framework.sh

# 3. Скачать wheels для офлайн установки (один раз)
bash scripts/download-wheels.sh

# 4. Сгенерировать Xcode проект
brew install xcodegen
xcodegen generate

# 5. Собрать DMG и запустить
bash scripts/build-unsigned-dmg.sh
```

При первом запуске скачивается модель GigaAM-v3 (~900 МБ).

## Как пользоваться

1. Запустите Говоруна — иконка появится в menu bar
2. Зажмите клавишу активации (по умолчанию **⌥**) на 200мс — начнётся запись
3. Говорите
4. Отпустите клавишу — текст вставится в активное поле
5. **Esc** — отмена

Клавишу и режим работы можно сменить в настройках.

## После переустановки

При переустановке через DMG или Cask macOS сбрасывает разрешение Accessibility. Если текст вставляется через ⌘V вместо прямой вставки:

1. Закройте Говоруна
2. Откройте **Системные настройки → Конфиденциальность и безопасность → Универсальный доступ**
3. Удалите Говоруна из списка (кнопка **−**)
4. Запустите Говоруна
5. Включите тогл для Говоруна в списке

При обновлении через Sparkle (автообновление) это делать **не нужно**.

## Обновление через Homebrew

```bash
brew update
brew upgrade --cask govorun
```

После обновления через Cask macOS сбрасывает разрешение Accessibility (меняется code signature). Повторите шаги из раздела «После переустановки» выше.

При обновлении через Sparkle (автообновление из menu bar) Accessibility **сохраняется** — повторять не нужно.

## Производительность

Замеры на MacBook Air M1, 16 GB RAM:

| Аудио | Длительность | Latency |
|-------|-------------|---------|
| «Привет, сегодня 25 марта, встреча в 5 часов» | 4 сек | **300 мс** |
| Обсуждение бюджета (3 предложения с числами) | 14 сек | **1.3 сек** |
| Отчёт за квартал (выручка, проценты, планы найма) | 26 сек | **1.9 сек** |
| Тишина | — | **2 мс** |

| Метрика | Значение |
|---------|----------|
| **Cold start** | 1.6 сек |
| **WER** | 6.9% (русский) |
| **RAM (worker)** | ~1.2 GB |
| **CPU (idle)** | 0% |
| **DMG** | ~150 MB |
| **Модель** | 892 MB (скачивается один раз) |

## Архитектура

```
Swift App (menu bar)                    Python Worker
┌──────────────────────┐               ┌──────────────────────┐
│ Activation Key Monitor│               │ onnx-asr             │
│ AudioCapture (16kHz) │──── unix ────▶│ GigaAM-v3 e2e_rnnt   │
│ PipelineEngine       │    socket     │ Silero VAD           │
│ DeterministicNorm    │◀─────────────│                      │
│ DictionaryStore      │               └──────────────────────┘
│ SnippetEngine        │
│ NumberNormalizer     │
│ TextInserter (AX)    │
└──────────────────────┘
```

- **Swift App** — UI, аудио, вставка текста
- **Python Worker** — ASR через unix socket (JSON протокол)
- **IPC**: `{"wav_path": "/tmp/govorun_xxx.wav"}` → `{"text": "распознанный текст"}`

## Технологии

- Swift 5.10, SwiftUI + AppKit
- AVAudioEngine (микрофон)
- Python 3.13 (embedded framework)
- onnx-asr, ONNX Runtime, Silero VAD
- Sparkle 2 (автообновление)
- SwiftData (история, словарь, сниппеты)
- XCTest (799 тестов)

## Разработка

```bash
# Тесты
xcodebuild test -scheme Govorun -destination 'platform=macOS'

# Python worker тесты
cd worker && python3 -m pytest test_server.py -v

# Собрать и установить тестовую версию
bash scripts/build-unsigned-dmg.sh
```

## Лицензия

[MIT](LICENSE)
