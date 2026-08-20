# Hypothesis Swarm and Audit Ledger Requirements

Status: initial requirements draft

Initial deployment: private GitHub repository

First client: Japanglify development workflow
Portability target: repository/account-independent and storage-backend-independent

## 1. Project summary

Build a project-agnostic coordination system for multiple development agents that
investigate defects through explicit hypotheses, evidence, decisions, patches,
and independent verification. The system must provide a durable, replayable,
tamper-evident audit trail without replacing the GitHub workflow that humans
already understand.

GitHub is the initial live system of record wherever a native GitHub object
already expresses the event: issues, comments, reactions, pull requests,
reviews, check runs, workflow runs, artifacts, releases, commits, and Project
field changes. The separate ledger normalizes and links those events, preserves
their provenance and integrity, adds swarm-specific events, and derives a live
knowledge graph.

The initial ledger repository is private. Its owner, repository name, default
branch, and authentication method are configuration, never hard-coded. Moving
the ledger to another GitHub account or to a future LAN collector must preserve
event identifiers, hashes, signatures, source references, and replay results.

## 2. Goals

1. Let specialized agents investigate the same task concurrently without
   losing responsibility, provenance, or human visibility.
2. Represent observations, hypotheses, evidence, contradictions, decisions,
   approvals, patches, validation, and outcomes as durable events.
3. Keep native GitHub activity visible and authoritative rather than hiding
   workflow state in a proprietary dashboard or opaque agent transcript.
4. Reconstruct the current knowledge graph deterministically from immutable
   events.
5. Associate every substantive worker action with a virtual task/PR envelope,
   exact worker configuration, source revision, and approval scope.
6. Separate reproduction, root-cause analysis, fix synthesis, and verification
   so a patch author does not silently certify its own work.
7. Feed privacy-bounded tester and CI outcomes back into future investigations.
8. Provide a stable event/storage interface that can later use a LAN service,
   object store, or database without changing worker semantics.

## 3. Non-goals

- Storing private chain-of-thought, hidden reasoning traces, or model internals.
- Capturing raw prompts, source selections, screenshots, clipboard contents, or
  user text by default.
- Replacing GitHub Issues, Pull Requests, Actions, Projects, or Releases.
- Letting confidence scores substitute for evidence or acceptance criteria.
- Allowing agents to approve their own model configuration, permissions,
  sensitive actions, patches, releases, or production promotion.
- Providing unrestricted remote shell execution.
- Treating an append-only Git history alone as sufficient cryptographic proof.
- Automatically training models from ledger contents.

## 4. Design principles

1. **GitHub-native first.** If GitHub already owns a fact, reference and verify
   that native object instead of inventing a parallel status.
2. **Events are immutable.** Corrections append a superseding event; they never
   rewrite an accepted event.
3. **Evidence precedes conclusions.** A hypothesis records falsification
   criteria and evidence links before it can become confirmed.
4. **Uncertainty is explicit.** Unknown, unavailable, contradictory, stale, and
   inferred states are distinct.
5. **Views are disposable.** Knowledge graphs, dashboards, summaries, and
   indexes are projections rebuilt from the event stream.
6. **Least disclosure.** Store structured summaries and content hashes; keep
   sensitive bodies in their authorized source system.
7. **Least authority.** A worker receives only the repository, branch, tools,
   secrets, network access, and event permissions required for its assignment.
8. **No invisible fallback.** A failed webhook, signature, check, test, or
   approval lookup remains visible and cannot silently become success.
9. **Portable identity.** Repository locations may change; stable event and
   actor identifiers must not.
10. **Human decisions remain human.** The ledger records and scopes approval; it
    does not manufacture it.

## 5. Actors and roles

### 5.1 Human authority

The configured human authority owns issue acceptance, model/provider/effort
approval, expanded permissions, non-routine changes, release promotion, and any
override of a failed gate. A deployment may configure multiple humans and
threshold policies later; the MVP supports one explicit authority.

### 5.2 Coordinator

The coordinator:

- Creates the virtual task envelope.
- Proposes worker assignments and concurrency slots.
- Prevents overlapping write scopes.
- Connects native GitHub events to ledger events.
- Detects stalled, contradicted, duplicated, or superseded work.
- Chooses no model/provider/effort configuration without the configured human
  approval when policy requires it.

### 5.3 Reproducer

Produces deterministic reproduction steps, environment facts, affected-build
boundaries, fixtures, and a failing test when practical. It does not implement
the product fix unless explicitly reassigned under a new event.

### 5.4 Root-cause analyzer

Inspects code, logs, traces, state transitions, concurrency, data integrity, and
security boundaries. It proposes and attempts to falsify competing hypotheses.

### 5.5 Fix synthesizer

Implements the smallest approved patch consistent with confirmed evidence and
acceptance criteria. It works in an isolated branch/worktree and emits patch,
test, and provenance events.

### 5.6 Diff verifier

Independently reviews the patch, changed behavior, tests, security properties,
and scope. By default it must not be the same worker instance that synthesized
the patch. Any exception is explicit in policy and visible in the ledger.

### 5.7 CI/tester

GitHub Actions, device farms, emulators, local test hosts, and human testers are
evidence producers. Their results do not automatically become product approval.

## 6. GitHub transparency contract

### 6.1 Native authoritative objects

The following remain authoritative in GitHub:

- Issue author, body, comments, reactions, labels, assignees, state, and links.
- Pull-request base/head repositories, refs, commits, reviews, conversations,
  merge state, and merge commit.
- Check suites/runs, workflow runs/jobs, conclusions, annotations, logs, and
  artifact metadata.
- Releases, tags, assets, checksums, and retention state.
- Project item and field values when Projects access is available.
- Repository permissions and branch/ruleset configuration.

The ledger stores stable GitHub node/database IDs, repository IDs, URLs,
observed timestamps, relevant commit SHAs, and a digest of the normalized source
payload. It does not copy an entire sensitive payload merely for convenience.

### 6.2 Native human approval

Approval policy is declarative per project. A GitHub approval event is valid
only when all configured predicates match, including:

- Exact repository and native object.
- Exact approving GitHub login or team policy.
- Exact signal type, such as a specified review, reaction, or exact command.
- Current task, manifest, patch/head SHA, and requested scope.
- Event not revoked, dismissed, edited out of validity, or superseded.

Labels, assignees, Project status, unrelated task messages, or another user's
reaction never substitute for a configured approval signal.

For the initial Japanglify integration, externally authored issues may be
accepted only by the configured trusted GitHub actor's exact `/accept` issue
comment or that actor's thumbs-up reaction on the issue body. Model and worker
configuration approval remains separately scoped.

### 6.3 Transparent ledger-originated activity

When useful to humans, ledger state is projected back to GitHub through concise
native artifacts:

- One intake/plan comment rather than repetitive status spam.
- PR body links to the virtual task, hypotheses, evidence summary, and tests.
- Check-run summaries for machine gates.
- Review comments for actionable code findings.
- Issue comments for ready-for-test artifacts and explicit blockers.
- Project fields for human-facing workflow status when available.

The GitHub projection contains links and summaries, not raw private model input.
Repeated updates should edit a designated bot comment/check when GitHub permits
instead of adding unbounded comments.

### 6.4 Ingestion

The preferred integration is GitHub webhooks. Polling is a supported MVP and
recovery path. Ingestion must support:

- Webhook delivery-ID deduplication and signature verification.
- REST/GraphQL node IDs and timestamps for polling deduplication.
- ETags or equivalent conditional requests where available.
- Rate-limit/backoff handling and explicit stale-state reporting.
- Pagination and deleted/inaccessible object tombstones.
- Reconciliation scans that detect missed, reordered, or edited native events.
- Separate observation time and GitHub source-event time.

CI builds and tests code; it must not manufacture or mirror issue records.

## 7. Ledger repository layout

The initial private GitHub repository uses this logical structure:

```text
ledger/
  schema/
    event-v1.schema.json
    policy-v1.schema.json
  actors/
    <actor-id>.json
  projects/
    <project-id>/policy.json
  events/
    YYYY/MM/DD/<timestamp>-<actor-short-id>-<uuid>.json
  checkpoints/
    YYYY/MM/DD/<checkpoint-id>.json
  projections/
    README.md
  tools/
  tests/
```

One immutable file per event avoids a shared JSONL append hotspot. File paths
are deterministic enough for discovery but uniqueness comes from `eventId`, not
from the path. Projections and indexes may be regenerated and replaced; event
files may not.

GitHub writes use optimistic concurrency. A unique-path event commit rejected
because the branch advanced is rebuilt on the latest verified head and retried
with a bounded policy. A retry never generates a new semantic event ID.

Force-push, event deletion, and history rewriting are forbidden on the ledger's
protected event branch. Administrative emergency recovery creates a new branch
and an explicit incident/supersession event.

## 8. Canonical event envelope

Every event contains at least:

```json
{
  "schemaVersion": 1,
  "eventId": "urn:uuid:...",
  "eventType": "hypothesis.proposed",
  "occurredAt": "2026-08-20T00:00:00.000Z",
  "observedAt": "2026-08-20T00:00:01.000Z",
  "actor": {
    "actorId": "worker:...",
    "kind": "human|agent|ci|tester|system",
    "githubLogin": null
  },
  "projectId": "project:...",
  "taskId": "virtual-pr:...",
  "parentEventIds": [],
  "correlationIds": [],
  "source": {
    "kind": "github|worker|tester|system",
    "repositoryId": null,
    "nodeId": null,
    "deliveryId": null,
    "url": null,
    "commitSha": null,
    "payloadDigest": "sha256:..."
  },
  "subject": {},
  "summary": "Concise auditable claim or transition",
  "data": {},
  "privacy": {
    "classification": "public|internal|confidential|restricted",
    "containsRawUserContent": false
  },
  "integrity": {
    "canonicalization": "JCS",
    "contentHash": "sha256:...",
    "signingKeyId": "key:...",
    "signature": "..."
  }
}
```

Required rules:

- Timestamps are UTC RFC 3339 with millisecond precision.
- IDs are globally unique and independent of GitHub account/repository paths.
- Canonical JSON serialization is specified and test-vector-backed.
- Hash and signature exclude only explicitly documented integrity fields.
- Unknown fields are preserved by forward-compatible readers.
- Unknown enum values do not become a known safe state.
- Payload size is bounded; large evidence is content-addressed externally.
- `summary` is an audit rationale, not private chain-of-thought.

## 9. Event taxonomy

The MVP supports at least:

### Task and assignment

- `task.discovered`
- `task.accepted`
- `task.rejected`
- `task.scoped`
- `task.blocked`
- `task.completed`
- `assignment.proposed`
- `assignment.approved`
- `assignment.started`
- `assignment.heartbeat`
- `assignment.finished`
- `assignment.cancelled`

### Knowledge

- `observation.recorded`
- `fact.asserted`
- `fact.superseded`
- `hypothesis.proposed`
- `hypothesis.supported`
- `hypothesis.contradicted`
- `hypothesis.rejected`
- `hypothesis.confirmed`
- `hypothesis.superseded`
- `evidence.recorded`
- `evidence.invalidated`
- `decision.proposed`
- `decision.approved`
- `decision.rejected`
- `decision.superseded`

### Implementation and verification

- `reproduction.attempted`
- `reproduction.confirmed`
- `reproduction.failed`
- `patch.proposed`
- `patch.updated`
- `review.recorded`
- `test.started`
- `test.finished`
- `artifact.published`
- `validation.ready`
- `validation.recorded`
- `regression.detected`

### Integrity and operations

- `approval.observed`
- `approval.revoked`
- `policy.changed`
- `actor.enrolled`
- `key.rotated`
- `key.revoked`
- `checkpoint.created`
- `ingestion.gap_detected`
- `integrity.failure`
- `incident.recorded`

Projects may extend taxonomy using namespaced event types. Core readers retain
unknown events and expose them without guessing their meaning.

## 10. Hypothesis and evidence model

Each hypothesis includes:

- Stable hypothesis ID and concise falsifiable statement.
- Task/build/branch/device/environment scope.
- Proposer and creation event.
- Preconditions and explicit falsification criteria.
- Supporting and contradicting evidence IDs.
- Current derived state and the event that caused it.
- Optional calibrated confidence class: `speculative`, `plausible`, `strong`,
  or `confirmed`; numerical confidence is not required by the MVP.
- Known alternatives and dependency relationships.

Evidence includes:

- Evidence type, producer, collection method, environment, and timestamp.
- Immutable source or artifact hash.
- Relevant excerpt/structured result within privacy limits.
- Reproduction count and independence information.
- Validity constraints and known sources of error.
- Which hypothesis/falsification criterion it bears on.

No single agent may mark its own hypothesis `confirmed` solely from its own
unreviewed narrative. Confirmation policy requires the configured combination
of reproducible evidence, tests, independent review, or human decision.

Contradictory evidence remains linked and visible. A projection must never omit
it merely because a later decision selected one explanation.

## 11. Knowledge-graph projection

The graph is deterministically rebuilt from ledger events and verified GitHub
sources. Node classes include:

- Project, repository, issue, task, virtual PR, real PR, commit, build, artifact.
- Actor, worker instance, host, model manifest, approval manifest.
- Observation, fact, hypothesis, evidence, decision, risk, acceptance criterion.
- Test, environment, result, defect, patch, review, release, validation outcome.

Edge classes include:

- `reported-by`, `observed-in`, `affects`, `reproduces`, `supports`,
  `contradicts`, `falsifies`, `depends-on`, `supersedes`, `implements`,
  `verifies`, `produces`, `derived-from`, `approved-by`, and `blocked-by`.

Every projected node and edge exposes the event IDs and native source objects
that justify it. Graph edits are prohibited; corrections append ledger events.

## 12. Virtual task/PR responsibility

Every substantive investigation or implementation has one task envelope with:

- Project, canonical issue, affected build, repository, and base revision.
- Scope, non-scope, risks, acceptance criteria, and validation plan.
- Coordinator and human authority.
- Assigned role, provider, exact model, reasoning/effort, host/location,
  write authority, tools, secrets, and concurrency slot.
- Branch/worktree or read-only snapshot.
- Start/state-change times, elapsed time, heartbeat, lease, and cancellation.
- Hypotheses/evidence/decisions produced.
- Patch, test, artifact, review, and final disposition.

Idle workers and read-only host inventory may exist without a virtual task.
Substantive repository analysis, model work, or code modification may not.

The coordinator rejects overlapping write leases for the same branch/worktree
unless an explicit multi-writer protocol is configured. Parallel roles normally
receive isolated worktrees and publish evidence rather than editing shared files.

## 13. Worker configuration and approval

An assignment proposal records:

- Provider and exact model/version.
- Reasoning/effort setting.
- Host/location and runtime identity.
- Role and task scope.
- Read/write/network/tool authority.
- Secret classes available, without secret values.
- Concurrency slot and resource budget.
- Expected cost/usage class when measurable.

Approval binds to the hash of this manifest. Changing provider, model, effort,
host, write scope, tools, network, secrets, or task scope creates a new manifest
and returns to the configured approval gate.

## 14. Source, patch, test, and artifact provenance

Patch events identify exact base/head SHAs and changed paths. Test events identify
exact code SHA, command/workflow/job, environment, toolchain, fixtures, start/end,
exit/conclusion, and result artifact hashes.

GitHub Actions artifacts are convenient distribution objects but may expire and
may be ZIP-wrapped by GitHub. The ledger records artifact name, workflow run/job,
retention, size, digest, and any separately published direct-download asset.

A result from one SHA cannot validate another SHA without an explicit equivalence
decision supported by evidence. A passing unit test cannot be projected as
device/UI/security validation.

## 15. Tester telemetry

Tester feedback is opt-in and minimized. Allowed default fields include:

- Project/build/commit and artifact digest.
- Test-case ID and outcome.
- Device/OS/API profile at a policy-approved granularity.
- Crash fingerprint, bounded stack metadata, timing, and resource measurements.
- Explicit tester comment and consent classification.

Raw translated text, clipboard contents, screenshots, account identifiers,
precise device identifiers, and unrelated logs are excluded by default. When a
screenshot or sensitive attachment is deliberately supplied, the ledger stores
a digest and authorized GitHub/reference URL plus a redacted summary.

Post-merge telemetry may create `regression.detected` evidence but never
silently reopen, patch, merge, or release code.

## 16. Integrity and signatures

### 16.1 Event integrity

- Every worker-originated event is content-hashed.
- Enrolled workers sign canonical events with an Ed25519-class software key in
  the MVP.
- Actor records bind keys to worker identities and validity intervals.
- Rotation and revocation append events and never erase historical validity.
- Native GitHub events are authenticated through GitHub webhook signatures or
  authorized API retrieval and include a normalized-payload digest.

### 16.2 Checkpoints

The checkpoint chain is an integrity protocol, not an encryption mode. The MVP
uses a deliberately small construction composed from standard primitives:

1. Canonicalize and hash every covered stored event envelope with SHA-256. For
   an encrypted event, the leaf commits to the exact ciphertext envelope and
   public cryptographic metadata; the signed plaintext event is verified only
   after authorized decryption.
2. Sort leaves by canonical event ID and build a domain-separated binary Merkle
   tree. Odd leaves are promoted according to one specified, test-vector-backed
   rule; implementations may not improvise it.
3. Create a canonical block header containing protocol/schema version, monotonically
   increasing sequence, previous block hash, event count/range, Merkle root,
   source high-water marks, creation time, and signer key ID.
4. Compute `blockHash = SHA-256(canonicalBlockHeader)` and sign the block hash
   with the enrolled Ed25519 checkpoint key.
5. The next block commits to the exact previous `blockHash`. The genesis block
   commits to a protocol-defined all-zero predecessor and the project/ledger ID.

Domain-separation prefixes distinguish event leaves, Merkle internal nodes, and
checkpoint headers. Verification recomputes every event hash, Merkle root,
block hash, predecessor link, signature, and source high-water mark. A missing,
reordered, inserted, modified, or cross-ledger block must fail verification.

A checkpoint block contains:

- Covered branch head and event set/range.
- Sorted event IDs and hashes or a Merkle root with reproducible construction.
- Previous checkpoint ID/hash.
- Projection version and schema/catalog revisions.
- Creator identity, signature, and creation time.
- Verification status of GitHub source references.

The covered branch head is the event-branch commit immediately before the
checkpoint commit; a block never attempts to include the commit that contains
itself.

Checkpoints are committed to the private ledger repository. A future deployment
may notarize checkpoint roots elsewhere without exposing event content.

### 16.3 Encryption is separate from chaining

Hash chaining proves integrity and ordering; it does not conceal event contents.
If confidential event bodies require encryption, the storage adapter applies a
versioned authenticated-encryption envelope after canonical event signing. The
default must be a widely reviewed AEAD construction such as AES-256-GCM or
XChaCha20-Poly1305 with unique nonces, explicit associated data, key IDs, and
test vectors.

Associated data binds at least the protocol version, ledger/project ID, event
ID, event type or confidentiality-safe type class, actor/key ID, and encryption
key ID. The inner plaintext content hash and actor signature are encrypted with
the event body; the outer checkpoint commits to the stored ciphertext envelope.

Unauthenticated CBC is prohibited. AES-CBC may be supported only for a narrowly
justified legacy interoperability profile using unpredictable IVs and a proven
encrypt-then-MAC construction with independent keys; MAC verification occurs
before decryption, and padding errors are never exposed as an oracle. CBC is
not the ledger's block-chain protocol and is not an MVP requirement.

Encryption keys are never stored in the event repository. The unencrypted event
envelope retains only the minimum routing, integrity, algorithm, key-ID, nonce,
and ciphertext metadata required for verification/decryption policy. Repository
privacy remains required even when payload encryption is enabled because paths,
commit timing, actors, and traffic patterns can reveal sensitive metadata.

### 16.4 TPM option

Hardware-backed keys, including TPM-protected worker identities, are a future
adapter. TPM use may strengthen key custody and host identity but must never be
represented as proof that an OS, model, event claim, or patch is correct.

## 17. Privacy and retention

The initial repository is private. Privacy classifications control which actors
may retrieve source material and which summaries may be projected to GitHub.

The system must:

- Reject secrets, tokens, credentials, private keys, and authorization headers.
- Redact sensitive URLs and source fragments from summaries.
- Avoid raw prompts and private model reasoning.
- Record prompt/template identifiers and hashes when reproducibility requires
  them, with controlled source storage if the prompt itself is sensitive.
- Support retention policies for referenced logs/artifacts without deleting
  immutable ledger metadata.
- Represent expired/deleted source evidence as unavailable, not nonexistent.
- Support a privacy audit that enumerates classifications and exceptions.

## 18. Security and threat model

Threats include:

- Malicious or compromised worker fabricating evidence.
- Prompt/issue/attachment content attempting to control the coordinator.
- GitHub account/token compromise.
- Event deletion, history rewrite, replay, duplication, or reordering.
- Approval confused across tasks, SHAs, scopes, or actors.
- Cross-task source or secret leakage.
- Compromised CI publishing substituted artifacts.
- Dashboard/projection bugs hiding contradictory evidence.
- Denial of service through event/comment spam or oversized evidence.

Required controls include:

- Treat issue bodies, comments, attachments, logs, and repository text as data,
  not higher-priority instructions.
- Verify signatures, actor enrollment, hashes, source IDs, and approval scope.
- Use protected branches/rulesets and least-privilege GitHub credentials.
- Prohibit force pushes and event-file mutation on the canonical branch.
- Bound event/evidence size, ingestion rate, retries, and comment projections.
- Isolate worker worktrees and task state.
- Use independent patch verification and code-owner/human gates where policy
  requires them.
- Surface ingestion gaps, signature failures, stale state, and policy mismatch
  prominently; fail closed for authorization.

## 19. Storage abstraction and migration

Workers target a logical API, not GitHub paths directly:

```text
appendEvent(event) -> receipt
getEvent(eventId) -> event
queryEvents(filter, cursor) -> page
getCheckpoint(checkpointId) -> checkpoint
createCheckpoint(range) -> checkpoint
verify(range|checkpoint) -> report
subscribe(cursor) -> event stream
```

The GitHub backend implements this API with immutable event files and GitHub
commits. A future LAN collector may use SQLite/PostgreSQL/object storage while
exporting the identical canonical event form.

Migration must:

1. Freeze or record a source high-water mark.
2. Export events, actor/key records, policies, checkpoints, and source cursors.
3. Verify every event hash/signature and checkpoint chain.
4. Import without changing IDs, canonical bytes, or occurrence times.
5. Rebuild projections and compare deterministic digests.
6. Append a backend-migration event and resume from the captured cursor.

No source GitHub account or repository URL is part of an event's intrinsic ID.

## 20. Interfaces

### 20.1 CLI

The first implementation provides commands equivalent to:

```text
swarm init
swarm actor enroll
swarm event append --file <event.json>
swarm ingest github --since <cursor>
swarm reconcile github
swarm task show <task-id>
swarm hypothesis show <hypothesis-id>
swarm graph build
swarm checkpoint create
swarm verify [--checkpoint <id>]
swarm export --output <directory>
```

Read-only commands work without mutation authority. Mutating commands preview
target repository/branch, actor, event type, privacy classification, and source
scope before writing when operating interactively.

### 20.2 Dashboard

`ci-pipeline-dashboard` may consume projections or event streams. It shows:

- Repository/issue/PR/virtual-task tree.
- Assigned workers, roles, exact configurations, elapsed time, state, host, and
  resource/power status.
- Active hypotheses with supporting/contradicting evidence.
- Approval and validation gates.
- CI runs, artifacts, reviews, and tester outcomes.
- Ingestion lag, integrity failures, stale workers, and unverified events.

The dashboard is not authoritative and must link every displayed conclusion to
ledger events and native GitHub sources.

## 21. Failure and recovery

- Duplicate delivery: return the original receipt; do not append twice.
- GitHub branch race: retry the same event ID against the latest verified head.
- Partial write: detect missing commit/receipt and reconcile by event ID/hash.
- Invalid signature/schema: quarantine and emit no trusted projection.
- Missing GitHub source: mark unverified/unavailable and retry within policy.
- Edited/deleted native event: append a source-change/tombstone observation.
- Worker timeout: expire lease, retain partial evidence, require reassignment.
- Conflicting hypotheses: retain both and request discriminating evidence.
- Projection corruption: discard and rebuild from verified events.
- Checkpoint mismatch or history rewrite: stop trusted ingestion and emit an
  incident requiring human review.

## 22. Testing strategy

### Unit/property tests

- Schema validation and forward compatibility.
- Canonical JSON and hash/signature golden vectors.
- Event-ID idempotency and replay resistance.
- Approval-manifest scoping.
- Hypothesis state transitions and contradiction retention.
- Privacy/redaction rules.
- Merkle/checkpoint construction and verification.

### Integration tests

- GitHub webhook signature, duplicate, reorder, edit, and delivery-gap fixtures.
- Polling pagination, rate limiting, ETag, deletion, and permission-loss cases.
- Concurrent unique event writes with branch-advance retries.
- Issue/comment/reaction/PR/review/check/workflow/artifact/release ingestion.
- GitHub account/repository migration without ID/hash changes.
- Offline event queue and later reconciliation.
- Projection rebuild producing identical graph digest.

### Adversarial tests

- Prompt injection in issue text, logs, diffs, and attachments.
- Approval by the wrong actor or on the wrong issue/SHA/manifest.
- Forged worker identity or revoked key.
- Artifact substitution and mismatched SHA.
- Event deletion/rewrite and checkpoint fork.
- Cross-task evidence, source, or secret leakage.
- Comment/event flood and oversized payloads.
- Synthesizer attempting to self-verify under separation policy.

### Japanglify acceptance fixture

Replay a bounded issue through:

1. Trusted/native issue acceptance.
2. Reproducer and root-cause hypothesis events.
3. Evidence convergence and scoped decision.
4. Isolated patch PR into `BETA-2`.
5. Independent diff verification.
6. Cached tester build with three individually downloadable APK assets.
7. Human tester outcome.
8. Complete checkpoint verification and graph reconstruction.

The fixture must not trigger a redundant post-merge build or create a user-facing
ZIP in place of direct APK assets.

## 23. Delivery phases

### Phase 0 — Contracts and fixtures

- Event/policy schemas and canonicalization rules.
- Actor, project, task, hypothesis, evidence, and approval fixtures.
- GitHub source mapping table.
- Threat model and privacy classification tests.
- Japanglify replay fixture from existing public/private metadata as policy
  permits.

### Phase 1 — Local ledger core

- Append/verify/query CLI.
- One-file-per-event repository layout.
- Deterministic projections and checkpoint creation.
- No GitHub writes beyond a test fixture repository.

### Phase 2 — GitHub ingestion

- Read-only polling first, then webhook support.
- Native object normalization, deduplication, and reconciliation.
- GitHub-derived approval validation.

### Phase 3 — Transparent GitHub projection

- Bounded issue/PR/check summaries and links.
- Optimistic GitHub event commits with protected-branch policy.
- Private production ledger repository.

### Phase 4 — Swarm coordination

- Virtual task envelopes, leases, role separation, and isolated worktrees.
- Reproducer/analyzer/synthesizer/verifier event contracts.
- Dashboard integration.

### Phase 5 — Tester feedback and portability

- Privacy-bounded tester telemetry.
- Backend export/import and migration verification.
- Optional LAN collector and signed offline queues.
- Optional hardware-backed actor keys.

Each phase has a separately reviewable security boundary. No later phase is
required to validate the correctness of an earlier phase.

## 24. Initial deployment decisions

The initial implementation uses these approved defaults:

- Project-agnostic architecture; Japanglify is the first client.
- Private GitHub ledger repository.
- Configurable GitHub owner/repository/branch.
- GitHub-native events remain authoritative and are used transparently wherever
  possible.
- One immutable canonical JSON file per ledger event.
- Structured summaries, hashes, and controlled references; no raw private
  prompts, chain-of-thought, user text, or screenshots by default.
- GitHub-native human approval signals validated by per-project policy.
- Software signing keys first; TPM/hardware-backed custody later.
- Read-only ingestion before automated GitHub write-back.

The initial implementation does not decide:

- Programming language/runtime.
- Exact GitHub App versus fine-grained-token deployment.
- Webhook hosting provider.
- Graph database or visualization library.
- Future LAN database engine.
- Worker provider/model/effort assignments.

Those choices require explicit implementation proposals with security,
compatibility, maintenance, and migration evidence.

## 25. Definition of done

The first usable release is complete when:

- A private, movable GitHub repository stores schema-valid immutable events.
- Native GitHub issue, comment, reaction, PR, review, check, workflow, artifact,
  release, and Project events can be linked or explicitly reported unsupported.
- Approval is accepted only from the exact configured native signal and scope.
- Concurrent writers do not lose or duplicate events.
- Every accepted event verifies by hash and applicable signature/source proof.
- A checkpoint detects event mutation, deletion, or history divergence.
- The knowledge graph is rebuilt deterministically and retains contradictions.
- Every substantive worker activity maps to a virtual task and exact assignment
  manifest.
- Synthesizer/verifier separation is enforced or visibly waived by policy.
- No raw private reasoning, prompts, user content, credentials, or secrets enter
  the ledger in the default path.
- The dashboard can show responsibility, elapsed state, hypotheses, evidence,
  approvals, CI/artifacts, and integrity health with source links.
- A complete Japanglify issue-to-tester replay passes the acceptance fixture.
- Export/import into a different configured GitHub repository preserves every
  event ID, canonical hash, signature, checkpoint, and projection digest.

The ledger is successful only if a human can answer, from durable linked
evidence: what was reported, what was believed, what contradicted it, who or
what decided, which exact code changed, what tested it, what remained uncertain,
and which human signal authorized each consequential transition.
