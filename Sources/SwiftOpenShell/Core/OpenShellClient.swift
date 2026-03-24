// OpenShellClient.swift — Primary entry point for NVIDIA OpenShell Swift SDK
//
// Usage:
//   let client = OpenShellClient()
//   let info = await client.detect()
//   if info.gatewayStatus == .running {
//       let sandbox = try await client.createSandbox(config: .init(agent: "claude"))
//       let result = try await client.exec(sandbox: sandbox, command: ["echo", "hello"])
//       try await client.destroySandbox(name: sandbox.name)
//   }

import Foundation

/// Primary entry point for interacting with NVIDIA OpenShell.
/// Manages gateway lifecycle, sandbox CRUD, command execution, and log streaming.
public final class OpenShellClient: Sendable {
    private let cli = CLIRunner()

    public init() {}

    // MARK: - Detection & Status

    /// Detect OpenShell installation and gateway status
    public func detect() async -> OpenShellInfo {
        let path = await cli.resolveOpenShellPath()
        let docker = await cli.isDockerAvailable()

        guard path != nil else {
            return OpenShellInfo(
                isInstalled: false,
                version: nil,
                gatewayStatus: .notInstalled,
                dockerAvailable: docker.available,
                dockerVersion: docker.version
            )
        }

        let version = await getVersion()
        let gwStatus = await gatewayStatus()

        return OpenShellInfo(
            isInstalled: true,
            version: version,
            gatewayStatus: gwStatus,
            dockerAvailable: docker.available,
            dockerVersion: docker.version
        )
    }

    /// Get the installed OpenShell version
    public func getVersion() async -> String? {
        guard let result = try? await cli.runOpenShell(arguments: ["--version"], timeout: 10) else {
            return nil
        }
        return result.succeeded ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    /// Check gateway status
    public func gatewayStatus() async -> GatewayStatus {
        guard let result = try? await cli.runOpenShell(arguments: ["gateway", "status"], timeout: 10) else {
            return .unknown
        }
        let output = result.stdout.lowercased() + result.stderr.lowercased()
        if output.contains("running") { return .running }
        if output.contains("stopped") || output.contains("not running") { return .stopped }
        if output.contains("docker") && output.contains("not") { return .dockerNotRunning }
        return result.succeeded ? .running : .stopped
    }

    // MARK: - Gateway Lifecycle

    /// Start the OpenShell gateway (starts K3s in Docker)
    public func startGateway() async throws {
        let result = try await cli.runOpenShell(arguments: ["gateway", "start"], timeout: 120)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Stop the OpenShell gateway
    public func stopGateway() async throws {
        let result = try await cli.runOpenShell(arguments: ["gateway", "stop"], timeout: 30)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Sandbox Lifecycle

    /// Create a new sandbox
    public func createSandbox(config: SandboxConfig) async throws -> Sandbox {
        var args = ["sandbox", "create"]

        if let name = config.name {
            args += ["--name", name]
        }
        if let policy = config.policyPath {
            args += ["--policy", policy]
        }
        if config.gpu {
            args.append("--gpu")
        }
        for provider in config.providers {
            args += ["--provider", provider]
        }
        args += config.extraArgs
        args.append("--")
        args.append(config.agent)

        let result = try await cli.runOpenShell(arguments: args, timeout: 120)
        guard result.succeeded else {
            throw OpenShellError.sandboxCreateFailed(result.stderr)
        }

        // Parse sandbox name from output
        let sandboxName = config.name ?? parseSandboxName(from: result.stdout) ?? "sandbox-\(UUID().uuidString.prefix(8))"

        return Sandbox(
            id: sandboxName,
            name: sandboxName,
            status: .running,
            createdAt: Date(),
            agent: config.agent,
            policyName: config.policyPath,
            gpuEnabled: config.gpu
        )
    }

    /// List all sandboxes
    public func listSandboxes() async throws -> [Sandbox] {
        let result = try await cli.runOpenShell(arguments: ["sandbox", "list"], timeout: 15)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return parseSandboxList(result.stdout)
    }

    /// Get details of a specific sandbox
    public func getSandbox(name: String) async throws -> Sandbox {
        let result = try await cli.runOpenShell(arguments: ["sandbox", "get", name], timeout: 10)
        guard result.succeeded else {
            throw OpenShellError.sandboxNotFound(name)
        }
        return parseSandboxDetail(name: name, output: result.stdout)
    }

    /// Destroy a sandbox
    public func destroySandbox(name: String) async throws {
        let result = try await cli.runOpenShell(arguments: ["sandbox", "delete", name], timeout: 30)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Command Execution

    /// Execute a command inside a sandbox
    public func exec(sandbox: Sandbox, command: [String], timeout: TimeInterval = 600) async throws -> ExecResult {
        var args = ["sandbox", "connect", sandbox.name, "--"]
        args += command
        return try await cli.runOpenShell(arguments: args, timeout: timeout)
    }

    /// Execute a shell command string inside a sandbox
    public func execShell(sandbox: Sandbox, command: String, timeout: TimeInterval = 600) async throws -> ExecResult {
        return try await exec(sandbox: sandbox, command: ["/bin/sh", "-c", command], timeout: timeout)
    }

    // MARK: - Log Streaming

    /// Stream logs from a sandbox
    public func streamLogs(sandboxName: String) async throws -> AsyncStream<String> {
        return try await cli.streamOpenShell(arguments: ["logs", sandboxName, "--tail"])
    }

    /// Stream audit logs in OCSF format
    public func streamAuditLogs(sandboxName: String) async throws -> AsyncStream<String> {
        return try await cli.streamOpenShell(arguments: ["logs", sandboxName, "--format", "ocsf", "--tail"])
    }

    // MARK: - Policy Management

    /// Apply a policy to a running sandbox (hot-reload for network policies)
    public func setPolicy(sandboxName: String, policyPath: String) async throws {
        let result = try await cli.runOpenShell(arguments: ["policy", "set", sandboxName, "--policy", policyPath, "--wait"], timeout: 30)
        guard result.succeeded else {
            throw OpenShellError.policyInvalid(result.stderr)
        }
    }

    // MARK: - Port Forwarding

    /// Start port forwarding from host to sandbox
    public func forwardPort(sandboxName: String, port: Int) async throws {
        let result = try await cli.runOpenShell(arguments: ["forward", "start", "\(port)", sandboxName], timeout: 10)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - File Transfer

    /// Upload a file to a sandbox
    public func upload(sandboxName: String, localPath: String, remotePath: String) async throws {
        let result = try await cli.runOpenShell(arguments: ["sandbox", "upload", sandboxName, localPath, remotePath], timeout: 60)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Download a file from a sandbox
    public func download(sandboxName: String, remotePath: String, localPath: String) async throws {
        let result = try await cli.runOpenShell(arguments: ["sandbox", "download", sandboxName, remotePath, localPath], timeout: 60)
        guard result.succeeded else {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Credential Providers

    /// Create a credential provider
    public func createProvider(name: String, type: CredentialProvider.ProviderType = .env, envVars: [String: String]) async throws -> CredentialProvider {
        var args = ["provider", "create", "--type", type.rawValue, "--name", name]
        for (key, value) in envVars {
            args += ["--env", "\(key)=\(value)"]
        }

        let result = try await cli.runOpenShell(arguments: args, timeout: 15)
        guard result.succeeded else {
            throw OpenShellError.providerFailed(result.stderr)
        }

        return CredentialProvider(name: name, type: type, envKeys: Array(envVars.keys))
    }

    /// Delete a credential provider
    public func deleteProvider(name: String) async throws {
        let result = try await cli.runOpenShell(arguments: ["provider", "delete", name], timeout: 10)
        guard result.succeeded else {
            throw OpenShellError.providerFailed(result.stderr)
        }
    }

    // MARK: - Terminal Dashboard

    /// Launch the OpenShell real-time dashboard (interactive — blocks)
    public func launchDashboard() async throws {
        let result = try await cli.runOpenShell(arguments: ["term"], timeout: 3600)
        if !result.succeeded {
            throw OpenShellError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Parsing Helpers

    private func parseSandboxName(from output: String) -> String? {
        // OpenShell outputs sandbox name on creation — parse from stdout
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("sandbox/") || trimmed.hasPrefix("Sandbox ") {
                return trimmed
                    .replacingOccurrences(of: "sandbox/", with: "")
                    .replacingOccurrences(of: "Sandbox ", with: "")
                    .components(separatedBy: .whitespaces).first
            }
            // If the line looks like just a name (no spaces, reasonable length)
            if !trimmed.isEmpty && !trimmed.contains(" ") && trimmed.count < 64 {
                return trimmed
            }
        }
        return nil
    }

    private func parseSandboxList(_ output: String) -> [Sandbox] {
        var sandboxes: [Sandbox] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.hasPrefix("NAME") && !trimmed.hasPrefix("---") else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let name = parts[0]
            let statusStr = parts.count > 1 ? parts[1].lowercased() : "unknown"
            let status: SandboxStatus = SandboxStatus(rawValue: statusStr) ?? .unknown

            sandboxes.append(Sandbox(id: name, name: name, status: status))
        }
        return sandboxes
    }

    private func parseSandboxDetail(name: String, output: String) -> Sandbox {
        let lower = output.lowercased()
        let status: SandboxStatus
        if lower.contains("running") { status = .running }
        else if lower.contains("stopped") { status = .stopped }
        else if lower.contains("failed") { status = .failed }
        else { status = .unknown }

        return Sandbox(id: name, name: name, status: status)
    }
}
