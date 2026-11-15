# PROGRESS

<!-- ≤50 lines. Read this first when a fresh agent session starts.
     Points to TASK_STATE.md for the details. -->

- **Project**: patchbay (swift-cli)
- **Active branch**: `main` (trunk)
- **Active TASK_STATE**: `TASK_STATE.md` (Phase 1 / routing engine)
- **Last session**: 2026-11-15 (Claude Opus 5.5): repo created, scaffolded, linked to Rivendell

## Last three decisions

- 2026-11-15 Public repo, no secrets (VIBE.yaml D3)
- 2026-11-15 Core Audio process taps, never an event tap (D2)
- 2026-11-15 A TUI, so nobody types device names (D1)

## Open blockers

- None.

## How to resume (for a fresh agent)

1. Read `AGENTS.md` then `TASK_STATE.md` §0 and the current slice.
2. `rivendell_list(repo="rex/patchbay")` for the issue board.
3. `make check-if-the-agent-can-consider-this-task-completed` for the gate state.

## Do NOT

- Add a keyboard, mouse or event tap of any kind.
- Copy code from jkjoplin/AudioRouter (no license). Build from Apple's docs.
