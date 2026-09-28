// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PingTrackerTests {
    static func run(_ suite: TestSuite) {
        hosts(suite)
        estimator(suite)
        stateMachine(suite)
        lateAndStaleReplies(suite)
        history(suite)
        framing(suite)
        targets(suite)
        readings(suite)
        strings(suite)
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

        tracker.sent(sequence: 1, at: 0)
        let up = tracker.received(sequence: 1, at: 0.02)
        suite.expect(up?.state == .up && up?.stateChanged == true, "the first reply brings the target up")
        suite.expectClose(up?.sample.rtt ?? -1, 0.02, "the reply carries its round trip")
        suite.expect(tracker.received(sequence: 1, at: 0.03) == nil, "a duplicate reply is ignored")
        suite.expect(tracker.received(sequence: 99, at: 0.03) == nil, "a reply to nothing sent is ignored")

        let timeout = tracker.sent(sequence: 2, at: 1)
        suite.expect(tracker.expire(now: 1 + timeout - 0.01).isEmpty, "a probe is not lost before its timeout")
        let suspect = tracker.expire(now: 2)
        suite.expect(suspect.count == 1 && suspect.first?.state == .suspect && suspect.first?.stateChanged == true,
                     "one missed reply only makes the target suspect")
        suite.expect(suspect.first?.sample.rtt == nil, "the miss is published as a lost sample")
        suite.expect(tracker.expire(now: 2.5).isEmpty, "a probe expires only once")

        tracker.sent(sequence: 3, at: 2)
        let down = tracker.expire(now: 3)
        suite.expect(down.first?.state == .down && down.first?.stateChanged == true,
                     "the second consecutive miss marks the target down")

        tracker.sent(sequence: 4, at: 3)
        let stillDown = tracker.expire(now: 4)
        suite.expect(stillDown.first?.state == .down && stillDown.first?.stateChanged == false,
                     "further misses keep it down")

        tracker.sent(sequence: 5, at: 4)
        let recovered = tracker.received(sequence: 5, at: 4.015)
        suite.expect(recovered?.state == .up && recovered?.stateChanged == true,
                     "the next reply recovers a down target")
        suite.expect(tracker.consecutiveMisses == 0, "a reply clears the miss count")

        tracker.sent(sequence: 6, at: 5)
        _ = tracker.expire(now: 6)
        tracker.sent(sequence: 7, at: 6)
        let saved = tracker.received(sequence: 7, at: 6.02)
        suite.expect(saved?.state == .up && saved?.stateChanged == true,
                     "a reply on the next tick clears a suspect target without it going down")

        var batch = PingTracker()
        batch.sent(sequence: 1, at: 0)
        batch.sent(sequence: 2, at: 0.5)
        let both = batch.expire(now: 10)
        suite.expect(both.map(\.sample.sequence) == [1, 2] && both.last?.state == .down,
                     "probes that expire in the same tick are judged oldest first")

        var unsent = PingTracker()
        unsent.sent(sequence: 1, at: 0)
        let failed = unsent.sendFailed(sequence: 1, at: 0)
        suite.expect(failed.state == .suspect, "a send that fails counts as a miss at once")
        suite.expect(unsent.received(sequence: 1, at: 0.01) == nil, "a failed send expects no reply")

        var timed = PingTracker()
        suite.expectClose(timed.sent(sequence: 1, at: 0), PingTimeoutEstimator.initialTimeout,
                          "the first probe waits the initial timeout")
        _ = timed.received(sequence: 1, at: 0.01)
        suite.expect(timed.sent(sequence: 2, at: 1) < PingTimeoutEstimator.initialTimeout,
                     "later probes wait for a timeout learned from replies")

        var slow = PingTracker()
        for sequence in 0..<20 {
            slow.sent(sequence: UInt16(sequence), at: Double(sequence))
            _ = slow.received(sequence: UInt16(sequence), at: Double(sequence) + 1.4)
        }
        slow.sent(sequence: 100, at: 100)
        suite.expect(slow.expire(now: 101).isEmpty,
                     "on a link slower than the tick, a probe survives the next tick")
        suite.expect(slow.received(sequence: 100, at: 101.4)?.sample.late == false,
                     "and its reply on the tick after is on time, not late")
    }

    private static func lateAndStaleReplies(_ suite: TestSuite) {
        var tracker = PingTracker()
        tracker.sent(sequence: 1, at: 0)
        _ = tracker.received(sequence: 1, at: 0.01)
        tracker.sent(sequence: 2, at: 1)
        _ = tracker.expire(now: 2)
        let late = tracker.received(sequence: 2, at: 2.1)
        suite.expect(late?.state == .up && late?.sample.late == true,
                     "a late reply still proves the host is up and is marked late")
        suite.expectClose(late?.sample.rtt ?? -1, 1.1, "a late reply keeps its true round trip")
        suite.expect((tracker.estimator.smoothedRTT ?? 0) > 0.01,
                     "a late reply teaches the estimator that replies can take longer")

        var overlap = PingTracker()
        overlap.sent(sequence: 1, at: 0)
        overlap.sent(sequence: 2, at: 1)
        _ = overlap.received(sequence: 2, at: 1.02)
        let stale = overlap.expire(now: 2).first
        suite.expect(stale?.sample.rtt == nil && stale?.state == .up && stale?.stateChanged == false,
                     "losing a probe older than one already answered does not make the target suspect")
        suite.expect(overlap.consecutiveMisses == 0, "a stale loss does not count as a miss")

        var crowded = PingTracker()
        for sequence in 0..<200 { crowded.sent(sequence: UInt16(sequence), at: Double(sequence) * 0.01) }
        suite.expect(crowded.received(sequence: 0, at: 2.5) == nil,
                     "the oldest unanswered probes are forgotten once too many are waiting")
        suite.expect(crowded.received(sequence: 199, at: 2.5) != nil, "the newest probe is still matched")

        var old = PingTracker()
        old.sent(sequence: 1, at: 0)
        old.sent(sequence: 2, at: PingTracker.rememberedSeconds + 1)
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

    private static func targets(_ suite: TestSuite) {
        suite.expect(PingHost(PingHost.gatewayToken) == PingHost.gateway && PingHost.gateway.kind == .gateway,
                     "the router token parses to the gateway target")
        suite.expect(PingHost("router")?.kind == .name, "a host literally named router stays a name")
        suite.expect(!PingHost.gateway.isLiteral && PingHost("1.1.1.1")?.isLiteral == true,
                     "only address literals skip lookups")
        let defaults = PingTargets.hosts(from: PingTargets.defaultList)
        suite.expect(defaults == [PingHost.gateway, PingHost("1.1.1.1")!],
                     "the default targets are the router and 1.1.1.1")
        suite.expect(PingTargets.hosts(from: "1.1.1.1\n\nbad host\n1.1.1.1\nExample.com") == [PingHost("1.1.1.1")!, PingHost("example.com")!],
                     "saved targets skip blanks, invalid entries and duplicates")
        let many = (1...10).map { "10.0.0.\($0)" }.joined(separator: "\n")
        suite.expect(PingTargets.hosts(from: many).count == PingTargets.maximumCount, "targets are capped")
        let added = PingTargets.adding(PingHost("8.8.8.8")!, to: PingTargets.defaultList)
        suite.expect(PingTargets.hosts(from: added).last == PingHost("8.8.8.8"), "a new target goes last")
        suite.expect(PingTargets.adding(PingHost("1.1.1.1")!, to: PingTargets.defaultList) == PingTargets.defaultList,
                     "adding a present target changes nothing")
        suite.expect(PingTargets.hosts(from: PingTargets.removing(PingHost.gateway, from: added))
                         == [PingHost("1.1.1.1")!, PingHost("8.8.8.8")!],
                     "removing a target keeps the others in order")
        let router = PingReading(host: PingHost.gateway)
        let cloudflare = PingReading(host: PingHost("1.1.1.1")!)
        suite.expect(PingTargets.menuBarReading(in: [router, cloudflare], pinned: "1.1.1.1") == cloudflare,
                     "the menu bar shows the pinned target")
        suite.expect(PingTargets.menuBarReading(in: [router, cloudflare], pinned: "gone.example") == router,
                     "a pinned target that was removed falls back to the first one")
        suite.expect(PingTargets.menuBarReading(in: [], pinned: "1.1.1.1") == nil, "no targets, no menu bar value")
    }

    private static func readings(_ suite: TestSuite) {
        var reading = PingReading(host: PingHost("1.1.1.1")!)
        reading.rttHistory = [12, 0, 14]
        reading.lostHistory = [0, 1, 0]
        let graph = reading.graphValues
        suite.expect(graph.count == 3 && graph[0] == 12 && graph[1].isNaN && graph[2] == 14,
                     "a lost probe is a gap in the graph, not a zero")
        suite.expect(reading.answeredMilliseconds == [12, 14], "statistics use answered probes only")
        suite.expect(!reading.isUnreachable, "an answering target is reachable")
        reading.state = .down
        suite.expect(reading.isUnreachable, "a down target is unreachable")
        var unresolved = PingReading(host: PingHost("nothing.invalid")!)
        unresolved.problem = .unresolved
        suite.expect(unresolved.isUnreachable, "a name that never resolved is unreachable")
        unresolved.problem = .resolving
        suite.expect(!unresolved.isUnreachable, "a name still resolving is not yet unreachable")

        MetricFormat.locale = Locale(identifier: "en_US")
        suite.expect(PingFormat.milliseconds(3.24) == "3.2", "fast round trips keep one decimal")
        suite.expect(PingFormat.milliseconds(14.6) == "15", "slower round trips are whole milliseconds")
        suite.expect(PingFormat.menuBarValue(0.0146) == "15" && PingFormat.menuBarValue(0.0042) == "4",
                     "the menu bar value is whole milliseconds without a unit")
        suite.expect(PingFormat.menuBarValue(0.0002) == "<1", "a sub-millisecond reply never reads as zero")
        suite.expect(PingFormat.menuBarValue(0.9994) == "999" && PingFormat.menuBarValue(1.2) == ">1s",
                     "the menu bar value is capped at three digits")
        suite.expect([0.0001, 0.0042, 0.0999, 0.5, 0.9994, 3.0].allSatisfy { PingFormat.menuBarValue($0).count <= 3 },
                     "every menu bar value fits three characters")
        suite.expect(PingFormat.menuBarLabel == "PING MS", "the unit sits in the menu bar label")
        suite.expect(PingMenuBarStyle(rawValue: "graph") == .graph && PingMenuBarStyle(rawValue: "dot") == .dot
                        && PingMenuBarStyle(rawValue: "bars") == nil,
                     "the menu bar ping style has a graph and a dot mode")
        suite.expect(PingFormat.menuBarValue(nil) == "–", "no reply yet reads as a dash")
        suite.expect(PingFormat.percent(0) == "0%" && PingFormat.percent(0.005) == "0.5%" && PingFormat.percent(0.25) == "25%",
                     "loss keeps a decimal only below one percent")
        suite.expect(PingFormat.summary([3, 4, 11]) == "3.0/6.0/11", "summary is min/avg/max")
        suite.expect(PingFormat.summary([]) == nil, "no answers, no summary")
        MetricFormat.locale = Locale(identifier: "de_DE")
        suite.expect(PingFormat.milliseconds(3.24) == "3,2", "milliseconds follow the region's decimal mark")
        MetricFormat.locale = .current
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
        func controlMessage(level: Int32, type: Int32, seconds: Int64, microseconds: Int32) -> [UInt8] {
            var bytes: [UInt8] = []
            func append<T>(_ value: T) { withUnsafeBytes(of: value) { bytes += $0 } }
            append(UInt32(28)); append(level); append(type)
            append(seconds); append(microseconds); append(Int32(0))
            return bytes
        }
        let stamp = controlMessage(level: 0xffff, type: 2, seconds: 1_800_000_000, microseconds: 250_000)
        suite.expectClose(ICMPEcho.kernelTimestamp(control: stamp, length: 28, level: 0xffff, type: 2) ?? 0,
                          1_800_000_000.25, "the kernel receive stamp is read from the control message")
        let other = controlMessage(level: 0xffff, type: 7, seconds: 1, microseconds: 0)
        suite.expectClose(ICMPEcho.kernelTimestamp(control: other + stamp, length: 56, level: 0xffff, type: 2) ?? 0,
                          1_800_000_000.25, "other control messages are skipped")
        suite.expect(ICMPEcho.kernelTimestamp(control: stamp, length: 20, level: 0xffff, type: 2) == nil,
                     "a truncated control buffer yields no stamp")
        suite.expect(ICMPEcho.kernelTimestamp(control: [], length: 0, level: 0xffff, type: 2) == nil,
                     "no control data yields no stamp")
        suite.expectClose(ICMPEcho.uptime(ofWallTime: 99.6, uptime: 500, wallNow: 100), 499.6,
                          "a reply stamped before the tick is placed back on the uptime clock")
        suite.expectClose(ICMPEcho.uptime(ofWallTime: 101, uptime: 500, wallNow: 100), 500,
                          "a stamp from the future falls back to the read time")
        suite.expectClose(ICMPEcho.uptime(ofWallTime: 0, uptime: 500, wallNow: 100), 500,
                          "a wall clock jump falls back to the read time")

        var neighbor = v6Reply
        neighbor[0] = 135
        suite.expect(ICMPEcho.parseReply(neighbor, ipv6: true) == nil, "other ICMPv6 messages are ignored")
    }

    private static func strings(_ suite: TestSuite) {
        let english = FeatureStrings.ping(.enUS)
        for language in AppLanguage.allCases {
            LocalizationTests.check(FeatureStrings.ping(language), against: english,
                                    name: "ping/\(language.rawValue)", suite: suite)
        }
    }
}
