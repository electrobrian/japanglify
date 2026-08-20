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
  APKs; the GitHub Project status, not a custom label, records *Ready for test*.

## 2026-08-20 — Issue-driven workflow dry run

- Issue #2 verified the remote agent workflow: issue intake from the Project
  queue, an `agent/` branch based on `BETA-2`, a narrowly scoped documentation
  commit, and a PR back to `BETA-2`. No application code or release branch was
  changed.
