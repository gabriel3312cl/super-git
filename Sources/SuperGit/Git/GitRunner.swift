import Foundation

/// Resultado crudo de un comando `git`.
struct GitResult: Sendable {
    let arguments: [String]
    let stdoutData: Data
    let stderrData: Data
    let exitCode: Int32

    var stdout: String { String(decoding: stdoutData, as: UTF8.self) }
    var stderr: String { String(decoding: stderrData, as: UTF8.self) }
    var ok: Bool { exitCode == 0 }

    /// stdout+stderr limpio, útil para mostrar el resultado de push/pull.
    var combined: String {
        (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GitError: LocalizedError {
    case launchFailed(String)
    case timedOut(command: String)
    case failed(command: String, message: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let m):
            return "No se pudo ejecutar git: \(m)"
        case .timedOut(let c):
            return "`git \(c)` excedió el tiempo de espera (¿pide credenciales?)"
        case .failed(_, let message, let code):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "git falló con código \(code)" : trimmed
        }
    }
}

/// Caja mutable con lock, para compartir estado entre las colas de lectura.
private final class MutableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    var wrapped: T {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set(_ newValue: T) {
        lock.lock(); value = newValue; lock.unlock()
    }
}

/// Ejecuta `git` como subproceso. No usa PATH del entorno para evitar
/// problemas cuando la app corre desde un bundle .app.
enum GitRunner {

    static let executable: String = {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }()

    static func run(
        _ arguments: [String],
        in directory: URL,
        timeout: TimeInterval = 90
    ) async throws -> GitResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GitResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = directory

                var env = ProcessInfo.processInfo.environment
                // Nunca pedir credenciales por terminal: preferimos fallar rápido
                // a quedarnos colgados esperando un prompt que nadie verá.
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["GIT_OPTIONAL_LOCKS"] = "0"
                env["SSH_ASKPASS_REQUIRE"] = "never"
                env["LC_ALL"] = "C"
                if env["PATH"] == nil {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GitError.launchFailed(error.localizedDescription))
                    return
                }

                let outBox = MutableBox(Data())
                let errBox = MutableBox(Data())
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outBox.set(outPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }

                let didTimeout = MutableBox(false)
                let watchdog = DispatchWorkItem {
                    if process.isRunning {
                        didTimeout.set(true)
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                process.waitUntilExit()
                watchdog.cancel()
                group.wait()

                if didTimeout.wrapped {
                    continuation.resume(
                        throwing: GitError.timedOut(command: arguments.joined(separator: " "))
                    )
                    return
                }

                continuation.resume(
                    returning: GitResult(
                        arguments: arguments,
                        stdoutData: outBox.wrapped,
                        stderrData: errBox.wrapped,
                        exitCode: process.terminationStatus
                    )
                )
            }
        }
    }

    /// Igual que `run`, pero lanza `GitError.failed` si el comando no termina en 0.
    @discardableResult
    static func checked(
        _ arguments: [String],
        in directory: URL,
        timeout: TimeInterval = 90
    ) async throws -> GitResult {
        let result = try await run(arguments, in: directory, timeout: timeout)
        guard result.ok else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(
                command: arguments.joined(separator: " "),
                message: message.isEmpty ? result.stdout : message,
                code: result.exitCode
            )
        }
        return result
    }
}
