import SwiftUI
import PetDomain

enum Palette {
    static let paper = Color(red: 0.97, green: 0.99, blue: 1)
    static let ink = Color(red: 0.08, green: 0.26, blue: 0.68)
    static let muted = Color(red: 0.29, green: 0.43, blue: 0.65)
    static let line = Color(red: 0.74, green: 0.83, blue: 0.96)
    static let sage = Color(red: 0.86, green: 0.93, blue: 1)
    static let coral = Color(red: 0.16, green: 0.39, blue: 0.88)
    static let blush = Color(red: 0.90, green: 0.95, blue: 1)
    static let room = Color.white
}

/// Square pixels and stepped corners, matching the monochrome board renderer.
struct PixelFrame: Shape {
    var corner: CGFloat = 8
    init(cornerRadius: CGFloat = 8) { corner = min(cornerRadius, 8) }
    func path(in rect: CGRect) -> Path {
        let c = min(corner, min(rect.width, rect.height) / 3)
        var p = Path()
        p.move(to: CGPoint(x: c, y: 0))
        for point in [CGPoint(x: rect.width-c, y: 0), CGPoint(x: rect.width-c, y: c),
            CGPoint(x: rect.width, y: c), CGPoint(x: rect.width, y: rect.height-c),
            CGPoint(x: rect.width-c, y: rect.height-c), CGPoint(x: rect.width-c, y: rect.height),
            CGPoint(x: c, y: rect.height), CGPoint(x: c, y: rect.height-c),
            CGPoint(x: 0, y: rect.height-c), CGPoint(x: 0, y: c), CGPoint(x: c, y: c)] { p.addLine(to: point) }
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct PixelGrid: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0.0, through: size.width, by: 24) {
                for y in stride(from: 0.0, through: size.height, by: 24) {
                    grid.addRect(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
            context.fill(grid, with: .color(Palette.line.opacity(0.5)))
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct FilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.paper).frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(Palette.ink, in: PixelFrame())
            .compositingGroup()
            .shadow(color: Palette.line, radius: 0, x: 4, y: 4)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Palette.sage.opacity(configuration.isPressed ? 0.6 : 0.35), in: PixelFrame(cornerRadius: 17))
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
            Text(title).font(.system(size: 31, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DemoBadge: View {
    var body: some View {
        Text("体验模式").font(.system(size: 10, weight: .medium))
            .foregroundStyle(Palette.muted).padding(.horizontal, 9).padding(.vertical, 6)
            .background(Palette.line.opacity(0.45), in: Rectangle())
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
        VStack(spacing: 10) {
            HStack { Text("NUCLEO / 01"); Spacer(); Rectangle().frame(width: 6, height: 6) }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
            ZStack {
                Rectangle().fill(Palette.ink)
                if session.residence == .device {
                    PixelPet(session: session, color: .white, fullScreen: true).padding(8)
                } else {
                    VStack(spacing: 8) {
                        PixelDoor().stroke(.white, lineWidth: 3).frame(width: 20, height: 28)
                        Text("VISITING PHONE").font(.system(size: 8, weight: .bold, design: .monospaced))
                    }.foregroundStyle(.white)
                }
            }.frame(height: 90)
            HStack(spacing: 12) {
                ForEach(0..<4) { _ in Rectangle().fill(Palette.ink).frame(width: 9, height: 9) }
            }.padding(.vertical, 3)
        }.padding(14).frame(width: 190)
            .background(Palette.sage, in: PixelFrame())
            .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 2))
            .compositingGroup()
            .shadow(color: Palette.line, radius: 0, x: 5, y: 5)
            .accessibilityElement(children: .combine)
    }
}

struct PixelDoor: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRect(CGRect(x: rect.width * 0.7, y: rect.height * 0.5, width: 2, height: 2))
        return p
    }
}

struct RoomBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let unit: CGFloat = 6
            func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            let floorY = floor(size.height * 0.8 / unit) * unit
            block(0, floorY, size.width, 3, Palette.ink)
            for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                block(x, floorY + 18, 12, 2, Palette.line)
                block(x + 12, floorY + 36, 12, 2, Palette.line)
            }
            let x: CGFloat = 24, y: CGFloat = 60
            block(x, y, 66, 60, Palette.line)
            block(x+3, y+3, 60, 54, Palette.sage)
            block(x+30, y, 3, 60, Palette.ink)
            block(x, y+30, 66, 3, Palette.ink)
            block(x+42, y+9, 12, 12, Palette.coral)
            let potX = size.width - 57
            block(potX, floorY-21, 30, 21, Palette.ink)
            block(potX+12, floorY-57, 6, 36, Palette.coral)
            block(potX, floorY-51, 12, 6, Palette.coral)
            block(potX+18, floorY-42, 12, 6, Palette.coral)
        }.accessibilityHidden(true)
    }
}
