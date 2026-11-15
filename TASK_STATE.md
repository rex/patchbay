# TASK_STATE — patchbay v1: route apps to devices from a TUI

> Source of truth for in-flight work. Humans and agents both write here.
> This file is **committed** to the repo. It survives sessions, machines,
> and context compactions. Issues live in Rivendell (rex/patchbay).
>
> Branch: `main` (trunk) · Owner (human): Pierce · Last update: 2026-11-15 by Claude Opus 5.5

## 0. TL;DR for a fresh agent session

The repo is scaffolded and linked to Rivendell. **Next action: the routing
engine (Phase 1)**: list apps that are playing audio and the output devices,
and route one app to one device. The TUI (Phase 2) sits on top of it. Never
add an event tap.

## Standing user directives

- It has to be a TUI: nobody should have to remember device names (Pierce, 2026-11-15).
- Public repo: no secrets land in it (Pierce, 2026-11-15).
- Don't copy jkjoplin/AudioRouter code; it has no license.

## 1. Phases

| # | Phase | Status | Exit criteria |
|---|---|---|---|
| 0 | Name, repo, scaffold, Rivendell | ✅ done | rex/patchbay public, gates green, issues on the board |
| 1 | Routing engine | ⏸ pending | `patchbay route <app> <device>` plays that app on that device until Ctrl-C; several routes at once; mismatched sample rates handled |
| 2 | TUI | ⏸ pending | Live app and device lists; add, retarget and remove routes; quitting restores everything |

Statuses: `⏸ pending` · `🟡 in-prog` · `✅ done` · `🔴 blocked`

## 2. Slices

### Slice 1.1 — Discovery: audio apps and output devices

- Acceptance:
  - [ ] When asked, the engine shall list processes whose output is running, with PID and bundle ID, grouping helper processes under their app.
  - [ ] When asked, the engine shall list output devices with their names, UIDs and nominal sample rates, and mark the default.
  - [ ] Tests: the pure grouping and naming logic, without Core Audio.

### Slice 1.2 — Route one app to one device

- Acceptance:
  - [ ] When a route starts, the app's audio shall play only on the chosen device.
  - [ ] If the tap and the device run at different sample rates, the audio shall still play at the right pitch and speed.
  - [ ] When patchbay exits, every tap and aggregate it created shall be destroyed.

## 3. Blockers / open questions

- None.

## 4. Recent decisions (append-only, newest first)

- 2026-11-15 — Repo lives at `~/Code/__APPS/terminal/patchbay`, public on GitHub (Pierce).
- 2026-11-15 — Name: patchbay (Pierce).

## 5. Next actions (ordered)

1. Slice 1.1, discovery.
2. Slice 1.2, routing, listen-tested on real devices.
3. Phase 2, the TUI.

## 6. Handoff note

2026-11-15: repo created and scaffolded; engine work starts next.
