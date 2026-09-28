// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

/// Live ICMP ping for any number of targets, independent of the system
/// monitor's sampling tick.
///
/// Each target owns an unprivileged ICMP datagram socket (no root, no helper)
/// connected to its address, and a strict timer that sends one echo per
/// interval. Every reply and every timeout is published the moment it happens,
/// so a view bound to `statuses` or `samples` is as current as a terminal
/// running `ping`. Reachability is decided by `PingTracker`: one miss makes a
/// target suspect and sends an extra probe right away, two make it down.
///
/// All probe state lives on one serial queue; published values are pushed to
/// the main thread.
final class PingService: ObservableObject {
    static let shared = PingService()

    enum Problem: Equatable {
        /// The name did not resolve; retried every `retrySeconds`.
        case unresolved
        /// The ICMP socket could not be opened, with its errno.
        case socket(Int32)
    }

    struct Status {
        let host: PingHost
        var address: String?
        var state: PingTracker.State = .unknown
        var lastRTT: TimeInterval?
        var smoothedRTT: TimeInterval?
        var history = PingHistory()
        var problem: Problem?
    }

    struct Event {
        let target: UUID
        let sample: PingSample
        let state: PingTracker.State
    }

    static let defaultInterval: TimeInterval = 1
    static let minimumInterval: TimeInterval = 0.2
    static let retrySeconds: TimeInterval = 5
    /// Names are looked up again this often, so a moved host is followed.
    static let refreshSeconds: TimeInterval = 300

    @Published private(set) var statuses: [UUID: Status] = [:]
    /// One event per reply or timeout, on the main thread, in order.
    let samples = PassthroughSubject<Event, Never>()

    private let queue = DispatchQueue(label: "com.vorssaint.ping", qos: .userInitiated)
    private var probes: [UUID: PingProbe] = [:]     // touched only on `queue`
    private var activity: NSObjectProtocol?         // touched only on main

    /// Starts pinging `host` and returns the id its status is published under.
    @discardableResult
    func start(_ host: PingHost, interval: TimeInterval = PingService.defaultInterval) -> UUID {
        let id = UUID()
        statuses[id] = Status(host: host)
        updateActivity()
        let interval = max(interval, Self.minimumInterval)
        queue.async {
            let probe = PingProbe(id: id, host: host, interval: interval, queue: self.queue) { [weak self] update in
                self?.publish(update)
            }
            self.probes[id] = probe
            probe.start()
        }
        return id
    }

    func stop(_ id: UUID) {
        statuses[id] = nil
        updateActivity()
        queue.async { self.probes.removeValue(forKey: id)?.stop() }
    }

    func stopAll() {
        statuses.removeAll()
        updateActivity()
        queue.async {
            self.probes.values.forEach { $0.stop() }
            self.probes.removeAll()
        }
    }

    private func publish(_ update: PingProbe.Update) {
        DispatchQueue.main.async {
            // A reply can still be in flight to main after `stop`.
            guard self.statuses[update.id] != nil else { return }
            self.statuses[update.id] = update.status
            if let sample = update.sample {
                self.samples.send(Event(target: update.id, sample: sample, state: update.status.state))
            }
        }
    }

    /// App Nap would stretch the probe timers of a menu bar app without a
    /// visible window, which is exactly the lag a live ping must not have.
    private func updateActivity() {
        if statuses.isEmpty, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        } else if !statuses.isEmpty, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Live ping")
        }
    }
}

/// One target: its address, socket, timers and tracker. Lives on the
/// service's queue and is touched nowhere else.
private final class PingProbe {
    struct Update {
        let id: UUID
        let status: PingService.Status
        let sample: PingSample?
    }

    private let id: UUID
    private let host: PingHost
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private let report: (Update) -> Void

    private var status: PingService.Status
    private var tracker = PingTracker()
    private var address: PingAddress?
    private var socket: CInt = -1
    private var readSource: DispatchSourceRead?
    private var sendTimer: DispatchSourceTimer?
    private var retryWork: DispatchWorkItem?
    private var sequence: UInt16 = 0
    /// Echoed back verbatim; filters out replies to anyone else's pings
    /// without trusting the kernel to keep the identifier as sent.
    private let cookie: [UInt8]
    private let identifier = UInt16.random(in: .min ... .max)
    /// Bumped on every restart so stale timeouts and lookups fall through.
    private var generation = 0
    private var resolvedAt: TimeInterval = -.infinity
    private var stopped = false

    init(id: UUID, host: PingHost, interval: TimeInterval, queue: DispatchQueue,
         report: @escaping (Update) -> Void) {
        self.id = id
        self.host = host
        self.interval = interval
        self.queue = queue
        self.report = report
        status = PingService.Status(host: host)
        cookie = (0..<8).map { _ in UInt8.random(in: .min ... .max) }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        resolve()
    }

    func stop() {
        stopped = true
        generation += 1
        retryWork?.cancel()
        closeSocket()
    }

    // MARK: Resolution

    private func resolve() {
        let generation = self.generation
        let host = self.host
        DispatchQueue.global(qos: .userInitiated).async {
            let address = PingAddress.resolve(host)
            self.queue.async {
                guard !self.stopped, generation == self.generation else { return }
                self.resolved(address)
            }
        }
    }

    private func resolved(_ address: PingAddress?) {
        resolvedAt = now
        guard let address else {
            if self.address == nil {
                status.problem = .unresolved
                status.state = .down
                emit(nil)
                scheduleRetry(after: PingService.retrySeconds)
            } else {
                // Keep pinging the last known address; DNS being down is not
                // the host being down.
                scheduleRetry(after: PingService.retrySeconds)
            }
            return
        }
        if address == self.address, socket >= 0 { return }
        self.address = address
        tracker.reset()
        status.address = address.text
        status.problem = nil
        status.state = tracker.state
        status.smoothedRTT = nil
        openSocket(address)
        emit(nil)
    }

    private func scheduleRetry(after seconds: TimeInterval) {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.resolve()
        }
        retryWork = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Socket

    private func openSocket(_ address: PingAddress) {
        closeSocket()
        generation += 1
        let fd = Darwin.socket(address.family, SOCK_DGRAM, address.ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else {
            fail(.socket(errno))
            return
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        // Connected, the kernel only delivers ICMP from this address.
        let connected = address.withSockaddr { Darwin.connect(fd, $0, $1) }
        guard connected == 0 else {
            let code = errno
            close(fd)
            fail(.socket(code))
            return
        }
        socket = fd

        let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        read.setEventHandler { [weak self] in self?.receive() }
        read.setCancelHandler { close(fd) }
        read.resume()
        readSource = read

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.send() }
        timer.resume()
        sendTimer = timer
    }

    private func closeSocket() {
        sendTimer?.cancel()
        sendTimer = nil
        if let readSource {
            readSource.cancel()          // closes the descriptor
        } else if socket >= 0 {
            close(socket)
        }
        readSource = nil
        socket = -1
    }

    private func fail(_ problem: PingService.Problem) {
        status.problem = problem
        status.state = .down
        emit(nil)
        address = nil
        scheduleRetry(after: PingService.retrySeconds)
    }

    // MARK: Probes

    private func send() {
        guard socket >= 0, let address else { return }
        sequence &+= 1
        let sequence = self.sequence
        let packet = ICMPEcho.request(identifier: identifier, sequence: sequence,
                                      payload: cookie, ipv6: address.ipv6)
        let sentAt = now
        let timeout = tracker.sent(sequence: sequence, at: sentAt)
        let sent = packet.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) }
        guard sent == packet.count else {
            apply(tracker.sendFailed(sequence: sequence, at: sentAt))
            return
        }
        let generation = self.generation
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, generation == self.generation else { return }
            if let outcome = self.tracker.expired(sequence: sequence, at: self.now) {
                self.apply(outcome)
            }
        }
    }

    private func receive() {
        guard socket >= 0, let address else { return }
        var buffer = [UInt8](repeating: 0, count: 2048)
        // Drain what is queued, bounded so a flood cannot starve the timers.
        for _ in 0..<32 {
            let count = recv(socket, &buffer, buffer.count, 0)
            let receivedAt = now
            guard count > 0 else { return }
            guard let reply = ICMPEcho.parseReply(Array(buffer[..<count]), ipv6: address.ipv6),
                  reply.payload.starts(with: cookie),
                  let outcome = tracker.received(sequence: reply.sequence, at: receivedAt)
            else { continue }
            apply(outcome)
        }
    }

    private func apply(_ outcome: PingTracker.Outcome) {
        status.state = outcome.state
        status.history.record(outcome.sample)
        if let rtt = outcome.sample.rtt { status.lastRTT = rtt }
        status.smoothedRTT = tracker.estimator.smoothedRTT
        emit(outcome.sample)
        if outcome.probeNow { send() }
        // A host that went down may have moved; look it up again, but not
        // more often than the retry interval.
        let sinceLookup = now - resolvedAt
        if host.kind == .name,
           (outcome.state == .down && sinceLookup >= PingService.retrySeconds)
            || sinceLookup >= PingService.refreshSeconds {
            resolvedAt = now
            resolve()
        }
    }

    private func emit(_ sample: PingSample?) {
        report(Update(id: id, status: status, sample: sample))
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

    /// Blocking; called off the probe queue. Takes the first address the
    /// system prefers, which already follows its IPv4/IPv6 policy.
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
