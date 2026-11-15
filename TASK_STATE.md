# TASK_STATE — patchbay v1: route apps to devices from a TUI

> Source of truth for in-flight work. Humans and agents both write here.
> This file is **committed** to the repo. It survives sessions, machines,
> and context compactions. Issues live in Rivendell (rex/patchbay).
>
> Branch: `main` (trunk) · Owner (human): Pierce · Last update: 2026-11-15 by Claude Opus 5.5

## 0. TL;DR for a fresh agent session

`patchbay` opens the patch panel: sources left, outputs right, click one then
the other and a cable is drawn. **Next action:** Pierce uses it for real
(pitch at 48→44.1 kHz, glitches over minutes, two routes at once, AirPods
staying in high quality), which also closes out #4. Never add an event tap.

## Standing user directives

- It has to be a TUI: nobody should have to remember device names (Pierce, 2026-11-15).
- Public repo: no secrets land in it (Pierce, 2026-11-15).
- Don't copy jkjoplin/AudioRouter code; it has no license.

## 1. Phases

| # | Phase | Status | Exit criteria |
|---|---|---|---|
| 0 | Name, repo, scaffold, Rivendell (#2, #3) | ✅ done | rex/patchbay public, gates green, issues on the board |
| 1 | Routing engine (#4) | 🟡 in-prog: built, awaiting listen test | `patchbay route <app> <device>` plays that app on that device until Ctrl-C; several routes at once; mismatched sample rates handled |
| 2 | TUI (#5) | ✅ done | Live app and device lists; add, retarget and remove routes; quitting restores everything |

Parent issue: #1. Issues #1–#5 came over from rex/todo#16–#20.

Statuses: `⏸ pending` · `🟡 in-prog` · `✅ done` · `🔴 blocked`

## 2. Slices

### Slice 1.1 — Discovery: audio apps and output devices ✅

- Acceptance:
  - [x] When asked, the engine shall list processes whose output is running, with PID and bundle ID, grouping helper processes under their app.
  - [x] When asked, the engine shall list output devices with their names, UIDs and nominal sample rates, and mark the default.
  - [x] Tests: the pure grouping logic, without Core Audio.

### Slice 1.2 — Route one app to one device 🟡

- Acceptance:
  - [x] When a route starts, the app's audio shall reach the chosen device (measured: peak flows through the ring into the output unit).
  - [ ] If the tap and the device run at different sample rates, the audio shall still play at the right pitch and speed. (48→44.1 kHz flows; pitch needs ears.)
  - [x] When patchbay exits, every tap and aggregate it created shall be destroyed (`Route.stop`, plus macOS cleanup of private objects).
  - [ ] Two routes at once (the engine allows it; the CLI routes one).
  - [ ] AirPods stay in high-quality mode while routed to (needs AirPods).

## 3. Blockers / open questions

- None.

## 4. Recent decisions (append-only, newest first)

- 2026-11-15 — Repo lives at `~/Code/__APPS/terminal/patchbay`, public on GitHub (Pierce).
- 2026-11-15 — Name: patchbay (Pierce).

## 5. Next actions (ordered)

1. Pierce: `swift run patchbay route chrome LG` (or AirPods) and listen.
2. Phase 2, the TUI (#5), which also exercises several routes at once.

## 6. Handoff note

2026-11-15: engine built and measured on this Mac (Scarlett 44.1 kHz,
BlackHole 48 kHz). The first design (destination inside the aggregate) was
dropped for the tap-only aggregate + ring + output-only AUHAL; AGENTS.md §9
says why.
