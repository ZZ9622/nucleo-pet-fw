import SwiftUI

struct AdventureScene: View {
    let stage: Int
    let waking: Bool
    let riding: Bool
    let paused: Bool

    private let captions = [
        "出发喵！", "翻小山！", "摸到云！",
        "过海啦！", "新大陆！", "喵爪到此！"
    ]

    private var captionAlignment: Alignment {
        if waking { return .center }
        switch stage {
        case 1, 4: return .leading
        case 2, 5: return .trailing
        default: return .center
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: paused)) { timeline in
            let beat = paused ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate * 5.5) % 360
            VStack(spacing: 0) {
                Text(LocalizedStringKey(waking ? "伸个懒腰" : captions[stage - 1]))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: captionAlignment)
                    .padding(.horizontal, 12)
                Canvas { context, size in
                    let blue = Color(red: 0.24, green: 0.62, blue: 0.94)
                    let dark = Color(red: 0.06, green: 0.18, blue: 0.37)
                    let scale = min(size.width / 100, size.height / 44)
                    func block(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color = .white) {
                        let rect = CGRect(x: (size.width - 100 * scale) / 2 + CGFloat(x) * scale,
                                          y: CGFloat(y) * scale, width: CGFloat(w) * scale,
                                          height: CGFloat(h) * scale)
                        context.fill(Path(rect), with: .color(color))
                    }
                    if !waking {
                        for x in -42...42 {
                            let top = 23 + x * x / 115
                            block(50 + x, top, 1, 44 - top, blue)
                            for y in top..<44 where (x + 90 + beat + y / 2) % 31 < 8 + y % 4 {
                                block(50 + x, y, 1, 1)
                            }
                        }
                        switch stage {
                        case 1: block(69, 11, 2, 5); block(67, 13, 6, 1)
                        case 2:
                            for row in 0..<7 { block(75 - row, 18 + row, row * 2 + 1, 1) }
                        case 3:
                            block(72 + beat % 6, 12, 13, 3); block(76 + beat % 6, 10, 6, 3)
                        case 4:
                            block(69, 23, 8, 2); block(84, 27, 7, 2); block(73 + beat % 4, 20, 1, 2)
                        case 5: block(70, 15, 12, 2); block(80, 13, 4, 6)
                        default: block(71, 10, 1, 17); block(72, 10, 10, 6); block(84 + beat % 3, 13, 2, 2)
                        }
                    }
                    let seated = riding || paused || waking
                    let hop = seated ? 0 : ((beat % 4 == 2) ? [2, 4, 5, 3, 1, 4][stage - 1] : 0)
                    let y = 9 - hop
                    let x = 39 + (seated ? 0 : beat % 3)
                    block(x + 8, y, 3, 4); block(x + 17, y, 3, 4)
                    block(x + 7, y + 3, 14, 8); block(x + 4, y + 8, 13, 5)
                    block(x + 2, y + 6, 5, 5, blue)
                    block(x, y + 6 - beat % 2, 4, 2)
                    block(x + 11, y + 5, 2, 1, dark); block(x + 17, y + 5, 2, 1, dark)
                    if waking {
                        block(x + 12, y + 8, 3, 2 + beat % 2, dark)
                        block(x + 18, y + 6, 4, 2)
                    } else if seated {
                        block(x + 10, y + 11, 10, 2)
                        if !paused && beat % 4 < 2 { block(x + 19, y + 7, 3, 2) }
                    } else {
                        block(x + 5 + beat % 2, y + 12, 3, 2)
                        block(x + 14 - beat % 2, y + 12, 3, 2)
                    }
                }
            }
            .padding(6)
            .background(Color(red: 0.06, green: 0.18, blue: 0.37), in: PixelFrame(cornerRadius: 15))
        }
        .accessibilityLabel("探险第 \(stage) 档，\(captions[stage - 1])")
    }
}
