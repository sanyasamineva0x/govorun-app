# Pitfalls Research

**Domain:** Breaking enum change (TextMode → SuperTextStyle) in macOS Swift app
**Researched:** 2026-03-29
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Style-Neutral Edit Distance

**What goes wrong:**
NormalizationGate считает стилистические трансформации (Slack→слак, спс→спасибо) как "правки" и отклоняет валидный LLM output.

**Why it happens:**
Edit distance работает на raw strings. Замена "Slack" на "слак" — это 5 символов разницы, хотя семантически это style-driven alias.

**How to avoid:**
Нормализовать оба текста к style-neutral form перед подсчётом edit distance. Обе формы brand alias'ов (Slack↔слак) должны считаться эквивалентными.

**Warning signs:**
Gate начинает отклонять LLM output для relaxed стиля чаще чем для normal.

**Phase to address:**
Phase 4 (Gate modernization) — style-aware protected tokens + edit distance normalization

---

### Pitfall 2: Каскад Broken Tests при Смене Сигнатуры

**What goes wrong:**
Изменение `LLMClient.normalize(_:superStyle:hints:)` ломает все тесты с MockLLMClient одновременно. Красные тесты по всему проекту.

**Why it happens:**
Protocol-based DI означает: менять протокол = менять все реализации + все моки + все call sites.

**How to avoid:**
1. Обновить протокол + MockLLMClient + LocalLLMClient одновременно
2. Обновить все call sites в pipeline
3. Запускать тесты после каждого batch изменений, не накапливать

**Warning signs:**
Если `xcodebuild test` показывает > 50 failures — вы забыли обновить мок или call site.

**Phase to address:**
Phase 3 (Pipeline integration) — атомарная замена сигнатуры

---

### Pitfall 3: UserDefaults Migration Order

**What goes wrong:**
Старый ключ `defaultTextMode` остаётся в UserDefaults. Новый `superStyleMode` не имеет default. Первый запуск после обновления — пустые настройки.

**Why it happens:**
UserDefaults.register(defaults:) не вызван для новых ключей, или вызван после первого чтения.

**How to avoid:**
1. register(defaults:) для `superStyleMode` = `.auto`, `manualSuperStyle` = `.normal`
2. Удалить `defaultTextMode` ключ при первом запуске (migration в AppDelegate/SettingsStore init)
3. Порядок: register defaults → migrate → read

**Warning signs:**
Если `SettingsStore.superStyleMode` возвращает nil или unexpected значение при первом запуске.

**Phase to address:**
Phase 6 (Settings & data)

---

### Pitfall 4: SwiftData Deserialization с Новыми Значениями

**What goes wrong:**
Старые HistoryItem записи с `textMode: "chat"` не map'ятся на SuperTextStyle. Если код делает force unwrap `SuperTextStyle(rawValue:)!` — crash.

**Why it happens:**
SwiftData хранит String, старые значения ("chat", "email", "universal") не являются валидными SuperTextStyle rawValues.

**How to avoid:**
Спека уже решает это: поле остаётся String, без migration. `SuperTextStyle(rawValue:)?.displayName` с fallback на raw string для legacy. НИКОГДА не force unwrap.

**Warning signs:**
Crash при открытии истории с legacy записями.

**Phase to address:**
Phase 6 (Settings & data) — HistoryStore/HistoryView миграция

---

### Pitfall 5: Circular Dependency SuperTextStyle ↔ LLMOutputContract

**What goes wrong:**
`SuperTextStyle.contract` возвращает `LLMOutputContract`, а `NormalizationGate` принимает оба. Если типы в разных модулях — circular import.

**Why it happens:**
Оба типа в Models/ — проблемы нет в текущей архитектуре (единый модуль). Но если кто-то попробует вынести в отдельный package...

**How to avoid:**
Оба enum в Models/ (один Swift module). `LLMOutputContract.swift` не импортирует `SuperTextStyle` — зависимость односторонняя.

**Warning signs:**
Compile error "circular reference" — не должно произойти при правильном размещении.

**Phase to address:**
Phase 1 (Foundation types)

---

### Pitfall 6: Забытые Ссылки на TextMode при Удалении

**What goes wrong:**
Удалили TextMode.swift, но осталась ссылка в каком-то тесте/view/helper. Compile error.

**Why it happens:**
986 тестов, grep может пропустить динамические ссылки или строковые литералы.

**How to avoid:**
1. `grep -rn "TextMode" --include="*.swift"` после удаления
2. `grep -rn "textMode" --include="*.swift"` — camelCase тоже
3. `grep -rn "text_mode" --include="*.swift"` — snake_case (аналитика)
4. Compile → fix → compile цикл до зелёного

**Warning signs:**
Compile errors после git rm TextMode.swift.

**Phase to address:**
Phase 9 (TextMode deletion) — последняя фаза перед тестами

---

### Pitfall 7: Analytics Gap

**What goes wrong:**
Старые события с `text_mode` перестают отправляться, новые с `effective_style` ещё не настроены. Дыра в аналитике.

**Why it happens:**
Analytics key переименование без backward compat: старый ключ удалён, новый не добавлен в том же коммите.

**How to avoid:**
Спека решает: "старые event values не мигрируем". Но новый ключ `effective_style` должен начать писаться ДО удаления старого `text_mode`. Overlap period.

**Warning signs:**
Дашборд показывает drop в событиях нормализации.

**Phase to address:**
Phase 7 (Analytics) — до Phase 9 (TextMode deletion)

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Legacy HistoryItem значения | Без SwiftData migration | UI показывает raw strings для старых записей | Всегда — migration дороже |
| LLMOutputContract.rewriting заглушка | Подготовка к 2.5 | Dead code до 2.5 | Сейчас — enum case дешёв |
| Trivial path без брендов/сленга | Не нужен LLM для коротких фраз | Неполная стилизация без LLM | Осознанный компромисс из спеки |

## "Looks Done But Isn't" Checklist

- [ ] **Gate:** Edit distance нормализует style aliases перед подсчётом — иначе false rejections
- [ ] **Protected tokens:** В relaxed оба варианта (Slack + слак) валидны — не только target form
- [ ] **Postflight:** nil superStyle (classic) → fallback на terminalPeriodEnabled — не на hardcoded default
- [ ] **HistoryView:** Legacy textMode значения отображаются через fallback, не crash
- [ ] **UserDefaults:** register(defaults:) вызван ДО первого чтения superStyleMode
- [ ] **Analytics:** effective_style пишется для ВСЕХ событий, включая classic ("none")
- [ ] **Test helpers:** MockLLMClient обновлён на новую сигнатуру — иначе все тесты красные

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Style-neutral edit distance | Phase 4 (Gate) | Unit test: relaxed input с brand alias проходит gate |
| Cascading broken tests | Phase 3 (Pipeline) | `xcodebuild test` зелёный после каждой фазы |
| UserDefaults migration | Phase 6 (Settings) | Unit test: clean defaults → correct initial values |
| SwiftData deserialization | Phase 6 (Settings) | Unit test: legacy "chat" → fallback display |
| Circular dependency | Phase 1 (Types) | Оба enum в Models/, compile check |
| Forgotten TextMode refs | Phase 9 (Deletion) | Zero grep hits для TextMode/textMode/text_mode |
| Analytics gap | Phase 7 → Phase 9 | New key starts before old key removed |

---
*Pitfalls research for: TextMode → SuperTextStyle breaking change*
*Researched: 2026-03-29*
