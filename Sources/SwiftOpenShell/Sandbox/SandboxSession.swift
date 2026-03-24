// SandboxSession.swift — High-level sandbox session management
// Wraps OpenShellClient with lifecycle management, credential injection, and audit streaming.

import Foundation

/// A managed sandbox session with automatic credential injection, policy application, and cleanup.
/// This is the recommended way to use OpenShell in mChatAI — it handles the full lifecycle.
public final class SandboxSession {
    public let name: String
    public let config: SandboxConfig

    private let client: OpenShellClient
    private let policyManager: PolicyManager
    private let credentialManager: CredentialProviderManager
    private let auditParser: AuditLogParser

    private var sandbox: Sandbox?
    private var providers: [CredentialProvider] = []
    private var auditEvents: [AuditEvent] = []

    /// Current status of the session
    public private(set) var status: SessionStatus = .idle

    public enum SessionStatus: Sendable {
        case idle
        case creating
        case running
        case stopped
        case failed(String)
    }

    public init(
        name: String? = nil,
        config: SandboxConfig,
        client: OpenShellClient = OpenShellClient(),
        policyManager: PolicyManager = PolicyManager(),
        keychainService: String = CredentialProviderManager.defaultKeychainService
    ) {
        self.name = name ?? "mchatai-\(config.agent)-\(UUID().uuidString.prefix(8))"
        self.config = config
        self.client = client
        self.policyManager = policyManager
        self.credentialManager = CredentialProviderManager(client: client)
        self.auditParser = AuditLogParser()
    }

    // MARK: - Lifecycle

    /// Start the sandbox session: create credentials, apply policy, launch sandbox
    public func start() async throws {
        status = .creating

        // 1. Create credential providers from Keychain
        do {
            providers = try await credentialManager.createProviders(for: config.agent)
        } catch {
            // Non-fatal — sandbox can run without credentials
            print("[SandboxSession] Warning: credential setup failed: \(error.localizedDescription)")
        }

        // 2. Generate and save policy if needed
        var finalConfig = config
        if config.policyPath == nil {
            let template = policyManager.template(.developer, workspaceRoot: config.workdir)
            if let policyURL = try? policyManager.save(policy: template) {
                finalConfig = SandboxConfig(
                    name: name,
                    agent: config.agent,
                    policyPath: policyURL.path,
                    workdir: config.workdir,
                    providers: providers.map(\.name) + config.providers,
                    gpu: config.gpu,
                    extraArgs: config.extraArgs
                )
            }
        }

        // 3. Create the sandbox
        do {
            sandbox = try await client.createSandbox(config: finalConfig)
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }

        // 4. Start audit log streaming in background
        Task {
            await streamAuditLogs()
        }
    }

    /// Execute a command in the running sandbox
    public func exec(command: [String], timeout: TimeInterval = 600) async throws -> ExecResult {
        guard let sandbox else {
            throw OpenShellError.sandboxNotFound(name)
        }
        return try await client.exec(sandbox: sandbox, command: command, timeout: timeout)
    }

    /// Execute a shell command string
    public func execShell(command: String, timeout: TimeInterval = 600) async throws -> ExecResult {
        guard let sandbox else {
            throw OpenShellError.sandboxNotFound(name)
        }
        return try await client.execShell(sandbox: sandbox, command: command, timeout: timeout)
    }

    /// Apply an updated policy (hot-reload for network policies)
    public func updatePolicy(_ policy: PolicyManager.Policy) async throws {
        let url = try policyManager.save(policy: policy)
        try await client.setPolicy(sandboxName: name, policyPath: url.path)
    }

    /// Stop and destroy the sandbox session
    public func stop() async {
        // Destroy sandbox
        if sandbox != nil {
            try? await client.destroySandbox(name: name)
        }

        // Clean up credential providers
        await credentialManager.deleteProviders(providers)

        sandbox = nil
        providers = []
        status = .stopped
    }

    // MARK: - Audit

    /// Get all collected audit events
    public var events: [AuditEvent] { auditEvents }

    /// Get a security summary for this session
    public var securitySummary: SecuritySummary {
        auditParser.summary(events: auditEvents)
    }

    /// Verify credentials are not leaked into sandbox environment
    public func verifyCredentialIsolation() async -> Bool {
        guard let sandbox else { return false }
        return await credentialManager.verifyCredentialIsolation(sandbox: sandbox)
    }

    // MARK: - Private

    private func streamAuditLogs() async {
        guard let stream = try? await client.streamAuditLogs(sandboxName: name) else { return }
        for await line in stream {
            if let event = auditParser.parse(line: line) {
                auditEvents.append(event)
            }
        }
    }
}
