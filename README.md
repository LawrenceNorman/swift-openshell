# SwiftOpenShell

Swift SDK for [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) — sandboxed execution, policy management, credential injection, privacy-aware inference routing, and audit logging for autonomous AI agents on macOS.

## Overview

SwiftOpenShell provides a typed Swift interface to NVIDIA OpenShell's sandboxed agent runtime. It wraps the `openshell` CLI with structured APIs for:

- **Sandbox lifecycle** — Create, monitor, execute commands in, and destroy isolated agent sandboxes
- **Policy management** — Generate, validate, and apply YAML security policies with built-in templates
- **Credential injection** — Bridge macOS Keychain secrets to OpenShell's secure credential proxy
- **Privacy routing** — Route inference requests based on data sensitivity (local vs. cloud)
- **Audit logging** — Parse OCSF security events and generate compliance summaries

## Requirements

- macOS 13+ (Ventura)
- Swift 5.9+
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) >= 28.04
- [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) CLI installed

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/LawrenceNorman/swift-openshell.git", from: "0.1.0")
]
```

Then add `"SwiftOpenShell"` as a dependency of your target.

## Quick Start

### Detection

```swift
import SwiftOpenShell

let client = OpenShellClient()
let info = await client.detect()

print("Installed: \(info.isInstalled)")
print("Version: \(info.version ?? "unknown")")
print("Gateway: \(info.gatewayStatus)")
print("Docker: \(info.dockerAvailable)")
```

### Create and Use a Sandbox

```swift
let client = OpenShellClient()

// Create a sandboxed Claude Code session
let sandbox = try await client.createSandbox(config: SandboxConfig(
    agent: "claude",
    policyPath: "/path/to/policy.yaml",
    workdir: "~/code/myproject",
    providers: ["mchatai-anthropic"]
))

// Execute commands inside the sandbox
let result = try await client.execShell(sandbox: sandbox, command: "echo hello from sandbox")
print(result.stdout) // "hello from sandbox"

// Clean up
try await client.destroySandbox(name: sandbox.name)
```

### High-Level Session Management

`SandboxSession` handles the full lifecycle — credentials, policy, sandbox, and cleanup:

```swift
let session = SandboxSession(
    config: SandboxConfig(agent: "claude", workdir: "~/code/myproject")
)

try await session.start()  // Creates credentials, applies policy, launches sandbox
let result = try await session.execShell(command: "ls -la")
let summary = session.securitySummary  // Audit event summary
await session.stop()  // Destroys sandbox, cleans up credentials
```

## Policy Management

### Built-in Templates

```swift
let manager = PolicyManager()

// 5 built-in templates
let devPolicy = manager.template(.developer, workspaceRoot: "~/code/myproject")
let privatePolicy = manager.template(.privateAirGapped)  // Air-gapped, no network

// Generate YAML
let yaml = manager.generateYAML(from: devPolicy)

// Save to disk
let url = try manager.save(policy: devPolicy)
```

### Templates

| Template | Filesystem | Network | Use Case |
|----------|-----------|---------|----------|
| **Developer** | workspace + /tmp | LLM APIs, GitHub, npm/pip | Code generation agents |
| **Content** | workspace + Downloads | LLM APIs, social APIs | Content creation |
| **Research** | workspace (read-only) | LLM APIs, web search | Information gathering |
| **Private** | workspace + /tmp | None (air-gapped) | Sensitive data processing |
| **Data Analyst** | workspace + data dirs | LLM APIs only | Data analysis |

### Migrate from CommandPolicy

```swift
let policy = manager.migrateFromCommandPolicy(
    workspaceRoot: "~/code/myproject",
    readOnlyMode: true,
    blockedCommands: ["rm -rf /", "sudo"],
    allowedDomains: ["api.anthropic.com"]
)
```

## Privacy Router

Route inference based on data sensitivity:

```swift
let router = PrivacyRouter(config: .init(
    localProviders: [
        .init(name: "ollama", model: "llama3.2"),
        .init(name: "nemotron", model: "nemotron-120b", isGPUAccelerated: true)
    ],
    forceLocalAbove: .confidential
))

// High sensitivity → forced local
let decision = router.route(sensitivity: .confidential, complexity: .high)
// → nemotron (GPU-accelerated local inference)

// Public data → cloud allowed
let decision2 = router.route(sensitivity: .public, complexity: .high)
// → anthropic/claude-sonnet-4-6
```

### Decision Matrix

| Sensitivity | Complexity | Result |
|------------|-----------|--------|
| Public | Low | Ollama local (cost savings) or Haiku |
| Public | High | Claude API (best quality) |
| Confidential | Low | Ollama local (privacy) |
| Confidential | High | Nemotron GPU (privacy + capability) |
| Restricted | Any | Local only (air-gapped) |

## Credential Management

Bridge macOS Keychain to OpenShell's secure credential proxy:

```swift
let credManager = CredentialProviderManager(client: client)

// Create providers from Keychain (reads com.mchatai.tokens)
let providers = try await credManager.createProviders(for: "claude")
// Creates: mchatai-anthropic provider with ANTHROPIC_API_KEY

// Verify credentials aren't leaked into sandbox env
let isolated = await credManager.verifyCredentialIsolation(sandbox: sandbox)
assert(isolated) // API keys visible only to supervisor proxy, not sandbox process
```

## Audit Logging

Parse OCSF security events:

```swift
let parser = AuditLogParser()

// Stream and parse audit logs
let logStream = try await client.streamAuditLogs(sandboxName: "my-sandbox")
let events = parser.parseStream(logStream)

for await event in events {
    print("[\(event.outcome)] \(event.category): \(event.action)")
    // [allowed] network: Connect to api.anthropic.com
    // [denied] network: Connect to evil.com
}

// Generate security summary
let summary = parser.summary(events: collectedEvents)
print("Total: \(summary.totalEvents), Denied: \(summary.denied)")
```

## Architecture

```
┌─ Your App (mChatAI, etc.) ──────────────────────────┐
│  SwiftOpenShell SDK                                    │
│  ├─ OpenShellClient    (gateway + sandbox CRUD)       │
│  ├─ PolicyManager      (YAML generation + templates)  │
│  ├─ CredentialManager  (Keychain → OpenShell proxy)   │
│  ├─ PrivacyRouter      (sensitivity → model routing)  │
│  ├─ AuditLogParser     (OCSF event parsing)           │
│  └─ SandboxSession     (high-level lifecycle)         │
└───────────────────────────────────────────────────────┘
           ↓ CLI subprocess (→ gRPC migration path)
┌─ OpenShell Gateway (K3s in Docker) ──────────────────┐
│  Per-agent sandbox pods                                │
│  Policy Engine (OPA/Rego)                              │
│  Privacy Router                                        │
│  Credential proxy (env var injection)                  │
│  Landlock LSM + seccomp BPF                            │
└───────────────────────────────────────────────────────┘
```

## License

MIT

## Credits

- [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) — the underlying sandboxed runtime
- Built for the [mChatAI Platform](https://mchatai.com)
