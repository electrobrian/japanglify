# Development handoff: Windows / Codex workstation

This is the setup and operational knowledge accumulated while developing
Japanglify on Windows in a sandboxed Codex session. It is deliberately
practical: use it to bring up a replacement workstation without repeating
environment troubleshooting.

## Toolchain

- **JDK:** JDK 22 has been validated here. Configure `JAVA_HOME` to the JDK
  installation (for example, `C:\Program Files\Java\jdk-22.0.1`) and put
  `%JAVA_HOME%\bin` on `PATH`. The project itself requires JDK 17 or newer.
- **Android:** compile SDK/platform **35** and build-tools **35** are the
  target toolchain. The app targets API 35; do not reduce it merely to make an
  older local SDK work.
- **Project-local SDK:** a project-local SDK may be used via `local.properties`
  (`sdk.dir=...`). Keep that path machine-local; `local.properties` must never
  be committed.
- **Gradle on Windows:** use `gradlew.bat` from PowerShell or Command Prompt.
  Do not require Git Bash, WSL, or `/bin/sh` to build the Android project.

Quick sanity check for the pure Kotlin module:

```powershell
.\gradlew.bat :domain:test :domain:runDemo
```

## Build and install loop

Use the downloadable debug flavor while iterating:

```powershell
.\gradlew.bat :app:assembleDownloadableDebug
adb install -r app\build\outputs\apk\downloadable\debug\app-downloadable-debug.apk
```

The core-domain test command above is a fast, useful check when an Android
build cannot run due to an IDE/Codex sandbox restriction. It does **not** prove
the Android app compiles. In restricted sessions, AGP can fail while accessing
or transforming Android platform JARs, or while writing Android telemetry.
Treat that as environment evidence first; rerun the Android build in a normal
local terminal before attributing it to app source.

## USB debugging

1. On the phone, enable Developer options, then USB debugging.
2. Attach the phone with a data-capable USB cable and accept the RSA prompt.
3. Verify it before installing:

   ```powershell
   adb devices
   ```

   The device must show `device`, not `unauthorized`.
4. Use `adb logcat` and the installed debug APK for the system-selection menu,
   share target, overlay chip, and accessibility-service behaviors; these are
   not meaningfully covered by the domain test suite.

## GitHub: safe fork and push

Never push experimental work to the upstream `brianreborn/japanglify` remote.
Authenticate the intended GitHub account, create its fork, add it as a
separate remote (for example, `codex`), and push a named work-in-progress
branch there:

```powershell
gh auth status --hostname github.com
gh api user --jq .login                 # verify the intended account
gh repo fork brianreborn/japanglify --clone=false --remote-name codex
git switch -c codex/<short-description>
git add <only the intended files>
git commit -m "wip: <short description>"
git push -u codex codex/<short-description>
```

In a sandboxed Codex Windows session, GitHub CLI may be unable to write its
normal configuration location, `%APPDATA%\GitHub CLI`. Browser device login can
therefore report success while `gh auth status` still reports no account. Use
a temporary configuration directory that is writable to the session, and keep
that environment variable set for **every** subsequent `gh` command:

```powershell
$env:GH_CONFIG_DIR = "$PWD\.gh-cli-temp"
gh auth login --web
# Complete the device code at https://github.com/login/device.
gh auth status
```

The CLI may not be allowed to launch Firefox itself; opening the device URL
manually is sufficient. After the fork/push completes, delete `.gh-cli-temp`.
It contains a temporary GitHub token and must not be committed.

## Current product priorities

The interaction hierarchy is intentional:

1. The accessibility **chip** is the primary fast path.
2. The Android **Share** target is the secondary workflow and can offer
   per-item output choices without accessibility permission.
3. Copy/cut/clipboard observation is a legacy fallback and belongs below the
   primary controls in the settings UI.

Avoid generating an image on the fast textual path unless the user explicitly
requests image output. Optional background image preparation is off by default
and must remain low-priority, cancellable, and keyed by all relevant rendering
settings. A one-deep current-result cache is appropriate; stale image reuse
after a settings change is not.


