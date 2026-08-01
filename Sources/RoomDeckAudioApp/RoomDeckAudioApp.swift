import AppKit
import MediaPlayer
import SwiftUI

enum ProductIdentity {
    static let name = "RoomDeck Audio"
    static let callbackScheme = "roomdeck-audio"
    static let legacyCallbackScheme = "homewave"
    static let callbackSchemes: Set<String> = [callbackScheme, legacyCallbackScheme]
    static let callbackHost = "sonos-auth"
}

@MainActor
final class RoomDeckApplicationDelegate: NSObject, NSApplicationDelegate {
    private var openURLHandler: ((URL) -> Void)?
    private var pendingURLs: [URL] = []

    func installOpenURLHandler(_ handler: @escaping (URL) -> Void) {
        openURLHandler = handler
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach(handler)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let openURLHandler {
                openURLHandler(url)
            } else {
                pendingURLs.append(url)
            }
        }

        application.activate(ignoringOtherApps: true)
        application.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct RoomDeckAudioApp: App {
    @NSApplicationDelegateAdaptor(RoomDeckApplicationDelegate.self) private var appDelegate
    @StateObject private var model = SonosModel()

    var body: some Scene {
        Window(ProductIdentity.name, id: "main") {
            SonosWindow()
                .environmentObject(model)
                .frame(minWidth: 1_080, minHeight: 680)
                .background(Theme.black)
                .onAppear {
                    appDelegate.installOpenURLHandler { url in
                        model.completeSonosSignIn(from: url)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_420, height: 860)
        .commands {
            CommandMenu("Playback") {
                Button(model.isPlaying ? "Pause" : "Play") {
                    model.togglePrimaryPlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.isSonosAccountConnected || model.selectedCloudGroup == nil)

                Button("Previous") { model.skipPrimary(forward: false) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(!model.isSonosAccountConnected || model.selectedCloudGroup == nil)

                Button("Next") { model.skipPrimary(forward: true) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(!model.isSonosAccountConnected || model.selectedCloudGroup == nil)
            }
        }
    }
}

enum Theme {
    static let black = Color(red: 0.005, green: 0.005, blue: 0.005)
    static let panel = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let text = Color.white.opacity(0.92)
}

@MainActor
final class SonosModel: ObservableObject {
    @Published private(set) var isSonosAccountConnected = false
    @Published private(set) var isSonosSigningIn = false
    @Published private(set) var cloudGroups: [CloudGroup] = []
    @Published private(set) var cloudFavorites: [CloudFavorite] = []
    @Published private(set) var cloudPlayers: [CloudPlayer] = []
    @Published private(set) var ungroupingCloudGroupIDs: Set<String> = []
    @Published private(set) var isLoadingCloudData = false
    @Published private(set) var isRefreshingCloudData = false
    @Published var selectedCloudGroupID: String?
    @Published var sonosAccountStatus = "Sign in to connect your compatible Sonos system"

    private let sonosCloud = SonosCloudConnector()
    private lazy var cloudControl = SonosCloudControl(session: sonosCloud)
    private var mediaCommandsConfigured = false
    private var pendingSonosSignInState: String?
    private var sonosSignInCallbackTickets = OneTimeCallbackRegistry()
    private var cloudVolumeTasks: [String: Task<Void, Never>] = [:]

    var selectedCloudGroup: CloudGroup? {
        if let selectedCloudGroupID,
            let selected = cloudGroups.first(where: { $0.id == selectedCloudGroupID })
        {
            return selected
        }
        return cloudGroups.first(where: \.isPlaying) ?? cloudGroups.first
    }

    var isPlaying: Bool {
        selectedCloudGroup?.isPlaying ?? false
    }

    func configureMediaCommands() {
        guard !mediaCommandsConfigured else { return }
        mediaCommandsConfigured = true

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true

        commands.playCommand.addTarget { [weak self] _ in
            guard let self, self.isSonosAccountConnected, !self.isPlaying else { return .commandFailed }
            Task { @MainActor in self.togglePrimaryPlayback() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isSonosAccountConnected, self.isPlaying else { return .commandFailed }
            Task { @MainActor in self.togglePrimaryPlayback() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.isSonosAccountConnected else { return .commandFailed }
            Task { @MainActor in self.togglePrimaryPlayback() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isSonosAccountConnected else { return .commandFailed }
            Task { @MainActor in self.skipPrimary(forward: true) }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isSonosAccountConnected else { return .commandFailed }
            Task { @MainActor in self.skipPrimary(forward: false) }
            return .success
        }
        updateNowPlayingInfo()
    }

    func restoreSonosAccountSession() async {
        isSonosAccountConnected = await sonosCloud.hasSession()
        if isSonosAccountConnected {
            sonosAccountStatus = "Sonos account connected"
            await refreshCloudData()
        }
    }

    func refreshCloudData() async {
        guard isSonosAccountConnected, !isLoadingCloudData, !isRefreshingCloudData else { return }
        let initialLoad = cloudGroups.isEmpty && cloudFavorites.isEmpty
        if initialLoad {
            isLoadingCloudData = true
        } else {
            isRefreshingCloudData = true
        }
        defer {
            isLoadingCloudData = false
            isRefreshingCloudData = false
        }

        do {
            let snapshot = try await cloudControl.snapshot()
            cloudGroups = snapshot.groups
            cloudFavorites = snapshot.favorites
            cloudPlayers = snapshot.players
            if selectedCloudGroupID == nil
                || !snapshot.groups.contains(where: { $0.id == selectedCloudGroupID })
            {
                selectedCloudGroupID =
                    snapshot.groups.first(where: \.isPlaying)?.id
                    ?? snapshot.groups.first?.id
            }
            sonosAccountStatus =
                snapshot.groups.isEmpty
                ? "No Sonos groups are available"
                : "Sonos account connected"
            updateNowPlayingInfo()
        } catch {
            sonosAccountStatus = error.localizedDescription
        }
    }

    func selectCloudGroup(_ group: CloudGroup) {
        selectedCloudGroupID = group.id
        updateNowPlayingInfo()
    }

    func togglePrimaryPlayback() {
        guard let group = selectedCloudGroup else { return }
        toggleCloudPlayback(group)
    }

    func skipPrimary(forward: Bool) {
        guard let group = selectedCloudGroup else { return }
        skipCloudPlayback(group, forward: forward)
    }

    func toggleCloudPlayback(_ group: CloudGroup) {
        selectCloudGroup(group)
        updateGroup(group.id) {
            $0.playbackState = group.isPlaying ? "PLAYBACK_STATE_PAUSED" : "PLAYBACK_STATE_PLAYING"
        }
        updateNowPlayingInfo()

        Task {
            do {
                try await cloudControl.togglePlayback(group: group)
                try? await Task.sleep(for: .milliseconds(350))
                await refreshCloudData()
            } catch {
                sonosAccountStatus = error.localizedDescription
                await refreshCloudData()
            }
        }
    }

    func skipCloudPlayback(_ group: CloudGroup, forward: Bool) {
        selectCloudGroup(group)
        Task {
            do {
                try await cloudControl.skip(groupID: group.id, forward: forward)
                try? await Task.sleep(for: .milliseconds(350))
                await refreshCloudData()
            } catch {
                sonosAccountStatus = error.localizedDescription
            }
        }
    }

    func previewCloudVolume(_ volume: Double, for group: CloudGroup) {
        selectCloudGroup(group)
        let target = min(100, max(0, Int(volume.rounded())))
        updateGroup(group.id) { $0.volume = target }
        cloudVolumeTasks[group.id]?.cancel()
        cloudVolumeTasks[group.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self else { return }
                try await self.cloudControl.setVolume(target, groupID: group.id)
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.sonosAccountStatus = error.localizedDescription
            }
        }
    }

    func setCloudVolume(_ volume: Double, for group: CloudGroup) {
        selectCloudGroup(group)
        let target = min(100, max(0, Int(volume.rounded())))
        cloudVolumeTasks[group.id]?.cancel()
        cloudVolumeTasks[group.id] = nil
        updateGroup(group.id) { $0.volume = target }
        Task {
            do {
                try await cloudControl.setVolume(target, groupID: group.id)
            } catch {
                sonosAccountStatus = error.localizedDescription
                await refreshCloudData()
            }
        }
    }

    func playCloudFavorite(_ favorite: CloudFavorite, on group: CloudGroup) {
        selectCloudGroup(group)
        Task {
            do {
                try await cloudControl.loadFavorite(favorite, groupID: group.id)
                try? await Task.sleep(for: .milliseconds(500))
                await refreshCloudData()
            } catch {
                sonosAccountStatus = error.localizedDescription
            }
        }
    }

    func createCloudGroup(playerIDs: [String], keepingPlaybackFrom group: CloudGroup?) {
        Task {
            do {
                try await cloudControl.createGroup(
                    playerIDs: playerIDs,
                    musicContextGroupID: group?.id
                )
                try? await Task.sleep(for: .milliseconds(600))
                await refreshCloudData()
            } catch {
                sonosAccountStatus = error.localizedDescription
            }
        }
    }

    func ungroupCloudGroup(_ group: CloudGroup) {
        guard group.playerIDs.count > 1, !ungroupingCloudGroupIDs.contains(group.id) else { return }
        ungroupingCloudGroupIDs.insert(group.id)
        Task {
            defer { ungroupingCloudGroupIDs.remove(group.id) }
            do {
                try await cloudControl.ungroup(group)
                selectedCloudGroupID = nil
                try? await Task.sleep(for: .milliseconds(600))
                await refreshCloudData()
            } catch {
                sonosAccountStatus = "Could not ungroup \(group.name): \(error.localizedDescription)"
                await refreshCloudData()
            }
        }
    }

    func connectSonosAccount() {
        guard !isSonosSigningIn else { return }
        let state = UUID().uuidString
        pendingSonosSignInState = state
        UserDefaults.standard.set(state, forKey: "pendingSonosSignInState")
        isSonosSigningIn = true
        sonosAccountStatus = "Waiting for Sonos sign-in..."

        Task {
            do {
                try await sonosCloud.openLogin(state: state)
            } catch {
                isSonosSigningIn = false
                sonosAccountStatus = error.localizedDescription
            }
        }
    }

    func completeSonosSignIn(from url: URL) {
        guard let scheme = url.scheme?.lowercased(),
            ProductIdentity.callbackSchemes.contains(scheme),
            url.host?.lowercased() == ProductIdentity.callbackHost
        else { return }
        guard let callback = SonosAuthCallback(url: url) else {
            sonosAccountStatus = SonosCloudError.invalidCallback.localizedDescription
            return
        }
        guard !sonosSignInCallbackTickets.contains(callback.ticket) else { return }
        guard
            callback.state
                == (pendingSonosSignInState
                    ?? UserDefaults.standard.string(forKey: "pendingSonosSignInState"))
        else {
            sonosAccountStatus = SonosCloudError.stateMismatch.localizedDescription
            return
        }
        guard sonosSignInCallbackTickets.begin(callback.ticket) else { return }

        sonosAccountStatus = "Completing Sonos sign-in..."
        Task {
            do {
                _ = try await sonosCloud.completeLogin(
                    ticket: callback.ticket,
                    expectedState: callback.state
                )
                isSonosAccountConnected = true
                isSonosSigningIn = false
                pendingSonosSignInState = nil
                UserDefaults.standard.removeObject(forKey: "pendingSonosSignInState")
                sonosAccountStatus = "Sonos account connected"
                await refreshCloudData()
            } catch {
                isSonosSigningIn = false
                sonosAccountStatus = error.localizedDescription
            }
        }
    }

    func disconnectSonosAccount() {
        Task {
            do {
                try await sonosCloud.disconnect()
                isSonosAccountConnected = false
                isSonosSigningIn = false
                cloudGroups = []
                cloudFavorites = []
                cloudPlayers = []
                selectedCloudGroupID = nil
                sonosAccountStatus = "Sign in to connect your compatible Sonos system"
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            } catch {
                sonosAccountStatus = error.localizedDescription
            }
        }
    }

    private func updateGroup(_ id: String, mutate: (inout CloudGroup) -> Void) {
        guard let index = cloudGroups.firstIndex(where: { $0.id == id }) else { return }
        mutate(&cloudGroups[index])
    }

    private func updateNowPlayingInfo() {
        guard let group = selectedCloudGroup else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: group.nowPlaying ?? group.name,
            MPMediaItemPropertyArtist:
                group.nowPlayingSubtitle ?? group.nowPlayingService ?? group.name,
            MPNowPlayingInfoPropertyPlaybackRate: group.isPlaying ? 1 : 0,
        ]
    }
}

struct SonosWindow: View {
    @EnvironmentObject private var model: SonosModel

    var body: some View {
        Group {
            if model.isSonosAccountConnected {
                MainView()
            } else {
                SignInView()
            }
        }
        .background(WindowSizeGuard())
        .foregroundStyle(Theme.text)
        .font(.system(size: 14))
        .background(Theme.black)
        .onAppear { model.configureMediaCommands() }
        .task { await model.restoreSonosAccountSession() }
    }
}

struct SignInView: View {
    @EnvironmentObject private var model: SonosModel

    var body: some View {
        ZStack {
            Theme.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    ProductWordmark()
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 28)

                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 76, height: 76)
                        .background(Color.white)
                        .clipShape(Circle())

                    VStack(spacing: 9) {
                        Text("Sign in to \(ProductIdentity.name)")
                            .font(.system(size: 28, weight: .bold))
                        Text("Connect your Sonos account to view and control your system.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        model.connectSonosAccount()
                    } label: {
                        HStack(spacing: 9) {
                            if model.isSonosSigningIn {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "person.badge.key")
                            }
                            Text(model.isSonosSigningIn ? "Waiting for Sonos..." : "Sign in with Sonos")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .frame(minWidth: 190)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(model.isSonosSigningIn)

                    Text(model.sonosAccountStatus)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    Text("Independent software compatible with Sonos. Not affiliated with or endorsed by Sonos, Inc.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                Spacer()
                Spacer()
            }
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: SonosModel

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView()
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                HStack(spacing: 0) {
                    FavoritesView()
                        .padding(.leading, 22)
                        .padding(.trailing, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Rectangle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 1)

                    ScrollView(.vertical, showsIndicators: true) {
                        CloudSystemSidebar()
                    }
                    .frame(width: 390)
                    .padding(.horizontal, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            CloudBottomPlayerBar()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await model.refreshCloudData()
            }
        }
    }
}

struct ProductWordmark: View {
    var body: some View {
        Text("ROOMDECK AUDIO")
            .font(.system(size: 22, weight: .black))
            .tracking(4)
    }
}

struct HeaderView: View {
    @State private var showsSettings = false

    var body: some View {
        HStack {
            ProductWordmark()
            Spacer()
            Button {
                showsSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .popover(isPresented: $showsSettings, arrowEdge: .top) {
                SettingsView()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: SonosModel

    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 18, weight: .bold))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sonos Account")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text(model.sonosAccountStatus)
                        .font(.system(size: 13))
                        .lineLimit(2)

                    Button {
                        Task { await model.refreshCloudData() }
                    } label: {
                        Label(
                            model.isRefreshingCloudData ? "Refreshing..." : "Refresh system",
                            systemImage: "arrow.clockwise"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRefreshingCloudData)

                    Button {
                        model.disconnectSonosAccount()
                    } label: {
                        Label("Disconnect Sonos", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Divider().overlay(Color.white.opacity(0.16))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Legal")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text(
                        "Independent software compatible with Sonos. Not affiliated with, endorsed by, or sponsored by Sonos, Inc. Sonos is a trademark of Sonos, Inc."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Sonos platform terms") {
                        guard let url = URL(string: "https://docs.sonos.com/docs/terms-of-service") else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)

                    if let privacyPolicyURL {
                        Button("Privacy policy") {
                            NSWorkspace.shared.open(privacyPolicyURL)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 310)
        .foregroundStyle(Color.white.opacity(0.94))
        .preferredColorScheme(.dark)
    }

    private var privacyPolicyURL: URL? {
        guard
            let value = Bundle.main.object(
                forInfoDictionaryKey: "PrivacyPolicyURL"
            ) as? String,
            let url = NetworkSecurityPolicy.validatedHTTPSBaseURL(value),
            url.host != "example.invalid"
        else { return nil }
        return url
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var model: SonosModel

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sonos Favorites")
                            .font(.system(size: 20, weight: .bold))
                        Text("Select a favorite to play it on the active group.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshCloudData() }
                    } label: {
                        if model.isRefreshingCloudData {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Refresh favorites")
                }

                if model.isLoadingCloudData {
                    ProgressView("Loading your Sonos system...")
                } else if model.cloudGroups.isEmpty {
                    Text(model.sonosAccountStatus)
                        .foregroundStyle(Color.white.opacity(0.62))
                } else if model.cloudFavorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "star",
                        description: Text("Favorites saved to your Sonos account will appear here.")
                    )
                    .foregroundStyle(Color.white.opacity(0.68))
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else if let target = model.selectedCloudGroup ?? model.cloudGroups.first {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(model.cloudFavorites) { favorite in
                            CloudFavoriteCard(favorite: favorite, target: target)
                        }
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }
}

struct CloudFavoriteCard: View {
    @EnvironmentObject private var model: SonosModel
    let favorite: CloudFavorite
    let target: CloudGroup

    var body: some View {
        Button {
            model.playCloudFavorite(favorite, on: target)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CloudArtwork(url: favorite.imageURL, size: 156, contentMode: .fit)
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(favorite.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(2)
                        if !favorite.subtitle.isEmpty {
                            Text(favorite.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.58))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(Color.white)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: 1)
                    }
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                }
                .frame(minHeight: 38, alignment: .top)
            }
            .frame(width: 156, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Play on \(target.name)")
    }
}

struct CloudSystemSidebar: View {
    @EnvironmentObject private var model: SonosModel
    @State private var showsNewGroup = false
    @State private var editingGroup: CloudGroup?
    @State private var draftVolumes: [String: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your System").font(.system(size: 18, weight: .bold))
                Spacer()
                Button {
                    Task { await model.refreshCloudData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh system")

                Button {
                    showsNewGroup = true
                } label: {
                    Label("New group", systemImage: "speaker.wave.3")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            Text("\(model.cloudGroups.count) group\(model.cloudGroups.count == 1 ? "" : "s") available")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.58))

            ForEach(model.cloudGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CloudArtwork(url: group.artworkURL, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name).font(.system(size: 18, weight: .bold))
                            Text("\(group.playerIDs.count) speaker\(group.playerIDs.count == 1 ? "" : "s")")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.62))
                            if let nowPlaying = group.nowPlaying {
                                Text(nowPlaying)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            if let detail = group.nowPlayingSubtitle ?? group.nowPlayingService {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.58))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            model.toggleCloudPlayback(group)
                        } label: {
                            Image(systemName: group.isPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 42, height: 42)
                                .background(Color.white.opacity(0.14))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(group.isPlaying ? "Pause" : "Play")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").font(.system(size: 12))
                        Slider(
                            value: Binding(
                                get: { draftVolumes[group.id] ?? Double(group.volume ?? 0) },
                                set: { value in
                                    draftVolumes[group.id] = value
                                    model.previewCloudVolume(value, for: group)
                                }
                            ),
                            in: 0...100,
                            onEditingChanged: { editing in
                                if editing {
                                    draftVolumes[group.id] = Double(group.volume ?? 0)
                                } else {
                                    let value = draftVolumes[group.id] ?? Double(group.volume ?? 0)
                                    model.setCloudVolume(value, for: group)
                                    draftVolumes[group.id] = nil
                                }
                            }
                        )
                        Text("\(Int((draftVolumes[group.id] ?? Double(group.volume ?? 0)).rounded()))")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, alignment: .trailing)
                    }

                    HStack(spacing: 8) {
                        Button {
                            editingGroup = group
                        } label: {
                            Label("Edit group", systemImage: "slider.horizontal.3")
                        }

                        if group.playerIDs.count > 1 {
                            Button {
                                model.ungroupCloudGroup(group)
                            } label: {
                                if model.ungroupingCloudGroupIDs.contains(group.id) {
                                    ProgressView().controlSize(.small).frame(minWidth: 70)
                                } else {
                                    Label("Ungroup", systemImage: "speaker.minus.fill")
                                }
                            }
                            .disabled(model.ungroupingCloudGroupIDs.contains(group.id))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color.white.opacity(model.selectedCloudGroupID == group.id ? 0.22 : 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            model.selectedCloudGroupID == group.id
                                ? Color.white.opacity(0.62) : .clear,
                            lineWidth: 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { model.selectCloudGroup(group) }
            }
        }
        .padding(.vertical, 22)
        .sheet(isPresented: $showsNewGroup) { CloudGroupEditor(seedGroup: nil) }
        .sheet(item: $editingGroup) { CloudGroupEditor(seedGroup: $0) }
    }
}

struct CloudArtwork: View {
    let url: URL?
    let size: CGFloat
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack {
            Color.white.opacity(0.1)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        fallback
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var fallback: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.62))
    }
}

struct CloudGroupEditor: View {
    @EnvironmentObject private var model: SonosModel
    @Environment(\.dismiss) private var dismiss
    let seedGroup: CloudGroup?
    @State private var selectedIDs: Set<String>
    @State private var sourceGroupID: String?

    init(seedGroup: CloudGroup?) {
        self.seedGroup = seedGroup
        _selectedIDs = State(initialValue: Set(seedGroup?.playerIDs ?? []))
        _sourceGroupID = State(initialValue: seedGroup?.id)
    }

    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(seedGroup.map { "Edit \($0.name)" } ?? "Create a Group")
                        .font(.system(size: 22, weight: .bold))
                    Text("Choose the rooms that should play together.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Speakers")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.56))

                    ForEach(model.cloudPlayers) { player in
                        Toggle(
                            isOn: Binding(
                                get: { selectedIDs.contains(player.id) },
                                set: { enabled in
                                    if enabled {
                                        selectedIDs.insert(player.id)
                                    } else {
                                        selectedIDs.remove(player.id)
                                    }
                                }
                            )
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: "hifispeaker.fill")
                                    .frame(width: 22)
                                    .foregroundStyle(Color.white.opacity(0.7))
                                Text(player.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(Color.white.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Playback source")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Picker("Playback source", selection: $sourceGroupID) {
                        Text("Start without audio").tag(String?.none)
                        ForEach(model.cloudGroups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text("\(selectedIDs.count) selected")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Button("Apply") {
                        model.createCloudGroup(
                            playerIDs: Array(selectedIDs),
                            keepingPlaybackFrom: model.cloudGroups.first {
                                $0.id == sourceGroupID
                            }
                        )
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 430)
        .foregroundStyle(Color.white.opacity(0.94))
        .preferredColorScheme(.dark)
    }
}

struct CloudBottomPlayerBar: View {
    @EnvironmentObject private var model: SonosModel
    @State private var draftVolume: Double?
    @State private var editingVolumeGroupID: String?

    var body: some View {
        let group = model.selectedCloudGroup

        HStack(spacing: 20) {
            HStack(spacing: 14) {
                CloudArtwork(url: group?.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(model.cloudGroups) { item in
                            Button {
                                model.selectCloudGroup(item)
                            } label: {
                                if item.id == group?.id {
                                    Label(item.name, systemImage: "checkmark")
                                } else {
                                    Text(item.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(group?.name ?? "Choose a group")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.82))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .environment(\.colorScheme, .dark)
                    .fixedSize()

                    Text(group?.nowPlaying ?? (group?.isPlaying == true ? "Playing" : "Nothing playing"))
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)

                    if let detail = playbackDetail(group) {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 210, maxWidth: 310, alignment: .leading)
            }

            Spacer()

            HStack(spacing: 22) {
                PlayerButton(systemName: "backward.end.fill", help: "Previous track") {
                    if let group { model.skipCloudPlayback(group, forward: false) }
                }
                .disabled(group == nil)

                Button {
                    if let group { model.toggleCloudPlayback(group) }
                } label: {
                    Image(systemName: group?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 50, height: 50)
                        .background(Color.white)
                        .foregroundStyle(Color.black)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(group == nil)
                .help(group?.isPlaying == true ? "Pause" : "Play")

                PlayerButton(systemName: "forward.end.fill", help: "Next track") {
                    if let group { model.skipCloudPlayback(group, forward: true) }
                }
                .disabled(group == nil)
            }

            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.68))
                Slider(
                    value: Binding(
                        get: {
                            if editingVolumeGroupID == group?.id, let draftVolume {
                                return draftVolume
                            }
                            return Double(group?.volume ?? 0)
                        },
                        set: { value in
                            guard let group else { return }
                            editingVolumeGroupID = group.id
                            draftVolume = value
                            model.previewCloudVolume(value, for: group)
                        }
                    ),
                    in: 0...100,
                    onEditingChanged: { editing in
                        guard let group else { return }
                        if editing {
                            editingVolumeGroupID = group.id
                            draftVolume = Double(group.volume ?? 0)
                        } else {
                            model.setCloudVolume(
                                draftVolume ?? Double(group.volume ?? 0),
                                for: group
                            )
                            draftVolume = nil
                            editingVolumeGroupID = nil
                        }
                    }
                )
                .disabled(group == nil)
                Text("\(Int((draftVolume ?? Double(group?.volume ?? 0)).rounded()))")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, alignment: .trailing)
            }
            .frame(width: 230)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .background(Theme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 14, y: -5)
        .onChange(of: group?.id) {
            draftVolume = nil
            editingVolumeGroupID = nil
        }
    }

    private func playbackDetail(_ group: CloudGroup?) -> String? {
        guard let group else { return nil }
        let values = [group.nowPlayingSubtitle, group.nowPlayingService]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return group.isPlaying ? "Playing" : "Ready" }
        return Array(NSOrderedSet(array: values))
            .compactMap { $0 as? String }
            .joined(separator: " · ")
    }
}

struct PlayerButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct WindowSizeGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.minSize = NSSize(width: 1_080, height: 680)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
