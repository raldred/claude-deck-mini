# Claude Deck Mini

Menu bar app that turns a Stream Deck Mini into a live status board for your Claude Code
agents — see which ones need you.

Each of the 6 keys shows a running Claude Code session: a colored band for its status
(red = needs you, green = working, grey = idle), the repo and branch it's working in, and how
long since it last did anything. Waiting agents bubble to the top; if you have more than six,
the last key pages through the rest. Glance at the deck — a red key means an agent is blocked
on you.

A native Swift/AppKit menu bar app owns the logic; a small bundled Python helper drives the
Stream Deck Mini over USB. The device is dedicated to Claude Deck Mini (Elgato's app is not
needed for it). Status is detected through Claude Code hooks that Claude Deck Mini installs
for you.

## Install

Requires macOS 13+, a Stream Deck Mini, and Xcode command line tools.

```sh
./go install     # resolve Swift deps
./go build       # build
./go run         # run in dev
```

A packaged `.app` and hook installation come from `scripts/install.sh` (see the plan).

## Status

Early development.
