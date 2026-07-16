import DeckCore
import Foundation

// `claude-deck hook` — invoked by the Claude Code plugin on every hook event.
// Read stdin, update the status files, exit fast. Must never block Claude.
if CommandLine.arguments.dropFirst().first == "hook" {
    HookCommand.run()
    exit(0)
}

// Otherwise launch the menu bar app. (Wired up in task 10.)
AppMain.run()
