import SwiftUI

struct GlassShard: Identifiable {
    let id: Int
    let points: [CGPoint]
    let offset: CGSize
    let rotation: Double

    var center: CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

struct GlassShardShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

struct GenieOverlay: View {
    let accent: Color
    @State private var breakProgress: CGFloat = 0

    private let shards: [GlassShard] = [
        GlassShard(id: 0, points: [CGPoint(x: 0.03, y: 0.05), CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.22, y: 0.42)], offset: CGSize(width: -34, height: -22), rotation: -16),
        GlassShard(id: 1, points: [CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.50, y: 0.40)], offset: CGSize(width: 4, height: -34), rotation: 9),
        GlassShard(id: 2, points: [CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.97, y: 0.04), CGPoint(x: 0.80, y: 0.35)], offset: CGSize(width: 38, height: -20), rotation: 18),
        GlassShard(id: 3, points: [CGPoint(x: 0.04, y: 0.48), CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -42, height: 10), rotation: -22),
        GlassShard(id: 4, points: [CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -8, height: 18), rotation: -6),
        GlassShard(id: 5, points: [CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.73, y: 0.78), CGPoint(x: 0.45, y: 0.74)], offset: CGSize(width: 16, height: 20), rotation: 7),
        GlassShard(id: 6, points: [CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.98, y: 0.48), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.73, y: 0.78)], offset: CGSize(width: 46, height: 12), rotation: 24),
        GlassShard(id: 7, points: [CGPoint(x: 0.08, y: 0.86), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: -28, height: 36), rotation: 15),
        GlassShard(id: 8, points: [CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.67, y: 0.98), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: 30, height: 38), rotation: -13)
    ]

    var body: some View {
        GeometryReader { proxy in
            let progress = min(max(breakProgress, 0), 1)
            let crackPhase = min(progress / 0.34, 1)
            let fallPhase = min(max((progress - 0.24) / 0.76, 0), 1)

            ZStack {
                ForEach(shards) { shard in
                    GlassShardFragmentView(
                        shard: shard,
                        accent: accent,
                        sinkOffset: shardSinkOffset(for: shard, in: proxy.size),
                        crackPhase: crackPhase,
                        fallPhase: fallPhase
                    )
                }
            }
            .background(.white.opacity(0.12 * (1 - fallPhase)))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.70)) {
                breakProgress = 1
            }
        }
    }

    private func shardSinkOffset(for shard: GlassShard, in size: CGSize) -> CGSize {
        let sinkX = size.width * 0.5
        let sinkY = size.height * 1.12
        let currentX = shard.center.x * size.width
        let currentY = shard.center.y * size.height
        let jitter = CGFloat(shard.id % 3 - 1) * 8
        return CGSize(width: sinkX - currentX + jitter, height: sinkY - currentY)
    }
}

// MARK: - Glass Unbreak (reverse: shards assemble from trash back into card)

struct ReverseGenieOverlay: View {
    let accent: Color
    /// Starts fully broken (1.0) and animates to whole (0.0)
    @State private var breakProgress: CGFloat = 1.0

    private let shards: [GlassShard] = [
        GlassShard(id: 0, points: [CGPoint(x: 0.03, y: 0.05), CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.22, y: 0.42)], offset: CGSize(width: -34, height: -22), rotation: -16),
        GlassShard(id: 1, points: [CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.50, y: 0.40)], offset: CGSize(width: 4, height: -34), rotation: 9),
        GlassShard(id: 2, points: [CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.97, y: 0.04), CGPoint(x: 0.80, y: 0.35)], offset: CGSize(width: 38, height: -20), rotation: 18),
        GlassShard(id: 3, points: [CGPoint(x: 0.04, y: 0.48), CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -42, height: 10), rotation: -22),
        GlassShard(id: 4, points: [CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -8, height: 18), rotation: -6),
        GlassShard(id: 5, points: [CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.73, y: 0.78), CGPoint(x: 0.45, y: 0.74)], offset: CGSize(width: 16, height: 20), rotation: 7),
        GlassShard(id: 6, points: [CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.98, y: 0.48), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.73, y: 0.78)], offset: CGSize(width: 46, height: 12), rotation: 24),
        GlassShard(id: 7, points: [CGPoint(x: 0.08, y: 0.86), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: -28, height: 36), rotation: 15),
        GlassShard(id: 8, points: [CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.67, y: 0.98), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: 30, height: 38), rotation: -13)
    ]

    var body: some View {
        GeometryReader { proxy in
            let progress = min(max(breakProgress, 0), 1)
            // Derive phases from the same formula as GenieOverlay so they mirror exactly
            let crackPhase = min(progress / 0.34, 1)
            let fallPhase  = min(max((progress - 0.24) / 0.76, 0), 1)

            ZStack {
                ForEach(shards) { shard in
                    GlassShardFragmentView(
                        shard: shard,
                        accent: accent,
                        sinkOffset: shardRiseOffset(for: shard, in: proxy.size),
                        crackPhase: crackPhase,
                        fallPhase: fallPhase
                    )
                }
            }
            // Frosted pane brightens as shards lock together
            .background(.white.opacity(0.12 * (1 - fallPhase)))
        }
        .onAppear {
            // Animate from broken (1) to whole (0), mirroring GenieOverlay.
            withAnimation(.easeOut(duration: 0.78)) {
                breakProgress = 0
            }
        }
    }

    /// Rise origin is the same sink point used during breaking (bottom-center / trash area),
    /// so shards appear to fly up from where they were discarded and snap back into place.
    private func shardRiseOffset(for shard: GlassShard, in size: CGSize) -> CGSize {
        let originX = size.width * 0.5
        let originY = size.height * 1.12
        let currentX = shard.center.x * size.width
        let currentY = shard.center.y * size.height
        let jitter = CGFloat(shard.id % 3 - 1) * 8
        return CGSize(width: originX - currentX + jitter, height: originY - currentY)
    }
}

struct GlassShardFragmentView: View {
    let shard: GlassShard
    let accent: Color
    let sinkOffset: CGSize
    let crackPhase: CGFloat
    let fallPhase: CGFloat

    private var crackOffset: CGSize {
        CGSize(width: shard.offset.width * crackPhase, height: shard.offset.height * crackPhase)
    }

    private var fallOffset: CGSize {
        CGSize(width: sinkOffset.width * fallPhase, height: sinkOffset.height * fallPhase)
    }

    var body: some View {
        GlassShardShape(points: shard.points)
            .fill(.white.opacity(0.20))
            .overlay {
                GlassShardShape(points: shard.points)
                    .stroke(.white.opacity(0.58), lineWidth: 0.9)
            }
            .overlay {
                GlassShardShape(points: shard.points)
                    .stroke(accent.opacity(0.30), lineWidth: 1.4)
                    .blur(radius: 2.5)
            }
            .shadow(color: .white.opacity(0.20 * (1 - fallPhase)), radius: 7)
            .offset(x: crackOffset.width + fallOffset.width, y: crackOffset.height + fallOffset.height)
            .rotationEffect(.degrees(shard.rotation * (crackPhase + fallPhase * 1.35)))
            .scaleEffect(1.0 - fallPhase * 0.48)
            .opacity(1.0 - fallPhase * 0.92)
    }
}

#Preview("GenieOverlay") {
    ZStack {
        Color.black.ignoresSafeArea()
        GenieOverlay(accent: .blue)
    }
}
