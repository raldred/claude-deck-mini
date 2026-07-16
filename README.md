# Claude Deck Mini

Menu bar app that turns a Stream Deck Mini into a live status board for your Claude Code
agents, so you can see which ones need you.

Each of the 6 keys shows a running Claude Code session: a colored band for its status
(red = needs you, green = working, grey = idle), the repo and branch it's working in, and how
long since it last did anything. Waiting agents bubble to the top; if you have more than six,
the last key pages through the rest. Glance at the deck: a red key means an agent is blocked
on you.

A native Swift/AppKit menu bar app owns the logic; a small bundled Python helper drives the
Stream Deck Mini over USB. The device is dedicated to Claude Deck Mini (Elgato's app is not
needed for it). Status is detected through Claude Code hooks that Claude Deck Mini installs
for you.

## Install

Requires macOS 13+, a Stream Deck Mini, Xcode command line tools, and `python3`.

```sh
scripts/install.sh
```

This builds a release binary, creates a Python venv for the device helper,
assembles `Claude Deck Mini.app` (a menu bar app with no Dock icon), installs it to
`/Applications`, and registers a Claude Code plugin that reports session status.

After installing:

1. Launch **Claude Deck Mini** from `/Applications` (it appears in the menu bar).
2. Start a **new** Claude Code session so the plugin's hooks activate.
3. Plug in your Stream Deck Mini, and keys populate as sessions report status.

## Develop

```sh
./go install     # resolve Swift deps
./go build       # build
./go test        # run the DeckCore test suite
./go run         # run in dev

# Device helper (needs the venv from install.sh, or your own deps):
deckd/venv/bin/python deckd/deckd.py --selftest   # light the keys with a demo
python3 deckd/test_render.py                       # headless render tests
```

## How it works

- A Claude Code **plugin** installs hooks that write a small JSON status file per
  session to `~/.claude-deck/status/`.
- The menu bar app watches that directory, resolves each session's `repo · branch`
  label (worktree-aware), orders them (agents waiting on you first), and lays them
  out across the 6 keys, with the last key paging when there are more than six.
- A bundled Python helper (`deckd`) paints the keys and reports presses over a
  small JSON protocol; all app logic stays in Swift.

## Status

Early development.
