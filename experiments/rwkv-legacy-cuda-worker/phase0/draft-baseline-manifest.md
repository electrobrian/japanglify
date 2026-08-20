# Draft Baseline Manifest

**Status:** Draft only. No model execution is authorized. The manifest
identifier is intentionally not populated until every field is confirmed and
canonicalized.

This draft covers every field required by section 5.3 of
`experiments/rwkv-legacy-cuda-worker/REQUIREMENTS.md`.

| Field | Draft value / status |
|---|---|
| Model repository and immutable revision, or local file hashes | `[PENDING — requires Brian approval]` |
| Model architecture and exact parameter count | RWKV-4 World 169M-class, 12 layers, `d_model=768`, vocabulary `65536`; exact checkpoint parameter count `[PENDING — requires Brian approval]` |
| License and approved usage purpose | License `[PENDING — requires license review]`; purpose `[PENDING — requires Brian approval]` |
| Tokenizer identity and immutable revision | `[PENDING — requires Brian approval]` |
| Source and destination weight formats | Source checkpoint format `[PENDING — requires Brian approval]`; destination `.rwkvq` format `[PENDING — requires Brian approval]` |
| Quantization scheme, block size, scale representation, and tensors excluded from quantization | `[PENDING — requires Brian approval]` |
| Runtime source revision and applied patches | `[PENDING — requires Brian approval]` |
| Compiler, CUDA toolkit, driver, and target architecture | Compiler `[PENDING — requires physical inventory run]`; CUDA toolkit `[PENDING — requires physical inventory run]`; driver `[PENDING — requires physical inventory run]`; target architecture `sm_11` candidate, physical compatibility `[PENDING — requires physical inventory run]` |
| GPU PCI identity and usable VRAM estimate | `[PENDING — requires physical inventory run]` |
| Weight, state, activation, workspace, display, and safety memory budgets | Weight/state/activation/workspace `[PENDING — requires exact checkpoint and format]`; display and usable VRAM `[PENDING — requires physical inventory run]`; safety reserve `[PENDING — requires Brian approval]` |
| Accumulator, state, activation, and output-logit precision | Candidate FP32 for all four; final values `[PENDING — requires Brian approval]` |
| Maximum prompt chunk, recurrent-state policy, batch size, and output limit | `[PENDING — requires Brian approval]` |
| Expected CPU and GPU operator placement | GPU-major-required placement `[PENDING — requires Brian approval and operator plan]`; CPU orchestration/tokenization/sampling `[PENDING — requires Brian approval]` |
| Expected tokens per second and time to first token, marked estimated or measured | `[PENDING — requires physical benchmark]` |
| Worker role and enabled tools | `[PENDING — requires Brian approval]` |
| Download, build, execution, cleanup, and rollback actions | `[PENDING — requires Brian approval]` and license review before any download |
| Model reasoning/effort controls, if any | `[PENDING — requires Brian approval]` |
| Manifest identifier derived from canonical manifest contents | **NOT POPULATED — `[PENDING — requires all fields confirmed]`** |

## Gate notes

- Physical inventory must fill in OS/toolchain, PCI identity, driver, and VRAM
  evidence without changing the host.
- License review must complete before a checkpoint or tokenizer is downloaded
  or redistributed.
- Brian must approve the exact checkpoint, quantization format, memory plan,
  runtime revision, placement policy, worker role, tools, limits, and actions.
- Approval applies only to the final canonical manifest identifier.
