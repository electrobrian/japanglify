# Model Surveyor MVP

This is a read-only Windows PowerShell 5.1-compatible host survey and
offline compatibility recommender. It does not install, download, compile, or
run a model.

```powershell
.\model-surveyor.ps1 inventory -OutputJson .\host-report.json
.\model-surveyor.ps1 recommend -HostReport .\host-report.json -OutputJson .\recommendations.json
```

On the other Windows 10 host, simply double-click:

```text
Run-Model-Survey.cmd
```

It makes a timestamped JSON report and matching log under `reports\`, then
opens the report folder. It also writes the predictable handoff file
`reports\latest-host-report.json`. No command-line parameters are needed. The launcher
uses a one-process execution-policy bypass only so this local, portable script
can start; it does not change the machine's persistent PowerShell policy.

For an operator who prefers the explicit PowerShell invocation, the launcher
effectively runs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\model-surveyor.ps1 inventory -OutputJson .\host-report.json
```

Bring back `host-report.json`, not a screenshot. It contains GPU identities,
RAM/VRAM evidence, toolchain probes, CPU/RAM suitability, power information
when Windows exposes it, and an `otherProgrammableResources` inventory.

That inventory deliberately distinguishes four classes:

- `programmable-compute` — a usable accelerator with a plausible runtime.
- `programmable-but-research-only` — for example, an identified FPGA whose
  exact board and safe toolchain still require investigation.
- `sensor-offload` — NICs and ordinary audio hardware: valuable acquisition
  and offload devices, but normally not general compute targets.
- `firmware-bound-not-a-compute-target` — TPM, storage, and management
  controllers that are useful for security/health but must not be repurposed.

The `recommend` result is intentionally conservative. A model that appears to
fit in memory remains `adaptable-research` until its exact runtime, device
operators, numerical behavior, and performance are physically validated.

The source catalog is local at `catalog\candidates.json`; update it by code
review, not through automatic network refreshes.

## Optional Windows 10 development setup

For the survey itself, install nothing: the supplied `.cmd` launcher only
needs the Windows PowerShell already included with Windows 10.

For comfortable inspection and a later approved experiment, use the free VS
Code editor with Microsoft's **PowerShell** and **C/C++** extensions. Set the
integrated terminal profile to Windows PowerShell and leave the workspace in
Restricted Mode until its contents have been reviewed. Git for Windows is
helpful for checking out the experiment, but is not required to run the
surveyor.

Do **not** install a Visual Studio C++ toolchain or CUDA solely for this MVP.
The GeForce 8600 GT needs a legacy CUDA path whose compatible MSVC version must
be established by the Phase 0 feasibility task; installing a current MSVC
toolchain first can create a misleading, incompatible baseline. Once that
task names a supported combination, install only its required C++ workload and
Windows 10 SDK through Visual Studio Build Tools or Visual Studio Community.

