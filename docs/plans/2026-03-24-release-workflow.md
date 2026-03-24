# Release Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Actions workflow that builds DMG, signs with Sparkle EdDSA, creates GitHub Release, updates appcast.xml, and updates Homebrew Cask — triggered by pushing a version tag.

**Architecture:** Single workflow file `.github/workflows/release.yml` triggered by `v*` tags. Builds from tagged commit, switches to `main` only for appcast commit. Uses GitHub App token for cross-repo Homebrew push.

**Tech Stack:** GitHub Actions, macOS runner, xcodebuild, XcodeGen, Sparkle sign_update, gh CLI, actions/cache, actions/create-github-app-token

**Spec:** `docs/2026-03-24-release-workflow-design.md`

---

### Task 1: Create release workflow file — skeleton + version validation

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create workflow with trigger, permissions, concurrency, checkout, version parse + validate**

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  release:
    name: Build & Release
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Parse version from tag
        id: version
        run: |
          TAG="${GITHUB_REF_NAME}"           # v0.1.11
          VERSION="${TAG#v}"                  # 0.1.11
          BUILD="${VERSION##*.}"              # 11 (last segment)
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "build=$BUILD" >> "$GITHUB_OUTPUT"
          echo "Releasing $TAG → version=$VERSION build=$BUILD"

      - name: Validate version in project.yml
        run: |
          EXPECTED_MV="${{ steps.version.outputs.version }}"
          EXPECTED_PV="${{ steps.version.outputs.build }}"
          ACTUAL_MV=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
          ACTUAL_PV=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *\([0-9]*\)/\1/')
          echo "Expected: MV=$EXPECTED_MV PV=$EXPECTED_PV"
          echo "Actual:   MV=$ACTUAL_MV PV=$ACTUAL_PV"
          if [ "$ACTUAL_MV" != "$EXPECTED_MV" ]; then
            echo "ERROR: MARKETING_VERSION mismatch: '$ACTUAL_MV' != '$EXPECTED_MV'"
            echo "Bump project.yml before tagging."
            exit 1
          fi
          if [ "$ACTUAL_PV" != "$EXPECTED_PV" ]; then
            echo "ERROR: CURRENT_PROJECT_VERSION mismatch: '$ACTUAL_PV' != '$EXPECTED_PV'"
            exit 1
          fi
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow skeleton — trigger, version validation"
```

---

### Task 2: Add dependency caching + install steps

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add XcodeGen install, Python.framework cache, wheels cache, fallback download steps**

After the validate step, add:

```yaml
      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Cache Python.framework
        id: cache-python
        uses: actions/cache@v4
        with:
          path: Frameworks/Python.framework
          key: python-fw-${{ hashFiles('scripts/fetch-python-framework.sh') }}

      - name: Download Python.framework
        if: steps.cache-python.outputs.cache-hit != 'true'
        run: bash scripts/fetch-python-framework.sh

      - name: Cache wheels
        id: cache-wheels
        uses: actions/cache@v4
        with:
          path: worker/wheels
          key: wheels-cp313-${{ hashFiles('worker/requirements.txt', 'scripts/download-wheels.sh') }}

      - name: Download wheels
        if: steps.cache-wheels.outputs.cache-hit != 'true'
        run: bash scripts/download-wheels.sh
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow — cache deps + install XcodeGen"
```

---

### Task 3: Add build + test + sign steps

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add xcodegen, tests, build DMG, artifact upload, sign_update steps**

```yaml
      - name: Generate Xcode project
        run: xcodegen generate

      - name: Run tests
        run: |
          set -o pipefail
          xcodebuild test \
            -scheme Govorun \
            -destination 'platform=macOS' \
            | tee /tmp/xcodebuild.log | tail -20
          echo "$(grep 'Executed' /tmp/xcodebuild.log | tail -1)"

      - name: Build unsigned DMG
        run: bash scripts/build-unsigned-dmg.sh

      - name: Upload DMG artifact
        uses: actions/upload-artifact@v4
        with:
          name: Govorun-${{ steps.version.outputs.version }}.dmg
          path: build/Govorun.dmg

      - name: Sign DMG with Sparkle EdDSA
        id: sign
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          # Find sign_update
          SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*" | head -1)
          if [ -z "$SIGN_UPDATE" ]; then
            echo "ERROR: sign_update not found in DerivedData"
            exit 1
          fi
          echo "Found sign_update: $SIGN_UPDATE"

          # Decode key
          echo "$SPARKLE_PRIVATE_KEY" | base64 -D > /tmp/sparkle_key
          trap "rm -f /tmp/sparkle_key" EXIT

          # Sign
          SIGN_OUTPUT=$("$SIGN_UPDATE" build/Govorun.dmg -f /tmp/sparkle_key)
          echo "sign_update output: $SIGN_OUTPUT"

          ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'edSignature="[^"]*"' | cut -d'"' -f2)
          LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

          if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
            echo "ERROR: Failed to parse sign_update output"
            exit 1
          fi

          echo "ed_signature=$ED_SIGNATURE" >> "$GITHUB_OUTPUT"
          echo "length=$LENGTH" >> "$GITHUB_OUTPUT"

      - name: Compute SHA256
        id: sha
        run: |
          SHA=$(shasum -a 256 build/Govorun.dmg | cut -d' ' -f1)
          echo "sha256=$SHA" >> "$GITHUB_OUTPUT"
          echo "SHA256: $SHA"
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow — build, test, sign, sha256"
```

---

### Task 4: Add GitHub Release creation with re-run safety

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add release create/upload step with exists check**

```yaml
      - name: Create or update GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          TAG="${{ steps.version.outputs.tag }}"
          if gh release view "$TAG" &>/dev/null; then
            echo "Release $TAG already exists — uploading DMG"
            gh release upload "$TAG" build/Govorun.dmg --clobber
          else
            gh release create "$TAG" build/Govorun.dmg --generate-notes
          fi
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow — GitHub Release with re-run safety"
```

---

### Task 5: Add appcast.xml update + push to main

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add appcast update step — fetch release body, build XML item, checkout main, commit, push**

```yaml
      - name: Update appcast.xml
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          VERSION="${{ steps.version.outputs.version }}"
          BUILD="${{ steps.version.outputs.build }}"
          TAG="${{ steps.version.outputs.tag }}"
          ED_SIGNATURE="${{ steps.sign.outputs.ed_signature }}"
          LENGTH="${{ steps.sign.outputs.length }}"
          PUB_DATE=$(LC_TIME=C date -u '+%a, %d %b %Y %H:%M:%S %z')

          # Fetch release body for description
          BODY=$(gh release view "$TAG" --json body -q .body 2>/dev/null || echo "")
          if [ -z "$BODY" ]; then
            BODY="<p>See <a href=\"https://github.com/sanyasamineva0x/govorun-app/releases/tag/$TAG\">release notes</a></p>"
          fi

          # Build new <item>
          ITEM=$(cat <<XMLEOF
    <item>
      <title>$TAG</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$BODY]]></description>
      <enclosure
        url="https://github.com/sanyasamineva0x/govorun-app/releases/download/$TAG/Govorun.dmg"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$LENGTH"
      />
    </item>
XMLEOF
          )

          # Switch to main for commit
          git fetch origin main
          git switch -C main --track origin/main

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          # Insert new item after <language>ru</language>\n
          # Use python for reliable XML insertion (sed with multiline is fragile)
          export APPCAST_ITEM="$ITEM"
          python3 -c "
import os
appcast = open('appcast.xml').read()
marker = '<language>ru</language>'
idx = appcast.index(marker) + len(marker)
new_item = '\n\n' + os.environ['APPCAST_ITEM'] + '\n'
result = appcast[:idx] + new_item + appcast[idx:]
open('appcast.xml', 'w').write(result)
          "

          git add appcast.xml
          git commit -m "appcast: $TAG"
          git push origin main
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow — appcast.xml update + push main"
```

---

### Task 6: Add Homebrew Cask update via GitHub App

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add GitHub App token generation + cask update step**

```yaml
      - name: Generate Homebrew token
        id: homebrew-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.HOMEBREW_APP_ID }}
          private-key: ${{ secrets.HOMEBREW_APP_PRIVATE_KEY }}
          repositories: homebrew-govorun
          owner: sanyasamineva0x

      - name: Update Homebrew Cask
        env:
          GH_TOKEN: ${{ steps.homebrew-token.outputs.token }}
        run: |
          VERSION="${{ steps.version.outputs.version }}"
          SHA="${{ steps.sha.outputs.sha256 }}"

          git clone https://x-access-token:${GH_TOKEN}@github.com/sanyasamineva0x/homebrew-govorun.git /tmp/homebrew-govorun
          cd /tmp/homebrew-govorun

          # Update version and sha256
          sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/govorun.rb
          sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/govorun.rb

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Casks/govorun.rb
          git commit -m "bump: govorun $VERSION"
          git push
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow — Homebrew Cask update via GitHub App"
```

---

### Task 7: Dry-run validation

**Files:**
- Read: `.github/workflows/release.yml` (final review)

- [ ] **Step 1: Validate complete workflow YAML syntax**

```bash
cd /Users/sanyasamineva/Desktop/govorun-app
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML valid"
```

- [ ] **Step 2: Review the complete workflow file end-to-end**

Read `.github/workflows/release.yml` and verify:
- All step IDs referenced in later steps exist
- All secrets referenced are documented in spec
- All outputs used in later steps are set in earlier steps
- No GNU-only CLI flags (base64 --decode, sha256sum)
- fetch-depth: 0 is set
- concurrency group is set

- [ ] **Step 3: Push to main**

```bash
git push origin main
```

- [ ] **Step 4: Document required secrets setup**

Print instructions for the developer:
1. `base64 < ~/.config/sparkle/eddsa_key | pbcopy` → add as `SPARKLE_PRIVATE_KEY` in repo Settings → Secrets
2. Create GitHub App with `contents: write` on `homebrew-govorun` → add `HOMEBREW_APP_ID` + `HOMEBREW_APP_PRIVATE_KEY`
3. Test: bump project.yml → commit → `git tag v0.1.11 && git push --tags`
