// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PingTargetsList: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.pingTargets) private var targetsRaw = PingTargets.defaultList
    @State private var isExpanded = false
    @State private var customDraft = ""
    @State private var showingCustomField = false
    @State private var invalidDraft = false

    private var strings: PingFeatureStrings {
        FeatureStrings.ping(l10n.language)
    }

    private var hosts: [PingHost] { PingTargets.hosts(from: targetsRaw) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(hosts, id: \.self) { host in
                HStack(spacing: 8) {
                    Image(systemName: host.kind == .gateway ? "wifi.router" : "network")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(name(of: host))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        update(PingTargets.removing(host, from: targetsRaw))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.remove)
                }
            }

            if showingCustomField {
                HStack(spacing: 8) {
                    TextField(strings.targetPlaceholder, text: $customDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCustom)
                        .onChange(of: customDraft) { _, _ in invalidDraft = false }
                    Button(strings.addTarget) {
                        addCustom()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(l10n.s.uninstallerCancel) {
                        customDraft = ""
                        invalidDraft = false
                        showingCustomField = false
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                }
                if invalidDraft {
                    Text(strings.invalidTarget)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else if hosts.count < PingTargets.maximumCount {
                let candidates = suggestions
                if !candidates.isEmpty {
                    Menu {
                        ForEach(candidates, id: \.self) { host in
                            Button(name(of: host)) {
                                update(PingTargets.adding(host, to: targetsRaw))
                            }
                        }
                        Divider()
                        Button(strings.otherTarget) {
                            showingCustomField = true
                        }
                    } label: {
                        Label(strings.addTarget, systemImage: "plus")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        showingCustomField = true
                    } label: {
                        Label(strings.addTarget, systemImage: "plus")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text(strings.targetsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(strings.targetsTitle)
                Spacer()
                if !hosts.isEmpty {
                    Text("\(hosts.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func name(of host: PingHost) -> String {
        host.kind == .gateway ? strings.router : host.text
    }

    private var suggestions: [PingHost] {
        [PingHost.gateway, PingHost("1.1.1.1"), PingHost("8.8.8.8")]
            .compactMap { $0 }
            .filter { !hosts.contains($0) }
    }

    private func addCustom() {
        guard let host = PingHost(customDraft) else {
            invalidDraft = true
            return
        }
        update(PingTargets.adding(host, to: targetsRaw))
        customDraft = ""
        showingCustomField = false
    }

    private func update(_ raw: String) {
        targetsRaw = raw
        SystemMonitor.shared.planDidChange()
    }
}
