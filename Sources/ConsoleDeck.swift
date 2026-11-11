import AppKit
import CoreGraphics
import OSLog
import ServiceManagement
import SwiftUI

struct DeckKey: Identifiable, Equatable {
    let id: String
    let label: String

    static let keys = (1...9).map { DeckKey(id: "BUTTON_\($0)", label: "Key \($0)") }
        + [DeckKey(id: "MEDIA", label: "Media")]
}

final class DeckModel: ObservableObject {
    @Published private(set) var actions: [String: DeckAction]
    @Published private(set) var connection = "Connect the ConsoleDeck by USB"
    @Published private(set) var connected = false
    @Published private(set) var lastInput = "Waiting for input"
    @Published private(set) var mediaAllowed = CGPreflightPostEventAccess()
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginError = ""

    private let defaults: UserDefaults
    private let log: FileHandle?
    private var serial: DeckSerial?

    init(defaults: UserDefaults = .standard, recordActivity: Bool = true) {
        self.defaults = defaults
        let data = defaults.data(forKey: "deckActions") ?? Data()
        actions = (try? JSONDecoder().decode([String: DeckAction].self, from: data)) ?? [:]
        log = recordActivity ? Self.openLog() : nil
    }

    func connect() {
        serial = DeckSerial(status: { [weak self] message, connected in
            DispatchQueue.main.async {
                guard let self, self.connection != message || self.connected != connected else { return }
                self.connection = message
                self.connected = connected
                self.record(message)
            }
        }, receive: { [weak self] message in
            DispatchQueue.main.async { self?.handle(message) }
        })
        serial?.start()
    }

    func action(for key: DeckKey) -> DeckAction {
        actions[key.id] ?? DeckAction(kind: key.id == "MEDIA" ? .playPause : .none)
    }

    func save(_ action: DeckAction, for key: DeckKey) {
        guard action.isValid else { return }
        var updated = actions
        updated[key.id] = action
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: "deckActions")
        actions = updated
    }

    func resolved(_ message: String) -> (String, DeckAction)? {
        if let key = DeckKey.keys.first(where: { $0.id == message }) {
            return (key.label, action(for: key))
        }
        switch message {
        case "MUTE": return ("Knob press", DeckAction(kind: .mute))
        case "VOLUME_UP": return ("Knob clockwise", DeckAction(kind: .volumeUp))
        case "VOLUME_DOWN": return ("Knob counterclockwise", DeckAction(kind: .volumeDown))
        default: return nil
        }
    }

    private func handle(_ message: String) {
        guard let (label, action) = resolved(message) else { return }
        let result = action.run()
        lastInput = "\(label) · \(result)"
        record("\(message) | \(action.kind.rawValue) | \(result)")
        if result == "Accessibility permission needed" { mediaAllowed = false }
    }

    func refreshPermissions() {
        mediaAllowed = CGPreflightPostEventAccess()
        loginStatus = SMAppService.mainApp.status
    }

    func requestMediaAccess() {
        if !CGRequestPostEventAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    func enableLogin() {
        loginError = ""
        if loginStatus == .enabled { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
        record("Start at login status \(loginStatus.rawValue) \(loginError)")
    }

    func changeLogin() {
        refreshPermissions()
        if loginStatus == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        } else if loginStatus == .enabled {
            do {
                try SMAppService.mainApp.unregister()
                loginError = ""
            } catch {
                loginError = error.localizedDescription
            }
            refreshPermissions()
        } else {
            enableLogin()
        }
    }

    private static func openLog() -> FileHandle? {
        let folder = URL.applicationSupportDirectory.appending(path: "ConsoleDeck", directoryHint: .isDirectory)
        let url = folder.appending(path: "activity.log")
        do {
            let files = FileManager.default
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if !files.fileExists(atPath: url.path) {
                files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let log = try FileHandle(forWritingTo: url)
            if try log.seekToEnd() > 512_000 {
                try log.truncate(atOffset: 0)
                try log.seek(toOffset: 0)
            }
            return log
        } catch {
            return nil
        }
    }

    private func record(_ message: String) {
        let line = "\(Date().ISO8601Format()) \(message)\n"
        try? log?.write(contentsOf: Data(line.utf8))
    }
}

struct DeckSettings: View {
    @ObservedObject var deck: DeckModel
    @State private var selected = DeckKey.keys[0]
    @State private var draft = DeckAction()
    @State private var shortcutMonitor: Any?
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ConsoleDeck").font(.largeTitle.bold())
                    Text("Configure the buttons on your deck.").foregroundStyle(.secondary)
                }
                Spacer()
                Label(deck.connection, systemImage: deck.connected ? "checkmark.circle.fill" : "cable.connector")
                    .font(.callout)
                    .foregroundStyle(deck.connected ? Color.green : Color.secondary)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(DeckKey.keys.prefix(9)) { key in keyTile(key) }
                    }
                    keyTile(DeckKey.keys[9], height: 47)
                }
                .frame(width: 292)

                VStack(alignment: .leading, spacing: 10) {
                    Text(selected.label).font(.title2.bold())
                    Picker("Action", selection: $draft.kind) {
                        ForEach(ActionKind.allCases) { kind in
                            Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                        }
                    }
                    .onChange(of: draft.kind) { _, _ in stopRecording() }

                    if draft.kind == .openItem {
                        Button("Choose App, File or Folder…") { pickFile() }
                        if !draft.target.isEmpty {
                            Text(draft.target).lineLimit(2).truncationMode(.middle).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if draft.kind == .openURL {
                        TextField("https://example.com", text: $draft.target).textFieldStyle(.roundedBorder)
                    } else if draft.kind == .shortcut {
                        Button(recording ? "Cancel Recording" : "Record Shortcut…") {
                            if recording { stopRecording() } else { recordShortcut() }
                        }
                        Text(recording ? "Press the shortcut now." : draft.shortcut?.label ?? "Choose a key combination.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Action") { deck.save(draft, for: selected) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.isValid || draft == deck.action(for: selected) || recording)

                    Divider().padding(.vertical, 3)
                    Label("Turn knob to change volume", systemImage: "dial.medium")
                    Label("Push knob to mute or unmute", systemImage: "speaker.slash")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .frame(height: 240, alignment: .topLeading)
                .background(.quaternary.opacity(0.40), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                Image(systemName: "waveform.path")
                Text(deck.lastInput)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Label(deck.mediaAllowed ? "Keyboard control allowed" : "Keyboard control requires Accessibility",
                      systemImage: deck.mediaAllowed ? "checkmark.shield" : "lock.shield")
                Spacer()
                if !deck.mediaAllowed {
                    Button("Allow Keyboard Control…") { deck.requestMediaAccess() }
                }
            }
            HStack {
                Label(loginLabel, systemImage: "power")
                Spacer()
                Button(loginButton) { deck.changeLogin() }
            }
            if !deck.loginError.isEmpty {
                Text(deck.loginError).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 690)
        .onAppear {
            draft = deck.action(for: selected)
            deck.refreshPermissions()
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            deck.refreshPermissions()
        }
    }

    private var loginLabel: String {
        switch deck.loginStatus {
        case .enabled: return "Start at login is on"
        case .requiresApproval: return "Start at login needs approval"
        default: return "Start at login is off"
        }
    }

    private var loginButton: String {
        switch deck.loginStatus {
        case .enabled: return "Turn Off"
        case .requiresApproval: return "Open Login Items…"
        default: return "Start at Login"
        }
    }

    private func keyTile(_ key: DeckKey, height: CGFloat = 55) -> some View {
        let action = deck.action(for: key)
        let isSelected = selected == key
        return Button {
            stopRecording()
            selected = key
            draft = action
        } label: {
            VStack(spacing: 3) {
                Label(key.label, systemImage: action.kind.icon).font(.callout.weight(.semibold))
                Text(action.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(isSelected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.18)
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            draft.target = url.path
        }
    }

    private func recordShortcut() {
        recording = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat else { return nil }
            draft.shortcut = RecordedShortcut(event: event)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        recording = false
    }
}

final class DeckDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let deck = DeckModel()
    private var statusItem: NSStatusItem?
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let microphoneItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let log = Logger(subsystem: "local.codex.consoledeck", category: "microphone")
    private lazy var microphone = MicrophoneStatus { [weak self] state in
        self?.updateMicrophoneIndicator(state)
    }
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "ConsoleDeck")
        item.button?.toolTip = "ConsoleDeck"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(connectionItem)
        menu.addItem(microphoneItem)
        menu.addItem(.separator())
        let configure = NSMenuItem(title: "Configure Buttons…", action: #selector(showSettings), keyEquivalent: ",")
        configure.target = self
        menu.addItem(configure)
        menu.addItem(NSMenuItem(title: "Quit ConsoleDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        microphone.start()
        deck.connect()

        if CommandLine.arguments.contains("--setup") {
            deck.enableLogin()
            showSettings()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        connectionItem.title = deck.connection
        microphone.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        microphone.stop()
    }

    private func updateMicrophoneIndicator(_ state: MicState) {
        guard let button = statusItem?.button else { return }
        let size = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let configuration = state == .muted
            ? size.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            : size
        let icon = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.rawValue)?
            .withSymbolConfiguration(configuration)
        icon?.isTemplate = state != .muted
        button.image = icon
        button.toolTip = "ConsoleDeck · \(state.rawValue)"
        button.setAccessibilityLabel("ConsoleDeck, \(state.rawValue)")
        microphoneItem.title = state.rawValue
        log.notice("ConsoleDeck menu shows \(state.rawValue, privacy: .public)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func showSettings() {
        deck.refreshPermissions()
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: DeckSettings(deck: deck)))
            window.title = "ConsoleDeck"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

@main
struct ConsoleDeck {
    static func main() {
        if CommandLine.arguments.contains("--check-ports") {
            print(DeckSerial.nanoPorts().joined(separator: "\n"))
            return
        }
        let application = NSApplication.shared
        let delegate = DeckDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
