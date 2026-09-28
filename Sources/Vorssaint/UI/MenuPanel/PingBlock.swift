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
    @AppStorage(DefaultsKey.menuBarPing) private var menuBarPing = false
    @AppStorage(DefaultsKey.menuBarPingTarget) private var menuBarTarget = PingTargets.defaultMenuBarTarget
    @State private var adding = false
    @State private var draft = ""
    @State private var invalidDraft = false
    @State private var hovered: PingHost?

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
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button {
                        adding.toggle()
                        draft = ""
                        invalidDraft = false
                    } label: {
                        Image(systemName: adding ? "xmark" : "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(strings.addTarget)
                    .disabled(!adding && hosts.count >= PingTargets.maximumCount)
                    if editing {
                        PanelInlineHideButton(isVisible: $isVisible)
                    }
                }
                ForEach(hosts, id: \.self) { host in
                    row(host)
                }
                if adding {
                    addField
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
                if hovered == host {
                    actions(for: host)
                } else {
                    value(for: reading)
                }
            }
            if values.count >= 2 {
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
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hovered = host
            } else if hovered == host {
                hovered = nil
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
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
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

    private func actions(for host: PingHost) -> some View {
        let pinned = menuBarPing && menuBarTarget == host.text
        return HStack(spacing: 2) {
            Button {
                menuBarTarget = host.text
                menuBarPing = true
                SystemMonitor.shared.planDidChange()
            } label: {
                Image(systemName: pinned ? "menubar.rectangle" : "menubar.arrow.up.rectangle")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
            .help(pinned ? strings.shownInMenuBar : strings.showInMenuBar)
            Button {
                targetsRaw = PingTargets.removing(host, from: targetsRaw)
                hovered = nil
                SystemMonitor.shared.planDidChange()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(strings.remove)
        }
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(strings.targetPlaceholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: 11))
                .onSubmit { add(draft) }
                .onChange(of: draft) { _, _ in invalidDraft = false }
            if invalidDraft {
                Text(strings.invalidTarget)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelMetricColor.red(for: colorScheme))
            }
            HStack(spacing: 4) {
                ForEach(suggestions, id: \.self) { host in
                    Button {
                        add(host.text)
                    } label: {
                        Text(name(of: host))
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var suggestions: [PingHost] {
        [PingHost.gateway, PingHost("1.1.1.1"), PingHost("8.8.8.8")]
            .compactMap { $0 }
            .filter { !hosts.contains($0) }
    }

    private func add(_ text: String) {
        guard let host = PingHost(text) else {
            invalidDraft = true
            return
        }
        targetsRaw = PingTargets.adding(host, to: targetsRaw)
        draft = ""
        adding = false
        SystemMonitor.shared.planDidChange()
    }
}
