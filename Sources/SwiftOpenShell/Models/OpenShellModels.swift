// OpenShellModels.swift — Core data models for NVIDIA OpenShell Swift SDK

import Foundation

/// Status of the OpenShell gateway
public enum GatewayStatus: String, Sendable {
    case running
    case stopped
    case notInstalled
    case dockerNotRunning
    case unknown
}

/// Information about the OpenShell installation
public struct OpenShellInfo: Sendable {
    public let isInstalled: Bool
    public let version: String?
    public let gatewayStatus: GatewayStatus
    public let dockerAvailable: Bool
    public let dockerVersion: String?

    public init(isInstalled: Bool, version: String?, gatewayStatus: GatewayStatus, dockerAvailable: Bool, dockerVersion: String?) {
        self.isInstalled = isInstalled
        self.version = version
        self.gatewayStatus = gatewayStatus
        self.dockerAvailable = dockerAvailable
        self.dockerVersion = dockerVersion
    }
}

/// A sandbox instance managed by OpenShell
public struct Sandbox: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let status: SandboxStatus
    public let createdAt: Date?
    public let agent: String?
    public let policyName: String?
    public let gpuEnabled: Bool

    public init(id: String, name: String, status: SandboxStatus, createdAt: Date? = nil, agent: String? = nil, policyName: String? = nil, gpuEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.status = status
        self.createdAt = createdAt
        self.agent = agent
        self.policyName = policyName
        self.gpuEnabled = gpuEnabled
    }
}

/// Status of a sandbox
public enum SandboxStatus: String, Sendable {
    case creating
    case running
    case stopped
    case failed
    case destroying
    case unknown
}

/// Result of executing a command inside a sandbox
public struct ExecResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let duration: TimeInterval

    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String, duration: TimeInterval) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

/// A credential provider registered with OpenShell
public struct CredentialProvider: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: ProviderType
    public let envKeys: [String]

    public init(id: String = UUID().uuidString, name: String, type: ProviderType, envKeys: [String]) {
        self.id = id
        self.name = name
        self.type = type
        self.envKeys = envKeys
    }

    public enum ProviderType: String, Sendable {
        case env
        case file
        case vault
    }
}

/// Data sensitivity level for privacy-aware routing
public enum SensitivityLevel: Int, Comparable, Sendable, CaseIterable {
    case `public` = 0
    case `internal` = 1
    case confidential = 2
    case restricted = 3

    public static func < (lhs: SensitivityLevel, rhs: SensitivityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .public: return "Public"
        case .internal: return "Internal"
        case .confidential: return "Confidential"
        case .restricted: return "Restricted"
        }
    }
}

/// An OCSF audit event from OpenShell
public struct AuditEvent: Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let sandboxName: String
    public let category: AuditCategory
    public let action: String
    public let outcome: AuditOutcome
    public let details: [String: String]

    public init(id: String = UUID().uuidString, timestamp: Date, sandboxName: String, category: AuditCategory, action: String, outcome: AuditOutcome, details: [String: String] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.sandboxName = sandboxName
        self.category = category
        self.action = action
        self.outcome = outcome
        self.details = details
    }
}

public enum AuditCategory: String, Sendable {
    case filesystem
    case network
    case process
    case credential
    case policy
    case inference
}

public enum AuditOutcome: String, Sendable {
    case allowed
    case denied
    case audited
    case error
}

/// Configuration for creating a sandbox
public struct SandboxConfig: Sendable {
    public let name: String?
    public let agent: String
    public let policyPath: String?
    public let workdir: String?
    public let providers: [String]
    public let gpu: Bool
    public let extraArgs: [String]

    public init(name: String? = nil, agent: String, policyPath: String? = nil, workdir: String? = nil, providers: [String] = [], gpu: Bool = false, extraArgs: [String] = []) {
        self.name = name
        self.agent = agent
        self.policyPath = policyPath
        self.workdir = workdir
        self.providers = providers
        self.gpu = gpu
        self.extraArgs = extraArgs
    }
}

/// Errors from OpenShell operations
public enum OpenShellError: LocalizedError, Sendable {
    case notInstalled
    case dockerNotAvailable
    case gatewayNotRunning
    case sandboxCreateFailed(String)
    case sandboxNotFound(String)
    case execFailed(String)
    case policyInvalid(String)
    case providerFailed(String)
    case timeout
    case commandFailed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "OpenShell is not installed. Install from: https://github.com/NVIDIA/OpenShell"
        case .dockerNotAvailable: return "Docker Desktop is not running. OpenShell requires Docker."
        case .gatewayNotRunning: return "OpenShell gateway is not running. Run: openshell gateway start"
        case .sandboxCreateFailed(let msg): return "Failed to create sandbox: \(msg)"
        case .sandboxNotFound(let name): return "Sandbox '\(name)' not found."
        case .execFailed(let msg): return "Command execution failed: \(msg)"
        case .policyInvalid(let msg): return "Invalid policy: \(msg)"
        case .providerFailed(let msg): return "Credential provider error: \(msg)"
        case .timeout: return "Operation timed out."
        case .commandFailed(let code, let stderr): return "Command exited with code \(code): \(stderr)"
        }
    }
}
