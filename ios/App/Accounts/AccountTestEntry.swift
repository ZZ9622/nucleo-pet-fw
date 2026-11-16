import SwiftUI

#if os(iOS)
struct AccountTestEntry: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var sessionURL: URL?
    @State private var usingWithoutAccount = false
    @State private var selectedPomi: String?
    @State private var token: String?

    var body: some View {
        if let sessionURL, let token {
            RootView(accountPage: AnyView(
                AccountTestView(onLogout: {
                    store.world.leaveAccount()
                    selectedPomi = nil
                    self.sessionURL = nil
                }, sessionURL: sessionURL, token: $token, selectedPomi: $selectedPomi)
            ), selectedPomi: selectedPomi, socialPage: AnyView(SocialView(token: token, serviceURL: sessionURL).environmentObject(store.world)))
            .task { await store.world.connect() }
        } else if usingWithoutAccount {
            RootView(accountPage: AnyView(
                Button("返回登录") { usingWithoutAccount = false }
                    .buttonStyle(FilledButtonStyle())
            ))
        } else {
            AccountTestView(onAuthenticated: { accountID, url in
                guard let token else { return }
                store.enterDevelopmentPreview()
                store.world.useAccount(token: token, id: accountID, url: url)
                sessionURL = url
            }, onContinueWithoutAccount: {
                store.showConnectionSettings()
                usingWithoutAccount = true
            }, token: $token, selectedPomi: $selectedPomi)
        }
    }
}
#endif
