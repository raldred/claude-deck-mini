import DeckCore
import Foundation

/// Bridges the Swift app to the `deckd` Python helper: launches it, sends render
/// commands as line-delimited JSON, and decodes its events (ready / keydown /
/// error). Auto-relaunches if the child dies. All app logic stays in Swift —
/// deckd only paints and reports presses.
final class DeckdBridge {
    /// Locates the python interpreter and `deckd.py`. Bundled paths when running
    /// from the installed .app; repo paths in dev (resolved from the executable).
    struct Config {
        let pythonPath: String
        let deckdScript: String
    }

    var onKeyDown: ((Int) -> Void)?
    var onReady: ((_ serial: String?, _ keyCount: Int) -> Void)?

    private let config: Config
    private var process: Process?
    private var stdinPipe: Pipe?
    private var readBuffer = Data()
    private let queue = DispatchQueue(label: "deckd.bridge")
    private var stopping = false

    init(config: Config = .resolve()) {
        self.config = config
    }

    func start() {
        queue.async { [weak self] in self?.launch() }
    }

    /// Synchronous, deterministic shutdown for app quit: blank the keys, close
    /// stdin so deckd's loop ends and resets the device, wait briefly for it to
    /// exit, then terminate as a fallback. Runs before applicationWillTerminate
    /// returns so the deck never keeps a stale frame.
    func stop() {
        queue.sync {
            stopping = true
            guard let pipe = stdinPipe, let proc = process else {
                process?.terminate()
                return
            }
            if var data = try? JSONSerialization.data(withJSONObject: ["cmd": "clear"]) {
                data.append(0x0A)
                pipe.fileHandleForWriting.write(data)
            }
            try? pipe.fileHandleForWriting.close()  // EOF → deckd loop exits → device reset
        }
        // Give deckd up to ~1s to reset and exit on its own; then force it.
        let deadline = Date().addingTimeInterval(1.0)
        while process?.isRunning == true, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process?.isRunning == true { process?.terminate() }
    }

    /// Send a full render command: one spec per key + brightness.
    func render(keys: [DeckKey], brightness: Int) {
        let payload: [String: Any] = [
            "cmd": "render",
            "brightness": brightness,
            "keys": keys.map(Self.encode),
        ]
        send(payload)
    }

    func setBrightness(_ value: Int) {
        send(["cmd": "brightness", "value": value])
    }

    func clear() { send(["cmd": "clear"]) }

    // MARK: - process lifecycle

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.pythonPath)
        process.arguments = [config.deckdScript]

        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.ingest(data) }
        }

        process.terminationHandler = { [weak self] _ in
            guard let self, !self.stopping else { return }
            // Child died unexpectedly — relaunch after a short delay.
            self.queue.asyncAfter(deadline: .now() + 2) { self.launch() }
        }

        do {
            try process.run()
            self.process = process
            self.stdinPipe = stdin
        } catch {
            NSLog("deckd launch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - IO

    private func send(_ object: [String: Any]) {
        queue.async { [weak self] in
            guard let self, let pipe = self.stdinPipe,
                  var data = try? JSONSerialization.data(withJSONObject: object) else { return }
            data.append(0x0A)  // newline-delimited
            pipe.fileHandleForWriting.write(data)
        }
    }

    private func ingest(_ data: Data) {
        readBuffer.append(data)
        while let idx = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer.subdata(in: readBuffer.startIndex..<idx)
            readBuffer = readBuffer.subdata(in: readBuffer.index(after: idx)..<readBuffer.endIndex)
            handleEvent(line)
        }
    }

    private func handleEvent(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let event = obj["event"] as? String else { return }
        switch event {
        case "keydown":
            if let index = obj["index"] as? Int {
                DispatchQueue.main.async { [weak self] in self?.onKeyDown?(index) }
            }
        case "ready":
            let serial = obj["serial"] as? String
            let count = obj["keyCount"] as? Int ?? 6
            DispatchQueue.main.async { [weak self] in self?.onReady?(serial, count) }
        case "error":
            NSLog("deckd error: \(obj["message"] as? String ?? "unknown")")
        default:
            break
        }
    }

    // MARK: - encoding

    static func encode(_ key: DeckKey) -> [String: Any] {
        switch key.kind {
        case let .agent(label, status, age, subagents):
            var spec: [String: Any] = ["index": key.index, "kind": "agent",
                                       "status": status.rawValue, "age": age,
                                       "subagents": subagents]
            switch label {
            case let .repoBranch(repo, branch):
                spec["repo"] = repo
                spec["branch"] = branch
            case let .plain(text):
                spec["label"] = text
            }
            return spec
        case let .more(remaining):
            return ["index": key.index, "kind": "more", "remaining": remaining]
        case let .banner(text):
            return ["index": key.index, "kind": "banner", "text": text]
        case .blank:
            return ["index": key.index, "kind": "blank"]
        }
    }
}

extension DeckdBridge.Config {
    /// Resolve interpreter + script. Inside the app bundle:
    /// `Contents/Resources/deckd/{venv/bin/python3,deckd.py}`. In dev: the repo's
    /// `deckd/` beside the built executable, using the venv if present.
    static func resolve() -> DeckdBridge.Config {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let fm = FileManager.default

        // Bundled layout: <exe>/../../Resources/deckd
        let bundledDeckd = exe.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/deckd")
        if fm.fileExists(atPath: bundledDeckd.appendingPathComponent("deckd.py").path) {
            return DeckdBridge.Config(
                pythonPath: bundledDeckd.appendingPathComponent("venv/bin/python3").path,
                deckdScript: bundledDeckd.appendingPathComponent("deckd.py").path)
        }

        // Dev layout: walk up from the executable to find the repo's deckd/.
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("deckd/deckd.py")
            if fm.fileExists(atPath: candidate.path) {
                let venv = dir.appendingPathComponent("deckd/venv/bin/python3")
                let python = fm.fileExists(atPath: venv.path) ? venv.path : "/usr/bin/python3"
                return DeckdBridge.Config(pythonPath: python, deckdScript: candidate.path)
            }
            dir = dir.deletingLastPathComponent()
        }
        // Last resort: assume a sibling deckd/ and system python.
        return DeckdBridge.Config(pythonPath: "/usr/bin/python3", deckdScript: "deckd/deckd.py")
    }
}
