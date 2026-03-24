# Release Workflow — GitHub Actions

## Trigger

Push тега `v*` (например `git tag v0.1.11 && git push --tags`).

Workflow собирает DMG из tagged commit, подписывает Sparkle EdDSA, создаёт GitHub Release, обновляет appcast.xml и Homebrew Cask.

## Preconditions

- Разработчик bump'ает `project.yml` и коммитит **до** тега
- Тесты проходят на main (tests.yml на push)
- Тег ставится на коммит, прошедший CI

## Version policy

Workflow **валидирует**, не bump'ает.

Соглашение: `CURRENT_PROJECT_VERSION` = последний сегмент semver (patch). Для `v0.1.11` → `MARKETING_VERSION: "0.1.11"`, `CURRENT_PROJECT_VERSION: 11`. Для `v0.2.0` → `CURRENT_PROJECT_VERSION: 0`. Для `v1.0.0` → `CURRENT_PROJECT_VERSION: 0`.

Workflow проверяет оба значения и падает при расхождении.

## Secrets

| Secret | Формат | Как получить |
|--------|--------|-------------|
| `SPARKLE_PRIVATE_KEY` | base64-encoded EdDSA key | `base64 < ~/.config/sparkle/eddsa_key \| pbcopy` |
| `HOMEBREW_APP_ID` | число | GitHub App → Settings → App ID |
| `HOMEBREW_APP_PRIVATE_KEY` | PEM | GitHub App → Settings → Generate private key |

## Permissions & concurrency

```yaml
permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false
```

`fetch-depth: 0` на checkout — для переключения между tag и main.
`concurrency: group: release` — сериализует параллельные релизы.

## Cache

```
python-fw-{hashFiles('scripts/fetch-python-framework.sh')}
wheels-cp313-{hashFiles('worker/requirements.txt', 'scripts/download-wheels.sh')}
```

## Шаги

```
 1. Checkout по tag SHA (fetch-depth: 0)
 2. Install XcodeGen (brew install xcodegen)
 3. Parse version из тега: v0.1.11 → version=0.1.11, build=11
 4. Validate: MARKETING_VERSION и CURRENT_PROJECT_VERSION в project.yml
 5. Run tests: xcodebuild test -scheme Govorun -destination 'platform=macOS'
 6. Restore cache: Python.framework
 7. Restore cache: wheels
 8. Cache miss → bash scripts/fetch-python-framework.sh
 9. Cache miss → bash scripts/download-wheels.sh
10. xcodegen generate
11. bash scripts/build-unsigned-dmg.sh
12. Upload DMG as artifact (actions/upload-artifact) — страховка перед release
13. Find sign_update in DerivedData (fail with clear error if not found)
14. Decode SPARKLE_PRIVATE_KEY (base64 -D), sign DMG → parse edSignature + length
15. shasum -a 256 build/Govorun.dmg
16. gh release create v$VERSION build/Govorun.dmg --generate-notes
17. Fetch release body → build appcast <item>
18. git fetch origin main && git switch -C main --track origin/main
19. Update appcast.xml (новый <item> сверху), git commit + push main
20. Generate GitHub App token (actions/create-github-app-token)
21. Clone homebrew-govorun, update Casks/govorun.rb (version + sha256), commit + push
```

## Re-run strategy

Если workflow упал после `gh release create`:
- Релиз уже существует → при повторном запуске использовать `gh release upload v$VERSION build/Govorun.dmg --clobber` вместо create
- Workflow проверяет: `gh release view v$VERSION` — если exists, upload вместо create

## Failure domains

| Шаг | При падении | Последствия |
|-----|-------------|-------------|
| Tests / Build / sign (1-15) | Fail workflow | Ничего не опубликовано |
| gh release (16) | Fail workflow | DMG сохранён как artifact |
| **Appcast update (17-19)** | **Критично** | Release есть, Sparkle не видит |
| Cask update (20-21) | Не критично | `brew upgrade` не работает, DMG доступен |

## sign_update на CI

После `xcodebuild archive` (внутри `build-unsigned-dmg.sh`) Sparkle SPM package собирается, `sign_update` появляется в DerivedData:

```bash
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*" | head -1)
if [ -z "$SIGN_UPDATE" ]; then
    echo "ERROR: sign_update not found in DerivedData"
    exit 1
fi
```

Parsing output:
```bash
# sign_update выводит: sparkle:edSignature="XXX" length="NNN"
SIGN_OUTPUT=$("$SIGN_UPDATE" build/Govorun.dmg -f /tmp/sparkle_key)
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
```

## macOS CLI

- `base64 -D` (BSD), не `--decode` (GNU)
- `shasum -a 256` (macOS), не `sha256sum`
- `date -u '+%a, %d %b %Y %H:%M:%S %z'` для RFC 2822 pubDate в appcast

## Git на CI

Для коммита appcast.xml:
```bash
git fetch origin main && git switch -C main --track origin/main
```

Git identity:
```bash
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
```

Если push конфликтует (main advanced) — workflow fails. Для одного разработчика это редкий edge case; force push не используем.

## Appcast item format

```xml
<item>
  <title>v$VERSION</title>
  <pubDate>$RFC2822_DATE</pubDate>
  <sparkle:version>$BUILD</sparkle:version>
  <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <description><![CDATA[$RELEASE_BODY_OR_FALLBACK]]></description>
  <enclosure
    url="https://github.com/sanyasamineva0x/govorun-app/releases/download/v$VERSION/Govorun.dmg"
    type="application/octet-stream"
    sparkle:edSignature="$ED_SIGNATURE"
    length="$LENGTH"
  />
</item>
```

Если release body пустое — fallback: `<p>See <a href="https://github.com/sanyasamineva0x/govorun-app/releases/tag/v$VERSION">release notes</a></p>`.

## Release notes

`gh release create` с `--generate-notes` автоматически генерирует notes из коммитов. Body используется для appcast description.

## CLAUDE.md reconciliation

CLAUDE.md шаг 7 говорит "коммит appcast.xml + project.yml + pbxproj". В workflow project.yml и pbxproj уже в tagged commit (разработчик bump'ает заранее). Workflow коммитит только appcast.xml на main.

## Runner

`macos-15`. Сборка через `build-unsigned-dmg.sh` (без Developer ID / notarization).

## Будущее

- Developer ID + notarization → отдельный workflow или замена скрипта
- Если схема CURRENT_PROJECT_VERSION изменится — поправить один regex
