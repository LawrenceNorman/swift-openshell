// PrivacyRouter.swift — Sensitivity-aware model routing for OpenShell
// Extends cost-based model routing with data sensitivity enforcement.

import Foundation

/// Routes inference requests based on data sensitivity + cost + complexity.
/// Integrates with OpenShell's Privacy Router for sandbox-level enforcement.
public final class PrivacyRouter: Sendable {

    /// A routing decision combining cost and privacy considerations
    public struct RoutingDecision: Sendable {
        public let provider: String
        public let model: String
        public let isLocal: Bool
        public let reason: String

        public init(provider: String, model: String, isLocal: Bool, reason: String) {
            self.provider = provider
            self.model = model
            self.isLocal = isLocal
            self.reason = reason
        }
    }

    /// Available local inference providers
    public struct LocalProvider: Sendable {
        public let name: String
        public let model: String
        public let isGPUAccelerated: Bool
        public let maxContextTokens: Int

        public init(name: String, model: String, isGPUAccelerated: Bool = false, maxContextTokens: Int = 8192) {
            self.name = name
            self.model = model
            self.isGPUAccelerated = isGPUAccelerated
            self.maxContextTokens = maxContextTokens
        }
    }

    /// Configuration for the privacy router
    public struct Config: Sendable {
        public var localProviders: [LocalProvider]
        public var cloudProviders: [String]
        public var defaultSensitivity: SensitivityLevel
        public var forceLocalAbove: SensitivityLevel
        public var preferLocalForCost: Bool

        public static let `default` = Config(
            localProviders: [
                LocalProvider(name: "ollama", model: "llama3.2"),
            ],
            cloudProviders: ["anthropic", "openai", "google"],
            defaultSensitivity: .public,
            forceLocalAbove: .confidential,
            preferLocalForCost: false
        )

        public init(
            localProviders: [LocalProvider] = [LocalProvider(name: "ollama", model: "llama3.2")],
            cloudProviders: [String] = ["anthropic", "openai", "google"],
            defaultSensitivity: SensitivityLevel = .public,
            forceLocalAbove: SensitivityLevel = .confidential,
            preferLocalForCost: Bool = false
        ) {
            self.localProviders = localProviders
            self.cloudProviders = cloudProviders
            self.defaultSensitivity = defaultSensitivity
            self.forceLocalAbove = forceLocalAbove
            self.preferLocalForCost = preferLocalForCost
        }
    }

    public let config: Config

    public init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Routing

    /// Route an inference request based on sensitivity and complexity
    public func route(
        sensitivity: SensitivityLevel,
        complexity: ComplexityLevel = .medium,
        preferredProvider: String? = nil
    ) -> RoutingDecision {
        // High sensitivity → force local
        if sensitivity >= config.forceLocalAbove {
            return routeLocal(complexity: complexity, reason: "Data sensitivity (\(sensitivity.label)) requires local inference")
        }

        // Low sensitivity → respect preferred provider or use cloud
        if sensitivity == .public {
            if let preferred = preferredProvider, config.cloudProviders.contains(preferred) {
                return RoutingDecision(
                    provider: preferred,
                    model: defaultModelFor(provider: preferred, complexity: complexity),
                    isLocal: false,
                    reason: "Public data — using preferred cloud provider"
                )
            }

            // Cost optimization: use local for simple tasks
            if complexity == .low && config.preferLocalForCost && !config.localProviders.isEmpty {
                return routeLocal(complexity: complexity, reason: "Low complexity — local inference for cost savings")
            }

            return RoutingDecision(
                provider: config.cloudProviders.first ?? "anthropic",
                model: defaultModelFor(provider: config.cloudProviders.first ?? "anthropic", complexity: complexity),
                isLocal: false,
                reason: "Public data, \(complexity.label) complexity — cloud inference"
                )
        }

        // Internal sensitivity → prefer local but allow cloud
        if config.preferLocalForCost && !config.localProviders.isEmpty {
            return routeLocal(complexity: complexity, reason: "Internal data — preferring local inference")
        }

        return RoutingDecision(
            provider: config.cloudProviders.first ?? "anthropic",
            model: defaultModelFor(provider: config.cloudProviders.first ?? "anthropic", complexity: complexity),
            isLocal: false,
            reason: "Internal data — cloud inference allowed by policy"
        )
    }

    private func routeLocal(complexity: ComplexityLevel, reason: String) -> RoutingDecision {
        // Choose best local provider based on complexity
        let provider: LocalProvider
        if complexity == .high, let gpu = config.localProviders.first(where: { $0.isGPUAccelerated }) {
            provider = gpu
        } else {
            provider = config.localProviders.first ?? LocalProvider(name: "ollama", model: "llama3.2")
        }

        return RoutingDecision(
            provider: provider.name,
            model: provider.model,
            isLocal: true,
            reason: reason
        )
    }

    private func defaultModelFor(provider: String, complexity: ComplexityLevel) -> String {
        switch (provider, complexity) {
        case ("anthropic", .high): return "claude-sonnet-4-6"
        case ("anthropic", .medium): return "claude-sonnet-4-6"
        case ("anthropic", .low): return "claude-haiku-4-5"
        case ("openai", .high): return "gpt-4o"
        case ("openai", .medium): return "gpt-4o-mini"
        case ("openai", .low): return "gpt-4o-mini"
        case ("google", .high): return "gemini-2.5-pro"
        case ("google", .medium): return "gemini-2.5-flash"
        case ("google", .low): return "gemini-2.5-flash"
        default: return "default"
        }
    }

    // MARK: - Combined Decision Matrix

    /// Full routing matrix for documentation/debugging
    public func routingMatrix() -> [(sensitivity: SensitivityLevel, complexity: ComplexityLevel, decision: RoutingDecision)] {
        var matrix: [(SensitivityLevel, ComplexityLevel, RoutingDecision)] = []
        for s in SensitivityLevel.allCases {
            for c in ComplexityLevel.allCases {
                matrix.append((s, c, route(sensitivity: s, complexity: c)))
            }
        }
        return matrix
    }
}

/// Task complexity level for routing decisions
public enum ComplexityLevel: Int, Comparable, CaseIterable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: ComplexityLevel, rhs: ComplexityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
