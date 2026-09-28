// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PingGraphShape: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2 else { return path }
        let peak = max(20, (values.filter(\.isFinite).max() ?? 0) * 1.1)
        let step = rect.width / CGFloat(values.count - 1)
        var drawing = false
        for (index, value) in values.enumerated() {
            guard value.isFinite else {
                drawing = false
                continue
            }
            let point = CGPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.maxY - 0.5 - (rect.height - 1) * CGFloat(min(1, max(0, value / peak))))
            if drawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                drawing = true
            }
        }
        return path
    }
}

struct PingBlock: View {
    @Binding var isVisible: Bool
    var editing: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.pingTargets) private var targetsRaw = PingTargets.defaultList
    @AppStorage(DefaultsKey.monitorGraphNetwork) private var showGraph = true

    private var strings: PingFeatureStrings { FeatureStrings.ping(l10n.language) }
    private var hosts: [PingHost] { PingTargets.hosts(from: targetsRaw) }

    var body: some View {
        if !isVisible {
            PanelHiddenItemRow(title: strings.title,
                               systemImage: MenuBarMetric.ping.symbolName,
                               isVisible: $isVisible)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(strings.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if hosts.isEmpty {
                        statusText(strings.noTargets)
                    }
                    if editing {
                        PanelInlineHideButton(isVisible: $isVisible)
                    }
                }
                ForEach(hosts, id: \.self) { host in
                    row(host)
                }
            }
        }
    }

    private func reading(for host: PingHost) -> PingReading? {
        monitor.snapshot.pings.first { $0.host == host }
    }

    private func name(of host: PingHost) -> String {
        host.kind == .gateway ? strings.router : host.text
    }

    private func row(_ host: PingHost) -> some View {
        let reading = reading(for: host)
        let values = reading?.graphValues ?? []
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                statusDot(reading)
                Text(name(of: host))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if let address = reading?.address, address != host.text {
                    Text(address)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                value(for: reading)
            }
            if showGraph, values.count >= 2 {
                Sparkline(values: values,
                          color: graphColor(reading),
                          maxValue: max(20, (values.filter(\.isFinite).max() ?? 0) * 1.1),
                          fillOpacity: 0.14,
                          lineWidth: 1.3,
                          showsZeroBaseline: true,
                          gapMarkColor: PanelMetricColor.red(for: colorScheme))
                    .frame(height: 22)
            }
            if let reading, !reading.lostHistory.isEmpty {
                HStack(spacing: 10) {
                    Text("\(strings.loss) \(PingFormat.percent(reading.lossRatio))")
                        .foregroundStyle(reading.lossRatio >= 0.01
                                         ? AnyShapeStyle(PanelMetricColor.red(for: colorScheme))
                                         : AnyShapeStyle(.tertiary))
                    if let summary = PingFormat.summary(reading.answeredMilliseconds) {
                        Text(summary + " ms")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 9.5, design: .monospaced))
                .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func statusDot(_ reading: PingReading?) -> some View {
        if reading?.state == .suspect {
            Circle()
                .strokeBorder(PanelMetricColor.yellow(for: colorScheme), lineWidth: 1.5)
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(dotColor(reading))
                .frame(width: 7, height: 7)
        }
    }

    private func dotColor(_ reading: PingReading?) -> Color {
        guard let reading else { return Color.secondary.opacity(0.5) }
        if reading.problem == .unresolved && reading.address == nil { return Color.secondary.opacity(0.5) }
        if reading.isUnreachable { return PanelMetricColor.red(for: colorScheme) }
        switch reading.state {
        case .up: return PanelMetricColor.green(for: colorScheme)
        case .suspect: return PanelMetricColor.yellow(for: colorScheme)
        case .down: return PanelMetricColor.red(for: colorScheme)
        case .unknown: return Color.secondary.opacity(0.5)
        }
    }

    private func graphColor(_ reading: PingReading?) -> Color {
        reading?.isUnreachable == true ? PanelMetricColor.red(for: colorScheme) : .accentColor
    }

    @ViewBuilder
    private func value(for reading: PingReading?) -> some View {
        if let reading {
            switch reading.problem {
            case .some(.resolving) where reading.address == nil:
                statusText(strings.resolving)
            case .some(.unresolved) where reading.address == nil:
                statusText(strings.unresolved)
            case .some(.socket(_)) where reading.address == nil:
                statusText(strings.unavailable)
            default:
                if reading.isUnreachable {
                    Text(strings.down)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(PanelMetricColor.red(for: colorScheme))
                } else if let rtt = reading.lastRTT {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(PingFormat.milliseconds(rtt * 1000))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("ms")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(reading.state == .suspect ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                } else {
                    statusText(strings.measuring)
                }
            }
        } else {
            statusText(strings.measuring)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}
