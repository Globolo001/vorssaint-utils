// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the user typed as something to ping: a hostname, a domain, or an IPv4
/// or IPv6 literal. A pasted URL is reduced to its host, so copying an address
/// out of a browser works without cleanup.
struct PingHost: Hashable {
    enum Kind: Equatable { case ipv4, ipv6, name }

    let text: String
    let kind: Kind

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // An all-numeric dotted name is an IPv4 address that failed to
            // parse, never a host worth handing to DNS.
            guard !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
            self.text = text.lowercased()
            kind = .name
        }
    }

    private static func isLiteral(_ text: String, family: Int32) -> Bool {
        var storage = in6_addr()
        return inet_pton(family, text, &storage) == 1
    }
}

/// Derives each probe's timeout from the replies seen so far, in the manner of
/// TCP's retransmission timer (RFC 6298): a smoothed RTT plus four times its
/// mean deviation. A steady 12 ms LAN host gets a timeout of a few hundred
/// milliseconds, so a dead link shows within a second; a jittery satellite
/// link gets room for its usual spikes instead of flapping.
struct PingTimeoutEstimator {
    /// Nothing measured yet.
    static let initialTimeout: TimeInterval = 1
    /// Below this, Wi-Fi power save and scheduler noise alone cause misses.
    static let minimumTimeout: TimeInterval = 0.3
    /// Beyond this a reply is too late to call the host reachable in real time.
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

/// One finished probe: a reply, or a probe that ran out of time.
struct PingSample: Equatable {
    let sequence: UInt16
    /// System uptime when the probe left, in seconds.
    let sentAt: TimeInterval
    /// `nil` when the probe was lost.
    let rtt: TimeInterval?
    /// A reply that arrived after its probe had already been counted as lost.
    let late: Bool
}

/// Reachability of one target, decided from its probes.
///
/// One missing reply is not an outage: Wi-Fi drops a frame now and then. The
/// first miss only makes the target suspect and asks for an extra probe right
/// away, so the doubt is settled within one more timeout rather than a full
/// probe interval later. A second consecutive miss marks it down. Any reply,
/// even a late one, proves the host is there and brings it back up.
///
/// Times are system uptime seconds, which stop while the Mac sleeps, the same
/// clock `SustainedAlertGate` uses.
struct PingTracker {
    enum State: Equatable { case unknown, up, suspect, down }

    struct Outcome: Equatable {
        let sample: PingSample
        let state: State
        let stateChanged: Bool
        /// Send one extra probe now instead of waiting for the next interval.
        let probeNow: Bool
    }

    static let missesUntilDown = 2
    /// Lost probes kept so a late reply can still be matched to its send time.
    static let maximumRemembered = 64
    static let rememberedSeconds: TimeInterval = 30

    private(set) var state: State = .unknown
    private(set) var consecutiveMisses = 0
    private(set) var estimator = PingTimeoutEstimator()

    private struct Probe {
        let sentAt: TimeInterval
        var expired: Bool
    }
    private var probes: [UInt16: Probe] = [:]
    /// Send time of the newest probe that got a reply. A timeout of a probe
    /// sent before it says nothing about the present.
    private var newestAnsweredSentAt: TimeInterval = -.infinity

    /// Records a probe that just left and returns how long to wait for it.
    mutating func sent(sequence: UInt16, at time: TimeInterval) -> TimeInterval {
        prune(now: time)
        probes[sequence] = Probe(sentAt: time, expired: false)
        return estimator.timeout
    }

    /// A reply for `sequence`. `nil` for a duplicate or a reply to nothing sent.
    mutating func received(sequence: UInt16, at time: TimeInterval) -> Outcome? {
        guard let probe = probes.removeValue(forKey: sequence), time >= probe.sentAt else { return nil }
        let rtt = time - probe.sentAt
        estimator.observe(rtt: rtt)
        newestAnsweredSentAt = max(newestAnsweredSentAt, probe.sentAt)
        consecutiveMisses = 0
        let sample = PingSample(sequence: sequence, sentAt: probe.sentAt, rtt: rtt, late: probe.expired)
        return transition(to: .up, sample: sample, probeNow: false)
    }

    /// The probe's timeout ran out. `nil` when it was answered in the meantime.
    mutating func expired(sequence: UInt16, at time: TimeInterval) -> Outcome? {
        guard var probe = probes[sequence], !probe.expired else { return nil }
        probe.expired = true
        probes[sequence] = probe
        return miss(sequence: sequence, sentAt: probe.sentAt)
    }

    /// The probe could not even be sent (no route, interface down). That is
    /// as good as a miss, and known right away.
    mutating func sendFailed(sequence: UInt16, at time: TimeInterval) -> Outcome {
        probes.removeValue(forKey: sequence)
        return miss(sequence: sequence, sentAt: time)
    }

    /// Forget measurements, for example when the name resolves somewhere new.
    mutating func reset() {
        self = PingTracker()
    }

    private mutating func miss(sequence: UInt16, sentAt: TimeInterval) -> Outcome {
        let sample = PingSample(sequence: sequence, sentAt: sentAt, rtt: nil, late: false)
        // A newer probe already came back: this loss is old news. It still
        // counts in the history, but not against the target's state.
        guard sentAt >= newestAnsweredSentAt else {
            return Outcome(sample: sample, state: state, stateChanged: false, probeNow: false)
        }
        consecutiveMisses += 1
        if consecutiveMisses >= Self.missesUntilDown {
            return transition(to: .down, sample: sample, probeNow: false)
        }
        return transition(to: .suspect, sample: sample, probeNow: true)
    }

    private mutating func transition(to next: State, sample: PingSample, probeNow: Bool) -> Outcome {
        let changed = next != state
        state = next
        return Outcome(sample: sample, state: next, stateChanged: changed, probeNow: probeNow)
    }

    private mutating func prune(now: TimeInterval) {
        probes = probes.filter { now - $0.value.sentAt < Self.rememberedSeconds }
        guard probes.count >= Self.maximumRemembered else { return }
        let keep = probes.sorted { $0.value.sentAt > $1.value.sentAt }.prefix(Self.maximumRemembered - 1)
        probes = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

/// Recent probes of one target, as two aligned `MetricHistory` rings: the
/// round trip in milliseconds (0 for a lost probe) and a loss flag (1 lost,
/// 0 answered). A graph draws the first and marks gaps from the second.
struct PingHistory {
    static let capacity = 120

    private(set) var rttMs = MetricHistory(capacity: PingHistory.capacity)
    private(set) var lost = MetricHistory(capacity: PingHistory.capacity)

    /// A late reply replaces nothing: its loss was already recorded when the
    /// probe timed out, and it only moves the estimator and the state.
    mutating func record(_ sample: PingSample) {
        guard !sample.late else { return }
        rttMs.push((sample.rtt ?? 0) * 1000)
        lost.push(sample.rtt == nil ? 1 : 0)
    }

    /// Share of the recorded probes that were lost, 0 to 1.
    var lossRatio: Double {
        let values = lost.values
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

/// ICMP echo framing for unprivileged datagram sockets. Pure bytes in and out,
/// so it runs in the test target.
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
        // The kernel fills in the ICMPv6 checksum, which covers a pseudo
        // header only it knows; for IPv4 it is ours to set.
        if !ipv6 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xff)
        }
        return packet
    }

    /// Parses what `recv` returned. macOS hands IPv4 datagram-socket replies
    /// over with their IP header in front; IPv6 ones arrive bare.
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

    /// The Internet checksum (RFC 1071). Over a packet that already carries
    /// its checksum, the result is 0.
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
