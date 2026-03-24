// AuditLogParser.swift — Parse OCSF audit events from OpenShell logs

import Foundation

/// Parses OCSF (Open Cybersecurity Schema Framework) events from OpenShell's audit log stream.
public final class AuditLogParser: Sendable {
    public init() {}

    /// Parse a single OCSF JSON event line into an AuditEvent
    public func parse(line: String) -> AuditEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let timestamp: Date
        if let ts = json["time"] as? Double {
            timestamp = Date(timeIntervalSince1970: ts)
        } else if let tsStr = json["time"] as? String,
                  let tsDate = ISO8601DateFormatter().date(from: tsStr) {
            timestamp = tsDate
        } else {
            timestamp = Date()
        }

        let category = categorize(json)
        let action = extractAction(json)
        let outcome = extractOutcome(json)
        let sandboxName = json["sandbox_name"] as? String
            ?? (json["metadata"] as? [String: Any])?["sandbox"] as? String
            ?? "unknown"

        var details: [String: String] = [:]
        if let dst = json["dst_endpoint"] as? [String: Any] {
            if let host = dst["hostname"] as? String { details["host"] = host }
            if let port = dst["port"] as? Int { details["port"] = "\(port)" }
        }
        if let file = json["file"] as? [String: Any] {
            if let path = file["path"] as? String { details["path"] = path }
        }
        if let process = json["process"] as? [String: Any] {
            if let name = process["name"] as? String { details["process"] = name }
            if let cmd = process["cmd_line"] as? String { details["command"] = cmd }
        }
        if let msg = json["message"] as? String { details["message"] = msg }

        return AuditEvent(
            timestamp: timestamp,
            sandboxName: sandboxName,
            category: category,
            action: action,
            outcome: outcome,
            details: details
        )
    }

    /// Parse multiple OCSF lines
    public func parseAll(lines: [String]) -> [AuditEvent] {
        lines.compactMap { parse(line: $0) }
    }

    /// Stream and parse OCSF events
    public func parseStream(_ stream: AsyncStream<String>) -> AsyncStream<AuditEvent> {
        AsyncStream { continuation in
            Task {
                for await line in stream {
                    if let event = parse(line: line) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Categorization

    private func categorize(_ json: [String: Any]) -> AuditCategory {
        if let classUid = json["class_uid"] as? Int {
            switch classUid {
            case 4001: return .network      // Network Activity
            case 4002: return .network      // HTTP Activity
            case 1001: return .filesystem   // File System Activity
            case 1007: return .process      // Process Activity
            case 3002: return .credential   // Authentication
            default: break
            }
        }

        if let category = json["category_name"] as? String {
            let lower = category.lowercased()
            if lower.contains("network") || lower.contains("http") { return .network }
            if lower.contains("file") { return .filesystem }
            if lower.contains("process") { return .process }
            if lower.contains("auth") || lower.contains("credential") { return .credential }
            if lower.contains("policy") { return .policy }
        }

        // Infer from content
        if json["dst_endpoint"] != nil { return .network }
        if json["file"] != nil { return .filesystem }
        if json["process"] != nil { return .process }

        return .policy
    }

    private func extractAction(_ json: [String: Any]) -> String {
        if let activity = json["activity_name"] as? String { return activity }
        if let action = json["action"] as? String { return action }
        if let type = json["type_name"] as? String { return type }
        return "unknown"
    }

    private func extractOutcome(_ json: [String: Any]) -> AuditOutcome {
        if let statusId = json["status_id"] as? Int {
            switch statusId {
            case 1: return .allowed   // Success
            case 2: return .denied    // Failure
            default: return .audited
            }
        }

        if let status = json["status"] as? String {
            let lower = status.lowercased()
            if lower.contains("success") || lower.contains("allow") { return .allowed }
            if lower.contains("denied") || lower.contains("block") || lower.contains("fail") { return .denied }
        }

        if let disposition = json["disposition"] as? String {
            let lower = disposition.lowercased()
            if lower.contains("allow") { return .allowed }
            if lower.contains("block") || lower.contains("deny") { return .denied }
        }

        return .audited
    }

    // MARK: - Summary Generation

    /// Generate a security summary from a collection of audit events
    public func summary(events: [AuditEvent]) -> SecuritySummary {
        var allowed = 0
        var denied = 0
        var byCategory: [AuditCategory: Int] = [:]
        var uniqueHosts: Set<String> = []
        var uniquePaths: Set<String> = []

        for event in events {
            switch event.outcome {
            case .allowed: allowed += 1
            case .denied: denied += 1
            default: break
            }
            byCategory[event.category, default: 0] += 1

            if let host = event.details["host"] { uniqueHosts.insert(host) }
            if let path = event.details["path"] { uniquePaths.insert(path) }
        }

        return SecuritySummary(
            totalEvents: events.count,
            allowed: allowed,
            denied: denied,
            byCategory: byCategory,
            uniqueHostsAccessed: uniqueHosts,
            uniqueFilesAccessed: uniquePaths
        )
    }
}

/// Summary of security events for a sandbox session
public struct SecuritySummary: Sendable {
    public let totalEvents: Int
    public let allowed: Int
    public let denied: Int
    public let byCategory: [AuditCategory: Int]
    public let uniqueHostsAccessed: Set<String>
    public let uniqueFilesAccessed: Set<String>

    public var denialRate: Double {
        totalEvents > 0 ? Double(denied) / Double(totalEvents) : 0
    }
}
