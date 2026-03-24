// CLIRunner.swift — Subprocess wrapper for executing OpenShell CLI commands

import Foundation

/// Low-level subprocess executor for `openshell` CLI commands.
/// All public API methods in this SDK delegate to CLIRunner for actual execution.
actor CLIRunner {
    /// Path to the openshell binary (resolved once on first use)
    private var resolvedPath: String?

    /// Resolve the path to the openshell binary
    func resolveOpenShellPath() async -> String? {
        if let cached = resolvedPath { return cached }

        // Check common locations
        let candidates = [
            "/usr/local/bin/openshell",
            "/opt/homebrew/bin/openshell",
            "/usr/bin/openshell",
            "\(NSHomeDirectory())/.local/bin/openshell"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                resolvedPath = path
                return path
            }
        }

        // Try `which`
        if let whichResult = try? await run(executable: "/usr/bin/which", arguments: ["openshell"], timeout: 5),
           whichResult.exitCode == 0 {
            let path = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                resolvedPath = path
                return path
            }
        }

        return nil
    }

    /// Run an openshell command and return the result
    func runOpenShell(arguments: [String], timeout: TimeInterval = 30) async throws -> ExecResult {
        guard let path = await resolveOpenShellPath() else {
            throw OpenShellError.notInstalled
        }
        return try await run(executable: path, arguments: arguments, timeout: timeout)
    }

    /// Run an openshell command and stream stdout line-by-line
    func streamOpenShell(arguments: [String]) async throws -> AsyncStream<String> {
        guard let path = await resolveOpenShellPath() else {
            throw OpenShellError.notInstalled
        }
        return streamOutput(executable: path, arguments: arguments)
    }

    /// Run any executable and return the result
    func run(executable: String, arguments: [String], timeout: TimeInterval = 30, environment: [String: String]? = nil) async throws -> ExecResult {
        let start = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let env = environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: OpenShellError.execFailed(error.localizedDescription))
                return
            }

            // Timeout task
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }

            // Wait for completion on a background thread
            Task.detached {
                process.waitUntilExit()
                timeoutTask.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = ExecResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    duration: Date().timeIntervalSince(start)
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// Stream stdout from a process line-by-line
    func streamOutput(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.finish()
                    return
                }

                let handle = pipe.fileHandleForReading
                var buffer = Data()

                while process.isRunning || handle.availableData.count > 0 {
                    let data = handle.availableData
                    if data.isEmpty {
                        try? await Task.sleep(for: .milliseconds(100))
                        continue
                    }
                    buffer.append(data)

                    // Emit complete lines
                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                        if let line = String(data: lineData, encoding: .utf8) {
                            continuation.yield(line)
                        }
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                    }
                }

                // Emit any remaining data
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    continuation.yield(line)
                }

                continuation.finish()
            }
        }
    }

    /// Check if Docker is available
    func isDockerAvailable() async -> (available: Bool, version: String?) {
        guard let result = try? await run(executable: "/usr/local/bin/docker", arguments: ["--version"], timeout: 5) else {
            // Try alternate path
            guard let result = try? await run(executable: "/usr/bin/docker", arguments: ["--version"], timeout: 5) else {
                return (false, nil)
            }
            return (result.exitCode == 0, result.exitCode == 0 ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        }
        return (result.exitCode == 0, result.exitCode == 0 ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
    }
}
