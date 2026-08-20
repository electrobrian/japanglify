# Japanglify

Stuck on Japanese text in a chat app, a game, a tweet, or a webpage?
Japanglify reads it for you, right where you found it.

Select any Japanese text on your phone — in any app — and Japanglify
adds furigana (how to read it), romaji (how to say it), and, if you
want, an English meaning and a matching emoji. No switching apps, no
retyping, no waiting on a translator page to load. Just select, tap,
and read.

- **Works everywhere** — the text-selection menu, the Share button, or
  a simple in-app box if an app doesn't cooperate with either.
- **Reads it out loud, in your head** — hiragana readings over every
  kanji, plus a Latin-letter pronunciation guide underneath, in
  whichever romanization style you're used to.
- **Tells you what it means** — optional English meanings for words
  and particles, smart about picking the *modern* meaning of a word
  rather than a dusty dictionary-first definition.
- **Speaks emoji too** — matching emoji for words that have one, so a
  sentence's mood comes through at a glance.
- **Choose how it looks** — stacked reading lines, inline-style
  furigana, old-school parenthetical notes, or a shareable image you
  can paste anywhere.
- **Works offline** — an optional version of the app bundles
  everything it needs right in the install, so it works on a plane,
  underground, or anywhere without a signal.
- **No account, no cloud, no catch** — everything happens on your own
  phone. Free to use, always.

---

Android app that adds a **global text-selection menu item**. Selecting Japanese text and tapping **Japanglify** expands the selection in place (or copies it when the host is read-only) with:

1. **Base text** — the original selection  
2. **Furigana** — hiragana readings (ruby basis; kanji via Kuromoji/IPADIC)  
3. **Romaji** — Latin phoneticization with a configurable system and position  

No prompts on the menu action. All options live on a separate settings screen (app launcher icon).

## Download

Not on the Play Store — install the APK directly from the latest GitHub Release:

**[⬇ Download app-release.apk](https://github.com/brianreborn/japanglify/releases/latest/download/app-release.apk)** (signed, dictionaries on demand)

A fully-offline **bundled** build (dictionaries included, larger APK) is
`app-bundled-release.apk` on the [Releases page](https://github.com/brianreborn/japanglify/releases/latest). Debug builds of both flavors are there too.

Current release: **1.0.0-beta1**.

Since this isn't a Play Store install, Android will warn about installing from an unknown source the first time — that's expected; allow it for this APK.

## Features

| Area | Details |
|------|---------|
| System menu | `ACTION_PROCESS_TEXT` — appears in the floating text toolbar system-wide |
| Furigana | Hiragana readings; kanji-only by default |
| Romaji systems | Modified Hepburn, Traditional Hepburn, Kunrei-shiki, Nihon-shiki, Wāpuro |
| Romaji position | Below (default, max visibility), above, after, before |
| Output formats | Interlinear (default), furigana inline (《》), parenthetical, HTML ruby, compact brackets |
| Orientation | Horizontal default; vertical (tategaki) experimental hook for future UI |
| Offline | Kuromoji dictionary bundled; no network required — except the optional English-translation line below, off by default |
| Build hosts | Linux, macOS, Windows, **FreeBSD** (Linuxulator + Linux SDK) |

### Triple-script conventions

- **HTML ruby**: furigana via `<ruby><rt>` (the markup browsers actually support); romaji as a smaller block `<span>` under/over the base. (`<rb>`/`<rtc>` were dropped from HTML and do not position correctly.)  
- **Parenthetical plain text**: `漢字（かんじ / kanji）` — common when ruby is unavailable.  
- **Interlinear**: three aligned lines (furigana / base / romaji) for maximum legibility.  
- **Vertical**: settings flag + HTML `writing-mode: vertical-rl` path; plain-text hosts get a marked approximation until a dedicated vertical view lands.

## Project layout

```
domain/          # pure Kotlin JVM — romanizer, analyzer, renderer (no Android)
app/             # Android shell: PROCESS_TEXT + settings + Kuromoji
scripts/         # SDK bootstrap, FreeBSD Linuxulator prep, brandelf
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces fit together
(the two independent entry points into the conversion engine, the
clipboard/accessibility assist pipeline, and the build setup).

For the validated Windows/Codex workstation setup, USB debugging loop, and
safe GitHub fork/push handoff, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Build without the Android SDK (domain)

The core conversion pipeline is a pure JVM module. You only need **JDK 17+** (21 recommended) and the Gradle wrapper — **no Android SDK, no Android Studio**.

```bash
./scripts/verify-domain.sh
# or:
./gradlew :domain:test :domain:runDemo
```

On Windows, use the native wrapper from PowerShell or Command Prompt (no
Git Bash or WSL required):

```powershell
.\gradlew.bat :domain:test :domain:runDemo
```

Demo (optional custom text, kana works offline without Kuromoji):

```bash
./gradlew :domain:runDemo -PdemoText=こんにちは
```

## Build the Android APK

Requires:

- JDK 17+ (run Gradle with 17 or 21)
- Android SDK platform **35** + build-tools **35**
- A supported host: **Linux, macOS, Windows, or FreeBSD**

### Option A — you already have an SDK

```bash
echo "sdk.dir=$HOME/Android/Sdk" > local.properties
./gradlew :app:assembleDownloadableDebug
adb install -r app/build/outputs/apk/downloadable/debug/app-downloadable-debug.apk
```

### Option B — bootstrap a minimal SDK (no Android Studio)

```bash
./scripts/bootstrap-android-sdk.sh   # downloads cmdline-tools into ./sdk
./gradlew :app:assembleDebug
```

### FreeBSD build host (Linuxulator)

Google ships Android SDK / AGP natives for Linux, not FreeBSD. This project treats FreeBSD as a first-class **build host** by:

1. Spoofing `os.name=Linux` for the Android Gradle Plugin so it pulls **Linux** aapt2/build-tools.
2. Installing the **Linux** command-line SDK under `./sdk` (or `$ANDROID_SDK_ROOT`).
3. Running **`brandelf -t Linux`** on newly downloaded Linux ELFs so the FreeBSD Linuxulator executes them.
4. Hooking Gradle task **`brandLinuxElfs`** so branding runs before `preBuild` / resource processing.

#### One-time host setup

```bash
# As root — load Linuxulator and install a Linux userland
sysrc linux_enable=YES
service linux start          # loads linux.ko / linux64.ko
pkg install linux_base-rl9   # provides /compat/linux (glibc, ld-linux)
# brandelf(1) ships with FreeBSD base
```

#### Build on FreeBSD

```bash
# Prefer OpenJDK 17/21 for Gradle (not a bleeding-edge default JDK)
export JAVA_HOME=/usr/local/openjdk21
export PATH="$JAVA_HOME/bin:$PATH"

./scripts/bootstrap-android-sdk.sh   # Linux SDK + brandelf
./scripts/assemble-debug.sh          # re-brands + :app:assembleDebug
# or:
./gradlew :app:assembleDebug         # auto-runs :brandLinuxElfs
```

`sdkmanager` and AGP are told `os.name=Linux` via `JAVA_TOOL_OPTIONS` so they offer/download the **Linux** package set (`platform-tools`, `build-tools`, aapt2). Fresh Linux ELFs are marked with `brandelf -t Linux` so the kernel Linuxulator runs them (verified: `aapt2 version`, `adb version`, and a full `:app:assembleDownloadableDebug` producing `app/build/outputs/apk/downloadable/debug/app-downloadable-debug.apk`).

If AGP downloads a fresh aapt2 into `~/.gradle/caches` mid-build and a native tool fails with “Exec format error”, re-brand and retry:

```bash
./scripts/prepare-freebsd-build.sh
./gradlew :app:assembleDebug
```

| Script | Role |
|--------|------|
| `scripts/lib/freebsd-linuxulator.sh` | Detect FreeBSD + Linuxulator readiness |
| `scripts/lib/brand-linux-elfs.sh` | Recursive `brandelf -t Linux` for Linux ELFs |
| `scripts/bootstrap-android-sdk.sh` | Download Linux SDK; brand after unpack |
| `scripts/prepare-freebsd-build.sh` | Brand SDK + Gradle cache natives |
| `scripts/assemble-debug.sh` | Prep + assembleDebug in one shot |
| `scripts/Run-CI-Pipeline-Dashboard.cmd` | Double-click launcher for the Windows CI/worker dashboard |

### Windows CI Pipeline Dashboard

Double-click `scripts\\Run-CI-Pipeline-Dashboard.cmd` to open a live, read-only
dashboard. It combines open PR/check/APK-release state and recent Codex-task
activity with per-core CPU, memory/commit pressure, uptime, power, and busiest
processes. It requires [GitHub CLI](https://cli.github.com/) (`gh`) to be on
`PATH` and already authenticated for PR/release data; system information still
renders when GitHub is temporarily unavailable. Press `Ctrl+C` to stop it.

For one static terminal snapshot or JSON-lines output for a future local web
viewer, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci-pipeline-dashboard.ps1 -Once
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci-pipeline-dashboard.ps1 -OutputFormat Json
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci-pipeline-dashboard.ps1 -NoColor
```

Console mode uses ANSI/VT colors when available; use `-NoColor` (or set
`NO_COLOR=1`) for monochrome terminals, transcript capture, or accessibility.
The layout is intentionally split into a left CI/workflow column and a right
host-health column, with a compact control-room banner and framed section
headers so the high-signal state remains scannable as the terminal grows.
The default live view follows familiar `top` ergonomics: 3-second refresh,
host-health focus, CPU-sorted busiest processes, task count, uptime, memory,
and power summaries visible immediately.
In interactive mode, Left/Right selects a column, Up/Down scrolls that column,
Home returns it to the top, Space pauses/resumes refresh, and `q` quits. These
keys are disabled for `-Once`, JSON output, redirected output, and other
non-interactive use.

Every run also appends the complete machine-readable snapshot to
`scripts/logs/ci-pipeline-dashboard-%PID%.jsonl` (with `%PID%` expanded per
process), including when the visible mode is Console. Pass `-LogPath` to choose
another location or `-NoLog` to disable it. Each line is a standalone JSON
snapshot suitable for later replay/visualization; `-OutputFormat Json` still
emits the same snapshots to stdout.

Skip the Android app module (domain only): `./gradlew -PincludeApp=false :domain:test`.

## Usage

1. Install the APK and open **Japanglify** once (settings / options).  
2. In any app, select Japanese text.  
3. Tap **Japanglify** in the selection toolbar (check the **⋮ overflow** if it is not among the first icons — Android only shows a few `PROCESS_TEXT` actions inline).  
4. Editable fields are replaced; read-only selections are copied to the clipboard.

### If Japanglify does not appear in the selection menu

| Cause | What to do |
|-------|------------|
| Overflow | Open ⋮ / “…” on the floating toolbar — custom actions often live there |
| Host app (e.g. **Twitter/X**) | Custom menus never call `PROCESS_TEXT` — use **Clipboard assist** instead |
| MIME type | `PROCESS_TEXT` is registered as `text/plain` only (what the platform actually queries) |
| Not installed / disabled | Reinstall APK; check Settings → Apps that Japanglify is enabled |

### Copy hook (primary path for X)

X never lists third-party items in Cut/Copy/Paste. Japanglify’s **main** path is:

1. Japanglify → enable **Process on Copy** → allow notifications.  
2. **Accessibility settings** → enable **Japanglify Copy assist** (status must be On).  
3. In X: select text → tap **Copy**.  
4. Auto Japanglify (uses remembered selection and/or clipboard with retries).  
5. Result notification → **tap to copy** → **Paste**.  

Optional: floating chip on selection is secondary. FGS clipboard watch is a weak fallback.

#### If the Accessibility toggle won't turn on ("restricted setting")

Android blocks apps installed **outside** an app store (which is how you got
this APK, since Japanglify isn't on the Play Store) from using Accessibility
until you explicitly unlock it:

1. Settings → **Apps** → **See all apps** → scroll to **Japanglify**.
2. Open it → tap the **⋮** overflow menu (top-right) → **Allow restricted settings**.
3. Now enable Accessibility → **Japanglify Copy assist** as in step 2 above — the toggle will work.

(The Accessibility list also shows a stock Android "shortcut" toggle — that's an OS-level quick-toggle gesture common to every accessibility service, not something Japanglify adds; it isn't part of the setup above.)

<details open>
<summary><b>Screenshots — every tap, start to finish</b></summary>
<br>

<table>
<tr>
<td align="center" width="25%"><img src="docs/screenshots/settings-home.png" width="180" alt="Android Settings home screen, with the Apps entry highlighted"><br><sub>1. Settings → <b>Apps</b></sub></td>
<td align="center" width="25%"><img src="docs/screenshots/apps-list.png" width="180" alt="Android Settings Apps screen, with recently opened apps and the See all apps link"><br><sub>2. Tap <b>See all apps</b></sub></td>
<td align="center" width="25%"><img src="docs/screenshots/all-apps-list.png" width="180" alt="Android Settings All apps list, scrolled to apps starting with A"><br><sub>3. Scroll the full app list…</sub></td>
<td align="center" width="25%"><img src="docs/screenshots/all-apps-japanglify.png" width="180" alt="Android Settings All apps list, scrolled down to show the Japanglify entry"><br><sub>4. …to find <b>Japanglify</b></sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/app-info.png" width="180" alt="Japanglify App info page in Android Settings, with the overflow menu icon in the top-right corner"><br><sub>5. Tap <b>⋮</b> → <b>Allow restricted settings</b></sub></td>
<td align="center"><img src="docs/screenshots/accessibility-list.png" width="180" alt="Android Accessibility settings list, showing the Japanglify Copy assist entry under Downloaded apps, currently Off"><br><sub>6. Accessibility → <b>Japanglify Copy assist</b></sub></td>
<td align="center"><img src="docs/screenshots/accessibility-toggle.png" width="180" alt="Japanglify Copy assist detail screen in Accessibility settings, with the Use Japanglify Copy assist toggle"><br><sub>7. Flip <b>Use Japanglify Copy assist</b> on</sub></td>
<td align="center"><img src="docs/screenshots/accessibility-confirm.png" width="180" alt="Android confirmation dialog asking to allow Japanglify Copy assist full control of the device, with Allow/Deny/Uninstall options"><br><sub>8. Confirm the permission dialog</sub></td>
</tr>
</table>

</details>

### Settings (separate screen only)

<img src="docs/screenshots/settings.png" width="300" alt="Japanglify settings screen, showing the Reset background services button and Scripts options">

- Include furigana / romaji  
- Furigana on kanji only  
- Romanization system (Hepburn variants, Kunrei, Nihon, Wāpuro)  
- Romaji position (default: **below** for maximum visibility)  
- Output format (interlinear default; furigana inline / parenthetical / HTML ruby / compact)  
- Writing orientation (horizontal / experimental vertical)
- Include English translation (off by default — requires network; the only feature that does)

## Example outputs

Interlinear (default, romaji below):

```
 にほんご      べんきょう
  日本語   を   勉強     する
nihongo o benkyou suru
```

Furigana inline (Aozora-style, best for Discord/chat):

```
日本語《にほんご》を勉強《べんきょう》する
nihongo o benkyou suru
```

Parenthetical:

```
日本語（にほんご / nihongo）を（o）勉強（べんきょう / benkyou）する（suru）
```

HTML ruby (paste into HTML-capable hosts; furigana is real ruby, romaji is a stacked span — `<rb>`/`<rtc>` are not used):

```html
<span style="display:inline-block;text-align:center">
  <ruby>日本語<rt>にほんご</rt></ruby>
  <span style="display:block;font-size:0.62em">nihongo</span>
</span>
```

## License

App code is licensed under the [Light-ware License](LICENSE) — the 4-clause BSD License plus one Beerware-style addition.

Bundled/downloaded third-party data and libraries keep their own upstream
licenses — see [ARCHITECTURE.md](ARCHITECTURE.md) and the in-app About →
Credits screen for the full list (Kuromoji/IPADIC: Apache License 2.0;
JMdict/EDICT: CC BY-SA 4.0; Unicode CLDR: Unicode-3.0; Princeton WordNet:
WordNet License).
