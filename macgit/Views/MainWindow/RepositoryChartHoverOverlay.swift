// SPDX-License-Identifier: AGPL-3.0-or-later
import Charts
import SwiftUI

struct RepositoryChartHoverInfo {
    let text: String
    let highlight: Path
}

struct RepositoryChartHoverOverlay: View {
    let proxy: ChartProxy
    let information: (ChartProxy, CGPoint, CGSize) -> RepositoryChartHoverInfo?
    @State private var info: RepositoryChartHoverInfo?
    private var text: String? { info?.text }
    @State private var location = CGPoint.zero

    var body: some View {
        GeometryReader { geometry in
            let width = min(280, max(100, geometry.size.width - 16))
            let height = CGFloat((text ?? "").split(separator: "\n").count * 18 + 24)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard let anchor = proxy.plotFrame else { info = nil; return }
                            let frame = geometry[anchor]
                            guard frame.contains(point) else { info = nil; return }
                            location = point
                            info = information(proxy, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), frame.size)
                        case .ended: info = nil
                        }
                    }
                if let info, let anchor = proxy.plotFrame {
                    info.highlight
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(info.highlight.stroke(Color.accentColor, lineWidth: 2))
                        .offset(x: geometry[anchor].minX, y: geometry[anchor].minY)
                        .allowsHitTesting(false)
                }
                if let text {
                    Text(text)
                        .font(.caption).monospacedDigit()
                        .padding(10)
                        .frame(width: width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .position(x: min(max(location.x, width / 2 + 4), geometry.size.width - width / 2 - 4),
                                  y: min(max(location.y - height / 2 - 12, height / 2 + 4), geometry.size.height - height / 2 - 4))
                        .allowsHitTesting(false)
                }
            }.accessibilityHidden(true)
        }
    }
}
