// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The live ping's decisions: target parsing, adaptive timeouts, the
/// suspect/down state machine, history and ICMP framing. Times are scripted.
enum PingTrackerTests {
    static func run(_ suite: TestSuite) {
        hosts(suite)
        estimator(suite)
        stateMachine(suite)
        lateAndStaleReplies(suite)
        history(suite)
        framing(suite)
    }

    private static func hosts(_ suite: TestSuite) {
        suite.expect(PingHost("1.1.1.1")?.kind == .ipv4, "a dotted quad is an IPv4 literal")
        suite.expect(PingHost("2606:4700::1111")?.kind == .ipv6, "an IPv6 address is an IPv6 literal")
        suite.expect(PingHost("[::1]")?.text == "::1", "brackets around an IPv6 literal are dropped")
        suite.expect(PingHost("  Example.COM. ")?.text == "example.com",
                     "a name is trimmed, lowercased and loses its root dot")
        suite.expect(PingHost("router")?.kind == .name, "a single-label local name is accepted")
        suite.expect(PingHost("https://www.apple.com/de/")?.text == "www.apple.com",
                     "a pasted URL is reduced to its host")
        for invalid in ["", "   ", "256.1.1.1", "1.2.3", "exa mple.com", "-bad.com", "a..b", "host:80"] {
            suite.expect(PingHost(invalid) == nil, "\(invalid.debugDescription) is not a ping target")
        }
    }

    private static func estimator(_ suite: TestSuite) {
        var estimator = PingTimeoutEstimator()
        suite.expectClose(estimator.timeout, PingTimeoutEstimator.initialTimeout,
                          "before any reply the timeout is the initial one")
        for _ in 0..<40 { estimator.observe(rtt: 0.012) }
        suite.expectClose(estimator.timeout, PingTimeoutEstimator.minimumTimeout,
                          "a steady fast host is held to the minimum timeout, not its tiny RTT")
        suite.expectClose(estimator.smoothedRTT ?? 0, 0.012, "a steady RTT smooths to itself")

        var steadySlow = PingTimeoutEstimator()
        for _ in 0..<40 { steadySlow.observe(rtt: 0.6) }
        suite.expect(steadySlow.timeout > 0.6 && steadySlow.timeout < 0.8,
                     "a steady slow host waits just past its RTT (\(steadySlow.timeout))")

        var jittery = PingTimeoutEstimator()
        for index in 0..<40 { jittery.observe(rtt: index.isMultiple(of: 2) ? 0.2 : 0.6) }
        suite.expect(jittery.timeout > steadySlow.timeout,
                     "jitter widens the timeout beyond the mean RTT")

        var huge = PingTimeoutEstimator()
        huge.observe(rtt: 30)
        suite.expectClose(huge.timeout, PingTimeoutEstimator.maximumTimeout,
                          "the timeout never exceeds the maximum")
        huge.observe(rtt: .nan)
        huge.observe(rtt: -1)
        suite.expectClose(huge.smoothedRTT ?? 0, 30, "invalid RTTs are ignored")
        huge.reset()
        suite.expect(huge.smoothedRTT == nil, "reset forgets every measurement")
    }

    private static func stateMachine(_ suite: TestSuite) {
        var tracker = PingTracker()
        suite.expect(tracker.state == .unknown, "a new target is unknown")

        _ = tracker.sent(sequence: 1, at: 0)
        let up = tracker.received(sequence: 1, at: 0.02)
        suite.expect(up?.state == .up && up?.stateChanged == true && up?.probeNow == false,
                     "the first reply brings the target up")
        suite.expectClose(up?.sample.rtt ?? -1, 0.02, "the reply carries its round trip")
        suite.expect(tracker.received(sequence: 1, at: 0.03) == nil, "a duplicate reply is ignored")
        suite.expect(tracker.received(sequence: 99, at: 0.03) == nil, "a reply to nothing sent is ignored")

        _ = tracker.sent(sequence: 2, at: 1)
        let suspect = tracker.expired(sequence: 2, at: 1.3)
        suite.expect(suspect?.state == .suspect && suspect?.stateChanged == true,
                     "one missed reply only makes the target suspect")
        suite.expect(suspect?.probeNow == true, "a suspect target asks for an extra probe at once")
        suite.expect(suspect?.sample.rtt == nil, "the miss is published as a lost sample")
        suite.expect(tracker.expired(sequence: 2, at: 1.4) == nil, "a probe expires only once")

        _ = tracker.sent(sequence: 3, at: 1.3)
        let down = tracker.expired(sequence: 3, at: 1.6)
        suite.expect(down?.state == .down && down?.stateChanged == true && down?.probeNow == false,
                     "the second consecutive miss marks the target down")

        _ = tracker.sent(sequence: 4, at: 2)
        let stillDown = tracker.expired(sequence: 4, at: 2.3)
        suite.expect(stillDown?.state == .down && stillDown?.stateChanged == false
                         && stillDown?.probeNow == false,
                     "further misses keep it down without extra probes")

        _ = tracker.sent(sequence: 5, at: 3)
        let recovered = tracker.received(sequence: 5, at: 3.015)
        suite.expect(recovered?.state == .up && recovered?.stateChanged == true,
                     "the next reply recovers a down target")
        suite.expect(tracker.consecutiveMisses == 0, "a reply clears the miss count")

        _ = tracker.sent(sequence: 6, at: 4)
        _ = tracker.expired(sequence: 6, at: 4.3)
        _ = tracker.sent(sequence: 7, at: 4.3)
        let saved = tracker.received(sequence: 7, at: 4.32)
        suite.expect(saved?.state == .up && saved?.stateChanged == true,
                     "an answered extra probe clears a suspect target without it going down")

        var unsent = PingTracker()
        _ = unsent.sent(sequence: 1, at: 0)
        let failed = unsent.sendFailed(sequence: 1, at: 0)
        suite.expect(failed.state == .suspect && failed.probeNow, "a send that fails counts as a miss at once")
        suite.expect(unsent.received(sequence: 1, at: 0.01) == nil, "a failed send expects no reply")

        var timed = PingTracker()
        suite.expectClose(timed.sent(sequence: 1, at: 0), PingTimeoutEstimator.initialTimeout,
                          "the first probe waits the initial timeout")
        _ = timed.received(sequence: 1, at: 0.01)
        suite.expect(timed.sent(sequence: 2, at: 1) < PingTimeoutEstimator.initialTimeout,
                     "later probes wait for a timeout learned from replies")
    }

    private static func lateAndStaleReplies(_ suite: TestSuite) {
        var tracker = PingTracker()
        _ = tracker.sent(sequence: 1, at: 0)
        _ = tracker.received(sequence: 1, at: 0.01)
        _ = tracker.sent(sequence: 2, at: 1)
        _ = tracker.expired(sequence: 2, at: 1.3)
        let late = tracker.received(sequence: 2, at: 1.8)
        suite.expect(late?.state == .up && late?.sample.late == true,
                     "a late reply still proves the host is up and is marked late")
        suite.expectClose(late?.sample.rtt ?? -1, 0.8, "a late reply keeps its true round trip")
        suite.expect((tracker.estimator.smoothedRTT ?? 0) > 0.01,
                     "a late reply teaches the estimator that replies can take longer")

        var overlap = PingTracker()
        _ = overlap.sent(sequence: 1, at: 0)
        _ = overlap.sent(sequence: 2, at: 1)
        _ = overlap.received(sequence: 2, at: 1.02)
        let stale = overlap.expired(sequence: 1, at: 1.1)
        suite.expect(stale?.sample.rtt == nil && stale?.state == .up && stale?.stateChanged == false
                         && stale?.probeNow == false,
                     "losing a probe older than one already answered does not make the target suspect")
        suite.expect(overlap.consecutiveMisses == 0, "a stale loss does not count as a miss")

        var crowded = PingTracker()
        for sequence in 0..<200 { _ = crowded.sent(sequence: UInt16(sequence), at: Double(sequence) * 0.01) }
        suite.expect(crowded.received(sequence: 0, at: 2.5) == nil,
                     "the oldest unanswered probes are forgotten once too many are waiting")
        suite.expect(crowded.received(sequence: 199, at: 2.5) != nil, "the newest probe is still matched")

        var old = PingTracker()
        _ = old.sent(sequence: 1, at: 0)
        _ = old.sent(sequence: 2, at: PingTracker.rememberedSeconds + 1)
        suite.expect(old.received(sequence: 1, at: PingTracker.rememberedSeconds + 1.1) == nil,
                     "a reply after the remembered window is not matched")
    }

    private static func history(_ suite: TestSuite) {
        var history = PingHistory()
        history.record(PingSample(sequence: 1, sentAt: 0, rtt: 0.02, late: false))
        history.record(PingSample(sequence: 2, sentAt: 1, rtt: nil, late: false))
        history.record(PingSample(sequence: 2, sentAt: 1, rtt: 0.9, late: true))
        history.record(PingSample(sequence: 3, sentAt: 2, rtt: 0.03, late: false))
        suite.expect(history.rttMs.values == [20, 0, 30], "history keeps milliseconds with 0 for a loss")
        suite.expect(history.lost.values == [0, 1, 0], "the loss ring stays aligned with the RTT ring")
        suite.expectClose(history.lossRatio, 1.0 / 3, "loss ratio is over the recorded probes")
        for sequence in 0..<300 {
            history.record(PingSample(sequence: UInt16(sequence), sentAt: 0, rtt: 0.01, late: false))
        }
        suite.expect(history.rttMs.values.count == PingHistory.capacity
                         && history.lost.values.count == PingHistory.capacity,
                     "both rings stop at the shared capacity")
        suite.expect(PingHistory().lossRatio == 0, "an empty history has no loss")
    }

    private static func framing(_ suite: TestSuite) {
        let payload: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let v4 = ICMPEcho.request(identifier: 0xBEEF, sequence: 0x0102, payload: payload, ipv6: false)
        suite.expect(v4[0] == ICMPEcho.requestV4 && v4.count == ICMPEcho.headerLength + payload.count,
                     "an IPv4 echo request has the echo type and carries the payload")
        suite.expect(ICMPEcho.checksum(v4) == 0, "an IPv4 request carries a valid checksum")
        suite.expect(ICMPEcho.checksum([0x45, 0x00, 0x00, 0x73]) == ~UInt16(0x4573),
                     "the checksum is the ones' complement sum")

        var reply = v4
        reply[0] = ICMPEcho.replyV4
        reply[2] = 0; reply[3] = 0
        let sum = ICMPEcho.checksum(reply)
        reply[2] = UInt8(sum >> 8); reply[3] = UInt8(sum & 0xff)
        let ipHeader: [UInt8] = [0x45] + [UInt8](repeating: 0, count: 19)
        let parsed = ICMPEcho.parseReply(ipHeader + reply, ipv6: false)
        suite.expect(parsed == ICMPEcho.Reply(identifier: 0xBEEF, sequence: 0x0102, payload: payload),
                     "an IPv4 reply is read past its IP header")
        suite.expect(ICMPEcho.parseReply(reply, ipv6: false)?.sequence == 0x0102,
                     "an IPv4 reply without an IP header is read too")
        var corrupt = ipHeader + reply
        corrupt[corrupt.count - 1] ^= 0xff
        suite.expect(ICMPEcho.parseReply(corrupt, ipv6: false) == nil, "a corrupted IPv4 reply is dropped")
        suite.expect(ICMPEcho.parseReply(ipHeader + v4, ipv6: false) == nil,
                     "our own echo request is not a reply")
        suite.expect(ICMPEcho.parseReply(Array(reply.prefix(5)), ipv6: false) == nil,
                     "a truncated packet is dropped")

        let v6 = ICMPEcho.request(identifier: 7, sequence: 9, payload: payload, ipv6: true)
        suite.expect(v6[0] == ICMPEcho.requestV6 && v6[2] == 0 && v6[3] == 0,
                     "an IPv6 request leaves the checksum to the kernel")
        var v6Reply = v6
        v6Reply[0] = ICMPEcho.replyV6
        suite.expect(ICMPEcho.parseReply(v6Reply, ipv6: true)
                         == ICMPEcho.Reply(identifier: 7, sequence: 9, payload: payload),
                     "an IPv6 reply arrives without an IP header")
        var neighbor = v6Reply
        neighbor[0] = 135
        suite.expect(ICMPEcho.parseReply(neighbor, ipv6: true) == nil, "other ICMPv6 messages are ignored")
    }
}
