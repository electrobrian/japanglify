# Japanglify agent playbook

This repository is intended to be operated from GitHub issues. An agent receives
the issue plus the repository context, implements a tightly scoped change, tests
it, and commits both the code and any new operational knowledge.

## Start every task here

1. Read `README.md`, `ARCHITECTURE.md`, and `DEVELOPMENT.md`.
2. Read `docs/agent-handoff.md` for the latest environment, test, and product
   decisions that are not obvious from source.
3. Read the assigned GitHub issue completely, including acceptance criteria,
   linked issues, and comments.
4. Inspect the current worktree before editing. Preserve unrelated user changes.

## Issue and release workflow

- `BETA-2` is the current integration branch. One issue gets one focused branch:
  `agent/<issue-number>-<short-name>`, based on `BETA-2`.
- Merge or otherwise integrate verified issue work into `BETA-2`; do not push
  directly to `main` or an upstream remote.
- `BETA-3` is a separate future branch, cut only from a personally tested
  `BETA-2` commit. A release tag is a later decision, not an automatic result
  of creating `BETA-3`.
- A successful GitHub Actions APK build produces the downloadable artifacts.
  Update the issue's **GitHub Project** status to *Ready for test*; do not
  invent status labels. Keep standard GitHub labels for classification only.
- State the validation actually performed. A passing domain test does not prove
  that the Android app compiled or that an accessibility interaction works.
- If a decision changes setup, architecture, a known limitation, or a repeatable
  test procedure, add a dated entry to `docs/agent-handoff.md` in the same
  commit.
- Keep secrets, tokens, `local.properties`, device identifiers, and temporary
  GitHub CLI configuration out of commits and issue text.

## Product direction

1. The accessibility chip is the primary quick interaction.
2. Share is the secondary path and can expose item-specific output choices
   without accessibility permission.
3. Clipboard/cut/copy observation is a fallback and should remain visually and
   conceptually subordinate.
4. Text output must stay fast. Image/PDF work must be requested explicitly or
   be opt-in, cancellable background work.

## Handoff contract

Each final issue comment and commit message should identify:

- What changed.
- Tests run and their result.
- What could not be tested, with the reason.
- Any new risk, follow-up, or decision recorded in `docs/agent-handoff.md`.
