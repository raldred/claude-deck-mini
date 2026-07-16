import DeckCore
import Foundation

switch CommandLine.arguments.dropFirst().first {
case "hook":
    // Invoked by the Claude Code plugin on every hook event. Read stdin, update
    // the status files, exit fast. Must never block Claude.
    HookCommand.run()
    exit(0)

case "write-plugin":
    // `claude-deck write-plugin <dir> [version]` — used by install.sh to lay the
    // bundled plugin tree into the .app's Resources during packaging.
    let args = Array(CommandLine.arguments.dropFirst(2))
    guard let dir = args.first else {
        FileHandle.standardError.write(Data("usage: claude-deck write-plugin <dir> [version]\n".utf8))
        exit(2)
    }
    let version = args.count > 1 ? args[1] : "0.1.0"
    do {
        try PluginInstaller().writePluginTree(to: URL(fileURLWithPath: dir), version: version)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("write-plugin failed: \(error)\n".utf8))
        exit(1)
    }

case "register-plugin":
    // `claude-deck register-plugin <pluginDir> [version]` — register + enable.
    let args = Array(CommandLine.arguments.dropFirst(2))
    guard let dir = args.first else {
        FileHandle.standardError.write(Data("usage: claude-deck register-plugin <dir> [version]\n".utf8))
        exit(2)
    }
    let version = args.count > 1 ? args[1] : "0.1.0"
    do {
        try PluginInstaller().register(pluginDir: URL(fileURLWithPath: dir), version: version)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("register-plugin failed: \(error)\n".utf8))
        exit(1)
    }

default:
    // Launch the menu bar app.
    AppMain.run()
}
