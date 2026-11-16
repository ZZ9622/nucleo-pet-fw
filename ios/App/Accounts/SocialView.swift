import SwiftUI
import PetDomain

#if os(iOS)
struct SocialView: View {
    @Environment(\.locale) private var locale
    let token: String
    let serviceURL: URL
    @EnvironmentObject private var world: PomiWorldStore
    @State private var profile: AccountProfile?
    @State private var ownListings: [Listing] = []
    @State private var visitedListings: [Listing] = []
    @State private var destination: Destination?
    @State private var friendCode = ""
    @State private var removal: String?
    @State private var listingToRemove: Listing?
    @State private var exchange: Listing?
    @State private var paymentID = ""
    @State private var busy = false
    @State private var message = ""

    private struct Listing: Decodable, Identifiable {
        let id: String
        let item: PomiItem
        let wantedKind: String
        let wantedKinds: [String]?

        var acceptedKinds: [String] { wantedKinds ?? [wantedKind] }
    }

    private struct Listings: Decodable { let listings: [Listing] }

    private struct Destination: Identifiable {
        let id: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("串门").font(.largeTitle.bold())
                    Spacer()
                    Button("刷新") { run { try await refresh() } }
                }
                VStack(alignment: .leading, spacing: 10) {
                    shelf(ownListings, title: "我的小卖部", empty: "货架空着。去仓库选一件物品上架吧。") {
                        listingToRemove = $0
                    }
                    Button("领取测试物品") { mutate("/shop/starter", [:]) }
                        .font(.caption)
                }
                if let profile { friends(profile) }
                if busy { ProgressView() }
                if !message.isEmpty { Text(LocalizedStringKey(message)).font(.footnote) }
            }
            .padding(24)
            .disabled(busy)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Palette.ink)
        .task {
            do { try await refresh() }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
        .alert("下架这件物品？", isPresented: Binding(
            get: { listingToRemove != nil },
            set: { if !$0 { listingToRemove = nil } }
        ), presenting: listingToRemove) { listing in
            Button("取消", role: .cancel) {}
            Button("下架并收回") { mutate("/shop/cancel", ["listingID": listing.id]) }
        } message: { listing in
            Text("\(itemTitle(listing.item)) 会回到你的仓库。")
        }
        .sheet(item: $destination) { page in
            shopPage(page)
                .interactiveDismissDisabled(busy)
        }
    }

    private func friends(_ profile: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("好友 · \(profile.friends.count)").font(.headline)
            ForEach(profile.incomingFriends, id: \.self) { code in
                HStack {
                    Text(code).font(.caption)
                    Spacer()
                    Button("接受申请") { run { try await updateProfile("friend/accept", code: code) } }
                }
            }
            ForEach(profile.friends, id: \.self) { code in
                HStack {
                    Label(code, systemImage: "pawprint").font(.caption)
                    Spacer()
                    Button("逛小卖部") { open(Destination(id: code)) }.font(.caption.bold())
                }
            }
            if profile.friends.isEmpty { Text("用好友码添加一位好友。").font(.footnote) }
            ForEach(profile.outgoingFriends, id: \.self) { code in
                Text("\(code) · 等待确认").font(.caption)
            }
            DisclosureGroup("＋ 添加好友") {
                TextField("输入对方的好友码", text: $friendCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("发送申请") {
                    run {
                        try await updateProfile("friend/request", code: friendCode)
                        friendCode = ""
                    }
                }.disabled(friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper, in: PixelFrame())
    }

    private func shopPage(_ page: Destination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("好友的小卖部").font(.title2.bold())
                    Spacer()
                    Button("完成") { destination = nil }.disabled(busy)
                }
                Text(page.id).font(.caption).foregroundStyle(Palette.muted)
                friendShop(page.id)
                if busy { ProgressView() }
                if !message.isEmpty { Text(LocalizedStringKey(message)).font(.footnote) }
            }.padding(24)
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .alert("确认删除好友？", isPresented: Binding(
            get: { removal != nil },
            set: { if !$0 { removal = nil } }
        ), presenting: removal) { code in
            Button("取消", role: .cancel) {}
            Button("删除好友", role: .destructive) {
                run {
                    try await updateProfile("friend/remove", code: code)
                    destination = nil
                }
            }
        } message: { code in
            Text("删除后，你和好友码为 \(code) 的用户将解除好友关系。")
        }
    }

    private func friendShop(_ code: String) -> some View {
        Group {
            if let exchange {
                Text("你收到 · \(itemTitle(exchange.item))").font(.headline)
                Text("对方想换 · \(wantedTitles(exchange))（任选一种 Lv1）")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                Picker("你给出", selection: $paymentID) {
                    Text("请选择").tag("")
                    ForEach(payments(for: exchange)) { item in Text(itemTitle(item)).tag(item.id) }
                }
                if payments(for: exchange).isEmpty {
                    Text("仓库里没有对方想要的闲置 Lv1 物品。").font(.footnote)
                }
                Button("确认交换") {
                    mutate("/shop/exchange", ["listingID": exchange.id, "itemID": paymentID], friend: code)
                }.buttonStyle(FilledButtonStyle())
                    .disabled(busy || !payments(for: exchange).contains { $0.id == paymentID })
                Button("取消交换") { self.exchange = nil }.disabled(busy)
            } else {
                shelf(visitedListings, empty: "好友暂未上架物品。") { listing in
                    paymentID = ""
                    exchange = listing
                }
                Button("删除好友", role: .destructive) { removal = code }.disabled(busy)
            }
        }
    }

    private func shelf(_ listings: [Listing], title: LocalizedStringKey? = nil, empty: String, select: @escaping (Listing) -> Void) -> some View {
        VStack(spacing: 0) {
            if let title {
                Text(title)
                    .font(.headline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(Palette.paper, in: PixelFrame())
                    .overlay(PixelFrame().stroke(Palette.ink, lineWidth: 1.5))
                    .padding(.bottom, -6)
                    .zIndex(2)
                    .accessibilityAddTraits(.isHeader)
            }
            shopAwning.zIndex(1)
            shelfDisplay(listings, select: select)
                .padding(.horizontal, 12)
            stallCounter
            if listings.isEmpty {
                Text(LocalizedStringKey(empty))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
    }

    private func shelfDisplay(_ listings: [Listing], select: @escaping (Listing) -> Void) -> some View {
        VStack(spacing: 0) {
            let upperRows = max(1, (listings.count + 2) / 3)
            ForEach(0..<upperRows, id: \.self) { row in
                HStack(alignment: .bottom, spacing: 4) {
                    let start = row * 3
                    ForEach(listings.dropFirst(start).prefix(3)) { listing in
                        Button { select(listing) } label: {
                            VStack(spacing: 3) {
                                ItemGlyph(item: listing.item, entry: world.inventory.entry(listing.item))
                                    .frame(height: 42)
                                    .accessibilityHidden(true)
                                Text(LocalizedStringKey(world.inventory.entry(listing.item).name))
                                    .font(.caption2.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("Lv\(listing.item.level)")
                                    .font(.caption2)
                                    .foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || world.busy)
                        .accessibilityLabel(itemTitle(listing.item))
                        .accessibilityHint(destination == nil ? "查看下架选项" : "查看交换选项")
                    }
                    ForEach(0..<max(0, 3 - (listings.count - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, minHeight: 62)
                    }
                }
                .padding(.horizontal, 8)
                shelfBoard
            }

            HStack(alignment: .bottom) {
                emptyShelfSlot
                    .padding(.leading, 24)
                    .padding(.bottom, 5)
                Spacer()
                stallCat
                    .frame(width: 72, height: 47)
                    .padding(.trailing, 15)
                    .offset(y: 4)
            }
            .frame(minHeight: 56, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .background(Palette.blush)
        .overlay {
            HStack {
                Rectangle().fill(Palette.sage).frame(width: 5)
                Spacer(minLength: 0)
                Rectangle().fill(Palette.sage).frame(width: 5)
            }
            .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 1.5))
            .allowsHitTesting(false)
        }
    }

    private var stallCat: some View {
        Canvas { context, size in
            let unit = min(size.width / 24, size.height / 16)
            let face = [
                "   ##       ##   ",
                "   #.##   ##.#   ",
                "  #...#####...#  ",
                "  #...........#  ",
                " #.............# ",
                " #...#.....#...# ",
                " #......#......# ",
                " ##...........## ",
                "#..###########..#",
                "#..#         #..#",
                "####         ####"
            ]
            for (y, row) in face.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != " " {
                    let rect = CGRect(x: CGFloat(x + 1) * unit, y: CGFloat(y + 5) * unit, width: unit, height: unit)
                    context.fill(Path(rect), with: .color(pixel == "#" ? Palette.ink : Palette.room))
                }
            }
            let mint = Color(red: 0.43, green: 0.76, blue: 0.53)
            for (x, y) in [(19, 1), (19, 2), (21, 4), (22, 3), (22, 6), (23, 6)] {
                let rect = CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)
                context.fill(Path(rect), with: .color(mint))
            }
        }
    }

    private var stallCounter: some View {
        VStack(spacing: 0) {
            PixelFrame(cornerRadius: 2)
                .fill(Palette.sage)
                .overlay(PixelFrame(cornerRadius: 2).stroke(Palette.ink, lineWidth: 1.5))
                .frame(height: 10)
            HStack {
                Rectangle().fill(Palette.ink).frame(width: 3, height: 7)
                Spacer()
                Rectangle().fill(Palette.ink).frame(width: 3, height: 7)
            }
            .padding(.horizontal, 14)
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    private var emptyShelfSlot: some View {
        PixelFrame(cornerRadius: 4)
            .stroke(Palette.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: 34, height: 32)
            .accessibilityHidden(true)
    }

    private var shopAwning: some View {
        Canvas { context, size in
            let mint = Color(red: 0.68, green: 0.89, blue: 0.79)
            let mintShadow = Color(red: 0.52, green: 0.80, blue: 0.69)
            let shadeHeight: CGFloat = 24
            let stripeCount = 9

            for band in 0..<6 {
                let inset = CGFloat(5 - band) * 4
                let y = CGFloat(band) * 4
                let stripeWidth = (size.width - 2 * inset) / CGFloat(stripeCount)
                for stripe in 0..<stripeCount {
                    let x = inset + CGFloat(stripe) * stripeWidth
                    let rect = CGRect(x: x, y: y, width: stripeWidth + 0.5, height: 4)
                    context.fill(Path(rect), with: .color(stripe.isMultiple(of: 2) ? mint : Palette.room))
                }
            }

            let hemWidth = size.width / CGFloat(stripeCount)
            for stripe in 0..<stripeCount {
                let x = CGFloat(stripe) * hemWidth
                let hem = CGRect(x: x + 0.5, y: shadeHeight, width: hemWidth - 1, height: 11)
                let edge = PixelFrame(cornerRadius: 3).path(in: hem)
                context.fill(edge, with: .color(stripe.isMultiple(of: 2) ? mintShadow : Palette.sage))
                context.stroke(edge, with: .color(Palette.ink.opacity(0.45)), lineWidth: 1)
            }
        }
        .frame(height: 35)
        .accessibilityHidden(true)
    }

    private var shelfBoard: some View {
        Rectangle()
            .fill(Palette.sage)
            .overlay(alignment: .top) { Rectangle().fill(Palette.ink.opacity(0.7)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 2) }
            .frame(height: 7)
            .accessibilityHidden(true)
    }

    private var availableItems: [PomiItem] {
        world.inventory.items.filter { item in
            !world.inventory.room.values.contains(item.id) && world.inventory.pending?.itemID != item.id
        }
    }

    private func payments(for listing: Listing) -> [PomiItem] {
        availableItems.filter { listing.acceptedKinds.contains($0.kind) && $0.level == 1 }
    }

    private func wantedTitles(_ listing: Listing) -> String {
        listing.acceptedKinds.map { kind in
            pomiLocalized(world.inventory.catalog.first { $0.id == kind }?.name ?? kind, locale: locale)
        }.joined(separator: pomiLocalized("、", locale: locale))
    }

    private func itemTitle(_ item: PomiItem) -> String {
        "\(pomiLocalized(world.inventory.entry(item).name, locale: locale)) · Lv\(item.level)"
    }

    private func open(_ page: Destination) {
        exchange = nil
        visitedListings = []
        destination = page
        run {
            await world.connect()
            visitedListings = try await listings(friend: page.id)
        }
    }

    private func refresh() async throws {
        try await updateProfile("profile")
        ownListings = try await listings()
    }

    private func updateProfile(_ action: String, code: String? = nil) async throws {
        let data = try await AccountAPI.request(action, body: code.map { ["friendCode": $0] } ?? [:], token: token, baseURL: serviceURL)
        profile = try JSONDecoder().decode(AccountProfile.self, from: data)
    }

    private func listings(friend: String? = nil) async throws -> [Listing] {
        let data = try await AccountAPI.request("shop/listings", body: friend.map { ["friendCode": $0] } ?? [:], token: token, baseURL: serviceURL)
        return try JSONDecoder().decode(Listings.self, from: data).listings
    }

    private func mutate(_ path: String, _ body: [String: String], friend: String? = nil) {
        run {
            try await world.perform(path, body)
            exchange = nil
            if let friend {
                visitedListings = try await listings(friend: friend)
                message = "交换成功，物品已放入仓库。"
            } else {
                ownListings = try await listings()
                if path == "/shop/cancel" { message = "物品已收回仓库。" }
                if path == "/shop/starter" { message = "每个账号可领取一份测试物品，请查看仓库。" }
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = ""
        Task {
            defer { busy = false }
            do { try await action() }
            catch { message = error.localizedDescription }
        }
    }
}
#endif
