import SwiftUI
import PetDomain

enum Palette {
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let ink = Color(red: 0.17, green: 0.25, blue: 0.21)
    static let muted = Color(red: 0.49, green: 0.52, blue: 0.46)
    static let line = Color(red: 0.88, green: 0.88, blue: 0.82)
    static let sage = Color(red: 0.87, green: 0.91, blue: 0.83)
    static let coral = Color(red: 0.87, green: 0.50, blue: 0.40)
    static let blush = Color(red: 0.98, green: 0.90, blue: 0.84)
    static let room = Color(red: 0.94, green: 0.92, blue: 0.86)
}

struct FilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.paper).frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 19))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Palette.sage.opacity(configuration.isPressed ? 0.6 : 0.35), in: RoundedRectangle(cornerRadius: 17))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2).foregroundStyle(Palette.muted)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(size: 31, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DemoBadge: View {
    var body: some View {
        Text("体验模式").font(.system(size: 10, weight: .medium))
            .foregroundStyle(Palette.muted).padding(.horizontal, 9).padding(.vertical, 6)
            .background(Palette.line.opacity(0.45), in: Capsule())
            .accessibilityLabel("体验模式，尚未连接真实挂件")
    }
}

struct PixelPet: View {
    let session: CompanionSession
    var color: Color = Palette.ink
    var fullScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var motionPaused: Bool { reduceMotion || AppRuntime.isUITesting }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: motionPaused || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let time = motionPaused ? 0 : timeline.date.timeIntervalSince(session.createdAt)
                let feedbackAge = session.lastActionAt.map { timeline.date.timeIntervalSince($0) } ?? 100
                let pixels = session.state.pixels(animationTime: time, feedbackAge: feedbackAge)
                let region = fullScreen ? (x: 0, y: 0, w: 128, h: 64) : (x: 30, y: 19, w: 76, h: 45)
                let unit = max(1, floor(min(size.width / Double(region.w), size.height / Double(region.h))))
                let left = (size.width - Double(region.w) * unit) / 2
                let top = (size.height - Double(region.h) * unit) / 2
                var path = Path()
                for y in region.y..<(region.y + region.h) {
                    for x in region.x..<(region.x + region.w) {
                        if pixels[y / 8 * 128 + x] & (1 << (y % 8)) != 0 {
                            path.addRect(CGRect(x: left + Double(x - region.x) * unit,
                                y: top + Double(y - region.y) * unit, width: unit, height: unit))
                        }
                    }
                }
                context.fill(path, with: .color(color))
            }
        }
        .accessibilityLabel("方块猫方方，\(session.state.moodTitle)")
    }
}

struct TinyDevice: View {
    let session: CompanionSession
    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).stroke(Palette.ink.opacity(0.3), lineWidth: 3)
                .frame(width: 20, height: 12).padding(.top, 8)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.ink)
                if session.residence == .device {
                    PixelPet(session: session, color: Palette.sage, fullScreen: true).padding(10)
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "door.left.hand.open").font(.title2)
                        Text("去手机里玩啦").font(.system(size: 10))
                    }.foregroundStyle(Palette.sage)
                }
            }.frame(height: 100).padding(.horizontal, 14)
            Circle().fill(Palette.paper).frame(width: 22, height: 22)
                .overlay(Circle().stroke(Palette.ink.opacity(0.15), lineWidth: 1)).padding(.bottom, 15)
        }
        .frame(width: 190)
        .background(Palette.sage, in: RoundedRectangle(cornerRadius: 35))
        .overlay(RoundedRectangle(cornerRadius: 35).stroke(Palette.ink.opacity(0.15), lineWidth: 1))
        .rotationEffect(.degrees(-7))
        .shadow(color: Palette.ink.opacity(0.09), radius: 12, x: 0, y: 12)
        .accessibilityElement(children: .combine)
    }
}

struct RoomBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let floorY = h * 0.76
            var floor = Path()
            floor.move(to: CGPoint(x: 0, y: floorY)); floor.addLine(to: CGPoint(x: w, y: floorY))
            for x in stride(from: -w, through: w * 2, by: w / 4) {
                floor.move(to: CGPoint(x: w / 2 + (x - w / 2) * 0.7, y: floorY))
                floor.addLine(to: CGPoint(x: x, y: h))
            }
            context.stroke(floor, with: .color(Palette.line.opacity(0.75)), lineWidth: 1)
            let window = CGRect(x: w * 0.12, y: h * 0.21, width: w * 0.25, height: h * 0.29)
            context.fill(Path(roundedRect: window, cornerRadius: 35), with: .color(Palette.paper.opacity(0.8)))
            context.fill(Path(ellipseIn: CGRect(x: window.minX + 17, y: window.minY + 14, width: 21, height: 21)), with: .color(Palette.coral.opacity(0.55)))
            var bars = Path()
            bars.move(to: CGPoint(x: window.midX, y: window.minY)); bars.addLine(to: CGPoint(x: window.midX, y: window.maxY))
            bars.move(to: CGPoint(x: window.minX, y: window.midY)); bars.addLine(to: CGPoint(x: window.maxX, y: window.midY))
            context.stroke(bars, with: .color(Palette.room), lineWidth: 4)
            let plantX = w * 0.83
            context.fill(Path(roundedRect: CGRect(x: plantX - 11, y: floorY - 26, width: 22, height: 27), cornerRadius: 5), with: .color(Palette.coral.opacity(0.55)))
            var stem = Path(); stem.move(to: CGPoint(x: plantX, y: floorY - 26)); stem.addLine(to: CGPoint(x: plantX, y: floorY - 70))
            context.stroke(stem, with: .color(Palette.muted), lineWidth: 2)
            for i in 0..<3 {
                let y = floorY - 65 + CGFloat(i) * 12
                context.fill(Path(ellipseIn: CGRect(x: plantX - 17, y: y, width: 17, height: 8)), with: .color(Palette.muted.opacity(0.55)))
                context.fill(Path(ellipseIn: CGRect(x: plantX, y: y - 5, width: 16, height: 8)), with: .color(Palette.muted.opacity(0.45)))
            }
        }
        .accessibilityHidden(true)
    }
}
