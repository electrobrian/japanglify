# RWKV Legacy CUDA Worker — Requirements

## 1. Project summary

Create a small, auditable RWKV inference and worker runtime capable of using legacy NVIDIA GPUs that are unsupported by contemporary machine-learning frameworks. The first physical target is a Windows 7-or-newer host with an Athlon II X2 B24 and a GeForce 8600 GT-class GPU.

The runtime is intended to make the GPU perform the model's major computation. It must not quietly degrade into a CPU inference engine. CPU use is acceptable for orchestration, tokenization, sampling, file I/O, networking, and other work that does not dominate inference time.

The first candidate checkpoint is RWKV-4 World 169M, using quantized weights and FP32 computation where required. This candidate is provisional: no checkpoint, quantization, context policy, runtime configuration, or worker role is authorized for execution until Brian approves an exact configuration manifest.

The project complements, but does not replace, the general-purpose host and model surveyor specified in `REQUIREMENTS.md`. The surveyor determines what might be feasible; this project implements and validates one RWKV execution path.

## 2. Goals

1. Run a useful RWKV-4-class model on a CUDA compute-capability 1.1-class NVIDIA GPU using a legacy-compatible CUDA toolchain.
2. Keep all major model operations on the GPU and make operator placement observable.
3. Use quantized weights to fit the model and working buffers within the actual VRAM budget.
4. Accumulate numerical work in FP32 because the target GPU lacks useful native FP16/BF16 acceleration.
5. Provide correctness evidence against a trusted modern reference implementation.
6. Measure real throughput, latency, utilization, memory pressure, power state, and throttling on the physical target.
7. Expose a constrained worker interface suitable for code-related experiments and future LAN orchestration.
8. Report worker state to `ci-pipeline-dashboard`, including elapsed time, responsible virtual PR/task, hardware health, and approval gates.
9. Support later model adaptation or fine-tuning performed on a separate capable machine, while keeping target-host inference reproducible.
10. Preserve Windows 7 compatibility for the deployed runtime and PowerShell management commands.

## 3. Non-goals

- Reimplement every RWKV generation or every model format.
- Provide a general-purpose replacement for PyTorch, llama.cpp, or rwkv.cpp.
- Train a 169M model on the Athlon II/GeForce 8600 GT host.
- Promise frontier-level coding or architectural reasoning from a small checkpoint.
- Permit arbitrary remote code execution through the worker protocol.
- Use CPU inference as the normal path when the GPU policy is enabled.
- Automatically download checkpoints, install drivers, install CUDA, change power plans, or approve model configurations.
- Hide numerical deviations, unsupported operators, CPU fallbacks, or estimated performance behind a single compatibility score.
- Ship model weights whose license or redistribution terms have not been reviewed.

## 4. Required target profiles

### 4.1 Primary legacy profile

- Windows 7 SP1 or newer, 64-bit preferred.
- Windows PowerShell 5.1 for management scripts.
- NVIDIA GeForce 8600 GT-class GPU identified by PCI hardware ID.
- CUDA compute-capability 1.1-class code generation.
- A verified driver and CUDA 6.5-era runtime/toolchain combination.
- 256 MiB, 512 MiB, and larger VRAM variants must be represented as separate tested profiles.
- The first Windows 10 host survey reports **256 MiB** through
  `Win32_VideoController.AdapterRAM` for the active GeForce 8600 GT and
  16 GiB of system RAM. The system RAM value is adequate for CPU-side
  verification and build work. Treat 256 MiB as the current conservative GPU
  planning limit until a display-safe direct allocation probe corroborates it;
  do not assume the previously suspected 512 MiB variant.
- Athlon II X2 B24-class CPU performance.
- The GPU may also drive the desktop; display memory reservation must be measured or conservatively budgeted.

The project must not assume the marketing name uniquely determines VRAM, memory bus, clock, driver compatibility, or board configuration.

The HP Compaq 6005 Pro's integrated Radeon HD 4200 was not enumerated by the
first survey. It may be disabled by firmware or unavailable through its current
driver configuration. It is not an assignable worker resource until a separate
approved BIOS/driver investigation makes it visible and measures the impact of
its shared-memory reservation on the Athlon.

The host also reports a TPM 1.2 device. A later worker may use it as an
optional machine-identity and sealed-secret store: for example, to protect a
mutually-authenticated LAN credential, sign inventory/benchmark reports, and
bind an approved model-manifest hash to the enrolled host. TPM 1.2 is not a
model-runtime sandbox, correctness oracle, or substitute for least-privilege
process isolation; no TPM integration is in the initial CUDA experiment.

### 4.2 Development/reference profile

A modern machine may be used for:

- Converting and quantizing checkpoints.
- Running the trusted reference implementation.
- Producing test vectors.
- Training or fine-tuning candidate models.
- Cross-compiling where licensing and the legacy toolchain allow it.
- CI checks that do not claim to replace physical-device validation.

### 4.3 Additional hosts

The architecture should allow later CUDA devices and CPU reference execution, but no generalization may compromise the initial `sm_11` implementation or obscure actual operator placement.

### 4.4 Heterogeneous use of the target host

The GeForce and Athlon are independently schedulable resources. The host must
not be rejected merely because one device is unsuitable for a particular
model. The surveyor and future scheduler should consider the Athlon and its
substantial system RAM for:

- CPU-compatible model inference when a specific CPU configuration is
  separately approved.
- Compilation and link jobs whose working sets fit the host.
- Deterministic checkpoint conversion, packing, hashing, compression, and
  artifact verification when measured completion time is acceptable.
- CPU reference operators and numerical comparison against GPU results.
- Tokenization, dataset preprocessing, evaluation scoring, and test-fixture
  generation.
- Repository indexing, static analysis, CI-log processing, orchestration,
  telemetry collection, and dashboard/worker supervision.
- A deliberately small, serialized Android VM used as an end-to-end Japanglify
  tester (APK install, share-target, accessibility/chip, and output checks).
  This is a validation-host assignment, not a model workload: it must reserve
  sufficient RAM for Windows, use no more than one guest at a time, and never
  run concurrently with GPU experiments or significant compilation work.

Similarly, the GPU may be assigned a standalone numeric or model workload
that does not use the Athlon heavily. Each assignment must state whether it is
`cpu`, `gpu`, or `heterogeneous`, identify which resource is expected to be
the bottleneck, and report per-resource elapsed time and utilization. The
`gpu-major-required` policy remains available for experiments intended to
prove that RWKV's major model computation truly executes on the legacy GPU;
it is not a blanket prohibition against useful CPU work on the host.

## 5. Approval and mutation policy

### 5.1 Read-only actions

The following may run without a model-execution approval:

- Hardware and software inventory.
- Reading locally supplied configuration and catalog files.
- Static memory calculations.
- Inspecting locally supplied model metadata without executing the model.
- Generating an approval manifest.

### 5.2 Separately approved actions

Each of these requires an explicit manifest and approval:

- Downloading any checkpoint, tokenizer, toolchain, runtime dependency, or source archive.
- Compiling or executing native CUDA code on a target host.
- Converting or quantizing checkpoint data.
- Executing a model.
- Binding a worker listener to the LAN.
- Changing a Windows power plan, GPU clock, driver, service, firewall rule, or startup behavior.
- Fine-tuning or modifying model weights.

### 5.3 Exact model execution manifest

The manifest must contain:

- Model repository and immutable revision, or local file hashes.
- Model architecture and exact parameter count.
- License and approved usage purpose.
- Tokenizer identity and immutable revision.
- Source and destination weight formats.
- Quantization scheme, block size, scale representation, and tensors excluded from quantization.
- Runtime source revision and applied patches.
- Compiler, CUDA toolkit, driver, and target architecture.
- GPU PCI identity and usable VRAM estimate.
- Weight, state, activation, workspace, display, and safety memory budgets.
- Accumulator, state, activation, and output-logit precision.
- Maximum prompt chunk, recurrent-state policy, batch size, and output limit.
- Expected CPU and GPU operator placement.
- Expected tokens per second and time to first token, marked estimated or measured.
- Worker role and enabled tools.
- Download, build, execution, cleanup, and rollback actions.
- Model reasoning/effort controls if any exist.
- Manifest identifier derived from the canonical manifest contents.

Approval applies only to the exact manifest identifier.

## 6. Initial checkpoint strategy

### 6.1 Baseline candidate

The first model to evaluate is the verified 169M-class RWKV-4 World checkpoint because it offers:

- A small enough parameter count for aggressive quantization on a low-VRAM device.
- Fixed-size recurrent state rather than a transformer KV cache that grows with context.
- Some code in its training mixture.
- A sufficiently simple inference graph to make a purpose-built runtime plausible.

The baseline must not be described as instruction-tuned unless the selected immutable checkpoint actually is. Prompt format and expected behavior must come from the selected checkpoint's evidence, not another model in the family.

### 6.2 Candidate variants

The project must evaluate at least:

- FP32 reference weights on the development host.
- Q8 weight storage with FP32 accumulation.
- Q5 weight storage with FP32 accumulation, if a validated format is implemented.
- Q4 weight storage with FP32 accumulation.
- A mixed-precision layout retaining numerically sensitive tensors at FP32 when required.

The target-host choice is based on measured correctness and memory/performance, not smallest file size alone.

### 6.3 Later adapted checkpoints

Later experiments may use a model adapted on a separate training machine for:

- CI-log diagnosis.
- Affected-file ranking.
- Constrained patch planning.
- Diff-review observations.
- Structured architecture-option generation.
- Project-history summarization.

Fine-tuned weights are a new model configuration and require a new manifest and evaluation. Fine-tuning may not be used to bypass license requirements or conceal quality regressions.

## 7. Model quality boundary

Hardware success and model-role success are separate gates.

The runtime may claim:

- `kernel-correct` after operator parity tests pass.
- `model-runs` after end-to-end inference passes.
- `performance-qualified` after the physical host meets approved performance floors.
- `role-qualified:<role>` only after role-specific evaluations pass.

It must never infer architectural authority from parameter count, successful inference, or fluent output. A 169M model should initially be treated as a constrained assistant that produces candidates for review.

## 8. System architecture

```text
PowerShell management CLI
  -> host/config/approval validation
  -> worker supervisor
       -> tokenizer
       -> native RWKV runtime DLL or executable
            -> model container loader
            -> GPU memory planner
            -> legacy CUDA kernels
            -> recurrent state manager
            -> logits/output interface
       -> sampler and structured-output validator
       -> task sandbox/tool adapter
       -> telemetry and event journal
  -> JSON status stream
  -> optional authenticated LAN collector client
```

### 8.1 Process isolation

The model runtime should execute in a dedicated child process. A failed kernel, driver reset, corrupt model, or out-of-memory condition must not corrupt the worker supervisor's journal or assignment state.

### 8.2 Native interface

The native process or library must expose a narrow versioned interface for:

- Runtime version and supported container versions.
- Device enumeration.
- Model metadata inspection.
- Memory-plan calculation without loading.
- Load/unload.
- Initialize, import, export, and clear recurrent state.
- Prompt ingestion.
- One-token and bounded multi-token generation.
- Logit or top-k retrieval for validation.
- Cancellation.
- Per-operation timing and placement telemetry.
- High-water memory reporting.

### 8.3 Management CLI

The Windows PowerShell 5.1-compatible CLI must support:

```powershell
.\rwkv-worker.ps1 inventory
.\rwkv-worker.ps1 plan -Configuration .\candidate.json
.\rwkv-worker.ps1 build -Manifest .\approved-manifest.json -ApprovalId <id>
.\rwkv-worker.ps1 verify-kernels -Manifest .\approved-manifest.json -ApprovalId <id>
.\rwkv-worker.ps1 benchmark -Manifest .\approved-manifest.json -ApprovalId <id>
.\rwkv-worker.ps1 run -Manifest .\approved-manifest.json -ApprovalId <id>
.\rwkv-worker.ps1 status -OutputJson .\status.json
```

`inventory` and `plan` are read-only. Other commands enforce the manifest gate.

## 9. Model container and conversion

### 9.1 Container goals

Define a minimal versioned container, tentatively `.rwkvq`, optimized for deterministic loading on the legacy runtime. It must contain:

- Magic, container version, endianness, architecture identifier, and tensor count.
- Model dimensions and tokenizer reference/hash.
- Tensor names, shapes, logical types, storage types, offsets, lengths, alignment, and hashes.
- Quantization parameters per tensor/block.
- Explicit precision exceptions.
- Source checkpoint revision and conversion tool revision.
- License/reference metadata without embedding mutable web content.
- Whole-file integrity hash recorded externally in the approval manifest.

### 9.2 Converter

The converter may require Python and modern libraries on the development host. It must not be required on the Windows 7 inference host.

The converter must:

- Accept only explicitly supported RWKV-4 tensor layouts.
- Reject missing, extra, transposed, or ambiguously named tensors.
- Provide deterministic output for a fixed input and configuration.
- Quantize per the selected documented format.
- Preserve designated sensitive tensors at FP32.
- Emit a tensor-by-tensor conversion report.
- Generate reference fixtures before discarding or moving source data.
- Verify hashes and reopen the completed container.

### 9.3 Quantization formats

Every implemented Q4/Q5/Q8 format must document:

- Block size.
- Packing order.
- Signed/unsigned code interpretation.
- Scale and optional zero-point type.
- Dequantization equation.
- Alignment and padding.
- Reference encoder/decoder.
- Kernel tolerance and end-to-end model tolerance.

Formats should be compatible with an established format when doing so does not impose unsupported runtime dependencies. Similar names must not imply binary compatibility.

## 10. GPU execution requirements

### 10.1 Placement policy

When `gpu-major-required` is selected, the following operations must execute on the GPU:

- Embedding lookup or equivalent GPU-resident input transformation.
- Layer normalization used in every block.
- All major weight matrix-vector products.
- RWKV time-mixing transformations.
- WKV recurrent update.
- Channel-mixing transformations and nonlinearities.
- Residual updates.
- Final normalization.
- Output projection to logits.

Tokenization, sampling from returned logits/top-k values, task orchestration, and network I/O may execute on the CPU.

No unsupported GPU operator may silently fall back. The runtime must either fail the approved placement policy or report a separately approved fallback.

### 10.2 Legacy CUDA constraints

The implementation must assume the primary GPU lacks:

- Native FP16/BF16 arithmetic useful to this workload.
- Tensor cores.
- Modern integer dot-product instructions.
- Unified memory features expected by modern frameworks.
- Support in current CUDA toolkits and current ML framework binaries.

Consequently, quantized weights primarily reduce storage and bandwidth. Kernels dequantize values and accumulate in FP32 unless a separately validated approach is approved.

### 10.3 Initial kernel set

Implement and independently validate:

- Quantized matrix-vector multiply for each approved weight format.
- FP32 matrix-vector multiply for reference/sensitive tensors.
- Embedding gather.
- Layer normalization.
- Elementwise add, multiply, sigmoid, exponential, and squared-ReLU operations required by the exact RWKV-4 graph.
- RWKV-4 time-mix and channel-mix operations.
- Numerically stable WKV recurrent update.
- Final logits projection.
- Reductions required for normalization, diagnostics, and optional top-k extraction.

The exact graph and equations must be transcribed from one pinned reference implementation and covered by generated reference vectors. “Equivalent-looking” equations are not sufficient.

### 10.4 Kernel implementation strategy

- Target `sm_11` explicitly.
- Avoid language, intrinsic, atomic, warp, or memory features unavailable on the target.
- Prefer coalesced sequential reads and persistent weight residency.
- Optimize batch-one matrix-vector performance rather than large-batch matrix multiplication.
- Minimize host/device transfers per token.
- Avoid repeated device allocation in the token loop.
- Use double-buffering or streams only after correctness and measured benefit are established.
- Provide a simple correctness kernel path before specialized kernels.
- Keep tunable launch parameters in a device profile rather than hard-coding one board configuration.

### 10.5 CPU budget

The target CPU is weak. The runtime must measure CPU time by category and fail performance qualification if tokenization, sampling, synchronization, logging, or a fallback operator dominates generation.

## 11. Memory planning

The runtime must generate a memory plan before loading the model.

### 11.1 Required categories

- Quantized and FP32 weight tensors.
- Recurrent state.
- Current-layer activations.
- Normalization and reduction scratch.
- Logits or top-k buffers.
- Runtime/driver overhead.
- Display reservation.
- Alignment/fragmentation allowance.
- Configurable safety reserve.

### 11.2 Residency modes

Evaluate:

1. **Fully resident:** all model weights remain in VRAM.
2. **Mostly resident:** a small explicitly identified tensor set streams from pinned host memory.
3. **Layer streamed:** used only as a research comparison because PCIe transfers per token may make it impractical.

The deployed default should be fully resident when possible. A streamed configuration is not equivalent to a fully GPU-resident configuration and requires separate approval and performance qualification.

### 11.3 VRAM uncertainty

Before a physical run, reconcile VRAM from PCI identity, WMI, registry, DirectX/vendor tooling, allocation probes, and operator-provided evidence. The allocation test must leave a display-safe margin and must not intentionally trigger a desktop driver reset.

## 12. Recurrent state and long-running context

### 12.1 State operations

The runtime must support:

- Fresh zero/default state.
- Deterministic state export and import.
- State hash and metadata.
- State association with model/container hash.
- State expiration and deletion policy.
- Cancellation without committing partial state unless explicitly requested.
- Optional checkpoints during long task ingestion.

### 12.2 Context semantics

RWKV's fixed-size recurrent state avoids a growing KV allocation, but it does not guarantee perfect recall or unlimited useful context. Reports must distinguish memory constancy from behavioral retention quality.

### 12.3 Task state isolation

Each virtual PR/task receives a separate state lineage. State from unrelated repositories, users, or tasks must not leak into another task. A task journal records the source inputs summarized into each state checkpoint.

## 13. Tokenization and sampling

- Use the tokenizer that belongs to the approved checkpoint revision.
- Validate token IDs for fixed multilingual, source-code, punctuation, whitespace, and binary-edge-case fixtures.
- Preserve code indentation and line endings as required by the worker protocol.
- Make temperature, top-k, top-p, repetition controls, seed, and maximum output explicit configuration fields.
- Provide deterministic greedy sampling for regression tests.
- Keep sampling on CPU initially unless measurements show it is a material bottleneck.
- Reject invalid or non-finite logits rather than sampling silently.

## 14. Correctness validation

### 14.1 Reference implementation

Pin one trusted modern RWKV-4 implementation and checkpoint revision. Generate fixtures on the development host containing:

- Input tokens.
- Initial recurrent state.
- Selected intermediate tensors for each block.
- Updated recurrent state.
- Final logits or selected logit slices.
- Expected generated tokens under deterministic sampling.

### 14.2 Validation levels

1. Container parsing and tensor hash validation.
2. Quantize/dequantize error analysis by tensor.
3. Individual operator parity.
4. Single RWKV block parity.
5. Full forward-token parity.
6. Multi-token recurrent-state parity.
7. State export/import parity.
8. End-to-end deterministic generation.

### 14.3 Numerical policy

Tolerance thresholds must be defined from measured reference distributions. The project must not use one arbitrary global epsilon for all tensors. Report maximum absolute error, relative error where meaningful, cosine similarity for large vectors, top-k logit agreement, and generated-token divergence.

Numerical instability, overflow, NaN, or Inf is a blocking failure. Precision exceptions required by the checkpoint must remain visible in the manifest and memory plan.

## 15. Performance and power validation

### 15.1 Required measurements

- Model load time.
- Time to ingest the first prompt token and a sustained prompt stream.
- Time to first generated token.
- Generation tokens per second over defined lengths.
- Per-kernel and per-layer timing.
- CPU time and utilization per core.
- GPU utilization if available.
- Peak system RAM and VRAM.
- Host/device bytes transferred per token.
- GPU and CPU clocks during the run.
- AC/battery state, charge estimate, temperature, power state, and throttle reasons when available.
- Driver errors, recoveries, or device resets.

### 15.2 Benchmark profiles

- Empty/fresh state, one-token generation.
- Short code prompt.
- Long incrementally ingested CI log.
- Reused state with a short follow-up.
- Fixed 32-, 128-, and 512-token generation where the model remains behaviorally valid.
- Concurrent supervisor/dashboard activity.

### 15.3 Qualification floor

No default speed floor is assumed in this requirements document. The first physical characterization establishes achievable performance. Brian approves the minimum useful performance for each proposed worker role afterward.

## 16. Role evaluations

### 16.1 Initial roles

Evaluate, independently:

- `ci-log-classifier`: categorize failure and identify likely next diagnostic.
- `affected-file-ranker`: rank repository files relevant to a bounded issue.
- `patch-plan-generator`: produce constrained JSON steps, not an unreviewed patch.
- `diff-review-observer`: flag possible defects with file/line evidence.
- `architecture-option-generator`: enumerate options, constraints, and tradeoffs for stronger review.
- `project-history-summarizer`: maintain a stateful concise task timeline.

### 16.2 Metrics

- Structured-output schema validity.
- Task completion rate.
- Top-k file recall.
- Diagnostic agreement with reviewed answers.
- Defect recall and false-positive rate.
- Constraint coverage in architecture options.
- Hallucinated file/API/reference rate.
- Reproducibility across fixed seeds.
- Human acceptance/rejection outcome.
- Latency, throughput, power, and resource cost per accepted result.

### 16.3 Promotion policy

A role begins in `observe-only`. Promotion stages are:

1. `observe-only`
2. `suggest-with-review`
3. `bounded-action-with-review`
4. `bounded-routine-action`

Promotion requires Brian's explicit approval and durable benchmark evidence. The small local model may never approve its own promotion, model change, worker permissions, or output.

## 17. Worker and virtual PR protocol

### 17.1 Responsibility model

Every active inference or tool task must have a virtual PR/task envelope identifying:

- Repository and optional real PR/issue.
- Virtual task identifier.
- Parent task and child attempt.
- Assigned host and worker instance.
- Model manifest identifier.
- Responsible orchestrator and approval owner.
- Scope and acceptance criteria.
- Start time, elapsed time, current phase, and heartbeat.
- Inputs, generated artifacts, findings, and final disposition.

Idle pool workers and system-level inventory processes may exist outside a virtual PR, but any substantive model work may not.

### 17.2 Worker states

- `idle`
- `assigned`
- `awaiting-configuration-approval`
- `preparing`
- `loading-model`
- `ingesting-context`
- `generating`
- `validating-output`
- `awaiting-review`
- `completed`
- `cancelled`
- `blocked`
- `failed`

Every transition is journaled with UTC time and a reason.

### 17.3 Tool access

The first worker release has no arbitrary shell tool. Inputs are bounded text or approved repository snapshots, and outputs are suggestions or structured records. Later tools must be individually allowlisted and sandboxed.

## 18. Dashboard and telemetry integration

### 18.1 Local output

The supervisor emits atomic JSON snapshots and an append-only JSON Lines event stream. Console display is optional; files are authoritative for integration.

Required fields include:

```json
{
  "schemaVersion": 1,
  "workerId": "host/instance",
  "hostId": "...",
  "taskId": "virtual-pr/...",
  "parentTaskId": null,
  "state": "generating",
  "stateSince": "...",
  "startedAt": "...",
  "elapsedMs": 0,
  "modelManifestId": "...",
  "modelRole": "ci-log-classifier",
  "progress": {},
  "resources": {
    "cpuPerCorePercent": [],
    "memoryUsedBytes": 0,
    "memoryAvailableBytes": 0,
    "gpuUtilizationPercent": null,
    "vramUsedBytes": null,
    "vramAvailableBytes": null
  },
  "power": {
    "source": "unknown",
    "chargePercent": null,
    "estimatedSecondsRemaining": null,
    "powerScheme": null,
    "cpuFrequencyRatio": null,
    "gpuPerformanceState": null,
    "throttleReasons": []
  },
  "operatorPlacement": {},
  "approval": {},
  "warnings": [],
  "lastHeartbeat": "..."
}
```

Unknown telemetry is `null` or explicitly unavailable, never falsely reported as zero or unthrottled.

### 18.2 LAN integration

The preferred first network design is an outbound worker heartbeat to a collector rather than an unauthenticated inbound control port. Network support must include:

- Explicit opt-in.
- Host and worker identity.
- Authentication suitable for the LAN threat model.
- Replay-resistant assignments.
- Bounded payload sizes.
- No model prompts or source code in telemetry unless policy explicitly permits them.
- Offline queueing and reconnect behavior.
- Cancellation and lease expiration.
- Compatibility with Windows 7 TLS limitations through an approved secure strategy rather than disabling certificate validation.

## 19. Failure handling

- Cancel between tokens and at documented safe kernel boundaries.
- Preserve the last committed recurrent state separately from in-progress state.
- On CUDA error, stop using the device until a health check passes.
- On out-of-memory, do not automatically choose a smaller or different model configuration; return to an approval gate with a revised plan.
- On driver reset, record relevant Windows events when readable and fail the attempt.
- On invalid output, retain bounded diagnostics without leaking unrelated task data.
- On supervisor restart, recover journal state but do not resume model execution without validating the manifest, model hash, and assignment lease.
- Never silently switch to CPU inference.

## 20. Security and privacy

- Run as a standard user by default.
- Validate model/container sizes, offsets, shapes, and integer arithmetic before allocation.
- Treat model files, tokenizers, task prompts, and LAN messages as untrusted inputs.
- Use bounded allocations and output limits.
- Store secrets outside repository and report files.
- Redact tokens, credentials, private URLs, and sensitive source fragments from telemetry.
- Bind any diagnostic server to localhost unless LAN access is explicitly approved.
- Sign or hash released binaries and model containers.
- Maintain dependency and source provenance for the legacy toolchain.
- Document the security limitations of running an obsolete operating system and driver stack.

## 21. Repository structure

```text
/REQUIREMENTS.md
/README.md
/LICENSES/
/docs/
  architecture.md
  toolchain.md
  model-format.md
  numerical-validation.md
  worker-protocol.md
  threat-model.md
/powershell/
  rwkv-worker.ps1
  RwkvWorker.psm1
/native/
  include/
  src/
  cuda/
  tests/
/converter/
/catalog/
  devices/
  models/
  toolchains/
/schemas/
/fixtures/
  operators/
  models/
  roles/
/tests/
/benchmarks/
/reports/
```

Generated weights, private prompts, toolchain installers, build outputs, and secrets must not be committed.

## 22. Build and toolchain requirements

- Pin all source revisions and record file hashes for externally archived legacy dependencies.
- Document a legally redistributable or operator-supplied path for CUDA 6.5-era components.
- Provide a clean-build procedure for the selected Windows compiler.
- Avoid runtime dependencies unavailable on Windows 7.
- Avoid requiring C++ language/runtime features unsupported by the selected compiler.
- Generate explicit `sm_11` device code and verify the resulting binary contains the intended target.
- Treat compiler warnings affecting numerical behavior, alignment, or host/device ABI as errors.
- Produce a build manifest with compiler versions, flags, source revision, and binary hashes.
- Keep modern development tooling outside the deployed binary's dependency chain.

Physical `sm_11` execution is required for release qualification. Successful compilation or execution on a modern GPU is not sufficient evidence.

## 23. Testing strategy

### 23.1 Management layer

- Pester tests compatible with Windows PowerShell 5.1.
- Approval-manifest canonicalization and mismatch tests.
- No-network and no-admin tests.
- Atomic status-file and event-journal recovery tests.
- Power/telemetry unavailable-data tests.

### 23.2 Native runtime

- Host-side unit tests for file parsing, bounds checking, memory planning, and tokenizer interfaces.
- CUDA operator reference tests on the physical target.
- Corrupt/truncated container tests.
- Deliberate insufficient-memory tests that avoid destabilizing the display driver.
- Cancellation and process-crash recovery tests.
- Repeated load/unload and long-generation stability tests.

### 23.3 Model tests

- FP32 reference parity on the development host.
- Quantized CPU decode parity for container validation only.
- Physical GPU parity at every validation level.
- Multilingual and source-code tokenizer fixtures.
- Recurrent state save/restore tests across process restarts.
- Fixed-seed regression generation.

### 23.4 Performance tests

- Cold and warm load.
- Fresh and reused recurrent state.
- Short and long prompt ingestion.
- Generation under idle and ordinary desktop load.
- AC, balanced/power-saving, and battery conditions where the host supports them and the operator approves the test.
- Thermal soak sufficient to observe clock or throughput degradation.

## 24. Delivery phases and gates

### Phase 0 — Confirm the physical target

Deliver:

- Read-only host report.
- Exact GPU PCI identity and reconciled VRAM.
- Driver/toolkit/build-tool inventory.
- Display reservation and safe allocation estimate.
- Draft baseline manifest.

Gate: Brian approves the precise target and baseline experiment.

### Phase 1 — Format and reference fixtures

Deliver:

- Pinned checkpoint/reference implementation proposal.
- `.rwkvq` specification.
- Deterministic converter.
- FP32 and quantized fixtures.
- Memory plans for Q8/Q5/Q4 variants.

Gate: conversion correctness and license review.

### Phase 2 — Legacy CUDA operator runtime

Deliver:

- `sm_11` build.
- Simple correctness versions of all required operators.
- Operator placement/timing instrumentation.
- Physical-device numerical report.

Gate: every operator passes and no major CPU fallback exists.

### Phase 3 — End-to-end inference

Deliver:

- Model loader and recurrent state manager.
- Deterministic generation.
- End-to-end correctness report.
- Memory and stability report.

Gate: `model-runs` qualification.

### Phase 4 — Performance work

Deliver:

- Batch-one quantized GEMV tuning.
- Transfer and synchronization reduction.
- Sustained thermal/power benchmarks.
- Recommended target configuration or a documented infeasibility result.

Gate: Brian sets and approves the useful-performance floor.

### Phase 5 — Worker integration

Deliver:

- Task envelope and state journal.
- Structured output validation.
- Dashboard JSON and heartbeat.
- Observe-only role evaluations.

Gate: explicit approval for each promoted role and any LAN connectivity.

### Phase 6 — Model adaptation

Deliver, if justified:

- Curated and licensed training/evaluation data specification.
- Fine-tuning method on a separate capable host.
- Immutable adapted checkpoint.
- Comparison against the base checkpoint.
- Updated manifest and role qualifications.

Gate: Brian approves the adapted model and exact deployed configuration.

## 25. Acceptance criteria

The initial runtime milestone is complete only when:

- The native executable runs on the actual Windows 7+ legacy host.
- The physical GPU is identified unambiguously and the binary targets the correct architecture.
- The approved RWKV-4 169M-class container fits with a documented display and safety reserve, or the project reports honestly that it does not.
- Every major operation executes on the GPU under `gpu-major-required` policy.
- Quantized kernels accumulate in FP32 and meet documented numerical tolerances.
- A fixed multi-token fixture matches the reference to the approved tolerance and deterministic token criteria.
- Recurrent state can be exported, imported, isolated by task, and reproduced.
- Peak RAM/VRAM, per-core CPU usage, GPU activity, latency, throughput, power state, throttle state, and elapsed time are recorded.
- The supervisor survives native runtime failure and never silently switches to CPU.
- No download, compilation, model execution, power change, or LAN exposure occurs without its required approval.
- The dashboard can associate every substantive run with one responsible virtual PR/task and exact model manifest.

The worker milestone is complete only when at least one bounded role passes its reviewed quality threshold and Brian explicitly promotes that model/configuration/role combination beyond observe-only.

## 26. Initial decisions reserved for approval

The requirements intentionally do not decide the following:

- Exact RWKV checkpoint revision.
- Whether the baseline is the World base model or a verified instruction-tuned 169M-class alternative.
- Q4, Q5, Q8, or mixed weight storage.
- Tensor-specific FP32 exceptions.
- Maximum prompt ingestion and generated-token limits.
- Sampling configuration.
- Minimum useful tokens per second.
- First approved worker role.
- Fine-tuning dataset and method.
- LAN protocol activation.
- Any model/provider/effort configuration used to review or operate the project.

These are presented as exact alternatives with evidence after Phase 0 and require Brian's final approval.

## 27. Definition of done

The project succeeds if it produces one of two honest, reproducible outcomes:

1. A numerically validated, GPU-major RWKV worker that runs a specifically approved small checkpoint on the legacy NVIDIA host, reports its state and resources, and demonstrates at least one useful bounded role; or
2. A conclusive physical-device report identifying the hard correctness, memory, driver, or performance constraint that makes the proposed configuration impractical, together with the smallest credible next hardware or software change.

Merely loading some weights, producing text through CPU fallback, or compiling nominal `sm_11` code does not satisfy the project.

