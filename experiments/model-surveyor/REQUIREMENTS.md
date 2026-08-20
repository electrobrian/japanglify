# Legacy GPU Model Surveyor — Requirements

## 1. Purpose

Build a Windows 7-or-newer host-survey and model-feasibility tool that answers four separate questions:

1. What compute hardware, drivers, runtimes, memory, and power constraints does this host actually have?
2. Which local machine-learning models can run immediately with an existing compatible runtime?
3. Which models could plausibly run after a small, explicitly described adaptation?
4. What evidence, uncertainty, expected performance, and engineering work support each conclusion?

The tool is an advisor and benchmark harness, not an autonomous installer. It must not download a model, install a driver or toolkit, compile native code, or run a model until the operator approves the exact model and execution configuration.

The first important target is an older Windows PC with an Athlon II X2 B24 and a GeForce 8600 GT, but the implementation must be useful on contemporary Windows hosts and on machines with NVIDIA, AMD, Intel, or CPU-only compute.

The first remote Windows 10 report established a concrete regression fixture:
an HP Compaq 6005 Pro SFF with 16 GiB RAM, an Athlon II X2 B24, a GeForce 8600
GT reporting 256 MiB through WMI, Broadcom NetXtreme GbE, Realtek ALC662-class
HDA audio, and TPM 1.2. No FPGA/BMC-class accelerator was enumerated. The
onboard Radeon HD 4200 was not enumerated and must be reported as unavailable,
not assumed active from platform documentation.

## 2. Product boundary

### In scope

- Inventory a Windows host without requiring administrator access.
- Identify GPUs by PCI hardware ID as well as marketing name.
- Detect installed display drivers, CUDA/OpenCL/Vulkan/DirectML capabilities, toolkits, compilers, and candidate runtimes.
- Correct unreliable or truncated VRAM reports using multiple evidence sources.
- Maintain a versioned catalog of model architectures, checkpoints, quantizations, operators, licenses, runtimes, and accelerator constraints.
- Estimate whether a model and a selected context length fit in system RAM and accelerator memory.
- Distinguish weight fit, runtime compatibility, operator compatibility, and likely usable performance.
- Identify a reproducible adaptation plan when no ready-made runtime exists.
- Recommend useful non-model assignments for each independently schedulable
  host resource, including CPU compilation, conversion, validation,
  preprocessing, indexing, orchestration, and telemetry work when a GPU model
  is not the best use of the machine.
- Classify a host's suitability as a serialized Android VM test host separately
  from model-inference suitability, including RAM headroom, CPU contention,
  virtualization availability, and the expected impact on concurrent GPU or
  build work.
- Optionally run non-model microbenchmarks and operator tests after explicit approval.
- Optionally validate a locally supplied model after explicit approval.
- Emit both a readable console report and stable JSON suitable for the `ci-pipeline-dashboard` collector.
- Support offline operation using a bundled or previously refreshed compatibility catalog.

### Out of scope for the first release

- Automatically choosing or approving a model for production work.
- Downloading model weights by default.
- Automatically installing or replacing GPU drivers.
- Automatically overclocking, changing firmware, or changing persistent power settings.
- Claiming that a model is capable of software architecture work solely because it fits in memory.
- Full model training on the surveyed host.
- Treating CPU fallback as successful GPU execution when the requested policy requires GPU-resident major computation.

## 3. Design principles

1. **Evidence before recommendation.** Every material claim must name its source: detected host fact, catalog fact, computed estimate, benchmark result, or operator override.
2. **Compatibility is multidimensional.** “Fits in VRAM” does not mean “runs.” Runtime, compiler, instruction-set, operator, precision, tokenizer, and license compatibility must be evaluated independently.
3. **Uncertainty is data.** Unknown VRAM, ambiguous GPU variants, incomplete model metadata, and untested kernels must remain visible.
4. **No surprise mutations.** Inventory is read-only. Downloads, compilation, model execution, and system changes are separate approval gates.
5. **Legacy hosts are first-class.** The core survey must work in Windows PowerShell 5.1 on Windows 7 SP1 without requiring PowerShell 7, WSL, Python, Node.js, or a package manager.
6. **Modern extensions are optional.** Native helpers, Python model inspection, remote catalog refresh, and web presentation may improve results but cannot be required for the base survey.
7. **Reproducible results.** Reports include tool version, catalog version, exact command, timestamps, hashes, and applicable overrides.

## 4. User roles and approval policy

### Operator

The operator runs surveys and benchmarks and supplies any local model files. The operator must approve every exact model execution configuration.

### Catalog maintainer

The maintainer reviews compatibility entries and supporting sources. Catalog changes must be code-reviewable and must not be learned silently from arbitrary web pages.

### Required approval manifest

Before any model download, conversion, compilation, or execution, the tool must display and optionally write an approval manifest containing:

- Checkpoint repository and immutable revision or local file hash.
- Architecture and parameter count.
- License and any usage restrictions.
- Weight format and quantization.
- Runtime and immutable runtime revision.
- Accelerator device and execution-provider policy.
- Precision and accumulator type.
- Context length, batch size, and cache/state precision.
- Estimated RAM, VRAM, disk use, first-token latency, and tokens per second.
- Expected CPU-versus-GPU operator placement.
- Planned downloads, compilation, generated files, and cleanup behavior.
- Model role, such as code completion, CI diagnosis, diff review, or architecture-option generation.
- Reasoning/effort controls when the runtime exposes them.

The tool proceeds only when the operator passes the generated manifest identifier back using an explicit approval option. Approval of one manifest must not authorize a materially different configuration.

## 5. Compatibility classifications

Each model/runtime combination receives one of the following states. A model can have multiple rows when different runtimes produce different outcomes.

### `ready`

A prebuilt runtime supports the detected OS, device architecture, required operators, model format, and selected precision. The model fits within the configured safety margins. “Ready” must still be marked `unbenchmarked` until a local smoke test passes.

### `ready-after-conversion`

An existing compatible runtime is available and the only required work is a deterministic, supported weight conversion or quantization. The conversion tool, source format, destination format, expected disk usage, and validation procedure must be identified.

### `adaptable-small`

No ready path exists, but the change is bounded and does not alter the model mathematically. Examples include:

- Compiling an already compatible runtime for the detected compute target.
- Backporting build-system support while all required device operators already exist.
- Adding a documented quantized weight loader around existing kernels.
- Implementing a small number of simple missing operators with known reference tests.

The report must list every missing operator and build dependency. “Small” must not be assigned when the work requires a new compiler toolchain, replacing a numerical backend, training, or implementing an architecture's main compute path.

### `adaptable-research`

The model might be feasible, but substantial kernel, compiler, numerical-stability, format, or performance work is required. The tool must not describe this as “slight work.”

### `infeasible`

A hard constraint prevents the selected configuration: insufficient addressable memory, unavailable required precision/instructions with no valid emulation plan, unsupported operating system, incompatible license, or a performance floor below the operator's minimum.

### `unknown`

Available evidence is insufficient. Unknown must never be automatically promoted to `ready`.

## 6. Host inventory requirements

### 6.1 Operating system

Collect:

- Windows product name, edition, architecture, build, service pack, and installation type.
- PowerShell version and language mode.
- Whether the process is 32-bit or 64-bit.
- Available Windows APIs relevant to telemetry and process execution.
- Hypervisor/VM indicators and, when discoverable, whether the GPU is physical, virtual, partitioned, or passed through.

### 6.2 CPU and system memory

Collect:

- CPU vendor, family/model/stepping, core and logical-processor counts, base/current clock when available, and instruction sets relevant to fallback operators.
- Installed and currently available physical memory.
- Commit limit, current committed memory, page-file configuration, and memory pressure.
- Per-core utilization during benchmarks.
- Process architecture restrictions that might cap usable memory.

### 6.3 GPU inventory

For every adapter, collect:

- PnP/PCI hardware ID, subsystem ID, vendor/device ID, adapter name, driver version/date, and display attachment.
- VRAM from all available sources, with a source and confidence for each value.
- DirectX feature information where available.
- NVIDIA CUDA compute capability or AMD/Intel equivalent architecture identifier from a curated PCI/device catalog.
- Supported numerical capabilities: FP64, FP32, native or storage-only FP16/BF16, integer dot products, tensor/matrix instructions, atomics, and practical alignment restrictions.
- Published or measured memory bandwidth when available, labeled clearly as catalog or benchmark data.
- Current utilization, temperature, clocks, power state, throttle reasons, and free accelerator memory when vendor APIs expose them.

`Win32_VideoController.AdapterRAM` must not be treated as authoritative. The tool must reconcile WMI/CIM, registry, DirectX diagnostics, vendor utilities/APIs, and operator overrides. Conflicts remain visible in the report.

### 6.4 Installed compute and build stack

Detect without mutating the host:

- NVIDIA driver and CUDA driver API level.
- Installed CUDA toolkits, `nvcc` versions, supported target architectures, and available CUDA runtime DLLs.
- OpenCL platforms/devices and reported extensions.
- Vulkan loader/device/API version and compute support.
- DirectML/DirectX availability where applicable.
- Visual Studio/MSVC, Windows SDK, CMake, Ninja, Git, Python, and relevant runtimes.
- Candidate inference engines and their versions, including any locally configured custom engine.

The catalog must separately represent the newest toolkit that recognizes a device and the toolkit/runtime combinations that can actually compile and execute the required kernels.

### 6.5 Power and throttling

Collect when the platform exposes it:

- AC versus battery state.
- Charge percentage and estimated remaining time.
- Active Windows power scheme.
- CPU frequency relative to nominal frequency.
- GPU performance/power state and throttle reasons.
- Thermal indicators and recent benchmark clock stability.

The report must distinguish unavailable telemetry from an unthrottled state.

## 7. Model and runtime catalog

The catalog must be human-reviewable YAML or JSON stored in the repository and versioned with the tool.

### 7.1 Model entry

Each checkpoint entry should contain:

- Stable identifier, source repository, immutable revision, architecture, parameter count, and license.
- Intended capabilities and training-domain evidence, including the degree of code specialization.
- Layer count, hidden width, attention/KV dimensions, vocabulary, maximum trained context, and relevant architecture-specific state dimensions.
- Available weight formats and their verified hashes or upstream references.
- Numerical requirements and known precision hazards.
- Required operator set.
- Tokenizer type and runtime requirements.
- Known working runtimes and configurations.
- Quality/evaluation evidence relevant to the proposed worker role.
- Provenance URL and date checked for each externally maintained fact.

Initial catalog candidates should include at least:

- `codeparrot/codeparrot-small` (GPT-2-style, 110M, code-specialized).
- `microsoft/CodeGPT-small-py`.
- `RWKV/rwkv-4-world-169m`.
- A small RWKV instruction/chat checkpoint if a stable, licensed 169M-class checkpoint is verified.
- `Salesforce/codegen-350M-mono` as a larger legacy-transformer comparison.
- `Qwen/Qwen2.5-Coder-0.5B-Instruct` as a modern stretch comparison.
- Tiny non-code reference models used only to validate kernels.

### 7.2 Runtime entry

Each runtime entry should contain:

- Repository, immutable revision, license, supported host operating systems, and supported compilers.
- Model architectures and file formats.
- Accelerator backends and minimum/maximum supported device architectures.
- Operator placement rules and known CPU fallbacks.
- Supported weight, activation, cache/state, and accumulator precisions.
- Whether the runtime can enforce GPU placement for all major compute.
- Required patches, if any, maintained as separately reviewable adaptation recipes.
- Reproducible build and smoke-test commands.

### 7.3 Adaptation recipe

An adaptation recipe must define:

- Exact upstream revision.
- Target host and device constraints.
- Required source changes grouped by build, loader, operator, and telemetry work.
- Expected missing operators and numerical reference implementation.
- Test vectors and allowed error tolerances.
- Estimated engineering-risk class: low, medium, high, or research.
- License compatibility of the resulting binary and distributed patches.
- Exit criteria and rollback/cleanup procedure.

## 8. Feasibility calculations

All calculations must show their inputs and units. Binary units (`MiB`, `GiB`) are required for memory.

### 8.1 Weight storage

Estimate raw weight storage as:

```text
weight_bytes = parameter_count * effective_bits_per_weight / 8
```

Then add format-specific block scales, zero points, alignment, metadata, embeddings, and any tensors retained at higher precision. Catalog entries may override generic estimates with measured model-file and loaded-memory values.

### 8.2 Transformer cache

Estimate the KV cache using the checkpoint's layer count, context length, KV width or KV-head ratio, batch size, and selected storage precision. Do not assume standard multi-head attention when a model uses multi-query or grouped-query attention.

### 8.3 Recurrent state

For RWKV and other state-space/recurrent architectures, estimate architecture-specific persistent state separately from temporary activation buffers. The report should explicitly show that state does or does not grow with context.

### 8.4 Runtime buffers and safety margin

Include:

- Scratch/workspace buffers.
- Activations.
- Tokenizer and host-side model structures.
- Display reservation for a GPU driving the desktop.
- Driver/runtime allocation overhead.
- A configurable safety margin, defaulting conservatively when free device memory cannot be queried.

The result must report at least `optimistic`, `expected`, and `conservative` memory totals.

### 8.5 Performance estimate

Before measurement, label performance only as an estimate. Use architecture-aware calculations and, where appropriate, a measured device-memory/GEMV calibration rather than peak FLOPS alone. Report:

- Estimated and measured time to first token.
- Prompt-processing tokens per second.
- Generation tokens per second.
- GPU and CPU utilization.
- Host-to-device transfer volume per token.
- Power state and clock stability during the sample.
- Whether a CPU fallback dominates wall-clock time.

## 9. Survey and benchmark modes

### 9.1 `inventory`

Read-only host survey. Must require no administrator rights, native compilation, network, or model files.

Example:

```powershell
.\model-surveyor.ps1 inventory -OutputJson .\host.json
```

### 9.2 `recommend`

Compare a host report against the local catalog. This must not download or execute anything.

```powershell
.\model-surveyor.ps1 recommend -HostReport .\host.json -Role code -Policy .\gpu-required.json
```

### 9.3 `plan-adaptation`

Produce a gap analysis and adaptation manifest for one exact model/runtime/device combination.

```powershell
.\model-surveyor.ps1 plan-adaptation -Candidate codeparrot-small-cuda65-sm11
```

### 9.4 `microbenchmark`

Run approved, non-model operator and memory tests. Native compilation or execution must be described in an approval manifest first.

### 9.5 `validate-model`

Validate an operator-supplied local model against an approved manifest. Required checks include model hash, load success, major-operator placement, deterministic prompt fixtures where possible, memory high-water mark, and performance telemetry.

## 10. Policy input

Recommendations must honor an explicit policy file. Supported policy fields include:

- Required accelerator vendor/device.
- Whether CPU fallback is allowed and for which operators.
- Maximum RAM, VRAM, disk, and power use.
- Minimum generation and prompt-processing speeds.
- Maximum first-token latency.
- Maximum adaptation classification.
- Allowed licenses and model sources.
- Model roles and minimum quality evidence.
- Maximum context and desired working-context duration.
- Whether networking, downloads, compilation, conversion, or execution are permitted in the current invocation.

For the legacy GPU experiment, the policy must be able to require that embeddings, layer transforms, attention or recurrence, feed-forward transforms, and the output projection execute on the GPU. Tokenization and sampling may remain on the CPU.

## 11. Output requirements

### 11.1 Human-readable report

The console report must lead with:

- Detected constraints and uncertain facts.
- Ready candidates.
- Small-adaptation candidates.
- Research-only or infeasible candidates.
- The exact next evidence-gathering step.

Each recommendation must explain why it received its class and what would invalidate it.

The report must also include a host-task suitability section. It evaluates
CPU, GPU, RAM, storage, and network resources independently and classifies
candidate work as `cpu`, `gpu`, or `heterogeneous`. It must not discard a host
because either its CPU or GPU is weak for model inference when the other
resource, available memory, or build environment can perform useful compile,
conversion, validation, indexing, or coordination work.

### 11.2 JSON report

The JSON format must be versioned and stable. At minimum it contains:

```json
{
  "schemaVersion": 1,
  "toolVersion": "0.1.0",
  "catalogVersion": "2026-08-20",
  "surveyId": "...",
  "capturedAt": "...",
  "host": {},
  "devices": [],
  "power": {},
  "toolchains": [],
  "candidates": [
    {
      "modelId": "codeparrot-small",
      "runtimeId": "legacy-cuda-gpt2",
      "classification": "adaptable-research",
      "confidence": "medium",
      "role": "code",
      "memory": {},
      "operatorPlacement": [],
      "gaps": [],
      "adaptationRecipeId": "...",
      "evidence": []
    }
  ],
  "warnings": [],
  "approvalManifest": null
}
```

JSON timestamps use UTC ISO 8601. Byte values are integers. Display strings do not replace machine-readable numeric values.

### 11.3 Dashboard integration

The report must be ingestible by a future LAN collector and the `ci-pipeline-dashboard`. It should expose:

- Host identity and last-seen time.
- Survey/benchmark state and elapsed time.
- Assigned virtual PR/task identity.
- Candidate model/runtime/effort configuration.
- GPU and CPU utilization.
- RAM/VRAM pressure.
- Power source, throttling state, and estimated charge time remaining.
- Current approval gate and owner.
- Links or paths to logs, manifests, and benchmark results.

The survey tool must not require the dashboard to function.

## 12. Suggested architecture

```text
model-surveyor.ps1
  -> PowerShell 5.1 command router and read-only inventory
  -> platform collectors
       WMI/CIM, registry, PnP, dxdiag, vendor utilities
  -> normalized host report
  -> versioned compatibility catalog
  -> feasibility and policy evaluator
  -> approval-manifest generator
  -> optional native benchmark helper
  -> console + JSON renderers
```

Suggested repository layout:

```text
/model-surveyor.ps1
/src/ModelSurveyor.psm1
/src/Collectors/*.ps1
/src/Evaluation/*.ps1
/catalog/models/*.json
/catalog/runtimes/*.json
/catalog/devices/*.json
/catalog/recipes/*.json
/native/legacy-cuda/
/schemas/*.schema.json
/fixtures/
/tests/
/docs/
```

The first implementation should remain a PowerShell module plus data files. A native helper is justified only for operator probing and performance measurement that PowerShell cannot perform accurately.

## 13. Implementation phases

### Phase 1 — Read-only PowerShell MVP

- Windows 7 SP1 and PowerShell 5.1 compatible inventory.
- Multi-source GPU identity and VRAM reporting.
- CPU, memory, driver, toolkit, power, and compiler inventory.
- Offline device/model/runtime catalogs.
- Static memory estimates and classification.
- Console and versioned JSON output.
- No downloads, compilation, or model execution.

### Phase 2 — Evidence and catalog tooling

- JSON Schema validation.
- Catalog provenance validation and stale-entry warnings.
- Deterministic catalog refresh performed only by a maintainer command.
- Model-file metadata inspection when files are supplied locally.
- Approval-manifest creation and verification.

### Phase 3 — Native microbenchmarks

- Legacy-compatible memory-bandwidth and FP32 GEMV tests.
- Quantized-weight dequantize-plus-GEMV kernel test.
- Numerical comparison against CPU reference vectors.
- Telemetry sampling and throttle detection.

### Phase 4 — Model validation

- GPT-2-style reference executor suitable for a CUDA 6.5/`sm_11` experiment.
- RWKV-4 reference executor using constant recurrent state.
- Major-operator GPU-placement verification.
- Fixed code, CI-diagnosis, and structured-planning test fixtures.

### Phase 5 — LAN worker integration

- Signed or authenticated report submission to an external collector.
- Lease/assignment identity tied to a virtual PR or task.
- Heartbeat, elapsed-time, approval, and power/throttle reporting.
- No remote arbitrary-code execution as part of the survey protocol.

## 14. Acceptance criteria

### Base survey

- Runs from Windows PowerShell 5.1 on Windows 7 SP1, Windows 10, and Windows 11.
- Completes inventory without administrator access and without network access.
- Leaves the host unchanged except for explicitly requested report files and temporary files it removes.
- Produces schema-valid JSON and a readable summary.
- Reports conflicting VRAM sources instead of silently choosing one.
- Does not crash when vendor tools, batteries, thermals, or modern APIs are absent.

### Compatibility evaluation

- Does not classify a model as `ready` merely because weights fit in memory.
- Identifies unsupported GPU architectures and runtime CPU fallbacks.
- Shows weight, cache/state, scratch, display reservation, and safety-margin estimates independently.
- Identifies whether context-related memory grows linearly, quadratically in compute, or remains constant for the selected architecture.
- Associates every catalog fact with provenance and every estimate with its inputs.
- Requires explicit operator approval before any download, compilation, conversion, or execution.

### Legacy NVIDIA regression fixture

For a fixture representing a GeForce 8600 GT:

- The tool identifies the device as a legacy CUDA compute-capability 1.1-class target when the PCI identity is unambiguous.
- It does not advertise FP16, BF16, tensor-core, or modern integer-dot-product acceleration.
- It rejects current CUDA runtimes that do not target the device.
- It treats CUDA 6.5-era custom compilation as an adaptation path requiring verification, not as an automatically ready runtime.
- It evaluates GPT-2-style 110M and RWKV-4 169M quantized candidates separately and shows the transformer's KV-cache growth versus RWKV's fixed recurrent state.
- It flags any major CPU operator fallback when the policy requires GPU-major execution.

### Quality evaluation

A model is not promoted from hardware-compatible to role-qualified until it is tested on role-specific fixtures. The initial suite must measure:

- Valid structured-output rate.
- Top-k affected-file recall from an issue description.
- Compile/test success for constrained code repairs.
- CI-diagnosis agreement with reviewed answers.
- Defect recall and false-positive rate in diff review.
- Architecture-option constraint coverage; this is advisory and must not be represented as autonomous architectural authority.
- Tokens per second, time to first token, peak RAM/VRAM, per-core CPU utilization, GPU utilization, and power/throttle state.

## 15. Test strategy

- Pester tests for every PowerShell collector and evaluator.
- Golden JSON reports for Windows 7, 10, and 11 fixtures.
- Fixtures for missing WMI fields, truncated VRAM, multiple GPUs, remote sessions, VMs, and absent vendor utilities.
- Property tests around memory arithmetic, unit conversion, and integer overflow.
- Schema validation in CI.
- Catalog linting for missing provenance, mutable model revisions, and contradictory constraints.
- CPU reference vectors for every native GPU operator.
- Numerical tolerance tests across FP32 and supported quantized formats.
- A no-network/no-admin test lane.
- A mutation audit confirming that `inventory` and `recommend` create only requested output files.

## 16. Initial decision expected from the tool

On the target Athlon II/GeForce 8600 GT host, the first useful report should compare at least:

1. A GPT-2-style 110M code checkpoint using quantized weights with FP32 accumulation.
2. RWKV-4 World 169M using quantized weights with FP32 recurrent state and any layers that require higher precision.

The report must not pick the winner from architecture or parameter count alone. It should recommend an ordered benchmark plan based on exact VRAM, driver/toolkit availability, required kernel work, model-role evidence, and operator policy. The operator retains final approval over model, runtime, quantization, context, effort configuration, and assigned worker responsibility.

## 17. Definition of done

The project is ready for practical use when an operator can run one read-only command on a Windows 7+ host, copy the resulting JSON to another machine, and receive a reproducible shortlist separating:

- Models runnable immediately.
- Models needing deterministic conversion only.
- Models needing genuinely small adaptations.
- Research ports.
- Infeasible or unknown candidates.

Every shortlist entry must explain its memory budget, runtime/operator compatibility, likely performance, evidence, uncertainty, approval state, and exact next validation step.

