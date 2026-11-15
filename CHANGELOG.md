# Changelog

All notable changes to this project are documented here. This project
follows [Semantic Versioning](https://semver.org/) and
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Format:

```markdown
## [X.Y.Z] — YYYY-MM-DD — Agent: <name>
### Added | Changed | Fixed | Removed | Deprecated | Security
- <what changed, in imperative voice>
```

**Every commit requires a version bump and a matching entry here.** The
`scripts/check_version_bumped.py` gate enforces this; `auto-commit.sh`
calls `scripts/bump_version.py <level>` before commit.

**Bump level guidance** (agent decides per slice):
- `patch` — bug fix, documentation change, refactor with no behavior change
- `minor` — new feature, new public API, any backward-compatible addition
- `major` — breaking change, removal, incompatible behavior change

**Agent attribution is required.** Every entry names the agent (or human)
that authored the change. This is how we keep `git blame` honest when
multiple agents and humans work on the same slice.

Append new entries at the top. One entry per commit (same cadence as
version bumps).

---

## [0.2.0] — 2026-11-15 — Agent: Claude Opus 5.5
### Added
- `PatchbayCore`, the routing engine. `OutputDevice.all()` lists output
  devices (default first, aggregates hidden). `AudioProcess.all()` and
  `AppGrouping` list the apps registered with the audio server, with browser
  and Electron helpers grouped under their app. `Route` sends one app to one
  device.
- A route is a muting process tap, then a private tap-only aggregate whose
  IOProc fills a lock-free SPSC `RingBuffer`, then an output-only AUHAL on
  the destination that converts the sample rate. Tested on this Mac: a 48 kHz
  tap into the 44.1 kHz Scarlett and into 48 kHz BlackHole, with audio
  flowing and the buffer steady at 300–950 frames over 12 seconds.
- `patchbay list` and `patchbay route <app> <device> [seconds]`.
- Swift Testing suites for app grouping, HAL error codes and the ring buffer
  (priming, underrun, trimming a fast writer, overflow, tap channel offset).

### Changed
- Tests are now a required gate (`VIBE.yaml`, `make test` runs `swift test`).
- The minimum is macOS 15, for `Synchronization.Atomic` in the ring buffer.

## [0.1.1] — 2026-11-15 — Agent: Claude Opus 5.5
### Changed
- TASK_STATE.md maps each phase to its issue (#1–#5, moved here from
  rex/todo). The repo is linked to Rivendell, which closes the naming and
  repo-setup issues.

## [0.1.0] — 2026-11-15 — Agent: Claude Opus 5.5
### Added
- Scaffold from `agentic-skeleton`: AGENTS.md (CLAUDE.md and GEMINI.md
  symlink to it), VIBE.yaml, TASK_STATE.md, the gate scripts, `.claude/`
  hooks, agents and commands, and pre-commit with gitleaks and
  detect-secrets.
- SwiftPM package (`Package.swift`, macOS 14.2+) with a placeholder
  `patchbay` executable.
- Makefile wired for Swift: `lint` (swift-format, strict), `typecheck`
  (`swift build --build-tests`), `test` (`swift test` once tests are
  required), `fix`, `build`, `dev`.
- CI on GitHub Actions (macOS): lint, compile, tests, and a gitleaks scan
  of the full history.
- VIBE.yaml decisions D1–D3: a TUI, Core Audio process taps with no event
  taps, and a public repo with no secrets.
