# Phase 0 Static Memory Plan

**Status: PHYSICAL INVENTORY RECEIVED; SAFE ALLOCATION PROBE PENDING.** This is
still a planning document only. It does not load a checkpoint, allocate device
memory, query the target, or execute CUDA. The inventory reports **256 MiB
VRAM** for an NVIDIA GeForce 8600 GT, PCI ID `VEN_10DE&DEV_0402`, with driver
`9.18.13.4192` / `341.92`. Display reservation and usable VRAM have not been
measured.

## Inputs and assumptions

- Candidate: RWKV-4 World 169M class.
- Layers: 12.
- Model width: `d_model = 768`.
- Vocabulary: `65,536` tokens.
- Candidate parameter count used for raw storage arithmetic: `169,000,000`.
- Physical host inventory: Windows 10 Home build 19045, AMD Athlon II X2 B24
  at 3.0 GHz, 16 GiB installed RAM, 44.14 GiB free on `C:`.
- CUDA toolkit follow-up: CUDA Toolkit `v6.5` is installed at
  `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v6.5`, and `nvcc.exe`
  is on PATH. `nvcc --version` reports release `6.5`, compiler version
  `V6.5.13`. `cudart64_65.dll`, `cudart.lib`, and `nvcuda.dll` are present.
  The driver DLL reports file/product version `8.17.13.4192` and product
  `NVIDIA CUDA 6.5.51 driver`; WMI reported display driver `9.18.13.4192` /
  `341.92`, so this version relationship must be preserved in the physical
  probe record. `nvidia-smi.exe` remains unavailable. No CUDA samples or
  `deviceQuery.exe` binary was found.
- TPM follow-up: present, enabled, ready, activated, and owned; manufacturer
  reports Infineon TPM 1.2 firmware `3.16`. No TPM integration is part of this
  CUDA experiment.
- Arithmetic precision: FP32 accumulation and FP32 recurrent state.
- Batch size: **PENDING — requires Brian approval**.
- Exact checkpoint tensor list, tied/untied output projection, quantization
  metadata, alignment, and FP32 exceptions: **PENDING PHYSICAL PROBE / CHECKPOINT
  SELECTION**.

The vocabulary embedding alone is `65,536 * 768 = 50,331,648` parameters,
or 192.0 MiB at FP32. The total model-size rows below use the stated 169M
candidate count, because the exact immutable checkpoint has not been selected.

## Raw weight storage

Formula: `bytes = parameter_count * bits_per_weight / 8`.
Binary conversions use `1 MiB = 1,048,576 bytes`.

| Storage | Calculation | Raw bytes | Raw MiB | Planning interpretation |
|---|---:|---:|---:|---|
| FP32 | `169,000,000 * 32 / 8` | 676,000,000 | 644.68 | Not resident within 256 MiB |
| Q8 | `169,000,000 * 8 / 8` | 169,000,000 | 161.17 | Borderline before display/runtime costs |
| Q5 | `169,000,000 * 5 / 8` | 105,625,000 | 100.73 | Potentially resident, subject to overhead and exceptions |
| Q4 | `169,000,000 * 4 / 8` | 84,500,000 | 80.59 | Most plausible resident candidate, subject to validation |

These are raw bit-packing estimates. Q4/Q5/Q8 scales, zero-points, block
padding, container metadata, and tensors retained at FP32 increase the actual
loaded footprint. Their size is **PENDING — requires an exact format and
checkpoint conversion**.

## Recurrent state

For the conventional RWKV-4 inference state layout, each layer has five FP32
vectors of width `d_model`: previous time-mix input, three WKV accumulators, and
previous channel-mix input.

`12 layers * 5 vectors * 768 values * 4 bytes = 184,320 bytes = 0.176 MiB`

This state is fixed-size with respect to context length. The exact reference
implementation's state layout and any temporary double-buffering are **PENDING
— requires a pinned reference implementation**. A conservative two-state
working allowance is approximately **0.35 MiB**, before allocator alignment.

## Non-weight categories

| Category | Static planning value | Status / rationale |
|---|---:|---|
| Current-layer activations | 1-8 MiB | Estimate for batch-one FP32 vectors and intermediates; exact graph pending |
| Normalization/reduction scratch | 1-8 MiB | Estimate; kernel implementation pending |
| Logits/output buffer | 0.25-1 MiB | `65,536 * 4 = 262,144 bytes = 0.25 MiB` for one FP32 logits vector; extra buffers pending |
| Runtime/driver overhead | 16-48 MiB | Planning estimate only; driver/toolkit allocation behavior is **PENDING PHYSICAL PROBE**; installed driver is 341.92 |
| Alignment/fragmentation | 4-16 MiB | Planning allowance; measured allocator behavior is **PENDING PHYSICAL PROBE** |
| Display reservation | **PENDING PHYSICAL PROBE** | An active Generic PnP monitor is present, but WMI did not expose pixel dimensions or the desktop's VRAM reservation |
| Safety reserve | 32 MiB minimum planning reserve | Configurable reserve per section 11.1; Brian must approve the final value |

The runtime/driver, display, and safety categories cannot be established from
architecture alone. Do not treat the estimates above as available VRAM.

## Residency assessment

- **FP32:** fully resident is infeasible at 256 MiB from raw weights alone.
  Layer streaming is theoretically possible as a research comparison but is
  not a useful deployment assumption.
- **Q8:** fully resident is unlikely after display reservation, runtime/driver
  overhead, metadata, and safety reserve. Mostly resident may be possible only
  with a small explicitly streamed tensor set; this is **PENDING PHYSICAL PROBE**.
- **Q5:** fully resident is plausible only if the physical display reservation
  and loaded-format overhead are low. Mostly resident is the more conservative
  planning assumption pending measurement.
- **Q4:** fully resident is the leading hypothesis, but is not yet established;
  the old driver and absent PATH-visible toolkit make toolchain validation an
  additional blocker.
  Mostly resident or layer-streamed modes remain fallback research comparisons,
  not an automatic downgrade.

No residency mode is approved for execution. A physical allocation test must
leave a display-safe margin and must not intentionally trigger a driver reset,
as required by section 11.3.

## PENDING PHYSICAL PROBE

The following still require the target Windows machine: reconciled VRAM from
multiple sources, active display reservation, legacy CUDA runtime/toolkit
compatibility, driver/runtime allocations, safe usable VRAM, actual converted
tensor footprint, and any allocation fragmentation. Throughput, time to first
token, and layer-transfer cost also require physical measurement and are not
inferred here. Do not install or change any driver/toolkit as part of this
read-only gate.
