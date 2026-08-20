# Agent handoff log

This is the durable context shared across issue-driven agent runs. Add concise,
dated entries when work discovers a reproducible environment constraint,
validation result, architectural decision, or follow-up risk.

## 2026-08-19 — Windows/Codex baseline

- Validated local toolchain target: JDK 22 and Android API/build-tools 35.
  Use `gradlew.bat` on Windows; do not depend on Git Bash, WSL, or `/bin/sh`.
- A fresh Codex shell may not inherit the machine-level `JAVA_HOME`. For local
  validation, set it explicitly to the validated JDK 22 installation before
  invoking `gradlew.bat`; do not commit this as a project-specific path.
- `:domain:test` passed. In the sandboxed Codex environment, full Android
  Gradle builds may fail while AGP accesses platform JAR transforms or Android
  telemetry directories. Treat that as an environment limitation until it
  reproduces in a normal local terminal.
- The project has an established FreeBSD Linuxulator build path, including full
  Android build and test validation. Prefer that proven route for a definitive
  full build when the constrained Windows/Codex environment cannot run AGP.
- USB test target was detected by `adb`; accessibility, selection menu, share,
  overlay, and clipboard behavior require device validation.
- The original checkout's `.git` ACL denies this sandbox write access. Work
  must be committed from a fresh writable clone of the GitHub fork.
- GitHub CLI device auth may not persist in `%APPDATA%\GitHub CLI`. A
  temporary `GH_CONFIG_DIR` under a writable build workspace works; delete it
  after use because it contains a token.
- This fork uses a distinct GitHub account. Keep the original repository as
  read-only upstream and push agent work only to dedicated fork branches.

## 2026-08-19 — Branch and test-APK policy

- `BETA-2` is the integration branch for issue work. `BETA-3` will be a new
  branch cut after personal testing, not an automatic release tag.
- An issue is **maybe resolved / requires testing** only after the APK workflow
  succeeds for its branch. The workflow uploads downloadable and bundled debug
  APKs; the GitHub Project `Validation` field, not a custom label, records *Ready for test*.

## 2026-08-20 — GitHub issue-agent integration

- The `electrobrian/japanglify` fork has Issues enabled and uses GitHub's
  standard repository labels only: `bug`, `enhancement`, `documentation`,
  `accessibility`, and the standard default set.
- Planning lives in the private **Japanglify development** GitHub Project,
  linked to the fork. `Status` remains the standard Todo/In Progress/Done
  field; `Validation` is a normal Project single-select field with Not ready,
  Ready for test, and Tested.
- The official Codex GitHub connector is authorized. A 15-minute Codex heartbeat
  inspects queued issues and posts an intake plan before it changes code,
  branches, issue state, or Project fields.
- The connected-agent dry run is issue #2 and its PR into `BETA-2`. It changes
  only this handoff log; its result validates issue → agent branch → PR without
  touching app code.

## 2026-08-20 — CI resource-link failure

- The first connected-agent APK workflow run reached Android resource linking
  and failed because the English string resources lacked
  `overlay_preview_status`, `overlay_action_settings`, and
  `overlay_action_copy_as_image`, even though the overlay layout referenced
  them. The missing English strings were added on `BETA-2`; wait for the
  follow-up workflow before considering any output ready for testing.


## 2026-08-20 — CI debug signing

- The next CI run passed resource linking and then failed at debug signing because
  `app/build/local-debug.keystore` is intentionally uncommitted. The APK
  workflow now generates this standard, ephemeral Android debug keystore on the
  hosted runner before assembly; no release key or secret is introduced.

## 2026-08-20 — Confirmed GitHub APK workflow

- The repaired `BETA-2` workflow completed successfully: it built both
  downloadable and bundled debug APKs, then uploaded artifact
  `japanglify-test-apks-13` (GitHub Actions retention through 2026-11-18).
- The workflow creates `app/build` and an ephemeral standard debug keystore
  before Gradle assembly. This is the established CI recipe; it never accesses
  a release keystore.

## 2026-08-20 — Preemptive image default regression guard

- The app module does not yet have a configured unit-test dependency. Issue #5
  adds a focused PowerShell verifier instead of expanding the build/test graph:
  it checks the runtime SharedPreferences getBoolean default for
  `preemptive_image_render` remains `false`. Run it with
  `powershell -ExecutionPolicy Bypass -File scripts/verify-preemptive-image-default.ps1`.
- This guards the fresh-install fast path without changing production behavior,
  preference names, SDK/toolchain versions, or CI configuration.

## 2026-08-20 — CI Pipeline Dashboard

- `scripts/ci-pipeline-dashboard.ps1` is a read-only Windows PowerShell 5.1+
  dashboard for open PR/check/tester-APK state, inferred Codex worker activity,
  recent transcript commentary, and host health. Its JSON-lines mode is the
  future-friendly collector boundary for a local web view.
- `scripts/Run-CI-Pipeline-Dashboard.cmd` is the double-click launcher: it uses
  a process-local execution-policy bypass and does not alter machine settings.
- GitHub lookup failures are displayed in the PR panel while local health and
  transcript panels continue rendering. The dashboard requires authenticated
  `gh` only for GitHub-backed data.
- Console mode color-codes headings, pass/fail/wait states, power warnings, and
  resource panels with ANSI/VT sequences when supported; `-NoColor` and the
  `NO_COLOR` environment variable provide deterministic monochrome output.
- The dashboard uses ASCII-only framing for portable Windows code pages, with a
  top-level control-room banner and deliberate left workflow/right host-health
  composition. This avoids relying on Unicode box drawing while preserving
  clear visual grouping.
- Interactive controls are deliberately isolated from machine-readable output:
  Left/Right changes pane focus, Up/Down scrolls, Home resets the selected pane,
  Space pauses/resumes refresh, and `q` quits. JSON-lines and redirected/`-Once`
  modes never read console keys or emit control sequences.
- The control-room pass follows familiar `top`/`ps` conventions: a compact
  summary line, stable section headers, aligned process columns, explicit
  pressure labels, and a short activity tail instead of repeatedly exposing
  long transcript paths in the visual panel. The JSON snapshot retains the
  complete transcript path and data.
- Each process appends complete raw snapshots as JSONL to
  `scripts/logs/ci-pipeline-dashboard-<PID>.jsonl` by default. `%PID%` is
  expanded before the first write, so simultaneous consoles do not collide;
  `-LogPath` overrides the destination and `-NoLog` disables persistence.
  Console styling and interactive controls never enter the log, making it a
  stable source for a future replay/viewer.
- Arrow handling accepts both native `ConsoleKeyInfo` arrow keys and ANSI
  escape sequences from pseudo-terminals. Input is drained before and after a
  refresh so network/counter work does not swallow navigation keystrokes.
- Defaults now follow familiar `top` ergonomics: 3-second refresh, host-health
  focus, CPU-sorted busiest processes, and a task count in the host summary.

## 2026-08-20 — GitHub-backed approval surface

- The dashboard now includes an `Approvals` collection in Console/JSON output.
  It observes canonical issue comments from `electrobrian` using the exact
  `/codex-approval-request` and `/codex-approval approve <digest>` forms.
- This is an audit/visibility surface, not an authority bypass: Codex still
  requires the in-task worker/model approval gate before assigning work.
