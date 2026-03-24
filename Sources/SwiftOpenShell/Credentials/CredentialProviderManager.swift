// CredentialProviderManager.swift — Manages OpenShell credential providers
// Bridges macOS Keychain credentials to OpenShell's secure credential proxy.

import Foundation
import Security

/// Manages the lifecycle of OpenShell credential providers.
/// Reads secrets from macOS Keychain and creates OpenShell providers
/// that inject credentials via the supervisor proxy (never on sandbox filesystem).
public final class CredentialProviderManager: Sendable {
    private let client: OpenShellClient

    /// Keychain service name for mChatAI tokens
    public static let defaultKeychainService = "com.mchatai.tokens"

    public init(client: OpenShellClient) {
        self.client = client
    }

    // MARK: - Provider Lifecycle

    /// A mapping of agent backend to required credential keys
    public struct AgentCredentials: Sendable {
        public let providerName: String
        public let envVars: [String: String]

        public init(providerName: String, envVars: [String: String]) {
            self.providerName = providerName
            self.envVars = envVars
        }
    }

    /// Create credential providers for an agent backend
    public func createProviders(for backend: String, keychainService: String = defaultKeychainService) async throws -> [CredentialProvider] {
        let credentials = resolveCredentials(for: backend, keychainService: keychainService)
        var providers: [CredentialProvider] = []

        for cred in credentials {
            guard !cred.envVars.isEmpty else { continue }
            let provider = try await client.createProvider(
                name: cred.providerName,
                type: .env,
                envVars: cred.envVars
            )
            providers.append(provider)
        }

        return providers
    }

    /// Delete credential providers
    public func deleteProviders(_ providers: [CredentialProvider]) async {
        for provider in providers {
            try? await client.deleteProvider(name: provider.name)
        }
    }

    // MARK: - Keychain Bridge

    /// Read a value from macOS Keychain
    public func readKeychain(service: String = defaultKeychainService, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Resolve which credentials are needed for a given backend
    private func resolveCredentials(for backend: String, keychainService: String) -> [AgentCredentials] {
        let backendLower = backend.lowercased()
        var credentials: [AgentCredentials] = []

        // Map backend names to Keychain account names and env var names
        let mappings: [(backend: String, keychainKey: String, envVar: String, providerName: String)] = [
            ("claude", "APIKey_macOS_Anthropic", "ANTHROPIC_API_KEY", "mchatai-anthropic"),
            ("codex", "APIKey_macOS_OpenAI", "OPENAI_API_KEY", "mchatai-openai"),
            ("gemini", "APIKey_macOS_Google", "GOOGLE_API_KEY", "mchatai-google"),
            ("openai", "APIKey_macOS_OpenAI", "OPENAI_API_KEY", "mchatai-openai"),
            ("anthropic", "APIKey_macOS_Anthropic", "ANTHROPIC_API_KEY", "mchatai-anthropic"),
            ("xai", "APIKey_macOS_xAI", "XAI_API_KEY", "mchatai-xai"),
            ("mistral", "APIKey_macOS_Mistral", "MISTRAL_API_KEY", "mchatai-mistral"),
            ("deepseek", "APIKey_macOS_DeepSeek", "DEEPSEEK_API_KEY", "mchatai-deepseek"),
            ("together", "APIKey_macOS_Together", "TOGETHER_API_KEY", "mchatai-together"),
            ("perplexity", "APIKey_macOS_Perplexity", "PERPLEXITY_API_KEY", "mchatai-perplexity"),
            ("elevenlabs", "APIKey_macOS_ElevenLabs", "ELEVENLABS_API_KEY", "mchatai-elevenlabs"),
        ]

        for mapping in mappings {
            if backendLower.contains(mapping.backend) {
                if let value = readKeychain(service: keychainService, account: mapping.keychainKey) {
                    credentials.append(AgentCredentials(
                        providerName: mapping.providerName,
                        envVars: [mapping.envVar: value]
                    ))
                }
            }
        }

        // Always include GitHub token if available (used by most dev agents)
        if let ghToken = readKeychain(service: keychainService, account: "APIKey_macOS_GitHub") {
            credentials.append(AgentCredentials(
                providerName: "mchatai-github",
                envVars: ["GITHUB_TOKEN": ghToken]
            ))
        }

        return credentials
    }

    // MARK: - Credential Rotation

    /// Re-create providers with fresh Keychain values (call after user updates API keys)
    public func rotateProviders(for backend: String, existingProviders: [CredentialProvider], keychainService: String = defaultKeychainService) async throws -> [CredentialProvider] {
        // Delete old providers
        await deleteProviders(existingProviders)
        // Create fresh ones from current Keychain values
        return try await createProviders(for: backend, keychainService: keychainService)
    }

    // MARK: - Verification

    /// Verify that credentials are NOT visible as plain env vars inside the sandbox
    public func verifyCredentialIsolation(sandbox: Sandbox) async -> Bool {
        guard let result = try? await client.execShell(sandbox: sandbox, command: "env") else {
            return false
        }

        let sensitivePatterns = ["sk-", "AIza", "gsk_", "xai-"]
        for pattern in sensitivePatterns {
            if result.stdout.contains(pattern) {
                return false // Credential leaked into sandbox environment
            }
        }
        return true
    }
}
