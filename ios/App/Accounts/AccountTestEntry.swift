import SwiftUI

#if os(iOS)
struct AccountTestEntry: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var sessionURL: URL?
    @State private var usingWithoutAccount = false
    @State private var openTowerOnEntry = false
    @State private var selectedPomi: String?
    @State private var token: String?

    var body: some View {
        if let sessionURL, token != nil {
            RootView(accountPage: AnyView(
                AccountTestView(onLogout: {
                    store.world.leaveAccount()
                    selectedPomi = nil
                    self.sessionURL = nil
                }, sessionURL: sessionURL, token: $token, selectedPomi: $selectedPomi)
            ), selectedPomi: selectedPomi, signedIn: true)
            .task { await store.world.connect() }
        } else if usingWithoutAccount {
            RootView(accountPage: AnyView(
                Button("返回登录") { usingWithoutAccount = false }
                    .buttonStyle(FilledButtonStyle())
            ), startsInTower: openTowerOnEntry)
        } else {
            AccountTestView(onAuthenticated: { accountID, url in
                guard let token else { return }
                store.enterLocalTower()
                store.world.useAccount(token: token, id: accountID, url: url)
                sessionURL = url
            }, onOpenLocalTower: {
                store.enterLocalTower()
                openTowerOnEntry = true
                usingWithoutAccount = true
            }, onContinueWithoutAccount: {
                store.showConnectionSettings()
                openTowerOnEntry = false
                usingWithoutAccount = true
            }, token: $token, selectedPomi: $selectedPomi)
        }
    }
}
#endif
