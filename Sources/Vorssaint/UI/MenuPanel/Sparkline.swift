// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A small history graph: a filled area under a smooth polyline. Hand-drawn with
/// `Path` so the app needs no charting framework (and stays clear of the SwiftUI
/// macro plugins the Command Line Tools cannot load).
///
/// `maxValue` fixes the vertical scale (CPU/memory use 1.0 for an absolute 0–100%
/// reading); when nil the graph auto-scales to its own peak (network, power).
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var maxValue: Double? = nil
    var fillOpacity: Double = 0.16
    var lineWidth: CGFloat = 1.5
    var showsZeroBaseline = false
    var gapMarks: [Bool] = []
    var gapMarkColor: Color? = nil

    var body: some View {
        GeometryReader { geometry in
            let baselineY = max(0.5, geometry.size.height - 0.5)
            let runs = pointRuns(in: geometry.size, baselineY: baselineY)
            if values.count >= 2 {
                ZStack {
                    Path { path in
                        for points in runs where points.count >= 2 {
                            path.move(to: CGPoint(x: points[0].x, y: baselineY))
                            points.forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
                            path.closeSubpath()
                        }
                    }
                    .fill(
                        LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    if showsZeroBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    }
                    Path { path in
                        for points in runs where points.count >= 2 {
                            path.move(to: points[0])
                            points.dropFirst().forEach { path.addLine(to: $0) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    Path { path in
                        for points in runs where points.count == 1 {
                            path.addEllipse(in: CGRect(x: points[0].x - lineWidth / 2, y: points[0].y - lineWidth / 2,
                                                       width: lineWidth, height: lineWidth))
                        }
                    }
                    .fill(color)
                    if let gapMarkColor {
                        Path { path in
                            for x in gapPositions(in: geometry.size) {
                                path.addRect(CGRect(x: x - 0.6, y: baselineY - 5, width: 1.2, height: 5))
                            }
                        }
                        .fill(gapMarkColor)
                    }
                }
            }
        }
    }

    private func pointRuns(in size: CGSize, baselineY: CGFloat) -> [[CGPoint]] {
        guard values.count >= 2 else { return [] }
        let finite = values.filter(\.isFinite)
        let peak = max(maxValue ?? (finite.max() ?? 1), 0.0001)
        let topY: CGFloat = 0.5
        let plotHeight = max(1, baselineY - topY)
        let lastIndex = values.count - 1
        var runs: [[CGPoint]] = [[]]
        for (index, value) in values.enumerated() {
            guard value.isFinite else {
                if !(runs.last?.isEmpty ?? true) { runs.append([]) }
                continue
            }
            let x = size.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = min(1, max(0, value / peak))
            runs[runs.count - 1].append(CGPoint(x: x, y: baselineY - plotHeight * CGFloat(normalized)))
        }
        return runs
    }

    private func gapPositions(in size: CGSize) -> [CGFloat] {
        guard values.count >= 2 else { return [] }
        let lastIndex = values.count - 1
        return gapMarks.prefix(values.count).enumerated().compactMap { index, marked in
            marked ? size.width * CGFloat(index) / CGFloat(lastIndex) : nil
        }
    }
}
