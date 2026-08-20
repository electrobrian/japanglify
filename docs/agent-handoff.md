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

## 2026-08-20 — Persisted tester-CI contract

- `Build test APKs` runs on qualifying PRs to `BETA-2` and on manual dispatch.
  It runs `:domain:test` and builds exactly three fresh-install tester APKs:
  downloadable debug, bundled debug, and downloadable release.
- Each qualifying PR publishes those APKs as individually downloadable GitHub
  prerelease assets tagged `pr-<PR_NUMBER>-build-<RUN_NUMBER>`, then posts the
  three direct download links and the Actions run link back to the PR. It does
  not upload a user-facing ZIP and it does not create a production release.
- The downloadable release artifact is minified but signed only with the
  ephemeral CI debug-style key. It is a tester artifact, never a production
  signing result. Brian alone creates BETA-2/BETA-3/production tags and
  production releases.
- The workflow uses Gradle's build cache to accelerate subsequent PRs. Its
  cache, generated `app/build` directory, and signing key are runner-local
  implementation details; no secret is committed or persisted in the repo.
- CI status is the validation authority for a PR when a host-local Android or
  Gradle environment cannot reproduce the test run. Record the limitation in
  the linked issue/PR and preserve the workflow URL rather than treating the
  host failure as an application failure.

## 2026-08-20 — Preemptive image default regression guard

- The app module does not yet have a configured unit-test dependency. Issue #5
  adds a focused PowerShell verifier instead of expanding the build/test graph:
  it checks the runtime SharedPreferences getBoolean default for
  `preemptive_image_render` remains `false`. Run it with
  `powershell -ExecutionPolicy Bypass -File scripts/verify-preemptive-image-default.ps1`.
- This guards the fresh-install fast path without changing production behavior,
  preference names, SDK/toolchain versions, or CI configuration.
