# patchbay

A terminal UI for sending each Mac app's audio to the output device you pick.
Chrome to the speakers and Finder previews to your AirPods, at the same time,
picked from live lists so you never type a device name.

**Status:** early. The routing engine works from the command line; the TUI is
next.

```sh
patchbay list                       # output devices and apps (▶ = playing now)
patchbay route chrome "LG"          # Chrome to the LG monitor until Ctrl-C
patchbay route finder airpods 30    # Finder to AirPods for 30 seconds
```

Names match on any part of the app or device name, ignoring case.

## How it works

macOS 14.2 added Core Audio process taps. For each route, patchbay:

1. taps the app's output with a `CATapDescription` set to mute the original
   (so you don't hear it twice),
2. runs a private aggregate device made of nothing but that tap, whose IO
   callback writes the audio into a lock-free ring buffer, and
3. plays the ring on the destination through an output-only audio unit, which
   also converts the sample rate when the app and the device differ (48 kHz
   into a 44.1 kHz interface, say).

The destination is never part of the aggregate. Putting it there would bring
its inputs along, and an open AirPods mic drops them into call-quality mode;
the output-only unit never opens an input.

Everything patchbay creates is private to its own process. Quit patchbay (or
let it crash) and macOS tears the taps down, so every app goes back to its
normal output.

patchbay never installs a keyboard or event tap. It reads no keystrokes
outside its own terminal window.

## Requirements

- macOS 15 or later (process taps need 14.2; the ring buffer's atomics need 15)
- Swift 6 toolchain (Xcode 16 or later, or the Command Line Tools)
- The **Screen & System Audio Recording** permission for the terminal app you
  run patchbay from (System Settings → Privacy & Security). macOS asks the
  first time patchbay creates a tap.

## Build and run

```sh
make setup   # resolve packages and compile
make dev     # swift run patchbay
make build   # release binary at .build/release/patchbay
```

## Development

`make help` lists every target. Before calling a change done:

```sh
make check-if-the-agent-can-consider-this-task-completed
```

That runs swift-format (strict), a full compile, the tests, the architecture
gates, and the version and changelog gate. Every commit bumps `VERSION` and
adds a `CHANGELOG.md` entry.

Secrets never belong in this public repo. Pre-commit runs gitleaks and
detect-secrets on every commit, CI runs gitleaks over the full history, and
GitHub secret scanning with push protection is on.

Repo policy lives in `VIBE.yaml`; agent instructions live in `AGENTS.md`.
