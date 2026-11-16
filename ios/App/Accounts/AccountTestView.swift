import SwiftUI
import PetDomain

#if os(iOS)
import UIKit
struct AccountTestView: View {
    var onAuthenticated: ((String, URL) -> Void)?
    var onLogout: (() -> Void)?
    var onContinueWithoutAccount: (() -> Void)?
    var sessionURL: URL?
    @AppStorage("pomi.accountServiceURL") private var serviceAddress = AccountAPI.defaultAddress
    @Binding var token: String?
    @Binding var selectedPomi: String?
    @State private var email = ""
    @State private var password = ""
    @State private var showingRegistration = false
    @State private var pomiID = ""
    @State private var copiedFriendCode: String?
    @State private var profile: AccountProfile?
    @State private var busy = false
    @State private var message = ""

    private struct Login: Decodable { let token: String }

    var body: some View {
        if onAuthenticated != nil {
            loginPage
        } else {
            accountPage
        }
    }

    private var accountPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "POMI / MY ACCOUNT")
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("我的 Pomi")
                            .font(.system(size: 29, weight: .bold, design: .monospaced))
                        Text("每一只都有自己的小故事。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                    TinyDevice(session: CompanionSession())
                        .scaleEffect(0.49)
                        .frame(width: 76, height: 64)
                        .accessibilityHidden(true)
                }
                if let profile {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "我的账号")
                        Text(profile.email).font(.subheadline).textSelection(.enabled)
                        HStack {
                            Text("好友码")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = profile.friendCode
                                copiedFriendCode = profile.friendCode
                            } label: {
                                Label(copiedFriendCode == profile.friendCode ? "已复制" : "复制",
                                      systemImage: copiedFriendCode == profile.friendCode ? "checkmark" : "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(copiedFriendCode == profile.friendCode ? "已复制好友码" : "复制好友码")
                        }
                        Text(profile.friendCode)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .tracking(1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .textSelection(.enabled)
                            .accessibilityLabel("好友码 \(profile.friendCode)")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paper, in: PixelFrame())
                    .overlay(PixelFrame().stroke(Palette.line, lineWidth: 1))

                    Eyebrow(text: "我的挂件 · \(profile.pomiIDs.count) 只")
                    if profile.pomiIDs.isEmpty {
                        Text("还没有小伙伴，先绑定一只 Pomi 吧。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    ForEach(profile.pomiIDs, id: \.self) { id in
                        let current = selectedPomi == id
                        Button {
                            selectedPomi = id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "pawprint.fill")
                                    .frame(width: 28, height: 28)
                                    .background(Palette.room, in: PixelFrame(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pomi · \(id.suffix(8).uppercased())")
                                        .font(.subheadline.bold())
                                    Text(id).font(.caption2).foregroundStyle(Palette.muted)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                if current {
                                    Label("当前", systemImage: "checkmark.circle.fill")
                                        .font(.caption2.bold())
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(current ? Palette.room : Palette.paper, in: PixelFrame())
                            .overlay(PixelFrame().stroke(current ? Palette.ink : Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(current ? .isSelected : [])
                    }
                    Text("测试切换只选择编号。实时互动需要连接对应挂件。")
                        .font(.caption).foregroundStyle(Palette.muted)

                    DisclosureGroup("添加测试 Pomi") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("测试 Pomi 编号", text: $pomiID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("生成测试编号") { pomiID = UUID().uuidString }
                                .buttonStyle(QuietButtonStyle())
                            Button("绑定测试 Pomi") { run {
                                profileUpdate(try await request("test-bind", body: ["pomiID": pomiID]))
                            } }
                            .buttonStyle(FilledButtonStyle())
                            .disabled(UUID(uuidString: pomiID) == nil)
                        }
                        .padding(.top, 10)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(Palette.paper, in: PixelFrame())
                    Button("退出登录", role: .destructive) { run {
                        _ = try await request("logout")
                        token = nil
                        self.profile = nil
                        onLogout?()
                    } }
                    .buttonStyle(QuietButtonStyle())
                } else if message.isEmpty {
                    ProgressView("正在读取账号…")
                }
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(Palette.muted)
                }
                Eyebrow(text: "账号测试")
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .disabled(busy)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Palette.ink)
        .task {
            do { profileUpdate(try await request("profile")) }
            catch { message = error.localizedDescription }
        }
    }

    private func profileUpdate(_ data: Data) {
        do { applyProfile(try JSONDecoder().decode(AccountProfile.self, from: data)) }
        catch { message = error.localizedDescription }
    }

    private func applyProfile(_ current: AccountProfile) {
        profile = current
        if !current.pomiIDs.contains(selectedPomi ?? "") {
            selectedPomi = current.pomiIDs.first
        }
    }

    private var loginPage: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            PixelGrid().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "POMI / LITTLE COMPANION")
                    TinyDevice(session: CompanionSession())
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(showingRegistration ? "注册账号" : "欢迎回到小屋")
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                        Text(showingRegistration ? "输入邮箱和密码，创建你的 Pomi 账号。" : "Pomi 正在等你喵。")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("账号服务地址").font(.caption.bold())
                        TextField("http://你的Mac名称.local:8788", text: $serviceAddress)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Text("iPhone 和运行服务的 Mac 需要连接同一个 Wi-Fi。")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    .disabled(busy)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("邮箱", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Palette.paper, in: PixelFrame())
                        SecureField("密码（至少 8 个字符）", text: $password)
                            .textContentType(showingRegistration ? .newPassword : .password)
                            .padding(12)
                            .background(Palette.paper, in: PixelFrame())
                        if showingRegistration {
                            Button(busy ? "正在注册…" : "创建账号") { register() }
                                .buttonStyle(FilledButtonStyle())
                            Button("返回登录") { showRegistration(false) }
                                .buttonStyle(QuietButtonStyle())
                        } else {
                            Button(busy ? "请稍等喵…" : "登录小屋") { login() }
                                .buttonStyle(FilledButtonStyle())
                            Button("第一次来？注册账号") { showRegistration(true) }
                                .buttonStyle(QuietButtonStyle())
                        }
                        if !message.isEmpty {
                            Text(message).font(.footnote).foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(16)
                    .background(.white, in: PixelFrame())
                    .overlay(PixelFrame().stroke(Palette.line, lineWidth: 1))
                    .disabled(busy)
                    if !showingRegistration, let onContinueWithoutAccount {
                        Button("不登录，连接挂件", action: onContinueWithoutAccount)
                            .buttonStyle(QuietButtonStyle())
                            .disabled(busy)
                    }

                }
                .padding(24)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .fontDesign(.monospaced)
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
    }

    private func showRegistration(_ visible: Bool) {
        password = ""
        message = ""
        showingRegistration = visible
    }

    private func register() {
        run {
            _ = try await request("register", body: ["email": email, "password": password])
            showRegistration(false)
            message = "注册成功，请登录。"
        }
    }

    private func login() {
        run {
            let url = try AccountAPI.serviceURL(from: serviceAddress)
            let data = try await AccountAPI.request("login", body: ["email": email, "password": password],
                                                    token: nil, baseURL: url)
            let newToken = try JSONDecoder().decode(Login.self, from: data).token
            let profileData = try await AccountAPI.request("profile", token: newToken, baseURL: url)
            let current = try JSONDecoder().decode(AccountProfile.self, from: profileData)
            token = newToken
            password = ""
            applyProfile(current)
            onAuthenticated?(current.friendCode, url)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        message = ""
        Task {
            defer { busy = false }
            do { try await action() }
            catch { message = error.localizedDescription }
        }
    }

    private func request(_ action: String, body: [String: String] = [:]) async throws -> Data {
        let url = try sessionURL ?? AccountAPI.serviceURL(from: serviceAddress)
        return try await AccountAPI.request(action, body: body, token: token, baseURL: url)
    }
}

struct AccountProfile: Decodable {
    let email: String
    let friendCode: String
    let pomiIDs: [String]
    let friends: [String]
    let incomingFriends: [String]
    let outgoingFriends: [String]
}

enum AccountAPI {
    static var defaultAddress: String {
        #if targetEnvironment(simulator)
        "http://127.0.0.1:8787"
        #else
        ""
        #endif
    }

    static func serviceURL(from text: String) throws -> URL {
        let example = "请输入账号服务地址，例如 http://你的Mac名称.local:8788。"
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw PhysicalError.message(example)
        }
        let loopback = host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
        #if !targetEnvironment(simulator)
        if loopback { throw PhysicalError.message("请填写 Mac 的 .local 地址。127.0.0.1 指向这台 iPhone。") }
        #endif
        guard scheme == "https" || (scheme == "http" && (host.hasSuffix(".local") || loopback)) else {
            throw PhysicalError.message("同一 Wi-Fi 测试请使用 Mac 的 .local 地址，其他服务请使用 HTTPS。")
        }
        parts.scheme = scheme
        parts.host = host
        parts.path = ""
        guard let url = parts.url else { throw PhysicalError.message(example) }
        return url
    }

    private struct Failure: Decodable { let error: String }

    static func request(_ action: String, body: [String: String] = [:], token: String?, baseURL: URL) async throws -> Data {
        let url = baseURL.appendingPathComponent("account").appendingPathComponent(action)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw PhysicalError.message(failure?.error ?? "账号测试服务暂时不可用")
        }
        return data
    }
}
#endif
