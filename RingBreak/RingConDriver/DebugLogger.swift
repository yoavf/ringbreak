//
//  DebugLogger.swift
//  RingBreak
//
//  Debug logging for HID communication troubleshooting
//

import Foundation

/// Singleton for capturing debug data from HID communication
@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    /// Maximum number of log entries to keep in memory
    private let maxEntries = 500

    /// All log entries
    @Published private(set) var entries: [DebugEntry] = []

    /// Latest raw report data (hex string)
    @Published private(set) var lastRawReport: String = "No data yet"

    /// Report type counts
    @Published private(set) var reportCounts: [UInt8: Int] = [:]

    /// Last flex value seen (raw)
    @Published var lastRawFlexValue: UInt16 = 0

    /// Last IMU sample magnitude (deg/s)
    @Published var lastAngularVelocityMagnitude: Double = 0

    /// MCU initialization steps completed
    @Published private(set) var mcuSteps: [String] = []

    /// File URL for log export
    var logFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("fitring_debug.log")
    }

    private init() {}

    // MARK: - Logging Methods

    func log(_ message: String, category: DebugCategory = .general) {
        let entry = DebugEntry(timestamp: Date(), category: category, message: message)
        entries.append(entry)

        // Trim old entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Also print to console for Xcode debugging
        #if DEBUG
        print("[\(category.rawValue)] \(message)")
        #endif
    }

    func logHIDReport(_ data: [UInt8]) {
        guard !data.isEmpty else {
            log("Empty HID report received", category: .hid)
            return
        }

        let reportID = data[0]

        // Update counts
        reportCounts[reportID, default: 0] += 1

        // Format hex string
        let hexString = data.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
        lastRawReport = "ID: 0x\(String(format: "%02X", reportID)) Len: \(data.count)\n\(hexString)"

        // Log first few of each type, then periodic
        let count = reportCounts[reportID] ?? 0
        if count <= 3 || count % 100 == 0 {
            log("Report 0x\(String(format: "%02X", reportID)) (#\(count), \(data.count) bytes): \(hexString)", category: .hid)
        }
    }

    func logFlexValue(raw: UInt16, normalized: Double, offset: Int) {
        lastRawFlexValue = raw
        log("Flex: raw=0x\(String(format: "%04X", raw)) (\(raw)) normalized=\(String(format: "%.3f", normalized)) offset=\(offset)", category: .ringcon)
    }

    func logMCUStep(_ step: String, success: Bool) {
        let status = success ? "✓" : "✗"
        let message = "\(status) \(step)"
        mcuSteps.append(message)
        log("MCU: \(message)", category: .mcu)
    }

    func logConnection(_ message: String) {
        log(message, category: .connection)
    }

    func logError(_ message: String) {
        log("ERROR: \(message)", category: .error)
    }

    // MARK: - Export

    func exportToFile() -> URL {
        let content = entries.map { entry in
            let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")

        try? content.write(to: logFileURL, atomically: true, encoding: .utf8)
        return logFileURL
    }

    func clear() {
        entries.removeAll()
        reportCounts.removeAll()
        mcuSteps.removeAll()
        lastRawReport = "Cleared"
        lastRawFlexValue = 0
    }
}

// MARK: - Supporting Types

struct DebugEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: DebugCategory
    let message: String
}

enum DebugCategory: String {
    case general = "GEN"
    case connection = "CONN"
    case hid = "HID"
    case mcu = "MCU"
    case ringcon = "RING"
    case error = "ERR"

    var color: String {
        switch self {
        case .general: return "gray"
        case .connection: return "blue"
        case .hid: return "purple"
        case .mcu: return "orange"
        case .ringcon: return "green"
        case .error: return "red"
        }
    }
}
