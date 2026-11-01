import SwiftUI
import PetDomain

struct HomeView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var travelRoute: TravelRoute?

    private struct TravelRoute: Identifiable {
        let id = UUID()
        let destination: Residence
    }

    private var isHere: Bool { store.session.residence == .phone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    Eyebrow(text: "NUCLEO / LITTLE COMPANION")
                    Spacer(minLength: 4)
                    if !store.physicalMode { DemoBadge() }
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("方方的小屋").font(.system(size: 31, weight: .semibold, design: .rounded))
                        Text("换个地方，继续陪你。").font(.system(size: 14)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Menu {
                        Button("喂一点小点心", systemImage: "carrot") { store.care(.feed) }
                            .accessibilityIdentifier("care.feed")
                        Button(store.session.state.isSleeping ? "轻轻叫醒" : "让它睡一会儿", systemImage: "moon") { store.care(.sleep) }
                            .accessibilityIdentifier("care.sleep")
                    } label: {
                        Image(systemName: "leaf").font(.system(size: 20))
                            .frame(width: 43, height: 43).background(Palette.sage.opacity(0.5), in: Circle())
                    }
                    .disabled(!store.session.canInteract)
                    .accessibilityLabel("照顾菜单，喂食和睡眠")
                    .accessibilityIdentifier("care.menu")
                }

                if store.session.pendingTransfer != nil {
                    Button { openTravel() } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("有一段旅程，等你继续").font(.system(size: 13, weight: .semibold))
                                Text("状态已保留，点这里接着走。").font(.system(size: 11))
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.padding(15).background(Palette.blush, in: RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain).accessibilityIdentifier("travel.resume")
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 30).fill(Palette.room)
                    RoomBackdrop()
                    HStack(spacing: 6) {
                        Circle().fill(isHere ? Palette.ink : Palette.coral).frame(width: 6, height: 6)
                        Text(store.session.pendingTransfer != nil ? "正在旅途中" : (isHere ? "正在手机小屋" : "正在随身挂件"))
                            .font(.system(size: 11, weight: .medium))
                    }.padding(12).background(Palette.paper.opacity(0.85), in: Capsule()).padding(18)

                    VStack(spacing: 0) {
                        Spacer(minLength: 45)
                        if isHere {
                            ZStack {
                                Ellipse().fill(Palette.ink.opacity(0.07)).frame(width: 120, height: 17).offset(y: 63)
                                PixelPet(session: store.session).frame(width: 260, height: 145)
                            }
                            .onTapGesture { store.care(.pet) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("轻点摸摸方方")
                        } else {
                            TinyDevice(session: store.session).scaleEffect(0.72).frame(height: 145)
                        }
                        Spacer(minLength: 0)
                        Text(isHere ? store.session.state.moodTitle : "小屋留着一盏灯，等它来玩。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.bottom, 20)
                    }.frame(maxWidth: .infinity)
                }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 30))

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(isHere ? "今天，也想靠近你一点。" : "它在挂件里，等你叫它。")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "sparkle").foregroundStyle(Palette.coral)
                    }
                    Text(store.response ?? (isHere ? "摸摸它，或者一起玩一小会儿。" : "接它来手机小屋，带着同一份心情和精力。"))
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        .frame(minHeight: 19, alignment: .leading)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                HStack(spacing: 19) {
                    stat("心情", english: "HAPPINESS", value: store.session.state.happiness, symbol: "heart.fill", tint: Palette.coral)
                    Rectangle().fill(Palette.line).frame(width: 1, height: 46)
                    stat("精力", english: "ENERGY", value: store.session.state.energy, symbol: "bolt.fill", tint: Palette.muted)
                }.padding(18).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))

                if isHere && store.session.pendingTransfer == nil {
                    HStack(spacing: 12) {
                        careButton("摸摸", subtitle: "一点温柔", symbol: "heart", action: .pet, color: Palette.blush)
                        careButton("玩一会儿", subtitle: "一起开心", symbol: "tennisball", action: .play, color: Palette.sage)
                    }
                    Button { openTravel() } label: {
                        HStack {
                            Image(systemName: "arrow.turn.up.left")
                            Text("送它回随身挂件")
                            Spacer(); Image(systemName: "arrow.right")
                        }.font(.system(size: 13, weight: .medium))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("travel.open")
                } else {
                    Button { openTravel() } label: {
                        Label(store.session.pendingTransfer == nil ? "接方方来小屋" : "继续这次旅程", systemImage: "door.left.hand.open")
                    }.buttonStyle(FilledButtonStyle()).accessibilityIdentifier("travel.open")
                    Text("同一只小伙伴，两个小世界。").font(.system(size: 11))
                        .foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
            }.foregroundStyle(Palette.ink).padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 25)
        }
        .sheet(item: $travelRoute) { route in
            TravelView(destination: route.destination).environmentObject(store)
        }
    }

    private func openTravel() {
        travelRoute = TravelRoute(destination: store.session.pendingTransfer?.destination ?? (isHere ? .device : .phone))
    }

    private func stat(_ title: String, english: String, value: UInt8, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text("\(value)").font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line.opacity(0.6))
                    Capsule().fill(tint.opacity(0.75)).frame(width: geometry.size.width * Double(value) / 100)
                }
            }.frame(height: 5)
            Eyebrow(text: english).font(.system(size: 8))
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(value)，满值100")
            .accessibilityIdentifier("stat.\(english.lowercased())")
    }

    private func careButton(_ title: String, subtitle: String, symbol: String, action: CareAction, color: Color) -> some View {
        Button { store.care(action) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 23))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }.padding(17).frame(maxWidth: .infinity).background(color, in: RoundedRectangle(cornerRadius: 21))
        }.buttonStyle(.plain).accessibilityIdentifier("care.\(action.rawValue)")
    }
}
