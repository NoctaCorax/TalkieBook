import Foundation

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One serial worker owns the model, so it is loaded only once per app session.
final class Engine {
    private let queue = DispatchQueue(label: "pl.talkiebook.piper", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var generation = 0
    private let lock = NSLock()

    func invalidate() { lock.lock(); generation += 1; lock.unlock() }
    private func currentGeneration() -> Int { lock.lock(); defer {lock.unlock()}; return generation }

    func request(_ payload: [String: Any], cancellable: Bool = false, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let token = currentGeneration()
        queue.async { [self] in
            if cancellable && token != currentGeneration() { return }
            do {
                try start()
                var command = payload
                command["id"] = UUID().uuidString
                var data = try JSONSerialization.data(withJSONObject: command)
                data.append(10)
                try input?.write(contentsOf: data)
                let response = try readResponse()
                if let error = response["error"] as? String { throw EngineError(message:L(error)) }
                let result = response["result"] as? [String: Any] ?? [:]
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                process?.terminate(); process = nil; buffer.removeAll()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
    private func start() throws {
        if process?.isRunning == true { return }
        guard let resources = Bundle.main.resourceURL else { throw EngineError(message: L("Brak zasobów aplikacji.")) }
        let runtime = resources.appendingPathComponent("Engine/python")
        let executable = runtime.appendingPathComponent("bin/python3.12")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw EngineError(message: L("Brak dołączonego silnika mowy. Zbuduj aplikację skryptem build.sh."))
        }
        let worker = Process(), stdin = Pipe(), stdout = Pipe()
        worker.executableURL = executable
        worker.arguments = ["-u", resources.appendingPathComponent("Engine/worker.py").path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONHOME"] = runtime.path
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONPATH"] = runtime.appendingPathComponent("lib/python3.12/site-packages").path
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["OMP_NUM_THREADS"] = "2"
        worker.environment = env
        worker.currentDirectoryURL = AppPaths.root
        worker.standardInput = stdin; worker.standardOutput = stdout
        let log = AppPaths.root.appendingPathComponent("engine.log")
        if !FileManager.default.fileExists(atPath: log.path) {FileManager.default.createFile(atPath: log.path, contents: nil)}
        let logHandle = try FileHandle(forWritingTo: log)
        try logHandle.truncate(atOffset: 0)
        worker.standardError = logHandle
        try worker.run()
        input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        process = worker; buffer.removeAll()
    }
    private func readResponse() throws -> [String: Any] {
        guard let output else { throw EngineError(message: "Silnik nie jest uruchomiony.") }
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let line = buffer[..<end]
                buffer.removeSubrange(...end)
                if line.isEmpty {continue}
                return try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] ?? [:]
            }
            let data = output.availableData
            if data.isEmpty {throw EngineError(message: L("Silnik mowy zakończył pracę. Spróbuj ponownie. Szczegóły: engine.log w danych aplikacji."))}
            buffer.append(data)
        }
    }
    func shutdown() {
        try? input?.close()
        process?.terminate()
    }
    deinit {shutdown()}
}
