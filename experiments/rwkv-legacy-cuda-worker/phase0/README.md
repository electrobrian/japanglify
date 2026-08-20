# Phase 0: Physical Target Confirmation

Phase 0 is the read-only confirmation stage for the legacy RWKV CUDA worker.
It produces a host inventory, a static memory plan, and a draft execution
manifest. It does not download a model, install software, allocate GPU memory,
compile or execute CUDA code, execute a model, or open a network listener.

## Run on the target Windows machine

Use Windows PowerShell 5.1 in a normal, non-administrator prompt. Copy this
`phase0` directory to the physical Windows target, then run:

```powershell
Set-Location .\phase0
.\Invoke-HostInventory.ps1
```

The script requires no internet access. It writes these files beside itself:

- `host-inventory-report.txt` for human-readable review.
- `host-inventory.json` for machine-readable planning input.

The inventory includes OS and PowerShell details, CPU and RAM, every display
adapter, NVIDIA registry entries, PATH-visible CUDA/NVIDIA tools, matching
installed programs, TPM status, and system-drive free space. Missing tools or
unavailable TPM data are recorded as unavailable; they are not guessed.

## Return the output

Send the report and JSON summary back to the planning process through the
approved private channel. Do not add secrets, private URLs, or unrelated source
content. The physical results are needed to reconcile PCI identity, VRAM,
driver/toolkit availability, display reservation, and a display-safe usable
VRAM estimate before Phase 1 planning.

## Fields filled after the physical run

The physical run can fill the manifest's OS/toolchain evidence, GPU PCI identity,
driver and CUDA presence, reported VRAM, and the inputs to the display and
memory budgets. A safe allocation probe and later benchmark are still separate
approved activities; inventory alone does not establish usable VRAM,
throughput, or time to first token.

The exact checkpoint, tokenizer, quantization format, runtime revision, memory
budgets, precision policy, context limits, placement, role, tools, actions,
and manifest identifier remain pending until the required technical and license
reviews are complete.

## Brian approval before Phase 1

Before Phase 1 begins, Brian must approve the exact immutable checkpoint and
license/usage purpose; tokenizer and destination format; quantization details
and FP32 exceptions; runtime/compiler/toolchain plan; physical GPU and memory
budget; precision, context, batch, and output limits; expected CPU/GPU
placement; worker role and enabled tools; and download/build/execution/cleanup/
rollback actions. The final canonical manifest identifier must be derived only
after those fields are confirmed. 
