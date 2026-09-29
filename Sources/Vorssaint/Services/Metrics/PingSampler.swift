// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import SystemConfiguration

final class PingSampler {
    static let refreshSeconds: TimeInterval = 300
    static let retrySeconds: TimeInterval = 5

    private let lookupQueue = DispatchQueue(label: "com.vorssaint.ping.lookup", qos: .utility)
    private let clock: () -> TimeInterval
    private var targets: [PingHost: PingTarget] = [:]
    private let cookie = (0..<8).map { _ in UInt8.random(in: .min ... .max) }
    private let identifier = UInt16.random(in: .min ... .max)
    private var buffer = [UInt8](repeating: 0, count: 1024)
    private var control = [UInt8](repeating: 0, count: 64)

    init(clock: @escaping () -> TimeInterval = { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }) {
        self.clock = clock
    }

    func sample(targets hosts: [PingHost], slotSeconds: TimeInterval) -> [PingReading] {
        let wanted = Set(hosts)
        for (host, target) in targets where !wanted.contains(host) {
            target.close()
            targets[host] = nil
        }
        return hosts.map { host in
            let target = targets[host] ?? PingTarget(host: host)
            targets[host] = target
            return read(target, slotSeconds: slotSeconds)
        }
    }

    func pause() {
        for target in targets.values {
            target.close()
            target.tracker = PingTracker()
        }
    }

    private func read(_ target: PingTarget, slotSeconds: TimeInterval) -> PingReading {
        let now = clock()
        adoptLookup(of: target)
        lookUpIfDue(target, now: now)

        if let address = target.address, target.socket < 0 {
            target.problem = openSocket(target, address: address)
            if target.problem != nil { target.address = nil }
        }

        if target.socket >= 0, let address = target.address {
            for outcome in drain(target, ipv6: address.ipv6) { target.record(outcome) }
            for outcome in target.tracker.expire(now: clock()) { target.record(outcome) }
            send(target, ipv6: address.ipv6)
        }

        var reading = PingReading(host: target.host)
        reading.address = target.address?.text
        reading.problem = target.problem
        reading.state = target.tracker.state
        reading.lastRTT = target.lastRTT
        reading.showsSeconds = target.showsSeconds
        let window = target.history.window(now: now, slotSeconds: slotSeconds)
        reading.slotSeconds = slotSeconds
        reading.lossRatio = target.history.lossRatio(now: now)
        reading.rttHistory = window.rttMs
        reading.lostHistory = window.lost
        reading.recentHistory = target.history.recent
        return reading
    }

    private func lookUpIfDue(_ target: PingTarget, now: TimeInterval) {
        guard !target.lookupInFlight else { return }
        let sinceLookup = now - target.lookedUpAt
        let due: Bool
        if target.address == nil {
            due = sinceLookup >= Self.retrySeconds
        } else if !target.host.isLiteral {
            due = sinceLookup >= Self.refreshSeconds
                || (target.tracker.state == .down && sinceLookup >= Self.retrySeconds)
        } else {
            due = false
        }
        guard due else { return }
        target.lookedUpAt = now
        if target.host.isLiteral {
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
            if target.address == nil { target.problem = .unresolved }
            return
        }
        guard address != target.address || target.socket < 0 else { return }
        target.close()
        target.address = address
        target.tracker = PingTracker()
        target.problem = openSocket(target, address: address)
        if target.problem != nil { target.address = nil }
    }

    private func openSocket(_ target: PingTarget, address: PingAddress) -> PingReading.Problem? {
        let fd = socket(address.family, SOCK_DGRAM, address.ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else { return .socket(errno) }
        guard fcntl(fd, F_SETNOSIGPIPE, 1) != -1 else {
            let code = errno
            Darwin.close(fd)
            return .socket(code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_TIMESTAMP, &on, socklen_t(MemoryLayout<Int32>.size))
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
        guard sent != packet.count else { return }
        let code = sent < 0 ? errno : 0
        target.record(target.tracker.sendFailed(sequence: sequence, at: sentAt))
        if PingSocketError.needsNewSocket(code) { target.close() }
    }
}

private final class PingTarget {
    let host: PingHost
    var address: PingAddress?
    var socket: CInt = -1
    var tracker = PingTracker()
    var history = PingHistory()
    var sequence: UInt16 = 0
    var lastRTT: TimeInterval?
    var showsSeconds = false
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
        if let rtt = outcome.sample.rtt {
            lastRTT = rtt
            showsSeconds = PingFormat.showsSeconds(rtt, previously: showsSeconds)
        }
    }

    func finishLookup(_ address: PingAddress?) {
        lock.withLock { lookupResult = .some(address) }
    }

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

    static func resolve(_ host: PingHost) -> PingAddress? {
        var name = host.text
        if host.kind == .gateway {
            guard let router = gatewayAddress() else { return nil }
            name = router
        }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = host.kind == .name ? AI_ADDRCONFIG : AI_NUMERICHOST
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &list) == 0 else { return nil }
        defer { freeaddrinfo(list) }
        var cursor = list
        while let info = cursor?.pointee {
            cursor = info.ai_next
            guard info.ai_family == AF_INET || info.ai_family == AF_INET6,
                  let socketAddress = info.ai_addr else { continue }
            let bytes = Array(UnsafeRawBufferPointer(start: UnsafeRawPointer(socketAddress),
                                                     count: Int(info.ai_addrlen)))
            var numeric = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress, info.ai_addrlen, &numeric, socklen_t(numeric.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return PingAddress(family: info.ai_family, text: String(cString: numeric), storage: bytes)
        }
        return nil
    }

    private static func gatewayAddress() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Vorssaint.ping" as CFString, nil, nil) else { return nil }
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
               let router = value["Router"] as? String, !router.isEmpty {
                return router
            }
        }
        return nil
    }
}
