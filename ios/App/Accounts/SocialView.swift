import SwiftUI
import PetDomain

#if os(iOS)
struct SocialView: View {
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
                    Label("我的小卖部", systemImage: "storefront").font(.headline)
                    shelf(ownListings, empty: "货架空着。去仓库选一件物品上架吧。") {
                        listingToRemove = $0
                    }
                    Button("领取测试物品") { mutate("/shop/starter", [:]) }
                        .font(.caption)
                }
                if let profile { friends(profile) }
                if busy { ProgressView() }
                if !message.isEmpty { Text(message).font(.footnote) }
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
                if !message.isEmpty { Text(message).font(.footnote) }
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

    private func shelf(_ listings: [Listing], empty: String, select: @escaping (Listing) -> Void) -> some View {
        VStack(spacing: 0) {
            shopRoof
            shelfDisplay(listings, empty: empty, select: select)
                .padding(.horizontal, 10)
            shopGarden
        }
    }

    private func shelfDisplay(_ listings: [Listing], empty: String, select: @escaping (Listing) -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<9) { stripe in
                    Rectangle().fill(stripe.isMultiple(of: 2) ? Palette.blush : Palette.paper)
                }
            }
            .frame(height: 18)
            .accessibilityHidden(true)

            if listings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "basket").font(.title2)
                    Text(empty).font(.footnote).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .padding(.horizontal, 12)
                shelfBoard
            } else {
                ForEach(Array(stride(from: 0, to: listings.count, by: 3)), id: \.self) { start in
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(listings[start..<min(start + 3, listings.count)]) { listing in
                            Button { select(listing) } label: {
                                VStack(spacing: 3) {
                                    ItemGlyph(item: listing.item, entry: world.inventory.entry(listing.item))
                                        .frame(height: 42)
                                        .accessibilityHidden(true)
                                    Text(world.inventory.entry(listing.item).name)
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
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)
                    shelfBoard
                }
            }
        }
        .background(Color(red: 1, green: 0.95, blue: 0.86))
        .overlay(Rectangle().stroke(Color(red: 0.67, green: 0.45, blue: 0.31), lineWidth: 2))
    }

    private var shopRoof: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                let step = size.width / 16
                let rose = Color(red: 0.83, green: 0.43, blue: 0.48)
                let tile = Color(red: 0.92, green: 0.59, blue: 0.60)
                for row in 0..<4 {
                    let inset = CGFloat(3 - row) * step
                    let y = CGFloat(row) * 7
                    context.fill(Path(CGRect(x: inset, y: y, width: size.width - 2 * inset, height: 7)),
                                 with: .color(row.isMultiple(of: 2) ? tile : rose))
                }
            }.frame(height: 28)
            Rectangle().fill(Color(red: 0.63, green: 0.29, blue: 0.35)).frame(height: 5)
        }
        .accessibilityHidden(true)
    }

    private var shopGarden: some View {
        Canvas { context, size in
            let grass = Color(red: 0.62, green: 0.76, blue: 0.45)
            let wood = Color(red: 0.78, green: 0.58, blue: 0.40)
            func pixel(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: .color(color))
            }
            pixel(0, 25, size.width, 6, grass)
            pixel(8, 15, size.width - 16, 3, wood)
            pixel(8, 21, size.width - 16, 3, wood)
            for x in stride(from: CGFloat(8), to: size.width - 8, by: 18) {
                pixel(x, 12, 5, 16, wood)
                pixel(x + 1, 10, 3, 2, wood)
            }
            let pink = Color(red: 0.89, green: 0.45, blue: 0.59)
            let yellow = Color(red: 0.98, green: 0.77, blue: 0.34)
            for (index, position) in [0.13, 0.25, 0.74, 0.87].enumerated() {
                let x = size.width * position
                let y: CGFloat = index.isMultiple(of: 2) ? 6 : 10
                let petal = index.isMultiple(of: 2) ? pink : yellow
                pixel(x, y + 7, 3, 20 - y, grass)
                pixel(x - 4, y + 12, 5, 3, grass)
                pixel(x - 3, y + 2, 9, 4, petal)
                pixel(x, y - 1, 3, 10, petal)
                pixel(x, y + 2, 3, 4, Palette.paper)
            }
        }
        .frame(height: 31)
        .accessibilityHidden(true)
    }

    private var shelfBoard: some View {
        Rectangle()
            .fill(Color(red: 0.72, green: 0.48, blue: 0.33))
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
            world.inventory.catalog.first { $0.id == kind }?.name ?? kind
        }.joined(separator: "、")
    }

    private func itemTitle(_ item: PomiItem) -> String {
        "\(world.inventory.entry(item).name) · Lv\(item.level)"
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
