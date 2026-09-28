// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// One ping target as the monitor last read it.
struct PingReading: Equatable {
    enum Problem: Equatable {
        /// The name is being looked up for the first time.
        case resolving
        /// The name did not resolve; looked up again every few seconds.
        case unresolved
        /// The ICMP socket could not be opened, with its errno.
        case socket(Int32)
    }

    let host: PingHost
    var address: String?
    var state: PingTracker.State = .unknown
    var lastRTT: TimeInterval?
    var smoothedRTT: TimeInterval?
    var lossRatio: Double = 0
    var problem: Problem?
    /// Oldest → newest, milliseconds, 0 for a lost probe. Empty while no
    /// graph is visible, like the monitor's other histories.
    var rttHistory: [Double] = []
    /// Aligned with `rttHistory`: 1 for a lost probe, 0 for an answered one.
    var lostHistory: [Double] = []
}

/// ICMP ping for `SystemMonitor`, read on its tick like every other sampler.
///
/// Each target keeps an unprivileged ICMP datagram socket (no root, no
/// helper) connected to its address. A read drains the replies that queued
/// since the last tick, using the kernel's receive timestamps so the round
/// trip is exact however late the tick is, expires probes whose timeout ran
/// out, then sends the next probe. No timers or read sources of its own.
///
/// Called only on the monitor's queue. Name lookups block, so they run on a
/// side queue and are picked up by a later read.
final class PingSampler {
    /// Names are looked up again this often, so a moved host is followed.
    static let refreshSeconds: TimeInterval = 300
    /// A failed lookup, or a target that went down, retries after this.
    static let retrySeconds: TimeInterval = 5

    private let lookupQueue = DispatchQueue(label: "com.vorssaint.ping.lookup", qos: .utility)
    private let clock: () -> TimeInterval
    private var targets: [PingHost: PingTarget] = [:]
    /// Echoed back verbatim; filters out replies to anyone else's pings
    /// without trusting the kernel to keep the identifier as sent.
    private let cookie = (0..<8).map { _ in UInt8.random(in: .min ... .max) }
    private let identifier = UInt16.random(in: .min ... .max)

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    func sample(targets hosts: [PingHost], publishHistory: Bool) -> [PingReading] {
        let wanted = Set(hosts)
        for (host, target) in targets where !wanted.contains(host) {
            target.close()
            targets[host] = nil
        }
        return hosts.map { host in
            let target = targets[host] ?? PingTarget(host: host)
            targets[host] = target
            return read(target, publishHistory: publishHistory)
        }
    }

    /// Closes every socket; the next read starts over.
    func reset() {
        targets.values.forEach { $0.close() }
        targets.removeAll()
    }

    private func read(_ target: PingTarget, publishHistory: Bool) -> PingReading {
        let now = clock()
        adoptLookup(of: target)
        lookUpIfDue(target, now: now)

        if target.socket >= 0, let address = target.address {
            for outcome in drain(target, ipv6: address.ipv6) { target.record(outcome) }
            for outcome in target.tracker.expire(now: clock()) { target.record(outcome) }
            send(target, ipv6: address.ipv6)
        }

        var reading = PingReading(host: target.host)
        reading.address = target.address?.text
        reading.problem = target.problem
        reading.state = target.address == nil && target.problem != nil && target.problem != .resolving
            ? .down : target.tracker.state
        reading.lastRTT = target.lastRTT
        reading.smoothedRTT = target.tracker.estimator.smoothedRTT
        reading.lossRatio = target.history.lossRatio
        reading.rttHistory = target.history.rttMs.publishedValues(whileVisible: publishHistory)
        reading.lostHistory = target.history.lost.publishedValues(whileVisible: publishHistory)
        return reading
    }

    // MARK: Lookup

    private func lookUpIfDue(_ target: PingTarget, now: TimeInterval) {
        guard !target.lookupInFlight else { return }
        let sinceLookup = now - target.lookedUpAt
        let due: Bool
        if target.address == nil {
            due = sinceLookup >= Self.retrySeconds
        } else if target.host.kind == .name {
            due = sinceLookup >= Self.refreshSeconds
                || (target.tracker.state == .down && sinceLookup >= Self.retrySeconds)
        } else {
            due = false
        }
        guard due else { return }
        target.lookedUpAt = now
        if target.host.kind != .name {
            // A literal parses instantly; no reason to wait a tick.
            target.finishLookup(PingAddress.resolve(target.host))
            adoptLookup(of: target)
            return
        }
        if target.address == nil { target.problem = .resolving }
        target.lookupInFlight = true
        lookupQueue.async { [target] in
            target.finishLookup(PingAddress.resolve(target.host))
        }
    }

    private func adoptLookup(of target: PingTarget) {
        guard let result = target.takeLookup() else { return }
        guard let address = result else {
            // Keep pinging a known address: DNS failing is not the host failing.
            if target.address == nil { target.problem = .unresolved }
            return
        }
        guard address != target.address || target.socket < 0 else { return }
        target.close()
        target.address = address
        target.tracker = PingTracker()
        target.problem = openSocket(target, address: address)
        // Without a socket, forget the address so the next lookup retries.
        if target.problem != nil { target.address = nil }
    }

    // MARK: Socket

    private func openSocket(_ target: PingTarget, address: PingAddress) -> PingReading.Problem? {
        let fd = socket(address.family, SOCK_DGRAM, address.ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else { return .socket(errno) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_TIMESTAMP, &on, socklen_t(MemoryLayout<Int32>.size))
        // Connected, the kernel only delivers ICMP from this address.
        guard address.withSockaddr({ connect(fd, $0, $1) }) == 0 else {
            let code = errno
            Darwin.close(fd)
            return .socket(code)
        }
        target.socket = fd
        return nil
    }

    private func drain(_ target: PingTarget, ipv6: Bool) -> [PingTracker.Outcome] {
        var outcomes: [PingTracker.Outcome] = []
        var buffer = [UInt8](repeating: 0, count: 1024)
        var control = [UInt8](repeating: 0, count: 64)
        // Bounded, so a flood cannot hold up the rest of the tick.
        for _ in 0..<64 {
            var controlLength = 0
            let count = buffer.withUnsafeMutableBytes { data in
                control.withUnsafeMutableBytes { ancillary in
                    var vector = iovec(iov_base: data.baseAddress, iov_len: data.count)
                    return withUnsafeMutablePointer(to: &vector) { vector in
                        var message = msghdr()
                        message.msg_iov = vector
                        message.msg_iovlen = 1
                        message.msg_control = ancillary.baseAddress
                        message.msg_controllen = socklen_t(ancillary.count)
                        let count = recvmsg(target.socket, &message, 0)
                        controlLength = Int(message.msg_controllen)
                        return count
                    }
                }
            }
            guard count > 0 else { break }
            let uptime = clock()
            let receivedAt = ICMPEcho.kernelTimestamp(control: control, length: controlLength,
                                                      level: SOL_SOCKET, type: SCM_TIMESTAMP)
                .map { ICMPEcho.uptime(ofWallTime: $0, uptime: uptime, wallNow: Date().timeIntervalSince1970) }
                ?? uptime
            guard let reply = ICMPEcho.parseReply(Array(buffer[..<count]), ipv6: ipv6),
                  reply.payload.starts(with: cookie),
                  let outcome = target.tracker.received(sequence: reply.sequence, at: receivedAt)
            else { continue }
            outcomes.append(outcome)
        }
        return outcomes
    }

    private func send(_ target: PingTarget, ipv6: Bool) {
        target.sequence &+= 1
        let sequence = target.sequence
        let packet = ICMPEcho.request(identifier: identifier, sequence: sequence, payload: cookie, ipv6: ipv6)
        let sentAt = clock()
        target.tracker.sent(sequence: sequence, at: sentAt)
        let sent = packet.withUnsafeBytes { Darwin.send(target.socket, $0.baseAddress, $0.count, 0) }
        if sent != packet.count {
            target.record(target.tracker.sendFailed(sequence: sequence, at: sentAt))
        }
    }
}

/// A target's socket, address and measurements. Touched on the monitor's
/// queue, except the lookup result, which the lookup queue hands over under
/// the lock.
private final class PingTarget {
    let host: PingHost
    var address: PingAddress?
    var socket: CInt = -1
    var tracker = PingTracker()
    var history = PingHistory()
    var sequence: UInt16 = 0
    var lastRTT: TimeInterval?
    var problem: PingReading.Problem?
    var lookedUpAt: TimeInterval = -.infinity
    var lookupInFlight = false

    private let lock = NSLock()
    private var lookupResult: PingAddress??

    init(host: PingHost) {
        self.host = host
    }

    func record(_ outcome: PingTracker.Outcome) {
        history.record(outcome.sample)
        if let rtt = outcome.sample.rtt { lastRTT = rtt }
    }

    func finishLookup(_ address: PingAddress?) {
        lock.withLock { lookupResult = .some(address) }
    }

    /// The finished lookup, once: `.some(nil)` for a failure.
    func takeLookup() -> PingAddress?? {
        lock.withLock {
            guard let result = lookupResult else { return nil }
            lookupResult = nil
            lookupInFlight = false
            return result
        }
    }

    func close() {
        if socket >= 0 { Darwin.close(socket) }
        socket = -1
    }
}

/// A resolved socket address, copied out of `getaddrinfo`.
private struct PingAddress: Equatable {
    let family: Int32
    let text: String
    private let storage: [UInt8]

    var ipv6: Bool { family == AF_INET6 }

    static func == (lhs: PingAddress, rhs: PingAddress) -> Bool {
        lhs.family == rhs.family && lhs.storage == rhs.storage
    }

    func withSockaddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        storage.withUnsafeBytes { raw in
            body(raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(raw.count))
        }
    }

    /// Blocking for names. Takes the first address the system prefers, which
    /// already follows its IPv4/IPv6 policy.
    static func resolve(_ host: PingHost) -> PingAddress? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = host.kind == .name ? AI_ADDRCONFIG : AI_NUMERICHOST
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host.text, nil, &hints, &list) == 0 else { return nil }
        defer { freeaddrinfo(list) }
        var cursor = list
        while let info = cursor?.pointee {
            cursor = info.ai_next
            guard info.ai_family == AF_INET || info.ai_family == AF_INET6,
                  let socketAddress = info.ai_addr else { continue }
            let bytes = Array(UnsafeRawBufferPointer(start: UnsafeRawPointer(socketAddress),
                                                     count: Int(info.ai_addrlen)))
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress, info.ai_addrlen, &name, socklen_t(name.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return PingAddress(family: info.ai_family, text: String(cString: name), storage: bytes)
        }
        return nil
    }
}
