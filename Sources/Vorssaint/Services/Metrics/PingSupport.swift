// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PingHost: Hashable {
    enum Kind: Equatable { case ipv4, ipv6, name, gateway }

    static let gatewayToken = "@gateway"
    static let gateway = PingHost(text: gatewayToken, kind: .gateway)

    let text: String
    let kind: Kind

    private init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased() == PingHost.gatewayToken {
            self = .gateway
            return
        }
        if text.contains("://"), let host = URLComponents(string: text)?.host {
            text = host
        }
        if text.hasPrefix("["), text.hasSuffix("]") {
            text = String(text.dropFirst().dropLast())
        }
        guard !text.isEmpty, text.utf8.count <= 253 else { return nil }
        if PingHost.isLiteral(text, family: AF_INET) {
            self.text = text
            kind = .ipv4
        } else if PingHost.isLiteral(text, family: AF_INET6) {
            self.text = text
            kind = .ipv6
        } else {
            if text.hasSuffix(".") { text.removeLast() }
            let labels = text.split(separator: ".", omittingEmptySubsequences: false)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            guard !labels.isEmpty, labels.allSatisfy({ label in
                !label.isEmpty && label.utf8.count <= 63
                    && !label.hasPrefix("-") && !label.hasSuffix("-")
                    && label.unicodeScalars.allSatisfy(allowed.contains)
            }) else { return nil }
            guard !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
            self.text = text.lowercased()
            kind = .name
        }
    }

    var isLiteral: Bool { kind == .ipv4 || kind == .ipv6 }

    private static func isLiteral(_ text: String, family: Int32) -> Bool {
        var storage = in6_addr()
        return inet_pton(family, text, &storage) == 1
    }
}

enum PingTargets {
    static let maximumCount = 6
    static let defaultList = [PingHost.gatewayToken, "1.1.1.1"].joined(separator: "\n")
    static let defaultMenuBarTarget = "1.1.1.1"

    static func hosts(from raw: String) -> [PingHost] {
        var seen = Set<PingHost>()
        var hosts: [PingHost] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            guard let host = PingHost(String(line)), seen.insert(host).inserted else { continue }
            hosts.append(host)
            if hosts.count == maximumCount { break }
        }
        return hosts
    }

    static func raw(from hosts: [PingHost]) -> String {
        hosts.map(\.text).joined(separator: "\n")
    }

    static func adding(_ host: PingHost, to raw: String) -> String {
        var hosts = self.hosts(from: raw)
        guard !hosts.contains(host), hosts.count < maximumCount else { return self.raw(from: hosts) }
        hosts.append(host)
        return self.raw(from: hosts)
    }

    static func removing(_ host: PingHost, from raw: String) -> String {
        self.raw(from: hosts(from: raw).filter { $0 != host })
    }

    static func menuBarReading(in readings: [PingReading], pinned: String) -> PingReading? {
        readings.first { $0.host.text == pinned } ?? readings.first
    }
}

struct PingReading: Equatable {
    enum Problem: Equatable {
        case resolving
        case unresolved
        case socket(Int32)
    }

    let host: PingHost
    var address: String?
    var state: PingTracker.State = .unknown
    var lastRTT: TimeInterval?
    var smoothedRTT: TimeInterval?
    var lossRatio: Double = 0
    var problem: Problem?
    var rttHistory: [Double] = []
    var lostHistory: [Double] = []

    var graphValues: [Double] {
        zip(rttHistory, lostHistory).map { rtt, lost in lost > 0 ? .nan : rtt }
    }

    var answeredMilliseconds: [Double] {
        zip(rttHistory, lostHistory).compactMap { rtt, lost in lost > 0 ? nil : rtt }
    }

    var isUnreachable: Bool {
        state == .down || (address == nil && problem != nil && problem != .resolving)
    }
}

enum PingMenuBarStyle: String, CaseIterable {
    case graph, dot

    static var current: PingMenuBarStyle {
        PingMenuBarStyle(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.menuBarPingStyle) ?? "") ?? .graph
    }
}

enum PingFormat {
    static func milliseconds(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "–" }
        return value < 10
            ? String(format: "%.1f", locale: MetricFormat.locale, value)
            : String(format: "%.0f", locale: MetricFormat.locale, value.rounded())
    }

    static let menuBarReserve = "888ms"

    static func menuBarValue(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–" }
        let value = seconds * 1000
        if value < 9.95 { return String(format: "%.1f", locale: MetricFormat.locale, value) + "ms" }
        if value < 999.5 { return String(format: "%.0f", locale: MetricFormat.locale, value.rounded()) + "ms" }
        return ">1s"
    }

    static func percent(_ ratio: Double) -> String {
        let value = max(0, min(1, ratio)) * 100
        return value > 0 && value < 1
            ? String(format: "%.1f%%", locale: MetricFormat.locale, value)
            : String(format: "%.0f%%", locale: MetricFormat.locale, value)
    }

    static func summary(_ milliseconds: [Double]) -> String? {
        guard let low = milliseconds.min(), let high = milliseconds.max(), !milliseconds.isEmpty else { return nil }
        let average = milliseconds.reduce(0, +) / Double(milliseconds.count)
        return [low, average, high].map(self.milliseconds).joined(separator: "/")
    }
}

struct PingTimeoutEstimator {
    static let initialTimeout: TimeInterval = 1
    static let minimumTimeout: TimeInterval = 0.3
    static let maximumTimeout: TimeInterval = 3

    private(set) var smoothedRTT: TimeInterval?
    private(set) var rttVariation: TimeInterval = 0

    var timeout: TimeInterval {
        guard let smoothedRTT else { return Self.initialTimeout }
        let raw = smoothedRTT + max(4 * rttVariation, 0.05)
        return min(max(raw, Self.minimumTimeout), Self.maximumTimeout)
    }

    mutating func observe(rtt: TimeInterval) {
        guard rtt.isFinite, rtt >= 0 else { return }
        guard let srtt = smoothedRTT else {
            smoothedRTT = rtt
            rttVariation = rtt / 2
            return
        }
        rttVariation = 0.75 * rttVariation + 0.25 * abs(srtt - rtt)
        smoothedRTT = 0.875 * srtt + 0.125 * rtt
    }

    mutating func reset() {
        smoothedRTT = nil
        rttVariation = 0
    }
}

struct PingSample: Equatable {
    let sequence: UInt16
    let sentAt: TimeInterval
    let rtt: TimeInterval?
    let late: Bool
}

struct PingTracker {
    enum State: Equatable { case unknown, up, suspect, down }

    struct Outcome: Equatable {
        let sample: PingSample
        let state: State
        let stateChanged: Bool
    }

    static let missesUntilDown = 2
    static let maximumRemembered = 64
    static let rememberedSeconds: TimeInterval = 30

    private(set) var state: State = .unknown
    private(set) var consecutiveMisses = 0
    private(set) var estimator = PingTimeoutEstimator()

    private struct Probe {
        let sentAt: TimeInterval
        let deadline: TimeInterval
        var expired: Bool
    }
    private var probes: [UInt16: Probe] = [:]
    private var newestAnsweredSentAt: TimeInterval = -.infinity

    @discardableResult
    mutating func sent(sequence: UInt16, at time: TimeInterval) -> TimeInterval {
        prune(now: time)
        let timeout = estimator.timeout
        probes[sequence] = Probe(sentAt: time, deadline: time + timeout, expired: false)
        return timeout
    }

    mutating func received(sequence: UInt16, at time: TimeInterval) -> Outcome? {
        guard let probe = probes[sequence], time >= probe.sentAt else { return nil }
        probes.removeValue(forKey: sequence)
        let rtt = time - probe.sentAt
        estimator.observe(rtt: rtt)
        newestAnsweredSentAt = max(newestAnsweredSentAt, probe.sentAt)
        consecutiveMisses = 0
        let sample = PingSample(sequence: sequence, sentAt: probe.sentAt, rtt: rtt, late: probe.expired)
        return transition(to: .up, sample: sample)
    }

    mutating func expire(now: TimeInterval) -> [Outcome] {
        let due = probes.filter { !$0.value.expired && $0.value.deadline <= now }
            .sorted { $0.value.sentAt < $1.value.sentAt }
        return due.map { sequence, probe in
            probes[sequence]?.expired = true
            return miss(sequence: sequence, sentAt: probe.sentAt)
        }
    }

    mutating func sendFailed(sequence: UInt16, at time: TimeInterval) -> Outcome {
        probes.removeValue(forKey: sequence)
        return miss(sequence: sequence, sentAt: time)
    }

    private mutating func miss(sequence: UInt16, sentAt: TimeInterval) -> Outcome {
        let sample = PingSample(sequence: sequence, sentAt: sentAt, rtt: nil, late: false)
        guard sentAt >= newestAnsweredSentAt else {
            return Outcome(sample: sample, state: state, stateChanged: false)
        }
        consecutiveMisses += 1
        return transition(to: consecutiveMisses >= Self.missesUntilDown ? .down : .suspect, sample: sample)
    }

    private mutating func transition(to next: State, sample: PingSample) -> Outcome {
        let changed = next != state
        state = next
        return Outcome(sample: sample, state: next, stateChanged: changed)
    }

    private mutating func prune(now: TimeInterval) {
        probes = probes.filter { now - $0.value.sentAt < Self.rememberedSeconds }
        guard probes.count >= Self.maximumRemembered else { return }
        let keep = probes.sorted { $0.value.sentAt > $1.value.sentAt }.prefix(Self.maximumRemembered - 1)
        probes = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

struct PingHistory {
    static let capacity = 120

    private(set) var rttMs = MetricHistory(capacity: PingHistory.capacity)
    private(set) var lost = MetricHistory(capacity: PingHistory.capacity)

    mutating func record(_ sample: PingSample) {
        guard !sample.late else { return }
        rttMs.push((sample.rtt ?? 0) * 1000)
        lost.push(sample.rtt == nil ? 1 : 0)
    }

    var lossRatio: Double {
        let values = lost.values
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

enum ICMPEcho {
    static let requestV4: UInt8 = 8
    static let replyV4: UInt8 = 0
    static let requestV6: UInt8 = 128
    static let replyV6: UInt8 = 129
    static let headerLength = 8

    struct Reply: Equatable {
        let identifier: UInt16
        let sequence: UInt16
        let payload: [UInt8]
    }

    static func request(identifier: UInt16, sequence: UInt16, payload: [UInt8], ipv6: Bool) -> [UInt8] {
        var packet: [UInt8] = [ipv6 ? requestV6 : requestV4, 0, 0, 0,
                               UInt8(identifier >> 8), UInt8(identifier & 0xff),
                               UInt8(sequence >> 8), UInt8(sequence & 0xff)]
        packet += payload
        if !ipv6 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xff)
        }
        return packet
    }

    static func parseReply(_ bytes: [UInt8], ipv6: Bool) -> Reply? {
        var offset = 0
        if !ipv6 {
            guard let first = bytes.first else { return nil }
            if first >> 4 == 4 {
                offset = Int(first & 0x0f) * 4
                guard offset >= 20 else { return nil }
            }
        }
        guard bytes.count >= offset + headerLength else { return nil }
        let type = bytes[offset]
        guard type == (ipv6 ? replyV6 : replyV4), bytes[offset + 1] == 0 else { return nil }
        if !ipv6, checksum(Array(bytes[offset...])) != 0 { return nil }
        let identifier = UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5])
        let sequence = UInt16(bytes[offset + 6]) << 8 | UInt16(bytes[offset + 7])
        return Reply(identifier: identifier, sequence: sequence,
                     payload: Array(bytes[(offset + headerLength)...]))
    }

    static func kernelTimestamp(control: [UInt8], length: Int,
                                level: Int32, type: Int32) -> TimeInterval? {
        let end = min(length, control.count)
        let headerLength = 12
        func aligned(_ value: Int) -> Int { (value + 3) & ~3 }
        return control.withUnsafeBytes { raw -> TimeInterval? in
            var offset = 0
            while offset + headerLength <= end {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                guard messageLength >= headerLength, offset + messageLength <= end else { return nil }
                let messageLevel = raw.loadUnaligned(fromByteOffset: offset + 4, as: Int32.self)
                let messageType = raw.loadUnaligned(fromByteOffset: offset + 8, as: Int32.self)
                let data = offset + aligned(headerLength)
                if messageLevel == level, messageType == type, data + 12 <= offset + messageLength {
                    let seconds = raw.loadUnaligned(fromByteOffset: data, as: Int64.self)
                    let microseconds = raw.loadUnaligned(fromByteOffset: data + 8, as: Int32.self)
                    return TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000
                }
                offset += aligned(messageLength)
            }
            return nil
        }
    }

    static func uptime(ofWallTime wall: TimeInterval, uptime: TimeInterval,
                       wallNow: TimeInterval) -> TimeInterval {
        let age = wallNow - wall
        guard age >= 0, age < 60 else { return uptime }
        return uptime - age
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }
}
